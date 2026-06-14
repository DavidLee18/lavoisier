//! Google **Gemini** provider for Lavoisier.
//!
//! Implements [`Provider`] over the native Generative Language API
//! (`POST /v1beta/models/{model}:streamGenerateContent?alt=sse`). Added so Lavoisier can run the
//! *same* model other agents benchmark on (`gemini-3-flash-preview`) with the *same* thinking
//! effort — see `bench/README.md`. This widens the original "Anthropic + xAI native only" scope
//! at the project owner's explicit request (recorded in `RECIPE.md` §1 / `CLAUDE.md`).
//!
//! Like the other adapters this is a thin hand-rolled `reqwest` client — no `google-*` SDK — and it
//! is the only place Gemini's wire format is mapped to the normalised [`Event`] stream. Gemini does
//! its own (implicit) prompt caching server-side, so we advertise `prompt_caching = false` (we emit
//! no request-side cache markers) while still surfacing `cachedContentTokenCount` as `cache_read`.
//!
//! **Thinking effort** is configurable (`thinkingConfig`): a keyword level (`low`/`high`/`dynamic`,
//! Gemini 3) or a numeric token budget (Gemini 2.5) — set via [`GoogleProvider::with_thinking`] or
//! `GOOGLE_THINKING` / the CLI `--thinking` flag. "High" matches the public Dirac refactor suite.

mod sse;

use std::collections::{HashMap, VecDeque};

use async_trait::async_trait;
use bytes::Bytes;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{
    Capabilities, ChatRequest, ContentBlock, Event, MediaSource, Message, OutputFormat, Provider,
    ProviderError, Role, ServerTool, ThinkingLevel, ToolChoice,
};
use serde_json::{json, Value};

use crate::sse::GeminiSseDecoder;

const DEFAULT_BASE_URL: &str = "https://generativelanguage.googleapis.com";

/// A Gemini content-safety harm category (`safetySettings[].category`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HarmCategory {
    Harassment,
    HateSpeech,
    SexuallyExplicit,
    DangerousContent,
    CivicIntegrity,
}

impl HarmCategory {
    fn as_api(self) -> &'static str {
        match self {
            HarmCategory::Harassment => "HARM_CATEGORY_HARASSMENT",
            HarmCategory::HateSpeech => "HARM_CATEGORY_HATE_SPEECH",
            HarmCategory::SexuallyExplicit => "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            HarmCategory::DangerousContent => "HARM_CATEGORY_DANGEROUS_CONTENT",
            HarmCategory::CivicIntegrity => "HARM_CATEGORY_CIVIC_INTEGRITY",
        }
    }
}

/// The blocking threshold for a [`HarmCategory`] (`safetySettings[].threshold`). Ordered from
/// strictest to most permissive; `Off` disables the filter entirely (use deliberately).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HarmBlockThreshold {
    /// Block low-probability-and-above harmful content (strictest).
    BlockLowAndAbove,
    BlockMediumAndAbove,
    BlockOnlyHigh,
    /// Block nothing (the filter still scores but never blocks).
    BlockNone,
    /// Disable the safety filter for this category.
    Off,
}

impl HarmBlockThreshold {
    fn as_api(self) -> &'static str {
        match self {
            HarmBlockThreshold::BlockLowAndAbove => "BLOCK_LOW_AND_ABOVE",
            HarmBlockThreshold::BlockMediumAndAbove => "BLOCK_MEDIUM_AND_ABOVE",
            HarmBlockThreshold::BlockOnlyHigh => "BLOCK_ONLY_HIGH",
            HarmBlockThreshold::BlockNone => "BLOCK_NONE",
            HarmBlockThreshold::Off => "OFF",
        }
    }
}

/// One configurable Gemini safety filter: a category and its blocking threshold.
#[derive(Debug, Clone, Copy)]
pub struct SafetySetting {
    pub category: HarmCategory,
    pub threshold: HarmBlockThreshold,
}

/// Render safety settings to the Gemini `safetySettings` array.
fn safety_settings_json(settings: &[SafetySetting]) -> Value {
    json!(settings
        .iter()
        .map(|s| json!({ "category": s.category.as_api(), "threshold": s.threshold.as_api() }))
        .collect::<Vec<_>>())
}

/// A [`Provider`] backed by the native Gemini Generative Language API.
pub struct GoogleProvider {
    api_key: String,
    base_url: String,
    /// Optional thinking effort: a keyword level (`low`/`high`/`dynamic`) or a numeric budget.
    thinking: Option<String>,
    /// Optional explicit `cachedContents/...` name to reference on every request (see
    /// [`create_cached_content`](Self::create_cached_content)). Pins a large reused prefix
    /// (e.g. a repo skeleton) at Gemini's cache-read rate.
    cached_content: Option<String>,
    /// Optional content-safety overrides (`safetySettings`). Empty = Gemini's defaults.
    safety_settings: Vec<SafetySetting>,
    http: reqwest::Client,
}

impl GoogleProvider {
    /// Construct against the default base URL.
    pub fn new(api_key: impl Into<String>) -> Self {
        Self::with_base_url(api_key, DEFAULT_BASE_URL)
    }

    /// Construct against an explicit base URL (e.g. a proxy or a mock server in tests).
    pub fn with_base_url(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            base_url: base_url.into(),
            thinking: None,
            cached_content: None,
            safety_settings: Vec::new(),
            http: reqwest::Client::new(),
        }
    }

    /// Set explicit Gemini content-safety thresholds. Empty leaves Gemini's defaults in place;
    /// callers must opt in deliberately (e.g. relaxing a category for a security-research workload).
    pub fn with_safety_settings(mut self, settings: Vec<SafetySetting>) -> Self {
        self.safety_settings = settings;
        self
    }

    /// Reference an explicit `cachedContents/...` resource on every request (created via
    /// [`create_cached_content`](Self::create_cached_content)).
    pub fn with_cached_content(mut self, name: impl Into<String>) -> Self {
        let n = name.into();
        self.cached_content = (!n.is_empty()).then_some(n);
        self
    }

    /// Set the thinking effort — a level keyword (`low`/`high`/`dynamic`) or a numeric token budget.
    pub fn with_thinking(mut self, thinking: impl Into<String>) -> Self {
        let t = thinking.into();
        self.thinking = (!t.is_empty()).then_some(t);
        self
    }

    /// Construct from `GOOGLE_API_KEY` (or `GEMINI_API_KEY`), `GOOGLE_BASE_URL` (optional), and
    /// `GOOGLE_THINKING` (optional thinking level/budget).
    pub fn from_env() -> Result<Self, ProviderError> {
        let api_key = std::env::var("GOOGLE_API_KEY")
            .or_else(|_| std::env::var("GEMINI_API_KEY"))
            .map_err(|_| {
                ProviderError::Config("GOOGLE_API_KEY (or GEMINI_API_KEY) is not set".into())
            })?;
        let base_url = std::env::var("GOOGLE_BASE_URL").unwrap_or_else(|_| DEFAULT_BASE_URL.into());
        let mut provider = Self::with_base_url(api_key, base_url);
        if let Ok(thinking) = std::env::var("GOOGLE_THINKING") {
            provider = provider.with_thinking(thinking);
        }
        Ok(provider)
    }

    /// Create an explicit cached-content resource over a fixed prefix (system + contents) for
    /// `model`, returning its `cachedContents/...` name. Pass that to [`with_cached_content`]
    /// (Self::with_cached_content) so a large reused prefix (e.g. a repo skeleton) bills at the
    /// cache-read rate. `ttl_seconds` sets the cache lifetime.
    pub async fn create_cached_content(
        &self,
        model: &str,
        system: Option<&str>,
        contents: &[Message],
        ttl_seconds: u64,
    ) -> Result<String, ProviderError> {
        let mut body = json!({
            "model": format!("models/{model}"),
            "contents": build_contents(contents),
            "ttl": format!("{ttl_seconds}s"),
        });
        if let Some(s) = system {
            body["systemInstruction"] = json!({ "parts": [ { "text": s } ] });
        }
        let url = format!(
            "{}/v1beta/cachedContents",
            self.base_url.trim_end_matches('/')
        );
        let resp = self
            .http
            .post(url)
            .header("x-goog-api-key", &self.api_key)
            .json(&body)
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
        v["name"]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| ProviderError::Decode("cachedContents response missing name".into()))
    }

    /// Upload a file to the Gemini **Files API** (resumable two-step), returning its `fileUri`.
    /// Pass that uri as a [`MediaSource::File`] `file_id` in a later request's
    /// [`ContentBlock::Image`]/[`ContentBlock::Document`] — the adapter renders it as `fileData`.
    /// Large media may still be `PROCESSING` server-side immediately after upload.
    pub async fn upload_file(
        &self,
        display_name: &str,
        bytes: Vec<u8>,
        mime: &str,
    ) -> Result<String, ProviderError> {
        // Step 1 — start a resumable session; the upload URL comes back in a response header.
        let start_url = format!(
            "{}/upload/v1beta/files",
            self.base_url.trim_end_matches('/')
        );
        let start = self
            .http
            .post(start_url)
            .header("x-goog-api-key", &self.api_key)
            .header("X-Goog-Upload-Protocol", "resumable")
            .header("X-Goog-Upload-Command", "start")
            .header("X-Goog-Upload-Header-Content-Length", bytes.len())
            .header("X-Goog-Upload-Header-Content-Type", mime)
            .json(&json!({ "file": { "display_name": display_name } }))
            .send()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;
        if !start.status().is_success() {
            return Err(ProviderError::Api {
                status: start.status().as_u16(),
                message: start.text().await.unwrap_or_default(),
            });
        }
        let upload_url = start
            .headers()
            .get("x-goog-upload-url")
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| {
                ProviderError::Decode("Files upload start missing x-goog-upload-url header".into())
            })?
            .to_string();

        // Step 2 — upload the bytes and finalize in one command.
        let len = bytes.len();
        let resp = self
            .http
            .post(upload_url)
            .header("Content-Length", len)
            .header("X-Goog-Upload-Offset", "0")
            .header("X-Goog-Upload-Command", "upload, finalize")
            .body(bytes)
            .send()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;
        if !resp.status().is_success() {
            return Err(ProviderError::Api {
                status: resp.status().as_u16(),
                message: resp.text().await.unwrap_or_default(),
            });
        }
        let v: Value = resp
            .json()
            .await
            .map_err(|e| ProviderError::Decode(e.to_string()))?;
        v["file"]["uri"]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| ProviderError::Decode("Files upload response missing file.uri".into()))
    }
}

#[async_trait]
impl Provider for GoogleProvider {
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        let mut body = build_body(
            &req,
            self.thinking.as_deref(),
            self.cached_content.as_deref(),
        );
        if !self.safety_settings.is_empty() {
            body["safetySettings"] = safety_settings_json(&self.safety_settings);
        }
        let url = format!(
            "{}/v1beta/models/{}:streamGenerateContent?alt=sse",
            self.base_url.trim_end_matches('/'),
            req.model,
        );

        // Send with bounded exponential backoff on transient throttling. The Generative Language
        // API rate-limits per minute, and the agent issues many calls in quick succession, so a
        // burst hits 429 (RESOURCE_EXHAUSTED) even when the key is healthy; 503 (overloaded) is the
        // other transient case. We retry those (the request is idempotent — nothing was generated)
        // and surface every other status immediately. Tunable via GOOGLE_MAX_RETRIES (default 6).
        let max_retries: u32 = std::env::var("GOOGLE_MAX_RETRIES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(6);
        let mut attempt: u32 = 0;
        let resp = loop {
            let resp = self
                .http
                .post(&url)
                .header("x-goog-api-key", &self.api_key)
                .json(&body)
                .send()
                .await
                .map_err(|e| ProviderError::Transport(e.to_string()))?;

            let status = resp.status();
            if status.is_success() {
                break resp;
            }
            let retryable = status.as_u16() == 429 || status.as_u16() == 503;
            if retryable && attempt < max_retries {
                // 2s, 4s, 8s … capped at 32s — long enough to refill a per-minute window.
                let backoff =
                    std::time::Duration::from_secs(2u64.saturating_pow(attempt + 1).min(32));
                attempt += 1;
                tokio::time::sleep(backoff).await;
                continue;
            }
            let message = resp.text().await.unwrap_or_default();
            return Err(ProviderError::Api {
                status: status.as_u16(),
                message,
            });
        };

        let state = SseState {
            body: resp.bytes_stream().boxed(),
            decoder: GeminiSseDecoder::default(),
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
            // Gemini caches implicitly server-side; we emit no request-side cache markers (cache
            // hits still surface as `cache_read` in usage), so we don't advertise prompt_caching.
            prompt_caching: false,
            extended_thinking: true,
            parallel_tool_use: true,
            server_side_tools: false,
            vision: true,
        }
    }
}

struct SseState {
    body: BoxStream<'static, reqwest::Result<Bytes>>,
    decoder: GeminiSseDecoder,
    pending: VecDeque<Result<Event, ProviderError>>,
    drained: bool,
}

/// Build the `generateContent` request body from a normalised [`ChatRequest`]. The model id lives
/// in the URL path, not the body.
fn build_body(req: &ChatRequest, thinking: Option<&str>, cached_content: Option<&str>) -> Value {
    let mut body = json!({ "contents": build_contents(&req.messages) });
    if let Some(name) = cached_content {
        body["cachedContent"] = json!(name);
    }

    if let Some(system) = &req.system {
        body["systemInstruction"] = json!({ "parts": [ { "text": system.text } ] });
    }
    // Tools entry: custom function declarations + provider-executed server tools
    // (WebSearch → Google Search grounding, CodeExecution → the code-execution tool).
    let mut tools: Vec<Value> = Vec::new();
    if !req.tools.is_empty() {
        let decls: Vec<Value> = req
            .tools
            .iter()
            .map(|t| {
                json!({
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.schema,
                })
            })
            .collect();
        tools.push(json!({ "functionDeclarations": decls }));
    }
    for st in &req.server_tools {
        match st {
            ServerTool::WebSearch { .. } => tools.push(json!({ "googleSearch": {} })),
            ServerTool::CodeExecution => tools.push(json!({ "codeExecution": {} })),
            ServerTool::WebFetch { .. } => {} // no direct Gemini equivalent
            // xAI-specific provider tools — no Gemini equivalent.
            ServerTool::XSearch { .. } | ServerTool::CollectionsSearch { .. } => {}
        }
    }
    if !tools.is_empty() {
        body["tools"] = json!(tools);
    }
    // Tool choice → functionCallingConfig.mode (+ allowedFunctionNames for a forced tool).
    if let Some(tc) = req.tool_choice.as_ref() {
        let fcc = match tc {
            ToolChoice::Auto => json!({ "mode": "AUTO" }),
            ToolChoice::Required => json!({ "mode": "ANY" }),
            ToolChoice::None => json!({ "mode": "NONE" }),
            ToolChoice::Tool(name) => json!({ "mode": "ANY", "allowedFunctionNames": [name] }),
        };
        body["toolConfig"] = json!({ "functionCallingConfig": fcc });
    }

    let mut generation = json!({ "maxOutputTokens": req.max_tokens });
    if let Some(t) = req.temperature {
        generation["temperature"] = json!(t);
    }
    if let Some(p) = req.top_p {
        generation["topP"] = json!(p);
    }
    if let Some(k) = req.top_k {
        generation["topK"] = json!(k);
    }
    if !req.stop_sequences.is_empty() {
        generation["stopSequences"] = json!(req.stop_sequences);
    }
    // Structured output: JSON mode + response schema (Gemini ignores unsupported schema keywords).
    if let Some(OutputFormat::JsonSchema { schema }) = req.output_format.as_ref() {
        generation["responseMimeType"] = json!("application/json");
        generation["responseSchema"] = schema.clone();
    }
    // A per-request normalised level (set by the agent's per-archetype default / tuner /
    // --thinking-budget) takes precedence over the construction-time `--thinking` fallback.
    if let Some(cfg) = req
        .thinking
        .map(thinking_level_config)
        .or_else(|| thinking.map(thinking_str_config))
    {
        generation["thinkingConfig"] = cfg;
    }
    body["generationConfig"] = generation;

    body
}

/// Map a normalised [`ThinkingLevel`] to Gemini's `thinkingConfig`. `Off` disables thinking
/// (`thinkingBudget: 0`); `Low`/`Medium`/`High` map to Gemini 3 effort levels (which are `low`/
/// `high`, so `Medium` and `High` both request `high`).
fn thinking_level_config(level: ThinkingLevel) -> Value {
    match level {
        ThinkingLevel::Off => json!({ "thinkingBudget": 0 }),
        ThinkingLevel::Low => json!({ "thinkingLevel": "low" }),
        ThinkingLevel::Medium | ThinkingLevel::High => json!({ "thinkingLevel": "high" }),
    }
}

/// Map the construction-time `--thinking` string: a bare integer is a token budget (Gemini 2.5);
/// anything else is a level keyword (Gemini 3, e.g. `low`/`high`/`dynamic`).
fn thinking_str_config(thinking: &str) -> Value {
    match thinking.parse::<i64>() {
        Ok(budget) => json!({ "thinkingBudget": budget }),
        Err(_) => json!({ "thinkingLevel": thinking }),
    }
}

/// Map the conversation to Gemini `contents`. Tool results carry only a `tool_use_id`, but Gemini
/// keys `functionResponse` by name, so we first index every assistant tool call's id → name.
fn build_contents(messages: &[Message]) -> Value {
    let mut id_to_name: HashMap<&str, &str> = HashMap::new();
    for m in messages {
        for block in &m.content {
            if let ContentBlock::ToolUse { id, name, .. } = block {
                id_to_name.insert(id, name);
            }
        }
    }

    let contents: Vec<Value> = messages
        .iter()
        .map(|m| {
            let role = match m.role {
                Role::User => "user",
                Role::Assistant => "model",
            };
            let parts: Vec<Value> = m
                .content
                .iter()
                .map(|b| content_part(b, &id_to_name))
                .collect();
            json!({ "role": role, "parts": parts })
        })
        .collect();
    Value::Array(contents)
}

/// Map a normalised media source onto a Gemini data part (`inlineData` / `fileData`).
fn gemini_media_part(source: &MediaSource) -> Value {
    match source {
        MediaSource::Base64 { media_type, data } => {
            json!({ "inlineData": { "mimeType": media_type, "data": data } })
        }
        MediaSource::Url { url } => json!({ "fileData": { "fileUri": url } }),
        // Gemini references uploaded files by URI; treat a file id as the file URI.
        MediaSource::File { file_id } => json!({ "fileData": { "fileUri": file_id } }),
    }
}

fn content_part(block: &ContentBlock, id_to_name: &HashMap<&str, &str>) -> Value {
    match block {
        ContentBlock::Text { text, .. } => json!({ "text": text }),
        // Gemini has no inbound "thinking" part; echo it as text (rare on the outbound path).
        ContentBlock::Thinking { text } => json!({ "text": text }),
        // Images and documents (PDF) both map to a Gemini data part: inlineData for base64,
        // fileData for a URL. Gemini accepts a PDF the same way as an image.
        ContentBlock::Image { source } | ContentBlock::Document { source, .. } => {
            gemini_media_part(source)
        }
        ContentBlock::ToolUse { id, name, input } => {
            let mut part = json!({ "functionCall": { "name": name, "args": input } });
            // Restore the `thoughtSignature` the decoder smuggled into the id (`call_{n}#{sig}`),
            // required by Gemini 3 thinking when a call is resent. Absent for non-thinking turns.
            if let Some((_, sig)) = id.split_once('#') {
                part["thoughtSignature"] = json!(sig);
            }
            part
        }
        ContentBlock::ToolResult {
            tool_use_id,
            content,
            is_error,
        } => {
            let name = id_to_name.get(tool_use_id.as_str()).copied().unwrap_or("");
            let response = if *is_error {
                json!({ "error": content })
            } else {
                json!({ "result": content })
            };
            json!({ "functionResponse": { "name": name, "response": response } })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{SystemPrompt, ToolDef};

    fn req() -> ChatRequest {
        let mut r = ChatRequest::new("gemini-3-flash-preview")
            .max_tokens(256)
            .push(Message::user("hi"));
        r.system = Some(SystemPrompt {
            text: "be terse".into(),
            cache: false,
        });
        r.tools.push(ToolDef {
            name: "read_file".into(),
            description: "read a file".into(),
            schema: json!({ "type": "object", "properties": { "path": { "type": "string" } } }),
            cache: false,
            strict: false,
        });
        r
    }

    #[test]
    fn maps_system_tools_and_generation_config() {
        let body = build_body(&req(), Some("high"), None);
        assert_eq!(body["systemInstruction"]["parts"][0]["text"], "be terse");
        assert_eq!(
            body["tools"][0]["functionDeclarations"][0]["name"],
            "read_file"
        );
        assert_eq!(body["generationConfig"]["maxOutputTokens"], 256);
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "high"
        );
        assert_eq!(body["contents"][0]["role"], "user");
        assert_eq!(body["contents"][0]["parts"][0]["text"], "hi");
    }

    #[test]
    fn per_request_thinking_level_overrides_the_construction_fallback() {
        let mut r = req();
        r.thinking = Some(ThinkingLevel::Low);
        // Construction fallback says "high", but the per-request Low must win.
        let body = build_body(&r, Some("high"), None);
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "low"
        );
        // Off disables thinking outright.
        r.thinking = Some(ThinkingLevel::Off);
        let body = build_body(&r, Some("high"), None);
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingBudget"],
            0
        );
    }

    #[test]
    fn common_request_params_map_to_gemini_shape() {
        let mut r = req();
        r.tool_choice = Some(ToolChoice::Tool("read_file".into()));
        r.top_p = Some(0.8);
        r.top_k = Some(20);
        r.stop_sequences = vec!["END".into()];
        r.output_format = Some(OutputFormat::JsonSchema {
            schema: json!({"type": "object"}),
        });
        let body = build_body(&r, None, None);
        let fcc = &body["toolConfig"]["functionCallingConfig"];
        assert_eq!(fcc["mode"], "ANY");
        assert_eq!(fcc["allowedFunctionNames"][0], "read_file");
        let g = &body["generationConfig"];
        assert!((g["topP"].as_f64().unwrap() - 0.8).abs() < 1e-4);
        assert_eq!(g["topK"], 20);
        assert_eq!(g["stopSequences"][0], "END");
        assert_eq!(g["responseMimeType"], "application/json");
        assert_eq!(g["responseSchema"]["type"], "object");
    }

    #[test]
    fn safety_settings_render_category_and_threshold() {
        let json = safety_settings_json(&[
            SafetySetting {
                category: HarmCategory::DangerousContent,
                threshold: HarmBlockThreshold::BlockOnlyHigh,
            },
            SafetySetting {
                category: HarmCategory::Harassment,
                threshold: HarmBlockThreshold::Off,
            },
        ]);
        let arr = json.as_array().unwrap();
        assert_eq!(arr[0]["category"], "HARM_CATEGORY_DANGEROUS_CONTENT");
        assert_eq!(arr[0]["threshold"], "BLOCK_ONLY_HIGH");
        assert_eq!(arr[1]["category"], "HARM_CATEGORY_HARASSMENT");
        assert_eq!(arr[1]["threshold"], "OFF");
    }

    #[test]
    fn server_tools_and_cached_content_map_to_gemini() {
        let mut r = req();
        r.server_tools = vec![
            ServerTool::WebSearch {
                max_uses: None,
                allowed_domains: vec![],
                blocked_domains: vec![],
            },
            ServerTool::CodeExecution,
        ];
        let body = build_body(&r, None, Some("cachedContents/abc"));
        let tools = body["tools"].as_array().unwrap();
        assert!(tools.iter().any(|t| t.get("googleSearch").is_some()));
        assert!(tools.iter().any(|t| t.get("codeExecution").is_some()));
        // The custom function declarations still ride alongside the server tools.
        assert!(tools
            .iter()
            .any(|t| t.get("functionDeclarations").is_some()));
        assert_eq!(body["cachedContent"], "cachedContents/abc");
    }

    #[test]
    fn numeric_thinking_is_a_budget_not_a_level() {
        let body = build_body(&req(), Some("2048"), None);
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingBudget"],
            2048
        );
        assert!(body["generationConfig"]["thinkingConfig"]["thinkingLevel"].is_null());
    }

    #[test]
    fn tool_use_and_result_round_trip_to_function_call_and_response() {
        let messages = vec![
            Message::user("read it"),
            Message {
                role: Role::Assistant,
                content: vec![ContentBlock::ToolUse {
                    id: "call_0".into(),
                    name: "read_file".into(),
                    input: json!({ "path": "a.rs" }),
                }],
            },
            Message {
                role: Role::User,
                content: vec![ContentBlock::ToolResult {
                    tool_use_id: "call_0".into(),
                    content: "fn main() {}".into(),
                    is_error: false,
                }],
            },
        ];
        let contents = build_contents(&messages);
        assert_eq!(contents[1]["role"], "model");
        assert_eq!(contents[1]["parts"][0]["functionCall"]["name"], "read_file");
        assert_eq!(
            contents[1]["parts"][0]["functionCall"]["args"]["path"],
            "a.rs"
        );
        // The response is keyed back to the tool's *name*, resolved from the call id.
        assert_eq!(
            contents[2]["parts"][0]["functionResponse"]["name"],
            "read_file"
        );
        assert_eq!(
            contents[2]["parts"][0]["functionResponse"]["response"]["result"],
            "fn main() {}"
        );
    }

    #[test]
    fn thought_signature_smuggled_in_id_is_echoed_back_on_the_function_call() {
        let messages = vec![Message {
            role: Role::Assistant,
            content: vec![ContentBlock::ToolUse {
                id: "call_0#SIG123".into(),
                name: "shell".into(),
                input: json!({ "command": "ls" }),
            }],
        }];
        let contents = build_contents(&messages);
        let part = &contents[0]["parts"][0];
        assert_eq!(part["functionCall"]["name"], "shell");
        // The signature is restored to the part (Gemini 3 thinking requires it on resend); the
        // synthetic `#SIG` suffix never leaks into the functionCall itself.
        assert_eq!(part["thoughtSignature"], "SIG123");
        assert!(part["functionCall"]["name"].as_str() == Some("shell"));
    }
}
