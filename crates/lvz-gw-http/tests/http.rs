//! End-to-end gateway tests: mount the real router on an ephemeral port with a stub
//! [`AgentHandle`], then drive it over HTTP with `reqwest`.

use std::sync::Arc;

use std::time::Duration;

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_gw_http::{GatewayConfig, HttpGateway};
use lvz_protocol::{AgentError, AgentHandle, Event, StopReason, TurnRequest, Usage};

/// An agent that echoes a fixed event stream, prefixed with the turn's input so tests can
/// confirm the request body reached the handle.
struct EchoAgent;

#[async_trait]
impl AgentHandle for EchoAgent {
    async fn submit(
        &self,
        turn: TurnRequest,
    ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError> {
        let events = vec![
            Ok(Event::TextDelta(format!("echo:{}", turn.input))),
            Ok(Event::Usage(Usage {
                input_tokens: 3,
                output_tokens: 1,
                ..Default::default()
            })),
            Ok(Event::Done(StopReason::EndTurn)),
        ];
        Ok(stream::iter(events).boxed())
    }
}

/// An agent that fails the submit outright.
struct FailingAgent;

#[async_trait]
impl AgentHandle for FailingAgent {
    async fn submit(
        &self,
        _turn: TurnRequest,
    ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError> {
        Err(AgentError::BudgetExceeded)
    }
}

async fn spawn(agent: Arc<dyn AgentHandle>) -> String {
    spawn_with(agent, GatewayConfig::default()).await
}

async fn spawn_with(agent: Arc<dyn AgentHandle>, config: GatewayConfig) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let app = HttpGateway::router_with(agent, config);
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

#[tokio::test]
async fn health_returns_ok() {
    let base = spawn(Arc::new(EchoAgent)).await;
    let body = reqwest::get(format!("{base}/health"))
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert_eq!(body, "ok");
}

#[tokio::test]
async fn post_turn_streams_events_as_sse() {
    let base = spawn(Arc::new(EchoAgent)).await;
    let resp = reqwest::Client::new()
        .post(format!("{base}/v1/turns"))
        .json(&serde_json::json!({ "input": "ping" }))
        .send()
        .await
        .unwrap();
    assert!(resp.status().is_success());
    assert!(resp
        .headers()
        .get("content-type")
        .unwrap()
        .to_str()
        .unwrap()
        .starts_with("text/event-stream"));

    let body = resp.text().await.unwrap();
    // The input reached the agent and the full event stream came back over SSE.
    assert!(body.contains("echo:ping"), "body was: {body}");
    assert!(body.contains("text_delta"));
    assert!(body.contains("usage"));
    assert!(body.contains("done"));
    assert!(body.contains("end_turn"));
}

#[tokio::test]
async fn submit_failure_is_reported_as_an_sse_error() {
    let base = spawn(Arc::new(FailingAgent)).await;
    let body = reqwest::Client::new()
        .post(format!("{base}/v1/turns"))
        .json(&serde_json::json!({ "session": "s1", "input": "x" }))
        .send()
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert!(
        body.contains("event:error") || body.contains("event: error"),
        "body was: {body}"
    );
    assert!(body.contains("budget"), "body was: {body}");
}

#[tokio::test]
async fn metrics_endpoint_reports_turn_telemetry() {
    let base = spawn(Arc::new(EchoAgent)).await;
    let client = reqwest::Client::new();

    // Fresh gateway: counters start at zero.
    let before = reqwest::get(format!("{base}/metrics"))
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert!(
        before.contains("lavoisier_turns_total 0"),
        "metrics:\n{before}"
    );

    // Run a turn and drain it fully (so the per-turn tap records before we scrape).
    let body = client
        .post(format!("{base}/v1/turns"))
        .json(&serde_json::json!({ "input": "ping" }))
        .send()
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert!(body.contains("echo:ping"));

    let after = reqwest::get(format!("{base}/metrics"))
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    // EchoAgent reports input=3, output=1 for the turn.
    assert!(
        after.contains("lavoisier_turns_total 1"),
        "metrics:\n{after}"
    );
    assert!(
        after.contains("lavoisier_input_tokens_total 3"),
        "metrics:\n{after}"
    );
    assert!(
        after.contains("lavoisier_output_tokens_total 1"),
        "metrics:\n{after}"
    );
}

#[tokio::test]
async fn api_key_auth_gates_protected_routes() {
    let config = GatewayConfig::default().with_api_keys(["sk-test".to_string()]);
    let base = spawn_with(Arc::new(EchoAgent), config).await;
    let client = reqwest::Client::new();

    // /health is always open.
    let health = reqwest::get(format!("{base}/health")).await.unwrap();
    assert!(health.status().is_success());

    let body = serde_json::json!({ "input": "ping" });

    // No key → 401.
    let no_key = client
        .post(format!("{base}/v1/turns"))
        .json(&body)
        .send()
        .await
        .unwrap();
    assert_eq!(no_key.status(), reqwest::StatusCode::UNAUTHORIZED);

    // Wrong key → 401.
    let wrong = client
        .post(format!("{base}/v1/turns"))
        .bearer_auth("nope")
        .json(&body)
        .send()
        .await
        .unwrap();
    assert_eq!(wrong.status(), reqwest::StatusCode::UNAUTHORIZED);

    // Correct key → 200 and the stream flows.
    let ok = client
        .post(format!("{base}/v1/turns"))
        .bearer_auth("sk-test")
        .json(&body)
        .send()
        .await
        .unwrap();
    assert!(ok.status().is_success());
    assert!(ok.text().await.unwrap().contains("echo:ping"));
}

#[tokio::test]
async fn rate_limit_returns_429_past_the_quota() {
    let config = GatewayConfig::default().with_rate_limit(2, Duration::from_secs(60));
    let base = spawn_with(Arc::new(EchoAgent), config).await;
    let client = reqwest::Client::new();
    let turn = serde_json::json!({ "input": "x" });

    let post = || client.post(format!("{base}/v1/turns")).json(&turn).send();
    assert!(post().await.unwrap().status().is_success());
    assert!(post().await.unwrap().status().is_success());
    assert_eq!(
        post().await.unwrap().status(),
        reqwest::StatusCode::TOO_MANY_REQUESTS
    );

    // /health is not a protected route, so it is never rate-limited.
    assert!(reqwest::get(format!("{base}/health"))
        .await
        .unwrap()
        .status()
        .is_success());
}
