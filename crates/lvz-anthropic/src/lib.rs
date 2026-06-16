//! Anthropic provider for Lavoisier.
//!
//! Implements [`Provider`] over the **native** Messages API (`POST /v1/messages`,
//! `stream: true`). The native path is required to keep prompt caching and extended thinking
//! (§1, §6.2, §8) — Anthropic's OpenAI-compat shim drops both, which is exactly
//! why this crate hand-rolls a thin `reqwest` adapter rather than depending on a stale
//! community crate.
//!
//! Caching: a [`cache_control: ephemeral`] marker is attached to any system prompt, tool
//! definition, or content block whose protocol-level `cache` flag is set, placing a cache
//! breakpoint at the end of the stable prefix. The agent (not this crate) decides where that
//! boundary is by setting the flags.

pub mod batch;
mod sse;

use std::collections::VecDeque;

use async_trait::async_trait;
use bytes::Bytes;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{
    retry_transient, BuiltinTool, Capabilities, ChatRequest, ContentBlock, Event, MediaSource,
    Message, OutputFormat, Provider, ProviderError, Role, ServerTool, SystemPrompt, ThinkingLevel,
    ToolChoice, ToolDef,
};
use serde_json::{json, Value};

use crate::sse::AnthropicSseDecoder;

const DEFAULT_BASE_URL: &str = "https://api.anthropic.com";
const ANTHROPIC_VERSION: &str = "2023-06-01";
/// Beta flag enabling the 1-hour cache TTL (`cache_control.ttl = "1h"`).
const EXTENDED_CACHE_TTL_BETA: &str = "extended-cache-ttl-2025-04-11";
/// Beta flag for the MCP connector (`mcp_servers`).
const MCP_BETA: &str = "mcp-client-2025-11-20";
/// Beta flag for the Files API (`/v1/files`, `source.type = "file"`).
const FILES_BETA: &str = "files-api-2025-04-14";
/// Beta flag for the memory tool (`memory_20250818`) / context management.
const CONTEXT_MGMT_BETA: &str = "context-management-2025-06-27";

/// A [`Provider`] backed by the native Anthropic Messages API.
pub struct AnthropicProvider {
    api_key: String,
    base_url: String,
    http: reqwest::Client,
    /// When set, the **immutable** prefix breakpoints (system / tool defs / repo skeleton — the
    /// protocol-`cache`-flagged blocks) use a 1-hour cache TTL instead of the default 5 minutes,
    /// so a long-running gateway keeps re-reading them across idle gaps without re-creating the
    /// cache. The volatile rolling conversation-tail breakpoint always stays at 5 minutes.
    extended_cache_ttl: bool,
}

impl AnthropicProvider {
    /// Construct against the default base URL (`https://api.anthropic.com`).
    pub fn new(api_key: impl Into<String>) -> Self {
        Self::with_base_url(api_key, DEFAULT_BASE_URL)
    }

    /// Construct against an explicit base URL (e.g. a proxy or a mock server in tests).
    pub fn with_base_url(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            base_url: base_url.into(),
            http: reqwest::Client::new(),
            extended_cache_ttl: false,
        }
    }

    /// Use a 1-hour cache TTL on the immutable prefix (best for a long-running `--serve` gateway;
    /// for one-shot runs the default 5-minute TTL is cheaper, since 1h cache writes cost more).
    pub fn with_extended_cache_ttl(mut self, on: bool) -> Self {
        self.extended_cache_ttl = on;
        self
    }

    /// Construct from `ANTHROPIC_API_KEY` (required) and `ANTHROPIC_BASE_URL` (optional).
    pub fn from_env() -> Result<Self, ProviderError> {
        let api_key = std::env::var("ANTHROPIC_API_KEY")
            .map_err(|_| ProviderError::Config("ANTHROPIC_API_KEY is not set".into()))?;
        let base_url =
            std::env::var("ANTHROPIC_BASE_URL").unwrap_or_else(|_| DEFAULT_BASE_URL.into());
        Ok(Self::with_base_url(api_key, base_url))
    }

    /// Upload a file to the Files API (`POST /v1/files`) and return its `file_id`, which can then
    /// be referenced from a message via [`MediaSource::File`]. `mime` is the file's content type
    /// (e.g. `application/pdf`, `image/png`).
    pub async fn upload_file(
        &self,
        filename: impl Into<String>,
        bytes: Vec<u8>,
        mime: &str,
    ) -> Result<String, ProviderError> {
        let part = reqwest::multipart::Part::bytes(bytes)
            .file_name(filename.into())
            .mime_str(mime)
            .map_err(|e| ProviderError::Config(e.to_string()))?;
        let form = reqwest::multipart::Form::new().part("file", part);
        let url = format!("{}/v1/files", self.base_url.trim_end_matches('/'));
        let resp = self
            .http
            .post(url)
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .header("anthropic-beta", FILES_BETA)
            .multipart(form)
            .send()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;
        let status = resp.status();
        if !status.is_success() {
            return Err(ProviderError::Api {
                status: status.as_u16(),
                message: resp.text().await.unwrap_or_default(),
            });
        }
        let v: Value = resp
            .json()
            .await
            .map_err(|e| ProviderError::Decode(e.to_string()))?;
        v["id"]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| ProviderError::Decode("files response missing id".into()))
    }
}

#[async_trait]
impl Provider for AnthropicProvider {
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        let body = build_body(&req, self.extended_cache_ttl);
        let url = format!("{}/v1/messages", self.base_url.trim_end_matches('/'));

        // Collect the beta flags this request needs (sent as one comma-joined header).
        let mut betas: Vec<&str> = Vec::new();
        if self.extended_cache_ttl {
            betas.push(EXTENDED_CACHE_TTL_BETA);
        }
        if !req.mcp_servers.is_empty() {
            betas.push(MCP_BETA);
        }
        // The memory tool rides on the context-management beta.
        if req.builtin_tools.contains(&BuiltinTool::Memory) {
            betas.push(CONTEXT_MGMT_BETA);
        }
        // A file-id media source references the Files API.
        if req.messages.iter().any(|m| {
            m.content.iter().any(|b| {
                matches!(
                    b,
                    ContentBlock::Image {
                        source: MediaSource::File { .. }
                    } | ContentBlock::Document {
                        source: MediaSource::File { .. },
                        ..
                    }
                )
            })
        }) {
            betas.push(FILES_BETA);
        }
        let beta_header = (!betas.is_empty()).then(|| betas.join(","));

        // Bounded exponential backoff on transient throttling (shared `retry_transient`): Anthropic
        // returns 429 when the per-minute token/request budget is exceeded and 503 when overloaded;
        // the send is idempotent (nothing is generated until the stream starts), so a burst from the
        // agent loop retries instead of failing the whole task. Tunable via ANTHROPIC_MAX_RETRIES.
        let max_retries: u32 = std::env::var("ANTHROPIC_MAX_RETRIES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(6);
        let resp = retry_transient(max_retries, || async {
            let mut request = self
                .http
                .post(&url)
                .header("x-api-key", &self.api_key)
                .header("anthropic-version", ANTHROPIC_VERSION);
            if let Some(h) = &beta_header {
                request = request.header("anthropic-beta", h);
            }
            let resp = request
                .json(&body)
                .send()
                .await
                .map_err(|e| ProviderError::Transport(e.to_string()))?;
            let status = resp.status();
            if status.is_success() {
                Ok(resp)
            } else {
                Err(ProviderError::Api {
                    status: status.as_u16(),
                    message: resp.text().await.unwrap_or_default(),
                })
            }
        })
        .await?;

        let state = SseState {
            body: resp.bytes_stream().boxed(),
            decoder: AnthropicSseDecoder::default(),
            pending: VecDeque::new(),
            drained: false,
        };

        let events = stream::unfold(state, |mut st| async move {
            loop {
                if let Some(event) = st.pending.pop_front() {
                    return Some((event, st));
                }
                if st.drained {
                    return None;
                }
                match st.body.next().await {
                    Some(Ok(chunk)) => st.decoder.push(&chunk, &mut st.pending),
                    Some(Err(e)) => {
                        st.pending
                            .push_back(Err(ProviderError::Transport(e.to_string())));
                        st.drained = true;
                    }
                    None => {
                        st.decoder.eof(&mut st.pending);
                        st.drained = true;
                    }
                }
            }
        });

        Ok(events.boxed())
    }

    fn capabilities(&self) -> Capabilities {
        Capabilities {
            prompt_caching: true,
            extended_thinking: true,
            parallel_tool_use: true,
            // Provider-executed tools (web_search/web_fetch/code_execution) are declarable.
            server_side_tools: true,
            vision: true,
        }
    }

    /// Native token counting via `POST /v1/messages/count_tokens` (returns `usage.input_tokens`).
    async fn count_tokens(&self, req: &ChatRequest) -> Result<Option<u64>, ProviderError> {
        let body = build_count_body(req);
        let url = format!(
            "{}/v1/messages/count_tokens",
            self.base_url.trim_end_matches('/')
        );
        let resp = self
            .http
            .post(url)
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .json(&body)
            .send()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;
        let status = resp.status();
        if !status.is_success() {
            let message = resp.text().await.unwrap_or_default();
            return Err(ProviderError::Api {
                status: status.as_u16(),
                message,
            });
        }
        let v: Value = resp
            .json()
            .await
            .map_err(|e| ProviderError::Decode(e.to_string()))?;
        Ok(v["input_tokens"].as_u64())
    }
}

/// Build the count-tokens request body: the same prompt-shaping fields as a completion request
/// (model, system, messages, tools) but **no** `stream`/`max_tokens` (rejected by the endpoint),
/// and no rolling cache-tail marker (counting is a one-shot, not a cached turn).
fn build_count_body(req: &ChatRequest) -> Value {
    let mut body = json!({
        "model": req.model,
        "messages": build_messages(&req.messages, false),
    });
    if let Some(system) = req.system.as_ref().map(|s| build_system(s, false)) {
        body["system"] = system;
    }
    if !req.tools.is_empty() {
        body["tools"] = build_tools(&req.tools, false);
    }
    if let Some(tc) = req.tool_choice.as_ref() {
        body["tool_choice"] = build_tool_choice(tc, req.disable_parallel_tool_use);
    }
    body
}

struct SseState {
    body: BoxStream<'static, reqwest::Result<Bytes>>,
    decoder: AnthropicSseDecoder,
    pending: VecDeque<Result<Event, ProviderError>>,
    drained: bool,
}

/// The ephemeral cache-control marker placed at a stable-prefix breakpoint. `ttl_1h` requests the
/// 1-hour TTL (immutable prefix on a long-running gateway); otherwise the default 5-minute TTL.
fn cache_control(ttl_1h: bool) -> Value {
    if ttl_1h {
        json!({ "type": "ephemeral", "ttl": "1h" })
    } else {
        json!({ "type": "ephemeral" })
    }
}

/// Build the Messages API request body from a normalised [`ChatRequest`]. `extended_ttl` puts the
/// 1-hour TTL on the immutable-prefix breakpoints (system / tools / skeleton).
fn build_body(req: &ChatRequest, extended_ttl: bool) -> Value {
    let mut body = json!({
        "model": req.model,
        "max_tokens": req.max_tokens,
        "messages": build_messages(&req.messages, extended_ttl),
        "stream": true,
    });
    if let Some(system) = req.system.as_ref().map(|s| build_system(s, extended_ttl)) {
        body["system"] = system;
    }
    if !req.tools.is_empty() || !req.server_tools.is_empty() || !req.builtin_tools.is_empty() {
        let mut tools = build_tools(&req.tools, extended_ttl);
        let arr = tools.as_array_mut().expect("build_tools returns an array");
        arr.extend(req.server_tools.iter().filter_map(build_server_tool));
        arr.extend(req.builtin_tools.iter().map(build_builtin_tool));
        body["tools"] = tools;
    }
    if !req.mcp_servers.is_empty() {
        body["mcp_servers"] = json!(req
            .mcp_servers
            .iter()
            .map(|s| {
                let mut v = json!({ "type": "url", "name": s.name, "url": s.url });
                if let Some(tok) = &s.authorization_token {
                    v["authorization_token"] = json!(tok);
                }
                v
            })
            .collect::<Vec<_>>());
    }
    // Sampling parameters are rejected (400) on Opus 4.7/4.8 and Fable/Mythos 5 — skip them there.
    if !rejects_sampling_params(&req.model) {
        if let Some(t) = req.temperature {
            body["temperature"] = json!(t);
        }
        if let Some(p) = req.top_p {
            body["top_p"] = json!(p);
        }
        if let Some(k) = req.top_k {
            body["top_k"] = json!(k);
        }
    }
    if !req.stop_sequences.is_empty() {
        body["stop_sequences"] = json!(req.stop_sequences);
    }
    if let Some(tc) = req.tool_choice.as_ref() {
        body["tool_choice"] = build_tool_choice(tc, req.disable_parallel_tool_use);
    }
    if let Some(OutputFormat::JsonSchema { schema }) = req.output_format.as_ref() {
        body["output_config"]["format"] = json!({ "type": "json_schema", "schema": schema });
    }
    apply_thinking(&mut body, req.thinking, &req.model, req.max_tokens);
    mark_conversation_tail(&mut body);
    body
}

/// Models that 400 on `temperature`/`top_p`/`top_k` (Opus 4.7/4.8, Fable 5, Mythos 5).
fn rejects_sampling_params(model: &str) -> bool {
    ["opus-4-7", "opus-4-8", "fable-5", "mythos-5"]
        .iter()
        .any(|m| model.contains(m))
}

/// Models that use *legacy* fixed-budget extended thinking (`thinking.budget_tokens`) rather than
/// adaptive thinking + `effort`. Adaptive/`effort` 400 or are unsupported on these (Sonnet 4.5,
/// Haiku 4.5, Opus 4.0/4.1); everything 4.6+ (incl. Fable) uses the modern path.
fn uses_legacy_thinking(model: &str) -> bool {
    ["haiku", "sonnet-4-5", "sonnet-4-0", "opus-4-1", "opus-4-0"]
        .iter()
        .any(|m| model.contains(m))
}

/// Map the normalised [`ToolChoice`] onto Anthropic's `tool_choice` object.
fn build_tool_choice(choice: &ToolChoice, disable_parallel: bool) -> Value {
    let mut v = match choice {
        ToolChoice::Auto => json!({ "type": "auto" }),
        ToolChoice::Required => json!({ "type": "any" }),
        ToolChoice::None => json!({ "type": "none" }),
        ToolChoice::Tool(name) => json!({ "type": "tool", "name": name }),
    };
    // `disable_parallel_tool_use` is valid on auto/any/tool (not none).
    if disable_parallel && !matches!(choice, ToolChoice::None) {
        v["disable_parallel_tool_use"] = json!(true);
    }
    v
}

/// Map the normalised [`ThinkingLevel`] onto Anthropic's thinking surface. Extended thinking stays
/// opt-in: `Off`/`Low` add nothing (a mechanical task never *raises* cost); `Medium`/`High` enable it.
///
/// The shape is **model-dependent** (see [`uses_legacy_thinking`]): modern models (Sonnet 4.6,
/// Opus 4.6/4.7/4.8, Fable 5) use **adaptive thinking + `output_config.effort`** — `budget_tokens`
/// 400s on Opus 4.7/4.8/Fable. Legacy models (Sonnet 4.5, Haiku 4.5, Opus 4.0/4.1) use fixed-budget
/// `thinking.budget_tokens`, where Anthropic requires `max_tokens > budget_tokens`. Either way a
/// custom `temperature` is disallowed alongside thinking, so it's dropped.
fn apply_thinking(body: &mut Value, thinking: Option<ThinkingLevel>, model: &str, max_tokens: u32) {
    let level = match thinking {
        Some(l @ (ThinkingLevel::Medium | ThinkingLevel::High)) => l,
        _ => return, // None / Off / Low ⇒ no thinking block
    };
    if uses_legacy_thinking(model) {
        let budget: u32 = if level == ThinkingLevel::High {
            12000
        } else {
            4096
        };
        body["thinking"] = json!({ "type": "enabled", "budget_tokens": budget });
        if max_tokens <= budget {
            body["max_tokens"] = json!(budget + 4096);
        }
    } else {
        // Modern: adaptive thinking, depth controlled by effort (preserves any output_config.format).
        body["thinking"] = json!({ "type": "adaptive" });
        let effort = if level == ThinkingLevel::High {
            "high"
        } else {
            "medium"
        };
        body["output_config"]["effort"] = json!(effort);
    }
    if let Some(obj) = body.as_object_mut() {
        obj.remove("temperature");
    }
}

/// Anthropic caps a request at **4** `cache_control` breakpoints. The static prefix (system +
/// last tool def + repo-skeleton block) uses up to 3; this spends the spare one on the **tail of
/// the conversation** — the last content block of the last message — so the whole transcript prefix
/// bills as `cache_read` on the next round-trip instead of full-price fresh input (the rolling-cache
/// pattern). It pays a one-time cache *write* on this turn to save the (larger) *read* next turn.
/// No-op when the breakpoint budget is already spent or there is no message content to mark.
fn mark_conversation_tail(body: &mut Value) {
    const MAX_BREAKPOINTS: usize = 4;
    if count_cache_breakpoints(body) >= MAX_BREAKPOINTS {
        return;
    }
    if let Some(last_msg) = body["messages"].as_array_mut().and_then(|m| m.last_mut()) {
        if let Some(last_block) = last_msg["content"]
            .as_array_mut()
            .and_then(|c| c.last_mut())
        {
            if last_block.get("cache_control").is_none() {
                // The conversation tail is volatile — always the short (5-minute) TTL.
                last_block["cache_control"] = cache_control(false);
            }
        }
    }
}

/// Count `cache_control` markers already present across system, tools, and message content.
fn count_cache_breakpoints(body: &Value) -> usize {
    fn count(v: &Value) -> usize {
        match v {
            Value::Object(map) => {
                let here = map.contains_key("cache_control") as usize;
                here + map
                    .iter()
                    .filter(|(k, _)| *k != "cache_control")
                    .map(|(_, val)| count(val))
                    .sum::<usize>()
            }
            Value::Array(arr) => arr.iter().map(count).sum(),
            _ => 0,
        }
    }
    ["system", "tools", "messages"]
        .iter()
        .map(|k| count(&body[*k]))
        .sum()
}

/// System prompt as a one-element text-block array, so a cache breakpoint can attach to it.
fn build_system(system: &SystemPrompt, extended_ttl: bool) -> Value {
    let mut block = json!({ "type": "text", "text": system.text });
    if system.cache {
        block["cache_control"] = cache_control(extended_ttl);
    }
    json!([block])
}

fn build_messages(messages: &[Message], extended_ttl: bool) -> Value {
    let arr = messages
        .iter()
        .map(|m| {
            let role = match m.role {
                Role::User => "user",
                Role::Assistant => "assistant",
            };
            let content: Vec<Value> = m
                .content
                .iter()
                .filter_map(|b| build_content_block(b, extended_ttl))
                .collect();
            json!({ "role": role, "content": content })
        })
        .collect::<Vec<_>>();
    Value::Array(arr)
}

/// Map a normalised [`ServerTool`] onto Anthropic's versioned built-in tool block. Returns `None`
/// for tools Anthropic doesn't offer (xAI's X/collections search), which are silently skipped.
fn build_server_tool(tool: &ServerTool) -> Option<Value> {
    let v = match tool {
        ServerTool::WebSearch {
            max_uses,
            allowed_domains,
            blocked_domains,
        } => {
            let mut v = json!({ "type": "web_search_20260209", "name": "web_search" });
            if let Some(n) = max_uses {
                v["max_uses"] = json!(n);
            }
            if !allowed_domains.is_empty() {
                v["allowed_domains"] = json!(allowed_domains);
            }
            if !blocked_domains.is_empty() {
                v["blocked_domains"] = json!(blocked_domains);
            }
            v
        }
        ServerTool::WebFetch { max_uses } => {
            let mut v = json!({ "type": "web_fetch_20260209", "name": "web_fetch" });
            if let Some(n) = max_uses {
                v["max_uses"] = json!(n);
            }
            v
        }
        ServerTool::CodeExecution => {
            json!({ "type": "code_execution_20260120", "name": "code_execution" })
        }
        // xAI-specific provider tools — no Anthropic equivalent.
        ServerTool::XSearch { .. } | ServerTool::CollectionsSearch { .. } => return None,
    };
    Some(v)
}

/// Map an Anthropic-defined client tool to its versioned `{type, name}` declaration. The schema
/// is implicit (Anthropic knows it); the model calls it as a normal `tool_use`.
fn build_builtin_tool(tool: &BuiltinTool) -> Value {
    match tool {
        BuiltinTool::Bash => json!({ "type": "bash_20250124", "name": "bash" }),
        BuiltinTool::TextEditor => {
            json!({ "type": "text_editor_20250728", "name": "str_replace_based_edit_tool" })
        }
        BuiltinTool::Memory => json!({ "type": "memory_20250818", "name": "memory" }),
    }
}

/// Map a normalised media source onto Anthropic's `source` object.
fn anthropic_media_source(source: &MediaSource) -> Value {
    match source {
        MediaSource::Base64 { media_type, data } => {
            json!({ "type": "base64", "media_type": media_type, "data": data })
        }
        MediaSource::Url { url } => json!({ "type": "url", "url": url }),
        MediaSource::File { file_id } => json!({ "type": "file", "file_id": file_id }),
        MediaSource::PlainText { text } => {
            json!({ "type": "text", "media_type": "text/plain", "data": text })
        }
    }
}

/// Map one normalised block to its Messages-API JSON, or `None` to omit it.
///
/// Prior-turn **thinking is dropped**, not re-sent. Echoing it back (verbatim or as text) would
/// re-bill those tokens every round-trip; the cheaper *and* correct choice is to omit it (the
/// Messages API does not require past thinking blocks once a turn's tool loop has closed). Caching
/// thinking would still cost cache-read tokens, so dropping it is strictly the most token-efficient
/// option.
fn build_content_block(block: &ContentBlock, extended_ttl: bool) -> Option<Value> {
    Some(match block {
        ContentBlock::Text { text, cache } => {
            let mut v = json!({ "type": "text", "text": text });
            if *cache {
                v["cache_control"] = cache_control(extended_ttl);
            }
            v
        }
        ContentBlock::Thinking { .. } => return None,
        ContentBlock::Image { source } => {
            json!({ "type": "image", "source": anthropic_media_source(source) })
        }
        ContentBlock::Document { source, citations } => {
            let mut v = json!({ "type": "document", "source": anthropic_media_source(source) });
            if *citations {
                v["citations"] = json!({ "enabled": true });
            }
            v
        }
        ContentBlock::ToolUse { id, name, input } => {
            json!({ "type": "tool_use", "id": id, "name": name, "input": input })
        }
        ContentBlock::ToolResult {
            tool_use_id,
            content,
            is_error,
        } => {
            let mut v = json!({
                "type": "tool_result",
                "tool_use_id": tool_use_id,
                "content": content,
            });
            if *is_error {
                v["is_error"] = json!(true);
            }
            v
        }
    })
}

fn build_tools(tools: &[ToolDef], extended_ttl: bool) -> Value {
    let arr = tools
        .iter()
        .map(|t| {
            let mut v = json!({
                "name": t.name,
                "description": t.description,
                "input_schema": t.schema,
            });
            if t.strict {
                v["strict"] = json!(true);
            }
            if t.cache {
                v["cache_control"] = cache_control(extended_ttl);
            }
            v
        })
        .collect::<Vec<_>>();
    Value::Array(arr)
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::ContentBlock;

    #[test]
    fn system_and_tools_carry_cache_control_when_flagged() {
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
        req.system = Some(SystemPrompt {
            text: "stable rules".into(),
            cache: true,
        });
        req.tools.push(ToolDef {
            name: "read_file".into(),
            description: "read a file".into(),
            schema: json!({"type": "object"}),
            cache: true,
            strict: false,
        });

        let body = build_body(&req, false);
        assert_eq!(body["system"][0]["cache_control"]["type"], "ephemeral");
        assert_eq!(body["tools"][0]["cache_control"]["type"], "ephemeral");
        assert_eq!(body["tools"][0]["input_schema"]["type"], "object");
        assert_eq!(body["stream"], true);
    }

    #[test]
    fn uncached_blocks_omit_cache_control() {
        let req = ChatRequest::new("claude-sonnet-4-6")
            .system("volatile")
            .push(Message::user("hi"));
        let body = build_body(&req, false);
        assert!(body["system"][0]["cache_control"].is_null());
    }

    #[test]
    fn tool_result_blocks_round_trip_into_anthropic_shape() {
        let msg = Message {
            role: Role::User,
            content: vec![ContentBlock::ToolResult {
                tool_use_id: "toolu_9".into(),
                content: "ok".into(),
                is_error: false,
            }],
        };
        let body = build_body(&ChatRequest::new("claude-sonnet-4-6").push(msg), false);
        let block = &body["messages"][0]["content"][0];
        assert_eq!(block["type"], "tool_result");
        assert_eq!(block["tool_use_id"], "toolu_9");
        assert!(block["is_error"].is_null()); // omitted when false
    }

    #[test]
    fn conversation_tail_gets_rolling_cache_breakpoint() {
        // A multi-turn transcript: the last block of the last message should carry the rolling
        // breakpoint so the whole prefix bills as cache_read next round-trip.
        let req = ChatRequest::new("claude-sonnet-4-6")
            .push(Message::user("do the task"))
            .push(Message::assistant("on it"))
            .push(Message::user("more context here"));
        let body = build_body(&req, false);
        let msgs = body["messages"].as_array().unwrap();
        let last = msgs.last().unwrap();
        let last_block = last["content"].as_array().unwrap().last().unwrap();
        assert_eq!(
            last_block["cache_control"]["type"], "ephemeral",
            "the conversation tail must carry the rolling cache breakpoint"
        );
        // Earlier messages stay uncached (the breakpoint is only on the tail).
        assert!(msgs[0]["content"][0]["cache_control"].is_null());
    }

    #[test]
    fn thinking_blocks_are_dropped_from_resent_history() {
        let msg = Message {
            role: Role::Assistant,
            content: vec![
                ContentBlock::Thinking {
                    text: "lots of reasoning we must not re-bill".into(),
                },
                ContentBlock::text("the answer"),
            ],
        };
        let body = build_body(&ChatRequest::new("claude-sonnet-4-6").push(msg), false);
        let content = body["messages"][0]["content"].as_array().unwrap();
        assert_eq!(content.len(), 1, "thinking block must be omitted");
        assert_eq!(content[0]["type"], "text");
        assert_eq!(content[0]["text"], "the answer");
        let serialized = body.to_string();
        assert!(
            !serialized.contains("re-bill"),
            "thinking text must not be re-sent in any form"
        );
    }

    #[test]
    fn cache_breakpoints_never_exceed_four() {
        // Saturate the static prefix with breakpoints (system + tool + two cached text blocks),
        // then assert the rolling-tail logic refuses to add a 5th.
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message {
            role: Role::User,
            content: vec![
                ContentBlock::Text {
                    text: "skeleton".into(),
                    cache: true,
                },
                ContentBlock::Text {
                    text: "task".into(),
                    cache: true,
                },
                ContentBlock::text("uncached tail"),
            ],
        });
        req.system = Some(SystemPrompt {
            text: "rules".into(),
            cache: true,
        });
        req.tools.push(ToolDef {
            name: "t".into(),
            description: "d".into(),
            schema: json!({"type": "object"}),
            cache: true,
            strict: false,
        });
        let body = build_body(&req, false);
        assert_eq!(
            count_cache_breakpoints(&body),
            4,
            "must cap at 4 breakpoints"
        );
        // The uncached tail block stays uncached because the budget was already spent.
        assert!(body["messages"][0]["content"][2]["cache_control"].is_null());
    }

    #[test]
    fn common_request_params_map_to_anthropic_shape() {
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
        req.tool_choice = Some(ToolChoice::Tool("get_weather".into()));
        req.disable_parallel_tool_use = true;
        req.top_p = Some(0.9);
        req.top_k = Some(40);
        req.stop_sequences = vec!["STOP".into()];
        req.output_format = Some(OutputFormat::JsonSchema {
            schema: json!({"type": "object"}),
        });
        req.tools.push(ToolDef {
            name: "get_weather".into(),
            description: "d".into(),
            schema: json!({"type": "object"}),
            cache: false,
            strict: true,
        });
        let body = build_body(&req, false);
        assert_eq!(body["tool_choice"]["type"], "tool");
        assert_eq!(body["tool_choice"]["name"], "get_weather");
        assert_eq!(body["tool_choice"]["disable_parallel_tool_use"], true);
        assert!((body["top_p"].as_f64().unwrap() - 0.9).abs() < 1e-4);
        assert_eq!(body["top_k"], 40);
        assert_eq!(body["stop_sequences"][0], "STOP");
        assert_eq!(body["output_config"]["format"]["type"], "json_schema");
        assert_eq!(body["tools"][0]["strict"], true);
    }

    #[test]
    fn image_and_document_blocks_map_to_anthropic_shape() {
        let msg = Message {
            role: Role::User,
            content: vec![
                ContentBlock::image_base64("image/png", "AAAA"),
                ContentBlock::Document {
                    source: MediaSource::Url {
                        url: "https://x/y.pdf".into(),
                    },
                    citations: false,
                },
                ContentBlock::text("describe these"),
            ],
        };
        let body = build_body(&ChatRequest::new("claude-sonnet-4-6").push(msg), false);
        let c = &body["messages"][0]["content"];
        assert_eq!(c[0]["type"], "image");
        assert_eq!(c[0]["source"]["type"], "base64");
        assert_eq!(c[0]["source"]["media_type"], "image/png");
        assert_eq!(c[1]["type"], "document");
        assert_eq!(c[1]["source"]["type"], "url");
        assert_eq!(c[1]["source"]["url"], "https://x/y.pdf");
    }

    #[test]
    fn server_tools_and_mcp_map_to_anthropic_shape() {
        use lvz_protocol::{McpServer, ServerTool};
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
        req.server_tools = vec![
            ServerTool::WebSearch {
                max_uses: Some(3),
                allowed_domains: vec!["docs.rs".into()],
                blocked_domains: vec![],
            },
            ServerTool::CodeExecution,
        ];
        req.mcp_servers = vec![McpServer {
            name: "gh".into(),
            url: "https://mcp.example/sse".into(),
            authorization_token: Some("tok".into()),
        }];
        let body = build_body(&req, false);
        let tools = body["tools"].as_array().unwrap();
        assert!(tools.iter().any(|t| t["type"] == "web_search_20260209"));
        assert!(tools.iter().any(|t| t["type"] == "code_execution_20260120"));
        let ws = tools
            .iter()
            .find(|t| t["type"] == "web_search_20260209")
            .unwrap();
        assert_eq!(ws["max_uses"], 3);
        assert_eq!(ws["allowed_domains"][0], "docs.rs");
        assert_eq!(body["mcp_servers"][0]["url"], "https://mcp.example/sse");
        assert_eq!(body["mcp_servers"][0]["authorization_token"], "tok");
    }

    #[test]
    fn builtin_tools_map_to_versioned_declarations() {
        use lvz_protocol::BuiltinTool;
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
        req.builtin_tools = vec![
            BuiltinTool::Bash,
            BuiltinTool::TextEditor,
            BuiltinTool::Memory,
        ];
        let body = build_body(&req, false);
        let tools = body["tools"].as_array().unwrap();
        let bash = tools.iter().find(|t| t["name"] == "bash").unwrap();
        assert_eq!(bash["type"], "bash_20250124");
        let ed = tools
            .iter()
            .find(|t| t["name"] == "str_replace_based_edit_tool")
            .unwrap();
        assert_eq!(ed["type"], "text_editor_20250728");
        let mem = tools.iter().find(|t| t["name"] == "memory").unwrap();
        assert_eq!(mem["type"], "memory_20250818");
        // Builtin tools carry no input_schema (Anthropic supplies it).
        assert!(bash.get("input_schema").is_none());
    }

    #[test]
    fn file_media_source_maps_to_anthropic_file_block() {
        let msg = Message {
            role: Role::User,
            content: vec![ContentBlock::Document {
                source: MediaSource::File {
                    file_id: "file_123".into(),
                },
                citations: false,
            }],
        };
        let body = build_body(&ChatRequest::new("claude-sonnet-4-6").push(msg), false);
        let src = &body["messages"][0]["content"][0]["source"];
        assert_eq!(src["type"], "file");
        assert_eq!(src["file_id"], "file_123");
    }

    #[test]
    fn document_citations_flag_maps_to_anthropic() {
        let msg = Message {
            role: Role::User,
            content: vec![ContentBlock::Document {
                source: MediaSource::File {
                    file_id: "file_9".into(),
                },
                citations: true,
            }],
        };
        let body = build_body(&ChatRequest::new("claude-sonnet-4-6").push(msg), false);
        assert_eq!(
            body["messages"][0]["content"][0]["citations"]["enabled"],
            true
        );
    }

    #[test]
    fn plain_text_document_maps_to_text_source_for_citations() {
        let msg = Message {
            role: Role::User,
            content: vec![ContentBlock::Document {
                source: MediaSource::PlainText {
                    text: "The sky is blue.".into(),
                },
                citations: true,
            }],
        };
        let body = build_body(&ChatRequest::new("claude-sonnet-4-6").push(msg), false);
        let src = &body["messages"][0]["content"][0]["source"];
        assert_eq!(src["type"], "text");
        assert_eq!(src["media_type"], "text/plain");
        assert_eq!(src["data"], "The sky is blue.");
        assert_eq!(
            body["messages"][0]["content"][0]["citations"]["enabled"],
            true
        );
    }

    #[test]
    fn count_tokens_body_omits_stream_and_max_tokens() {
        let mut req = ChatRequest::new("claude-sonnet-4-6")
            .system("rules")
            .push(Message::user("hi"));
        req.tools.push(ToolDef {
            name: "t".into(),
            description: "d".into(),
            schema: json!({"type": "object"}),
            cache: false,
            strict: false,
        });
        let body = build_count_body(&req);
        assert_eq!(body["model"], "claude-sonnet-4-6");
        assert_eq!(body["messages"][0]["role"], "user");
        assert_eq!(body["system"][0]["text"], "rules");
        assert_eq!(body["tools"][0]["name"], "t");
        // The count endpoint rejects these completion-only fields.
        assert!(body["stream"].is_null());
        assert!(body["max_tokens"].is_null());
    }

    #[test]
    fn thinking_off_and_low_add_no_block() {
        let mk = |level: Option<ThinkingLevel>| {
            let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
            req.thinking = level;
            build_body(&req, false)
        };
        assert!(mk(None)["thinking"].is_null());
        assert!(mk(Some(ThinkingLevel::Off))["thinking"].is_null());
        assert!(mk(Some(ThinkingLevel::Low))["thinking"].is_null());
    }

    #[test]
    fn modern_models_use_adaptive_thinking_plus_effort() {
        // Sonnet 4.6 / Opus 4.8 / Fable 5 must NOT use budget_tokens (it 400s on the flagships).
        for model in ["claude-sonnet-4-6", "claude-opus-4-8", "claude-fable-5"] {
            let mut req = ChatRequest::new(model).push(Message::user("hi"));
            req.thinking = Some(ThinkingLevel::High);
            let body = build_body(&req, false);
            assert_eq!(body["thinking"]["type"], "adaptive", "{model}");
            assert!(body["thinking"]["budget_tokens"].is_null(), "{model}");
            assert_eq!(body["output_config"]["effort"], "high", "{model}");
        }
        // Effort tracks the level (Medium → "medium").
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
        req.thinking = Some(ThinkingLevel::Medium);
        assert_eq!(build_body(&req, false)["output_config"]["effort"], "medium");
    }

    #[test]
    fn legacy_models_use_fixed_budget_thinking() {
        // Haiku 4.5 / Sonnet 4.5 etc. use budget_tokens (adaptive/effort unsupported there).
        let mut req = ChatRequest::new("claude-haiku-4-5").push(Message::user("hi"));
        req.thinking = Some(ThinkingLevel::High);
        req.max_tokens = 4096;
        let body = build_body(&req, false);
        assert_eq!(body["thinking"]["type"], "enabled");
        assert_eq!(body["thinking"]["budget_tokens"], 12000);
        assert!(body["max_tokens"].as_u64().unwrap() > 12000);
    }

    #[test]
    fn flagship_models_drop_sampling_params() {
        // temperature/top_p/top_k 400 on Opus 4.7/4.8 + Fable — must be stripped.
        let mut req = ChatRequest::new("claude-opus-4-8").push(Message::user("hi"));
        req.temperature = Some(0.7);
        req.top_p = Some(0.9);
        req.top_k = Some(40);
        let body = build_body(&req, false);
        assert!(body["temperature"].is_null());
        assert!(body["top_p"].is_null());
        assert!(body["top_k"].is_null());
        // Sonnet 4.6 still accepts them.
        let mut s = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
        s.temperature = Some(0.5);
        assert!(!build_body(&s, false)["temperature"].is_null());
    }

    #[test]
    fn thinking_drops_temperature() {
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
        req.thinking = Some(ThinkingLevel::High);
        req.temperature = Some(0.7);
        let body = build_body(&req, false);
        assert!(
            body["temperature"].is_null(),
            "temperature must be dropped when thinking is enabled"
        );
    }

    #[test]
    fn extended_ttl_marks_only_the_immutable_prefix() {
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message {
            role: Role::User,
            content: vec![
                ContentBlock::Text {
                    text: "skeleton".into(),
                    cache: true,
                },
                ContentBlock::text("volatile tail"),
            ],
        });
        req.system = Some(SystemPrompt {
            text: "rules".into(),
            cache: true,
        });
        let body = build_body(&req, true);
        // System + skeleton (immutable prefix) get the 1h TTL...
        assert_eq!(body["system"][0]["cache_control"]["ttl"], "1h");
        assert_eq!(
            body["messages"][0]["content"][0]["cache_control"]["ttl"],
            "1h"
        );
        // ...but the rolling conversation tail stays at the default (5-minute) TTL.
        let tail = &body["messages"][0]["content"][1]["cache_control"];
        assert_eq!(tail["type"], "ephemeral");
        assert!(
            tail["ttl"].is_null(),
            "the volatile tail must not use the 1h TTL"
        );
    }
}
