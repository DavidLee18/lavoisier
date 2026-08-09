//! `lvz-gw-acp` — an **ACP (Agent Communication Protocol) server** gateway.
//!
//! The **Agent Communication Protocol** (BeeAI/IBM) is a REST protocol for agent interoperability:
//! an agent publishes a manifest and accepts *runs*. This is a concrete [`Gateway`] that exposes the
//! shared agent over that surface, depending only on `lvz-protocol` (the [`Gateway`]/[`AgentHandle`]
//! contracts + the normalised [`Event`] stream) — never on a provider or on `lvz-agent`'s internals.
//!
//! Surface:
//! - `GET  /agents` and `GET /agents/{name}` — the agent **manifest(s)** (discovery).
//! - `POST /runs` — create a run: `{ agent_name, input: [Message], mode, session_id? }`.
//!   - `mode: "sync"` (default) — run to completion, return the finished `Run`.
//!   - `mode: "stream"` — stream ACP run events over SSE.
//!   - `mode: "async"` — return a created run immediately; poll `GET /runs/{run_id}`.
//! - `GET  /runs/{run_id}` — a run's current state; `POST /runs/{run_id}/cancel` — best-effort.
//! - `GET  /ping` — liveness.
//!
//! The ACP `session_id` maps to a Lavoisier session, so multi-run conversations accrue memory. The
//! REST surface is hand-rolled over `axum`/`serde_json` — no ACP SDK.

#![warn(missing_docs)]

use std::collections::{HashSet, VecDeque};
use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use axum::{
    extract::{Path, State},
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

/// The single agent this gateway advertises.
const AGENT_NAME: &str = "lavoisier";

/// How many runs the in-memory store keeps for `GET /runs/{id}` before evicting the oldest.
const RUN_STORE_CAP: usize = 256;

/// The shared agent, as every handler sees it.
type SharedAgent = Arc<dyn AgentHandle>;

/// Customisable manifest fields.
#[derive(Clone)]
struct ManifestConfig {
    description: String,
}

impl Default for ManifestConfig {
    fn default() -> Self {
        Self {
            description: "Token-efficient CLI coding agent, exposed over ACP.".into(),
        }
    }
}

/// The ACP server gateway. Construct with a bind address, then [`Gateway::serve`] it with an
/// [`AgentHandle`].
pub struct AcpGateway {
    addr: SocketAddr,
    api_keys: HashSet<String>,
    manifest: ManifestConfig,
}

impl AcpGateway {
    /// Bind-address constructor with an open (no-auth) policy and the default manifest.
    pub fn new(addr: SocketAddr) -> Self {
        Self {
            addr,
            api_keys: HashSet::new(),
            manifest: ManifestConfig::default(),
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

    /// Require one of these API keys (sent as `Authorization: Bearer <key>`) on the `/runs` routes.
    /// An empty set (the default) leaves the gateway open.
    pub fn with_api_keys<I: IntoIterator<Item = String>>(mut self, keys: I) -> Self {
        self.api_keys = keys.into_iter().collect();
        self
    }

    /// Override the manifest description.
    pub fn with_description(mut self, description: impl Into<String>) -> Self {
        self.manifest.description = description.into();
        self
    }

    fn manifest_json(&self) -> Value {
        json!({
            "name": AGENT_NAME,
            "description": self.manifest.description,
            "metadata": { "programming_language": "Rust" },
            "input_content_types": ["text/plain"],
            "output_content_types": ["text/plain"],
        })
    }

    fn router(&self, agent: SharedAgent) -> Router {
        let state = Arc::new(AppState {
            agent,
            manifest: self.manifest_json(),
            api_keys: self.api_keys.clone(),
            runs: Mutex::new(VecDeque::new()),
            ids: AtomicU64::new(1),
        });
        Router::new()
            .route("/ping", get(ping))
            .route("/agents", get(list_agents))
            .route("/agents/{name}", get(get_agent))
            .route("/runs", post(create_run))
            .route("/runs/{run_id}", get(get_run))
            .route("/runs/{run_id}/cancel", post(cancel_run))
            .with_state(state)
    }
}

#[async_trait]
impl Gateway for AcpGateway {
    fn name(&self) -> &str {
        "acp"
    }

    async fn serve(self: Arc<Self>, agent: SharedAgent) -> Result<(), GatewayError> {
        let app = self.router(agent);
        let listener = tokio::net::TcpListener::bind(self.addr)
            .await
            .map_err(|e| GatewayError::Bind(e.to_string()))?;
        tracing::info!(addr = %self.addr, "ACP gateway listening (GET /agents, POST /runs)");
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))
    }
}

/// Shared handler state.
struct AppState {
    agent: SharedAgent,
    manifest: Value,
    api_keys: HashSet<String>,
    /// Runs, newest last, for `GET /runs/{id}`. Bounded by [`RUN_STORE_CAP`].
    runs: Mutex<VecDeque<(String, Value)>>,
    ids: AtomicU64,
}

impl AppState {
    fn next(&self, prefix: &str) -> String {
        format!("{prefix}-{}", self.ids.fetch_add(1, Ordering::Relaxed))
    }

    fn put_run(&self, id: &str, run: Value) {
        let mut store = self.runs.lock().expect("acp run store poisoned");
        if let Some(slot) = store.iter_mut().find(|(rid, _)| rid == id) {
            slot.1 = run;
            return;
        }
        store.push_back((id.to_string(), run));
        while store.len() > RUN_STORE_CAP {
            store.pop_front();
        }
    }

    fn get_run(&self, id: &str) -> Option<Value> {
        let store = self.runs.lock().expect("acp run store poisoned");
        store
            .iter()
            .rev()
            .find(|(rid, _)| rid == id)
            .map(|(_, r)| r.clone())
    }

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

async fn ping() -> &'static str {
    "pong"
}

/// `GET /agents` — the manifest list (one agent).
async fn list_agents(State(state): State<Arc<AppState>>) -> Json<Value> {
    Json(json!({ "agents": [state.manifest.clone()] }))
}

/// `GET /agents/{name}` — one agent's manifest.
async fn get_agent(State(state): State<Arc<AppState>>, Path(name): Path<String>) -> Response {
    if name == AGENT_NAME {
        Json(state.manifest.clone()).into_response()
    } else {
        error_response(StatusCode::NOT_FOUND, &format!("no such agent: {name}"))
    }
}

/// `POST /runs` — create a run in sync / stream / async mode.
async fn create_run(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> Response {
    if !state.authorized(&headers) {
        return error_response(StatusCode::UNAUTHORIZED, "missing or invalid API key");
    }
    let text = extract_input(&body);
    if text.is_empty() {
        return error_response(StatusCode::BAD_REQUEST, "run input has no text content");
    }
    let session_id = body
        .get("session_id")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| state.next("session"));
    let mode = body.get("mode").and_then(Value::as_str).unwrap_or("sync");
    let run_id = state.next("run");

    match mode {
        "stream" => stream_run(&state, run_id, session_id, text),
        "async" => {
            // Return an in-progress run immediately; a background task finishes it into the store.
            let run = build_run(&run_id, &session_id, "in-progress", None);
            state.put_run(&run_id, run.clone());
            let bg = state.clone();
            tokio::spawn(async move {
                let final_run = match run_turn(&bg, &session_id, &text).await {
                    Ok(answer) => build_run(
                        &run_id,
                        &session_id,
                        "completed",
                        Some(answer_output(&answer)),
                    ),
                    Err(e) => {
                        let mut r = build_run(&run_id, &session_id, "failed", None);
                        r["error"] = json!({ "message": e });
                        r
                    }
                };
                bg.put_run(&run_id, final_run);
            });
            Json(run).into_response()
        }
        _ => {
            // sync
            match run_turn(&state, &session_id, &text).await {
                Ok(answer) => {
                    let run = build_run(
                        &run_id,
                        &session_id,
                        "completed",
                        Some(answer_output(&answer)),
                    );
                    state.put_run(&run_id, run.clone());
                    Json(run).into_response()
                }
                Err(e) => error_response(StatusCode::INTERNAL_SERVER_ERROR, &e),
            }
        }
    }
}

/// `GET /runs/{run_id}` — a run's current state.
async fn get_run(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(run_id): Path<String>,
) -> Response {
    if !state.authorized(&headers) {
        return error_response(StatusCode::UNAUTHORIZED, "missing or invalid API key");
    }
    match state.get_run(&run_id) {
        Some(run) => Json(run).into_response(),
        None => error_response(StatusCode::NOT_FOUND, &format!("no such run: {run_id}")),
    }
}

/// `POST /runs/{run_id}/cancel` — best-effort cancellation.
async fn cancel_run(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(run_id): Path<String>,
) -> Response {
    if !state.authorized(&headers) {
        return error_response(StatusCode::UNAUTHORIZED, "missing or invalid API key");
    }
    match state.get_run(&run_id) {
        Some(mut run) => {
            // Only an unfinished run can move to cancelled; a completed one is returned as-is.
            if run.get("status").and_then(Value::as_str) == Some("in-progress") {
                run["status"] = json!("cancelled");
                state.put_run(&run_id, run.clone());
            }
            Json(run).into_response()
        }
        None => error_response(StatusCode::NOT_FOUND, &format!("no such run: {run_id}")),
    }
}

/// `mode: "stream"` — run the turn and stream ACP run events over SSE: a `run.in-progress` head,
/// one `message.part` per text delta (accumulating the full answer), then a terminal `run.completed`
/// (or `run.failed`) carrying the assembled output.
fn stream_run(state: &Arc<AppState>, run_id: String, session_id: String, text: String) -> Response {
    let in_progress = build_run(&run_id, &session_id, "in-progress", None);
    state.put_run(&run_id, in_progress.clone());
    let head = stream::once(async move {
        Ok::<_, Infallible>(sse_json(
            &json!({ "type": "run.in-progress", "run": in_progress }),
        ))
    });

    // The turn is submitted lazily inside the stream, so the SSE response starts flushing at once.
    let submit_state = state.clone();
    let submit = async move {
        let events = submit_state
            .agent
            .submit(TurnRequest::new(session_id.clone(), text))
            .await;
        (submit_state, run_id, session_id, events)
    };

    let body = stream::once(submit).flat_map(|(state, run_id, session_id, events)| match events {
        Ok(ev) => {
            // Accumulate deltas so the terminal `run.completed` can carry the full output.
            let acc = Arc::new(Mutex::new(String::new()));
            let acc_body = acc.clone();
            let parts = ev.filter_map(move |item| {
                let acc = acc_body.clone();
                async move {
                    match item {
                        Ok(Event::TextDelta(t)) => {
                            acc.lock().expect("acp acc poisoned").push_str(&t);
                            Some(Ok::<_, Infallible>(sse_json(&json!({
                                "type": "message.part",
                                "part": { "content_type": "text/plain", "content": t },
                            }))))
                        }
                        _ => None,
                    }
                }
            });
            let tail = stream::once(async move {
                let answer = acc.lock().expect("acp acc poisoned").trim().to_string();
                let run = build_run(
                    &run_id,
                    &session_id,
                    "completed",
                    Some(answer_output(&answer)),
                );
                state.put_run(&run_id, run.clone());
                Ok::<_, Infallible>(sse_json(&json!({ "type": "run.completed", "run": run })))
            });
            parts.chain(tail).boxed()
        }
        Err(e) => {
            let run = build_run(&run_id, &session_id, "failed", None);
            state.put_run(&run_id, run.clone());
            stream::once(async move {
                Ok::<_, Infallible>(sse_json(&json!({
                    "type": "run.failed",
                    "run": run,
                    "error": { "message": e.to_string() },
                })))
            })
            .boxed()
        }
    });

    let full: BoxStream<'static, Result<SseEvent, Infallible>> = head.chain(body).boxed();
    Sse::new(full).into_response()
}

// --- helpers ---

/// Submit a turn and fold its text deltas into the final answer.
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

/// Pull all text-part content out of a run's `input` messages.
fn extract_input(body: &Value) -> String {
    let Some(messages) = body.get("input").and_then(Value::as_array) else {
        return String::new();
    };
    let mut text = String::new();
    for msg in messages {
        let Some(parts) = msg.get("parts").and_then(Value::as_array) else {
            continue;
        };
        for part in parts {
            let ctype = part
                .get("content_type")
                .and_then(Value::as_str)
                .unwrap_or("text/plain");
            if ctype.starts_with("text") {
                if let Some(content) = part.get("content").and_then(Value::as_str) {
                    text.push_str(content);
                }
            }
        }
    }
    text
}

/// The ACP output messages for a completed run.
fn answer_output(answer: &str) -> Value {
    json!([{
        "role": "agent/lavoisier",
        "parts": [{ "content_type": "text/plain", "content": answer }],
    }])
}

/// Build a `Run` object.
fn build_run(run_id: &str, session_id: &str, status: &str, output: Option<Value>) -> Value {
    json!({
        "run_id": run_id,
        "agent_name": AGENT_NAME,
        "session_id": session_id,
        "status": status,
        "output": output.unwrap_or_else(|| json!([])),
    })
}

fn sse_json(value: &Value) -> SseEvent {
    SseEvent::default().data(value.to_string())
}

fn error_response(status: StatusCode, message: &str) -> Response {
    (status, Json(json!({ "error": message }))).into_response()
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
    use lvz_protocol::{AgentError, StopReason};

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

    async fn spawn(agent: SharedAgent) -> String {
        let gw = AcpGateway::bind("127.0.0.1:0").unwrap();
        let app = gw.router(agent);
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        format!("http://{addr}")
    }

    #[tokio::test]
    async fn lists_the_agent_manifest() {
        let base = spawn(Arc::new(StubAgent("hi"))).await;
        let v: Value = reqwest::get(format!("{base}/agents"))
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(v["agents"][0]["name"], "lavoisier");
        assert_eq!(v["agents"][0]["input_content_types"][0], "text/plain");
    }

    #[tokio::test]
    async fn sync_run_returns_completed_with_output() {
        let base = spawn(Arc::new(StubAgent("42 is the answer"))).await;
        let body = json!({
            "agent_name": "lavoisier",
            "input": [{ "parts": [{ "content_type": "text/plain", "content": "hi" }] }],
        });
        let run: Value = reqwest::Client::new()
            .post(format!("{base}/runs"))
            .json(&body)
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(run["status"], "completed");
        assert_eq!(run["output"][0]["parts"][0]["content"], "42 is the answer");
        // Retrievable by run_id.
        let run_id = run["run_id"].as_str().unwrap().to_string();
        let got: Value = reqwest::get(format!("{base}/runs/{run_id}"))
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        assert_eq!(got["status"], "completed");
    }

    #[tokio::test]
    async fn stream_run_emits_sse_events() {
        let base = spawn(Arc::new(StubAgent("streamed answer"))).await;
        let body = json!({
            "agent_name": "lavoisier",
            "mode": "stream",
            "input": [{ "parts": [{ "content_type": "text/plain", "content": "go" }] }],
        });
        let text = reqwest::Client::new()
            .post(format!("{base}/runs"))
            .json(&body)
            .send()
            .await
            .unwrap()
            .text()
            .await
            .unwrap();
        assert!(text.contains("run.in-progress"));
        assert!(text.contains("streamed answer"));
        assert!(text.contains("run.completed"));
    }

    #[tokio::test]
    async fn empty_input_is_a_bad_request() {
        let base = spawn(Arc::new(StubAgent("x"))).await;
        let body = json!({ "agent_name": "lavoisier", "input": [] });
        let resp = reqwest::Client::new()
            .post(format!("{base}/runs"))
            .json(&body)
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status(), 400);
    }
}
