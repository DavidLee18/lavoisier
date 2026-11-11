//! `POST /v1/jobs/{id}` end to end on an ephemeral port, with a stub [`JobRunner`].
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_gw_http::jobs::{JobRejection, JobReport, JobRequest, JobRunner};
use lvz_gw_http::{GatewayConfig, HttpGateway};
use lvz_protocol::{AgentError, AgentHandle, Event, StopReason, TurnRequest};
use serde_json::{json, Value};
use tokio::sync::Notify;

struct NoAgent;
#[async_trait]
impl AgentHandle for NoAgent {
    async fn submit(
        &self,
        _t: TurnRequest,
    ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError> {
        Ok(stream::iter(vec![Ok(Event::Done(StopReason::EndTurn))]).boxed())
    }
}

/// Jobs: `ok` (instant), `wait` (sends ⏳ then succeeds), `gate` (blocks until notified),
/// `boom` (cannot run). Slots every 5 minutes; attempts 1..=4.
struct Runner {
    runs: AtomicUsize,
    gate: Notify,
}
#[async_trait]
impl JobRunner for Runner {
    fn validate(&self, job: &str, req: &JobRequest) -> Result<(), JobRejection> {
        if !["ok", "wait", "gate", "boom"].contains(&job) {
            return Err(JobRejection::UnknownJob);
        }
        if !req.scheduled_minute.is_multiple_of(300) {
            return Err(JobRejection::Invalid(
                "not_a_slot",
                "not a cron slot".into(),
            ));
        }
        if !(1..=4).contains(&req.attempt) {
            return Err(JobRejection::Invalid("bad_attempt", "1..=4".into()));
        }
        Ok(())
    }
    async fn run(
        &self,
        job: &str,
        req: &JobRequest,
        mut waiting: Box<dyn FnMut(String) + Send>,
    ) -> Result<JobReport, String> {
        self.runs.fetch_add(1, Ordering::SeqCst);
        match job {
            "boom" => return Err("tool registry unavailable".into()),
            "wait" => {
                waiting("⏳ `wait` · started".into());
                waiting("⏳ again (dropped)".into());
            }
            "gate" => self.gate.notified().await,
            _ => {}
        }
        Ok(JobReport {
            ok: req.attempt > 1,
            body: format!("body {job} {}", req.attempt),
            attempt: req.attempt,
            retry_in_s: (req.attempt == 1).then_some(60),
            gave_up: false,
            images: 0,
        })
    }
}

async fn spawn() -> (String, Arc<Runner>) {
    let runner = Arc::new(Runner {
        runs: AtomicUsize::new(0),
        gate: Notify::new(),
    });
    let cfg = GatewayConfig::default()
        .with_api_keys(["k".to_string()])
        .with_jobs(runner.clone());
    let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = l.local_addr().unwrap();
    let app = HttpGateway::router_with(Arc::new(NoAgent), cfg);
    tokio::spawn(async move { axum::serve(l, app).await.unwrap() });
    (format!("http://{addr}"), runner)
}

fn slot() -> u64 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    now / 300 * 300
}

async fn post(url: &str, job: &str, body: Value) -> reqwest::Response {
    reqwest::Client::new()
        .post(format!("{url}/v1/jobs/{job}"))
        .bearer_auth("k")
        .json(&body)
        .send()
        .await
        .unwrap()
}

/// (event, data) pairs of a finished SSE body.
async fn events(r: reqwest::Response) -> Vec<(String, Value)> {
    assert_eq!(r.status(), 200);
    let text = r.text().await.unwrap();
    text.split("\n\n")
        .filter_map(|frame| {
            let ev = frame.lines().find_map(|l| l.strip_prefix("event: "))?;
            let d = frame.lines().find_map(|l| l.strip_prefix("data: "))?;
            Some((ev.to_string(), serde_json::from_str(d).unwrap()))
        })
        .collect()
}

async fn code(url: &str, r: Value) -> (u16, String) {
    let resp = post(url, "ok", r).await;
    let st = resp.status().as_u16();
    (
        st,
        resp.json::<Value>().await.unwrap()["error"]
            .as_str()
            .unwrap()
            .to_string(),
    )
}

fn req(key: &str, attempt: u32) -> Value {
    json!({"scheduled_minute": slot(), "idempotency_key": key, "attempt": attempt})
}

#[tokio::test]
async fn runs_once_reports_and_replays() {
    let (url, runner) = spawn().await;
    let ev = events(post(&url, "wait", req("lav:wait:1:1", 1)).await).await;
    assert_eq!(ev.len(), 2, "{ev:?}");
    assert_eq!(
        ev[0],
        (
            "waiting".into(),
            json!({"job":"wait","body":"⏳ `wait` · started"})
        )
    );
    assert_eq!(
        ev[1],
        (
            "report".into(),
            json!({"job":"wait","ok":false,"body":"body wait 1","attempt":1,"retry_in_s":60,"gave_up":false,"images":0,"replayed":false})
        )
    );
    let again = events(post(&url, "wait", req("lav:wait:1:1", 1)).await).await;
    assert_eq!(again.len(), 1);
    assert_eq!(again[0].1["replayed"], true);
    assert_eq!(again[0].1["body"], "body wait 1");
    assert_eq!(
        runner.runs.load(Ordering::SeqCst),
        1,
        "replay does not re-run"
    );
    let next = events(post(&url, "wait", req("lav:wait:1:2", 2)).await).await;
    assert_eq!(
        (next[1].1["ok"].clone(), next[1].1["retry_in_s"].clone()),
        (json!(true), Value::Null)
    );
}

#[tokio::test]
async fn in_progress_is_409_and_the_attempt_survives_a_dropped_stream() {
    let (url, runner) = spawn().await;
    let first = post(&url, "gate", req("g1", 1)).await;
    assert_eq!(first.status(), 200);
    drop(first); // the caller's stream is lost mid-run
    while runner.runs.load(Ordering::SeqCst) == 0 {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    let same = post(&url, "gate", req("g1", 1)).await;
    assert_eq!(same.status(), 409);
    assert_eq!(same.json::<Value>().await.unwrap()["error"], "in_progress");
    assert_eq!(
        post(&url, "gate", req("g2", 1)).await.status(),
        409,
        "one attempt per job"
    );
    assert_eq!(
        post(&url, "ok", req("o1", 2)).await.status(),
        200,
        "other jobs run"
    );
    runner.gate.notify_one();
    let ev = loop {
        let r = post(&url, "gate", req("g1", 1)).await;
        if r.status() == 200 {
            break events(r).await;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    };
    assert_eq!(ev[0].1["replayed"], true);
    assert_eq!(
        post(&url, "ok", req("g1", 1)).await.status(),
        422,
        "key reused for another job"
    );
}

#[tokio::test]
async fn refusals_and_errors() {
    let (url, runner) = spawn().await;
    let anon = reqwest::Client::new()
        .post(format!("{url}/v1/jobs/ok"))
        .json(&req("a", 1))
        .send()
        .await
        .unwrap();
    assert_eq!(anon.status(), 401);
    assert_eq!(
        code(&url, json!({"idempotency_key":"a","attempt":1})).await,
        (422, "bad_body".into())
    );
    assert_eq!(
        code(
            &url,
            json!({"scheduled_minute":slot(),"idempotency_key":"a","attempt":1,"x":1})
        )
        .await,
        (422, "bad_body".into())
    );
    assert_eq!(
        code(&url, req("has space", 1)).await,
        (422, "bad_key".into())
    );
    assert_eq!(
        code(&url, req(&"k".repeat(129), 1)).await,
        (422, "bad_key".into())
    );
    assert_eq!(
        code(
            &url,
            json!({"scheduled_minute":slot()+1,"idempotency_key":"a","attempt":1})
        )
        .await,
        (422, "not_a_slot".into())
    );
    assert_eq!(
        code(
            &url,
            json!({"scheduled_minute":slot()+600,"idempotency_key":"a","attempt":1})
        )
        .await,
        (422, "stale".into())
    );
    assert_eq!(
        code(
            &url,
            json!({"scheduled_minute":slot()-7*3600,"idempotency_key":"a","attempt":1})
        )
        .await,
        (422, "stale".into())
    );
    assert_eq!(
        code(
            &url,
            json!({"scheduled_minute":slot()+60-300,"idempotency_key":"a","attempt":1})
        )
        .await
        .1,
        "not_a_slot"
    );
    assert_eq!(code(&url, req("a", 5)).await, (422, "bad_attempt".into()));
    let unknown = post(&url, "nope", req("a", 1)).await;
    assert_eq!(unknown.status(), 404);
    assert_eq!(
        unknown.json::<Value>().await.unwrap()["error"],
        "unknown_job"
    );
    assert_eq!(runner.runs.load(Ordering::SeqCst), 0, "nothing ran");
    let ev = events(post(&url, "boom", req("b", 1)).await).await;
    assert_eq!(
        ev,
        vec![("error".into(), json!({"error":"tool registry unavailable"}))]
    );
}

#[tokio::test]
async fn the_route_is_absent_without_a_runner() {
    let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = l.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(l, HttpGateway::router(Arc::new(NoAgent)))
            .await
            .unwrap()
    });
    let r = post(&format!("http://{addr}"), "ok", req("a", 1)).await;
    assert_eq!(r.status(), 404);
}
