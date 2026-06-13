//! Request shape sent to a [`Provider`](crate::Provider): the model id, an optional system
//! prompt, the conversation as role-tagged content blocks, and the available tool
//! definitions. Cache markers live here so the protocol — not any one adapter — decides
//! where the stable prefix ends (`RECIPE.md` §6.2). Adapters that lack caching ignore them.

use serde::{Deserialize, Serialize};

/// Normalised extended-thinking effort, mapped per-provider by each adapter (`RECIPE.md` §8).
///
/// This is a *cost* dial: more thinking ⇒ more (priced) output tokens. The agent defaults it
/// **lower for mechanical archetypes** (renames, single-file edits) and lets the ATO tuner learn
/// it; `--thinking-budget` forces a level. Mapping per provider (each maps `Low` to its cheapest
/// meaningful setting, so a mechanical task never *raises* cost):
/// - **Anthropic**: `Off`/`Low` ⇒ no `thinking` block; `Medium` ⇒ `budget_tokens: 4096`;
///   `High` ⇒ `budget_tokens: 12000` (extended thinking stays opt-in via `Medium`/`High`).
/// - **Google**: `Off` ⇒ budget 0; `Low`/`Medium`/`High` ⇒ the matching Gemini effort.
/// - **xAI**: no request-side control (grok reasons automatically) — ignored.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ThinkingLevel {
    Off,
    Low,
    Medium,
    High,
}

/// How the model should choose among the offered tools. Each adapter maps this to its provider's
/// shape (Anthropic `tool_choice`, OpenAI/xAI `tool_choice`, Gemini `functionCallingConfig.mode`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolChoice {
    /// Model decides whether to call a tool (provider default).
    Auto,
    /// Model must call at least one tool (Anthropic `any` / OpenAI `required` / Gemini `ANY`).
    Required,
    /// Model may not call any tool.
    None,
    /// Model must call exactly this tool.
    Tool(String),
}

/// Constrain the model's output. Each adapter maps this to its structured-output surface
/// (Anthropic `output_config.format`, OpenAI/xAI `response_format`, Gemini `responseSchema`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OutputFormat {
    /// Constrain the response to JSON matching this JSON Schema.
    JsonSchema { schema: serde_json::Value },
}

/// A full chat-completion request in provider-agnostic form.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatRequest {
    /// Provider-specific model id (e.g. `grok-4`, `claude-opus-4-8`).
    pub model: String,
    /// Optional system prompt. Ordered first and a natural cache breakpoint.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system: Option<SystemPrompt>,
    /// The conversation so far, oldest first.
    pub messages: Vec<Message>,
    /// Tool definitions offered to the model this turn.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<ToolDef>,
    /// Hard ceiling on generated tokens.
    pub max_tokens: u32,
    /// Sampling temperature; `None` defers to the provider default.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    /// Extended-thinking effort. `None` defers to the provider's own default (current behaviour);
    /// `Some(_)` requests a specific level. Set by the agent from the per-archetype default / tuner.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thinking: Option<ThinkingLevel>,
    /// How the model should choose among tools. `None` defers to the provider default (`auto`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_choice: Option<ToolChoice>,
    /// Forbid parallel tool calls within a single turn (at most one tool per response).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub disable_parallel_tool_use: bool,
    /// Nucleus-sampling cutoff; `None` defers to the provider default.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub top_p: Option<f32>,
    /// Top-k sampling cutoff; `None` defers to the provider default.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub top_k: Option<u32>,
    /// Stop generation when any of these strings is produced.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub stop_sequences: Vec<String>,
    /// Constrain the output shape (structured outputs / JSON schema). `None` = free-form.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_format: Option<OutputFormat>,
}

impl ChatRequest {
    /// A request with sane defaults: no system prompt, no tools, `max_tokens = 1024`.
    pub fn new(model: impl Into<String>) -> Self {
        Self {
            model: model.into(),
            system: None,
            messages: Vec::new(),
            tools: Vec::new(),
            max_tokens: 1024,
            temperature: None,
            thinking: None,
            tool_choice: None,
            disable_parallel_tool_use: false,
            top_p: None,
            top_k: None,
            stop_sequences: Vec::new(),
            output_format: None,
        }
    }

    /// Set the extended-thinking effort (builder style).
    pub fn thinking(mut self, level: ThinkingLevel) -> Self {
        self.thinking = Some(level);
        self
    }

    /// Set the tool-choice policy (builder style).
    pub fn tool_choice(mut self, choice: ToolChoice) -> Self {
        self.tool_choice = Some(choice);
        self
    }

    /// Constrain the output to JSON matching `schema` (builder style).
    pub fn json_schema(mut self, schema: serde_json::Value) -> Self {
        self.output_format = Some(OutputFormat::JsonSchema { schema });
        self
    }

    /// Set an (un-cached) system prompt.
    pub fn system(mut self, text: impl Into<String>) -> Self {
        self.system = Some(SystemPrompt {
            text: text.into(),
            cache: false,
        });
        self
    }

    /// Append a message.
    pub fn push(mut self, message: Message) -> Self {
        self.messages.push(message);
        self
    }

    /// Override the token ceiling.
    pub fn max_tokens(mut self, n: u32) -> Self {
        self.max_tokens = n;
        self
    }

    /// Set the sampling temperature.
    pub fn temperature(mut self, t: f32) -> Self {
        self.temperature = Some(t);
        self
    }
}

/// System prompt with a cache marker. When `cache` is true and the provider advertises
/// [`prompt_caching`](crate::Capabilities::prompt_caching), the adapter places a cache
/// breakpoint after it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemPrompt {
    pub text: String,
    #[serde(default)]
    pub cache: bool,
}

/// Who authored a message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    User,
    Assistant,
}

/// One message: a role plus an ordered list of content blocks.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: Role,
    pub content: Vec<ContentBlock>,
}

impl Message {
    /// A user message containing a single text block.
    pub fn user(text: impl Into<String>) -> Self {
        Self {
            role: Role::User,
            content: vec![ContentBlock::text(text)],
        }
    }

    /// An assistant message containing a single text block.
    pub fn assistant(text: impl Into<String>) -> Self {
        Self {
            role: Role::Assistant,
            content: vec![ContentBlock::text(text)],
        }
    }

    /// Concatenate all text/thinking blocks (ignoring tool blocks) into one string.
    pub fn text(&self) -> String {
        let mut out = String::new();
        for block in &self.content {
            match block {
                ContentBlock::Text { text, .. } | ContentBlock::Thinking { text } => {
                    out.push_str(text)
                }
                _ => {}
            }
        }
        out
    }
}

/// A unit of message content. A message can mix text, thinking, tool calls, and tool
/// results, mirroring the providers' block model.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentBlock {
    /// Plain text. `cache` requests a breakpoint after this block (caching-capable providers).
    Text {
        text: String,
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        cache: bool,
    },
    /// Extended-thinking text echoed back into history (Anthropic).
    Thinking { text: String },
    /// An assistant tool call: opaque `id`, tool `name`, and parsed argument JSON.
    ToolUse {
        id: String,
        name: String,
        input: serde_json::Value,
    },
    /// The result of executing a tool call, keyed by the originating `tool_use_id`.
    ToolResult {
        tool_use_id: String,
        content: String,
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        is_error: bool,
    },
}

impl ContentBlock {
    /// An un-cached text block.
    pub fn text(text: impl Into<String>) -> Self {
        ContentBlock::Text {
            text: text.into(),
            cache: false,
        }
    }
}

/// A tool advertised to the model: name, human-readable description, and JSON Schema for
/// its arguments. `cache` marks the end of the (stable) tool-definition prefix.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolDef {
    pub name: String,
    pub description: String,
    pub schema: serde_json::Value,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub cache: bool,
    /// Request strict schema validation of the tool's arguments (structured tool use). Providers
    /// that don't support it ignore the flag.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub strict: bool,
}
