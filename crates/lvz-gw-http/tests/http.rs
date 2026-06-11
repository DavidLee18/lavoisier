//! End-to-end gateway tests: mount the real router on an ephemeral port with a stub
//! [`AgentHandle`], then drive it over HTTP with `reqwest`.

use std::sync::Arc;

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_gw_http::HttpGateway;
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
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let app = HttpGateway::router(agent);
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
