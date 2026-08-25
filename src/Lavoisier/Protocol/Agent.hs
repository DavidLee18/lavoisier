{- | The gateway-facing agent contract: submit a 'TurnRequest', get back a stream of 'Event's.
Ported from Rust @lvz-protocol@ @agent.rs@ (@Arc\<dyn AgentHandle\>@ → a record of functions).
-}
module Lavoisier.Protocol.Agent (
    TurnRequest (..),
    turnRequest,
    withAllowedTools,
    withModel,
    AgentError (..),
    TurnStream,
    AgentHandle (..),
)
where

import Data.Text (Text)

import Lavoisier.Domain (ModelId, ToolName)
import Lavoisier.Protocol.Event (Event)
import Lavoisier.Protocol.Stream (Producer)

-- | One turn submitted to the agent by a gateway.
data TurnRequest = TurnRequest
    { trSession ∷ Text
    -- ^ Session key; continues a conversation across turns (memory).
    , trInput ∷ Text
    -- ^ The user input for this turn.
    , trAllowedTools ∷ Maybe [ToolName]
    -- ^ Restrict this turn to the given tool names. 'Nothing' = full tool set; @Just []@ = no tools.
    , trModel ∷ Maybe ModelId
    {- ^ Optional per-turn __model override__. 'Nothing' ⇒ the agent's configured executor model
    (the default). @Just name@ runs /this turn/ on that model instead — an interactive frontend
    (the TUI's @\/model@) uses it to switch models mid-session. It replaces the executor model and
    suppresses cheap-model-first for the turn, so the chosen model is used throughout. Within one
    provider (the primary); it does not select a different provider.
    -}
    }
    deriving stock (Eq, Show)

-- | A turn with the default (unrestricted) tool policy.
turnRequest ∷ Text → Text → TurnRequest
turnRequest session input = TurnRequest session input Nothing Nothing

-- | Restrict a turn to the given tool names.
withAllowedTools ∷ [ToolName] → TurnRequest → TurnRequest
withAllowedTools ts tr = tr {trAllowedTools = Just ts}

-- | Run this turn on a specific model instead of the agent's configured one (see 'trModel').
withModel ∷ ModelId → TurnRequest → TurnRequest
withModel m tr = tr {trModel = Just m}

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
    { submit ∷ TurnRequest → IO (Either AgentError TurnStream)
    }
