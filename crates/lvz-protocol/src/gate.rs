//! The [`ToolGate`] contract: an optional per-call **approval hook** the agent consults before it
//! executes a tool.
//!
//! Where [`TurnRequest::allowed_tools`](crate::TurnRequest) is a *static* per-turn allowlist decided
//! up front, a `ToolGate` is a *dynamic* check made at the moment of each call — it can inspect the
//! concrete arguments and answer interactively. That is what lets an interactive frontend (the TUI)
//! implement Claude-Code-style "allow this edit?" prompts: reads run unattended, mutating calls ask.
//!
//! It is held on the agent as an `Option<Arc<dyn ToolGate>>` (the `Deliberator`/tuner injection
//! pattern — *not* in the `Debug`-derived config). `None` ⇒ every tool runs, byte-identical to a
//! build with no gate, so this is fully backward-compatible.

use async_trait::async_trait;
use serde_json::Value;

/// The verdict a [`ToolGate`] returns for one prospective tool call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ToolDecision {
    /// Run the tool.
    Allow,
    /// Do not run it; the carried reason is fed back to the model as the tool result (`is_error`),
    /// so the turn continues and the model can adapt rather than the turn aborting.
    Deny(String),
}

/// A hook the agent consults immediately before invoking each tool. Implementors decide — possibly
/// interactively — whether the call may proceed.
#[async_trait]
pub trait ToolGate: Send + Sync {
    /// Review a prospective call to `name` with its fully-assembled `args`. Returning
    /// [`ToolDecision::Deny`] blocks execution and surfaces the reason to the model as an error
    /// result (never aborting the turn).
    async fn review(&self, name: &str, args: &Value) -> ToolDecision;
}
