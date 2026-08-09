module Main (main) where

import Crypto.Olm (ed25519Verify, newUtility)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Lavoisier.Gateway.Matrix.E2ee
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "matrix e2ee (Olm/Megolm over libolm)"
    [ testCase "device_keys are signed with the account's ed25519 key" $ do
        c <- newCrypto "@bot:hs" "BOTDEV"
        (_, ed) <- cryptoIdentityKeys c
        dk <- deviceKeysPayload c
        -- the signature verifies over the canonical JSON of the object minus its `signatures`
        let sig = sigOf "@bot:hs" "ed25519:BOTDEV" dk
            signable = canonicalJson (stripSignatures dk)
        util <- newUtility
        ed25519Verify util (encodeUtf8 ed) signable (encodeUtf8 sig) >>= (@?= True)
        -- a tampered body no longer verifies
        ed25519Verify util (encodeUtf8 ed) (signable <> " ") (encodeUtf8 sig) >>= (@?= False),
      testCase "canonicalJson sorts object keys and drops whitespace" $
        canonicalJson (object ["b" .= (1 :: Int), "a" .= object ["y" .= t "2", "x" .= t "1"]])
          @?= "{\"a\":{\"x\":\"1\",\"y\":\"2\"},\"b\":1}",
      testCase "a room key shared over Olm decrypts the room's Megolm messages" $ do
        -- alice is the sender, bob the bot. Both hold real Olm accounts.
        alice <- newCrypto "@alice:hs" "ALICEDEV"
        bob <- newCrypto "@bob:hs" "BOTDEV"
        (bobCurve, _) <- cryptoIdentityKeys bob
        (aliceCurve, _) <- cryptoIdentityKeys alice
        Just bobOtk <- takeOneTimeKey bob

        -- alice creates the room's Megolm session and shares its key to bob over a 1:1 Olm message.
        rk <- roomKeyEvent alice "!room:hs"
        (mtype, olmBody) <- olmEncryptTo alice bobCurve bobOtk rk

        -- bob decrypts the Olm message and stores the room key.
        eRoomKey <- decryptOlm bob aliceCurve mtype olmBody
        case eRoomKey of
          Left e -> assertFailure ("olm decrypt failed: " <> show e)
          Right decoded -> do
            typeOf decoded @?= Just "m.room_key"
            storeRoomKey bob aliceCurve decoded >>= (@?= Right ())

        -- alice Megolm-encrypts a room message; bob decrypts it with the shared session.
        let inner =
              object
                [ "type" .= t "m.room.message",
                  "room_id" .= t "!room:hs",
                  "content" .= object ["msgtype" .= t "m.text", "body" .= t "secret hello"]
                ]
        enc <- encryptMegolm alice "!room:hs" inner
        eDec <- decryptMegolm bob enc
        eDec @?= Right inner,
      testCase "decryptMegolm without the session key is a clean error" $ do
        alice <- newCrypto "@alice:hs" "ALICEDEV"
        bob <- newCrypto "@bob:hs" "BOTDEV"
        enc <- encryptMegolm alice "!room:hs" (object ["type" .= t "m.room.message"])
        -- bob never received the room key → a Left, not a crash.
        r <- decryptMegolm bob enc
        assertBool "left" (isLeft r)
    ]
  where
    t = id :: Text -> Text
    isLeft = either (const True) (const False)

-- Pull a signature string out of a signed object's `signatures.<user>.<keyid>`.
sigOf :: Text -> Text -> Value -> Text
sigOf user keyId v = case lookK "signatures" v >>= lookK user >>= lookK keyId of
  Just (String s) -> s
  _ -> error "e2ee test: signature missing"

typeOf :: Value -> Maybe Text
typeOf v = case lookK "type" v of
  Just (String s) -> Just s
  _ -> Nothing

stripSignatures :: Value -> Value
stripSignatures (Object o) = Object (KM.delete "signatures" o)
stripSignatures v = v

lookK :: Text -> Value -> Maybe Value
lookK k (Object o) = KM.lookup (K.fromText k) o
lookK _ _ = Nothing
