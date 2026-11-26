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
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
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

    /// Cancel the real work of a running attempt. The default does nothing.
    async fn cancel(&self, _job: &str, _key: &str) {}
}

#[derive(Clone)]
enum Terminal {
    Report(JobReport),
    Error(String),
}

struct Entry {
    job: String,
    done: Option<Terminal>,
    /// Set when a persisted `running` row is read back after a restart.
    lost: bool,
    waiting: Option<String>,
    at: Instant,
}

pub(crate) struct JobsState {
    runner: Arc<dyn JobRunner>,
    entries: Mutex<HashMap<String, Entry>>,
    dir: Option<std::path::PathBuf>,
}

/// The route, unguarded; `router_with` puts it behind the API-key guard.
///
/// `dir` persists attempts. A `running` row read back at startup is `lost`.
pub(crate) fn router(runner: Arc<dyn JobRunner>, dir: Option<std::path::PathBuf>) -> Router {
    let mut entries = HashMap::new();
    if let Some(dir) = &dir {
        for (key, entry) in load_attempts(dir) {
            entries.insert(key, entry);
        }
    }
    let state = Arc::new(JobsState {
        runner,
        entries: Mutex::new(entries),
        dir,
    });
    Router::new()
        .route("/v1/jobs/{id}", post(post_job))
        .route(
            "/v1/jobs/{id}/attempts/{key}",
            axum::routing::get(get_attempt).delete(delete_attempt),
        )
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

fn respond_async(headers: &axum::http::HeaderMap) -> bool {
    headers
        .get("prefer")
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.to_ascii_lowercase().contains("respond-async"))
}

async fn post_job(
    Path(id): Path<String>,
    State(st): State<Arc<JobsState>>,
    headers: axum::http::HeaderMap,
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

    let async_ack = respond_async(&headers);
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
                lost: false,
                waiting: None,
                at: Instant::now(),
            },
        );
        save_attempt(&st, &req.idempotency_key);
    }

    // Detached: a dropped stream does not cancel the attempt; its verdict stays replayable.
    let status_key = req.idempotency_key.clone();
    let status_job = id.clone();
    tokio::spawn(async move {
        let wtx = tx.clone();
        let wjob = id.clone();
        let wst = Arc::clone(&st);
        let wkey = req.idempotency_key.clone();
        let mut sent = false;
        let waiting = Box::new(move |body: String| {
            if let Ok(mut map) = wst.entries.lock() {
                if let Some(entry) = map.get_mut(&wkey) {
                    if entry.waiting.is_none() {
                        entry.waiting = Some(body.clone());
                    }
                }
            }
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
        save_attempt(&st, &req.idempotency_key);
        let _ = tx.send(terminal_event(&id, &t, false));
    });
    if async_ack {
        let status_url = format!("/v1/jobs/{status_job}/attempts/{status_key}");
        return (
            StatusCode::ACCEPTED,
            Json(serde_json::json!({
                "attempt": status_key,
                "status_url": status_url,
            })),
        )
            .into_response();
    }
    sse(rx)
}

async fn get_attempt(
    Path((id, key)): Path<(String, String)>,
    State(st): State<Arc<JobsState>>,
) -> Response {
    let map = match st.entries.lock() {
        Ok(map) => map,
        Err(err) => err.into_inner(),
    };
    let Some(entry) = map.get(&key) else {
        return reject(StatusCode::NOT_FOUND, "unknown_attempt", "no such attempt");
    };
    if entry.job != id {
        return reject(StatusCode::NOT_FOUND, "unknown_attempt", "no such attempt");
    }
    let state = if entry.lost {
        "lost"
    } else {
        match &entry.done {
            None => "running",
            Some(Terminal::Report(report)) if report.ok => "done",
            Some(_) => "failed",
        }
    };
    let report = match &entry.done {
        Some(Terminal::Report(report)) => serde_json::to_value(report).unwrap_or_default(),
        _ => serde_json::Value::Null,
    };
    Json(serde_json::json!({
        "state": state,
        "report": report,
        "waiting": entry.waiting,
    }))
    .into_response()
}

async fn delete_attempt(
    Path((id, key)): Path<(String, String)>,
    State(st): State<Arc<JobsState>>,
) -> StatusCode {
    st.runner.cancel(&id, &key).await;
    StatusCode::NO_CONTENT
}

fn save_attempt(st: &JobsState, key: &str) {
    let Some(dir) = st.dir.clone() else {
        return;
    };
    let record = {
        let map = match st.entries.lock() {
            Ok(map) => map,
            Err(err) => err.into_inner(),
        };
        let Some(entry) = map.get(key) else {
            return;
        };
        let state = if entry.lost {
            "lost"
        } else if entry.done.is_none() {
            "running"
        } else {
            "terminal"
        };
        serde_json::json!({
            "job": entry.job,
            "state": state,
            "waiting": entry.waiting,
            "done": match &entry.done {
                Some(Terminal::Report(report)) => serde_json::to_value(report).unwrap_or(serde_json::Value::Null),
                Some(Terminal::Error(text)) => serde_json::json!({ "error": text }),
                None => serde_json::Value::Null,
            },
        })
    };
    let _ = write_attempt(&dir, key, &record.to_string());
}

fn write_attempt(dir: &std::path::Path, key: &str, body: &str) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)?;
    let path = dir.join(key);
    let tmp = dir.join(format!(".{key}.tmp"));
    let mut file = std::fs::File::create(&tmp)?;
    std::io::Write::write_all(&mut file, body.as_bytes())?;
    file.sync_all()?;
    std::fs::rename(tmp, path)?;
    Ok(())
}

fn load_attempts(dir: &std::path::Path) -> Vec<(String, Entry)> {
    let Ok(read) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for item in read.flatten() {
        let Some(name) = item.file_name().to_str().map(str::to_string) else {
            continue;
        };
        if name.starts_with('.') {
            continue;
        }
        let Ok(bytes) = std::fs::read(item.path()) else {
            continue;
        };
        let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bytes) else {
            continue;
        };
        let Some(job) = value.get("job").and_then(|v| v.as_str()) else {
            continue;
        };
        let state = value.get("state").and_then(|v| v.as_str()).unwrap_or("");
        let done = match value.get("done") {
            Some(done) if done.get("error").and_then(|v| v.as_str()).is_some() => Some(
                Terminal::Error(done["error"].as_str().unwrap_or("").to_string()),
            ),
            Some(done) if done.get("ok").is_some() => serde_json::from_value(done.clone())
                .ok()
                .map(Terminal::Report),
            _ => None,
        };
        let lost = state == "running";
        if !lost && done.is_none() {
            continue;
        }
        out.push((
            name,
            Entry {
                job: job.to_string(),
                done,
                lost,
                waiting: value
                    .get("waiting")
                    .and_then(|v| v.as_str())
                    .map(str::to_string),
                at: Instant::now(),
            },
        ));
    }
    out
}
