-- Orphan Arbitrary instances for the library's types are the idiomatic place for test generators.
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Control.Concurrent (forkIO)
import Control.Exception (IOException, try)
import Control.Monad (replicateM, replicateM_)
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Scientific (toBoundedInteger)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Data.Word (Word64)
import Lavoisier.Agent
import Lavoisier.Config (FileConfig (..), defaultConfig, loadConfig)
import Lavoisier.Context.Anchor qualified as Anc
import Lavoisier.Context.Budget qualified as Bud
import Lavoisier.Context.Diff qualified as Dff
import Lavoisier.Context.Lang (Lang (..), LangSpec (..), langFromPath, langSpec)
import Lavoisier.Context.Skeleton qualified as Skel
import Lavoisier.Context.Symbols qualified as Sym
import Lavoisier.Context.Tokens (estimateTokens)
import Lavoisier.Context.TreeSitter qualified as TS
import Lavoisier.Gateway.A2A (defaultA2aConfig, newA2aApp)
import Lavoisier.Gateway.Acp (defaultAcpConfig, newAcpApp)
import Lavoisier.Gateway.Cron (CronConfigError (..), CronJob (..), parseCliJob, parseFileJobs)
import Lavoisier.Gateway.Http (GatewayConfig (..), defaultGatewayConfig, httpApp)
import Lavoisier.Gateway.Matrix qualified as MX
import Lavoisier.Gateway.Slack (SlackMessage (..), parseEvent, senderAllowed, slackSession)
import Lavoisier.Legion (Debater, Language (..), LegionError (..), languageFromLocale, mkDebater, newPanel, panelDeliberator, withLanguage)
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
import Lavoisier.Memory (SessionStore (..), newFileStore, newInMemoryStore, sessionAgentHandle, trimTo)
import Lavoisier.Protocol.Agent (AgentError (..), AgentHandle (..), turnRequest)
import Lavoisier.Protocol.Deliberate (DeliberateError (..), Deliberation (..), DeliberationContext (..), deliberate, runDeliberation)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Protocol.Stream (drain, fromList)
import Lavoisier.Protocol.Tool
import Lavoisier.Protocol.Tune qualified as Tn
import Lavoisier.Provider.Anthropic (buildBody)
import Lavoisier.Provider.Anthropic.Sse (initSse, mapStop, sseEof, ssePush)
import Lavoisier.Provider.ClaudeCli (eofDecoder, initDecoder, pushLine, renderPrompt)
import Lavoisier.Provider.Google qualified as G
import Lavoisier.Provider.Google.Sse qualified as GS
import Lavoisier.Provider.Xai (buildMessages)
import Lavoisier.Provider.Xai.Sse qualified as XS
import Lavoisier.Schedule.Cron (Civil (..), CronError (..), civilFromUnix, nextAfter, parseCron)
import Lavoisier.Tool.Builtins
import Lavoisier.Tool.Registry
import Lavoisier.Tune
import Lavoisier.Tune.Bayes (asBayesTuner, bayesTuner, loadBayes, newBayesTuner, sampleBeta, saveBayes)
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
      fallbackTests,
      contextTests,
      treeSitterTests,
      skeletonTests,
      symbolTests,
      budgetTests,
      gatewayTests,
      a2aTests,
      acpTests,
      memoryTests,
      configTests,
      mcpTests,
      tuneTests,
      bayesTests,
      claudeCliTests,
      legionTests,
      slackTests,
      cronTests,
      xaiTests,
      matrixTests
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
  let (st, evs) = BS.foldl' stepByte (initSse, []) input
   in [e | Right e <- evs <> sseEof st]
  where
    stepByte (s, acc) b = let (s', more) = ssePush s (BS.singleton b) in (s', acc <> more)

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
        agent <- mkAgent stub withBuiltins (defaultAgentConfig "stub-model") Tn.noopTuner Nothing
        res <- runAgent agent (turnRequest "t" "please write the file") (\ev -> modifyIORef' emitted (ev :))
        res @?= (Right () :: Either AgentError ())
        written <- TIO.readFile f
        written @?= "hi from stub"
        evs <- reverse <$> readIORef emitted
        assertBool "emitted the final text" (TextDelta "all done" `elem` evs),
      testCase "the truncate knob caps a large tool result and records the counterfactual" $ withTmp "trunc" $ \dir -> do
        let f = dir </> "big.txt"
            big = T.replicate 100 "x" -- 100 bytes, well over the 16-byte budget below
            args = decodeUtf8Lenient . BL.toStrict . encode $ object ["path" .= T.pack f]
            round1 = [ToolUseStart "t1" "read_file", ToolUseDelta "t1" args, ToolUseEnd "t1", Usage emptyUsage, Done ToolUse]
            round2 = [TextDelta "done", Usage emptyUsage, Done EndTurn]
        TIO.writeFile f big
        ref <- newIORef (0 :: Int)
        obsRef <- newIORef Nothing
        let stub =
              Provider
                { providerStream = \_ -> do
                    n <- atomicModifyIORef' ref (\k -> (k + 1, k))
                    s <- fromList (map Right (if n == 0 then round1 else round2))
                    pure (Right s),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            -- A tuner that forces a tiny truncate budget and captures the observed Outcome.
            tuner =
              Tn.Tuner
                { Tn.tunerSelect = \_ -> pure Tn.defaultKnobs {Tn.truncateBytes = 16},
                  Tn.tunerObserve = \_ _ o -> writeIORef obsRef (Just o)
                }
        agent <- mkAgent stub withBuiltins (defaultAgentConfig "stub-model") tuner Nothing
        r <- runLoopSeeded agent Nothing [userMessage "read it"] (const (pure ()))
        case r of
          Left e -> assertFailure ("loop failed: " <> show e)
          Right msgs -> do
            let results = [content | Message _ blocks <- msgs, ToolResultBlock _ content _ <- blocks]
            assertBool "a tool result is present" (not (null results))
            assertBool "the result was truncated" (any ("truncated" `T.isInfixOf`) results)
        obs <- readIORef obsRef
        case obs >>= Tn.otMaxToolResultBytes of
          Just m -> assertBool ("recorded pre-truncation size " <> show m) (m >= 100)
          Nothing -> assertFailure "no max-tool-result-bytes recorded in the outcome"
    ]

-- --- fallback chain (offline; scripted providers + the cross-turn circuit breaker) ---------------

fallbackTests :: TestTree
fallbackTests =
  testGroup
    "fallback chain"
    [ testCase "reroutes to the next model when the primary errors before any output" $ do
        emitted <- newIORef []
        agent0 <- mkAgent (scriptedProv "" emptyUsage True) withBuiltins (defaultAgentConfig "primary") Tn.noopTuner Nothing
        agent <- withFallbacks [(scriptedProv "from fallback" emptyUsage False, "backup")] 60 agent0
        res <- runAgent agent (turnRequest "t" "hi") (\ev -> modifyIORef' emitted (ev :))
        res @?= (Right () :: Either AgentError ())
        evs <- reverse <$> readIORef emitted
        assertBool "answered from the fallback" (TextDelta "from fallback" `elem` evs),
      testCase "with no fallback, a primary open-error surfaces as an error" $ do
        agent <- mkAgent (scriptedProv "" emptyUsage True) withBuiltins (defaultAgentConfig "primary") Tn.noopTuner Nothing
        res <- runAgent agent (turnRequest "t" "hi") (const (pure ()))
        assertBool "left" (isLeftE res),
      testCase "a failure after output has streamed does NOT reroute" $ do
        emitted <- newIORef []
        agent0 <- mkAgent midStreamProv withBuiltins (defaultAgentConfig "primary") Tn.noopTuner Nothing
        agent <- withFallbacks [(scriptedProv "from fallback" emptyUsage False, "backup")] 60 agent0
        res <- runAgent agent (turnRequest "t" "hi") (\ev -> modifyIORef' emitted (ev :))
        assertBool "surfaces the mid-stream error" (isLeftE res)
        evs <- reverse <$> readIORef emitted
        assertBool "streamed the partial output" (TextDelta "partial" `elem` evs)
        assertBool "never used the fallback" (TextDelta "from fallback" `notElem` evs),
      testCase "the breaker keeps a downed primary demoted across turns" $ do
        calls <- newIORef (0 :: Int)
        agent0 <- mkAgent (countingFailProv calls) withBuiltins (defaultAgentConfig "primary") Tn.noopTuner Nothing
        agent <- withFallbacks [(scriptedProv "backup" emptyUsage False, "backup")] 3600 agent0
        _ <- runAgent agent (turnRequest "t" "one") (const (pure ()))
        _ <- runAgent agent (turnRequest "t" "two") (const (pure ()))
        n <- readIORef calls
        -- Primary tried once (turn 1, which trips it); turn 2 starts past it while it stays demoted.
        n @?= 1
    ]
  where
    isLeftE = either (const True) (const False)
    midStreamProv =
      Provider
        { providerStream = \_ -> do
            s <- fromList [Right (TextDelta "partial"), Left (PTransport "boom")]
            pure (Right s),
          providerCapabilities = noCapabilities,
          providerCountTokens = \_ -> pure (Right Nothing)
        }
    countingFailProv ref =
      Provider
        { providerStream = \_ -> do
            modifyIORef' ref (+ 1)
            pure (Left (PTransport "down")),
          providerCapabilities = noCapabilities,
          providerCountTokens = \_ -> pure (Right Nothing)
        }

-- --- context engine, parse-free part: tokens + diff + anchor (ports lvz-context tests) -----------

contextTests :: TestTree
contextTests =
  testGroup
    "context engine (tokens/diff/anchor)"
    [ testCase "estimateTokens: empty and whitespace are zero" $ do
        estimateTokens "" @?= 0
        estimateTokens "   \n\t " @?= 0,
      testCase "estimateTokens: counts words and punctuation" $
        -- `fn` `add` `(` `a` `,` `b` `)` => 7
        estimateTokens "fn add(a, b)" @?= 7,
      testCase "estimateTokens: an elided body is cheaper than the full body" $
        assertBool
          "skeleton cheaper"
          (estimateTokens "fn f() { … }" < estimateTokens "fn f() {\n    let x = compute(1, 2, 3);\n    x\n}"),
      testCase "unifiedDiff: identical inputs produce no diff" $ do
        Dff.unifiedDiff "a\nb\n" "a\nb\n" 1 @?= ""
        Dff.changedLines "a\nb\n" "a\nb\n" @?= 0,
      testCase "unifiedDiff: shows only the changed hunk within the context radius" $ do
        let d = Dff.unifiedDiff "one\ntwo\nthree\nfour\nfive\n" "one\ntwo\nTHREE\nfour\nfive\n" 1
        assertBool "deletes three" ("-three" `T.isInfixOf` d)
        assertBool "inserts THREE" ("+THREE" `T.isInfixOf` d)
        -- With radius 1 the distant unchanged lines are excluded.
        assertBool "excludes one" (not ("one" `T.isInfixOf` d))
        assertBool "excludes five" (not ("five" `T.isInfixOf` d)),
      testCase "changedLines: counts inserts and deletes" $
        -- one line replaced => one delete + one insert.
        Dff.changedLines "a\nb\nc\n" "a\nB\nc\n" @?= 2,
      testCase "anchorOf is indentation-insensitive and stable 8-hex" $ do
        Anc.anchorOf "    let x = 1;" @?= Anc.anchorOf "let x = 1;"
        T.length (Anc.anchorOf "let x = 1;") @?= 8,
      testCase "replace targets the anchored line" $ do
        out <- expectRight (Anc.applyEdits src [Anc.replaceEdit (Anc.anchorOf "    let x = 1;") "    let x = 42;"])
        assertBool "new value present" ("let x = 42;" `T.isInfixOf` out)
        assertBool "old value gone" (not ("let x = 1;" `T.isInfixOf` out))
        assertBool "trailing newline kept" ("\n" `T.isSuffixOf` out),
      testCase "insert after and before place lines around the anchor" $ do
        out <- expectRight (Anc.applyEdits src [Anc.insertAfterEdit (Anc.anchorOf "    let x = 1;") "    let y = 2;"])
        let ls = T.lines out
            xi = length (takeWhile (not . T.isInfixOf "let x = 1;") ls)
        assertBool "y follows x" ("let y = 2;" `T.isInfixOf` (ls !! (xi + 1))),
      testCase "delete removes the anchored line" $ do
        out <- expectRight (Anc.applyEdits src [Anc.deleteEdit (Anc.anchorOf "    println!(\"{x}\");")])
        assertBool "line gone" (not ("println!" `T.isInfixOf` out)),
      testCase "an unmatched anchor fails the whole batch" $
        case Anc.applyEdits src [Anc.replaceEdit "deadbeef" "x"] of
          Left (Anc.NotFound _) -> pure ()
          other -> assertFailure ("expected NotFound, got " <> show other),
      testCase "an ambiguous anchor is rejected" $
        case Anc.applyEdits "dup\ndup\n" [Anc.replaceEdit (Anc.anchorOf "dup") "x"] of
          Left (Anc.Ambiguous _ 2) -> pure ()
          other -> assertFailure ("expected Ambiguous _ 2, got " <> show other),
      testCase "renderAnchored has an anchor gutter" $ do
        let r = Anc.renderAnchored "hello"
        assertBool "starts with the anchor" (Anc.anchorOf "hello" `T.isPrefixOf` r)
        assertBool "has the gutter bar" ("\9474" `T.isInfixOf` r),
      testCase "end-to-end: anchored edit then minimal diff" $ do
        let source = "/// Doubles n.\nfn double(n: i32) -> i32 {\n    n * 2\n}\n"
        edited <- expectRight (Anc.applyEdits source [Anc.replaceEdit (Anc.anchorOf "    n * 2") "    n * 3"])
        assertBool "body changed" ("n * 3" `T.isInfixOf` edited)
        let d = Dff.unifiedDiff source edited 0
        assertBool "diff deletes old body" ("-    n * 2" `T.isInfixOf` d)
        assertBool "diff inserts new body" ("+    n * 3" `T.isInfixOf` d)
    ]
  where
    src = "fn main() {\n    let x = 1;\n    println!(\"{x}\");\n}\n"
    expectRight = either (\e -> assertFailure ("expected Right, got " <> show e)) pure

-- The tree-sitter substrate (Phase 23b): language config + a real parse over the vendored Rust
-- grammar via the C-FFI shim. Proves the fragile C build actually parses end-to-end.
treeSitterTests :: TestTree
treeSitterTests =
  testGroup
    "context engine (tree-sitter)"
    [ testCase "langFromPath detects by extension" $ do
        langFromPath "src/main.rs" @?= Just Rust
        langFromPath "a/b/c.py" @?= Just Python
        langFromPath "x.JSX" @?= Just JavaScript
        langFromPath "x.tsx" @?= Just TypeScript
        langFromPath "README.md" @?= Nothing
        langFromPath "noext" @?= Nothing,
      testCase "langSpec: Rust elides bodies, Python keeps docstrings" $ do
        elision (langSpec Rust) @?= "{ … }"
        keepsDocstring (langSpec Python) @?= True
        keepsDocstring (langSpec Rust) @?= False,
      testCase "supported: all four grammars are wired" $ do
        TS.supported Rust @?= True
        TS.supported Python @?= True
        TS.supported JavaScript @?= True
        TS.supported TypeScript @?= True,
      testCase "parse: a Rust fn yields a named function_item with name + body fields" $ do
        let code = BS8.pack "fn add(a: i32, b: i32) -> i32 { a + b }\n"
        mroot <- TS.parse Rust code
        case mroot of
          Nothing -> assertFailure "expected a parse tree"
          Just root -> do
            TS.synType root @?= "source_file"
            case [n | n <- TS.descendants root, TS.synType n == "function_item"] of
              [fn] -> do
                case TS.childByField "name" fn of
                  Just nameNode -> TS.nodeText code nameNode @?= BS8.pack "add"
                  Nothing -> assertFailure "function_item has no name field"
                case TS.childByField "body" fn of
                  Just body -> TS.synType body @?= "block"
                  Nothing -> assertFailure "function_item has no body field"
              other -> assertFailure ("expected exactly one function_item, got " <> show (length other)),
      testCase "parse: Python finds a function_definition named greet" $ do
        let code = BS8.pack "def greet(name):\n    return name\n"
        mroot <- TS.parse Python code
        case mroot of
          Nothing -> assertFailure "expected a Python parse tree"
          Just root -> case [n | n <- TS.descendants root, TS.synType n == "function_definition"] of
            (fn : _) -> case TS.childByField "name" fn of
              Just nm -> TS.nodeText code nm @?= BS8.pack "greet"
              Nothing -> assertFailure "def has no name field"
            [] -> assertFailure "no function_definition found",
      testCase "parse: JavaScript and TypeScript both parse a declaration" $ do
        jsRoot <- TS.parse JavaScript (BS8.pack "function f(x) { return x; }\n")
        case jsRoot of
          Just r -> assertBool "js function_declaration" (any ((== "function_declaration") . TS.synType) (TS.descendants r))
          Nothing -> assertFailure "expected a JS parse tree"
        tsRoot <- TS.parse TypeScript (BS8.pack "interface P { x: number }\n")
        case tsRoot of
          Just r -> assertBool "ts interface_declaration" (any ((== "interface_declaration") . TS.synType) (TS.descendants r))
          Nothing -> assertFailure "expected a TS parse tree"
    ]

-- Skeletonisation (Phase 23b): keep signatures + docs, elide bodies (the §6.1 token lever).
skeletonTests :: TestTree
skeletonTests =
  testGroup
    "context engine (skeleton)"
    [ testCase "Rust bodies are elided; signatures and docs kept" $ do
        out <-
          skel Rust $
            "/// Adds two numbers.\npub fn add(a: i32, b: i32) -> i32 {\n    let sum = a + b;\n    sum\n}\n\nstruct Point { x: i32, y: i32 }\n"
        assertBool "doc kept" ("/// Adds two numbers." `T.isInfixOf` out)
        assertBool "signature kept" ("pub fn add(a: i32, b: i32) -> i32" `T.isInfixOf` out)
        assertBool "placeholder present" ("{ … }" `T.isInfixOf` out)
        assertBool "body elided" (not ("let sum = a + b;" `T.isInfixOf` out))
        assertBool "struct fields kept" ("struct Point { x: i32, y: i32 }" `T.isInfixOf` out),
      testCase "keepBodies preserves the named function only" $ do
        out <-
          Skel.skeletonize Rust (Set.fromList ["keep_me"]) $
            BS8.pack "fn keep_me() { let a = 1; }\nfn drop_me() { let b = 2; }\n"
        let t = decodeUtf8Lenient out
        assertBool "kept body remains" ("let a = 1;" `T.isInfixOf` t)
        assertBool "other body elided" (not ("let b = 2;" `T.isInfixOf` t)),
      testCase "methods inside impl blocks are skeletonised" $ do
        out <- skel Rust "impl Foo {\n    fn method(&self) -> u8 {\n        let secret = 42;\n        secret\n    }\n}\n"
        assertBool "method sig kept" ("fn method(&self) -> u8" `T.isInfixOf` out)
        assertBool "method body elided" (not ("let secret = 42;" `T.isInfixOf` out)),
      testCase "Python bodies are elided" $ do
        out <- skel Python "def greet(name):\n    msg = 'hi ' + name\n    return msg\n"
        assertBool "def kept" ("def greet(name):" `T.isInfixOf` out)
        assertBool "placeholder" ("..." `T.isInfixOf` out)
        assertBool "body elided" (not ("msg = 'hi ' + name" `T.isInfixOf` out)),
      testCase "Python docstring kept when body elided, re-indented placeholder" $ do
        out <- skel Python "def greet(name):\n    \"\"\"Return a friendly greeting for name.\"\"\"\n    msg = 'hi ' + name\n    return msg\n"
        assertBool "docstring kept" ("\"\"\"Return a friendly greeting for name.\"\"\"" `T.isInfixOf` out)
        assertBool "body elided" (not ("msg = 'hi ' + name" `T.isInfixOf` out))
        assertBool "re-indented placeholder" ("\"\"\"\n    ..." `T.isInfixOf` out),
      testCase "Python docstring-only body is kept whole (no stray placeholder)" $ do
        out <- skel Python "def stub():\n    \"\"\"Not implemented yet.\"\"\"\n"
        assertBool "docstring kept" ("\"\"\"Not implemented yet.\"\"\"" `T.isInfixOf` out)
        assertBool "no placeholder" (not ("..." `T.isInfixOf` out)),
      testCase "Python method docstring kept with class-level indent" $ do
        out <- skel Python "class C:\n    def m(self):\n        \"\"\"Do the thing.\"\"\"\n        x = 1\n        return x\n"
        assertBool "method docstring kept" ("\"\"\"Do the thing.\"\"\"" `T.isInfixOf` out)
        assertBool "method body elided" (not ("x = 1" `T.isInfixOf` out))
        assertBool "deep indent preserved" ("\"\"\"\n        ..." `T.isInfixOf` out),
      testCase "TypeScript bodies are elided" $ do
        out <- skel TypeScript "function add(a: number, b: number): number {\n    const s = a + b;\n    return s;\n}\n"
        assertBool "signature kept" ("function add(a: number, b: number): number" `T.isInfixOf` out)
        assertBool "body elided" (not ("const s = a + b;" `T.isInfixOf` out)),
      testCase "an unknown extension yields Nothing" $ do
        r <- Skel.skeletonizePath "notes.md" (BS8.pack "# hi")
        assertBool "unknown → Nothing" (isNothing r)
    ]
  where
    skel :: Lang -> ByteString -> IO Text
    skel lang src = decodeUtf8Lenient <$> Skel.skeleton lang src

-- Symbol-dependency graph (Phase 23b): AST-resolved, scope-aware edges → the radius knob.
symbolTests :: TestTree
symbolTests =
  testGroup
    "context engine (symbols)"
    [ testCase "references in strings and comments do not link" $ do
        g <- Sym.fromSource Rust "fn helper() -> i32 { 1 }\nfn target() -> i32 {\n    // call helper here later\n    let s = \"remember to call helper\";\n    2\n}\n"
        assertBool "no string/comment edge" (not (Set.member "helper" (Sym.neighborsWithin "target" 1 g))),
      testCase "a local shadowing a symbol name does not link" $ do
        g <- Sym.fromSource Rust "fn helper() -> i32 { 1 }\nfn target() -> i32 {\n    let helper = 5;\n    helper + 1\n}\n"
        assertBool "shadowing local excluded" (not (Set.member "helper" (Sym.neighborsWithin "target" 1 g))),
      testCase "graph links caller to callee, excludes unrelated" $ do
        g <- Sym.fromSource Rust src
        let within1 = Sym.neighborsWithin "target" 1 g
        assertBool "target" (Set.member "target" within1)
        assertBool "helper" (Set.member "helper" within1)
        assertBool "not unrelated" (not (Set.member "unrelated" within1)),
      testCase "radius 0 is just the target" $ do
        g <- Sym.fromSource Rust src
        Sym.neighborsWithin "target" 0 g @?= Set.singleton "target",
      testCase "skeleton_with_radius keeps only dependencies" $ do
        out <- decodeUtf8Lenient <$> Sym.skeletonWithRadius Rust "target" 1 src
        assertBool "target body kept" ("helper(41)" `T.isInfixOf` out)
        assertBool "helper body kept" ("x + 1" `T.isInfixOf` out)
        assertBool "unrelated body elided" (not ("    7\n" `T.isInfixOf` out)),
      testCase "radius 0 elides dependencies too" $ do
        out <- decodeUtf8Lenient <$> Sym.skeletonWithRadius Rust "target" 0 src
        assertBool "target body kept" ("helper(41)" `T.isInfixOf` out)
        assertBool "helper body elided at radius 0" (not ("x + 1" `T.isInfixOf` out)),
      testCase "findIdentifierLines matches code, not strings or comments" $ do
        r <- Sym.findIdentifierLines Rust "helper" "fn helper() -> i32 { 1 }\nfn target() -> i32 {\n    // helper is mentioned in this comment\n    let s = \"call helper here\";\n    helper()\n}\n"
        case r of
          Just hits -> do
            map fst hits @?= [1, 5]
            assertBool "call line has helper()" (any (\(ln, t) -> ln == 5 && "helper()" `T.isInfixOf` t) hits)
          Nothing -> assertFailure "expected a parse",
      testCase "findIdentifierLines dedups a line with two uses" $ do
        r <- Sym.findIdentifierLines Rust "g" "fn f() -> i32 { g() + g() }\nfn g() -> i32 { 1 }\n"
        fmap (map fst) r @?= Just [1, 2],
      testCase "multi-file graph links across sources" $ do
        g <- Sym.fromSources [(Rust, "fn caller() -> i32 { shared() }"), (Rust, "fn shared() -> i32 { 5 }")]
        assertBool "caller → shared" (Set.member "shared" (Sym.neighborsWithin "caller" 1 g)),
      testCase "same name across files resolves to the local definition" $ do
        g <-
          Sym.fromSources
            [ (Rust, "fn helper() -> i32 { 0 }\nfn target() -> i32 { helper() }\n"),
              (Rust, "fn helper() -> i32 { dep() }\nfn dep() -> i32 { 9 }\n")
            ]
        let within2 = Sym.neighborsWithin "target" 2 g
        assertBool "local helper linked" (Set.member "helper" within2)
        assertBool "does not reach the other file's dep" (not (Set.member "dep" within2)),
      testCase "neighbors-by-file keeps a body only in its owning file" $ do
        g <-
          Sym.fromSources
            [ (Rust, "fn target() -> i32 { repo() }\nfn noise_a() -> i32 { 0 }"),
              (Rust, "fn repo() -> i32 { 5 }\nfn noise_b() -> i32 { 1 }")
            ]
        let perFile = Sym.neighborsWithinByFile "target" 1 g
        length perFile @?= 2
        assertBool "file 0 has target not repo" (Set.member "target" (perFile !! 0) && not (Set.member "repo" (perFile !! 0)))
        assertBool "file 1 has repo not target" (Set.member "repo" (perFile !! 1) && not (Set.member "target" (perFile !! 1)))
    ]
  where
    src = "fn helper(x: i32) -> i32 {\n    x + 1\n}\n\nfn target() -> i32 {\n    helper(41)\n}\n\nfn unrelated() -> i32 {\n    7\n}\n"

-- Budget-fixture loop (Phase 23b): the deterministic skeleton-radius token lever.
budgetTests :: TestTree
budgetTests =
  testGroup
    "context engine (budget)"
    [ testCase "kept set never shrinks with radius" $ do
        reports <- Bud.sweep demo 3
        let kepts = map Bud.brKeptSymbols reports
        assertBool ("monotonic kept set: " <> show kepts) (and (zipWith (<=) kepts (drop 1 kepts))),
      testCase "radius is a real lever for substantial bodies" $ do
        let bigDep =
              Bud.Fixture
                { Bud.fxName = "big_dep",
                  Bud.fxArchetype = Bud.SingleFileEdit,
                  Bud.fxFiles =
                    [ ( Rust,
                        BS8.pack "fn target() -> i32 { big() }\nfn big() -> i32 {\n    let mut total = 0;\n    for i in 0..100 { total += i * i - 3 * i + 7; }\n    total\n}\n"
                      )
                    ],
                  Bud.fxTarget = "target"
                }
        r0 <- Bud.measure bigDep 0
        r1 <- Bud.measure bigDep 1
        assertBool "radius 1 costs more tokens" (Bud.brEstTokens r1 > Bud.brEstTokens r0),
      testCase "radius expands the kept set along the dependency chain" $ do
        k0 <- Bud.brKeptSymbols <$> Bud.measure demo 0
        k1 <- Bud.brKeptSymbols <$> Bud.measure demo 1
        k2 <- Bud.brKeptSymbols <$> Bud.measure demo 2
        k3 <- Bud.brKeptSymbols <$> Bud.measure demo 3
        (k0, k1, k2, k3) @?= (1, 2, 3, 3)
    ]
  where
    demo =
      Bud.Fixture
        { Bud.fxName = "demo",
          Bud.fxArchetype = Bud.SingleFileEdit,
          Bud.fxFiles =
            [ ( Rust,
                BS8.pack "fn a() -> i32 { b() + 1 }\nfn b() -> i32 { c() + 1 }\nfn c() -> i32 { 1 }\nfn unrelated() -> i32 { 99 }\n"
              )
            ],
          Bud.fxTarget = "a"
        }

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
        agent <- mkAgent stub withBuiltins (defaultAgentConfig "stub") Tn.noopTuner Nothing
        let handle = sessionAgentHandle store agent
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

-- --- Phase 14: ATO tuner (offline; ε-greedy learner, ports lvz-tune tests) ------------------------

-- A single-file-edit context over the default (uncached) capabilities.
tnCtx :: Tn.TaskContext
tnCtx =
  Tn.TaskContext
    { Tn.tcArchetype = Tn.SingleFileEdit,
      Tn.tcRepo = Tn.defaultRepoProfile,
      Tn.tcCaps = noCapabilities,
      Tn.tcModel = Tn.Balanced,
      Tn.tcModelId = "test-model",
      Tn.tcRepoId = "test-repo"
    }

outc :: Word64 -> Bool -> Tn.Outcome
outc tokens ok = Tn.defaultOutcome {Tn.otTotalTokens = tokens, Tn.otRoundTrips = 1, Tn.otSuccess = ok}

-- Deterministic (no-explore) config with an explicit trust bar.
strictCfg :: Double -> TuneConfig
strictCfg d = TuneConfig {epsilon = 0, successTarget = 0.9, minTrials = 3, decay = d}

tuneTests :: TestTree
tuneTests =
  testGroup
    "ato tuner"
    [ testCase "cold select returns the baseline" $ do
        t <- learningTuner (strictCfg 1.0)
        Tn.tunerSelect t tnCtx >>= (@?= Tn.defaultKnobs),
      testCase "thinking is a reachable tunable dial" $ do
        assertBool
          "a thinking-varied neighbour exists"
          (any (isJust . Tn.knobThinking) (allNeighbours Tn.defaultKnobs))
        let up = step Tn.defaultKnobs (dials - 1) True
        assertBool "stepping thinking up leaves the baseline" (isJust (Tn.knobThinking up) && up /= Tn.defaultKnobs),
      testCase "exploits a cheaper trusted candidate" $ do
        t <- learningTuner (strictCfg 1.0)
        let cheaper = Tn.defaultKnobs {Tn.skeletonRadius = 0}
        replicateM_ 3 (Tn.tunerObserve t tnCtx Tn.defaultKnobs (outc 1000 True))
        replicateM_ 3 (Tn.tunerObserve t tnCtx cheaper (outc 600 True))
        Tn.tunerSelect t tnCtx >>= (@?= cheaper),
      testCase "never picks a cheaper-but-failing candidate" $ do
        t <- learningTuner (strictCfg 1.0)
        replicateM_ 4 (Tn.tunerObserve t tnCtx Tn.defaultKnobs (outc 1000 True))
        let starved = Tn.defaultKnobs {Tn.skeletonRadius = 0, Tn.truncateBytes = 2048}
        Tn.tunerObserve t tnCtx starved (outc 300 True)
        replicateM_ 4 (Tn.tunerObserve t tnCtx starved (outc 300 False))
        Tn.tunerSelect t tnCtx >>= (@?= Tn.defaultKnobs),
      testCase "exploration steps one knob and stays within bounds" $ do
        t <- learningTuner (TuneConfig {epsilon = 1, successTarget = 0.9, minTrials = 3, decay = 1})
        replicateM_ 200 $ do
          k <- Tn.tunerSelect t tnCtx
          assertBool "radius" (Tn.skeletonRadius k >= 0 && Tn.skeletonRadius k <= 3)
          assertBool "truncate" (Tn.truncateBytes k >= 2048 && Tn.truncateBytes k <= 32768)
          assertBool "compact" (Tn.compactAfter k >= 8000 && Tn.compactAfter k <= 64000)
          assertBool "batch" (Tn.batchWidth k >= 1 && Tn.batchWidth k <= 8),
      testCase "profiles are isolated by the caching confounder" $ do
        t <- learningTuner (TuneConfig {epsilon = 0, successTarget = 0.9, minTrials = 2, decay = 1})
        let cached = tnCtx {Tn.tcCaps = noCapabilities {promptCaching = True}}
            uncached = tnCtx {Tn.tcCaps = noCapabilities {promptCaching = False}}
            cheaper = Tn.defaultKnobs {Tn.batchWidth = 8}
        replicateM_ 2 (Tn.tunerObserve t cached cheaper (outc 500 True))
        Tn.tunerSelect t uncached >>= (@?= Tn.defaultKnobs)
        Tn.tunerSelect t cached >>= (@?= cheaper),
      testCase "model id keys profiles apart" $ do
        t <- learningTuner (TuneConfig {epsilon = 0, successTarget = 0.9, minTrials = 2, decay = 1})
        let v1 = tnCtx {Tn.tcModelId = "model-v1"}
            v2 = tnCtx {Tn.tcModelId = "model-v2"}
            cheaper = Tn.defaultKnobs {Tn.batchWidth = 8}
        replicateM_ 2 (Tn.tunerObserve t v1 cheaper (outc 500 True))
        Tn.tunerSelect t v1 >>= (@?= cheaper)
        Tn.tunerSelect t v2 >>= (@?= Tn.defaultKnobs),
      testCase "decay lets recent failures dethrone a stale winner" $ do
        let run d = do
              t <- learningTuner (TuneConfig {epsilon = 0, successTarget = 0.9, minTrials = 2, decay = d})
              let cheaper = Tn.defaultKnobs {Tn.skeletonRadius = 0}
              replicateM_ 30 (Tn.tunerObserve t tnCtx cheaper (outc 600 True))
              replicateM_ 3 (Tn.tunerObserve t tnCtx cheaper (outc 600 False))
              Tn.tunerSelect t tnCtx
        let cheaper = Tn.defaultKnobs {Tn.skeletonRadius = 0}
        run 1.0 >>= (@?= cheaper) -- 30/33 ≈ 0.909 ≥ target: still trusted
        run 0.9 >>= (@?= Tn.defaultKnobs), -- EWMA: recent failures drop it below target
      testCase "counterfactual credits a provably-equivalent cheaper truncate" $ do
        t <- learningTuner (strictCfg 1.0)
        let out = (outc 1000 True) {Tn.otMaxToolResultBytes = Just 1500}
        replicateM_ 3 (Tn.tunerObserve t tnCtx Tn.defaultKnobs out)
        chosen <- Tn.truncateBytes <$> Tn.tunerSelect t tnCtx
        assertBool "credited a cheaper value (2048/4096)" (chosen == 2048 || chosen == 4096)
        assertBool "below the default 8192" (chosen < Tn.truncateBytes Tn.defaultKnobs),
      testCase "save and load round-trips profiles" $ withTmp "tune" $ \dir -> do
        let path = dir </> "state.json"
        lt <- newLearningTuner (strictCfg 1.0)
        let t = asTuner lt
            cheaper = Tn.defaultKnobs {Tn.skeletonRadius = 0}
        replicateM_ 3 $ do
          Tn.tunerObserve t tnCtx Tn.defaultKnobs (outc 1000 True)
          Tn.tunerObserve t tnCtx cheaper (outc 600 True)
        Tn.tunerSelect t tnCtx >>= (@?= cheaper)
        saveTuner lt path
        -- A fresh tuner loaded from the snapshot picks the same learned winner.
        reloaded <- loadTuner path (strictCfg 1.0)
        case reloaded of
          Left e -> assertFailure ("load failed: " <> e)
          Right lt2 -> Tn.tunerSelect (asTuner lt2) tnCtx >>= (@?= cheaper)
        -- A missing file loads cold (baseline), not an error.
        cold <- loadTuner (dir </> "does-not-exist.json") (strictCfg 1.0)
        case cold of
          Left e -> assertFailure ("cold load errored: " <> e)
          Right ltc -> Tn.tunerSelect (asTuner ltc) tnCtx >>= (@?= Tn.defaultKnobs)
    ]

-- --- Phase 14b: Bayesian (Thompson) ATO tuner (offline; ports lvz-tune bayes.rs tests) ------------

-- Count how often selecting over @tnCtx@ returns a given knob vector, across @n@ draws.
countPicks :: Tn.Tuner -> Tn.Knobs -> Int -> IO Int
countPicks t k n = length . filter (== k) <$> replicateM n (Tn.tunerSelect t tnCtx)

-- Mean of @n@ Beta(a,b) samples threaded from a seed (the PRNG is pure/explicit).
betaMean :: Double -> Double -> Int -> Word64 -> Double
betaMean a b n seed = go n seed 0 / fromIntegral n
  where
    go 0 _ acc = acc
    go k r acc = let (x, r') = sampleBeta a b r in go (k - 1) r' (acc + x)

bayesTests :: TestTree
bayesTests =
  testGroup
    "ato tuner (bayes)"
    [ testCase "beta samples track their parameters" $ do
        let high = betaMean 20 2 4000 12345
            low = betaMean 2 20 4000 6789
        assertBool ("high mean " <> show high) (high > 0.82 && high < 0.97)
        assertBool ("low mean " <> show low) (low > 0.03 && low < 0.18),
      testCase "converges to a cheaper reliable vector" $ do
        t <- bayesTuner defaultTuneConfig
        let cheaper = Tn.defaultKnobs {Tn.skeletonRadius = 0}
        replicateM_ 60 $ do
          Tn.tunerObserve t tnCtx Tn.defaultKnobs (outc 1000 True)
          Tn.tunerObserve t tnCtx cheaper (outc 600 True)
        cheaperPicks <- countPicks t cheaper 200
        baselinePicks <- countPicks t Tn.defaultKnobs 200
        assertBool
          ("cheaper=" <> show cheaperPicks <> " baseline=" <> show baselinePicks)
          (cheaperPicks > baselinePicks * 3 && cheaperPicks > 80),
      testCase "avoids a cheap but failing vector" $ do
        t <- bayesTuner defaultTuneConfig
        let starved = Tn.defaultKnobs {Tn.skeletonRadius = 0, Tn.truncateBytes = 2048}
        replicateM_ 40 (Tn.tunerObserve t tnCtx Tn.defaultKnobs (outc 1000 True))
        Tn.tunerObserve t tnCtx starved (outc 300 True)
        replicateM_ 40 (Tn.tunerObserve t tnCtx starved (outc 300 False))
        picks <- countPicks t starved 200
        assertBool ("starved picked " <> show picks <> "/200") (picks < 20),
      testCase "save and load round-trips posteriors" $ withTmp "bayes" $ \dir -> do
        let path = dir </> "state.json"
        bt <- newBayesTuner defaultTuneConfig
        let t = asBayesTuner bt
            cheaper = Tn.defaultKnobs {Tn.skeletonRadius = 0}
        replicateM_ 60 $ do
          Tn.tunerObserve t tnCtx Tn.defaultKnobs (outc 1000 True)
          Tn.tunerObserve t tnCtx cheaper (outc 600 True)
        saveBayes bt path
        reloaded <- loadBayes path defaultTuneConfig
        case reloaded of
          Left e -> assertFailure ("load failed: " <> e)
          Right bt2 -> do
            cp <- countPicks (asBayesTuner bt2) cheaper 200
            bp <- countPicks (asBayesTuner bt2) Tn.defaultKnobs 200
            assertBool
              ("reloaded cheaper=" <> show cp <> " baseline=" <> show bp)
              (cp > bp * 3 && cp > 80)
        -- A missing file loads cold (no error); a cold Thompson sampler still selects a valid vector.
        cold <- loadBayes (dir </> "missing.json") defaultTuneConfig
        case cold of
          Left e -> assertFailure ("cold load errored: " <> e)
          Right btc -> do
            k <- Tn.tunerSelect (asBayesTuner btc) tnCtx
            assertBool "valid grid vector" (Tn.skeletonRadius k <= 3 && Tn.batchWidth k >= 1 && Tn.batchWidth k <= 8)
    ]

-- --- Phase 15: claude-cli provider (offline; the stream-json Decoder, ports lvz-claude-cli tests) --

-- Fold lines through the decoder then EOF, keeping the successful events.
ccDecode :: [Text] -> [Event]
ccDecode ls =
  let (d, evs) = foldl stepLine (initDecoder, []) ls
      (_, eofEvs) = eofDecoder d
   in [e | Right e <- evs <> eofEvs]
  where
    stepLine (dc, acc) l = let (dc', more) = pushLine dc l in (dc', acc <> more)

claudeCliTests :: TestTree
claudeCliTests =
  testGroup
    "claude-cli provider"
    [ testCase "renders the conversation with role labels" $ do
        let req =
              (chatRequest "sonnet")
                { crMessages = [userMessage "hello", assistantMessage "hi there", userMessage "more"]
                }
        renderPrompt req @?= "User: hello\n\nAssistant: hi there\n\nUser: more\n\n",
      testCase "streams partial deltas, then usage and done" $ do
        let evs =
              ccDecode
                [ "{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"sonnet\"}",
                  "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}}",
                  "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}}",
                  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]}}",
                  "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"usage\":{\"input_tokens\":12,\"output_tokens\":3}}"
                ]
        take 2 evs @?= [TextDelta "Hel", TextDelta "lo"]
        case evs !! 2 of
          Usage u -> do
            inputTokens u @?= 12
            outputTokens u @?= 3
          o -> assertFailure ("expected usage, got " <> show o)
        evs !! 3 @?= Done EndTurn
        length evs @?= 4, -- the assembled `assistant` message is suppressed (no dup)
      testCase "falls back to the assistant message when no partials" $ do
        let evs =
              ccDecode
                [ "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"thinking\",\"thinking\":\"hmm\"},{\"type\":\"text\",\"text\":\"answer\"}]}}",
                  "{\"type\":\"result\",\"subtype\":\"success\",\"usage\":{\"input_tokens\":5,\"output_tokens\":2}}"
                ]
        take 2 evs @?= [Thinking "hmm", TextDelta "answer"]
        case evs !! 2 of
          Usage _ -> pure ()
          o -> assertFailure ("expected usage, got " <> show o)
        evs !! 3 @?= Done EndTurn,
      testCase "an error result maps to Other, and EOF guarantees exactly one Done" $ do
        let err =
              ccDecode
                ["{\"type\":\"result\",\"subtype\":\"error_max_turns\",\"is_error\":true,\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}"]
        last err @?= Done (Other "claude_cli_error")
        let truncated =
              ccDecode
                ["{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"hi\"}}}"]
        truncated @?= [TextDelta "hi", Done EndTurn]
    ]

-- --- Phase 16: legion council (offline; scripted providers, ports lvz-legion tests) ---------------

-- A provider that replies with one fixed text (+ usage), or always errors.
scriptedProv :: Text -> Usage -> Bool -> Provider
scriptedProv reply usage failing =
  Provider
    { providerStream = \_ ->
        if failing
          then pure (Left (PTransport "scripted failure"))
          else do
            s <- fromList [Right (TextDelta reply), Right (Usage usage), Right (Done EndTurn)]
            pure (Right s),
      providerCapabilities = noCapabilities,
      providerCountTokens = \_ -> pure (Right Nothing)
    }

-- A debater whose every call yields `reply` and 10 output tokens.
debaterD :: Text -> Text -> Debater
debaterD name reply = mkDebater name (scriptedProv reply (MkUsage 0 10 0 0) False) (name <> "-model") Nothing

-- A debater whose every call errors.
failingD :: Text -> Debater
failingD name = mkDebater name (scriptedProv "" emptyUsage True) (name <> "-model") Nothing

-- A provider that records every system prompt it streams under, then replies with a fixed text.
capturingProv :: IORef [Text] -> Text -> Provider
capturingProv ref reply =
  Provider
    { providerStream = \req -> do
        modifyIORef' ref (<> [maybe "" spText (crSystem req)])
        s <- fromList [Right (TextDelta reply), Right (Usage emptyUsage), Right (Done EndTurn)]
        pure (Right s),
      providerCapabilities = noCapabilities,
      providerCountTokens = \_ -> pure (Right Nothing)
    }

legionTests :: TestTree
legionTests =
  testGroup
    "legion council"
    [ testCase "a panel rejects fewer than two debaters" $
        case newPanel [debaterD "solo" "x"] (debaterD "judge" "v") 1 of
          Left (TooFewDebaters 1) -> pure ()
          Left e -> assertFailure ("expected TooFewDebaters 1, got " <> show e)
          Right _ -> assertFailure "expected TooFewDebaters, got a valid panel",
      testCase "deliberate drafts, critiques, and judges" $
        withPanel [debaterD "a" "position A", debaterD "b" "position B"] (debaterD "judge" "AGREED PLAN") 1 $ \panel -> do
          r <- deliberate (panelDeliberator panel) "do the thing"
          case r of
            Right del -> do
              delPlan del @?= "AGREED PLAN"
              -- 2 drafts + 2 critiques (1 round) + 1 judge = 5 calls × 10 output tokens.
              outputTokens (delUsage del) @?= 50
            Left e -> assertFailure ("deliberation failed: " <> show e),
      testCase "the rounds knob changes the call count" $
        withPanel [debaterD "a" "A", debaterD "b" "B"] (debaterD "judge" "PLAN") 0 $ \panel -> do
          r <- deliberate (panelDeliberator panel) "task"
          case r of
            -- 2 drafts + 0 critiques + 1 judge = 3 × 10.
            Right del -> outputTokens (delUsage del) @?= 30
            Left e -> assertFailure ("deliberation failed: " <> show e),
      testCase "a failing debater is tolerated" $
        withPanel [failingD "a", debaterD "b" "position B"] (debaterD "judge" "PLAN") 1 $ \panel -> do
          r <- deliberate (panelDeliberator panel) "task"
          case r of
            Right del -> do
              delPlan del @?= "PLAN"
              -- Only debater b contributes: 1 draft + 1 critique + 1 judge = 3 × 10.
              outputTokens (delUsage del) @?= 30
            Left e -> assertFailure ("deliberation failed: " <> show e),
      testCase "all debaters failing yields NoPositions" $
        withPanel [failingD "a", failingD "b"] (debaterD "judge" "PLAN") 1 $ \panel -> do
          r <- deliberate (panelDeliberator panel) "task"
          case r of
            Left NoPositions -> pure ()
            other -> assertFailure ("expected NoPositions, got " <> show (fmap delPlan other)),
      testCase "context grounds every debater with the persona and tools" $ do
        ref <- newIORef []
        let a = mkDebater "a" (capturingProv ref "A") "a-model" Nothing
            b = mkDebater "b" (capturingProv ref "B") "b-model" Nothing
            judge = mkDebater "judge" (capturingProv ref "PLAN") "judge-model" Nothing
            tools = [ToolDef "start_broadcast" "Start a live broadcast" (object []) False False]
            dctx = DeliberationContext "You are Lav, the parish broadcast bot." tools Nothing
        withPanel [a, b] judge 1 $ \panel -> do
          r <- runDeliberation (panelDeliberator panel) "start the service" dctx
          case r of
            Right del -> delPlan del @?= "PLAN"
            Left e -> assertFailure ("deliberation failed: " <> show e)
          seen <- readIORef ref
          assertBool "some system prompts captured" (not (null seen))
          mapM_
            ( \s -> do
                assertBool "persona present" ("You are Lav, the parish broadcast bot." `T.isInfixOf` s)
                assertBool "tool catalogue present" ("start_broadcast" `T.isInfixOf` s)
            )
            seen,
      testCase "progress notices are emitted per phase (English)" $ do
        notices <- newIORef []
        let dctx = DeliberationContext "" [] (Just (\m -> modifyIORef' notices (<> [m])))
        withPanel [debaterD "a" "A", debaterD "b" "B"] (debaterD "judge" "PLAN") 1 $ \panel -> do
          _ <- runDeliberation (panelDeliberator panel) "task" dctx
          ns <- readIORef notices
          assertBool "convened" (any ("council convened" `T.isInfixOf`) ns)
          assertBool "critique 1/1" (any ("critique round 1/1" `T.isInfixOf`) ns)
          assertBool "judge" (any ("judge synthesising" `T.isInfixOf`) ns),
      testCase "progress notices localise to Korean when set" $ do
        notices <- newIORef []
        let dctx = DeliberationContext "" [] (Just (\m -> modifyIORef' notices (<> [m])))
        case newPanel [debaterD "a" "A", debaterD "b" "B"] (debaterD "judge" "PLAN") 1 of
          Left e -> assertFailure (show e)
          Right panel0 -> do
            _ <- runDeliberation (panelDeliberator (withLanguage Korean panel0)) "task" dctx
            ns <- readIORef notices
            assertBool "convened" (any ("위원회 소집" `T.isInfixOf`) ns)
            assertBool "critique" (any ("비평 라운드 1/1" `T.isInfixOf`) ns)
            assertBool "judge" (any ("결론을 종합" `T.isInfixOf`) ns),
      testCase "languageFromLocale only ko_KR selects Korean" $ do
        languageFromLocale "ko_KR.UTF-8" @?= Korean
        languageFromLocale "KO_KR" @?= Korean
        languageFromLocale "ko_kr.utf-8" @?= Korean
        languageFromLocale "en_US.UTF-8" @?= English
        languageFromLocale "ko" @?= English
        languageFromLocale "" @?= English
    ]
  where
    -- Build a panel and run the body, failing the test if the panel is rejected.
    withPanel debs judge rounds body =
      case newPanel debs judge rounds of
        Left e -> assertFailure ("panel build failed: " <> show e)
        Right panel -> body panel

-- --- Phase 17: Slack gateway (offline; the pure Socket-Mode event parser, ports lvz-gw-slack) ------

slackTests :: TestTree
slackTests =
  testGroup
    "slack gateway"
    [ testCase "parses a plain message" $
        case parseEvent (payload (ev "message" "U_ALICE" "hello bot" "C1" Nothing)) "U_BOT" Nothing of
          Just m -> do
            smChannel m @?= "C1"
            smText m @?= "hello bot"
            smThreadTs m @?= Nothing
            slackSession m @?= "slack:C1"
          Nothing -> assertFailure "expected a message",
      testCase "app_mention strips the bot mention and threads" $
        case parseEvent (payload (ev "app_mention" "U_ALICE" "<@U_BOT> do a thing" "C1" (Just "1700000000.0001"))) "U_BOT" Nothing of
          Just m -> do
            smText m @?= "do a thing"
            smThreadTs m @?= Just "1700000000.0001"
            slackSession m @?= "slack:C1:1700000000.0001"
          Nothing -> assertFailure "expected a threaded message",
      testCase "skips self, bots, subtypes, non-message, and empty text" $ do
        let skip lbl e = assertBool lbl (isNothing (parseEvent (payload e) "U_BOT" Nothing))
        skip "own message" (ev "message" "U_BOT" "hi" "C1" Nothing)
        skip "bot message" (object ["type" .= t "message", "bot_id" .= t "B1", "text" .= t "hi", "channel" .= t "C1"])
        skip "edited (subtype)" (object ["type" .= t "message", "subtype" .= t "message_changed", "user" .= t "U_A", "text" .= t "hi", "channel" .= t "C1"])
        skip "non-message" (object ["type" .= t "reaction_added", "user" .= t "U_A", "channel" .= t "C1"])
        skip "empty text" (ev "message" "U_A" "   " "C1" Nothing),
      testCase "the allowlist filters senders" $ do
        let allowed = Just (Set.fromList ["U_ALICE"])
            alice = ev "message" "U_ALICE" "hi" "C1" Nothing
            mallory = ev "message" "U_MALLORY" "hi" "C1" Nothing
        assertBool "alice allowed" (isJust (parseEvent (payload alice) "U_BOT" allowed))
        assertBool "mallory blocked" (isNothing (parseEvent (payload mallory) "U_BOT" allowed))
        assertBool "no allowlist ⇒ answered" (isJust (parseEvent (payload mallory) "U_BOT" Nothing)),
      testCase "senderAllowed semantics" $ do
        let allowed = Just (Set.fromList ["U_A"])
        senderAllowed Nothing "U_ANYONE" @?= True
        senderAllowed allowed "U_A" @?= True
        senderAllowed allowed "U_B" @?= False
    ]
  where
    payload e = object ["event" .= e]
    ev etype user text channel threadTs =
      object $
        ["type" .= t etype, "user" .= t user, "text" .= t text, "channel" .= t channel]
          <> maybe [] (\ts -> ["thread_ts" .= t ts]) threadTs
    t = id :: Text -> Text

-- --- Phase 18: cron engine + gateway (offline; ports lvz-schedule cron.rs + lvz-gw-cron) ----------

cronTests :: TestTree
cronTests =
  testGroup
    "cron"
    [ testCase "civil epoch is a Thursday" $ do
        let c = civilFromUnix 0
        (cvMonth c, cvDom c, cvHour c, cvMinute c) @?= (1, 1, 0, 0)
        cvDow c @?= 4,
      testCase "civil known timestamp" $ do
        -- 1_700_000_000 = 2023-11-14 22:13:20 UTC, a Tuesday.
        let c = civilFromUnix 1700000000
        (cvMonth c, cvDom c) @?= (11, 14)
        (cvHour c, cvMinute c) @?= (22, 13)
        cvDow c @?= 2,
      testCase "every minute matches the next minute" $ do
        s <- parseOk "* * * * *"
        nextAfter s 100 @?= Just 120
        nextAfter s 120 @?= Just 180,
      testCase "step minutes fire on the quarter hours" $ do
        s <- parseOk "*/15 * * * *"
        let base = 16 * 3600 + 7 * 60
        (cvMinute . civilFromUnix <$> nextAfter s base) @?= Just 15,
      testCase "daily midnight rolls to the next day" $ do
        s <- parseOk "0 0 * * *"
        case nextAfter s 1700000000 of
          Just next -> do
            let c = civilFromUnix next
            (cvHour c, cvMinute c) @?= (0, 0)
            cvDom c @?= 15
          Nothing -> assertFailure "expected a fire",
      testCase "the 7 alias equals Sunday 0" $ do
        a <- parseOk "0 0 * * 0"
        b <- parseOk "0 0 * * 7"
        nextAfter a 0 @?= nextAfter b 0
        (cvDow . civilFromUnix <$> nextAfter a 0) @?= Just 0,
      testCase "dom-or-dow when both are restricted (Vixie)" $ do
        s <- parseOk "0 0 1 * 1"
        case nextAfter s 0 of
          Just next -> let c = civilFromUnix next in assertBool "1st or Monday" (cvDom c == 1 || cvDow c == 1)
          Nothing -> assertFailure "expected a fire",
      testCase "an impossible date has no fire" $ do
        s <- parseOk "0 0 30 2 *" -- Feb 30 never occurs
        nextAfter s 0 @?= Nothing,
      testCase "rejects bad expressions" $ do
        parseCron "* * * *" @?= Left (CronFieldCount 4)
        assertBool "minute > 59" (isLeftE (parseCron "60 * * * *"))
        assertBool "hour > 23" (isLeftE (parseCron "* 24 * * *"))
        assertBool "zero step" (isLeftE (parseCron "*/0 * * * *"))
        assertBool "inverted range" (isLeftE (parseCron "5-1 * * * *"))
        assertBool "non-numeric" (isLeftE (parseCron "x * * * *")),
      testCase "parse_cli splits the schedule from the prompt" $
        case parseCliJob "*/30 9-17 * * 1-5 check CI and report failures" 2 0 0 of
          Right j -> do
            cjSession j @?= "cron-2"
            cjPrompt j @?= "check CI and report failures"
          Left e -> assertFailure (show e),
      testCase "parse_cli requires a prompt" $
        case parseCliJob "* * * * *" 0 0 0 of
          Left (CCEMissingPrompt _) -> pure ()
          other -> assertFailure ("expected MissingPrompt, got " <> show other),
      testCase "parse_cli applies the global retry defaults" $
        case parseCliJob "* * * * * ping" 0 3 30 of
          Right j -> (cjRetryMax j, cjRetryWait j) @?= (3, 30)
          Left e -> assertFailure (show e),
      testCase "parse_file reads jobs with session defaults" $ do
        let json = "[{\"schedule\":\"0 9 * * *\",\"session\":\"digest\",\"prompt\":\"morning digest\"},{\"schedule\":\"*/15 * * * *\",\"prompt\":\"poll the queue\"}]"
        case parseFileJobs json 0 0 of
          Right [j0, j1] -> do
            cjSession j0 @?= "digest"
            cjSession j1 @?= "cron-1"
            cjPrompt j1 @?= "poll the queue"
          Right _ -> assertFailure "expected two jobs"
          Left e -> assertFailure (show e),
      testCase "parse_file per-job retry overrides the global default" $ do
        let json = "[{\"schedule\":\"0 9 * * *\",\"prompt\":\"defaults\"},{\"schedule\":\"0 9 * * *\",\"prompt\":\"override\",\"retry_max\":5,\"retry_wait\":120}]"
        case parseFileJobs json 2 60 of
          Right [j0, j1] -> do
            (cjRetryMax j0, cjRetryWait j0) @?= (2, 60)
            (cjRetryMax j1, cjRetryWait j1) @?= (5, 120)
          Right _ -> assertFailure "expected two jobs"
          Left e -> assertFailure (show e),
      testCase "parse_file surfaces a bad schedule" $
        assertBool "bad schedule" (isLeftCfg (parseFileJobs "[{\"schedule\":\"bad\",\"prompt\":\"x\"}]" 0 0))
    ]
  where
    parseOk e = either (assertFailure . ("bad cron: " <>) . show) pure (parseCron e)
    isLeftE = either (const True) (const False)
    isLeftCfg = either (const True) (const False)

-- --- Phase 19: xAI provider (offline; OpenAI-compat request + SSE decoder, ports lvz-xai http.rs) --

xaiDecode :: ByteString -> [Event]
xaiDecode input = let (st, e1) = XS.ssePush XS.initSse input in [e | Right e <- e1 <> XS.sseEof st]

xaiTests :: TestTree
xaiTests =
  testGroup
    "xAI (OpenAI-compat)"
    [ testCase "system prompt leads and tools are function-shaped" $ do
        let req =
              (chatRequest "grok-4")
                { crSystem = Just (SystemPrompt "be terse" False),
                  crMessages = [userMessage "hi"],
                  crTools = [ToolDef "list_dir" "list a dir" (object ["type" .= ("object" :: Text)]) False False]
                }
            msgs = buildMessages req
        roleAt msgs 0 @?= Just "system"
        roleAt msgs 1 @?= Just "user",
      testCase "tool_use and tool_result map to OpenAI shape" $ do
        let req =
              (chatRequest "grok-4")
                { crMessages =
                    [ userMessage "go",
                      Message Assistant [ToolUseBlock "call_1" "shell" (object ["command" .= ("ls" :: Text)])],
                      Message User [ToolResultBlock "call_1" "files" False]
                    ]
                }
            msgs = buildMessages req
        -- user, assistant(tool_calls), tool(result)
        roleAt msgs 1 @?= Just "assistant"
        strAt msgs 1 ["tool_calls", "0", "id"] @?= Just "call_1"
        strAt msgs 1 ["tool_calls", "0", "function", "name"] @?= Just "shell"
        roleAt msgs 2 @?= Just "tool"
        strAt msgs 2 ["tool_call_id"] @?= Just "call_1"
        strAt msgs 2 ["content"] @?= Just "files",
      testCase "decodes text, usage, done in order" $ do
        let evs =
              xaiDecode $
                BS.concat
                  [ "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
                    "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2}}\n\n",
                    "data: [DONE]\n\n"
                  ]
        take 2 evs @?= [TextDelta "Hel", TextDelta "lo"]
        case evs !! 2 of
          Usage u -> do
            inputTokens u @?= 5
            outputTokens u @?= 2
          o -> assertFailure ("expected usage, got " <> show o)
        evs !! 3 @?= Done EndTurn
        length evs @?= 4,
      testCase "decodes a streamed tool call" $ do
        let evs =
              xaiDecode $
                BS.concat
                  [ "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_9\",\"type\":\"function\",\"function\":{\"name\":\"list_dir\",\"arguments\":\"\"}}]}}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"path\\\":\"}}]}}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\".\\\"}\"}}]}}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
                    "data: [DONE]\n\n"
                  ]
        evs
          @?= [ ToolUseStart "call_9" "list_dir",
                ToolUseDelta "call_9" "{\"path\":",
                ToolUseDelta "call_9" "\".\"}",
                ToolUseEnd "call_9",
                Done ToolUse
              ],
      testCase "reassembles lines split across chunk boundaries" $ do
        let sample = "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
            byteAtATime = let (st, evs) = BS.foldl' stepB (XS.initSse, []) sample in [e | Right e <- evs <> XS.sseEof st]
            stepB (s, acc) b = let (s', more) = XS.ssePush s (BS.singleton b) in (s', acc <> more)
        byteAtATime @?= [TextDelta "hi", Done EndTurn],
      testCase "maps finish reasons" $ do
        XS.mapStop "stop" @?= EndTurn
        XS.mapStop "length" @?= MaxTokens
        XS.mapStop "tool_calls" @?= ToolUse
        XS.mapStop "weird" @?= Other "weird"
    ]
  where
    roleAt msgs i = strAt msgs i ["role"]
    -- Walk a path of object keys / array indices into the i-th message, returning a leaf string.
    strAt msgs i path = case drop i msgs of
      (m : _) -> walk path m
      [] -> Nothing
    walk [] (String s) = Just s
    walk (k : ks) (Object o) = KM.lookup (K.fromText k) o >>= walk ks
    walk (k : ks) (Array a) = case reads (T.unpack k) of
      [(n, "")] | n >= 0 && n < V.length a -> walk ks (a V.! n)
      _ -> Nothing
    walk _ _ = Nothing

-- --- Phase 20: plaintext Matrix gateway (offline; the pure engagement/extraction logic) -----------

-- A minimal /sync response with one m.room.message in a joined room.
syncWith :: Value -> Value
syncWith event =
  object ["next_batch" .= t "s2", "rooms" .= object ["join" .= object ["!room:hs" .= joined]]]
  where
    joined = object ["timeline" .= object ["events" .= [event]]]
    t = id :: Text -> Text

msgEvent :: Text -> Text -> Value -> Value
msgEvent sender eid content =
  object ["type" .= t "m.room.message", "sender" .= sender, "event_id" .= eid, "content" .= content]
  where
    t = id :: Text -> Text

textContent :: Text -> Value
textContent body = object ["msgtype" .= t "m.text", "body" .= body] where t = id :: Text -> Text

matrixTests :: TestTree
matrixTests =
  testGroup
    "matrix gateway"
    [ testCase "extracts an m.text message and skips the bot's own" $ do
        let sync = object ["next_batch" .= t "s", "rooms" .= object ["join" .= object ["!r:hs" .= room]]]
            room = object ["timeline" .= object ["events" .= [mine, theirs]]]
            mine = msgEvent "@bot:hs" "$1" (textContent "i am the bot")
            theirs = msgEvent "@alice:hs" "$2" (textContent "hello bot")
            msgs = MX.extractMessages sync "@bot:hs" Nothing Nothing
        map MX.imSender msgs @?= ["@alice:hs"]
        map MX.imBody msgs @?= ["hello bot"],
      testCase "the sender allowlist filters extraction" $ do
        let sync = syncWith (msgEvent "@mallory:hs" "$1" (textContent "hi"))
            allowed = Just (Set.fromList ["@alice:hs"])
        MX.extractMessages sync "@bot:hs" allowed Nothing @?= []
        length (MX.extractMessages sync "@bot:hs" Nothing Nothing) @?= 1,
      testCase "the room allowlist filters extraction" $ do
        let sync = syncWith (msgEvent "@alice:hs" "$1" (textContent "hi")) -- room is !room:hs
        MX.extractMessages sync "@bot:hs" Nothing (Just (Set.fromList ["!other:hs"])) @?= []
        length (MX.extractMessages sync "@bot:hs" Nothing (Just (Set.fromList ["!room:hs"]))) @?= 1,
      testCase "mentionsBot: m.mentions, textual @localpart, and MXID" $ do
        let viaMentions = object ["msgtype" .= t "m.text", "body" .= t "hey", "m.mentions" .= object ["user_ids" .= [t "@bot:hs"]]]
            viaHandle = textContent "hey @bot please help"
            viaMxid = textContent "cc @bot:hs"
            noMention = textContent "just chatting"
        MX.mentionsBot viaMentions "@bot:hs" @?= True
        MX.mentionsBot viaHandle "@bot:hs" @?= True
        MX.mentionsBot viaMxid "@bot:hs" @?= True
        MX.mentionsBot noMention "@bot:hs" @?= False,
      testCase "replyTarget reads m.relates_to → m.in_reply_to" $ do
        let content = object ["msgtype" .= t "m.text", "body" .= t "re", "m.relates_to" .= object ["m.in_reply_to" .= object ["event_id" .= t "$orig"]]]
        MX.replyTarget content @?= Just "$orig"
        MX.replyTarget (textContent "plain") @?= Nothing,
      testCase "messageTriggers: DM always, else mention or reply-to-own" $ do
        recent <- MX.newRecentIds 8
        MX.insertRecent recent "$mine"
        (MX.messageTriggers True False Nothing recent >>= (@?= True)) -- DM
        (MX.messageTriggers False True Nothing recent >>= (@?= True)) -- mention
        (MX.messageTriggers False False (Just "$mine") recent >>= (@?= True)) -- reply to ours
        (MX.messageTriggers False False (Just "$other") recent >>= (@?= False))
        MX.messageTriggers False False Nothing recent >>= (@?= False),
      testCase "toolsFor intersects room and user permissions" $ do
        let cfg =
              (MX.defaultMatrixConfig "https://hs" "@bot:hs")
                { MX.mcRoomTools = Map.fromList [("!r:hs", ["read_file", "shell", "write_file"])],
                  MX.mcUserTools = Map.fromList [("@alice:hs", ["read_file", "shell"])]
                }
        MX.toolsFor cfg "!r:hs" "@alice:hs" @?= Just ["read_file", "shell"] -- intersection
        MX.toolsFor cfg "!r:hs" "@bob:hs" @?= Just ["read_file", "shell", "write_file"] -- room only
        MX.toolsFor cfg "!other:hs" "@alice:hs" @?= Just ["read_file", "shell"] -- user only
        MX.toolsFor cfg "!other:hs" "@bob:hs" @?= Nothing, -- unconstrained
      testCase "RecentIds is bounded and FIFO-evicts" $ do
        recent <- MX.newRecentIds 2
        mapM_ (MX.insertRecent recent) ["$a", "$b", "$c"]
        -- \$a evicted
        MX.containsRecent recent "$a" >>= (@?= False)
        MX.containsRecent recent "$b" >>= (@?= True)
        MX.containsRecent recent "$c" >>= (@?= True),
      testCase "extractInvites and parseNextBatch" $ do
        let sync = object ["next_batch" .= t "tok", "rooms" .= object ["invite" .= object ["!inv:hs" .= object []]]]
        MX.extractInvites sync @?= ["!inv:hs"]
        MX.parseNextBatch sync @?= Right "tok"
        assertBool "no next_batch is an error" (isLeftE (MX.parseNextBatch (object [])))
    ]
  where
    t = id :: Text -> Text
    isLeftE = either (const True) (const False)

-- Run an action in a fresh temp directory, cleaned up afterwards.
withTmp :: String -> (FilePath -> IO a) -> IO a
withTmp name k = do
  base <- getTemporaryDirectory
  let dir = base </> ("lavoisier-hs-test-" <> name)
  createDirectoryIfMissing True dir
  r <- k dir
  removeDirectoryRecursive dir
  pure r
