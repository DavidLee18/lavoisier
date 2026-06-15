//! The [`Tool`] contract. Built-in tools (filesystem, shell, browser) live in `lvz-tools`;
//! the agent dispatches calls through this trait without knowing their concrete types
//! (`RECIPE.md` §5.4).

use async_trait::async_trait;

/// A capability the model can invoke. Implementors expose a name, a JSON Schema for their
/// arguments, and an async `invoke`.
#[async_trait]
pub trait Tool: Send + Sync {
    /// Stable identifier the model uses to call this tool.
    fn name(&self) -> &str;

    /// Human-readable description sent to the model. Defaults to empty.
    fn description(&self) -> &str {
        ""
    }

    /// JSON Schema describing the tool's argument object.
    fn schema(&self) -> serde_json::Value;

    /// Execute the tool against parsed argument JSON.
    async fn invoke(&self, args: serde_json::Value) -> Result<ToolOutput, ToolError>;
}

/// The successful result of a tool invocation. `is_error` lets a tool report a recoverable
/// failure to the model (bad path, command exited non-zero) without aborting the turn.
#[derive(Debug, Clone)]
pub struct ToolOutput {
    pub content: String,
    pub is_error: bool,
    /// Whether this invocation **actually mutated the workspace** (an edit tool that wrote a real
    /// change to a file). `false` for read-only tools and for edit tools that no-op'd — e.g. an
    /// anchored edit whose anchors didn't match, so nothing was written. The agent keys its
    /// convergence levers on this, not merely on which tool was called, so a failed/empty edit
    /// can't be mistaken for progress (`RECIPE.md` §6.6 convergence). Default `false`.
    pub changed: bool,
}

impl ToolOutput {
    /// A successful result (no workspace mutation by default; edit tools call [`changed`]).
    pub fn ok(content: impl Into<String>) -> Self {
        Self {
            content: content.into(),
            is_error: false,
            changed: false,
        }
    }

    /// A model-visible error result (turn continues; the model sees the message).
    pub fn error(content: impl Into<String>) -> Self {
        Self {
            content: content.into(),
            is_error: true,
            changed: false,
        }
    }

    /// Mark whether this invocation actually changed a file (builder). See [`ToolOutput::changed`].
    pub fn changed(mut self, changed: bool) -> Self {
        self.changed = changed;
        self
    }
}

/// A hard tool failure (the dispatcher could not run the tool at all).
#[derive(Debug, thiserror::Error)]
pub enum ToolError {
    /// No tool registered under the requested name.
    #[error("unknown tool: {0}")]
    Unknown(String),

    /// Arguments did not match the tool's schema.
    #[error("invalid arguments: {0}")]
    InvalidArgs(String),

    /// The tool ran but failed irrecoverably.
    #[error("execution failed: {0}")]
    Execution(String),
}
