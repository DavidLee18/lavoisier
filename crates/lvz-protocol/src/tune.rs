//! The [`Tuner`] contract for adaptive token optimisation (ATO, `RECIPE.md` §5.6, §6.6).
//!
//! The agent asks a tuner which [`Knobs`] to use for a given [`TaskContext`] and reports the
//! realised [`Outcome`] back. The default [`NoopTuner`] returns the static §6.5 defaults and
//! ignores observations, so the agent runs identically whether or not `lvz-tune` is present;
//! enabling ATO swaps in the learning implementation with no other change.

use serde::{Deserialize, Serialize};

use crate::message::ThinkingLevel;
use crate::provider::Capabilities;

/// What kind of coding task this is. Knob optima differ per archetype (`RECIPE.md` §6.5).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Archetype {
    SingleFileEdit,
    Refactor,
    Rename,
    Feature,
    Other,
}

/// Coarse model capability/cost tier, used for routing and for keying tuner profiles.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelTier {
    /// Cheap/fast: routing, classification, summaries (e.g. Haiku).
    Fast,
    /// Mid tier for ordinary turns.
    Balanced,
    /// Expensive/deep reasoning (e.g. Opus).
    Deep,
}

/// Repository shape that conditions knob selection.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RepoProfile {
    pub file_count: u32,
    pub total_bytes: u64,
    pub primary_language: String,
}

/// The context a tuner conditions on. Caching state is a major confounder and is carried
/// explicitly so profiles can condition on it (`RECIPE.md` §6.6).
#[derive(Debug, Clone)]
pub struct TaskContext {
    pub archetype: Archetype,
    pub repo: RepoProfile,
    pub caps: Capabilities,
    pub model: ModelTier,
    /// The concrete model id (e.g. `"claude-sonnet-4-6"`). Keyed by the learner *alongside* the
    /// coarse [`model`](Self::model) tier so a model upgrade (which shifts the knob optimum,
    /// `RECIPE.md` §6.6 non-stationarity) starts a fresh profile instead of polluting the old
    /// one. Empty string when unknown.
    pub model_id: String,
    /// Stable identity of the repository the task runs against (the agent uses the repo root
    /// path). Keyed by the learner so per-repo knob optima don't average together (`RECIPE.md`
    /// §6.6). Empty string when there's no repo context — then all tasks share one repo profile,
    /// so single-repo use sees no key fragmentation.
    pub repo_id: String,
}

/// The efficiency dials tuned per context. [`Default`] returns the static §6.5 baseline,
/// which is also the floor ATO may never regress below.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Knobs {
    /// Include full bodies for symbols within `N` dependency hops of the edit target.
    pub skeleton_radius: u8,
    /// Truncate tool results larger than this many bytes (head/tail + summary).
    pub truncate_bytes: usize,
    /// Compact conversation history once it exceeds this many tokens.
    pub compact_after: usize,
    /// Number of file reads/edits to batch into a single round-trip.
    pub batch_width: u8,
    /// Extended-thinking effort to request. `None` ⇒ the agent's per-archetype default applies
    /// (mechanical archetypes think less); ATO tunes this like any other dial. Defaulted (and
    /// `#[serde(default)]`) so older persisted tune-state files load without it.
    #[serde(default)]
    pub thinking: Option<ThinkingLevel>,
}

impl Default for Knobs {
    fn default() -> Self {
        Self {
            skeleton_radius: 1,
            truncate_bytes: 8 * 1024,
            compact_after: 24_000,
            batch_width: 4,
            thinking: None,
        }
    }
}

/// The realised result of a completed task. `total_tokens` is the optimisation objective;
/// `success` is the non-negotiable constraint (`RECIPE.md` §6.6).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Outcome {
    /// The **cost-weighted** task total across ALL round-trips (in fresh-input-token-equivalent
    /// units, [`Usage::cost`](crate::Usage::cost)) — the metric ATO minimises. Cost-weighted
    /// rather than a flat token count so caching (cheap reads, pricier writes) and output cost
    /// register in the objective; with flat [`CostWeights`](crate::CostWeights) it collapses to
    /// the raw token sum.
    pub total_tokens: u64,
    /// Round-trip count (diagnostic).
    pub round_trips: u32,
    /// Cache-hit rate over the task (diagnostic).
    pub cache_hit_rate: f32,
    /// The constraint: compile/tests pass, diff accepted, no correction turn needed.
    pub success: bool,
    /// Largest *untruncated* tool-result size (bytes) seen during the task, when known. Enables
    /// the learner's safe **counterfactual** crediting (`docs/ATO.md` §3, §10): if nothing in the
    /// task exceeded the [`truncate_bytes`](Knobs::truncate_bytes) used, then any cheaper truncate
    /// value still ≥ this size would have produced a byte-identical transcript — the same outcome
    /// at the same cost — so the learner can credit it without a live trial. `None` = not tracked.
    pub max_tool_result_bytes: Option<usize>,
}

impl Default for Outcome {
    fn default() -> Self {
        Self {
            total_tokens: 0,
            round_trips: 0,
            cache_hit_rate: 0.0,
            success: true,
            max_tool_result_bytes: None,
        }
    }
}

/// Picks knob settings per task and learns from realised outcomes. Pure bookkeeping; adds
/// negligible tokens/compute. Methods are synchronous — selection and observation are
/// in-memory profile lookups/updates.
pub trait Tuner: Send + Sync {
    /// Choose knobs for a task (exploit + bounded explore); never below the CI baseline.
    fn select(&self, ctx: &TaskContext) -> Knobs;

    /// Update profiles from the realised outcome of a completed task.
    fn observe(&self, ctx: &TaskContext, used: &Knobs, out: &Outcome);
}

/// The default tuner: always returns the static [`Knobs::default`] and ignores observations.
/// Ship this first; swap in the `lvz-tune` learner later without touching the agent.
#[derive(Debug, Clone, Copy, Default)]
pub struct NoopTuner;

impl Tuner for NoopTuner {
    fn select(&self, _ctx: &TaskContext) -> Knobs {
        Knobs::default()
    }

    fn observe(&self, _ctx: &TaskContext, _used: &Knobs, _out: &Outcome) {}
}
