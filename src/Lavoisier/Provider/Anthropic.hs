{-# LANGUAGE DataKinds #-}

-- | The Anthropic Messages-API provider — the first concrete 'Provider'. Ported from Rust
-- @lvz-anthropic@ @lib.rs@: build the request JSON from a normalised 'ChatRequest' (system,
-- messages, tools, @cache_control@ on the stable prefix + rolling tail, @thinking@ per
-- 'ThinkingLevel'), @POST \/v1\/messages@ with @stream:true@, and decode the SSE into the 'Event'
-- stream via "Lavoisier.Provider.Anthropic.Sse". Hand-rolled over @http-client-tls@ — no SDK.
module Lavoisier.Provider.Anthropic
  ( anthropicFromEnv,
    anthropicProvider,
    AnthropicConfig (..),
    newAnthropicConfig,
    -- exposed for testing
    AnthropicCaps,
    serverToolJson,
    buildBody,
    buildCountBody,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (Object, Value (..), decode, encode, toJSON)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Vector qualified as V
import Data.Word (Word32, Word64)
import Lavoisier.Domain (ModelId (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Provider.Anthropic.Sse (initSse, sseEof, ssePush)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (RequestHeaders)
import Network.HTTP.Types.Status (statusCode, statusIsSuccessful)
import System.Environment (lookupEnv)

anthropicVersion :: BS.ByteString
anthropicVersion = "2023-06-01"

defaultBaseUrl :: Text
defaultBaseUrl = "https://api.anthropic.com"

-- | Everything the provider needs at runtime: credentials, endpoint, a shared connection manager,
-- and whether to request the 1-hour extended cache TTL on the immutable prefix.
data AnthropicConfig = AnthropicConfig
  { acApiKey :: Text,
    acBaseUrl :: Text,
    acManager :: Manager,
    acExtendedTtl :: Bool
  }

-- | Build a config with a fresh TLS connection manager.
newAnthropicConfig :: Text -> Text -> IO AnthropicConfig
newAnthropicConfig apiKey baseUrl = do
  mgr <- newManager tlsManagerSettings
  pure (AnthropicConfig apiKey baseUrl mgr False)

-- | Construct the provider from @ANTHROPIC_API_KEY@ (required) and @ANTHROPIC_BASE_URL@ (optional).
anthropicFromEnv :: IO (Either ProviderError Provider)
anthropicFromEnv = do
  mkey <- lookupEnv "ANTHROPIC_API_KEY"
  case mkey of
    Nothing -> pure (Left (PConfig "ANTHROPIC_API_KEY is not set"))
    Just key -> do
      base <- maybe defaultBaseUrl T.pack <$> lookupEnv "ANTHROPIC_BASE_URL"
      cfg <- newAnthropicConfig (T.pack key) base
      pure (Right (anthropicProvider cfg))

-- | Everything Anthropic supports, named once so 'declare' and 'negotiate' cannot drift apart.
-- The tool entries must match what 'serverToolJson' and 'builtinToolJson' actually map.
type AnthropicCaps =
  '[ 'PromptCaching,
     'ExtendedThinking,
     'Vision,
     'WebSearch,
     'WebFetch,
     'CodeExecution,
     'ClientBuiltinTools,
     'RemoteMcp,
     'Sampling,
     'TopK,
     'StopSequences,
     'StructuredOutput,
     'ToolChoiceControl
   ]

-- | The 'Provider' record backed by an 'AnthropicConfig'.
anthropicProvider :: AnthropicConfig -> Provider
anthropicProvider cfg =
  Provider
    { providerStream = anthropicStream cfg,
      providerCapabilities = declare @AnthropicCaps,
      providerCountTokens = anthropicCountTokens cfg
    }

-- --- streaming -------------------------------------------------------------------------------------

anthropicStream :: AnthropicConfig -> ChatRequest -> IO (Either ProviderError EventStream)
anthropicStream cfg chatReq = withNegotiated @AnthropicCaps chatReq $ \nreq -> do
  let body = encode (buildBody (acExtendedTtl cfg) nreq)
      url = T.unpack (T.dropWhileEnd (== '/') (acBaseUrl cfg)) <> "/v1/messages"
  ereq0 <- try (parseRequest url) :: IO (Either SomeException Request)
  case ereq0 of
    Left e -> pure (Left (PConfig (T.pack (show e))))
    Right req0 -> do
      let httpReq =
            req0
              { method = "POST",
                requestHeaders = headers cfg,
                requestBody = RequestBodyLBS body,
                responseTimeout = responseTimeoutNone
              }
      eresp <- try (responseOpen httpReq (acManager cfg)) :: IO (Either HttpException (Response BodyReader))
      case eresp of
        Left e -> pure (Left (PTransport (T.pack (show e))))
        Right resp
          | statusIsSuccessful (responseStatus resp) -> Right <$> makeStream resp
          | otherwise -> do
              errBody <- BS.concat <$> brConsume (responseBody resp)
              responseClose resp
              pure (Left (PApi (statusCode (responseStatus resp)) (decodeUtf8Lenient errBody)))

-- | Wrap the open response in a pull 'Producer': read a chunk, feed the SSE decoder, buffer the
-- events it yields, and hand them out one at a time. Closes the response at end-of-stream.
makeStream :: Response BodyReader -> IO EventStream
makeStream resp = do
  stateRef <- newIORef initSse
  pendRef <- newIORef []
  doneRef <- newIORef False
  let feed [] = pull
      feed (x : xs) = writeIORef pendRef xs >> pure (Just x)
      pull =
        readIORef pendRef >>= \case
          (x : xs) -> writeIORef pendRef xs >> pure (Just x)
          [] ->
            readIORef doneRef >>= \case
              True -> pure Nothing
              False -> do
                chunk <- brRead (responseBody resp)
                if BS.null chunk
                  then do
                    st <- readIORef stateRef
                    responseClose resp
                    writeIORef doneRef True
                    feed (sseEof st)
                  else do
                    st <- readIORef stateRef
                    let (st', evs) = ssePush st chunk
                    writeIORef stateRef st'
                    feed evs
  pure (Producer pull)

headers :: AnthropicConfig -> RequestHeaders
headers cfg =
  [ ("x-api-key", encodeUtf8 (acApiKey cfg)),
    ("anthropic-version", anthropicVersion),
    ("content-type", "application/json")
  ]
    <> [("anthropic-beta", "extended-cache-ttl-2025-04-11") | acExtendedTtl cfg]

-- --- native token counting -------------------------------------------------------------------------

anthropicCountTokens :: AnthropicConfig -> ChatRequest -> IO (Either ProviderError (Maybe Word64))
anthropicCountTokens cfg req = do
  let body = encode (buildCountBody req)
      url = T.unpack (T.dropWhileEnd (== '/') (acBaseUrl cfg)) <> "/v1/messages/count_tokens"
  ereq0 <- try (parseRequest url) :: IO (Either SomeException Request)
  case ereq0 of
    Left e -> pure (Left (PConfig (T.pack (show e))))
    Right req0 -> do
      let httpReq = req0 {method = "POST", requestHeaders = headers cfg, requestBody = RequestBodyLBS body}
      eresp <- try (httpLbs httpReq (acManager cfg)) :: IO (Either HttpException (Response BL.ByteString))
      case eresp of
        Left e -> pure (Left (PTransport (T.pack (show e))))
        Right resp
          | statusIsSuccessful (responseStatus resp) ->
              pure (Right (decode (responseBody resp) >>= \v -> lookNum "input_tokens" v))
          | otherwise ->
              pure (Left (PApi (statusCode (responseStatus resp)) (decodeUtf8Lenient (BL.toStrict (responseBody resp)))))
  where
    lookNum k (Object o) = case KM.lookup (K.fromText k) o of
      Just (Number n) -> Just (truncate n)
      _ -> Nothing
    lookNum _ _ = Nothing

-- --- request-body construction (ports build_body & friends) ---------------------------------------

-- | Build the Messages-API request body from a normalised 'ChatRequest'. @extended_ttl@ puts the
-- 1-hour TTL on the immutable-prefix breakpoints.
buildBody :: Bool -> Negotiated caps -> Value
buildBody ttl nreq =
  Object
    . markConversationTail
    . applyThinking (crThinking req) (unModelId (crModel req)) (crMaxTokens req)
    $ kmap pairs
  where
    req = negotiatedRequest nreq
    pairs =
      concat
        [ [ ("model", String (unModelId (crModel req))),
            ("max_tokens", toJSON (crMaxTokens req)),
            ("messages", buildMessages ttl (crMessages req)),
            ("stream", Bool True)
          ],
          [("system", buildSystem ttl sp) | Just sp <- [crSystem req]],
          [("tools", allTools) | hasAnyTools],
          [("mcp_servers", Array (V.fromList (map mcpJson (crMcpServers req)))) | not (null (crMcpServers req))],
          samplingPairs,
          [("stop_sequences", toJSON (crStopSequences req)) | not (null (crStopSequences req))],
          [("tool_choice", buildToolChoice (crDisableParallelToolUse req) tc) | Just tc <- [crToolChoice req]],
          [ ("output_config", kobj [("format", kobj [("type", String "json_schema"), ("schema", sch)])])
          | Just (JsonSchema sch) <- [crOutputFormat req]
          ]
        ]
    hasAnyTools = not (null (crTools req)) || not (null (crServerTools req)) || not (null (crBuiltinTools req))
    allTools =
      Array . V.fromList $
        map (toolJson ttl) (crTools req)
          <> mapMaybe serverToolJson (crServerTools req)
          <> map builtinToolJson (crBuiltinTools req)
    samplingPairs
      | rejectsSampling (unModelId (crModel req)) = []
      | otherwise =
          concat
            [ [("temperature", toJSON t) | Just t <- [crTemperature req]],
              [("top_p", toJSON p) | Just p <- [crTopP req]],
              [("top_k", toJSON kk) | Just kk <- [crTopK req]]
            ]

-- | The count-tokens body: the same prompt-shaping fields, but no @stream@\/@max_tokens@ and no
-- rolling cache-tail marker.
buildCountBody :: ChatRequest -> Value
buildCountBody req =
  kobj $
    concat
      [ [("model", String (unModelId (crModel req))), ("messages", buildMessages False (crMessages req))],
        [("system", buildSystem False sp) | Just sp <- [crSystem req]],
        [("tools", Array (V.fromList (map (toolJson False) (crTools req)))) | not (null (crTools req))],
        [("tool_choice", buildToolChoice (crDisableParallelToolUse req) tc) | Just tc <- [crToolChoice req]]
      ]

rejectsSampling :: Text -> Bool
rejectsSampling model = any (`T.isInfixOf` model) ["opus-4-7", "opus-4-8", "fable-5", "mythos-5"]

usesLegacyThinking :: Text -> Bool
usesLegacyThinking model = any (`T.isInfixOf` model) ["haiku", "sonnet-4-5", "sonnet-4-0", "opus-4-1", "opus-4-0"]

applyThinking :: Maybe ThinkingLevel -> Text -> Word32 -> Object -> Object
applyThinking mlvl model maxTok body = case mlvl of
  Just ThinkMedium -> go False
  Just ThinkHigh -> go True
  _ -> body
  where
    go isHigh =
      let body1 = KM.delete (K.fromText "temperature") body
       in if usesLegacyThinking model
            then
              let budget = if isHigh then 12000 else 4096 :: Word32
                  b2 = insO "thinking" (kobj [("type", String "enabled"), ("budget_tokens", toJSON budget)]) body1
               in if maxTok <= budget then insO "max_tokens" (toJSON (budget + 4096)) b2 else b2
            else
              let effort = if isHigh then "high" else "medium" :: Text
                  b2 = insO "thinking" (kobj [("type", String "adaptive")]) body1
                  oc = case lookO "output_config" b2 of
                    Just (Object o) -> o
                    _ -> KM.empty
               in insO "output_config" (Object (insO "effort" (String effort) oc)) b2

-- | Spend the spare cache breakpoint on the tail of the conversation (the rolling-cache pattern).
markConversationTail :: Object -> Object
markConversationTail body
  | countBreakpoints (Object body) >= 4 = body
  | otherwise = case lookO "messages" body of
      Just (Array msgs) | not (V.null msgs) -> case V.last msgs of
        Object mo -> case lookO' "content" mo of
          Just (Array blocks) | not (V.null blocks) -> case V.last blocks of
            Object bo
              | not (KM.member (K.fromText "cache_control") bo) ->
                  let bo' = insO "cache_control" (cacheControl False) bo
                      blocks' = blocks V.// [(V.length blocks - 1, Object bo')]
                      mo' = insO "content" (Array blocks') mo
                      msgs' = msgs V.// [(V.length msgs - 1, Object mo')]
                   in insO "messages" (Array msgs') body
            _ -> body
          _ -> body
        _ -> body
      _ -> body

countBreakpoints :: Value -> Int
countBreakpoints (Object o) =
  (if KM.member (K.fromText "cache_control") o then 1 else 0)
    + sum [countBreakpoints v | (kk, v) <- KM.toList o, kk /= K.fromText "cache_control"]
countBreakpoints (Array a) = sum (map countBreakpoints (V.toList a))
countBreakpoints _ = 0

cacheControl :: Bool -> Value
cacheControl ttl1h
  | ttl1h = kobj [("type", String "ephemeral"), ("ttl", String "1h")]
  | otherwise = kobj [("type", String "ephemeral")]

buildSystem :: Bool -> SystemPrompt -> Value
buildSystem ttl sp =
  Array . V.singleton . kobj $
    [("type", String "text"), ("text", String (spText sp))]
      <> [("cache_control", cacheControl ttl) | spCache sp]

buildMessages :: Bool -> [Message] -> Value
buildMessages ttl msgs = Array (V.fromList (map msgJson msgs))
  where
    msgJson m =
      kobj
        [ ("role", String (roleStr (msgRole m))),
          ("content", Array (V.fromList (mapMaybe (buildContentBlock ttl) (msgContent m))))
        ]
    roleStr User = "user"
    roleStr Assistant = "assistant"

buildContentBlock :: Bool -> ContentBlock -> Maybe Value
buildContentBlock ttl = \case
  TextBlock t cache ->
    Just . kobj $ [("type", String "text"), ("text", String t)] <> [("cache_control", cacheControl ttl) | cache]
  ThinkingBlock _ -> Nothing -- prior-turn thinking is dropped, not re-sent
  ImageBlock src -> Just (kobj [("type", String "image"), ("source", mediaSource src)])
  DocumentBlock src cit ->
    Just . kobj $
      [("type", String "document"), ("source", mediaSource src)]
        <> [("citations", kobj [("enabled", Bool True)]) | cit]
  ToolUseBlock i n input ->
    Just (kobj [("type", String "tool_use"), ("id", String i), ("name", String n), ("input", input)])
  ToolResultBlock tuid content err ->
    Just . kobj $
      [("type", String "tool_result"), ("tool_use_id", String tuid), ("content", String content)]
        <> [("is_error", Bool True) | err]

mediaSource :: MediaSource -> Value
mediaSource = \case
  SrcBase64 mt d -> kobj [("type", String "base64"), ("media_type", String mt), ("data", String d)]
  SrcUrl u -> kobj [("type", String "url"), ("url", String u)]
  SrcFile f -> kobj [("type", String "file"), ("file_id", String f)]
  SrcPlainText t -> kobj [("type", String "text"), ("media_type", String "text/plain"), ("data", String t)]

toolJson :: Bool -> ToolDef -> Value
toolJson ttl t =
  kobj $
    [("name", String (tdName t)), ("description", String (tdDescription t)), ("input_schema", tdSchema t)]
      <> [("strict", Bool True) | tdStrict t]
      <> [("cache_control", cacheControl ttl) | tdCache t]

serverToolJson :: ServerTool -> Maybe Value
serverToolJson = \case
  STWebSearch mu ad bd ->
    Just . kobj $
      [("type", String "web_search_20260209"), ("name", String "web_search")]
        <> [("max_uses", toJSON n) | Just n <- [mu]]
        <> [("allowed_domains", toJSON ad) | not (null ad)]
        <> [("blocked_domains", toJSON bd) | not (null bd)]
  STWebFetch mu ->
    Just . kobj $
      [("type", String "web_fetch_20260209"), ("name", String "web_fetch")]
        <> [("max_uses", toJSON n) | Just n <- [mu]]
  STCodeExecution -> Just (kobj [("type", String "code_execution_20260120"), ("name", String "code_execution")])
  STXSearch {} -> Nothing
  STCollectionsSearch {} -> Nothing
  STUrlContext -> Nothing

builtinToolJson :: BuiltinTool -> Value
builtinToolJson = \case
  BTBash -> kobj [("type", String "bash_20250124"), ("name", String "bash")]
  BTTextEditor -> kobj [("type", String "text_editor_20250728"), ("name", String "str_replace_based_edit_tool")]
  BTMemory -> kobj [("type", String "memory_20250818"), ("name", String "memory")]

mcpJson :: McpServer -> Value
mcpJson s =
  kobj $
    [("type", String "url"), ("name", String (mcpName s)), ("url", String (mcpUrl s))]
      <> [("authorization_token", String tok) | Just tok <- [mcpAuthToken s]]

buildToolChoice :: Bool -> ToolChoice -> Value
buildToolChoice disablePar choice = kobj (base <> extra)
  where
    base = case choice of
      ChoiceAuto -> [("type", String "auto")]
      ChoiceRequired -> [("type", String "any")]
      ChoiceNone -> [("type", String "none")]
      ChoiceTool n -> [("type", String "tool"), ("name", String n)]
    extra = [("disable_parallel_tool_use", Bool True) | disablePar, choice /= ChoiceNone]

-- --- tiny KeyMap helpers ---------------------------------------------------------------------------

kmap :: [(Text, Value)] -> Object
kmap = KM.fromList . map (\(a, b) -> (K.fromText a, b))

kobj :: [(Text, Value)] -> Value
kobj = Object . kmap

insO :: Text -> Value -> Object -> Object
insO k = KM.insert (K.fromText k)

lookO :: Text -> Object -> Maybe Value
lookO k = KM.lookup (K.fromText k)

lookO' :: Text -> Object -> Maybe Value
lookO' = lookO
