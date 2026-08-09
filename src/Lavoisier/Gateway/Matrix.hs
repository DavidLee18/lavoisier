-- | @Lavoisier.Gateway.Matrix@ — a Matrix gateway driving the shared agent. Ports the plaintext core
-- of Rust @lvz-gw-matrix@ (E2EE is layered on separately, over the @olm@ package).
--
-- A hand-rolled REST client (no matrix SDK): authenticate (access token or password), @\/sync@ in a
-- loop, and for each answerable message decide whether to __engage__ — always in a 1:1 DM, in a group
-- room only when @-mentioned or when the message replies to one of the bot's own recent messages —
-- then react 👀, show typing, run the turn, post the reply, and swap the ack for a ✅\/❌ outcome.
-- Sessions are keyed per room. Sender\/room allowlists and per-room\/user tool permissions gate turns.
--
-- The pure decision logic (engagement, message extraction, allowlists, 'RecentIds') is unit-tested;
-- the @\/sync@ loop and REST calls are live-only (need a homeserver). Deferred here: media ingest, the
-- schedule integration, the graceful-shutdown room notice, and the 20s typing keep-alive.
module Lavoisier.Gateway.Matrix
  ( MatrixConfig (..),
    defaultMatrixConfig,
    matrixFromEnv,
    matrixGateway,

    -- * Pure logic (exposed for testing)
    IncomingMessage (..),
    extractMessages,
    mentionsBot,
    replyTarget,
    messageBody,
    messageTriggers,
    senderAllowed,
    roomAllowed,
    toolsFor,
    RecentIds,
    newRecentIds,
    insertRecent,
    containsRecent,
    extractInvites,
    parseNextBatch,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAlphaNum)
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Vector qualified as V
import Lavoisier.Protocol.Agent (AgentHandle (..), TurnRequest (..), turnRequest)
import Lavoisier.Protocol.Event (Event (..))
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (QueryItem, urlEncode)
import Network.HTTP.Types.Status (statusCode, statusIsSuccessful)
import System.Environment (lookupEnv)

syncTimeoutMs :: Int
syncTimeoutMs = 30000

-- | Configuration for the Matrix gateway. Auth precedence: explicit token > persisted > password.
data MatrixConfig = MatrixConfig
  { mcHomeserver :: Text,
    mcUser :: Text,
    mcAccessToken :: Maybe Text,
    mcPassword :: Maybe Text,
    mcDeviceId :: Maybe Text,
    -- | If set, only answer messages whose sender is in this allowlist.
    mcAllowedUsers :: Maybe (Set Text),
    -- | If set, only act in these rooms (conjunction with the sender allowlist).
    mcAllowedRooms :: Maybe (Set Text),
    -- | Per-room tool permission map (a room absent from the map is unconstrained).
    mcRoomTools :: Map Text [Text],
    -- | Per-member tool permission map (intersected with the room's when both apply).
    mcUserTools :: Map Text [Text],
    -- | Auto-accept room invites (@\/join@ each invited room).
    mcAutoJoin :: Bool
  }

-- | A config with only the required fields; everything else off.
defaultMatrixConfig :: Text -> Text -> MatrixConfig
defaultMatrixConfig homeserver user =
  MatrixConfig homeserver user Nothing Nothing Nothing Nothing Nothing Map.empty Map.empty True

-- | Build the config from the @MATRIX_*@ environment (homeserver + user required; token or password
-- for auth; optional device id, allowlists, auto-join).
matrixFromEnv :: IO (Either GatewayError MatrixConfig)
matrixFromEnv = do
  mhs <- lookupEnv "MATRIX_HOMESERVER"
  muser <- lookupEnv "MATRIX_USER"
  tok <- lookupEnv "MATRIX_ACCESS_TOKEN"
  pw <- lookupEnv "MATRIX_PASSWORD"
  dev <- lookupEnv "MATRIX_DEVICE_ID"
  allowedU <- lookupEnv "MATRIX_ALLOWED_USERS"
  allowedR <- lookupEnv "MATRIX_ALLOWED_ROOMS"
  autoJoin <- lookupEnv "MATRIX_NO_AUTO_JOIN"
  pure $ case (mhs, muser) of
    (Nothing, _) -> Left (GEBind "MATRIX_HOMESERVER is not set")
    (_, Nothing) -> Left (GEBind "MATRIX_USER is not set")
    (Just hs, Just user)
      | tok == Nothing && pw == Nothing ->
          Left (GEBind "set MATRIX_ACCESS_TOKEN or MATRIX_PASSWORD")
      | otherwise ->
          Right
            (defaultMatrixConfig (T.pack (dropTrailingSlash hs)) (T.pack user))
              { mcAccessToken = T.pack <$> tok,
                mcPassword = T.pack <$> pw,
                mcDeviceId = T.pack <$> dev,
                mcAllowedUsers = parseSet allowedU,
                mcAllowedRooms = parseSet allowedR,
                mcAutoJoin = autoJoin == Nothing
              }
  where
    dropTrailingSlash = reverse . dropWhile (== '/') . reverse
    parseSet Nothing = Nothing
    parseSet (Just raw) =
      let s = Set.fromList [u | u <- map T.strip (T.splitOn "," (T.pack raw)), not (T.null u)]
       in if Set.null s then Nothing else Just s

-- | The 'Gateway' record backed by a 'MatrixConfig'.
matrixGateway :: MatrixConfig -> Gateway
matrixGateway cfg =
  Gateway
    { gatewayName = "matrix",
      gatewayServe = serveLoop cfg
    }

-- --- runtime environment ---------------------------------------------------------------------------

-- | The resolved session + shared HTTP state used across the serve loop.
data MatrixEnv = MatrixEnv
  { meConfig :: MatrixConfig,
    meManager :: Manager,
    meToken :: Text,
    meUserId :: Text,
    meTxn :: IORef Int
  }

-- --- the serve loop (live-only) --------------------------------------------------------------------

serveLoop :: MatrixConfig -> AgentHandle -> IO (Either GatewayError ())
serveLoop cfg agent = do
  mgr <- newManager tlsManagerSettings
  esess <- resolveSession cfg mgr
  case esess of
    Left e -> pure (Left e)
    Right (token, userId) -> do
      txn <- newIORef (0 :: Int)
      let env = MatrixEnv cfg mgr token userId txn
      recent <- newRecentIds 256
      dmCache <- newIORef Map.empty
      -- Baseline sync: take a `since` and discard the backlog so we only act on new messages
      -- (pending invites are still accepted).
      ebaseline <- syncOnce env Nothing
      case ebaseline of
        Left e -> pure (Left e)
        Right baseline -> do
          autoJoinInvites env baseline
          case parseNextBatch baseline of
            Left e -> pure (Left e)
            Right since0 -> Right <$> loop env recent dmCache since0
  where
    loop env recent dmCache since = do
      eres <- syncOnce env (Just since)
      case eres of
        Left _ -> threadDelay 3000000 >> loop env recent dmCache since -- transient: back off
        Right sync -> do
          autoJoinInvites env sync
          let msgs = extractMessages sync (meUserId env) (mcAllowedUsers cfg) (mcAllowedRooms cfg)
          mapM_ (dispatch env recent dmCache) msgs
          case parseNextBatch sync of
            Right next -> loop env recent dmCache next
            Left _ -> loop env recent dmCache since

    dispatch env recent dmCache msg = do
      dm <- isDm env dmCache (imRoom msg)
      trigger <- messageTriggers dm (imMentions msg) (imReplyTo msg) recent
      if trigger then handleMessage env agent recent msg else pure ()

-- | The full engage → react → run → reply → outcome flow for one message.
handleMessage :: MatrixEnv -> AgentHandle -> RecentIds -> IncomingMessage -> IO ()
handleMessage env agent recent msg = do
  ack <- either (const Nothing) Just <$> react env room (imEventId msg) "👀"
  _ <- setTyping env room True
  let base = turnRequest room (imBody msg)
      turn = base {trAllowedTools = toolsFor (meConfig env) room (imSender msg)}
  est <- submit agent turn
  case est of
    Left _ -> do
      _ <- setTyping env room False
      finishReaction env room (imEventId msg) ack False
    Right stream -> do
      ok <- drain stream ""
      _ <- setTyping env room False
      finishReaction env room (imEventId msg) ack ok
  where
    room = imRoom msg
    drain stream acc =
      nextItem stream >>= \case
        Nothing -> sendAnswer (T.strip acc) >> pure True
        Just (Left _) -> sendAnswer (T.strip acc) >> pure False
        Just (Right ev) -> case ev of
          TextDelta t -> drain stream (acc <> t)
          Notice t -> notice t >> drain stream acc
          ToolUseStart _ name -> notice ("🔧 `" <> name <> "`") >> drain stream acc
          _ -> drain stream acc
    notice t = do
      e <- sendMessage env room t
      either (const (pure ())) (insertRecent recent) e
      _ <- setTyping env room True
      pure ()
    sendAnswer answer
      | T.null answer = pure ()
      | otherwise = do
          e <- sendMessage env room answer
          either (const (pure ())) (insertRecent recent) e

-- | Retract the transient 👀 ack and react ✅\/❌ with the outcome (best-effort).
finishReaction :: MatrixEnv -> Text -> Text -> Maybe Text -> Bool -> IO ()
finishReaction env room eventId ack ok = do
  maybe (pure ()) (\a -> () <$ redact env room a) ack
  _ <- react env room eventId (if ok then "✅" else "❌")
  pure ()

-- --- auth ------------------------------------------------------------------------------------------

-- | Resolve the session (token > password login). Persisted-session reuse is deferred (no state dir
-- persistence yet); a configured token is validated via @whoami@.
resolveSession :: MatrixConfig -> Manager -> IO (Either GatewayError (Text, Text))
resolveSession cfg mgr = case mcAccessToken cfg of
  Just token -> do
    ewho <- whoami cfg mgr token
    pure (fmap (\uid -> (token, uid)) ewho)
  Nothing -> login cfg mgr

whoami :: MatrixConfig -> Manager -> Text -> IO (Either GatewayError Text)
whoami cfg mgr token = do
  r <- httpGet cfg mgr token "/_matrix/client/v3/account/whoami"
  pure $ case r of
    Left e -> Left e
    Right v -> maybe (Left (GEProtocol "whoami missing user_id")) Right (lookStr "user_id" v)

login :: MatrixConfig -> Manager -> IO (Either GatewayError (Text, Text))
login cfg mgr = case mcPassword cfg of
  Nothing -> pure (Left (GEBind "no MATRIX_PASSWORD set and no usable access token"))
  Just pw -> do
    let body =
          object $
            [ "type" .= ("m.login.password" :: Text),
              "identifier" .= object ["type" .= ("m.id.user" :: Text), "user" .= mcUser cfg],
              "password" .= pw
            ]
              <> maybe [] (\d -> ["device_id" .= d]) (mcDeviceId cfg)
    r <- httpSend cfg mgr Nothing "POST" "/_matrix/client/v3/login" (Just body)
    pure $ case r of
      Left e -> Left e
      Right v -> case (lookStr "access_token" v, lookStr "user_id" v) of
        (Just tok, Just uid) -> Right (tok, uid)
        _ -> Left (GEProtocol "login response missing access_token/user_id")

-- --- REST helpers ----------------------------------------------------------------------------------

syncOnce :: MatrixEnv -> Maybe Text -> IO (Either GatewayError Value)
syncOnce env since = do
  let q =
        ("timeout", Just (encodeUtf8 (T.pack (show syncTimeoutMs))))
          : maybe [] (\s -> [("since", Just (encodeUtf8 s))]) since
  r <- httpGetQuery (meConfig env) (meManager env) (meToken env) "/_matrix/client/v3/sync" q
  pure (either (Left . toIo) Right r)
  where
    toIo (GEProtocol m) = GEIo m -- a sync decode failure is treated as transient
    toIo e = e

sendMessage :: MatrixEnv -> Text -> Text -> IO (Either GatewayError Text)
sendMessage env room body = do
  n <- nextTxn env
  let path = "/_matrix/client/v3/rooms/" <> enc room <> "/send/m.room.message/lvz" <> T.pack (show n)
      payload = object ["msgtype" .= ("m.text" :: Text), "body" .= body]
  r <- httpSend (meConfig env) (meManager env) (Just (meToken env)) "PUT" path (Just payload)
  pure (r >>= \v -> maybe (Left (GEProtocol "send missing event_id")) Right (lookStr "event_id" v))

react :: MatrixEnv -> Text -> Text -> Text -> IO (Either GatewayError Text)
react env room eventId emoji = do
  n <- nextTxn env
  let path = "/_matrix/client/v3/rooms/" <> enc room <> "/send/m.reaction/lvz" <> T.pack (show n)
      payload =
        object
          [ "m.relates_to"
              .= object ["rel_type" .= ("m.annotation" :: Text), "event_id" .= eventId, "key" .= emoji]
          ]
  r <- httpSend (meConfig env) (meManager env) (Just (meToken env)) "PUT" path (Just payload)
  pure (r >>= \v -> maybe (Left (GEProtocol "react missing event_id")) Right (lookStr "event_id" v))

redact :: MatrixEnv -> Text -> Text -> IO (Either GatewayError ())
redact env room eventId = do
  n <- nextTxn env
  let path = "/_matrix/client/v3/rooms/" <> enc room <> "/redact/" <> enc eventId <> "/lvz" <> T.pack (show n)
  fmap (const ()) <$> httpSend (meConfig env) (meManager env) (Just (meToken env)) "PUT" path (Just (object []))

setTyping :: MatrixEnv -> Text -> Bool -> IO (Either GatewayError ())
setTyping env room typing = do
  let path = "/_matrix/client/v3/rooms/" <> enc room <> "/typing/" <> enc (meUserId env)
      payload = object ["typing" .= typing, "timeout" .= (30000 :: Int)]
  fmap (const ()) <$> httpSend (meConfig env) (meManager env) (Just (meToken env)) "PUT" path (Just payload)

-- | Whether a room is a 1:1 DM (exactly two joined members), cached per room.
isDm :: MatrixEnv -> IORef (Map Text Bool) -> Text -> IO Bool
isDm env cacheRef room = do
  cache <- readIORef cacheRef
  case Map.lookup room cache of
    Just b -> pure b
    Nothing -> do
      n <- joinedMemberCount env room
      let dm = n == 2
      modifyIORef' cacheRef (Map.insert room dm)
      pure dm

joinedMemberCount :: MatrixEnv -> Text -> IO Int
joinedMemberCount env room = do
  let path = "/_matrix/client/v3/rooms/" <> enc room <> "/joined_members"
  r <- httpGet (meConfig env) (meManager env) (meToken env) path
  pure $ case r of
    Right v -> case lookKey "joined" v of
      Just (Object o) -> KM.size o
      _ -> 0
    Left _ -> 0

-- | Accept any pending room invites in a sync response (@\/join@ each), when auto-join is on.
autoJoinInvites :: MatrixEnv -> Value -> IO ()
autoJoinInvites env sync
  | not (mcAutoJoin (meConfig env)) = pure ()
  | otherwise = mapM_ joinRoom (extractInvites sync)
  where
    joinRoom room = do
      _ <- httpSend (meConfig env) (meManager env) (Just (meToken env)) "POST" ("/_matrix/client/v3/join/" <> enc room) (Just (object []))
      pure ()

nextTxn :: MatrixEnv -> IO Int
nextTxn env = atomicModifyIORef' (meTxn env) (\n -> (n + 1, n))

enc :: Text -> Text
enc = decodeUtf8Lenient . urlEncode True . encodeUtf8

-- --- HTTP plumbing ---------------------------------------------------------------------------------

httpGet :: MatrixConfig -> Manager -> Text -> Text -> IO (Either GatewayError Value)
httpGet cfg mgr token path = httpGetQuery cfg mgr token path []

httpGetQuery :: MatrixConfig -> Manager -> Text -> Text -> [QueryItem] -> IO (Either GatewayError Value)
httpGetQuery cfg mgr token path q = do
  er <- try (parseRequest (T.unpack (mcHomeserver cfg <> path))) :: IO (Either SomeException Request)
  case er of
    Left e -> pure (Left (GEIo (tshow e)))
    Right req0 ->
      runReq mgr $
        setQueryString q req0 {method = "GET", requestHeaders = [("Authorization", "Bearer " <> encodeUtf8 token)]}

httpSend :: MatrixConfig -> Manager -> Maybe Text -> BL.ByteString -> Text -> Maybe Value -> IO (Either GatewayError Value)
httpSend cfg mgr mtoken httpMethod path mbody = do
  er <- try (parseRequest (T.unpack (mcHomeserver cfg <> path))) :: IO (Either SomeException Request)
  case er of
    Left e -> pure (Left (GEIo (tshow e)))
    Right req0 ->
      let hdrs =
            maybe [] (\t -> [("Authorization", "Bearer " <> encodeUtf8 t)]) mtoken
              <> maybe [] (const [("Content-Type", "application/json")]) mbody
       in runReq
            mgr
            req0
              { method = BL.toStrict httpMethod,
                requestHeaders = hdrs,
                requestBody = RequestBodyLBS (maybe "{}" encode mbody)
              }

runReq :: Manager -> Request -> IO (Either GatewayError Value)
runReq mgr req = do
  eresp <- try (httpLbs req mgr) :: IO (Either HttpException (Response BL.ByteString))
  pure $ case eresp of
    Left e -> Left (GEIo (tshow e))
    Right resp
      | statusIsSuccessful (responseStatus resp) ->
          maybe (Right Null) Right (decode (responseBody resp))
      | otherwise ->
          Left (classifyStatus (statusCode (responseStatus resp)) (decodeUtf8Lenient (BL.toStrict (responseBody resp))))

-- | Classify an HTTP failure: 4xx (except 429) is fatal config\/auth ('GEBind'); 429\/5xx\/other is
-- transient ('GEIo', retried by the loop).
classifyStatus :: Int -> Text -> GatewayError
classifyStatus code msg
  | code == 429 || code >= 500 = GEIo msg
  | code >= 400 = GEBind msg
  | otherwise = GEIo msg

-- --- pure logic (unit-tested) ----------------------------------------------------------------------

-- | One answerable inbound message plus the signals the serve loop needs to decide engagement.
data IncomingMessage = IncomingMessage
  { imRoom :: Text,
    imSender :: Text,
    imBody :: Text,
    imEventId :: Text,
    imMentions :: Bool,
    imReplyTo :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | Pull the answerable @m.room.message@ events out of a sync response, skipping the bot's own
-- messages and senders\/rooms outside any configured allowlist, and attaching the mention\/reply
-- signals.
extractMessages :: Value -> Text -> Maybe (Set Text) -> Maybe (Set Text) -> [IncomingMessage]
extractMessages sync self allowedUsers allowedRooms =
  [ IncomingMessage roomId sender body eid (mentionsBot content self) (replyTarget content)
  | (roomId, room) <- objToList (lookKey "rooms" sync >>= lookKey "join"),
    roomAllowed allowedRooms roomId,
    event <- arrGet "events" (fromMaybe Null (lookKey "timeline" room)),
    lookStr "type" event == Just "m.room.message",
    let sender = fromMaybe "" (lookStr "sender" event),
    sender /= self,
    senderAllowed allowedUsers sender,
    let content = fromMaybe Null (lookKey "content" event),
    Just body <- [messageBody content],
    let eid = fromMaybe "" (lookStr "event_id" event)
  ]

-- | Whether a message's content @-mentions the bot: the authoritative @m.mentions@ list (MSC3952),
-- or a textual fallback (the full MXID or @\@localpart@ as a token in the plain\/formatted body).
mentionsBot :: Value -> Text -> Bool
mentionsBot content self = explicit || textual
  where
    explicit = case lookKey "m.mentions" content >>= lookKey "user_ids" of
      Just (Array a) -> self `elem` mapMaybe asText (V.toList a)
      _ -> False
    handle = case T.stripPrefix "@" self of
      Just rest -> let l = T.takeWhile (/= ':') rest in if T.null l then Nothing else Just ("@" <> l)
      Nothing -> Nothing
    texts = mapMaybe (`lookStr` content) ["body", "formatted_body"]
    textual = any (any hasTok . tokenize) texts
    hasTok tok = tok == self || Just tok == handle
    tokenize = T.split (\c -> not (isAlphaNum c || c `elem` ("@:_.-" :: String)))

-- | The event id a message replies to (@m.relates_to@ → @m.in_reply_to@), if any.
replyTarget :: Value -> Maybe Text
replyTarget content =
  case lookKey "m.relates_to" content >>= lookKey "m.in_reply_to" >>= lookStr "event_id" of
    Just e | not (T.null e) -> Just e
    _ -> Nothing

-- | The answerable body of a message: an @m.text@ yields its body; other message types are ignored
-- (media ingest is deferred).
messageBody :: Value -> Maybe Text
messageBody content = case lookStr "msgtype" content of
  Just "m.text" -> lookStr "body" content
  _ -> Nothing

-- | Decide whether to engage: always in a 1:1 DM; in a group room only when @-mentioned or when the
-- message replies to one of the bot's own recent messages.
messageTriggers :: Bool -> Bool -> Maybe Text -> RecentIds -> IO Bool
messageTriggers isDmRoom mentions replyTo recent
  | isDmRoom = pure True
  | mentions = pure True
  | otherwise = maybe (pure False) (containsRecent recent) replyTo

-- | Whether @sender@ may drive the agent (no allowlist ⇒ everyone).
senderAllowed :: Maybe (Set Text) -> Text -> Bool
senderAllowed Nothing _ = True
senderAllowed (Just s) u = Set.member u s

-- | Whether the bot may act in @room@ (no allowlist ⇒ everywhere).
roomAllowed :: Maybe (Set Text) -> Text -> Bool
roomAllowed Nothing _ = True
roomAllowed (Just s) r = Set.member r s

-- | The tool allowlist for a turn: the room's permissions ∩ the member's (a party absent from its
-- map is unconstrained; 'Nothing' ⇒ no restriction).
toolsFor :: MatrixConfig -> Text -> Text -> Maybe [Text]
toolsFor cfg room sender =
  case (Map.lookup room (mcRoomTools cfg), Map.lookup sender (mcUserTools cfg)) of
    (Nothing, Nothing) -> Nothing
    (Just r, Nothing) -> Just r
    (Nothing, Just u) -> Just u
    (Just r, Just u) -> Just (filter (`elem` u) r)

-- | The invited room ids in a sync response.
extractInvites :: Value -> [Text]
extractInvites sync = map fst (objToList (lookKey "rooms" sync >>= lookKey "invite"))

-- | The @next_batch@ sync token (or a protocol error if absent).
parseNextBatch :: Value -> Either GatewayError Text
parseNextBatch sync = maybe (Left (GEProtocol "sync response missing next_batch")) Right (lookStr "next_batch" sync)

-- --- RecentIds (bounded set of the bot's own recent event ids) -------------------------------------

-- | A bounded FIFO of the bot's own recent message event ids, so a reply to one re-engages it.
newtype RecentIds = RecentIds (IORef ([Text], Int))

-- | A fresh 'RecentIds' holding at most @cap@ ids.
newRecentIds :: Int -> IO RecentIds
newRecentIds cap = RecentIds <$> newIORef ([], cap)

-- | Record an id (evicting the oldest past the cap).
insertRecent :: RecentIds -> Text -> IO ()
insertRecent (RecentIds ref) x = modifyIORef' ref (\(xs, c) -> (take c (x : filter (/= x) xs), c))

-- | Whether an id is in the recent set.
containsRecent :: RecentIds -> Text -> IO Bool
containsRecent (RecentIds ref) x = do
  (xs, _) <- readIORef ref
  pure (x `elem` xs)

-- --- tiny JSON helpers -----------------------------------------------------------------------------

lookKey :: Text -> Value -> Maybe Value
lookKey k (Object o) = KM.lookup (K.fromText k) o
lookKey _ _ = Nothing

lookStr :: Text -> Value -> Maybe Text
lookStr k v = lookKey k v >>= asText

asText :: Value -> Maybe Text
asText (String s) = Just s
asText _ = Nothing

arrGet :: Text -> Value -> [Value]
arrGet k v = case lookKey k v of
  Just (Array a) -> V.toList a
  _ -> []

objToList :: Maybe Value -> [(Text, Value)]
objToList (Just (Object o)) = [(K.toText k, v) | (k, v) <- KM.toList o]
objToList _ = []

tshow :: (Show a) => a -> Text
tshow = T.pack . show
