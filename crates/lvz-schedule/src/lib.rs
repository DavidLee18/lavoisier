//! Scheduled, **unconditional** actions for the Lavoisier agent.
//!
//! Where the cron gateway (`lvz-gw-cron`) fires a *prompt* and hopes the model picks the right
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

#![warn(missing_docs)]

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use futures::StreamExt;
use lvz_protocol::{AgentHandle, Event, TurnRequest, Usage};
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

/// Floor on the polling budget for accepted-but-unfinished work, so a tool reporting an
/// implausibly small estimate still gets a usable window.
const MIN_PENDING_BUDGET: u64 = 60;

/// Polling budget when neither the tool nor the deployment says how long the work takes.
pub const DEFAULT_PENDING_TIMEOUT: u64 = 600;

/// How long between polls of accepted-but-unfinished work.
///
/// Flat, deliberately. An earlier version waited out the tool's own `estimated_seconds` before the
/// first poll to avoid redundant calls; a fixed cadence is simpler to reason about and to predict
/// in the operator log, and the cost is a handful of cheap local tool calls. `estimated_seconds`
/// still sets the DEADLINE — it just no longer paces the polling.
const POLL_INTERVAL: u64 = 30;

/// What a job does when it fires.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Invoke a tool **directly** through the shared [`ToolRegistry`]. Deterministic and free —
    /// no model round-trip. This is the "unconditionally run this" case.
    Tool {
        /// Registry name of the tool to invoke.
        name: String,
        /// JSON arguments passed straight to the tool, verbatim on every fire.
        args: serde_json::Value,
    },
    /// Fire a prompt into the agent and let it decide which tools to call (the cron gateway's
    /// behaviour). Use when the job needs reasoning or a written summary.
    Prompt {
        /// The prompt fired into the agent, exactly as the model receives it.
        text: String,
    },
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
    /// The parsed form of `expr`, driving the wait/fire loop.
    pub schedule: CronSchedule,
    /// What the job does when it fires — a direct tool call or a prompt turn.
    pub action: Action,
    /// Where to report this job's outcome. `None` ⇒ the caller's default room.
    pub room: Option<String>,
    /// Agent session for `Action::Prompt`, so a job accrues memory across fires.
    pub session: String,
    /// Optional instruction to render a tool action's raw output as prose before it is posted to the
    /// room — for **both** outcomes (the owner's 2026-08-10 amendment; successes-only originally).
    /// When set on an [`Action::Tool`] job, the tool still runs deterministically; its output (or the
    /// error text) is then handed to a **tool-less** turn (empty allowlist) that rewrites it under
    /// this instruction, prefixed with a `SUCCESS`/`FAILURE` line so the register matches. `None` ⇒
    /// post the raw output as before. The verdict stays the tool's, and the ❌ marker + retry
    /// countdown stay structural (composed outside the prose), so a paraphrase can never hide a failure.
    pub summarize: Option<String>,
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
    summarize: Option<String>,
    #[serde(default)]
    retry_max: Option<u32>,
    #[serde(default)]
    retry_wait: Option<u64>,
}

/// A failure building jobs from a schedule file.
#[derive(Debug, thiserror::Error)]
pub enum ScheduleConfigError {
    /// The file was not the expected JSON array of job specs.
    #[error("invalid schedule JSON: {0}")]
    Json(String),
    /// A job's cron expression failed to parse.
    #[error("job {id:?}: invalid cron expression: {source}")]
    Cron {
        /// The offending job's id.
        id: String,
        /// The underlying parse failure.
        source: CronError,
    },
    /// A job named neither, or both, of `tool`/`prompt` — the action is ambiguous.
    #[error("job {id:?}: specify exactly one of `tool` or `prompt`")]
    Action {
        /// The offending job's id.
        id: String,
    },
    /// Two jobs shared an id; ids must be unique so chat can name one.
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
                summarize: spec.summarize.clone(),
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
    /// Whether the attempt succeeded.
    pub ok: bool,
    /// Output summary on success, error text on failure.
    pub detail: String,
    /// 1 for the first attempt of a chain, 2 for the first retry, …
    pub attempt: u32,
}

impl FireReport {
    /// The room line for the moment a job **accepts** work and the scheduler starts waiting.
    ///
    /// Posted once, on the first acceptance. Later polls that are still running return `None`
    /// from `fire`, so the room is not told "still waiting" every 30 s. `ok` is false because
    /// this is not a verdict — the ✅/❌ line is the later, terminal report.
    fn waiting(job: &ScheduleJob, acc: &lvz_protocol::Pending) -> Self {
        let eta = acc
            .estimated_seconds
            .map(|s| format!(", ~{s}s"))
            .unwrap_or_default();
        FireReport {
            job_id: job.id.clone(),
            room: job.room.clone(),
            ok: false,
            body: format!(
                "⏳ `{}` · started, waiting on `{}` (handle {}{eta})",
                job.id, acc.poll_with, acc.handle
            ),
            attempt: 0,
        }
    }
}

/// Work a tool accepted but has not finished, which the scheduler is polling to completion.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PendingWork {
    /// Opaque token from the dispatching tool, passed to `poll_with` as `{"handle": …}`.
    pub handle: String,
    /// The tool that reports the terminal outcome.
    pub poll_with: String,
    /// When to poll next (unix seconds).
    pub poll_at: u64,
    /// Give up and report a timeout after this instant. Derived from the tool's own estimate so a
    /// job that never completes is *reported*, rather than holding its slot forever.
    pub deadline: u64,
    /// How many polls have been made, for the operator log.
    pub polls: u32,
}

/// Live state for one job. Read by the `schedule_*` tools.
#[derive(Debug, Clone, Default)]
pub struct JobState {
    /// Next cron slot, or `None` while a retry chain is in flight (the retry supersedes it) or the
    /// schedule can never fire again.
    pub next_due: Option<u64>,
    /// When the in-flight retry should run.
    pub retry_at: Option<u64>,
    /// When to next poll an accepted-but-unfinished action, and what to poll.
    ///
    /// Set when a tool returned [`ToolOutput::pending`]. While this is `Some`, the job is **not**
    /// idle: the cron slot is suppressed exactly as a retry suppresses it, so the next tick cannot
    /// double-dispatch work that is still running.
    pub pending: Option<PendingWork>,
    /// Attempts used in the current chain (0 when idle).
    pub attempt: u32,
    /// Unix seconds of the most recent fire, or `None` if never fired.
    pub last_fired: Option<u64>,
    /// Outcome of the most recent fire, or `None` if never fired.
    pub last_ok: Option<bool>,
    /// Total attempts ever recorded, retries included.
    pub runs: u64,
    /// Total failed attempts ever recorded.
    pub failures: u64,
    /// Failures since the last success — the streak, reset to 0 on any success.
    pub consecutive_failures: u32,
    /// Recent outcomes, newest last, bounded by `HISTORY_CAP`.
    pub history: VecDeque<Outcome>,
}

/// What happened on one fire, for the caller to deliver. `body` is preformatted — every fire
/// reports, and failures are louder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireReport {
    /// Which job fired.
    pub job_id: String,
    /// The job's own room, if it set one; otherwise the caller's default.
    pub room: Option<String>,
    /// Whether this attempt succeeded.
    pub ok: bool,
    /// The preformatted report text ready to post.
    pub body: String,
    /// Which attempt in the current chain this was (1 = first try).
    pub attempt: u32,
}

/// One action's raw result, before it is summarised for a room.
///
/// Carries the **untruncated** output and (for a prompt job) the turn's token usage, so the
/// operator log can record what the chat summary necessarily drops.
struct ActionOutcome {
    /// Set when the tool accepted work that is still running, so the scheduler must poll for the
    /// terminal outcome before reporting anything.
    accepted: Option<lvz_protocol::Pending>,
    result: Result<String, String>,
    usage: Option<Usage>,
    /// Prose rendering of the tool action's outcome (success or failure), when the job set
    /// `summarize`. This is what the room sees; `result` (the raw output) still drives the verdict
    /// and the history trail.
    summary: Option<String>,
    /// Tools the agent called, for a prompt job.
    tools_used: Vec<String>,
}

/// The jobs, their live state, and the wait/fire loop. Shared as an `Arc` between the gateway
/// driving it and the `schedule_*` tools reporting on it.
pub struct ScheduleRegistry {
    /// Fallback polling budget for a tool that returned `pending` with no `estimated_seconds`.
    /// Set from `[gateway] schedule_pending_timeout`.
    pending_timeout: u64,
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
            pending_timeout: DEFAULT_PENDING_TIMEOUT,
            state: RwLock::new(state),
            requested: Mutex::new(VecDeque::new()),
            notify: Notify::new(),
        }
    }

    /// Override the fallback polling budget for tools that return `pending` without an estimate
    /// (`[gateway] schedule_pending_timeout`). A tool's own `estimated_seconds` still wins.
    pub fn with_pending_timeout(mut self, seconds: u64) -> Self {
        self.pending_timeout = seconds.max(MIN_PENDING_BUDGET);
        self
    }

    /// The jobs, in registration order (the index the `schedule_*` tools address).
    pub fn jobs(&self) -> &[ScheduleJob] {
        &self.jobs
    }

    /// True when no jobs are registered.
    pub fn is_empty(&self) -> bool {
        self.jobs.is_empty()
    }

    /// How many jobs are registered.
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

    /// The effective next fire time for a job, in precedence order: an in-flight **pending poll**
    /// beats a retry, which beats the cron slot.
    ///
    /// Polling rides this existing timer rather than awaiting inline, and that is the load-bearing
    /// choice: schedule jobs share a task with the Matrix `/sync` loop (the crypto state is not
    /// `Send`), so blocking `fire` for the ~minutes a wake takes would make the bot deaf for the
    /// duration. As a timer it costs nothing — `wait_due` already sleeps until the soonest.
    fn due_at(&self, job: &ScheduleJob) -> Option<u64> {
        let state = self.state.read().ok()?;
        let s = state.get(&job.id)?;
        s.pending
            .as_ref()
            .map(|p| p.poll_at)
            .or(s.retry_at)
            .or(s.next_due)
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
    ///
    /// Also writes the **verbose** account of the fire to stderr — full untruncated output,
    /// duration, and token usage. The room only ever sees a summary, so the operator log is the
    /// one place the whole picture exists.
    pub async fn fire(
        &self,
        idx: usize,
        tools: &ToolRegistry,
        agent: &Arc<dyn AgentHandle>,
    ) -> Option<FireReport> {
        let job = self.jobs.get(idx)?.clone();
        let started = std::time::Instant::now();

        // If work from an earlier fire is still running, this tick polls it rather than
        // dispatching again — that is what stops a cron slot double-firing a wake in progress.
        let in_flight = self.take_pending(&job.id);
        let first_accept = in_flight.is_none();
        let outcome = match in_flight.clone() {
            Some(p) => poll_pending(&job, p, tools, agent, self.pending_timeout).await,
            None => run_action(&job, tools, agent).await,
        };
        let elapsed = started.elapsed();

        // Still unfinished. The first acceptance is posted (`⏳ started, waiting`); a later poll
        // that is still running is not, so the room gets two messages for the job — waiting, then
        // the verdict — and not one per 30 s poll. The waiting line is not a success: `record` is
        // not called, so history and the retry counter stay untouched until the outcome is real.
        if let Some(acc) = &outcome.accepted {
            if let Some(prior) = in_flight {
                // `take_pending` removed the record so this tick could poll. Put it back before
                // re-arming, or the deadline (fixed at first acceptance) and the poll count reset.
                self.restore_pending(&job.id, prior);
            }
            self.arm_pending(&job, acc);
            let report = FireReport::waiting(&job, acc);
            log_verbose(&job, &outcome, &report, elapsed);
            return first_accept.then_some(report);
        }

        let report = self.record(&job, &outcome.result, outcome.summary.as_deref());
        log_verbose(&job, &outcome, &report, elapsed);
        Some(report)
    }

    /// Take any in-flight pending work off the job, so this tick polls it instead of dispatching.
    fn take_pending(&self, id: &str) -> Option<PendingWork> {
        let mut guard = self.state.write().ok()?;
        guard.get_mut(id).and_then(|s| s.pending.take())
    }

    /// Put a record removed by [`take_pending`](Self::take_pending) back, so a still-running poll
    /// re-arms against the original deadline instead of starting a new one.
    fn restore_pending(&self, id: &str, prior: PendingWork) {
        let Ok(mut guard) = self.state.write() else {
            return;
        };
        guard.entry(id.to_string()).or_default().pending = Some(prior);
    }

    /// Record accepted-but-unfinished work and arm the next poll.
    ///
    /// The cron slot and any retry timer are cleared for the duration, mirroring how a retry chain
    /// suppresses the slot: while work is in flight the job is not idle, and the next tick must not
    /// dispatch a second copy of it.
    fn arm_pending(&self, job: &ScheduleJob, acc: &lvz_protocol::Pending) {
        let now = now_unix();
        let Ok(mut guard) = self.state.write() else {
            return;
        };
        let s = guard.entry(job.id.clone()).or_default();
        let prior = s.pending.as_ref();
        // Deadline is set once, on the first acceptance, so repeated polls cannot extend it.
        let deadline = prior.map(|p| p.deadline).unwrap_or_else(|| {
            let budget = acc.estimated_seconds.unwrap_or(self.pending_timeout);
            // 2x the tool's own estimate: generous enough that a merely slow run is not cut off,
            // bounded enough that a hung one is reported.
            now + budget.saturating_mul(2).max(MIN_PENDING_BUDGET)
        });
        let polls = prior.map(|p| p.polls + 1).unwrap_or(0);
        s.pending = Some(PendingWork {
            handle: acc.handle.clone(),
            poll_with: acc.poll_with.clone(),
            poll_at: now + POLL_INTERVAL,
            deadline,
            polls,
        });
        s.retry_at = None;
        s.next_due = None;
    }

    /// Fold one attempt's result into the job's state and build its report.
    ///
    /// `summary` is the prose rendering of the tool action's outcome — success or failure — present
    /// only when the job set `summarize` and the render succeeded. The raw `result` still drives the
    /// verdict, the stored `Outcome.detail`, and the history trail — only the posted body prefers the
    /// prose.
    fn record(
        &self,
        job: &ScheduleJob,
        result: &Result<String, String>,
        summary: Option<&str>,
    ) -> FireReport {
        let now = now_unix();
        let ok = result.is_ok();
        let detail = truncate(
            match result {
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

        // Prose when we have it, raw output otherwise. A failure summary (when the render succeeds)
        // now lands in the detail slot too; `report_body` composes the ❌ marker and the retry
        // countdown *around* it, so the failure structure survives the paraphrase, and a failed
        // render still degrades to the raw error here.
        let shown = summary
            .map(|s| truncate(s, DETAIL_CAP))
            .unwrap_or_else(|| detail.clone());

        FireReport {
            job_id: job.id.clone(),
            room: job.room.clone(),
            ok,
            body: report_body(job, ok, &shown, attempt, retry_in, gave_up),
            attempt,
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
/// Poll accepted-but-unfinished work for its terminal outcome.
///
/// Three outcomes: still running (re-arm), finished (report it), or past the deadline (report a
/// timeout). A timeout is a **failure**, so it retries like any other — the request asked for a
/// failure at second 200 to behave like any other failure.
async fn poll_pending(
    job: &ScheduleJob,
    p: PendingWork,
    tools: &ToolRegistry,
    agent: &Arc<dyn AgentHandle>,
    _pending_timeout: u64,
) -> ActionOutcome {
    let now = now_unix();
    if now >= p.deadline {
        let waited = p.deadline.saturating_sub(now.min(p.deadline));
        let _ = waited;
        return finish(
            job,
            agent,
            Err(format!(
                "tool `{}` accepted work (handle {}) that did not complete before its deadline \
                 after {} poll(s) — reporting a timeout rather than holding the slot",
                p.poll_with, p.handle, p.polls
            )),
            vec![p.poll_with.clone()],
            None,
        )
        .await;
    }

    let args = serde_json::json!({ "handle": p.handle });
    match tools.invoke(&p.poll_with, args).await {
        Err(e) => {
            // The poll tool itself is broken. Terminal: retrying the poll forever would hide it.
            finish(
                job,
                agent,
                Err(format!("poll tool `{}` failed: {e}", p.poll_with)),
                vec![p.poll_with.clone()],
                None,
            )
            .await
        }
        Ok(out) if out.pending.is_some() => {
            // Still running. Re-arm from the fresh handle the poll returned.
            ActionOutcome {
                result: Ok(out.content),
                usage: None,
                summary: None,
                tools_used: vec![p.poll_with.clone()],
                accepted: out.pending,
            }
        }
        Ok(out) if out.is_error => {
            let e = format!("tool `{}` reported: {}", p.poll_with, out.content);
            finish(job, agent, Err(e), vec![p.poll_with.clone()], None).await
        }
        Ok(out) => finish(job, agent, Ok(out.content), vec![p.poll_with.clone()], None).await,
    }
}

/// Render the terminal outcome of an action, applying `summarize` exactly as a direct call would.
///
/// Shared by the direct path and the polled path so a pending job's report is indistinguishable
/// from an immediate one — same SUCCESS/FAILURE labelling, same degrade-to-raw on a failed render.
async fn finish(
    job: &ScheduleJob,
    agent: &Arc<dyn AgentHandle>,
    result: Result<String, String>,
    tools_used: Vec<String>,
    usage: Option<lvz_protocol::Usage>,
) -> ActionOutcome {
    let (summary, sum_usage) = match (&result, job.summarize.as_deref()) {
        (Ok(raw), Some(instruction)) => {
            summarise(job, agent, instruction, &format!("SUCCESS\n{raw}")).await
        }
        (Err(err), Some(instruction)) => {
            summarise(job, agent, instruction, &format!("FAILURE\n{err}")).await
        }
        _ => (None, None),
    };
    ActionOutcome {
        result,
        usage: usage.or(sum_usage),
        summary,
        tools_used,
        accepted: None,
    }
}

async fn run_action(
    job: &ScheduleJob,
    tools: &ToolRegistry,
    agent: &Arc<dyn AgentHandle>,
) -> ActionOutcome {
    match &job.action {
        Action::Tool { name, args } => {
            let mut accepted = None;
            let result = match tools.invoke(name, args.clone()).await {
                Err(e) => Err(format!("tool `{name}` failed: {e}")),
                Ok(out) if out.is_error => Err(format!("tool `{name}` reported: {}", out.content)),
                Ok(out) => {
                    // A pending result is NOT a success. `Ok` here would mean "dispatched", and a
                    // job whose whole purpose is "the machine is up before the service starts"
                    // must not assert that from an acceptance.
                    accepted = out.pending.clone();
                    Ok(out.content)
                }
            };
            // Summarise either outcome, labelling which it is (a leading SUCCESS/FAILURE line) so the
            // model renders a failure in the register of a failure — the owner's 2026-08-10 amendment;
            // successes-only originally. The tool call itself never reaches a provider (nothing to
            // bill); the summary turn does, so its usage flows in here. A summary render that fails
            // degrades to the raw output (see `record`/`summarise`), and the ❌ marker + retry
            // countdown stay structural in `report_body`, outside the prose slot — so a paraphrase can
            // never hide or soften a genuinely refused ATX power call.
            // An acceptance is not an outcome: skip the summary turn until the poll is terminal.
            let (summary, usage) = if accepted.is_some() {
                (None, None)
            } else {
                match (&result, job.summarize.as_deref()) {
                    (Ok(raw), Some(instruction)) => {
                        summarise(job, agent, instruction, &format!("SUCCESS\n{raw}")).await
                    }
                    (Err(err), Some(instruction)) => {
                        summarise(job, agent, instruction, &format!("FAILURE\n{err}")).await
                    }
                    _ => (None, None),
                }
            };
            ActionOutcome {
                result,
                usage,
                summary,
                tools_used: vec![name.clone()],
                accepted,
            }
        }
        Action::Prompt { text } => {
            let turn = TurnRequest::new(job.session.clone(), text.clone());
            let mut stream = match agent.submit(turn).await {
                Ok(s) => s,
                Err(e) => {
                    return ActionOutcome {
                        result: Err(format!("submit failed: {e}")),
                        usage: None,
                        summary: None,
                        tools_used: Vec::new(),
                        // A prompt turn has no dispatch/poll split; it runs to completion here.
                        accepted: None,
                    };
                }
            };
            let mut answer = String::new();
            let mut used: Vec<String> = Vec::new();
            let mut usage = None;
            let mut failed = None;
            while let Some(item) = stream.next().await {
                match item {
                    Ok(Event::TextDelta(t)) => answer.push_str(&t),
                    Ok(Event::ToolUseStart { name, .. }) => used.push(name),
                    Ok(Event::Usage(u)) => usage = Some(u),
                    Ok(_) => {}
                    Err(e) => {
                        failed = Some(format!("stream error: {e}"));
                        break;
                    }
                }
            }
            let tools_note = if used.is_empty() {
                String::new()
            } else {
                format!(" [tools: {}]", used.join(", "))
            };
            ActionOutcome {
                // Usage is kept even on a mid-turn failure — a turn that died still cost tokens,
                // and the operator log is where that has to be visible.
                result: match failed {
                    Some(e) => Err(e),
                    None => Ok(format!("{}{tools_note}", answer.trim())),
                },
                usage,
                // A prompt turn is already prose; there is nothing to re-render.
                summary: None,
                tools_used: used,
                accepted: None,
            }
        }
    }
}

/// Render a tool's raw output as prose for the room.
///
/// Tool-less **by construction**: the turn is submitted with an EMPTY allowlist, so the model can
/// only write text — it cannot act. That is what makes this safe where [`Action::Prompt`] is not (a
/// prompt job carries no room/sender identity, so `matrix_room_tools` cannot scope it). Any failure
/// returns `None` so the caller degrades to the raw JSON; a provider outage must never swallow a
/// scheduled report.
async fn summarise(
    job: &ScheduleJob,
    agent: &Arc<dyn AgentHandle>,
    instruction: &str,
    raw: &str,
) -> (Option<String>, Option<Usage>) {
    let turn = TurnRequest::new(job.session.clone(), format!("{instruction}\n\n{raw}"))
        .with_allowed_tools(Vec::new());
    let mut stream = match agent.submit(turn).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!(job = %job.id, error = %e, "summary submit failed; posting raw output");
            return (None, None);
        }
    };
    let (mut text, mut usage) = (String::new(), None);
    while let Some(item) = stream.next().await {
        match item {
            Ok(Event::TextDelta(t)) => text.push_str(&t),
            Ok(Event::Usage(u)) => usage = Some(u),
            Ok(_) => {}
            Err(e) => {
                tracing::warn!(job = %job.id, error = %e, "summary stream error; posting raw output");
                return (None, usage);
            }
        }
    }
    let text = text.trim().to_string();
    ((!text.is_empty()).then_some(text), usage)
}

/// Emit the full account of one fire as a single `tracing` event.
///
/// The Matrix report is deliberately short — a room is a bad log — so this is the only place the
/// untruncated output, the timing, and the token cost all land. Kept in this crate (rather than the
/// gateway) so every frontend gets the same operator log for free.
///
/// One event per fire, at `info!` on success and `error!` on failure, so both are visible under the
/// CLI's default filter. The untruncated body rides along as the `output`/`error` field rather than
/// as extra lines.
fn log_verbose(
    job: &ScheduleJob,
    outcome: &ActionOutcome,
    report: &FireReport,
    elapsed: std::time::Duration,
) {
    let ms = elapsed.as_millis();
    let tools_note = if outcome.tools_used.is_empty() {
        String::new()
    } else {
        format!(" tools=[{}]", outcome.tools_used.join(", "))
    };
    let usage_note = outcome
        .usage
        .as_ref()
        .map(|u| {
            format!(
                " usage=[in {} / out {} / cache_read {}]",
                u.input_tokens, u.output_tokens, u.cache_read_tokens
            )
        })
        .unwrap_or_default();

    if outcome.accepted.is_some() {
        tracing::info!(
            job = %job.id,
            duration_ms = ms,
            "job accepted, waiting{tools_note}"
        );
        return;
    }
    match &outcome.result {
        Ok(output) => {
            let output = output.trim();
            tracing::info!(
                job = %job.id,
                attempt = report.attempt,
                duration_ms = ms,
                bytes = output.len(),
                output = %output,
                summary = outcome.summary.as_deref().unwrap_or("-"),
                "job fired ok{tools_note}{usage_note}",
            );
        }
        Err(error) => {
            tracing::error!(
                job = %job.id,
                attempt = report.attempt,
                max_attempts = job.retry_max + 1,
                duration_ms = ms,
                error = %error.trim(),
                summary = outcome.summary.as_deref().unwrap_or("-"),
                "job FAILED{tools_note}{usage_note}",
            );
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
            summarize: None,
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
        let report = reg.record(&reg.jobs[0].clone(), &Ok("all good".into()), None);
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
        let report = reg.record(&reg.jobs[0].clone(), &Err("boom".into()), None);
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
        let r1 = reg.record(&j, &Err("boom".into()), None);
        assert!(r1.body.contains("↻ retry 1/2 in 30s"));
        let s = reg.state_of("a").unwrap();
        assert!(s.retry_at.is_some());
        assert!(s.next_due.is_none());
        assert_eq!(s.attempt, 1);

        // Attempt 2 fails → retry 2/2 queued.
        let r2 = reg.record(&j, &Err("boom".into()), None);
        assert!(r2.body.contains("↻ retry 2/2 in 30s"));
        assert_eq!(reg.state_of("a").unwrap().attempt, 2);

        // Attempt 3 exhausts the budget → give up and re-arm the cron slot from now.
        let r3 = reg.record(&j, &Err("boom".into()), None);
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
        reg.record(&j, &Err("boom".into()), None);
        let ok = reg.record(&j, &Ok("recovered".into()), None);
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
            reg.record(&j, &Ok("x".into()), None);
        }
        assert_eq!(reg.state_of("a").unwrap().history.len(), HISTORY_CAP);
    }

    #[test]
    fn report_carries_the_jobs_own_room() {
        let mut j = tool_job("a");
        j.room = Some("!ops:hs".into());
        let reg = ScheduleRegistry::new(vec![j]);
        let report = reg.record(&reg.jobs[0].clone(), &Ok("x".into()), None);
        assert_eq!(report.room.as_deref(), Some("!ops:hs"));
    }

    #[test]
    fn long_output_is_truncated() {
        let reg = ScheduleRegistry::new(vec![tool_job("a")]);
        let report = reg.record(&reg.jobs[0].clone(), &Ok("x".repeat(5_000)), None);
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

    /// A tool that always succeeds with a fixed JSON payload — the `bcast-*` shape.
    struct JsonTool;
    #[async_trait::async_trait]
    impl lvz_protocol::Tool for JsonTool {
        fn name(&self) -> &str {
            "server_wake"
        }
        fn schema(&self) -> serde_json::Value {
            serde_json::json!({"type": "object"})
        }
        async fn invoke(
            &self,
            _args: serde_json::Value,
        ) -> Result<lvz_protocol::ToolOutput, lvz_protocol::ToolError> {
            Ok(lvz_protocol::ToolOutput::ok(
                serde_json::json!({"status": "wake started", "success": true}).to_string(),
            ))
        }
    }

    /// An agent that streams a scripted answer and records the turn it was handed, so a test can
    /// assert what the summary turn actually submitted.
    struct StubAgent {
        answer: String,
        seen: Arc<Mutex<Option<TurnRequest>>>,
    }
    #[async_trait::async_trait]
    impl AgentHandle for StubAgent {
        async fn submit(
            &self,
            turn: TurnRequest,
        ) -> Result<
            futures::stream::BoxStream<'static, Result<Event, lvz_protocol::AgentError>>,
            lvz_protocol::AgentError,
        > {
            *self.seen.lock().unwrap() = Some(turn);
            let answer = self.answer.clone();
            Ok(futures::stream::iter(vec![Ok(Event::TextDelta(answer))]).boxed())
        }
    }

    fn summarising_job(id: &str) -> ScheduleJob {
        let mut j = job(
            id,
            Action::Tool {
                name: "server_wake".into(),
                args: serde_json::json!({}),
            },
        );
        j.summarize = Some("Say what happened in one plain sentence.".into());
        j.session = "!room:hs".into();
        j
    }

    #[tokio::test]
    async fn summarize_renders_prose_and_keeps_raw_output_in_history() {
        let mut tools = ToolRegistry::new();
        tools.register(Arc::new(JsonTool));
        let seen = Arc::new(Mutex::new(None));
        let agent: Arc<dyn AgentHandle> = Arc::new(StubAgent {
            answer: "The machine woke up and is logging in.".into(),
            seen: seen.clone(),
        });

        let reg = ScheduleRegistry::new(vec![summarising_job("w")]);
        let report = reg.fire(0, &tools, &agent).await.unwrap();

        // The room sees the prose, not the raw JSON.
        assert!(report.ok);
        assert!(report.body.contains("The machine woke up"));
        assert!(!report.body.contains("\"success\""));

        // The verdict stays the tool's, and the raw JSON is still stored for debugging.
        let state = reg.state_of("w").unwrap();
        let detail = &state.history.back().unwrap().detail;
        assert!(detail.contains("\"success\""));

        // Tool-less by construction: the summary turn carried an EMPTY allowlist and the raw output.
        let turn = seen.lock().unwrap().clone().unwrap();
        assert_eq!(turn.allowed_tools, Some(Vec::new()));
        assert_eq!(turn.session, "!room:hs");
        assert!(turn.input.contains("\"success\""));
    }

    #[tokio::test]
    async fn summarize_failure_degrades_to_raw_output() {
        // The summary turn's provider is down; the scheduled report must still go out with the raw
        // JSON rather than being swallowed.
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
                Err(lvz_protocol::AgentError::Provider("down".into()))
            }
        }
        let mut tools = ToolRegistry::new();
        tools.register(Arc::new(JsonTool));
        let agent: Arc<dyn AgentHandle> = Arc::new(DeadAgent);
        let reg = ScheduleRegistry::new(vec![summarising_job("w")]);
        let report = reg.fire(0, &tools, &agent).await.unwrap();
        assert!(report.ok);
        assert!(report.body.contains("\"success\""));
    }

    #[tokio::test]
    async fn a_failing_tool_is_summarised_without_losing_the_failure_structure() {
        // The owner's 2026-08-10 amendment: failures are summarised too. The prose replaces the raw
        // error in the detail slot, but the verdict stays the tool's and the ❌ marker + attempt
        // counter + retry countdown stay structural. The payload the model sees is labelled FAILURE
        // and carries the raw error, and the raw error is still stored for the operator trail.
        struct FailTool;
        #[async_trait::async_trait]
        impl lvz_protocol::Tool for FailTool {
            fn name(&self) -> &str {
                "server_wake"
            }
            fn schema(&self) -> serde_json::Value {
                serde_json::json!({"type": "object"})
            }
            async fn invoke(
                &self,
                _args: serde_json::Value,
            ) -> Result<lvz_protocol::ToolOutput, lvz_protocol::ToolError> {
                Ok(lvz_protocol::ToolOutput::error("ATX call refused"))
            }
        }

        let mut tools = ToolRegistry::new();
        tools.register(Arc::new(FailTool));
        let seen = Arc::new(Mutex::new(None));
        let agent: Arc<dyn AgentHandle> = Arc::new(StubAgent {
            answer: "The wake FAILED: the power call was refused.".into(),
            seen: seen.clone(),
        });

        // retry_max > 0 so the countdown line is present to assert it survives the paraphrase.
        let mut j = summarising_job("w");
        j.retry_max = 3;
        j.retry_wait = 60;
        let reg = ScheduleRegistry::new(vec![j]);
        let report = reg.fire(0, &tools, &agent).await.unwrap();

        // Verdict stays the tool's; the failure structure is intact.
        assert!(!report.ok);
        assert!(report.body.contains("❌"));
        assert!(report.body.contains("attempt 1"));
        assert!(report.body.contains("↻ retry 1/3 in 60s"));

        // The room sees the prose in the detail slot, not the raw error.
        assert!(report.body.contains("The wake FAILED"));
        assert!(!report.body.contains("ATX call refused"));

        // The raw error is still stored for debugging.
        let state = reg.state_of("w").unwrap();
        assert!(state
            .history
            .back()
            .unwrap()
            .detail
            .contains("ATX call refused"));

        // The summary turn was consulted, tool-less, with a FAILURE-labelled payload carrying the error.
        let turn = seen.lock().unwrap().clone().unwrap();
        assert_eq!(turn.allowed_tools, Some(Vec::new()));
        assert!(turn.input.contains("FAILURE"));
        assert!(turn.input.contains("ATX call refused"));
    }
}

#[cfg(test)]
mod pending_tests {
    use super::*;

    /// A job on a DAILY cron, so the pending poll is demonstrably sooner than the next slot.
    fn job(id: &str) -> ScheduleJob {
        ScheduleJob {
            id: id.into(),
            expr: "0 9 * * *".into(),
            schedule: CronSchedule::parse("0 9 * * *").unwrap(),
            action: Action::Tool {
                name: "server_wake".into(),
                args: serde_json::json!({}),
            },
            room: Some("!ops:hs".into()),
            session: id.into(),
            summarize: None,
            retry_max: 2,
            retry_wait: 60,
        }
    }

    fn accepted() -> lvz_protocol::Pending {
        lvz_protocol::Pending {
            handle: "d63b23".into(),
            poll_with: "server_wake_result".into(),
            estimated_seconds: Some(218),
        }
    }

    /// The core guard: while work is in flight the cron slot and any retry are suppressed, so the
    /// next tick polls rather than dispatching a second wake.
    #[test]
    fn pending_work_suppresses_the_cron_slot_and_any_retry() {
        let reg = ScheduleRegistry::new(vec![job("wake")]);
        let j = reg.jobs()[0].clone();
        reg.arm_pending(&j, &accepted());

        let s = reg.state_of("wake").unwrap();
        assert!(s.pending.is_some(), "pending must be recorded");
        assert!(s.next_due.is_none(), "the cron slot must be suppressed");
        assert!(
            s.retry_at.is_none(),
            "a retry must not race the in-flight work"
        );
    }

    /// A pending poll outranks a retry, which outranks the cron slot.
    #[test]
    fn the_poll_is_the_highest_precedence_timer() {
        let reg = ScheduleRegistry::new(vec![job("wake")]);
        let j = reg.jobs()[0].clone();
        let cron_only = reg
            .due_at(&j)
            .expect("a fresh job is armed on its cron slot");

        reg.arm_pending(&j, &accepted());
        let while_pending = reg.due_at(&j).expect("pending work is due for a poll");
        assert!(
            while_pending < cron_only,
            "the poll ({while_pending}) must come before the cron slot ({cron_only})"
        );
    }

    /// The deadline is fixed at first acceptance. Re-arming on each poll must not extend it, or a
    /// tool that keeps saying "still working" would hold its slot forever — the exact failure the
    /// bound exists to prevent.
    #[test]
    fn repeated_polls_do_not_extend_the_deadline() {
        let reg = ScheduleRegistry::new(vec![job("wake")]);
        let j = reg.jobs()[0].clone();
        reg.arm_pending(&j, &accepted());
        let first = reg.state_of("wake").unwrap().pending.unwrap();

        reg.arm_pending(&j, &accepted());
        let second = reg.state_of("wake").unwrap().pending.unwrap();

        assert_eq!(first.deadline, second.deadline, "deadline must be set once");
        assert_eq!(second.polls, first.polls + 1, "poll count advances");
    }

    /// Taking the pending work clears it, so a tick polls at most once.
    #[test]
    fn take_pending_is_a_one_shot() {
        let reg = ScheduleRegistry::new(vec![job("wake")]);
        let j = reg.jobs()[0].clone();
        reg.arm_pending(&j, &accepted());
        assert!(reg.take_pending("wake").is_some());
        assert!(reg.take_pending("wake").is_none());
    }

    /// Polling is a flat 30s cadence; the DEADLINE bounds the total, not the interval.
    #[test]
    fn polling_is_a_flat_cadence() {
        let reg = ScheduleRegistry::new(vec![job("wake")]);
        let j = reg.jobs()[0].clone();
        let before = now_unix();
        reg.arm_pending(&j, &accepted());
        let p = reg.state_of("wake").unwrap().pending.unwrap();
        assert!(
            p.poll_at >= before + POLL_INTERVAL && p.poll_at <= before + POLL_INTERVAL + 2,
            "first poll is one interval out, not paced by the 218s estimate"
        );

        // A later poll uses the same interval — no backoff to reason about.
        let mid = now_unix();
        reg.arm_pending(&j, &accepted());
        let q = reg.state_of("wake").unwrap().pending.unwrap();
        assert!(q.poll_at >= mid + POLL_INTERVAL && q.poll_at <= mid + POLL_INTERVAL + 2);
    }

    /// A tool with no estimate falls back to the configured budget, floored.
    #[test]
    fn the_configured_timeout_backs_an_estimate_less_tool() {
        let reg = ScheduleRegistry::new(vec![job("wake")]).with_pending_timeout(100);
        let j = reg.jobs()[0].clone();
        let mut acc = accepted();
        acc.estimated_seconds = None;
        reg.arm_pending(&j, &acc);
        let p = reg.state_of("wake").unwrap().pending.unwrap();
        assert!(p.deadline >= now_unix() + 200, "2x the configured budget");

        // And the floor applies to the setting itself.
        let floored = ScheduleRegistry::new(vec![job("w2")]).with_pending_timeout(1);
        assert_eq!(floored.pending_timeout, MIN_PENDING_BUDGET);
    }

    /// The room hears the wait once, then the verdict. A poll that is still running posts nothing
    /// and does not count as an attempt.
    #[tokio::test]
    async fn a_pending_job_reports_waiting_once_then_the_verdict() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        struct Wake;
        #[async_trait::async_trait]
        impl lvz_protocol::Tool for Wake {
            fn name(&self) -> &str {
                "server_wake"
            }
            fn schema(&self) -> serde_json::Value {
                serde_json::json!({"type": "object"})
            }
            async fn invoke(
                &self,
                _args: serde_json::Value,
            ) -> Result<lvz_protocol::ToolOutput, lvz_protocol::ToolError> {
                Ok(lvz_protocol::ToolOutput::pending(
                    "powered on",
                    "h1",
                    "server_wake_result",
                    Some(218),
                ))
            }
        }
        struct WakeResult {
            polls: Arc<AtomicUsize>,
        }
        #[async_trait::async_trait]
        impl lvz_protocol::Tool for WakeResult {
            fn name(&self) -> &str {
                "server_wake_result"
            }
            fn schema(&self) -> serde_json::Value {
                serde_json::json!({"type": "object"})
            }
            async fn invoke(
                &self,
                _args: serde_json::Value,
            ) -> Result<lvz_protocol::ToolOutput, lvz_protocol::ToolError> {
                // The first poll is still running; the second is the terminal success.
                if self.polls.fetch_add(1, Ordering::SeqCst) == 0 {
                    Ok(lvz_protocol::ToolOutput::pending(
                        "still logging in",
                        "h1",
                        "server_wake_result",
                        Some(218),
                    ))
                } else {
                    Ok(lvz_protocol::ToolOutput::ok("desktop up"))
                }
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

        let polls = Arc::new(AtomicUsize::new(0));
        let mut tools = ToolRegistry::new();
        tools.register(Arc::new(Wake));
        tools.register(Arc::new(WakeResult { polls }));
        let agent: Arc<dyn AgentHandle> = Arc::new(DeadAgent);
        let reg = ScheduleRegistry::new(vec![job("wake")]);

        let waiting = reg
            .fire(0, &tools, &agent)
            .await
            .expect("first accept posts");
        assert!(!waiting.ok, "waiting is not a success");
        assert!(waiting.body.contains("⏳"));
        assert!(waiting.body.contains("started, waiting"));
        assert!(waiting.body.contains("server_wake_result"));
        assert!(waiting.body.contains("h1"));
        assert!(waiting.body.contains("~218s"));
        let after_accept = reg.state_of("wake").unwrap();
        assert!(after_accept.history.is_empty(), "waiting is not an attempt");
        assert_eq!(after_accept.runs, 0);
        let deadline = after_accept.pending.unwrap().deadline;

        assert!(
            reg.fire(0, &tools, &agent).await.is_none(),
            "a poll that is still running posts nothing"
        );
        let after_poll = reg.state_of("wake").unwrap();
        assert!(after_poll.history.is_empty());
        assert_eq!(after_poll.pending.unwrap().deadline, deadline);

        let done = reg.fire(0, &tools, &agent).await.expect("terminal posts");
        assert!(done.ok);
        assert!(done.body.contains("✅"));
        assert!(done.body.contains("desktop up"));
        assert!(reg.state_of("wake").unwrap().pending.is_none());
    }

    /// An ordinary tool is untouched: no pending field, no behaviour change.
    #[test]
    fn a_terminal_result_carries_no_pending_state() {
        let out = lvz_protocol::ToolOutput::ok("done");
        assert!(out.pending.is_none());
        let err = lvz_protocol::ToolOutput::error("nope");
        assert!(
            err.pending.is_none(),
            "an error is terminal by construction"
        );
    }
}
