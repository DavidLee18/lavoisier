-- | The gateway-facing agent contract: submit a 'TurnRequest', get back a stream of 'Event's.
-- Ported from Rust @lvz-protocol@ @agent.rs@ (@Arc\<dyn AgentHandle\>@ → a record of functions).
module Lavoisier.Protocol.Agent
  ( TurnRequest (..),
    turnRequest,
    withAllowedTools,
    AgentError (..),
    TurnStream,
    AgentHandle (..),
  )
where

import Data.Text (Text)
import Lavoisier.Protocol.Event (Event)
import Lavoisier.Protocol.Stream (Producer)

-- | One turn submitted to the agent by a gateway.
data TurnRequest = TurnRequest
  { -- | Session key; continues a conversation across turns (memory).
    trSession :: Text,
    -- | The user input for this turn.
    trInput :: Text,
    -- | Restrict this turn to the given tool names. 'Nothing' = full tool set; @Just []@ = no tools.
    trAllowedTools :: Maybe [Text]
  }
  deriving stock (Eq, Show)

-- | A turn with the default (unrestricted) tool policy.
turnRequest :: Text -> Text -> TurnRequest
turnRequest session input = TurnRequest session input Nothing

-- | Restrict a turn to the given tool names.
withAllowedTools :: [Text] -> TurnRequest -> TurnRequest
withAllowedTools ts tr = tr {trAllowedTools = Just ts}

-- | Errors surfaced by the agent.
data AgentError
  = -- | A provider failure propagated to the turn.
    AEProvider Text
  | -- | A tool dispatch failure.
    AETool Text
  | -- | The turn exceeded its cost-weighted token budget.
    AEBudgetExceeded
  | -- | No such session.
    AEUnknownSession Text
  deriving stock (Eq, Show)

-- | A streamed turn as the gateway sees it: events, each of which may be an 'AgentError'.
type TurnStream = Producer (Either AgentError Event)

-- | The agent, as a record of functions (the @Arc\<dyn AgentHandle\>@ analogue).
newtype AgentHandle = AgentHandle
  { submit :: TurnRequest -> IO (Either AgentError TurnStream)
  }
