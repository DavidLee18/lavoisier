//! The gateway-facing facade over `lvz-agent`. A [`Gateway`](crate::Gateway) submits a turn
//! and consumes the resulting [`Event`] stream; it never touches a [`Provider`](crate::Provider)
//! or the agent's internals. The CLI, HTTP, Matrix, and Discord gateways all drive the same
//! agent through this handle (`RECIPE.md` §5.5).

use async_trait::async_trait;
use futures::stream::BoxStream;

use crate::event::Event;

/// One inbound request to the agent: which session it belongs to and the user's input.
#[derive(Debug, Clone)]
pub struct TurnRequest {
    /// Conversation/session identifier for multi-session isolation (Hermes tier).
    pub session: String,
    /// The user's message for this turn.
    pub input: String,
}

impl TurnRequest {
    pub fn new(session: impl Into<String>, input: impl Into<String>) -> Self {
        Self {
            session: session.into(),
            input: input.into(),
        }
    }
}

/// The shared agent as seen by gateways: submit a turn, receive a normalised event stream.
/// Implemented by `lvz-agent`; depended on by every `lvz-gw-*` crate.
#[async_trait]
pub trait AgentHandle: Send + Sync {
    /// Run one turn to completion, streaming events as they are produced.
    async fn submit(
        &self,
        turn: TurnRequest,
    ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError>;
}

/// Errors surfaced by the agent to a gateway.
#[derive(Debug, thiserror::Error)]
pub enum AgentError {
    /// A downstream provider failed.
    #[error("provider error: {0}")]
    Provider(String),

    /// A tool failed in a way the agent could not recover from.
    #[error("tool error: {0}")]
    Tool(String),

    /// The turn exceeded its configured token budget (`RECIPE.md` §6.4).
    #[error("token budget exceeded")]
    BudgetExceeded,

    /// No such session.
    #[error("unknown session: {0}")]
    UnknownSession(String),
}
