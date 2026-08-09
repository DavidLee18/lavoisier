module Main (main) where

import Data.Aeson (decode, encode, object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Message
import Lavoisier.Provider.Anthropic (buildBody)
import Lavoisier.Provider.Anthropic.Sse (initSse, mapStop, sseEof, ssePush)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "lavoisier"
    [ eventTests,
      stopReasonTests,
      usageTests,
      sseTests,
      anthropicBodyTests
    ]

-- --- Phase 1: protocol wire shapes ----------------------------------------------------------------

eventTests :: TestTree
eventTests =
  testGroup "Event JSON" $
    [ testCase ("roundtrip: " <> show ev) (decode (encode ev) @?= Just ev)
      | ev <- allEvents
    ]
      <> [ testCase "wire shape: text_delta" $
             decodeE "{\"kind\":\"text_delta\",\"data\":\"hello\"}" @?= Just (TextDelta "hello"),
           testCase "wire shape: tool_use_start" $
             decodeE "{\"kind\":\"tool_use_start\",\"data\":{\"id\":\"i\",\"name\":\"read\"}}"
               @?= Just (ToolUseStart "i" "read"),
           testCase "wire shape: done/end_turn" $
             decodeE "{\"kind\":\"done\",\"data\":\"end_turn\"}" @?= Just (Done EndTurn),
           testCase "wire shape: done/other" $
             decodeE "{\"kind\":\"done\",\"data\":{\"other\":\"weird\"}}"
               @?= Just (Done (Other "weird"))
         ]

allEvents :: [Event]
allEvents =
  [ TextDelta "hello",
    Thinking "hmm",
    ToolUseStart "id1" "read_file",
    ToolUseDelta "id1" "{\"path\":",
    ToolUseEnd "id1",
    ServerToolUse "s1" "web_search",
    ServerToolResult "s1" "[]",
    Citation "cited text" "document 1",
    Usage (MkUsage 10 20 5 3),
    Notice "council convened",
    Done EndTurn,
    Done (Other "weird")
  ]

stopReasonTests :: TestTree
stopReasonTests =
  testGroup
    "StopReason JSON"
    [ testCase "end_turn is a bare string" $ decodeSR "\"end_turn\"" @?= Just EndTurn,
      testCase "other is an object" $ decodeSR "{\"other\":\"x\"}" @?= Just (Other "x"),
      testCase "roundtrip all" $ mapM_ (\sr -> decode (encode sr) @?= Just sr) allStops
    ]

allStops :: [StopReason]
allStops = [EndTurn, MaxTokens, ToolUse, StopSequence, Refusal, PauseTurn, Other "custom"]

usageTests :: TestTree
usageTests =
  testGroup
    "Usage"
    [ testCase "cost is weighted, not flat" $
        usageCost (MkUsage 100 10 0 0) defaultCostWeights @?= 150,
      testCase "cache read is cheap" $
        usageCost (MkUsage 0 0 0 100) defaultCostWeights @?= 10,
      testCase "accumulate sums fields" $
        accumulateUsage (MkUsage 1 2 3 4) (MkUsage 10 20 30 40) @?= MkUsage 11 22 33 44,
      testCase "cache hit rate" $ cacheHitRate (MkUsage 25 0 0 75) @?= 0.75,
      testCase "wire fields are snake_case" $
        decodeU "{\"input_tokens\":1,\"output_tokens\":2,\"cache_creation_tokens\":3,\"cache_read_tokens\":4}"
          @?= Just (MkUsage 1 2 3 4)
    ]

-- --- Phase 2: Anthropic SSE decoder (ports lvz-anthropic/src/sse.rs tests) -------------------------

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
        evs !! 0 @?= ToolUseStart "toolu_1" "read_file"
        evs !! 1 @?= ToolUseDelta "toolu_1" "{\"path\":"
        evs !! 2 @?= ToolUseDelta "toolu_1" "\"a.rs\"}"
        evs !! 3 @?= ToolUseEnd "toolu_1"
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

-- Feed one byte at a time (mirrors the Rust byte_at_a_time test).
decodeChunked :: ByteString -> [Event]
decodeChunked input =
  let (st, evs) = BS.foldl' step (initSse, []) input
   in [e | Right e <- evs <> sseEof st]
  where
    step (s, acc) b =
      let (s', more) = ssePush s (BS.singleton b) in (s', acc <> more)

textStream :: ByteString
textStream =
  BS.concat
    [ "event: message_start\n",
      "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":10,\"cache_read_input_tokens\":4,\"cache_creation_input_tokens\":0,\"output_tokens\":1}}}\n\n",
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

-- --- Phase 2: Anthropic request-body construction -------------------------------------------------

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

decodeE :: ByteString -> Maybe Event
decodeE = decode . BL.fromStrict

decodeSR :: ByteString -> Maybe StopReason
decodeSR = decode . BL.fromStrict

decodeU :: ByteString -> Maybe Usage
decodeU = decode . BL.fromStrict
