//! Deploy handoff for the fenced crypto store.
//!
//! These decisions are pure so they can be tested without Postgres. The Matrix
//! serve loop and the CLI supervisor call them. A parked holder never
//! re-acquires: the only outcomes are to keep the ready file or to exit.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::sync::Notify;

/// How the process supervisor treats one finished gateway future.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SupervisorStep {
    /// This completion ends the process.
    Exit,
    /// Slack returned `Ok` after a requested handoff, and the release `UPDATE`
    /// has not run yet. Do not leave the supervisor.
    WaitForRelease,
    /// Slack returned `Ok` after the release `UPDATE`. Ignore it.
    Ignore,
}

/// `ok` is the Slack (or other) result. Only a Slack `Ok` after the handoff
/// stop flag is set is ignored, and only once `released` is true.
pub fn supervisor_step(
    slack: bool,
    ok: bool,
    handoff_requested: bool,
    released: bool,
) -> SupervisorStep {
    if slack && handoff_requested && ok {
        if released {
            SupervisorStep::Ignore
        } else {
            SupervisorStep::WaitForRelease
        }
    } else {
        SupervisorStep::Exit
    }
}

/// Shared flag the Matrix loop sets when it asks Slack to stop, and sets again
/// after the fence release `UPDATE`.
#[derive(Debug, Default)]
pub struct Handoff {
    stop: AtomicBool,
    released: AtomicBool,
    stop_notify: Notify,
    release_notify: Notify,
}

impl Handoff {
    /// A new handoff that has not been requested and has not released.
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Ask Slack to stop. The supervisor may ignore a later Slack `Ok`.
    pub fn request_stop(&self) {
        self.stop.store(true, Ordering::SeqCst);
        self.stop_notify.notify_waiters();
    }

    /// Whether [`Self::request_stop`] has run.
    pub fn requested(&self) -> bool {
        self.stop.load(Ordering::SeqCst)
    }

    /// Resolves when [`Self::request_stop`] has run.
    pub async fn stopped(&self) {
        loop {
            let notified = self.stop_notify.notified();
            if self.stop.load(Ordering::SeqCst) {
                return;
            }
            notified.await;
        }
    }

    /// The release `UPDATE` has committed.
    pub fn mark_released(&self) {
        self.released.store(true, Ordering::SeqCst);
        self.release_notify.notify_waiters();
    }

    /// Whether [`Self::mark_released`] has run.
    pub fn released(&self) -> bool {
        self.released.load(Ordering::SeqCst)
    }

    /// Resolves when the release `UPDATE` has been recorded.
    pub async fn wait_released(&self) {
        loop {
            let notified = self.release_notify.notified();
            if self.released.load(Ordering::SeqCst) {
                return;
            }
            notified.await;
        }
    }
}

/// What the parked holder does with `/tmp/e2ee-ready`. There is no re-acquire.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParkAction {
    /// Keep the ready file. The successor is still acquiring or loading.
    Keep,
    /// Unlink the ready file and exit. Do not take the fence again.
    Exit,
}

/// One read of `crypto.crypto_fence` from the parked task.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FenceSnapshot {
    /// Current `holder`. Empty after release.
    pub holder: String,
    /// `lease_until > clock_timestamp()`.
    pub lease_live: bool,
    /// Current `waiter`, if any.
    pub waiter: Option<String>,
    /// `waiter_until > clock_timestamp()`.
    pub waiter_live: bool,
}

/// Grace clock for one lapsed foreign lease. `None` until the first lapse.
#[derive(Clone, Debug, Default)]
#[cfg_attr(not(feature = "e2ee"), allow(dead_code))]
pub struct ParkState {
    grace_deadline: Option<Instant>,
}

impl ParkState {
    /// No grace clock running.
    #[cfg_attr(not(feature = "e2ee"), allow(dead_code))]
    pub fn new() -> Self {
        Self::default()
    }
}

/// Decide the park. `me` is this process's holder id. `grace` is the load
/// grace (120 seconds in production). A live waiter claim and the first lapsed
/// foreign lease inside the grace are not abandonment.
#[cfg_attr(not(feature = "e2ee"), allow(dead_code))]
pub fn park_action(
    me: &str,
    snap: &FenceSnapshot,
    state: &mut ParkState,
    now: Instant,
    grace: Duration,
) -> ParkAction {
    let foreign = !snap.holder.is_empty() && snap.holder != me;
    if foreign && snap.lease_live {
        state.grace_deadline = None;
        return ParkAction::Keep;
    }
    if foreign && !snap.lease_live {
        let deadline = *state.grace_deadline.get_or_insert(now + grace);
        if now >= deadline {
            return ParkAction::Exit;
        }
        return ParkAction::Keep;
    }
    state.grace_deadline = None;
    if snap.waiter.is_some() && snap.waiter_live {
        return ParkAction::Keep;
    }
    ParkAction::Exit
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slack_err_with_flag_clear_exits() {
        assert_eq!(
            supervisor_step(true, false, false, false),
            SupervisorStep::Exit
        );
    }

    #[test]
    fn slack_ok_before_release_waits() {
        assert_eq!(
            supervisor_step(true, true, true, false),
            SupervisorStep::WaitForRelease
        );
    }

    #[test]
    fn slack_ok_after_release_is_ignored() {
        assert_eq!(
            supervisor_step(true, true, true, true),
            SupervisorStep::Ignore
        );
    }

    #[test]
    fn slack_err_after_flag_still_exits() {
        assert_eq!(
            supervisor_step(true, false, true, false),
            SupervisorStep::Exit
        );
    }

    #[tokio::test]
    async fn handoff_slack_ok_does_not_finish_before_release() {
        let handoff = Handoff::new();
        handoff.request_stop();
        let gate = Arc::clone(&handoff);
        let task = tokio::spawn(async move {
            assert_eq!(
                supervisor_step(true, true, gate.requested(), gate.released()),
                SupervisorStep::WaitForRelease
            );
            gate.wait_released().await;
            supervisor_step(true, true, true, true)
        });
        tokio::task::yield_now().await;
        assert!(
            !task.is_finished(),
            "supervisor returned before the release UPDATE"
        );
        handoff.mark_released();
        assert_eq!(task.await.unwrap(), SupervisorStep::Ignore);
    }

    fn snap(
        holder: &str,
        lease_live: bool,
        waiter: Option<&str>,
        waiter_live: bool,
    ) -> FenceSnapshot {
        FenceSnapshot {
            holder: holder.to_string(),
            lease_live,
            waiter: waiter.map(str::to_string),
            waiter_live,
        }
    }

    #[test]
    fn refreshed_waiter_claim_is_not_abandonment() {
        let mut state = ParkState::new();
        let now = Instant::now();
        let action = park_action(
            "old",
            &snap("", false, Some("new"), true),
            &mut state,
            now,
            Duration::from_secs(120),
        );
        assert_eq!(action, ParkAction::Keep);
    }

    #[test]
    fn first_lapsed_lease_stays_inside_the_load_grace() {
        let mut state = ParkState::new();
        let now = Instant::now();
        let action = park_action(
            "old",
            &snap("new", false, None, false),
            &mut state,
            now,
            Duration::from_secs(120),
        );
        assert_eq!(action, ParkAction::Keep);
        let later = park_action(
            "old",
            &snap("new", false, None, false),
            &mut state,
            now + Duration::from_secs(121),
            Duration::from_secs(120),
        );
        assert_eq!(later, ParkAction::Exit);
    }

    #[test]
    fn live_foreign_holder_keeps_the_file() {
        let mut state = ParkState::new();
        let action = park_action(
            "old",
            &snap("new", true, None, false),
            &mut state,
            Instant::now(),
            Duration::from_secs(120),
        );
        assert_eq!(action, ParkAction::Keep);
    }

    #[test]
    fn expired_waiter_with_no_holder_exits() {
        let mut state = ParkState::new();
        let action = park_action(
            "old",
            &snap("", false, Some("new"), false),
            &mut state,
            Instant::now(),
            Duration::from_secs(120),
        );
        assert_eq!(action, ParkAction::Exit);
    }
}
