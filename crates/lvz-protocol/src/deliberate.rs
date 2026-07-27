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
use crate::message::ToolDef;

/// The executor's context, handed to the council so it deliberates **as the agent** rather than as
/// a generic, tool-less assistant.
///
/// Without this a council reasons in a vacuum: it doesn't know the agent's persona/identity, and it
/// assumes it has no tools — so it can wrongly conclude a task is impossible and synthesise a
/// *refusal*, which then seeds (and dooms) the executor even though the executor holds the tools.
/// Supplying the executor's system prompt and this turn's advertised tools closes that gap. All
/// fields are borrowed for the duration of the [`deliberate_with_context`](Deliberator::deliberate_with_context)
/// call.
#[derive(Clone, Copy)]
pub struct DeliberationContext<'a> {
    /// The executor's full system prompt (the persona layered above the operating instructions), so
    /// the council shares the agent's identity, priorities, and constraints.
    pub system: &'a str,
    /// The tools advertised to the executor **this turn** (already filtered by any per-turn
    /// permission allowlist), so the council plans with the real capabilities instead of assuming
    /// it has none.
    pub tools: &'a [ToolDef],
    /// Optional **progress sink**: a callback the council may invoke with a short human-readable
    /// phase notice (e.g. `"council convened — 2 debaters drafting…"`, `"judge synthesising…"`).
    /// The agent wires this to the turn's [`Event::Notice`](crate::Event::Notice) stream so a slow
    /// deliberation isn't dead air on the frontend. `None` ⇒ the council stays silent (the default).
    pub progress: Option<&'a (dyn Fn(&str) + Send + Sync)>,
}

impl DeliberationContext<'_> {
    /// A context with no system prompt, no tools, and no progress sink — the council reasons with no
    /// extra grounding. This is what the default [`Deliberator::deliberate_with_context`] falls back
    /// to.
    pub const EMPTY: DeliberationContext<'static> = DeliberationContext {
        system: "",
        tools: &[],
        progress: None,
    };

    /// Emit a progress `notice` through the [`progress`](Self::progress) sink, if one is set.
    pub fn notify(&self, notice: &str) {
        if let Some(sink) = self.progress {
            sink(notice);
        }
    }
}

impl std::fmt::Debug for DeliberationContext<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // The `progress` callback isn't `Debug`; show the data fields and whether a sink is present.
        f.debug_struct("DeliberationContext")
            .field("system", &self.system)
            .field("tools", &self.tools)
            .field("progress", &self.progress.is_some())
            .finish()
    }
}

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
    ///
    /// This is the bare form. The agent actually calls
    /// [`deliberate_with_context`](Self::deliberate_with_context), which additionally hands the
    /// council the executor's [`DeliberationContext`] (system prompt + this turn's tools). Keep
    /// implementing this method — it stays the required entry point and the default target of the
    /// context-aware one — but implementors that can use the context (like `lvz-legion`'s panel)
    /// should override [`deliberate_with_context`](Self::deliberate_with_context) with the richer
    /// logic and let this delegate to it with [`DeliberationContext::EMPTY`].
    async fn deliberate(&self, task: &str) -> Result<Deliberation, DeliberateError>;

    /// Deliberate `task` with the executor's [`DeliberationContext`] (its system prompt and the
    /// tools it may call this turn).
    ///
    /// The default implementation **ignores** the context and delegates to
    /// [`deliberate`](Self::deliberate), so pre-existing implementors keep working unchanged. A
    /// council that grounds its debate in the agent's persona and real capabilities (so it plans to
    /// *use* the tools instead of concluding the task is impossible) overrides this. Added as a
    /// backward-compatible extension.
    async fn deliberate_with_context(
        &self,
        task: &str,
        _ctx: &DeliberationContext<'_>,
    ) -> Result<Deliberation, DeliberateError> {
        self.deliberate(task).await
    }
}
