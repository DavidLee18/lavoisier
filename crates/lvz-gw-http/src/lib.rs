//! `lvz-gw-http` — the HTTP/REST + WebSocket gateway (§7.2).
//!
//! A concrete [`Gateway`] that fronts the shared agent over HTTP. It depends only on
//! `lvz-protocol` (the [`Gateway`]/[`AgentHandle`] contracts + the normalised [`Event`]
//! stream) — never on a provider or on `lvz-agent`'s internals — so the same agent core
//! serves the CLI and this gateway unchanged (§6 invariant).
//!
//! Surface:
//! - `GET  /health`   — liveness probe.
//! - `POST /v1/turns` — submit one turn (`{ "session"?, "input" }`), stream the resulting
//!   events back as **Server-Sent Events** (one JSON-encoded [`Event`] per `data:` frame).
//! - `GET  /v1/ws`    — a **WebSocket**: send a turn JSON per message, receive the event
//!   stream as JSON text frames; the socket stays open for further turns.

use std::collections::HashSet;
use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use async_trait::async_trait;
use axum::{
    extract::{
        ws::{Message as WsMessage, WebSocket, WebSocketUpgrade},
        Request, State,
    },
    http::{
        header::{AUTHORIZATION, CONTENT_TYPE},
        HeaderMap, StatusCode,
    },
    middleware::{self, Next},
    response::{
        sse::{Event as SseEvent, Sse},
        IntoResponse, Response,
    },
    routing::{get, post},
    Json, Router,
};
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{AgentError, AgentHandle, Event, Gateway, GatewayError, TurnRequest};
use serde::Deserialize;

/// The shared agent, as every handler sees it.
type SharedAgent = Arc<dyn AgentHandle>;

/// Auth + quota policy for the protected routes (§7.3). Defaults are wide open
/// (no keys required, no rate limit) — suitable for local use; lock down for exposed deploys.
#[derive(Clone, Default)]
pub struct GatewayConfig {
    /// Accepted API keys. Empty ⇒ no auth (open access).
    api_keys: HashSet<String>,
    /// Optional fixed-window per-principal request quota.
    rate_limit: Option<(u32, Duration)>,
}

impl GatewayConfig {
    /// Require one of these API keys (sent as `Authorization: Bearer <key>`) on protected
    /// routes. An empty set leaves the gateway open.
    pub fn with_api_keys<I: IntoIterator<Item = String>>(mut self, keys: I) -> Self {
        self.api_keys = keys.into_iter().collect();
        self
    }

    /// Cap each principal (API key, or all anonymous callers together) to `max_requests`
    /// protected requests per `window`.
    pub fn with_rate_limit(mut self, max_requests: u32, window: Duration) -> Self {
        self.rate_limit = Some((max_requests, window));
        self
    }
}

/// The HTTP/WebSocket gateway. Construct with a bind address (+ optional [`GatewayConfig`]),
/// then [`Gateway::serve`] it with an [`AgentHandle`].
pub struct HttpGateway {
    addr: SocketAddr,
    config: GatewayConfig,
}

impl HttpGateway {
    /// Bind-address constructor with an open (no-auth) policy.
    pub fn new(addr: SocketAddr) -> Self {
        Self {
            addr,
            config: GatewayConfig::default(),
        }
    }

    /// Parse a `host:port` string into a gateway, surfacing a [`GatewayError::Bind`] on a
    /// malformed address.
    pub fn bind(addr: &str) -> Result<Self, GatewayError> {
        let addr = addr
            .parse()
            .map_err(|e: std::net::AddrParseError| GatewayError::Bind(e.to_string()))?;
        Ok(Self::new(addr))
    }

    /// Apply an auth/quota policy to the protected routes.
    pub fn with_config(mut self, config: GatewayConfig) -> Self {
        self.config = config;
        self
    }

    /// Build the router for a given agent with an open policy. Exposed so callers (and tests)
    /// can mount it on their own listener.
    pub fn router(agent: SharedAgent) -> Router {
        Self::router_with(agent, GatewayConfig::default())
    }

    /// Build the router with an explicit auth/quota policy. `/health` and `/metrics` are
    /// always open; `/v1/turns` and `/v1/ws` sit behind the [`GatewayConfig`] guard.
    pub fn router_with(agent: SharedAgent, config: GatewayConfig) -> Router {
        let state = Arc::new(AppState {
            agent,
            metrics: Arc::new(Metrics::default()),
        });
        let guard = Arc::new(Guard::new(config));
        let protected = Router::new()
            .route("/v1/turns", post(post_turn))
            .route("/v1/ws", get(ws_upgrade))
            .route_layer(middleware::from_fn_with_state(guard, guard_request))
            .with_state(state.clone());
        Router::new()
            .route("/health", get(health))
            .route("/metrics", get(metrics))
            .with_state(state)
            .merge(protected)
    }
}

/// Shared handler state: the agent plus the cross-cutting telemetry recorder (the design notes
/// §6.4, §7.3).
struct AppState {
    agent: SharedAgent,
    metrics: Arc<Metrics>,
}

#[async_trait]
impl Gateway for HttpGateway {
    fn name(&self) -> &str {
        "http"
    }

    async fn serve(self: Arc<Self>, agent: SharedAgent) -> Result<(), GatewayError> {
        let app = HttpGateway::router_with(agent, self.config.clone());
        let listener = tokio::net::TcpListener::bind(self.addr)
            .await
            .map_err(|e| GatewayError::Bind(e.to_string()))?;
        axum::serve(listener, app)
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))
    }
}

// --- auth + quota middleware ---

/// Runtime guard state behind the protected routes.
struct Guard {
    api_keys: HashSet<String>,
    limiter: Option<Limiter>,
}

impl Guard {
    fn new(config: GatewayConfig) -> Self {
        Self {
            api_keys: config.api_keys,
            limiter: config
                .rate_limit
                .map(|(max, window)| Limiter::new(max, window)),
        }
    }
}

/// A fixed-window request counter keyed by principal.
struct Limiter {
    max: u32,
    window: Duration,
    windows: Mutex<std::collections::HashMap<String, Window>>,
}

struct Window {
    start: Instant,
    count: u32,
}

impl Limiter {
    fn new(max: u32, window: Duration) -> Self {
        Self {
            max,
            window,
            windows: Mutex::new(std::collections::HashMap::new()),
        }
    }

    /// Record a request for `principal`; `false` once it exceeds `max` within the window.
    fn allow(&self, principal: &str) -> bool {
        let now = Instant::now();
        let mut windows = self.windows.lock().unwrap();
        let w = windows.entry(principal.to_string()).or_insert(Window {
            start: now,
            count: 0,
        });
        if now.duration_since(w.start) >= self.window {
            w.start = now;
            w.count = 0;
        }
        if w.count >= self.max {
            false
        } else {
            w.count += 1;
            true
        }
    }
}

fn bearer(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(AUTHORIZATION)?
        .to_str()
        .ok()?
        .strip_prefix("Bearer ")
        .map(str::trim)
}

/// Authenticate (if keys are configured) then rate-limit (if configured) before the handler.
async fn guard_request(
    State(guard): State<Arc<Guard>>,
    headers: HeaderMap,
    request: Request,
    next: Next,
) -> Response {
    // Identify the principal: a valid API key, or "anon" when auth is disabled.
    let principal = if guard.api_keys.is_empty() {
        "anon".to_string()
    } else {
        match bearer(&headers) {
            Some(key) if guard.api_keys.contains(key) => key.to_string(),
            _ => return (StatusCode::UNAUTHORIZED, "missing or invalid API key").into_response(),
        }
    };
    if let Some(limiter) = &guard.limiter {
        if !limiter.allow(&principal) {
            return (StatusCode::TOO_MANY_REQUESTS, "rate limit exceeded").into_response();
        }
    }
    next.run(request).await
}

// --- telemetry (§6.4): tokens, cache hits, latency, per-turn counts ---

/// Process-wide counters, exported in Prometheus text format at `GET /metrics`. The agent
/// emits exactly one terminal [`Usage`] per turn (the task total across round-trips), so the
/// per-turn tap records that single total — never double-counting.
#[derive(Default)]
struct Metrics {
    turns_total: AtomicU64,
    errors_total: AtomicU64,
    input_tokens_total: AtomicU64,
    output_tokens_total: AtomicU64,
    cache_read_tokens_total: AtomicU64,
    cache_creation_tokens_total: AtomicU64,
    turn_duration_micros_total: AtomicU64,
}

impl Metrics {
    fn record_turn(&self, usage: &lvz_protocol::Usage, elapsed: Duration, errored: bool) {
        self.turns_total.fetch_add(1, Ordering::Relaxed);
        if errored {
            self.errors_total.fetch_add(1, Ordering::Relaxed);
        }
        self.input_tokens_total
            .fetch_add(usage.input_tokens, Ordering::Relaxed);
        self.output_tokens_total
            .fetch_add(usage.output_tokens, Ordering::Relaxed);
        self.cache_read_tokens_total
            .fetch_add(usage.cache_read_tokens, Ordering::Relaxed);
        self.cache_creation_tokens_total
            .fetch_add(usage.cache_creation_tokens, Ordering::Relaxed);
        self.turn_duration_micros_total
            .fetch_add(elapsed.as_micros() as u64, Ordering::Relaxed);
    }

    /// Render the Prometheus text exposition format (v0.0.4). Operators scrape this directly,
    /// or bridge it to OTLP at the collector — keeping the gateway free of a heavy exporter.
    fn render_prometheus(&self) -> String {
        let g = |a: &AtomicU64| a.load(Ordering::Relaxed);
        let mut s = String::new();
        let mut counter = |name: &str, help: &str, value: u64| {
            s.push_str(&format!(
                "# HELP {name} {help}\n# TYPE {name} counter\n{name} {value}\n"
            ));
        };
        counter(
            "lavoisier_turns_total",
            "Agent turns completed.",
            g(&self.turns_total),
        );
        counter(
            "lavoisier_turn_errors_total",
            "Turns that ended in an error.",
            g(&self.errors_total),
        );
        counter(
            "lavoisier_input_tokens_total",
            "Billed input tokens across all turns.",
            g(&self.input_tokens_total),
        );
        counter(
            "lavoisier_output_tokens_total",
            "Generated output tokens across all turns.",
            g(&self.output_tokens_total),
        );
        counter(
            "lavoisier_cache_read_tokens_total",
            "Prompt tokens served from cache.",
            g(&self.cache_read_tokens_total),
        );
        counter(
            "lavoisier_cache_creation_tokens_total",
            "Prompt tokens written to cache.",
            g(&self.cache_creation_tokens_total),
        );
        counter(
            "lavoisier_turn_duration_micros_total",
            "Summed wall-clock turn latency, microseconds.",
            g(&self.turn_duration_micros_total),
        );
        // Derived gauge: the share of prompt tokens served from cache. Total prompt tokens =
        // fresh input + cache reads + cache writes; the ratio is the single number operators
        // watch to confirm the caching levers (§6.1) are paying off. 0.0 until any prompt
        // tokens are billed (avoids a NaN from 0/0).
        let cache_read = g(&self.cache_read_tokens_total);
        let prompt_total =
            g(&self.input_tokens_total) + cache_read + g(&self.cache_creation_tokens_total);
        let hit_rate = if prompt_total == 0 {
            0.0
        } else {
            cache_read as f64 / prompt_total as f64
        };
        s.push_str(&format!(
            "# HELP {name} {help}\n# TYPE {name} gauge\n{name} {hit_rate}\n",
            name = "lavoisier_cache_hit_rate",
            help =
                "Fraction of prompt tokens served from cache (cache_read / total prompt tokens)."
        ));
        s
    }
}

/// Wrap an agent's per-turn event stream to record telemetry on completion: accumulate the
/// last [`Usage`] (last-wins) and, on the terminal `Done` or stream end, record the turn.
fn instrument(
    inner: BoxStream<'static, Result<Event, AgentError>>,
    metrics: Arc<Metrics>,
) -> BoxStream<'static, Result<Event, AgentError>> {
    let tap = MetricTap {
        inner,
        metrics,
        start: Instant::now(),
        usage: lvz_protocol::Usage::default(),
        errored: false,
        recorded: false,
    };
    stream::unfold(tap, |mut tap| async move {
        match tap.inner.next().await {
            Some(item) => {
                match &item {
                    Ok(Event::Usage(u)) => tap.usage = *u,
                    Err(_) => tap.errored = true,
                    _ => {}
                }
                if matches!(item, Ok(Event::Done(_))) {
                    tap.record();
                }
                Some((item, tap))
            }
            None => {
                tap.record();
                None
            }
        }
    })
    .boxed()
}

struct MetricTap {
    inner: BoxStream<'static, Result<Event, AgentError>>,
    metrics: Arc<Metrics>,
    start: Instant,
    usage: lvz_protocol::Usage,
    errored: bool,
    recorded: bool,
}

impl MetricTap {
    fn record(&mut self) {
        if self.recorded {
            return;
        }
        self.recorded = true;
        self.metrics
            .record_turn(&self.usage, self.start.elapsed(), self.errored);
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

/// `GET /metrics` — Prometheus text exposition of the cross-cutting telemetry.
async fn metrics(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    (
        [(CONTENT_TYPE, "text/plain; version=0.0.4")],
        state.metrics.render_prometheus(),
    )
}

/// `POST /v1/turns` — run one turn and stream its events as SSE.
async fn post_turn(
    State(state): State<Arc<AppState>>,
    Json(dto): Json<TurnDto>,
) -> Sse<BoxStream<'static, Result<SseEvent, Infallible>>> {
    let turn = TurnRequest::new(dto.session, dto.input);
    let body: BoxStream<'static, Result<SseEvent, Infallible>> =
        match state.agent.submit(turn).await {
            Ok(events) => instrument(events, state.metrics.clone())
                .map(|item| Ok(to_sse(item)))
                .boxed(),
            Err(e) => {
                state
                    .metrics
                    .record_turn(&lvz_protocol::Usage::default(), Duration::ZERO, true);
                stream::once(async move { Ok(error_sse(&e)) }).boxed()
            }
        };
    Sse::new(body)
}

/// `GET /v1/ws` — upgrade to a WebSocket and serve turns on it.
async fn ws_upgrade(State(state): State<Arc<AppState>>, ws: WebSocketUpgrade) -> impl IntoResponse {
    ws.on_upgrade(move |socket| ws_loop(socket, state))
}

/// One WebSocket connection: each inbound text frame is a [`TurnDto`]; the agent's events for
/// that turn stream back as JSON text frames before the next inbound frame is read.
async fn ws_loop(mut socket: WebSocket, state: Arc<AppState>) {
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
        match state.agent.submit(turn).await {
            Ok(events) => {
                let mut events = instrument(events, state.metrics.clone());
                while let Some(item) = events.next().await {
                    if send_text(&mut socket, to_json(item)).await.is_err() {
                        return;
                    }
                }
            }
            Err(e) => {
                state
                    .metrics
                    .record_turn(&lvz_protocol::Usage::default(), Duration::ZERO, true);
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
    fn cache_hit_rate_gauge_reflects_recorded_usage() {
        let metrics = Metrics::default();
        // Empty: gauge present and 0.0 (no division by zero).
        let empty = metrics.render_prometheus();
        assert!(empty.contains("# TYPE lavoisier_cache_hit_rate gauge"));
        assert!(empty.contains("lavoisier_cache_hit_rate 0\n"));

        // 30 fresh input + 60 cache reads + 10 cache writes ⇒ 60/100 = 0.6.
        metrics.record_turn(
            &Usage {
                input_tokens: 30,
                cache_read_tokens: 60,
                cache_creation_tokens: 10,
                ..Default::default()
            },
            Duration::ZERO,
            false,
        );
        let out = metrics.render_prometheus();
        assert!(out.contains("lavoisier_cache_hit_rate 0.6\n"), "got: {out}");
    }

    #[test]
    fn agent_errors_encode_as_an_error_envelope() {
        let payload = to_json(Err(AgentError::BudgetExceeded));
        let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert!(value["error"].as_str().unwrap().contains("budget"));
    }
}
