//! The [`TelemetrySink`] contract: a per-task observability hook (§6.4).
//!
//! The gateway exports Prometheus `/metrics`, but a one-shot `--agent` run has no server to
//! scrape. This trait lets *any* host of the agent — the CLI, a gateway, a test — receive one
//! structured [`TaskTelemetry`] record when a task ends (on every exit: success, error, budget,
//! step-cap), so token/latency/success signals are captured on the CLI/agent path too. The
//! default is no sink, so behaviour is unchanged when none is installed.

use std::time::Duration;

use crate::event::{CostWeights, Usage};
use crate::tune::{Archetype, Knobs, ModelTier};

/// What a task cost and how it ended — emitted once per task to a [`TelemetrySink`].
#[derive(Debug, Clone)]
pub struct TaskTelemetry {
    /// The classified task archetype (§6.5).
    pub archetype: Archetype,
    /// The headline model id the task ran on.
    pub model: String,
    /// The coarse tier of [`model`](Self::model).
    pub model_tier: ModelTier,
    /// The efficiency knobs the tuner chose for this task.
    pub knobs: Knobs,
    /// Token usage summed across every round-trip (incl. compaction/advisor calls).
    pub usage: Usage,
    /// The cost weights the task's budget/ATO objective used — so a sink can report the same
    /// cost-weighted figure ([`cost`](Self::cost)) the agent optimised, not just raw tokens.
    pub cost_weights: CostWeights,
    /// Number of model round-trips the task took.
    pub round_trips: u32,
    /// Whether the task succeeded (the ATO constraint signal; see [`crate::Outcome::success`]).
    pub success: bool,
    /// Wall-clock time from task start to this exit.
    pub elapsed: Duration,
}

impl TaskTelemetry {
    /// The cost-weighted task total ([`Usage::cost`]) under [`cost_weights`](Self::cost_weights) —
    /// the figure the budget ceiling and the ATO tuner actually minimised.
    pub fn cost(&self) -> u64 {
        self.usage.cost(&self.cost_weights)
    }

    /// Fraction of input tokens served from cache this task (0 when nothing was read/cacheable).
    pub fn cache_hit_rate(&self) -> f32 {
        let cacheable = self.usage.input_tokens + self.usage.cache_read_tokens;
        if cacheable == 0 {
            0.0
        } else {
            self.usage.cache_read_tokens as f32 / cacheable as f32
        }
    }
}

/// A sink that receives one [`TaskTelemetry`] per completed task. Implementations must be cheap
/// and non-blocking (it is called on the agent's task path). `Send + Sync` for shared use.
pub trait TelemetrySink: Send + Sync {
    fn record(&self, telemetry: &TaskTelemetry);
}
