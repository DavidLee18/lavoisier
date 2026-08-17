module Main (main) where

import Crypto.Olm (ed25519Verify, newUtility)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
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
        assertBool "left" (isLeft r),
      testCase "parseDeviceKeys / parseClaimedOtk read homeserver responses" $ do
        let devResp = object ["device_keys" .= object ["@u:hs" .= object ["D" .= object ["keys" .= object ["curve25519:D" .= t "CURVE", "ed25519:D" .= t "ED"]]]]]
            claimResp = object ["one_time_keys" .= object ["@u:hs" .= object ["D" .= object ["signed_curve25519:AAAA" .= object ["key" .= t "OTKVAL"]]]]]
        parseDeviceKeys "@u:hs" "D" devResp @?= Right ("CURVE", "ED")
        parseClaimedOtk "@u:hs" "D" claimResp @?= Right "OTKVAL",
      testCase "publishKeys posts device + one-time keys to /keys/upload" $ do
        c <- newCrypto "@bot:hs" "BOTDEV"
        cap <- newIORef Nothing
        let rest _ path body = writeIORef cap (Just (path, body)) >> pure (Right (object []))
        r <- publishKeys c rest
        r @?= Right ()
        Just (path, body) <- readIORef cap
        assertBool "upload path" ("keys/upload" `T.isInfixOf` path)
        assertBool "has device_keys" (has "device_keys" body)
        assertBool "has one_time_keys" (has "one_time_keys" body),
      testCase "shareRoomKeyWith drives query+claim+to-device; the peer decrypts the room key" $ do
        alice <- newCrypto "@alice:hs" "ALICEDEV"
        bob <- newCrypto "@bob:hs" "BOTDEV"
        (bobCurve, bobEd) <- cryptoIdentityKeys bob
        (aliceCurve, _) <- cryptoIdentityKeys alice
        Just bobOtk <- takeOneTimeKey bob
        let devResp = object ["device_keys" .= object ["@bob:hs" .= object ["BOTDEV" .= object ["keys" .= object ["curve25519:BOTDEV" .= bobCurve, "ed25519:BOTDEV" .= bobEd]]]]]
            claimResp = object ["one_time_keys" .= object ["@bob:hs" .= object ["BOTDEV" .= object ["signed_curve25519:AAAA" .= object ["key" .= bobOtk]]]]]
        cap <- newIORef Nothing
        let rest _ path body
              | "keys/query" `T.isInfixOf` path = pure (Right devResp)
              | "keys/claim" `T.isInfixOf` path = pure (Right claimResp)
              | "sendToDevice" `T.isInfixOf` path = writeIORef cap (Just body) >> pure (Right (object []))
              | otherwise = pure (Left ("unexpected: " <> path))
        r <- shareRoomKeyWith alice rest "txn1" "!room:hs" "@bob:hs" "BOTDEV"
        r @?= Right ()
        Just sent <- readIORef cap
        let ctObj = lookK "messages" sent >>= lookK "@bob:hs" >>= lookK "BOTDEV" >>= lookK "ciphertext" >>= lookK bobCurve
            mtype = maybe 0 id (ctObj >>= lookK "type" >>= asInt)
            body' = maybe "" id (ctObj >>= lookK "body" >>= asStr)
        Right roomKey <- decryptOlm bob aliceCurve mtype body'
        Right () <- storeRoomKey bob aliceCurve roomKey
        enc2 <- encryptMegolm alice "!room:hs" (object ["type" .= t "m.room.message", "content" .= object ["body" .= t "hi bob"]])
        edec <- decryptMegolm bob enc2
        case edec of
          Right inner -> (lookK "content" inner >>= lookK "body") @?= Just (String "hi bob")
          Left e -> assertFailure (T.unpack e)
    ]
  where
    t = id :: Text -> Text
    isLeft = either (const True) (const False)
    has key = maybe False (const True) . lookK key
    asInt v = case v of Number n -> Just (round n :: Int); _ -> Nothing
    asStr v = case v of String s -> Just s; _ -> Nothing

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
