//! `jobs_list` and `job_cancel`. Registered only when `[jobs] user_tools` is on.

use async_trait::async_trait;
use lvz_protocol::{tool_grant_slice, work_scope, JobError, JobId, Tool, ToolError, ToolOutput};

use crate::jobs::{self, UserCancel};

/// List the running jobs of this turn's session.
pub struct JobsListTool;

#[async_trait]
impl Tool for JobsListTool {
    fn name(&self) -> &str {
        "jobs_list"
    }

    fn description(&self) -> &str {
        "List this session's running jobs: id, tool, age, and progress step."
    }

    fn schema(&self) -> serde_json::Value {
        serde_json::json!({"type": "object", "properties": {}})
    }

    async fn invoke(&self, _args: serde_json::Value) -> Result<ToolOutput, ToolError> {
        let Some(scope) = work_scope() else {
            return Err(ToolError::Execution(
                "jobs_list is only available inside a turn".into(),
            ));
        };
        let rows = jobs::global().list_running(&scope.session);
        if rows.is_empty() {
            return Ok(ToolOutput::ok("실행 중인 작업이 없습니다."));
        }
        let mut text = String::new();
        for row in rows {
            if !text.is_empty() {
                text.push('\n');
            }
            text.push_str(&format!(
                "{} · {} · {}s · {}",
                row.id, row.tool, row.age_s, row.step
            ));
        }
        Ok(ToolOutput::ok(text))
    }
}

/// Cancel one job in this turn's session.
pub struct JobCancelTool;

#[async_trait]
impl Tool for JobCancelTool {
    fn name(&self) -> &str {
        "job_cancel"
    }

    fn description(&self) -> &str {
        "Cancel one running job in this session by its id. Scheduled jobs cannot be cancelled."
    }

    fn schema(&self) -> serde_json::Value {
        serde_json::json!({
            "type": "object",
            "properties": {"id": {"type": "string"}},
            "required": ["id"]
        })
    }

    async fn invoke(&self, args: serde_json::Value) -> Result<ToolOutput, ToolError> {
        let Some(scope) = work_scope() else {
            return Err(ToolError::Execution(
                "job_cancel is only available inside a turn".into(),
            ));
        };
        let id = args.get("id").and_then(|v| v.as_str()).unwrap_or_default();
        let id = JobId::new(id).map_err(|err| ToolError::Execution(err.to_string()))?;
        let grant = tool_grant_slice();
        match jobs::global().cancel_for_user(&scope.session, &id, grant.as_deref()) {
            UserCancel::Cancelled { id, tool } => {
                Ok(ToolOutput::ok(format!("cancelled {id} ({tool})")))
            }
            UserCancel::Schedule => Ok(ToolOutput::ok("예약 작업은 취소할 수 없습니다")),
            UserCancel::Denied => Ok(ToolOutput::error("권한 없음")),
            UserCancel::Finished { id, tool, text } => Ok(ToolOutput::ok(format!(
                "job {id} ({tool}) already finished: {text}"
            ))),
            UserCancel::Unknown => Err(ToolError::Execution(JobError::Unknown(id).to_string())),
        }
    }
}
