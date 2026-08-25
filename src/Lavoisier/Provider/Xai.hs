{-# LANGUAGE DataKinds #-}

-- | @Lavoisier.Provider.Xai@ — the xAI (Grok) provider over its __OpenAI-compatible HTTP__ endpoint
-- (@https:\/\/api.x.ai\/v1\/chat\/completions@, @stream:true@). Ported from Rust @lvz-xai@ @http.rs@.
--
-- Builds the OpenAI chat-completions body from a normalised 'ChatRequest' (system leads; tool-use
-- blocks → assistant @tool_calls@; tool-result blocks → standalone @tool@ messages; images →
-- @image_url@ parts; @thinking@ → @reasoning_effort@; @output_format@ → @response_format@), POSTs it
-- over @http-client-tls@, and decodes the SSE into the 'Event' stream via
-- "Lavoisier.Provider.Xai.Sse". Hand-rolled, no SDK.
--
-- This is the OpenAI-compat transport (the one Rust also ships alongside its gRPC path). No prompt
-- caching and no native server-side tools, so those 'Capabilities' are false; parallel tool use and
-- vision are supported. The gRPC transport is a deferred follow-up.
module Lavoisier.Provider.Xai
  ( xaiFromEnv,
    xaiProvider,
    XaiConfig (..),
    newXaiConfig,
    -- exposed for testing
    buildBody,
    buildMessages,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (Object, Value (..), encode, toJSON)
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
import Lavoisier.Domain (ModelId (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Provider.Xai.Sse (initSse, sseEof, ssePush)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (RequestHeaders)
import Network.HTTP.Types.Status (statusCode, statusIsSuccessful)
import System.Environment (lookupEnv)

defaultBaseUrl :: Text
defaultBaseUrl = "https://api.x.ai/v1"

-- | Credentials, endpoint, and a shared TLS connection manager.
data XaiConfig = XaiConfig
  { xcApiKey :: Text,
    xcBaseUrl :: Text,
    xcManager :: Manager
  }

-- | Build a config with a fresh TLS connection manager.
newXaiConfig :: Text -> Text -> IO XaiConfig
newXaiConfig apiKey baseUrl = XaiConfig apiKey baseUrl <$> newManager tlsManagerSettings

-- | Construct the provider from @XAI_API_KEY@ (required) and @XAI_BASE_URL@ (optional).
xaiFromEnv :: IO (Either ProviderError Provider)
xaiFromEnv = do
  mkey <- lookupEnv "XAI_API_KEY"
  case mkey of
    Nothing -> pure (Left (PConfig "XAI_API_KEY is not set"))
    Just key -> do
      base <- maybe defaultBaseUrl T.pack <$> lookupEnv "XAI_BASE_URL"
      cfg <- newXaiConfig (T.pack key) base
      pure (Right (xaiProvider cfg))

-- | Everything the xAI REST transport supports, named once so 'declare' and 'negotiate' cannot
-- drift apart.
type XaiCaps = '[ 'Vision]

-- | The 'Provider' record backed by an 'XaiConfig'. No caching\/thinking\/server-tools; vision is
-- supported. No native token counting on this transport.
xaiProvider :: XaiConfig -> Provider
xaiProvider cfg =
  Provider
    { providerStream = xaiStream cfg,
      providerCapabilities = declare @XaiCaps,
      providerCountTokens = \_ -> pure (Right Nothing)
    }

-- --- streaming -------------------------------------------------------------------------------------

xaiStream :: XaiConfig -> ChatRequest -> IO (Either ProviderError EventStream)
xaiStream cfg chatReq = withNegotiated @XaiCaps chatReq $ \nreq -> do
  let body = encode (buildBody nreq)
      url = T.unpack (T.dropWhileEnd (== '/') (xcBaseUrl cfg)) <> "/chat/completions"
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
      eresp <- try (responseOpen httpReq (xcManager cfg)) :: IO (Either HttpException (Response BodyReader))
      case eresp of
        Left e -> pure (Left (PTransport (T.pack (show e))))
        Right resp
          | statusIsSuccessful (responseStatus resp) -> Right <$> makeStream resp
          | otherwise -> do
              errBody <- BS.concat <$> brConsume (responseBody resp)
              responseClose resp
              pure (Left (PApi (statusCode (responseStatus resp)) (decodeUtf8Lenient errBody)))

-- | Wrap the open response in a pull 'Producer' driving the SSE decoder (same shape as the Anthropic
-- adapter).
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

headers :: XaiConfig -> RequestHeaders
headers cfg =
  [ ("Authorization", "Bearer " <> encodeUtf8 (xcApiKey cfg)),
    ("Content-Type", "application/json")
  ]

-- --- request-body construction (ports build_messages/build_tools/&c.) ------------------------------

-- | Build the OpenAI chat-completions request body from a normalised 'ChatRequest'.
buildBody :: Negotiated caps -> Value
buildBody nreq =
  let req = negotiatedRequest nreq
   in buildBodyFor req

buildBodyFor :: ChatRequest -> Value
buildBodyFor req =
  Object . kmap $
    concat
      [ [ ("model", String (unModelId (crModel req))),
          ("messages", Array (V.fromList (buildMessages req))),
          ("max_tokens", toJSON (crMaxTokens req)),
          ("stream", Bool True),
          ("stream_options", kobj [("include_usage", Bool True)])
        ],
        [("temperature", toJSON t) | Just t <- [crTemperature req]],
        [("top_p", toJSON p) | Just p <- [crTopP req]],
        [("stop", toJSON (crStopSequences req)) | not (null (crStopSequences req))],
        [("tools", Array (V.fromList (map toolJson (crTools req)))) | not (null (crTools req))],
        [("tool_choice", toolChoiceJson tc) | Just tc <- [crToolChoice req]],
        [("parallel_tool_calls", Bool False) | crDisableParallelToolUse req],
        [("reasoning_effort", String (reasoningEffort lvl)) | Just lvl <- [crThinking req]],
        [("response_format", responseFormat sch) | Just (JsonSchema sch) <- [crOutputFormat req]]
      ]

-- | Flatten a 'ChatRequest' into OpenAI chat messages. System leads; tool-use blocks become
-- assistant @tool_calls@; tool-result blocks become standalone @tool@ messages.
buildMessages :: ChatRequest -> [Value]
buildMessages req =
  [kobj [("role", String "system"), ("content", String (spText sp))] | Just sp <- [crSystem req]]
    <> concatMap messageJson (crMessages req)

messageJson :: Message -> [Value]
messageJson m = case msgRole m of
  User -> userMessages (msgContent m)
  Assistant -> [assistantJson (msgContent m)]

-- | A user turn: tool-result blocks become their own @tool@ messages (and must precede any free
-- text); images use the content-array form.
userMessages :: [ContentBlock] -> [Value]
userMessages blocks = toolResults <> [userTurn | keep]
  where
    txt = T.concat [t | b <- blocks, t <- textOf b]
    textOf (TextBlock t _) = [t]
    textOf (ThinkingBlock t) = [t]
    textOf (DocumentBlock (SrcPlainText t) _) = [t]
    textOf (ImageBlock (SrcPlainText t)) = [t]
    textOf _ = []
    images = mapMaybe imagePart blocks
    toolResults =
      [ kobj [("role", String "tool"), ("tool_call_id", String tuid), ("content", String content)]
      | ToolResultBlock tuid content _ <- blocks
      ]
    keep = not (null images) || not (T.null txt) || null blocks
    userTurn
      | null images = kobj [("role", String "user"), ("content", String txt)]
      | otherwise =
          kobj
            [ ("role", String "user"),
              ("content", Array (V.fromList (textPart <> images)))
            ]
    textPart = [kobj [("type", String "text"), ("text", String txt)] | not (T.null txt)]

imagePart :: ContentBlock -> Maybe Value
imagePart = \case
  ImageBlock src -> mediaPart src
  DocumentBlock src _ -> mediaPart src
  _ -> Nothing
  where
    mediaPart = \case
      SrcUrl u -> Just (kobj [("type", String "image_url"), ("image_url", kobj [("url", String u)])])
      SrcBase64 mt d ->
        Just (kobj [("type", String "image_url"), ("image_url", kobj [("url", String ("data:" <> mt <> ";base64," <> d))])])
      SrcFile f -> Just (kobj [("type", String "file"), ("file", kobj [("file_id", String f)])])
      SrcPlainText _ -> Nothing -- folded into the message text

assistantJson :: [ContentBlock] -> Value
assistantJson blocks = Object (foldr (\(k, v) -> KM.insert (K.fromText k) v) KM.empty pairs)
  where
    txt = T.concat [t | TextBlock t _ <- blocks]
    toolCalls =
      [ kobj
          [ ("id", String i),
            ("type", String "function"),
            ("function", kobj [("name", String n), ("arguments", String (jsonText input))])
          ]
      | ToolUseBlock i n input <- blocks
      ]
    pairs =
      [("role", String "assistant"), ("content", if T.null txt then Null else String txt)]
        <> [("tool_calls", Array (V.fromList toolCalls)) | not (null toolCalls)]

toolJson :: ToolDef -> Value
toolJson t =
  kobj
    [ ("type", String "function"),
      ("function", kobj [("name", String (tdName t)), ("description", String (tdDescription t)), ("parameters", tdSchema t)])
    ]

toolChoiceJson :: ToolChoice -> Value
toolChoiceJson = \case
  ChoiceAuto -> String "auto"
  ChoiceRequired -> String "required"
  ChoiceNone -> String "none"
  ChoiceTool n -> kobj [("type", String "function"), ("function", kobj [("name", String n)])]

responseFormat :: Value -> Value
responseFormat schema =
  kobj
    [ ("type", String "json_schema"),
      ("json_schema", kobj [("name", String "response"), ("schema", schema), ("strict", Bool True)])
    ]

-- | Map the normalised thinking level onto grok's @reasoning_effort@.
reasoningEffort :: ThinkingLevel -> Text
reasoningEffort = \case
  ThinkOff -> "low"
  ThinkLow -> "low"
  ThinkMedium -> "high"
  ThinkHigh -> "high"

-- --- helpers ---------------------------------------------------------------------------------------

jsonText :: Value -> Text
jsonText = decodeUtf8Lenient . BL.toStrict . encode

kmap :: [(Text, Value)] -> Object
kmap = KM.fromList . map (\(a, b) -> (K.fromText a, b))

kobj :: [(Text, Value)] -> Value
kobj = Object . kmap
