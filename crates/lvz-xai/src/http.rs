//! The in-crate OpenAI-compatible fallback transport (`RECIPE.md` §1, §8).
//!
//! Streams `chat/completions` against `https://api.x.ai/v1` (`stream: true`), normalising
//! SSE chunks into the [`Event`] stream and supporting OpenAI-style function/tool calling:
//! tool definitions are sent, normalised tool blocks are mapped into OpenAI message shape,
//! and streamed `tool_calls` deltas are decoded into [`Event::ToolUseStart`]/`ToolUseDelta`/
//! `ToolUseEnd`. This path has no prompt caching and no native server-side tools, so those
//! [`Capabilities`](lvz_protocol::Capabilities) are `false`; parallel tool use is supported.

use std::collections::{BTreeMap, VecDeque};

use async_trait::async_trait;
use bytes::Bytes;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{
    Capabilities, ChatRequest, ContentBlock, Event, MediaSource, OutputFormat, Provider,
    ProviderError, Role, ServerTool, StopReason, ThinkingLevel, ToolChoice, Usage,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub(crate) const DEFAULT_BASE_URL: &str = "https://api.x.ai/v1";

/// A [`Provider`] backed by xAI's OpenAI-compatible REST endpoint.
pub struct HttpTransport {
    api_key: String,
    base_url: String,
    http: reqwest::Client,
}

impl HttpTransport {
    /// Construct against the default base URL (`https://api.x.ai/v1`).
    pub fn new(api_key: impl Into<String>) -> Self {
        Self::with_base_url(api_key, DEFAULT_BASE_URL)
    }

    /// Construct against an explicit base URL (e.g. a proxy or a mock server in tests).
    pub fn with_base_url(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            base_url: base_url.into(),
            http: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl Provider for HttpTransport {
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        let body = OaiRequest {
            messages: build_messages(&req),
            tools: build_tools(&req),
            tool_choice: req.tool_choice.as_ref().map(oai_tool_choice),
            // Only emit when forbidding parallel calls; otherwise defer to the xAI default.
            parallel_tool_calls: req.disable_parallel_tool_use.then_some(false),
            response_format: req.output_format.as_ref().map(|f| {
                let OutputFormat::JsonSchema { schema } = f;
                json!({
                    "type": "json_schema",
                    "json_schema": { "name": "response", "schema": schema, "strict": true },
                })
            }),
            reasoning_effort: req.thinking.and_then(reasoning_effort),
            // A WebSearch server tool enables xAI Live Search (model decides when to search).
            search_parameters: req
                .server_tools
                .iter()
                .any(|t| matches!(t, ServerTool::WebSearch { .. }))
                .then(|| json!({ "mode": "auto" })),
            model: req.model,
            max_tokens: req.max_tokens,
            temperature: req.temperature,
            top_p: req.top_p,
            stop: req.stop_sequences.clone(),
            stream: true,
            stream_options: Some(StreamOptions {
                include_usage: true,
            }),
        };
        let url = format!("{}/chat/completions", self.base_url.trim_end_matches('/'));

        let resp = self
            .http
            .post(url)
            .bearer_auth(&self.api_key)
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

        let state = SseState {
            body: resp.bytes_stream().boxed(),
            decoder: SseDecoder::default(),
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
            prompt_caching: false,
            extended_thinking: false,
            parallel_tool_use: true,
            server_side_tools: false,
            vision: true,
        }
    }
}

struct SseState {
    body: BoxStream<'static, reqwest::Result<Bytes>>,
    decoder: SseDecoder,
    pending: VecDeque<Result<Event, ProviderError>>,
    drained: bool,
}

// --- request building: normalised ChatRequest → OpenAI chat messages ---

/// Flatten a [`ChatRequest`] into OpenAI chat messages. Tool-use blocks become assistant
/// `tool_calls`; tool-result blocks become standalone `tool` messages (OpenAI's shape).
fn build_messages(req: &ChatRequest) -> Vec<Value> {
    let mut out = Vec::new();
    if let Some(system) = &req.system {
        out.push(json!({ "role": "system", "content": system.text }));
    }
    for m in &req.messages {
        match m.role {
            Role::User => push_user_message(m, &mut out),
            Role::Assistant => out.push(build_assistant_message(m)),
        }
    }
    out
}

fn push_user_message(m: &lvz_protocol::Message, out: &mut Vec<Value>) {
    let mut text = String::new();
    let mut images = Vec::new();
    let mut tool_results = Vec::new();
    for block in &m.content {
        match block {
            ContentBlock::Text { text: t, .. } | ContentBlock::Thinking { text: t } => {
                text.push_str(t)
            }
            ContentBlock::Image { source } | ContentBlock::Document { source, .. } => {
                // OpenAI-compat carries images as `image_url` parts (URL or base64 data-URL); a
                // Files-API id becomes a `file` part.
                let part = match source {
                    MediaSource::Url { url } => {
                        json!({ "type": "image_url", "image_url": { "url": url } })
                    }
                    MediaSource::Base64 { media_type, data } => json!({
                        "type": "image_url",
                        "image_url": { "url": format!("data:{media_type};base64,{data}") },
                    }),
                    MediaSource::File { file_id } => {
                        json!({ "type": "file", "file": { "file_id": file_id } })
                    }
                };
                images.push(part);
            }
            ContentBlock::ToolResult {
                tool_use_id,
                content,
                ..
            } => tool_results.push(json!({
                "role": "tool",
                "tool_call_id": tool_use_id,
                "content": content,
            })),
            ContentBlock::ToolUse { .. } => {} // not valid on a user turn
        }
    }
    // Tool results are their own messages and must precede any free-text follow-up.
    out.extend(tool_results);
    if images.is_empty() {
        if !text.is_empty() {
            out.push(json!({ "role": "user", "content": text }));
        } else if m.content.is_empty() {
            out.push(json!({ "role": "user", "content": "" }));
        }
    } else {
        // Mixed text+image turns use the content-array form.
        let mut parts = Vec::new();
        if !text.is_empty() {
            parts.push(json!({ "type": "text", "text": text }));
        }
        parts.extend(images);
        out.push(json!({ "role": "user", "content": parts }));
    }
}

fn build_assistant_message(m: &lvz_protocol::Message) -> Value {
    let mut text = String::new();
    let mut tool_calls = Vec::new();
    for block in &m.content {
        match block {
            ContentBlock::Text { text: t, .. } => text.push_str(t),
            // Thinking is not echoed back to the OpenAI-compat endpoint.
            ContentBlock::Thinking { .. } => {}
            // Images/documents are inputs, never part of an assistant turn we re-send.
            ContentBlock::Image { .. } | ContentBlock::Document { .. } => {}
            ContentBlock::ToolUse { id, name, input } => tool_calls.push(json!({
                "id": id,
                "type": "function",
                "function": { "name": name, "arguments": input.to_string() },
            })),
            ContentBlock::ToolResult { .. } => {}
        }
    }
    let mut msg = json!({ "role": "assistant" });
    msg["content"] = if text.is_empty() {
        Value::Null
    } else {
        Value::String(text)
    };
    if !tool_calls.is_empty() {
        msg["tool_calls"] = Value::Array(tool_calls);
    }
    msg
}

fn build_tools(req: &ChatRequest) -> Option<Vec<Value>> {
    if req.tools.is_empty() {
        return None;
    }
    Some(
        req.tools
            .iter()
            .map(|t| {
                json!({
                    "type": "function",
                    "function": {
                        "name": t.name,
                        "description": t.description,
                        "parameters": t.schema,
                    }
                })
            })
            .collect(),
    )
}

fn map_stop(reason: &str) -> StopReason {
    match reason {
        "stop" => StopReason::EndTurn,
        "length" => StopReason::MaxTokens,
        "tool_calls" => StopReason::ToolUse,
        other => StopReason::Other(other.to_string()),
    }
}

// --- SSE decoding: OpenAI stream chunks → normalised events ---

type Sink = VecDeque<Result<Event, ProviderError>>;

/// Incremental decoder for the OpenAI-compat SSE stream. Buffers until each line is
/// `\n`-complete, emits text/usage/tool events as they arrive, reassembles streamed
/// `tool_calls` by their `index`, and defers a single terminal [`Event::Done`].
#[derive(Default)]
struct SseDecoder {
    buf: Vec<u8>,
    /// tool-call index → emitted tool id, for correlating argument deltas and closing.
    tool_ids: BTreeMap<u64, String>,
    stop: Option<StopReason>,
    done_emitted: bool,
}

impl SseDecoder {
    fn push(&mut self, bytes: &[u8], out: &mut Sink) {
        self.buf.extend_from_slice(bytes);
        while let Some(pos) = self.buf.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.buf.drain(..=pos).collect();
            let line = String::from_utf8_lossy(&line);
            self.handle_line(line.trim(), out);
        }
    }

    fn eof(&mut self, out: &mut Sink) {
        if !self.buf.is_empty() {
            let line = String::from_utf8_lossy(&self.buf).trim().to_string();
            self.buf.clear();
            self.handle_line(&line, out);
        }
        self.emit_done(out);
    }

    fn handle_line(&mut self, line: &str, out: &mut Sink) {
        let Some(payload) = line.strip_prefix("data:") else {
            return;
        };
        let payload = payload.trim();
        if payload.is_empty() {
            return;
        }
        if payload == "[DONE]" {
            self.emit_done(out);
            return;
        }
        match serde_json::from_str::<OaiStreamChunk>(payload) {
            Ok(chunk) => {
                if let Some(usage) = chunk.usage {
                    out.push_back(Ok(Event::Usage(usage.into())));
                }
                if let Some(choice) = chunk.choices.into_iter().next() {
                    if let Some(content) = choice.delta.content {
                        if !content.is_empty() {
                            out.push_back(Ok(Event::TextDelta(content)));
                        }
                    }
                    for tc in choice.delta.tool_calls {
                        self.handle_tool_call_delta(tc, out);
                    }
                    if let Some(reason) = choice.finish_reason {
                        self.stop = Some(map_stop(&reason));
                        self.close_tools(out); // ends arrive right after the last arg delta
                    }
                }
            }
            Err(e) => out.push_back(Err(ProviderError::Decode(e.to_string()))),
        }
    }

    fn handle_tool_call_delta(&mut self, tc: OaiToolCallDelta, out: &mut Sink) {
        // The first delta for an index carries the id (and usually the name).
        if let Some(id) = tc.id {
            let name = tc
                .function
                .as_ref()
                .and_then(|f| f.name.clone())
                .unwrap_or_default();
            self.tool_ids.insert(tc.index, id.clone());
            out.push_back(Ok(Event::ToolUseStart { id, name }));
        }
        if let Some(func) = tc.function {
            if let Some(args) = func.arguments {
                if !args.is_empty() {
                    if let Some(id) = self.tool_ids.get(&tc.index) {
                        out.push_back(Ok(Event::ToolUseDelta {
                            id: id.clone(),
                            json: args,
                        }));
                    }
                }
            }
        }
    }

    /// Emit a `ToolUseEnd` for every open tool call, in index order.
    fn close_tools(&mut self, out: &mut Sink) {
        for (_, id) in std::mem::take(&mut self.tool_ids) {
            out.push_back(Ok(Event::ToolUseEnd { id }));
        }
    }

    fn emit_done(&mut self, out: &mut Sink) {
        if self.done_emitted {
            return;
        }
        self.close_tools(out); // safety net if no finish_reason was seen
        self.done_emitted = true;
        let stop = self.stop.take().unwrap_or(StopReason::EndTurn);
        out.push_back(Ok(Event::Done(stop)));
    }
}

// --- OpenAI-compatible wire types (the only place this shape is known) ---

#[derive(Serialize)]
struct OaiRequest {
    model: String,
    messages: Vec<Value>,
    max_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    top_p: Option<f32>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    stop: Vec<String>,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    stream_options: Option<StreamOptions>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tools: Option<Vec<Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tool_choice: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    parallel_tool_calls: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_format: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    reasoning_effort: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    search_parameters: Option<Value>,
}

/// Map the normalised thinking level onto grok's `reasoning_effort` (`low`/`high` on reasoning
/// models; ignored by non-reasoning models). `None` ⇒ defer to the model default.
fn reasoning_effort(level: ThinkingLevel) -> Option<&'static str> {
    match level {
        ThinkingLevel::Off | ThinkingLevel::Low => Some("low"),
        ThinkingLevel::Medium | ThinkingLevel::High => Some("high"),
    }
}

/// Map the normalised tool choice onto OpenAI's `tool_choice`.
fn oai_tool_choice(tc: &ToolChoice) -> Value {
    match tc {
        ToolChoice::Auto => json!("auto"),
        ToolChoice::Required => json!("required"),
        ToolChoice::None => json!("none"),
        ToolChoice::Tool(name) => json!({ "type": "function", "function": { "name": name } }),
    }
}

#[derive(Serialize)]
struct StreamOptions {
    include_usage: bool,
}

#[derive(Deserialize)]
struct OaiStreamChunk {
    #[serde(default)]
    choices: Vec<OaiStreamChoice>,
    #[serde(default)]
    usage: Option<OaiUsage>,
}

#[derive(Deserialize)]
struct OaiStreamChoice {
    #[serde(default)]
    delta: OaiDelta,
    #[serde(default)]
    finish_reason: Option<String>,
}

#[derive(Deserialize, Default)]
struct OaiDelta {
    #[serde(default)]
    content: Option<String>,
    #[serde(default)]
    tool_calls: Vec<OaiToolCallDelta>,
}

#[derive(Deserialize)]
struct OaiToolCallDelta {
    #[serde(default)]
    index: u64,
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    function: Option<OaiFunctionDelta>,
}

#[derive(Deserialize)]
struct OaiFunctionDelta {
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    arguments: Option<String>,
}

#[derive(Deserialize)]
struct OaiUsage {
    #[serde(default)]
    prompt_tokens: u64,
    #[serde(default)]
    completion_tokens: u64,
}

impl From<OaiUsage> for Usage {
    fn from(u: OaiUsage) -> Self {
        Usage {
            input_tokens: u.prompt_tokens,
            output_tokens: u.completion_tokens,
            cache_creation_tokens: 0,
            cache_read_tokens: 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{Message, ToolDef};

    fn role_at(messages: &[Value], i: usize) -> &str {
        messages[i]["role"].as_str().unwrap()
    }

    #[test]
    fn system_prompt_leads_and_tools_are_function_shaped() {
        let mut req = ChatRequest::new("grok-4")
            .system("be terse")
            .push(Message::user("hi"));
        req.tools.push(ToolDef {
            name: "list_dir".into(),
            description: "list a dir".into(),
            schema: json!({"type": "object"}),
            cache: false,
            strict: false,
        });

        let messages = build_messages(&req);
        assert_eq!(role_at(&messages, 0), "system");
        assert_eq!(role_at(&messages, 1), "user");

        let tools = build_tools(&req).unwrap();
        assert_eq!(tools[0]["type"], "function");
        assert_eq!(tools[0]["function"]["name"], "list_dir");
    }

    #[test]
    fn tool_use_and_result_map_to_openai_shape() {
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
        let messages = build_messages(&req);

        // user, assistant(tool_calls), tool(result)
        let asst = &messages[1];
        assert_eq!(asst["role"], "assistant");
        assert_eq!(asst["tool_calls"][0]["id"], "call_1");
        assert_eq!(asst["tool_calls"][0]["function"]["name"], "shell");

        let tool = &messages[2];
        assert_eq!(tool["role"], "tool");
        assert_eq!(tool["tool_call_id"], "call_1");
        assert_eq!(tool["content"], "files");
    }

    fn decode_all(input: &str) -> Vec<Event> {
        let mut decoder = SseDecoder::default();
        let mut out = VecDeque::new();
        decoder.push(input.as_bytes(), &mut out);
        decoder.eof(&mut out);
        out.into_iter().map(|e| e.unwrap()).collect()
    }

    #[test]
    fn decodes_text_usage_done_in_order() {
        let input = concat!(
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2}}\n\n",
            "data: [DONE]\n\n",
        );
        let events = decode_all(input);
        assert_eq!(events[0], Event::TextDelta("Hel".into()));
        assert_eq!(events[1], Event::TextDelta("lo".into()));
        assert!(
            matches!(events[2], Event::Usage(u) if u.input_tokens == 5 && u.output_tokens == 2)
        );
        assert_eq!(events[3], Event::Done(StopReason::EndTurn));
        assert_eq!(events.len(), 4);
    }

    #[test]
    fn decodes_a_streamed_tool_call() {
        let input = concat!(
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_9\",\"type\":\"function\",\"function\":{\"name\":\"list_dir\",\"arguments\":\"\"}}]}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"path\\\":\"}}]}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\".\\\"}\"}}]}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
            "data: [DONE]\n\n",
        );
        let events = decode_all(input);
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
                json: "{\"path\":".into()
            }
        );
        assert_eq!(
            events[2],
            Event::ToolUseDelta {
                id: "call_9".into(),
                json: "\".\"}".into()
            }
        );
        assert_eq!(
            events[3],
            Event::ToolUseEnd {
                id: "call_9".into()
            }
        );
        assert_eq!(events[4], Event::Done(StopReason::ToolUse));
    }

    #[test]
    fn reassembles_lines_split_across_chunk_boundaries() {
        let sample = "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n";
        let mut decoder = SseDecoder::default();
        let mut out = VecDeque::new();
        for b in sample.as_bytes() {
            decoder.push(&[*b], &mut out);
        }
        decoder.eof(&mut out);
        let events: Vec<Event> = out.into_iter().map(|e| e.unwrap()).collect();
        assert_eq!(events[0], Event::TextDelta("hi".into()));
        assert_eq!(events[1], Event::Done(StopReason::EndTurn));
    }
}
