-- | @Lavoisier.Mcp@ — a **Model Context Protocol** client that adapts an external MCP server's tools
-- into Lavoisier 'Tool's. Ported from Rust @lvz-mcp@ @lib.rs@.
--
-- Lavoisier is the MCP **client**: it connects to one or more MCP *servers* (each a child process
-- over stdio, or an HTTP endpoint), discovers the tools they expose (@tools\/list@), and wraps each
-- as a 'Tool'. Because the adaptation lands at that record, the remote tools flow through the *same*
-- 'ToolRegistry' every frontend already uses — CLI and all gateways gain them for free.
--
-- Transports sit behind the 'Transport' record (so the JSON-RPC 'McpClient' is transport-agnostic):
--
--   * __stdio__ — spawn the server as a child process, frame newline-delimited JSON-RPC 2.0 over its
--     stdin\/stdout. Backed by a generic 'newPipeTransport' over any pair of handles, so it is
--     unit-tested offline against an in-process mock server over OS pipes (no child process).
--   * __HTTP__ — POST JSON-RPC 2.0 to a URL, accepting a JSON or Streamable-HTTP SSE reply, carrying
--     any @Mcp-Session-Id@ the server assigns on @initialize@.
--
-- The protocol (JSON-RPC 2.0 + the MCP method set) is hand-rolled over @http-client@\/@typed-process@
-- — no MCP SDK — matching the workspace's minimal-dependency rule.
module Lavoisier.Mcp
  ( -- * Server specs
    McpError (..),
    renderMcpError,
    TransportSpec (..),
    McpServerSpec (..),
    parseServerSpec,
    advertisedName,

    -- * Connecting
    connectTools,

    -- * The JSON-RPC client (exposed for testing)
    Transport (..),
    McpClient (..),
    mkClient,
    newPipeTransport,
    newHttpTransport,
    mcInitialize,
    mcListTools,
    mcCallTool,
    RemoteTool (..),
    CallResult (..),
    renderCall,
    parseHttpReply,
    toTool,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar
import Control.Exception (IOException, SomeException, try)
import Data.Aeson (Value (..), decodeStrict, encode, object, (.=))
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isNothing)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Vector qualified as V
import Lavoisier.Protocol.Tool
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode, statusIsSuccessful)
import System.IO (BufferMode (LineBuffering), Handle, hFlush, hSetBinaryMode, hSetBuffering)
import System.Process.Typed
  ( Process,
    createPipe,
    getStdin,
    getStdout,
    inherit,
    proc,
    setStderr,
    setStdin,
    setStdout,
    startProcess,
    stopProcess,
  )
import System.Timeout (timeout)

-- | The MCP protocol version advertised on @initialize@ (servers negotiate down if older).
protocolVersion :: Text
protocolVersion = "2025-06-18"

-- | Ceiling on any single JSON-RPC round-trip (microseconds). A hung server must not wedge the turn.
requestTimeoutMicros :: Int
requestTimeoutMicros = 120 * 1000000

-- | A failure talking to an MCP server. Mirrors Rust @McpError@.
data McpError
  = -- | A @--mcp-server@ spec could not be parsed.
    BadSpec Text
  | -- | The server process could not be spawned.
    Spawn Text
  | -- | A transport-level I\/O failure (broken pipe, socket error).
    Io Text
  | -- | An HTTP transport failure.
    Http Text
  | -- | The server returned a JSON-RPC @error@ object.
    Rpc Text
  | -- | A reply did not match the expected shape.
    Protocol Text
  | -- | The round-trip exceeded 'requestTimeoutMicros'.
    Timeout
  | -- | The transport closed before the reply arrived (server exited \/ pipe closed).
    Closed
  deriving stock (Eq, Show)

-- | A human-readable one-line message (mirrors the Rust @Display@ text).
renderMcpError :: McpError -> Text
renderMcpError = \case
  BadSpec s -> "bad MCP server spec: " <> s
  Spawn s -> "spawn failed: " <> s
  Io s -> "io error: " <> s
  Http s -> "http error: " <> s
  Rpc s -> "server error: " <> s
  Protocol s -> "protocol error: " <> s
  Timeout -> "request timed out"
  Closed -> "connection closed"

-- | Which transport a server spec selects.
data TransportSpec
  = -- | Spawn a child process and speak JSON-RPC over its stdio. The list is the command + args.
    StdioSpec [Text]
  | -- | POST JSON-RPC to this URL.
    HttpSpec Text
  deriving stock (Eq, Show)

-- | One MCP server to connect to: a short @label@ (namespaces its tools) and a transport.
data McpServerSpec = McpServerSpec
  { mssLabel :: Text,
    mssTransport :: TransportSpec
  }
  deriving stock (Eq, Show)

-- | Parse a @label: target@ spec. The target is an @http(s):\/\/@ URL ⇒ 'HttpSpec', otherwise a
-- command line split on whitespace ⇒ 'StdioSpec'. Splitting on the __first__ @:@ keeps a @:\/\/@ URL
-- intact.
--
-- >>> parseServerSpec "fs: npx -y server-filesystem ."
-- >>> parseServerSpec "remote: https://mcp.example.com/"
parseServerSpec :: Text -> Either McpError McpServerSpec
parseServerSpec spec =
  case T.breakOn ":" spec of
    (_, "") -> Left (BadSpec (tshow spec <> ": expected `label: target`"))
    (label0, rest) ->
      let label = T.strip label0
          target = T.strip (T.drop 1 rest)
       in if T.null label
            then Left (BadSpec (tshow spec <> ": empty label"))
            else
              if T.null target
                then Left (BadSpec (tshow spec <> ": empty target"))
                else
                  if "http://" `T.isPrefixOf` target || "https://" `T.isPrefixOf` target
                    then Right (McpServerSpec label (HttpSpec target))
                    else case T.words target of
                      [] -> Left (BadSpec (tshow spec <> ": empty command"))
                      argv -> Right (McpServerSpec label (StdioSpec argv))

-- | Namespace a remote tool name under its server label (@\<label\>_\<tool\>@) so MCP tools never
-- silently shadow a built-in, coercing it into the provider tool-name charset @^[A-Za-z0-9_-]{1,64}$@.
advertisedName :: Text -> Text -> Text
advertisedName label name = T.take 64 (T.map sanitize (label <> "_" <> name))
  where
    sanitize c
      | isAsciiAlphaNum c || c == '_' || c == '-' = c
      | otherwise = '_'
    isAsciiAlphaNum c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

-- ---------------------------------------------------------------------------------------------
-- Connect + adapt.
-- ---------------------------------------------------------------------------------------------

-- | Connect to the server described by @spec@, run the MCP handshake, and return one 'Tool' per
-- advertised remote tool. The returned tools keep the underlying connection (child process or HTTP
-- client) alive through their closures, so hold them for the program's lifetime.
connectTools :: McpServerSpec -> IO (Either McpError [Tool])
connectTools spec = do
  etr <- case mssTransport spec of
    StdioSpec argv -> connectStdio argv
    HttpSpec url -> newHttpTransport url
  case etr of
    Left e -> pure (Left e)
    Right tr -> do
      let client = mkClient (mssLabel spec) tr
      ei <- mcInitialize client
      case ei of
        Left e -> pure (Left e)
        Right () -> do
          er <- mcListTools client
          pure (fmap (map (toTool client (mssLabel spec))) er)

-- | Build a 'Tool' record from a remote tool, dispatching @invoke@ back through the client. A remote
-- 'McpError' becomes a hard 'TEExecution'; a tool-level @isError@ is mirrored onto a 'toolErr' output
-- (model-visible, recoverable) — exactly as the Rust adapter does.
toTool :: McpClient -> Text -> RemoteTool -> Tool
toTool client label rt =
  let advertised = advertisedName label (rtName rt)
   in Tool
        { toolName = advertised,
          toolDescription = fromMaybe "" (rtDescription rt),
          toolSchema = fromMaybe (object ["type" .= ("object" :: Text)]) (rtSchema rt),
          toolInvoke = \args -> do
            r <- mcCallTool client (rtName rt) args
            pure $ case r of
              Left e -> Left (TEExecution ("mcp `" <> advertised <> "`: " <> renderMcpError e))
              Right res ->
                Right (if resIsError res then toolErr (renderCall res) else toolOk (renderCall res))
        }

-- ---------------------------------------------------------------------------------------------
-- The JSON-RPC client.
-- ---------------------------------------------------------------------------------------------

-- | A JSON-RPC 2.0 transport to an MCP server, as a record of functions (the Rust @dyn Transport@).
data Transport = Transport
  { -- | Issue a request and await its matching @result@ (or map its @error@).
    transportRequest :: Text -> Value -> IO (Either McpError Value),
    -- | Fire a notification (no id, no response).
    transportNotify :: Text -> Value -> IO (Either McpError ())
  }

-- | A live connection to one MCP server: a label (for namespacing) and a 'Transport'.
data McpClient = McpClient
  { mcLabel :: Text,
    mcTransport :: Transport
  }

-- | Build a client over a transport.
mkClient :: Text -> Transport -> McpClient
mkClient = McpClient

-- | The @initialize@ handshake, followed by the @notifications\/initialized@ acknowledgement the spec
-- requires before other requests.
mcInitialize :: McpClient -> IO (Either McpError ())
mcInitialize client = do
  let params =
        object
          [ "protocolVersion" .= protocolVersion,
            "capabilities" .= object [],
            "clientInfo" .= object ["name" .= ("lavoisier" :: Text), "version" .= ("0.13.0" :: Text)]
          ]
  r <- transportRequest (mcTransport client) "initialize" params
  case r of
    Left e -> pure (Left e)
    Right _ -> transportNotify (mcTransport client) "notifications/initialized" (object [])

-- | Discover the server's tools, following @nextCursor@ pagination to completion.
mcListTools :: McpClient -> IO (Either McpError [RemoteTool])
mcListTools client = go [] Nothing
  where
    go acc cursor = do
      let params = maybe (object []) (\c -> object ["cursor" .= c]) cursor
      r <- transportRequest (mcTransport client) "tools/list" params
      case r of
        Left e -> pure (Left e)
        Right result -> case parseToolsList result of
          Left e -> pure (Left (Protocol ("tools/list: " <> e)))
          Right (tools, next) -> case next of
            Just c | not (T.null c) -> go (acc <> tools) (Just c)
            _ -> pure (Right (acc <> tools))

-- | Invoke a tool by its __remote__ name and return the parsed result.
mcCallTool :: McpClient -> Text -> Value -> IO (Either McpError CallResult)
mcCallTool client name args = do
  -- MCP wants an object for `arguments`; a tool with no args may arrive as JSON null.
  let arguments = case args of Null -> object []; v -> v
  r <- transportRequest (mcTransport client) "tools/call" (object ["name" .= name, "arguments" .= arguments])
  case r of
    Left e -> pure (Left e)
    Right result -> case parseCallResult result of
      Left e -> pure (Left (Protocol ("tools/call: " <> e)))
      Right cr -> pure (Right cr)

-- | A tool advertised by an MCP server, in the shape @tools\/list@ returns.
data RemoteTool = RemoteTool
  { rtName :: Text,
    rtDescription :: Maybe Text,
    rtSchema :: Maybe Value
  }
  deriving stock (Eq, Show)

-- | The @tools\/call@ result: content blocks plus an error flag.
data CallResult = CallResult
  { resContent :: [Value],
    resIsError :: Bool
  }
  deriving stock (Eq, Show)

-- | Flatten the content blocks into one string: @text@ blocks contribute their @text@; any other
-- block contributes its JSON, so nothing is silently dropped.
renderCall :: CallResult -> Text
renderCall = T.intercalate "\n" . map renderBlock . resContent
  where
    renderBlock v@(Object o)
      | KM.lookup "type" o == Just (String "text") =
          case KM.lookup "text" o of
            Just (String t) -> t
            _ -> ""
      | otherwise = jsonText v
    renderBlock v = jsonText v
    jsonText = decodeUtf8Lenient . BL.toStrict . encode

parseToolsList :: Value -> Either Text ([RemoteTool], Maybe Text)
parseToolsList (Object o) = do
  tools <- case KM.lookup "tools" o of
    Just (Array a) -> traverse parseRemoteTool (V.toList a)
    Just _ -> Left "`tools` must be an array"
    Nothing -> Right []
  let next = KM.lookup "nextCursor" o >>= asText
  Right (tools, next)
parseToolsList _ = Left "expected an object"

parseRemoteTool :: Value -> Either Text RemoteTool
parseRemoteTool (Object o) = case KM.lookup "name" o >>= asText of
  Nothing -> Left "a tool is missing its `name`"
  Just n -> Right (RemoteTool n (KM.lookup "description" o >>= asText) (KM.lookup "inputSchema" o))
parseRemoteTool _ = Left "a tool entry must be an object"

parseCallResult :: Value -> Either Text CallResult
parseCallResult (Object o) =
  let content = case KM.lookup "content" o of
        Just (Array a) -> V.toList a
        _ -> []
      isErr = KM.lookup "isError" o == Just (Bool True)
   in Right (CallResult content isErr)
parseCallResult _ = Left "expected an object"

-- ---------------------------------------------------------------------------------------------
-- The stdio (pipe) transport.
-- ---------------------------------------------------------------------------------------------

type Pending = IORef (Map Int (MVar (Either McpError Value)))

-- | Internal state of a newline-delimited JSON-RPC transport over a reader\/writer handle pair.
data PipeState = PipeState
  { psWrite :: Handle,
    psWriteLock :: MVar (),
    psPending :: Pending,
    psNextId :: IORef Int,
    -- | Kept only to retain a spawned child process (and its cleanup) for the transport's lifetime.
    -- Underscore-prefixed: the accessor is intentionally unused; the field's job is to hold the
    -- 'stopProcess' closure alive so the child is not GC'd (and killed) while its tools exist.
    _psKeepAlive :: Maybe (IO ())
  }

-- | Build a JSON-RPC transport over an arbitrary reader\/writer handle pair, spawning the background
-- demux reader. @keepAlive@ retains a spawned process (pass 'Nothing' for a test pipe).
newPipeTransport :: Handle -> Handle -> Maybe (IO ()) -> IO Transport
newPipeTransport readH writeH keepAlive = do
  hSetBinaryMode readH True
  hSetBinaryMode writeH True
  hSetBuffering writeH LineBuffering
  pending <- newIORef Map.empty
  nid <- newIORef 1
  wlock <- newMVar ()
  _ <- forkIO (readerLoop readH pending)
  let st = PipeState writeH wlock pending nid keepAlive
  pure Transport {transportRequest = pipeRequest st, transportNotify = pipeNotify st}

-- | Drain the reader: route each inbound line to its waiter by id; on EOF\/error fail every
-- outstanding request with 'Closed' rather than let it hang to timeout.
readerLoop :: Handle -> Pending -> IO ()
readerLoop readH pending = loop
  where
    loop = do
      r <- try (BS8.hGetLine readH) :: IO (Either IOException BS.ByteString)
      case r of
        Left _ -> drainPending pending Closed
        Right line -> dispatchLine pending line >> loop

drainPending :: Pending -> McpError -> IO ()
drainPending pending err = do
  waiters <- atomicModifyIORef' pending (\m -> (Map.empty, Map.elems m))
  mapM_ (`putMVar` Left err) waiters

-- | Route one inbound line to the waiting requester by id. A line with no id we know (server-initiated
-- request\/notification) is ignored — this client exposes no roots\/sampling.
dispatchLine :: Pending -> BS.ByteString -> IO ()
dispatchLine pending line
  | BS.null (BS.dropWhile isSpace line) = pure ()
  | otherwise = case decodeStrict line of
      Nothing -> pure ()
      Just msg -> case msgId msg of
        Nothing -> pure ()
        Just i -> do
          m <- atomicModifyIORef' pending (\mp -> (Map.delete i mp, Map.lookup i mp))
          maybe (pure ()) (`putMVar` rpcResult msg) m
  where
    isSpace w = w == 32 || w == 9 || w == 10 || w == 13

pipeRequest :: PipeState -> Text -> Value -> IO (Either McpError Value)
pipeRequest st method params = do
  i <- atomicModifyIORef' (psNextId st) (\n -> (n + 1, n))
  mv <- newEmptyMVar
  atomicModifyIORef' (psPending st) (\m -> (Map.insert i mv m, ()))
  let msg = object ["jsonrpc" .= ("2.0" :: Text), "id" .= i, "method" .= method, "params" .= params]
  w <- writeMessage st msg
  case w of
    Left e -> forget i >> pure (Left e)
    Right () -> do
      r <- timeout requestTimeoutMicros (takeMVar mv)
      case r of
        Just v -> pure v
        Nothing -> forget i >> pure (Left Timeout)
  where
    forget i = atomicModifyIORef' (psPending st) (\m -> (Map.delete i m, ()))

pipeNotify :: PipeState -> Text -> Value -> IO (Either McpError ())
pipeNotify st method params =
  writeMessage st (object ["jsonrpc" .= ("2.0" :: Text), "method" .= method, "params" .= params])

writeMessage :: PipeState -> Value -> IO (Either McpError ())
writeMessage st msg =
  withMVar (psWriteLock st) $ \_ -> do
    let line = BL.toStrict (encode msg) <> "\n"
    r <- try (BS.hPut (psWrite st) line >> hFlush (psWrite st)) :: IO (Either IOException ())
    pure (either (Left . Io . tshow) Right r)

-- | Spawn the child process for a stdio server and wrap its stdin\/stdout in a pipe transport. The
-- returned transport retains the process (killed via 'stopProcess' when the transport is dropped by
-- GC at program end).
connectStdio :: [Text] -> IO (Either McpError Transport)
connectStdio [] = pure (Left (BadSpec "empty command"))
connectStdio (cmd : args) = do
  let pc =
        setStdin createPipe
          . setStdout createPipe
          . setStderr inherit
          $ proc (T.unpack cmd) (map T.unpack args)
  r <- try (startProcess pc) :: IO (Either SomeException (Process Handle Handle ()))
  case r of
    Left e -> pure (Left (Spawn ("`" <> cmd <> "`: " <> tshow e)))
    Right p -> Right <$> newPipeTransport (getStdout p) (getStdin p) (Just (stopProcess p))

-- ---------------------------------------------------------------------------------------------
-- The HTTP transport.
-- ---------------------------------------------------------------------------------------------

data HttpState = HttpState
  { htManager :: Manager,
    htUrl :: String,
    htNextId :: IORef Int,
    htSession :: IORef (Maybe BS.ByteString)
  }

-- | Build an HTTP JSON-RPC transport that POSTs to @url@ (Streamable HTTP: carries any assigned
-- @Mcp-Session-Id@, accepts a JSON or SSE reply).
newHttpTransport :: Text -> IO (Either McpError Transport)
newHttpTransport url = do
  mgr <- newManager tlsManagerSettings
  nid <- newIORef 1
  sess <- newIORef Nothing
  let st = HttpState mgr (T.unpack url) nid sess
  pure (Right Transport {transportRequest = httpRequest st, transportNotify = httpNotify st})

httpRequest :: HttpState -> Text -> Value -> IO (Either McpError Value)
httpRequest st method params = do
  i <- atomicModifyIORef' (htNextId st) (\n -> (n + 1, n))
  httpPost st (object ["jsonrpc" .= ("2.0" :: Text), "id" .= i, "method" .= method, "params" .= params]) True

httpNotify :: HttpState -> Text -> Value -> IO (Either McpError ())
httpNotify st method params =
  fmap (fmap (const ())) $
    httpPost st (object ["jsonrpc" .= ("2.0" :: Text), "method" .= method, "params" .= params]) False

httpPost :: HttpState -> Value -> Bool -> IO (Either McpError Value)
httpPost st msg expectReply = do
  ereq0 <- try (parseRequest (htUrl st)) :: IO (Either SomeException Request)
  case ereq0 of
    Left e -> pure (Left (Http (tshow e)))
    Right req0 -> do
      msess <- readIORef (htSession st)
      let hdrs =
            [ ("content-type", "application/json"),
              ("accept", "application/json, text/event-stream")
            ]
              <> maybe [] (\s -> [("mcp-session-id", s)]) msess
          httpReq = req0 {method = "POST", requestHeaders = hdrs, requestBody = RequestBodyLBS (encode msg)}
      eresp <- try (httpLbs httpReq (htManager st)) :: IO (Either HttpException (Response BL.ByteString))
      case eresp of
        Left e -> pure (Left (Http (tshow e)))
        Right resp -> do
          case lookup "mcp-session-id" (responseHeaders resp) of
            Just s -> writeIORef (htSession st) (Just s)
            Nothing -> pure ()
          let status = responseStatus resp
              ctype = fromMaybe "" (lookup "content-type" (responseHeaders resp))
              body = BL.toStrict (responseBody resp)
          pure $
            if not (statusIsSuccessful status)
              then Left (Http ("HTTP " <> tshow (statusCode status) <> ": " <> decodeUtf8Lenient body))
              else
                if not expectReply
                  then Right Null
                  else parseHttpReply body ctype (msgId msg)

-- | Parse an HTTP JSON-RPC reply, whether a bare JSON object or a Streamable-HTTP SSE body. In an SSE
-- body the response rides a @data:@ line; scan for the one whose @id@ matches the request.
parseHttpReply :: BS.ByteString -> BS.ByteString -> Maybe Int -> Either McpError Value
parseHttpReply body ctype mid
  | "text/event-stream" `BS.isInfixOf` ctype = scan (T.lines (decodeUtf8Lenient body))
  | otherwise = case decodeStrict body of
      Just v -> rpcResult v
      Nothing -> Left (Protocol (decodeUtf8Lenient body))
  where
    scan [] = Left (Protocol "no JSON-RPC response in SSE body")
    scan (l : ls) = case T.stripPrefix "data:" (T.stripStart l) of
      Nothing -> scan ls
      Just d -> case decodeStrict (encodeUtf8 (T.strip d)) of
        Nothing -> scan ls
        Just msg -> if isNothing mid || msgId msg == mid then rpcResult msg else scan ls

-- ---------------------------------------------------------------------------------------------
-- JSON-RPC helpers.
-- ---------------------------------------------------------------------------------------------

-- | Extract a JSON-RPC @result@ (or map its @error@) from a response object.
rpcResult :: Value -> Either McpError Value
rpcResult (Object o)
  | Just err <- KM.lookup "error" o = Left (Rpc (errMessage err))
  | otherwise = Right (fromMaybe Null (KM.lookup "result" o))
rpcResult _ = Right Null

errMessage :: Value -> Text
errMessage v@(Object o) = case KM.lookup "message" o >>= asText of
  Just m -> m
  Nothing -> jsonText v
  where
    jsonText = decodeUtf8Lenient . BL.toStrict . encode
errMessage v = decodeUtf8Lenient (BL.toStrict (encode v))

msgId :: Value -> Maybe Int
msgId (Object o) = case KM.lookup "id" o of
  Just (Number n) -> toBoundedInteger n
  _ -> Nothing
msgId _ = Nothing

asText :: Value -> Maybe Text
asText (String s) = Just s
asText _ = Nothing

tshow :: (Show a) => a -> Text
tshow = T.pack . show
