//! Fenced Aurora `CryptoStore` for the Matrix gateway (`e2ee` feature).
//!
//! SQLite remains the store when `MATRIX_CRYPTO_STORE_SECRET` is unset.

mod codec;
mod error;
mod migrate;
mod store;

#[cfg(test)]
mod tests;

pub use error::{Reconcile, StoreError};
pub use migrate::migrate_sqlite;
pub use store::PostgresCryptoStore;

use std::sync::Arc;
use std::time::Duration;

use crate::fence_supervisor::Handoff;
use crate::GatewayError;

/// Leadership the CLI acquired once, before Slack, the schedule, or the memory store.
pub struct Leadership {
    /// The store. `Crypto::new` must not run the incrementing acquire again.
    pub store: Arc<PostgresCryptoStore>,
    /// Handoff flag shared with the process supervisor.
    pub handoff: Arc<Handoff>,
}

/// Connect and acquire when `MATRIX_CRYPTO_STORE_SECRET` is set. `Ok(None)` when it is unset.
/// The secret JSON and the passphrase are not logged.
pub async fn acquire_leadership_from_env() -> Result<Option<Leadership>, GatewayError> {
    let secret = match std::env::var("MATRIX_CRYPTO_STORE_SECRET") {
        Ok(v) if !v.is_empty() => v,
        _ => return Ok(None),
    };
    let passphrase = std::env::var("MATRIX_CRYPTO_STORE_KEY").map_err(|_| {
        GatewayError::Bind("MATRIX_CRYPTO_STORE_SECRET requires MATRIX_CRYPTO_STORE_KEY".into())
    })?;
    let holder = holder_id().await;
    let store = PostgresCryptoStore::connect_secret(&secret, &passphrase, holder)
        .await
        .map_err(|e| GatewayError::Bind(e.to_string()))?;
    // Drop the JSON. It must not be logged later by a Debug of this stack.
    drop(secret);
    drop(passphrase);
    loop {
        store
            .record_waiter()
            .await
            .map_err(|e| GatewayError::Bind(e.to_string()))?;
        match store.acquire().await {
            Ok(_) => break,
            Err(StoreError::Other(msg)) if msg == "fence held" => {
                let jitter = Duration::from_millis(500 + (std::process::id() as u64 % 500));
                tokio::time::sleep(jitter).await;
            }
            Err(e) => return Err(GatewayError::Bind(e.to_string())),
        }
    }
    Ok(Some(Leadership {
        store,
        handoff: Handoff::new(),
    }))
}

async fn holder_id() -> String {
    let Some(uri) = std::env::var("ECS_CONTAINER_METADATA_URI_V4").ok() else {
        return uuid::Uuid::new_v4().to_string();
    };
    let url = format!("{uri}/task");
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(2))
        .build();
    let Ok(client) = client else {
        return uuid::Uuid::new_v4().to_string();
    };
    let Ok(resp) = client.get(url).send().await else {
        return uuid::Uuid::new_v4().to_string();
    };
    let Ok(body) = resp.json::<serde_json::Value>().await else {
        return uuid::Uuid::new_v4().to_string();
    };
    body.get("TaskARN")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string())
}
