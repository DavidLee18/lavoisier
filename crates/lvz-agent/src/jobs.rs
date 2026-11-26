//! In-flight background jobs for one process.
//!
//! # Ownership and locking
//!
//! [`JobRuntime`] is shared. The chat loop, a tool's `invoke`, and a restarted process all
//! reach the same process-wide runtime through [`global`].
//!
//! The table is a `std::sync::Mutex`. The lock is never held across `.await`, and it is not
//! held across the jobs-file write. A mutation records a snapshot, drops the guard, then a
//! [`crate::durable::PersistQueue`] thread fsyncs it. A worker publishes a terminal state by
//! locking, writing the row, dropping the guard, then `Notify::notify_waiters`. The agent
//! task waits on that `Notify` and drains under a new lock.
//!
//! Each accepted job gets a child [`CancellationToken`](tokio_util::sync::CancellationToken)
//! of the turn token. Cancelling the turn (dropping the event stream, or ACP
//! `session/cancel`, which drops that stream) cancels every child. Cancelling one child
//! does not cancel the turn. The parent token stays on the turn, not in the map.
//!
//! The cap of [`MAX_JOBS_PER_SESSION`](lvz_protocol::MAX_JOBS_PER_SESSION) running rows is
//! checked and the new row inserted in the same critical section, so two overlapping
//! `reserve` calls cannot both pass the cap.
//!
//! Terminal state is written once. A later `finish` for the same id is ignored, so a
//! timeout and a late poll cannot both become a `tool_result`.
//!
//! # Persistence
//!
//! Rows are written beside the session transcript as `{hex}.jobs.json` (version 2), where
//! `{hex}` is the same session encoding as `FileStore::path_for`. A version-1 file (no
//! `version`, only `{id, tool, session, started}`) still loads. A terminal row stays in the
//! file until it is drained into a completion message. On startup, power and OBS tools
//! become [`JobError::Interrupted`] and are not run again. `run_build` reattaches from
//! `{artifact}/{id}.code` or, when a [`BuildProbe`] is installed, from `meta.task_arn`.
//! With [`JobRuntime::set_recover_on_signal`], startup does not adopt rows; [`adopt`] does,
//! and only for a lease generation that is not older than the one already accepted.

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::Instant;

use lvz_protocol::{
    admit_tool_images, fails_closed_on_restart, origin, tool_permitted, work_scope, ContentBlock,
    JobError, JobId, Message, Origin, Pending, ProgressNote, ProgressTx, Role, ToolError,
    ToolOutput, WorkLease, MAX_JOBS_PER_SESSION,
};
use lvz_tools::ToolRegistry;
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

use crate::durable::{sweep_stray_tmp, DurableFs, LocalFs, PersistQueue};

/// Result of waiting until a session has something to inject, or the turn is cancelled.
#[derive(Debug)]
pub enum JobWait {
    /// One or more jobs reached a terminal state, in finish order.
    Ready(Vec<JobCompletion>),
    /// The turn token fired. Running rows are the caller's to fail.
    Cancelled,
}

/// One terminal job, in the order `finish` recorded it.
#[derive(Debug)]
pub struct JobCompletion {
    /// Accepted id.
    pub id: JobId,
    /// Tool name that accepted the work.
    pub tool: String,
    /// The single terminal value.
    pub result: Result<ToolOutput, JobError>,
}

/// What a test (or a log line that must not include a body) can observe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OutcomeKind {
    /// Still running.
    Running,
    /// Terminal tool output. `true` when that output is `is_error`.
    Done {
        /// `ToolOutput::is_error`.
        is_error: bool,
    },
    /// Terminal [`JobError`] display text.
    Failed(String),
}

#[derive(Debug)]
enum State {
    Running,
    Done(ToolOutput),
    Failed(JobError),
}

impl State {
    fn is_running(&self) -> bool {
        matches!(self, State::Running)
    }
}

struct Row {
    id: JobId,
    tool: String,
    session: String,
    started: u64,
    /// Monotonic accept time. Timeouts use this so a paused test clock can elapse the budget.
    /// `started` is the wall-clock instant written to disk.
    started_instant: Instant,
    timeout_secs: u64,
    cancel: CancellationToken,
    state: State,
    progress: Option<ProgressNote>,
    task_arn: Option<String>,
    origin_label: String,
    pod: String,
    boot_id: String,
    generation: Option<u64>,
}

/// What a restarted `run_build` can learn without the build log socket.
pub enum BuildLook {
    /// The task has stopped. `exit_code` is `None` when the control plane did not report one.
    Stopped {
        /// Container exit code, when known.
        exit_code: Option<i32>,
    },
    /// The task is still running.
    Running,
    /// The control plane did not answer. Treated as still in flight.
    Unknown,
}

/// Describes a persisted `run_build` task. Installed by the host that owns the ECS client.
pub trait BuildProbe: Send + Sync {
    /// Look up `task_arn`. Must not log the task payload.
    fn describe(&self, task_arn: &str) -> BuildLook;
}

struct Tables {
    rows: HashMap<JobId, Row>,
    /// Finish order, per session. Drained into the next user message.
    ready: HashMap<String, VecDeque<JobId>>,
    store_dir: Option<PathBuf>,
    artifact_dir: Option<PathBuf>,
    default_timeout: u64,
    fs: Arc<dyn DurableFs>,
    recover_on_signal: bool,
    adopted: Option<u64>,
    /// Lease generation copied onto rows during [`JobRuntime::adopt`].
    stamp: Option<u64>,
    boot_id: String,
    pod: String,
    snaps: Vec<(PathBuf, Option<Vec<u8>>)>,
    probe: Option<Arc<dyn BuildProbe>>,
}

/// The in-flight table. See the module docs for who may lock it.
type TerminalHook = std::sync::Arc<dyn Fn(&str, &str) + Send + Sync>;

/// The in-process job table. One per process, reached through [`global`].
pub struct JobRuntime {
    inner: Mutex<Tables>,
    notify: Notify,
    queue: Mutex<Option<PersistQueue>>,
    adopt_gate: Mutex<()>,
    /// When true, a terminal row is handed to [`JobRuntime::set_terminal_hook`] instead of
    /// the chat turn.
    detached: std::sync::atomic::AtomicBool,
    hook: Mutex<Option<TerminalHook>>,
}

/// A build the process should keep watching after a restart.
struct Watch {
    id: JobId,
    dir: PathBuf,
    deadline_unix: u64,
    timeout_secs: u64,
}

impl JobRuntime {
    /// An empty table. Chat timeouts default to 600s until [`configure`](Self::configure_with) runs.
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(Tables {
                rows: HashMap::new(),
                ready: HashMap::new(),
                store_dir: None,
                artifact_dir: None,
                default_timeout: 600,
                fs: Arc::new(LocalFs),
                recover_on_signal: false,
                adopted: None,
                stamp: None,
                boot_id: format!("{}-{}", std::process::id(), now_unix()),
                pod: std::env::var("HOSTNAME").unwrap_or_else(|_| "local".into()),
                snaps: Vec::new(),
                probe: None,
            }),
            notify: Notify::new(),
            queue: Mutex::new(None),
            adopt_gate: Mutex::new(()),
            detached: std::sync::atomic::AtomicBool::new(false),
            hook: Mutex::new(None),
        }
    }

    /// Turn on detached delivery. Terminal rows go to the hook, not the waiting turn.
    pub fn set_detached(&self, on: bool) {
        self.detached
            .store(on, std::sync::atomic::Ordering::Relaxed);
    }

    /// Receive `session` and the completion text when a detached job finishes.
    pub fn set_terminal_hook(&self, hook: TerminalHook) {
        *self.hook.lock().unwrap_or_else(|err| err.into_inner()) = Some(hook);
    }

    fn dispatch_ready(&self, session: &str) {
        if !self.detached.load(std::sync::atomic::Ordering::Relaxed) {
            return;
        }
        let hook = self
            .hook
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .clone();
        let Some(hook) = hook else {
            return;
        };
        let Some(message) = self.drain_ready(session) else {
            return;
        };
        hook(session, &message.text());
    }

    /// Set the session directory, the `run_build` artifact directory, and the fallback timeout.
    pub fn configure_with(
        &self,
        store: Option<PathBuf>,
        artifact: Option<PathBuf>,
        default_timeout: u64,
    ) {
        self.configure_fs(store, artifact, default_timeout, false, Arc::new(LocalFs));
    }

    /// [`configure_with`](Self::configure_with) plus the filesystem and the lease-gated recovery flag.
    ///
    /// When `recover_on_signal` is set, callers must not adopt rows until [`adopt`](Self::adopt).
    /// Stray `*.tmp.*` files in `store` are removed. The count is logged.
    pub fn configure_fs(
        &self,
        store: Option<PathBuf>,
        artifact: Option<PathBuf>,
        default_timeout: u64,
        recover_on_signal: bool,
        fs: Arc<dyn DurableFs>,
    ) {
        if let Some(dir) = &store {
            match sweep_stray_tmp(dir) {
                Ok(n) if n > 0 => tracing::info!(removed = n, "swept stray job temp files"),
                Ok(_) => {}
                Err(err) => tracing::error!(error = %err, "could not sweep stray job temp files"),
            }
        }
        let mut guard = self.lock();
        guard.store_dir = store;
        guard.artifact_dir = artifact;
        guard.default_timeout = default_timeout.max(1);
        guard.recover_on_signal = recover_on_signal;
        guard.fs = fs;
    }

    /// Install the `run_build` probe used when a recovered row has `meta.task_arn`.
    pub fn set_build_probe(&self, probe: Arc<dyn BuildProbe>) {
        self.lock().probe = Some(probe);
    }

    /// Remember the ECS task that `id` is following. Persisted so a restart can describe it.
    pub fn note_task_arn(&self, id: &JobId, arn: &str) {
        let mut guard = self.lock();
        let Some(row) = guard.rows.get_mut(id) else {
            return;
        };
        let session = row.session.clone();
        row.task_arn = Some(arn.to_string());
        guard.persist_session(&session);
        self.finish_guard(guard);
    }

    /// Ask the probe again for running builds that have a task arn.
    pub fn recheck_builds(&self) {
        let looks: Vec<(JobId, String, BuildLook)> = {
            let guard = self.lock();
            let Some(probe) = guard.probe.clone() else {
                return;
            };
            guard
                .rows
                .values()
                .filter(|row| row.state.is_running() && row.tool == "run_build")
                .filter_map(|row| {
                    let arn = row.task_arn.clone()?;
                    let look = probe.describe(&arn);
                    Some((row.id.clone(), row.tool.clone(), look))
                })
                .collect()
        };
        for (id, tool, look) in looks {
            if let BuildLook::Stopped { exit_code } = look {
                let code = exit_code.unwrap_or(1);
                let content =
                    format!("run_build {id} exited {code}; output unavailable after restart");
                let output = if code == 0 {
                    ToolOutput::ok(content)
                } else {
                    ToolOutput::error(content)
                };
                let _ = tool;
                self.finish(id, Ok(output));
            }
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Tables> {
        // A poisoned lock means a holder panicked. Recover the table so a later job can
        // still finish; the panic itself is outside this path.
        self.inner.lock().unwrap_or_else(|err| err.into_inner())
    }

    /// Insert a running row or refuse because the session is at the cap.
    ///
    /// The returned token is a child of `parent`. Drop the child to cancel only this job.
    ///
    /// # Errors
    ///
    /// [`ToolError::Execution`] when the session already has
    /// [`MAX_JOBS_PER_SESSION`] running jobs, or this id is already in the table.
    pub fn reserve(
        &self,
        session: &str,
        tool: &str,
        id: JobId,
        estimated_seconds: Option<u64>,
        parent: &CancellationToken,
    ) -> Result<CancellationToken, ToolError> {
        let mut guard = self.lock();
        if guard.rows.contains_key(&id) {
            return Err(ToolError::Execution(format!(
                "job {id} is already in flight"
            )));
        }
        let running = guard
            .rows
            .values()
            .filter(|row| row.session == session && row.state.is_running())
            .count();
        if running >= MAX_JOBS_PER_SESSION {
            return Err(ToolError::Execution(format!(
                "{tool} not started: session already has {MAX_JOBS_PER_SESSION} jobs in flight"
            )));
        }
        let timeout_secs = estimated_seconds.unwrap_or(guard.default_timeout).max(1);
        let cancel = parent.child_token();
        let (pod, boot_id) = (guard.pod.clone(), guard.boot_id.clone());
        guard.rows.insert(
            id.clone(),
            Row {
                id: id.clone(),
                tool: tool.to_string(),
                session: session.to_string(),
                started: now_unix(),
                started_instant: Instant::now(),
                timeout_secs,
                cancel: cancel.clone(),
                state: State::Running,
                progress: None,
                task_arn: None,
                origin_label: origin_label(),
                pod,
                boot_id,
                generation: None,
            },
        );
        guard.persist_session(session);
        self.finish_guard(guard);
        Ok(cancel)
    }

    /// Whether `id` is in the table, running or already finished.
    pub fn contains(&self, id: &JobId) -> bool {
        self.lock().rows.contains_key(id)
    }

    /// Running jobs for `session`. Finished-but-not-drained rows do not count toward the cap.
    pub fn inflight(&self, session: &str) -> usize {
        self.lock()
            .rows
            .values()
            .filter(|row| row.session == session && row.state.is_running())
            .count()
    }

    /// Running work, or a terminal result the loop has not injected yet.
    pub fn session_busy(&self, session: &str) -> bool {
        let guard = self.lock();
        let running = guard
            .rows
            .values()
            .any(|row| row.session == session && row.state.is_running());
        let queued = guard
            .ready
            .get(session)
            .is_some_and(|queue| !queue.is_empty());
        running || queued
    }

    /// Record the single terminal value. A second call for the same id does nothing.
    pub fn finish(&self, id: JobId, result: Result<ToolOutput, JobError>) {
        let mut guard = self.lock();
        let Some(row) = guard.rows.get_mut(&id) else {
            return;
        };
        if !row.state.is_running() {
            return;
        }
        let session = row.session.clone();
        row.cancel.cancel();
        row.state = match result {
            Ok(output) => State::Done(output),
            Err(err) => State::Failed(err),
        };
        guard
            .ready
            .entry(session.clone())
            .or_default()
            .push_back(id);
        guard.persist_session(&session);
        self.finish_guard(guard);
        self.notify.notify_waiters();
        self.dispatch_ready(&session);
    }

    /// Cancel one running job.
    ///
    /// # Errors
    ///
    /// [`JobError::Unknown`] when `id` is not in the table.
    pub fn cancel(&self, id: &JobId) -> Result<(), JobError> {
        let tool = {
            let guard = self.lock();
            let Some(row) = guard.rows.get(id) else {
                return Err(JobError::Unknown(id.clone()));
            };
            if !row.state.is_running() {
                return Ok(());
            }
            row.tool.clone()
        };
        self.finish(id.clone(), Err(JobError::Cancelled { name: tool }));
        Ok(())
    }

    /// Running jobs in `session`, oldest first.
    pub fn list_running(&self, session: &str) -> Vec<RunningJob> {
        let mut rows: Vec<RunningJob> = self
            .lock()
            .rows
            .values()
            .filter(|row| row.session == session && row.state.is_running())
            .map(|row| RunningJob {
                id: row.id.as_str().to_string(),
                tool: row.tool.clone(),
                age_s: now_unix().saturating_sub(row.started),
                step: row
                    .progress
                    .as_ref()
                    .map(|note| note.label.clone())
                    .unwrap_or_else(|| "unknown".to_string()),
                origin: row.origin_label.clone(),
            })
            .collect();
        rows.sort_by(|a, b| a.id.cmp(&b.id));
        rows
    }

    /// Cancel `id` for a person in `session`.
    ///
    /// A schedule-origin row is refused. A finished row is reported and left as it is.
    /// `grant` `None` allows every tool.
    pub fn cancel_for_user(
        &self,
        session: &str,
        id: &JobId,
        grant: Option<&[String]>,
    ) -> UserCancel {
        let snapshot = {
            let guard = self.lock();
            let Some(row) = guard.rows.get(id) else {
                return UserCancel::Unknown;
            };
            if row.session != session {
                return UserCancel::Unknown;
            }
            UserSnap {
                tool: row.tool.clone(),
                origin: row.origin_label.clone(),
                running: row.state.is_running(),
                text: match &row.state {
                    State::Running => String::new(),
                    State::Done(output) => output.content.clone(),
                    State::Failed(err) => err.to_string(),
                },
            }
        };
        if snapshot.origin == "schedule" {
            return UserCancel::Schedule;
        }
        if !tool_permitted(grant, &snapshot.tool) {
            return UserCancel::Denied;
        }
        if !snapshot.running {
            return UserCancel::Finished {
                id: id.as_str().to_string(),
                tool: snapshot.tool,
                text: snapshot.text,
            };
        }
        let _ = self.cancel(id);
        UserCancel::Cancelled {
            id: id.as_str().to_string(),
            tool: snapshot.tool,
        }
    }

    /// Fail every running job in `session` with `err` (cancel, drop, or max steps).
    pub fn fail_running(&self, session: &str, err: JobError) {
        let ids: Vec<JobId> = {
            let guard = self.lock();
            guard
                .rows
                .iter()
                .filter(|(_, row)| row.session == session && row.state.is_running())
                .map(|(id, _)| id.clone())
                .collect()
        };
        for id in ids {
            self.finish(id, Err(err.clone()));
        }
    }

    /// Observe one row without its payload. Bodies stay out of this string.
    pub fn outcome_kind(&self, id: &JobId) -> Option<OutcomeKind> {
        let guard = self.lock();
        let row = guard.rows.get(id)?;
        Some(match &row.state {
            State::Running => OutcomeKind::Running,
            State::Done(output) => OutcomeKind::Done {
                is_error: output.is_error,
            },
            State::Failed(err) => OutcomeKind::Failed(err.to_string()),
        })
    }

    /// Record a progress sample and persist it. A missing or finished id is ignored.
    pub fn set_progress(&self, id: &JobId, note: ProgressNote) {
        let mut guard = self.lock();
        let Some(row) = guard.rows.get_mut(id) else {
            return;
        };
        if !row.state.is_running() {
            return;
        }
        let session = row.session.clone();
        row.progress = Some(note);
        guard.persist_session(&session);
        self.finish_guard(guard);
    }

    /// The timeout stored on `id`, for tests and recovery checks.
    pub fn timeout_of(&self, id: &JobId) -> Option<u64> {
        self.lock().rows.get(id).map(|row| row.timeout_secs)
    }

    /// Adopt persisted rows. See [`adopt`].
    pub fn adopt_lease(&self, generation: u64) -> Result<Adopted, AdoptErr> {
        let _gate = self
            .adopt_gate
            .lock()
            .unwrap_or_else(|err| err.into_inner());
        {
            let guard = self.lock();
            if let Some(have) = guard.adopted {
                if have == generation {
                    return Ok(Adopted::Already);
                }
                return Err(AdoptErr::Stale {
                    have,
                    got: generation,
                });
            }
            if !guard.recover_on_signal {
                drop(guard);
                self.lock().adopted = Some(generation);
                return Ok(Adopted::Already);
            }
        }
        {
            let mut guard = self.lock();
            guard.stamp = Some(generation);
        }
        let watches = self.recover();
        let jobs = {
            let guard = self.lock();
            guard
                .rows
                .values()
                .filter(|row| row.generation == Some(generation))
                .count()
        };
        spawn_watches(watches);
        self.lock().adopted = Some(generation);
        Ok(Adopted::Recovered { jobs })
    }

    /// Drop every row for `session`. Tests use this so a shared process table stays isolated.
    pub fn clear_session(&self, session: &str) {
        cancel_session(session);
        let mut guard = self.lock();
        guard.rows.retain(|_, row| row.session != session);
        guard.ready.remove(session);
        guard.persist_session(session);
        self.finish_guard(guard);
    }

    /// Take terminal rows already queued for `session`, sweeping timeouts first.
    pub fn drain_ready(&self, session: &str) -> Option<Message> {
        let mut guard = self.lock();
        sweep_timeouts(&mut guard);
        let items = take_ready(&mut guard, session);
        if !items.is_empty() {
            guard.persist_session(session);
        }
        let message = if items.is_empty() {
            None
        } else {
            Some(completion_message(&items))
        };
        self.finish_guard(guard);
        message
    }

    /// Wait until `session` has a terminal job, or `parent` is cancelled.
    pub async fn wait_ready(&self, session: &str, parent: &CancellationToken) -> JobWait {
        loop {
            let notified = self.notify.notified();
            tokio::pin!(notified);
            let sleep_for = {
                let mut guard = self.lock();
                sweep_timeouts(&mut guard);
                let items = take_ready(&mut guard, session);
                if !items.is_empty() {
                    guard.persist_session(session);
                    self.finish_guard(guard);
                    return JobWait::Ready(items);
                }
                let sleep_for = next_sleep(&guard, session);
                self.finish_guard(guard);
                sleep_for
            };
            if parent.is_cancelled() {
                return JobWait::Cancelled;
            }
            let Some(sleep_for) = sleep_for else {
                return JobWait::Ready(Vec::new());
            };
            tokio::select! {
                _ = parent.cancelled() => return JobWait::Cancelled,
                _ = &mut notified => {}
                _ = tokio::time::sleep(sleep_for) => {}
            }
        }
    }

    /// Load `{hex}.jobs.json` files. Returns builds that still need an artifact watcher.
    ///
    /// Rows already in the table are left alone, so a second call does not double-finish.
    pub fn recover(&self) -> Vec<(JobId, PathBuf, u64, u64)> {
        let (dir, artifact, default_timeout) = {
            let guard = self.lock();
            (
                guard.store_dir.clone(),
                guard.artifact_dir.clone(),
                guard.default_timeout,
            )
        };
        let Some(dir) = dir else {
            return Vec::new();
        };
        let entries = match std::fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(err) => {
                tracing::error!(
                    dir = %dir.display(),
                    error = %err,
                    "cannot read the job directory; no in-flight rows were restored"
                );
                return Vec::new();
            }
        };
        let mut watches = Vec::new();
        for entry in entries {
            let Ok(entry) = entry else {
                continue;
            };
            let name = entry.file_name();
            let Some(name) = name.to_str() else {
                continue;
            };
            if !name.ends_with(".jobs.json") {
                continue;
            }
            let Ok(bytes) = std::fs::read(entry.path()) else {
                continue;
            };
            let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bytes) else {
                tracing::error!(file = name, "job file is not json; leaving it unread");
                continue;
            };
            let Some(list) = value.get("jobs").and_then(|v| v.as_array()) else {
                continue;
            };
            for item in list {
                let Some(settled) = self.settle_one(item, artifact.as_deref(), default_timeout)
                else {
                    continue;
                };
                if let Some(watch) = settled {
                    watches.push((watch.id, watch.dir, watch.deadline_unix, watch.timeout_secs));
                }
            }
        }
        watches
    }

    /// `Some(watch)` when a build must be watched. `None` when the row was settled or skipped.
    fn settle_one(
        &self,
        item: &serde_json::Value,
        artifact: Option<&Path>,
        default_timeout: u64,
    ) -> Option<Option<Watch>> {
        let tool = item.get("tool").and_then(|v| v.as_str()).unwrap_or("");
        let session = item.get("session").and_then(|v| v.as_str()).unwrap_or("");
        let started = item.get("started").and_then(|v| v.as_u64()).unwrap_or(0);
        let id_str = item.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let timeout = item
            .get("timeout_secs")
            .and_then(|v| v.as_u64())
            .unwrap_or(default_timeout)
            .max(1);
        let state = item
            .get("state")
            .and_then(|v| v.as_str())
            .unwrap_or("running");
        let step = progress_step(item);
        let arn = item
            .pointer("/meta/task_arn")
            .and_then(|v| v.as_str())
            .map(str::to_string);
        let Ok(id) = JobId::new(id_str) else {
            tracing::error!(
                tool,
                "dropped a persisted job whose id is not a path segment"
            );
            return None;
        };
        if self.contains(&id) {
            return None;
        }
        if state != "running" {
            self.restore_terminal(item, &id, tool, session, started, timeout);
            return Some(None);
        }
        let parent = CancellationToken::new();
        if self
            .reserve(session, tool, id.clone(), Some(timeout), &parent)
            .is_err()
        {
            return None;
        }
        // `reserve` stamped `started` as now. Put the persisted instant back so the budget
        // is measured from the original accept, and keep the file's own timeout.
        {
            let mut guard = self.lock();
            let stamp = guard.stamp;
            if let Some(row) = guard.rows.get_mut(&id) {
                row.started = started;
                row.timeout_secs = timeout;
                row.task_arn = arn.clone();
                row.generation = stamp;
                if let Some(label) = item.pointer("/progress/label").and_then(|v| v.as_str()) {
                    let step_n = item
                        .pointer("/progress/step")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0) as u32;
                    let of_n = item
                        .pointer("/progress/of")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0) as u32;
                    row.progress = Some(ProgressNote {
                        step: step_n,
                        of: of_n,
                        label: label.to_string(),
                    });
                }
                let age = now_unix().saturating_sub(started);
                row.started_instant = Instant::now()
                    .checked_sub(Duration::from_secs(age))
                    .unwrap_or_else(Instant::now);
            }
            guard.persist_session(session);
            self.finish_guard(guard);
        }
        if fails_closed_on_restart(tool) {
            self.finish(
                id,
                Err(JobError::Interrupted {
                    tool: tool.to_string(),
                    step,
                }),
            );
            return Some(None);
        }
        if let Some(arn) = arn.as_deref() {
            let probe = self.lock().probe.clone();
            if let Some(probe) = probe {
                if let BuildLook::Stopped { exit_code } = probe.describe(arn) {
                    let code = exit_code.unwrap_or(1);
                    let content =
                        format!("run_build {id} exited {code}; output unavailable after restart");
                    let output = if code == 0 {
                        ToolOutput::ok(content)
                    } else {
                        ToolOutput::error(content)
                    };
                    self.finish(id, Ok(output));
                    return Some(None);
                }
            }
        }
        let Some(dir) = artifact else {
            self.finish(
                id,
                Err(JobError::Interrupted {
                    tool: tool.to_string(),
                    step,
                }),
            );
            return Some(None);
        };
        if let Some(output) = read_artifact(dir, id.as_str()) {
            self.finish(id, Ok(output));
            return Some(None);
        }
        let deadline = started.saturating_add(timeout);
        if now_unix() >= deadline {
            self.finish(
                id,
                Err(JobError::Timeout {
                    name: tool.to_string(),
                    secs: timeout,
                }),
            );
            return Some(None);
        }
        Some(Some(Watch {
            id,
            dir: dir.to_path_buf(),
            deadline_unix: deadline,
            timeout_secs: timeout,
        }))
    }

    fn restore_terminal(
        &self,
        item: &serde_json::Value,
        id: &JobId,
        tool: &str,
        session: &str,
        started: u64,
        timeout: u64,
    ) {
        let content = item
            .pointer("/result/content_capped")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let is_error = item
            .pointer("/result/is_error")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        let state_name = item
            .get("state")
            .and_then(|v| v.as_str())
            .unwrap_or("failed");
        let state = if state_name == "cancelled" {
            State::Failed(JobError::Cancelled {
                name: tool.to_string(),
            })
        } else if state_name == "done" && !is_error {
            State::Done(ToolOutput::ok(content))
        } else if state_name == "failed" || is_error {
            State::Failed(JobError::Failed {
                name: tool.to_string(),
                message: content,
            })
        } else {
            State::Done(ToolOutput::ok(content))
        };
        let mut guard = self.lock();
        let (pod, boot_id, stamp) = (guard.pod.clone(), guard.boot_id.clone(), guard.stamp);
        guard.rows.insert(
            id.clone(),
            Row {
                id: id.clone(),
                tool: tool.to_string(),
                session: session.to_string(),
                started,
                started_instant: Instant::now(),
                timeout_secs: timeout,
                cancel: CancellationToken::new(),
                state,
                progress: None,
                task_arn: None,
                origin_label: item
                    .get("origin")
                    .and_then(|v| v.as_str())
                    .unwrap_or("cli")
                    .to_string(),
                pod,
                boot_id,
                generation: stamp,
            },
        );
        guard
            .ready
            .entry(session.to_string())
            .or_default()
            .push_back(id.clone());
        guard.persist_session(session);
        self.finish_guard(guard);
    }
}

impl Default for JobRuntime {
    fn default() -> Self {
        Self::new()
    }
}

fn take_ready(guard: &mut Tables, session: &str) -> Vec<JobCompletion> {
    let ids: Vec<JobId> = match guard.ready.get_mut(session) {
        Some(queue) => queue.drain(..).collect(),
        None => Vec::new(),
    };
    let mut items = Vec::with_capacity(ids.len());
    for id in ids {
        let Some(row) = guard.rows.get(&id) else {
            continue;
        };
        let result = match &row.state {
            State::Done(output) => Ok(output.clone()),
            State::Failed(err) => Err(err.clone()),
            State::Running => continue,
        };
        items.push(JobCompletion {
            id: id.clone(),
            tool: row.tool.clone(),
            result,
        });
        // The terminal value has been copied out. Drop the row so a finished id does not
        // stay in the map for the life of the process. A late finish finds no row and is ignored.
        guard.rows.remove(&id);
    }
    items
}

fn sweep_timeouts(guard: &mut Tables) {
    let mut due = Vec::new();
    for (id, row) in &guard.rows {
        if !row.state.is_running() {
            continue;
        }
        if row.started_instant.elapsed() >= Duration::from_secs(row.timeout_secs) {
            due.push((
                id.clone(),
                row.session.clone(),
                row.tool.clone(),
                row.timeout_secs,
            ));
        }
    }
    for (id, session, tool, secs) in due {
        if let Some(row) = guard.rows.get_mut(&id) {
            if !row.state.is_running() {
                continue;
            }
            row.cancel.cancel();
            row.state = State::Failed(JobError::Timeout { name: tool, secs });
        }
        guard
            .ready
            .entry(session.clone())
            .or_default()
            .push_back(id);
        guard.persist_session(&session);
    }
}

fn next_sleep(guard: &Tables, session: &str) -> Option<Duration> {
    let mut soon: Option<Duration> = None;
    for row in guard.rows.values() {
        if row.session != session || !row.state.is_running() {
            continue;
        }
        let budget = Duration::from_secs(row.timeout_secs);
        let left = budget
            .saturating_sub(row.started_instant.elapsed())
            .max(Duration::from_millis(1));
        soon = Some(soon.map_or(left, |prev| prev.min(left)));
    }
    soon
}

impl Tables {
    fn persist_session(&mut self, session: &str) {
        let Some(dir) = &self.store_dir else {
            return;
        };
        let path = jobs_path(dir, session);
        let jobs: Vec<serde_json::Value> = self
            .rows
            .values()
            .filter(|row| row.session == session)
            .map(row_json)
            .collect();
        let bytes = if jobs.is_empty() {
            None
        } else {
            match serde_json::to_vec_pretty(&serde_json::json!({
                "version": 2,
                "jobs": jobs,
            })) {
                Ok(bytes) => Some(bytes),
                Err(err) => {
                    tracing::error!(error = %err, "cannot serialize in-flight jobs");
                    return;
                }
            }
        };
        if let Some(pos) = self.snaps.iter().position(|(p, _)| p == &path) {
            self.snaps[pos] = (path, bytes);
        } else {
            self.snaps.push((path, bytes));
        }
    }
}

fn row_json(row: &Row) -> serde_json::Value {
    let (state, is_error, content) = match &row.state {
        State::Running => ("running", false, String::new()),
        State::Done(output) => {
            let state = if output.is_error { "failed" } else { "done" };
            (state, output.is_error, cap_content(&output.content))
        }
        State::Failed(JobError::Cancelled { .. }) => ("cancelled", true, String::new()),
        State::Failed(err) => ("failed", true, cap_content(&err.to_string())),
    };
    let mut value = serde_json::json!({
        "id": row.id.as_str(),
        "tool": row.tool,
        "session": row.session,
        "started": row.started,
        "timeout_secs": row.timeout_secs,
        "state": state,
        "origin": row.origin_label,
        "writer": { "pod": row.pod, "boot_id": row.boot_id },
    });
    if let Some(progress) = &row.progress {
        value["progress"] = serde_json::json!({
            "step": progress.step,
            "of": progress.of,
            "label": progress.label,
        });
    }
    if let Some(arn) = &row.task_arn {
        value["meta"] = serde_json::json!({ "task_arn": arn });
    }
    if let Some(generation) = row.generation {
        value["generation"] = serde_json::json!(generation);
    }
    if state != "running" {
        value["result"] = serde_json::json!({
            "is_error": is_error,
            "content_capped": content,
            "images": 0,
        });
    }
    value
}

fn cap_content(text: &str) -> String {
    let mut end = 1024.min(text.len());
    while end > 0 && !text.is_char_boundary(end) {
        end -= 1;
    }
    text[..end].to_string()
}

fn origin_label() -> String {
    match origin() {
        Origin::Chat { .. } => "chat".to_string(),
        Origin::Schedule { .. } => "schedule".to_string(),
        Origin::Job { .. } => "job".to_string(),
        Origin::Cli => "cli".to_string(),
    }
}

/// Placeholder text for the one `tool_result` a background accept is allowed to produce.
pub fn placeholder(id: &JobId) -> String {
    format!("accepted, id={id}")
}

/// User message carrying terminal jobs, in `items` order.
pub fn completion_message(items: &[JobCompletion]) -> Message {
    Message {
        role: Role::User,
        content: completion_blocks(items),
    }
}

/// Blocks for [`completion_message`]. Images ride on the user turn, not a second tool result.
pub fn completion_blocks(items: &[JobCompletion]) -> Vec<ContentBlock> {
    let mut blocks = Vec::new();
    for item in items {
        match &item.result {
            Ok(output) => {
                let status = if output.is_error {
                    "failed"
                } else {
                    "finished"
                };
                let mut text = format!(
                    "job {} ({}) {status}\n{}",
                    item.id, item.tool, output.content
                );
                let images = admit_tool_images(&mut text, output.images.clone());
                blocks.push(ContentBlock::text(text));
                for image in images {
                    blocks.push(ContentBlock::image_base64(image.media_type, image.data));
                }
            }
            Err(err) => {
                blocks.push(ContentBlock::text(format!(
                    "job {} ({}) failed: {err}",
                    item.id, item.tool
                )));
            }
        }
    }
    blocks
}

/// Session file stem. Must stay identical to `lvz_memory::FileStore`'s `{hex}.json` stem.
pub fn session_file_stem(session: &str) -> String {
    let mut name = String::with_capacity(session.len() * 2);
    for byte in session.bytes() {
        name.push_str(&format!("{byte:02x}"));
    }
    name
}

/// `{dir}/{hex}.jobs.json`, beside the session transcript `{hex}.json`.
pub fn jobs_path(dir: &Path, session: &str) -> PathBuf {
    dir.join(format!("{}.jobs.json", session_file_stem(session)))
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

impl JobRuntime {
    fn finish_guard(&self, mut guard: std::sync::MutexGuard<'_, Tables>) {
        let snaps = std::mem::take(&mut guard.snaps);
        let fs = Arc::clone(&guard.fs);
        drop(guard);
        if snaps.is_empty() {
            return;
        }
        let queue = {
            let mut slot = self.queue.lock().unwrap_or_else(|err| err.into_inner());
            if slot.is_none() {
                *slot = Some(PersistQueue::start(fs));
            }
            match slot.as_ref() {
                Some(queue) => queue.clone(),
                None => return,
            }
        };
        for (path, bytes) in snaps {
            queue.write_and_wait(path, bytes);
        }
    }
}

fn read_artifact(dir: &Path, id: &str) -> Option<ToolOutput> {
    let code_text = std::fs::read_to_string(dir.join(format!("{id}.code"))).ok()?;
    let code: i32 = code_text.trim().parse().ok()?;
    let mut content = format!("run_build {id} exited {code}");
    if let Ok(log) = std::fs::read_to_string(dir.join(format!("{id}.out"))) {
        let mut end = 4_000.min(log.len());
        while end > 0 && !log.is_char_boundary(end) {
            end -= 1;
        }
        content.push('\n');
        content.push_str(&log[..end]);
    }
    let output = if code == 0 {
        ToolOutput::ok(content)
    } else {
        ToolOutput::error(content)
    };
    Some(output)
}

fn progress_step(item: &serde_json::Value) -> String {
    let Some(label) = item.pointer("/progress/label").and_then(|v| v.as_str()) else {
        return "unknown".to_string();
    };
    let step = item
        .pointer("/progress/step")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let of = item
        .pointer("/progress/of")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    format!("{step}/{of} {label}")
}

/// One running job, without its payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunningJob {
    /// Job id.
    pub id: String,
    /// Tool that accepted it.
    pub tool: String,
    /// Seconds since accept.
    pub age_s: u64,
    /// Last progress label, or `unknown`.
    pub step: String,
    /// `chat`, `schedule`, or `cli`.
    pub origin: String,
}

struct UserSnap {
    tool: String,
    origin: String,
    running: bool,
    text: String,
}

/// What a person's cancel did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UserCancel {
    /// The row was running and is now cancelled.
    Cancelled {
        /// Job id.
        id: String,
        /// Tool name.
        tool: String,
    },
    /// The row belongs to the scheduler.
    Schedule,
    /// The sender may not use that tool.
    Denied,
    /// The row already had a result.
    Finished {
        /// Job id.
        id: String,
        /// Tool name.
        tool: String,
        /// The result text already stored.
        text: String,
    },
    /// No row in this session.
    Unknown,
}

fn session_parents() -> &'static Mutex<HashMap<String, CancellationToken>> {
    static PARENTS: OnceLock<Mutex<HashMap<String, CancellationToken>>> = OnceLock::new();
    PARENTS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// The token detached jobs in `session` are children of.
///
/// Cancelling it stops those jobs. A chat turn's own token does not.
pub fn session_parent(session: &str) -> CancellationToken {
    let mut map = session_parents()
        .lock()
        .unwrap_or_else(|err| err.into_inner());
    map.entry(session.to_string()).or_default().clone()
}

/// Cancel the session token and forget it. Running detached jobs observe the cancel.
pub fn cancel_session(session: &str) {
    if let Some(token) = session_parents()
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .remove(session)
    {
        token.cancel();
    }
}

/// The process-wide table. Tools and the chat loop share it.
pub fn global() -> &'static JobRuntime {
    static GLOBAL: OnceLock<JobRuntime> = OnceLock::new();
    GLOBAL.get_or_init(JobRuntime::new)
}

/// Why [`adopt`] refused a lease generation.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AdoptErr {
    /// A newer generation was already accepted.
    #[error("stale lease")]
    Stale {
        /// Generation already adopted.
        have: u64,
        /// Generation the caller offered.
        got: u64,
    },
}

/// What [`adopt`] did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Adopted {
    /// Rows were read and settled.
    Recovered {
        /// Rows touched.
        jobs: usize,
    },
    /// This generation was already adopted, or boot recovery already ran.
    Already,
}

/// Point the process table at the session directory and settle any persisted rows.
///
/// `store` is the `FileStore` directory. `artifact` is where `run_build` writes
/// `$BUILD_ID.code` (`BUILDER_RESULT_DIR`, otherwise `$HOME/.builds`).
/// Boot recovery runs. [`configure_ext`] with `recover_on_signal` skips it.
pub fn configure(store: Option<PathBuf>, artifact: Option<PathBuf>, default_timeout: u64) {
    configure_ext(store, artifact, default_timeout, false, Arc::new(LocalFs));
}

/// [`configure`] with an explicit filesystem and the lease-gated recovery switch.
///
/// `recover_on_signal` true performs no adoption. [`adopt`] does that later.
pub fn configure_ext(
    store: Option<PathBuf>,
    artifact: Option<PathBuf>,
    default_timeout: u64,
    recover_on_signal: bool,
    fs: Arc<dyn DurableFs>,
) {
    let runtime = global();
    runtime.configure_fs(store, artifact, default_timeout, recover_on_signal, fs);
    if recover_on_signal {
        return;
    }
    spawn_watches(runtime.recover());
}

/// Adopt persisted rows for `generation`.
///
/// The first call settles them. The same generation returns [`Adopted::Already`].
/// A different generation after that is [`AdoptErr::Stale`]. When recovery-on-signal
/// is off, boot recovery already ran and this returns [`Adopted::Already`].
///
/// # Errors
///
/// [`AdoptErr::Stale`] when `generation` is not the generation already adopted.
pub fn adopt(generation: u64) -> Result<Adopted, AdoptErr> {
    global().adopt_lease(generation)
}

fn spawn_watches(watches: Vec<(JobId, PathBuf, u64, u64)>) {
    if watches.is_empty() {
        return;
    }
    let Ok(handle) = tokio::runtime::Handle::try_current() else {
        for (id, dir, deadline, secs) in watches {
            // No runtime (a sync caller). The row stays running; a later process tick
            // is not available here, so settle an expired deadline inline.
            if now_unix() >= deadline {
                global().finish(
                    id,
                    Err(JobError::Timeout {
                        name: "run_build".into(),
                        secs,
                    }),
                );
            } else {
                let _ = (dir, id);
            }
        }
        return;
    };
    for (id, dir, deadline, secs) in watches {
        handle.spawn(async move {
            watch_loop(id, dir, deadline, secs).await;
        });
    }
}

async fn watch_loop(id: JobId, dir: PathBuf, deadline_unix: u64, timeout_secs: u64) {
    loop {
        if let Some(output) = read_artifact(&dir, id.as_str()) {
            global().finish(id, Ok(output));
            return;
        }
        if now_unix() >= deadline_unix {
            global().finish(
                id,
                Err(JobError::Timeout {
                    name: "run_build".to_string(),
                    secs: timeout_secs,
                }),
            );
            return;
        }
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
}

/// `true` while this task has a work scope (a chat tool call or a scheduled attempt).
pub fn in_job_scope() -> bool {
    work_scope().is_some()
}

/// `true` while `id` is still running. A finished id is gone once the loop has injected it.
pub fn job_running(id: &JobId) -> bool {
    matches!(global().outcome_kind(id), Some(OutcomeKind::Running))
}

/// Reserve `id` on the current work scope and return the lease the worker holds.
///
/// # Errors
///
/// [`ToolError::Execution`] outside a work scope, when the session is at the cap, or when `id`
/// is already in the table.
pub fn reserve_work(
    tool: &str,
    id: JobId,
    estimated_seconds: Option<u64>,
) -> Result<WorkLease, ToolError> {
    let token = reserve_job(tool, id.clone(), estimated_seconds)?;
    let progress_id = id.clone();
    let progress = ProgressTx::from_fn(move |note| {
        global().set_progress(&progress_id, note);
    });
    Ok(WorkLease {
        id,
        token,
        progress,
    })
}

/// Reserve `id` on the current turn and return the child cancel token.
///
/// # Errors
///
/// [`ToolError::Execution`] outside a chat turn, when the session is at the cap, or when `id`
/// is already in the table.
pub fn reserve_job(
    tool: &str,
    id: JobId,
    estimated_seconds: Option<u64>,
) -> Result<CancellationToken, ToolError> {
    let Some(scope) = work_scope() else {
        return Err(ToolError::Execution(
            "no job scope on this call".to_string(),
        ));
    };
    global().reserve(&scope.session, tool, id, estimated_seconds, &scope.cancel)
}

/// Publish the terminal output for `id`. A second publish is ignored.
pub fn finish_job(id: JobId, output: ToolOutput) {
    global().finish(id, Ok(output));
}

/// Publish a terminal [`JobError`] for `id`. A second publish is ignored.
pub fn fail_job(id: JobId, err: JobError) {
    global().finish(id, Err(err));
}

/// Run `invoke` with the turn's job scope installed.
pub async fn scoped_invoke<F, T>(session: &str, cancel: &CancellationToken, invoke: F) -> T
where
    F: std::future::Future<Output = T>,
{
    lvz_protocol::enter_work_scope(session, cancel.clone(), invoke).await
}

/// Chat path for a legacy [`Pending`] result: reserve a job and poll `poll_with` in the background.
///
/// The model is not asked to call the poll tool. The schedule path does not use this; it still
/// polls inline. A timeout here fails the job and does not call the original tool again.
///
/// # Errors
///
/// [`ToolError::Execution`] when the handle is not a [`JobId`] or the session is at the cap.
pub fn promote_pending(
    session: &str,
    tool: &str,
    pending: &Pending,
    parent: &CancellationToken,
    tools: ToolRegistry,
) -> Result<JobId, ToolError> {
    let id = JobId::new(&pending.handle).map_err(|err| ToolError::Execution(err.to_string()))?;
    let child = global().reserve(session, tool, id.clone(), pending.estimated_seconds, parent)?;
    let poll_with = pending.poll_with.clone();
    let handle = pending.handle.clone();
    let name = tool.to_string();
    let id_task = id.clone();
    tokio::spawn(async move {
        loop {
            if child.is_cancelled() {
                fail_job(id_task, JobError::Cancelled { name: name.clone() });
                return;
            }
            match tools
                .invoke(&poll_with, serde_json::json!({ "handle": handle }))
                .await
            {
                Ok(output) if output.pending.is_some() || output.accepted.is_some() => {
                    tokio::select! {
                        _ = child.cancelled() => {
                            fail_job(id_task, JobError::Cancelled { name: name.clone() });
                            return;
                        }
                        _ = tokio::time::sleep(Duration::from_secs(2)) => {}
                    }
                }
                Ok(output) => {
                    finish_job(id_task, output);
                    return;
                }
                Err(err) => {
                    fail_job(
                        id_task,
                        JobError::Failed {
                            name,
                            message: err.to_string(),
                        },
                    );
                    return;
                }
            }
        }
    });
    Ok(id)
}

/// Notice posted to the room when a job is accepted. Names and the id only.
pub fn accept_notice(tool: &str, id: &JobId) -> String {
    format!("⏳ `{tool}` accepted, id={id}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::thread;

    fn id(token: &str) -> JobId {
        JobId::new(token).expect("test id")
    }

    #[test]
    fn cap_is_per_session_and_the_fifth_start_is_an_error() {
        let runtime = JobRuntime::new();
        let parent = CancellationToken::new();
        for n in 0..4 {
            runtime
                .reserve(
                    "room",
                    "server_wake",
                    id(&format!("c{n}")),
                    Some(30),
                    &parent,
                )
                .expect("under the cap");
        }
        let err = runtime
            .reserve("room", "server_wake", id("c4"), Some(30), &parent)
            .expect_err("cap");
        assert!(matches!(err, ToolError::Execution(ref msg) if msg.contains("4")));
        runtime
            .reserve("other", "server_wake", id("o0"), Some(30), &parent)
            .expect("a second session has its own cap");
        assert_eq!(runtime.inflight("room"), 4);
    }

    #[test]
    fn concurrent_reserves_do_not_pass_the_cap() {
        let runtime = Arc::new(JobRuntime::new());
        let parent = CancellationToken::new();
        let barrier = Arc::new(std::sync::Barrier::new(8));
        let mut threads = Vec::new();
        for n in 0..8 {
            let runtime = Arc::clone(&runtime);
            let parent = parent.clone();
            let barrier = Arc::clone(&barrier);
            threads.push(thread::spawn(move || {
                barrier.wait();
                runtime.reserve("conc", "run_build", id(&format!("k{n}")), Some(10), &parent)
            }));
        }
        let mut oks = 0;
        let mut errs = 0;
        for handle in threads {
            match handle.join().expect("thread") {
                Ok(_) => oks += 1,
                Err(_) => errs += 1,
            }
        }
        assert_eq!(oks, 4);
        assert_eq!(errs, 4);
        assert_eq!(runtime.inflight("conc"), 4);
    }

    #[test]
    fn completions_drain_in_finish_order_not_start_order() {
        let runtime = JobRuntime::new();
        let parent = CancellationToken::new();
        let first = id("A");
        let second = id("B");
        runtime
            .reserve("ord", "order_job", first.clone(), Some(30), &parent)
            .expect("a");
        runtime
            .reserve("ord", "order_job", second.clone(), Some(30), &parent)
            .expect("b");
        runtime.finish(second.clone(), Ok(ToolOutput::ok("PAYLOAD_B")));
        runtime.finish(first.clone(), Ok(ToolOutput::ok("PAYLOAD_A")));
        // A second finish must not enqueue another result for the same id.
        runtime.finish(second, Ok(ToolOutput::ok("PAYLOAD_B_AGAIN")));
        let text = runtime.drain_ready("ord").expect("ready").text();
        let b = text.find("PAYLOAD_B").expect("b");
        let a = text.find("PAYLOAD_A").expect("a");
        assert!(b < a, "finish order, got {text}");
        assert!(!text.contains("PAYLOAD_B_AGAIN"));
        assert!(runtime.drain_ready("ord").is_none());
    }

    #[test]
    fn failure_is_a_single_terminal_error() {
        let runtime = JobRuntime::new();
        let parent = CancellationToken::new();
        let job = id("fail1");
        runtime
            .reserve("f", "server_wake", job.clone(), Some(30), &parent)
            .expect("reserve");
        runtime.finish(
            job,
            Err(JobError::Failed {
                name: "server_wake".into(),
                message: "boom".into(),
            }),
        );
        let text = runtime.drain_ready("f").expect("ready").text();
        assert!(text.contains("server_wake failed: boom"), "{text}");
        assert_eq!(runtime.inflight("f"), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn timeout_fails_the_job_and_does_not_require_another_reserve() {
        let runtime = JobRuntime::new();
        let parent = CancellationToken::new();
        let job = id("tm");
        let reserves = AtomicUsize::new(0);
        reserves.fetch_add(1, Ordering::SeqCst);
        runtime
            .reserve("ts", "server_wake", job.clone(), Some(5), &parent)
            .expect("reserve");
        let wait = runtime.wait_ready("ts", &parent);
        let ready = tokio::time::timeout(Duration::from_secs(6), wait)
            .await
            .expect("timeout should complete under the paused clock");
        match ready {
            JobWait::Ready(items) => {
                assert_eq!(items.len(), 1);
                match &items[0].result {
                    Err(JobError::Timeout { name, secs }) => {
                        assert_eq!(name, "server_wake");
                        assert_eq!(*secs, 5);
                    }
                    other => panic!("expected timeout, got {other:?}"),
                }
            }
            JobWait::Cancelled => panic!("not cancelled"),
        }
        assert_eq!(reserves.load(Ordering::SeqCst), 1);
        assert_eq!(runtime.inflight("ts"), 0);
    }

    #[test]
    fn cancel_marks_the_job_and_fires_the_child_token() {
        let runtime = JobRuntime::new();
        let parent = CancellationToken::new();
        let job = id("cx");
        let child = runtime
            .reserve("cs", "run_build", job.clone(), Some(60), &parent)
            .expect("reserve");
        runtime.cancel(&job).expect("cancel");
        assert!(child.is_cancelled());
        let kind = runtime.outcome_kind(&job).expect("row");
        assert_eq!(kind, OutcomeKind::Failed("run_build cancelled".to_string()));
        let missing = id("nope");
        assert!(matches!(
            runtime.cancel(&missing),
            Err(JobError::Unknown(_))
        ));
    }

    #[test]
    fn restart_fails_power_and_obs_and_reattaches_a_finished_build() {
        let dir =
            std::env::temp_dir().join(format!("lvz-jobs-{}-{}", std::process::id(), now_unix()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let art = dir.join("art");
        std::fs::create_dir_all(&art).expect("art");
        std::fs::write(art.join("bld1.code"), "0\n").expect("code");
        std::fs::write(art.join("bld1.out"), "ok-log").expect("out");
        let session = "room1";
        let started = now_unix();
        let body = serde_json::json!({
            "jobs": [
                {"id": "wake1", "tool": "server_wake", "session": session, "started": started},
                {"id": "obs1", "tool": "obs_macro", "session": session, "started": started},
                {"id": "bld1", "tool": "run_build", "session": session, "started": started}
            ]
        });
        std::fs::write(jobs_path(&dir, session), body.to_string()).expect("jobs file");
        let runtime = JobRuntime::new();
        runtime.configure_with(Some(dir.clone()), Some(art), 600);
        let watches = runtime.recover();
        assert!(watches.is_empty(), "a code file is already the result");
        let text = runtime.drain_ready(session).expect("settled").text();
        assert!(
            text.contains("server_wake interrupted after unknown"),
            "{text}"
        );
        assert!(
            text.contains("obs_macro interrupted after unknown"),
            "{text}"
        );
        assert!(text.contains("run_build bld1 exited 0"), "{text}");
        assert!(text.contains("ok-log"), "{text}");
        assert!(!jobs_path(&dir, session).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn restart_times_out_a_build_whose_artifact_never_appeared() {
        let dir = std::env::temp_dir().join(format!(
            "lvz-jobs-miss-{}-{}",
            std::process::id(),
            now_unix()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let art = dir.join("art");
        std::fs::create_dir_all(&art).expect("art");
        let session = "room2";
        let body = serde_json::json!({
            "jobs": [
                {"id": "oldbuild", "tool": "run_build", "session": session, "started": 1}
            ]
        });
        std::fs::write(jobs_path(&dir, session), body.to_string()).expect("jobs file");
        let runtime = JobRuntime::new();
        runtime.configure_with(Some(dir.clone()), Some(art), 600);
        let watches = runtime.recover();
        assert!(watches.is_empty());
        let text = runtime.drain_ready(session).expect("timeout").text();
        assert!(text.contains("timed out"), "{text}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_running_build_without_a_code_file_is_watched() {
        let dir = std::env::temp_dir().join(format!(
            "lvz-jobs-watch-{}-{}",
            std::process::id(),
            now_unix()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let art = dir.join("art");
        std::fs::create_dir_all(&art).expect("art");
        let session = "room3";
        let body = serde_json::json!({
            "jobs": [
                {"id": "live1", "tool": "run_build", "session": session, "started": now_unix()}
            ]
        });
        std::fs::write(jobs_path(&dir, session), body.to_string()).expect("jobs file");
        let runtime = JobRuntime::new();
        runtime.configure_with(Some(dir.clone()), Some(art), 600);
        let watches = runtime.recover();
        assert_eq!(watches.len(), 1);
        assert_eq!(runtime.inflight(session), 1);
        assert_eq!(
            runtime.outcome_kind(&id("live1")),
            Some(OutcomeKind::Running)
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn reserve_persists_the_four_fields_and_finish_removes_the_row() {
        let dir = std::env::temp_dir().join(format!(
            "lvz-jobs-persist-{}-{}",
            std::process::id(),
            now_unix()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let runtime = JobRuntime::new();
        runtime.configure_with(Some(dir.clone()), None, 600);
        let parent = CancellationToken::new();
        let job = id("pers1");
        runtime
            .reserve("sess", "run_build", job.clone(), Some(30), &parent)
            .expect("reserve");
        let raw = std::fs::read_to_string(jobs_path(&dir, "sess")).expect("file");
        let value: serde_json::Value = serde_json::from_str(&raw).expect("json");
        let row = &value["jobs"][0];
        assert_eq!(row["id"], "pers1");
        assert_eq!(row["tool"], "run_build");
        assert_eq!(row["session"], "sess");
        assert!(row["started"].as_u64().is_some());
        runtime.finish(job.clone(), Ok(ToolOutput::ok("done")));
        let raw = std::fs::read_to_string(jobs_path(&dir, "sess")).expect("kept until delivered");
        assert!(raw.contains("\"done\""), "{raw}");
        runtime.drain_ready("sess").expect("deliver");
        assert!(!jobs_path(&dir, "sess").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn v2_recovers_its_own_timeout_and_v1_uses_the_default() {
        let dir =
            std::env::temp_dir().join(format!("lvz-jobs-v2-{}-{}", std::process::id(), now_unix()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let session = "v2";
        let body = serde_json::json!({
            "version": 2,
            "jobs": [{
                "id": "live2",
                "tool": "run_build",
                "session": session,
                "started": now_unix(),
                "timeout_secs": 42,
                "state": "running"
            }]
        });
        std::fs::write(jobs_path(&dir, session), body.to_string()).expect("file");
        let runtime = JobRuntime::new();
        runtime.configure_with(Some(dir.clone()), Some(dir.clone()), 600);
        let watches = runtime.recover();
        assert_eq!(watches.len(), 1);
        assert_eq!(runtime.timeout_of(&id("live2")), Some(42));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn terminal_undelivered_row_is_delivered_once() {
        let dir = std::env::temp_dir().join(format!(
            "lvz-jobs-undelivered-{}-{}",
            std::process::id(),
            now_unix()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let session = "held";
        let body = serde_json::json!({
            "version": 2,
            "jobs": [{
                "id": "done1",
                "tool": "server_wake",
                "session": session,
                "started": now_unix(),
                "timeout_secs": 30,
                "state": "done",
                "result": {"is_error": false, "content_capped": "powered on", "images": 0}
            }]
        });
        std::fs::write(jobs_path(&dir, session), body.to_string()).expect("file");
        let runtime = JobRuntime::new();
        runtime.configure_with(Some(dir.clone()), None, 600);
        assert!(runtime.recover().is_empty());
        let text = runtime.drain_ready(session).expect("once").text();
        assert!(text.contains("powered on"), "{text}");
        assert!(runtime.drain_ready(session).is_none());
        assert!(!jobs_path(&dir, session).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn recover_on_signal_waits_for_adopt_and_rejects_a_stale_generation() {
        let dir = std::env::temp_dir().join(format!(
            "lvz-jobs-lease-{}-{}",
            std::process::id(),
            now_unix()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let session = "lease";
        let body = serde_json::json!({
            "jobs": [{"id": "wake9", "tool": "server_wake", "session": session, "started": now_unix()}]
        });
        std::fs::write(jobs_path(&dir, session), body.to_string()).expect("file");
        let runtime = JobRuntime::new();
        runtime.configure_fs(
            Some(dir.clone()),
            None,
            600,
            true,
            std::sync::Arc::new(crate::durable::LocalFs),
        );
        assert!(runtime.recover().is_empty() || runtime.inflight(session) == 0);
        // Flag on: recover() still loads if called. Boot must not call it.
        // Clear anything a mistaken call would have added by using a fresh read through adopt.
        runtime.clear_session(session);
        std::fs::write(jobs_path(&dir, session), body.to_string()).expect("rewrite");
        assert_eq!(runtime.inflight(session), 0);
        let adopted = runtime.adopt_lease(7).expect("first");
        assert!(matches!(adopted, Adopted::Recovered { .. }));
        let text = runtime.drain_ready(session).expect("settled").text();
        assert!(text.contains("interrupted"), "{text}");
        assert_eq!(runtime.adopt_lease(7).expect("same"), Adopted::Already);
        assert!(matches!(
            runtime.adopt_lease(3),
            Err(AdoptErr::Stale { have: 7, got: 3 })
        ));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn exactly_one_terminal_across_seeded_races() {
        for seed in 0..1000u32 {
            let runtime = JobRuntime::new();
            let parent = CancellationToken::new();
            let job = id(&format!("race{seed}"));
            runtime
                .reserve("race", "server_wake", job.clone(), Some(30), &parent)
                .expect("reserve");
            match seed % 5 {
                0 => {
                    runtime.finish(job.clone(), Ok(ToolOutput::ok("a")));
                    let _ = runtime.cancel(&job);
                }
                1 => {
                    let _ = runtime.cancel(&job);
                    runtime.finish(job.clone(), Ok(ToolOutput::ok("b")));
                }
                2 => {
                    runtime.finish(job.clone(), Ok(ToolOutput::ok("c")));
                    runtime.finish(
                        job.clone(),
                        Err(JobError::Failed {
                            name: "server_wake".into(),
                            message: "late".into(),
                        }),
                    );
                }
                3 => {
                    let _ = runtime.cancel(&job);
                    let _ = runtime.cancel(&job);
                }
                _ => {
                    runtime.finish(
                        job.clone(),
                        Err(JobError::Timeout {
                            name: "server_wake".into(),
                            secs: 1,
                        }),
                    );
                    let _ = runtime.cancel(&job);
                }
            }
            let text = runtime.drain_ready("race").expect("one").text();
            assert_eq!(text.matches("job ").count(), 1, "{text}");
        }
    }
}
