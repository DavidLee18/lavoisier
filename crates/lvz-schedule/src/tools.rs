//! The chat surface for schedules, as agent tools.
//!
//! Making these **tools** rather than `!commands` is what lets the schedule be *talked about*: the
//! model answers "how's the backup job doing?" by calling [`ScheduleStatusTool`] and "run it again"
//! by calling [`ScheduleRunTool`], in whatever words the user actually used. They compose with the
//! Matrix gateway's existing mention/reply gate for free.
//!
//! All three are read-mostly and cheap: they never touch the model, and [`ScheduleRunTool`]
//! *queues* a run rather than executing it inline — the scheduler owns firing, so a job can't be
//! re-entered from inside a turn it triggered, and the outcome still lands in the room as a normal
//! report.

use std::sync::Arc;

use async_trait::async_trait;
use lvz_protocol::{Tool, ToolError, ToolOutput};
use serde_json::{json, Value};

use crate::{JobState, ScheduleRegistry};

/// Render a unix timestamp as a relative, human phrase ("in 4m", "2h ago"). Relative beats
/// absolute here: the model is answering conversationally, and it avoids implying a timezone the
/// scheduler doesn't have (everything is UTC).
fn relative(at: u64, now: u64) -> String {
    let (delta, suffix, prefix) = if at >= now {
        (at - now, "", "in ")
    } else {
        (now - at, " ago", "")
    };
    let unit = match delta {
        0 => "now".to_string(),
        1..=89 => format!("{delta}s"),
        90..=5399 => format!("{}m", delta / 60),
        5400..=172_799 => format!("{}h", delta / 3600),
        _ => format!("{}d", delta / 86_400),
    };
    if unit == "now" {
        "now".to_string()
    } else {
        format!("{prefix}{unit}{suffix}")
    }
}

fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// One line summarising a job's health, shared by list and status.
fn health_line(state: &JobState, now: u64) -> String {
    let last = match (state.last_fired, state.last_ok) {
        (Some(at), Some(true)) => format!("last ✅ {}", relative(at, now)),
        (Some(at), Some(false)) => format!("last ❌ {}", relative(at, now)),
        _ => "never run".to_string(),
    };
    let next = match (state.retry_at, state.next_due) {
        (Some(at), _) => format!("retry {}", relative(at, now)),
        (None, Some(at)) => format!("next {}", relative(at, now)),
        (None, None) => "not scheduled".to_string(),
    };
    let streak = if state.consecutive_failures > 1 {
        format!(", {} consecutive failures", state.consecutive_failures)
    } else {
        String::new()
    };
    format!(
        "{last}, {next}, {} run(s)/{} failure(s){streak}",
        state.runs, state.failures
    )
}

/// `schedule_list` — every job, its schedule, and its current health.
pub struct ScheduleListTool {
    registry: Arc<ScheduleRegistry>,
}

impl ScheduleListTool {
    pub fn new(registry: Arc<ScheduleRegistry>) -> Self {
        Self { registry }
    }
}

#[async_trait]
impl Tool for ScheduleListTool {
    fn name(&self) -> &str {
        "schedule_list"
    }

    fn description(&self) -> &str {
        "List the scheduled jobs this agent runs, with each job's cron schedule, what it does, \
         when it next runs, and whether its last run succeeded. Use this to answer questions \
         about what is scheduled or which jobs are failing."
    }

    fn schema(&self) -> Value {
        json!({"type": "object", "properties": {}, "additionalProperties": false})
    }

    async fn invoke(&self, _args: Value) -> Result<ToolOutput, ToolError> {
        if self.registry.is_empty() {
            return Ok(ToolOutput::ok("No jobs are scheduled."));
        }
        let now = now_unix();
        let mut out = String::new();
        for job in self.registry.jobs() {
            let state = self.registry.state_of(&job.id).unwrap_or_default();
            out.push_str(&format!(
                "- {} [{}] {} — {}\n",
                job.id,
                job.expr,
                job.action.summary(),
                health_line(&state, now)
            ));
        }
        Ok(ToolOutput::ok(out.trim_end()))
    }
}

/// `schedule_status` — one job in detail, including recent history.
pub struct ScheduleStatusTool {
    registry: Arc<ScheduleRegistry>,
}

impl ScheduleStatusTool {
    pub fn new(registry: Arc<ScheduleRegistry>) -> Self {
        Self { registry }
    }
}

#[async_trait]
impl Tool for ScheduleStatusTool {
    fn name(&self) -> &str {
        "schedule_status"
    }

    fn description(&self) -> &str {
        "Get the detailed status of one scheduled job by id: its schedule, next run, success and \
         failure counts, and its recent run history with output or error text. Use this when \
         asked how a specific job is doing or why it failed."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "The job id, as shown by schedule_list."}
            },
            "required": ["id"],
            "additionalProperties": false
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let id = args
            .get("id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| ToolError::InvalidArgs("missing `id`".into()))?;
        let Some(idx) = self.registry.index_of(id) else {
            let known: Vec<&str> = self.registry.jobs().iter().map(|j| j.id.as_str()).collect();
            return Ok(ToolOutput::error(format!(
                "No scheduled job with id {id:?}. Known jobs: {}",
                if known.is_empty() {
                    "(none)".to_string()
                } else {
                    known.join(", ")
                }
            )));
        };
        let job = &self.registry.jobs()[idx];
        let state = self.registry.state_of(id).unwrap_or_default();
        let now = now_unix();

        let mut out = format!(
            "{} [{}] {}\nroom: {}\n{}\n",
            job.id,
            job.expr,
            job.action.summary(),
            job.room.as_deref().unwrap_or("(default)"),
            health_line(&state, now),
        );
        if job.retry_max > 0 {
            out.push_str(&format!(
                "retry policy: up to {} retr{}, {}s apart\n",
                job.retry_max,
                if job.retry_max == 1 { "y" } else { "ies" },
                job.retry_wait
            ));
        }
        if state.history.is_empty() {
            out.push_str("\nNo runs recorded yet.");
        } else {
            out.push_str("\nrecent runs (newest first):\n");
            for o in state.history.iter().rev() {
                out.push_str(&format!(
                    "- {} {} (attempt {}): {}\n",
                    if o.ok { "✅" } else { "❌" },
                    relative(o.at, now),
                    o.attempt,
                    o.detail
                ));
            }
        }
        Ok(ToolOutput::ok(out.trim_end()))
    }
}

/// `schedule_run` — fire a job now, out of band.
pub struct ScheduleRunTool {
    registry: Arc<ScheduleRegistry>,
}

impl ScheduleRunTool {
    pub fn new(registry: Arc<ScheduleRegistry>) -> Self {
        Self { registry }
    }
}

#[async_trait]
impl Tool for ScheduleRunTool {
    fn name(&self) -> &str {
        "schedule_run"
    }

    fn description(&self) -> &str {
        "Run a scheduled job immediately, without waiting for its next slot — use this when asked \
         to retry or re-run a job. The run happens in the background and its result is reported \
         separately, so report that the run was started rather than claiming its outcome."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "The job id, as shown by schedule_list."}
            },
            "required": ["id"],
            "additionalProperties": false
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let id = args
            .get("id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| ToolError::InvalidArgs("missing `id`".into()))?;
        if self.registry.request_run(id) {
            Ok(ToolOutput::ok(format!(
                "Queued job {id:?} to run now; its result will be reported when it finishes."
            )))
        } else {
            let known: Vec<&str> = self.registry.jobs().iter().map(|j| j.id.as_str()).collect();
            Ok(ToolOutput::error(format!(
                "No scheduled job with id {id:?}. Known jobs: {}",
                if known.is_empty() {
                    "(none)".to_string()
                } else {
                    known.join(", ")
                }
            )))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Action, CronSchedule, ScheduleJob};

    fn registry() -> Arc<ScheduleRegistry> {
        Arc::new(ScheduleRegistry::new(vec![
            ScheduleJob {
                id: "disk".into(),
                expr: "0 9 * * *".into(),
                schedule: CronSchedule::parse("0 9 * * *").unwrap(),
                action: Action::Tool {
                    name: "shell".into(),
                    args: json!({"command": "df -h"}),
                },
                room: Some("!ops:hs".into()),
                session: "schedule-disk".into(),
                retry_max: 2,
                retry_wait: 60,
            },
            ScheduleJob {
                id: "build".into(),
                expr: "*/15 * * * *".into(),
                schedule: CronSchedule::parse("*/15 * * * *").unwrap(),
                action: Action::Prompt {
                    text: "check the build".into(),
                },
                room: None,
                session: "schedule-build".into(),
                retry_max: 0,
                retry_wait: 0,
            },
        ]))
    }

    #[tokio::test]
    async fn list_shows_every_job() {
        let out = ScheduleListTool::new(registry())
            .invoke(json!({}))
            .await
            .unwrap();
        assert!(!out.is_error);
        assert!(out.content.contains("disk [0 9 * * *] tool `shell`"));
        assert!(out.content.contains("build [*/15 * * * *] prompt"));
        assert!(out.content.contains("never run"));
    }

    #[tokio::test]
    async fn list_handles_an_empty_schedule() {
        let reg = Arc::new(ScheduleRegistry::new(vec![]));
        let out = ScheduleListTool::new(reg).invoke(json!({})).await.unwrap();
        assert!(out.content.contains("No jobs are scheduled"));
    }

    #[tokio::test]
    async fn status_reports_detail_and_history() {
        let reg = registry();
        let job = reg.jobs()[0].clone();
        reg.record(&job, &Ok("Filesystem 42% used".into()));
        let out = ScheduleStatusTool::new(reg)
            .invoke(json!({"id": "disk"}))
            .await
            .unwrap();
        assert!(!out.is_error);
        assert!(out.content.contains("room: !ops:hs"));
        assert!(out
            .content
            .contains("retry policy: up to 2 retries, 60s apart"));
        assert!(out.content.contains("Filesystem 42% used"));
        assert!(out.content.contains("last ✅"));
    }

    #[tokio::test]
    async fn status_on_unknown_id_lists_the_known_ones() {
        let out = ScheduleStatusTool::new(registry())
            .invoke(json!({"id": "nope"}))
            .await
            .unwrap();
        // A model-visible error, not a hard failure — the turn continues and can self-correct.
        assert!(out.is_error);
        assert!(out.content.contains("disk, build"));
    }

    #[tokio::test]
    async fn status_requires_an_id() {
        let err = ScheduleStatusTool::new(registry())
            .invoke(json!({}))
            .await
            .unwrap_err();
        assert!(matches!(err, ToolError::InvalidArgs(_)));
    }

    #[tokio::test]
    async fn run_queues_a_known_job_and_rejects_an_unknown_one() {
        let reg = registry();
        let tool = ScheduleRunTool::new(reg.clone());

        let out = tool.invoke(json!({"id": "build"})).await.unwrap();
        assert!(!out.is_error);
        assert!(out.content.contains("Queued"));
        assert_eq!(reg.wait_due().await, vec![1]);

        let out = tool.invoke(json!({"id": "nope"})).await.unwrap();
        assert!(out.is_error);
    }

    #[test]
    fn relative_reads_naturally_in_both_directions() {
        let now = 1_000_000;
        assert_eq!(relative(now, now), "now");
        assert_eq!(relative(now + 240, now), "in 4m");
        assert_eq!(relative(now - 7200, now), "2h ago");
        assert_eq!(relative(now - 30, now), "30s ago");
        assert_eq!(relative(now + 3 * 86_400, now), "in 3d");
    }
}
