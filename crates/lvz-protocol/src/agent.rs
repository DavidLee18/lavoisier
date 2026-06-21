//! The gateway-facing facade over `lvz-agent`. A [`Gateway`](crate::Gateway) submits a turn
//! and consumes the resulting [`Event`] stream; it never touches a [`Provider`](crate::Provider)
//! or the agent's internals. The CLI, HTTP, and Matrix gateways all drive the same
//! agent through this handle (§5.5).

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
    /// Optional per-turn tool allowlist. `None` ⇒ the agent's full tool set (the default).
    /// `Some(names)` restricts *this turn* to exactly those tools — both what's advertised to the
    /// model and what `invoke` will run. The agent core enforces it generically; a gateway computes
    /// the set from its own policy (e.g. the Matrix gateway's room/member tool permissions). An
    /// empty set means "no tools this turn".
    pub allowed_tools: Option<Vec<String>>,
}

impl TurnRequest {
    pub fn new(session: impl Into<String>, input: impl Into<String>) -> Self {
        Self {
            session: session.into(),
            input: input.into(),
            allowed_tools: None,
        }
    }

    /// Restrict this turn to the given tool names (see [`TurnRequest::allowed_tools`]).
    pub fn with_allowed_tools(mut self, tools: impl IntoIterator<Item = String>) -> Self {
        self.allowed_tools = Some(tools.into_iter().collect());
        self
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

    /// The turn exceeded its configured token budget (§6.4).
    #[error("token budget exceeded")]
    BudgetExceeded,

    /// No such session.
    #[error("unknown session: {0}")]
    UnknownSession(String),
}
