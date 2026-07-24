//! Request shape sent to a [`Provider`](crate::Provider): the model id, an optional system
//! prompt, the conversation as role-tagged content blocks, and the available tool
//! definitions. Cache markers live here so the protocol — not any one adapter — decides
//! where the stable prefix ends (§6.2). Adapters that lack caching ignore them.

use serde::{Deserialize, Serialize};

/// Normalised extended-thinking effort, mapped per-provider by each adapter (§8).
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
    /// No extended thinking.
    Off,
    /// The provider's cheapest meaningful thinking setting.
    Low,
    /// Moderate thinking budget.
    Medium,
    /// Maximum thinking budget.
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
    JsonSchema {
        /// The JSON Schema the response must conform to.
        schema: serde_json::Value,
    },
}

/// A **provider-executed** (server-side) tool: the model invokes it and the *provider* runs it,
/// returning results inline — the agent never executes these. Adapters map each to their built-in
/// tool type (Anthropic versioned tool blocks, xAI `WebSearch`/`CodeExecution`, Gemini grounding).
/// Providers that don't offer a given tool ignore it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ServerTool {
    /// Web search with optional caps and domain allow/block lists.
    WebSearch {
        /// Cap on searches per turn; `None` ⇒ the provider default.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        max_uses: Option<u32>,
        /// If non-empty, restrict results to these domains.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        allowed_domains: Vec<String>,
        /// Domains to exclude from results.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        blocked_domains: Vec<String>,
    },
    /// Fetch the contents of a specific URL.
    WebFetch {
        /// Cap on fetches per turn; `None` ⇒ the provider default.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        max_uses: Option<u32>,
    },
    /// Run code in a provider-hosted sandbox.
    CodeExecution,
    /// Search X (Twitter) posts (xAI Live Search). Optional handle allow/block lists and an
    /// ISO-8601 `YYYY-MM-DD` date window. xAI-specific — other providers ignore it.
    XSearch {
        /// If non-empty, restrict to posts from these handles.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        allowed_handles: Vec<String>,
        /// Handles to exclude.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        blocked_handles: Vec<String>,
        /// Inclusive start of the ISO-8601 `YYYY-MM-DD` date window; `None` ⇒ unbounded.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        from_date: Option<String>,
        /// Inclusive end of the date window; `None` ⇒ unbounded.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        to_date: Option<String>,
    },
    /// Retrieval-augmented search over xAI document collections by id, with an optional result
    /// cap. xAI-specific — other providers ignore it.
    CollectionsSearch {
        /// The document collections to search.
        collection_ids: Vec<String>,
        /// Cap on returned results; `None` ⇒ the provider default.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        limit: Option<u32>,
    },
}

/// An Anthropic-defined tool whose argument schema the model already knows — declared by a
/// versioned `type` rather than a custom `input_schema`. The model invokes it as an ordinary
/// `tool_use` (so it flows through [`Event::ToolUseStart`](crate::Event::ToolUseStart) and is
/// executed **client-side**, like any other tool); the only difference is the declaration.
/// Anthropic-specific — other providers ignore these (no equivalent built-in client tool type).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BuiltinTool {
    /// Run shell commands (`bash_20250124`, tool name `bash`).
    Bash,
    /// View and str-replace-edit files (`text_editor_20250728`, name `str_replace_based_edit_tool`).
    TextEditor,
    /// Agentic file-backed memory (`memory_20250818`, tool name `memory`).
    Memory,
}

/// A remote MCP (Model Context Protocol) server the provider connects to on the model's behalf.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct McpServer {
    /// Label identifying the server in tool calls.
    pub name: String,
    /// The server's endpoint URL.
    pub url: String,
    /// Bearer token for the server (omit when the provider injects credentials out of band).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub authorization_token: Option<String>,
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
    /// Provider-executed (server-side) tools to offer — web search, code execution, etc.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub server_tools: Vec<ServerTool>,
    /// Remote MCP servers the provider should connect to on the model's behalf.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub mcp_servers: Vec<McpServer>,
    /// Anthropic-defined client tools to declare by versioned type (bash/text_editor/memory).
    /// The model calls them as normal `tool_use` blocks; non-Anthropic providers ignore them.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub builtin_tools: Vec<BuiltinTool>,
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
            server_tools: Vec::new(),
            mcp_servers: Vec::new(),
            builtin_tools: Vec::new(),
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
    /// The system prompt text.
    pub text: String,
    /// Request a cache breakpoint after this prompt (honoured only by caching providers).
    #[serde(default)]
    pub cache: bool,
}

/// Who authored a message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    /// A message from the user.
    User,
    /// A message from the model.
    Assistant,
}

/// One message: a role plus an ordered list of content blocks.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    /// Who authored the message.
    pub role: Role,
    /// The message's ordered content blocks.
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

/// Where the bytes of an image or document come from. Adapters map this to their media source
/// shape (Anthropic `source.type` base64/url, Gemini `inlineData`/`fileData`, OpenAI `image_url`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum MediaSource {
    /// Inline base64-encoded bytes with their MIME type (e.g. `image/png`, `application/pdf`).
    Base64 {
        /// MIME type of the bytes (e.g. `image/png`).
        media_type: String,
        /// The base64-encoded bytes.
        data: String,
    },
    /// A URL the provider fetches itself.
    Url {
        /// The URL to fetch.
        url: String,
    },
    /// A previously-uploaded file referenced by id (provider Files API).
    File {
        /// The provider's file id.
        file_id: String,
    },
    /// Inline **plain text** (raw, not base64) — used for text documents, the lightest way to get
    /// source-grounded [`ContentBlock::Document`] `citations` without a PDF. Anthropic maps it to a
    /// `text`-type document source; Gemini inlines it as a text part; image inputs ignore it.
    PlainText {
        /// The raw document text.
        text: String,
    },
}

/// A unit of message content. A message can mix text, thinking, images, documents, tool calls,
/// and tool results, mirroring the providers' block model.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentBlock {
    /// Plain text. `cache` requests a breakpoint after this block (caching-capable providers).
    Text {
        /// The text content.
        text: String,
        /// Request a cache breakpoint after this block.
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        cache: bool,
    },
    /// Extended-thinking text echoed back into history (Anthropic).
    Thinking {
        /// The thinking text.
        text: String,
    },
    /// An image input (vision). Providers without vision ignore it.
    Image {
        /// Where the image bytes come from.
        source: MediaSource,
    },
    /// A document input (e.g. PDF). Anthropic/Gemini support it; others ignore it. `citations`
    /// requests source-grounded citations in the answer (Anthropic; ignored elsewhere).
    Document {
        /// Where the document bytes come from.
        source: MediaSource,
        /// Request source-grounded citations in the answer.
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        citations: bool,
    },
    /// An assistant tool call: opaque `id`, tool `name`, and parsed argument JSON.
    ToolUse {
        /// Opaque call id, echoed back on the matching [`ToolResult`](ContentBlock::ToolResult).
        id: String,
        /// The tool being called.
        name: String,
        /// The parsed argument object.
        input: serde_json::Value,
    },
    /// The result of executing a tool call, keyed by the originating `tool_use_id`.
    ToolResult {
        /// The `id` of the [`ToolUse`](ContentBlock::ToolUse) this answers.
        tool_use_id: String,
        /// The tool's output, rendered for the model.
        content: String,
        /// Whether the tool reported a (recoverable) error.
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

    /// An inline (base64) image block.
    pub fn image_base64(media_type: impl Into<String>, data: impl Into<String>) -> Self {
        ContentBlock::Image {
            source: MediaSource::Base64 {
                media_type: media_type.into(),
                data: data.into(),
            },
        }
    }

    /// An image block referencing a URL the provider fetches.
    pub fn image_url(url: impl Into<String>) -> Self {
        ContentBlock::Image {
            source: MediaSource::Url { url: url.into() },
        }
    }
}

/// A tool advertised to the model: name, human-readable description, and JSON Schema for
/// its arguments. `cache` marks the end of the (stable) tool-definition prefix.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolDef {
    /// The tool's name, as the model calls it.
    pub name: String,
    /// Human-readable description sent to the model.
    pub description: String,
    /// JSON Schema for the tool's argument object.
    pub schema: serde_json::Value,
    /// Mark the end of the (stable) tool-definition prefix for caching.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub cache: bool,
    /// Request strict schema validation of the tool's arguments (structured tool use). Providers
    /// that don't support it ignore the flag.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub strict: bool,
}
