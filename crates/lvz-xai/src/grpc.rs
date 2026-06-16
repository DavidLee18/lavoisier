//! The native xAI **gRPC** transport (§8): the primary path, generated from the
//! vendored `xai-proto` chat service.
//!
//! It opens a TLS [`Channel`](tonic::transport::Channel) to `api.x.ai`, calls the server-
//! streaming `Chat.GetCompletionChunk`, and normalises each [`pb::GetChatCompletionChunk`]
//! into the [`Event`] stream — text/reasoning deltas, streamed `tool_calls`, per-chunk
//! [`SamplingUsage`](pb::SamplingUsage) (cumulative; the agent takes last-wins), and a
//! terminal [`Event::Done`]. Auth is a per-request `authorization: Bearer <key>` metadata
//! header. This is the only place the xAI proto wire format is known.

use std::collections::VecDeque;

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{
    retry_transient, Capabilities, ChatRequest, ContentBlock, Event, MediaSource, Message,
    OutputFormat, Provider, ProviderError, Role, ServerTool, StopReason, ThinkingLevel, ToolChoice,
    Usage,
};
use tonic::transport::{ClientTlsConfig, Endpoint};

/// Generated xAI proto types (`package xai_api`). See `build.rs` and `proto/VENDOR.md`.
/// The full service surface is generated; we only consume the `Chat` streaming RPC, so the
/// rest is dead code by design.
#[allow(clippy::all, dead_code, rustdoc::all)]
pub mod pb {
    tonic::include_proto!("xai_api");
}

pub(crate) const DEFAULT_ENDPOINT: &str = "https://api.x.ai";

/// A [`Provider`] backed by xAI's native gRPC API.
pub struct GrpcTransport {
    api_key: String,
    endpoint: String,
}

impl GrpcTransport {
    /// Construct against the default endpoint (`https://api.x.ai`).
    pub fn new(api_key: impl Into<String>) -> Self {
        Self::with_endpoint(api_key, DEFAULT_ENDPOINT)
    }

    /// Construct against an explicit gRPC endpoint (e.g. a proxy or a local mock).
    pub fn with_endpoint(api_key: impl Into<String>, endpoint: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            endpoint: endpoint.into(),
        }
    }

    /// Open a TLS channel to the endpoint and return a ready `Chat` client.
    async fn connect(
        &self,
    ) -> Result<pb::chat_client::ChatClient<tonic::transport::Channel>, ProviderError> {
        let tls = ClientTlsConfig::new().with_webpki_roots();
        let channel = Endpoint::from_shared(self.endpoint.clone())
            .map_err(|e| ProviderError::Config(format!("invalid xAI gRPC endpoint: {e}")))?
            .tls_config(tls)
            .map_err(|e| ProviderError::Transport(e.to_string()))?
            .connect()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;
        Ok(pb::chat_client::ChatClient::new(channel))
    }

    /// Wrap a request message with the per-request `authorization: Bearer <key>` metadata.
    fn authed<T>(&self, msg: T) -> Result<tonic::Request<T>, ProviderError> {
        let mut request = tonic::Request::new(msg);
        let bearer: tonic::metadata::MetadataValue<_> = format!("Bearer {}", self.api_key)
            .parse()
            .map_err(|_| ProviderError::Config("xAI API key is not a valid header value".into()))?;
        request.metadata_mut().insert("authorization", bearer);
        Ok(request)
    }

    /// Start a **deferred** (async) completion: submit the request and immediately receive a
    /// `request_id` to poll with [`poll_deferred`](Self::poll_deferred). Best for long jobs where
    /// holding a stream open is impractical; xAI keeps the result available for a limited window.
    pub async fn start_deferred(&self, req: ChatRequest) -> Result<String, ProviderError> {
        let mut client = self.connect().await?;
        let resp = client
            .start_deferred_completion(self.authed(build_request(req))?)
            .await
            .map_err(status_to_err)?
            .into_inner();
        Ok(resp.request_id)
    }

    /// Poll a deferred completion by `request_id`. `Ok(None)` while still pending; `Ok(Some(events))`
    /// once done — the same normalised [`Event`] sequence the streaming path would yield. Errors if
    /// the job failed or its result has expired.
    pub async fn poll_deferred(
        &self,
        request_id: &str,
    ) -> Result<Option<Vec<Event>>, ProviderError> {
        let mut client = self.connect().await?;
        let resp = client
            .get_deferred_completion(self.authed(pb::GetDeferredRequest {
                request_id: request_id.to_string(),
            })?)
            .await
            .map_err(status_to_err)?
            .into_inner();
        match resp.status() {
            pb::DeferredStatus::Done => {
                let response = resp.response.ok_or_else(|| {
                    ProviderError::Decode("deferred completion DONE but no response payload".into())
                })?;
                Ok(Some(events_from_response(response)))
            }
            pb::DeferredStatus::Pending | pb::DeferredStatus::InvalidDeferredStatus => Ok(None),
            pb::DeferredStatus::Expired => Err(ProviderError::Api {
                status: 410,
                message: "deferred completion result expired".into(),
            }),
            pb::DeferredStatus::Failed => Err(ProviderError::Api {
                status: 500,
                message: "deferred completion failed".into(),
            }),
        }
    }
}

#[async_trait]
impl Provider for GrpcTransport {
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        let grpc_req = build_request(req);

        // Bounded exponential backoff on transient throttling (shared `retry_transient`): xAI returns
        // gRPC ResourceExhausted (→429) when rate-limited and Unavailable (→503) when overloaded;
        // `status_to_err` maps those onto the HTTP statuses the shared policy retries. The call is
        // idempotent (nothing is generated until the stream starts). Tunable via XAI_MAX_RETRIES.
        let max_retries: u32 = std::env::var("XAI_MAX_RETRIES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(6);
        let streaming = retry_transient(max_retries, || async {
            let mut client = self.connect().await?;
            let request = self.authed(grpc_req.clone())?;
            client
                .get_completion_chunk(request)
                .await
                .map_err(status_to_err)
                .map(|r| r.into_inner())
        })
        .await?;

        let state = GrpcState {
            streaming,
            decoder: Decoder::default(),
            finished: false,
        };

        let events = stream::unfold(state, |mut st| async move {
            loop {
                if let Some(ev) = st.decoder.pending.pop_front() {
                    return Some((ev, st));
                }
                if st.finished {
                    return None;
                }
                match st.streaming.message().await {
                    Ok(Some(chunk)) => st.decoder.chunk(chunk),
                    Ok(None) => {
                        st.decoder.finish();
                        st.finished = true;
                    }
                    Err(status) => {
                        st.decoder.pending.push_back(Err(status_to_err(status)));
                        st.finished = true;
                    }
                }
            }
        });

        Ok(events.boxed())
    }

    fn capabilities(&self) -> Capabilities {
        Capabilities {
            // xAI caches automatically server-side; we don't honour request-side cache markers.
            prompt_caching: false,
            extended_thinking: false,
            parallel_tool_use: true,
            // The native path exposes provider-executed tools (web/x search, code exec, …).
            server_side_tools: true,
            vision: true,
        }
    }
}

struct GrpcState {
    streaming: tonic::Streaming<pb::GetChatCompletionChunk>,
    decoder: Decoder,
    finished: bool,
}

// --- chunk decoding: xAI streamed outputs → normalised events ---

/// Accumulates streamed `GetChatCompletionChunk`s into normalised [`Event`]s. Tool calls
/// are correlated by id (xAI may stream a call's arguments across chunks, or whole); a
/// single terminal [`Event::Done`] is deferred until the stream ends.
#[derive(Default)]
struct Decoder {
    pending: VecDeque<Result<Event, ProviderError>>,
    /// Tool-call ids in first-seen order, so we can close them all at the end.
    seen_tools: Vec<String>,
    /// Last id seen, to attribute argument-only chunks that omit the id.
    last_tool_id: Option<String>,
    stop: Option<StopReason>,
    done_emitted: bool,
}

impl Decoder {
    fn chunk(&mut self, chunk: pb::GetChatCompletionChunk) {
        if let Some(usage) = &chunk.usage {
            self.pending.push_back(Ok(Event::Usage(usage_from(usage))));
        }
        for output in chunk.outputs {
            // REASON_INVALID is the proto3 default and means "not set" on a mid-stream chunk.
            let reason = output.finish_reason();
            if let Some(delta) = output.delta {
                if !delta.content.is_empty() {
                    self.pending.push_back(Ok(Event::TextDelta(delta.content)));
                }
                if !delta.reasoning_content.is_empty() {
                    self.pending
                        .push_back(Ok(Event::Thinking(delta.reasoning_content)));
                }
                for tc in delta.tool_calls {
                    self.handle_tool_call(tc);
                }
            }
            if reason != pb::FinishReason::ReasonInvalid {
                self.stop = Some(map_finish(reason));
            }
        }
    }

    fn handle_tool_call(&mut self, tc: pb::ToolCall) {
        let id = if !tc.id.is_empty() {
            tc.id.clone()
        } else {
            self.last_tool_id.clone().unwrap_or_default()
        };
        if id.is_empty() {
            return;
        }
        let (name, args) = match &tc.tool {
            Some(pb::tool_call::Tool::Function(f)) => (f.name.clone(), f.arguments.clone()),
            None => (String::new(), String::new()),
        };
        if !self.seen_tools.iter().any(|seen| seen == &id) {
            self.seen_tools.push(id.clone());
            self.pending.push_back(Ok(Event::ToolUseStart {
                id: id.clone(),
                name,
            }));
        }
        self.last_tool_id = Some(id.clone());
        if !args.is_empty() {
            self.pending
                .push_back(Ok(Event::ToolUseDelta { id, json: args }));
        }
    }

    /// Close every open tool call (in first-seen order), then emit the single `Done`.
    fn finish(&mut self) {
        if self.done_emitted {
            return;
        }
        for id in std::mem::take(&mut self.seen_tools) {
            self.pending.push_back(Ok(Event::ToolUseEnd { id }));
        }
        self.done_emitted = true;
        let stop = self.stop.take().unwrap_or(StopReason::EndTurn);
        self.pending.push_back(Ok(Event::Done(stop)));
    }
}

fn map_finish(reason: pb::FinishReason) -> StopReason {
    use pb::FinishReason::*;
    match reason {
        ReasonStop => StopReason::EndTurn,
        ReasonMaxLen | ReasonMaxContext => StopReason::MaxTokens,
        ReasonToolCalls => StopReason::ToolUse,
        ReasonTimeLimit => StopReason::Other("time_limit".into()),
        ReasonInvalid => StopReason::EndTurn,
    }
}

/// Map xAI's cumulative `SamplingUsage` onto [`Usage`]. xAI's `prompt_tokens` *includes*
/// cached text tokens, so the uncached input is `prompt_tokens - cached_prompt_text_tokens`,
/// keeping [`Usage::cache_hit_rate`] aligned with the Anthropic adapter's semantics. xAI
/// does not report cache *creation*, so that field stays zero.
fn usage_from(u: &pb::SamplingUsage) -> Usage {
    let cached = u.cached_prompt_text_tokens.max(0) as u64;
    let prompt = u.prompt_tokens.max(0) as u64;
    Usage {
        input_tokens: prompt.saturating_sub(cached),
        output_tokens: u.completion_tokens.max(0) as u64,
        cache_creation_tokens: 0,
        cache_read_tokens: cached,
    }
}

/// Normalise a non-streaming [`pb::GetChatCompletionResponse`] (as returned by a finished
/// deferred completion) into the same [`Event`] sequence the streaming decoder produces:
/// text/thinking, whole tool calls (start→delta→end), then usage and a terminal `Done`.
fn events_from_response(resp: pb::GetChatCompletionResponse) -> Vec<Event> {
    let mut events = Vec::new();
    let mut stop = StopReason::EndTurn;
    for output in resp.outputs {
        let reason = output.finish_reason();
        if reason != pb::FinishReason::ReasonInvalid {
            stop = map_finish(reason);
        }
        if let Some(msg) = output.message {
            if !msg.content.is_empty() {
                events.push(Event::TextDelta(msg.content));
            }
            if !msg.reasoning_content.is_empty() {
                events.push(Event::Thinking(msg.reasoning_content));
            }
            for tc in msg.tool_calls {
                if tc.id.is_empty() {
                    continue;
                }
                let (name, args) = match &tc.tool {
                    Some(pb::tool_call::Tool::Function(f)) => (f.name.clone(), f.arguments.clone()),
                    None => (String::new(), String::new()),
                };
                events.push(Event::ToolUseStart {
                    id: tc.id.clone(),
                    name,
                });
                if !args.is_empty() {
                    events.push(Event::ToolUseDelta {
                        id: tc.id.clone(),
                        json: args,
                    });
                }
                events.push(Event::ToolUseEnd { id: tc.id });
            }
        }
    }
    if let Some(usage) = &resp.usage {
        events.push(Event::Usage(usage_from(usage)));
    }
    events.push(Event::Done(stop));
    events
}

fn status_to_err(status: tonic::Status) -> ProviderError {
    // Map the two transient gRPC codes onto their HTTP equivalents so the shared retry policy
    // (`is_transient_status`) treats them uniformly with the HTTP provider paths; other codes keep
    // their raw gRPC value.
    let status_code = match status.code() {
        tonic::Code::ResourceExhausted => 429,
        tonic::Code::Unavailable => 503,
        other => other as u16,
    };
    ProviderError::Api {
        status: status_code,
        message: status.message().to_string(),
    }
}

// --- request building: normalised ChatRequest → xAI GetCompletionsRequest ---

fn build_request(req: ChatRequest) -> pb::GetCompletionsRequest {
    // Custom tools + any provider-executed server tools mapped to the proto `Tool` oneof.
    // (WebSearch is handled separately via `search_parameters`, below.)
    let mut tools = build_tools(&req);
    for st in &req.server_tools {
        match st {
            ServerTool::CodeExecution => {
                tools.push(grpc_tool(pb::tool::Tool::CodeExecution(
                    pb::CodeExecution {},
                )));
            }
            ServerTool::XSearch {
                allowed_handles,
                blocked_handles,
                from_date,
                to_date,
            } => {
                tools.push(grpc_tool(pb::tool::Tool::XSearch(pb::XSearch {
                    from_date: from_date.as_deref().and_then(iso_date_to_timestamp),
                    to_date: to_date.as_deref().and_then(iso_date_to_timestamp),
                    allowed_x_handles: allowed_handles.clone(),
                    excluded_x_handles: blocked_handles.clone(),
                    ..Default::default()
                })));
            }
            ServerTool::CollectionsSearch {
                collection_ids,
                limit,
            } => {
                tools.push(grpc_tool(pb::tool::Tool::CollectionsSearch(
                    pb::CollectionsSearch {
                        collection_ids: collection_ids.clone(),
                        limit: limit.map(|n| n as i32),
                        ..Default::default()
                    },
                )));
            }
            // WebSearch → search_parameters; WebFetch has no xAI equivalent.
            ServerTool::WebSearch { .. } | ServerTool::WebFetch { .. } => {}
        }
    }
    // MCP servers are a `Tool` variant on the xAI proto (Anthropic uses a top-level field).
    for mcp in &req.mcp_servers {
        tools.push(grpc_tool(pb::tool::Tool::Mcp(pb::Mcp {
            server_label: mcp.name.clone(),
            server_url: mcp.url.clone(),
            authorization: mcp.authorization_token.clone(),
            ..Default::default()
        })));
    }
    pb::GetCompletionsRequest {
        messages: build_messages(&req),
        model: req.model.clone(),
        max_tokens: Some(i32::try_from(req.max_tokens).unwrap_or(i32::MAX)),
        temperature: req.temperature,
        top_p: req.top_p,
        stop: req.stop_sequences.clone(),
        tools,
        tool_choice: req.tool_choice.as_ref().map(build_tool_choice),
        response_format: req.output_format.as_ref().map(|f| {
            let OutputFormat::JsonSchema { schema } = f;
            pb::ResponseFormat {
                format_type: pb::FormatType::JsonSchema as i32,
                schema: Some(schema.to_string()),
            }
        }),
        reasoning_effort: req.thinking.map(|t| reasoning_effort(t) as i32),
        // A WebSearch server tool enables xAI Live Search (model decides when to search), with the
        // requested domain allow/block lists and result cap mapped onto a web source.
        search_parameters: grpc_search_params(&req.server_tools),
        ..Default::default()
    }
}

/// Wrap a proto tool oneof in a [`pb::Tool`].
fn grpc_tool(t: pb::tool::Tool) -> pb::Tool {
    pb::Tool { tool: Some(t) }
}

/// Parse an ISO-8601 `YYYY-MM-DD` date into a UTC midnight [`prost_types::Timestamp`]. Returns
/// `None` on a malformed date (the field is then simply omitted).
fn iso_date_to_timestamp(s: &str) -> Option<prost_types::Timestamp> {
    let mut parts = s.split('-');
    let y: i64 = parts.next()?.parse().ok()?;
    let m: i64 = parts.next()?.parse().ok()?;
    let d: i64 = parts.next()?.parse().ok()?;
    if parts.next().is_some() || !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    Some(prost_types::Timestamp {
        seconds: days_from_civil(y, m, d) * 86_400,
        nanos: 0,
    })
}

/// Days since the Unix epoch for a civil date (Howard Hinnant's `days_from_civil`).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = (if y >= 0 { y } else { y - 399 }) / 400;
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Build xAI [`SearchParameters`](pb::SearchParameters) from a `WebSearch` server tool, if present.
fn grpc_search_params(server_tools: &[ServerTool]) -> Option<pb::SearchParameters> {
    let (max_uses, allowed, blocked) = server_tools.iter().find_map(|t| match t {
        ServerTool::WebSearch {
            max_uses,
            allowed_domains,
            blocked_domains,
        } => Some((max_uses, allowed_domains, blocked_domains)),
        _ => None,
    })?;
    let mut sp = pb::SearchParameters {
        mode: pb::SearchMode::AutoSearchMode as i32,
        max_search_results: max_uses.map(|n| n as i32),
        ..Default::default()
    };
    if !allowed.is_empty() || !blocked.is_empty() {
        sp.sources = vec![pb::Source {
            source: Some(pb::source::Source::Web(pb::WebSource {
                allowed_websites: allowed.clone(),
                excluded_websites: blocked.clone(),
                ..Default::default()
            })),
        }];
    }
    Some(sp)
}

/// Map the normalised tool choice onto the xAI proto `ToolChoice` oneof.
fn build_tool_choice(tc: &ToolChoice) -> pb::ToolChoice {
    use pb::tool_choice::ToolChoice as Oneof;
    let inner = match tc {
        ToolChoice::Auto => Oneof::Mode(pb::ToolMode::Auto as i32),
        ToolChoice::Required => Oneof::Mode(pb::ToolMode::Required as i32),
        ToolChoice::None => Oneof::Mode(pb::ToolMode::None as i32),
        ToolChoice::Tool(name) => Oneof::FunctionName(name.clone()),
    };
    pb::ToolChoice {
        tool_choice: Some(inner),
    }
}

/// Map the normalised thinking level onto the xAI proto `ReasoningEffort`.
fn reasoning_effort(level: ThinkingLevel) -> pb::ReasoningEffort {
    match level {
        ThinkingLevel::Off => pb::ReasoningEffort::EffortNone,
        ThinkingLevel::Low => pb::ReasoningEffort::EffortLow,
        ThinkingLevel::Medium => pb::ReasoningEffort::EffortMedium,
        ThinkingLevel::High => pb::ReasoningEffort::EffortHigh,
    }
}

fn text_content(text: String) -> pb::Content {
    pb::Content {
        content: Some(pb::content::Content::Text(text)),
    }
}

fn build_messages(req: &ChatRequest) -> Vec<pb::Message> {
    let mut out = Vec::new();
    if let Some(system) = &req.system {
        out.push(pb::Message {
            content: vec![text_content(system.text.clone())],
            role: pb::MessageRole::RoleSystem as i32,
            ..Default::default()
        });
    }
    for m in &req.messages {
        match m.role {
            Role::User => push_user(m, &mut out),
            Role::Assistant => out.push(build_assistant(m)),
        }
    }
    out
}

fn push_user(m: &Message, out: &mut Vec<pb::Message>) {
    let mut text = String::new();
    let mut media = Vec::new();
    let mut tool_results = Vec::new();
    for block in &m.content {
        match block {
            ContentBlock::Text { text: t, .. } | ContentBlock::Thinking { text: t } => {
                text.push_str(t)
            }
            ContentBlock::Image { source } => media.push(image_content(source)),
            ContentBlock::Document { source, .. } => media.extend(file_content(source)),
            ContentBlock::ToolResult {
                tool_use_id,
                content,
                ..
            } => tool_results.push(pb::Message {
                content: vec![text_content(content.clone())],
                role: pb::MessageRole::RoleTool as i32,
                tool_call_id: Some(tool_use_id.clone()),
                ..Default::default()
            }),
            ContentBlock::ToolUse { .. } => {} // not valid on a user turn
        }
    }
    // Tool results are their own ROLE_TOOL messages and precede any free-text follow-up.
    out.extend(tool_results);
    let mut content: Vec<pb::Content> = Vec::new();
    if !text.is_empty() {
        content.push(text_content(text));
    }
    content.extend(media);
    if !content.is_empty() {
        out.push(pb::Message {
            content,
            role: pb::MessageRole::RoleUser as i32,
            ..Default::default()
        });
    } else if m.content.is_empty() {
        out.push(pb::Message {
            content: vec![text_content(String::new())],
            role: pb::MessageRole::RoleUser as i32,
            ..Default::default()
        });
    }
}

/// An image content part. xAI's `image_url` accepts a URL or a base64 data-URL string; a
/// Files-API id maps to a `FileContent` attachment instead.
fn image_content(source: &MediaSource) -> pb::Content {
    match source {
        MediaSource::Url { url } => image_url_content(url.clone()),
        MediaSource::Base64 { media_type, data } => {
            image_url_content(format!("data:{media_type};base64,{data}"))
        }
        MediaSource::File { file_id } => pb::Content {
            content: Some(pb::content::Content::File(pb::FileContent {
                file_id: file_id.clone(),
                ..Default::default()
            })),
        },
        // No image semantics for inline text; pass it through as a text part.
        MediaSource::PlainText { text } => text_content(text.clone()),
    }
}

fn image_url_content(image_url: String) -> pb::Content {
    pb::Content {
        content: Some(pb::content::Content::ImageUrl(pb::ImageUrlContent {
            image_url,
            detail: pb::ImageDetail::DetailAuto as i32,
        })),
    }
}

/// A document/file content part. A URL → `FileContent.url`, a Files-API id → `FileContent.file_id`;
/// inline base64 is unsupported on the gRPC transport (it wants raw bytes), so it degrades to a note.
fn file_content(source: &MediaSource) -> Vec<pb::Content> {
    let fc = match source {
        MediaSource::Url { url } => pb::FileContent {
            url: url.clone(),
            ..Default::default()
        },
        MediaSource::File { file_id } => pb::FileContent {
            file_id: file_id.clone(),
            ..Default::default()
        },
        MediaSource::Base64 { .. } => {
            return vec![text_content(
                "[document omitted: send via URL or file id on the xAI gRPC transport]".into(),
            )]
        }
        // xAI has no document-citation source; inline plain text directly.
        MediaSource::PlainText { text } => return vec![text_content(text.clone())],
    };
    vec![pb::Content {
        content: Some(pb::content::Content::File(fc)),
    }]
}

fn build_assistant(m: &Message) -> pb::Message {
    let mut text = String::new();
    let mut tool_calls = Vec::new();
    for block in &m.content {
        match block {
            ContentBlock::Text { text: t, .. } => text.push_str(t),
            // Thinking is rehydrated server-side via encrypted_content, which we don't echo.
            ContentBlock::Thinking { .. } => {}
            // Images/documents are inputs, not assistant output — never re-sent on an assistant turn.
            ContentBlock::Image { .. } | ContentBlock::Document { .. } => {}
            ContentBlock::ToolUse { id, name, input } => tool_calls.push(pb::ToolCall {
                id: id.clone(),
                tool: Some(pb::tool_call::Tool::Function(pb::FunctionCall {
                    name: name.clone(),
                    arguments: input.to_string(),
                })),
                ..Default::default()
            }),
            ContentBlock::ToolResult { .. } => {}
        }
    }
    let content = if text.is_empty() {
        Vec::new()
    } else {
        vec![text_content(text)]
    };
    pb::Message {
        content,
        role: pb::MessageRole::RoleAssistant as i32,
        tool_calls,
        ..Default::default()
    }
}

fn build_tools(req: &ChatRequest) -> Vec<pb::Tool> {
    req.tools
        .iter()
        .map(|t| pb::Tool {
            tool: Some(pb::tool::Tool::Function(pb::Function {
                name: t.name.clone(),
                description: t.description.clone(),
                strict: false,
                // xAI takes the JSON Schema as a JSON-encoded string.
                parameters: t.schema.to_string(),
            })),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{Message, ToolDef};
    use serde_json::json;

    fn content_text(c: &pb::Content) -> &str {
        match &c.content {
            Some(pb::content::Content::Text(t)) => t,
            _ => "",
        }
    }

    fn drain(d: Decoder) -> Vec<Event> {
        d.pending.into_iter().map(|e| e.unwrap()).collect()
    }

    #[test]
    fn system_leads_user_follows_and_tools_are_function_shaped() {
        let mut req = ChatRequest::new("grok-4")
            .system("be terse")
            .push(Message::user("hi"));
        req.tools.push(ToolDef {
            name: "list_dir".into(),
            description: "list a dir".into(),
            schema: json!({ "type": "object" }),
            cache: false,
            strict: false,
        });

        let g = build_request(req);
        assert_eq!(g.model, "grok-4");
        assert_eq!(g.max_tokens, Some(1024));
        assert_eq!(g.messages[0].role, pb::MessageRole::RoleSystem as i32);
        assert_eq!(content_text(&g.messages[0].content[0]), "be terse");
        assert_eq!(g.messages[1].role, pb::MessageRole::RoleUser as i32);
        assert_eq!(content_text(&g.messages[1].content[0]), "hi");

        let Some(pb::tool::Tool::Function(f)) = &g.tools[0].tool else {
            panic!("expected a function tool");
        };
        assert_eq!(f.name, "list_dir");
        assert!(f.parameters.contains("object"));
    }

    #[test]
    fn server_tools_enable_live_search_and_code_execution() {
        let mut req = ChatRequest::new("grok-4").push(Message::user("hi"));
        req.server_tools = vec![
            ServerTool::WebSearch {
                max_uses: Some(5),
                allowed_domains: vec!["docs.rs".into()],
                blocked_domains: vec![],
            },
            ServerTool::CodeExecution,
        ];
        let g = build_request(req);
        // WebSearch → Live Search (AUTO mode) with the cap + allowed-domain web source.
        let sp = g.search_parameters.unwrap();
        assert_eq!(sp.mode, pb::SearchMode::AutoSearchMode as i32);
        assert_eq!(sp.max_search_results, Some(5));
        let Some(pb::source::Source::Web(web)) = &sp.sources[0].source else {
            panic!("expected a web source");
        };
        assert_eq!(web.allowed_websites, vec!["docs.rs".to_string()]);
        // CodeExecution → a built-in code-execution tool entry.
        assert!(g
            .tools
            .iter()
            .any(|t| matches!(&t.tool, Some(pb::tool::Tool::CodeExecution(_)))));
    }

    #[test]
    fn tool_use_and_result_map_to_xai_shape() {
        let assistant = Message {
            role: Role::Assistant,
            content: vec![ContentBlock::ToolUse {
                id: "call_1".into(),
                name: "shell".into(),
                input: json!({ "command": "ls" }),
            }],
        };
        let result = Message {
            role: Role::User,
            content: vec![ContentBlock::ToolResult {
                tool_use_id: "call_1".into(),
                content: "files".into(),
                is_error: false,
            }],
        };
        let req = ChatRequest::new("grok-4")
            .push(Message::user("go"))
            .push(assistant)
            .push(result);
        let g = build_request(req);

        // user("go"), assistant(tool_calls), tool(result)
        let asst = &g.messages[1];
        assert_eq!(asst.role, pb::MessageRole::RoleAssistant as i32);
        let tc = &asst.tool_calls[0];
        assert_eq!(tc.id, "call_1");
        let Some(pb::tool_call::Tool::Function(f)) = &tc.tool else {
            panic!("expected a function call");
        };
        assert_eq!(f.name, "shell");

        let tool = &g.messages[2];
        assert_eq!(tool.role, pb::MessageRole::RoleTool as i32);
        assert_eq!(tool.tool_call_id.as_deref(), Some("call_1"));
        assert_eq!(content_text(&tool.content[0]), "files");
    }

    #[test]
    fn usage_splits_cached_from_uncached_input() {
        let u = usage_from(&pb::SamplingUsage {
            prompt_tokens: 10,
            completion_tokens: 4,
            cached_prompt_text_tokens: 4,
            ..Default::default()
        });
        assert_eq!(u.input_tokens, 6);
        assert_eq!(u.cache_read_tokens, 4);
        assert_eq!(u.output_tokens, 4);
        assert_eq!(u.cache_creation_tokens, 0);
    }

    #[test]
    fn decodes_text_thinking_usage_then_done() {
        let mut d = Decoder::default();
        d.chunk(pb::GetChatCompletionChunk {
            outputs: vec![pb::CompletionOutputChunk {
                delta: Some(pb::Delta {
                    content: "Hi".into(),
                    reasoning_content: "ponder".into(),
                    ..Default::default()
                }),
                finish_reason: pb::FinishReason::ReasonStop as i32,
                ..Default::default()
            }],
            usage: Some(pb::SamplingUsage {
                prompt_tokens: 5,
                completion_tokens: 2,
                ..Default::default()
            }),
            ..Default::default()
        });
        d.finish();
        let events = drain(d);
        assert!(
            matches!(events[0], Event::Usage(u) if u.input_tokens == 5 && u.output_tokens == 2)
        );
        assert_eq!(events[1], Event::TextDelta("Hi".into()));
        assert_eq!(events[2], Event::Thinking("ponder".into()));
        assert_eq!(events[3], Event::Done(StopReason::EndTurn));
        assert_eq!(events.len(), 4);
    }

    #[test]
    fn decodes_a_streamed_tool_call() {
        let mut d = Decoder::default();
        d.chunk(pb::GetChatCompletionChunk {
            outputs: vec![pb::CompletionOutputChunk {
                delta: Some(pb::Delta {
                    tool_calls: vec![pb::ToolCall {
                        id: "call_9".into(),
                        tool: Some(pb::tool_call::Tool::Function(pb::FunctionCall {
                            name: "list_dir".into(),
                            arguments: "{\"path\":\".\"}".into(),
                        })),
                        ..Default::default()
                    }],
                    ..Default::default()
                }),
                finish_reason: pb::FinishReason::ReasonToolCalls as i32,
                ..Default::default()
            }],
            ..Default::default()
        });
        d.finish();
        let events = drain(d);
        assert_eq!(
            events[0],
            Event::ToolUseStart {
                id: "call_9".into(),
                name: "list_dir".into()
            }
        );
        assert_eq!(
            events[1],
            Event::ToolUseDelta {
                id: "call_9".into(),
                json: "{\"path\":\".\"}".into()
            }
        );
        assert_eq!(
            events[2],
            Event::ToolUseEnd {
                id: "call_9".into()
            }
        );
        assert_eq!(events[3], Event::Done(StopReason::ToolUse));
    }

    #[test]
    fn attributes_argument_only_chunks_to_the_open_call() {
        let mut d = Decoder::default();
        // First chunk: opens the call with name, no args yet.
        d.chunk(pb::GetChatCompletionChunk {
            outputs: vec![pb::CompletionOutputChunk {
                delta: Some(pb::Delta {
                    tool_calls: vec![pb::ToolCall {
                        id: "call_1".into(),
                        tool: Some(pb::tool_call::Tool::Function(pb::FunctionCall {
                            name: "shell".into(),
                            arguments: String::new(),
                        })),
                        ..Default::default()
                    }],
                    ..Default::default()
                }),
                ..Default::default()
            }],
            ..Default::default()
        });
        // Second chunk: argument fragment with an empty id — must attach to call_1.
        d.chunk(pb::GetChatCompletionChunk {
            outputs: vec![pb::CompletionOutputChunk {
                delta: Some(pb::Delta {
                    tool_calls: vec![pb::ToolCall {
                        id: String::new(),
                        tool: Some(pb::tool_call::Tool::Function(pb::FunctionCall {
                            name: String::new(),
                            arguments: "{\"cmd\":\"ls\"}".into(),
                        })),
                        ..Default::default()
                    }],
                    ..Default::default()
                }),
                finish_reason: pb::FinishReason::ReasonToolCalls as i32,
                ..Default::default()
            }],
            ..Default::default()
        });
        d.finish();
        let events = drain(d);
        assert_eq!(
            events[0],
            Event::ToolUseStart {
                id: "call_1".into(),
                name: "shell".into()
            }
        );
        assert_eq!(
            events[1],
            Event::ToolUseDelta {
                id: "call_1".into(),
                json: "{\"cmd\":\"ls\"}".into()
            }
        );
        assert_eq!(
            events[2],
            Event::ToolUseEnd {
                id: "call_1".into()
            }
        );
        assert_eq!(events[3], Event::Done(StopReason::ToolUse));
    }

    #[test]
    fn x_collections_and_mcp_tools_map_to_proto_oneof() {
        use lvz_protocol::{McpServer, ServerTool};
        let mut req = ChatRequest::new("grok-4").push(Message::user("hi"));
        req.server_tools = vec![
            ServerTool::XSearch {
                allowed_handles: vec!["xai".into()],
                blocked_handles: vec![],
                from_date: Some("2024-05-24".into()),
                to_date: None,
            },
            ServerTool::CollectionsSearch {
                collection_ids: vec!["col_1".into(), "col_2".into()],
                limit: Some(5),
            },
        ];
        req.mcp_servers = vec![McpServer {
            name: "gh".into(),
            url: "https://mcp.example".into(),
            authorization_token: Some("tok".into()),
        }];
        let g = build_request(req);
        let xs = g
            .tools
            .iter()
            .find_map(|t| match &t.tool {
                Some(pb::tool::Tool::XSearch(x)) => Some(x),
                _ => None,
            })
            .expect("x search tool");
        assert_eq!(xs.allowed_x_handles, vec!["xai".to_string()]);
        assert!(xs.from_date.is_some());
        let cs = g
            .tools
            .iter()
            .find_map(|t| match &t.tool {
                Some(pb::tool::Tool::CollectionsSearch(c)) => Some(c),
                _ => None,
            })
            .expect("collections search tool");
        assert_eq!(cs.collection_ids.len(), 2);
        assert_eq!(cs.limit, Some(5));
        let mcp = g
            .tools
            .iter()
            .find_map(|t| match &t.tool {
                Some(pb::tool::Tool::Mcp(m)) => Some(m),
                _ => None,
            })
            .expect("mcp tool");
        assert_eq!(mcp.server_label, "gh");
        assert_eq!(mcp.server_url, "https://mcp.example");
        assert_eq!(mcp.authorization.as_deref(), Some("tok"));
    }

    #[test]
    fn iso_date_parses_to_epoch_midnight() {
        // 1970-01-01 is day 0; 2024-05-24 is a known offset.
        assert_eq!(iso_date_to_timestamp("1970-01-01").unwrap().seconds, 0);
        assert_eq!(
            iso_date_to_timestamp("2024-05-24").unwrap().seconds,
            19_867 * 86_400
        );
        assert!(iso_date_to_timestamp("not-a-date").is_none());
        assert!(iso_date_to_timestamp("2024-13-01").is_none());
    }

    #[test]
    fn deferred_response_maps_to_event_sequence() {
        let resp = pb::GetChatCompletionResponse {
            outputs: vec![pb::CompletionOutput {
                finish_reason: pb::FinishReason::ReasonToolCalls as i32,
                message: Some(pb::CompletionMessage {
                    content: "done".into(),
                    reasoning_content: "thought".into(),
                    tool_calls: vec![pb::ToolCall {
                        id: "call_7".into(),
                        tool: Some(pb::tool_call::Tool::Function(pb::FunctionCall {
                            name: "shell".into(),
                            arguments: "{\"cmd\":\"ls\"}".into(),
                        })),
                        ..Default::default()
                    }],
                    ..Default::default()
                }),
                ..Default::default()
            }],
            usage: Some(pb::SamplingUsage {
                prompt_tokens: 9,
                completion_tokens: 3,
                cached_prompt_text_tokens: 4,
                ..Default::default()
            }),
            ..Default::default()
        };
        let events = events_from_response(resp);
        assert_eq!(events[0], Event::TextDelta("done".into()));
        assert_eq!(events[1], Event::Thinking("thought".into()));
        assert_eq!(
            events[2],
            Event::ToolUseStart {
                id: "call_7".into(),
                name: "shell".into()
            }
        );
        assert_eq!(
            events[3],
            Event::ToolUseDelta {
                id: "call_7".into(),
                json: "{\"cmd\":\"ls\"}".into()
            }
        );
        assert_eq!(
            events[4],
            Event::ToolUseEnd {
                id: "call_7".into()
            }
        );
        assert!(matches!(
            events[5],
            Event::Usage(u) if u.input_tokens == 5 && u.cache_read_tokens == 4 && u.output_tokens == 3
        ));
        assert_eq!(events[6], Event::Done(StopReason::ToolUse));
    }
}
