{- | A safe, 'ByteString'-based wrapper over the libolm FFI ("Crypto.Olm.FFI"). Objects are managed
'ForeignPtr's cleared + freed on GC; randomness is drawn from @\/dev\/urandom@; calls that libolm
documents as overwriting their input buffer are given a private copy.

Covers what Matrix E2EE needs: an 'Account' (identity + one-time + fallback keys, signing), 1:1
'Session's (Olm ratchet: encrypt\/decrypt), Megolm group sessions ('OutboundGroupSession' /
'InboundGroupSession'), the 'Utility' (Ed25519 verify, SHA-256), and pickling for durable storage.
-}
module Crypto.Olm (
    -- * Account
    Account,
    newAccount,
    identityKeys,
    sign,
    maxOneTimeKeys,
    generateOneTimeKeys,
    oneTimeKeys,
    markKeysAsPublished,
    generateFallbackKey,
    unpublishedFallbackKey,
    pickleAccount,
    unpickleAccount,

    -- * Olm 1:1 sessions
    Session,
    createOutboundSession,
    createInboundSession,
    createInboundSessionFrom,
    sessionId,
    matchesInboundSession,
    removeOneTimeKeys,
    encrypt,
    decrypt,
    pickleSession,
    unpickleSession,

    -- * Megolm group sessions
    OutboundGroupSession,
    newOutboundGroupSession,
    outboundSessionId,
    outboundSessionKey,
    outboundMessageIndex,
    groupEncrypt,
    pickleOutbound,
    unpickleOutbound,
    InboundGroupSession,
    newInboundGroupSession,
    importInboundGroupSession,
    inboundSessionId,
    groupDecrypt,
    exportInboundGroupSession,
    firstKnownIndex,
    pickleInbound,
    unpickleInbound,

    -- * Utility
    Utility,
    newUtility,
    sha256,
    ed25519Verify,
)
where

import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.Word (Word32)
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CSize)
import Foreign.ForeignPtr (ForeignPtr, withForeignPtr)
import Foreign.Marshal.Alloc (alloca, allocaBytes, free, mallocBytes)
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Ptr (Ptr, castPtr, nullPtr)
import Foreign.Storable (peek)
import System.IO (IOMode (ReadMode), hGetBuf, withBinaryFile)

import Data.ByteString qualified as BS
import Foreign.Concurrent qualified as FC

import Crypto.Olm.FFI

-- | The libolm error sentinel (@olm_error()@ = @SIZE_MAX@).
olmError ∷ CSize
olmError = maxBound

-- --- object lifetime + error handling --------------------------------------------------------------

{- | Allocate a libolm object into fresh memory, initialise it, and wrap it in a 'ForeignPtr' whose
finalizer clears (zeroes) then frees the backing memory.
-}
newObject ∷ IO CSize → (Ptr () → IO (Ptr a)) → (Ptr a → IO CSize) → IO (ForeignPtr a)
newObject sizeF initF clearF = do
    sz ← sizeF
    mem ← mallocBytes (fromIntegral sz) ∷ IO (Ptr ())
    p ← initF mem
    FC.newForeignPtr p (clearF p >> free mem)

{- | Fail (as an IO exception) when a libolm call returned the error sentinel, using its
object-specific @last_error@ string.
-}
check ∷ IO CString → CSize → IO ()
check errF r
    | r == olmError = do
        msg ← errF >>= peekCString
        ioError (userError ("olm: " <> msg))
    | otherwise = pure ()

-- | Run @act@ with a buffer of @n@ fresh random bytes (from @\/dev\/urandom@); libolm may zero it.
withRandom ∷ Int → (Ptr () → CSize → IO a) → IO a
withRandom n act
    | n <= 0 = act nullPtr 0
    | otherwise = allocaBytes n $ \buf → do
        withBinaryFile "/dev/urandom" ReadMode $ \h → do
            got ← hGetBuf h buf n
            when (got < n) (ioError (userError "olm: short read from /dev/urandom"))
        act (castPtr (buf ∷ Ptr ())) (fromIntegral n)

-- | Run @act@ with a __writable__ copy of @bs@ (for libolm calls that overwrite their input).
withCopy ∷ ByteString → (Ptr () → CSize → IO a) → IO a
withCopy bs act = BS.useAsCStringLen bs $ \(src, n) →
    allocaBytes n $ \dst → do
        copyBytes dst (castPtr src) n
        act (castPtr (dst ∷ Ptr ())) (fromIntegral n)

-- | The common "size then fill a full-length buffer" reader (base64 key\/id\/pickle output).
produce ∷ (Ptr a → IO CSize) → (Ptr a → Ptr () → CSize → IO CSize) → (Ptr a → IO CString) → ForeignPtr a → IO ByteString
produce lenF writeF errF fp = withForeignPtr fp $ \p → do
    len ← lenF p
    allocaBytes (fromIntegral len) $ \out → do
        r ← writeF p out len
        check (errF p) r
        BS.packCStringLen (castPtr out, fromIntegral len)

-- --- Account ---------------------------------------------------------------------------------------

-- | An Olm account: the device's long-term Curve25519\/Ed25519 identity plus its one-time keys.
newtype Account = Account (ForeignPtr OlmAccount)

-- | Create a fresh account with a random identity.
newAccount ∷ IO Account
newAccount = do
    fp ← newObject olm_account_size olm_account olm_clear_account
    withForeignPtr fp $ \p → do
        rlen ← olm_create_account_random_length p
        withRandom (fromIntegral rlen) $ \rp rl →
            olm_create_account p rp rl >>= check (olm_account_last_error p)
    pure (Account fp)

-- | The account's identity keys as libolm's JSON (@{"curve25519":…,"ed25519":…}@).
identityKeys ∷ Account → IO ByteString
identityKeys (Account fp) = produce olm_account_identity_keys_length olm_account_identity_keys olm_account_last_error fp

-- | Sign @message@ with the account's Ed25519 key (base64 signature).
sign ∷ Account → ByteString → IO ByteString
sign (Account fp) message = withForeignPtr fp $ \p →
    BS.useAsCStringLen message $ \(mp, ml) → do
        slen ← olm_account_signature_length p
        allocaBytes (fromIntegral slen) $ \sig → do
            r ← olm_account_sign p (castPtr mp) (fromIntegral ml) sig slen
            check (olm_account_last_error p) r
            BS.packCStringLen (castPtr sig, fromIntegral slen)

-- | The maximum number of one-time keys the account can hold.
maxOneTimeKeys ∷ Account → IO Int
maxOneTimeKeys (Account fp) = withForeignPtr fp (fmap fromIntegral . olm_account_max_number_of_one_time_keys)

-- | Generate @n@ new one-time keys (call 'oneTimeKeys' to read them, 'markKeysAsPublished' after upload).
generateOneTimeKeys ∷ Account → Int → IO ()
generateOneTimeKeys (Account fp) n = withForeignPtr fp $ \p → do
    rlen ← olm_account_generate_one_time_keys_random_length p (fromIntegral n)
    withRandom (fromIntegral rlen) $ \rp rl →
        olm_account_generate_one_time_keys p (fromIntegral n) rp rl >>= check (olm_account_last_error p)

-- | The account's unpublished one-time keys as libolm JSON (@{"curve25519":{id:key,…}}@).
oneTimeKeys ∷ Account → IO ByteString
oneTimeKeys (Account fp) = produce olm_account_one_time_keys_length olm_account_one_time_keys olm_account_last_error fp

-- | Mark the current one-time keys as published (so they are not returned again).
markKeysAsPublished ∷ Account → IO ()
markKeysAsPublished (Account fp) = withForeignPtr fp $ \p →
    olm_account_mark_keys_as_published p >>= check (olm_account_last_error p)

-- | Generate a new fallback key (used when a peer has no unclaimed one-time key).
generateFallbackKey ∷ Account → IO ()
generateFallbackKey (Account fp) = withForeignPtr fp $ \p → do
    rlen ← olm_account_generate_fallback_key_random_length p
    withRandom (fromIntegral rlen) $ \rp rl →
        olm_account_generate_fallback_key p rp rl >>= check (olm_account_last_error p)

-- | The unpublished fallback key as libolm JSON.
unpublishedFallbackKey ∷ Account → IO ByteString
unpublishedFallbackKey (Account fp) =
    produce olm_account_unpublished_fallback_key_length olm_account_unpublished_fallback_key olm_account_last_error fp

-- | Serialise the account, encrypted with @key@ (durable storage).
pickleAccount ∷ Account → ByteString → IO ByteString
pickleAccount (Account fp) key = pickleWith olm_pickle_account_length olm_pickle_account olm_account_last_error fp key

-- | Restore an account from 'pickleAccount' output with the same @key@.
unpickleAccount ∷ ByteString → ByteString → IO Account
unpickleAccount key pickled = do
    fp ← newObject olm_account_size olm_account olm_clear_account
    unpickleWith olm_unpickle_account olm_account_last_error fp key pickled
    pure (Account fp)

-- --- Olm 1:1 sessions ------------------------------------------------------------------------------

-- | An Olm session: the encrypted 1:1 channel between two devices (used to share Megolm keys).
newtype Session = Session (ForeignPtr OlmSession)

-- | Start an outbound session to a device given its Curve25519 identity key and one claimed one-time key.
createOutboundSession ∷ Account → ByteString → ByteString → IO Session
createOutboundSession (Account afp) theirIdentityKey theirOneTimeKey = do
    fp ← newObject olm_session_size olm_session olm_clear_session
    withForeignPtr fp $ \s → withForeignPtr afp $ \a →
        BS.useAsCStringLen theirIdentityKey $ \(ik, ikl) →
            BS.useAsCStringLen theirOneTimeKey $ \(ok, okl) → do
                rlen ← olm_create_outbound_session_random_length s
                withRandom (fromIntegral rlen) $ \rp rl →
                    olm_create_outbound_session s a (castPtr ik) (fromIntegral ikl) (castPtr ok) (fromIntegral okl) rp rl
                        >>= check (olm_session_last_error s)
    pure (Session fp)

-- | Start an inbound session from a received PRE_KEY message.
createInboundSession ∷ Account → ByteString → IO Session
createInboundSession (Account afp) preKeyMessage = do
    fp ← newObject olm_session_size olm_session olm_clear_session
    withForeignPtr fp $ \s → withForeignPtr afp $ \a →
        withCopy preKeyMessage $ \mp ml →
            olm_create_inbound_session s a mp ml >>= check (olm_session_last_error s)
    pure (Session fp)

-- | Start an inbound session from a PRE_KEY message, checking it came from @theirIdentityKey@.
createInboundSessionFrom ∷ Account → ByteString → ByteString → IO Session
createInboundSessionFrom (Account afp) theirIdentityKey preKeyMessage = do
    fp ← newObject olm_session_size olm_session olm_clear_session
    withForeignPtr fp $ \s → withForeignPtr afp $ \a →
        BS.useAsCStringLen theirIdentityKey $ \(ik, ikl) →
            withCopy preKeyMessage $ \mp ml →
                olm_create_inbound_session_from s a (castPtr ik) (fromIntegral ikl) mp ml
                    >>= check (olm_session_last_error s)
    pure (Session fp)

-- | The session's identity (base64).
sessionId ∷ Session → IO ByteString
sessionId (Session fp) = produce olm_session_id_length olm_session_id olm_session_last_error fp

-- | Whether a received PRE_KEY message would establish this same inbound session.
matchesInboundSession ∷ Session → ByteString → IO Bool
matchesInboundSession (Session fp) preKeyMessage = withForeignPtr fp $ \s →
    withCopy preKeyMessage $ \mp ml → (== 1) <$> olm_matches_inbound_session s mp ml

-- | Remove the account's one-time key used to establish @session@ (after a successful inbound session).
removeOneTimeKeys ∷ Account → Session → IO ()
removeOneTimeKeys (Account afp) (Session sfp) =
    withForeignPtr afp $ \a → withForeignPtr sfp $ \s →
        olm_remove_one_time_keys a s >>= check (olm_account_last_error a)

-- | Encrypt @plaintext@; returns the message type (0 = PRE_KEY, 1 = normal) and the ciphertext.
encrypt ∷ Session → ByteString → IO (Int, ByteString)
encrypt (Session fp) plaintext = withForeignPtr fp $ \s → do
    mtype ← olm_encrypt_message_type s
    BS.useAsCStringLen plaintext $ \(pt, ptl) → do
        mlen ← olm_encrypt_message_length s (fromIntegral ptl)
        rlen ← olm_encrypt_random_length s
        withRandom (fromIntegral rlen) $ \rp rl →
            allocaBytes (fromIntegral mlen) $ \out → do
                r ← olm_encrypt s (castPtr pt) (fromIntegral ptl) rp rl out mlen
                check (olm_session_last_error s) r
                ct ← BS.packCStringLen (castPtr out, fromIntegral mlen)
                pure (fromIntegral mtype, ct)

-- | Decrypt a message of the given type. The ciphertext is copied twice (libolm overwrites it).
decrypt ∷ Session → Int → ByteString → IO ByteString
decrypt (Session fp) mtype ciphertext = withForeignPtr fp $ \s → do
    maxLen ← withCopy ciphertext $ \cp cl → olm_decrypt_max_plaintext_length s (fromIntegral mtype) cp cl
    check (olm_session_last_error s) maxLen
    withCopy ciphertext $ \cp cl →
        allocaBytes (fromIntegral maxLen) $ \out → do
            n ← olm_decrypt s (fromIntegral mtype) cp cl out maxLen
            check (olm_session_last_error s) n
            BS.packCStringLen (castPtr out, fromIntegral n)

-- | Serialise the session, encrypted with @key@.
pickleSession ∷ Session → ByteString → IO ByteString
pickleSession (Session fp) key = pickleWith olm_pickle_session_length olm_pickle_session olm_session_last_error fp key

-- | Restore a session from 'pickleSession' output.
unpickleSession ∷ ByteString → ByteString → IO Session
unpickleSession key pickled = do
    fp ← newObject olm_session_size olm_session olm_clear_session
    unpickleWith olm_unpickle_session olm_session_last_error fp key pickled
    pure (Session fp)

-- --- Megolm group sessions -------------------------------------------------------------------------

{- | A Megolm outbound group session: the sender's ratchet for a room. Its 'outboundSessionKey' is
shared (over Olm) with recipients so they can build a matching 'InboundGroupSession'.
-}
newtype OutboundGroupSession = OutboundGroupSession (ForeignPtr OlmOutboundGroupSession)

-- | Create a fresh outbound group session.
newOutboundGroupSession ∷ IO OutboundGroupSession
newOutboundGroupSession = do
    fp ← newObject olm_outbound_group_session_size olm_outbound_group_session olm_clear_outbound_group_session
    withForeignPtr fp $ \s → do
        rlen ← olm_init_outbound_group_session_random_length s
        withRandom (fromIntegral rlen) $ \rp rl →
            olm_init_outbound_group_session s rp rl >>= check (olm_outbound_group_session_last_error s)
    pure (OutboundGroupSession fp)

-- | The session identity (base64), used as @session_id@ on @m.room.encrypted@ events.
outboundSessionId ∷ OutboundGroupSession → IO ByteString
outboundSessionId (OutboundGroupSession fp) =
    produce olm_outbound_group_session_id_length olm_outbound_group_session_id olm_outbound_group_session_last_error fp

-- | The current session key to share with recipients (its value changes as the ratchet advances).
outboundSessionKey ∷ OutboundGroupSession → IO ByteString
outboundSessionKey (OutboundGroupSession fp) =
    produce olm_outbound_group_session_key_length olm_outbound_group_session_key olm_outbound_group_session_last_error fp

-- | The next message index the session will emit.
outboundMessageIndex ∷ OutboundGroupSession → IO Int
outboundMessageIndex (OutboundGroupSession fp) =
    withForeignPtr fp (fmap fromIntegral . olm_outbound_group_session_message_index)

-- | Megolm-encrypt @plaintext@ (the ciphertext body of an @m.room.encrypted@ event).
groupEncrypt ∷ OutboundGroupSession → ByteString → IO ByteString
groupEncrypt (OutboundGroupSession fp) plaintext = withForeignPtr fp $ \s →
    BS.useAsCStringLen plaintext $ \(pt, ptl) → do
        mlen ← olm_group_encrypt_message_length s (fromIntegral ptl)
        allocaBytes (fromIntegral mlen) $ \out → do
            r ← olm_group_encrypt s (castPtr pt) (fromIntegral ptl) out mlen
            check (olm_outbound_group_session_last_error s) r
            BS.packCStringLen (castPtr out, fromIntegral mlen)

-- | Serialise the outbound group session, encrypted with @key@.
pickleOutbound ∷ OutboundGroupSession → ByteString → IO ByteString
pickleOutbound (OutboundGroupSession fp) key =
    pickleWith olm_pickle_outbound_group_session_length olm_pickle_outbound_group_session olm_outbound_group_session_last_error fp key

-- | Restore an outbound group session.
unpickleOutbound ∷ ByteString → ByteString → IO OutboundGroupSession
unpickleOutbound key pickled = do
    fp ← newObject olm_outbound_group_session_size olm_outbound_group_session olm_clear_outbound_group_session
    unpickleWith olm_unpickle_outbound_group_session olm_outbound_group_session_last_error fp key pickled
    pure (OutboundGroupSession fp)

-- | A Megolm inbound group session: a recipient's decrypt ratchet, built from a shared session key.
newtype InboundGroupSession = InboundGroupSession (ForeignPtr OlmInboundGroupSession)

-- | Build an inbound group session from a session key (as produced by 'outboundSessionKey').
newInboundGroupSession ∷ ByteString → IO InboundGroupSession
newInboundGroupSession sessionKey = do
    fp ← newObject olm_inbound_group_session_size olm_inbound_group_session olm_clear_inbound_group_session
    withForeignPtr fp $ \s →
        BS.useAsCStringLen sessionKey $ \(kp, kl) →
            olm_init_inbound_group_session s (castPtr kp) (fromIntegral kl) >>= check (olm_inbound_group_session_last_error s)
    pure (InboundGroupSession fp)

-- | Build an inbound group session from an __exported__ key (as produced by 'exportInboundGroupSession').
importInboundGroupSession ∷ ByteString → IO InboundGroupSession
importInboundGroupSession exportedKey = do
    fp ← newObject olm_inbound_group_session_size olm_inbound_group_session olm_clear_inbound_group_session
    withForeignPtr fp $ \s →
        withCopy exportedKey $ \kp kl →
            olm_import_inbound_group_session s kp kl >>= check (olm_inbound_group_session_last_error s)
    pure (InboundGroupSession fp)

-- | The session identity (base64).
inboundSessionId ∷ InboundGroupSession → IO ByteString
inboundSessionId (InboundGroupSession fp) =
    produce olm_inbound_group_session_id_length olm_inbound_group_session_id olm_inbound_group_session_last_error fp

-- | Megolm-decrypt a message; returns the plaintext and its ratchet message index.
groupDecrypt ∷ InboundGroupSession → ByteString → IO (ByteString, Int)
groupDecrypt (InboundGroupSession fp) message = withForeignPtr fp $ \s → do
    maxLen ← withCopy message $ \mp ml → olm_group_decrypt_max_plaintext_length s mp ml
    check (olm_inbound_group_session_last_error s) maxLen
    withCopy message $ \mp ml →
        allocaBytes (fromIntegral maxLen) $ \out →
            alloca $ \idxPtr → do
                n ← olm_group_decrypt s mp ml out maxLen idxPtr
                check (olm_inbound_group_session_last_error s) n
                idx ← peek idxPtr ∷ IO Word32
                pt ← BS.packCStringLen (castPtr out, fromIntegral n)
                pure (pt, fromIntegral idx)

-- | Export the session key at its first known ratchet index (for key backup\/sharing).
exportInboundGroupSession ∷ InboundGroupSession → IO ByteString
exportInboundGroupSession (InboundGroupSession fp) = withForeignPtr fp $ \s → do
    len ← olm_export_inbound_group_session_length s
    idx ← olm_inbound_group_session_first_known_index s
    allocaBytes (fromIntegral len) $ \out → do
        r ← olm_export_inbound_group_session s out len idx
        check (olm_inbound_group_session_last_error s) r
        BS.packCStringLen (castPtr out, fromIntegral len)

-- | The first ratchet index this session can decrypt.
firstKnownIndex ∷ InboundGroupSession → IO Int
firstKnownIndex (InboundGroupSession fp) =
    withForeignPtr fp (fmap fromIntegral . olm_inbound_group_session_first_known_index)

-- | Serialise the inbound group session, encrypted with @key@.
pickleInbound ∷ InboundGroupSession → ByteString → IO ByteString
pickleInbound (InboundGroupSession fp) key =
    pickleWith olm_pickle_inbound_group_session_length olm_pickle_inbound_group_session olm_inbound_group_session_last_error fp key

-- | Restore an inbound group session.
unpickleInbound ∷ ByteString → ByteString → IO InboundGroupSession
unpickleInbound key pickled = do
    fp ← newObject olm_inbound_group_session_size olm_inbound_group_session olm_clear_inbound_group_session
    unpickleWith olm_unpickle_inbound_group_session olm_inbound_group_session_last_error fp key pickled
    pure (InboundGroupSession fp)

-- --- Utility ---------------------------------------------------------------------------------------

-- | A libolm utility handle for Ed25519 verification and SHA-256.
newtype Utility = Utility (ForeignPtr OlmUtility)

-- | Create a utility.
newUtility ∷ IO Utility
newUtility = Utility <$> newObject olm_utility_size olm_utility olm_clear_utility

-- | SHA-256 of @input@ as unpadded base64.
sha256 ∷ Utility → ByteString → IO ByteString
sha256 (Utility fp) input = withForeignPtr fp $ \u →
    BS.useAsCStringLen input $ \(ip, il) → do
        len ← olm_sha256_length u
        allocaBytes (fromIntegral len) $ \out → do
            r ← olm_sha256 u (castPtr ip) (fromIntegral il) out len
            check (olm_utility_last_error u) r
            BS.packCStringLen (castPtr out, fromIntegral len)

-- | Verify an Ed25519 @signature@ of @message@ under @key@ (all base64). 'True' iff valid.
ed25519Verify ∷ Utility → ByteString → ByteString → ByteString → IO Bool
ed25519Verify (Utility fp) key message signature = withForeignPtr fp $ \u →
    BS.useAsCStringLen key $ \(kp, kl) →
        BS.useAsCStringLen message $ \(mp, ml) →
            withCopy signature $ \sp sl →
                (== 0) <$> olm_ed25519_verify u (castPtr kp) (fromIntegral kl) (castPtr mp) (fromIntegral ml) sp sl

-- --- pickle helpers (shared shape) -----------------------------------------------------------------

pickleWith ∷ (Ptr a → IO CSize) → (Ptr a → Ptr () → CSize → Ptr () → CSize → IO CSize) → (Ptr a → IO CString) → ForeignPtr a → ByteString → IO ByteString
pickleWith lenF pickleF errF fp key = withForeignPtr fp $ \p →
    BS.useAsCStringLen key $ \(kp, kl) → do
        len ← lenF p
        allocaBytes (fromIntegral len) $ \out → do
            r ← pickleF p (castPtr kp) (fromIntegral kl) out len
            check (errF p) r
            BS.packCStringLen (castPtr out, fromIntegral len)

unpickleWith ∷ (Ptr a → Ptr () → CSize → Ptr () → CSize → IO CSize) → (Ptr a → IO CString) → ForeignPtr a → ByteString → ByteString → IO ()
unpickleWith unpickleF errF fp key pickled = withForeignPtr fp $ \p →
    BS.useAsCStringLen key $ \(kp, kl) →
        withCopy pickled $ \pp pl →
            unpickleF p (castPtr kp) (fromIntegral kl) pp pl >>= check (errF p)
