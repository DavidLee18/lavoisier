//! `lvz-gw-http` — the HTTP/REST + WebSocket gateway (`RECIPE.md` §7.2).
//!
//! A concrete [`Gateway`] that fronts the shared agent over HTTP. It depends only on
//! `lvz-protocol` (the [`Gateway`]/[`AgentHandle`] contracts + the normalised [`Event`]
//! stream) — never on a provider or on `lvz-agent`'s internals — so the same agent core
//! serves the CLI and this gateway unchanged (`RECIPE.md` §6 invariant).
//!
//! Surface:
//! - `GET  /health`   — liveness probe.
//! - `POST /v1/turns` — submit one turn (`{ "session"?, "input" }`), stream the resulting
//!   events back as **Server-Sent Events** (one JSON-encoded [`Event`] per `data:` frame).
//! - `GET  /v1/ws`    — a **WebSocket**: send a turn JSON per message, receive the event
//!   stream as JSON text frames; the socket stays open for further turns.

use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::Arc;

use async_trait::async_trait;
use axum::{
    extract::{
        ws::{Message as WsMessage, WebSocket, WebSocketUpgrade},
        State,
    },
    response::{
        sse::{Event as SseEvent, Sse},
        IntoResponse,
    },
    routing::{get, post},
    Json, Router,
};
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{AgentError, AgentHandle, Event, Gateway, GatewayError, TurnRequest};
use serde::Deserialize;

/// The shared agent, as every handler sees it.
type SharedAgent = Arc<dyn AgentHandle>;

/// The HTTP/WebSocket gateway. Construct with a bind address, then [`Gateway::serve`] it
/// with an [`AgentHandle`].
pub struct HttpGateway {
    addr: SocketAddr,
}

impl HttpGateway {
    /// Bind-address constructor.
    pub fn new(addr: SocketAddr) -> Self {
        Self { addr }
    }

    /// Parse a `host:port` string into a gateway, surfacing a [`GatewayError::Bind`] on a
    /// malformed address.
    pub fn bind(addr: &str) -> Result<Self, GatewayError> {
        let addr = addr
            .parse()
            .map_err(|e: std::net::AddrParseError| GatewayError::Bind(e.to_string()))?;
        Ok(Self::new(addr))
    }

    /// Build the router for a given agent. Exposed so callers (and tests) can mount it on
    /// their own listener.
    pub fn router(agent: SharedAgent) -> Router {
        Router::new()
            .route("/health", get(health))
            .route("/v1/turns", post(post_turn))
            .route("/v1/ws", get(ws_upgrade))
            .with_state(agent)
    }
}

#[async_trait]
impl Gateway for HttpGateway {
    fn name(&self) -> &str {
        "http"
    }

    async fn serve(self: Arc<Self>, agent: SharedAgent) -> Result<(), GatewayError> {
        let app = HttpGateway::router(agent);
        let listener = tokio::net::TcpListener::bind(self.addr)
            .await
            .map_err(|e| GatewayError::Bind(e.to_string()))?;
        axum::serve(listener, app)
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))
    }
}

/// Inbound turn payload. `session` defaults so a single-session client can omit it.
#[derive(Deserialize)]
struct TurnDto {
    #[serde(default = "default_session")]
    session: String,
    input: String,
}

fn default_session() -> String {
    "default".into()
}

async fn health() -> &'static str {
    "ok"
}

/// `POST /v1/turns` — run one turn and stream its events as SSE.
async fn post_turn(
    State(agent): State<SharedAgent>,
    Json(dto): Json<TurnDto>,
) -> Sse<BoxStream<'static, Result<SseEvent, Infallible>>> {
    let turn = TurnRequest::new(dto.session, dto.input);
    let body: BoxStream<'static, Result<SseEvent, Infallible>> = match agent.submit(turn).await {
        Ok(events) => events.map(|item| Ok(to_sse(item))).boxed(),
        Err(e) => stream::once(async move { Ok(error_sse(&e)) }).boxed(),
    };
    Sse::new(body)
}

/// `GET /v1/ws` — upgrade to a WebSocket and serve turns on it.
async fn ws_upgrade(State(agent): State<SharedAgent>, ws: WebSocketUpgrade) -> impl IntoResponse {
    ws.on_upgrade(move |socket| ws_loop(socket, agent))
}

/// One WebSocket connection: each inbound text frame is a [`TurnDto`]; the agent's events for
/// that turn stream back as JSON text frames before the next inbound frame is read.
async fn ws_loop(mut socket: WebSocket, agent: SharedAgent) {
    while let Some(Ok(msg)) = socket.recv().await {
        let text = match msg {
            WsMessage::Text(t) => t,
            WsMessage::Close(_) => break,
            // Ping/Pong are handled by axum; binary turns aren't supported.
            _ => continue,
        };
        let dto: TurnDto = match serde_json::from_str(text.as_str()) {
            Ok(dto) => dto,
            Err(e) => {
                if send_text(&mut socket, error_json(&e.to_string()))
                    .await
                    .is_err()
                {
                    return;
                }
                continue;
            }
        };
        let turn = TurnRequest::new(dto.session, dto.input);
        match agent.submit(turn).await {
            Ok(mut events) => {
                while let Some(item) = events.next().await {
                    if send_text(&mut socket, to_json(item)).await.is_err() {
                        return;
                    }
                }
            }
            Err(e) => {
                if send_text(&mut socket, error_json(&e.to_string()))
                    .await
                    .is_err()
                {
                    return;
                }
            }
        }
    }
}

async fn send_text(socket: &mut WebSocket, payload: String) -> Result<(), axum::Error> {
    socket.send(WsMessage::Text(payload.into())).await
}

// --- event → wire encoding (the only place the gateway's JSON shape is decided) ---

/// Encode one agent stream item as an SSE frame: successes carry the JSON [`Event`]; errors
/// are tagged with an `error` event name and an `{"error": …}` payload.
fn to_sse(item: Result<Event, AgentError>) -> SseEvent {
    match item {
        Ok(event) => SseEvent::default().data(encode_event(&event)),
        Err(e) => error_sse(&e),
    }
}

fn error_sse(e: &AgentError) -> SseEvent {
    SseEvent::default()
        .event("error")
        .data(error_json(&e.to_string()))
}

/// Encode one agent stream item as a WebSocket text payload (JSON either way).
fn to_json(item: Result<Event, AgentError>) -> String {
    match item {
        Ok(event) => encode_event(&event),
        Err(e) => error_json(&e.to_string()),
    }
}

fn encode_event(event: &Event) -> String {
    // Event is adjacently tagged and always serializes; the fallback is defensive only.
    serde_json::to_string(event).unwrap_or_else(|e| error_json(&e.to_string()))
}

fn error_json(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{StopReason, Usage};

    #[test]
    fn turn_dto_defaults_the_session() {
        let dto: TurnDto = serde_json::from_str(r#"{"input":"hi"}"#).unwrap();
        assert_eq!(dto.session, "default");
        assert_eq!(dto.input, "hi");
    }

    #[test]
    fn ok_events_encode_as_their_json() {
        let payload = to_json(Ok(Event::TextDelta("hi".into())));
        let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert_eq!(value["kind"], "text_delta");
        assert_eq!(value["data"], "hi");

        let usage = to_json(Ok(Event::Usage(Usage {
            input_tokens: 5,
            output_tokens: 2,
            ..Default::default()
        })));
        let value: serde_json::Value = serde_json::from_str(&usage).unwrap();
        assert_eq!(value["kind"], "usage");
        assert_eq!(value["data"]["input_tokens"], 5);

        let done = to_json(Ok(Event::Done(StopReason::EndTurn)));
        assert!(done.contains("done") && done.contains("end_turn"));
    }

    #[test]
    fn agent_errors_encode_as_an_error_envelope() {
        let payload = to_json(Err(AgentError::BudgetExceeded));
        let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert!(value["error"].as_str().unwrap().contains("budget"));
    }
}
