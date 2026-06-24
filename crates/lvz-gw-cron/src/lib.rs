//! `lvz-gw-cron` — a cron-scheduled gateway for the shared agent.
//!
//! A [`Gateway`] whose "channel" is *time*: it holds a set of [`CronJob`]s and, for each,
//! sleeps until the job's next fire (UTC), submits a [`TurnRequest`] to the shared
//! [`AgentHandle`], drains the resulting [`Event`] stream, and logs the outcome. Jobs run
//! concurrently on one task (no `tokio::spawn`), so the gateway is cheap to host alongside the
//! HTTP/Matrix gateways under `--serve` in a low-resource environment.
//!
//! Like the other `lvz-gw-*` crates it depends only on [`lvz_protocol`]; the agent core stays
//! unaware that a scheduler is driving it. Each job keeps a fixed `session`, so [`lvz-memory`]
//! gives a job continuity across fires (the same way the Matrix gateway keys a session per
//! room). The cron engine itself is in [`cron`].

mod cron;

use std::sync::Arc;

use async_trait::async_trait;
use futures::stream::StreamExt;
use lvz_protocol::{AgentHandle, Event, Gateway, GatewayError, TurnRequest};
use serde::Deserialize;

pub use cron::{CronError, CronSchedule};

/// One scheduled task: when to fire, which session to run it under, and the prompt to submit.
#[derive(Debug, Clone)]
pub struct CronJob {
    /// Parsed cron schedule (UTC).
    pub schedule: CronSchedule,
    /// Session id — fixed across fires so the job accrues memory/continuity.
    pub session: String,
    /// The prompt submitted to the agent on each fire.
    pub prompt: String,
    /// Max retries after a *failed* fire (submit error or mid-turn stream error), before giving up
    /// and waiting for the next scheduled slot. `0` ⇒ no retry (single-shot, the prior behaviour).
    pub retry_max: u32,
    /// Seconds to wait between retries (fixed delay). Ignored when `retry_max == 0`.
    pub retry_wait: u64,
}

/// JSON shape for a job in a `--cron-file` document:
/// `{"schedule","session"?,"prompt","retry_max"?,"retry_wait"?}`. A per-job `retry_max`/`retry_wait`
/// overrides the global default passed to [`CronJob::parse_file`].
#[derive(Debug, Deserialize)]
struct JobSpec {
    schedule: String,
    #[serde(default)]
    session: Option<String>,
    prompt: String,
    #[serde(default)]
    retry_max: Option<u32>,
    #[serde(default)]
    retry_wait: Option<u64>,
}

/// A failure building cron jobs from CLI/file input.
#[derive(Debug, thiserror::Error)]
pub enum CronConfigError {
    /// A cron expression failed to parse.
    #[error("{0}")]
    Cron(#[from] CronError),
    /// A `--cron` quick spec lacked a prompt after its 5 schedule fields.
    #[error("cron spec has no prompt after the 5 schedule fields: {0:?}")]
    MissingPrompt(String),
    /// The `--cron-file` JSON was malformed.
    #[error("cron file parse error: {0}")]
    Json(String),
}

impl CronJob {
    /// Build a job directly from parts, with no retries (single-shot per fire).
    pub fn new(
        schedule: CronSchedule,
        session: impl Into<String>,
        prompt: impl Into<String>,
    ) -> Self {
        Self {
            schedule,
            session: session.into(),
            prompt: prompt.into(),
            retry_max: 0,
            retry_wait: 0,
        }
    }

    /// Set the retry policy (max retries after a failed fire + fixed wait, in seconds) for this job.
    pub fn with_retries(mut self, retry_max: u32, retry_wait: u64) -> Self {
        self.retry_max = retry_max;
        self.retry_wait = retry_wait;
        self
    }

    /// Parse a quick CLI spec: the first **five** whitespace-separated tokens are the cron
    /// schedule, the remainder is the prompt. `index` seeds the default session id
    /// (`cron-<index>`) so multiple `--cron` flags don't share memory by accident. `retry_max`/
    /// `retry_wait` are the global retry defaults (a quick spec carries no inline retry policy).
    ///
    /// Example: `"*/30 * * * * summarise new issues and post a digest"`.
    pub fn parse_cli(
        spec: &str,
        index: usize,
        retry_max: u32,
        retry_wait: u64,
    ) -> Result<Self, CronConfigError> {
        let toks: Vec<&str> = spec.split_whitespace().collect();
        if toks.len() < 6 {
            return Err(CronConfigError::MissingPrompt(spec.to_string()));
        }
        let schedule = CronSchedule::parse(&toks[..5].join(" "))?;
        let prompt = toks[5..].join(" ");
        Ok(
            Self::new(schedule, format!("cron-{index}"), prompt)
                .with_retries(retry_max, retry_wait),
        )
    }

    /// Parse a `--cron-file` JSON document: an array of
    /// `{schedule, session?, prompt, retry_max?, retry_wait?}`. A missing `session` defaults to
    /// `cron-<index>`; a missing `retry_max`/`retry_wait` falls back to the global default args.
    pub fn parse_file(
        json: &str,
        retry_max: u32,
        retry_wait: u64,
    ) -> Result<Vec<Self>, CronConfigError> {
        let specs: Vec<JobSpec> =
            serde_json::from_str(json).map_err(|e| CronConfigError::Json(e.to_string()))?;
        specs
            .into_iter()
            .enumerate()
            .map(|(i, s)| {
                Ok(Self::new(
                    CronSchedule::parse(&s.schedule)?,
                    s.session.unwrap_or_else(|| format!("cron-{i}")),
                    s.prompt,
                )
                .with_retries(
                    s.retry_max.unwrap_or(retry_max),
                    s.retry_wait.unwrap_or(retry_wait),
                ))
            })
            .collect()
    }
}

/// The cron gateway: drives the shared agent from a set of [`CronJob`]s.
pub struct CronGateway {
    jobs: Vec<CronJob>,
}

impl CronGateway {
    /// Construct from the jobs to run. An empty set makes [`serve`](Gateway::serve) return
    /// immediately.
    pub fn new(jobs: Vec<CronJob>) -> Self {
        Self { jobs }
    }

    /// Number of scheduled jobs.
    pub fn len(&self) -> usize {
        self.jobs.len()
    }

    /// True when no jobs are scheduled.
    pub fn is_empty(&self) -> bool {
        self.jobs.is_empty()
    }
}

#[async_trait]
impl Gateway for CronGateway {
    fn name(&self) -> &str {
        "cron"
    }

    async fn serve(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError> {
        if self.jobs.is_empty() {
            return Ok(());
        }
        for job in &self.jobs {
            match job.schedule.next_after_now() {
                Some(_) => eprintln!(
                    "lavoisier[cron]: scheduled session={:?} — {}",
                    job.session, job.prompt
                ),
                None => eprintln!(
                    "lavoisier[cron]: WARNING session={:?} never fires (impossible schedule) — skipping",
                    job.session
                ),
            }
        }
        // Drive every job concurrently on this one task; each loops forever, so join_all only
        // returns if every job has self-disabled (no future fire).
        let runs = self.jobs.iter().map(|job| run_job(job, agent.clone()));
        futures::future::join_all(runs).await;
        Ok(())
    }
}

/// Loop a single job: wait for its next fire, run a turn (with retries on failure), log the
/// result, repeat. Returns when the schedule has no further fire (so an impossible schedule
/// disables just that job).
///
/// The next scheduled slot is always recomputed from "now" *after* any retries finish, so a
/// retry's wait can never bleed into — or double-fire against — the following slot.
async fn run_job(job: &CronJob, agent: Arc<dyn AgentHandle>) {
    loop {
        let now = now_unix();
        let Some(next) = job.schedule.next_after(now) else {
            return;
        };
        let wait = next.saturating_sub(now);
        tokio::time::sleep(std::time::Duration::from_secs(wait)).await;

        // Fire, then retry up to `retry_max` times on failure with a fixed `retry_wait`.
        let mut attempt = 0u32;
        loop {
            if fire(job, &agent).await {
                break;
            }
            if attempt >= job.retry_max {
                if job.retry_max > 0 {
                    eprintln!(
                        "lavoisier[cron]: session={:?} gave up after {} retr{}",
                        job.session,
                        job.retry_max,
                        if job.retry_max == 1 { "y" } else { "ies" }
                    );
                }
                break;
            }
            attempt += 1;
            eprintln!(
                "lavoisier[cron]: session={:?} retry {attempt}/{} in {}s",
                job.session, job.retry_max, job.retry_wait
            );
            tokio::time::sleep(std::time::Duration::from_secs(job.retry_wait)).await;
        }
    }
}

/// Run one turn for `job` and log the assistant's final text + token usage. Returns `true` on a
/// clean turn, `false` on a failure worth retrying (the submit was rejected, or the event stream
/// errored mid-turn) — a completed turn is a success even if its answer is unsatisfying, since
/// that's semantic and not knowable here.
async fn fire(job: &CronJob, agent: &Arc<dyn AgentHandle>) -> bool {
    let turn = TurnRequest::new(job.session.clone(), job.prompt.clone());
    let mut stream = match agent.submit(turn).await {
        Ok(s) => s,
        Err(e) => {
            eprintln!(
                "lavoisier[cron]: session={:?} submit failed: {e}",
                job.session
            );
            return false;
        }
    };

    let mut answer = String::new();
    let mut usage = None;
    // Track tool activity so the operator can see the job actually *did* work (ran tools), not
    // just produced text — cron turns drive the same tool-using agent loop as every other gateway.
    let mut tools: Vec<String> = Vec::new();
    let mut ok = true;
    while let Some(item) = stream.next().await {
        match item {
            Ok(Event::TextDelta(t)) => answer.push_str(&t),
            Ok(Event::Usage(u)) => usage = Some(u),
            Ok(Event::ToolUseStart { name, .. }) => tools.push(name),
            Ok(Event::Done(_)) => {}
            Ok(_) => {}
            Err(e) => {
                eprintln!(
                    "lavoisier[cron]: session={:?} stream error: {e}",
                    job.session
                );
                ok = false;
                break;
            }
        }
    }

    let toks = usage
        .map(|u| {
            format!(
                " [in {} / out {} / cache_read {}]",
                u.input_tokens, u.output_tokens, u.cache_read_tokens
            )
        })
        .unwrap_or_default();
    let tools_note = if tools.is_empty() {
        String::new()
    } else {
        format!(" [tools: {}]", tools.join(", "))
    };
    eprintln!(
        "lavoisier[cron]: session={:?} fired{toks}{tools_note}: {}",
        job.session,
        answer.trim()
    );
    ok
}

fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_cli_splits_schedule_from_prompt() {
        let j =
            CronJob::parse_cli("*/30 9-17 * * 1-5 check CI and report failures", 2, 0, 0).unwrap();
        assert_eq!(j.session, "cron-2");
        assert_eq!(j.prompt, "check CI and report failures");
    }

    #[test]
    fn parse_cli_requires_a_prompt() {
        assert!(matches!(
            CronJob::parse_cli("* * * * *", 0, 0, 0),
            Err(CronConfigError::MissingPrompt(_))
        ));
    }

    #[test]
    fn parse_cli_rejects_bad_schedule() {
        assert!(CronJob::parse_cli("99 * * * * do a thing", 0, 0, 0).is_err());
    }

    #[test]
    fn parse_cli_applies_global_retry_defaults() {
        let j = CronJob::parse_cli("* * * * * ping", 0, 3, 30).unwrap();
        assert_eq!(j.retry_max, 3);
        assert_eq!(j.retry_wait, 30);
    }

    #[test]
    fn parse_file_reads_jobs_with_session_defaults() {
        let json = r#"[
            {"schedule": "0 9 * * *", "session": "digest", "prompt": "morning digest"},
            {"schedule": "*/15 * * * *", "prompt": "poll the queue"}
        ]"#;
        let jobs = CronJob::parse_file(json, 0, 0).unwrap();
        assert_eq!(jobs.len(), 2);
        assert_eq!(jobs[0].session, "digest");
        assert_eq!(jobs[1].session, "cron-1"); // defaulted
        assert_eq!(jobs[1].prompt, "poll the queue");
    }

    #[test]
    fn parse_file_retry_per_job_overrides_global_default() {
        let json = r#"[
            {"schedule": "0 9 * * *", "prompt": "uses defaults"},
            {"schedule": "0 9 * * *", "prompt": "overrides", "retry_max": 5, "retry_wait": 120}
        ]"#;
        let jobs = CronJob::parse_file(json, 2, 60).unwrap();
        // Job 0 inherits the global defaults; job 1 overrides both.
        assert_eq!((jobs[0].retry_max, jobs[0].retry_wait), (2, 60));
        assert_eq!((jobs[1].retry_max, jobs[1].retry_wait), (5, 120));
    }

    #[test]
    fn parse_file_surfaces_bad_schedule() {
        let json = r#"[{"schedule": "bad", "prompt": "x"}]"#;
        assert!(CronJob::parse_file(json, 0, 0).is_err());
    }

    #[test]
    fn empty_gateway_is_empty() {
        assert!(CronGateway::new(vec![]).is_empty());
    }
}
