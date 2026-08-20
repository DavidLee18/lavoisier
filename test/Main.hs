{-# LANGUAGE OverloadedLabels #-}
-- Orphan Arbitrary instances for the library's types are the idiomatic place for test generators.
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (IOException, try)
import Control.Monad (replicateM, replicateM_, void)
import Data.Aeson (Value (..), decode, encode, object, toJSON, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BL
import Data.Char (isHexDigit)
import Data.IORef
import Data.List (find, isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.ProtoLens (defMessage)
import Data.ProtoLens.Labels ()
import Data.Scientific (toBoundedInteger)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Data.Word (Word64, Word8)
import Lavoisier.Agent
import Lavoisier.CLI qualified as CLI
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
import Lavoisier.Gateway.Acp qualified as Acp
import Lavoisier.Gateway.Cron (CronConfigError (..), CronJob (..), loadFileJobs, parseCliJob)
import Lavoisier.Gateway.Http (GatewayConfig (..), defaultGatewayConfig, httpApp, newHttpApp, stepWindow, wsAuthorized, wsPrincipal)
import Lavoisier.Gateway.Matrix qualified as MX
import Lavoisier.Gateway.Slack (SlackMessage (..), parseEvent, senderAllowed, slackSession)
import Lavoisier.Gateway.Tui qualified as Tui
import Lavoisier.Gateway.Tui.Gate qualified as TG
import Lavoisier.Gateway.Tui.Md qualified as Md
import Lavoisier.Gateway.Tui.Price qualified as Price
import Lavoisier.Legion (Debater, Language (..), LegionError (..), languageFromLocale, mkDebater, newPanel, panelDeliberator, withLanguage)
import Lavoisier.Log (LogLevel (..), parseLogLevel)
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
import Lavoisier.Protocol.Agent (AgentError (..), AgentHandle (..), turnRequest, withModel)
import Lavoisier.Protocol.Batch (Batch (..), BatchItem (..), BatchTask (..))
import Lavoisier.Protocol.Deliberate (DeliberateError (..), Deliberation (..), DeliberationContext (..), deliberate, runDeliberation)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Gate (ToolDecision (..), ToolGate (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Protocol.Stream (drain, fromList)
import Lavoisier.Protocol.Tool
import Lavoisier.Protocol.Tune qualified as Tn
import Lavoisier.Provider.Anthropic (buildBody)
import Lavoisier.Provider.Anthropic.Batch (batchRequestsBody, parseResultLine)
import Lavoisier.Provider.Anthropic.Sse (initSse, mapStop, sseEof, ssePush)
import Lavoisier.Provider.ClaudeCli (eofDecoder, initDecoder, pushLine, renderPrompt)
import Lavoisier.Provider.Google qualified as G
import Lavoisier.Provider.Google.Batch qualified as GB
import Lavoisier.Provider.Google.Sse qualified as GS
import Lavoisier.Provider.Xai (buildMessages)
import Lavoisier.Provider.Xai.Grpc qualified as XG
import Lavoisier.Provider.Xai.Sse qualified as XS
import Lavoisier.Schedule qualified as Sch
import Lavoisier.Schedule.Cron (Civil (..), CronError (..), civilFromUnix, nextAfter, parseCron)
import Lavoisier.Tool.Batch (applyResponse, batchEditTool, stripCodeFence)
import Lavoisier.Tool.Builtins
import Lavoisier.Tool.Edit
import Lavoisier.Tool.Registry
import Lavoisier.Tool.Search (findReferencesTool)
import Lavoisier.Tune
import Lavoisier.Tune.Bayes (asBayesTuner, bayesTuner, loadBayes, newBayesTuner, sampleBeta, saveBayes)
import Lens.Family2 ((&), (.~), (^.))
import Network.HTTP.Types (hAuthorization, hContentType, status200, status401, status429)
import Network.Wai (defaultRequest, pathInfo, requestHeaders, requestMethod)
import Network.Wai.Test (SRequest (..), runSession, simpleBody, simpleStatus, srequest)
import Network.WebSockets qualified as WS
import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure, info)
import Proto.Xai.Api.V1.Chat qualified as PX
import Proto.Xai.Api.V1.Sample qualified as SX
import System.Directory (createDirectoryIfMissing, doesFileExist, getTemporaryDirectory, listDirectory, removeDirectoryRecursive)
import System.FilePath ((</>))
import System.IO (BufferMode (LineBuffering), Handle, hClose, hFlush, hSetBinaryMode, hSetBuffering, hSetEncoding, utf8)
import System.Process (createPipe)
import Test.QuickCheck (Arbitrary (..), Gen, NonNegative (..), Positive (..), choose, counterexample, elements, forAll, ioProperty, listOf, oneof, resize, (.&&.))
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
      pureProperties,
      monadicProperties,
      sseTests,
      anthropicBodyTests,
      googleTests,
      toolTests,
      editToolTests,
      batchEditTests,
      agentTests,
      compactionTests,
      section8Tests,
      convergenceTests,
      minorLeverTests,
      fallbackTests,
      contextTests,
      treeSitterTests,
      skeletonTests,
      symbolTests,
      budgetTests,
      gatewayTests,
      a2aTests,
      acpTests,
      tuiTests,
      memoryTests,
      configTests,
      logTests,
      mcpTests,
      tuneTests,
      bayesTests,
      claudeCliTests,
      legionTests,
      slackTests,
      cronTests,
      scheduleTests,
      xaiTests,
      xaiGrpcTests,
      matrixTests
    ]

-- --- Phase 1: protocol wire shapes, as QuickCheck round-trip properties ----------------------------

genText :: Gen Text
genText = T.pack <$> arbitrary

instance Arbitrary Text where
  arbitrary = genText

-- | Text safe to splice into a Dhall string literal (no quotes/backslashes/newlines to escape).
genSafe :: Gen Text
genSafe = T.pack <$> listOf (elements (['a' .. 'z'] <> ['0' .. '9'] <> "-_ "))

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

-- --- Pure-function properties (QuickCheck) — invariants over the deterministic core ----------------

pureProperties :: TestTree
pureProperties =
  testGroup
    "pure invariants (QuickCheck)"
    [ testProperty "estimateTokens: leading/trailing spaces don't change the count" $ \t ->
        estimateTokens (" " <> t <> " ") === estimateTokens t,
      testProperty "estimateTokens: a leading space-separated word adds exactly one" $ \t ->
        estimateTokens ("x " <> t) === 1 + estimateTokens t,
      testProperty "anchorOf is an 8-char lowercase-hex string" $ \t ->
        let a = Anc.anchorOf t in (T.length a === 8) .&&. counterexample (T.unpack a) (T.all isHexDigit a),
      testProperty "anchorOf is indentation-insensitive" $ \t ->
        Anc.anchorOf ("    " <> t) === Anc.anchorOf t,
      -- The keystone safety property of the edit path: an anchored replace either refuses outright
      -- or rewrites exactly the line it named, leaving every other line byte-identical. Nothing
      -- positional can shift a target, so this holds however the surrounding lines repeat.
      testProperty "applyEdits either fails or changes only the targeted line" $
        forAll (resize 8 (listOf (elements ["a", "b", "  a", "dup", "dup", "zz"]))) $ \ls ->
          forAll (choose (0, max 0 (length ls - 1))) $ \i ->
            let src = T.unlines ls
                target = ls !! i
             in null ls || case Anc.applyEdits src [Anc.replaceEdit (Anc.anchorOf target) "REPLACED"] of
                  Left _ -> True
                  Right out ->
                    let orig = T.lines src
                        edited = T.lines out
                     in length orig == length edited
                          && and
                            [ if Anc.anchorOf b == Anc.anchorOf target then a == "REPLACED" else a == b
                            | (a, b) <- zip edited orig
                            ],
      testProperty "stepWindow admits exactly min(n, cap) within one window" $
        forAll (choose (1, 20)) $ \mx ->
          forAll (choose (0, 40)) $ \n ->
            let go _ 0 = 0 :: Int
                go st k = let (ok, st') = stepWindow mx 60 1000 st in (if ok then 1 else 0) + go (Just st') (k - 1)
             in go Nothing n === min n (fromIntegral mx),
      testProperty "stepWindow re-admits once the window has elapsed" $
        forAll (choose (1, 20)) $ \mx ->
          fst (stepWindow mx 60 1060 (Just (1000, mx))) === True,
      testProperty "nextAfter of `* * * * *` is the next minute boundary in (t, t+60]" $
        forAll (choose (0, 4_000_000_000)) $ \t ->
          case parseCron "* * * * *" of
            Left _ -> counterexample "parse failed" False
            Right s -> case nextAfter s t of
              Nothing -> counterexample "no next fire" False
              Just t' -> (t' > t) .&&. (t' - t <= 60) .&&. (t' `mod` 60 === 0),
      testProperty "trimTo (Just n) keeps min(n, len) messages" $ \(NonNegative n) h ->
        length (trimTo (Just n) (h :: [Message])) === min n (length h),
      testProperty "trimTo (Just n) is a suffix of the input" $ \(NonNegative n) h ->
        trimTo (Just n) (h :: [Message]) `isSuffixOf` h,
      testProperty "trimTo Nothing is the identity" $ \h ->
        trimTo Nothing (h :: [Message]) === h,
      testProperty "senderAllowed: no allowlist admits everyone" $ \u ->
        MX.senderAllowed Nothing u === True,
      testProperty "senderAllowed: an allowlist is exactly set membership" $ \u us ->
        MX.senderAllowed (Just (Set.fromList us)) u === (u `elem` us),
      testProperty "roomAllowed: no allowlist admits everywhere" $ \r ->
        MX.roomAllowed Nothing r === True,
      testCase "toolsFor: a room absent from the map is unconstrained, one present is restricted" $ do
        let cfg = (MX.defaultMatrixConfig "hs" "@b:hs") {MX.mcRoomTools = Map.singleton "!ops" ["obs_start", "schedule_list"]}
        MX.toolsFor cfg "!dev" "@a:hs" @?= Nothing
        MX.toolsFor cfg "!ops" "@a:hs" @?= Just ["obs_start", "schedule_list"],
      testCase "toolsFor: room ∩ user, so a member cannot exceed the room's grant" $ do
        let cfg =
              (MX.defaultMatrixConfig "hs" "@b:hs")
                { MX.mcRoomTools = Map.singleton "!bcast" ["obs_start", "server_shutdown"],
                  MX.mcUserTools = Map.singleton "@rian:hs" ["obs_start", "schedule_list"]
                }
        MX.toolsFor cfg "!bcast" "@rian:hs" @?= Just ["obs_start"]
        MX.toolsFor cfg "!bcast" "@david:hs" @?= Just ["obs_start", "server_shutdown"],
      testProperty "toolsFor returns the room∩user intersection, a subset of both" $ \rs us ->
        let cfg = (MX.defaultMatrixConfig "hs" "@b:hs") {MX.mcRoomTools = Map.singleton "r" rs, MX.mcUserTools = Map.singleton "u" us}
         in case MX.toolsFor cfg "r" "u" of
              Just ts -> counterexample (show ts) (all (`elem` rs) ts && all (`elem` us) ts && ts == filter (`elem` us) rs)
              Nothing -> counterexample "expected Just" False
    ]

-- --- Monadic (IO) properties (QuickCheck) ----------------------------------------------------------

monadicProperties :: TestTree
monadicProperties =
  testGroup
    "IO invariants (QuickCheck)"
    [ testProperty "RecentIds: the most recently inserted id is always contained" $ \(Positive cap) xs x ->
        ioProperty $ do
          r <- MX.newRecentIds cap
          mapM_ (MX.insertRecent r) (xs <> [x] :: [Text]) -- x inserted last
          MX.containsRecent r x,
      testProperty "RecentIds: cap+1 distinct ids evicts the oldest, keeps the newest" $
        forAll (choose (1, 30)) $ \cap ->
          ioProperty $ do
            let oldestId = T.pack (show (1 :: Int))
                newestId = T.pack (show (cap + 1))
                xs = map (T.pack . show) [1 .. cap + 1]
            r <- MX.newRecentIds cap
            mapM_ (MX.insertRecent r) xs
            oldest <- MX.containsRecent r oldestId
            newest <- MX.containsRecent r newestId
            pure (not oldest && newest),
      testProperty "in-memory store round-trips a session as the trimmed history" $
        forAll (choose (0, 12)) $ \n ->
          \h -> ioProperty $ do
            store <- newInMemoryStore (Just n)
            saveSession store "s" (h :: [Message])
            loaded <- loadSession store "s"
            pure (loaded === trimTo (Just n) h),
      testProperty "cron-file (Dhall) round-trips a job's session/prompt/retry" $
        forAll genSafe $ \sess ->
          forAll genSafe $ \prm ->
            forAll (choose (0, 9)) $ \(rmax :: Int) ->
              forAll (choose (0, 300)) $ \(rwait :: Int) ->
                ioProperty $
                  withTmp "cronqc" $ \dir -> do
                    r <-
                      loadCron dir 0 0 $
                        "[ c // { schedule = \"* * * * *\", session = Some \"" <> sess <> "\", prompt = \"" <> prm <> "\", retryMax = Some " <> tshow' rmax <> ", retryWait = Some " <> tshow' rwait <> " } ]"
                    pure $ case r of
                      Right [j] -> (cjSession j === sess) .&&. (cjPrompt j === prm) .&&. (cjRetryMax j === rmax) .&&. (cjRetryWait j === rwait)
                      other -> counterexample (show (fmap (map cjSession) other)) False
    ]
  where
    tshow' :: Int -> Text
    tshow' = T.pack . show

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
          other -> assertFailure ("expected TEUnknown, got " <> show (fmap (const ()) other)),
      testCase "outline_file elides bodies, keeps signatures" $ withTmp "outline" $ \dir -> do
        let f = dir </> "m.rs"
        TIO.writeFile f "/// doc\nfn add(a: i32) -> i32 {\n    let s = a + 1;\n    s\n}\n"
        r <- toolInvoke outlineFileTool (object ["path" .= T.pack f])
        case r of
          Right o -> do
            assertBool "signature kept" ("fn add(a: i32) -> i32" `T.isInfixOf` toContent o)
            assertBool "placeholder" ("{ … }" `T.isInfixOf` toContent o)
            assertBool "body elided" (not ("let s = a + 1;" `T.isInfixOf` toContent o))
          Left e -> assertFailure ("outline failed: " <> show e),
      testCase "outline_file focus keeps the target's dependency bodies" $ withTmp "focus" $ \dir -> do
        let f = dir </> "f.rs"
        TIO.writeFile f "fn helper() -> i32 { 41 }\nfn target() -> i32 { helper() }\n"
        r1 <- toolInvoke outlineFileTool (object ["path" .= T.pack f, "focus" .= ("target" :: Text), "radius" .= (1 :: Int)])
        case r1 of
          Right o -> assertBool "helper body kept at radius 1" ("41" `T.isInfixOf` toContent o)
          Left e -> assertFailure ("outline failed: " <> show e)
        r0 <- toolInvoke outlineFileTool (object ["path" .= T.pack f, "focus" .= ("target" :: Text), "radius" .= (0 :: Int)])
        case r0 of
          Right o -> assertBool "helper body elided at radius 0" (not ("41" `T.isInfixOf` toContent o))
          Left e -> assertFailure ("outline failed: " <> show e),
      testCase "find_references scans a directory, AST-precise, skipping ignore dirs" $ withTmp "refs" $ \dir -> do
        TIO.writeFile (dir </> "r.rs") "fn helper() -> i32 { 1 }\nfn target() -> i32 {\n    // helper mention\n    helper()\n}\n"
        createDirectoryIfMissing True (dir </> "node_modules")
        TIO.writeFile (dir </> "node_modules" </> "junk.rs") "fn helper() {}\n"
        r <- toolInvoke findReferencesTool (object ["name" .= ("helper" :: Text), "path" .= T.pack dir])
        case r of
          Right o -> do
            toIsError o @?= False
            let c = toContent o
            assertBool "count header" ("reference(s) to `helper`" `T.isInfixOf` c)
            assertBool "def line 1" ("1: fn helper" `T.isInfixOf` c)
            assertBool "call line 4" ("4: helper()" `T.isInfixOf` c)
            assertBool "comment line 3 excluded" (not ("3:" `T.isInfixOf` c))
            assertBool "node_modules skipped" (not ("node_modules" `T.isInfixOf` c))
          Left e -> assertFailure ("find_references failed: " <> show e),
      testCase "outline_files batches under per-file headers" $ withTmp "outlines" $ \dir -> do
        let a = dir </> "a.rs"
            b = dir </> "b.rs"
        TIO.writeFile a "fn one() -> i32 { 1 }\n"
        TIO.writeFile b "fn two() -> i32 { 2 }\n"
        r <- toolInvoke outlineFilesTool (object ["paths" .= [T.pack a, T.pack b]])
        case r of
          Right o -> do
            assertBool "header a" (T.pack a `T.isInfixOf` toContent o)
            assertBool "header b" (T.pack b `T.isInfixOf` toContent o)
            assertBool "both signatures" ("fn one() -> i32" `T.isInfixOf` toContent o && "fn two() -> i32" `T.isInfixOf` toContent o)
          Left e -> assertFailure ("outline_files failed: " <> show e)
    ]

-- --- Phase 4: the agent loop (offline; a stub provider drives a full tool round-trip) --------------

batchEditTests :: TestTree
batchEditTests =
  testGroup
    "batch_edit"
    [ testCase "applyResponse applies a SEARCH/REPLACE block" $ do
        let orig = "fn main() {\n    let x = 1;\n    println!(\"{x}\");\n}\n"
            resp = "<<<<<<< SEARCH\n    let x = 1;\n=======\n    let x = 2;\n>>>>>>> REPLACE"
        case applyResponse orig resp of
          Right out -> do
            assertBool "new value" ("let x = 2;" `T.isInfixOf` out)
            assertBool "old gone" (not ("let x = 1;" `T.isInfixOf` out))
            assertBool "rest kept" ("fn main()" `T.isInfixOf` out && "println!" `T.isInfixOf` out)
          Left e -> assertFailure (T.unpack e),
      testCase "applyResponse supports multiple blocks" $
        applyResponse "a\nb\nc\n" "<<<<<<< SEARCH\na\n=======\nA\n>>>>>>> REPLACE\n<<<<<<< SEARCH\nc\n=======\nC\n>>>>>>> REPLACE" @?= Right "A\nb\nC\n",
      testCase "applyResponse errors when SEARCH does not match" $
        case applyResponse "hello world\n" "<<<<<<< SEARCH\nnot present\n=======\nx\n>>>>>>> REPLACE" of
          Left e -> assertBool "did not match" ("did not match" `T.isInfixOf` e)
          Right _ -> assertFailure "expected a Left",
      testCase "applyResponse falls back to the full file when no markers" $
        applyResponse "old\n" "brand new\ncontents\n" @?= Right "brand new\ncontents\n",
      testCase "stripCodeFence unwraps only whole fenced blocks" $ do
        stripCodeFence "```rust\nlet x = 1;\n```" @?= "let x = 1;\n"
        stripCodeFence "```\nplain\n```\n" @?= "plain\n"
        stripCodeFence "no fences here" @?= "no fences here",
      testCase "batch_edit runs the batch and applies each result" $ withTmp "batch" $ \dir -> do
        let f = dir </> "m.rs"
        TIO.writeFile f "fn main() {\n    let x = 1;\n}\n"
        let mockBatch = Batch $ \tasks -> pure (Right [BatchItem (btId task) "<<<<<<< SEARCH\n    let x = 1;\n=======\n    let x = 42;\n>>>>>>> REPLACE" emptyUsage Nothing | task <- tasks])
        r <- toolInvoke (batchEditTool "m" mockBatch) (object ["edits" .= [object ["path" .= T.pack f, "instruction" .= ("bump x" :: Text)]]])
        case r of
          Right o -> do
            toChanged o @?= True
            assertBool "applied 1/1" ("applied 1/1" `T.isInfixOf` toContent o)
            c <- TIO.readFile f
            assertBool "file edited" ("let x = 42;" `T.isInfixOf` c)
          Left e -> assertFailure (show e),
      testCase "Anthropic batchRequestsBody wraps custom_id + strips stream" $ do
        let task = BatchTask "0" ((chatRequest "claude") {crMessages = [userMessage "hi"], crMaxTokens = 64})
            body = batchRequestsBody False [task]
            req0 = jix (jkey "requests" body) 0
        jkey "custom_id" req0 @?= Just (String "0")
        assertBool "params carries the model" (jkey "model" (maybe Null id (jkey "params" req0)) == Just (String "claude"))
        assertBool "params has no stream" (jkey "stream" (maybe Null id (jkey "params" req0)) == Nothing),
      testCase "Anthropic parseResultLine reads a succeeded + an errored line" $ do
        let okMsg = object ["content" .= [object ["type" .= t "text", "text" .= t "hello"]], "usage" .= object ["input_tokens" .= (10 :: Int), "output_tokens" .= (3 :: Int)]]
            ok = object ["custom_id" .= t "0", "result" .= object ["type" .= t "succeeded", "message" .= okMsg]]
            bad = object ["custom_id" .= t "1", "result" .= object ["type" .= t "errored", "error" .= object ["type" .= t "overloaded"]]]
            i0 = parseResultLine ok
            i1 = parseResultLine bad
        (biId i0, biText i0, biError i0) @?= ("0", "hello", Nothing)
        inputTokens (biUsage i0) @?= 10
        (biId i1, biError i1) @?= ("1", Just "overloaded"),
      testCase "Google batchBody inlines request + metadata key" $ do
        let cfg = G.GoogleConfig "k" "https://x" undefined G.defaultReasoningFloor
            task = BatchTask "task-0" ((chatRequest "gemini") {crMessages = [userMessage "hi"], crMaxTokens = 64})
            body = GB.batchBody cfg [task]
            inl = jix (jkey "requests" (maybe Null id (jkey "requests" (maybe Null id (jkey "input_config" (maybe Null id (jkey "batch" body))))))) 0
        jkey "key" (maybe Null id (jkey "metadata" inl)) @?= Just (String "task-0")
        assertBool "carries a request" (jkey "request" inl /= Nothing),
      testCase "Google parseBatchOp reads name/state/done" $ do
        let op = object ["name" .= t "batches/abc", "metadata" .= object ["state" .= t "BATCH_STATE_SUCCEEDED"], "done" .= True]
            (nm, st, dn) = GB.parseBatchOp op
        (nm, st, dn) @?= ("batches/abc", "BATCH_STATE_SUCCEEDED", True),
      testCase "Google parseResults reads text/error/usage" $ do
        let op =
              object
                [ "response"
                    .= object
                      [ "inlinedResponses"
                          .= object
                            [ "inlinedResponses"
                                .= [ object
                                       [ "metadata" .= object ["key" .= t "task-1"],
                                         "response"
                                           .= object
                                             [ "candidates" .= [object ["content" .= object ["parts" .= [object ["text" .= t "hello"]]]]],
                                               "usageMetadata" .= object ["promptTokenCount" .= (10 :: Int), "cachedContentTokenCount" .= (4 :: Int), "candidatesTokenCount" .= (3 :: Int)]
                                             ]
                                       ],
                                     object ["metadata" .= object ["key" .= t "task-2"], "error" .= object ["message" .= t "boom"]]
                                   ]
                            ]
                      ]
                ]
            items = GB.parseResults op
        length items @?= 2
        let g0 = items !! 0
            g1 = items !! 1
        (biId g0, biText g0, biError g0) @?= ("task-1", "hello", Nothing)
        (inputTokens (biUsage g0), cacheReadTokens (biUsage g0), outputTokens (biUsage g0)) @?= (6, 4, 3)
        (biId g1, biError g1) @?= ("task-2", Just "boom")
    ]
  where
    t = id :: Text -> Text
    jkey k (Object o) = KM.lookup (K.fromText k) o
    jkey _ _ = Nothing
    jix (Just (Array a)) i = a V.! i
    jix _ _ = Null

editToolTests :: TestTree
editToolTests =
  testGroup
    "edit tools"
    [ testCase "str_replace edits a unique match and reports changed" $ withTmp "sr" $ \dir -> do
        let f = dir </> "a.txt"
        TIO.writeFile f "hello world\n"
        r <- toolInvoke strReplaceTool (object ["path" .= T.pack f, "old" .= ("world" :: Text), "new" .= ("haskell" :: Text)])
        case r of
          Right o -> do
            toIsError o @?= False
            toChanged o @?= True
            TIO.readFile f >>= (@?= "hello haskell\n")
          Left e -> assertFailure (show e),
      testCase "str_replace refuses a non-unique match and does not write" $ withTmp "sr2" $ \dir -> do
        let f = dir </> "b.txt"
        TIO.writeFile f "x x\n"
        r <- toolInvoke strReplaceTool (object ["path" .= T.pack f, "old" .= ("x" :: Text), "new" .= ("y" :: Text)])
        case r of
          Right o -> do
            toIsError o @?= True
            TIO.readFile f >>= (@?= "x x\n") -- unchanged
          Left e -> assertFailure (show e),
      testCase "str_replace with replace_all changes every occurrence" $ withTmp "sr3" $ \dir -> do
        let f = dir </> "c.txt"
        TIO.writeFile f "a a a\n"
        r <- toolInvoke strReplaceTool (object ["path" .= T.pack f, "old" .= ("a" :: Text), "new" .= ("b" :: Text), "replace_all" .= True])
        case r of
          Right o -> do
            toChanged o @?= True
            TIO.readFile f >>= (@?= "b b b\n")
          Left e -> assertFailure (show e),
      testCase "str_replace: `after` picks one of several matches by content" $ withTmp "sra" $ \dir -> do
        let f = dir </> "w.txt"
        TIO.writeFile f "x = 1\n-- marker\nx = 1\n"
        r <- toolInvoke strReplaceTool (object ["path" .= T.pack f, "old" .= ("x = 1" :: Text), "new" .= ("x = 2" :: Text), "after" .= ("-- marker" :: Text)])
        case r of
          Right o -> do
            toChanged o @?= True
            c <- TIO.readFile f
            c @?= "x = 1\n-- marker\nx = 2\n"
          Left e -> assertFailure (show e),
      testCase "str_replace: `before` bounds the window from the other side" $ withTmp "srb" $ \dir -> do
        let f = dir </> "w.txt"
        TIO.writeFile f "x = 1\n-- marker\nx = 1\n"
        r <- toolInvoke strReplaceTool (object ["path" .= T.pack f, "old" .= ("x = 1" :: Text), "new" .= ("x = 2" :: Text), "before" .= ("-- marker" :: Text)])
        case r of
          Right _ -> do
            c <- TIO.readFile f
            c @?= "x = 2\n-- marker\nx = 1\n"
          Left e -> assertFailure (show e),
      testCase "str_replace: a repeated `after` snippet is refused, not guessed" $ withTmp "srd" $ \dir -> do
        let f = dir </> "w.txt"
        TIO.writeFile f "m\nx = 1\nm\nx = 1\n"
        r <- toolInvoke strReplaceTool (object ["path" .= T.pack f, "old" .= ("x = 1" :: Text), "new" .= ("x = 2" :: Text), "after" .= ("m" :: Text)])
        case r of
          Right o -> do
            toChanged o @?= False
            assertBool "explains the rule" ("must match exactly once" `T.isInfixOf` toContent o)
            c <- TIO.readFile f
            c @?= "m\nx = 1\nm\nx = 1\n"
          Left e -> assertFailure (show e),
      testCase "str_replace: an ambiguous match names the disambiguating arguments" $ withTmp "sre" $ \dir -> do
        let f = dir </> "w.txt"
        TIO.writeFile f "x = 1\nx = 1\n"
        r <- toolInvoke strReplaceTool (object ["path" .= T.pack f, "old" .= ("x = 1" :: Text), "new" .= ("x = 2" :: Text)])
        case r of
          Right o -> do
            toChanged o @?= False
            assertBool "suggests after/before" ("`after`/`before`" `T.isInfixOf` toContent o)
            assertBool "still mentions replace_all" ("replace_all" `T.isInfixOf` toContent o)
          Left e -> assertFailure (show e),
      testCase "str_replace: replace_all is scoped to the window when one is given" $ withTmp "srf" $ \dir -> do
        let f = dir </> "w.txt"
        TIO.writeFile f "x\n-- marker\nx\nx\n"
        r <- toolInvoke strReplaceTool (object ["path" .= T.pack f, "old" .= ("x" :: Text), "new" .= ("y" :: Text), "after" .= ("-- marker" :: Text), "replace_all" .= True])
        case r of
          Right _ -> do
            c <- TIO.readFile f
            c @?= "x\n-- marker\ny\ny\n"
          Left e -> assertFailure (show e),
      testCase "edit_files applies an anchored replace" $ withTmp "ef" $ \dir -> do
        let f = dir </> "d.txt"
        TIO.writeFile f "line one\nline two\n"
        let edit = object ["anchor" .= Anc.anchorOf "line two", "op" .= ("replace" :: Text), "text" .= ("LINE TWO" :: Text)]
            files = [object ["path" .= T.pack f, "edits" .= [edit]]]
        r <- toolInvoke editFilesTool (object ["files" .= files])
        case r of
          Right o -> do
            toChanged o @?= True
            c <- TIO.readFile f
            assertBool "replaced" ("LINE TWO" `T.isInfixOf` c)
            assertBool "old gone" (not ("line two" `T.isInfixOf` c))
          Left e -> assertFailure (show e)
    ]

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
          Nothing -> assertFailure "no max-tool-result-bytes recorded in the outcome",
      testCase "applyKnobsToArgs caps a batch tool's paths to batch_width" $ do
        let knobs = Tn.defaultKnobs {Tn.batchWidth = 2}
            out = applyKnobsToArgs knobs "read_files" (object ["paths" .= (["a", "b", "c", "d"] :: [Text])])
        case out of
          Object o -> case KM.lookup "paths" o of
            Just (Array a) -> V.length a @?= 2
            _ -> assertFailure "paths missing/!array"
          _ -> assertFailure "not an object",
      testCase "applyKnobsToArgs injects the tuned radius when focus is set but radius unset" $ do
        let knobs = Tn.defaultKnobs {Tn.skeletonRadius = 3}
            out = applyKnobsToArgs knobs "outline_file" (object ["path" .= ("x.rs" :: Text), "focus" .= ("f" :: Text)])
        case out of
          Object o -> KM.lookup "radius" o @?= Just (Number 3)
          _ -> assertFailure "not an object",
      testCase "applyKnobsToArgs leaves a pinned radius and non-batch tools untouched" $ do
        let knobs = Tn.defaultKnobs {Tn.skeletonRadius = 3, Tn.batchWidth = 1}
        case applyKnobsToArgs knobs "outline_file" (object ["path" .= ("x.rs" :: Text), "focus" .= ("f" :: Text), "radius" .= (0 :: Int)]) of
          Object o -> KM.lookup "radius" o @?= Just (Number 0)
          _ -> assertFailure "not an object"
        let a = object ["path" .= ("x" :: Text)]
        applyKnobsToArgs knobs "read_file" a @?= a
    ]

-- --- history compaction (§6.3): dedup + summarise-the-middle ---------------------------------------

compactionTests :: TestTree
compactionTests =
  testGroup
    "history compaction"
    [ testCase "dedupToolResults collapses a repeated large result, keeps the newest" $ do
        let big = T.replicate 300 "y" -- > dedupMinBytes (200)
            hist =
              [ userMessage "task",
                Message Assistant [ToolUseBlock "1" "read_file" (object [])],
                Message User [ToolResultBlock "1" big False],
                Message Assistant [ToolUseBlock "2" "read_file" (object [])],
                Message User [ToolResultBlock "2" big False]
              ]
            contents = [c | Message _ bs <- dedupToolResults hist, ToolResultBlock _ c _ <- bs]
        -- newest (last) kept verbatim; the older identical copy becomes a pointer.
        contents @?= ["[duplicate of a more recent identical result, 300 bytes]", big],
      testCase "dedupToolResults leaves small results alone" $ do
        let small = "tiny" -- < 200 bytes
            hist =
              [ Message User [ToolResultBlock "1" small False],
                Message User [ToolResultBlock "2" small False]
              ]
            contents = [c | Message _ bs <- dedupToolResults hist, ToolResultBlock _ c _ <- bs]
        contents @?= [small, small],
      testCase "compaction summarises the middle once history outgrows compactAfter" $ do
        let big = T.replicate 400 "z"
            mkPair i =
              [ Message Assistant [ToolUseBlock (T.pack (show i)) "read_file" (object [])],
                Message User [ToolResultBlock (T.pack (show i)) (big <> T.pack (show i)) False]
              ]
            seed = userMessage "the original task" : concatMap mkPair [1 .. 3 :: Int] -- 7 messages
            stub =
              Provider
                { providerStream = \req -> do
                    let evs =
                          if null (crTools req)
                            then [TextDelta "SUMMARY: read files 1-3", Usage emptyUsage, Done EndTurn]
                            else [TextDelta "final answer", Usage emptyUsage, Done EndTurn]
                    s <- fromList (map Right evs)
                    pure (Right s),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            tuner =
              Tn.Tuner
                { Tn.tunerSelect = \_ -> pure Tn.defaultKnobs {Tn.compactAfter = 1},
                  Tn.tunerObserve = \_ _ _ -> pure ()
                }
        agent <- mkAgent stub withBuiltins (defaultAgentConfig "stub-model") tuner Nothing
        r <- runLoopSeeded agent Nothing seed (const (pure ()))
        case r of
          Left e -> assertFailure ("loop failed: " <> show e)
          Right msgs -> do
            let texts = [c | Message _ bs <- msgs, TextBlock c _ <- bs]
                results = [c | Message _ bs <- msgs, ToolResultBlock _ c _ <- bs]
            assertBool "compaction note present" (any ("[Earlier conversation compacted to save tokens]" `T.isInfixOf`) texts)
            assertBool "the summary text is in the note" (any ("SUMMARY: read files 1-3" `T.isInfixOf`) texts)
            assertBool "summarised pair-1 result elided" (not (any ((big <> "1") `T.isInfixOf`) results))
            assertBool "recent pair-3 result kept verbatim" (any ((big <> "3") `T.isInfixOf`) results),
      testCase "markStaleReads elides a read superseded by a later edit of the same file" $ do
        let big = T.replicate 300 "r"
            hist =
              [ userMessage "task",
                Message Assistant [ToolUseBlock "r1" "read_file" (object ["path" .= ("a.rs" :: Text)])],
                Message User [ToolResultBlock "r1" big False],
                Message Assistant [ToolUseBlock "e1" "write_file" (object ["path" .= ("a.rs" :: Text), "content" .= ("new" :: Text)])],
                Message User [ToolResultBlock "e1" "wrote 3 bytes to a.rs" False]
              ]
            results = [c | Message _ bs <- markStaleReads hist, ToolResultBlock _ c _ <- bs]
        assertBool "read result marked stale" (any ("[stale: a.rs was edited" `T.isInfixOf`) results)
        assertBool "original read bytes elided" (not (any (big `T.isInfixOf`) results)),
      testCase "markStaleReads leaves a read with no later edit intact" $ do
        let big = T.replicate 300 "r"
            hist =
              [ Message Assistant [ToolUseBlock "r1" "read_file" (object ["path" .= ("b.rs" :: Text)])],
                Message User [ToolResultBlock "r1" big False]
              ]
        markStaleReads hist @?= hist,
      testCase "evictToFit evicts oldest tool output until under the limit, keeps recent" $ do
        let big = T.intercalate " " (replicate 200 "lorem")
            pair i = [Message Assistant [ToolUseBlock (T.pack (show i)) "shell" (object [])], Message User [ToolResultBlock (T.pack (show i)) big False]]
            hist = userMessage "task" : concatMap pair [1 .. 4 :: Int] -- 9 messages; protected window = last 4
            out = evictToFit 50 hist
            evicted = [c | Message _ bs <- out, ToolResultBlock _ c _ <- bs, "[evicted" `T.isInfixOf` c]
            recent = [c | Message _ bs <- drop (length out - 2) out, ToolResultBlock _ c _ <- bs]
        assertBool "some oldest results evicted" (not (null evicted))
        assertBool "the most recent result is kept verbatim" (any (big `T.isInfixOf`) recent)
    ]

-- --- §8 model routing: cheap-model-first + advisor pre-pass ----------------------------------------

section8Tests :: TestTree
section8Tests =
  testGroup
    "model routing (§8)"
    [ testCase "cheap-model-first runs the cheap model then escalates after escalateAfter" $ do
        models <- newIORef []
        ref <- newIORef (0 :: Int)
        let call i = [ToolUseStart i "read_file", ToolUseDelta i (jsonArg (object ["path" .= ("/no/such" :: Text)])), ToolUseEnd i, Usage emptyUsage, Done ToolUse]
            final = [TextDelta "done", Usage emptyUsage, Done EndTurn]
            stub =
              Provider
                { providerStream = \req -> do
                    modifyIORef' models (<> [crModel req])
                    n <- atomicModifyIORef' ref (\k -> (k + 1, k))
                    fmap Right (fromList (map Right (if n < 2 then call (T.pack ('t' : show n)) else final))),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "strong") {acCheapModel = Just "cheap", acEscalateAfter = 2}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        _ <- runLoopSeeded agent Nothing [userMessage "go"] (const (pure ()))
        readIORef models >>= (@?= ["cheap", "cheap", "strong"]),
      testCase "advisor pre-pass seeds the transcript with a plan" $ do
        let stub =
              Provider
                { providerStream = \req ->
                    fmap Right . fromList . map Right $
                      if null (crTools req)
                        then [TextDelta "- inspect main.rs\n- edit it", Usage emptyUsage, Done EndTurn]
                        else [TextDelta "final", Usage emptyUsage, Done EndTurn],
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "exec") {acAdvisorModel = Just "smart"}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        r <- runLoopSeeded agent Nothing [userMessage "do the thing"] (const (pure ()))
        case r of
          Right msgs -> assertBool "plan seeded" (any ("Plan:\n- inspect main.rs" `T.isInfixOf`) [c | Message _ bs <- msgs, TextBlock c _ <- bs])
          Left e -> assertFailure (show e),
      testCase "a per-turn model override reaches the provider request" $ do
        models <- newIORef []
        let stub =
              Provider
                { providerStream = \req -> do
                    modifyIORef' models (<> [crModel req])
                    fmap Right (fromList [Right (Done EndTurn)]),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
        agent <- mkAgent stub withBuiltins (defaultAgentConfig "base-model") Tn.noopTuner Nothing
        est <- submit (agentHandle agent) (withModel "picked-model" (turnRequest "s" "hi"))
        case est of
          Left e -> assertFailure (show e)
          Right st -> void (drain st)
        readIORef models >>= (@?= ["picked-model"]),
      testCase "a denying tool gate blocks the call and the file is never written" $ withTmp "gate-deny" $ \dir -> do
        calls <- newIORef (0 :: Int)
        let path = T.pack (dir </> "g.txt")
            arg = jsonArg (object ["path" .= path, "content" .= ("x" :: Text)])
            stub =
              Provider
                { providerStream = \_ -> do
                    n <- atomicModifyIORef' calls (\k -> (k + 1, k))
                    fmap Right . fromList . map Right $
                      if n == 0
                        then [ToolUseStart "e1" "write_file", ToolUseDelta "e1" arg, ToolUseEnd "e1", Done ToolUse]
                        else [TextDelta "done", Done EndTurn],
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
        agent0 <- mkAgent stub withBuiltins (defaultAgentConfig "m") Tn.noopTuner Nothing
        let agent = withToolGate (ToolGate (\_ _ -> pure (Deny "nope"))) agent0
        _ <- runLoopSeeded agent Nothing [userMessage "write it"] (const (pure ()))
        -- The denied write never touched the filesystem…
        exists <- doesFileExist (dir </> "g.txt")
        assertBool "a denied write must not create the file" (not exists)
        -- …and the denial was fed back as a tool result, so the model got a second turn.
        readIORef calls >>= (@?= 2),
      testCase "an allowing gate lets the write through" $ withTmp "gate-allow" $ \dir -> do
        n <- newIORef (0 :: Int)
        let path = T.pack (dir </> "g.txt")
            arg = jsonArg (object ["path" .= path, "content" .= ("hello" :: Text)])
            stub =
              Provider
                { providerStream = \_ -> do
                    k <- atomicModifyIORef' n (\i -> (i + 1, i))
                    fmap Right . fromList . map Right $
                      if k == 0
                        then [ToolUseStart "e1" "write_file", ToolUseDelta "e1" arg, ToolUseEnd "e1", Done ToolUse]
                        else [Done EndTurn],
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
        agent0 <- mkAgent stub withBuiltins (defaultAgentConfig "m") Tn.noopTuner Nothing
        let agent = withToolGate (ToolGate (\_ _ -> pure Allow)) agent0
        _ <- runLoopSeeded agent Nothing [userMessage "write it"] (const (pure ()))
        readFile (dir </> "g.txt") >>= (@?= "hello")
    ]
  where
    jsonArg = decodeUtf8Lenient . BL.toStrict . encode

-- --- convergence levers: whole-task budget + no-progress breaker ----------------------------------

convergenceTests :: TestTree
convergenceTests =
  testGroup
    "convergence levers"
    [ testCase "budget stops the turn when the cost-weighted total exceeds it" $ do
        let costly = MkUsage 0 100 0 0 -- cost = 100*5 = 500 ≫ 1
            stub =
              Provider
                { providerStream = \_ -> fmap Right (fromList (map Right [ToolUseStart "t" "read_file", ToolUseDelta "t" "{}", ToolUseEnd "t", Usage costly, Done ToolUse])),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "m") {acTokenBudget = Just 1}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        r <- runLoopSeeded agent Nothing [userMessage "go"] (const (pure ()))
        case r of
          Left AEBudgetExceeded -> pure ()
          other -> assertFailure ("expected AEBudgetExceeded, got " <> show (fmap (const ()) other)),
      testCase "no-progress-limit hard-stops after 2N edit-free round-trips" $ do
        emitted <- newIORef []
        let arg = decodeUtf8Lenient . BL.toStrict . encode $ object ["path" .= ("/no/such" :: Text)]
            stub =
              Provider
                { providerStream = \_ -> fmap Right (fromList (map Right [ToolUseStart "t" "read_file", ToolUseDelta "t" arg, ToolUseEnd "t", Usage emptyUsage, Done ToolUse])),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "m") {acNoProgressLimit = Just 1}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        _ <- runLoopSeeded agent Nothing [userMessage "go"] (\e -> modifyIORef' emitted (e :))
        evs <- readIORef emitted
        assertBool "emitted a no_progress stop" (Done (Other "no_progress") `elem` evs),
      testCase "require-edit nudges a no-edit finish then accepts (bounded)" $ do
        ref <- newIORef (0 :: Int)
        let stub =
              Provider
                { providerStream = \_ -> modifyIORef' ref (+ 1) >> fmap Right (fromList (map Right [TextDelta "you should edit X", Usage emptyUsage, Done EndTurn])),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "m") {acRequireEdit = True}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        r <- runLoopSeeded agent Nothing [userMessage "edit the thing"] (const (pure ()))
        n <- readIORef ref
        case r of
          Right msgs -> do
            assertBool "nudged" (any ("haven't changed any files" `T.isInfixOf`) [c | Message _ bs <- msgs, TextBlock c _ <- bs])
            n @?= 3 -- finish + 2 nudges
          Left e -> assertFailure (show e),
      testCase "verify-and-fix bounces a failing verify then accepts (bounded)" $ do
        ref <- newIORef (0 :: Int)
        let stub =
              Provider
                { providerStream = \_ -> modifyIORef' ref (+ 1) >> fmap Right (fromList (map Right [TextDelta "done", Usage emptyUsage, Done EndTurn])),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "m") {acVerifyCommand = Just "false", acVerifyAndFix = True}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        r <- runLoopSeeded agent Nothing [userMessage "go"] (const (pure ()))
        n <- readIORef ref
        case r of
          Right msgs -> do
            assertBool "fed the failure back" (any ("Verification failed" `T.isInfixOf`) [c | Message _ bs <- msgs, TextBlock c _ <- bs])
            n @?= 4 -- finish + 3 fix attempts
          Left e -> assertFailure (show e),
      testCase "in-loop-verify stops as soon as an edit makes verify pass" $ withTmp "ilv" $ \dir -> do
        ref <- newIORef (0 :: Int)
        emitted <- newIORef []
        let f = dir </> "out.txt"
            wargs = decodeUtf8Lenient . BL.toStrict . encode $ object ["path" .= T.pack f, "content" .= ("hi" :: Text)]
            stub =
              Provider
                { providerStream = \_ -> modifyIORef' ref (+ 1) >> fmap Right (fromList (map Right [ToolUseStart "w" "write_file", ToolUseDelta "w" wargs, ToolUseEnd "w", Usage emptyUsage, Done ToolUse])),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "m") {acVerifyCommand = Just "true", acInLoopVerify = True}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        _ <- runLoopSeeded agent Nothing [userMessage "write it"] (\e -> modifyIORef' emitted (e :))
        n <- readIORef ref
        evs <- readIORef emitted
        n @?= 1 -- stopped after one edit turn
        assertBool "emitted EndTurn" (Done EndTurn `elem` evs)
    ]

-- --- minor levers: archetype classification, budget-awareness, summary-model routing --------------

minorLeverTests :: TestTree
minorLeverTests =
  testGroup
    "minor levers"
    [ testCase "classifyArchetype keys off task keywords" $ do
        classifyArchetype "please rename foo" @?= Tn.Rename
        classifyArchetype "refactor the module" @?= Tn.Refactor
        classifyArchetype "implement a new endpoint" @?= Tn.Feature
        classifyArchetype "fix the bug" @?= Tn.SingleFileEdit
        classifyArchetype "what does this function do?" @?= Tn.Other,
      testCase "parseArchetype leniently reads a model's label" $ do
        parseArchetype "refactor" @?= Just Tn.Refactor
        parseArchetype "  Single_File_Edit.\n" @?= Just Tn.SingleFileEdit
        parseArchetype "feature — adds a thing" @?= Just Tn.Feature
        parseArchetype "rename" @?= Just Tn.Rename
        parseArchetype "i think it is a bugfix" @?= Nothing
        parseArchetype "" @?= Nothing,
      testCase "classify-with-model routes the archetype through a model call" $ do
        archRef <- newIORef Tn.Other
        let stub =
              Provider
                { providerStream = \req ->
                    fmap Right . fromList . map Right $
                      if null (crTools req)
                        then [TextDelta "refactor", Usage emptyUsage, Done EndTurn] -- the classify call
                        else [TextDelta "done", Usage emptyUsage, Done EndTurn],
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            tuner = Tn.Tuner {Tn.tunerSelect = \c -> writeIORef archRef (Tn.tcArchetype c) >> pure Tn.defaultKnobs, Tn.tunerObserve = \_ _ _ -> pure ()}
            cfg = (defaultAgentConfig "m") {acClassifyWithModel = True}
        agent <- mkAgent stub withBuiltins cfg tuner Nothing
        _ <- runLoopSeeded agent Nothing [userMessage "please restructure this"] (const (pure ()))
        readIORef archRef >>= (@?= Tn.Refactor),
      testCase "budget-awareness appends a progress note to a turn's results" $ do
        ref <- newIORef (0 :: Int)
        let arg = decodeUtf8Lenient . BL.toStrict . encode $ object ["path" .= ("/no" :: Text)]
            stub =
              Provider
                { providerStream = \_ -> do
                    n <- atomicModifyIORef' ref (\k -> (k + 1, k))
                    fmap Right (fromList (map Right (if n == 0 then [ToolUseStart "t" "read_file", ToolUseDelta "t" arg, ToolUseEnd "t", Usage emptyUsage, Done ToolUse] else [TextDelta "done", Usage emptyUsage, Done EndTurn]))),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "m") {acBudgetAwareness = True}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        r <- runLoopSeeded agent Nothing [userMessage "go"] (const (pure ()))
        case r of
          Right msgs -> assertBool "progress note present" (any ("[progress: turn 1/" `T.isInfixOf`) [c | Message _ bs <- msgs, TextBlock c _ <- bs])
          Left e -> assertFailure (show e),
      testCase "require-edit does not nudge a question (Other archetype)" $ do
        ref <- newIORef (0 :: Int)
        let stub =
              Provider
                { providerStream = \_ -> modifyIORef' ref (+ 1) >> fmap Right (fromList (map Right [TextDelta "it does X", Usage emptyUsage, Done EndTurn])),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            cfg = (defaultAgentConfig "m") {acRequireEdit = True}
        agent <- mkAgent stub withBuiltins cfg Tn.noopTuner Nothing
        _ <- runLoopSeeded agent Nothing [userMessage "what does this do?"] (const (pure ()))
        readIORef ref >>= (@?= 1), -- Other ⇒ no nudge ⇒ single round-trip
      testCase "compaction routes to the summary model when set" $ do
        models <- newIORef []
        let big = T.replicate 400 "z"
            mkPair i = [Message Assistant [ToolUseBlock (T.pack (show i)) "read_file" (object [])], Message User [ToolResultBlock (T.pack (show i)) (big <> T.pack (show i)) False]]
            seed = userMessage "task" : concatMap mkPair [1 .. 3 :: Int]
            stub =
              Provider
                { providerStream = \req -> do
                    modifyIORef' models (<> [(null (crTools req), crModel req)])
                    fmap Right (fromList (map Right (if null (crTools req) then [TextDelta "SUM", Usage emptyUsage, Done EndTurn] else [TextDelta "final", Usage emptyUsage, Done EndTurn]))),
                  providerCapabilities = noCapabilities,
                  providerCountTokens = \_ -> pure (Right Nothing)
                }
            tuner = Tn.Tuner {Tn.tunerSelect = \_ -> pure Tn.defaultKnobs {Tn.compactAfter = 1}, Tn.tunerObserve = \_ _ _ -> pure ()}
            cfg = (defaultAgentConfig "exec") {acSummaryModel = Just "cheap-sum"}
        agent <- mkAgent stub withBuiltins cfg tuner Nothing
        _ <- runLoopSeeded agent Nothing seed (const (pure ()))
        ms <- readIORef models
        assertBool "the tool-less summary call used the summary model" ((True, "cheap-sum") `elem` ms)
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
      testCase "an `after` landmark picks the first identical line below it" $ do
        let dupSrc = "dup\nalpha\ndup\nbeta\ndup\n"
            edit = Anc.after (Anc.anchorOf "beta") (Anc.replaceEdit (Anc.anchorOf "dup") "PICKED")
        out <- expectRight (Anc.applyEdits dupSrc [edit])
        T.lines out @?= ["dup", "alpha", "dup", "beta", "PICKED"],
      testCase "an earlier landmark reaches an earlier copy" $ do
        let dupSrc = "dup\nalpha\ndup\nbeta\ndup\n"
            edit = Anc.after (Anc.anchorOf "alpha") (Anc.replaceEdit (Anc.anchorOf "dup") "PICKED")
        out <- expectRight (Anc.applyEdits dupSrc [edit])
        T.lines out @?= ["dup", "alpha", "PICKED", "beta", "dup"],
      testCase "a landmark below every copy is refused, not wrapped around" $
        case Anc.applyEdits "dup\ndup\ntail\n" [Anc.after (Anc.anchorOf "tail") (Anc.replaceEdit (Anc.anchorOf "dup") "x")] of
          Left (Anc.NoneAfter _ _) -> pure ()
          other -> assertFailure ("expected NoneAfter, got " <> show other),
      testCase "a repeated `after` landmark pins nothing and is rejected" $
        case Anc.applyEdits "n\ndup\nn\ndup\n" [Anc.after (Anc.anchorOf "n") (Anc.replaceEdit (Anc.anchorOf "dup") "x")] of
          Left (Anc.AfterAmbiguous _ 2) -> pure ()
          other -> assertFailure ("expected AfterAmbiguous _ 2, got " <> show other),
      testCase "a missing `after` landmark is rejected" $
        case Anc.applyEdits "dup\ndup\n" [Anc.after "deadbeef" (Anc.replaceEdit (Anc.anchorOf "dup") "x")] of
          Left (Anc.AfterNotFound _) -> pure ()
          other -> assertFailure ("expected AfterNotFound, got " <> show other),
      testCase "anchor errors name the fix, not just the fault" $ do
        let amb = Anc.renderAnchorError (Anc.Ambiguous "abc12345" 3)
        assertBool "says how many" ("3 identical lines" `T.isInfixOf` amb)
        assertBool "suggests after" ("\"after\"" `T.isInfixOf` amb)
        assertBool "stale anchor points at read_anchored" $
          "read_anchored" `T.isInfixOf` Anc.renderAnchorError (Anc.NotFound "abc12345"),
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
        let app = httpApp (GatewayConfig ["secret"] Nothing) (stubAgent [])
        r <- runSession (srequest (SRequest (post ["v1", "turns"] []) "{\"input\":\"x\"}")) app
        simpleStatus r @?= status401,
      testCase "protected route accepts a valid bearer key" $ do
        let app = httpApp (GatewayConfig ["secret"] Nothing) (stubAgent [Done EndTurn])
            auth = [(hAuthorization, "Bearer secret")]
        r <- runSession (srequest (SRequest (post ["v1", "turns"] auth) "{\"input\":\"x\"}")) app
        simpleStatus r @?= status200,
      testCase "GET /metrics counts turns and tokens" $ do
        app <- newHttpApp defaultGatewayConfig (stubAgent [TextDelta "hi", Usage (MkUsage 3 5 0 7), Done EndTurn])
        _ <- runSession (srequest (SRequest (post ["v1", "turns"] []) "{\"input\":\"x\"}")) app
        mr <- runSession (srequest (SRequest (get ["metrics"]) "")) app
        let body = decodeUtf8Lenient (BL.toStrict (simpleBody mr))
        assertBool "turns counted" ("lavoisier_turns_total 1" `T.isInfixOf` body)
        assertBool "input tokens" ("lavoisier_input_tokens_total 3" `T.isInfixOf` body)
        assertBool "output tokens" ("lavoisier_output_tokens_total 5" `T.isInfixOf` body),
      testCase "rate limit returns 429 once the window cap is hit" $ do
        app <- newHttpApp (GatewayConfig [] (Just (1, 60))) (stubAgent [Done EndTurn])
        r1 <- runSession (srequest (SRequest (post ["v1", "turns"] []) "{\"input\":\"x\"}")) app
        simpleStatus r1 @?= status200
        r2 <- runSession (srequest (SRequest (post ["v1", "turns"] []) "{\"input\":\"x\"}")) app
        simpleStatus r2 @?= status429,
      testCase "stepWindow admits within cap and resets after the window" $ do
        stepWindow 2 60 100 Nothing @?= (True, (100, 1))
        stepWindow 2 60 100 (Just (100, 2)) @?= (False, (100, 2))
        stepWindow 2 60 200 (Just (100, 2)) @?= (True, (200, 1)),
      testCase "wsAuthorized gates the /v1/ws upgrade like the SSE route" $ do
        let open = defaultGatewayConfig
            keyed = GatewayConfig ["secret"] Nothing
            head' hdrs = WS.RequestHead "/v1/ws" hdrs False
        wsAuthorized open (head' []) @?= True
        wsAuthorized keyed (head' []) @?= False
        wsAuthorized keyed (head' [(hAuthorization, "Bearer secret")]) @?= True
        wsAuthorized keyed (head' [(hAuthorization, "Bearer wrong")]) @?= False,
      testCase "wsPrincipal is the bearer key when keyed, else anon" $ do
        let keyed = GatewayConfig ["secret"] Nothing
            head' hdrs = WS.RequestHead "/v1/ws" hdrs False
        wsPrincipal defaultGatewayConfig (head' [(hAuthorization, "Bearer secret")]) @?= "anon"
        wsPrincipal keyed (head' [(hAuthorization, "Bearer secret")]) @?= "secret"
        wsPrincipal keyed (head' []) @?= "anon"
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

-- --- Phase 10: the ACP gateway (offline; a real pipe pair, stub agent) ---------------------------

acpTests :: TestTree
acpTests =
  testGroup
    "acp gateway (Zed ACP over stdio)"
    [ testCase "initialize advertises the protocol version and no auth methods" $ do
        c <- spawnAcp []
        acpSend c (object ["jsonrpc" .= t "2.0", "id" .= (1 :: Int), "method" .= t "initialize", "params" .= object []])
        resp <- acpRecv c
        at resp ["result", "protocolVersion"] @?= Just (toJSON Acp.acpProtocolVersion)
        at resp ["result", "authMethods"] @?= Just (toJSON ([] :: [Value]))
        at resp ["result", "agentCapabilities", "loadSession"] @?= Just (Bool False),
      testCase "session/new then session/prompt streams message chunks and ends" $ do
        c <- spawnAcp [TextDelta "the answer ", TextDelta "is 42", Done EndTurn]
        acpSend c (object ["jsonrpc" .= t "2.0", "id" .= (1 :: Int), "method" .= t "session/new", "params" .= object []])
        sid <- acpRecv c >>= \v -> maybe (assertFailure "no sessionId") pure (at v ["result", "sessionId"] >>= asStr)
        assertBool "session ids are namespaced" ("acp-" `T.isPrefixOf` sid)
        acpSend c (promptReq 2 sid "hi")
        (notes, resp) <- acpRecvUntilResult c
        -- The two deltas arrive as agent_message_chunk updates on this session.
        let chunks = [x | n <- notes, at n ["params", "update", "sessionUpdate"] == Just (String "agent_message_chunk"), Just x <- [at n ["params", "update", "content", "text"] >>= asStr]]
        T.concat chunks @?= "the answer is 42"
        assertBool "every update names the session" (all (\n -> at n ["params", "sessionId"] == Just (String sid)) notes)
        at resp ["result", "stopReason"] @?= Just (String "end_turn"),
      testCase "tool calls surface as tool_call then tool_call_update with rawInput" $ do
        c <-
          spawnAcp
            [ ToolUseStart "call_1" "read_file",
              ToolUseDelta "call_1" "{\"path\":\"a.hs\"}",
              ToolUseEnd "call_1",
              TextDelta "done",
              Done EndTurn
            ]
        acpSend c (promptReq 1 "acp-1" "read it")
        (notes, resp) <- acpRecvUntilResult c
        start <- maybe (assertFailure "a tool_call update") pure (find (\n -> at n ["params", "update", "sessionUpdate"] == Just (String "tool_call")) notes)
        at start ["params", "update", "toolCallId"] @?= Just (String "call_1")
        at start ["params", "update", "kind"] @?= Just (String "read")
        end <- maybe (assertFailure "a tool_call_update") pure (find (\n -> at n ["params", "update", "sessionUpdate"] == Just (String "tool_call_update")) notes)
        at end ["params", "update", "status"] @?= Just (String "completed")
        -- The accumulated argument JSON is surfaced as rawInput.
        at end ["params", "update", "rawInput", "path"] @?= Just (String "a.hs")
        at resp ["result", "stopReason"] @?= Just (String "end_turn"),
      testCase "a refusal maps to the refusal stop reason" $ do
        c <- spawnAcp [Done Refusal]
        acpSend c (promptReq 1 "acp-1" "x")
        (_, resp) <- acpRecvUntilResult c
        at resp ["result", "stopReason"] @?= Just (String "refusal"),
      testCase "an empty prompt is an invalid-params error" $ do
        c <- spawnAcp []
        acpSend c (object ["jsonrpc" .= t "2.0", "id" .= (5 :: Int), "method" .= t "session/prompt", "params" .= object ["sessionId" .= t "acp-1", "prompt" .= ([] :: [Value])]])
        resp <- acpRecv c
        at resp ["error", "code"] @?= Just (toJSON (-32602 :: Int)),
      testCase "an unknown method is a -32601" $ do
        c <- spawnAcp []
        acpSend c (object ["jsonrpc" .= t "2.0", "id" .= (9 :: Int), "method" .= t "frobnicate", "params" .= object []])
        resp <- acpRecv c
        at resp ["error", "code"] @?= Just (toJSON (-32601 :: Int)),
      testCase "a malformed line is skipped, not fatal" $ do
        c <- spawnAcp []
        acpSendRaw c "{not json"
        acpSend c (object ["jsonrpc" .= t "2.0", "id" .= (1 :: Int), "method" .= t "initialize", "params" .= object []])
        resp <- acpRecv c
        at resp ["result", "protocolVersion"] @?= Just (toJSON Acp.acpProtocolVersion),
      testCase "tool kinds map sensibly" $ do
        map Acp.toolKind ["read_files", "edit_files", "find_references", "shell", "whatever"]
          @?= ["read", "edit", "search", "execute", "other"],
      testCase "prompt text extraction reads text blocks and embedded resources" $ do
        let prompt =
              toJSON
                [ object ["type" .= t "text", "text" .= t "hello "],
                  object ["type" .= t "resource_link", "uri" .= t "file:///x"],
                  object ["type" .= t "resource", "resource" .= object ["text" .= t "big "]],
                  object ["type" .= t "text", "text" .= t "world"]
                ]
        Acp.extractPromptText (Just prompt) @?= "hello big world"
        Acp.extractPromptText Nothing @?= "",
      testCase "stop reasons narrow to the ACP set" $ do
        map Acp.mapStopReason [MaxTokens, Refusal, EndTurn, ToolUse, Other "x"]
          @?= ["max_tokens", "refusal", "end_turn", "end_turn", "end_turn"]
    ]
  where
    t = id :: Text -> Text
    promptReq :: Int -> Text -> Text -> Value
    promptReq i sid txt =
      object
        [ "jsonrpc" .= t "2.0",
          "id" .= i,
          "method" .= t "session/prompt",
          "params" .= object ["sessionId" .= sid, "prompt" .= [object ["type" .= t "text", "text" .= txt]]]
        ]
    asStr = \case String x -> Just x; _ -> Nothing
    -- Walk a JSON path, so assertions read like the Rust `resp["result"]["stopReason"]`.
    at v [] = Just v
    at (Object o) (k : ks) = KM.lookup (K.fromText k) o >>= \v -> at v ks
    at _ _ = Nothing

-- | A live ACP server over a real pipe pair, plus the client end of each pipe. The gateway is
-- transport-agnostic, so this exercises the actual framing/dispatch it uses on stdio.
data AcpClient = AcpClient {acpIn :: Handle, acpOut :: Handle}

spawnAcp :: [Event] -> IO AcpClient
spawnAcp evs = do
  (serverIn, clientOut) <- createPipe -- client → server
  (clientIn, serverOut) <- createPipe -- server → client
  mapM_ (`hSetEncoding` utf8) [serverIn, clientOut, clientIn, serverOut]
  hSetBuffering clientOut LineBuffering
  let stub = AgentHandle $ \_ -> do s <- fromList (map Right evs); pure (Right s)
  _ <- forkIO (void (Acp.serveAcpOver stub serverIn serverOut))
  pure (AcpClient clientIn clientOut)

acpSend :: AcpClient -> Value -> IO ()
acpSend c = acpSendRaw c . decodeUtf8Lenient . BL.toStrict . encode

acpSendRaw :: AcpClient -> Text -> IO ()
acpSendRaw c line = TIO.hPutStrLn (acpOut c) line >> hFlush (acpOut c)

acpRecv :: AcpClient -> IO Value
acpRecv c = do
  line <- TIO.hGetLine (acpIn c)
  maybe (assertFailure ("unparseable reply: " <> T.unpack line)) pure (decode (BL.fromStrict (encodeUtf8 line)))

-- | Read reply lines until one carries a @result@ or @error@ (a response), collecting the
-- notifications seen on the way.
acpRecvUntilResult :: AcpClient -> IO ([Value], Value)
acpRecvUntilResult c = go []
  where
    go acc = do
      v <- acpRecv c
      case v of
        Object o | KM.member "result" o || KM.member "error" o -> pure (reverse acc, v)
        _ -> go (v : acc)

-- --- Phase 15: the inline TUI (offline; the pure render/pricing/approval logic) -------------------

tuiTests :: TestTree
tuiTests =
  testGroup
    "tui frontend"
    [ testGroup
        "markdown"
        [ testCase "inline styles bold, italic, and code" $ do
            let segs = Md.inline "a **b** c `d` _e_"
            -- Reconstruct the text to confirm markers are consumed, not literal.
            T.concat (map fst segs) @?= "a b c d e"
            assertBool "bold b" (any (\(t, st) -> t == "b" && Md.stBold st) segs)
            assertBool "code d" (any (\(t, st) -> t == "d" && Md.stFg st == Just Md.Cyan) segs)
            assertBool "italic e" (any (\(t, st) -> t == "e" && Md.stItalic st) segs),
          testCase "an unterminated marker stays literal" $ do
            let segs = Md.inline "2 * 3 = 6"
            T.concat (map fst segs) @?= "2 * 3 = 6"
            assertBool "nothing italicised" (not (any (Md.stItalic . snd) segs)),
          testCase "wrap splits at width and preserves style" $ do
            let rows = Md.wrap [("abcdef", Md.bold Md.defaultStyle)] 3
            length rows @?= 2
            map (T.concat . map fst) rows @?= ["abc", "def"]
            assertBool "style survives the wrap" (all (all (Md.stBold . snd)) rows),
          testCase "wide characters count as two columns" $ do
            Md.displayWidth "한글" @?= 4
            Md.charWidth 'a' @?= 1
            map (T.concat . map fst) (Md.wrap [("한글", Md.defaultStyle)] 2) @?= ["한", "글"],
          testCase "detects table and separator rows" $ do
            assertBool "row" (Md.isTableRow "| a | b |")
            assertBool "indented row" (Md.isTableRow "  |x|")
            assertBool "prose" (not (Md.isTableRow "just text"))
            assertBool "sep" (Md.isSeparatorRow "|---|:--:|")
            assertBool "sep with spaces" (Md.isSeparatorRow "| :-- | --: |")
            assertBool "header is not a sep" (not (Md.isSeparatorRow "| a | b |")),
          testCase "renders an aligned table" $ do
            let ls = ["| Name | Score |", "|------|------:|", "| alice | 3 |", "| bob | 100 |"]
            rows <- maybe (assertFailure "valid table") pure (Md.renderTable ls 80)
            -- header + rule + 2 data rows.
            length rows @?= 4
            assertBool "header cells are bold" (any (\(t, st) -> "Name" `T.isInfixOf` t && Md.stBold st) (rows !! 0))
            let rule = T.concat (map fst (rows !! 1))
            assertBool "rule uses box characters" ("─" `T.isInfixOf` rule && "┼" `T.isInfixOf` rule)
            -- Right-aligned Score column pads on the left ("  3").
            assertBool "right-aligned" ("  3" `T.isInfixOf` T.concat (map fst (rows !! 2))),
          testCase "lines without a separator row are not a table" $
            Md.renderTable ["| a | b |", "| c | d |"] 80 @?= Nothing,
          testCase "a too-wide table shrinks to fit" $ do
            let ls = ["| col |", "|-----|", "| " <> T.replicate 200 "x" <> " |"]
            rows <- maybe (assertFailure "valid table") pure (Md.renderTable ls 40)
            mapM_ (\r -> assertBool "row within width" (sum (map (Md.displayWidth . fst) r) <= 40)) rows
        ],
      testGroup
        "pricing"
        [ testCase "known models price out" $ do
            let usage = MkUsage 1000000 1000000 0 0
            -- Sonnet: $3 in + $15 out per 1M = $18.
            sonnet <- maybe (assertFailure "sonnet priced") pure (Price.estimateUsd "claude-sonnet-4" usage)
            assertBool ("got " <> show sonnet) (abs (sonnet - 18.0) < 1e-9)
            -- Opus is pricier than Sonnet for identical usage.
            opus <- maybe (assertFailure "opus priced") pure (Price.estimateUsd "claude-opus-4" usage)
            assertBool "opus > sonnet" (opus > sonnet),
          testCase "an unknown model has no estimate" $
            Price.estimateUsd "some-random-model" emptyUsage @?= Nothing,
          testCase "token formatting" $ do
            Price.fmtTokens 950 @?= "950"
            Price.fmtTokens 1500 @?= "1.5k"
        ],
      testGroup
        "approval gate"
        [ testCase "read-only tools are auto-allowed, others ask" $ do
            map TG.isReadOnly ["read_file", "find_references", "grep", "write_file", "edit_files", "shell", "fs_delete"]
              @?= [True, True, True, False, False, False, False],
          testCase "a read-only call needs no prompt" $ do
            (gate, _permits) <- TG.newChannelGate
            -- No one is draining the permits; a read-only tool must still resolve immediately.
            d <- review gate "read_file" (object ["path" .= ("a" :: Text)])
            d @?= Allow,
          testCase "a mutating call prompts, and 'always' is remembered" $ do
            (gate, permits) <- TG.newChannelGate
            -- Drive the "UI": approve-always the first prompt.
            done <- newEmptyMVar
            _ <- forkIO (review gate "write_file" (object ["path" .= ("a" :: Text)]) >>= putMVar done)
            req <- TG.recvPermit permits
            TG.prName req @?= "write_file"
            assertBool "the preview carries the arguments" ("\"a\"" `T.isInfixOf` TG.prArgs req)
            TG.answerPermit req TG.AllowAlways
            takeMVar done >>= (@?= Allow)
            -- The second call is now auto-allowed with no prompt.
            d <- review gate "write_file" (object ["path" .= ("b" :: Text)])
            d @?= Allow,
          testCase "a denied call is reported back to the model" $ do
            (gate, permits) <- TG.newChannelGate
            done <- newEmptyMVar
            _ <- forkIO (review gate "shell" (object []) >>= putMVar done)
            req <- TG.recvPermit permits
            TG.answerPermit req TG.DenyOnce
            takeMVar done >>= \case
              Deny _ -> pure ()
              other -> assertFailure ("expected Deny, got " <> show other)
        ],
      testGroup
        "app state"
        [ testCase "slash commands parse" $ do
            map Tui.parseCommand ["help", "q", "clear", "new", "session work", "session", "model opus", "m", "frob"]
              @?= [ Tui.CmdHelp,
                    Tui.CmdQuit,
                    Tui.CmdClear,
                    Tui.CmdNew,
                    Tui.CmdSession "work",
                    Tui.CmdSession "",
                    Tui.CmdModel "opus",
                    Tui.CmdModel "",
                    Tui.CmdUnknown "frob"
                  ],
          testCase "tool_hint pulls the salient argument" $ do
            map Tui.toolHint ["{\"path\":\"src/Main.hs\"}", "{\"command\":\"cabal test\"}", "{\"unknown\":1}", "not json"]
              @?= ["src/Main.hs", "cabal test", "", ""],
          testCase "hardWrap breaks at width without clipping" $ do
            Tui.hardWrap "abcdef" 3 @?= ["abc", "def"]
            Tui.hardWrap "" 5 @?= [""],
          testCase "a model override selects the active model" $ do
            let app = Tui.newApp "s" "base"
            Tui.activeModel app @?= "base"
            Tui.activeModel app {Tui.appModelOverride = Just "opus"} @?= "opus",
          testCase "the footer reports session, model, flows, and spend" $ do
            let app = (Tui.newApp "s" "claude-sonnet-4") {Tui.appUsage = MkUsage 1000000 0 0 0}
            -- 1M sonnet input tokens = $3.
            Tui.footerLine app @?= "s · claude-sonnet-4 · ↑1000.0k ↓0 · ~$3.0000"
            -- An unpriced model falls back to a raw token count.
            let unknown = (Tui.newApp "s" "mystery") {Tui.appUsage = MkUsage 1200 300 0 0}
            assertBool "token fallback" ("1.5k tok" `T.isSuffixOf` Tui.footerLine unknown)
        ]
    ]

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
        map msgRole back @?= [Assistant, User],
      testCase "a corrupt session file is preserved, not silently wiped" $ withTmp "filestore-corrupt" $ \dir -> do
        store <- newFileStore dir Nothing
        -- Simulate a crash mid-write (pre-atomic behaviour): a truncated, unparseable file.
        let path = dir </> sessionFileFor "!room:hs"
        BS.writeFile path "[{\"role\":\"user\",\"con"
        -- load must not throw or return garbage — it starts empty …
        loadSession store "!room:hs" >>= \h -> length h @?= 0
        -- … and must NOT have discarded the evidence: the bad file is set aside, the live path freed.
        doesFileExist (path <> ".corrupt") >>= assertBool "corrupt file preserved as .corrupt"
        doesFileExist path >>= \live -> assertBool "corrupt file moved off the live path" (not live)
        -- A subsequent save writes a valid transcript and leaves the preserved evidence intact.
        saveSession store "!room:hs" [userMessage "fresh"]
        loadSession store "!room:hs" >>= \h -> length h @?= 1
        doesFileExist (path <> ".corrupt") >>= assertBool "preserved evidence survives the next save",
      testCase "an atomic save leaves no temp files behind" $ withTmp "filestore-atomic" $ \dir -> do
        store <- newFileStore dir Nothing
        saveSession store "s" [userMessage "hi"]
        -- The temp file was renamed into place, not left behind.
        entries <- listDirectory dir
        filter (".tmp" `isSuffixOf`) entries @?= []
        loadSession store "s" >>= \h -> length h @?= 1
    ]
  where
    -- Mirrors 'Lavoisier.Memory.sessionFile': the hex-encoded, filesystem-safe session filename.
    sessionFileFor :: Text -> FilePath
    sessionFileFor t = concatMap byteHex (BS.unpack (encodeUtf8 t)) <> ".json"
    byteHex :: Word8 -> String
    byteHex w = [hexDigit (w `div` 16), hexDigit (w `mod` 16)]
    hexDigit n
      | n < 10 = toEnum (fromEnum '0' + fromIntegral n)
      | otherwise = toEnum (fromEnum 'a' + fromIntegral n - 10)

-- --- Phase 12: Dhall config (offline; loads real Dhall from a temp file) --------------------------

logTests :: TestTree
logTests =
  testGroup
    "operator logging"
    [ testCase "parseLogLevel reads bare level names" $ do
        map parseLogLevel ["error", "warn", "info", "debug"] @?= [LogError, LogWarn, LogInfo, LogDebug]
        parseLogLevel "WARN" @?= LogWarn
        parseLogLevel "trace" @?= LogDebug,
      testCase "parseLogLevel reduces a RUST_LOG directive set to its last bare level" $ do
        parseLogLevel "lvz_gw_matrix=debug,info" @?= LogInfo
        parseLogLevel "lvz_agent=debug,warn,foo=trace" @?= LogWarn,
      testCase "parseLogLevel falls back to info" $ do
        parseLogLevel "" @?= LogInfo
        parseLogLevel "garbage" @?= LogInfo
        parseLogLevel "lvz_gw_matrix=debug" @?= LogInfo, -- no bare token
      testCase "the level ordering makes info admit warn+error, not debug" $
        assertBool "info < debug, error < info" (LogError < LogInfo && LogInfo < LogDebug)
    ]

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
        fc @?= defaultConfig,
      -- The Matrix permission maps are the reason the file has to be able to reach the gateway at
      -- all: with them unset every sender gets the whole registry in every room, silently.
      testCase "the Matrix tool maps decode from Dhall's assoc-list encoding" $ withTmp "config3" $ \dir -> do
        let f = dir </> "c.dhall"
        TIO.writeFile
          f
          "{ matrixRoomTools = Some (toMap { `!ops:hs` = [\"obs_start\", \"schedule_list\"] })\n\
          \, matrixUserTools = Some (toMap { `@rian:hs` = [\"obs_start\"] })\n\
          \, persona = Some \"/etc/lavoisier/PERSONA.md\"\n\
          \, scheduleRetryMax = Some 3, scheduleRetryWait = Some 60 }"
        fc <- loadConfig f
        matrixRoomTools fc @?= Just (Map.fromList [("!ops:hs", ["obs_start", "schedule_list"])])
        matrixUserTools fc @?= Just (Map.fromList [("@rian:hs", ["obs_start"])])
        persona fc @?= Just "/etc/lavoisier/PERSONA.md"
        scheduleRetryMax fc @?= Just 3
        scheduleRetryWait fc @?= Just 60,
      testCase "applyConfig writes them onto Options (the file is their only source)" $ do
        let fc =
              defaultConfig
                { matrixRoomTools = Just (Map.fromList [("!ops:hs", ["obs_start"])]),
                  matrixUserTools = Just (Map.fromList [("@rian:hs", ["obs_start"])]),
                  persona = Just "/etc/lavoisier/PERSONA.md",
                  system = Just "custom",
                  scheduleRetryMax = Just 3,
                  scheduleRetryWait = Just 60
                }
            o = CLI.applyConfig fc bareOptions
        CLI.optMatrixRoomTools o @?= Map.fromList [("!ops:hs", ["obs_start"])]
        CLI.optMatrixUserTools o @?= Map.fromList [("@rian:hs", ["obs_start"])]
        CLI.optPersona o @?= Just "/etc/lavoisier/PERSONA.md"
        CLI.optSystem o @?= Just "custom"
        CLI.optScheduleRetryMax o @?= Just 3
        CLI.optScheduleRetryWait o @?= Just 60,
      testCase "a CLI --persona wins over the file" $ do
        let o = CLI.applyConfig defaultConfig {persona = Just "from-file"} bareOptions {CLI.optPersona = Just "from-flag"}
        CLI.optPersona o @?= Just "from-flag",
      testCase "layerPersona puts the persona above the operating instructions, never over them" $ do
        layerPersona Nothing Nothing @?= Nothing
        layerPersona Nothing (Just "sys") @?= Just "sys"
        case layerPersona (Just "I am Lavoisier.") Nothing of
          Nothing -> assertFailure "expected a layered prompt"
          Just t -> do
            assertBool "persona first" ("I am Lavoisier." `T.isPrefixOf` t)
            assertBool "operating instructions retained" (defaultSystemPrompt `T.isInfixOf` t)
        case layerPersona (Just "persona") (Just "custom ops") of
          Nothing -> assertFailure "expected a layered prompt"
          Just t -> do
            assertBool "custom ops used" ("custom ops" `T.isInfixOf` t)
            assertBool "default not smuggled in" (not (defaultSystemPrompt `T.isInfixOf` t))
    ]
  where
    layerPersona = CLI.layerPersona

-- | The all-unset 'CLI.Options', built through the real parser so the record and the parser stay
-- aligned (they are positional — a mismatch is a silent field swap, not a type error).
bareOptions :: CLI.Options
bareOptions = case execParserPure defaultPrefs (info CLI.optionsParser mempty) [] of
  Success o -> o
  _ -> error "optionsParser must accept an empty argument list"

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

-- | Write a cron Dhall file (type @C@ + default record @c@ to merge over) and load it.
loadCron :: FilePath -> Int -> Int -> Text -> IO (Either CronConfigError [CronJob])
loadCron dir rmax rwait body = do
  let path = dir </> "cron.dhall"
      preamble =
        "let C = { schedule : Text, session : Optional Text, prompt : Text, retryMax : Optional Natural, retryWait : Optional Natural }\n"
          <> "let c : C = { schedule = \"* * * * *\", session = None Text, prompt = \"\", retryMax = None Natural, retryWait = None Natural }\n"
          <> "in "
  TIO.writeFile path (preamble <> body)
  loadFileJobs path rmax rwait

-- | Write a schedule Dhall file (with a type @J@ and an all-@None@ default record @d@ to merge over
-- with @//@) and load it through the real Dhall loader.
loadSched :: FilePath -> Int -> Integer -> Text -> IO (Either Sch.ScheduleConfigError [Sch.ScheduleJob])
loadSched dir rmax rwait body = do
  let path = dir </> "sched.dhall"
      preamble =
        "let J = { jobId : Text, schedule : Text, room : Optional Text, session : Optional Text, tool : Optional Text, toolArgs : Optional Text, prompt : Optional Text, summarize : Optional Text, retryMax : Optional Natural, retryWait : Optional Natural }\n"
          <> "let d : J = { jobId = \"\", schedule = \"* * * * *\", room = None Text, session = None Text, tool = None Text, toolArgs = None Text, prompt = None Text, summarize = None Text, retryMax = None Natural, retryWait = None Natural }\n"
          <> "in "
  TIO.writeFile path (preamble <> body)
  Sch.loadScheduleFile path rmax rwait

scheduleTests :: TestTree
scheduleTests =
  testGroup
    "schedule (jobs + registry + tools)"
    [ testCase "loadScheduleFile builds tool + prompt jobs with defaults (Dhall)" $ withTmp "sch" $ \dir -> do
        js <-
          loadSched dir 2 30 $
            "[ d // { jobId = \"disk\", schedule = \"0 * * * *\", tool = Some \"shell\", toolArgs = Some \"{\\\"command\\\":\\\"df\\\"}\" }"
              <> ", d // { jobId = \"digest\", schedule = \"0 9 * * *\", prompt = Some \"summarize\" } ]"
        js2 <- either (assertFailure . show) pure js
        map Sch.sjId js2 @?= ["disk", "digest"]
        case js2 of
          (a : b : _) -> do
            Sch.sjAction a @?= Sch.ActTool "shell" (object ["command" .= ("df" :: Text)])
            Sch.sjSession a @?= "schedule-disk" -- default session
            Sch.sjRetryMax a @?= 2 -- global default applied
            Sch.sjAction b @?= Sch.ActPrompt "summarize"
          _ -> assertFailure "expected two jobs",
      testCase "loadScheduleFile rejects ambiguous action / duplicate id / bad cron (Dhall)" $ withTmp "sch" $ \dir -> do
        let bad e body = loadSched dir 0 0 body >>= \r -> case r of Left err | err == e -> pure (); other -> assertFailure ("expected " <> show e <> ", got " <> show (fmap (map Sch.sjId) other))
        bad (Sch.SceAction "x") "[ d // { jobId = \"x\" } ]"
        bad (Sch.SceDuplicateId "x") "[ d // { jobId = \"x\", tool = Some \"t\" }, d // { jobId = \"x\", prompt = Some \"p\" } ]"
        r <- loadSched dir 0 0 "[ d // { jobId = \"x\", schedule = \"nonsense\", prompt = Some \"p\" } ]"
        case r of
          Left (Sch.SceCron "x" _) -> pure ()
          other -> assertFailure ("expected SceCron, got " <> show (fmap (map Sch.sjId) other)),
      testCase "recordOutcome tracks runs/failures/streak and retry scheduling" $ withTmp "sch" $ \dir -> do
        js <- either (assertFailure . show) pure =<< loadSched dir 0 0 "[ d // { jobId = \"j\", prompt = Some \"p\", retryMax = Some 1, retryWait = Some 60 } ]"
        let j = js !! 0
        reg <- Sch.newRegistry 0 js
        r1 <- Sch.recordOutcome reg 100 j (Left "boom") -- attempt 1, retry (1<=1)
        r1 @?= Sch.FireRecord 1 (Just 60) False
        s1 <- maybe (assertFailure "no state") pure =<< Sch.stateOf reg "j"
        (Sch.jsRuns s1, Sch.jsFailures s1, Sch.jsConsecutiveFailures s1) @?= (1, 1, 1)
        Sch.jsRetryAt s1 @?= Just 160
        Sch.jsNextDue s1 @?= Nothing -- cron slot suppressed during a retry chain
        r2 <- Sch.recordOutcome reg 200 j (Left "boom2") -- attempt 2, retries exhausted
        r2 @?= Sch.FireRecord 2 Nothing True
        s2 <- maybe (assertFailure "no state") pure =<< Sch.stateOf reg "j"
        Sch.jsRetryAt s2 @?= Nothing
        assertBool "next cron slot rearmed" (Sch.jsNextDue s2 /= Nothing)
        r3 <- Sch.recordOutcome reg 300 j (Right "ok") -- success resets the streak
        r3 @?= Sch.FireRecord 1 Nothing False
        s3 <- maybe (assertFailure "no state") pure =<< Sch.stateOf reg "j"
        Sch.jsConsecutiveFailures s3 @?= 0,
      testCase "reportBody keeps the failure structure outside the paraphrasable detail slot" $ withTmp "sch" $ \dir -> do
        js <- either (assertFailure . show) pure =<< loadSched dir 0 0 "[ d // { jobId = \"w\", prompt = Some \"p\", retryMax = Some 3, retryWait = Some 60 } ]"
        let j = js !! 0
            -- The prose a `summarize` turn produced, standing in for the raw error.
            prose = "The wake FAILED: the power call was refused."
            failed = Sch.reportBody j False prose (Sch.FireRecord 1 (Just 60) False)
        -- Verdict marker, attempt counter, and retry countdown are structural…
        assertBool "marker" ("\10060" `T.isInfixOf` failed)
        assertBool "attempt" ("attempt 1" `T.isInfixOf` failed)
        assertBool "countdown" ("\8635 retry 1/3 in 60s" `T.isInfixOf` failed)
        -- …and the room sees the prose in the detail slot.
        assertBool "prose" (prose `T.isInfixOf` failed)
        -- Exhausting the budget says so instead of counting down.
        let gaveUp = Sch.reportBody j False prose (Sch.FireRecord 4 Nothing True)
        assertBool "gave up" ("\9940 gave up after 3 retries" `T.isInfixOf` gaveUp)
        assertBool "no countdown once exhausted" (not ("\8635" `T.isInfixOf` gaveUp))
        -- A success that needed retries reports how many; a first-try success does not.
        Sch.reportBody j True "all good" (Sch.FireRecord 1 Nothing False) @?= "\9989 `w` \183 all good"
        Sch.reportBody j True "all good" (Sch.FireRecord 2 Nothing False) @?= "\9989 `w` (after 2 attempts) \183 all good",
      testCase "schedule_run queues a known job and errors on an unknown one" $ withTmp "sch" $ \dir -> do
        js <- either (assertFailure . show) pure =<< loadSched dir 0 0 "[ d // { jobId = \"j\", prompt = Some \"p\" } ]"
        reg <- Sch.newRegistry 0 js
        let runTool = Sch.scheduleTools reg !! 2 -- list, status, run
        r1 <- toolInvoke runTool (object ["id" .= ("j" :: Text)])
        either (assertFailure . show) (\o -> toIsError o @?= False) r1
        q <- Sch.takeRequested reg
        q @?= [0]
        r2 <- toolInvoke runTool (object ["id" .= ("nope" :: Text)])
        either (assertFailure . show) (\o -> toIsError o @?= True) r2
    ]

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
      testCase "cron-file (Dhall) reads jobs with session defaults" $ withTmp "cron" $ \dir -> do
        r <-
          loadCron dir 0 0 $
            "[ c // { schedule = \"0 9 * * *\", session = Some \"digest\", prompt = \"morning digest\" }"
              <> ", c // { schedule = \"*/15 * * * *\", prompt = \"poll the queue\" } ]"
        case r of
          Right [j0, j1] -> do
            cjSession j0 @?= "digest"
            cjSession j1 @?= "cron-1"
            cjPrompt j1 @?= "poll the queue"
          Right _ -> assertFailure "expected two jobs"
          Left e -> assertFailure (show e),
      testCase "cron-file (Dhall) per-job retry overrides the global default" $ withTmp "cron" $ \dir -> do
        r <-
          loadCron dir 2 60 $
            "[ c // { schedule = \"0 9 * * *\", prompt = \"defaults\" }"
              <> ", c // { schedule = \"0 9 * * *\", prompt = \"override\", retryMax = Some 5, retryWait = Some 120 } ]"
        case r of
          Right [j0, j1] -> do
            (cjRetryMax j0, cjRetryWait j0) @?= (2, 60)
            (cjRetryMax j1, cjRetryWait j1) @?= (5, 120)
          Right _ -> assertFailure "expected two jobs"
          Left e -> assertFailure (show e),
      testCase "cron-file (Dhall) surfaces a bad schedule" $ withTmp "cron" $ \dir -> do
        r <- loadCron dir 0 0 "[ c // { schedule = \"bad\", prompt = \"x\" } ]"
        assertBool "bad schedule" (isLeftCfg r)
    ]
  where
    parseOk e = either (assertFailure . ("bad cron: " <>) . show) pure (parseCron e)
    isLeftE = either (const True) (const False)
    isLeftCfg = either (const True) (const False)

-- --- Phase 19: xAI provider (offline; OpenAI-compat request + SSE decoder, ports lvz-xai http.rs) --

xaiDecode :: ByteString -> [Event]
xaiDecode input = let (st, e1) = XS.ssePush XS.initSse input in [e | Right e <- e1 <> XS.sseEof st]

-- The xAI native gRPC transport: pure request-build + chunk-decode (no network / grapesy call).
xaiGrpcTests :: TestTree
xaiGrpcTests =
  testGroup
    "xAI (gRPC)"
    [ testCase "mapFinish maps proto finish reasons" $ do
        XG.mapFinish SX.REASON_STOP @?= EndTurn
        XG.mapFinish SX.REASON_MAX_LEN @?= MaxTokens
        XG.mapFinish SX.REASON_TOOL_CALLS @?= ToolUse,
      testCase "decodeChunk emits a TextDelta from a delta chunk" $ do
        let chunk :: PX.GetChatCompletionChunk
            chunk = defMessage & #outputs .~ [defMessage & #maybe'delta .~ Just (defMessage & #content .~ "hi") & #finishReason .~ SX.REASON_STOP]
        fst (XG.decodeChunk XG.emptyDecoder chunk) @?= [TextDelta "hi"],
      testCase "decodeChunk opens and streams a tool call" $ do
        let call = defMessage & #id .~ "t1" & #function .~ (defMessage & #name .~ "read_file" & #arguments .~ "{}")
            chunk :: PX.GetChatCompletionChunk
            chunk = defMessage & #outputs .~ [defMessage & #maybe'delta .~ Just (defMessage & #toolCalls .~ [call])]
        fst (XG.decodeChunk XG.emptyDecoder chunk) @?= [ToolUseStart "t1" "read_file", ToolUseDelta "t1" "{}"],
      testCase "buildMessages maps roles (system, tool-result, assistant)" $ do
        let req =
              (chatRequest "grok-4")
                { crSystem = Just (SystemPrompt "sys" False),
                  crMessages =
                    [ Message User [ToolResultBlock "t1" "the result" False],
                      Message Assistant [TextBlock "hi" False, ToolUseBlock "t2" "f" (object [])]
                    ]
                }
        map (^. #role) (XG.buildMessages req) @?= [PX.ROLE_SYSTEM, PX.ROLE_TOOL, PX.ROLE_ASSISTANT]
    ]

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
        map MX.imBody msgs @?= ["hello bot"]
        map MX.imAttachment msgs @?= [Nothing],
      testCase "messageContent: text vs plaintext media attachment vs unsupported" $ do
        MX.messageContent (textContent "hi") @?= Just ("hi", Nothing)
        let img = object ["msgtype" .= t "m.image", "body" .= t "cat.png", "url" .= t "mxc://hs/abc", "info" .= object ["mimetype" .= t "image/png"]]
        MX.messageContent img @?= Just ("cat.png", Just (MX.Attachment "mxc://hs/abc" "cat.png" "image/png"))
        -- an encrypted image (reference under `file`, no plaintext url) is not ingested
        MX.messageContent (object ["msgtype" .= t "m.image", "body" .= t "secret.png", "file" .= object ["url" .= t "mxc://hs/enc"]]) @?= Nothing,
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
      testCase "extractInvites and parseNextBatch" $ do
        let sync = object ["next_batch" .= t "tok", "rooms" .= object ["invite" .= object ["!inv:hs" .= object []]]]
        MX.extractInvites sync @?= ["!inv:hs"]
        MX.parseNextBatch sync @?= Right "tok"
        assertBool "no next_batch is an error" (isLeftE (MX.parseNextBatch (object []))),
      testCase "languageFromLocale selects Korean only for ko_KR" $ do
        MX.languageFromLocale "ko_KR.UTF-8" @?= MX.Korean
        MX.languageFromLocale "KO_kr" @?= MX.Korean
        MX.languageFromLocale "en_US.UTF-8" @?= MX.English
        MX.languageFromLocale "" @?= MX.English
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
