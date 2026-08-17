-- | The HTTP gateway — a concrete 'Gateway' that fronts the shared agent over HTTP. Ported (core
-- subset) from Rust @lvz-gw-http@. It depends only on the protocol contracts (the 'AgentHandle' +
-- the normalised 'Event' stream), so the same agent core serves the CLI and this gateway unchanged.
--
-- Surface (this pass):
--
--   * @GET  \/health@   — liveness.
--   * @POST \/v1\/turns@ — submit one turn (@{ "session"?, "input" }@) and stream the resulting
--     'Event's back as **Server-Sent Events** (one JSON-encoded 'Event' per @data:@ frame), matching
--     the Rust gateway's wire shape.
--
-- Optional bearer-key auth gates @\/v1\/turns@. The WebSocket endpoint, Prometheus @\/metrics@, and
-- rate limiting are deferred to a follow-up.
module Lavoisier.Gateway.Http
  ( GatewayConfig (..),
    defaultGatewayConfig,
    httpApp,
    httpGateway,
    newHttpApp,
    stepWindow,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON (..), decode, encode, object, withObject, (.:), (.:?), (.=))
import Data.ByteString.Builder (Builder, byteString, lazyByteString)
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Word (Word32, Word64)
import GHC.Clock (getMonotonicTime)
import Lavoisier.Protocol.Agent (AgentError, AgentHandle (..), TurnRequest (..), TurnStream)
import Lavoisier.Protocol.Event (Event (Usage), Usage (..))
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))
import Network.HTTP.Types (ResponseHeaders, hAuthorization, hContentType, status200, status400, status401, status404, status429)
import Network.Wai
import Network.Wai.Handler.Warp (run)

-- | Auth + quota policy for the protected routes. Empty key set ⇒ open access; 'gcRateLimit' is an
-- optional @(max requests, window seconds)@ per principal (the API key, or @anon@ when auth is off).
data GatewayConfig = GatewayConfig
  { gcApiKeys :: [Text],
    gcRateLimit :: Maybe (Word32, Double)
  }

-- | Open (no-auth, no-quota) policy.
defaultGatewayConfig :: GatewayConfig
defaultGatewayConfig = GatewayConfig [] Nothing

-- | The 'Gateway' record: bind and serve on @port@ with @warp@. A bind failure maps to
-- 'GEBind'. (Serves until the process is stopped; graceful shutdown lands with the CLI wiring.)
httpGateway :: Int -> GatewayConfig -> Gateway
httpGateway port cfg =
  Gateway
    { gatewayName = "http",
      gatewayServe = \agent -> do
        app <- newHttpApp cfg agent
        r <- try (run port app) :: IO (Either SomeException ())
        pure $ case r of
          Left e -> Left (GEBind (T.pack (show e)))
          Right () -> Right ()
    }

-- | Build the stateful WAI 'Application': @/health@ and @/metrics@ are always open, @/v1/turns@ sits
-- behind the auth + rate-limit guard. The 'Metrics' counters and rate-limit windows live in this
-- closure (created once), so use this — not 'httpApp' — when their state must persist across requests.
newHttpApp :: GatewayConfig -> AgentHandle -> IO Application
newHttpApp cfg agent = do
  metrics <- newMetrics
  limiter <- traverse (uncurry newLimiter) (gcRateLimit cfg)
  pure $ \req respond ->
    case (requestMethod req, pathInfo req) of
      ("GET", ["health"]) -> respond (responseLBS status200 [] "ok")
      ("GET", ["metrics"]) -> do
        body <- renderMetrics metrics
        respond (responseLBS status200 [(hContentType, "text/plain; version=0.0.4")] (BL.fromStrict (encodeUtf8 body)))
      ("POST", ["v1", "turns"])
        | authorized cfg req -> do
            ok <- maybe (pure True) (\l -> allow l (principal cfg req)) limiter
            if not ok
              then respond (responseLBS status429 jsonHeader "{\"error\":\"rate limit exceeded\"}")
              else do
                body <- strictRequestBody req
                case decode body of
                  Nothing -> respond (responseLBS status400 jsonHeader "{\"error\":\"invalid JSON body\"}")
                  Just dto -> do
                    let turn = TurnRequest (dtoSession dto) (dtoInput dto) Nothing
                    estream <- submit agent turn
                    case estream of
                      Left e -> recordTurn metrics True >> respond (responseStream status200 sseHeader (sseError e))
                      Right stream -> recordTurn metrics False >> respond (responseStream status200 sseHeader (sseBody metrics stream))
        | otherwise -> respond (responseLBS status401 jsonHeader "{\"error\":\"missing or invalid API key\"}")
      _ -> respond (responseLBS status404 jsonHeader "{\"error\":\"not found\"}")

-- | The stateless convenience 'Application' (fresh metrics\/limiter per request — fine for one-shot
-- tests, but rate-limit\/metrics accumulation needs 'newHttpApp').
httpApp :: GatewayConfig -> AgentHandle -> Application
httpApp cfg agent req respond = do
  app <- newHttpApp cfg agent
  app req respond

-- | Stream each event as an SSE @data:@ frame, tapping the terminal 'Usage' into the metrics.
sseBody :: Metrics -> TurnStream -> StreamingBody
sseBody metrics stream write flush = loop
  where
    loop =
      nextItem stream >>= \case
        Nothing -> pure ()
        Just item -> do
          case item of
            Right (Usage u) -> recordUsage metrics u
            _ -> pure ()
          write (frame (encodeItem item))
          flush
          loop
    encodeItem (Right ev) = encode ev
    encodeItem (Left err) = encode (object ["error" .= tshow (err :: AgentError)])

-- --- metrics (Prometheus counters at /metrics) -----------------------------------------------------

-- | Process-wide counters. The agent emits one terminal 'Usage' per turn (the task total), so the
-- token counters record that single total, never double-counting.
data Metrics = Metrics
  { mTurns :: IORef Word64,
    mErrors :: IORef Word64,
    mInput :: IORef Word64,
    mOutput :: IORef Word64,
    mCacheRead :: IORef Word64,
    mCacheCreate :: IORef Word64
  }

newMetrics :: IO Metrics
newMetrics = Metrics <$> newIORef 0 <*> newIORef 0 <*> newIORef 0 <*> newIORef 0 <*> newIORef 0 <*> newIORef 0

recordTurn :: Metrics -> Bool -> IO ()
recordTurn m errored = do
  modifyIORef' (mTurns m) (+ 1)
  if errored then modifyIORef' (mErrors m) (+ 1) else pure ()

recordUsage :: Metrics -> Usage -> IO ()
recordUsage m u = do
  modifyIORef' (mInput m) (+ inputTokens u)
  modifyIORef' (mOutput m) (+ outputTokens u)
  modifyIORef' (mCacheRead m) (+ cacheReadTokens u)
  modifyIORef' (mCacheCreate m) (+ cacheCreationTokens u)

renderMetrics :: Metrics -> IO Text
renderMetrics m = do
  t <- readIORef (mTurns m)
  e <- readIORef (mErrors m)
  i <- readIORef (mInput m)
  o <- readIORef (mOutput m)
  cr <- readIORef (mCacheRead m)
  cc <- readIORef (mCacheCreate m)
  pure $
    T.concat
      [ counter "lavoisier_turns_total" t,
        counter "lavoisier_errors_total" e,
        counter "lavoisier_input_tokens_total" i,
        counter "lavoisier_output_tokens_total" o,
        counter "lavoisier_cache_read_tokens_total" cr,
        counter "lavoisier_cache_creation_tokens_total" cc
      ]
  where
    counter name v = "# TYPE " <> name <> " counter\n" <> name <> " " <> tshow v <> "\n"

-- --- rate limiting (per-principal fixed window) ----------------------------------------------------

-- | A per-principal request counter over a fixed time window.
data Limiter = Limiter
  { limMax :: Word32,
    limWindow :: Double,
    limState :: IORef (Map Text (Double, Word32))
  }

newLimiter :: Word32 -> Double -> IO Limiter
newLimiter mx w = Limiter mx w <$> newIORef Map.empty

-- | Record a request for @principal@; 'False' once it exceeds the window's cap.
allow :: Limiter -> Text -> IO Bool
allow l pr = do
  now <- getMonotonicTime
  atomicModifyIORef' (limState l) $ \st ->
    let (ok, w') = stepWindow (limMax l) (limWindow l) now (Map.lookup pr st)
     in (Map.insert pr w' st, ok)

-- | Pure fixed-window decision: reset the window if it has elapsed, then admit unless the count has
-- reached the cap. Returns @(admit?, new window state)@.
stepWindow :: Word32 -> Double -> Double -> Maybe (Double, Word32) -> (Bool, (Double, Word32))
stepWindow mx window now cur =
  let (start, count) = case cur of
        Just (s, c) | now - s < window -> (s, c)
        _ -> (now, 0)
   in if count >= mx then (False, (start, count)) else (True, (start, count + 1))

-- | The rate-limit principal: the bearer API key when auth is on, else @anon@.
principal :: GatewayConfig -> Request -> Text
principal cfg req = case gcApiKeys cfg of
  [] -> "anon"
  _ -> case lookup hAuthorization (requestHeaders req) of
    Just v | Just k <- T.stripPrefix "Bearer " (decodeUtf8Lenient v) -> k
    _ -> "anon"

-- | A single terminal error frame when the turn could not even start.
sseError :: AgentError -> StreamingBody
sseError err write flush = do
  write (byteString "event: error\n")
  write (frame (encode (object ["error" .= tshow err])))
  flush

-- | Wrap a JSON payload as an SSE @data:@ frame.
frame :: BL.ByteString -> Builder
frame json = byteString "data: " <> lazyByteString json <> byteString "\n\n"

-- --- request auth + body ---------------------------------------------------------------------------

-- | Enforce the API-key policy: open when no keys are configured, else a matching
-- @Authorization: Bearer \<key\>@ is required.
authorized :: GatewayConfig -> Request -> Bool
authorized cfg req = case gcApiKeys cfg of
  [] -> True
  keys -> case lookup hAuthorization (requestHeaders req) of
    Just v | Just key <- T.stripPrefix "Bearer " (decodeUtf8Lenient v) -> key `elem` keys
    _ -> False

-- | The inbound turn payload. @session@ defaults so a single-session client can omit it.
data TurnDto = TurnDto
  { dtoSession :: Text,
    dtoInput :: Text
  }

instance FromJSON TurnDto where
  parseJSON = withObject "TurnDto" $ \o ->
    TurnDto
      <$> (fromMaybe "default" <$> o .:? "session")
      <*> o .: "input"

sseHeader :: ResponseHeaders
sseHeader = [(hContentType, "text/event-stream")]

jsonHeader :: ResponseHeaders
jsonHeader = [(hContentType, "application/json")]

tshow :: (Show a) => a -> Text
tshow = T.pack . show
