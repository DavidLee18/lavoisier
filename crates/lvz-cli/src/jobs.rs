//! `--serve-jobs`: the [`JobRunner`] behind `POST /v1/jobs/{id}`, over the same
//! [`ScheduleRegistry`], tool registry and agent the Matrix scheduler would use.
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use lvz_gw_http::jobs::{JobRejection, JobReport, JobRequest, JobRunner};
use lvz_protocol::AgentHandle;
use lvz_schedule::ScheduleRegistry;
use lvz_tools::ToolRegistry;

/// Runs one attempt of a schedule job per request.
pub(crate) struct ScheduleJobRunner {
    schedule: Arc<ScheduleRegistry>,
    tools: ToolRegistry,
    agent: Arc<dyn AgentHandle>,
    timeout: Duration,
}

impl ScheduleJobRunner {
    pub(crate) fn new(
        schedule: Arc<ScheduleRegistry>,
        tools: ToolRegistry,
        agent: Arc<dyn AgentHandle>,
        timeout: Duration,
    ) -> Self {
        Self {
            schedule,
            tools,
            agent,
            timeout,
        }
    }
}

#[async_trait]
impl JobRunner for ScheduleJobRunner {
    fn validate(&self, job: &str, req: &JobRequest) -> Result<(), JobRejection> {
        let idx = self
            .schedule
            .index_of(job)
            .ok_or(JobRejection::UnknownJob)?;
        let j = &self.schedule.jobs()[idx];
        if !j.schedule.matches_at(req.scheduled_minute) {
            return Err(JobRejection::Invalid(
                "not_a_slot",
                format!(
                    "{} is not a slot of `{}` ({}, UTC)",
                    req.scheduled_minute, j.id, j.expr
                ),
            ));
        }
        let max = j.retry_max.saturating_add(1);
        if req.attempt == 0 || req.attempt > max {
            return Err(JobRejection::Invalid(
                "bad_attempt",
                format!("attempt must be 1..={max} for `{}`", j.id),
            ));
        }
        Ok(())
    }

    async fn run(
        &self,
        job: &str,
        req: &JobRequest,
        waiting: Box<dyn FnMut(String) + Send>,
    ) -> Result<JobReport, String> {
        let idx = self
            .schedule
            .index_of(job)
            .ok_or_else(|| format!("no job {job}"))?;
        tracing::info!(job, minute = req.scheduled_minute, attempt = req.attempt,
            key = %req.idempotency_key, "job attempt requested");
        let r = self
            .schedule
            .run_attempt(
                idx,
                req.attempt,
                &self.tools,
                &self.agent,
                self.timeout,
                waiting,
            )
            .await
            .ok_or_else(|| format!("job {job} attempt {} not runnable", req.attempt))?;
        Ok(JobReport {
            ok: r.ok,
            body: r.body,
            attempt: r.attempt,
            retry_in_s: r.retry_in,
            gave_up: r.gave_up,
            images: r.images.len(),
        })
    }

    async fn cancel(&self, job: &str, _key: &str) {
        lvz_schedule::cancel_attempt(job);
    }
}

/// `POST /v1/admin/recover` → the process job table.
pub(crate) struct LeaseHook;

/// `GET /v1/sessions/{session}/trace` over the installed trace store.
pub(crate) struct TraceBridge;

impl lvz_gw_http::TraceRead for TraceBridge {
    fn read(&self, session: &str, last: usize) -> Vec<serde_json::Value> {
        lvz_agent::trace::read_installed(session, last)
    }
}

/// `GET /v1/outbox` over the agent's durable outbox.
pub(crate) struct OutboxBridge(lvz_agent::outbox::Outbox);

impl lvz_gw_http::OutboxRead for OutboxBridge {
    fn since(&self, after: u64) -> Vec<lvz_gw_http::OutRecord> {
        self.0
            .since(after)
            .into_iter()
            .map(|item| lvz_gw_http::OutRecord {
                seq: item.seq,
                body: serde_json::json!({
                    "seq": item.seq,
                    "session": item.session,
                    "kind": item.kind,
                    "text": item.text,
                    "images": item.images,
                }),
            })
            .collect()
    }

    fn ack(&self, seq: u64) {
        self.0.ack(seq);
    }

    fn poke(&self) -> std::sync::Arc<tokio::sync::Notify> {
        self.0.poke()
    }
}

/// Open the outbox, and deliver each finished detached job as a continuation turn.
///
/// `None` when the directory cannot be created. The turn still returns early; the reply
/// stays in the job table until a later process can write the outbox.
pub(crate) fn arm_detached(
    config: &crate::Config,
    agent: std::sync::Arc<dyn lvz_protocol::AgentHandle>,
) -> Option<std::sync::Arc<dyn lvz_gw_http::OutboxRead>> {
    let dir = config
        .memory
        .path
        .clone()
        .unwrap_or_else(|| std::path::PathBuf::from(".lavoisier"));
    let outbox = match lvz_agent::outbox::Outbox::open_local(&dir) {
        Ok(outbox) => outbox,
        Err(err) => {
            tracing::error!(error = %err, "detached outbox did not open");
            return None;
        }
    };
    lvz_agent::jobs::global().set_detached(true);
    let hook_box = outbox.clone();
    lvz_agent::jobs::global().set_terminal_hook(std::sync::Arc::new(move |session, text| {
        let agent = agent.clone();
        let outbox = hook_box.clone();
        let session = session.to_string();
        let text = text.to_string();
        if let Ok(runtime) = tokio::runtime::Handle::try_current() {
            runtime.spawn(async move {
                deliver(agent, outbox, session, text).await;
            });
        }
    }));
    Some(std::sync::Arc::new(OutboxBridge(outbox)))
}

async fn deliver(
    agent: std::sync::Arc<dyn lvz_protocol::AgentHandle>,
    outbox: lvz_agent::outbox::Outbox,
    session: String,
    raw: String,
) {
    use futures::StreamExt;
    let turn = lvz_protocol::TurnRequest::new(session.clone(), raw.clone()).with_origin(
        lvz_protocol::Origin::Job {
            id: session.clone(),
        },
    );
    let mut reply = String::new();
    let mut failed = false;
    match agent.submit(turn).await {
        Ok(mut stream) => {
            while let Some(event) = stream.next().await {
                match event {
                    Ok(lvz_protocol::Event::TextDelta(text)) => reply.push_str(&text),
                    Err(_) => {
                        failed = true;
                        break;
                    }
                    _ => {}
                }
            }
        }
        Err(_) => failed = true,
    }
    if failed || reply.trim().is_empty() {
        reply = raw;
    }
    outbox.publish(session, reply);
}

impl lvz_gw_http::LeaseRecover for LeaseHook {
    fn recover(
        &self,
        lease_generation: u64,
    ) -> Result<lvz_gw_http::RecoverReport, lvz_gw_http::RecoverRefuse> {
        match lvz_agent::jobs::adopt(lease_generation) {
            Ok(lvz_agent::jobs::Adopted::Recovered { jobs }) => {
                Ok(lvz_gw_http::RecoverReport::Recovered { jobs })
            }
            Ok(lvz_agent::jobs::Adopted::Already) => {
                Ok(lvz_gw_http::RecoverReport::AlreadyRecovered)
            }
            Err(lvz_agent::jobs::AdoptErr::Stale { .. }) => {
                Err(lvz_gw_http::RecoverRefuse::StaleLease)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;
    use lvz_protocol::{AgentError, Event, TurnRequest};

    const SCHEDULE: &str = r#"[{"id":"wake","schedule":"25 10 * * 2","room":"!ops:hs","tool":"no_such_tool","args":{}}]"#;

    fn schedule_file() -> std::path::PathBuf {
        // Unique per call: a pid-only path is shared by every test in the process, so a
        // parallel `std::fs::write` can truncate the file while another test is mid-parse
        // and yield `Json("EOF while parsing a value at line 1 column 0")`.
        static N: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let p = std::env::temp_dir().join(format!("lvz-jobs-{}-{n}.json", std::process::id()));
        std::fs::write(&p, SCHEDULE).expect("write schedule fixture");
        p
    }

    fn cli(extra: &[&str]) -> crate::Cli {
        let f = schedule_file();
        let mut args = vec!["lav", "--schedule-file", f.to_str().unwrap()];
        args.extend_from_slice(extra);
        crate::Cli::parse_from(args)
    }

    #[test]
    fn serve_jobs_flag_rules() {
        let ok = crate::build_schedule(&cli(&["--serve", "127.0.0.1:8090", "--serve-jobs"]));
        let jobs = ok.unwrap_or_else(|e| {
            panic!("--serve --serve-jobs should load the one-job fixture, got {e}")
        });
        assert_eq!(
            jobs.expect("--serve-jobs with a non-empty schedule returns Some")
                .len(),
            1
        );
        let both = crate::build_schedule(&cli(&[
            "--serve",
            "127.0.0.1:8090",
            "--serve-jobs",
            "--serve-matrix",
        ]));
        assert!(both.unwrap_err().to_string().contains("cannot be combined"));
        let no_http = crate::build_schedule(&cli(&["--serve-jobs"]));
        assert!(no_http
            .unwrap_err()
            .to_string()
            .contains("requires --serve"));
        let neither = crate::build_schedule(&cli(&["--serve", "127.0.0.1:8090"]));
        assert!(neither
            .unwrap_err()
            .to_string()
            .contains("--serve-matrix or --serve-jobs"));
        let no_file = crate::build_schedule(&crate::Cli::parse_from([
            "lav",
            "--serve",
            "x:1",
            "--serve-jobs",
        ]));
        assert!(no_file
            .unwrap_err()
            .to_string()
            .contains("requires --schedule-file"));
    }

    #[test]
    fn jobs_mode_leaves_out_schedule_run() {
        let jobs = lvz_schedule::ScheduleJob::parse_file(SCHEDULE, 0, 0).unwrap();
        let reg = Arc::new(ScheduleRegistry::new(jobs));
        let names = |c: &crate::Cli| -> Vec<String> {
            crate::build_tool_registry(c, None, "m".into(), &[], Some(&reg), false)
                .defs()
                .into_iter()
                .map(|d| d.name)
                .collect()
        };
        let jobs_mode = names(&cli(&["--serve", "127.0.0.1:8090", "--serve-jobs"]));
        assert!(jobs_mode.contains(&"schedule_status".to_string()));
        assert!(!jobs_mode.contains(&"schedule_run".to_string()));
        assert!(names(&cli(&["--serve-matrix"])).contains(&"schedule_run".to_string()));
    }

    struct DeadAgent;
    #[async_trait]
    impl AgentHandle for DeadAgent {
        async fn submit(
            &self,
            _t: TurnRequest,
        ) -> Result<futures::stream::BoxStream<'static, Result<Event, AgentError>>, AgentError>
        {
            Err(AgentError::Provider("unused".into()))
        }
    }

    #[tokio::test]
    async fn runner_validates_and_runs_one_attempt() {
        let jobs = lvz_schedule::ScheduleJob::parse_file(SCHEDULE, 2, 60).unwrap();
        let r = ScheduleJobRunner::new(
            Arc::new(ScheduleRegistry::new(jobs)),
            ToolRegistry::new(),
            Arc::new(DeadAgent),
            Duration::from_secs(5),
        );
        let req = |m: u64, attempt: u32| JobRequest {
            scheduled_minute: m,
            idempotency_key: "k".into(),
            attempt,
        };
        let slot = 1_794_306_300; // Tue 2026-11-10 10:25 UTC
        assert_eq!(
            r.validate("nope", &req(slot, 1)),
            Err(JobRejection::UnknownJob)
        );
        assert!(matches!(
            r.validate("wake", &req(slot + 60, 1)),
            Err(JobRejection::Invalid("not_a_slot", _))
        ));
        assert!(matches!(
            r.validate("wake", &req(slot, 4)),
            Err(JobRejection::Invalid("bad_attempt", _))
        ));
        assert!(matches!(
            r.validate("wake", &req(slot, 0)),
            Err(JobRejection::Invalid("bad_attempt", _))
        ));
        assert_eq!(r.validate("wake", &req(slot, 3)), Ok(()));
        let rep = r
            .run("wake", &req(slot, 1), Box::new(|_| {}))
            .await
            .unwrap();
        assert!(!rep.ok, "an unknown tool is a failed attempt");
        assert_eq!(
            (rep.attempt, rep.retry_in_s, rep.gave_up),
            (1, Some(60), false)
        );
        let last = r
            .run("wake", &req(slot, 3), Box::new(|_| {}))
            .await
            .unwrap();
        assert_eq!((last.retry_in_s, last.gave_up), (None, true));
        assert!(last.body.contains("⛔"));
    }
}
