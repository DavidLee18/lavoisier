{-# LANGUAGE DataKinds #-}

{- | xAI's __Responses API__ (@POST \/v1\/responses@) — the Agent-Tools transport.

A third xAI transport beside "Lavoisier.Provider.Xai" (@chat\/completions@) and
"Lavoisier.Provider.Xai.Grpc", not a replacement for either. It exists because xAI's provider-run
tools live only here: the old route into them, Live Search via @search_parameters@ on
@chat\/completions@, has returned @410 Gone@ since 2026-01-12.

The request is a different shape from @chat\/completions@ — @input@ rather than @messages@,
@instructions@ rather than a system message, @max_output_tokens@ rather than @max_tokens@, and tools
declared __flat__ (@{"type":"function","name":…}@) rather than nested under @"function"@. The
response stream is decoded by "Lavoisier.Provider.Xai.ResponsesSse".
-}
module Lavoisier.Provider.Xai.Responses (
    xaiResponsesFromEnv,
    xaiResponsesProvider,
    XaiResponsesConfig (..),
    newXaiResponsesConfig,
    defaultResponsesBaseUrl,

    -- * exposed for testing
    XaiResponsesCaps,
    buildBody,
    inputItems,
    serverToolJson,
)
where

import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), encode, object, toJSON, (.=))
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (RequestHeaders)
import Network.HTTP.Types.Status (statusCode, statusIsSuccessful)
import System.Environment (lookupEnv)

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T

import Lavoisier.Domain (ModelId (..), renderDate)
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Provider.Xai.ResponsesSse (initResp, respEof, respPush)

-- | Connection settings. @xrBaseUrl@ has no trailing @\/responses@ — that is appended.
data XaiResponsesConfig = XaiResponsesConfig
    { xrApiKey ∷ Text
    , xrBaseUrl ∷ Text
    , xrManager ∷ Manager
    }

-- | @https:\/\/api.x.ai\/v1@.
defaultResponsesBaseUrl ∷ Text
defaultResponsesBaseUrl = "https://api.x.ai/v1"

newXaiResponsesConfig ∷ Text → Text → IO XaiResponsesConfig
newXaiResponsesConfig apiKey baseUrl = do
    mgr ← newManager tlsManagerSettings
    pure (XaiResponsesConfig apiKey baseUrl mgr)

-- | Construct from @XAI_API_KEY@ (required) and @XAI_BASE_URL@ (optional).
xaiResponsesFromEnv ∷ IO (Either ProviderError Provider)
xaiResponsesFromEnv = do
    mkey ← lookupEnv "XAI_API_KEY"
    case mkey of
        Nothing → pure (Left (PConfig "XAI_API_KEY is not set"))
        Just key → do
            base ← maybe defaultResponsesBaseUrl T.pack <$> lookupEnv "XAI_BASE_URL"
            cfg ← newXaiResponsesConfig (T.pack key) base
            pure (Right (xaiResponsesProvider cfg))

{- | Everything this transport supports, named once so 'declare' and 'negotiate' cannot drift apart.

Deliberately absent, each for a reason:

* __'PromptCaching'__ — xAI caches server-side with no request markers, and the usage payload
  carries @input_tokens_details.cached_tokens@ but no cache-/creation/ counter.
* __'Vision'__, __'StructuredOutput'__, __'StopSequences'__ — the request fields exist in the
  OpenAI-shaped API but were not exercised against the live endpoint, so declaring them would let a
  request through on an unverified encoding.
* __'TopK'__ — xAI has no @top_k@ on any transport.
* __'WebFetch'__, __'UrlContext'__, __'ClientBuiltinTools'__, __'RemoteMcp'__ — other providers\'
  tools.
-}
type XaiResponsesCaps =
    '[ 'ExtendedThinking
     , 'Sampling
     , 'ToolChoiceControl
     , 'WebSearch
     , 'XSearch
     , 'CodeExecution
     , 'CollectionsSearch
     ]

xaiResponsesProvider ∷ XaiResponsesConfig → Provider
xaiResponsesProvider cfg =
    Provider
        { providerStream = responsesStream cfg
        , providerCapabilities = declare @XaiResponsesCaps
        , providerCountTokens = \_ → pure (Right Nothing)
        }

-- --- streaming -------------------------------------------------------------------------------------

responsesStream ∷ XaiResponsesConfig → ChatRequest → IO (Either ProviderError EventStream)
responsesStream cfg chatReq = withNegotiated @XaiResponsesCaps chatReq $ \nreq → do
    let body = encode (buildBody nreq)
        url = T.unpack (T.dropWhileEnd (== '/') (xrBaseUrl cfg)) <> "/responses"
    ereq0 ← try (parseRequest url) ∷ IO (Either SomeException Request)
    case ereq0 of
        Left e → pure (Left (PConfig (T.pack (show e))))
        Right base → do
            let httpReq =
                    base
                        { method = "POST"
                        , requestHeaders = headers cfg
                        , requestBody = RequestBodyLBS body
                        , responseTimeout = responseTimeoutNone
                        }
            eresp ← try (responseOpen httpReq (xrManager cfg)) ∷ IO (Either HttpException (Response BodyReader))
            case eresp of
                Left e → pure (Left (PTransport (T.pack (show e))))
                Right resp
                    | statusIsSuccessful (responseStatus resp) → Right <$> makeStream resp
                    | otherwise → do
                        errBody ← BS.concat <$> brConsume (responseBody resp)
                        responseClose resp
                        pure (Left (PApi (statusCode (responseStatus resp)) (decodeUtf8Lenient errBody)))

headers ∷ XaiResponsesConfig → RequestHeaders
headers cfg =
    [ ("content-type", "application/json")
    , ("authorization", "Bearer " <> encodeUtf8 (xrApiKey cfg))
    ]

-- | Wrap the open response in a pull 'Producer' over the Responses SSE decoder.
makeStream ∷ Response BodyReader → IO EventStream
makeStream resp = do
    stateRef ← newIORef initResp
    pendRef ← newIORef []
    doneRef ← newIORef False
    let feed [] = pull
        feed (x : xs) = writeIORef pendRef xs >> pure (Just x)
        pull =
            readIORef pendRef >>= \case
                (x : xs) → writeIORef pendRef xs >> pure (Just x)
                [] →
                    readIORef doneRef >>= \case
                        True → pure Nothing
                        False → do
                            chunk ← brRead (responseBody resp)
                            if BS.null chunk
                                then do
                                    st ← readIORef stateRef
                                    responseClose resp
                                    writeIORef doneRef True
                                    feed (respEof st)
                                else do
                                    st ← readIORef stateRef
                                    let (st', evs) = respPush st chunk
                                    writeIORef stateRef st'
                                    feed evs
    pure (Producer pull)

-- --- the request body ------------------------------------------------------------------------------

-- | The @\/v1\/responses@ body.
buildBody ∷ Negotiated caps → Value
buildBody nreq =
    object $
        [ "model" .= unModelId (crModel req)
        , "stream" .= True
        , "input" .= inputItems (crMessages req)
        , "max_output_tokens" .= crMaxTokens req
        ]
            <> ["instructions" .= spText sp | Just sp ← [crSystem req]]
            <> ["temperature" .= t | Just t ← [crTemperature req]]
            <> ["top_p" .= p | Just p ← [crTopP req]]
            <> ["reasoning" .= object ["effort" .= effortOf l] | Just l ← [crThinking req], l /= ThinkOff]
            <> ["tool_choice" .= toolChoiceJson tc | Just tc ← [crToolChoice req]]
            <> ["tools" .= allTools | not (null allTools)]
    where
        req = negotiatedRequest nreq
        allTools = map functionToolJson (crTools req) <> mapMaybe serverToolJson (crServerTools req)

{- | @low@ or @high@ — xAI's only two reasoning efforts (medium rounds down, not up: on a
cost-weighted metric, buying more reasoning than was asked for is the worse error).
-}
effortOf ∷ ThinkingLevel → Text
effortOf = \case
    ThinkHigh → "high"
    _ → "low"

{- | A client-side tool. Responses declares these __flat__ — @{"type":"function","name":…}@ — where
@chat\/completions@ nests them under @"function"@. Verified against the live endpoint.
-}
functionToolJson ∷ ToolDef → Value
functionToolJson t =
    object
        [ "type" .= ("function" ∷ Text)
        , "name" .= tdName t
        , "description" .= tdDescription t
        , "parameters" .= tdSchema t
        ]

{- | A provider-run tool. 'Nothing' for tools this transport does not run; 'negotiate' refuses those
before they reach here, and a test pins the two lists together.
-}
serverToolJson ∷ ServerTool → Maybe Value
serverToolJson = \case
    STWebSearch _ allowed blocked →
        Just . object $
            ["type" .= ("web_search" ∷ Text)]
                -- allowed_domains and excluded_domains cannot both be set; allowed wins.
                <> [ "filters" .= object ["allowed_domains" .= allowed]
                   | not (null allowed)
                   ]
                <> [ "filters" .= object ["excluded_domains" .= blocked]
                   | null allowed && not (null blocked)
                   ]
    STXSearch allowed blocked from to →
        Just . object $
            ["type" .= ("x_search" ∷ Text)]
                <> ["allowed_x_handles" .= allowed | not (null allowed)]
                <> ["excluded_x_handles" .= blocked | null allowed, not (null blocked)]
                <> ["from_date" .= renderDate d | Just d ← [from]]
                <> ["to_date" .= renderDate d | Just d ← [to]]
    STCodeExecution → Just (object ["type" .= ("code_interpreter" ∷ Text)])
    STCollectionsSearch ids lim →
        Just . object $
            ["type" .= ("collections_search" ∷ Text), "collection_ids" .= ids]
                <> ["limit" .= n | Just n ← [lim]]
    STWebFetch {} → Nothing
    STUrlContext → Nothing

toolChoiceJson ∷ ToolChoice → Value
toolChoiceJson = \case
    ChoiceAuto → String "auto"
    ChoiceRequired → String "required"
    ChoiceNone → String "none"
    ChoiceTool n → object ["type" .= ("function" ∷ Text), "name" .= n]

{- | Messages → the @input@ array.

Assistant tool calls and their results round-trip as @function_call@ \/ @function_call_output@ items
keyed by @call_id@ — the id the stream reports as @call_id@, __not__ the @fc_…@ item id.

Verified live on 2026-08-25 by a three-turn agent run: the model called a tool, saw its result, and
answered from it, which only happens if both the @function_call@ echo and the
@function_call_output@ item are encoded as the provider expects.
-}
inputItems ∷ [Message] → Value
inputItems msgs = toJSON (concatMap one msgs)
    where
        one m = concatMap (blockItem (roleText (msgRole m))) (msgContent m)

        blockItem role = \case
            TextBlock t _ | not (T.null t) → [object ["role" .= role, "content" .= t]]
            ThinkingBlock _ → []
            ToolUseBlock callId name args →
                [ object
                    [ "type" .= ("function_call" ∷ Text)
                    , "call_id" .= callId
                    , "name" .= name
                    , "arguments" .= encodeArgs args
                    ]
                ]
            ToolResultBlock callId content _ →
                [ object
                    [ "type" .= ("function_call_output" ∷ Text)
                    , "call_id" .= callId
                    , "output" .= content
                    ]
                ]
            _ → []

        roleText ∷ Role → Text
        roleText = \case
            User → "user"
            Assistant → "assistant"

        encodeArgs ∷ Value → Text
        encodeArgs v = decodeUtf8Lenient (BL.toStrict (encode v))
