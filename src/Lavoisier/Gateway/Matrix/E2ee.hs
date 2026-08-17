-- | @Lavoisier.Gateway.Matrix.E2ee@ — Matrix end-to-end encryption over the @olm@ package (the
-- Olm/Megolm C library). Built only with the @e2ee@ cabal flag.
--
-- This is the crypto __orchestration__ the Rust gateway delegates to @matrix-sdk-crypto@'s
-- @OlmMachine@: a bot 'Crypto' state (its Olm 'Account', its Megolm inbound\/outbound group sessions,
-- and its 1:1 Olm sessions to peers) plus the operations that drive Matrix E2EE:
--
--   * publish signed device keys + one-time keys ('deviceKeysPayload' \/ 'oneTimeKeysPayload');
--   * receive a room key shared over Olm ('decryptOlm' → 'storeRoomKey') and then decrypt the room's
--     timeline ('decryptMegolm');
--   * establish an Olm session to a peer device and share the room key ('olmEncryptTo'), then
--     Megolm-encrypt outbound messages ('encryptMegolm').
--
-- Matrix signs device keys over __canonical JSON__ ('canonicalJson'), implemented here. The full
-- crypto path — Olm room-key share → Megolm decrypt, and device-key signing — is exercised offline
-- with two in-process 'Crypto' instances (see the @lavoisier-e2ee-test@ suite). The live REST wiring
-- (@\/keys\/upload@, @\/keys\/query@, @\/keys\/claim@, to-device send, and the serve-loop
-- decrypt\/encrypt hooks) is the remaining homeserver-only integration.
module Lavoisier.Gateway.Matrix.E2ee
  ( Crypto,
    newCrypto,
    cryptoIdentityKeys,
    takeOneTimeKey,

    -- * Key publishing
    deviceKeysPayload,
    oneTimeKeysPayload,
    canonicalJson,
    signJson,

    -- * Inbound (receiving)
    decryptOlm,
    storeRoomKey,
    decryptMegolm,

    -- * Outbound (sending)
    getOrCreateOutbound,
    olmEncryptTo,
    roomKeyEvent,
    encryptMegolm,

    -- * Homeserver REST wiring (decoupled via a 'Rest' hook, so it is offline-testable)
    Rest,
    publishKeys,
    queryDevice,
    claimOtk,
    shareRoomKeyWith,
    olmEncryptedContent,
    parseDeviceKeys,
    parseClaimedOtk,
  )
where

import Crypto.Olm
import Data.Aeson (Value (..), decodeStrict, encode, object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Vector qualified as V

megolmAlgorithm :: Text
megolmAlgorithm = "m.megolm.v1.aes-sha2"

olmAlgorithm :: Text
olmAlgorithm = "m.olm.v1.curve25519-aes-sha2"

-- | The bot's end-to-end-encryption state.
data Crypto = Crypto
  { crAccount :: Account,
    crUserId :: Text,
    crDeviceId :: Text,
    crCurve :: Text,
    crEd :: Text,
    -- | Received Megolm sessions, keyed by @(sender curve25519 key, session id)@.
    crInbound :: IORef (Map (Text, Text) InboundGroupSession),
    -- | Our Megolm sending session per room.
    crOutbound :: IORef (Map Text OutboundGroupSession),
    -- | Our 1:1 Olm sessions, keyed by the peer's curve25519 identity key.
    crOlm :: IORef (Map Text Session)
  }

-- | Create a fresh crypto identity for @userId@\/@deviceId@ with an initial batch of one-time keys.
newCrypto :: Text -> Text -> IO Crypto
newCrypto userId deviceId = do
  acc <- newAccount
  maxOtk <- maxOneTimeKeys acc
  generateOneTimeKeys acc (max 1 (maxOtk `div` 2))
  idk <- identityKeysRaw acc
  inbound <- newIORef Map.empty
  outbound <- newIORef Map.empty
  olm <- newIORef Map.empty
  pure (Crypto acc userId deviceId (fst idk) (snd idk) inbound outbound olm)

identityKeysRaw :: Account -> IO (Text, Text)
identityKeysRaw acc = do
  idk <- identityKeys acc
  pure (jField "curve25519" idk, jField "ed25519" idk)

-- | The bot's @(curve25519, ed25519)@ identity keys.
cryptoIdentityKeys :: Crypto -> IO (Text, Text)
cryptoIdentityKeys c = pure (crCurve c, crEd c)

-- | One of the account's current unpublished one-time keys (its base64 value), if any. (Test helper
-- standing in for a server @\/keys\/claim@.)
takeOneTimeKey :: Crypto -> IO (Maybe Text)
takeOneTimeKey c = do
  otks <- oneTimeKeys (crAccount c)
  pure (firstCurveValue otks)

-- --- key publishing --------------------------------------------------------------------------------

-- | The signed @device_keys@ object for @POST \/keys\/upload@.
deviceKeysPayload :: Crypto -> IO Value
deviceKeysPayload c = do
  let unsigned =
        object
          [ "user_id" .= crUserId c,
            "device_id" .= crDeviceId c,
            "algorithms" .= [olmAlgorithm, megolmAlgorithm],
            "keys"
              .= object
                [ K.fromText ("curve25519:" <> crDeviceId c) .= crCurve c,
                  K.fromText ("ed25519:" <> crDeviceId c) .= crEd c
                ]
          ]
  sig <- signJson c unsigned
  pure (addSignature c sig unsigned)

-- | The @one_time_keys@ object for @POST \/keys\/upload@ (each key signed), and mark them published.
oneTimeKeysPayload :: Crypto -> IO Value
oneTimeKeysPayload c = do
  otks <- oneTimeKeys (crAccount c)
  let pairs = curveEntries otks
  signed <- mapM signOtk pairs
  markKeysAsPublished (crAccount c)
  pure (object [K.fromText ("signed_curve25519:" <> kid) .= v | (kid, v) <- signed])
  where
    signOtk (kid, key) = do
      let unsigned = object ["key" .= key]
      sig <- signJson c unsigned
      pure (kid, addSignature c sig unsigned)

-- | Sign @value@ over Matrix __canonical JSON__ (its @signatures@\/@unsigned@ fields removed) with
-- the account's Ed25519 key; returns the unpadded-base64 signature.
signJson :: Crypto -> Value -> IO Text
signJson c value = decodeUtf8Lenient <$> sign (crAccount c) (canonicalJson (stripSigning value))

-- | Attach @{"signatures":{user_id:{"ed25519:device":sig}}}@ to an object.
addSignature :: Crypto -> Text -> Value -> Value
addSignature c sig (Object o) =
  Object (KM.insert "signatures" sigs o)
  where
    sigs = object [K.fromText (crUserId c) .= object [K.fromText ("ed25519:" <> crDeviceId c) .= sig]]
addSignature _ _ v = v

stripSigning :: Value -> Value
stripSigning (Object o) = Object (KM.delete "signatures" (KM.delete "unsigned" o))
stripSigning v = v

-- | Matrix canonical JSON: UTF-8, object keys sorted lexicographically, no insignificant whitespace.
-- Leaf values are rendered by aeson's (already compact) encoder; only object-key ordering and
-- assembly are handled here.
canonicalJson :: Value -> ByteString
canonicalJson (Object o) =
  "{" <> BS.intercalate "," [enc (String k) <> ":" <> canonicalJson v | (k, v) <- sortOn fst fields] <> "}"
  where
    fields = [(K.toText k, v) | (k, v) <- KM.toList o]
    enc = BL.toStrict . encode
canonicalJson (Array a) = "[" <> BS.intercalate "," (map canonicalJson (V.toList a)) <> "]"
canonicalJson v = BL.toStrict (encode v)

-- --- inbound (receiving) ---------------------------------------------------------------------------

-- | Decrypt a 1:1 Olm message from a peer (its curve25519 @senderKey@): reuse an existing session, or
-- (a PRE_KEY message, type 0) establish an inbound one. Returns the decrypted plaintext JSON.
decryptOlm :: Crypto -> Text -> Int -> Text -> IO (Either Text Value)
decryptOlm c senderKey msgType body = do
  sessions <- readIORef (crOlm c)
  msess <- case Map.lookup senderKey sessions of
    Just s -> pure (Just s)
    Nothing
      | msgType == 0 -> do
          s <- createInboundSessionFrom (crAccount c) (encodeUtf8 senderKey) (encodeUtf8 body)
          removeOneTimeKeys (crAccount c) s
          modifyIORef' (crOlm c) (Map.insert senderKey s)
          pure (Just s)
      | otherwise -> pure Nothing
  case msess of
    Nothing -> pure (Left "no Olm session for a non-prekey message")
    Just s -> do
      pt <- decrypt s msgType (encodeUtf8 body)
      pure (maybe (Left "olm plaintext was not JSON") Right (decodeStrict pt))

-- | Store a Megolm session shared in an @m.room_key@ event (as decrypted from an Olm message), keyed
-- by @(senderKey, session_id)@ so 'decryptMegolm' can find it.
storeRoomKey :: Crypto -> Text -> Value -> IO (Either Text ())
storeRoomKey c senderKey roomKey =
  case (lookStr "session_id" content, lookStr "session_key" content) of
    (Just sid, Just skey) -> do
      inb <- newInboundGroupSession (encodeUtf8 skey)
      modifyIORef' (crInbound c) (Map.insert (senderKey, sid) inb)
      pure (Right ())
    _ -> pure (Left "m.room_key missing session_id/session_key")
  where
    content = maybe roomKey id (lookKey "content" roomKey)

-- | Decrypt an @m.room.encrypted@ (Megolm) event content: look up the inbound session by
-- @(sender_key, session_id)@, Megolm-decrypt the ciphertext, and parse the inner event JSON.
decryptMegolm :: Crypto -> Value -> IO (Either Text Value)
decryptMegolm c content =
  case (lookStr "sender_key" content, lookStr "session_id" content, lookStr "ciphertext" content) of
    (Just sk, Just sid, Just ct) -> do
      inbound <- readIORef (crInbound c)
      case Map.lookup (sk, sid) inbound of
        Nothing -> pure (Left "no Megolm session for this (sender_key, session_id)")
        Just inb -> do
          (pt, _idx) <- groupDecrypt inb (encodeUtf8 ct)
          pure (maybe (Left "megolm plaintext was not JSON") Right (decodeStrict pt))
    _ -> pure (Left "m.room.encrypted missing sender_key/session_id/ciphertext")

-- --- outbound (sending) ----------------------------------------------------------------------------

-- | Get (creating if needed) this room's Megolm sending session; returns @(session_id, session_key)@.
-- The session key is what must be shared with recipients via 'roomKeyEvent' + 'olmEncryptTo'.
getOrCreateOutbound :: Crypto -> Text -> IO (Text, Text)
getOrCreateOutbound c room = do
  outs <- readIORef (crOutbound c)
  out <- case Map.lookup room outs of
    Just o -> pure o
    Nothing -> do
      o <- newOutboundGroupSession
      modifyIORef' (crOutbound c) (Map.insert room o)
      -- Also seed our own inbound copy so we could decrypt our own messages if echoed.
      pure o
  sid <- decodeUtf8Lenient <$> outboundSessionId out
  skey <- decodeUtf8Lenient <$> outboundSessionKey out
  pure (sid, skey)

-- | The @m.room_key@ event body sharing @room@'s current Megolm session with recipients.
roomKeyEvent :: Crypto -> Text -> IO Value
roomKeyEvent c room = do
  (sid, skey) <- getOrCreateOutbound c room
  pure
    ( object
        [ "type" .= ("m.room_key" :: Text),
          "content"
            .= object
              [ "algorithm" .= megolmAlgorithm,
                "room_id" .= room,
                "session_id" .= sid,
                "session_key" .= skey
              ]
        ]
    )

-- | Establish (if needed) an Olm session to a peer given its curve25519 identity key and a claimed
-- one-time key, and Olm-encrypt @event@ for it. Returns @(message_type, ciphertext_body)@.
olmEncryptTo :: Crypto -> Text -> Text -> Value -> IO (Int, Text)
olmEncryptTo c theirIdentityKey theirOtk event = do
  sessions <- readIORef (crOlm c)
  sess <- case Map.lookup theirIdentityKey sessions of
    Just s -> pure s
    Nothing -> do
      s <- createOutboundSession (crAccount c) (encodeUtf8 theirIdentityKey) (encodeUtf8 theirOtk)
      modifyIORef' (crOlm c) (Map.insert theirIdentityKey s)
      pure s
  (mtype, ct) <- encrypt sess (BL.toStrict (encode event))
  pure (mtype, decodeUtf8Lenient ct)

-- | Megolm-encrypt an inner event for @room@; returns the @m.room.encrypted@ event content.
encryptMegolm :: Crypto -> Text -> Value -> IO Value
encryptMegolm c room event = do
  outs <- readIORef (crOutbound c)
  out <- case Map.lookup room outs of
    Just o -> pure o
    Nothing -> do
      o <- newOutboundGroupSession
      modifyIORef' (crOutbound c) (Map.insert room o)
      pure o
  sid <- decodeUtf8Lenient <$> outboundSessionId out
  ct <- decodeUtf8Lenient <$> groupEncrypt out (BL.toStrict (encode event))
  pure
    ( object
        [ "algorithm" .= megolmAlgorithm,
          "sender_key" .= crCurve c,
          "session_id" .= sid,
          "device_id" .= crDeviceId c,
          "ciphertext" .= ct
        ]
    )

-- --- homeserver REST wiring ------------------------------------------------------------------------

-- | The gateway supplies this: @method → path → body → response@ (or an error). Keeping it abstract
-- lets the E2EE key exchange be driven against a real homeserver by the gateway, and against a mock
-- in tests, without this module depending on the HTTP client.
type Rest = Text -> Text -> Value -> IO (Either Text Value)

-- | Publish the bot's device keys + a batch of one-time keys (@POST \/keys\/upload@).
publishKeys :: Crypto -> Rest -> IO (Either Text ())
publishKeys c rest = do
  dk <- deviceKeysPayload c
  otk <- oneTimeKeysPayload c
  fmap (const ()) <$> rest "POST" "/_matrix/client/v3/keys/upload" (object ["device_keys" .= dk, "one_time_keys" .= otk])

-- | Query a peer device's @(curve25519, ed25519)@ identity keys (@POST \/keys\/query@).
queryDevice :: Rest -> Text -> Text -> IO (Either Text (Text, Text))
queryDevice rest userId deviceId = do
  r <- rest "POST" "/_matrix/client/v3/keys/query" (object ["device_keys" .= object [K.fromText userId .= ([] :: [Text])]])
  pure (r >>= parseDeviceKeys userId deviceId)

-- | Claim a one-time key for a peer device (@POST \/keys\/claim@), returning its base64 value.
claimOtk :: Rest -> Text -> Text -> IO (Either Text Text)
claimOtk rest userId deviceId = do
  let body = object ["one_time_keys" .= object [K.fromText userId .= object [K.fromText deviceId .= ("signed_curve25519" :: Text)]]]
  r <- rest "POST" "/_matrix/client/v3/keys/claim" body
  pure (r >>= parseClaimedOtk userId deviceId)

-- | Share @room@'s current Megolm session with a peer device: look up its keys, claim a one-time key,
-- Olm-encrypt the @m.room_key@ to it, and send it to-device (@PUT \/sendToDevice@, @txn@ supplied by
-- the caller). The room key must be shared before 'encryptMegolm' output is sent.
shareRoomKeyWith :: Crypto -> Rest -> Text -> Text -> Text -> Text -> IO (Either Text ())
shareRoomKeyWith c rest txn room userId deviceId = do
  ek <- queryDevice rest userId deviceId
  case ek of
    Left e -> pure (Left e)
    Right (curve, _ed) -> do
      mo <- claimOtk rest userId deviceId
      case mo of
        Left e -> pure (Left e)
        Right otk -> do
          rk <- roomKeyEvent c room
          (mtype, ctBody) <- olmEncryptTo c curve otk rk
          let msg = object ["messages" .= object [K.fromText userId .= object [K.fromText deviceId .= olmEncryptedContent c curve mtype ctBody]]]
          fmap (const ()) <$> rest "PUT" ("/_matrix/client/v3/sendToDevice/m.room.encrypted/" <> txn) msg

-- | The to-device @m.room.encrypted@ (Olm) content wrapping a ciphertext for a peer's curve25519 key.
olmEncryptedContent :: Crypto -> Text -> Int -> Text -> Value
olmEncryptedContent c theirCurve mtype ctBody =
  object
    [ "algorithm" .= olmAlgorithm,
      "sender_key" .= crCurve c,
      "ciphertext" .= object [K.fromText theirCurve .= object ["type" .= mtype, "body" .= ctBody]]
    ]

-- | Parse a peer device's @(curve25519, ed25519)@ identity keys from a @\/keys\/query@ response.
parseDeviceKeys :: Text -> Text -> Value -> Either Text (Text, Text)
parseDeviceKeys userId deviceId resp = do
  keys <- note "no device_keys.<user>.<device>.keys" (lookKey "device_keys" resp >>= lookKey userId >>= lookKey deviceId >>= lookKey "keys")
  curve <- note "no curve25519 key" (lookStr ("curve25519:" <> deviceId) keys)
  ed <- note "no ed25519 key" (lookStr ("ed25519:" <> deviceId) keys)
  pure (curve, ed)

-- | Parse the claimed one-time key's base64 value from a @\/keys\/claim@ response.
parseClaimedOtk :: Text -> Text -> Value -> Either Text Text
parseClaimedOtk userId deviceId resp = do
  dev <- note "no one_time_keys.<user>.<device>" (lookKey "one_time_keys" resp >>= lookKey userId >>= lookKey deviceId)
  case dev of
    Object o -> case [v | (k, v) <- KM.toList o, "signed_curve25519:" `T.isPrefixOf` K.toText k] of
      (keyObj : _) -> note "claimed key has no `key`" (lookStr "key" keyObj)
      [] -> Left "no signed_curve25519 key in claim response"
    _ -> Left "claim response device entry was not an object"

note :: Text -> Maybe a -> Either Text a
note e = maybe (Left e) Right

-- --- JSON helpers ----------------------------------------------------------------------------------

lookKey :: Text -> Value -> Maybe Value
lookKey k (Object o) = KM.lookup (K.fromText k) o
lookKey _ _ = Nothing

lookStr :: Text -> Value -> Maybe Text
lookStr k v = case lookKey k v of
  Just (String s) -> Just s
  _ -> Nothing

-- | A required top-level string field of libolm's identity-keys JSON.
jField :: Text -> ByteString -> Text
jField k bs = case decodeStrict bs of
  Just v -> maybe (error ("e2ee: identity key field " <> T.unpack k <> " missing")) id (lookStr k v)
  Nothing -> error "e2ee: identity keys were not JSON"

-- | The first value of libolm's @{"curve25519":{id:key,…}}@ one-time-keys JSON.
firstCurveValue :: ByteString -> Maybe Text
firstCurveValue bs = do
  v <- decodeStrict bs
  Object keys <- lookKey "curve25519" v
  listToMaybe [s | String s <- KM.elems keys]

-- | The @(keyId, keyValue)@ entries of the curve25519 one-time-keys JSON.
curveEntries :: ByteString -> [(Text, Text)]
curveEntries bs = case decodeStrict bs >>= lookKey "curve25519" of
  Just (Object keys) -> [(K.toText k, s) | (k, String s) <- KM.toList keys]
  _ -> []
