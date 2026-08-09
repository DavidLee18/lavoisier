//! `lvz-gw-a2a` — an **A2A (Agent-to-Agent) server** gateway.
//!
//! A concrete [`Gateway`] that exposes the shared agent as a Google **A2A** agent so other agents
//! can discover and delegate tasks to it. It depends only on `lvz-protocol` (the
//! [`Gateway`]/[`AgentHandle`] contracts + the normalised [`Event`] stream) — never on a provider or
//! on `lvz-agent`'s internals — so the same agent core drives the CLI and this gateway unchanged.
//!
//! Surface:
//! - `GET  /.well-known/agent-card.json` — the **Agent Card** (discovery): name, version, skills,
//!   and `capabilities.streaming = true`.
//! - `POST /` — a **JSON-RPC 2.0** endpoint:
//!   - `message/send` — run one turn, return a completed `Task` carrying the agent's reply.
//!   - `message/stream` — run one turn, stream A2A status/artifact update events over SSE.
//!   - `tasks/get` — look up a previously-returned task by id.
//!   - `tasks/cancel` — best-effort; a completed task cannot be cancelled.
//!
//! The A2A `contextId` maps to a Lavoisier session, so a multi-turn A2A conversation accrues memory.
//! JSON-RPC is hand-rolled over `axum`/`serde_json` — no A2A SDK.

#![warn(missing_docs)]

use std::collections::{HashSet, VecDeque};
use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use axum::{
    extract::State,
    http::{header::AUTHORIZATION, HeaderMap, StatusCode},
    response::{
        sse::{Event as SseEvent, Sse},
        IntoResponse, Response,
    },
    routing::{get, post},
    Json, Router,
};
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{AgentHandle, Event, Gateway, GatewayError, TurnRequest};
use serde_json::{json, Value};

/// The A2A protocol version advertised on the Agent Card.
const A2A_PROTOCOL_VERSION: &str = "0.3.0";

/// How many completed tasks the in-memory store keeps for `tasks/get` before evicting the oldest.
const TASK_STORE_CAP: usize = 256;

/// The shared agent, as every handler sees it.
type SharedAgent = Arc<dyn AgentHandle>;

/// Customisable fields of the Agent Card.
#[derive(Clone)]
struct CardConfig {
    name: String,
    description: String,
    /// Public base URL other agents reach this server at; defaults to `http://<bind-addr>/`.
    url: Option<String>,
    version: String,
}

impl Default for CardConfig {
    fn default() -> Self {
        Self {
            name: "Lavoisier".into(),
            description: "Token-efficient CLI coding agent, exposed over A2A.".into(),
            url: None,
            version: env!("CARGO_PKG_VERSION").into(),
        }
    }
}

/// The A2A server gateway. Construct with a bind address, then [`Gateway::serve`] it with an
/// [`AgentHandle`].
pub struct A2aGateway {
    addr: SocketAddr,
    api_keys: HashSet<String>,
    card: CardConfig,
}

impl A2aGateway {
    /// Bind-address constructor with an open (no-auth) policy and the default Agent Card.
    pub fn new(addr: SocketAddr) -> Self {
        Self {
            addr,
            api_keys: HashSet::new(),
            card: CardConfig::default(),
        }
    }

    /// Parse a `host:port` string into a gateway, surfacing a [`GatewayError::Bind`] on a malformed
    /// address.
    pub fn bind(addr: &str) -> Result<Self, GatewayError> {
        let addr = addr
            .parse()
            .map_err(|e: std::net::AddrParseError| GatewayError::Bind(e.to_string()))?;
        Ok(Self::new(addr))
    }

    /// Require one of these API keys (sent as `Authorization: Bearer <key>`) on the JSON-RPC
    /// endpoint. An empty set (the default) leaves the gateway open.
    pub fn with_api_keys<I: IntoIterator<Item = String>>(mut self, keys: I) -> Self {
        self.api_keys = keys.into_iter().collect();
        self
    }

    /// Override the Agent Card's advertised name.
    pub fn with_name(mut self, name: impl Into<String>) -> Self {
        self.card.name = name.into();
        self
    }

    /// Override the Agent Card's description.
    pub fn with_description(mut self, description: impl Into<String>) -> Self {
        self.card.description = description.into();
        self
    }

    /// Set the public base URL advertised in the Agent Card (else derived from the bind address).
    pub fn with_public_url(mut self, url: impl Into<String>) -> Self {
        self.card.url = Some(url.into());
        self
    }

    fn card_json(&self) -> Value {
        let url = self
            .card
            .url
            .clone()
            .unwrap_or_else(|| format!("http://{}/", self.addr));
        json!({
            "protocolVersion": A2A_PROTOCOL_VERSION,
            "name": self.card.name,
            "description": self.card.description,
            "url": url,
            "version": self.card.version,
            "capabilities": { "streaming": true, "pushNotifications": false },
            "defaultInputModes": ["text/plain"],
            "defaultOutputModes": ["text/plain"],
            "skills": [{
                "id": "general",
                "name": "General assistant",
                "description": "Answers questions and carries out coding tasks with the full tool loop.",
                "tags": ["coding", "general"],
            }],
        })
    }

    /// Build the router for a given agent (exposed so tests can mount it on their own listener).
    fn router(&self, agent: SharedAgent) -> Router {
        let state = Arc::new(AppState {
            agent,
            card: self.card_json(),
            api_keys: self.api_keys.clone(),
            tasks: Mutex::new(VecDeque::new()),
            ids: AtomicU64::new(1),
        });
        Router::new()
            .route("/.well-known/agent-card.json", get(agent_card))
            .route("/", post(rpc))
            .with_state(state)
    }
}

#[async_trait]
impl Gateway for A2aGateway {
    fn name(&self) -> &str {
        "a2a"
    }

    async fn serve(self: Arc<Self>, agent: SharedAgent) -> Result<(), GatewayError> {
        let app = self.router(agent);
        let listener = tokio::net::TcpListener::bind(self.addr)
            .await
            .map_err(|e| GatewayError::Bind(e.to_string()))?;
        tracing::info!(addr = %self.addr, "A2A gateway listening (GET /.well-known/agent-card.json, POST /)");
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))
    }
}

/// Shared handler state.
struct AppState {
    agent: SharedAgent,
    card: Value,
    api_keys: HashSet<String>,
    /// Completed tasks, newest last, for `tasks/get`. Bounded by [`TASK_STORE_CAP`].
    tasks: Mutex<VecDeque<(String, Value)>>,
    ids: AtomicU64,
}

impl AppState {
    fn next(&self, prefix: &str) -> String {
        format!("{prefix}-{}", self.ids.fetch_add(1, Ordering::Relaxed))
    }

    fn store_task(&self, id: &str, task: Value) {
        let mut store = self.tasks.lock().expect("a2a task store poisoned");
        store.push_back((id.to_string(), task));
        while store.len() > TASK_STORE_CAP {
            store.pop_front();
        }
    }

    fn get_task(&self, id: &str) -> Option<Value> {
        let store = self.tasks.lock().expect("a2a task store poisoned");
        store
            .iter()
            .rev()
            .find(|(tid, _)| tid == id)
            .map(|(_, t)| t.clone())
    }

    /// Enforce the API-key policy: open when no keys are configured, else a matching
    /// `Authorization: Bearer <key>` is required.
    fn authorized(&self, headers: &HeaderMap) -> bool {
        if self.api_keys.is_empty() {
            return true;
        }
        headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .is_some_and(|key| self.api_keys.contains(key))
    }
}

/// `GET /.well-known/agent-card.json` — the discovery document.
async fn agent_card(State(state): State<Arc<AppState>>) -> Json<Value> {
    Json(state.card.clone())
}

/// `POST /` — the JSON-RPC 2.0 endpoint. Dispatches to the A2A method set.
async fn rpc(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(req): Json<Value>,
) -> Response {
    if !state.authorized(&headers) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "error": "missing or invalid API key" })),
        )
            .into_response();
    }
    let id = req.get("id").cloned().unwrap_or(Value::Null);
    let method = req
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let params = req.get("params").cloned().unwrap_or(Value::Null);

    match method {
        "message/send" => message_send(&state, id, &params).await,
        "message/stream" => message_stream(&state, id, &params).await,
        "tasks/get" => tasks_get(&state, id, &params),
        "tasks/cancel" => tasks_cancel(&state, id, &params),
        other => rpc_error(id, -32601, &format!("method not found: {other}")).into_response(),
    }
}

/// `message/send`: run one turn to completion and return a `Task` carrying the agent's reply.
async fn message_send(state: &Arc<AppState>, id: Value, params: &Value) -> Response {
    let (text, context_id) = match parse_message(state, params) {
        Ok(v) => v,
        Err(e) => return rpc_error(id, -32602, &e).into_response(),
    };
    let user_msg = params.get("message").cloned().unwrap_or(Value::Null);
    let task_id = state.next("task");

    let answer = match run_turn(state, &context_id, &text).await {
        Ok(answer) => answer,
        Err(e) => return rpc_error(id, -32603, &e).into_response(),
    };

    let agent_msg = agent_message(state, &answer, &task_id, &context_id);
    let task = json!({
        "id": task_id,
        "contextId": context_id,
        "kind": "task",
        "status": { "state": "completed", "message": agent_msg },
        "history": [user_msg, agent_msg],
        "artifacts": [{
            "artifactId": state.next("artifact"),
            "parts": [{ "kind": "text", "text": answer }],
        }],
    });
    state.store_task(&task_id, task.clone());
    Json(rpc_ok(id, task)).into_response()
}

/// `message/stream`: run one turn and stream A2A status/artifact updates over SSE.
async fn message_stream(state: &Arc<AppState>, id: Value, params: &Value) -> Response {
    let (text, context_id) = match parse_message(state, params) {
        Ok(v) => v,
        Err(e) => return rpc_error(id, -32602, &e).into_response(),
    };
    let task_id = state.next("task");
    let artifact_id = state.next("artifact");

    let events = match state
        .agent
        .submit(TurnRequest::new(context_id.clone(), text))
        .await
    {
        Ok(s) => s,
        Err(e) => {
            let frame = rpc_ok(id, status_update(&task_id, &context_id, "failed", true));
            let _ = e; // the failure is surfaced as a `failed` status; detail is logged upstream.
            return Sse::new(once_frame(frame)).into_response();
        }
    };

    // Head: a `working` status-update. Body: one artifact-update per text delta. Tail: `completed`.
    let head_id = id.clone();
    let head = stream::once({
        let f = rpc_ok(
            head_id,
            status_update(&task_id, &context_id, "working", false),
        );
        async move { Ok::<_, Infallible>(sse_data(&f)) }
    });

    let body_id = id.clone();
    let body_task = task_id.clone();
    let body_ctx = context_id.clone();
    let body = events.filter_map(move |item| {
        let rpc_id = body_id.clone();
        let task_id = body_task.clone();
        let ctx = body_ctx.clone();
        let artifact_id = artifact_id.clone();
        async move {
            match item {
                Ok(Event::TextDelta(t)) => {
                    let ev = artifact_update(&task_id, &ctx, &artifact_id, &t);
                    Some(Ok::<_, Infallible>(sse_data(&rpc_ok(rpc_id, ev))))
                }
                _ => None,
            }
        }
    });

    let tail = stream::once({
        let f = rpc_ok(id, status_update(&task_id, &context_id, "completed", true));
        async move { Ok::<_, Infallible>(sse_data(&f)) }
    });

    let full: BoxStream<'static, Result<SseEvent, Infallible>> =
        head.chain(body).chain(tail).boxed();
    Sse::new(full).into_response()
}

/// `tasks/get`: return a previously-stored task, or a task-not-found error.
fn tasks_get(state: &Arc<AppState>, id: Value, params: &Value) -> Response {
    let task_id = params.get("id").and_then(Value::as_str).unwrap_or_default();
    match state.get_task(task_id) {
        Some(task) => Json(rpc_ok(id, task)).into_response(),
        None => rpc_error(id, -32001, &format!("task not found: {task_id}")).into_response(),
    }
}

/// `tasks/cancel`: best-effort. A stored (completed) task cannot be cancelled.
fn tasks_cancel(state: &Arc<AppState>, id: Value, params: &Value) -> Response {
    let task_id = params.get("id").and_then(Value::as_str).unwrap_or_default();
    match state.get_task(task_id) {
        Some(_) => {
            rpc_error(id, -32002, "task cannot be cancelled (already completed)").into_response()
        }
        None => rpc_error(id, -32001, &format!("task not found: {task_id}")).into_response(),
    }
}

// --- helpers ---

/// Submit a turn and fold its text deltas into the final answer (other events are internal).
async fn run_turn(state: &Arc<AppState>, session: &str, input: &str) -> Result<String, String> {
    let mut stream = state
        .agent
        .submit(TurnRequest::new(session.to_string(), input.to_string()))
        .await
        .map_err(|e| e.to_string())?;
    let mut answer = String::new();
    while let Some(item) = stream.next().await {
        match item {
            Ok(Event::TextDelta(t)) => answer.push_str(&t),
            Ok(_) => {}
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok(answer.trim().to_string())
}

/// Pull the text from an A2A message's parts and resolve its context id (generating one if absent).
fn parse_message(state: &Arc<AppState>, params: &Value) -> Result<(String, String), String> {
    let message = params
        .get("message")
        .ok_or_else(|| "missing `message`".to_string())?;
    let parts = message
        .get("parts")
        .and_then(Value::as_array)
        .ok_or_else(|| "message has no `parts`".to_string())?;
    let text: String = parts
        .iter()
        .filter(|p| {
            let kind = p
                .get("kind")
                .or_else(|| p.get("type"))
                .and_then(Value::as_str);
            kind == Some("text")
        })
        .filter_map(|p| p.get("text").and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join("");
    if text.is_empty() {
        return Err("message has no text part".to_string());
    }
    let context_id = message
        .get("contextId")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| state.next("ctx"));
    Ok((text, context_id))
}

/// Build an A2A agent `Message` object.
fn agent_message(state: &Arc<AppState>, text: &str, task_id: &str, context_id: &str) -> Value {
    json!({
        "role": "agent",
        "parts": [{ "kind": "text", "text": text }],
        "messageId": state.next("msg"),
        "taskId": task_id,
        "contextId": context_id,
        "kind": "message",
    })
}

/// A `TaskStatusUpdateEvent`.
fn status_update(task_id: &str, context_id: &str, state_name: &str, final_: bool) -> Value {
    json!({
        "taskId": task_id,
        "contextId": context_id,
        "kind": "status-update",
        "status": { "state": state_name },
        "final": final_,
    })
}

/// A `TaskArtifactUpdateEvent` carrying one text chunk.
fn artifact_update(task_id: &str, context_id: &str, artifact_id: &str, text: &str) -> Value {
    json!({
        "taskId": task_id,
        "contextId": context_id,
        "kind": "artifact-update",
        "artifact": { "artifactId": artifact_id, "parts": [{ "kind": "text", "text": text }] },
        "append": true,
        "lastChunk": false,
    })
}

fn rpc_ok(id: Value, result: Value) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "result": result })
}

fn rpc_error(id: Value, code: i64, message: &str) -> Json<Value> {
    Json(json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } }))
}

fn sse_data(frame: &Value) -> SseEvent {
    SseEvent::default().data(frame.to_string())
}

fn once_frame(frame: Value) -> BoxStream<'static, Result<SseEvent, Infallible>> {
    stream::once(async move { Ok(sse_data(&frame)) }).boxed()
}

/// Resolve when the process is asked to terminate (SIGTERM/Ctrl-C), so the serve loop can shut down
/// gracefully under the CLI's `select_all` join.
async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        match signal(SignalKind::terminate()) {
            Ok(mut term) => {
                tokio::select! {
                    _ = term.recv() => {}
                    _ = tokio::signal::ctrl_c() => {}
                }
            }
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::stream::BoxStream;
    use lvz_protocol::{AgentError, StopReason};

    /// A stub agent that streams a fixed answer, so the gateway can be tested without a provider.
    struct StubAgent(&'static str);
    #[async_trait]
    impl AgentHandle for StubAgent {
        async fn submit(
            &self,
            _turn: TurnRequest,
        ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError> {
            let answer = self.0.to_string();
            Ok(stream::iter(vec![
                Ok(Event::TextDelta(answer)),
                Ok(Event::Done(StopReason::EndTurn)),
            ])
            .boxed())
        }
    }

    async fn spawn(agent: SharedAgent) -> (String, tokio::task::JoinHandle<()>) {
        let gw = A2aGateway::bind("127.0.0.1:0").unwrap();
        let app = gw.router(agent);
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let handle = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        (format!("http://{addr}"), handle)
    }

    #[tokio::test]
    async fn serves_the_agent_card() {
        let agent: SharedAgent = Arc::new(StubAgent("hi"));
        let (base, _h) = spawn(agent).await;
        let card: Value = reqwest::get(format!("{base}/.well-known/agent-card.json"))
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(card["name"], "Lavoisier");
        assert_eq!(card["capabilities"]["streaming"], true);
        assert!(card["skills"].is_array());
    }

    #[tokio::test]
    async fn message_send_returns_a_completed_task() {
        let agent: SharedAgent = Arc::new(StubAgent("the answer is 42"));
        let (base, _h) = spawn(agent).await;
        let req = json!({
            "jsonrpc": "2.0", "id": 1, "method": "message/send",
            "params": { "message": { "role": "user", "parts": [{ "kind": "text", "text": "hi" }] } }
        });
        let resp: Value = reqwest::Client::new()
            .post(&base)
            .json(&req)
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(resp["result"]["status"]["state"], "completed");
        assert_eq!(
            resp["result"]["artifacts"][0]["parts"][0]["text"],
            "the answer is 42"
        );
        // The task is retrievable by id.
        let task_id = resp["result"]["id"].as_str().unwrap().to_string();
        let get = json!({ "jsonrpc": "2.0", "id": 2, "method": "tasks/get", "params": { "id": task_id } });
        let got: Value = reqwest::Client::new()
            .post(&base)
            .json(&get)
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(got["result"]["status"]["state"], "completed");
    }

    #[tokio::test]
    async fn message_stream_yields_sse_ending_in_completed() {
        let agent: SharedAgent = Arc::new(StubAgent("streamed"));
        let (base, _h) = spawn(agent).await;
        let req = json!({
            "jsonrpc": "2.0", "id": 7, "method": "message/stream",
            "params": { "message": { "role": "user", "parts": [{ "kind": "text", "text": "go" }] } }
        });
        let body = reqwest::Client::new()
            .post(&base)
            .json(&req)
            .send()
            .await
            .unwrap()
            .text()
            .await
            .unwrap();
        assert!(body.contains("working"));
        assert!(body.contains("streamed"));
        assert!(body.contains("completed"));
    }

    #[tokio::test]
    async fn unknown_method_is_a_minus_32601() {
        let agent: SharedAgent = Arc::new(StubAgent("x"));
        let (base, _h) = spawn(agent).await;
        let req = json!({ "jsonrpc": "2.0", "id": 9, "method": "frobnicate", "params": {} });
        let resp: Value = reqwest::Client::new()
            .post(&base)
            .json(&req)
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(resp["error"]["code"], -32601);
    }
}
