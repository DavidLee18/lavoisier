{- | The 'Tuner' contract for adaptive token optimisation (ATO). Ported from Rust @lvz-protocol@
@tune.rs@.

The agent asks a tuner which 'Knobs' to use for a given 'TaskContext' and reports the realised
'Outcome' back. The default 'noopTuner' returns the static baseline 'defaultKnobs' and ignores
observations, so the agent runs identically whether or not the learner is present; enabling ATO
swaps in @Lavoisier.Tune@'s learning implementation with no other change.

Rust's @Arc\<dyn Tuner\>@ becomes a __record of functions__ ('Tuner'). Rust's methods are
synchronous (interior @Mutex@); here 'tunerSelect'\/'tunerObserve' are 'IO' actions (the learner's
state lives behind an 'Data.IORef.IORef'), which is the idiomatic analogue.
-}
module Lavoisier.Protocol.Tune (
    Archetype (..),
    ModelTier (..),
    RepoProfile (..),
    defaultRepoProfile,
    TaskContext (..),
    Knobs (..),
    defaultKnobs,
    Outcome (..),
    defaultOutcome,
    Tuner (..),
    noopTuner,
)
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Word (Word32, Word64)
import GHC.Generics (Generic)

import Lavoisier.Protocol.Message (ThinkingLevel)
import Lavoisier.Protocol.Provider (Capabilities)

-- | What kind of coding task this is. Knob optima differ per archetype.
data Archetype
    = -- | A localized edit within one file.
      SingleFileEdit
    | -- | A structural change spanning multiple files.
      Refactor
    | -- | A symbol rename across the codebase.
      Rename
    | -- | Net-new functionality.
      Feature
    | -- | Anything not fitting the above.
      Other
    deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)

instance ToJSON Archetype

instance FromJSON Archetype

-- | Coarse model capability\/cost tier, used for routing and for keying tuner profiles.
data ModelTier
    = -- | Cheap\/fast: routing, classification, summaries (e.g. Haiku).
      Fast
    | -- | Mid tier for ordinary turns.
      Balanced
    | -- | Expensive\/deep reasoning (e.g. Opus).
      Deep
    deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)

instance ToJSON ModelTier

instance FromJSON ModelTier

-- | Repository shape that conditions knob selection.
data RepoProfile = RepoProfile
    { fileCount ∷ Word32
    , totalBytes ∷ Word64
    , primaryLanguage ∷ Text
    }
    deriving stock (Eq, Generic, Show)

instance ToJSON RepoProfile

instance FromJSON RepoProfile

-- | The empty repo profile (Rust @RepoProfile::default()@).
defaultRepoProfile ∷ RepoProfile
defaultRepoProfile = RepoProfile 0 0 ""

{- | The context a tuner conditions on. Caching state is a major confounder and is carried
explicitly so profiles can condition on it. Runtime-only (not serialised).
-}
data TaskContext = TaskContext
    { tcArchetype ∷ Archetype
    -- ^ The classified task archetype.
    , tcRepo ∷ RepoProfile
    -- ^ Shape of the repository the task runs against.
    , tcCaps ∷ Capabilities
    -- ^ The provider's advertised capabilities (caching state is a major confounder).
    , tcModel ∷ ModelTier
    -- ^ The coarse capability\/cost tier of the model.
    , tcModelId ∷ Text
    {- ^ The concrete model id, keyed alongside the coarse tier so a model upgrade starts a fresh
    profile rather than polluting the old one. Empty when unknown.
    -}
    , tcRepoId ∷ Text
    -- ^ Stable identity of the repository (the repo root path). Empty when there is no repo context.
    }

{- | The efficiency dials tuned per context. 'defaultKnobs' is the static baseline, which is also the
floor ATO may never regress below.
-}
data Knobs = Knobs
    { skeletonRadius ∷ Word8Knob
    -- ^ Include full bodies for symbols within @N@ dependency hops of the edit target.
    , truncateBytes ∷ Int
    -- ^ Truncate tool results larger than this many bytes (head\/tail + summary).
    , compactAfter ∷ Int
    -- ^ Compact conversation history once it exceeds this many tokens.
    , batchWidth ∷ Word8Knob
    -- ^ Number of file reads\/edits to batch into a single round-trip.
    , knobThinking ∷ Maybe ThinkingLevel
    {- ^ Extended-thinking effort to request. 'Nothing' ⇒ the agent's per-archetype default applies;
    ATO tunes this like any other dial.
    -}
    }
    deriving stock (Eq, Generic, Ord, Show)

instance ToJSON Knobs

instance FromJSON Knobs

{- | Small non-negative dials (skeleton radius, batch width). @Int@ for arithmetic ease; values stay
on their small grids.
-}
type Word8Knob = Int

{- | The static baseline (Rust @Knobs::default()@): radius 1, 8 KiB truncate, 24k compaction, batch 4,
default thinking.
-}
defaultKnobs ∷ Knobs
defaultKnobs = Knobs 1 8192 24000 4 Nothing

{- | The realised result of a completed task. 'otTotalTokens' is the optimisation objective;
'otSuccess' is the non-negotiable constraint.
-}
data Outcome = Outcome
    { otTotalTokens ∷ Word64
    {- ^ The __cost-weighted__ task total across ALL round-trips (fresh-input-token-equivalent units)
    — the metric ATO minimises.
    -}
    , otRoundTrips ∷ Word32
    -- ^ Round-trip count (diagnostic).
    , otCacheHitRate ∷ Double
    -- ^ Cache-hit rate over the task (diagnostic).
    , otSuccess ∷ Bool
    -- ^ The constraint: compile\/tests pass, diff accepted, no correction turn needed.
    , otMaxToolResultBytes ∷ Maybe Int
    {- ^ Largest __untruncated__ tool-result size (bytes) seen, when known. Enables the learner's
    safe counterfactual crediting of cheaper truncate values. 'Nothing' = not tracked.
    -}
    }
    deriving stock (Eq, Generic, Show)

instance ToJSON Outcome

instance FromJSON Outcome

-- | The success-by-default empty outcome (Rust @Outcome::default()@).
defaultOutcome ∷ Outcome
defaultOutcome = Outcome 0 0 0.0 True Nothing

{- | Picks knob settings per task and learns from realised outcomes. A record of functions (the Rust
@dyn Tuner@). Pure bookkeeping; negligible tokens\/compute.
-}
data Tuner = Tuner
    { tunerSelect ∷ TaskContext → IO Knobs
    -- ^ Choose knobs for a task (exploit + bounded explore); never below the baseline.
    , tunerObserve ∷ TaskContext → Knobs → Outcome → IO ()
    -- ^ Update profiles from the realised outcome of a completed task.
    }

{- | The default tuner: always returns 'defaultKnobs' and ignores observations. Ships by default; the
@Lavoisier.Tune@ learner swaps in without touching the agent.
-}
noopTuner ∷ Tuner
noopTuner =
    Tuner
        { tunerSelect = \_ → pure defaultKnobs
        , tunerObserve = \_ _ _ → pure ()
        }
