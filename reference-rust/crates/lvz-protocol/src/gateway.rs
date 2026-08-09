//! The [`Gateway`] contract [Hermes tier]. A gateway is a frontend/channel (CLI, HTTP,
//! Matrix) that drives the shared agent via an [`AgentHandle`](crate::AgentHandle).
//! Adding a channel means one new `lvz-gw-*` crate; the agent core stays unaware of it
//! (§5.5, §7).

use std::sync::Arc;

use async_trait::async_trait;

use crate::agent::AgentHandle;

/// A frontend that runs an event loop, translating inbound requests into agent turns and
/// rendering outbound [`Event`](crate::Event)s back to its channel.
#[async_trait]
pub trait Gateway: Send + Sync {
    /// Identifier for logs/telemetry (e.g. `cli`, `http`, `matrix`).
    fn name(&self) -> &str;

    /// Run the gateway's serve loop until shutdown, dispatching to the shared `agent`.
    async fn serve(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError>;
}

/// Errors surfaced by a gateway's serve loop.
#[derive(Debug, thiserror::Error)]
pub enum GatewayError {
    /// Failed to bind/listen/connect the channel.
    #[error("bind error: {0}")]
    Bind(String),

    /// Channel-level I/O failure during serving.
    #[error("io error: {0}")]
    Io(String),

    /// Inbound payload could not be parsed into a turn.
    #[error("protocol error: {0}")]
    Protocol(String),
}
