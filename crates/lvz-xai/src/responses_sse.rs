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
//! * `response.output_item.added` with `item.type == "function_call"` → [`Event::ToolUseStart`],
//!   argument deltas → [`Event::ToolUseDelta`], and the call closes with [`Event::ToolUseEnd`].
//!   A call may also arrive **whole**, in one item (`arguments` already complete on
//!   `output_item.added` / `output_item.done`, with no `function_call_arguments.*` frames) — xAI
//!   documents function calls as a single chunk under streaming. That shape still emits
//!   start → delta → end, because a missing end is what makes a frontend (the Matrix tool notice)
//!   stay silent while the call itself is real.
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

use std::collections::{HashMap, HashSet, VecDeque};

use lvz_protocol::{Event, ProviderError, StopReason, Usage};
use serde_json::Value;

type Sink = VecDeque<Result<Event, ProviderError>>;

/// A provider-run call seen on the stream but not yet (or already) announced.
struct PendingServerTool {
    name: String,
    /// Search query, or the first line of code. Empty until a frame carries one.
    hint: String,
    announced: bool,
}

/// Decoder state for one Responses stream.
#[derive(Default)]
pub(crate) struct RespDecoder {
    buf: Vec<u8>,
    /// Open provider-run calls, keyed by item id. Announced once, with a glimpse when we have one.
    open_tools: HashMap<String, PendingServerTool>,
    /// `item_id` (`fc_…`) → `call_id` (`call-…`).
    ///
    /// Argument deltas are correlated by **item id**, but the id that must be echoed back on the
    /// tool result is the **call id**, and they are different strings. Emitting the item id would
    /// produce a tool result the provider cannot match to its call, and the loop would stall with
    /// no error to explain why. Same class of trap as Gemini's `thoughtSignature`.
    call_ids: HashMap<String, String>,
    /// `call_id` → function name, in first-seen order. The order is what a late close uses.
    fn_names: Vec<(String, String)>,
    /// Call ids that have emitted [`Event::ToolUseStart`].
    fn_started: HashSet<String>,
    /// Call ids that have emitted any argument bytes.
    fn_args_sent: HashSet<String>,
    /// Call ids whose arguments arrived as one complete blob. Further deltas would duplicate it.
    fn_args_whole: HashSet<String>,
    /// Call ids that already produced [`Event::ToolUseEnd`].
    fn_closed: HashSet<String>,
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
            self.close_remaining(out);
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
                    if let Some(call_id) = self.call_ids.get(item_id).cloned() {
                        self.emit_arg_delta(&call_id, d, false, out);
                    }
                }
            }
            "response.function_call_arguments.done" => {
                // The streamed shape keys this frame by item id. A whole-chunk call may instead
                // carry `call_id` directly and the complete `arguments`, with no prior deltas.
                let call_id = str_at(v, "item_id")
                    .and_then(|i| self.call_ids.get(i).cloned())
                    .or_else(|| str_at(v, "call_id").map(str::to_string));
                if let Some(call_id) = call_id {
                    self.close_function(
                        &call_id,
                        str_at(v, "name"),
                        str_at(v, "arguments").unwrap_or(""),
                        out,
                    );
                }
            }
            "response.output_item.done" => self.item_done(v, out),
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
            "response.completed" => self.terminal(v, None, out),
            "response.incomplete" => {
                self.terminal(v, Some(StopReason::Other("incomplete".into())), out);
            }
            "response.failed" => self.failed(v, out),
            _ => {
                // A searching/in-progress frame sometimes carries the query before the item is done.
                if let Some(item_id) = str_at(v, "item_id") {
                    if let Some(hint) = server_tool_glimpse(v) {
                        let name = self
                            .open_tools
                            .get(item_id)
                            .map(|t| t.name.clone())
                            .unwrap_or_default();
                        if !name.is_empty() {
                            self.touch_server_tool(item_id, &name, Some(hint), false, out);
                        }
                    }
                }
                // `response.<tool>_call.completed`. Matched by *shape* rather than a fixed tool
                // list, so a tool xAI adds later still closes its open call instead of leaking one.
                if let Some(item_type) = completed_tool_item_type(ty) {
                    if let Some(name) = server_tool_item_name(item_type) {
                        if let Some(item_id) = str_at(v, "item_id") {
                            self.touch_server_tool(
                                item_id,
                                name,
                                server_tool_glimpse(v),
                                true,
                                out,
                            );
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
            // `arguments` is empty while the call streams, and already complete when xAI returns
            // the call in one chunk. Remember the id mapping either way; emit the blob only when
            // it is actually present so a later delta is not suppressed by an empty prefix.
            if let (Some(item_id), Some(call_id), Some(name)) = (
                str_at(item, "id"),
                str_at(item, "call_id"),
                str_at(item, "name"),
            ) {
                self.note_function(item_id, call_id, name);
                self.open_function(call_id, name, out);
                if let Some(args) = non_empty(str_at(item, "arguments")) {
                    self.emit_arg_delta(call_id, args, true, out);
                }
            }
            return;
        }
        if let (Some(name), Some(item_id)) =
            (item_ty.and_then(server_tool_item_name), str_at(item, "id"))
        {
            // Hold the announcement until the query shows up. The added frame's `action.query`
            // is often still empty; posting then would be a name with no glimpse.
            self.touch_server_tool(item_id, name, server_tool_glimpse(item), false, out);
        }
    }

    /// Record a provider-run call and emit [`Event::ServerToolUse`] once.
    ///
    /// `force` announces even with an empty glimpse (the call is finished and the room should
    /// still see the name). A later frame must not emit a second use.
    fn touch_server_tool(
        &mut self,
        id: &str,
        name: &str,
        hint: Option<String>,
        force: bool,
        out: &mut Sink,
    ) {
        let entry = self
            .open_tools
            .entry(id.to_string())
            .or_insert(PendingServerTool {
                name: name.to_string(),
                hint: String::new(),
                announced: false,
            });
        if !name.is_empty() {
            entry.name = name.to_string();
        }
        if let Some(hint) = hint.filter(|h| !h.is_empty()) {
            if entry.hint.is_empty() {
                entry.hint = hint;
            }
        }
        if entry.announced || (!force && entry.hint.is_empty()) {
            return;
        }
        entry.announced = true;
        out.push_back(Ok(Event::ServerToolUse {
            id: id.to_string(),
            name: entry.name.clone(),
            hint: entry.hint.clone(),
        }));
    }

    /// `response.output_item.done` for a function call carries the finished arguments. The streamed
    /// shape also sends `function_call_arguments.done` first; closing twice must not emit a second
    /// end (or a second copy of the arguments).
    fn item_done(&mut self, v: &Value, out: &mut Sink) {
        let Some(item) = v.get("item") else { return };
        let item_ty = str_at(item, "type");
        if let (Some(name), Some(item_id)) =
            (item_ty.and_then(server_tool_item_name), str_at(item, "id"))
        {
            // The done item is where the query usually lands (`action.query`), after the added
            // frame had an empty one.
            self.touch_server_tool(item_id, name, server_tool_glimpse(item), true, out);
            return;
        }
        if item_ty != Some("function_call") {
            return;
        }
        let Some(call_id) = str_at(item, "call_id") else {
            return;
        };
        if let (Some(item_id), Some(name)) = (str_at(item, "id"), str_at(item, "name")) {
            self.note_function(item_id, call_id, name);
        }
        self.close_function(
            call_id,
            str_at(item, "name"),
            str_at(item, "arguments").unwrap_or(""),
            out,
        );
    }

    fn note_function(&mut self, item_id: &str, call_id: &str, name: &str) {
        self.call_ids
            .insert(item_id.to_string(), call_id.to_string());
        if !self.fn_names.iter().any(|(id, _)| id == call_id) {
            self.fn_names.push((call_id.to_string(), name.to_string()));
        }
    }

    /// Emit [`Event::ToolUseStart`] once per call id.
    fn open_function(&mut self, call_id: &str, name: &str, out: &mut Sink) {
        if !self.fn_names.iter().any(|(id, _)| id == call_id) {
            self.fn_names.push((call_id.to_string(), name.to_string()));
        }
        if !self.fn_started.insert(call_id.to_string()) {
            return;
        }
        self.saw_tool_call = true;
        let name = self
            .fn_names
            .iter()
            .find(|(id, _)| id == call_id)
            .map(|(_, n)| n.clone())
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| name.to_string());
        out.push_back(Ok(Event::ToolUseStart {
            id: call_id.to_string(),
            name,
        }));
    }

    /// Emit one argument fragment.
    ///
    /// `whole` marks a complete arguments blob (the item itself, or `arguments` on a `.done`
    /// frame). A later streamed delta is dropped once a whole blob was emitted, and a whole blob
    /// is dropped once any arguments were already emitted — either way the JSON is not concatenated
    /// with a second copy of itself.
    fn emit_arg_delta(&mut self, call_id: &str, json: &str, whole: bool, out: &mut Sink) {
        if json.is_empty() || self.fn_args_whole.contains(call_id) {
            return;
        }
        if whole && self.fn_args_sent.contains(call_id) {
            return;
        }
        self.fn_args_sent.insert(call_id.to_string());
        if whole {
            self.fn_args_whole.insert(call_id.to_string());
        }
        out.push_back(Ok(Event::ToolUseDelta {
            id: call_id.to_string(),
            json: json.to_string(),
        }));
    }

    /// Finish one function call: start it if the only frame we saw was the completed item, emit
    /// arguments if they were not streamed, then exactly one [`Event::ToolUseEnd`].
    fn close_function(
        &mut self,
        call_id: &str,
        name: Option<&str>,
        arguments: &str,
        out: &mut Sink,
    ) {
        let name = name.unwrap_or("").to_string();
        self.open_function(call_id, &name, out);
        self.emit_arg_delta(call_id, arguments, true, out);
        if !self.fn_closed.insert(call_id.to_string()) {
            return;
        }
        out.push_back(Ok(Event::ToolUseEnd {
            id: call_id.to_string(),
        }));
    }

    /// Close every function call that streamed a start but never a done frame, so a frontend still
    /// sees the call. Arguments already emitted are left as they are.
    fn close_remaining(&mut self, out: &mut Sink) {
        let open: Vec<String> = self
            .fn_names
            .iter()
            .map(|(id, _)| id.clone())
            .filter(|id| !self.fn_closed.contains(id))
            .collect();
        for id in open {
            self.close_function(&id, None, "", out);
        }
    }

    /// Function calls that show up only inside the terminal `response.output` array — no streamed
    /// frames at all — still have to become a start/delta/end triple.
    fn harvest_output(&mut self, v: &Value, out: &mut Sink) {
        let Some(items) = v
            .get("response")
            .and_then(|r| r.get("output"))
            .and_then(Value::as_array)
        else {
            return;
        };
        for item in items {
            if str_at(item, "type") != Some("function_call") {
                continue;
            }
            let Some(call_id) = str_at(item, "call_id") else {
                continue;
            };
            if let (Some(item_id), Some(name)) = (str_at(item, "id"), str_at(item, "name")) {
                self.note_function(item_id, call_id, name);
            }
            self.close_function(
                call_id,
                str_at(item, "name"),
                str_at(item, "arguments").unwrap_or(""),
                out,
            );
        }
    }

    fn terminal(&mut self, v: &Value, forced: Option<StopReason>, out: &mut Sink) {
        if self.done {
            return;
        }
        // Harvest before choosing the stop reason: a call that exists only on `response.output`
        // has not set `saw_tool_call` yet.
        self.harvest_output(v, out);
        self.close_remaining(out);
        self.done = true;
        let stop = forced.unwrap_or(if self.saw_tool_call {
            StopReason::ToolUse
        } else {
            StopReason::EndTurn
        });
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
/// A short target glimpse from a server-tool frame: the search query or the first line of code.
/// Search hits (`sources`, page text) are deliberately not read — the room shows a glimpse.
fn server_tool_glimpse(v: &Value) -> Option<String> {
    let action = v.get("action");
    if let Some(q) = action.and_then(|a| non_empty(str_at(a, "query"))) {
        return Some(glimpse_line(q));
    }
    if let Some(q) = action
        .and_then(|a| a.get("queries"))
        .and_then(Value::as_array)
        .and_then(|a| a.first())
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
    {
        return Some(glimpse_line(q));
    }
    for key in ["query", "code", "input", "command"] {
        if let Some(s) = non_empty(str_at(v, key)) {
            return Some(glimpse_line(s));
        }
    }
    None
}

fn glimpse_line(s: &str) -> String {
    let line = s.lines().next().unwrap_or(s).trim();
    const MAX: usize = 80;
    if line.chars().count() <= MAX {
        line.to_string()
    } else {
        let kept: String = line.chars().take(MAX).collect();
        format!("{kept}…")
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;

    fn decode(frames: &[&str]) -> Vec<Event> {
        let mut dec = RespDecoder::default();
        let mut out = VecDeque::new();
        for frame in frames {
            let v: Value = serde_json::from_str(frame).unwrap();
            dec.decode_event(&v, &mut out);
        }
        out.into_iter().map(Result::unwrap).collect()
    }

    fn tool_shape(events: &[Event]) -> Vec<&str> {
        events
            .iter()
            .filter_map(|e| match e {
                Event::ToolUseStart { .. } => Some("start"),
                Event::ToolUseDelta { .. } => Some("delta"),
                Event::ToolUseEnd { .. } => Some("end"),
                Event::Done(StopReason::ToolUse) => Some("done-tool"),
                Event::Done(_) => Some("done"),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn streamed_function_call_emits_one_end_under_the_call_id() {
        // The recorded shape: empty arguments on add, one delta keyed by item id, then both
        // `function_call_arguments.done` and `output_item.done`. Exactly one end, on the call id.
        let events = decode(&[
            r#"{"type":"response.output_item.added","item":{"arguments":"","call_id":"call-1","name":"read_file","type":"function_call","id":"fc_1","status":"in_progress"}}"#,
            r#"{"type":"response.function_call_arguments.delta","delta":"{\"path\":\"notes.txt\"}","item_id":"fc_1"}"#,
            r#"{"type":"response.function_call_arguments.done","arguments":"{\"path\":\"notes.txt\"}","item_id":"fc_1","name":"read_file"}"#,
            r#"{"type":"response.output_item.done","item":{"arguments":"{\"path\":\"notes.txt\"}","call_id":"call-1","name":"read_file","type":"function_call","id":"fc_1","status":"completed"}}"#,
            r#"{"type":"response.completed","response":{"usage":{"input_tokens":3,"output_tokens":1,"input_tokens_details":{"cached_tokens":0}},"output":[{"type":"function_call"}]}}"#,
        ]);
        assert_eq!(tool_shape(&events), ["start", "delta", "end", "done-tool"]);
        match &events[0] {
            Event::ToolUseStart { id, name } => {
                assert_eq!(id, "call-1");
                assert_eq!(name, "read_file");
            }
            other => panic!("expected start, got {other:?}"),
        }
        match &events[1] {
            Event::ToolUseDelta { id, json } => {
                assert_eq!(id, "call-1");
                assert_eq!(json, r#"{"path":"notes.txt"}"#);
            }
            other => panic!("expected one delta, got {other:?}"),
        }
    }

    #[test]
    fn whole_chunk_function_call_still_ends() {
        // grok returns the call in one item: arguments already complete, no argument-delta frames.
        // The Matrix notice is posted on ToolUseEnd, so a missing end is a silent tool call.
        let events = decode(&[
            r#"{"type":"response.output_item.added","item":{"type":"function_call","id":"fc_9","call_id":"call_9","name":"read_file","arguments":"{\"path\":\"src/lib.rs\"}","status":"in_progress"}}"#,
            r#"{"type":"response.output_item.done","item":{"type":"function_call","id":"fc_9","call_id":"call_9","name":"read_file","arguments":"{\"path\":\"src/lib.rs\"}","status":"completed"}}"#,
            r#"{"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":2,"input_tokens_details":{"cached_tokens":0}},"output":[{"type":"function_call","id":"fc_9","call_id":"call_9","name":"read_file","arguments":"{\"path\":\"src/lib.rs\"}"}]}}"#,
        ]);
        assert_eq!(tool_shape(&events), ["start", "delta", "end", "done-tool"]);
        match &events[1] {
            Event::ToolUseDelta { json, .. } => assert_eq!(json, r#"{"path":"src/lib.rs"}"#),
            other => panic!("expected the whole arguments once, got {other:?}"),
        }
    }

    #[test]
    fn web_search_notice_carries_the_query_not_the_hits() {
        let events = decode(&[
            r#"{"type":"response.output_item.added","item":{"id":"ws_1","type":"web_search_call","status":"in_progress","action":{"type":"search","query":"","sources":[]}}}"#,
            r#"{"type":"response.output_item.done","item":{"id":"ws_1","type":"web_search_call","status":"completed","action":{"type":"search","query":"grok 4.7 release notes","sources":[{"url":"https://x.ai/news","title":"a long page"}]}}}"#,
            r#"{"type":"response.web_search_call.completed","item_id":"ws_1"}"#,
        ]);
        let uses: Vec<_> = events
            .iter()
            .filter_map(|e| match e {
                Event::ServerToolUse { name, hint, .. } => Some((name.as_str(), hint.as_str())),
                _ => None,
            })
            .collect();
        assert_eq!(uses, vec![("web_search", "grok 4.7 release notes")]);
        assert!(
            !format!("{events:?}").contains("https://x.ai"),
            "search hits must not ride the tool-use event: {events:?}"
        );
    }

    #[test]
    fn function_call_only_on_the_completed_output_still_ends_as_tool_use() {
        let events = decode(&[
            r#"{"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1,"input_tokens_details":{"cached_tokens":0}},"output":[{"type":"function_call","id":"fc_2","call_id":"call_2","name":"shell","arguments":"{\"command\":\"pwd\"}"}]}}"#,
        ]);
        assert_eq!(tool_shape(&events), ["start", "delta", "end", "done-tool"]);
    }
}
