//! Scheduled, **unconditional** actions for the Lavoisier agent.
//!
//! Where the cron gateway ([`lvz-gw-cron`]) fires a *prompt* and hopes the model picks the right
//! tool, a schedule job can name a **tool call directly** — it runs every time, deterministically,
//! with no model round-trip (and so no tokens). A job may still fire a prompt turn when the point
//! is for the agent to reason; both shapes live in [`Action`].
//!
//! The crate is deliberately **frontend-agnostic**: it owns timing, retry, and status, and hands
//! back a [`FireReport`] describing what happened. The caller (today the Matrix gateway) decides
//! where that report goes. Nothing here knows about Matrix.
//!
//! Three pieces:
//! - [`ScheduleRegistry`] — the jobs, their live [`JobState`], and the wait/fire loop. Shared as an
//!   `Arc` between the gateway that runs it and the tools that report on it.
//! - [`Action`] — a direct tool call or a prompt turn.
//! - The `schedule_list` / `schedule_status` / `schedule_run` tools (see [`tools`]), which let the
//!   agent answer "how's the backup job?" and "run it again" from chat.
//!
//! Retry mirrors the cron gateway's semantics exactly: up to `retry_max` attempts with a fixed
//! `retry_wait`, and **the next scheduled slot is recomputed from "now" once the retry chain
//! resolves**, so a retry's wait can never double-fire the following slot. Unlike cron, the wait is
//! not a blocking sleep — a pending retry is just another due time, so the host loop stays free.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use futures::StreamExt;
use lvz_protocol::{AgentHandle, Event, TurnRequest};
use lvz_tools::ToolRegistry;
use serde::Deserialize;
use tokio::sync::Notify;

mod cron;
pub mod tools;

pub use cron::{CronError, CronSchedule};
pub use tools::{ScheduleListTool, ScheduleRunTool, ScheduleStatusTool};

/// How many past outcomes each job keeps for `schedule_status`.
const HISTORY_CAP: usize = 20;

/// Longest action output carried into a status report / stored in state. Keeps a chatty job from
/// flooding a room or ballooning the tool output the model reads back.
const DETAIL_CAP: usize = 600;

/// What a job does when it fires.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Invoke a tool **directly** through the shared [`ToolRegistry`]. Deterministic and free —
    /// no model round-trip. This is the "unconditionally run this" case.
    Tool {
        name: String,
        args: serde_json::Value,
    },
    /// Fire a prompt into the agent and let it decide which tools to call (the cron gateway's
    /// behaviour). Use when the job needs reasoning or a written summary.
    Prompt { text: String },
}

impl Action {
    /// One-line description for listings and reports.
    pub fn summary(&self) -> String {
        match self {
            Action::Tool { name, .. } => format!("tool `{name}`"),
            Action::Prompt { text } => format!("prompt {:?}", truncate(text, 60)),
        }
    }
}

/// A single scheduled job.
#[derive(Debug, Clone)]
pub struct ScheduleJob {
    /// Stable, user-facing identifier — how chat names the job ("how's `disk` doing?").
    pub id: String,
    /// The cron expression as written, kept for display.
    pub expr: String,
    pub schedule: CronSchedule,
    pub action: Action,
    /// Where to report this job's outcome. `None` ⇒ the caller's default room.
    pub room: Option<String>,
    /// Agent session for `Action::Prompt`, so a job accrues memory across fires.
    pub session: String,
    /// Retries after a failed fire; 0 = no retry.
    pub retry_max: u32,
    /// Fixed seconds between retries; ignored when `retry_max == 0`.
    pub retry_wait: u64,
}

/// The JSON shape of one entry in a `--schedule-file`.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct JobSpec {
    id: String,
    schedule: String,
    #[serde(default)]
    room: Option<String>,
    #[serde(default)]
    session: Option<String>,
    #[serde(default)]
    tool: Option<String>,
    #[serde(default)]
    args: Option<serde_json::Value>,
    #[serde(default)]
    prompt: Option<String>,
    #[serde(default)]
    retry_max: Option<u32>,
    #[serde(default)]
    retry_wait: Option<u64>,
}

/// A failure building jobs from a schedule file.
#[derive(Debug, thiserror::Error)]
pub enum ScheduleConfigError {
    #[error("invalid schedule JSON: {0}")]
    Json(String),
    #[error("job {id:?}: invalid cron expression: {source}")]
    Cron { id: String, source: CronError },
    #[error("job {id:?}: specify exactly one of `tool` or `prompt`")]
    Action { id: String },
    #[error("duplicate job id {0:?}")]
    DuplicateId(String),
}

impl ScheduleJob {
    /// Parse a JSON array of job specs, applying the global `retry_max`/`retry_wait` defaults to
    /// any job that doesn't override them.
    pub fn parse_file(
        json: &str,
        retry_max: u32,
        retry_wait: u64,
    ) -> Result<Vec<Self>, ScheduleConfigError> {
        let specs: Vec<JobSpec> =
            serde_json::from_str(json).map_err(|e| ScheduleConfigError::Json(e.to_string()))?;
        let mut seen = std::collections::HashSet::new();
        let mut jobs = Vec::with_capacity(specs.len());
        for spec in specs {
            if !seen.insert(spec.id.clone()) {
                return Err(ScheduleConfigError::DuplicateId(spec.id));
            }
            // `tool` and `prompt` are mutually exclusive, and one is required — an ambiguous job
            // would silently do the wrong thing forever, so reject it at load.
            let action = match (&spec.tool, &spec.prompt) {
                (Some(name), None) => Action::Tool {
                    name: name.clone(),
                    args: spec.args.clone().unwrap_or_else(|| serde_json::json!({})),
                },
                (None, Some(text)) => Action::Prompt { text: text.clone() },
                _ => return Err(ScheduleConfigError::Action { id: spec.id }),
            };
            let schedule =
                CronSchedule::parse(&spec.schedule).map_err(|e| ScheduleConfigError::Cron {
                    id: spec.id.clone(),
                    source: e,
                })?;
            let session = spec
                .session
                .clone()
                .unwrap_or_else(|| format!("schedule-{}", spec.id));
            jobs.push(ScheduleJob {
                expr: spec.schedule.clone(),
                schedule,
                action,
                room: spec.room.clone(),
                session,
                retry_max: spec.retry_max.unwrap_or(retry_max),
                retry_wait: spec.retry_wait.unwrap_or(retry_wait),
                id: spec.id,
            });
        }
        Ok(jobs)
    }
}

/// One recorded fire.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Outcome {
    /// Unix seconds when the attempt finished.
    pub at: u64,
    pub ok: bool,
    /// Output summary on success, error text on failure.
    pub detail: String,
    /// 1 for the first attempt of a chain, 2 for the first retry, …
    pub attempt: u32,
}

/// Live state for one job. Read by the `schedule_*` tools.
#[derive(Debug, Clone, Default)]
pub struct JobState {
    /// Next cron slot, or `None` while a retry chain is in flight (the retry supersedes it) or the
    /// schedule can never fire again.
    pub next_due: Option<u64>,
    /// When the in-flight retry should run.
    pub retry_at: Option<u64>,
    /// Attempts used in the current chain (0 when idle).
    pub attempt: u32,
    pub last_fired: Option<u64>,
    pub last_ok: Option<bool>,
    pub runs: u64,
    pub failures: u64,
    pub consecutive_failures: u32,
    pub history: VecDeque<Outcome>,
}

/// What happened on one fire, for the caller to deliver. `body` is preformatted — every fire
/// reports, and failures are louder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireReport {
    pub job_id: String,
    /// The job's own room, if it set one; otherwise the caller's default.
    pub room: Option<String>,
    pub ok: bool,
    pub body: String,
}

/// The jobs, their live state, and the wait/fire loop. Shared as an `Arc` between the gateway
/// driving it and the `schedule_*` tools reporting on it.
pub struct ScheduleRegistry {
    jobs: Vec<ScheduleJob>,
    state: RwLock<HashMap<String, JobState>>,
    /// Manual `schedule_run` requests, as job indices.
    requested: Mutex<VecDeque<usize>>,
    /// Wakes [`wait_due`](Self::wait_due) when a manual run is queued.
    notify: Notify,
}

impl ScheduleRegistry {
    /// Build a registry over `jobs` and arm each one's first slot.
    pub fn new(jobs: Vec<ScheduleJob>) -> Self {
        let mut state = HashMap::new();
        for job in &jobs {
            state.insert(
                job.id.clone(),
                JobState {
                    next_due: job.schedule.next_after_now(),
                    ..Default::default()
                },
            );
        }
        Self {
            jobs,
            state: RwLock::new(state),
            requested: Mutex::new(VecDeque::new()),
            notify: Notify::new(),
        }
    }

    pub fn jobs(&self) -> &[ScheduleJob] {
        &self.jobs
    }

    pub fn is_empty(&self) -> bool {
        self.jobs.is_empty()
    }

    pub fn len(&self) -> usize {
        self.jobs.len()
    }

    /// A snapshot of one job's state.
    pub fn state_of(&self, id: &str) -> Option<JobState> {
        self.state.read().ok()?.get(id).cloned()
    }

    /// Index of a job by id.
    pub fn index_of(&self, id: &str) -> Option<usize> {
        self.jobs.iter().position(|j| j.id == id)
    }

    /// Queue an out-of-band run of `id` (the "retry it now" path used by `schedule_run`), waking
    /// the wait loop. Returns false if no such job.
    pub fn request_run(&self, id: &str) -> bool {
        let Some(idx) = self.index_of(id) else {
            return false;
        };
        if let Ok(mut q) = self.requested.lock() {
            q.push_back(idx);
        }
        self.notify.notify_one();
        true
    }

    /// The effective next fire time for a job: a pending retry supersedes the cron slot.
    fn due_at(&self, job: &ScheduleJob) -> Option<u64> {
        let state = self.state.read().ok()?;
        let s = state.get(&job.id)?;
        s.retry_at.or(s.next_due)
    }

    /// Wait until at least one job is due (scheduled or manually requested) and return their
    /// indices.
    ///
    /// Cancel-safe: the caller may drop this future (e.g. losing a `select!` race) without losing
    /// work — all state lives in the registry, and a queued manual run keeps its wakeup.
    pub async fn wait_due(&self) -> Vec<usize> {
        loop {
            let manual = self.take_requested();
            if !manual.is_empty() {
                return manual;
            }
            let now = now_unix();
            let mut soonest: Option<u64> = None;
            let mut due = Vec::new();
            for (i, job) in self.jobs.iter().enumerate() {
                let Some(at) = self.due_at(job) else { continue };
                if at <= now {
                    due.push(i);
                } else {
                    soonest = Some(soonest.map_or(at, |s: u64| s.min(at)));
                }
            }
            if !due.is_empty() {
                return due;
            }
            // Nothing due: sleep until the soonest slot, or idle in case a manual run arrives.
            let wait = soonest.map_or(3600, |at| at.saturating_sub(now).max(1));
            tokio::select! {
                _ = tokio::time::sleep(Duration::from_secs(wait)) => {}
                _ = self.notify.notified() => {}
            }
        }
    }

    fn take_requested(&self) -> Vec<usize> {
        self.requested
            .lock()
            .map(|mut q| q.drain(..).collect())
            .unwrap_or_default()
    }

    /// Run job `idx` once, record the outcome, schedule any retry, and return the report to
    /// deliver. `None` if `idx` is out of range.
    pub async fn fire(
        &self,
        idx: usize,
        tools: &ToolRegistry,
        agent: &Arc<dyn AgentHandle>,
    ) -> Option<FireReport> {
        let job = self.jobs.get(idx)?.clone();
        let result = run_action(&job, tools, agent).await;
        Some(self.record(&job, result))
    }

    /// Fold one attempt's result into the job's state and build its report.
    fn record(&self, job: &ScheduleJob, result: Result<String, String>) -> FireReport {
        let now = now_unix();
        let ok = result.is_ok();
        let detail = truncate(
            match &result {
                Ok(s) => s,
                Err(e) => e,
            },
            DETAIL_CAP,
        );

        // Decide the follow-up before touching state so the report and the schedule agree.
        let mut retry_in = None;
        let mut gave_up = false;
        let attempt;
        {
            let mut guard = self.state.write().expect("schedule state poisoned");
            let s = guard.entry(job.id.clone()).or_default();
            s.attempt += 1;
            attempt = s.attempt;
            s.runs += 1;
            s.last_fired = Some(now);
            s.last_ok = Some(ok);
            s.history.push_back(Outcome {
                at: now,
                ok,
                detail: detail.clone(),
                attempt,
            });
            while s.history.len() > HISTORY_CAP {
                s.history.pop_front();
            }
            if ok {
                s.consecutive_failures = 0;
            } else {
                s.failures += 1;
                s.consecutive_failures += 1;
            }

            // Retry bookkeeping. While a chain is in flight the cron slot is suppressed
            // (`next_due = None`) so a retry can never race the following slot; once the chain
            // resolves — success or exhaustion — the next slot is recomputed from *now*, exactly
            // as the cron gateway does.
            if !ok && attempt <= job.retry_max {
                s.retry_at = Some(now + job.retry_wait);
                s.next_due = None;
                retry_in = Some(job.retry_wait);
            } else {
                gave_up = !ok && job.retry_max > 0;
                s.retry_at = None;
                s.attempt = 0;
                s.next_due = job.schedule.next_after(now);
            }
        }

        FireReport {
            job_id: job.id.clone(),
            room: job.room.clone(),
            ok,
            body: report_body(job, ok, &detail, attempt, retry_in, gave_up),
        }
    }
}

/// Execute a job's action once. `Ok(summary)` on success, `Err(error)` on a failure worth retrying.
///
/// For a tool call, a tool that reports `is_error` counts as a failure — that is the whole point of
/// "unconditional": the call always happens, and a non-zero exit is a real failure, not a nudge to
/// the model. For a prompt turn the rule matches the cron gateway: a rejected submit or a mid-turn
/// stream error fails, while a *completed* turn succeeds even if the answer is weak (that is
/// semantic, and not knowable here).
async fn run_action(
    job: &ScheduleJob,
    tools: &ToolRegistry,
    agent: &Arc<dyn AgentHandle>,
) -> Result<String, String> {
    match &job.action {
        Action::Tool { name, args } => match tools.invoke(name, args.clone()).await {
            Err(e) => Err(format!("tool `{name}` failed: {e}")),
            Ok(out) if out.is_error => Err(format!("tool `{name}` reported: {}", out.content)),
            Ok(out) => Ok(out.content),
        },
        Action::Prompt { text } => {
            let turn = TurnRequest::new(job.session.clone(), text.clone());
            let mut stream = agent
                .submit(turn)
                .await
                .map_err(|e| format!("submit failed: {e}"))?;
            let mut answer = String::new();
            let mut used: Vec<String> = Vec::new();
            while let Some(item) = stream.next().await {
                match item {
                    Ok(Event::TextDelta(t)) => answer.push_str(&t),
                    Ok(Event::ToolUseStart { name, .. }) => used.push(name),
                    Ok(_) => {}
                    Err(e) => return Err(format!("stream error: {e}")),
                }
            }
            let tools_note = if used.is_empty() {
                String::new()
            } else {
                format!(" [tools: {}]", used.join(", "))
            };
            Ok(format!("{}{tools_note}", answer.trim()))
        }
    }
}

/// Format a fire's report body. Every fire reports; failures are louder (multi-line, with the
/// retry countdown or the give-up notice).
fn report_body(
    job: &ScheduleJob,
    ok: bool,
    detail: &str,
    attempt: u32,
    retry_in: Option<u64>,
    gave_up: bool,
) -> String {
    if ok {
        let detail = detail.trim();
        let retried = if attempt > 1 {
            format!(" (after {} attempt{})", attempt, plural(attempt))
        } else {
            String::new()
        };
        if detail.is_empty() {
            format!("✅ `{}`{retried}", job.id)
        } else {
            format!("✅ `{}`{retried} · {detail}", job.id)
        }
    } else {
        let mut body = format!(
            "❌ `{}` failed (attempt {attempt})\n{}",
            job.id,
            detail.trim()
        );
        if let Some(wait) = retry_in {
            body.push_str(&format!(
                "\n↻ retry {}/{} in {}s",
                attempt, job.retry_max, wait
            ));
        } else if gave_up {
            body.push_str(&format!(
                "\n⛔ gave up after {} retr{}",
                job.retry_max,
                if job.retry_max == 1 { "y" } else { "ies" }
            ));
        }
        body
    }
}

fn plural(n: u32) -> &'static str {
    if n == 1 {
        ""
    } else {
        "s"
    }
}

/// Truncate to `cap` chars on a char boundary, marking elision.
fn truncate(s: &str, cap: usize) -> String {
    let s = s.trim();
    if s.chars().count() <= cap {
        return s.to_string();
    }
    let head: String = s.chars().take(cap).collect();
    format!("{head}… [truncated]")
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn job(id: &str, action: Action) -> ScheduleJob {
        ScheduleJob {
            id: id.to_string(),
            expr: "* * * * *".to_string(),
            schedule: CronSchedule::parse("* * * * *").unwrap(),
            action,
            room: None,
            session: format!("schedule-{id}"),
            retry_max: 0,
            retry_wait: 0,
        }
    }

    fn tool_job(id: &str) -> ScheduleJob {
        job(
            id,
            Action::Tool {
                name: "shell".into(),
                args: serde_json::json!({"command": "true"}),
            },
        )
    }

    #[test]
    fn parses_tool_and_prompt_jobs() {
        let json = r#"[
            {"id":"disk","schedule":"0 9 * * *","room":"!ops:hs","tool":"shell","args":{"command":"df -h"}},
            {"id":"build","schedule":"*/15 * * * *","prompt":"check the build"}
        ]"#;
        let jobs = ScheduleJob::parse_file(json, 0, 0).unwrap();
        assert_eq!(jobs.len(), 2);
        assert_eq!(
            jobs[0].action,
            Action::Tool {
                name: "shell".into(),
                args: serde_json::json!({"command": "df -h"}),
            }
        );
        assert_eq!(jobs[0].room.as_deref(), Some("!ops:hs"));
        // Session defaults to `schedule-<id>` so a prompt job accrues memory across fires.
        assert_eq!(jobs[1].session, "schedule-build");
        assert_eq!(
            jobs[1].action,
            Action::Prompt {
                text: "check the build".into()
            }
        );
    }

    #[test]
    fn rejects_job_with_both_or_neither_action() {
        let both = r#"[{"id":"x","schedule":"* * * * *","tool":"shell","prompt":"hi"}]"#;
        assert!(matches!(
            ScheduleJob::parse_file(both, 0, 0),
            Err(ScheduleConfigError::Action { .. })
        ));
        let neither = r#"[{"id":"x","schedule":"* * * * *"}]"#;
        assert!(matches!(
            ScheduleJob::parse_file(neither, 0, 0),
            Err(ScheduleConfigError::Action { .. })
        ));
    }

    #[test]
    fn rejects_duplicate_ids_and_bad_cron() {
        let dup = r#"[{"id":"x","schedule":"* * * * *","prompt":"a"},
                      {"id":"x","schedule":"* * * * *","prompt":"b"}]"#;
        assert!(matches!(
            ScheduleJob::parse_file(dup, 0, 0),
            Err(ScheduleConfigError::DuplicateId(_))
        ));
        let bad = r#"[{"id":"x","schedule":"nope","prompt":"a"}]"#;
        assert!(matches!(
            ScheduleJob::parse_file(bad, 0, 0),
            Err(ScheduleConfigError::Cron { .. })
        ));
    }

    #[test]
    fn per_job_retry_overrides_global_default() {
        let json = r#"[
            {"id":"a","schedule":"* * * * *","prompt":"a"},
            {"id":"b","schedule":"* * * * *","prompt":"b","retry_max":5,"retry_wait":30}
        ]"#;
        let jobs = ScheduleJob::parse_file(json, 2, 60).unwrap();
        assert_eq!((jobs[0].retry_max, jobs[0].retry_wait), (2, 60));
        assert_eq!((jobs[1].retry_max, jobs[1].retry_wait), (5, 30));
    }

    #[test]
    fn unknown_field_is_rejected() {
        let json = r#"[{"id":"x","schedule":"* * * * *","prompt":"a","typo":1}]"#;
        assert!(matches!(
            ScheduleJob::parse_file(json, 0, 0),
            Err(ScheduleConfigError::Json(_))
        ));
    }

    #[test]
    fn new_arms_next_due_for_every_job() {
        let reg = ScheduleRegistry::new(vec![tool_job("a"), tool_job("b")]);
        for id in ["a", "b"] {
            assert!(reg.state_of(id).unwrap().next_due.is_some());
        }
        assert_eq!(reg.len(), 2);
    }

    #[test]
    fn request_run_queues_only_known_jobs() {
        let reg = ScheduleRegistry::new(vec![tool_job("a")]);
        assert!(reg.request_run("a"));
        assert!(!reg.request_run("nope"));
        assert_eq!(reg.take_requested(), vec![0]);
        assert!(reg.take_requested().is_empty());
    }

    #[test]
    fn success_records_history_and_rearms() {
        let reg = ScheduleRegistry::new(vec![tool_job("a")]);
        let report = reg.record(&reg.jobs[0].clone(), Ok("all good".into()));
        assert!(report.ok);
        assert!(report.body.starts_with("✅ `a`"));
        assert!(report.body.contains("all good"));
        let s = reg.state_of("a").unwrap();
        assert_eq!((s.runs, s.failures, s.consecutive_failures), (1, 0, 0));
        assert_eq!(s.last_ok, Some(true));
        assert_eq!(s.history.len(), 1);
        // Chain idle, next slot re-armed.
        assert_eq!(s.attempt, 0);
        assert!(s.retry_at.is_none());
        assert!(s.next_due.is_some());
    }

    #[test]
    fn failure_without_retries_gives_up_immediately() {
        let reg = ScheduleRegistry::new(vec![tool_job("a")]);
        let report = reg.record(&reg.jobs[0].clone(), Err("boom".into()));
        assert!(!report.ok);
        assert!(report.body.starts_with("❌ `a` failed (attempt 1)"));
        assert!(report.body.contains("boom"));
        // retry_max = 0 ⇒ no retry line, no give-up line (there was nothing to give up on).
        assert!(!report.body.contains("↻"));
        assert!(!report.body.contains("⛔"));
        let s = reg.state_of("a").unwrap();
        assert_eq!((s.runs, s.failures, s.consecutive_failures), (1, 1, 1));
        assert!(s.retry_at.is_none());
        assert!(s.next_due.is_some());
    }

    #[test]
    fn failure_schedules_retry_then_gives_up_after_max() {
        let mut j = tool_job("a");
        j.retry_max = 2;
        j.retry_wait = 30;
        let reg = ScheduleRegistry::new(vec![j]);
        let j = reg.jobs[0].clone();

        // Attempt 1 fails → retry 1/2 queued, cron slot suppressed so it can't race the retry.
        let r1 = reg.record(&j, Err("boom".into()));
        assert!(r1.body.contains("↻ retry 1/2 in 30s"));
        let s = reg.state_of("a").unwrap();
        assert!(s.retry_at.is_some());
        assert!(s.next_due.is_none());
        assert_eq!(s.attempt, 1);

        // Attempt 2 fails → retry 2/2 queued.
        let r2 = reg.record(&j, Err("boom".into()));
        assert!(r2.body.contains("↻ retry 2/2 in 30s"));
        assert_eq!(reg.state_of("a").unwrap().attempt, 2);

        // Attempt 3 exhausts the budget → give up and re-arm the cron slot from now.
        let r3 = reg.record(&j, Err("boom".into()));
        assert!(r3.body.contains("⛔ gave up after 2 retries"));
        let s = reg.state_of("a").unwrap();
        assert!(s.retry_at.is_none());
        assert!(s.next_due.is_some());
        assert_eq!(s.attempt, 0);
        assert_eq!((s.runs, s.failures, s.consecutive_failures), (3, 3, 3));
    }

    #[test]
    fn success_after_retry_notes_the_attempts_and_clears_the_streak() {
        let mut j = tool_job("a");
        j.retry_max = 3;
        j.retry_wait = 5;
        let reg = ScheduleRegistry::new(vec![j]);
        let j = reg.jobs[0].clone();
        reg.record(&j, Err("boom".into()));
        let ok = reg.record(&j, Ok("recovered".into()));
        assert!(ok.ok);
        assert!(ok.body.contains("after 2 attempts"));
        let s = reg.state_of("a").unwrap();
        assert_eq!(s.consecutive_failures, 0);
        assert_eq!(s.attempt, 0);
        assert!(s.next_due.is_some());
    }

    #[test]
    fn history_is_bounded() {
        let reg = ScheduleRegistry::new(vec![tool_job("a")]);
        let j = reg.jobs[0].clone();
        for _ in 0..(HISTORY_CAP + 5) {
            reg.record(&j, Ok("x".into()));
        }
        assert_eq!(reg.state_of("a").unwrap().history.len(), HISTORY_CAP);
    }

    #[test]
    fn report_carries_the_jobs_own_room() {
        let mut j = tool_job("a");
        j.room = Some("!ops:hs".into());
        let reg = ScheduleRegistry::new(vec![j]);
        let report = reg.record(&reg.jobs[0].clone(), Ok("x".into()));
        assert_eq!(report.room.as_deref(), Some("!ops:hs"));
    }

    #[test]
    fn long_output_is_truncated() {
        let reg = ScheduleRegistry::new(vec![tool_job("a")]);
        let report = reg.record(&reg.jobs[0].clone(), Ok("x".repeat(5_000)));
        assert!(report.body.contains("[truncated]"));
        assert!(report.body.chars().count() < DETAIL_CAP + 100);
    }

    #[tokio::test]
    async fn wait_due_returns_manual_requests_immediately() {
        // Both jobs are a minute away, so only the manual request can be due.
        let reg = ScheduleRegistry::new(vec![tool_job("a"), tool_job("b")]);
        assert!(reg.request_run("b"));
        assert_eq!(reg.wait_due().await, vec![1]);
    }

    #[tokio::test]
    async fn wait_due_returns_jobs_whose_slot_has_passed() {
        let reg = ScheduleRegistry::new(vec![tool_job("a"), tool_job("b")]);
        // Force job `a` overdue; `b` stays in the future.
        reg.state.write().unwrap().get_mut("a").unwrap().next_due = Some(now_unix() - 1);
        assert_eq!(reg.wait_due().await, vec![0]);
    }

    #[tokio::test]
    async fn wait_due_picks_up_a_pending_retry() {
        let reg = ScheduleRegistry::new(vec![tool_job("a")]);
        {
            let mut g = reg.state.write().unwrap();
            let s = g.get_mut("a").unwrap();
            s.next_due = None;
            s.retry_at = Some(now_unix() - 1);
        }
        assert_eq!(reg.wait_due().await, vec![0]);
    }

    #[tokio::test]
    async fn fire_runs_a_tool_action_through_the_registry() {
        use lvz_protocol::{Tool, ToolError, ToolOutput};

        struct Echo;
        #[async_trait::async_trait]
        impl Tool for Echo {
            fn name(&self) -> &str {
                "echo"
            }
            fn schema(&self) -> serde_json::Value {
                serde_json::json!({"type": "object"})
            }
            async fn invoke(&self, args: serde_json::Value) -> Result<ToolOutput, ToolError> {
                Ok(ToolOutput::ok(
                    args["msg"].as_str().unwrap_or_default().to_string(),
                ))
            }
        }

        struct DeadAgent;
        #[async_trait::async_trait]
        impl AgentHandle for DeadAgent {
            async fn submit(
                &self,
                _turn: TurnRequest,
            ) -> Result<
                futures::stream::BoxStream<'static, Result<Event, lvz_protocol::AgentError>>,
                lvz_protocol::AgentError,
            > {
                Err(lvz_protocol::AgentError::Provider("unused".into()))
            }
        }

        let mut tools = ToolRegistry::new();
        tools.register(Arc::new(Echo));
        let agent: Arc<dyn AgentHandle> = Arc::new(DeadAgent);

        let j = job(
            "e",
            Action::Tool {
                name: "echo".into(),
                args: serde_json::json!({"msg": "hello from the schedule"}),
            },
        );
        let reg = ScheduleRegistry::new(vec![j]);
        let report = reg.fire(0, &tools, &agent).await.unwrap();
        // The tool ran with no model round-trip at all — that is the "unconditional" guarantee.
        assert!(report.ok);
        assert!(report.body.contains("hello from the schedule"));
        assert_eq!(reg.state_of("e").unwrap().runs, 1);
        assert!(reg.fire(99, &tools, &agent).await.is_none());
    }

    #[tokio::test]
    async fn a_tool_reporting_is_error_counts_as_failure() {
        use lvz_protocol::{Tool, ToolError, ToolOutput};

        struct Failing;
        #[async_trait::async_trait]
        impl Tool for Failing {
            fn name(&self) -> &str {
                "failing"
            }
            fn schema(&self) -> serde_json::Value {
                serde_json::json!({"type": "object"})
            }
            async fn invoke(&self, _args: serde_json::Value) -> Result<ToolOutput, ToolError> {
                Ok(ToolOutput::error("exit status 1"))
            }
        }

        struct DeadAgent;
        #[async_trait::async_trait]
        impl AgentHandle for DeadAgent {
            async fn submit(
                &self,
                _turn: TurnRequest,
            ) -> Result<
                futures::stream::BoxStream<'static, Result<Event, lvz_protocol::AgentError>>,
                lvz_protocol::AgentError,
            > {
                Err(lvz_protocol::AgentError::Provider("unused".into()))
            }
        }

        let mut tools = ToolRegistry::new();
        tools.register(Arc::new(Failing));
        let agent: Arc<dyn AgentHandle> = Arc::new(DeadAgent);
        let reg = ScheduleRegistry::new(vec![job(
            "f",
            Action::Tool {
                name: "failing".into(),
                args: serde_json::json!({}),
            },
        )]);
        let report = reg.fire(0, &tools, &agent).await.unwrap();
        assert!(!report.ok);
        assert!(report.body.contains("exit status 1"));
        assert_eq!(reg.state_of("f").unwrap().failures, 1);
    }

    #[tokio::test]
    async fn an_unknown_tool_is_a_failure_not_a_panic() {
        struct DeadAgent;
        #[async_trait::async_trait]
        impl AgentHandle for DeadAgent {
            async fn submit(
                &self,
                _turn: TurnRequest,
            ) -> Result<
                futures::stream::BoxStream<'static, Result<Event, lvz_protocol::AgentError>>,
                lvz_protocol::AgentError,
            > {
                Err(lvz_protocol::AgentError::Provider("unused".into()))
            }
        }
        let tools = ToolRegistry::new();
        let agent: Arc<dyn AgentHandle> = Arc::new(DeadAgent);
        let reg = ScheduleRegistry::new(vec![job(
            "u",
            Action::Tool {
                name: "nosuchtool".into(),
                args: serde_json::json!({}),
            },
        )]);
        let report = reg.fire(0, &tools, &agent).await.unwrap();
        assert!(!report.ok);
        assert!(report.body.contains("nosuchtool"));
    }
}
