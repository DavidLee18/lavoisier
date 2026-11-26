//! Trusted turn identity and where a call came from.
//!
//! A gateway that has already authenticated the caller sets [`TurnContext`] on the
//! [`crate::TurnRequest`]. The agent installs it as a task-local for the turn task, so a tool
//! can read [`turn_context`] and [`origin`] without a new argument on [`crate::Tool::invoke`].
//! Spawned tasks do not inherit the local; the agent re-installs it on the turn task itself.

use std::future::Future;

use serde::{Deserialize, Serialize};

/// Identity of the caller, copied from an authenticated gateway event.
///
/// Field names match the HTTP `context` object. Unknown JSON fields are ignored by callers
/// that use `#[serde(default)]` on the parent. Every field defaults so a partial object still
/// decodes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct TurnContext {
    /// Matrix user id (`@user:server`) or another gateway's stable sender id.
    #[serde(default)]
    pub sender: String,
    /// Event id of the message that started the turn.
    #[serde(default)]
    pub event_id: String,
    /// Room (or channel) the message was sent in.
    #[serde(default)]
    pub room: String,
    /// Per-room monotonic counter assigned by the gateway in sync order.
    ///
    /// This is the authoritative "later". Client clocks are not consulted.
    #[serde(default)]
    pub seq: u64,
    /// Gateway timestamp of the event, unix milliseconds. Informational.
    #[serde(default)]
    pub origin_ts_ms: u64,
    /// The plaintext the user typed, before any model rewrite.
    ///
    /// Command hooks (a cancel phrase) read this and not the model-visible paraphrase.
    #[serde(default)]
    pub raw_input: String,
}

/// Why a tool call or turn is running.
///
/// Never parsed out of user text. A gateway or the scheduler sets it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Origin {
    /// A person sent a message. The fields are the same identity as [`TurnContext`].
    Chat {
        /// Sender MXID.
        sender: String,
        /// Room id.
        room: String,
        /// Inbound event id.
        event_id: String,
        /// Gateway sequence of that event.
        seq: u64,
    },
    /// The scheduler fired this call. `job` is the schedule id.
    Schedule {
        /// Schedule job id.
        job: String,
    },
    /// A continuation turn posted when a detached job finished.
    Job {
        /// Session the job belonged to.
        id: String,
    },
    /// A local CLI turn with no remote sender.
    Cli,
}

tokio::task_local! {
    static TURN_CONTEXT: TurnContext;
    static TURN_ORIGIN: Origin;
}

/// The context installed for this task, if the turn had one.
pub fn turn_context() -> Option<TurnContext> {
    TURN_CONTEXT.try_with(|ctx| ctx.clone()).ok()
}

/// The origin installed for this task. Tasks outside a turn read [`Origin::Cli`].
pub fn origin() -> Origin {
    TURN_ORIGIN
        .try_with(|origin| origin.clone())
        .unwrap_or(Origin::Cli)
}

/// Pick an origin from an explicit value, otherwise from `context`, otherwise [`Origin::Cli`].
pub fn resolve_origin(context: Option<&TurnContext>, explicit: Option<Origin>) -> Origin {
    if let Some(origin) = explicit {
        return origin;
    }
    if let Some(ctx) = context {
        return Origin::Chat {
            sender: ctx.sender.clone(),
            room: ctx.room.clone(),
            event_id: ctx.event_id.clone(),
            seq: ctx.seq,
        };
    }
    Origin::Cli
}

/// Run `fut` on this task with `origin` and, when present, `context` installed.
pub async fn enter_turn<F>(context: Option<TurnContext>, origin: Origin, fut: F) -> F::Output
where
    F: Future,
{
    match context {
        Some(ctx) => {
            TURN_CONTEXT
                .scope(ctx, TURN_ORIGIN.scope(origin, fut))
                .await
        }
        None => TURN_ORIGIN.scope(origin, fut).await,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn context_defaults_and_ignores_nothing_required() {
        let ctx: TurnContext = serde_json::from_str("{}").expect("defaults");
        assert_eq!(ctx.sender, "");
        assert_eq!(ctx.seq, 0);
        let raw = r#"{"sender":"@a:hs","event_id":"$e","room":"!r:hs","seq":4,"origin_ts_ms":9,"raw_input":"hi"}"#;
        let ctx: TurnContext = serde_json::from_str(raw).expect("full");
        assert_eq!(ctx.sender, "@a:hs");
        assert_eq!(ctx.seq, 4);
        assert_eq!(ctx.raw_input, "hi");
    }

    #[test]
    fn resolve_prefers_explicit_then_context_then_cli() {
        let ctx = TurnContext {
            sender: "@a:hs".into(),
            room: "!r:hs".into(),
            event_id: "$e".into(),
            seq: 2,
            ..TurnContext::default()
        };
        assert!(matches!(
            resolve_origin(Some(&ctx), None),
            Origin::Chat { seq: 2, .. }
        ));
        assert!(matches!(
            resolve_origin(Some(&ctx), Some(Origin::Schedule { job: "disk".into() })),
            Origin::Schedule { .. }
        ));
        assert_eq!(resolve_origin(None, None), Origin::Cli);
    }

    #[tokio::test]
    async fn task_local_is_visible_inside_the_scope_only() {
        assert!(turn_context().is_none());
        assert_eq!(origin(), Origin::Cli);
        let ctx = TurnContext {
            sender: "@a:hs".into(),
            room: "!r:hs".into(),
            seq: 7,
            ..TurnContext::default()
        };
        enter_turn(Some(ctx), Origin::Cli, async {
            // Explicit origin wins over the derived chat origin.
            assert_eq!(origin(), Origin::Cli);
            assert_eq!(turn_context().expect("installed").seq, 7);
        })
        .await;
        assert!(turn_context().is_none());
    }
}
