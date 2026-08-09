module Main (main) where

import Data.Aeson (decode, encode)
import Data.ByteString.Lazy (ByteString)
import Lavoisier.Protocol.Event
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
      usageTests
    ]

-- | Every 'Event' variant must round-trip through JSON (ports the Rust
-- @every_event_variant_roundtrips_through_json@).
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
    [ testCase "end_turn is a bare string" $
        decodeSR "\"end_turn\"" @?= Just EndTurn,
      testCase "other is an object" $
        decodeSR "{\"other\":\"x\"}" @?= Just (Other "x"),
      testCase "roundtrip all" $
        mapM_ (\sr -> decode (encode sr) @?= Just sr) allStops
    ]

allStops :: [StopReason]
allStops = [EndTurn, MaxTokens, ToolUse, StopSequence, Refusal, PauseTurn, Other "custom"]

usageTests :: TestTree
usageTests =
  testGroup
    "Usage"
    [ testCase "cost is weighted, not flat" $
        usageCost (MkUsage 100 10 0 0) defaultCostWeights @?= 150, -- 100*1 + 10*5
      testCase "cache read is cheap" $
        usageCost (MkUsage 0 0 0 100) defaultCostWeights @?= 10, -- 100*0.1
      testCase "accumulate sums fields" $
        accumulateUsage (MkUsage 1 2 3 4) (MkUsage 10 20 30 40) @?= MkUsage 11 22 33 44,
      testCase "cache hit rate" $
        cacheHitRate (MkUsage 25 0 0 75) @?= 0.75,
      testCase "wire fields are snake_case" $
        decodeU "{\"input_tokens\":1,\"output_tokens\":2,\"cache_creation_tokens\":3,\"cache_read_tokens\":4}"
          @?= Just (MkUsage 1 2 3 4)
    ]

decodeE :: ByteString -> Maybe Event
decodeE = decode

decodeSR :: ByteString -> Maybe StopReason
decodeSR = decode

decodeU :: ByteString -> Maybe Usage
decodeU = decode
