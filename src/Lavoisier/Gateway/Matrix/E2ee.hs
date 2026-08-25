{- | @Lavoisier.Gateway.Matrix.E2ee@ — Matrix end-to-end encryption over the @olm@ package (the
Olm/Megolm C library). Built only with the @e2ee@ cabal flag.

This is the crypto __orchestration__ the Rust gateway delegates to @matrix-sdk-crypto@'s
@OlmMachine@: a bot 'Crypto' state (its Olm 'Account', its Megolm inbound\/outbound group sessions,
and its 1:1 Olm sessions to peers) plus the operations that drive Matrix E2EE:

  * publish signed device keys + one-time keys ('deviceKeysPayload' \/ 'oneTimeKeysPayload');
  * receive a room key shared over Olm ('decryptOlm' → 'storeRoomKey') and then decrypt the room's
    timeline ('decryptMegolm');
  * establish an Olm session to a peer device and share the room key ('olmEncryptTo'), then
    Megolm-encrypt outbound messages ('encryptMegolm').

Matrix signs device keys over __canonical JSON__ ('canonicalJson'), implemented here, and a peer's
device keys are __verified__ against their Ed25519 self-signature before use ('verifyDeviceKeys').
The identity is __durable__: 'pickleStore' \/ 'unpickleStore' round-trip the account + all sessions
to disk so the bot survives a restart. The crypto path is exercised offline with two in-process
'Crypto' instances (see @lavoisier-e2ee-test@) and the whole serve loop is live-verified end to end
against a real homeserver.
-}
module Lavoisier.Gateway.Matrix.E2ee (
    Crypto,
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
    storeForwardedRoomKey,
    decryptMegolm,

    -- * Outbound (sending)
    getOrCreateOutbound,
    olmEncryptTo,
    roomKeyEvent,
    encryptMegolm,

    -- * Durable crypto store (pickle the account + all sessions)
    pickleStore,
    unpickleStore,
    verifyDeviceKeys,

    -- * Homeserver REST wiring (decoupled via a 'Rest' hook, so it is offline-testable)
    Rest,
    publishKeys,
    replenishOtks,
    queryDevice,
    claimOtk,
    shareRoomKeyWith,
    olmEncryptedContent,

    -- * Recovery (a lost or diverged session is repaired, never waited out)
    findDeviceByCurve,
    sendDummyTo,
    requestRoomKey,
    cancelRoomKeyRequest,
    parseDeviceKeys,
    parseClaimedOtk,
)
where

import Control.Exception (SomeException, try)
import Control.Monad (foldM)
import Crypto.Olm
import Data.Aeson (Value (..), decodeStrict, encode, object, (.=))
import Data.ByteString (ByteString)
import Data.IORef
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Vector qualified as V

megolmAlgorithm ∷ Text
megolmAlgorithm = "m.megolm.v1.aes-sha2"

olmAlgorithm ∷ Text
olmAlgorithm = "m.olm.v1.curve25519-aes-sha2"

-- | The bot's end-to-end-encryption state.
data Crypto = Crypto
    { crAccount ∷ Account
    , crUserId ∷ Text
    , crDeviceId ∷ Text
    , crCurve ∷ Text
    , crEd ∷ Text
    , crInbound ∷ IORef (Map (Text, Text) InboundGroupSession)
    -- ^ Received Megolm sessions, keyed by @(sender curve25519 key, session id)@.
    , crOutbound ∷ IORef (Map Text OutboundGroupSession)
    -- ^ Our Megolm sending session per room.
    , crOlm ∷ IORef (Map Text Session)
    -- ^ Our 1:1 Olm sessions, keyed by the peer's curve25519 identity key.
    }

-- | Create a fresh crypto identity for @userId@\/@deviceId@ with an initial batch of one-time keys.
newCrypto ∷ Text → Text → IO Crypto
newCrypto userId deviceId = do
    acc ← newAccount
    maxOtk ← maxOneTimeKeys acc
    generateOneTimeKeys acc (max 1 (maxOtk `div` 2))
    idk ← identityKeysRaw acc
    inbound ← newIORef Map.empty
    outbound ← newIORef Map.empty
    olm ← newIORef Map.empty
    pure (Crypto acc userId deviceId (fst idk) (snd idk) inbound outbound olm)

identityKeysRaw ∷ Account → IO (Text, Text)
identityKeysRaw acc = do
    idk ← identityKeys acc
    pure (jField "curve25519" idk, jField "ed25519" idk)

-- | The bot's @(curve25519, ed25519)@ identity keys.
cryptoIdentityKeys ∷ Crypto → IO (Text, Text)
cryptoIdentityKeys c = pure (crCurve c, crEd c)

-- --- durable crypto store --------------------------------------------------------------------------

{- | Pickle the whole crypto identity (the Olm account, the 1:1 Olm sessions, and the inbound\/outbound
Megolm sessions) to a JSON value, each blob encrypted at rest under @passphrase@ (libolm pickling).
Round-trips with 'unpickleStore' so the E2EE identity survives a restart — no re-verification, no
lost inbound room keys.
-}
pickleStore ∷ Crypto → Text → IO Value
pickleStore c passphrase = do
    let key = encodeUtf8 passphrase
    acc ← decodeUtf8Lenient <$> pickleAccount (crAccount c) key
    olm ← readIORef (crOlm c) >>= traverse (\s → decodeUtf8Lenient <$> pickleSession s key)
    inb ← readIORef (crInbound c)
    inbTriples ← mapM (\((curve, sid), s) → (\p → [curve, sid, decodeUtf8Lenient p]) <$> pickleInbound s key) (Map.toList inb)
    out ← readIORef (crOutbound c) >>= traverse (\s → decodeUtf8Lenient <$> pickleOutbound s key)
    pure $
        object
            [ "account" .= acc
            , "olm" .= object [K.fromText k .= v | (k, v) ← Map.toList olm]
            , "inbound" .= inbTriples
            , "outbound" .= object [K.fromText k .= v | (k, v) ← Map.toList out]
            ]

{- | Restore a 'Crypto' pickled by 'pickleStore' for @userId@\/@deviceId@ under @passphrase@. A bad
passphrase or a corrupt store yields 'Nothing' (the caller falls back to a fresh identity).
-}
unpickleStore ∷ Text → Text → Text → Value → IO (Maybe Crypto)
unpickleStore userId deviceId passphrase v =
    either (const Nothing) Just <$> (try restore ∷ IO (Either SomeException Crypto))
    where
        key = encodeUtf8 passphrase
        restore = do
            accB64 ← maybe (fail "no account") pure (lookStr "account" v)
            acc ← unpickleAccount key (encodeUtf8 accB64)
            (curve, ed) ← identityKeysRaw acc
            olmMap ← restoreMap (lookKey "olm" v) (unpickleSession key)
            outMap ← restoreMap (lookKey "outbound" v) (unpickleOutbound key)
            inbMap0 ← restoreInbound (lookKey "inbound" v)
            inbMap ← seedSelfInbound curve outMap inbMap0
            Crypto acc userId deviceId curve ed <$> newIORef inbMap <*> newIORef outMap <*> newIORef olmMap
        restoreMap (Just (Object o)) un =
            Map.fromList <$> mapM (\(k, val) → case val of String p → (,) (K.toText k) <$> un (encodeUtf8 p); _ → fail "non-string pickle") (KM.toList o)
        restoreMap _ _ = pure Map.empty
        restoreInbound (Just (Array a)) =
            Map.fromList
                <$> sequence
                    [ (\s → ((curve, sid), s)) <$> unpickleInbound key (encodeUtf8 p)
                    | Array e ← V.toList a
                    , [String curve, String sid, String p] ← [V.toList e]
                    ]
        restoreInbound _ = pure Map.empty
        -- Every sending session needs our own inbound copy so we can read our own echoed sends
        -- ('outboundFor' seeds it at creation). A store written before that existed — every store in
        -- the field, including a migrated one — has outbound sessions with no such copy, so seed any
        -- that are missing on restore rather than warning on our own messages until the session rotates.
        seedSelfInbound curve outMap inbMap = foldM (seedOne curve) inbMap (Map.elems outMap)
        seedOne curve inbMap out = do
            sid ← decodeUtf8Lenient <$> outboundSessionId out
            if Map.member (curve, sid) inbMap
                then pure inbMap
                else do
                    inb ← outboundSessionKey out >>= newInboundGroupSession
                    pure (Map.insert (curve, sid) inb inbMap)

{- | Verify a peer @device_keys@ object's Ed25519 __self-signature__ over Matrix canonical JSON: the
device advertises its ed25519 key and signs its own key object with it. Returns 'False' when the
signature is absent or does not verify, so the caller can refuse to trust unsigned\/forged keys.
-}
verifyDeviceKeys ∷ Text → Text → Value → IO Bool
verifyDeviceKeys userId deviceId dev = case (edKey, sig) of
    (Just ed, Just s) → do
        u ← newUtility
        r ← try (ed25519Verify u (encodeUtf8 ed) (canonicalJson (stripSigning dev)) (encodeUtf8 s)) ∷ IO (Either SomeException Bool)
        pure (either (const False) id r)
    _ → pure False
    where
        edKey = lookKey "keys" dev >>= lookStr ("ed25519:" <> deviceId)
        sig = lookKey "signatures" dev >>= lookKey userId >>= lookStr ("ed25519:" <> deviceId)

{- | One of the account's current unpublished one-time keys (its base64 value), if any. (Test helper
standing in for a server @\/keys\/claim@.)
-}
takeOneTimeKey ∷ Crypto → IO (Maybe Text)
takeOneTimeKey c = do
    otks ← oneTimeKeys (crAccount c)
    pure (firstCurveValue otks)

-- --- key publishing --------------------------------------------------------------------------------

-- | The signed @device_keys@ object for @POST \/keys\/upload@.
deviceKeysPayload ∷ Crypto → IO Value
deviceKeysPayload c = do
    let unsigned =
            object
                [ "user_id" .= crUserId c
                , "device_id" .= crDeviceId c
                , "algorithms" .= [olmAlgorithm, megolmAlgorithm]
                , "keys"
                    .= object
                        [ K.fromText ("curve25519:" <> crDeviceId c) .= crCurve c
                        , K.fromText ("ed25519:" <> crDeviceId c) .= crEd c
                        ]
                ]
    sig ← signJson c unsigned
    pure (addSignature c sig unsigned)

-- | The @one_time_keys@ object for @POST \/keys\/upload@ (each key signed), and mark them published.
oneTimeKeysPayload ∷ Crypto → IO Value
oneTimeKeysPayload c = do
    otks ← oneTimeKeys (crAccount c)
    let pairs = curveEntries otks
    signed ← mapM signOtk pairs
    markKeysAsPublished (crAccount c)
    pure (object [K.fromText ("signed_curve25519:" <> kid) .= v | (kid, v) ← signed])
    where
        signOtk (kid, key) = do
            let unsigned = object ["key" .= key]
            sig ← signJson c unsigned
            pure (kid, addSignature c sig unsigned)

{- | Sign @value@ over Matrix __canonical JSON__ (its @signatures@\/@unsigned@ fields removed) with
the account's Ed25519 key; returns the unpadded-base64 signature.
-}
signJson ∷ Crypto → Value → IO Text
signJson c value = decodeUtf8Lenient <$> sign (crAccount c) (canonicalJson (stripSigning value))

-- | Attach @{"signatures":{user_id:{"ed25519:device":sig}}}@ to an object.
addSignature ∷ Crypto → Text → Value → Value
addSignature c sig (Object o) =
    Object (KM.insert "signatures" sigs o)
    where
        sigs = object [K.fromText (crUserId c) .= object [K.fromText ("ed25519:" <> crDeviceId c) .= sig]]
addSignature _ _ v = v

stripSigning ∷ Value → Value
stripSigning (Object o) = Object (KM.delete "signatures" (KM.delete "unsigned" o))
stripSigning v = v

{- | Matrix canonical JSON: UTF-8, object keys sorted lexicographically, no insignificant whitespace.
Leaf values are rendered by aeson's (already compact) encoder; only object-key ordering and
assembly are handled here.
-}
canonicalJson ∷ Value → ByteString
canonicalJson (Object o) =
    "{" <> BS.intercalate "," [enc (String k) <> ":" <> canonicalJson v | (k, v) ← sortOn fst fields] <> "}"
    where
        fields = [(K.toText k, v) | (k, v) ← KM.toList o]
        enc = BL.toStrict . encode
canonicalJson (Array a) = "[" <> BS.intercalate "," (map canonicalJson (V.toList a)) <> "]"
canonicalJson v = BL.toStrict (encode v)

{- | Run a libolm-backed decrypt, turning a thrown libolm C error (e.g. @BAD_MESSAGE_KEY_ID@ from a
pre-key message that references a one-time key the account no longer holds) into a clean 'Left' so
a malformed\/stale inbound message can never crash the serve loop.
-}
catchOlm ∷ IO (Either Text a) → IO (Either Text a)
catchOlm act = do
    r ← try act
    pure $ case r of
        Left e → Left (T.pack (show (e ∷ SomeException)))
        Right x → x

-- --- inbound (receiving) ---------------------------------------------------------------------------

{- | Decrypt a 1:1 Olm message from a peer (its curve25519 @senderKey@): reuse an existing session, or
(a PRE_KEY message, type 0) establish an inbound one. Returns the decrypted plaintext JSON.

A type-1 message with no matching session is __unrecoverable here__ and is reported as such: the
peer is talking over a session we no longer hold (a restored backup, a migrated store, a rolled-back
state dir). The caller answers that 'Left' with 'sendDummyTo', which makes the peer replace it.
-}
decryptOlm ∷ Crypto → Text → Int → Text → IO (Either Text Value)
decryptOlm c senderKey msgType body = catchOlm $ do
    sessions ← readIORef (crOlm c)
    msess ← case (Map.lookup senderKey sessions, msgType) of
        (Just s, 0) → do
            -- A PRE_KEY message our stored session does not match is the peer replacing a session it
            -- considers lost — its own recovery, or its answer to our 'sendDummyTo'. Decrypting it with the
            -- stale session would fail and wedge the channel in the other direction, so take the new one.
            matches ← matchesInboundSession s (encodeUtf8 body)
            if matches then pure (Just s) else Just <$> freshInbound
        (Just s, _) → pure (Just s)
        (Nothing, 0) → Just <$> freshInbound
        (Nothing, _) → pure Nothing
    case msess of
        Nothing → pure (Left "no Olm session for a non-prekey message")
        Just s → do
            pt ← decrypt s msgType (encodeUtf8 body)
            pure (maybe (Left "olm plaintext was not JSON") Right (decodeStrict pt))
    where
        freshInbound = do
            s ← createInboundSessionFrom (crAccount c) (encodeUtf8 senderKey) (encodeUtf8 body)
            removeOneTimeKeys (crAccount c) s
            modifyIORef' (crOlm c) (Map.insert senderKey s)
            pure s

{- | Store a Megolm session shared in an @m.room_key@ event (as decrypted from an Olm message), keyed
by @(senderKey, session_id)@ so 'decryptMegolm' can find it.
-}
storeRoomKey ∷ Crypto → Text → Value → IO (Either Text ())
storeRoomKey c senderKey roomKey =
    case (lookStr "session_id" content, lookStr "session_key" content) of
        (Just sid, Just skey) → do
            inb ← newInboundGroupSession (encodeUtf8 skey)
            modifyIORef' (crInbound c) (Map.insert (senderKey, sid) inb)
            pure (Right ())
        _ → pure (Left "m.room_key missing session_id/session_key")
    where
        content = maybe roomKey id (lookKey "content" roomKey)

{- | Store a Megolm session delivered by an @m.forwarded_room_key@ (a peer answering our
'requestRoomKey'). Unlike 'storeRoomKey' the key is keyed by the __content's__ @sender_key@ — the
device that originally created the session, not the one forwarding it — because that is what the
room's events carry and therefore what 'decryptMegolm' looks up. The @session_key@ is in libolm's
/export/ format, so it is imported rather than initialised.
-}
storeForwardedRoomKey ∷ Crypto → Value → IO (Either Text ())
storeForwardedRoomKey c ev = catchOlm $
    case (lookStr "sender_key" content, lookStr "session_id" content, lookStr "session_key" content) of
        (Just sk, Just sid, Just skey) → do
            inb ← importInboundGroupSession (encodeUtf8 skey)
            modifyIORef' (crInbound c) (Map.insert (sk, sid) inb)
            pure (Right ())
        _ → pure (Left "m.forwarded_room_key missing sender_key/session_id/session_key")
    where
        content = fromMaybe ev (lookKey "content" ev)

{- | Decrypt an @m.room.encrypted@ (Megolm) event content: look up the inbound session by
@(sender_key, session_id)@, Megolm-decrypt the ciphertext, and parse the inner event JSON.
-}
decryptMegolm ∷ Crypto → Value → IO (Either Text Value)
decryptMegolm c content =
    catchOlm $ case (lookStr "sender_key" content, lookStr "session_id" content, lookStr "ciphertext" content) of
        (Just sk, Just sid, Just ct) → do
            inbound ← readIORef (crInbound c)
            case Map.lookup (sk, sid) inbound of
                Nothing → pure (Left "no Megolm session for this (sender_key, session_id)")
                Just inb → do
                    (pt, _idx) ← groupDecrypt inb (encodeUtf8 ct)
                    pure (maybe (Left "megolm plaintext was not JSON") Right (decodeStrict pt))
        _ → pure (Left "m.room.encrypted missing sender_key/session_id/ciphertext")

-- --- outbound (sending) ----------------------------------------------------------------------------

{- | Get (creating if needed) this room's Megolm sending session; returns @(session_id, session_key)@.
The session key is what must be shared with recipients via 'roomKeyEvent' + 'olmEncryptTo'.
-}
getOrCreateOutbound ∷ Crypto → Text → IO (Text, Text)
getOrCreateOutbound c room = do
    out ← outboundFor c room
    sid ← decodeUtf8Lenient <$> outboundSessionId out
    skey ← decodeUtf8Lenient <$> outboundSessionKey out
    pure (sid, skey)

{- | This room's Megolm sending session, created on first use.

Creating one also seeds our __own__ inbound copy, keyed by our own curve25519 key. The homeserver
echoes our sends back down @\/sync@, so without it every message the bot itself sends returns as an
event it cannot decrypt — noise that is indistinguishable from a real missing key, and which would
otherwise have the gateway asking itself for a room key it already holds.
-}
outboundFor ∷ Crypto → Text → IO OutboundGroupSession
outboundFor c room = do
    outs ← readIORef (crOutbound c)
    case Map.lookup room outs of
        Just o → pure o
        Nothing → do
            o ← newOutboundGroupSession
            modifyIORef' (crOutbound c) (Map.insert room o)
            sid ← decodeUtf8Lenient <$> outboundSessionId o
            inb ← outboundSessionKey o >>= newInboundGroupSession
            modifyIORef' (crInbound c) (Map.insert (crCurve c, sid) inb)
            pure o

-- | The @m.room_key@ event body sharing @room@'s current Megolm session with recipients.
roomKeyEvent ∷ Crypto → Text → IO Value
roomKeyEvent c room = do
    (sid, skey) ← getOrCreateOutbound c room
    pure
        ( object
            [ "type" .= ("m.room_key" ∷ Text)
            , "content"
                .= object
                    [ "algorithm" .= megolmAlgorithm
                    , "room_id" .= room
                    , "session_id" .= sid
                    , "session_key" .= skey
                    ]
            ]
        )

{- | Establish (if needed) an Olm session to a peer given its curve25519 identity key and a claimed
one-time key, and Olm-encrypt @event@ for it. Returns @(message_type, ciphertext_body)@.
-}
olmEncryptTo ∷ Crypto → Text → Text → Value → IO (Int, Text)
olmEncryptTo c theirIdentityKey theirOtk event = do
    sessions ← readIORef (crOlm c)
    sess ← case Map.lookup theirIdentityKey sessions of
        Just s → pure s
        Nothing → do
            s ← createOutboundSession (crAccount c) (encodeUtf8 theirIdentityKey) (encodeUtf8 theirOtk)
            modifyIORef' (crOlm c) (Map.insert theirIdentityKey s)
            pure s
    (mtype, ct) ← encrypt sess (BL.toStrict (encode event))
    pure (mtype, decodeUtf8Lenient ct)

-- | Megolm-encrypt an inner event for @room@; returns the @m.room.encrypted@ event content.
encryptMegolm ∷ Crypto → Text → Value → IO Value
encryptMegolm c room event = do
    out ← outboundFor c room
    sid ← decodeUtf8Lenient <$> outboundSessionId out
    ct ← decodeUtf8Lenient <$> groupEncrypt out (BL.toStrict (encode event))
    pure
        ( object
            [ "algorithm" .= megolmAlgorithm
            , "sender_key" .= crCurve c
            , "session_id" .= sid
            , "device_id" .= crDeviceId c
            , "ciphertext" .= ct
            ]
        )

-- --- homeserver REST wiring ------------------------------------------------------------------------

{- | The gateway supplies this: @method → path → body → response@ (or an error). Keeping it abstract
lets the E2EE key exchange be driven against a real homeserver by the gateway, and against a mock
in tests, without this module depending on the HTTP client.
-}
type Rest = Text → Text → Value → IO (Either Text Value)

-- | Publish the bot's device keys + a batch of one-time keys (@POST \/keys\/upload@).
publishKeys ∷ Crypto → Rest → IO (Either Text ())
publishKeys c rest = do
    dk ← deviceKeysPayload c
    otk ← oneTimeKeysPayload c
    fmap (const ()) <$> rest "POST" "/_matrix/client/v3/keys/upload" (object ["device_keys" .= dk, "one_time_keys" .= otk])

{- | Top up published one-time keys when the homeserver's current count (@serverCount@, from
@/sync@'s @device_one_time_keys_count@) has fallen below half the account maximum. Generates the
shortfall and uploads a signed @one_time_keys@ batch. A no-op when the count is already healthy.
-}
replenishOtks ∷ Crypto → Rest → Int → IO (Either Text ())
replenishOtks c rest serverCount = do
    maxOtk ← maxOneTimeKeys (crAccount c)
    let target = max 1 (maxOtk `div` 2)
    if serverCount >= target
        then pure (Right ())
        else do
            generateOneTimeKeys (crAccount c) (target - serverCount)
            otk ← oneTimeKeysPayload c
            fmap (const ()) <$> rest "POST" "/_matrix/client/v3/keys/upload" (object ["one_time_keys" .= otk])

{- | Query a peer device's @(curve25519, ed25519)@ identity keys (@POST \/keys\/query@), __verifying__
the device object's Ed25519 self-signature before trusting it — an unsigned or forged key set is
rejected with a clear error rather than used to establish a session.
-}
queryDevice ∷ Rest → Text → Text → IO (Either Text (Text, Text))
queryDevice rest userId deviceId = do
    r ← rest "POST" "/_matrix/client/v3/keys/query" (object ["device_keys" .= object [K.fromText userId .= ([] ∷ [Text])]])
    case r of
        Left e → pure (Left e)
        Right resp → case lookKey "device_keys" resp >>= lookKey userId >>= lookKey deviceId of
            Nothing → pure (Left ("no device_keys." <> userId <> "." <> deviceId))
            Just dev → do
                okSig ← verifyDeviceKeys userId deviceId dev
                pure $
                    if okSig
                        then parseDeviceKeys userId deviceId resp
                        else Left ("device key signature verification failed for " <> deviceId)

-- | Claim a one-time key for a peer device (@POST \/keys\/claim@), returning its base64 value.
claimOtk ∷ Rest → Text → Text → IO (Either Text Text)
claimOtk rest userId deviceId = do
    let body = object ["one_time_keys" .= object [K.fromText userId .= object [K.fromText deviceId .= ("signed_curve25519" ∷ Text)]]]
    r ← rest "POST" "/_matrix/client/v3/keys/claim" body
    pure (r >>= parseClaimedOtk userId deviceId)

{- | Share @room@'s current Megolm session with a peer device: look up its keys, claim a one-time key,
Olm-encrypt the @m.room_key@ to it, and send it to-device (@PUT \/sendToDevice@, @txn@ supplied by
the caller). The room key must be shared before 'encryptMegolm' output is sent.
-}
shareRoomKeyWith ∷ Crypto → Rest → Text → Text → Text → Text → IO (Either Text ())
shareRoomKeyWith c rest txn room userId deviceId = do
    ek ← queryDevice rest userId deviceId
    case ek of
        Left e → pure (Left e)
        Right (curve, ed) → do
            mo ← claimOtk rest userId deviceId
            case mo of
                Left e → pure (Left e)
                Right otk → do
                    rk ← roomKeyEvent c room
                    (mtype, ctBody) ← olmEncryptTo c curve otk (olmPlaintext c userId ed rk)
                    let msg = object ["messages" .= object [K.fromText userId .= object [K.fromText deviceId .= olmEncryptedContent c curve mtype ctBody]]]
                    fmap (const ()) <$> rest "PUT" ("/_matrix/client/v3/sendToDevice/m.room.encrypted/" <> txn) msg

-- --- recovery -------------------------------------------------------------------------------------

{- | Find which of @userId@'s devices advertises the curve25519 identity key @curve@. A to-device
envelope names only the @sender_key@, but @\/keys\/claim@ and @\/sendToDevice@ are addressed by
device id, so recovering from an unreadable message means resolving one to the other. The matched
device's key object is signature-verified before it is trusted, exactly as in 'queryDevice'.
-}
findDeviceByCurve ∷ Rest → Text → Text → IO (Either Text Text)
findDeviceByCurve rest userId curve = do
    r ← rest "POST" "/_matrix/client/v3/keys/query" (object ["device_keys" .= object [K.fromText userId .= ([] ∷ [Text])]])
    case r of
        Left e → pure (Left e)
        Right resp → case lookKey "device_keys" resp >>= lookKey userId of
            Just (Object o) →
                case [(K.toText k, dev) | (k, dev) ← KM.toList o, (lookKey "keys" dev >>= lookStr ("curve25519:" <> K.toText k)) == Just curve] of
                    ((deviceId, dev) : _) → do
                        okSig ← verifyDeviceKeys userId deviceId dev
                        pure $
                            if okSig
                                then Right deviceId
                                else Left ("device key signature verification failed for " <> deviceId)
                    [] → pure (Left ("no device of " <> userId <> " advertises curve25519 key " <> curve))
            _ → pure (Left ("no device_keys." <> userId))

{- | Force a peer device to replace a stale Olm session by sending it an @m.dummy@ over a __fresh__
one. Receiving a PRE_KEY message is what makes a peer discard the session it was using, so its next
to-device message arrives on a channel we can read; without this, a peer that still holds a session
we lost keeps sending type-1 messages forever and the gateway is permanently deaf to it.

Mechanically 'shareRoomKeyWith' with a different inner event, save for the fresh session: reusing
the stored one would emit another type-1 message and repair nothing. Rate-limiting is the caller's
(each call costs a @\/keys\/claim@).
-}
sendDummyTo ∷ Crypto → Rest → Text → Text → Text → IO (Either Text ())
sendDummyTo c rest txn userId deviceId = catchOlm $ do
    ek ← queryDevice rest userId deviceId
    case ek of
        Left e → pure (Left e)
        Right (curve, ed) → do
            mo ← claimOtk rest userId deviceId
            case mo of
                Left e → pure (Left e)
                Right otk → do
                    let dummy = object ["type" .= ("m.dummy" ∷ Text), "content" .= object []]
                    (mtype, ctBody) ← olmEncryptFresh c curve otk (olmPlaintext c userId ed dummy)
                    let msg = object ["messages" .= object [K.fromText userId .= object [K.fromText deviceId .= olmEncryptedContent c curve mtype ctBody]]]
                    fmap (const ()) <$> rest "PUT" ("/_matrix/client/v3/sendToDevice/m.room.encrypted/" <> txn) msg

{- | Olm-encrypt @event@ over a __newly created__ outbound session, replacing any stored one for that
peer. The deliberate opposite of 'olmEncryptTo': this is the unwedge path, where the stored session
is precisely what is suspect.
-}
olmEncryptFresh ∷ Crypto → Text → Text → Value → IO (Int, Text)
olmEncryptFresh c theirIdentityKey theirOtk event = do
    s ← createOutboundSession (crAccount c) (encodeUtf8 theirIdentityKey) (encodeUtf8 theirOtk)
    modifyIORef' (crOlm c) (Map.insert theirIdentityKey s)
    (mtype, ct) ← encrypt s (BL.toStrict (encode event))
    pure (mtype, decodeUtf8Lenient ct)

{- | Ask every device of @userId@ to re-send the Megolm session @sessionId@ (created by @senderKey@ in
@room@), as an unencrypted @m.room_key_request@ to-device event.

Repairing the Olm channel is __not sufficient__ on its own: the peer believes it already delivered
the key for its current session and will not re-share it, so without a request the gateway stays
deaf to that room until the peer happens to rotate — by default up to a week. The reply arrives as
an @m.forwarded_room_key@ ('storeForwardedRoomKey'). The session id doubles as the @request_id@ so
'cancelRoomKeyRequest' needs no extra bookkeeping.
-}
requestRoomKey ∷ Crypto → Rest → Text → Text → Text → Text → Text → IO (Either Text ())
requestRoomKey c rest txn userId room senderKey sid =
    sendToDeviceAll rest txn userId "m.room_key_request" $
        object
            [ "action" .= ("request" ∷ Text)
            , "requesting_device_id" .= crDeviceId c
            , "request_id" .= sid
            , "body"
                .= object
                    [ "algorithm" .= megolmAlgorithm
                    , "room_id" .= room
                    , "sender_key" .= senderKey
                    , "session_id" .= sid
                    ]
            ]

-- | Withdraw an outstanding 'requestRoomKey' once the key has arrived, so peers stop being asked.
cancelRoomKeyRequest ∷ Crypto → Rest → Text → Text → Text → IO (Either Text ())
cancelRoomKeyRequest c rest txn userId requestId =
    sendToDeviceAll rest txn userId "m.room_key_request" $
        object
            [ "action" .= ("request_cancellation" ∷ Text)
            , "requesting_device_id" .= crDeviceId c
            , "request_id" .= requestId
            ]

-- | @PUT \/sendToDevice\/{type}\/{txn}@ addressed to every device of @userId@ (the @"*"@ wildcard).
sendToDeviceAll ∷ Rest → Text → Text → Text → Value → IO (Either Text ())
sendToDeviceAll rest txn userId evType content =
    fmap (const ())
        <$> rest
            "PUT"
            ("/_matrix/client/v3/sendToDevice/" <> evType <> "/" <> txn)
            (object ["messages" .= object [K.fromText userId .= object ["*" .= content]]])

{- | Wrap an inner to-device event (@{type, content}@) in the Matrix Olm plaintext envelope the spec
requires: @sender@\/@sender_device@\/@keys@ (ours) and @recipient@\/@recipient_keys@ (the peer's).
A receiver (e.g. matrix-nio) rejects a room key that lacks these, so the peer could not decrypt.
-}
olmPlaintext ∷ Crypto → Text → Text → Value → Value
olmPlaintext c recipient recipientEd inner =
    object
        [ "type" .= lk "type"
        , "content" .= lk "content"
        , "sender" .= crUserId c
        , "sender_device" .= crDeviceId c
        , "keys" .= object ["ed25519" .= crEd c]
        , "recipient" .= recipient
        , "recipient_keys" .= object ["ed25519" .= recipientEd]
        ]
    where
        lk k = fromMaybe Null (lookKey k inner)

-- | The to-device @m.room.encrypted@ (Olm) content wrapping a ciphertext for a peer's curve25519 key.
olmEncryptedContent ∷ Crypto → Text → Int → Text → Value
olmEncryptedContent c theirCurve mtype ctBody =
    object
        [ "algorithm" .= olmAlgorithm
        , "sender_key" .= crCurve c
        , "ciphertext" .= object [K.fromText theirCurve .= object ["type" .= mtype, "body" .= ctBody]]
        ]

-- | Parse a peer device's @(curve25519, ed25519)@ identity keys from a @\/keys\/query@ response.
parseDeviceKeys ∷ Text → Text → Value → Either Text (Text, Text)
parseDeviceKeys userId deviceId resp = do
    keys ← note "no device_keys.<user>.<device>.keys" (lookKey "device_keys" resp >>= lookKey userId >>= lookKey deviceId >>= lookKey "keys")
    curve ← note "no curve25519 key" (lookStr ("curve25519:" <> deviceId) keys)
    ed ← note "no ed25519 key" (lookStr ("ed25519:" <> deviceId) keys)
    pure (curve, ed)

-- | Parse the claimed one-time key's base64 value from a @\/keys\/claim@ response.
parseClaimedOtk ∷ Text → Text → Value → Either Text Text
parseClaimedOtk userId deviceId resp = do
    dev ← note "no one_time_keys.<user>.<device>" (lookKey "one_time_keys" resp >>= lookKey userId >>= lookKey deviceId)
    case dev of
        Object o → case [v | (k, v) ← KM.toList o, "signed_curve25519:" `T.isPrefixOf` K.toText k] of
            (keyObj : _) → note "claimed key has no `key`" (lookStr "key" keyObj)
            [] → Left "no signed_curve25519 key in claim response"
        _ → Left "claim response device entry was not an object"

note ∷ Text → Maybe a → Either Text a
note e = maybe (Left e) Right

-- --- JSON helpers ----------------------------------------------------------------------------------

lookKey ∷ Text → Value → Maybe Value
lookKey k (Object o) = KM.lookup (K.fromText k) o
lookKey _ _ = Nothing

lookStr ∷ Text → Value → Maybe Text
lookStr k v = case lookKey k v of
    Just (String s) → Just s
    _ → Nothing

-- | A required top-level string field of libolm's identity-keys JSON.
jField ∷ Text → ByteString → Text
jField k bs = case decodeStrict bs of
    Just v → maybe (error ("e2ee: identity key field " <> T.unpack k <> " missing")) id (lookStr k v)
    Nothing → error "e2ee: identity keys were not JSON"

-- | The first value of libolm's @{"curve25519":{id:key,…}}@ one-time-keys JSON.
firstCurveValue ∷ ByteString → Maybe Text
firstCurveValue bs = do
    v ← decodeStrict bs
    Object keys ← lookKey "curve25519" v
    listToMaybe [s | String s ← KM.elems keys]

-- | The @(keyId, keyValue)@ entries of the curve25519 one-time-keys JSON.
curveEntries ∷ ByteString → [(Text, Text)]
curveEntries bs = case decodeStrict bs >>= lookKey "curve25519" of
    Just (Object keys) → [(K.toText k, s) | (k, String s) ← KM.toList keys]
    _ → []
