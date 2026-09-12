//! Bounded exponential backoff for transient provider failures.
//!
//! Provider adapters issue many requests in quick succession (the agent loop, batch polling), so a
//! burst can trip a provider's per-minute rate limit (HTTP 429) or hit a transient overload (503)
//! even with a healthy key. For an *idempotent* send — where nothing was generated yet — those are
//! safe to retry, so this combinator retries them with exponential backoff (2s, 4s, … capped at
//! 32s) and surfaces every other error immediately. Shared by all HTTP provider paths so the policy
//! is identical across Anthropic / xAI / Google instead of one provider having it and the others
//! failing a whole task on the first throttle.

use std::future::Future;
use std::time::Duration;

use crate::ProviderError;

/// HTTP statuses worth retrying: 429 (rate-limited) and 503 (overloaded). Everything else is a hard
/// failure (auth, bad request, model error) and returns at once.
pub fn is_transient_status(status: u16) -> bool {
    status == 429 || status == 503
}

/// Run an idempotent provider operation, retrying transient API failures ([`is_transient_status`])
/// with bounded exponential backoff. `op` is re-invoked from scratch on each attempt (it must build
/// a fresh request), up to `max_retries` *extra* times. Successes and non-transient errors return
/// immediately; once the retries are exhausted the last error is surfaced.
pub async fn retry_transient<F, Fut, T>(max_retries: u32, mut op: F) -> Result<T, ProviderError>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, ProviderError>>,
{
    let mut attempt: u32 = 0;
    loop {
        match op().await {
            Err(ProviderError::Api { status, .. })
                if is_transient_status(status) && attempt < max_retries =>
            {
                // 2s, 4s, 8s … capped at 32s — long enough to refill a per-minute window.
                let backoff = Duration::from_secs(2u64.saturating_pow(attempt + 1).min(32));
                attempt += 1;
                tokio::time::sleep(backoff).await;
            }
            other => return other,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    #[test]
    fn classifies_transient_statuses() {
        assert!(is_transient_status(429));
        assert!(is_transient_status(503));
        assert!(!is_transient_status(400));
        assert!(!is_transient_status(401));
        assert!(!is_transient_status(500));
    }

    #[tokio::test]
    async fn returns_success_without_retrying() {
        let calls = Cell::new(0);
        let out: Result<u8, ProviderError> = retry_transient(5, || {
            calls.set(calls.get() + 1);
            async { Ok(7) }
        })
        .await;
        assert_eq!(out.unwrap(), 7);
        assert_eq!(calls.get(), 1);
    }

    #[tokio::test]
    async fn surfaces_non_transient_errors_immediately() {
        let calls = Cell::new(0);
        let out: Result<u8, ProviderError> = retry_transient(5, || {
            calls.set(calls.get() + 1);
            async {
                Err(ProviderError::Api {
                    status: 400,
                    message: "bad request".into(),
                })
            }
        })
        .await;
        assert!(matches!(out, Err(ProviderError::Api { status: 400, .. })));
        assert_eq!(calls.get(), 1, "non-transient errors are not retried");
    }

    #[tokio::test(start_paused = true)]
    async fn retries_transient_then_succeeds() {
        let calls = Cell::new(0);
        let out: Result<u8, ProviderError> = retry_transient(5, || {
            calls.set(calls.get() + 1);
            let n = calls.get();
            async move {
                if n < 3 {
                    Err(ProviderError::Api {
                        status: 429,
                        message: "slow down".into(),
                    })
                } else {
                    Ok(42)
                }
            }
        })
        .await;
        assert_eq!(out.unwrap(), 42);
        assert_eq!(calls.get(), 3, "two retries then success");
    }

    #[tokio::test(start_paused = true)]
    async fn gives_up_after_max_retries() {
        let calls = Cell::new(0);
        let out: Result<u8, ProviderError> = retry_transient(2, || {
            calls.set(calls.get() + 1);
            async {
                Err(ProviderError::Api {
                    status: 503,
                    message: "overloaded".into(),
                })
            }
        })
        .await;
        assert!(matches!(out, Err(ProviderError::Api { status: 503, .. })));
        assert_eq!(calls.get(), 3, "initial attempt + 2 retries");
    }
}
