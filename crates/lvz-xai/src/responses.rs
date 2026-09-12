//! xAI's **Responses API** (`POST /v1/responses`) — the Agent-Tools transport.
//!
//! A third xAI transport beside [`http`](crate::http) (`chat/completions`) and
//! [`grpc`](crate::grpc), not a replacement for either. It exists because xAI's provider-run tools
//! live only here: the old route into them, Live Search via `search_parameters` on
//! `chat/completions`, has returned **410 Gone since 2026-01-12**.
//!
//! The request is a different shape from `chat/completions` — `input` rather than `messages`,
//! `instructions` rather than a system message, `max_output_tokens` rather than `max_tokens`, and
//! tools declared **flat** (`{"type":"function","name":…}`) rather than nested under `"function"`.
//! The response stream is decoded by [`responses_sse`](crate::responses_sse).
//!
//! Note that `max_output_tokens` does **not** bound reasoning tokens — a 512-token ceiling has been
//! observed returning 1273 output tokens. The field is sent; the provider does not honour it as a
//! ceiling. Budget accordingly.

use std::collections::VecDeque;

use async_trait::async_trait;
use bytes::Bytes;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{
    retry_transient, with_negotiated, Capabilities, Capability, ChatRequest, ContentBlock, Event,
    Message, Negotiated, Provider, ProviderCaps, ProviderError, Role, ServerTool, ThinkingLevel,
    ToolChoice, ToolDef,
};
use serde_json::{json, Value};

use crate::responses_sse::RespDecoder;

pub(crate) const DEFAULT_BASE_URL: &str = "https://api.x.ai/v1";

/// A [`Provider`] backed by xAI's Responses API.
pub struct ResponsesTransport {
    api_key: String,
    base_url: String,
    http: reqwest::Client,
}

impl ResponsesTransport {
    /// Construct against the default base URL (`https://api.x.ai/v1`).
    pub fn new(api_key: impl Into<String>) -> Self {
        Self::with_base_url(api_key, DEFAULT_BASE_URL)
    }

    /// Construct against an explicit base URL (e.g. a proxy or a mock server in tests). The URL
    /// carries no trailing `/responses` — that is appended.
    pub fn with_base_url(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            base_url: base_url.into(),
            http: reqwest::Client::new(),
        }
    }

    /// Construct from `XAI_API_KEY` (required) and `XAI_BASE_URL` (optional).
    pub fn from_env() -> Result<Self, ProviderError> {
        let api_key = std::env::var("XAI_API_KEY")
            .map_err(|_| ProviderError::Config("XAI_API_KEY is not set".into()))?;
        let base_url = std::env::var("XAI_BASE_URL").unwrap_or_else(|_| DEFAULT_BASE_URL.into());
        Ok(Self::with_base_url(api_key, base_url))
    }
}

/// Everything this transport supports, named once so the declaration and the check cannot drift.
///
/// Deliberately absent, each for a reason:
///
/// * **`PromptCaching`** — xAI caches server-side with no request markers, and the usage payload
///   carries `input_tokens_details.cached_tokens` but no cache-*creation* counter.
/// * **`Vision`**, **`StructuredOutput`**, **`StopSequences`** — the request fields exist in the
///   OpenAI-shaped API but have not been exercised against the live endpoint, so declaring them
///   would let a request through on an unverified encoding.
/// * **`TopK`** — xAI has no `top_k` on any transport.
/// * **`WebFetch`**, **`UrlContext`**, **`ClientBuiltinTools`**, **`RemoteMcp`** — other providers'
///   tools.
pub struct XaiResponsesCaps;

impl ProviderCaps for XaiResponsesCaps {
    const CAPS: &'static [Capability] = &[
        Capability::ExtendedThinking,
        Capability::Sampling,
        Capability::ToolChoiceControl,
        Capability::WebSearch,
        Capability::XSearch,
        Capability::CodeExecution,
        Capability::CollectionsSearch,
    ];
}

#[async_trait]
impl Provider for ResponsesTransport {
    /// Negotiate, then send: this method is the negotiation call and nothing else.
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        with_negotiated::<XaiResponsesCaps, _, _>(req, |nreq| self.send(nreq)).await
    }

    fn capabilities(&self) -> Capabilities {
        XaiResponsesCaps::declare()
    }
}

impl ResponsesTransport {
    async fn send(
        &self,
        nreq: Negotiated<XaiResponsesCaps>,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        let body = build_body(&nreq);
        let url = format!("{}/responses", self.base_url.trim_end_matches('/'));

        let max_retries: u32 = std::env::var("XAI_MAX_RETRIES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(6);
        let resp = retry_transient(max_retries, || async {
            let resp = self
                .http
                .post(&url)
                .bearer_auth(&self.api_key)
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

        let state = RespState {
            body: resp.bytes_stream().boxed(),
            decoder: RespDecoder::default(),
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
}

struct RespState {
    body: BoxStream<'static, reqwest::Result<Bytes>>,
    decoder: RespDecoder,
    pending: VecDeque<Result<Event, ProviderError>>,
    drained: bool,
}

// --- the request body ---

/// Build the `/v1/responses` body from a negotiated request.
pub(crate) fn build_body(nreq: &Negotiated<XaiResponsesCaps>) -> Value {
    let req = nreq.request();
    let mut body = json!({
        "model": req.model,
        "stream": true,
        "input": input_items(&req.messages),
        "max_output_tokens": req.max_tokens,
    });
    if let Some(sp) = &req.system {
        body["instructions"] = json!(sp.text);
    }
    if let Some(t) = req.temperature {
        body["temperature"] = json!(t);
    }
    if let Some(p) = req.top_p {
        body["top_p"] = json!(p);
    }
    if let Some(l) = req.thinking {
        if l != ThinkingLevel::Off {
            body["reasoning"] = json!({ "effort": effort_of(l) });
        }
    }
    if let Some(tc) = &req.tool_choice {
        body["tool_choice"] = tool_choice_json(tc);
    }
    let mut tools: Vec<Value> = req.tools.iter().map(function_tool_json).collect();
    tools.extend(req.server_tools.iter().filter_map(server_tool_json));
    if !tools.is_empty() {
        body["tools"] = json!(tools);
    }
    body
}

/// `low` or `high` — xAI's only two reasoning efforts.
///
/// `Medium` rounds **down**, not up: on a cost-weighted metric where output is ~5x input, buying
/// more reasoning than was asked for is the worse error.
fn effort_of(l: ThinkingLevel) -> &'static str {
    match l {
        ThinkingLevel::High => "high",
        _ => "low",
    }
}

/// A client-side tool. Responses declares these **flat** — `{"type":"function","name":…}` — where
/// `chat/completions` nests them under `"function"`.
fn function_tool_json(t: &ToolDef) -> Value {
    json!({
        "type": "function",
        "name": t.name,
        "description": t.description,
        "parameters": t.schema,
    })
}

/// A provider-run tool. `None` for tools this transport does not run; [`negotiate`] refuses those
/// before they reach here, and a test pins the two lists together.
pub(crate) fn server_tool_json(t: &ServerTool) -> Option<Value> {
    Some(match t {
        ServerTool::WebSearch {
            allowed_domains,
            blocked_domains,
            ..
        } => {
            let mut v = json!({ "type": "web_search" });
            // allowed_domains and excluded_domains cannot both be set; allowed wins.
            if !allowed_domains.is_empty() {
                v["filters"] = json!({ "allowed_domains": allowed_domains });
            } else if !blocked_domains.is_empty() {
                v["filters"] = json!({ "excluded_domains": blocked_domains });
            }
            v
        }
        ServerTool::XSearch {
            allowed_handles,
            blocked_handles,
            from_date,
            to_date,
        } => {
            let mut v = json!({ "type": "x_search" });
            if !allowed_handles.is_empty() {
                v["allowed_x_handles"] = json!(allowed_handles);
            } else if !blocked_handles.is_empty() {
                v["excluded_x_handles"] = json!(blocked_handles);
            }
            if let Some(d) = from_date {
                v["from_date"] = json!(d);
            }
            if let Some(d) = to_date {
                v["to_date"] = json!(d);
            }
            v
        }
        ServerTool::CodeExecution => json!({ "type": "code_interpreter" }),
        ServerTool::CollectionsSearch {
            collection_ids,
            limit,
        } => {
            let mut v = json!({ "type": "collections_search", "collection_ids": collection_ids });
            if let Some(n) = limit {
                v["limit"] = json!(n);
            }
            v
        }
        // Not xAI tools; negotiate refuses them before they reach here.
        ServerTool::WebFetch { .. } | ServerTool::UrlContext => return None,
    })
}

fn tool_choice_json(tc: &ToolChoice) -> Value {
    match tc {
        ToolChoice::Auto => json!("auto"),
        ToolChoice::Required => json!("required"),
        ToolChoice::None => json!("none"),
        ToolChoice::Tool(n) => json!({ "type": "function", "name": n }),
    }
}

/// Messages → the `input` array.
///
/// Assistant tool calls and their results round-trip as `function_call` / `function_call_output`
/// items keyed by `call_id` — the id the stream reports as `call_id`, **not** the `fc_…` item id.
fn input_items(msgs: &[Message]) -> Value {
    let mut out: Vec<Value> = Vec::new();
    for m in msgs {
        let role = match m.role {
            Role::User => "user",
            Role::Assistant => "assistant",
        };
        for block in &m.content {
            match block {
                ContentBlock::Text { text, .. } if !text.is_empty() => {
                    out.push(json!({ "role": role, "content": text }));
                }
                ContentBlock::ToolUse { id, name, input } => {
                    out.push(json!({
                        "type": "function_call",
                        "call_id": id,
                        "name": name,
                        "arguments": input.to_string(),
                    }));
                }
                ContentBlock::ToolResult {
                    tool_use_id,
                    content,
                    ..
                } => {
                    out.push(json!({
                        "type": "function_call_output",
                        "call_id": tool_use_id,
                        "output": content,
                    }));
                }
                _ => {}
            }
        }
    }
    json!(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{negotiate, SystemPrompt};

    fn negotiated(req: ChatRequest) -> Negotiated<XaiResponsesCaps> {
        negotiate::<XaiResponsesCaps>(req)
            .1
            .expect("fixture must negotiate")
    }

    fn base() -> ChatRequest {
        let mut r = ChatRequest::new("grok-4.6");
        r.max_tokens = 256;
        r.messages = vec![Message::user("hi")];
        r
    }

    #[test]
    fn the_body_uses_the_responses_field_names_not_chat_completions() {
        let mut r = base();
        r.system = Some(SystemPrompt {
            text: "be terse".into(),
            cache: false,
        });
        let b = build_body(&negotiated(r));
        // `input` not `messages`, `instructions` not a system message, `max_output_tokens` not
        // `max_tokens`. Getting any of these wrong is a 400 from the endpoint.
        assert!(b.get("input").is_some(), "{b}");
        assert!(b.get("messages").is_none(), "{b}");
        assert_eq!(b["instructions"], "be terse");
        assert_eq!(b["max_output_tokens"], 256);
        assert!(b.get("max_tokens").is_none(), "{b}");
        assert_eq!(b["stream"], true);
    }

    #[test]
    fn function_tools_are_declared_flat_not_nested() {
        let mut r = base();
        r.tools = vec![ToolDef {
            name: "read_file".into(),
            description: "read a file".into(),
            schema: json!({"type": "object"}),
            cache: false,
            strict: false,
        }];
        let b = build_body(&negotiated(r));
        let t = &b["tools"][0];
        assert_eq!(t["type"], "function");
        // Flat: the name sits beside `type`, NOT under a "function" object the way
        // chat/completions nests it.
        assert_eq!(t["name"], "read_file");
        assert!(t.get("function").is_none(), "{t}");
    }

    #[test]
    fn tool_calls_round_trip_by_call_id() {
        let mut r = base();
        r.messages = vec![
            Message::user("read it"),
            Message {
                role: Role::Assistant,
                content: vec![ContentBlock::ToolUse {
                    id: "call-1".into(),
                    name: "read_file".into(),
                    input: json!({"path": "a.txt"}),
                }],
            },
            Message {
                role: Role::User,
                content: vec![ContentBlock::ToolResult {
                    tool_use_id: "call-1".into(),
                    content: "contents".into(),
                    is_error: false,
                }],
            },
        ];
        let b = build_body(&negotiated(r));
        let items = b["input"].as_array().expect("input array");
        assert_eq!(items[1]["type"], "function_call");
        assert_eq!(items[1]["call_id"], "call-1");
        // Arguments go over the wire as a JSON *string*, not an object.
        assert!(items[1]["arguments"].is_string(), "{}", items[1]);
        assert_eq!(items[2]["type"], "function_call_output");
        assert_eq!(items[2]["call_id"], "call-1");
        assert_eq!(items[2]["output"], "contents");
    }

    #[test]
    fn medium_thinking_rounds_down_to_low() {
        // xAI has only `low` and `high`. On a cost-weighted metric where output is ~5x input,
        // buying more reasoning than was asked for is the worse error.
        for (level, want) in [
            (ThinkingLevel::Low, "low"),
            (ThinkingLevel::Medium, "low"),
            (ThinkingLevel::High, "high"),
        ] {
            let mut r = base();
            r.thinking = Some(level);
            let b = build_body(&negotiated(r));
            assert_eq!(b["reasoning"]["effort"], want, "{level:?}");
        }
        // Off emits no reasoning block at all.
        let mut r = base();
        r.thinking = Some(ThinkingLevel::Off);
        assert!(build_body(&negotiated(r)).get("reasoning").is_none());
    }

    #[test]
    fn web_search_domain_filters_are_mutually_exclusive() {
        // allowed_domains and excluded_domains cannot both be set; allowed wins.
        let v = server_tool_json(&ServerTool::WebSearch {
            max_uses: None,
            allowed_domains: vec!["docs.rs".into()],
            blocked_domains: vec!["spam.example".into()],
        })
        .expect("web_search maps");
        assert_eq!(v["filters"]["allowed_domains"][0], "docs.rs");
        assert!(v["filters"].get("excluded_domains").is_none(), "{v}");

        let v = server_tool_json(&ServerTool::WebSearch {
            max_uses: None,
            allowed_domains: vec![],
            blocked_domains: vec!["spam.example".into()],
        })
        .unwrap();
        assert_eq!(v["filters"]["excluded_domains"][0], "spam.example");
    }

    /// The declared capability list and what `server_tool_json` actually maps must agree.
    ///
    /// Widening the mapper without widening the declaration would let a tool through that the
    /// provider never receives; widening the declaration without the mapper would accept a tool
    /// and then drop it. Either way the model is offered something that does not work, silently.
    #[test]
    fn the_declaration_and_the_mapper_agree() {
        let every = [
            (
                ServerTool::WebSearch {
                    max_uses: None,
                    allowed_domains: vec![],
                    blocked_domains: vec![],
                },
                Capability::WebSearch,
            ),
            (
                ServerTool::WebFetch { max_uses: None },
                Capability::WebFetch,
            ),
            (ServerTool::CodeExecution, Capability::CodeExecution),
            (
                ServerTool::XSearch {
                    allowed_handles: vec![],
                    blocked_handles: vec![],
                    from_date: None,
                    to_date: None,
                },
                Capability::XSearch,
            ),
            (
                ServerTool::CollectionsSearch {
                    collection_ids: vec!["c".into()],
                    limit: None,
                },
                Capability::CollectionsSearch,
            ),
            (ServerTool::UrlContext, Capability::UrlContext),
        ];
        let declared = XaiResponsesCaps::declare();
        for (tool, cap) in every {
            let maps = server_tool_json(&tool).is_some();
            assert_eq!(
                maps,
                declared.supports(cap),
                "{cap:?}: mapper says {maps}, declaration says {}",
                declared.supports(cap)
            );
        }
    }
}
