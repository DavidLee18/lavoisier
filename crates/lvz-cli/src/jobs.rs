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
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;
    use lvz_protocol::{AgentError, Event, TurnRequest};

    const SCHEDULE: &str = r#"[{"id":"wake","schedule":"25 10 * * 2","room":"!ops:hs","tool":"no_such_tool","args":{}}]"#;

    fn schedule_file() -> std::path::PathBuf {
        let p = std::env::temp_dir().join(format!("lvz-jobs-{}.json", std::process::id()));
        std::fs::write(&p, SCHEDULE).unwrap();
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
        assert_eq!(ok.unwrap().unwrap().len(), 1);
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
            crate::build_tool_registry(c, None, "m".into(), &[], Some(&reg))
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
