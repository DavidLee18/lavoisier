{-# LANGUAGE DataKinds #-}

-- | The Google (Gemini) provider — the second concrete 'Provider', proving the abstraction
-- generalises to a quite different API. Ported from Rust @lvz-google@ @lib.rs@: build the
-- @generateContent@ request JSON from a normalised 'ChatRequest' (contents from messages incl.
-- functionCall\/functionResponse, systemInstruction, functionDeclarations, generationConfig +
-- thinkingConfig), @POST …:streamGenerateContent?alt=sse@, decode the SSE via
-- "Lavoisier.Provider.Google.Sse". Hand-rolled over @http-client-tls@ — no SDK.
module Lavoisier.Provider.Google
  ( googleFromEnv,
    googleProvider,
    GoogleConfig (..),
    newGoogleConfig,
    -- exposed for testing
    buildBody,
    defaultReasoningFloor,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), encode, object, toJSON, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Vector qualified as V
import Data.Word (Word32)
import Lavoisier.Domain (ModelId (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Provider.Google.Sse (initSse, sseEof, ssePush)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (RequestHeaders, statusCode, statusIsSuccessful)
import System.Environment (lookupEnv)

defaultBaseUrl :: Text
defaultBaseUrl = "https://generativelanguage.googleapis.com"

-- | Minimum @maxOutputTokens@ applied to reasoning models (they spend output budget on thinking
-- first, so a small cap can starve the visible answer).
defaultReasoningFloor :: Word32
defaultReasoningFloor = 8192

data GoogleConfig = GoogleConfig
  { gcApiKey :: Text,
    gcBaseUrl :: Text,
    gcManager :: Manager,
    gcReasoningFloor :: Word32
  }

newGoogleConfig :: Text -> Text -> IO GoogleConfig
newGoogleConfig apiKey baseUrl = do
  mgr <- newManager tlsManagerSettings
  pure (GoogleConfig apiKey baseUrl mgr defaultReasoningFloor)

-- | Construct from @GOOGLE_API_KEY@ (required) and @GOOGLE_BASE_URL@ (optional).
googleFromEnv :: IO (Either ProviderError Provider)
googleFromEnv = do
  mkey <- lookupEnv "GOOGLE_API_KEY"
  case mkey of
    Nothing -> pure (Left (PConfig "GOOGLE_API_KEY is not set"))
    Just key -> do
      base <- maybe defaultBaseUrl T.pack <$> lookupEnv "GOOGLE_BASE_URL"
      cfg <- newGoogleConfig (T.pack key) base
      pure (Right (googleProvider cfg))

googleProvider :: GoogleConfig -> Provider
googleProvider cfg =
  Provider
    { providerStream = googleStream cfg,
      providerCapabilities = declare @'[ 'ExtendedThinking, 'ParallelToolUse, 'ServerSideTools, 'Vision],
      -- Native countTokens exists but is deferred; the agent falls back to its own estimate.
      providerCountTokens = \_ -> pure (Right Nothing)
    }

-- --- streaming -------------------------------------------------------------------------------------

googleStream :: GoogleConfig -> ChatRequest -> IO (Either ProviderError EventStream)
googleStream cfg req = do
  let body = encode (buildBody (gcReasoningFloor cfg) req)
      base = T.unpack (T.dropWhileEnd (== '/') (gcBaseUrl cfg))
      url = base <> "/v1beta/models/" <> T.unpack (unModelId (crModel req)) <> ":streamGenerateContent?alt=sse"
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
      eresp <- try (responseOpen httpReq (gcManager cfg)) :: IO (Either HttpException (Response BodyReader))
      case eresp of
        Left e -> pure (Left (PTransport (T.pack (show e))))
        Right resp
          | statusIsSuccessful (responseStatus resp) -> Right <$> makeStream resp
          | otherwise -> do
              errBody <- BS.concat <$> brConsume (responseBody resp)
              responseClose resp
              pure (Left (PApi (statusCode (responseStatus resp)) (decodeUtf8Lenient errBody)))

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

headers :: GoogleConfig -> RequestHeaders
headers cfg =
  [ ("x-goog-api-key", encodeUtf8 (gcApiKey cfg)),
    ("content-type", "application/json")
  ]

-- --- request-body construction --------------------------------------------------------------------

buildBody :: Word32 -> ChatRequest -> Value
buildBody reasoningFloor req =
  kobj $
    concat
      [ [("contents", buildContents (crMessages req))],
        [("systemInstruction", kobj [("parts", arr [kobj [("text", String (spText sp))]])]) | Just sp <- [crSystem req]],
        [("tools", arr toolsArr) | not (null toolsArr)],
        [("toolConfig", kobj [("functionCallingConfig", functionCalling tc)]) | Just tc <- [crToolChoice req]],
        [("generationConfig", generation)]
      ]
  where
    toolsArr = declTools <> concatMap serverTool (crServerTools req)
    declTools =
      [ kobj [("functionDeclarations", arr [funcDecl t | t <- crTools req])]
      | not (null (crTools req))
      ]
    funcDecl t = kobj [("name", String (tdName t)), ("description", String (tdDescription t)), ("parameters", tdSchema t)]
    generation =
      kobj $
        concat
          [ [("maxOutputTokens", toJSON (effectiveMaxOutput (unModelId (crModel req)) (crMaxTokens req) reasoningFloor))],
            [("temperature", toJSON x) | Just x <- [crTemperature req]],
            [("topP", toJSON x) | Just x <- [crTopP req]],
            [("topK", toJSON x) | Just x <- [crTopK req]],
            [("stopSequences", toJSON (crStopSequences req)) | not (null (crStopSequences req))],
            outputSchema,
            [("thinkingConfig", thinkingConfig lvl) | Just lvl <- [crThinking req]]
          ]
    outputSchema = case crOutputFormat req of
      Just (JsonSchema sch) -> [("responseMimeType", String "application/json"), ("responseSchema", sch)]
      Nothing -> []

functionCalling :: ToolChoice -> Value
functionCalling = \case
  ChoiceAuto -> object ["mode" .= s "AUTO"]
  ChoiceRequired -> object ["mode" .= s "ANY"]
  ChoiceNone -> object ["mode" .= s "NONE"]
  ChoiceTool n -> object ["mode" .= s "ANY", "allowedFunctionNames" .= [n]]

serverTool :: ServerTool -> [Value]
serverTool = \case
  STWebSearch {} -> [kobj [("googleSearch", object [])]]
  STCodeExecution -> [kobj [("codeExecution", object [])]]
  _ -> []

thinkingConfig :: ThinkingLevel -> Value
thinkingConfig = \case
  ThinkOff -> kobj [("thinkingBudget", toJSON (0 :: Int))]
  ThinkLow -> kobj [("thinkingLevel", String "low")]
  ThinkMedium -> kobj [("thinkingLevel", String "high")]
  ThinkHigh -> kobj [("thinkingLevel", String "high")]

effectiveMaxOutput :: Text -> Word32 -> Word32 -> Word32
effectiveMaxOutput model requested reasoningFloor
  | isReasoningModel model = max requested reasoningFloor
  | otherwise = requested

isReasoningModel :: Text -> Bool
isReasoningModel model =
  let m = T.toLower model
   in "gemini-3" `T.isPrefixOf` m || "gemini-2.5" `T.isInfixOf` m || "gemini-2-5" `T.isInfixOf` m

buildContents :: [Message] -> Value
buildContents msgs = arr (map msgVal msgs)
  where
    idName = Map.fromList [(i, n) | m <- msgs, ToolUseBlock i n _ <- msgContent m]
    msgVal m = kobj [("role", String (role (msgRole m))), ("parts", arr (map (contentPart idName) (msgContent m)))]
    role User = "user"
    role Assistant = "model"

contentPart :: Map.Map Text Text -> ContentBlock -> Value
contentPart idName = \case
  TextBlock txt _ -> kobj [("text", String txt)]
  ThinkingBlock txt -> kobj [("text", String txt)]
  ImageBlock src -> mediaPart src
  DocumentBlock src _ -> mediaPart src
  ToolUseBlock i n input ->
    kobj $
      [("functionCall", kobj [("name", String n), ("args", input)])]
        <> [("thoughtSignature", String (T.drop 1 sig)) | let (_, sig) = T.breakOn "#" i, not (T.null sig)]
  ToolResultBlock tuid content err ->
    let name = Map.findWithDefault "" tuid idName
        response = if err then kobj [("error", String content)] else kobj [("result", String content)]
     in kobj [("functionResponse", kobj [("name", String name), ("response", response)])]

mediaPart :: MediaSource -> Value
mediaPart = \case
  SrcBase64 mt d -> kobj [("inlineData", kobj [("mimeType", String mt), ("data", String d)])]
  SrcUrl u -> kobj [("fileData", kobj [("fileUri", String u)])]
  SrcFile f -> kobj [("fileData", kobj [("fileUri", String f)])]
  SrcPlainText txt -> kobj [("text", String txt)]

-- --- tiny helpers ---------------------------------------------------------------------------------

kobj :: [(Text, Value)] -> Value
kobj = Object . KM.fromList . map (\(a, b) -> (K.fromText a, b))

arr :: [Value] -> Value
arr = Array . V.fromList

s :: Text -> Text
s = id
