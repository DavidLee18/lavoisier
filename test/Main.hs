-- Orphan Arbitrary instances for the library's types are the idiomatic place for test generators.
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Control.Concurrent (forkIO)
import Control.Exception (IOException, try)
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Data.Text.IO qualified as TIO
import Lavoisier.Agent
import Lavoisier.Config (FileConfig (..), defaultConfig, loadConfig)
import Lavoisier.Gateway.A2A (defaultA2aConfig, newA2aApp)
import Lavoisier.Gateway.Acp (defaultAcpConfig, newAcpApp)
import Lavoisier.Gateway.Http (GatewayConfig (..), defaultGatewayConfig, httpApp)
import Lavoisier.Mcp
  ( CallResult (..),
    McpClient,
    McpError (..),
    McpServerSpec (..),
    RemoteTool (..),
    TransportSpec (..),
    advertisedName,
    mcCallTool,
    mcInitialize,
    mcListTools,
    mkClient,
    newPipeTransport,
    parseHttpReply,
    parseServerSpec,
    renderCall,
    toTool,
  )
import Lavoisier.Protocol.Agent (AgentError (..), AgentHandle (..), turnRequest)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Memory (SessionStore (..), newFileStore, newInMemoryStore, sessionAgentHandle, trimTo)
import Lavoisier.Protocol.Stream (drain, fromList)
import Lavoisier.Protocol.Tool
import Lavoisier.Provider.Anthropic (buildBody)
import Lavoisier.Provider.Anthropic.Sse (initSse, mapStop, sseEof, ssePush)
import Lavoisier.Provider.Google qualified as G
import Lavoisier.Provider.Google.Sse qualified as GS
import Lavoisier.Tool.Builtins
import Lavoisier.Tool.Registry
import Network.HTTP.Types (hAuthorization, hContentType, status200, status401)
import Network.Wai (defaultRequest, pathInfo, requestHeaders, requestMethod)
import Network.Wai.Test (SRequest (..), runSession, simpleBody, simpleStatus, srequest)
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removeDirectoryRecursive)
import System.FilePath ((</>))
import System.IO (Handle, hClose, hFlush, hSetBinaryMode)
import System.Process (createPipe)
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
      googleTests,
      toolTests,
      agentTests,
      gatewayTests,
      a2aTests,
      acpTests,
      memoryTests,
      configTests,
      mcpTests
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

-- --- Phase 11: Google (Gemini) provider (offline; ports lvz-google tests) --------------------------

googleTests :: TestTree
googleTests =
  testGroup
    "Google (Gemini)"
    [ testCase "decodes text with cache+thinking-aware usage" $ do
        let evs = gDecode gTextStream
        take 2 evs @?= [TextDelta "Hi", TextDelta " there"]
        case evs !! 2 of
          Usage u -> do
            inputTokens u @?= 6 -- prompt 10 - cached 4
            outputTokens u @?= 12 -- candidates 5 + thoughts 7
            cacheReadTokens u @?= 4
          o -> assertFailure ("expected usage, got " <> show o)
        evs !! 3 @?= Done EndTurn,
      testCase "function call becomes start/delta/end and ToolUse stop" $ do
        let evs = gDecode gFuncStream
        evs !! 0 @?= ToolUseStart "call_0" "shell"
        case evs !! 1 of
          ToolUseDelta i j -> do
            i @?= "call_0"
            assertBool "carries args" ("command" `T.isInfixOf` j)
          o -> assertFailure ("expected delta, got " <> show o)
        evs !! 2 @?= ToolUseEnd "call_0"
        last evs @?= Done ToolUse,
      testCase "separates thinking parts from answer text" $ do
        let evs = gDecode "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"reasoning\",\"thought\":true},{\"text\":\"answer\"}]},\"finishReason\":\"STOP\"}]}\n\n"
        take 2 evs @?= [Thinking "reasoning", TextDelta "answer"],
      testCase "maps finish reasons" $ do
        GS.mapFinish "STOP" @?= EndTurn
        GS.mapFinish "MAX_TOKENS" @?= MaxTokens
        GS.mapFinish "SAFETY" @?= Other "SAFETY",
      testCase "buildBody maps roles, functionCall/Response, generationConfig" $ do
        let req =
              (chatRequest "gemini-2.5-flash")
                { crSystem = Just (SystemPrompt "sys" False),
                  crMessages =
                    [ userMessage "hi",
                      Message Assistant [ToolUseBlock "c1" "shell" (object ["command" .= ("ls" :: Text)])],
                      Message User [ToolResultBlock "c1" "files" False]
                    ]
                }
            bt = decodeUtf8Lenient (BL.toStrict (encode (G.buildBody G.defaultReasoningFloor req)))
        assertBool "assistant -> model" ("\"role\":\"model\"" `T.isInfixOf` bt)
        assertBool "functionCall" ("functionCall" `T.isInfixOf` bt)
        assertBool "functionResponse" ("functionResponse" `T.isInfixOf` bt)
        assertBool "generationConfig" ("maxOutputTokens" `T.isInfixOf` bt)
        assertBool "systemInstruction" ("systemInstruction" `T.isInfixOf` bt)
    ]

gDecode :: ByteString -> [Event]
gDecode input = let (st, e1) = GS.ssePush GS.initSse input in [e | Right e <- e1 <> GS.sseEof st]

gTextStream :: ByteString
gTextStream =
  BS.concat
    [ "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}],\"role\":\"model\"}}],\"usageMetadata\":{\"promptTokenCount\":10,\"cachedContentTokenCount\":4,\"candidatesTokenCount\":1}}\n\n",
      "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\" there\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"cachedContentTokenCount\":4,\"candidatesTokenCount\":5,\"thoughtsTokenCount\":7}}\n\n"
    ]

gFuncStream :: ByteString
gFuncStream =
  "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"shell\",\"args\":{\"command\":\"ls\"}}}]},\"finishReason\":\"STOP\"}]}\n\n"

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

-- --- Phase 9: the A2A gateway (offline; WAI harness, stub agent) -----------------------------------

a2aTests :: TestTree
a2aTests =
  testGroup
    "a2a gateway"
    [ testCase "serves the agent card" $ do
        app <- newA2aApp defaultA2aConfig (a2aStub [])
        r <- runSession (srequest (SRequest (getP [".well-known", "agent-card.json"]) "")) app
        simpleStatus r @?= status200
        assertBool "name" ("Lavoisier" `T.isInfixOf` a2aBody r)
        assertBool "streaming" ("streaming" `T.isInfixOf` a2aBody r),
      testCase "message/send returns a completed task" $ do
        app <- newA2aApp defaultA2aConfig (a2aStub [TextDelta "PONG", Done EndTurn])
        r <- runSession (srequest (SRequest postRoot sendBody)) app
        simpleStatus r @?= status200
        assertBool "completed" ("completed" `T.isInfixOf` a2aBody r)
        assertBool "carries the answer" ("PONG" `T.isInfixOf` a2aBody r),
      testCase "tasks/get returns the stored task" $ do
        app <- newA2aApp defaultA2aConfig (a2aStub [TextDelta "PONG", Done EndTurn])
        _ <- runSession (srequest (SRequest postRoot sendBody)) app
        r <- runSession (srequest (SRequest postRoot getBody)) app
        assertBool "found + completed" ("completed" `T.isInfixOf` a2aBody r),
      testCase "unknown method is -32601" $ do
        app <- newA2aApp defaultA2aConfig (a2aStub [])
        r <- runSession (srequest (SRequest postRoot "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"frobnicate\",\"params\":{}}")) app
        assertBool "-32601" ("-32601" `T.isInfixOf` a2aBody r)
    ]
  where
    getP p = defaultRequest {requestMethod = "GET", pathInfo = p}
    postRoot = defaultRequest {requestMethod = "POST", pathInfo = [], requestHeaders = [(hContentType, "application/json")]}
    sendBody = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"message/send\",\"params\":{\"message\":{\"role\":\"user\",\"contextId\":\"c1\",\"parts\":[{\"kind\":\"text\",\"text\":\"hi\"}]}}}"
    getBody = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tasks/get\",\"params\":{\"id\":\"task-0\"}}"
    a2aBody = decodeUtf8Lenient . BL.toStrict . simpleBody
    a2aStub evs = AgentHandle $ \_ -> do s <- fromList (map Right evs); pure (Right s)

-- --- Phase 10: the ACP gateway (offline; WAI harness, stub agent) ----------------------------------

acpTests :: TestTree
acpTests =
  testGroup
    "acp gateway"
    [ testCase "lists the manifest" $ do
        app <- newAcpApp defaultAcpConfig (acpStub [])
        r <- runSession (srequest (SRequest (getP ["agents"]) "")) app
        simpleStatus r @?= status200
        assertBool "agent name" ("lavoisier" `T.isInfixOf` acpBody r),
      testCase "sync run returns completed with output" $ do
        app <- newAcpApp defaultAcpConfig (acpStub [TextDelta "ACPOK", Done EndTurn])
        r <- runSession (srequest (SRequest postRuns syncBody)) app
        simpleStatus r @?= status200
        assertBool "completed" ("completed" `T.isInfixOf` acpBody r)
        assertBool "carries the answer" ("ACPOK" `T.isInfixOf` acpBody r),
      testCase "GET /runs/{id} reflects the store" $ do
        app <- newAcpApp defaultAcpConfig (acpStub [TextDelta "ACPOK", Done EndTurn])
        _ <- runSession (srequest (SRequest postRuns syncBody)) app
        r <- runSession (srequest (SRequest (getP ["runs", "run-0"]) "")) app
        assertBool "completed" ("completed" `T.isInfixOf` acpBody r),
      testCase "ping" $ do
        app <- newAcpApp defaultAcpConfig (acpStub [])
        r <- runSession (srequest (SRequest (getP ["ping"]) "")) app
        simpleBody r @?= "pong"
    ]
  where
    getP p = defaultRequest {requestMethod = "GET", pathInfo = p}
    postRuns = defaultRequest {requestMethod = "POST", pathInfo = ["runs"], requestHeaders = [(hContentType, "application/json")]}
    syncBody = "{\"agent_name\":\"lavoisier\",\"session_id\":\"s1\",\"input\":[{\"parts\":[{\"content_type\":\"text/plain\",\"content\":\"hi\"}]}]}"
    acpBody = decodeUtf8Lenient . BL.toStrict . simpleBody
    acpStub evs = AgentHandle $ \_ -> do s <- fromList (map Right evs); pure (Right s)

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

-- --- Phase 12: Dhall config (offline; loads real Dhall from a temp file) --------------------------

configTests :: TestTree
configTests =
  testGroup
    "Dhall config"
    [ testCase "a partial config merges over all-None defaults" $ withTmp "config" $ \dir -> do
        let f = dir </> "c.dhall"
        TIO.writeFile f "{ provider = Some \"google\", serve = Some 8080 }"
        fc <- loadConfig f
        provider fc @?= Just "google"
        serve fc @?= Just 8080
        model fc @?= Nothing
        maxTokens fc @?= Nothing,
      testCase "an empty config is all defaults" $ withTmp "config2" $ \dir -> do
        let f = dir </> "c.dhall"
        TIO.writeFile f "{=}"
        fc <- loadConfig f
        fc @?= defaultConfig
    ]

-- --- Phase 13: MCP client (offline; specs/rendering + a real in-process pipe server) --------------

mcpTests :: TestTree
mcpTests =
  testGroup
    "mcp client"
    [ testCase "parses stdio and http specs" $ do
        parseServerSpec "fs: npx -y server-filesystem ."
          @?= Right (McpServerSpec "fs" (StdioSpec ["npx", "-y", "server-filesystem", "."]))
        parseServerSpec "remote: https://mcp.example.com/rpc"
          @?= Right (McpServerSpec "remote" (HttpSpec "https://mcp.example.com/rpc")),
      testCase "rejects malformed specs" $ do
        assertBool "no colon" (isLeft (parseServerSpec "no-colon"))
        assertBool "empty label" (isLeft (parseServerSpec ": missing label"))
        assertBool "empty target" (isLeft (parseServerSpec "empty:")),
      testCase "advertised names are namespaced and sanitized" $ do
        advertisedName "fs" "read_file" @?= "fs_read_file"
        advertisedName "gh" "list/issues" @?= "gh_list_issues"
        assertBool "truncated to 64" (T.length (advertisedName "x" (T.replicate 200 "a")) <= 64),
      testCase "renders content blocks and falls back to JSON" $ do
        let r =
              CallResult
                [ object ["type" .= ("text" :: Text), "text" .= ("hello" :: Text)],
                  object ["type" .= ("text" :: Text), "text" .= ("world" :: Text)],
                  object ["type" .= ("image" :: Text), "data" .= ("…" :: Text)]
                ]
                False
            out = renderCall r
        assertBool "hello" ("hello" `T.isInfixOf` out)
        assertBool "world" ("world" `T.isInfixOf` out)
        assertBool "image preserved as JSON" ("image" `T.isInfixOf` out),
      testCase "parses http json and sse replies" $ do
        parseHttpReply "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ok\":true}}" "application/json" (Just 1)
          @?= Right (object ["ok" .= True])
        let sse = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"n\":5}}\n\n"
        parseHttpReply sse "text/event-stream" (Just 2) @?= Right (object ["n" .= (5 :: Int)])
        case parseHttpReply "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"nope\"}}" "application/json" (Just 1) of
          Left (Rpc m) -> m @?= "nope"
          other -> assertFailure ("expected Rpc, got " <> show other),
      testCase "discovers and invokes tools over a real pipe" $ do
        client <- mkPipeClient "fs"
        mcInitialize client >>= (@?= Right ())
        et <- mcListTools client
        case et of
          Right [rt] -> rtName rt @?= "echo"
          other -> assertFailure ("expected one tool, got " <> show other)
        ec <- mcCallTool client "echo" (object ["text" .= ("hi there" :: Text)])
        case ec of
          Right res -> do
            resIsError res @?= False
            renderCall res @?= "hi there"
          Left e -> assertFailure ("call failed: " <> show e),
      testCase "adapter maps a call into a ToolOutput" $ do
        client <- mkPipeClient "fs"
        _ <- mcInitialize client
        let tool = toTool client "fs" (RemoteTool "echo" (Just "echo") (Just (object ["type" .= ("object" :: Text)])))
        toolName tool @?= "fs_echo"
        out <- toolInvoke tool (object ["text" .= ("pong" :: Text)])
        case out of
          Right o -> do
            toIsError o @?= False
            toContent o @?= "pong"
          Left e -> assertFailure ("invoke failed: " <> show e),
      testCase "a closed pipe fails fast, not on timeout" $ do
        -- Server ends closed at both ends: the client's write breaks (or its reader drains pending).
        (aR, aW) <- createPipe
        (bR, bW) <- createPipe
        hClose bW
        hClose aR
        tr <- newPipeTransport bR aW Nothing
        let client = mkClient "dead" tr
        r <- mcInitialize client
        case r of
          Left Closed -> pure ()
          Left (Io _) -> pure ()
          other -> assertFailure ("expected Closed/Io, got " <> show other)
    ]

-- | Wire an in-process mock MCP server to a client over two OS pipes (the offline analogue of Rust's
-- @tokio::io::duplex@): client→server on one pipe, server→client on the other.
mkPipeClient :: Text -> IO McpClient
mkPipeClient label = do
  (aR, aW) <- createPipe -- client writes aW, server reads aR
  (bR, bW) <- createPipe -- server writes bW, client reads bR
  _ <- forkIO (mockServer aR bW)
  tr <- newPipeTransport bR aW Nothing
  pure (mkClient label tr)

-- | A minimal MCP server over a handle pair: answers initialize/tools/list/tools/call, swallows the
-- initialized notification. Exercises the real stdio framing/demux path.
mockServer :: Handle -> Handle -> IO ()
mockServer readH writeH = do
  hSetBinaryMode readH True
  hSetBinaryMode writeH True
  let loop = do
        r <- try (BS8.hGetLine readH) :: IO (Either IOException BS.ByteString)
        case r of
          Left _ -> pure ()
          Right line
            | BS.null (BS.dropWhile isSpaceW line) -> loop
            | otherwise -> do
                case decode (BL.fromStrict line) :: Maybe Value of
                  Nothing -> loop
                  Just msg -> case msgIdOf msg of
                    Nothing -> loop -- a notification: no reply
                    Just i -> do
                      let result = case methodOf msg of
                            "initialize" -> object ["protocolVersion" .= ("2025-06-18" :: Text), "capabilities" .= object []]
                            "tools/list" ->
                              object
                                ["tools" .= [object ["name" .= ("echo" :: Text), "description" .= ("echo back" :: Text), "inputSchema" .= object ["type" .= ("object" :: Text)]]]]
                            "tools/call" -> object ["content" .= [object ["type" .= ("text" :: Text), "text" .= argText msg]], "isError" .= False]
                            _ -> Null
                          out = BL.toStrict (encode (object ["jsonrpc" .= ("2.0" :: Text), "id" .= i, "result" .= result])) <> "\n"
                      BS.hPut writeH out
                      hFlush writeH
                      loop
  loop
  where
    isSpaceW w = w == 32 || w == 9 || w == 10 || w == 13

objLookup :: Text -> Value -> Maybe Value
objLookup k (Object o) = KM.lookup (K.fromText k) o
objLookup _ _ = Nothing

msgIdOf :: Value -> Maybe Int
msgIdOf msg = case objLookup "id" msg of
  Just (Number n) -> toBoundedInteger n
  _ -> Nothing

methodOf :: Value -> Text
methodOf msg = case objLookup "method" msg of
  Just (String s) -> s
  _ -> ""

argText :: Value -> Text
argText msg = case objLookup "params" msg >>= objLookup "arguments" >>= objLookup "text" of
  Just (String s) -> s
  _ -> ""

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

-- Run an action in a fresh temp directory, cleaned up afterwards.
withTmp :: String -> (FilePath -> IO a) -> IO a
withTmp name k = do
  base <- getTemporaryDirectory
  let dir = base </> ("lavoisier-hs-test-" <> name)
  createDirectoryIfMissing True dir
  r <- k dir
  removeDirectoryRecursive dir
  pure r
