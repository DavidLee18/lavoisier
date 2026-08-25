{- | @Lavoisier.Gateway.Slack@ — a Slack gateway driving the shared agent over __Socket Mode__.
Ported from Rust @lvz-gw-slack@.

A deliberately __thin__ client — @http-client@ for the Web API and @wuss@\/@websockets@ for the
Socket Mode WebSocket, no Slack SDK. Socket Mode means __no inbound port__: the bot opens an
outbound WebSocket (@apps.connections.open@), receives @message@\/@app_mention@ events over it,
runs an agent turn, and posts the reply with @chat.postMessage@.

Sessions are keyed per channel (or per thread, when a message is threaded), so the session store
gives each conversation continuity. Auth: an app-level token (@xapp-…@, @SLACK_APP_TOKEN@) opens
the socket; a bot token (@xoxb-…@, @SLACK_BOT_TOKEN@) makes Web API calls; an optional
@SLACK_ALLOWED_USERS@ allowlist restricts who may drive the agent.

The WebSocket serve loop needs a live Slack workspace, so only the pure event parsing is
unit-tested here (like the Matrix gateway).
-}
module Lavoisier.Gateway.Slack (
    SlackConfig (..),
    slackFromEnv,
    slackGateway,
    -- exposed for testing
    SlackMessage (..),
    slackSession,
    senderAllowed,
    parseEvent,
)
where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (forever, void, when)
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.Socket (PortNumber)
import Network.URI (URI (..), URIAuth (..), parseURI)
import Network.WebSockets (Connection, ConnectionException, DataMessage (..), receiveDataMessage, sendTextData)
import System.Environment (lookupEnv)
import Wuss (runSecureClient)

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as BL
import Data.Set qualified as Set
import Data.Text qualified as T

import Lavoisier.Protocol.Agent (AgentHandle (..), turnRequest)
import Lavoisier.Protocol.Event (Event (..))
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))

-- | Configuration for a Slack Socket-Mode connection.
data SlackConfig = SlackConfig
    { scAppToken ∷ Text
    , scBotToken ∷ Text
    , scAllowedUsers ∷ Maybe (Set Text)
    -- ^ If set, only answer messages whose sender is in this allowlist. 'Nothing' ⇒ answer everyone.
    }

{- | Build the config from @SLACK_APP_TOKEN@, @SLACK_BOT_TOKEN@, and the optional comma-separated
@SLACK_ALLOWED_USERS@.
-}
slackFromEnv ∷ IO (Either GatewayError SlackConfig)
slackFromEnv = do
    mapp ← lookupEnv "SLACK_APP_TOKEN"
    mbot ← lookupEnv "SLACK_BOT_TOKEN"
    users ← lookupEnv "SLACK_ALLOWED_USERS"
    pure $ case (mapp, mbot) of
        (Nothing, _) → Left (GEBind "SLACK_APP_TOKEN is not set")
        (_, Nothing) → Left (GEBind "SLACK_BOT_TOKEN is not set")
        (Just app, Just bot) → Right (SlackConfig (T.pack app) (T.pack bot) (parseAllowed users))
    where
        parseAllowed Nothing = Nothing
        parseAllowed (Just raw) =
            let set = Set.fromList [u | u ← map T.strip (T.splitOn "," (T.pack raw)), not (T.null u)]
             in if Set.null set then Nothing else Just set

-- | The 'Gateway' record backed by a 'SlackConfig'.
slackGateway ∷ SlackConfig → Gateway
slackGateway cfg =
    Gateway
        { gatewayName = "slack"
        , gatewayServe = serveLoop cfg
        }

-- --- the serve loop (live-only; needs a real Slack workspace) --------------------------------------

serveLoop ∷ SlackConfig → AgentHandle → IO (Either GatewayError ())
serveLoop cfg agent = do
    mgr ← newManager tlsManagerSettings
    eid ← botUserId mgr cfg
    case eid of
        Left e → pure (Left e) -- a genuine auth/config error surfaces immediately
        Right botUser →
            -- Keep a Socket Mode connection alive, reconnecting on the periodic `disconnect` refresh
            -- (Right ()) or backing off briefly on a transient failure (Left _). Runs until the process
            -- is killed, like the other gateways' serve loops.
            fmap Right . forever $ do
                r ← runConnection cfg mgr agent botUser
                case r of
                    Left _ → threadDelay 3000000
                    Right () → pure ()

runConnection ∷ SlackConfig → Manager → AgentHandle → Text → IO (Either GatewayError ())
runConnection cfg mgr agent botUser = do
    eurl ← openConnection mgr cfg
    case eurl of
        Left e → pure (Left e)
        Right url → case wssParts url of
            Nothing → pure (Left (GEProtocol ("slack: bad socket url: " <> url)))
            Just (host, port, path) → do
                er ← try (runSecureClient host port path (clientApp cfg mgr agent botUser)) ∷ IO (Either SomeException ())
                pure $ case er of
                    Left e → Left (GEIo ("slack socket: " <> tshow e))
                    Right () → Right ()

{- | Pump one Socket Mode WebSocket until it closes or the server asks us to reconnect (@disconnect@).
@websockets@ auto-replies to ping frames, so we only handle text frames.
-}
clientApp ∷ SlackConfig → Manager → AgentHandle → Text → Connection → IO ()
clientApp cfg mgr agent botUser conn = loop
    where
        loop = do
            edm ← try (receiveDataMessage conn) ∷ IO (Either ConnectionException DataMessage)
            case edm of
                Left _ → pure () -- closed / reconnect
                Right (Text bs _) → do
                    cont ← handleFrame cfg mgr agent botUser conn (decode bs)
                    when cont loop
                Right (Binary _) → loop

-- | Handle one decoded Socket-Mode frame; returns 'False' when the server asked us to reconnect.
handleFrame ∷ SlackConfig → Manager → AgentHandle → Text → Connection → Maybe Value → IO Bool
handleFrame _ _ _ _ _ Nothing = pure True
handleFrame cfg mgr agent botUser conn (Just value) =
    case lookStr "type" value of
        Just "hello" → pure True
        Just "disconnect" → pure False -- the server refreshes the connection; reopen a new one
        Just "events_api" → do
            ackEnvelope conn value
            case lookKey "payload" value of
                Just payload → case parseEvent payload botUser (scAllowedUsers cfg) of
                    -- Run the turn off the read loop so acks/pings keep flowing.
                    Just msg → void (forkIO (handleTurn cfg mgr agent msg)) >> pure True
                    Nothing → pure True
                Nothing → pure True
        -- slash_commands / interactive / unknown: ack and ignore (out of scope).
        _ → ackEnvelope conn value >> pure True

-- | Ack a Socket-Mode envelope by echoing its @envelope_id@ (Slack expects it within ~3s).
ackEnvelope ∷ Connection → Value → IO ()
ackEnvelope conn value = case lookStr "envelope_id" value of
    Just eid → sendTextData conn (encode (object ["envelope_id" .= eid]))
    Nothing → pure ()

-- | Run one inbound message through the agent and post the reply (spawned per message).
handleTurn ∷ SlackConfig → Manager → AgentHandle → SlackMessage → IO ()
handleTurn cfg mgr agent msg = do
    est ← submit agent (turnRequest (slackSession msg) (smText msg))
    case est of
        Left _ → pure ()
        Right stream → do
            answer ← drainText stream ""
            let trimmed = T.strip answer
            if T.null trimmed
                then pure ()
                else postMessage mgr cfg (smChannel msg) (smThreadTs msg) trimmed
    where
        drainText stream acc =
            nextItem stream >>= \case
                Nothing → pure acc
                Just (Left _) → pure acc
                Just (Right (TextDelta t)) → drainText stream (acc <> t)
                Just (Right _) → drainText stream acc

-- --- Slack Web API (http-client) -------------------------------------------------------------------

{- | @POST https:\/\/slack.com\/api\/\<method\>@ with a bearer @token@ and a JSON @body@; returns the
parsed response. Slack signals app-level failure with @{"ok": false, "error": …}@ even on HTTP 200,
so callers check @ok@.
-}
webPost ∷ Manager → Text → Text → Value → IO (Either GatewayError Value)
webPost mgr token method body = do
    er ← try (parseRequest ("POST https://slack.com/api/" <> T.unpack method)) ∷ IO (Either SomeException Request)
    case er of
        Left e → pure (Left (GEIo (tshow e)))
        Right req0 → do
            let req =
                    req0
                        { requestHeaders =
                            [ ("Authorization", "Bearer " <> encodeUtf8 token)
                            , ("Content-Type", "application/json")
                            ]
                        , requestBody = RequestBodyLBS (encode body)
                        }
            eresp ← try (httpLbs req mgr) ∷ IO (Either HttpException (Response BL.ByteString))
            pure $ case eresp of
                Left e → Left (GEIo (tshow e))
                Right resp → maybe (Left (GEProtocol "slack: non-JSON response")) Right (decode (responseBody resp))

-- | Resolve our own bot user id (so we never answer our own messages) via @auth.test@.
botUserId ∷ Manager → SlackConfig → IO (Either GatewayError Text)
botUserId mgr cfg = do
    r ← webPost mgr (scBotToken cfg) "auth.test" (object [])
    pure $ case r of
        Left e → Left e
        Right v
            | lookBool "ok" v /= Just True →
                Left (GEBind ("slack auth.test failed: " <> fromMaybe "unknown" (lookStr "error" v)))
            | otherwise → maybe (Left (GEProtocol "auth.test missing user_id")) Right (lookStr "user_id" v)

{- | Open a Socket Mode connection and return its @wss:\/\/@ URL (@apps.connections.open@ uses the
__app-level__ token, not the bot token).
-}
openConnection ∷ Manager → SlackConfig → IO (Either GatewayError Text)
openConnection mgr cfg = do
    r ← webPost mgr (scAppToken cfg) "apps.connections.open" (object [])
    pure $ case r of
        Left e → Left e
        Right v
            | lookBool "ok" v /= Just True →
                Left (GEBind ("slack apps.connections.open failed: " <> fromMaybe "unknown" (lookStr "error" v)))
            | otherwise → maybe (Left (GEProtocol "connections.open missing url")) Right (lookStr "url" v)

-- | Post a reply to a channel, threading it under @thread_ts@ when the trigger was in a thread.
postMessage ∷ Manager → SlackConfig → Text → Maybe Text → Text → IO ()
postMessage mgr cfg channel threadTs text = do
    let body =
            object $
                ["channel" .= channel, "text" .= text]
                    <> maybe [] (\ts → ["thread_ts" .= ts]) threadTs
    _ ← webPost mgr (scBotToken cfg) "chat.postMessage" body
    pure ()

-- | Split a @wss:\/\/host[:port]\/path?query@ URL into @(host, port, path)@ for 'runSecureClient'.
wssParts ∷ Text → Maybe (String, PortNumber, String)
wssParts url = do
    uri ← parseURI (T.unpack url)
    auth ← uriAuthority uri
    let host = uriRegName auth
        port = case uriPort auth of
            ':' : ds | [(n, "")] ← reads ds → fromInteger n
            _ → 443
        path = case uriPath uri <> uriQuery uri of
            "" → "/"
            p → p
    if null host then Nothing else Just (host, port, path)

-- --- pure event parsing (unit-tested) --------------------------------------------------------------

-- | One inbound Slack message worth answering.
data SlackMessage = SlackMessage
    { smChannel ∷ Text
    , smThreadTs ∷ Maybe Text
    {- ^ Present when the message is in a thread; the reply is threaded under it and the session is
    keyed by it (so a thread is its own conversation).
    -}
    , smText ∷ Text
    }
    deriving stock (Eq, Show)

-- | Session id: per-thread when threaded, else per-channel.
slackSession ∷ SlackMessage → Text
slackSession msg = case smThreadTs msg of
    Just ts → "slack:" <> smChannel msg <> ":" <> ts
    Nothing → "slack:" <> smChannel msg

-- | Whether @user@ may drive the agent: true if no allowlist is configured, else membership.
senderAllowed ∷ Maybe (Set Text) → Text → Bool
senderAllowed Nothing _ = True
senderAllowed (Just set) user = Set.member user set

{- | Parse a Socket-Mode @events_api@ payload into an answerable message, or 'Nothing' to skip it.
Skips non-@message@\/@app_mention@ events, bot\/edited\/system messages, our own messages, and
(when an allowlist is set) non-allowlisted senders. A leading bot @-mention is stripped.
-}
parseEvent ∷ Value → Text → Maybe (Set Text) → Maybe SlackMessage
parseEvent payload botUser allowed = do
    event ← lookKey "event" payload
    etype ← lookStr "type" event
    if etype /= "message" && etype /= "app_mention" then Nothing else Just ()
    -- Skip bot messages and message edits/joins/etc. (subtyped events).
    if lookKey "bot_id" event /= Nothing || lookKey "subtype" event /= Nothing then Nothing else Just ()
    let user = fromMaybe "" (lookStr "user" event)
    if T.null user || user == botUser || not (senderAllowed allowed user) then Nothing else Just ()
    channel ← lookStr "channel" event
    let threadTs = lookStr "thread_ts" event
        -- Strip the bot's own @-mention (`<@BOTID>`) so the agent sees a clean prompt.
        text = T.strip (T.replace ("<@" <> botUser <> ">") "" (fromMaybe "" (lookStr "text" event)))
    if T.null text then Nothing else Just (SlackMessage channel threadTs text)

-- --- tiny JSON helpers -----------------------------------------------------------------------------

lookKey ∷ Text → Value → Maybe Value
lookKey k (Object o) = KM.lookup (K.fromText k) o
lookKey _ _ = Nothing

lookStr ∷ Text → Value → Maybe Text
lookStr k v = case lookKey k v of
    Just (String s) → Just s
    _ → Nothing

lookBool ∷ Text → Value → Maybe Bool
lookBool k v = case lookKey k v of
    Just (Bool b) → Just b
    _ → Nothing

tshow ∷ Show a ⇒ a → Text
tshow = T.pack . show
