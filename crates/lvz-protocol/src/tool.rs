//! The [`Tool`] contract. Built-in tools (filesystem, shell, browser) live in `lvz-tools`;
//! the agent dispatches calls through this trait without knowing their concrete types
//! (§5.4).

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

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

    /// [`invoke`](Tool::invoke), and push progress lines while the work runs.
    ///
    /// The default drops `logs` and calls `invoke`, so existing tools are unchanged. A tool
    /// that can see its work as it happens (a build's compiler output) overrides this and sends
    /// one line at a time. The agent posts each line and also keeps them for the model.
    async fn invoke_reporting(
        &self,
        args: serde_json::Value,
        logs: tokio::sync::mpsc::UnboundedSender<String>,
    ) -> Result<ToolOutput, ToolError> {
        drop(logs);
        self.invoke(args).await
    }
}

/// The successful result of a tool invocation. `is_error` lets a tool report a recoverable
/// failure to the model (bad path, command exited non-zero) without aborting the turn.
#[derive(Debug, Clone)]
pub struct ToolOutput {
    /// The tool's output, rendered for the model.
    pub content: String,
    /// Whether this result represents a recoverable, model-visible error.
    pub is_error: bool,
    /// Whether this invocation **actually mutated the workspace** (an edit tool that wrote a real
    /// change to a file). `false` for read-only tools and for edit tools that no-op'd — e.g. an
    /// anchored edit whose anchors didn't match, so nothing was written. The agent keys its
    /// convergence levers on this, not merely on which tool was called, so a failed/empty edit
    /// can't be mistaken for progress (§6.6 convergence). Default `false`.
    pub changed: bool,
    /// Set when the tool **accepted** work that is still running, rather than finishing it.
    ///
    /// A long-running action (waking a machine, a remote build) cannot block: it would hold a
    /// scheduler slot for minutes, collide with a retry window shorter than its own runtime, and
    /// make an interactive caller wait. So it returns immediately — but then `Ok` means *dispatched*,
    /// not *succeeded*, and anything reporting on it asserts something it does not know.
    ///
    /// `pending` closes that gap: the caller polls [`Pending::poll_with`] until a terminal result
    /// arrives, and reports THAT. `None` (the default) is an ordinary terminal result, so every
    /// existing tool is unaffected.
    ///
    /// A **typed field, not a JSON convention** in `content`: a tool that mis-spelled a magic key
    /// would silently be treated as terminal, which is the failure this exists to remove.
    pub pending: Option<Pending>,
    /// Images the model should see along with [`content`](ToolOutput::content). Empty for every
    /// tool that returns text only. The bytes are base64, not a file path: a path would depend on
    /// a later `read_file`, and that read is text-only.
    pub images: Vec<ToolImage>,
}

/// One image attached to a [`ToolOutput`]. `data` is the base64 payload, never a sliced prefix.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolImage {
    /// MIME type, e.g. `image/jpeg`.
    pub media_type: String,
    /// Base64-encoded bytes. Adapters send this whole string or omit the image.
    pub data: String,
}

/// A handle to work a tool started but has not finished.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pending {
    /// Opaque token identifying this run, passed back to the polling tool as `{"handle": …}`.
    pub handle: String,
    /// Name of the tool that reports the terminal outcome for `handle`.
    pub poll_with: String,
    /// The tool's own estimate of how long the work takes. Used to derive a polling deadline, so a
    /// job that never completes is reported as a timeout rather than holding a slot forever.
    /// `None` falls back to the caller's configured default.
    pub estimated_seconds: Option<u64>,
}

impl ToolOutput {
    /// A successful result (no workspace mutation by default; edit tools call [`ToolOutput::changed`]).
    pub fn ok(content: impl Into<String>) -> Self {
        Self {
            content: content.into(),
            is_error: false,
            changed: false,
            pending: None,
            images: Vec::new(),
        }
    }

    /// Attach an image. `data` is base64. The text in `content` stays the tool result.
    pub fn with_image(mut self, media_type: impl Into<String>, data: impl Into<String>) -> Self {
        self.images.push(ToolImage {
            media_type: media_type.into(),
            data: data.into(),
        });
        self
    }

    /// Report that the work was **accepted and is still running**; the caller must poll
    /// `poll_with` with `handle` for the terminal outcome.
    pub fn pending(
        content: impl Into<String>,
        handle: impl Into<String>,
        poll_with: impl Into<String>,
        estimated_seconds: Option<u64>,
    ) -> Self {
        Self {
            content: content.into(),
            is_error: false,
            changed: false,
            pending: Some(Pending {
                handle: handle.into(),
                poll_with: poll_with.into(),
                estimated_seconds,
            }),
            images: Vec::new(),
        }
    }

    /// A model-visible error result (turn continues; the model sees the message).
    pub fn error(content: impl Into<String>) -> Self {
        Self {
            content: content.into(),
            is_error: true,
            changed: false,
            // An error is terminal by construction: there is nothing to poll for.
            pending: None,
            images: Vec::new(),
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
