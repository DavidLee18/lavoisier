module Main (main) where

import Crypto.Olm (ed25519Verify, exportInboundGroupSession, newInboundGroupSession, newUtility)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
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
        (bobCurve, _bobEd) <- cryptoIdentityKeys bob
        (aliceCurve, _) <- cryptoIdentityKeys alice
        Just bobOtk <- takeOneTimeKey bob
        -- The device object must carry bob's real Ed25519 self-signature: queryDevice now verifies it.
        bobDev <- deviceKeysPayload bob
        let devResp = object ["device_keys" .= object ["@bob:hs" .= object ["BOTDEV" .= bobDev]]]
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
          Left e -> assertFailure (T.unpack e),
      testCase "pickleStore/unpickleStore round-trips the crypto identity and inbound sessions" $ do
        -- alice shares a room key to bob; bob's restored store must still decrypt alice's message.
        alice <- newCrypto "@alice:hs" "ALICEDEV"
        bob <- newCrypto "@bob:hs" "BOTDEV"
        (aliceCurve, _) <- cryptoIdentityKeys alice
        bobDev <- deviceKeysPayload bob
        Just bobOtk <- takeOneTimeKey bob
        let devResp = object ["device_keys" .= object ["@bob:hs" .= object ["BOTDEV" .= bobDev]]]
            claimResp = object ["one_time_keys" .= object ["@bob:hs" .= object ["BOTDEV" .= object ["signed_curve25519:AAAA" .= object ["key" .= bobOtk]]]]]
        cap <- newIORef Nothing
        let rest _ path body
              | "keys/query" `T.isInfixOf` path = pure (Right devResp)
              | "keys/claim" `T.isInfixOf` path = pure (Right claimResp)
              | "sendToDevice" `T.isInfixOf` path = writeIORef cap (Just body) >> pure (Right (object []))
              | otherwise = pure (Left ("unexpected: " <> path))
        _ <- shareRoomKeyWith alice rest "txn1" "!room:hs" "@bob:hs" "BOTDEV"
        Just sent <- readIORef cap
        -- deliver the room key to bob, then persist + restore bob, then decrypt an alice message
        (bobCurve, _) <- cryptoIdentityKeys bob
        let ct = lookK "messages" sent >>= lookK "@bob:hs" >>= lookK "BOTDEV" >>= lookK "ciphertext" >>= lookK bobCurve
            mtype = maybe 0 id (ct >>= lookK "type" >>= asInt)
            body' = maybe "" id (ct >>= lookK "body" >>= asStr)
        Right roomKey <- decryptOlm bob aliceCurve mtype body'
        Right () <- storeRoomKey bob aliceCurve roomKey
        pickled <- pickleStore bob "pass"
        Just bob2 <- unpickleStore "@bob:hs" "BOTDEV" "pass" pickled
        enc2 <- encryptMegolm alice "!room:hs" (object ["type" .= t "m.room.message", "content" .= object ["body" .= t "after restart"]])
        edec <- decryptMegolm bob2 enc2
        case edec of
          Right inner -> (lookK "content" inner >>= lookK "body") @?= Just (String "after restart")
          Left e -> assertFailure ("restored store failed to decrypt: " <> T.unpack e),
      testCase "unpickleStore rejects a wrong passphrase" $ do
        c <- newCrypto "@x:hs" "XDEV"
        pickled <- pickleStore c "right"
        bad <- unpickleStore "@x:hs" "XDEV" "wrong" pickled
        assertBool "wrong passphrase yields Nothing" (maybe True (const False) bad),
      testCase "verifyDeviceKeys accepts a self-signed device and rejects a tampered one" $ do
        c <- newCrypto "@bot:hs" "BOTDEV"
        dev <- deviceKeysPayload c
        okGood <- verifyDeviceKeys "@bot:hs" "BOTDEV" dev
        assertBool "genuine self-signature verifies" okGood
        let tampered = case dev of
              Object o -> Object (KM.insert "keys" (object ["curve25519:BOTDEV" .= t "FORGED", "ed25519:BOTDEV" .= t "FORGED"]) o)
              v -> v
        okBad <- verifyDeviceKeys "@bot:hs" "BOTDEV" tampered
        assertBool "a tampered key object is rejected" (not okBad),
      -- The production failure of 2026-08-19: a store migration preserves the device id but cannot
      -- carry the Olm 1:1 sessions, so peers keep sending type-1 messages we have no session for.
      -- Reproduced exactly — pickle the bot, drop the `olm` map, restore — then repaired end to end.
      testCase "a bot that lost its Olm sessions unwedges itself with m.dummy" $ do
        alice <- newCrypto "@alice:hs" "ALICEDEV"
        bot0 <- newCrypto "@bot:hs" "BOTDEV"
        (botCurve, _) <- cryptoIdentityKeys bot0
        (aliceCurve, _) <- cryptoIdentityKeys alice
        Just botOtk <- takeOneTimeKey bot0
        -- Alice establishes a session with the bot and gets one message through.
        (mt0, b0) <- olmEncryptTo alice botCurve botOtk (object ["type" .= t "m.dummy", "content" .= object []])
        Right _ <- decryptOlm bot0 aliceCurve mt0 b0
        -- The bot answers, which is what moves alice off PRE_KEY onto normal (type-1) messages — the
        -- established steady state every long-lived peer of a deployed bot is already in.
        (mtR, bR) <- olmEncryptTo bot0 aliceCurve "" (object ["type" .= t "m.dummy", "content" .= object []])
        Right _ <- decryptOlm alice botCurve mtR bR
        -- The migration: everything but the 1:1 Olm sessions survives.
        pickled <- pickleStore bot0 "pw"
        let stripped = case pickled of
              Object o -> Object (KM.insert "olm" (object []) o)
              v -> v
        Just bot <- unpickleStore "@bot:hs" "BOTDEV" "pw" stripped
        -- Alice, unaware, keeps using her session: a type-1 message the bot cannot read.
        (mt1, b1) <- olmEncryptTo alice botCurve botOtk (object ["type" .= t "m.room_key", "content" .= object []])
        mt1 @?= 1
        wedged <- decryptOlm bot aliceCurve mt1 b1
        assertBool "a type-1 message with no session is an error, not silence" (isLeft wedged)
        -- Recovery: the bot resolves alice's device from her sender_key and sends her an m.dummy.
        aliceDev <- deviceKeysPayload alice
        Just aliceOtk <- takeOneTimeKey alice
        let devResp = object ["device_keys" .= object ["@alice:hs" .= object ["ALICEDEV" .= aliceDev]]]
            claimResp = object ["one_time_keys" .= object ["@alice:hs" .= object ["ALICEDEV" .= object ["signed_curve25519:AAAA" .= object ["key" .= aliceOtk]]]]]
        cap <- newIORef Nothing
        let rest _ path body
              | "keys/query" `T.isInfixOf` path = pure (Right devResp)
              | "keys/claim" `T.isInfixOf` path = pure (Right claimResp)
              | "sendToDevice" `T.isInfixOf` path = writeIORef cap (Just body) >> pure (Right (object []))
              | otherwise = pure (Left ("unexpected: " <> path))
        found <- findDeviceByCurve rest "@alice:hs" aliceCurve
        found @?= Right "ALICEDEV"
        rd <- sendDummyTo bot rest "txn1" "@alice:hs" "ALICEDEV"
        rd @?= Right ()
        Just sent <- readIORef cap
        let ctObj = lookK "messages" sent >>= lookK "@alice:hs" >>= lookK "ALICEDEV" >>= lookK "ciphertext" >>= lookK aliceCurve
            dmt = maybe (-1) id (ctObj >>= lookK "type" >>= asInt)
            dbody = maybe "" id (ctObj >>= lookK "body" >>= asStr)
        assertBool "the unwedge must be a PRE_KEY message, or it repairs nothing" (dmt == 0)
        -- Alice replaces her session on receiving it, and her next message reaches the bot.
        Right dummy <- decryptOlm alice botCurve dmt dbody
        typeOf dummy @?= Just "m.dummy"
        (mt2, b2) <- olmEncryptTo alice botCurve botOtk (object ["type" .= t "m.room_key", "content" .= object []])
        recovered <- decryptOlm bot aliceCurve mt2 b2
        case recovered of
          Right ev -> typeOf ev @?= Just "m.room_key"
          Left e -> assertFailure ("still wedged after the m.dummy: " <> T.unpack e),
      testCase "requestRoomKey/cancelRoomKeyRequest address every device of the sender" $ do
        bot <- newCrypto "@bot:hs" "BOTDEV"
        cap <- newIORef []
        let rest _ path body = modifyIORef' cap ((path, body) :) >> pure (Right (object []))
        Right () <- requestRoomKey bot rest "txn1" "@alice:hs" "!room:hs" "SENDERKEY" "SESS1"
        Right () <- cancelRoomKeyRequest bot rest "txn2" "@alice:hs" "SESS1"
        [(cancelPath, cancelBody), (reqPath, reqBody)] <- readIORef cap
        assertBool "request is a room key request" ("sendToDevice/m.room_key_request/txn1" `T.isInfixOf` reqPath)
        assertBool "cancellation is too" ("sendToDevice/m.room_key_request/txn2" `T.isInfixOf` cancelPath)
        let content p = lookK "messages" p >>= lookK "@alice:hs" >>= lookK "*"
        (content reqBody >>= lookK "action") @?= Just (String "request")
        (content reqBody >>= lookK "request_id") @?= Just (String "SESS1")
        (content reqBody >>= lookK "body" >>= lookK "session_id") @?= Just (String "SESS1")
        (content reqBody >>= lookK "body" >>= lookK "room_id") @?= Just (String "!room:hs")
        (content cancelBody >>= lookK "action") @?= Just (String "request_cancellation")
        (content cancelBody >>= lookK "request_id") @?= Just (String "SESS1"),
      testCase "a forwarded room key decrypts the session it was exported from" $ do
        alice <- newCrypto "@alice:hs" "ALICEDEV"
        bot <- newCrypto "@bot:hs" "BOTDEV"
        (aliceCurve, _) <- cryptoIdentityKeys alice
        -- Alice creates a session and a message; the bot never got the key over Olm.
        rk <- roomKeyEvent alice "!room:hs"
        ev <- encryptMegolm alice "!room:hs" (object ["type" .= t "m.room.message", "content" .= object ["body" .= t "hi"]])
        missing <- decryptMegolm bot ev
        assertBool "no session yet" (isLeft missing)
        -- A forwarding peer sends the key it holds, which is an *exported* one — a different libolm
        -- format from the `session_key` of an m.room_key, and the reason this needs its own importer.
        let initKey = maybe "" id (lookK "content" rk >>= lookK "session_key" >>= asStr)
        exported <- newInboundGroupSession (encodeUtf8 initKey) >>= exportInboundGroupSession
        -- A peer answers the request with m.forwarded_room_key: keyed by the *content's* sender_key,
        -- which is what the room's events carry.
        let inner = maybe (object []) id (lookK "content" rk)
            fwd =
              object
                [ "type" .= t "m.forwarded_room_key",
                  "content"
                    .= object
                      [ "algorithm" .= t "m.megolm.v1.aes-sha2",
                        "room_id" .= t "!room:hs",
                        "sender_key" .= aliceCurve,
                        "session_id" .= maybe Null id (lookK "session_id" inner),
                        "session_key" .= decodeUtf8 exported,
                        "forwarding_curve25519_key_chain" .= ([] :: [Text])
                      ]
                ]
        Right () <- storeForwardedRoomKey bot fwd
        edec <- decryptMegolm bot ev
        case edec of
          Right dec -> (lookK "content" dec >>= lookK "body") @?= Just (String "hi")
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
