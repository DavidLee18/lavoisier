module Main (main) where

import Crypto.Olm
import Data.Aeson (Value (..), decodeStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "olm (libolm FFI)"
    [ testCase "an account exposes curve25519 + ed25519 identity keys" $ do
        acc <- newAccount
        idk <- identityKeys acc
        assertBool "curve25519 present" ("curve25519" `BS.isInfixOf` idk)
        assertBool "ed25519 present" ("ed25519" `BS.isInfixOf` idk),
      testCase "an Olm 1:1 session round-trips a message" $ do
        alice <- newAccount
        bob <- newAccount
        bobIdk <- identityKeys bob
        generateOneTimeKeys bob 1
        bobOtks <- oneTimeKeys bob
        let bobCurve = objField "curve25519" bobIdk
            bobOtk = firstOtk bobOtks
        out <- createOutboundSession alice bobCurve bobOtk
        (mtype, ct) <- encrypt out "hello bob"
        mtype @?= 0 -- the first message is a PRE_KEY message
        inb <- createInboundSession bob ct
        pt <- decrypt inb mtype ct
        pt @?= "hello bob"
        -- a reply on the now-established session decrypts too
        (rtype, rct) <- encrypt inb "hi alice"
        decrypt out rtype rct >>= (@?= "hi alice"),
      testCase "a Megolm group session round-trips a message" $ do
        out <- newOutboundGroupSession
        key <- outboundSessionKey out
        inb <- newInboundGroupSession key
        ct <- groupEncrypt out "room message"
        (pt, idx) <- groupDecrypt inb ct
        pt @?= "room message"
        idx @?= 0
        -- session ids match between the two halves
        oid <- outboundSessionId out
        iid <- inboundSessionId inb
        oid @?= iid,
      testCase "Ed25519 sign/verify (and rejects tampering)" $ do
        acc <- newAccount
        idk <- identityKeys acc
        let ed = objField "ed25519" idk
        sig <- sign acc "the message"
        util <- newUtility
        ed25519Verify util ed "the message" sig >>= (@?= True)
        ed25519Verify util ed "a different message" sig >>= (@?= False),
      testCase "SHA-256 is deterministic and length-stable" $ do
        util <- newUtility
        a <- sha256 util "lavoisier"
        b <- sha256 util "lavoisier"
        a @?= b
        c <- sha256 util "different"
        assertBool "distinct inputs differ" (a /= c),
      testCase "pickling an account round-trips its identity" $ do
        acc <- newAccount
        idk <- identityKeys acc
        pick <- pickleAccount acc "storekey"
        restored <- unpickleAccount "storekey" pick
        identityKeys restored >>= (@?= idk)
    ]

-- Extract a top-level string field from libolm's identity-keys JSON.
objField :: Text -> ByteString -> ByteString
objField k bs = case decodeStrict bs of
  Just (Object o) -> case KM.lookup (K.fromText k) o of
    Just (String s) -> encodeUtf8 s
    _ -> error ("olm test: field " <> show k <> " missing")
  _ -> error "olm test: not a JSON object"

-- Extract the first one-time key value from `{"curve25519":{id:key,...}}`.
firstOtk :: ByteString -> ByteString
firstOtk bs = case decodeStrict bs of
  Just (Object o) -> case KM.lookup "curve25519" o of
    Just (Object keys) -> case KM.elems keys of
      (String s : _) -> encodeUtf8 s
      _ -> error "olm test: no one-time keys"
    _ -> error "olm test: curve25519 map missing"
  _ -> error "olm test: not a JSON object"
