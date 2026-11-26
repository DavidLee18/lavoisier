//! Durable outbox for detached job replies.
//!
//! Each item is one JSON file, `outbox/{seq}.json`. `ack` deletes it. A reader that
//! passes `Last-Event-ID` receives only later sequence numbers.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use tokio::sync::Notify;

use crate::durable::{DurableError, DurableFs, LocalFs};

/// One item the endpoint relays to a room.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutItem {
    /// Monotonic id. The SSE `id` field.
    pub seq: u64,
    /// Lavoisier session, which the endpoint maps back to a room.
    pub session: String,
    /// `reply` for a continuation turn.
    pub kind: String,
    /// The text to post. Raw completion text when phrasing failed.
    pub text: String,
    /// Image count. The bytes stay in the transcript, not in this item.
    pub images: u32,
}

/// Process-local outbox backed by [`DurableFs`].
#[derive(Clone)]
pub struct Outbox {
    inner: Arc<Inner>,
}

struct Inner {
    dir: PathBuf,
    fs: Arc<dyn DurableFs>,
    items: Mutex<Vec<OutItem>>,
    next: AtomicU64,
    notify: Arc<Notify>,
}

impl Outbox {
    /// Load any unacked files under `dir/outbox`.
    pub fn open(dir: impl Into<PathBuf>, fs: Arc<dyn DurableFs>) -> Result<Self, DurableError> {
        let dir = dir.into().join("outbox");
        std::fs::create_dir_all(&dir).map_err(DurableError::from)?;
        let mut items = Vec::new();
        for path in fs.list(&dir)? {
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            if !name.ends_with(".json") {
                continue;
            }
            let Ok(bytes) = std::fs::read(&path) else {
                continue;
            };
            if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bytes) {
                if let Some(item) = item_from_json(&value) {
                    items.push(item);
                }
            }
        }
        items.sort_by_key(|item| item.seq);
        let next = items
            .last()
            .map(|item| item.seq.saturating_add(1))
            .unwrap_or(1);
        Ok(Self {
            inner: Arc::new(Inner {
                dir,
                fs,
                items: Mutex::new(items),
                next: AtomicU64::new(next),
                notify: Arc::new(Notify::new()),
            }),
        })
    }

    /// Open with [`LocalFs`].
    pub fn open_local(dir: impl Into<PathBuf>) -> Result<Self, DurableError> {
        Self::open(dir, Arc::new(LocalFs))
    }

    /// Append `text` for `session` and wake readers.
    pub fn publish(&self, session: impl Into<String>, text: impl Into<String>) -> OutItem {
        let seq = self.inner.next.fetch_add(1, Ordering::Relaxed);
        let item = OutItem {
            seq,
            session: session.into(),
            kind: "reply".into(),
            text: text.into(),
            images: 0,
        };
        let path = self.path(seq);
        let bytes = serde_json::to_vec(&item_json(&item)).unwrap_or_default();
        if self.inner.fs.write_atomic(&path, &bytes).is_err() {
            tracing::error!(seq, "outbox write failed");
        }
        self.inner
            .items
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .push(item.clone());
        self.inner.notify.notify_waiters();
        item
    }

    /// Items with `seq` greater than `after`, in order.
    pub fn since(&self, after: u64) -> Vec<OutItem> {
        self.inner
            .items
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .iter()
            .filter(|item| item.seq > after)
            .cloned()
            .collect()
    }

    /// Delete `seq`. A second ack is a no-op.
    pub fn ack(&self, seq: u64) {
        self.inner
            .items
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .retain(|item| item.seq != seq);
        if self.inner.fs.remove(&self.path(seq)).is_err() {
            tracing::debug!(seq, "outbox ack remove");
        }
    }

    /// Wait until a later [`publish`](Self::publish).
    pub async fn notified(&self) {
        self.inner.notify.notified().await;
    }

    /// The same notify the SSE loop waits on.
    pub fn poke(&self) -> Arc<Notify> {
        Arc::clone(&self.inner.notify)
    }

    fn path(&self, seq: u64) -> PathBuf {
        self.inner.dir.join(format!("{seq}.json"))
    }
}

fn item_json(item: &OutItem) -> serde_json::Value {
    serde_json::json!({
        "seq": item.seq,
        "session": item.session,
        "kind": item.kind,
        "text": item.text,
        "images": item.images,
    })
}

fn item_from_json(value: &serde_json::Value) -> Option<OutItem> {
    Some(OutItem {
        seq: value.get("seq")?.as_u64()?,
        session: value.get("session")?.as_str()?.to_string(),
        kind: value.get("kind")?.as_str()?.to_string(),
        text: value.get("text")?.as_str()?.to_string(),
        images: value.get("images").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
    })
}

/// The directory an [`Outbox`] was opened under, for tests that inspect files.
pub fn item_path(dir: &Path, seq: u64) -> PathBuf {
    dir.join("outbox").join(format!("{seq}.json"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn publish_ack_and_reload() {
        let dir = std::env::temp_dir().join(format!("lvz-outbox-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let box1 = Outbox::open_local(&dir).expect("open");
        let first = box1.publish("s", "hello");
        let second = box1.publish("s", "again");
        assert_eq!(box1.since(first.seq).len(), 1);
        box1.ack(first.seq);
        assert!(!item_path(&dir, first.seq).exists());
        let box2 = Outbox::open_local(&dir).expect("reload");
        let left = box2.since(0);
        assert_eq!(left.len(), 1);
        assert_eq!(left[0].seq, second.seq);
        assert_eq!(left[0].text, "again");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
