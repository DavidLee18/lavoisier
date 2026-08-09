module Main (main) where

import Lavoisier.Protocol.Event (Event (..), StopReason (..))
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "lavoisier"
    [ testCase "Event Eq" $ TextDelta "hi" @?= TextDelta "hi",
      testCase "StopReason Eq" $ Done EndTurn @?= Done EndTurn
    ]
