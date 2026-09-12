//! `lvz-gw-acp` — a **Zed Agent Client Protocol (ACP)** agent gateway.
//!
//! The **Agent Client Protocol** (from Zed; <https://agentclientprotocol.com>) lets a code editor
//! drive an AI coding agent that it launches **as a subprocess**, speaking **JSON-RPC 2.0 over
//! stdio**. The editor is the *client*; Lavoisier is the *agent*. Wire an ACP-capable editor (Zed,
//! or Neovim via a bridge) to run `lav --acp` and it gains the full Lavoisier tool loop inside the
//! editor's agent panel — with **zero core change**, like every other gateway.
//!
//! (Not to be confused with IBM/BeeAI's *Agent Communication Protocol*, which shared the acronym —
//! that project folded into A2A, so `--serve-a2a` is the interop server surface now. This `acp` is
//! the editor-facing stdio protocol.)
//!
//! It is a **leaf crate**: it depends only on `lvz-protocol` (the [`Gateway`]/[`AgentHandle`]
//! contracts + the normalised [`Event`] stream), never on a provider or on `lvz-agent`'s internals,
//! so the same shared agent drives the CLI and this gateway unchanged.
//!
//! Surface (client → agent):
//! - `initialize` — capability negotiation. We advertise protocol version `1`, text prompts, and no
//!   auth methods (Lavoisier authenticates to model providers itself, via env keys).
//! - `session/new` — allocate a session id (mapped straight onto a Lavoisier session, so a
//!   multi-turn ACP conversation accrues memory through the shared `SessionAgent`).
//! - `session/prompt` — run one turn. Text/thinking deltas stream out as `session/update`
//!   notifications (`agent_message_chunk` / `agent_thought_chunk`); tool calls surface as
//!   `tool_call` + `tool_call_update` updates; the request resolves with a `stopReason`.
//! - `session/cancel` — a notification that cancels the session's in-flight prompt (dropping the
//!   provider stream cancels the request), which then resolves with `stopReason: "cancelled"`.
//!
//! Deferred (documented, not yet wired): delegating file reads/writes to the editor
//! (`fs/read_text_file` / `fs/write_text_file`) and `session/request_permission` — for now Lavoisier
//! runs its own tools directly, which is a valid ACP posture. `session/load` is likewise not offered
//! (`loadSession: false`). JSON-RPC is **hand-rolled** over `tokio`/`serde_json` — no ACP SDK.

#![warn(missing_docs)]

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};

use async_trait::async_trait;
use futures::stream::StreamExt;
use lvz_protocol::{AgentHandle, Event, Gateway, GatewayError, StopReason, TurnRequest};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::sync::{Mutex as AsyncMutex, Notify};

/// The ACP protocol version this agent implements.
const PROTOCOL_VERSION: u64 = 1;

/// The shared agent, as every handler sees it.
type SharedAgent = Arc<dyn AgentHandle>;

/// A writer shared by the reader loop and every spawned prompt task; the mutex serialises whole
/// JSON-RPC lines so interleaved notifications and responses never corrupt each other.
type SharedWriter = Arc<AsyncMutex<Box<dyn AsyncWrite + Unpin + Send>>>;

/// The Zed ACP agent gateway. Construct with [`AcpGateway::new`], then [`Gateway::serve`] it with
/// an [`AgentHandle`] — it takes over the process's stdin/stdout for the protocol.
#[derive(Default)]
pub struct AcpGateway {
    _private: (),
}

impl AcpGateway {
    /// A new gateway with default configuration.
    pub fn new() -> Self {
        Self::default()
    }
}

#[async_trait]
impl Gateway for AcpGateway {
    fn name(&self) -> &str {
        "acp"
    }

    async fn serve(self: Arc<Self>, agent: SharedAgent) -> Result<(), GatewayError> {
        tracing::info!("Zed ACP agent on stdio (JSON-RPC 2.0)");
        serve_over(
            agent,
            Box::new(tokio::io::stdin()),
            Box::new(tokio::io::stdout()),
        )
        .await
    }
}

/// The transport-agnostic serve loop: read newline-framed JSON-RPC from `reader`, dispatch, and
/// write responses + `session/update` notifications to `writer`. Generic over the pipe so it can be
/// unit-tested over an in-memory duplex instead of real stdio.
///
/// The loop stays responsive while a prompt runs: `session/prompt` is spawned as a task (so a
/// concurrent `session/cancel` can still be read and acted on), and the shared `writer` serialises
/// their output. Ends cleanly on EOF (the editor closing the pipe).
async fn serve_over(
    agent: SharedAgent,
    reader: Box<dyn AsyncRead + Unpin + Send>,
    writer: Box<dyn AsyncWrite + Unpin + Send>,
) -> Result<(), GatewayError> {
    let writer: SharedWriter = Arc::new(AsyncMutex::new(writer));
    let state = Arc::new(ServerState::new(agent));
    let mut lines = BufReader::new(reader).lines();
    while let Some(line) = lines
        .next_line()
        .await
        .map_err(|e| GatewayError::Io(e.to_string()))?
    {
        if line.trim().is_empty() {
            continue;
        }
        let msg: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(e) => {
                // A malformed line has no reliable id to answer; log and keep serving.
                tracing::debug!(error = %e, "acp: unparseable line");
                continue;
            }
        };
        dispatch(&state, &writer, msg).await;
    }
    Ok(())
}

/// Route one inbound JSON-RPC message. Requests carry a non-null `id` and get a response;
/// notifications (no id) do not. Only `session/prompt` is long-running, so only it is spawned.
async fn dispatch(state: &Arc<ServerState>, writer: &SharedWriter, msg: Value) {
    let id = msg.get("id").cloned().filter(|v| !v.is_null());
    let method = msg
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let params = msg.get("params").cloned().unwrap_or(Value::Null);

    match method {
        "initialize" => respond(writer, id, initialize_result()).await,
        // No ACP auth methods are advertised, so `authenticate` is a no-op acknowledgement.
        "authenticate" => respond(writer, id, json!({})).await,
        "session/new" => {
            let session_id = state.new_session();
            tracing::info!(session = %session_id, "acp session/new");
            respond(writer, id, json!({ "sessionId": session_id })).await;
        }
        "session/prompt" => {
            let state = state.clone();
            let writer = writer.clone();
            tokio::spawn(async move { run_prompt(state, writer, id, params).await });
        }
        "session/cancel" => {
            // A notification: no response. Signal the session's in-flight prompt to stop.
            if let Some(session_id) = params.get("sessionId").and_then(Value::as_str) {
                tracing::info!(session = %session_id, "acp session/cancel");
                state.cancel(session_id);
            }
        }
        other => {
            if id.is_some() {
                respond_err(writer, id, -32601, &format!("method not found: {other}")).await;
            }
        }
    }
}

/// The `initialize` result: protocol version, agent capabilities, and (no) auth methods.
fn initialize_result() -> Value {
    json!({
        "protocolVersion": PROTOCOL_VERSION,
        "agentCapabilities": {
            "loadSession": false,
            "promptCapabilities": {
                "image": false,
                "audio": false,
                "embeddedContext": false,
            },
        },
        "authMethods": [],
    })
}

/// Run one `session/prompt` to completion: submit the turn, stream its events as `session/update`
/// notifications, and answer the original request with a `stopReason` (or a JSON-RPC error).
async fn run_prompt(
    state: Arc<ServerState>,
    writer: SharedWriter,
    id: Option<Value>,
    params: Value,
) {
    let Some(session_id) = params
        .get("sessionId")
        .and_then(Value::as_str)
        .map(str::to_string)
    else {
        respond_err(&writer, id, -32602, "missing `sessionId`").await;
        return;
    };
    let text = extract_prompt_text(params.get("prompt"));
    if text.is_empty() {
        respond_err(&writer, id, -32602, "prompt has no text content").await;
        return;
    }

    // Arm cancellation *before* submitting so a race between the turn starting and a cancel arriving
    // is caught (`Notify::notify_one` stores a permit even if we are not yet awaiting it).
    let cancel = state.arm(&session_id);

    let events = match state
        .agent
        .submit(TurnRequest::new(session_id.clone(), text))
        .await
    {
        Ok(s) => s,
        Err(e) => {
            state.disarm(&session_id);
            respond_err(&writer, id, -32603, &e.to_string()).await;
            return;
        }
    };

    let result = stream_updates(&writer, &session_id, events, cancel).await;
    state.disarm(&session_id);
    match result {
        Ok(stop_reason) => respond(&writer, id, json!({ "stopReason": stop_reason })).await,
        Err(e) => respond_err(&writer, id, -32603, &e).await,
    }
}

/// Consume the agent's event stream, emitting one `session/update` per relevant [`Event`], until the
/// turn ends, is cancelled, or errors. Returns the ACP `stopReason` on a clean finish.
async fn stream_updates(
    writer: &SharedWriter,
    session_id: &str,
    mut events: futures::stream::BoxStream<'static, Result<Event, lvz_protocol::AgentError>>,
    cancel: Arc<Notify>,
) -> Result<&'static str, String> {
    // Accumulated tool-argument JSON per call id, so `tool_call_update` can carry the whole input.
    let mut tool_args: HashMap<String, String> = HashMap::new();
    let mut stop_reason = "end_turn";
    loop {
        tokio::select! {
            biased;
            // Cancellation wins the race: drop the stream (cancelling the provider request) and stop.
            _ = cancel.notified() => {
                return Ok("cancelled");
            }
            item = events.next() => match item {
                None => break,
                Some(Ok(event)) => {
                    if let Some(update) = event_to_update(&event, &mut tool_args) {
                        notify(writer, "session/update", json!({
                            "sessionId": session_id,
                            "update": update,
                        }))
                        .await;
                    }
                    if let Event::Done(reason) = event {
                        stop_reason = map_stop_reason(&reason);
                    }
                }
                Some(Err(e)) => return Err(e.to_string()),
            }
        }
    }
    Ok(stop_reason)
}

/// Translate one [`Event`] into an ACP `session/update` payload, or `None` for events ACP has no
/// slot for (usage, citations — informational, folded away for now).
fn event_to_update(event: &Event, tool_args: &mut HashMap<String, String>) -> Option<Value> {
    match event {
        Event::TextDelta(t) => Some(json!({
            "sessionUpdate": "agent_message_chunk",
            "content": { "type": "text", "text": t },
        })),
        Event::Thinking(t) | Event::Notice(t) => Some(json!({
            "sessionUpdate": "agent_thought_chunk",
            "content": { "type": "text", "text": t },
        })),
        Event::ToolUseStart { id, name } | Event::ServerToolUse { id, name } => Some(json!({
            "sessionUpdate": "tool_call",
            "toolCallId": id,
            "title": name,
            "kind": tool_kind(name),
            "status": "in_progress",
        })),
        Event::ToolUseDelta { id, json } => {
            tool_args.entry(id.clone()).or_default().push_str(json);
            None
        }
        Event::ToolUseEnd { id } => {
            // The call's arguments are now whole. Surface the parsed input if it parses.
            let raw_input = tool_args
                .remove(id)
                .and_then(|s| serde_json::from_str::<Value>(&s).ok());
            let mut update = json!({
                "sessionUpdate": "tool_call_update",
                "toolCallId": id,
                "status": "completed",
            });
            if let Some(input) = raw_input {
                update["rawInput"] = input;
            }
            Some(update)
        }
        Event::ServerToolResult { id, content } => Some(json!({
            "sessionUpdate": "tool_call_update",
            "toolCallId": id,
            "status": "completed",
            "content": [{ "type": "content", "content": { "type": "text", "text": content } }],
        })),
        // Usage/Citation/Done carry no user-visible update chunk of their own.
        _ => None,
    }
}

/// Best-effort mapping of a Lavoisier tool name onto an ACP tool-call `kind` (drives the editor's
/// icon/label). Unknown tools fall to `other`.
fn tool_kind(name: &str) -> &'static str {
    match name {
        n if n.starts_with("read") || n.starts_with("outline") || n.starts_with("list") => "read",
        n if n.starts_with("write")
            || n.starts_with("edit")
            || n.starts_with("batch_edit")
            || n.starts_with("apply") =>
        {
            "edit"
        }
        n if n.starts_with("find") || n.starts_with("grep") || n.starts_with("search") => "search",
        "shell" | "bash" => "execute",
        _ => "other",
    }
}

/// Map a Lavoisier [`StopReason`] onto an ACP `stopReason`. ACP has a narrower set — the extras all
/// fold to the natural end of a turn.
fn map_stop_reason(reason: &StopReason) -> &'static str {
    match reason {
        StopReason::MaxTokens => "max_tokens",
        StopReason::Refusal => "refusal",
        // EndTurn / ToolUse / StopSequence / PauseTurn / Other all present as a completed turn.
        _ => "end_turn",
    }
}

/// Pull the text out of an ACP prompt (an array of content blocks): concatenate every `text` block.
fn extract_prompt_text(prompt: Option<&Value>) -> String {
    let Some(blocks) = prompt.and_then(Value::as_array) else {
        return String::new();
    };
    let mut text = String::new();
    for block in blocks {
        let kind = block.get("type").and_then(Value::as_str);
        // A plain text block, or a `resource` block whose embedded resource is text.
        if kind == Some("text") || kind.is_none() {
            if let Some(t) = block.get("text").and_then(Value::as_str) {
                text.push_str(t);
            }
        } else if kind == Some("resource") {
            if let Some(t) = block
                .get("resource")
                .and_then(|r| r.get("text"))
                .and_then(Value::as_str)
            {
                text.push_str(t);
            }
        }
    }
    text
}

// --- JSON-RPC write helpers ---

/// Write a JSON-RPC success response.
async fn respond(writer: &SharedWriter, id: Option<Value>, result: Value) {
    write_line(
        writer,
        &json!({ "jsonrpc": "2.0", "id": id.unwrap_or(Value::Null), "result": result }),
    )
    .await;
}

/// Write a JSON-RPC error response.
async fn respond_err(writer: &SharedWriter, id: Option<Value>, code: i64, message: &str) {
    write_line(
        writer,
        &json!({
            "jsonrpc": "2.0",
            "id": id.unwrap_or(Value::Null),
            "error": { "code": code, "message": message },
        }),
    )
    .await;
}

/// Write a JSON-RPC notification (no id).
async fn notify(writer: &SharedWriter, method: &str, params: Value) {
    write_line(
        writer,
        &json!({ "jsonrpc": "2.0", "method": method, "params": params }),
    )
    .await;
}

/// Serialise one message and write it as a newline-framed line, flushing so the editor sees it at
/// once. A write failure (the editor closed the pipe) is logged, not fatal — the reader loop's EOF
/// is the authoritative end-of-serve.
async fn write_line(writer: &SharedWriter, msg: &Value) {
    let mut line = serde_json::to_string(msg).expect("json-rpc message serialises");
    line.push('\n');
    let mut w = writer.lock().await;
    if let Err(e) = w.write_all(line.as_bytes()).await {
        tracing::debug!(error = %e, "acp: write failed");
        return;
    }
    let _ = w.flush().await;
}

/// Per-connection server state: the shared agent, a session-id counter, and the set of in-flight
/// prompts (so a `session/cancel` can find and stop one).
struct ServerState {
    agent: SharedAgent,
    next_session: AtomicU64,
    /// sessionId → its in-flight prompt's cancellation handle. Present only while a prompt runs.
    prompts: StdMutex<HashMap<String, Arc<Notify>>>,
}

impl ServerState {
    fn new(agent: SharedAgent) -> Self {
        Self {
            agent,
            next_session: AtomicU64::new(1),
            prompts: StdMutex::new(HashMap::new()),
        }
    }

    fn new_session(&self) -> String {
        format!("acp-{}", self.next_session.fetch_add(1, Ordering::Relaxed))
    }

    /// Register a cancellation handle for `session`'s prompt, returning it for the stream loop to
    /// await. Replaces any prior handle for the same session (a new prompt supersedes the old).
    fn arm(&self, session: &str) -> Arc<Notify> {
        let notify = Arc::new(Notify::new());
        self.prompts
            .lock()
            .expect("acp prompts poisoned")
            .insert(session.to_string(), notify.clone());
        notify
    }

    fn disarm(&self, session: &str) {
        self.prompts
            .lock()
            .expect("acp prompts poisoned")
            .remove(session);
    }

    /// Signal `session`'s in-flight prompt to cancel. `notify_one` stores a permit if the stream is
    /// momentarily between awaits, so the cancel is never lost to a race.
    fn cancel(&self, session: &str) {
        if let Some(notify) = self
            .prompts
            .lock()
            .expect("acp prompts poisoned")
            .get(session)
        {
            notify.notify_one();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::stream::{self, BoxStream};
    use lvz_protocol::AgentError;
    use tokio::io::{split, AsyncBufReadExt, AsyncWriteExt, BufReader};

    /// A stub agent streaming a scripted event list, so the gateway is testable without a provider.
    struct StubAgent(Vec<Event>);
    #[async_trait]
    impl AgentHandle for StubAgent {
        async fn submit(
            &self,
            _turn: TurnRequest,
        ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError> {
            let events: Vec<_> = self.0.iter().cloned().map(Ok).collect();
            Ok(stream::iter(events).boxed())
        }
    }

    /// Drive the gateway over a duplex: return a client that can write requests and read reply lines.
    fn spawn(agent: SharedAgent) -> Client {
        let (server_end, client_end) = tokio::io::duplex(64 * 1024);
        let (sr, sw) = split(server_end);
        tokio::spawn(async move { serve_over(agent, Box::new(sr), Box::new(sw)).await });
        let (cr, cw) = split(client_end);
        Client {
            reader: BufReader::new(Box::new(cr)),
            writer: Box::new(cw),
        }
    }

    struct Client {
        reader: BufReader<Box<dyn AsyncRead + Unpin + Send>>,
        writer: Box<dyn AsyncWrite + Unpin + Send>,
    }
    impl Client {
        async fn send(&mut self, msg: Value) {
            let mut line = msg.to_string();
            line.push('\n');
            self.writer.write_all(line.as_bytes()).await.unwrap();
            self.writer.flush().await.unwrap();
        }
        /// Read one reply line as JSON.
        async fn recv(&mut self) -> Value {
            let mut line = String::new();
            self.reader.read_line(&mut line).await.unwrap();
            serde_json::from_str(&line).unwrap()
        }
        /// Read reply lines until one carries a `result` (a response), collecting notifications seen.
        async fn recv_until_result(&mut self) -> (Vec<Value>, Value) {
            let mut notes = Vec::new();
            loop {
                let v = self.recv().await;
                if v.get("result").is_some() || v.get("error").is_some() {
                    return (notes, v);
                }
                notes.push(v);
            }
        }
    }

    #[tokio::test]
    async fn initialize_advertises_protocol_and_no_auth() {
        let mut c = spawn(Arc::new(StubAgent(vec![])));
        c.send(json!({ "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {} }))
            .await;
        let resp = c.recv().await;
        assert_eq!(resp["result"]["protocolVersion"], PROTOCOL_VERSION);
        assert_eq!(resp["result"]["authMethods"], json!([]));
        assert_eq!(resp["result"]["agentCapabilities"]["loadSession"], false);
    }

    #[tokio::test]
    async fn new_session_then_prompt_streams_message_chunks_and_ends() {
        let mut c = spawn(Arc::new(StubAgent(vec![
            Event::TextDelta("the answer ".into()),
            Event::TextDelta("is 42".into()),
            Event::Done(StopReason::EndTurn),
        ])));
        c.send(json!({ "jsonrpc": "2.0", "id": 1, "method": "session/new", "params": {} }))
            .await;
        let sid = c.recv().await["result"]["sessionId"]
            .as_str()
            .unwrap()
            .to_string();
        assert!(sid.starts_with("acp-"));

        c.send(json!({
            "jsonrpc": "2.0", "id": 2, "method": "session/prompt",
            "params": { "sessionId": sid, "prompt": [{ "type": "text", "text": "hi" }] }
        }))
        .await;
        let (notes, resp) = c.recv_until_result().await;
        // The two deltas arrive as agent_message_chunk updates on this session.
        let text: String = notes
            .iter()
            .filter(|n| n["params"]["update"]["sessionUpdate"] == "agent_message_chunk")
            .filter_map(|n| n["params"]["update"]["content"]["text"].as_str())
            .collect();
        assert_eq!(text, "the answer is 42");
        assert!(notes
            .iter()
            .all(|n| n["params"]["sessionId"].as_str() == Some(sid.as_str())));
        assert_eq!(resp["result"]["stopReason"], "end_turn");
    }

    #[tokio::test]
    async fn tool_calls_surface_as_tool_call_updates() {
        let mut c = spawn(Arc::new(StubAgent(vec![
            Event::ToolUseStart {
                id: "call_1".into(),
                name: "read_file".into(),
            },
            Event::ToolUseDelta {
                id: "call_1".into(),
                json: "{\"path\":\"a.rs\"}".into(),
            },
            Event::ToolUseEnd {
                id: "call_1".into(),
            },
            Event::TextDelta("done".into()),
            Event::Done(StopReason::EndTurn),
        ])));
        c.send(json!({
            "jsonrpc": "2.0", "id": 1, "method": "session/prompt",
            "params": { "sessionId": "acp-1", "prompt": [{ "type": "text", "text": "read it" }] }
        }))
        .await;
        let (notes, resp) = c.recv_until_result().await;
        let start = notes
            .iter()
            .find(|n| n["params"]["update"]["sessionUpdate"] == "tool_call")
            .expect("a tool_call update");
        assert_eq!(start["params"]["update"]["toolCallId"], "call_1");
        assert_eq!(start["params"]["update"]["kind"], "read");
        let end = notes
            .iter()
            .find(|n| n["params"]["update"]["sessionUpdate"] == "tool_call_update")
            .expect("a tool_call_update");
        assert_eq!(end["params"]["update"]["status"], "completed");
        // The accumulated argument JSON is surfaced as rawInput.
        assert_eq!(end["params"]["update"]["rawInput"]["path"], "a.rs");
        assert_eq!(resp["result"]["stopReason"], "end_turn");
    }

    #[tokio::test]
    async fn refusal_maps_to_the_refusal_stop_reason() {
        let mut c = spawn(Arc::new(StubAgent(vec![Event::Done(StopReason::Refusal)])));
        c.send(json!({
            "jsonrpc": "2.0", "id": 1, "method": "session/prompt",
            "params": { "sessionId": "acp-1", "prompt": [{ "type": "text", "text": "x" }] }
        }))
        .await;
        let (_notes, resp) = c.recv_until_result().await;
        assert_eq!(resp["result"]["stopReason"], "refusal");
    }

    #[tokio::test]
    async fn empty_prompt_is_an_invalid_params_error() {
        let mut c = spawn(Arc::new(StubAgent(vec![])));
        c.send(json!({
            "jsonrpc": "2.0", "id": 5, "method": "session/prompt",
            "params": { "sessionId": "acp-1", "prompt": [] }
        }))
        .await;
        let resp = c.recv().await;
        assert_eq!(resp["error"]["code"], -32602);
    }

    #[tokio::test]
    async fn unknown_method_is_a_minus_32601() {
        let mut c = spawn(Arc::new(StubAgent(vec![])));
        c.send(json!({ "jsonrpc": "2.0", "id": 9, "method": "frobnicate", "params": {} }))
            .await;
        let resp = c.recv().await;
        assert_eq!(resp["error"]["code"], -32601);
    }

    #[test]
    fn tool_kinds_map_sensibly() {
        assert_eq!(tool_kind("read_files"), "read");
        assert_eq!(tool_kind("edit_files"), "edit");
        assert_eq!(tool_kind("find_references"), "search");
        assert_eq!(tool_kind("shell"), "execute");
        assert_eq!(tool_kind("whatever"), "other");
    }

    #[test]
    fn prompt_text_extraction_reads_text_blocks() {
        let prompt = json!([
            { "type": "text", "text": "hello " },
            { "type": "resource_link", "uri": "file:///x" },
            { "type": "text", "text": "world" },
        ]);
        assert_eq!(extract_prompt_text(Some(&prompt)), "hello world");
        assert_eq!(extract_prompt_text(None), "");
    }
}
