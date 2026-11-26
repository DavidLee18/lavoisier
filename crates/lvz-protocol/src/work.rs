//! A lease for background work and the typed errors that work can return.
//!
//! The agent owns the lease. The tool moves the token into the spawned task and reports
//! progress through [`ProgressTx`]. Cancel, timeout, and shutdown all cancel that same token.

use std::sync::Arc;

use tokio_util::sync::CancellationToken;

use crate::JobId;

/// One progress sample from a running job. Labels are short and already redacted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgressNote {
    /// 1-based step index.
    pub step: u32,
    /// How many steps the tool expects, when it knows.
    pub of: u32,
    /// Short label (`hid_print`, `waiting`). Not a log line and not a secret.
    pub label: String,
}

/// Sends progress into the job row. Cloning is cheap. Calling it never waits on I/O.
#[derive(Clone)]
pub struct ProgressTx {
    inner: Arc<dyn Fn(ProgressNote) + Send + Sync>,
}

impl ProgressTx {
    /// Build a sender. `report` runs `f` inline on the caller.
    pub fn from_fn(f: impl Fn(ProgressNote) + Send + Sync + 'static) -> Self {
        Self { inner: Arc::new(f) }
    }

    /// A sender that drops every note. Tests and tools that have nowhere to report use this.
    pub fn sink() -> Self {
        Self::from_fn(|_| {})
    }

    /// Record `note`. The callback must not wait.
    pub fn report(&self, note: ProgressNote) {
        (self.inner)(note);
    }
}

impl std::fmt::Debug for ProgressTx {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ProgressTx")
    }
}

/// Handle a tool holds while its background work runs.
pub struct WorkLease {
    /// Job id reserved in the table.
    pub id: JobId,
    /// Cancel this to stop the work. The same token is stored on the job row.
    pub token: CancellationToken,
    /// Progress samples. Safe to call from the worker.
    pub progress: ProgressTx,
}

/// HID failure that a wake or a replay can return. No response body is included.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum HidFault {
    /// `POST /api/hid/reset` did not succeed.
    #[error("hid reset failed (status {status})")]
    ResetFailed {
        /// HTTP status. Not a body.
        status: u16,
    },
    /// The HID request did not complete.
    #[error("hid transport failed")]
    Transport,
}

/// ECS failure for a build follower. No task payload is included.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum EcsFault {
    /// `StopTask` was refused.
    #[error("StopTask failed")]
    StopFailed,
    /// `DescribeTasks` was refused.
    #[error("DescribeTasks failed")]
    DescribeFailed,
}

/// Why background work stopped short of a normal tool result.
#[derive(Debug, thiserror::Error)]
pub enum WorkError {
    /// The lease token fired. `step` is the step that was in progress.
    #[error("cancelled at step {step}")]
    Cancelled {
        /// Step label at cancel.
        step: String,
    },
    /// The budget elapsed.
    #[error("timed out after {secs}s")]
    Timeout {
        /// Budget in seconds.
        secs: u64,
    },
    /// HID cleanup or a HID call failed.
    #[error(transparent)]
    Hid(#[from] HidFault),
    /// The ECS control-plane call failed.
    #[error(transparent)]
    Ecs(#[from] EcsFault),
    /// A local I/O failure. Only the [`std::io::ErrorKind`] is kept.
    #[error("io error ({kind})")]
    Io {
        /// Kind of the I/O error.
        kind: std::io::ErrorKind,
    },
}

impl From<std::io::Error> for WorkError {
    fn from(err: std::io::Error) -> Self {
        Self::Io { kind: err.kind() }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn work_error_display_has_no_payload() {
        assert_eq!(
            WorkError::Cancelled {
                step: "hid_print".into()
            }
            .to_string(),
            "cancelled at step hid_print"
        );
        assert_eq!(
            WorkError::Timeout { secs: 3 }.to_string(),
            "timed out after 3s"
        );
        assert_eq!(
            WorkError::Hid(HidFault::ResetFailed { status: 500 }).to_string(),
            "hid reset failed (status 500)"
        );
        assert_eq!(
            WorkError::Ecs(EcsFault::StopFailed).to_string(),
            "StopTask failed"
        );
        let io = WorkError::from(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "secret-path",
        ));
        let text = io.to_string();
        assert!(text.contains("not found") || text.contains("NotFound") || text.contains("entity"));
        assert!(!text.contains("secret-path"));
    }

    #[test]
    fn progress_sender_invokes_the_callback() {
        use std::sync::Mutex;
        let seen = Arc::new(Mutex::new(None));
        let slot = Arc::clone(&seen);
        let tx = ProgressTx::from_fn(move |note| {
            *slot.lock().unwrap_or_else(|e| e.into_inner()) = Some(note.label);
        });
        tx.report(ProgressNote {
            step: 1,
            of: 2,
            label: "boot".into(),
        });
        assert_eq!(
            seen.lock().unwrap_or_else(|e| e.into_inner()).as_deref(),
            Some("boot")
        );
    }
}
