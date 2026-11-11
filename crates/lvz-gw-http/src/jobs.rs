//! `POST /v1/jobs/{id}` — run **one attempt** of a scheduled job for an external clock
//! (`lav --serve-jobs`; spec: lvz-matrix-infra `LAV-JOBS-ROUTE-SPEC.md`).
//!
//! The caller owns the clock, the lease and the retry chain; this route owns nothing durable.
//! Request `{"scheduled_minute", "idempotency_key", "attempt"}`; the answer is an SSE stream:
//! at most one `event: waiting` (`{"job","body"}`), then exactly one terminal `event: report`
//! (`{"job","ok","body","attempt","retry_in_s","gave_up","images","replayed"}`) or
//! `event: error` (`{"error"}`), with a keep-alive comment every 15 s.
//!
//! Idempotency is in memory (lost on restart, which the caller's fenced receipt covers): a key
//! that is still running answers 409, a finished key replays its terminal event with
//! `replayed: true`. The attempt runs detached, so a dropped stream does not cancel it. One
//! attempt per job at a time (409 `in_progress` for a second key while one runs).
use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use axum::{
    body::Bytes,
    extract::{Path, State},
    http::StatusCode,
    response::{
        sse::{Event as SseEvent, KeepAlive, Sse},
        IntoResponse, Response,
    },
    routing::post,
    Json, Router,
};
use futures::stream::{self, StreamExt};
use futures::FutureExt;
use serde::{Deserialize, Serialize};

/// Finished keys kept for replay, at most.
pub const MAX_ENTRIES: usize = 1024;
/// How long a finished key is replayable.
pub const ENTRY_TTL: Duration = Duration::from_secs(24 * 3600);
/// Oldest `scheduled_minute` accepted, relative to now.
pub const MAX_AGE_SECS: u64 = 6 * 3600;

/// The request body.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct JobRequest {
    /// The cron slot being run: unix seconds, a multiple of 60.
    pub scheduled_minute: u64,
    /// Caller's key for this attempt (convention `{bot}:{job}:{minute}:{attempt}`).
    pub idempotency_key: String,
    /// 1-based attempt number within the caller's retry chain.
    pub attempt: u32,
}

/// Why a request is refused before anything runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JobRejection {
    /// No such job id (404).
    UnknownJob,
    /// 422 with a machine code (`not_a_slot`, `bad_attempt`, …) and a human message.
    Invalid(&'static str, String),
}

/// The verdict of one attempt.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct JobReport {
    /// Whether the attempt succeeded.
    pub ok: bool,
    /// The preformatted report text.
    pub body: String,
    /// The attempt number.
    pub attempt: u32,
    /// Seconds before the caller's next attempt; `None` = do not retry.
    pub retry_in_s: Option<u64>,
    /// The chain is exhausted.
    pub gave_up: bool,
    /// How many images the terminal result carried (not transported).
    pub images: usize,
}

/// What runs the attempt (implemented by `lavoisier` over `lvz-schedule`).
#[async_trait]
pub trait JobRunner: Send + Sync + 'static {
    /// Job-specific checks: known id, `scheduled_minute` is a cron slot, `attempt` in range.
    fn validate(&self, job: &str, req: &JobRequest) -> Result<(), JobRejection>;
    /// Run one attempt to its verdict. `waiting` gets the `⏳` line if work is accepted.
    /// `Err` = the attempt could not run at all (reported as `event: error`).
    async fn run(
        &self,
        job: &str,
        req: &JobRequest,
        waiting: Box<dyn FnMut(String) + Send>,
    ) -> Result<JobReport, String>;
}

#[derive(Clone)]
enum Terminal {
    Report(JobReport),
    Error(String),
}

struct Entry {
    job: String,
    done: Option<Terminal>,
    at: Instant,
}

pub(crate) struct JobsState {
    runner: Arc<dyn JobRunner>,
    entries: Mutex<HashMap<String, Entry>>,
}

/// The route, unguarded; `router_with` puts it behind the API-key guard.
pub(crate) fn router(runner: Arc<dyn JobRunner>) -> Router {
    let state = Arc::new(JobsState {
        runner,
        entries: Mutex::new(HashMap::new()),
    });
    Router::new()
        .route("/v1/jobs/{id}", post(post_job))
        .with_state(state)
}

fn reject(status: StatusCode, code: &str, message: &str) -> Response {
    (
        status,
        Json(serde_json::json!({ "error": code, "message": message })),
    )
        .into_response()
}

fn key_ok(k: &str) -> bool {
    (1..=128).contains(&k.len())
        && k.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._:@#-".contains(&b))
}

fn terminal_event(job: &str, t: &Terminal, replayed: bool) -> SseEvent {
    match t {
        Terminal::Report(r) => {
            let mut v = serde_json::to_value(r).unwrap_or_default();
            v["job"] = job.into();
            v["replayed"] = replayed.into();
            SseEvent::default().event("report").data(v.to_string())
        }
        Terminal::Error(e) => SseEvent::default()
            .event("error")
            .data(serde_json::json!({ "error": e }).to_string()),
    }
}

fn sse(rx: tokio::sync::mpsc::UnboundedReceiver<SseEvent>) -> Response {
    let s = stream::unfold(rx, |mut rx| async move {
        rx.recv().await.map(|e| (Ok::<_, Infallible>(e), rx))
    });
    Sse::new(s.boxed())
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)))
        .into_response()
}

async fn post_job(
    Path(id): Path<String>,
    State(st): State<Arc<JobsState>>,
    body: Bytes,
) -> Response {
    let req: JobRequest = match serde_json::from_slice(&body) {
        Ok(r) => r,
        Err(e) => return reject(StatusCode::UNPROCESSABLE_ENTITY, "bad_body", &e.to_string()),
    };
    if !key_ok(&req.idempotency_key) {
        let m = "idempotency_key: 1-128 chars of [A-Za-z0-9._:@#-]";
        return reject(StatusCode::UNPROCESSABLE_ENTITY, "bad_key", m);
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let m = req.scheduled_minute;
    if !m.is_multiple_of(60) {
        let msg = "scheduled_minute must be a multiple of 60";
        return reject(StatusCode::UNPROCESSABLE_ENTITY, "not_a_slot", msg);
    }
    if m > now + 60 || m + MAX_AGE_SECS < now {
        let msg = "scheduled_minute is in the future or older than 6 h";
        return reject(StatusCode::UNPROCESSABLE_ENTITY, "stale", msg);
    }
    match st.runner.validate(&id, &req) {
        Ok(()) => {}
        Err(JobRejection::UnknownJob) => {
            return reject(
                StatusCode::NOT_FOUND,
                "unknown_job",
                &format!("no job {id}"),
            )
        }
        Err(JobRejection::Invalid(code, msg)) => {
            return reject(StatusCode::UNPROCESSABLE_ENTITY, code, &msg)
        }
    }

    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    {
        let mut map = st.entries.lock().expect("jobs map poisoned");
        map.retain(|_, e| e.done.is_none() || e.at.elapsed() < ENTRY_TTL);
        if let Some(e) = map.get(&req.idempotency_key) {
            if e.job != id {
                let msg = "idempotency_key already used for another job";
                return reject(StatusCode::UNPROCESSABLE_ENTITY, "bad_key", msg);
            }
            return match &e.done {
                None => reject(StatusCode::CONFLICT, "in_progress", "this key is running"),
                Some(t) => {
                    let _ = tx.send(terminal_event(&id, t, true));
                    drop(tx);
                    sse(rx)
                }
            };
        }
        if map.values().any(|e| e.job == id && e.done.is_none()) {
            let msg = "another attempt of this job is running";
            return reject(StatusCode::CONFLICT, "in_progress", msg);
        }
        while map.len() >= MAX_ENTRIES {
            let oldest = map
                .iter()
                .filter(|(_, e)| e.done.is_some())
                .min_by_key(|(_, e)| e.at)
                .map(|(k, _)| k.clone());
            match oldest {
                Some(k) => map.remove(&k),
                None => break,
            };
        }
        map.insert(
            req.idempotency_key.clone(),
            Entry {
                job: id.clone(),
                done: None,
                at: Instant::now(),
            },
        );
    }

    // Detached: a dropped stream does not cancel the attempt; its verdict stays replayable.
    tokio::spawn(async move {
        let wtx = tx.clone();
        let wjob = id.clone();
        let mut sent = false;
        let waiting = Box::new(move |body: String| {
            if !std::mem::replace(&mut sent, true) {
                let d = serde_json::json!({ "job": wjob, "body": body }).to_string();
                let _ = wtx.send(SseEvent::default().event("waiting").data(d));
            }
        });
        let run = st.runner.run(&id, &req, waiting);
        let t = match std::panic::AssertUnwindSafe(run).catch_unwind().await {
            Ok(Ok(r)) => Terminal::Report(r),
            Ok(Err(e)) => Terminal::Error(e),
            Err(_) => Terminal::Error("job attempt panicked".into()),
        };
        if let Some(e) = st
            .entries
            .lock()
            .expect("jobs map poisoned")
            .get_mut(&req.idempotency_key)
        {
            e.done = Some(t.clone());
            e.at = Instant::now();
        }
        let _ = tx.send(terminal_event(&id, &t, false));
    });
    sse(rx)
}
