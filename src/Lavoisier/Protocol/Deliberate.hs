{- | The 'Deliberator' contract: a multi-model __council__ ("legion") that argues out a task before
the agent acts. Ported from Rust @lvz-protocol@ @deliberate.rs@.

This mirrors the 'Lavoisier.Protocol.Tune.Tuner' shape: the agent holds an optional 'Deliberator'
and, when one is configured, runs a __pre-pass__ that asks the council to deliberate the task and
folds the agreed plan into the transcript before the tool-using loop begins (deliberate-then-act).
Absent by default, so the agent runs identically whether or not @Lavoisier.Legion@ is present.

The contract is narrow — one @task@ string in, one agreed 'Deliberation' out — so this keystone
module stays free of any knowledge of /how/ the council debates (how many debaters, which
providers, how many rounds, who judges). That policy lives in the implementing module.

Rust's @Arc\<dyn Deliberator\>@ with its two methods becomes a __record of one function__: the
context-aware 'runDeliberation'. The bare form is the helper 'deliberate' (context = empty).
-}
module Lavoisier.Protocol.Deliberate (
    DeliberationContext (..),
    emptyDeliberationContext,
    dcNotify,
    Deliberation (..),
    emptyDeliberation,
    DeliberateError (..),
    Deliberator (..),
    deliberate,
)
where

import Data.Text (Text)

import Lavoisier.Protocol.Event (Usage, emptyUsage)
import Lavoisier.Protocol.Message (ToolDef)

{- | The executor's context, handed to the council so it deliberates __as the agent__ rather than as
a generic, tool-less assistant. Without it a council reasons in a vacuum — not knowing the agent's
persona, and assuming it has no tools — so it can wrongly conclude a task is impossible and
synthesise a /refusal/ that then seeds (and dooms) the executor even though the executor holds the
tools. Supplying the system prompt and this turn's advertised tools closes that gap.
-}
data DeliberationContext = DeliberationContext
    { dcSystem ∷ Text
    {- ^ The executor's full system prompt (persona + operating instructions), so the council shares
    the agent's identity, priorities, and constraints.
    -}
    , dcTools ∷ [ToolDef]
    {- ^ The tools advertised to the executor __this turn__ (already permission-filtered), so the
    council plans with the real capabilities instead of assuming it has none.
    -}
    , dcProgress ∷ Maybe (Text → IO ())
    {- ^ Optional __progress sink__: a callback the council may invoke with a short phase notice. The
    agent wires this to the turn's @Event.Notice@ stream so a slow debate isn't dead air. 'Nothing'
    ⇒ the council stays silent.
    -}
    }

{- | A context with no system prompt, no tools, and no progress sink — the council reasons with no
extra grounding (the fallback of the bare 'deliberate').
-}
emptyDeliberationContext ∷ DeliberationContext
emptyDeliberationContext = DeliberationContext "" [] Nothing

-- | Emit a progress @notice@ through the context's sink, if one is set.
dcNotify ∷ DeliberationContext → Text → IO ()
dcNotify ctx notice = maybe (pure ()) ($ notice) (dcProgress ctx)

{- | The agreed outcome of a council deliberation: the synthesised plan-of-action plus the total
token 'Usage' the debate cost. The @plan@ is injected into the executor's transcript as its opening
move (it seeds but does not constrain the loop); the @usage@ is summed across every model call the
council made (drafts, critiques, judge) so the debate's cost flows into the agent's accounting.
-}
data Deliberation = Deliberation
    { delPlan ∷ Text
    , delUsage ∷ Usage
    }
    deriving stock (Eq, Show)

-- | The empty deliberation (no plan, no cost).
emptyDeliberation ∷ Deliberation
emptyDeliberation = Deliberation "" emptyUsage

{- | Why a deliberation failed. The agent treats every one as __non-fatal__ — a failed council is
logged and the turn proceeds unseeded (best-effort) — so these exist for diagnostics.
-}
data DeliberateError
    = -- | Every debater's call errored (or produced empty output), so there was nothing to judge.
      NoPositions
    | -- | The judge call failed or returned an empty synthesis.
      JudgeFailed Text
    | -- | Any other deliberation failure.
      DeliberateOther Text
    deriving stock (Eq, Show)

{- | A multi-model council that argues out a task and returns one agreed plan. Implemented by
@Lavoisier.Legion@'s @Panel@; the agent depends only on this record (the same inversion as
'Lavoisier.Protocol.Provider.Provider' \/ 'Lavoisier.Protocol.Tune.Tuner').
-}
newtype Deliberator = Deliberator
    { runDeliberation ∷ Text → DeliberationContext → IO (Either DeliberateError Deliberation)
    {- ^ Run the council's argument over @task@ with the executor's 'DeliberationContext', returning
    the agreed plan plus the tokens it cost (or a 'DeliberateError').
    -}
    }

-- | The bare entry point: deliberate a @task@ with no executor grounding.
deliberate ∷ Deliberator → Text → IO (Either DeliberateError Deliberation)
deliberate d task = runDeliberation d task emptyDeliberationContext
