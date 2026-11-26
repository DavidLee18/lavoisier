//! Second-user confirmation marker and the live-broadcast probe.
//!
//! Extra-tools reads [`confirmed_call`] during a stored execution. The probe is optional:
//! a missing probe, or [`Liveness::Unknown`], is treated as live by the gate.

use std::future::Future;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use serde_json::Value;

/// Whether a shutdown target is on the air.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Liveness {
    /// A confirm is required.
    Live,
    /// The call may proceed.
    NotLive,
    /// The probe failed. The gate treats this as [`Live`].
    Unknown,
}

/// Asks whether `tool` is operating on a live target. Implemented outside this crate.
#[async_trait]
pub trait LiveProbe: Send + Sync {
    /// `Unknown` on timeout or error.
    async fn live(&self, tool: &str, args: &Value) -> Liveness;
}

static PROBE: Mutex<Option<Arc<dyn LiveProbe>>> = Mutex::new(None);

/// Register the probe. A later call replaces the earlier one.
pub fn set_live_probe(probe: Arc<dyn LiveProbe>) {
    *PROBE.lock().unwrap_or_else(|err| err.into_inner()) = Some(probe);
}

/// The probe, if one was registered.
pub fn live_probe() -> Option<Arc<dyn LiveProbe>> {
    PROBE.lock().unwrap_or_else(|err| err.into_inner()).clone()
}

/// The tool call a second user just confirmed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfirmedCall {
    /// Tool name.
    pub tool: String,
    /// Hash of the canonical arguments.
    pub args_hash: String,
}

tokio::task_local! {
    static CONFIRMED: ConfirmedCall;
}

/// The confirmed call on this task, if the stored executor installed one.
pub fn confirmed_call() -> Option<ConfirmedCall> {
    CONFIRMED.try_with(|call| call.clone()).ok()
}

/// Run `fut` with [`confirmed_call`] set.
pub async fn enter_confirmed<F>(call: ConfirmedCall, fut: F) -> F::Output
where
    F: Future,
{
    CONFIRMED.scope(call, fut).await
}
