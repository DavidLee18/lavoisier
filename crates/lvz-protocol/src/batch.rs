//! Unified **auto-batch** abstraction: run many independent one-shot completions at a provider's
//! discounted batch price (≈50%), polling the whole create→wait→fetch lifecycle behind one call.
//!
//! For non-interactive workloads — bulk classification, offline evals, the benchmark suite — where
//! latency doesn't matter but token cost does. Not for the interactive agent loop (each turn there
//! depends on the previous one, so it can't be batched). Providers without a batch API simply don't
//! implement the trait.

use async_trait::async_trait;

use crate::{ChatRequest, ProviderError, Usage};

/// One request in an auto-batch run: a caller-chosen `custom_id` (echoed back to correlate the
/// result) plus the request itself.
pub struct BatchTask {
    /// Caller-chosen id echoed back on the matching [`BatchItem`] to correlate the result.
    pub custom_id: String,
    /// The one-shot completion request to run.
    pub request: ChatRequest,
}

impl BatchTask {
    /// A task pairing `custom_id` with the `request` to run under it.
    pub fn new(custom_id: impl Into<String>, request: ChatRequest) -> Self {
        Self {
            custom_id: custom_id.into(),
            request,
        }
    }
}

/// The outcome of one batched request, correlated by `custom_id`.
#[derive(Debug, Clone)]
pub struct BatchItem {
    /// The `custom_id` of the [`BatchTask`] this result belongs to.
    pub custom_id: String,
    /// Concatenated answer text (empty when `error` is set).
    pub text: String,
    /// Token usage for this request (billed at the batch discount).
    pub usage: Usage,
    /// Set if the request failed, was canceled, or expired.
    pub error: Option<String>,
}

/// A provider offering a discounted asynchronous **batch** API. [`run_batch`](BatchProvider::run_batch)
/// submits every task, polls until the batch finishes, and returns one [`BatchItem`] per task — the
/// entire lifecycle behind a single call ("auto-batch"). Trades latency for ≈50% lower token cost.
#[async_trait]
pub trait BatchProvider: Send + Sync {
    /// Run all `tasks` as one batch and return their results once the batch completes.
    async fn run_batch(&self, tasks: Vec<BatchTask>) -> Result<Vec<BatchItem>, ProviderError>;
}
