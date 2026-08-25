{- | The A2A (Agent-to-Agent) server gateway — exposes the shared agent as a Google **A2A** agent so
other agents can discover and delegate to it. Ported from Rust @lvz-gw-a2a@ (built earlier the same
day). Depends only on the protocol contracts; hand-rolled JSON-RPC over warp\/wai — no A2A SDK.

Surface: @GET \/.well-known\/agent-card.json@ (discovery) and a JSON-RPC 2.0 endpoint at @POST \/@:
@message\/send@ (run one turn → a completed @Task@), @message\/stream@ (SSE status\/artifact
updates), @tasks\/get@, @tasks\/cancel@. The A2A @contextId@ maps to a Lavoisier session.
-}
module Lavoisier.Gateway.A2A (
    A2aConfig (..),
    defaultA2aConfig,
    newA2aApp,
    a2aGateway,
)
where

import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.ByteString.Builder (byteString, lazyByteString)
import Data.IORef
import Data.Map.Strict (Map)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient)
import Network.HTTP.Types (ResponseHeaders, hAuthorization, hContentType, status200)
import Network.Wai
import Network.Wai.Handler.Warp (run)

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Vector qualified as V

import Lavoisier.Domain (Port, unPort)
import Lavoisier.Protocol.Agent (AgentError, AgentHandle (..), TurnStream, turnRequest)
import Lavoisier.Protocol.Event (Event (..))
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))

a2aProtocolVersion ∷ Text
a2aProtocolVersion = "0.3.0"

-- | Customisable Agent Card fields + auth.
data A2aConfig = A2aConfig
    { a2aName ∷ Text
    , a2aDescription ∷ Text
    , a2aApiKeys ∷ [Text]
    }

defaultA2aConfig ∷ A2aConfig
defaultA2aConfig =
    A2aConfig
        { a2aName = "Lavoisier"
        , a2aDescription = "Token-efficient CLI coding agent, exposed over A2A."
        , a2aApiKeys = []
        }

-- | Mutable per-serve state: the bounded-ish task store and a monotonic id counter.
data A2aState = A2aState
    { stTasks ∷ IORef (Map Text Value)
    , stIds ∷ IORef Int
    , stCard ∷ Value
    , stKeys ∷ [Text]
    , stAgent ∷ AgentHandle
    }

-- | Build the WAI 'Application' (creates the mutable state). Exposed so tests can drive it directly.
newA2aApp ∷ A2aConfig → AgentHandle → IO Application
newA2aApp cfg agent = do
    tasks ← newIORef Map.empty
    ids ← newIORef 0
    let st = A2aState tasks ids (agentCard cfg) (a2aApiKeys cfg) agent
    pure (a2aApp st)

-- | The 'Gateway' record: bind and serve with warp.
a2aGateway ∷ Port → A2aConfig → Gateway
a2aGateway port cfg =
    Gateway
        { gatewayName = "a2a"
        , gatewayServe = \agent → do
            app ← newA2aApp cfg agent
            r ← try (run (fromIntegral (unPort port)) app) ∷ IO (Either SomeException ())
            pure $ case r of
                Left e → Left (GEBind (T.pack (show e)))
                Right () → Right ()
        }

agentCard ∷ A2aConfig → Value
agentCard cfg =
    object
        [ "protocolVersion" .= a2aProtocolVersion
        , "name" .= a2aName cfg
        , "description" .= a2aDescription cfg
        , "version" .= t "0.13.0"
        , "capabilities" .= object ["streaming" .= True, "pushNotifications" .= False]
        , "defaultInputModes" .= [t "text/plain"]
        , "defaultOutputModes" .= [t "text/plain"]
        , "skills"
            .= [ object
                    [ "id" .= t "general"
                    , "name" .= t "General assistant"
                    , "description" .= t "Answers questions and carries out coding tasks with the full tool loop."
                    , "tags" .= [t "coding", t "general"]
                    ]
               ]
        ]

a2aApp ∷ A2aState → Application
a2aApp st req respond =
    case (requestMethod req, pathInfo req) of
        ("GET", [".well-known", "agent-card.json"]) →
            respond (responseLBS status200 jsonHeader (encode (stCard st)))
        ("POST", [])
            | authorized st req → do
                body ← strictRequestBody req
                case decode body of
                    Nothing → respond (jsonRpc (rpcErr Null (-32700) "parse error"))
                    Just j → dispatch st j respond
            | otherwise → respond (jsonRpc (rpcErr Null (-32600) "missing or invalid API key"))
        _ → respond (responseLBS status200 jsonHeader (encode (rpcErr Null (-32601) "not found")))

dispatch ∷ A2aState → Value → (Response → IO ResponseReceived) → IO ResponseReceived
dispatch st j respond =
    case look "method" j >>= asText of
        Just "message/send" → messageSend st rid params respond
        Just "message/stream" → messageStream st rid params respond
        Just "tasks/get" → tasksGet st rid params respond
        Just "tasks/cancel" → tasksCancel st rid params respond
        other → respond (jsonRpc (rpcErr rid (-32601) ("method not found: " <> fromMaybe "?" other)))
    where
        rid = fromMaybe Null (look "id" j)
        params = fromMaybe Null (look "params" j)

-- | @message/send@: run one turn to completion, return a completed @Task@ carrying the reply.
messageSend ∷ A2aState → Value → Value → (Response → IO ResponseReceived) → IO ResponseReceived
messageSend st rid params respond =
    case parseText params of
        Left err → respond (jsonRpc (rpcErr rid (-32602) err))
        Right text → do
            ctx ← resolveCtx st params
            taskId ← nextId st "task"
            eanswer ← runToText (stAgent st) ctx text
            case eanswer of
                Left e → respond (jsonRpc (rpcErr rid (-32603) (tshow e)))
                Right answer → do
                    msgId ← nextId st "msg"
                    artId ← nextId st "artifact"
                    let agentMsg = agentMessage msgId taskId ctx answer
                        userMsg = fromMaybe Null (look "message" params)
                        task =
                            object
                                [ "id" .= taskId
                                , "contextId" .= ctx
                                , "kind" .= t "task"
                                , "status" .= object ["state" .= t "completed", "message" .= agentMsg]
                                , "history" .= [userMsg, agentMsg]
                                , "artifacts" .= [object ["artifactId" .= artId, "parts" .= [textPart answer]]]
                                ]
                    modifyIORef' (stTasks st) (Map.insert taskId task)
                    respond (jsonRpc (rpcOk rid task))

-- | @message/stream@: run one turn, stream A2A status\/artifact updates over SSE.
messageStream ∷ A2aState → Value → Value → (Response → IO ResponseReceived) → IO ResponseReceived
messageStream st rid params respond =
    case parseText params of
        Left err → respond (jsonRpc (rpcErr rid (-32602) err))
        Right text → do
            ctx ← resolveCtx st params
            taskId ← nextId st "task"
            artId ← nextId st "artifact"
            estream ← submit (stAgent st) (turnRequest ctx text)
            case estream of
                Left _ →
                    respond (responseStream status200 sseHeader (frameOnce (rpcOk rid (statusUpdate taskId ctx "failed" True))))
                Right stream →
                    respond (responseStream status200 sseHeader (streamBody rid taskId ctx artId stream))

streamBody ∷ Value → Text → Text → Text → TurnStream → StreamingBody
streamBody rid taskId ctx artId stream write flush = do
    emit (rpcOk rid (statusUpdate taskId ctx "working" False))
    loop
    where
        emit v = write (byteString "data: ") >> write (lazyByteString (encode v)) >> write (byteString "\n\n") >> flush
        loop =
            nextItem stream >>= \case
                Nothing → emit (rpcOk rid (statusUpdate taskId ctx "completed" True))
                Just (Left _) → emit (rpcOk rid (statusUpdate taskId ctx "failed" True))
                Just (Right (TextDelta chunk)) → emit (rpcOk rid (artifactUpdate taskId ctx artId chunk)) >> loop
                Just (Right _) → loop

tasksGet ∷ A2aState → Value → Value → (Response → IO ResponseReceived) → IO ResponseReceived
tasksGet st rid params respond = do
    store ← readIORef (stTasks st)
    case look "id" params >>= asText of
        Just tid | Just task ← Map.lookup tid store → respond (jsonRpc (rpcOk rid task))
        Just tid → respond (jsonRpc (rpcErr rid (-32001) ("task not found: " <> tid)))
        Nothing → respond (jsonRpc (rpcErr rid (-32602) "missing task id"))

tasksCancel ∷ A2aState → Value → Value → (Response → IO ResponseReceived) → IO ResponseReceived
tasksCancel st rid params respond = do
    store ← readIORef (stTasks st)
    case look "id" params >>= asText of
        Just tid | Map.member tid store → respond (jsonRpc (rpcErr rid (-32002) "task cannot be cancelled (already completed)"))
        Just tid → respond (jsonRpc (rpcErr rid (-32001) ("task not found: " <> tid)))
        Nothing → respond (jsonRpc (rpcErr rid (-32602) "missing task id"))

-- --- helpers --------------------------------------------------------------------------------------

runToText ∷ AgentHandle → Text → Text → IO (Either AgentError Text)
runToText handle session input = do
    e ← submit handle (turnRequest session input)
    case e of
        Left err → pure (Left err)
        Right stream → fold "" stream
    where
        fold acc stream =
            nextItem stream >>= \case
                Nothing → pure (Right (T.strip acc))
                Just (Left err) → pure (Left err)
                Just (Right (TextDelta chunk)) → fold (acc <> chunk) stream
                Just (Right _) → fold acc stream

parseText ∷ Value → Either Text Text
parseText params = case look "message" params of
    Nothing → Left "missing `message`"
    Just msg → case look "parts" msg >>= asArray of
        Nothing → Left "message has no `parts`"
        Just parts →
            let txt = T.concat [x | p ← parts, isTextPart p, Just x ← [look "text" p >>= asText]]
             in if T.null txt then Left "message has no text part" else Right txt
    where
        isTextPart p = (look "kind" p >>= asText) == Just "text" || (look "type" p >>= asText) == Just "text"

resolveCtx ∷ A2aState → Value → IO Text
resolveCtx st params = case look "message" params >>= look "contextId" >>= asText of
    Just c → pure c
    Nothing → nextId st "ctx"

nextId ∷ A2aState → Text → IO Text
nextId st prefix = do
    n ← atomicModifyIORef' (stIds st) (\k → (k + 1, k))
    pure (prefix <> "-" <> tshow n)

authorized ∷ A2aState → Request → Bool
authorized st req = case stKeys st of
    [] → True
    keys → case lookup hAuthorization (requestHeaders req) of
        Just v | Just key ← T.stripPrefix "Bearer " (decodeUtf8Lenient v) → key `elem` keys
        _ → False

textPart ∷ Text → Value
textPart txt = object ["kind" .= t "text", "text" .= txt]

agentMessage ∷ Text → Text → Text → Text → Value
agentMessage msgId taskId ctx txt =
    object
        [ "role" .= t "agent"
        , "parts" .= [textPart txt]
        , "messageId" .= msgId
        , "taskId" .= taskId
        , "contextId" .= ctx
        , "kind" .= t "message"
        ]

statusUpdate ∷ Text → Text → Text → Bool → Value
statusUpdate taskId ctx state final =
    object
        [ "taskId" .= taskId
        , "contextId" .= ctx
        , "kind" .= t "status-update"
        , "status" .= object ["state" .= state]
        , "final" .= final
        ]

artifactUpdate ∷ Text → Text → Text → Text → Value
artifactUpdate taskId ctx artId txt =
    object
        [ "taskId" .= taskId
        , "contextId" .= ctx
        , "kind" .= t "artifact-update"
        , "artifact" .= object ["artifactId" .= artId, "parts" .= [textPart txt]]
        , "append" .= True
        , "lastChunk" .= False
        ]

rpcOk ∷ Value → Value → Value
rpcOk rid result = object ["jsonrpc" .= t "2.0", "id" .= rid, "result" .= result]

rpcErr ∷ Value → Int → Text → Value
rpcErr rid code msg = object ["jsonrpc" .= t "2.0", "id" .= rid, "error" .= object ["code" .= code, "message" .= msg]]

jsonRpc ∷ Value → Response
jsonRpc = responseLBS status200 jsonHeader . encode

frameOnce ∷ Value → StreamingBody
frameOnce v write flush = write (byteString "data: ") >> write (lazyByteString (encode v)) >> write (byteString "\n\n") >> flush

sseHeader ∷ ResponseHeaders
sseHeader = [(hContentType, "text/event-stream")]

jsonHeader ∷ ResponseHeaders
jsonHeader = [(hContentType, "application/json")]

look ∷ Text → Value → Maybe Value
look k (Object o) = KM.lookup (K.fromText k) o
look _ _ = Nothing

asText ∷ Value → Maybe Text
asText (String s) = Just s
asText _ = Nothing

asArray ∷ Value → Maybe [Value]
asArray (Array a) = Just (V.toList a)
asArray _ = Nothing

t ∷ Text → Text
t = id

tshow ∷ Show a ⇒ a → Text
tshow = T.pack . show
