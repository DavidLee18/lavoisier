//! The TUI's tool-approval gate: a [`ToolGate`] that bridges the agent's synchronous "may I run this
//! tool?" question to the render loop, which asks the user interactively.
//!
//! Policy mirrors Claude Code's default: **read-only tools run unattended**; anything that mutates
//! the workspace or shells out (and any unrecognised tool — safe default) **asks first**. A per-tool
//! "always allow" set, populated when the user picks *always*, suppresses repeat prompts within the
//! session.

use std::collections::HashSet;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;

use async_trait::async_trait;
use lvz_protocol::{ToolDecision, ToolGate};
use serde_json::Value;
use tokio::sync::{mpsc, oneshot};

/// How the user (via the render loop) answers a prompt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PermitReply {
    /// Run it this once.
    AllowOnce,
    /// Run it, and stop asking for this tool for the rest of the session.
    AllowAlways,
    /// Refuse; the model is told and can adapt.
    Deny,
}

/// A prompt sent from the gate (agent side) to the render loop (UI side), carrying a one-shot channel
/// for the answer.
pub struct PermitRequest {
    /// The tool being called.
    pub name: String,
    /// Its arguments, pretty-printed for display (already truncated).
    pub args: String,
    /// Where the render loop sends the user's decision.
    pub reply: oneshot::Sender<PermitReply>,
}

/// A [`ToolGate`] that asks the render loop for approval on mutating calls and remembers
/// "always allow" choices.
pub struct ChannelGate {
    tx: mpsc::Sender<PermitRequest>,
    always: StdMutex<HashSet<String>>,
}

impl ChannelGate {
    /// Build a gate and the receiver the render loop drains. Inject the gate into the agent with
    /// [`Agent::with_tool_gate`](https://docs.rs/lvz-agent) and hand the receiver to the TUI.
    pub fn new() -> (Arc<ChannelGate>, mpsc::Receiver<PermitRequest>) {
        let (tx, rx) = mpsc::channel(8);
        (
            Arc::new(ChannelGate {
                tx,
                always: StdMutex::new(HashSet::new()),
            }),
            rx,
        )
    }
}

#[async_trait]
impl ToolGate for ChannelGate {
    async fn review(&self, name: &str, args: &Value) -> ToolDecision {
        // Read-only tools, and anything the user already said "always" to, run without a prompt.
        if is_read_only(name)
            || self
                .always
                .lock()
                .expect("gate always-set poisoned")
                .contains(name)
        {
            return ToolDecision::Allow;
        }
        let (reply_tx, reply_rx) = oneshot::channel();
        let req = PermitRequest {
            name: name.to_string(),
            args: preview(args),
            reply: reply_tx,
        };
        // If the UI is gone, fail safe: deny rather than silently run.
        if self.tx.send(req).await.is_err() {
            return ToolDecision::Deny("approval channel closed".into());
        }
        match reply_rx.await {
            Ok(PermitReply::AllowOnce) => ToolDecision::Allow,
            Ok(PermitReply::AllowAlways) => {
                self.always
                    .lock()
                    .expect("gate always-set poisoned")
                    .insert(name.to_string());
                ToolDecision::Allow
            }
            Ok(PermitReply::Deny) | Err(_) => ToolDecision::Deny("declined by user".into()),
        }
    }
}

/// Whether a tool is read-only and so runs unattended (Claude-Code default). Everything else —
/// edits, shells, and any unrecognised/namespaced (MCP) tool — asks first.
pub(crate) fn is_read_only(name: &str) -> bool {
    const PREFIXES: &[&str] = &[
        "read", "list", "find", "grep", "search", "outline", "view", "cat",
    ];
    PREFIXES.iter().any(|p| name.starts_with(p))
}

/// A compact, single-block preview of a call's arguments for the prompt (pretty JSON, capped).
fn preview(args: &Value) -> String {
    let s = serde_json::to_string_pretty(args).unwrap_or_else(|_| args.to_string());
    if s.len() > 400 {
        format!("{}…", &s[..400])
    } else {
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_only_tools_are_auto_allowed_others_ask() {
        assert!(is_read_only("read_file"));
        assert!(is_read_only("find_references"));
        assert!(is_read_only("grep"));
        assert!(!is_read_only("write_file"));
        assert!(!is_read_only("edit_files"));
        assert!(!is_read_only("shell"));
        assert!(!is_read_only("fs_delete")); // namespaced/MCP → ask
    }

    #[tokio::test]
    async fn read_only_call_needs_no_prompt() {
        let (gate, mut rx) = ChannelGate::new();
        // No one is draining `rx`; a read-only tool must still resolve immediately (no prompt sent).
        let d = gate
            .review("read_file", &serde_json::json!({"path": "a"}))
            .await;
        assert_eq!(d, ToolDecision::Allow);
        assert!(rx.try_recv().is_err(), "no prompt should have been sent");
    }

    #[tokio::test]
    async fn mutating_call_prompts_and_always_is_remembered() {
        let (gate, mut rx) = ChannelGate::new();
        // Drive the "UI": approve-always the first prompt.
        let g = gate.clone();
        let h = tokio::spawn(async move {
            g.review("write_file", &serde_json::json!({"path": "a"}))
                .await
        });
        let req = rx.recv().await.expect("a prompt");
        assert_eq!(req.name, "write_file");
        req.reply.send(PermitReply::AllowAlways).unwrap();
        assert_eq!(h.await.unwrap(), ToolDecision::Allow);
        // The second call is now auto-allowed with no prompt.
        let d = gate
            .review("write_file", &serde_json::json!({"path": "b"}))
            .await;
        assert_eq!(d, ToolDecision::Allow);
        assert!(rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn a_denied_call_is_reported() {
        let (gate, mut rx) = ChannelGate::new();
        let g = gate.clone();
        let h = tokio::spawn(async move { g.review("shell", &serde_json::json!({})).await });
        let req = rx.recv().await.unwrap();
        req.reply.send(PermitReply::Deny).unwrap();
        assert!(matches!(h.await.unwrap(), ToolDecision::Deny(_)));
    }
}
