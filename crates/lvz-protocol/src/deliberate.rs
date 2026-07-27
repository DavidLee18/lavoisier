//! The [`Deliberator`] contract: a multi-model **council** ("legion") that argues out a task
//! before the agent acts.
//!
//! This mirrors the [`Tuner`](crate::Tuner) contract's shape: the agent holds an
//! `Arc<dyn Deliberator>` and, when one is configured, runs a **pre-pass** that asks the council
//! to deliberate the task and folds the agreed plan into the transcript before the tool-using
//! loop begins (deliberate-then-act). The default is *absent* (no deliberator), so the agent runs
//! identically whether or not `lvz-legion` is present; enabling a council swaps in the
//! implementation with no other change.
//!
//! The contract is deliberately narrow — one `task` string in, one agreed [`Deliberation`] out —
//! so this keystone crate stays free of any knowledge of *how* the council debates (how many
//! debaters, which providers, how many rounds, who judges). That policy lives entirely in the
//! implementing crate.

use async_trait::async_trait;

use crate::event::Usage;

/// The agreed outcome of a council deliberation: the synthesised plan-of-action plus the total
/// token [`Usage`] the debate cost.
///
/// The `plan` is injected into the executor's transcript as the assistant's opening move (like the
/// advisor pre-pass), so it seeds — but does not constrain — the tool-using loop that follows. The
/// `usage` is summed across *every* model call the council made (drafts, critiques, and the judge)
/// so the debate's cost flows into the agent's cost-weighted budget accounting.
#[derive(Debug, Clone, Default)]
pub struct Deliberation {
    /// The judge's synthesised plan-of-action and key reply points.
    pub plan: String,
    /// Total tokens the whole deliberation consumed, summed across all debaters and the judge.
    pub usage: Usage,
}

/// Why a deliberation failed. The agent treats every one as **non-fatal** — a failed council is
/// logged and the turn proceeds without a seeded plan (best-effort, exactly like the advisor
/// pre-pass) — so these exist for diagnostics, not control flow.
#[derive(Debug, thiserror::Error)]
pub enum DeliberateError {
    /// Every debater's call errored (or produced empty output), so there was nothing to judge.
    #[error("no debater produced a usable position")]
    NoPositions,
    /// The judge call failed or returned an empty synthesis.
    #[error("judge synthesis failed: {0}")]
    Judge(String),
    /// Any other deliberation failure.
    #[error("deliberation error: {0}")]
    Other(String),
}

/// A multi-model council that argues out a task and returns one agreed plan.
///
/// Implemented by `lvz-legion`'s `Panel`. The agent depends only on this trait, never on the
/// concrete panel (the same inversion as [`Provider`](crate::Provider) / [`Tuner`](crate::Tuner)):
/// the CLI is the one place that builds the concrete council and hands it in as
/// `Arc<dyn Deliberator>`.
#[async_trait]
pub trait Deliberator: Send + Sync {
    /// Run the council's argument over `task` and return the agreed plan plus the tokens it cost.
    async fn deliberate(&self, task: &str) -> Result<Deliberation, DeliberateError>;
}
