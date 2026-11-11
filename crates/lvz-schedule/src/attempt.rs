//! One externally clocked attempt of a job, for `POST /v1/jobs/{id}` (`lav --serve-jobs`).
//!
//! In that mode lav runs no timer: the caller (phase5-endpoint) owns the clock, the lease and
//! the retry chain, and asks for one attempt at a time. The attempt is the same as a fire of
//! the in-process scheduler: the direct tool call or prompt turn, accepted (pending) work polled
//! to its verdict **inline**, the `summarize` render, and the same `report_body`. The verdict and
//! retry decision come from the same `record`, so `retry_in`/`gave_up` match today's policy:
//! any failure retries (a tool's `is_error` included) while `attempt <= retry_max`.
use std::sync::Arc;
use std::time::Duration;

use lvz_protocol::{AgentHandle, ToolImage};
use lvz_tools::ToolRegistry;

use super::{
    finish, log_verbose, now_unix, poll_pending, run_action, ActionOutcome, FireReport,
    PendingWork, ScheduleJob, ScheduleRegistry, MIN_PENDING_BUDGET,
};

/// The verdict of one attempt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AttemptReport {
    /// Which job ran.
    pub job_id: String,
    /// Whether the attempt succeeded.
    pub ok: bool,
    /// The preformatted report (`✅`/`❌`, retry countdown or give-up line).
    pub body: String,
    /// The attempt number the caller asked for (1 = first try).
    pub attempt: u32,
    /// Seconds the caller should wait before the next attempt; `None` = no retry.
    pub retry_in: Option<u64>,
    /// True when the chain is exhausted (failure with `retry_max > 0` and no retry left).
    pub gave_up: bool,
    /// Admitted images from a terminal tool result.
    pub images: Vec<ToolImage>,
}

impl ScheduleRegistry {
    /// Shorten the inline poll cadence of [`run_attempt`](Self::run_attempt) (tests).
    pub fn with_poll_interval(mut self, seconds: u64) -> Self {
        self.poll_interval = seconds;
        self
    }

    /// Run attempt `attempt` (1-based) of job `idx` to its verdict. `on_waiting` receives the
    /// `⏳` line once if the tool accepts work that is still running. The whole attempt —
    /// polling and the `summarize` turn included — is capped at `timeout`; hitting the cap is
    /// a failure like any other. `None` if `idx` is out of range or `attempt` is 0.
    pub async fn run_attempt(
        &self,
        idx: usize,
        attempt: u32,
        tools: &ToolRegistry,
        agent: &Arc<dyn AgentHandle>,
        timeout: Duration,
        mut on_waiting: impl FnMut(String) + Send,
    ) -> Option<AttemptReport> {
        let job = self.jobs.get(idx)?.clone();
        if attempt == 0 {
            return None;
        }
        let started = std::time::Instant::now();
        let outcome =
            match tokio::time::timeout(timeout, self.drive(&job, tools, agent, &mut on_waiting))
                .await
            {
                Ok(o) => o,
                Err(_) => {
                    let e = format!(
                        "attempt did not finish within the jobs timeout ({}s)",
                        timeout.as_secs()
                    );
                    finish(&job, agent, Err(e), Vec::new(), None, Vec::new()).await
                }
            };
        // The caller numbers the chain; align the registry's counter so `record` numbers the
        // attempt and decides the retry exactly as the in-process scheduler would.
        if let Ok(mut guard) = self.state.write() {
            let s = guard.entry(job.id.clone()).or_default();
            s.attempt = attempt - 1;
            s.pending = None;
        }
        let report: FireReport = self.record(
            &job,
            &outcome.result,
            outcome.summary.as_deref(),
            outcome.images.clone(),
        );
        log_verbose(&job, &outcome, &report, started.elapsed());
        let retry_in = (!report.ok && attempt <= job.retry_max).then_some(job.retry_wait);
        Some(AttemptReport {
            job_id: job.id.clone(),
            ok: report.ok,
            body: report.body,
            attempt,
            retry_in,
            gave_up: !report.ok && retry_in.is_none() && job.retry_max > 0,
            images: report.images,
        })
    }

    /// The action, then any accepted work polled inline to its terminal outcome.
    async fn drive(
        &self,
        job: &ScheduleJob,
        tools: &ToolRegistry,
        agent: &Arc<dyn AgentHandle>,
        on_waiting: &mut (impl FnMut(String) + Send),
    ) -> ActionOutcome {
        let mut outcome = run_action(job, tools, agent).await;
        let mut prior: Option<PendingWork> = None;
        while let Some(acc) = outcome.accepted.clone() {
            let now = now_unix();
            let p = match prior.take() {
                None => {
                    on_waiting(FireReport::waiting(job, &acc).body);
                    let budget = acc.estimated_seconds.unwrap_or(self.pending_timeout);
                    PendingWork {
                        handle: acc.handle.clone(),
                        poll_with: acc.poll_with.clone(),
                        poll_at: now + self.poll_interval,
                        deadline: now + budget.saturating_mul(2).max(MIN_PENDING_BUDGET),
                        polls: 0,
                    }
                }
                // Same deadline as the first acceptance: repeated polls cannot extend it.
                Some(p) => PendingWork {
                    handle: acc.handle.clone(),
                    poll_with: acc.poll_with.clone(),
                    poll_at: now + self.poll_interval,
                    deadline: p.deadline,
                    polls: p.polls + 1,
                },
            };
            tokio::time::sleep(Duration::from_secs(self.poll_interval)).await;
            prior = Some(p.clone());
            outcome = poll_pending(job, p, tools, agent, self.pending_timeout).await;
        }
        outcome
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Action, CronSchedule};
    use lvz_protocol::{AgentError, Event, Tool, ToolError, ToolOutput, TurnRequest};
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// `server_wake`: behaviour picked by `mode`; `polls` counts `server_wake_result` calls.
    struct Wake(&'static str);
    #[async_trait::async_trait]
    impl Tool for Wake {
        fn name(&self) -> &str {
            "server_wake"
        }
        fn schema(&self) -> serde_json::Value {
            serde_json::json!({"type": "object"})
        }
        async fn invoke(&self, _a: serde_json::Value) -> Result<ToolOutput, ToolError> {
            match self.0 {
                "ok" => Ok(ToolOutput::ok("powered on")),
                "tool_error" => Ok(ToolOutput::error("ATX refused")),
                "pending" => Ok(ToolOutput::pending(
                    "accepted",
                    "h1",
                    "server_wake_result",
                    Some(1),
                )),
                _ => {
                    tokio::time::sleep(Duration::from_secs(5)).await;
                    Ok(ToolOutput::ok("late"))
                }
            }
        }
    }
    struct WakeResult(Arc<AtomicUsize>);
    #[async_trait::async_trait]
    impl Tool for WakeResult {
        fn name(&self) -> &str {
            "server_wake_result"
        }
        fn schema(&self) -> serde_json::Value {
            serde_json::json!({"type": "object"})
        }
        async fn invoke(&self, _a: serde_json::Value) -> Result<ToolOutput, ToolError> {
            if self.0.fetch_add(1, Ordering::SeqCst) == 0 {
                Ok(ToolOutput::pending(
                    "logging in",
                    "h1",
                    "server_wake_result",
                    Some(1),
                ))
            } else {
                Ok(ToolOutput::ok("desktop up").with_image("image/jpeg", "abcd"))
            }
        }
    }
    struct DeadAgent;
    #[async_trait::async_trait]
    impl AgentHandle for DeadAgent {
        async fn submit(
            &self,
            _t: TurnRequest,
        ) -> Result<futures::stream::BoxStream<'static, Result<Event, AgentError>>, AgentError>
        {
            Err(AgentError::Provider("unused".into()))
        }
    }

    fn setup(
        mode: &'static str,
        retry_max: u32,
    ) -> (
        ScheduleRegistry,
        ToolRegistry,
        Arc<dyn AgentHandle>,
        Arc<AtomicUsize>,
    ) {
        let job = ScheduleJob {
            id: "wake".into(),
            expr: "25 10 * * 2".into(),
            schedule: CronSchedule::parse("25 10 * * 2").unwrap(),
            action: Action::Tool {
                name: "server_wake".into(),
                args: serde_json::json!({}),
            },
            room: Some("!ops:hs".into()),
            session: "wake".into(),
            summarize: None,
            retry_max,
            retry_wait: 60,
        };
        let polls = Arc::new(AtomicUsize::new(0));
        let mut tools = ToolRegistry::new();
        tools.register(Arc::new(Wake(mode)));
        tools.register(Arc::new(WakeResult(polls.clone())));
        let reg = ScheduleRegistry::new(vec![job]).with_poll_interval(0);
        (reg, tools, Arc::new(DeadAgent), polls)
    }

    const T: Duration = Duration::from_secs(10);

    #[tokio::test]
    async fn success_reports_once_and_never_retries() {
        let (reg, tools, agent, _) = setup("ok", 3);
        let r = reg
            .run_attempt(0, 1, &tools, &agent, T, |_| panic!("no waiting"))
            .await
            .unwrap();
        assert!(r.ok && r.retry_in.is_none() && !r.gave_up);
        assert_eq!(r.body, "✅ `wake` · powered on");
        assert_eq!(reg.state_of("wake").unwrap().runs, 1);
        assert!(reg
            .run_attempt(0, 0, &tools, &agent, T, |_| {})
            .await
            .is_none());
        assert!(reg
            .run_attempt(9, 1, &tools, &agent, T, |_| {})
            .await
            .is_none());
    }

    #[tokio::test]
    async fn a_tool_error_retries_then_gives_up_like_the_timer_path() {
        let (reg, tools, agent, _) = setup("tool_error", 2);
        let r1 = reg
            .run_attempt(0, 1, &tools, &agent, T, |_| {})
            .await
            .unwrap();
        assert!(!r1.ok);
        assert_eq!(r1.retry_in, Some(60));
        assert!(r1.body.starts_with("❌ `wake` failed (attempt 1)"));
        assert!(r1.body.ends_with("↻ retry 1/2 in 60s"));
        // The caller numbers attempts; a fresh process (counter 0) still reports attempt 3.
        let (reg, tools, agent, _) = setup("tool_error", 2);
        let r3 = reg
            .run_attempt(0, 3, &tools, &agent, T, |_| {})
            .await
            .unwrap();
        assert_eq!((r3.attempt, r3.retry_in, r3.gave_up), (3, None, true));
        assert!(
            r3.body.contains("failed (attempt 3)")
                && r3.body.ends_with("⛔ gave up after 2 retries")
        );
        let (reg, tools, agent, _) = setup("tool_error", 0);
        let r = reg
            .run_attempt(0, 1, &tools, &agent, T, |_| {})
            .await
            .unwrap();
        assert_eq!((r.retry_in, r.gave_up), (None, false));
    }

    #[tokio::test]
    async fn accepted_work_is_polled_inline_and_waiting_is_sent_once() {
        let (reg, tools, agent, polls) = setup("pending", 3);
        let mut waiting = Vec::new();
        let r = reg
            .run_attempt(0, 1, &tools, &agent, T, |w| waiting.push(w))
            .await
            .unwrap();
        assert_eq!(waiting.len(), 1);
        assert!(waiting[0].starts_with("⏳ `wake` · started, waiting on `server_wake_result`"));
        assert!(r.ok && r.body.contains("desktop up"));
        assert_eq!(r.images.len(), 1);
        assert_eq!(polls.load(Ordering::SeqCst), 2);
        assert!(reg.state_of("wake").unwrap().pending.is_none());
    }

    #[tokio::test]
    async fn the_jobs_timeout_is_a_retryable_failure() {
        let (reg, tools, agent, _) = setup("slow", 1);
        let r = reg
            .run_attempt(0, 1, &tools, &agent, Duration::from_millis(50), |_| {})
            .await
            .unwrap();
        assert!(!r.ok && r.retry_in == Some(60));
        assert!(r.body.contains("did not finish within the jobs timeout"));
    }
}
