//! The [`Provider`] contract: stream a chat turn as normalised [`Event`]s, regardless of
//! wire protocol, and declare what optional features the transport supports.

use async_trait::async_trait;
use futures::stream::BoxStream;

use crate::event::Event;
use crate::message::ChatRequest;

/// A model backend. Implemented once per transport (`lvz-anthropic`, `lvz-xai`,
/// `lvz-claude-cli`). The agent core depends only on this trait, never on a concrete
/// transport (`RECIPE.md` §5.1).
#[async_trait]
pub trait Provider: Send + Sync {
    /// Stream a chat turn as normalised events. The returned stream owns its state so it
    /// can outlive the borrow of `self`.
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError>;

    /// Declare optional features so the agent can negotiate / degrade gracefully.
    fn capabilities(&self) -> Capabilities;
}

/// Optional features a provider may support. The agent conditions behaviour on these —
/// e.g. it only attaches `cache_control` when [`prompt_caching`](Capabilities::prompt_caching)
/// is true (`RECIPE.md` §5.3, §6.2).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Capabilities {
    /// Ephemeral prompt caching on stable prefixes. Anthropic: true; claude-cli: false.
    pub prompt_caching: bool,
    /// Extended-thinking blocks. Anthropic: true.
    pub extended_thinking: bool,
    /// Multiple tool calls within a single turn.
    pub parallel_tool_use: bool,
    /// Provider-executed (server-side) tools. xAI gRPC v6: true.
    pub server_side_tools: bool,
    /// Image/document (multimodal) inputs. Anthropic / Google / xAI vision models: true.
    pub vision: bool,
}

/// Errors surfaced by a provider. Adapters map their transport/API failures onto these.
#[derive(Debug, thiserror::Error)]
pub enum ProviderError {
    /// Network / transport-level failure (connection, TLS, timeout).
    #[error("transport error: {0}")]
    Transport(String),

    /// The API returned a non-success status with a message.
    #[error("api error {status}: {message}")]
    Api { status: u16, message: String },

    /// A response (or SSE/gRPC frame) could not be decoded into the expected shape.
    #[error("decode error: {0}")]
    Decode(String),

    /// The caller cancelled mid-stream. Tokens consumed before cancellation may still bill.
    #[error("request cancelled")]
    Cancelled,

    /// The request used a feature this provider's [`Capabilities`] does not advertise.
    #[error("unsupported capability: {0}")]
    Unsupported(String),

    /// Configuration problem (missing API key, bad base URL).
    #[error("configuration error: {0}")]
    Config(String),
}
