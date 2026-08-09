-- | The normalised event stream every provider adapter emits and the agent/gateways consume.
--
-- This is the keystone of the Haskell port: providers map their wire format (Anthropic SSE, xAI
-- gRPC, Google) onto these constructors, and the agent loop + every gateway consume them without
-- knowing the provider. Placeholder for scaffolding — Phase 1 fills in the full set with aeson
-- instances mirroring the Rust @lvz-protocol@ serde shapes.
module Lavoisier.Protocol.Event
  ( Event (..),
    StopReason (..),
  )
where

import Data.Text (Text)

-- | Why the model stopped generating.
data StopReason
  = EndTurn
  | MaxTokens
  | ToolUse
  | StopSequence
  | Refusal
  | PauseTurn
  | Other Text
  deriving stock (Eq, Show)

-- | One normalised event in a streamed turn (subset; expanded in Phase 1).
data Event
  = TextDelta Text
  | Done StopReason
  deriving stock (Eq, Show)
