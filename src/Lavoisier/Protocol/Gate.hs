{- | The 'ToolGate' contract: an optional per-call __approval hook__ the agent consults before it
executes a tool.

Where 'Lavoisier.Protocol.Agent.trAllowedTools' is a /static/ per-turn allowlist decided up front,
a 'ToolGate' is a /dynamic/ check made at the moment of each call — it can inspect the concrete
arguments and answer interactively. That is what lets an interactive frontend (the TUI) implement
Claude-Code-style \"allow this edit?\" prompts: reads run unattended, mutating calls ask.

It is held on the agent as a @Maybe ToolGate@ (the deliberator\/tuner injection pattern — /not/ in
the config record). 'Nothing' ⇒ every tool runs, byte-identical to a build with no gate, so this
is fully backward-compatible.

Ported from Rust @lvz-protocol@ @gate.rs@ (@Arc\<dyn ToolGate\>@ → a record of functions).
-}
module Lavoisier.Protocol.Gate (
    ToolDecision (..),
    ToolGate (..),
)
where

import Data.Aeson (Value)
import Data.Text (Text)

-- | The verdict a 'ToolGate' returns for one prospective tool call.
data ToolDecision
    = -- | Run the tool.
      Allow
    | {- | Do not run it; the carried reason is fed back to the model as the tool result (as an error),
      so the turn continues and the model can adapt rather than the turn aborting.
      -}
      Deny Text
    deriving stock (Eq, Show)

{- | A hook the agent consults immediately before invoking each tool. Implementations decide —
possibly interactively — whether the call may proceed.
-}
newtype ToolGate = ToolGate
    { review ∷ Text → Value → IO ToolDecision
    {- ^ Review a prospective call to the named tool with its fully-assembled arguments. Returning
    'Deny' blocks execution and surfaces the reason to the model as an error result (never
    aborting the turn).
    -}
    }
