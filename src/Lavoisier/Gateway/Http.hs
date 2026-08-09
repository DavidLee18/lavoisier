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
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON (..), decode, encode, object, withObject, (.:), (.:?), (.=))
import Data.ByteString.Builder (Builder, byteString, lazyByteString)
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Lavoisier.Protocol.Agent (AgentError, AgentHandle (..), TurnRequest (..), TurnStream)
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))
import Network.HTTP.Types (ResponseHeaders, hAuthorization, hContentType, status200, status400, status401, status404)
import Network.Wai
import Network.Wai.Handler.Warp (run)

-- | Auth policy for the protected routes. Empty key set ⇒ open access (suitable for local use).
newtype GatewayConfig = GatewayConfig
  { gcApiKeys :: [Text]
  }

-- | Open (no-auth) policy.
defaultGatewayConfig :: GatewayConfig
defaultGatewayConfig = GatewayConfig []

-- | The 'Gateway' record: bind and serve on @port@ with @warp@. A bind failure maps to
-- 'GEBind'. (Serves until the process is stopped; graceful shutdown lands with the CLI wiring.)
httpGateway :: Int -> GatewayConfig -> Gateway
httpGateway port cfg =
  Gateway
    { gatewayName = "http",
      gatewayServe = \agent -> do
        r <- try (run port (httpApp cfg agent)) :: IO (Either SomeException ())
        pure $ case r of
          Left e -> Left (GEBind (T.pack (show e)))
          Right () -> Right ()
    }

-- | The WAI 'Application' (exposed so tests can exercise it without a socket).
httpApp :: GatewayConfig -> AgentHandle -> Application
httpApp cfg agent req respond =
  case (requestMethod req, pathInfo req) of
    ("GET", ["health"]) -> respond (responseLBS status200 [] "ok")
    ("POST", ["v1", "turns"])
      | authorized cfg req -> do
          body <- strictRequestBody req
          case decode body of
            Nothing -> respond (responseLBS status400 jsonHeader "{\"error\":\"invalid JSON body\"}")
            Just dto -> do
              let turn = TurnRequest (dtoSession dto) (dtoInput dto) Nothing
              estream <- submit agent turn
              case estream of
                Left e -> respond (responseStream status200 sseHeader (sseError e))
                Right stream -> respond (responseStream status200 sseHeader (sseBody stream))
      | otherwise -> respond (responseLBS status401 jsonHeader "{\"error\":\"missing or invalid API key\"}")
    _ -> respond (responseLBS status404 jsonHeader "{\"error\":\"not found\"}")

-- | Stream each event as an SSE @data:@ frame carrying the JSON-encoded 'Event'.
sseBody :: TurnStream -> StreamingBody
sseBody stream write flush = loop
  where
    loop =
      nextItem stream >>= \case
        Nothing -> pure ()
        Just item -> do
          write (frame (encodeItem item))
          flush
          loop
    encodeItem (Right ev) = encode ev
    encodeItem (Left err) = encode (object ["error" .= tshow (err :: AgentError)])

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
