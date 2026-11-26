//! Background job ids and the long-tool accept contract.
//!
//! A short tool still finishes inside [`Tool::invoke`](crate::Tool::invoke). A long tool
//! returns a [`JobId`] immediately. The host runs the work and delivers one terminal
//! [`crate::ToolOutput`] later, as user text, not as a second `tool_result` for the same id.
//!
//! The in-flight table, the per-session cap, and restart settlement live in `lvz-agent`.
//! This module is the typed contract those pieces share. It does no I/O.

use std::fmt;

use serde::{Deserialize, Serialize};

use crate::{Tool, ToolError};

/// How many jobs one session may have running at once.
///
/// A further accept is [`ToolError::Execution`](crate::ToolError::Execution). The
/// placeholder `tool_result` for that call is `is_error`.
pub const MAX_JOBS_PER_SESSION: usize = 4;

/// Opaque id of one accepted background job.
///
/// The token is the map key and the text the model sees (`accepted, id=…`). It is not a
/// secret. Empty tokens and path separators are rejected so a persisted id cannot escape
/// the jobs directory.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct JobId(String);

impl JobId {
    /// Build an id from `token`.
    ///
    /// # Errors
    ///
    /// [`JobError::Failed`] when `token` is empty, longer than 128 bytes, or contains a
    /// control character or a path separator.
    pub fn new(token: impl Into<String>) -> Result<Self, JobError> {
        let token = token.into();
        let bad = token.is_empty()
            || token.len() > 128
            || token
                .chars()
                .any(|c| c.is_control() || c == '/' || c == '\\' || c == '.');
        if bad {
            return Err(JobError::Failed {
                name: "job".to_string(),
                message: "job id is empty or not a single path segment".to_string(),
            });
        }
        Ok(Self(token))
    }

    /// The raw token.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for JobId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// Why a background job did not produce a successful [`crate::ToolOutput`].
#[derive(Debug, thiserror::Error, Clone, PartialEq, Eq)]
pub enum JobError {
    /// No row for this id.
    #[error("unknown job {0}")]
    Unknown(JobId),
    /// The accept budget elapsed. A chat timeout does not run the tool again.
    #[error("{name} timed out after {secs}s")]
    Timeout {
        /// Tool that accepted the work.
        name: String,
        /// Budget in seconds.
        secs: u64,
    },
    /// The turn was dropped, or ACP `session/cancel` fired the parent token.
    #[error("{name} cancelled")]
    Cancelled {
        /// Tool that accepted the work.
        name: String,
    },
    /// The work failed, including a process restart that must not repeat a wake or an OBS call.
    #[error("{name} failed: {message}")]
    Failed {
        /// Tool that accepted the work.
        name: String,
        /// Operator-facing reason. Not a credential, token, or response body.
        message: String,
    },
    /// A side-effecting job was in flight when the process stopped. It is not run again.
    /// `step` is the last persisted progress label, or `unknown` when none was stored.
    #[error("{tool} interrupted after {step}")]
    Interrupted {
        /// Tool that had accepted the work.
        tool: String,
        /// Last progress step, already redacted.
        step: String,
    },
    /// A schedule attempt was still running when the process stopped, so its verdict is unknown.
    #[error("{name} lost")]
    Lost {
        /// Job or attempt name.
        name: String,
    },
}

/// A job the tool has accepted and is no longer blocking the turn on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AcceptedJob {
    /// Id the host tracks and the placeholder quotes.
    pub id: JobId,
    /// Tool estimate used as the chat timeout. `None` uses the configured schedule budget.
    pub estimated_seconds: Option<u64>,
}

/// A tool whose work outlives the `tool_result`.
///
/// `start` returns as soon as the work is accepted. The host owns the in-flight row and the
/// cancel token. Native tools that must await a fast check before accepting (ATX power-on)
/// call the agent `reserve_job` helper from [`Tool::invoke`](crate::Tool::invoke) after that
/// check. The same [`JobId`] and cap apply. `start` is the synchronous entry a `brain` host
/// import calls when the guest itself does not spawn.
pub trait LongTool: Tool {
    /// Accept `args` and return the id of the background job.
    ///
    /// # Errors
    ///
    /// [`ToolError::Execution`] when the session is already at [`MAX_JOBS_PER_SESSION`], or
    /// [`ToolError`] when the arguments cannot be accepted.
    fn start(
        &self,
        args: serde_json::Value,
        cancel: tokio_util::sync::CancellationToken,
    ) -> Result<JobId, ToolError>;
}

/// Power, OBS, and other side-effecting tools must not run again after a restart.
///
/// `run_build` is the exception: its exit code is an external `$BUILD_ID.code` file, so a
/// restarted process may reattach instead of launching a second build.
pub fn reattach_from_artifact(tool: &str) -> bool {
    tool == "run_build"
}

/// `true` when a persisted row must become [`JobError::Failed`] with `"process restarted"`.
pub fn fails_closed_on_restart(tool: &str) -> bool {
    !reattach_from_artifact(tool)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ToolOutput;

    struct Echo;

    #[async_trait::async_trait]
    impl Tool for Echo {
        fn name(&self) -> &str {
            "echo"
        }
        fn schema(&self) -> serde_json::Value {
            serde_json::json!({})
        }
        async fn invoke(&self, _args: serde_json::Value) -> Result<ToolOutput, ToolError> {
            Ok(ToolOutput::ok("nope"))
        }
    }

    impl LongTool for Echo {
        fn start(
            &self,
            args: serde_json::Value,
            _cancel: tokio_util::sync::CancellationToken,
        ) -> Result<JobId, ToolError> {
            let token = args.get("id").and_then(|v| v.as_str()).unwrap_or("job-1");
            JobId::new(token).map_err(|e| ToolError::Execution(e.to_string()))
        }
    }

    #[test]
    fn job_id_rejects_path_segments() {
        assert!(JobId::new("").is_err());
        assert!(JobId::new("../x").is_err());
        assert!(JobId::new("a/b").is_err());
        assert!(JobId::new("ok-1").is_ok());
    }

    #[test]
    fn restart_policy_keeps_builds_and_fails_power() {
        assert!(reattach_from_artifact("run_build"));
        assert!(fails_closed_on_restart("server_wake"));
        assert!(fails_closed_on_restart("server_shutdown"));
        assert!(fails_closed_on_restart("obs_scene_switch"));
        assert!(!fails_closed_on_restart("run_build"));
    }

    #[test]
    fn long_tool_start_returns_the_id() {
        let id = Echo
            .start(
                serde_json::json!({"id": "abc"}),
                tokio_util::sync::CancellationToken::new(),
            )
            .expect("id");
        assert_eq!(id.as_str(), "abc");
    }

    #[test]
    fn job_error_display_matches_the_contract() {
        let id = JobId::new("j1").expect("id");
        assert_eq!(JobError::Unknown(id).to_string(), "unknown job j1");
        assert_eq!(
            JobError::Timeout {
                name: "server_wake".into(),
                secs: 30
            }
            .to_string(),
            "server_wake timed out after 30s"
        );
        assert_eq!(
            JobError::Cancelled {
                name: "run_build".into()
            }
            .to_string(),
            "run_build cancelled"
        );
        assert_eq!(
            JobError::Failed {
                name: "server_wake".into(),
                message: "process restarted".into()
            }
            .to_string(),
            "server_wake failed: process restarted"
        );
        assert_eq!(
            JobError::Interrupted {
                tool: "server_wake".into(),
                step: "3/5 hid".into(),
            }
            .to_string(),
            "server_wake interrupted after 3/5 hid"
        );
        assert_eq!(
            JobError::Lost {
                name: "wake".into()
            }
            .to_string(),
            "wake lost"
        );
    }
}
