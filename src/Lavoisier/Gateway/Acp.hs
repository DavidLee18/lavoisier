-- | The ACP (Agent Communication Protocol, BeeAI\/IBM) server gateway — a REST agents\/runs API.
-- Ported from Rust @lvz-gw-acp@ (built earlier the same day). Depends only on the protocol contracts;
-- hand-rolled REST over warp\/wai — no ACP SDK.
--
-- Surface: @GET \/agents@ + @GET \/agents\/{name}@ (manifest), @POST \/runs@ (create a run in
-- @sync@\/@stream@\/@async@ mode), @GET \/runs\/{id}@, @POST \/runs\/{id}\/cancel@, @GET \/ping@. The
-- ACP @session_id@ maps to a Lavoisier session.
module Lavoisier.Gateway.Acp
  ( AcpConfig (..),
    defaultAcpConfig,
    newAcpApp,
    acpGateway,
  )
where

import Control.Concurrent (forkIO)
import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Builder (byteString, lazyByteString)
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Data.Vector qualified as V
import Lavoisier.Protocol.Agent (AgentHandle (..), TurnStream, turnRequest)
import Lavoisier.Protocol.Event (Event (..))
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))
import Network.HTTP.Types (ResponseHeaders, Status, hAuthorization, hContentType, status200, status400, status401, status404)
import Network.Wai
import Network.Wai.Handler.Warp (run)

agentName :: Text
agentName = "lavoisier"

-- | Manifest description + auth.
data AcpConfig = AcpConfig
  { acpDescription :: Text,
    acpApiKeys :: [Text]
  }

defaultAcpConfig :: AcpConfig
defaultAcpConfig =
  AcpConfig
    { acpDescription = "Token-efficient CLI coding agent, exposed over ACP.",
      acpApiKeys = []
    }

data AcpState = AcpState
  { stRuns :: IORef (Map Text Value),
    stIds :: IORef Int,
    stManifest :: Value,
    stKeys :: [Text],
    stAgent :: AgentHandle
  }

-- | Build the WAI 'Application' (creates the mutable state). Exposed for tests.
newAcpApp :: AcpConfig -> AgentHandle -> IO Application
newAcpApp cfg agent = do
  runs <- newIORef Map.empty
  ids <- newIORef 0
  let st = AcpState runs ids (manifest cfg) (acpApiKeys cfg) agent
  pure (acpApp st)

-- | The 'Gateway' record: bind and serve with warp.
acpGateway :: Int -> AcpConfig -> Gateway
acpGateway port cfg =
  Gateway
    { gatewayName = "acp",
      gatewayServe = \agent -> do
        app <- newAcpApp cfg agent
        r <- try (run port app) :: IO (Either SomeException ())
        pure $ case r of
          Left e -> Left (GEBind (T.pack (show e)))
          Right () -> Right ()
    }

manifest :: AcpConfig -> Value
manifest cfg =
  object
    [ "name" .= agentName,
      "description" .= acpDescription cfg,
      "metadata" .= object ["programming_language" .= t "Haskell"],
      "input_content_types" .= [t "text/plain"],
      "output_content_types" .= [t "text/plain"]
    ]

acpApp :: AcpState -> Application
acpApp st req respond =
  case (requestMethod req, pathInfo req) of
    ("GET", ["ping"]) -> respond (responseLBS status200 [] "pong")
    ("GET", ["agents"]) -> respond (jsonResp status200 (object ["agents" .= [stManifest st]]))
    ("GET", ["agents", name])
      | name == agentName -> respond (jsonResp status200 (stManifest st))
      | otherwise -> respond (errResp status404 ("no such agent: " <> name))
    ("POST", ["runs"])
      | authorized st req -> do
          body <- strictRequestBody req
          case decode body of
            Nothing -> respond (errResp status400 "invalid JSON body")
            Just j -> createRun st j respond
      | otherwise -> respond (errResp status401 "missing or invalid API key")
    ("GET", ["runs", rid])
      | authorized st req -> do
          store <- readIORef (stRuns st)
          case Map.lookup rid store of
            Just r -> respond (jsonResp status200 r)
            Nothing -> respond (errResp status404 ("no such run: " <> rid))
      | otherwise -> respond (errResp status401 "missing or invalid API key")
    ("POST", ["runs", rid, "cancel"])
      | authorized st req -> do
          store <- readIORef (stRuns st)
          case Map.lookup rid store of
            Just r -> respond (jsonResp status200 r)
            Nothing -> respond (errResp status404 ("no such run: " <> rid))
      | otherwise -> respond (errResp status401 "missing or invalid API key")
    _ -> respond (errResp status404 "not found")

createRun :: AcpState -> Value -> (Response -> IO ResponseReceived) -> IO ResponseReceived
createRun st body respond =
  let text = extractInput body
   in if T.null text
        then respond (errResp status400 "run input has no text content")
        else do
          session <- case look "session_id" body >>= asText of
            Just s -> pure s
            Nothing -> nextId st "session"
          runId <- nextId st "run"
          case fromMaybe "sync" (look "mode" body >>= asText) of
            "stream" -> streamRun st runId session text respond
            "async" -> asyncRun st runId session text respond
            _ -> syncRun st runId session text respond

syncRun :: AcpState -> Text -> Text -> Text -> (Response -> IO ResponseReceived) -> IO ResponseReceived
syncRun st runId session text respond = do
  eanswer <- runToText (stAgent st) session text
  case eanswer of
    Left e -> respond (errResp status400 ("run failed: " <> tshow e))
    Right answer -> do
      let r = buildRun runId session "completed" (answerOutput answer)
      modifyIORef' (stRuns st) (Map.insert runId r)
      respond (jsonResp status200 r)

asyncRun :: AcpState -> Text -> Text -> Text -> (Response -> IO ResponseReceived) -> IO ResponseReceived
asyncRun st runId session text respond = do
  let inProgress = buildRun runId session "in-progress" (Array V.empty)
  modifyIORef' (stRuns st) (Map.insert runId inProgress)
  _ <- forkIO $ do
    eanswer <- runToText (stAgent st) session text
    let final = case eanswer of
          Right answer -> buildRun runId session "completed" (answerOutput answer)
          Left e -> addError (buildRun runId session "failed" (Array V.empty)) (tshow e)
    modifyIORef' (stRuns st) (Map.insert runId final)
  respond (jsonResp status200 inProgress)

streamRun :: AcpState -> Text -> Text -> Text -> (Response -> IO ResponseReceived) -> IO ResponseReceived
streamRun st runId session text respond = do
  let inProgress = buildRun runId session "in-progress" (Array V.empty)
  modifyIORef' (stRuns st) (Map.insert runId inProgress)
  estream <- submit (stAgent st) (turnRequest session text)
  case estream of
    Left _ -> respond (responseStream status200 sseHeader (frameOnce (object ["type" .= t "run.failed", "run" .= buildRun runId session "failed" (Array V.empty)])))
    Right stream -> respond (responseStream status200 sseHeader (streamBody st runId session inProgress stream))

streamBody :: AcpState -> Text -> Text -> Value -> TurnStream -> StreamingBody
streamBody st runId session inProgress stream write flush = do
  emit (object ["type" .= t "run.in-progress", "run" .= inProgress])
  loop ""
  where
    emit v = write (byteString "data: ") >> write (lazyByteString (encode v)) >> write (byteString "\n\n") >> flush
    loop acc =
      nextItem stream >>= \case
        Nothing -> do
          let r = buildRun runId session "completed" (answerOutput (T.strip acc))
          modifyIORef' (stRuns st) (Map.insert runId r)
          emit (object ["type" .= t "run.completed", "run" .= r])
        Just (Left _) -> emit (object ["type" .= t "run.failed", "run" .= buildRun runId session "failed" (Array V.empty)])
        Just (Right (TextDelta chunk)) -> do
          emit (object ["type" .= t "message.part", "part" .= object ["content_type" .= t "text/plain", "content" .= chunk]])
          loop (acc <> chunk)
        Just (Right _) -> loop acc

-- --- helpers --------------------------------------------------------------------------------------

runToText :: AgentHandle -> Text -> Text -> IO (Either GatewayError Text)
runToText handle session input = do
  e <- submit handle (turnRequest session input)
  case e of
    Left err -> pure (Left (GEProtocol (tshow err)))
    Right stream -> fold "" stream
  where
    fold acc stream =
      nextItem stream >>= \case
        Nothing -> pure (Right (T.strip acc))
        Just (Left err) -> pure (Left (GEProtocol (tshow err)))
        Just (Right (TextDelta chunk)) -> fold (acc <> chunk) stream
        Just (Right _) -> fold acc stream

-- | Pull all text-part content out of a run's @input@ messages.
extractInput :: Value -> Text
extractInput body =
  case look "input" body >>= asArray of
    Nothing -> ""
    Just msgs ->
      T.concat
        [ c
          | msg <- msgs,
            Just parts <- [look "parts" msg >>= asArray],
            p <- parts,
            isText p,
            Just c <- [look "content" p >>= asText]
        ]
  where
    isText p = case look "content_type" p >>= asText of
      Just ct -> "text" `T.isPrefixOf` ct
      Nothing -> True -- default content_type is text/plain

answerOutput :: Text -> Value
answerOutput answer =
  Array $
    V.singleton $
      object
        [ "role" .= t "agent/lavoisier",
          "parts" .= [object ["content_type" .= t "text/plain", "content" .= answer]]
        ]

buildRun :: Text -> Text -> Text -> Value -> Value
buildRun runId session status output =
  object
    [ "run_id" .= runId,
      "agent_name" .= agentName,
      "session_id" .= session,
      "status" .= status,
      "output" .= output
    ]

addError :: Value -> Text -> Value
addError (Object o) msg = Object (KM.insert (K.fromText "error") (object ["message" .= msg]) o)
addError v _ = v

nextId :: AcpState -> Text -> IO Text
nextId st prefix = do
  n <- atomicModifyIORef' (stIds st) (\k -> (k + 1, k))
  pure (prefix <> "-" <> tshow n)

authorized :: AcpState -> Request -> Bool
authorized st req = case stKeys st of
  [] -> True
  keys -> case lookup hAuthorization (requestHeaders req) of
    Just v | Just key <- T.stripPrefix "Bearer " (decodeUtf8Lenient v) -> key `elem` keys
    _ -> False

jsonResp :: Status -> Value -> Response
jsonResp status = responseLBS status jsonHeader . encode

errResp :: Status -> Text -> Response
errResp status msg = responseLBS status jsonHeader (encode (object ["error" .= msg]))

frameOnce :: Value -> StreamingBody
frameOnce v write flush = write (byteString "data: ") >> write (lazyByteString (encode v)) >> write (byteString "\n\n") >> flush

sseHeader :: ResponseHeaders
sseHeader = [(hContentType, "text/event-stream")]

jsonHeader :: ResponseHeaders
jsonHeader = [(hContentType, "application/json")]

look :: Text -> Value -> Maybe Value
look k (Object o) = KM.lookup (K.fromText k) o
look _ _ = Nothing

asText :: Value -> Maybe Text
asText (String s) = Just s
asText _ = Nothing

asArray :: Value -> Maybe [Value]
asArray (Array a) = Just (V.toList a)
asArray _ = Nothing

t :: Text -> Text
t = id

tshow :: (Show a) => a -> Text
tshow = T.pack . show
