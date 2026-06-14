//! `lvz-protocol` — the only stable public contract in Lavoisier.
//!
//! It defines the normalised [`Event`] stream plus the [`Provider`], [`Tool`],
//! [`Gateway`], and [`Tuner`] traits and their supporting types. It performs **no I/O**
//! and has **zero** provider- or gateway-specific knowledge: every other crate depends on
//! it, and it depends on nothing of theirs. Swapping a transport, adding a provider, or
//! adding a gateway never touches this crate (see `RECIPE.md` §3–§5).
//!
//! ```text
//!   gateways ─┐
//!   providers ┼─► lvz-protocol ◄─ lvz-agent / lvz-context / lvz-tools
//!   tuner ────┘
//! ```

mod agent;
mod batch;
mod event;
mod gateway;
mod message;
mod provider;
mod telemetry;
mod tool;
mod tune;

pub use agent::{AgentError, AgentHandle, TurnRequest};
pub use batch::{BatchItem, BatchProvider, BatchTask};
pub use event::{Event, StopReason, Usage};
pub use gateway::{Gateway, GatewayError};
pub use message::{
    BuiltinTool, ChatRequest, ContentBlock, McpServer, MediaSource, Message, OutputFormat, Role,
    ServerTool, SystemPrompt, ThinkingLevel, ToolChoice, ToolDef,
};
pub use provider::{Capabilities, Provider, ProviderError};
pub use telemetry::{TaskTelemetry, TelemetrySink};
pub use tool::{Tool, ToolError, ToolOutput};
pub use tune::{Archetype, Knobs, ModelTier, NoopTuner, Outcome, RepoProfile, TaskContext, Tuner};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chat_request_builder_roundtrips_through_serde() {
        let req = ChatRequest::new("grok-4")
            .system("You are terse.")
            .push(Message::user("hello"))
            .max_tokens(256);

        let json = serde_json::to_string(&req).expect("serialize");
        let back: ChatRequest = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back.model, "grok-4");
        assert_eq!(back.messages.len(), 1);
        assert!(matches!(back.messages[0].role, Role::User));
    }

    #[test]
    fn noop_tuner_returns_static_defaults_and_swallows_observations() {
        let tuner = NoopTuner;
        let ctx = TaskContext {
            archetype: Archetype::SingleFileEdit,
            repo: RepoProfile::default(),
            caps: Capabilities::default(),
            model: ModelTier::Balanced,
            model_id: "test-model".to_string(),
            repo_id: String::new(),
        };
        let knobs = tuner.select(&ctx);
        assert_eq!(knobs, Knobs::default());
        // observe() must never panic or mutate observable state.
        tuner.observe(&ctx, &knobs, &Outcome::default());
    }

    #[test]
    fn default_capabilities_are_conservative() {
        let caps = Capabilities::default();
        assert!(!caps.prompt_caching);
        assert!(!caps.extended_thinking);
        assert!(!caps.parallel_tool_use);
        assert!(!caps.server_side_tools);
    }
}
