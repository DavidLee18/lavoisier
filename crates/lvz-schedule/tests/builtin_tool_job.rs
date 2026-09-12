//! End-to-end check of the feature's headline claim: a scheduled `tool` job runs a **real
//! built-in tool, unconditionally, with no model in the loop**.
//!
//! The agent handle here always rejects `submit`, so if any part of the path reached for the model
//! the test would fail — success proves the tool executed on its own.

use std::sync::Arc;

use futures::stream::BoxStream;
use lvz_protocol::{AgentError, AgentHandle, Event, TurnRequest};
use lvz_schedule::{Action, CronSchedule, ScheduleJob, ScheduleRegistry};
use lvz_tools::ToolRegistry;

/// An agent that refuses every turn — proof that the tool path never consults the model.
struct NeverAgent;

#[async_trait::async_trait]
impl AgentHandle for NeverAgent {
    async fn submit(
        &self,
        _turn: TurnRequest,
    ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError> {
        Err(AgentError::Provider(
            "the scheduler must not call the model for a tool job".into(),
        ))
    }
}

fn job(id: &str, command: &str) -> ScheduleJob {
    ScheduleJob {
        id: id.to_string(),
        expr: "* * * * *".to_string(),
        schedule: CronSchedule::parse("* * * * *").unwrap(),
        action: Action::Tool {
            name: "shell".into(),
            args: serde_json::json!({ "command": command }),
        },
        room: None,
        session: format!("schedule-{id}"),
        summarize: None,
        retry_max: 0,
        retry_wait: 0,
    }
}

#[tokio::test]
async fn scheduled_tool_job_runs_a_real_shell_command() {
    let tools = ToolRegistry::with_builtins();
    let agent: Arc<dyn AgentHandle> = Arc::new(NeverAgent);
    let reg = ScheduleRegistry::new(vec![job("greet", "echo scheduled-hello")]);

    let report = reg.fire(0, &tools, &agent).await.expect("job exists");

    assert!(report.ok, "expected success, got: {}", report.body);
    assert!(report.body.starts_with("✅ `greet`"));
    assert!(report.body.contains("scheduled-hello"));
    assert_eq!(report.attempt, 1);

    let state = reg.state_of("greet").unwrap();
    assert_eq!((state.runs, state.failures), (1, 0));
    assert_eq!(state.last_ok, Some(true));
    // The chain resolved, so the next cron slot is armed again.
    assert!(state.next_due.is_some());
    assert!(state.retry_at.is_none());
}

#[tokio::test]
async fn a_nonzero_exit_is_a_failure_and_schedules_a_retry() {
    let tools = ToolRegistry::with_builtins();
    let agent: Arc<dyn AgentHandle> = Arc::new(NeverAgent);
    let mut j = job("failing", "exit 3");
    j.retry_max = 1;
    j.retry_wait = 45;
    let reg = ScheduleRegistry::new(vec![j]);

    let report = reg.fire(0, &tools, &agent).await.expect("job exists");

    assert!(!report.ok, "a non-zero exit must count as a failed fire");
    assert!(report.body.starts_with("❌ `failing` failed (attempt 1)"));
    assert!(report.body.contains("↻ retry 1/1 in 45s"));

    // While the retry is pending the cron slot is suppressed, so the retry can't race it.
    let state = reg.state_of("failing").unwrap();
    assert!(state.retry_at.is_some());
    assert!(state.next_due.is_none());
    assert_eq!(state.consecutive_failures, 1);
}
