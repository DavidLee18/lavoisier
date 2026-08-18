{-# LANGUAGE CPP #-}

-- | @Lavoisier.Gateway.Matrix@ — a Matrix gateway driving the shared agent. Ports the plaintext core
-- of Rust @lvz-gw-matrix@; under the @e2ee@ cabal flag (@-DE2EE@) the serve loop also drives Matrix
-- end-to-end encryption over "Lavoisier.Gateway.Matrix.E2ee" (the @olm@ package): it publishes signed
-- device\/one-time keys, receives Megolm room keys via to-device Olm messages, decrypts inbound
-- @m.room.encrypted@ timeline events, and Megolm-encrypts replies in encrypted rooms.
--
-- A hand-rolled REST client (no matrix SDK): authenticate (access token or password), @\/sync@ in a
-- loop, and for each answerable message decide whether to __engage__ — always in a 1:1 DM, in a group
-- room only when @-mentioned or when the message replies to one of the bot's own recent messages —
-- then react 👀, show typing, run the turn, post the reply, and swap the ack for a ✅\/❌ outcome.
-- Sessions are keyed per room. Sender\/room allowlists and per-room\/user tool permissions gate turns.
--
-- The pure decision logic (engagement, message extraction, allowlists, 'RecentIds') is unit-tested;
-- the @\/sync@ loop and REST calls are live-only (need a homeserver). Media ingest, the in-gateway
-- schedule ('ScheduleCtx'), the graceful-shutdown room notice, and the 20s typing keep-alive are all
-- wired in.
module Lavoisier.Gateway.Matrix
  ( MatrixConfig (..),
    defaultMatrixConfig,
    matrixFromEnv,
    matrixGateway,
    matrixScheduleGateway,
    ScheduleCtx (..),
    Language (..),
    languageFromLocale,
    withLanguage,

    -- * Pure logic (exposed for testing)
    IncomingMessage (..),
    Attachment (..),
    extractMessages,
    mentionsBot,
    replyTarget,
    messageContent,
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
import Control.Concurrent.Async (race, withAsync)
import Control.Concurrent.MVar (MVar, newEmptyMVar, takeMVar, tryPutMVar)
import Control.Exception (SomeException, try)
import Control.Monad (forever)
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
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Vector qualified as V
import Lavoisier.Protocol.Agent (AgentHandle (..), TurnRequest (..), TurnStream, turnRequest)
import Lavoisier.Protocol.Event (Event (..))
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Protocol.Tool (ToolError, ToolOutput, toContent, toIsError)
import Lavoisier.Schedule (Action (..), ScheduleJob (..), ScheduleRegistry, dueJobs, recordOutcome, registryJobs, takeRequested)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (QueryItem, urlEncode)
import Network.HTTP.Types.Status (statusCode, statusIsSuccessful)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)
import System.Posix.Signals (Handler (Catch), installHandler, sigINT, sigTERM)
#ifdef E2EE
import Control.Monad (forM_, unless)
import Data.Scientific (toBoundedInteger)
import Lavoisier.Gateway.Matrix.E2ee qualified as E2
#endif

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
    mcAutoJoin :: Bool,
    -- | Directory persisting @session.json@ (token + device id, so the device id is stable across
    -- restarts) and, under @e2ee@, the pickled crypto store. Unset ⇒ in-memory only.
    mcStateDir :: Maybe FilePath,
    -- | Optional at-rest passphrase for the pickled crypto store (@MATRIX_CRYPTO_STORE_KEY@).
    mcCryptoStoreKey :: Maybe Text,
    -- | Room to greet with a friendly "going offline" notice on shutdown (@MATRIX_HOME_ROOM@).
    mcHomeRoom :: Maybe Text,
    -- | If set, download inbound image\/file attachments here and hand the local path to the turn.
    mcMediaDir :: Maybe FilePath,
    -- | Language for gateway-authored notices (only the shutdown message; default 'English').
    mcLanguage :: Language
  }

-- | UI language for notices this gateway authors itself — currently just the graceful-shutdown
-- notice. Inbound turns and the agent's replies are unaffected. Mirrors @lvz_gw_matrix::Language@.
data Language = English | Korean
  deriving stock (Eq, Show)

-- | Resolve a POSIX locale to a 'Language': only @ko_KR@ (case-insensitive, any @.encoding@ suffix
-- ignored) selects Korean; everything else is English.
languageFromLocale :: Text -> Language
languageFromLocale raw =
  if T.toUpper (T.takeWhile (/= '.') raw) == "KO_KR" then Korean else English

-- | Set the language for gateway-authored notices.
withLanguage :: Language -> MatrixConfig -> MatrixConfig
withLanguage lang cfg = cfg {mcLanguage = lang}

-- | A config with only the required fields; everything else off.
defaultMatrixConfig :: Text -> Text -> MatrixConfig
defaultMatrixConfig homeserver user =
  MatrixConfig homeserver user Nothing Nothing Nothing Nothing Nothing Map.empty Map.empty True Nothing Nothing Nothing Nothing English

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
  stateDir <- lookupEnv "MATRIX_STATE_DIR"
  cryptoKey <- lookupEnv "MATRIX_CRYPTO_STORE_KEY"
  homeRoom <- lookupEnv "MATRIX_HOME_ROOM"
  mediaDir <- lookupEnv "MATRIX_MEDIA_DIR"
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
                mcAutoJoin = autoJoin == Nothing,
                mcStateDir = stateDir,
                mcCryptoStoreKey = T.pack <$> cryptoKey,
                mcHomeRoom = T.pack <$> homeRoom,
                mcMediaDir = mediaDir
              }
  where
    dropTrailingSlash = reverse . dropWhile (== '/') . reverse
    parseSet Nothing = Nothing
    parseSet (Just raw) =
      let s = Set.fromList [u | u <- map T.strip (T.splitOn "," (T.pack raw)), not (T.null u)]
       in if Set.null s then Nothing else Just s

-- | The 'Gateway' record backed by a 'MatrixConfig' (no in-gateway schedule).
matrixGateway :: MatrixConfig -> Gateway
matrixGateway cfg =
  Gateway
    { gatewayName = "matrix",
      gatewayServe = serveLoop cfg Nothing
    }

-- | The Matrix gateway with an in-gateway schedule: its jobs fire inside the serve loop and report
-- their outcomes to a room. The @schedule_*@ tools query\/re-run it via the shared registry.
matrixScheduleGateway :: MatrixConfig -> ScheduleCtx -> Gateway
matrixScheduleGateway cfg ctx =
  Gateway
    { gatewayName = "matrix",
      gatewayServe = serveLoop cfg (Just ctx)
    }

-- | What the Matrix gateway needs to fire scheduled jobs: the live 'ScheduleRegistry' and a direct
-- tool invoker (the shared 'Lavoisier.Tool.Registry.ToolRegistry', so an 'Action' tool call runs
-- deterministically with no model round-trip).
data ScheduleCtx = ScheduleCtx
  { scRegistry :: ScheduleRegistry,
    scInvoke :: Text -> Value -> IO (Either ToolError ToolOutput)
  }

-- --- runtime environment ---------------------------------------------------------------------------

#ifdef E2EE

-- | The resolved session + shared HTTP state used across the serve loop (with E2EE state under
-- @-DE2EE@: the crypto identity + per-room key-sharing\/encryption caches).
data MatrixEnv = MatrixEnv
  { meConfig :: MatrixConfig,
    meManager :: Manager,
    meToken :: Text,
    meUserId :: Text,
    meTxn :: IORef Int,
    meE2 :: E2State
  }

-- | The serve loop's E2EE state: the bot 'E2.Crypto', the set of @(room, user, device)@ triples the
-- current Megolm session was already shared with (so a room key is only sent once), and a per-room
-- encrypted-or-not cache (from @m.room.encryption@ state).
data E2State = E2State
  { esCrypto :: E2.Crypto,
    esShared :: IORef (Set (Text, Text, Text)),
    esEnc :: IORef (Map Text Bool),
    -- | Set when the crypto state changed (a room key received, a session created), so the loop
    -- re-persists the pickled store; cleared after a successful write.
    esDirty :: IORef Bool
  }

#else

-- | The resolved session + shared HTTP state used across the serve loop.
data MatrixEnv = MatrixEnv
  { meConfig :: MatrixConfig,
    meManager :: Manager,
    meToken :: Text,
    meUserId :: Text,
    meTxn :: IORef Int
  }

#endif

-- --- the serve loop (live-only) --------------------------------------------------------------------

serveLoop :: MatrixConfig -> Maybe ScheduleCtx -> AgentHandle -> IO (Either GatewayError ())
serveLoop cfg mctx agent = do
  mgr <- newManager tlsManagerSettings
  esess <- resolveSession cfg mgr
  case esess of
    Left e -> pure (Left e)
    Right (token, userId, deviceId) -> do
      txn <- newIORef (0 :: Int)
      env <- mkEnv cfg mgr token userId deviceId txn
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
            Right since0 -> do
              -- Race the sync loop against a shutdown signal: on SIGTERM/SIGINT, post a friendly
              -- "going offline" notice to the home room, persist the crypto store, and exit cleanly.
              shutdown <- newEmptyMVar
              installShutdown shutdown
              outcome <- race (takeMVar shutdown) (loop env recent dmCache since0)
              case outcome of
                Left () -> onShutdown env >> pure (Right ())
                Right () -> pure (Right ())
  where
    loop env recent dmCache since = do
      eres <- syncOnce env (Just since)
      case eres of
        Left _ -> threadDelay 3000000 >> loop env recent dmCache since -- transient: back off
        Right sync -> do
          autoJoinInvites env sync
          syncD <- decryptedSync env sync
          let msgs = extractMessages syncD (meUserId env) (mcAllowedUsers cfg) (mcAllowedRooms cfg)
          mapM_ (dispatch env recent dmCache) msgs
          persistIfDirty env
          maybe (pure ()) (fireDueSchedule env agent recent) mctx
          case parseNextBatch sync of
            Right next -> loop env recent dmCache next
            Left _ -> loop env recent dmCache since

    dispatch env recent dmCache msg = do
      dm <- isDm env dmCache (imRoom msg)
      trigger <- messageTriggers dm (imMentions msg) (imReplyTo msg) recent
      if trigger then handleMessage env agent recent msg else pure ()

-- | Install SIGTERM\/SIGINT handlers that unblock the serve loop's shutdown race (idempotent fire).
installShutdown :: MVar () -> IO ()
installShutdown v = do
  let fire = tryPutMVar v () >> pure ()
  _ <- installHandler sigTERM (Catch fire) Nothing
  _ <- installHandler sigINT (Catch fire) Nothing
  pure ()

-- | On shutdown: post the "going offline" notice to the home room (encrypted when the room is, via
-- 'sendText') and flush the crypto store.
onShutdown :: MatrixEnv -> IO ()
onShutdown env = do
  case mcHomeRoom (meConfig env) of
    Just room -> () <$ sendText env room (shutdownNotice (mcLanguage (meConfig env)))
    Nothing -> pure ()
  persistIfDirty env

-- | The friendly "going offline" notice, localised ('English' default, 'Korean' when @--lang@\/@LANG@
-- resolves to @ko_KR@). "Lavoisier" is kept as a name.
shutdownNotice :: Language -> Text
shutdownNotice English = "👋 Lavoisier is going offline for a bit — thanks for chatting, and see you soon!"
shutdownNotice Korean = "👋 Lavoisier가 잠시 오프라인 상태가 됩니다 — 대화 감사했어요, 곧 다시 만나요!"

-- | The full engage → react → run → reply → outcome flow for one message.
handleMessage :: MatrixEnv -> AgentHandle -> RecentIds -> IncomingMessage -> IO ()
handleMessage env agent recent msg = do
  ack <- either (const Nothing) Just <$> react env room (imEventId msg) "👀"
  _ <- setTyping env room True
  turnText <- augmentWithMedia env msg
  let base = turnRequest room turnText
      turn = base {trAllowedTools = toolsFor (meConfig env) room (imSender msg)}
  est <- submit agent turn
  case est of
    Left _ -> do
      _ <- setTyping env room False
      finishReaction env room (imEventId msg) ack False
    Right stream -> do
      -- Keep the typing indicator alive through a long, silent turn (e.g. a legion deliberation that
      -- emits no events for 60 s+): the homeserver's typing timeout is 30 s, so refresh every 20 s.
      ok <- withAsync (typingKeepAlive env room) (const (drain stream ""))
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
      e <- sendText env room t
      either (const (pure ())) (insertRecent recent) e
      _ <- setTyping env room True
      pure ()
    sendAnswer answer
      | T.null answer = pure ()
      | otherwise = do
          e <- sendText env room answer
          either (const (pure ())) (insertRecent recent) e

-- | When a media dir is configured and the message carries a plaintext attachment, download it and
-- append an @[attachment] …saved locally at \<path\>@ line to the turn text so a tool can act on the
-- local file. The model never sees the bytes — only the path (the bytes-to-tool path).
augmentWithMedia :: MatrixEnv -> IncomingMessage -> IO Text
augmentWithMedia env msg = case (mcMediaDir (meConfig env), imAttachment msg) of
  (Just dir, Just att) -> do
    saved <- downloadMedia env dir (imEventId msg) att
    pure $ case saved of
      Right path -> imBody msg <> "\n[attachment] " <> atFilename att <> " (" <> atMime att <> ") saved locally at " <> T.pack path
      Left _ -> imBody msg
  _ -> pure (imBody msg)

-- | Download an @mxc://server/mediaId@ via the authenticated media endpoint (Matrix 1.11+) to
-- @\<dir\>/\<eventId\>_\<filename\>@ (both sanitised so nothing escapes the dir).
downloadMedia :: MatrixEnv -> FilePath -> Text -> Attachment -> IO (Either GatewayError FilePath)
downloadMedia env dir eventId att = case parseMxc (atMxc att) of
  Nothing -> pure (Left (GEProtocol "bad mxc url"))
  Just (server, mediaId) -> do
    let path = dir </> (sanitizeComponent eventId <> "_" <> sanitizeComponent (atFilename att))
        url = "/_matrix/client/v1/media/download/" <> enc server <> "/" <> enc mediaId
    r <-
      try
        ( do
            createDirectoryIfMissing True dir
            req0 <- parseRequest (T.unpack (mcHomeserver (meConfig env) <> url))
            resp <- httpLbs req0 {requestHeaders = [("Authorization", "Bearer " <> encodeUtf8 (meToken env))]} (meManager env)
            if statusIsSuccessful (responseStatus resp)
              then BL.writeFile path (responseBody resp) >> pure path
              else ioError (userError ("media download status " <> show (statusCode (responseStatus resp))))
        ) ::
        IO (Either SomeException FilePath)
    pure (either (Left . GEIo . tshow) Right r)

-- | Parse @mxc://server/mediaId@ into @(server, mediaId)@.
parseMxc :: Text -> Maybe (Text, Text)
parseMxc t = case T.stripPrefix "mxc://" t of
  Just rest -> case T.breakOn "/" rest of
    (server, p) | not (T.null server), T.length p > 1 -> Just (server, T.drop 1 p)
    _ -> Nothing
  Nothing -> Nothing

-- | Reduce a path component to @[A-Za-z0-9._-]@ so a filename\/event id can never escape the media dir.
sanitizeComponent :: Text -> FilePath
sanitizeComponent = T.unpack . T.map (\c -> if isAlphaNum c || c `elem` ("._-" :: String) then c else '_')

-- | Refresh the typing indicator every 20 s until cancelled (the homeserver times it out at 30 s).
typingKeepAlive :: MatrixEnv -> Text -> IO ()
typingKeepAlive env room = forever (threadDelay 20000000 >> setTyping env room True)

-- | Retract the transient 👀 ack and react ✅\/❌ with the outcome (best-effort).
finishReaction :: MatrixEnv -> Text -> Text -> Maybe Text -> Bool -> IO ()
finishReaction env room eventId ack ok = do
  maybe (pure ()) (\a -> () <$ redact env room a) ack
  _ <- react env room eventId (if ok then "✅" else "❌")
  pure ()

-- --- in-gateway schedule (jobs fire inside the serve loop, report to a room) -----------------------

nowUnix :: IO Integer
nowUnix = round <$> getPOSIXTime

-- | Fire every due-or-manually-requested schedule job once (registration order, deduped), recording
-- each outcome and posting a report to its room. Runs single-threaded inside the serve loop so it
-- shares the (non-thread-safe) crypto state, exactly as the sync\/message handling does.
fireDueSchedule :: MatrixEnv -> AgentHandle -> RecentIds -> ScheduleCtx -> IO ()
fireDueSchedule env agent recent ctx = do
  now <- nowUnix
  manual <- takeRequested (scRegistry ctx)
  due <- dueJobs (scRegistry ctx) now
  let jobs = registryJobs (scRegistry ctx)
  mapM_ (\i -> case drop i jobs of (job : _) -> fireScheduleJob env agent recent ctx job now; [] -> pure ()) (dedup (manual <> due))
  where
    dedup = go []
      where
        go seen [] = reverse seen
        go seen (x : xs) = if x `elem` seen then go seen xs else go (x : seen) xs

-- | Run one job's action, record the verdict (the action's — untouched by summarisation), and post a
-- report: a __failure__ goes to the room verbatim (its retry countdown must be visible); a __success__
-- may be rewritten as prose by a tool-less @summarize@ turn (degrading to the raw output on failure).
fireScheduleJob :: MatrixEnv -> AgentHandle -> RecentIds -> ScheduleCtx -> ScheduleJob -> Integer -> IO ()
fireScheduleJob env agent recent ctx job now = do
  result <- runScheduleAction agent ctx job
  recordOutcome (scRegistry ctx) now job result
  body <- case (result, sjSummarize job) of
    (Right raw, Just instr) -> summariseForRoom agent job instr raw
    _ -> pure (either id id result)
  -- Untruncated operator log to stderr per fire (every frontend gets it).
  hPutStrLn stderr (T.unpack ("[schedule] " <> sjId job <> " " <> either (const "FAIL") (const "ok") result <> ": " <> either id id result))
  let marker = either (const ("\10060" :: Text)) (const "\9989") result
      report = "\9200 schedule `" <> sjId job <> "` " <> marker <> "\n" <> body
  case sjRoom job of
    Just room -> sendText env room report >>= either (const (pure ())) (insertRecent recent)
    Nothing -> pure ()

-- | A job's action → @Either failureDetail successOutput@. A tool @isError@ or a rejected\/errored
-- turn is a failure (drives retry); a completed turn or a clean tool result is a success.
runScheduleAction :: AgentHandle -> ScheduleCtx -> ScheduleJob -> IO (Either Text Text)
runScheduleAction agent ctx job = case sjAction job of
  ActTool name args -> do
    r <- scInvoke ctx name args
    pure $ case r of
      Left e -> Left (tshow e)
      Right out
        | toIsError out -> Left (toContent out)
        | otherwise -> Right (toContent out)
  ActPrompt p ->
    submit agent (turnRequest (sjSession job) p) >>= \case
      Left e -> pure (Left (tshow e))
      Right stream -> drainScheduleTurn stream

-- | Rewrite a successful tool result as room prose with a __tool-less__ turn (empty @allowed_tools@,
-- so the model can only write text, never act). Best-effort: any failure degrades to the raw output.
summariseForRoom :: AgentHandle -> ScheduleJob -> Text -> Text -> IO Text
summariseForRoom agent job instr raw = do
  let tr = (turnRequest (sjSession job) (instr <> "\n\n" <> raw)) {trAllowedTools = Just []}
  submit agent tr >>= \case
    Left _ -> pure raw
    Right stream -> either (const raw) id <$> drainScheduleTurn stream

-- | Fold a turn's stream to its answer text (or a Left on a mid-stream error).
drainScheduleTurn :: TurnStream -> IO (Either Text Text)
drainScheduleTurn stream = go ""
  where
    go acc =
      nextItem stream >>= \case
        Nothing -> pure (Right (T.strip acc))
        Just (Left _) -> pure (Left "turn stream error")
        Just (Right (TextDelta t)) -> go (acc <> t)
        Just (Right _) -> go acc

-- --- E2EE serve-loop wiring (only under -DE2EE) ----------------------------------------------------

#ifdef E2EE

-- | Build the serve env and, under E2EE, restore the crypto identity from the durable store (else
-- create a fresh one, publish its keys, and seed the store).
mkEnv :: MatrixConfig -> Manager -> Text -> Text -> Text -> IORef Int -> IO MatrixEnv
mkEnv cfg mgr token userId deviceId txn = do
  loaded <- loadCrypto cfg userId deviceId
  (c, fresh) <- case loaded of
    Just c -> pure (c, False)
    Nothing -> (,True) <$> E2.newCrypto userId deviceId
  shared <- newIORef Set.empty
  encc <- newIORef Map.empty
  dirty <- newIORef False
  let e2 = E2State c shared encc dirty
      env = MatrixEnv cfg mgr token userId txn e2
  -- A fresh identity publishes its keys and seeds the store; a restored one is already published.
  if fresh
    then do
      _ <- E2.publishKeys c (restAdapter cfg mgr token) -- best-effort
      persistCrypto env
    else pure ()
  pure env

-- | Restore the pickled 'E2.Crypto' from @\<stateDir\>/crypto.json@ (under the configured passphrase),
-- if a state dir is set and the file is present and readable.
loadCrypto :: MatrixConfig -> Text -> Text -> IO (Maybe E2.Crypto)
loadCrypto cfg userId deviceId = case mcStateDir cfg of
  Nothing -> pure Nothing
  Just dir -> do
    let path = dir </> "crypto.json"
    ok <- doesFileExist path
    if not ok
      then pure Nothing
      else do
        r <- try (BL.readFile path) :: IO (Either SomeException BL.ByteString)
        case r of
          Left _ -> pure Nothing
          Right bytes -> case decode bytes of
            Nothing -> pure Nothing
            Just v -> E2.unpickleStore userId deviceId (cryptoPassphrase cfg) v

-- | Persist the crypto store to @\<stateDir\>/crypto.json@ (best-effort) and clear the dirty flag.
persistCrypto :: MatrixEnv -> IO ()
persistCrypto env = case mcStateDir (meConfig env) of
  Nothing -> pure ()
  Just dir -> do
    v <- E2.pickleStore (esCrypto (meE2 env)) (cryptoPassphrase (meConfig env))
    _ <- try (createDirectoryIfMissing True dir) :: IO (Either SomeException ())
    _ <- try (BL.writeFile (dir </> "crypto.json") (encode v)) :: IO (Either SomeException ())
    writeIORef (esDirty (meE2 env)) False

-- | Re-persist the crypto store only if it changed since the last write.
persistIfDirty :: MatrixEnv -> IO ()
persistIfDirty env = do
  dirty <- readIORef (esDirty (meE2 env))
  if dirty then persistCrypto env else pure ()

cryptoPassphrase :: MatrixConfig -> Text
cryptoPassphrase = fromMaybe "" . mcCryptoStoreKey

-- | Adapt the gateway's HTTP client to the E2ee module's abstract 'E2.Rest' hook.
restAdapter :: MatrixConfig -> Manager -> Text -> E2.Rest
restAdapter cfg mgr token httpMethod path body =
  either (Left . geText) Right <$> httpSend cfg mgr (Just token) (BL.fromStrict (encodeUtf8 httpMethod)) path (Just body)

geText :: GatewayError -> Text
geText (GEIo m) = m
geText (GEBind m) = m
geText (GEProtocol m) = m

-- | Under E2EE: consume to-device room keys, top up one-time keys, then decrypt the timeline in place
-- so the existing plaintext extraction\/engagement logic runs post-decrypt.
decryptedSync :: MatrixEnv -> Value -> IO Value
decryptedSync env sync = do
  processToDevice env sync
  replenishFromSync env sync
  decryptTimeline env sync

-- | Receive Megolm room keys: for each @m.room.encrypted@ to-device event addressed to our
-- curve25519 key, Olm-decrypt it and, when it is an @m.room_key@, store the inbound session.
processToDevice :: MatrixEnv -> Value -> IO ()
processToDevice env sync = do
  let c = esCrypto (meE2 env)
  (ourCurve, _ed) <- E2.cryptoIdentityKeys c
  forM_ (arrGet "events" (fromMaybe Null (lookKey "to_device" sync))) (handleTd c ourCurve)
  where
    handleTd c ourCurve ev
      | lookStr "type" ev == Just "m.room.encrypted" =
          let content = fromMaybe Null (lookKey "content" ev)
           in case (lookStr "sender_key" content, olmCipherFor ourCurve content) of
                (Just senderKey, Just (mtype, body)) -> do
                  r <- E2.decryptOlm c senderKey mtype body
                  case r of
                    Right pt | lookStr "type" pt == Just "m.room_key" -> do
                      _ <- E2.storeRoomKey c senderKey pt
                      writeIORef (esDirty (meE2 env)) True
                    _ -> pure ()
                _ -> pure ()
      | otherwise = pure ()

-- | The @(message_type, body)@ of an Olm ciphertext addressed to our curve25519 key, if present.
olmCipherFor :: Text -> Value -> Maybe (Int, Text)
olmCipherFor ourCurve content = do
  ct <- lookKey "ciphertext" content
  entry <- lookKey ourCurve ct
  mtype <- lookInt "type" entry
  body <- lookStr "body" entry
  pure (mtype, body)

-- | Top up published one-time keys when the homeserver reports the count has fallen below half the
-- account maximum (best-effort; the server count rides on each @/sync@).
replenishFromSync :: MatrixEnv -> Value -> IO ()
replenishFromSync env sync = do
  let count = fromMaybe 0 (lookKey "device_one_time_keys_count" sync >>= lookInt "signed_curve25519")
  _ <- E2.replenishOtks (esCrypto (meE2 env)) (restAdapter (meConfig env) (meManager env) (meToken env)) count
  pure ()

-- | Rewrite a sync response so each encrypted joined-room timeline event is replaced by its decrypted
-- inner event (@type@\/@content@ spliced onto the outer envelope). Undecryptable events are left as-is.
decryptTimeline :: MatrixEnv -> Value -> IO Value
decryptTimeline env sync = case lookKey "rooms" sync of
  Just (Object roomsObj) -> case KM.lookup "join" roomsObj of
    Just (Object joinObj) -> do
      joinObj' <- KM.traverseWithKey (\_ room -> decryptRoom room) joinObj
      let roomsObj' = KM.insert "join" (Object joinObj') roomsObj
      pure (setKey "rooms" (Object roomsObj') sync)
    _ -> pure sync
  _ -> pure sync
  where
    c = esCrypto (meE2 env)
    decryptRoom (Object ro) = case KM.lookup "timeline" ro of
      Just (Object tl) -> case KM.lookup "events" tl of
        Just (Array evs) -> do
          evs' <- V.mapM decryptEvent evs
          pure (Object (KM.insert "timeline" (Object (KM.insert "events" (Array evs') tl)) ro))
        _ -> pure (Object ro)
      _ -> pure (Object ro)
    decryptRoom v = pure v
    decryptEvent ev
      | lookStr "type" ev == Just "m.room.encrypted" = do
          r <- E2.decryptMegolm c (fromMaybe Null (lookKey "content" ev))
          pure $ case r of
            Right inner -> case (lookKey "type" inner, lookKey "content" inner) of
              (Just ty, Just ct) -> setKey "type" ty (setKey "content" ct ev)
              _ -> ev
            Left _ -> ev
      | otherwise = pure ev

-- | Send a message body, Megolm-encrypting it when the room is encrypted (else plaintext).
sendText :: MatrixEnv -> Text -> Text -> IO (Either GatewayError Text)
sendText env room body = do
  enc' <- roomEncrypted env room
  if enc' then sendEncrypted env room body else sendMessage env room body

-- | Whether @room@ has @m.room.encryption@ state (cached per room).
roomEncrypted :: MatrixEnv -> Text -> IO Bool
roomEncrypted env room = do
  let ref = esEnc (meE2 env)
  cache <- readIORef ref
  case Map.lookup room cache of
    Just b -> pure b
    Nothing -> do
      r <- httpGet (meConfig env) (meManager env) (meToken env) ("/_matrix/client/v3/rooms/" <> enc room <> "/state/m.room.encryption/")
      let b = case r of Right v -> lookKey "algorithm" v /= Nothing; _ -> False
      modifyIORef' ref (Map.insert room b)
      pure b

-- | Share the room key with every peer device (once per Megolm session), then Megolm-encrypt @body@
-- and PUT it as an @m.room.encrypted@ timeline event.
sendEncrypted :: MatrixEnv -> Text -> Text -> IO (Either GatewayError Text)
sendEncrypted env room body = do
  ensureRoomKeyShared env room
  let c = esCrypto (meE2 env)
      inner =
        object
          [ "type" .= ("m.room.message" :: Text),
            "room_id" .= room,
            "content" .= object ["msgtype" .= ("m.text" :: Text), "body" .= body]
          ]
  content <- E2.encryptMegolm c room inner
  writeIORef (esDirty (meE2 env)) True -- the outbound Megolm ratchet advanced
  n <- nextTxn env
  let path = "/_matrix/client/v3/rooms/" <> enc room <> "/send/m.room.encrypted/lvz" <> tshow n
  r <- httpSend (meConfig env) (meManager env) (Just (meToken env)) "PUT" path (Just content)
  pure (r >>= \v -> maybe (Left (GEProtocol "send missing event_id")) Right (lookStr "event_id" v))

-- | Ensure the current room key has been Olm-shared to every joined peer device (deduped in 'esShared').
ensureRoomKeyShared :: MatrixEnv -> Text -> IO ()
ensureRoomKeyShared env room = do
  members <- joinedMembers env room
  forM_ [m | m <- members, m /= meUserId env] $ \userId -> do
    devices <- userDevices env userId
    forM_ devices (shareToDevice env room userId)

shareToDevice :: MatrixEnv -> Text -> Text -> Text -> IO ()
shareToDevice env room userId deviceId = do
  let ref = esShared (meE2 env)
  s <- readIORef ref
  unless (Set.member (room, userId, deviceId) s) $ do
    n <- nextTxn env
    r <- E2.shareRoomKeyWith (esCrypto (meE2 env)) (restAdapter (meConfig env) (meManager env) (meToken env)) ("lvz" <> tshow n) room userId deviceId
    case r of
      Right () -> modifyIORef' ref (Set.insert (room, userId, deviceId)) >> writeIORef (esDirty (meE2 env)) True
      Left _ -> pure () -- best-effort; retried on the next send

-- | The joined members of a room (their user ids).
joinedMembers :: MatrixEnv -> Text -> IO [Text]
joinedMembers env room = do
  r <- httpGet (meConfig env) (meManager env) (meToken env) ("/_matrix/client/v3/rooms/" <> enc room <> "/joined_members")
  pure $ case r of
    Right v -> map fst (objToList (lookKey "joined" v))
    Left _ -> []

-- | A user's device ids (from a @/keys/query@ over that user).
userDevices :: MatrixEnv -> Text -> IO [Text]
userDevices env userId = do
  r <- restAdapter (meConfig env) (meManager env) (meToken env) "POST" "/_matrix/client/v3/keys/query" (object ["device_keys" .= object [K.fromText userId .= ([] :: [Text])]])
  pure $ case r of
    Right v -> case lookKey "device_keys" v >>= lookKey userId of
      Just (Object o) -> map K.toText (KM.keys o)
      _ -> []
    Left _ -> []

lookInt :: Text -> Value -> Maybe Int
lookInt k v = case lookKey k v of
  Just (Number n) -> toBoundedInteger n
  _ -> Nothing

setKey :: Text -> Value -> Value -> Value
setKey k val (Object o) = Object (KM.insert (K.fromText k) val o)
setKey _ _ v = v

#else

-- | Without E2EE: the plaintext env, an identity sync transform, and a plaintext sender.
mkEnv :: MatrixConfig -> Manager -> Text -> Text -> Text -> IORef Int -> IO MatrixEnv
mkEnv cfg mgr token userId _deviceId txn = pure (MatrixEnv cfg mgr token userId txn)

decryptedSync :: MatrixEnv -> Value -> IO Value
decryptedSync _ sync = pure sync

persistIfDirty :: MatrixEnv -> IO ()
persistIfDirty _ = pure ()

sendText :: MatrixEnv -> Text -> Text -> IO (Either GatewayError Text)
sendText = sendMessage

#endif

-- --- auth ------------------------------------------------------------------------------------------

-- | Resolve the session (token > password login). Persisted-session reuse is deferred (no state dir
-- persistence yet); a configured token is validated via @whoami@.
resolveSession :: MatrixConfig -> Manager -> IO (Either GatewayError (Text, Text, Text))
resolveSession cfg mgr = case mcAccessToken cfg of
  -- Explicit token wins (validated via whoami).
  Just token -> do
    ewho <- whoami cfg mgr token
    pure (fmap (\(uid, dev) -> (token, uid, dev)) ewho)
  Nothing -> do
    -- A persisted session (token + device id) is reused when valid, keeping the device id stable.
    persisted <- maybe (pure Nothing) loadSession (mcStateDir cfg)
    case persisted of
      Just (ptoken, pdev) -> do
        ewho <- whoami cfg mgr ptoken
        case ewho of
          Right (uid, _) -> pure (Right (ptoken, uid, pdev))
          Left _ -> loginAndSave cfg mgr (Just pdev)
      Nothing -> loginAndSave cfg mgr Nothing

-- | Password-login, reusing a persisted\/configured device id so the device stays stable, then
-- persist the issued @{access_token, device_id}@ to @session.json@ when a state dir is configured.
loginAndSave :: MatrixConfig -> Manager -> Maybe Text -> IO (Either GatewayError (Text, Text, Text))
loginAndSave cfg mgr persistedDev = do
  let cfg' = cfg {mcDeviceId = mcDeviceId cfg `orElse` persistedDev}
  r <- login cfg' mgr
  case r of
    Right (token, uid, dev) -> do
      maybe (pure ()) (\d -> saveSession d token dev) (mcStateDir cfg)
      pure (Right (token, uid, dev))
    Left e -> pure (Left e)
  where
    orElse (Just x) _ = Just x
    orElse Nothing y = y

-- | Load @{access_token, device_id}@ from @\<dir\>/session.json@, if present and well-formed.
loadSession :: FilePath -> IO (Maybe (Text, Text))
loadSession dir = do
  let path = dir </> "session.json"
  ok <- doesFileExist path
  if not ok
    then pure Nothing
    else do
      bytes <- BL.readFile path
      pure $ do
        v <- decode bytes
        (,) <$> lookStr "access_token" v <*> lookStr "device_id" v

-- | Persist @{access_token, device_id}@ to @\<dir\>/session.json@ (creating the dir; best-effort).
saveSession :: FilePath -> Text -> Text -> IO ()
saveSession dir token dev = do
  _ <- try (createDirectoryIfMissing True dir) :: IO (Either SomeException ())
  _ <- try (BL.writeFile (dir </> "session.json") (encode (object ["access_token" .= token, "device_id" .= dev]))) :: IO (Either SomeException ())
  pure ()

whoami :: MatrixConfig -> Manager -> Text -> IO (Either GatewayError (Text, Text))
whoami cfg mgr token = do
  r <- httpGet cfg mgr token "/_matrix/client/v3/account/whoami"
  pure $ case r of
    Left e -> Left e
    Right v -> case lookStr "user_id" v of
      Just uid -> Right (uid, deviceIdFrom cfg v)
      Nothing -> Left (GEProtocol "whoami missing user_id")

login :: MatrixConfig -> Manager -> IO (Either GatewayError (Text, Text, Text))
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
        (Just tok, Just uid) -> Right (tok, uid, deviceIdFrom cfg v)
        _ -> Left (GEProtocol "login response missing access_token/user_id")

-- | The device id from a login\/whoami response, else the configured @MATRIX_DEVICE_ID@, else empty.
-- (Only E2EE actually needs a stable device id; the plaintext path ignores it.)
deviceIdFrom :: MatrixConfig -> Value -> Text
deviceIdFrom cfg v = fromMaybe (fromMaybe "" (mcDeviceId cfg)) (lookStr "device_id" v)

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
    imReplyTo :: Maybe Text,
    -- | A plaintext media attachment (image\/file\/audio\/video), when present; downloaded to the
    -- media dir and handed to the turn as a local path (E2EE media is not ingested).
    imAttachment :: Maybe Attachment
  }
  deriving stock (Eq, Show)

-- | A plaintext inbound attachment: its @mxc://@ URI, filename, and mimetype.
data Attachment = Attachment
  { atMxc :: Text,
    atFilename :: Text,
    atMime :: Text
  }
  deriving stock (Eq, Show)

-- | Pull the answerable @m.room.message@ events out of a sync response, skipping the bot's own
-- messages and senders\/rooms outside any configured allowlist, and attaching the mention\/reply
-- signals.
extractMessages :: Value -> Text -> Maybe (Set Text) -> Maybe (Set Text) -> [IncomingMessage]
extractMessages sync self allowedUsers allowedRooms =
  [ IncomingMessage roomId sender body eid (mentionsBot content self) (replyTarget content) att
  | (roomId, room) <- objToList (lookKey "rooms" sync >>= lookKey "join"),
    roomAllowed allowedRooms roomId,
    event <- arrGet "events" (fromMaybe Null (lookKey "timeline" room)),
    lookStr "type" event == Just "m.room.message",
    let sender = fromMaybe "" (lookStr "sender" event),
    sender /= self,
    senderAllowed allowedUsers sender,
    let content = fromMaybe Null (lookKey "content" event),
    Just (body, att) <- [messageContent content],
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

-- | The answerable content of a message: an @m.text@ yields @(body, Nothing)@; a plaintext
-- @m.image@\/@m.file@\/@m.audio@\/@m.video@ (a cleartext @url@) yields @(caption, Just attachment)@;
-- anything else (including E2EE media, whose reference is under @content.file@, not @url@) is ignored.
messageContent :: Value -> Maybe (Text, Maybe Attachment)
messageContent content = case lookStr "msgtype" content of
  Just "m.text" -> (\b -> (b, Nothing)) <$> lookStr "body" content
  Just mt
    | mt `elem` ["m.image", "m.file", "m.audio", "m.video"] ->
        case lookStr "url" content of
          Just mxc ->
            let name = fromMaybe "attachment" (lookStr "body" content)
                mime = fromMaybe "application/octet-stream" (lookKey "info" content >>= lookStr "mimetype")
             in Just (fromMaybe "" (lookStr "body" content), Just (Attachment mxc name mime))
          Nothing -> Nothing
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
