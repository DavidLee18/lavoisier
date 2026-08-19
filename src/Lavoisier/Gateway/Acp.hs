-- | @Lavoisier.Gateway.Acp@ — a __Zed Agent Client Protocol (ACP)__ agent gateway.
--
-- The __Agent Client Protocol__ (from Zed; <https://agentclientprotocol.com>) lets a code editor
-- drive an AI coding agent that it launches __as a subprocess__, speaking __JSON-RPC 2.0 over
-- stdio__. The editor is the /client/; Lavoisier is the /agent/. Wire an ACP-capable editor (Zed, or
-- Neovim via a bridge) to run @lav --acp@ and it gains the full Lavoisier tool loop inside the
-- editor's agent panel — with __zero core change__, like every other gateway.
--
-- (Not to be confused with IBM\/BeeAI's /Agent Communication Protocol/, which shared the acronym —
-- that project folded into A2A, so @--serve-a2a@ is the interop server surface now. This @acp@ is
-- the editor-facing stdio protocol. Ported from Rust @lvz-gw-acp@ 0.2.0, which replaced the REST
-- agents\/runs server this module used to be.)
--
-- It depends only on the protocol contracts — never on a provider or on the agent's internals — so
-- the same shared agent drives the CLI and this gateway unchanged.
--
-- Surface (client → agent):
--
-- * @initialize@ — capability negotiation. We advertise protocol version @1@, text prompts, and no
--   auth methods (Lavoisier authenticates to model providers itself, via env keys).
-- * @session\/new@ — allocate a session id (mapped straight onto a Lavoisier session, so a
--   multi-turn ACP conversation accrues memory through the shared session store).
-- * @session\/prompt@ — run one turn. Text\/thinking deltas stream out as @session\/update@
--   notifications (@agent_message_chunk@ \/ @agent_thought_chunk@); tool calls surface as
--   @tool_call@ + @tool_call_update@ updates; the request resolves with a @stopReason@.
-- * @session\/cancel@ — a notification that cancels the session's in-flight prompt, which then
--   resolves with @stopReason: \"cancelled\"@.
--
-- Deferred (documented, not yet wired): delegating file reads\/writes to the editor
-- (@fs\/read_text_file@ \/ @fs\/write_text_file@) and @session\/request_permission@ — for now
-- Lavoisier runs its own tools directly, which is a valid ACP posture. @session\/load@ is likewise
-- not offered (@loadSession: false@). JSON-RPC is __hand-rolled__ over aeson — no ACP SDK.
module Lavoisier.Gateway.Acp
  ( acpGateway,
    acpProtocolVersion,
    serveAcpOver,

    -- * Exposed for tests
    toolKind,
    mapStopReason,
    extractPromptText,
    eventToUpdate,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.Async (race)
import Control.Concurrent.MVar
import Control.Exception (IOException, try)
import Control.Monad (unless, void)
import Data.Aeson (Value (..), decodeStrict, encode, object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Text.IO qualified as TIO
import Lavoisier.Log (logDebug, logInfo)
import Lavoisier.Protocol.Agent (AgentHandle (..), TurnStream, turnRequest)
import Lavoisier.Protocol.Event (Event (..), StopReason (..))
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))
import System.IO (BufferMode (LineBuffering), Handle, hFlush, hIsEOF, hSetBuffering, hSetEncoding, stdin, stdout, utf8)

-- | The ACP protocol version this agent implements.
acpProtocolVersion :: Int
acpProtocolVersion = 1

-- | The Zed ACP agent gateway. Serving takes over the process's stdin\/stdout for the protocol.
acpGateway :: Gateway
acpGateway =
  Gateway
    { gatewayName = "acp",
      gatewayServe = \agent -> do
        logInfo "acp" "Zed ACP agent on stdio (JSON-RPC 2.0)"
        serveAcpOver agent stdin stdout
    }

-- | The transport-agnostic serve loop: read newline-framed JSON-RPC from @inH@, dispatch, and write
-- responses + @session\/update@ notifications to @outH@. Generic over the pipe so it can be
-- unit-tested over a pair of pipes instead of real stdio.
--
-- The loop stays responsive while a prompt runs: @session\/prompt@ is forked (so a concurrent
-- @session\/cancel@ can still be read and acted on), and the writer lock serialises whole JSON-RPC
-- lines so interleaved notifications and responses never corrupt each other. Ends cleanly on EOF
-- (the editor closing the pipe).
serveAcpOver :: AgentHandle -> Handle -> Handle -> IO (Either GatewayError ())
serveAcpOver agent inH outH = do
  hSetEncoding inH utf8
  hSetEncoding outH utf8
  hSetBuffering outH LineBuffering
  st <- newServerState agent outH
  r <- try (loop st) :: IO (Either IOException ())
  pure (either (Left . GEIo . T.pack . show) Right r)
  where
    loop st = do
      eof <- hIsEOF inH
      unless eof $ do
        line <- TIO.hGetLine inH
        unless (T.null (T.strip line)) $ case decodeStrict (encodeUtf8 line) of
          -- A malformed line has no reliable id to answer; log and keep serving.
          Nothing -> logDebug "acp" ("unparseable line: " <> T.take 200 line)
          Just msg -> dispatch st msg
        loop st

-- | Route one inbound JSON-RPC message. Requests carry a non-null @id@ and get a response;
-- notifications (no id) do not. Only @session\/prompt@ is long-running, so only it is forked.
dispatch :: ServerState -> Value -> IO ()
dispatch st msg = case method of
  "initialize" -> respond st reqId initializeResult
  -- No ACP auth methods are advertised, so `authenticate` is a no-op acknowledgement.
  "authenticate" -> respond st reqId (object [])
  "session/new" -> do
    sid <- newSession st
    logInfo "acp" ("session/new " <> sid)
    respond st reqId (object ["sessionId" .= sid])
  "session/prompt" -> void (forkIO (runPrompt st reqId params))
  "session/cancel" ->
    -- A notification: no response. Signal the session's in-flight prompt to stop.
    case lookStr "sessionId" params of
      Just sid -> logInfo "acp" ("session/cancel " <> sid) >> cancelSession st sid
      Nothing -> pure ()
  other ->
    case reqId of
      Just _ -> respondErr st reqId (-32601) ("method not found: " <> other)
      Nothing -> pure ()
  where
    reqId = case lookKey "id" msg of
      Just Null -> Nothing
      v -> v
    method = fromMaybe "" (lookStr "method" msg)
    params = fromMaybe Null (lookKey "params" msg)

-- | The @initialize@ result: protocol version, agent capabilities, and (no) auth methods.
initializeResult :: Value
initializeResult =
  object
    [ "protocolVersion" .= acpProtocolVersion,
      "agentCapabilities"
        .= object
          [ "loadSession" .= False,
            "promptCapabilities"
              .= object ["image" .= False, "audio" .= False, "embeddedContext" .= False]
          ],
      "authMethods" .= ([] :: [Value])
    ]

-- | Run one @session\/prompt@ to completion: submit the turn, stream its events as @session\/update@
-- notifications, and answer the original request with a @stopReason@ (or a JSON-RPC error).
runPrompt :: ServerState -> Maybe Value -> Value -> IO ()
runPrompt st reqId params = case lookStr "sessionId" params of
  Nothing -> respondErr st reqId (-32602) "missing `sessionId`"
  Just sid -> do
    let text = extractPromptText (lookKey "prompt" params)
    if T.null text
      then respondErr st reqId (-32602) "prompt has no text content"
      else do
        -- Arm cancellation *before* submitting so a race between the turn starting and a cancel
        -- arriving is caught (the MVar holds the signal even if nothing is awaiting it yet).
        cancel <- armSession st sid
        submit (ssAgent st) (turnRequest sid text) >>= \case
          Left e -> disarmSession st sid >> respondErr st reqId (-32603) (T.pack (show e))
          Right stream -> do
            result <- streamUpdates st sid stream cancel
            disarmSession st sid
            case result of
              Right stopReason -> respond st reqId (object ["stopReason" .= stopReason])
              Left e -> respondErr st reqId (-32603) e

-- | Consume the agent's event stream, emitting one @session\/update@ per relevant 'Event', until the
-- turn ends, is cancelled, or errors. Returns the ACP @stopReason@ on a clean finish.
streamUpdates :: ServerState -> Text -> TurnStream -> MVar () -> IO (Either Text Text)
streamUpdates st sid stream cancel = do
  -- Accumulated tool-argument JSON per call id, so `tool_call_update` can carry the whole input.
  argsRef <- newIORef Map.empty
  go argsRef "end_turn"
  where
    go argsRef stopReason =
      -- Cancellation wins the race: abandoning the stream cancels the provider request.
      race (readMVar cancel) (nextItem stream) >>= \case
        Left () -> pure (Right "cancelled")
        Right Nothing -> pure (Right stopReason)
        Right (Just (Left e)) -> pure (Left (T.pack (show e)))
        Right (Just (Right ev)) -> do
          acc <- readIORef argsRef
          let (upd, acc') = eventToUpdate ev acc
          writeIORef argsRef acc'
          case upd of
            Just u -> notify st "session/update" (object ["sessionId" .= sid, "update" .= u])
            Nothing -> pure ()
          go argsRef (case ev of Done r -> mapStopReason r; _ -> stopReason)

-- | Translate one 'Event' into an ACP @session\/update@ payload (or 'Nothing' for events ACP has no
-- slot for — usage, citations: informational, folded away for now), threading the per-call
-- accumulated argument JSON so a completed call can surface its whole input as @rawInput@.
eventToUpdate :: Event -> Map Text Text -> (Maybe Value, Map Text Text)
eventToUpdate ev acc = case ev of
  TextDelta t -> (Just (chunk "agent_message_chunk" t), acc)
  Thinking t -> (Just (chunk "agent_thought_chunk" t), acc)
  Notice t -> (Just (chunk "agent_thought_chunk" t), acc)
  ToolUseStart i n -> (Just (callStart i n), acc)
  ServerToolUse i n -> (Just (callStart i n), acc)
  ToolUseDelta i j -> (Nothing, Map.insertWith (flip (<>)) i j acc)
  ToolUseEnd i ->
    -- The call's arguments are now whole. Surface the parsed input if it parses.
    let raw = Map.lookup i acc >>= decodeStrict . encodeUtf8 :: Maybe Value
        base =
          [ "sessionUpdate" .= ("tool_call_update" :: Text),
            "toolCallId" .= i,
            "status" .= ("completed" :: Text)
          ]
     in (Just (object (base <> maybe [] (\v -> ["rawInput" .= v]) raw)), Map.delete i acc)
  ServerToolResult i content ->
    ( Just
        ( object
            [ "sessionUpdate" .= ("tool_call_update" :: Text),
              "toolCallId" .= i,
              "status" .= ("completed" :: Text),
              "content"
                .= [ object
                       [ "type" .= ("content" :: Text),
                         "content" .= object ["type" .= ("text" :: Text), "text" .= content]
                       ]
                   ]
            ]
        ),
      acc
    )
  -- Usage/Citation/Done carry no user-visible update chunk of their own.
  _ -> (Nothing, acc)
  where
    chunk kind t =
      object
        [ "sessionUpdate" .= (kind :: Text),
          "content" .= object ["type" .= ("text" :: Text), "text" .= t]
        ]
    callStart i n =
      object
        [ "sessionUpdate" .= ("tool_call" :: Text),
          "toolCallId" .= i,
          "title" .= n,
          "kind" .= toolKind n,
          "status" .= ("in_progress" :: Text)
        ]

-- | Best-effort mapping of a Lavoisier tool name onto an ACP tool-call @kind@ (drives the editor's
-- icon\/label). Unknown tools fall to @other@.
toolKind :: Text -> Text
toolKind n
  | any (`T.isPrefixOf` n) ["read", "outline", "list"] = "read"
  | any (`T.isPrefixOf` n) ["write", "edit", "batch_edit", "apply"] = "edit"
  | any (`T.isPrefixOf` n) ["find", "grep", "search"] = "search"
  | n `elem` ["shell", "bash"] = "execute"
  | otherwise = "other"

-- | Map a Lavoisier 'StopReason' onto an ACP @stopReason@. ACP has a narrower set — the extras all
-- fold to the natural end of a turn.
mapStopReason :: StopReason -> Text
mapStopReason = \case
  MaxTokens -> "max_tokens"
  Refusal -> "refusal"
  -- EndTurn / ToolUse / StopSequence / PauseTurn / Other all present as a completed turn.
  _ -> "end_turn"

-- | Pull the text out of an ACP prompt (an array of content blocks): concatenate every @text@ block,
-- plus the text of any embedded @resource@.
extractPromptText :: Maybe Value -> Text
extractPromptText (Just (Array blocks)) = foldMap blockText blocks
  where
    blockText b = case lookStr "type" b of
      -- A plain text block …
      Just "text" -> fromMaybe "" (lookStr "text" b)
      Nothing -> fromMaybe "" (lookStr "text" b)
      -- … or a `resource` block whose embedded resource is text.
      Just "resource" -> fromMaybe "" (lookKey "resource" b >>= lookStr "text")
      Just _ -> ""
extractPromptText _ = ""

-- --- JSON-RPC write helpers -----------------------------------------------------------------------

-- | Write a JSON-RPC success response.
respond :: ServerState -> Maybe Value -> Value -> IO ()
respond st reqId result =
  writeLine st (object ["jsonrpc" .= ("2.0" :: Text), "id" .= fromMaybe Null reqId, "result" .= result])

-- | Write a JSON-RPC error response.
respondErr :: ServerState -> Maybe Value -> Int -> Text -> IO ()
respondErr st reqId code message =
  writeLine
    st
    ( object
        [ "jsonrpc" .= ("2.0" :: Text),
          "id" .= fromMaybe Null reqId,
          "error" .= object ["code" .= code, "message" .= message]
        ]
    )

-- | Write a JSON-RPC notification (no id).
notify :: ServerState -> Text -> Value -> IO ()
notify st method params =
  writeLine st (object ["jsonrpc" .= ("2.0" :: Text), "method" .= method, "params" .= params])

-- | Serialise one message and write it as a newline-framed line, flushing so the editor sees it at
-- once. A write failure (the editor closed the pipe) is logged, not fatal — the reader loop's EOF is
-- the authoritative end-of-serve. The lock serialises whole lines across the reader loop and every
-- forked prompt.
writeLine :: ServerState -> Value -> IO ()
writeLine st msg = withMVar (ssWriteLock st) $ \() -> do
  let h = ssOut st
  r <- try (BL.hPut h (encode msg <> "\n") >> hFlush h) :: IO (Either IOException ())
  case r of
    Right () -> pure ()
    Left e -> logDebug "acp" ("write failed: " <> T.pack (show e))

-- --- server state ---------------------------------------------------------------------------------

-- | Per-connection server state: the shared agent, the output handle + its write lock, a session-id
-- counter, and the set of in-flight prompts (so a @session\/cancel@ can find and stop one).
data ServerState = ServerState
  { ssAgent :: AgentHandle,
    ssOut :: Handle,
    ssWriteLock :: MVar (),
    ssNextSession :: IORef Int,
    -- | sessionId → its in-flight prompt's cancellation signal. Present only while a prompt runs.
    ssPrompts :: IORef (Map Text (MVar ()))
  }

newServerState :: AgentHandle -> Handle -> IO ServerState
newServerState agent outH =
  ServerState agent outH <$> newMVar () <*> newIORef 1 <*> newIORef Map.empty

newSession :: ServerState -> IO Text
newSession st = do
  n <- atomicModifyIORef' (ssNextSession st) (\k -> (k + 1, k))
  pure ("acp-" <> T.pack (show n))

-- | Register a cancellation signal for @session@'s prompt, returning it for the stream loop to await.
-- Replaces any prior signal for the same session (a new prompt supersedes the old).
armSession :: ServerState -> Text -> IO (MVar ())
armSession st sid = do
  sig <- newEmptyMVar
  modifyIORef' (ssPrompts st) (Map.insert sid sig)
  pure sig

disarmSession :: ServerState -> Text -> IO ()
disarmSession st sid = modifyIORef' (ssPrompts st) (Map.delete sid)

-- | Signal @session@'s in-flight prompt to cancel. The MVar holds the signal even if the stream loop
-- is momentarily between awaits, so the cancel is never lost to a race.
cancelSession :: ServerState -> Text -> IO ()
cancelSession st sid = do
  ps <- readIORef (ssPrompts st)
  case Map.lookup sid ps of
    Just sig -> void (tryPutMVar sig ())
    Nothing -> pure ()

-- --- small JSON helpers ---------------------------------------------------------------------------

lookKey :: Text -> Value -> Maybe Value
lookKey k (Object o) = KM.lookup (K.fromText k) o
lookKey _ _ = Nothing

lookStr :: Text -> Value -> Maybe Text
lookStr k v = case lookKey k v of
  Just (String s) -> Just s
  _ -> Nothing
