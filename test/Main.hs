-- Orphan Arbitrary instances for the library's types are the idiomatic place for test generators.
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Data.Text.IO qualified as TIO
import Lavoisier.Agent
import Lavoisier.Gateway.Http (GatewayConfig (..), defaultGatewayConfig, httpApp)
import Lavoisier.Protocol.Agent (AgentError (..), AgentHandle (..), turnRequest)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Memory (SessionStore (..), newFileStore, newInMemoryStore, sessionAgentHandle, trimTo)
import Lavoisier.Protocol.Stream (drain, fromList)
import Lavoisier.Protocol.Tool
import Lavoisier.Provider.Anthropic (buildBody)
import Lavoisier.Provider.Anthropic.Sse (initSse, mapStop, sseEof, ssePush)
import Lavoisier.Tool.Builtins
import Lavoisier.Tool.Registry
import Network.HTTP.Types (hAuthorization, hContentType, status200, status401)
import Network.Wai (defaultRequest, pathInfo, requestHeaders, requestMethod)
import Network.Wai.Test (SRequest (..), runSession, simpleBody, simpleStatus, srequest)
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removeDirectoryRecursive)
import System.FilePath ((</>))
import Test.QuickCheck (Arbitrary (..), Gen, choose, elements, listOf, oneof, resize)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck (Property, testProperty, (===))

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "lavoisier"
    [ jsonProperties,
      usageProperties,
      sseTests,
      anthropicBodyTests,
      toolTests,
      agentTests,
      gatewayTests,
      memoryTests
    ]

-- --- Phase 1: protocol wire shapes, as QuickCheck round-trip properties ----------------------------

genText :: Gen Text
genText = T.pack <$> arbitrary

instance Arbitrary Usage where
  -- Realistic token magnitudes: usageCost sums via Double (faithful to the Rust `.round() as u64`),
  -- which is exact only below ~2^53. Real counts are millions, so bound the generator accordingly.
  arbitrary = MkUsage <$> tok <*> tok <*> tok <*> tok
    where
      tok = choose (0, 1_000_000_000)

instance Arbitrary StopReason where
  arbitrary =
    oneof
      [ pure EndTurn,
        pure MaxTokens,
        pure ToolUse,
        pure StopSequence,
        pure Refusal,
        pure PauseTurn,
        Other <$> genText
      ]

instance Arbitrary Event where
  arbitrary =
    oneof
      [ TextDelta <$> genText,
        Thinking <$> genText,
        ToolUseStart <$> genText <*> genText,
        ToolUseDelta <$> genText <*> genText,
        ToolUseEnd <$> genText,
        ServerToolUse <$> genText <*> genText,
        ServerToolResult <$> genText <*> genText,
        Citation <$> genText <*> genText,
        Usage <$> arbitrary,
        Notice <$> genText,
        Done <$> arbitrary
      ]

genValue :: Gen Value
genValue = oneof [pure Null, String <$> genText]

instance Arbitrary Role where
  arbitrary = elements [User, Assistant]

instance Arbitrary MediaSource where
  arbitrary =
    oneof
      [ SrcBase64 <$> genText <*> genText,
        SrcUrl <$> genText,
        SrcFile <$> genText,
        SrcPlainText <$> genText
      ]

instance Arbitrary ContentBlock where
  arbitrary =
    oneof
      [ TextBlock <$> genText <*> arbitrary,
        ThinkingBlock <$> genText,
        ImageBlock <$> arbitrary,
        DocumentBlock <$> arbitrary <*> arbitrary,
        ToolUseBlock <$> genText <*> genText <*> genValue,
        ToolResultBlock <$> genText <*> genText <*> arbitrary
      ]

instance Arbitrary Message where
  arbitrary = Message <$> arbitrary <*> resize 4 (listOf arbitrary)

jsonProperties :: TestTree
jsonProperties =
  testGroup
    "JSON round-trips (QuickCheck)"
    [ testProperty "Event encodes/decodes to itself" prop_eventRoundtrip,
      testProperty "StopReason encodes/decodes to itself" prop_stopRoundtrip,
      testProperty "Usage encodes/decodes to itself" prop_usageRoundtrip,
      testProperty "Message encodes/decodes to itself" prop_messageRoundtrip
    ]

prop_messageRoundtrip :: Message -> Property
prop_messageRoundtrip m = decode (encode m) === Just m

prop_eventRoundtrip :: Event -> Property
prop_eventRoundtrip ev = decode (encode ev) === Just ev

prop_stopRoundtrip :: StopReason -> Property
prop_stopRoundtrip sr = decode (encode sr) === Just sr

prop_usageRoundtrip :: Usage -> Property
prop_usageRoundtrip u = decode (encode u) === Just u

usageProperties :: TestTree
usageProperties =
  testGroup
    "Usage arithmetic (QuickCheck)"
    [ testProperty "accumulate with empty is identity" prop_accIdentity,
      testProperty "flat-weighted cost is the plain sum" prop_costFlat,
      testProperty "total ignores cache classes" prop_total
    ]

prop_accIdentity :: Usage -> Property
prop_accIdentity u = accumulateUsage u emptyUsage === u

prop_costFlat :: Usage -> Property
prop_costFlat u =
  usageCost u flatWeights
    === inputTokens u + outputTokens u + cacheCreationTokens u + cacheReadTokens u

prop_total :: Usage -> Property
prop_total u = usageTotal u === inputTokens u + outputTokens u

-- --- Phase 2: Anthropic SSE decoder (example-based; ports sse.rs tests) ----------------------------

sseTests :: TestTree
sseTests =
  testGroup
    "Anthropic SSE"
    [ testCase "decodes text with cache-aware usage" $ do
        let evs = decodeAll textStream
        take 2 evs @?= [TextDelta "Hi", TextDelta " there"]
        case evs !! 2 of
          Usage u -> do
            inputTokens u @?= 10
            outputTokens u @?= 5
            cacheReadTokens u @?= 4
          other -> assertFailure ("expected usage, got " <> show other)
        evs !! 3 @?= Done EndTurn
        length evs @?= 4,
      testCase "byte-at-a-time matches whole feed" $
        decodeChunked textStream @?= decodeAll textStream,
      testCase "streams a tool call start/delta/end" $ do
        let evs = decodeAll toolStream
        take 4 evs
          @?= [ ToolUseStart "toolu_1" "read_file",
                ToolUseDelta "toolu_1" "{\"path\":",
                ToolUseDelta "toolu_1" "\"a.rs\"}",
                ToolUseEnd "toolu_1"
              ]
        last evs @?= Done ToolUse,
      testCase "maps stop reasons" $ do
        mapStop "refusal" @?= Refusal
        mapStop "pause_turn" @?= PauseTurn
        mapStop "weird" @?= Other "weird"
    ]

decodeAll :: ByteString -> [Event]
decodeAll input =
  let (st, evs1) = ssePush initSse input
   in [e | Right e <- evs1 <> sseEof st]

decodeChunked :: ByteString -> [Event]
decodeChunked input =
  let (st, evs) = BS.foldl' step (initSse, []) input
   in [e | Right e <- evs <> sseEof st]
  where
    step (s, acc) b = let (s', more) = ssePush s (BS.singleton b) in (s', acc <> more)

textStream :: ByteString
textStream =
  BS.concat
    [ "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":10,\"cache_read_input_tokens\":4,\"cache_creation_input_tokens\":0,\"output_tokens\":1}}}\n\n",
      "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}\n\n",
      "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" there\"}}\n\n",
      "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5}}\n\n",
      "data: {\"type\":\"message_stop\"}\n\n"
    ]

toolStream :: ByteString
toolStream =
  BS.concat
    [ "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"read_file\",\"input\":{}}}\n\n",
      "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"path\\\":\"}}\n\n",
      "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"\\\"a.rs\\\"}\"}}\n\n",
      "data: {\"type\":\"content_block_stop\",\"index\":1}\n\n",
      "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":8}}\n\n",
      "data: {\"type\":\"message_stop\"}\n\n"
    ]

-- --- Phase 2: Anthropic request body (example-based) ----------------------------------------------

anthropicBodyTests :: TestTree
anthropicBodyTests =
  testGroup
    "Anthropic buildBody"
    [ testCase "system and tools carry cache_control when flagged" $ do
        let req =
              (chatRequest "claude-sonnet-4-5")
                { crSystem = Just (SystemPrompt "rules" True),
                  crMessages = [userMessage "hi"],
                  crTools = [ToolDef "read_file" "read a file" (object ["type" .= ("object" :: Text)]) True False]
                }
        assertBool "cache_control present" ("cache_control" `T.isInfixOf` bodyText req)
        assertBool "stream is set" ("\"stream\":true" `T.isInfixOf` bodyText req),
      testCase "sampling params dropped for opus-4-8" $ do
        let req = (chatRequest "claude-opus-4-8") {crMessages = [userMessage "hi"], crTemperature = Just 0.5}
        assertBool "no temperature" (not ("temperature" `T.isInfixOf` bodyText req)),
      testCase "temperature kept for a normal model" $ do
        let req = (chatRequest "claude-sonnet-4-6") {crMessages = [userMessage "hi"], crTemperature = Just 0.5}
        assertBool "has temperature" ("temperature" `T.isInfixOf` bodyText req)
    ]
  where
    bodyText = decodeUtf8Lenient . BL.toStrict . encode . buildBody False

-- --- Phase 3: built-in tools (offline; real filesystem in a temp dir) ------------------------------

toolTests :: TestTree
toolTests =
  testGroup
    "builtin tools"
    [ testCase "write_file then read_file round-trips" $ withTmp "tools" $ \dir -> do
        let f = dir </> "hi.txt"
        wr <- toolInvoke writeFileTool (object ["path" .= T.pack f, "content" .= ("hello hs" :: Text)])
        case wr of
          Right o -> toChanged o @?= True
          Left e -> assertFailure ("write failed: " <> show e)
        rd <- toolInvoke readFileTool (object ["path" .= T.pack f])
        case rd of
          Right o -> toContent o @?= "hello hs"
          Left e -> assertFailure ("read failed: " <> show e),
      testCase "read_file on a missing path is a tool error, not a hard failure" $ do
        rd <- toolInvoke readFileTool (object ["path" .= ("/nonexistent/lvz/xyz" :: Text)])
        case rd of
          Right o -> toIsError o @?= True
          Left e -> assertFailure ("expected a soft error, got " <> show e),
      testCase "shell echoes and reports exit 0" $ do
        r <- toolInvoke shellTool (object ["command" .= ("echo lavoisier" :: Text)])
        case r of
          Right o -> do
            toIsError o @?= False
            assertBool "has output" ("lavoisier" `T.isInfixOf` toContent o)
            assertBool "exit 0" ("exit=0" `T.isInfixOf` toContent o)
          Left e -> assertFailure ("shell failed: " <> show e),
      testCase "shell non-zero exit is a tool error" $ do
        r <- toolInvoke shellTool (object ["command" .= ("exit 3" :: Text)])
        case r of
          Right o -> do
            toIsError o @?= True
            assertBool "exit 3" ("exit=3" `T.isInfixOf` toContent o)
          Left e -> assertFailure ("shell failed: " <> show e),
      testCase "unknown tool name is TEUnknown" $ do
        r <- invokeTool "nope" (object []) withBuiltins
        case r of
          Left (TEUnknown n) -> n @?= "nope"
          other -> assertFailure ("expected TEUnknown, got " <> show (fmap (const ()) other))
    ]

-- --- Phase 4: the agent loop (offline; a stub provider drives a full tool round-trip) --------------

agentTests :: TestTree
agentTests =
  testGroup
    "agent loop"
    [ testCase "runs a tool round-trip then finishes" $ withTmp "agent" $ \dir -> do
        let f = dir </> "agent.txt"
            args =
              decodeUtf8Lenient . BL.toStrict . encode $
                object ["path" .= T.pack f, "content" .= ("hi from stub" :: Text)]
            round1 =
              [ ToolUseStart "t1" "write_file",
                ToolUseDelta "t1" args,
                ToolUseEnd "t1",
                Usage emptyUsage,
                Done ToolUse
              ]
            round2 = [TextDelta "all done", Usage emptyUsage, Done EndTurn]
        ref <- newIORef (0 :: Int)
        emitted <- newIORef []
        let stub =
              Provider
                { providerStream = \_ -> do
                    n <- atomicModifyIORef' ref (\k -> (k + 1, k))
                    s <- fromList (map Right (if n == 0 then round1 else round2))
                    pure (Right s),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            agent = Agent stub withBuiltins (defaultAgentConfig "stub-model")
        res <- runAgent agent (turnRequest "t" "please write the file") (\ev -> modifyIORef' emitted (ev :))
        res @?= (Right () :: Either AgentError ())
        written <- TIO.readFile f
        written @?= "hi from stub"
        evs <- reverse <$> readIORef emitted
        assertBool "emitted the final text" (TextDelta "all done" `elem` evs)
    ]

-- --- Phase 6: the HTTP gateway (offline; WAI test harness, no socket or API) ----------------------

gatewayTests :: TestTree
gatewayTests =
  testGroup
    "http gateway"
    [ testCase "GET /health" $ do
        r <- runSession (srequest (SRequest (get ["health"]) "")) (httpApp defaultGatewayConfig deadAgent)
        simpleStatus r @?= status200
        simpleBody r @?= "ok",
      testCase "POST /v1/turns streams events as SSE" $ do
        let app = httpApp defaultGatewayConfig (stubAgent [TextDelta "hi there", Usage emptyUsage, Done EndTurn])
        r <- runSession (srequest (SRequest (post ["v1", "turns"] []) "{\"input\":\"hello\"}")) app
        simpleStatus r @?= status200
        let body = decodeUtf8Lenient (BL.toStrict (simpleBody r))
        assertBool "streams text_delta frames" ("text_delta" `T.isInfixOf` body)
        assertBool "carries the answer text" ("hi there" `T.isInfixOf` body)
        assertBool "ends with a done event" ("\"kind\":\"done\"" `T.isInfixOf` body),
      testCase "protected route rejects a missing key" $ do
        let app = httpApp (GatewayConfig ["secret"]) (stubAgent [])
        r <- runSession (srequest (SRequest (post ["v1", "turns"] []) "{\"input\":\"x\"}")) app
        simpleStatus r @?= status401,
      testCase "protected route accepts a valid bearer key" $ do
        let app = httpApp (GatewayConfig ["secret"]) (stubAgent [Done EndTurn])
            auth = [(hAuthorization, "Bearer secret")]
        r <- runSession (srequest (SRequest (post ["v1", "turns"] auth) "{\"input\":\"x\"}")) app
        simpleStatus r @?= status200
    ]
  where
    get p = defaultRequest {requestMethod = "GET", pathInfo = p}
    post p hdrs =
      defaultRequest
        { requestMethod = "POST",
          pathInfo = p,
          requestHeaders = (hContentType, "application/json") : hdrs
        }
    stubAgent evs = AgentHandle $ \_ -> do s <- fromList (map Right evs); pure (Right s)
    deadAgent = AgentHandle $ \_ -> pure (Left (AEProvider "unused"))

-- --- Phase 7: session memory (offline; stub provider) ---------------------------------------------

memoryTests :: TestTree
memoryTests =
  testGroup
    "session memory"
    [ testCase "store round-trips and trims to most recent" $ do
        store <- newInMemoryStore (Just 2)
        m0 <- loadSession store "missing"
        m0 @?= []
        saveSession store "s" [userMessage "a", assistantMessage "b", userMessage "c"]
        back <- loadSession store "s"
        length back @?= 2
        map msgRole back @?= [Assistant, User],
      testCase "trimTo keeps the most recent, or all when unbounded" $ do
        let h = [userMessage "1", userMessage "2", userMessage "3"]
        map messageText (trimTo (Just 2) h) @?= ["2", "3"]
        trimTo Nothing h @?= h,
      testCase "session agent threads the transcript across turns" $ do
        store <- newInMemoryStore Nothing
        let stub =
              Provider
                { providerStream = \_ -> do
                    s <- fromList (map Right [TextDelta "ok", Usage emptyUsage, Done EndTurn])
                    pure (Right s),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            agent = Agent stub withBuiltins (defaultAgentConfig "stub")
            handle = sessionAgentHandle store agent
            runTurn input = do
              e <- submit handle (turnRequest "s" input)
              case e of
                Right prod -> drain prod >> pure ()
                Left err -> assertFailure ("submit failed: " <> show err)
        runTurn "hello"
        runTurn "again"
        transcript <- loadSession store "s"
        length transcript @?= 4
        map msgRole transcript @?= [User, Assistant, User, Assistant],
      testCase "file store persists across instances and trims" $ withTmp "filestore" $ \dir -> do
        s1 <- newFileStore dir (Just 2)
        saveSession s1 "sess/one" [userMessage "a", assistantMessage "b", userMessage "c"]
        -- A fresh store instance over the same dir reads what the first persisted.
        s2 <- newFileStore dir (Just 2)
        back <- loadSession s2 "sess/one"
        length back @?= 2
        map msgRole back @?= [Assistant, User]
    ]

-- Run an action in a fresh temp directory, cleaned up afterwards.
withTmp :: String -> (FilePath -> IO a) -> IO a
withTmp name k = do
  base <- getTemporaryDirectory
  let dir = base </> ("lavoisier-hs-test-" <> name)
  createDirectoryIfMissing True dir
  r <- k dir
  removeDirectoryRecursive dir
  pure r
