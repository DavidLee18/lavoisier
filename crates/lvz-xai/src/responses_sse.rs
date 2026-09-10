//! Incremental decoder for xAI's **Responses API** (`POST /v1/responses`) SSE stream — the
//! Agent-Tools transport. A state machine of the same shape as [`SseDecoder`](crate::http), fed
//! with [`push`](RespDecoder::push) and ended with [`eof`](RespDecoder::eof).
//!
//! Unlike `chat/completions`, every frame carries a named event whose `type` field repeats the
//! `event:` line, so the decoder switches on `type` alone and ignores `event:` lines. The
//! vocabulary was captured from a live stream — xAI documents the Responses *request* body but not
//! its streaming events — which is why `tests/fixtures/xai-responses-*.sse` are the decoder's spec.
//! **If the wire moves, re-record rather than guess.**
//!
//! * `response.output_text.delta` → [`Event::TextDelta`] (field `delta`)
//! * `response.reasoning_summary_text.delta` → [`Event::Thinking`]. This is the reasoning
//!   *summary*, not raw reasoning — xAI streams no raw chain of thought.
//! * `response.output_item.added` with `item.type == "web_search_call"` → [`Event::ServerToolUse`],
//!   and the matching `response.<tool>_call.completed` → [`Event::ServerToolResult`]. The item id
//!   correlates them.
//! * `response.output_text.annotation.added` → [`Event::Citation`] (`annotation.url`).
//! * `response.completed` → [`Event::Usage`] then [`Event::Done`]. Usage lives on `response.usage`,
//!   naming its fields `input_tokens`/`output_tokens`, with `input_tokens_details.cached_tokens`
//!   for the cache read. There is **no cache-creation counter**: xAI caches server-side with no
//!   request markers, which is also why this transport declares no `PromptCaching`.
//! * `response.incomplete` and `response.failed` are terminal too, and must not be mistaken for a
//!   normal end — an incomplete response that emitted `Done(EndTurn)` would look like success.
//!
//! Lifecycle frames (`response.created`, `response.in_progress`, `*.part.added`/`.done`,
//! `*_call.in_progress`/`.searching`) carry nothing the [`Event`] stream models and are dropped.

use std::collections::{HashMap, VecDeque};

use lvz_protocol::{Event, ProviderError, StopReason, Usage};
use serde_json::Value;

type Sink = VecDeque<Result<Event, ProviderError>>;

/// Decoder state for one Responses stream.
#[derive(Default)]
pub(crate) struct RespDecoder {
    buf: Vec<u8>,
    /// Open provider-run calls: item id → tool name, so the completion can be labelled.
    open_tools: HashMap<String, String>,
    /// `item_id` (`fc_…`) → `call_id` (`call-…`).
    ///
    /// Argument deltas are correlated by **item id**, but the id that must be echoed back on the
    /// tool result is the **call id**, and they are different strings. Emitting the item id would
    /// produce a tool result the provider cannot match to its call, and the loop would stall with
    /// no error to explain why. Same class of trap as Gemini's `thoughtSignature`.
    call_ids: HashMap<String, String>,
    /// Whether any function call was seen, so the turn ends as `ToolUse` rather than `EndTurn`.
    saw_tool_call: bool,
    /// Whether a terminal `Done` has been emitted, so exactly one is.
    done: bool,
}

impl RespDecoder {
    /// Feed a chunk of bytes, draining every complete line into `out`.
    pub(crate) fn push(&mut self, bytes: &[u8], out: &mut Sink) {
        self.buf.extend_from_slice(bytes);
        while let Some(pos) = self.buf.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.buf.drain(..=pos).collect();
            let line = String::from_utf8_lossy(&line);
            self.handle_line(line.trim(), out);
        }
    }

    /// End the stream: flush any trailing partial line, then guarantee exactly one `Done`.
    ///
    /// A stream that ends without `response.completed` (a dropped connection) still terminates, but
    /// as `Other("incomplete")` rather than `EndTurn` — the turn did not finish, and saying it did
    /// would let the agent loop treat a truncated answer as a final one.
    pub(crate) fn eof(&mut self, out: &mut Sink) {
        if !self.buf.is_empty() {
            let line = String::from_utf8_lossy(&self.buf).trim().to_string();
            self.buf.clear();
            self.handle_line(&line, out);
        }
        if !self.done {
            self.done = true;
            out.push_back(Ok(Event::Done(StopReason::Other("incomplete".into()))));
        }
    }

    fn handle_line(&mut self, line: &str, out: &mut Sink) {
        // `event:` lines duplicate the payload's own `type`, and blank lines separate frames.
        let Some(rest) = line.strip_prefix("data:") else {
            return;
        };
        let payload = rest.trim();
        if payload.is_empty() {
            return;
        }
        match serde_json::from_str::<Value>(payload) {
            Ok(v) => self.decode_event(&v, out),
            Err(_) => out.push_back(Err(ProviderError::Decode(format!(
                "xai responses sse: bad json: {payload}"
            )))),
        }
    }

    /// Decode one frame. Split out so tests can feed frames directly rather than through the buffer.
    pub(crate) fn decode_event(&mut self, v: &Value, out: &mut Sink) {
        let Some(ty) = str_at(v, "type") else {
            out.push_back(Err(ProviderError::Decode(
                "xai responses sse: frame has no type".into(),
            )));
            return;
        };
        match ty {
            "response.output_text.delta" => {
                if let Some(d) = non_empty(str_at(v, "delta")) {
                    out.push_back(Ok(Event::TextDelta(d.to_string())));
                }
            }
            "response.reasoning_summary_text.delta" => {
                if let Some(d) = non_empty(str_at(v, "delta")) {
                    out.push_back(Ok(Event::Thinking(d.to_string())));
                }
            }
            "response.output_item.added" => self.item_added(v, out),
            "response.function_call_arguments.delta" => {
                // Keyed by item id; translate to the call id before emitting.
                if let (Some(item_id), Some(d)) =
                    (str_at(v, "item_id"), non_empty(str_at(v, "delta")))
                {
                    if let Some(call_id) = self.call_ids.get(item_id) {
                        out.push_back(Ok(Event::ToolUseDelta {
                            id: call_id.clone(),
                            json: d.to_string(),
                        }));
                    }
                }
            }
            "response.function_call_arguments.done" => {
                if let Some(call_id) = str_at(v, "item_id").and_then(|i| self.call_ids.get(i)) {
                    out.push_back(Ok(Event::ToolUseEnd {
                        id: call_id.clone(),
                    }));
                }
            }
            "response.output_text.annotation.added" => {
                if let Some(a) = v.get("annotation") {
                    if let Some(url) = str_at(a, "url") {
                        out.push_back(Ok(Event::Citation {
                            cited_text: str_at(a, "title").unwrap_or("").to_string(),
                            source: url.to_string(),
                        }));
                    }
                }
            }
            "response.completed" => {
                let stop = if self.saw_tool_call {
                    StopReason::ToolUse
                } else {
                    StopReason::EndTurn
                };
                self.terminal(v, stop, out);
            }
            "response.incomplete" => self.terminal(v, StopReason::Other("incomplete".into()), out),
            "response.failed" => self.failed(v, out),
            _ => {
                // `response.<tool>_call.completed`. Matched by *shape* rather than a fixed tool
                // list, so a tool xAI adds later still closes its open call instead of leaking one.
                if let Some(item_type) = completed_tool_item_type(ty) {
                    if server_tool_item_name(item_type).is_some() {
                        if let Some(item_id) = str_at(v, "item_id") {
                            let name = self
                                .open_tools
                                .remove(item_id)
                                .unwrap_or_else(|| item_type.to_string());
                            out.push_back(Ok(Event::ServerToolResult {
                                id: item_id.to_string(),
                                content: serde_json::json!({ "tool": name, "status": "completed" })
                                    .to_string(),
                            }));
                        }
                    }
                }
            }
        }
    }

    fn item_added(&mut self, v: &Value, out: &mut Sink) {
        let Some(item) = v.get("item") else { return };
        let item_ty = str_at(item, "type");
        if item_ty == Some("function_call") {
            if let (Some(item_id), Some(call_id), Some(name)) = (
                str_at(item, "id"),
                str_at(item, "call_id"),
                str_at(item, "name"),
            ) {
                self.call_ids
                    .insert(item_id.to_string(), call_id.to_string());
                self.saw_tool_call = true;
                out.push_back(Ok(Event::ToolUseStart {
                    id: call_id.to_string(),
                    name: name.to_string(),
                }));
            }
            return;
        }
        if let (Some(name), Some(item_id)) =
            (item_ty.and_then(server_tool_item_name), str_at(item, "id"))
        {
            self.open_tools
                .insert(item_id.to_string(), name.to_string());
            out.push_back(Ok(Event::ServerToolUse {
                id: item_id.to_string(),
                name: name.to_string(),
            }));
        }
    }

    fn terminal(&mut self, v: &Value, stop: StopReason, out: &mut Sink) {
        if self.done {
            return;
        }
        self.done = true;
        let usage = v
            .get("response")
            .and_then(|r| r.get("usage"))
            .map(parse_resp_usage)
            .unwrap_or_default();
        out.push_back(Ok(Event::Usage(usage)));
        out.push_back(Ok(Event::Done(stop)));
    }

    fn failed(&mut self, v: &Value, out: &mut Sink) {
        if self.done {
            return;
        }
        self.done = true;
        let msg = v
            .get("response")
            .and_then(|r| r.get("error"))
            .and_then(|e| str_at(e, "message"))
            .unwrap_or("xai responses: the provider reported a failed response")
            .to_string();
        out.push_back(Err(ProviderError::Api {
            status: 200,
            message: msg,
        }));
        out.push_back(Ok(Event::Done(StopReason::Other("failed".into()))));
    }
}

/// The `item.type` of a provider-run tool call, mapped to the name reported on the event stream.
/// `None` for item types that are not tool calls (`reasoning`, `message`).
pub(crate) fn server_tool_item_name(item_type: &str) -> Option<&'static str> {
    Some(match item_type {
        "web_search_call" => "web_search",
        "x_search_call" => "x_search",
        "code_interpreter_call" => "code_interpreter",
        "collections_search_call" => "collections_search",
        "document_search_call" => "document_search",
        "file_search_call" => "file_search",
        "image_generation_call" => "image_generation",
        "mcp_call" => "mcp",
        _ => return None,
    })
}

/// `response.web_search_call.completed` → `Some("web_search_call")`; anything else → `None`.
fn completed_tool_item_type(ty: &str) -> Option<&str> {
    ty.strip_prefix("response.")?.strip_suffix(".completed")
}

/// `response.usage` → [`Usage`]. `input_tokens` is the full prompt including the cached part, and
/// `input_tokens_details.cached_tokens` is the cache read; there is no cache-creation counter.
pub(crate) fn parse_resp_usage(v: &Value) -> Usage {
    Usage {
        input_tokens: u64_at(v, "input_tokens"),
        output_tokens: u64_at(v, "output_tokens"),
        cache_creation_tokens: 0,
        cache_read_tokens: v
            .get("input_tokens_details")
            .map(|d| u64_at(d, "cached_tokens"))
            .unwrap_or(0),
    }
}

fn str_at<'a>(v: &'a Value, key: &str) -> Option<&'a str> {
    v.get(key)?.as_str()
}

fn u64_at(v: &Value, key: &str) -> u64 {
    v.get(key).and_then(Value::as_u64).unwrap_or(0)
}

fn non_empty(s: Option<&str>) -> Option<&str> {
    s.filter(|t| !t.is_empty())
}
