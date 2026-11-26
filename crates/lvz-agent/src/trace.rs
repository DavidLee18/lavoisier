//! Staged history beside the transcript.
//!
//! The transcript file stays a `Vec<Message>`. This module writes one JSON object per turn or
//! job under `{hex}.trace/`. `[trace] enabled` defaults false: nothing is installed, and every
//! call below is a no-op.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use base64::Engine;
use lvz_protocol::{Event, ToolImage, Usage};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::cancel::take_cancel_records;
use crate::durable::{DurableFs, LocalFs};

const RECORD_CAP: usize = 256 * 1024;
const KNOWN: &[&str] = &[
    "ModelCall",
    "ToolCall",
    "JobAccepted",
    "JobProgress",
    "JobResult",
    "ConfirmRequested",
    "ConfirmConsumed",
    "ReplySent",
    "CancelCommand",
];

static INSTALLED: Mutex<Option<Arc<TraceStore>>> = Mutex::new(None);
static WRITE_SEQ: AtomicU64 = AtomicU64::new(0);

/// Install the process trace store. A second call replaces the first.
pub fn install(store: Arc<TraceStore>) {
    *INSTALLED.lock().unwrap_or_else(|err| err.into_inner()) = Some(store);
}

/// Read the installed store. Empty when the trace is off.
pub fn read_installed(session: &str, last: usize) -> Vec<Value> {
    current()
        .map(|store| store.read(session, last))
        .unwrap_or_default()
}

fn current() -> Option<Arc<TraceStore>> {
    INSTALLED
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .clone()
}

/// Where records are written.
pub struct TraceStore {
    dir: PathBuf,
    keep: usize,
    fs: Arc<dyn DurableFs>,
}

impl TraceStore {
    /// Records live under `dir`. `keep` is how many files a session retains.
    pub fn open(dir: PathBuf, keep: usize, fs: Arc<dyn DurableFs>) -> Self {
        Self { dir, keep, fs }
    }

    /// A local-filesystem store.
    pub fn open_local(dir: PathBuf, keep: usize) -> Self {
        Self::open(dir, keep, Arc::new(LocalFs))
    }

    /// Read the newest `last` records. Stages with an unknown `t` are dropped.
    pub fn read(&self, session: &str, last: usize) -> Vec<Value> {
        let folder = self.folder(session);
        let Ok(mut paths) = self.fs.list(&folder) else {
            return Vec::new();
        };
        paths.sort();
        if last > 0 && paths.len() > last {
            paths = paths.split_off(paths.len() - last);
        }
        let mut out = Vec::new();
        for path in paths {
            let Ok(bytes) = std::fs::read(&path) else {
                continue;
            };
            let Ok(mut value) = serde_json::from_slice::<Value>(&bytes) else {
                continue;
            };
            if let Some(stages) = value.get_mut("stages").and_then(|item| item.as_array_mut()) {
                stages.retain(|stage| {
                    stage
                        .get("t")
                        .and_then(|tag| tag.as_str())
                        .is_some_and(|tag| KNOWN.contains(&tag))
                });
            }
            out.push(value);
        }
        out
    }

    fn folder(&self, session: &str) -> PathBuf {
        self.dir.join(format!("{}.trace", hex_session(session)))
    }

    fn write_now(&self, session: &str, id: &str, kind: &str, stages: Vec<Value>) {
        let mut stages = stages;
        let mut body = record_body(session, id, kind, &stages);
        while body.len() > RECORD_CAP && !stages.is_empty() {
            stages.remove(0);
            body = record_body(session, id, kind, &stages);
        }
        if body.len() > RECORD_CAP {
            return;
        }
        let folder = self.folder(session);
        let safe = sanitize_id(id);
        let seq = WRITE_SEQ.fetch_add(1, Ordering::Relaxed);
        let path = folder.join(format!("{}-{seq:06}-{safe}.json", unix_ms()));
        if self.fs.write_atomic(&path, body.as_bytes()).is_err() {
            return;
        }
        self.prune(session);
    }

    fn prune(&self, session: &str) {
        if self.keep == 0 {
            return;
        }
        let folder = self.folder(session);
        let Ok(mut paths) = self.fs.list(&folder) else {
            return;
        };
        paths.sort();
        if paths.len() <= self.keep {
            return;
        }
        let extra = paths.len() - self.keep;
        for path in paths.into_iter().take(extra) {
            let _ = self.fs.remove(&path);
        }
    }
}

/// One turn's stages, collected from the event stream. The transcript is not touched.
pub struct TurnTrace {
    id: String,
    open: std::collections::HashMap<String, (String, String)>,
    stages: Vec<Value>,
}

impl TurnTrace {
    /// Start a collector. `id` is the turn or job id used in the filename.
    pub fn new(id: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            open: std::collections::HashMap::new(),
            stages: Vec::new(),
        }
    }

    /// Fold one event into the collector.
    pub fn observe(&mut self, event: &Event) {
        match event {
            Event::ToolUseStart { id, name } => {
                self.open.insert(id.clone(), (name.clone(), String::new()));
            }
            Event::ToolUseDelta { id, json } => {
                if let Some((_, args)) = self.open.get_mut(id) {
                    args.push_str(json);
                }
            }
            Event::ToolUseEnd { id } => {
                if let Some((name, args)) = self.open.remove(id) {
                    self.stages.push(tool_stage(id, &name, &args, false, 0));
                }
            }
            Event::Usage(usage) => self.stages.push(model_stage(usage)),
            Event::ConfirmRequired {
                code,
                room,
                tool,
                expires_s,
            } => self.stages.push(json!({
                "t": "ConfirmRequested",
                "code": code,
                "room": room,
                "tool": tool,
                "expires_s": expires_s,
            })),
            Event::ToolResultImages { id, name, images } => {
                self.stages.push(image_stage(id, name, images));
            }
            _ => {}
        }
    }

    /// Write the record when a store is installed. Includes cancel-hook rows drained now.
    pub async fn flush(&mut self, session: &str) {
        let Some(store) = current() else {
            return;
        };
        for record in take_cancel_records() {
            self.stages.push(json!({
                "t": "CancelCommand",
                "sender": record.sender,
                "job": record.job,
                "matched_by": record.matched_by,
            }));
        }
        let id = self.id.clone();
        let stages = std::mem::take(&mut self.stages);
        let session = session.to_string();
        let _ = tokio::task::spawn_blocking(move || store.write_now(&session, &id, "Turn", stages))
            .await;
    }
}

/// A job was reserved. No-op when the trace is off.
pub fn job_accepted(session: &str, id: &str, tool: &str, estimate_s: Option<u64>) {
    let Some(store) = current() else {
        return;
    };
    store.write_now(
        session,
        id,
        "Job",
        vec![json!({
            "t": "JobAccepted",
            "job_id": id,
            "tool": tool,
            "estimate_s": estimate_s,
        })],
    );
}

/// A running job published progress. No-op when the trace is off.
pub fn job_progress(session: &str, id: &str, step: u32, of: u32, label: &str) {
    let Some(store) = current() else {
        return;
    };
    let stamp = unix_ms();
    store.write_now(
        session,
        &format!("{id}-p{stamp}"),
        "Job",
        vec![json!({
            "t": "JobProgress",
            "job_id": id,
            "step": step,
            "of": of,
            "label": label,
            "at_ms": stamp,
        })],
    );
}

/// A job reached a terminal state. No-op when the trace is off.
pub fn job_result(session: &str, id: &str, outcome: &str) {
    let Some(store) = current() else {
        return;
    };
    store.write_now(
        session,
        id,
        "Job",
        vec![json!({
            "t": "JobResult",
            "job_id": id,
            "outcome": outcome,
            "ms": 0,
        })],
    );
}

/// Replace secret-shaped object keys and cap strings at 512 characters.
pub fn redact_value(value: &mut Value) {
    match value {
        Value::Object(map) => {
            for (key, child) in map.iter_mut() {
                if secret_key(key) {
                    *child = Value::String("<redacted>".to_string());
                } else {
                    redact_value(child);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                redact_value(item);
            }
        }
        Value::String(text) if text.chars().count() > 512 => {
            *text = text.chars().take(512).collect();
        }
        _ => {}
    }
}

fn secret_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    ["pass", "secret", "token", "key", "otp", "auth"]
        .iter()
        .any(|part| lower.contains(part))
}

fn tool_stage(id: &str, name: &str, args: &str, is_error: bool, result_bytes: u64) -> Value {
    let mut parsed = serde_json::from_str::<Value>(args).unwrap_or(Value::String(args.to_string()));
    redact_value(&mut parsed);
    json!({
        "t": "ToolCall",
        "call_id": id,
        "name": name,
        "args_redacted": parsed,
        "ms_to_result": 0,
        "is_error": is_error,
        "result_bytes": result_bytes,
    })
}

fn model_stage(usage: &Usage) -> Value {
    json!({
        "t": "ModelCall",
        "round": 0,
        "model": "",
        "ms": 0,
        "tokens_in": usage.input_tokens,
        "tokens_out": usage.output_tokens,
        "stop": "",
    })
}

fn image_stage(id: &str, name: &str, images: &[ToolImage]) -> Value {
    let images: Vec<Value> = images
        .iter()
        .map(|image| {
            let raw = base64::engine::general_purpose::STANDARD
                .decode(&image.data)
                .unwrap_or_else(|_| image.data.as_bytes().to_vec());
            let digest = Sha256::digest(&raw);
            let sha = digest.iter().take(4).fold(String::new(), |mut acc, byte| {
                acc.push_str(&format!("{byte:02x}"));
                acc
            });
            json!({
                "media_type": image.media_type,
                "bytes": raw.len(),
                "sha256_8": sha,
            })
        })
        .collect();
    json!({
        "t": "ToolCall",
        "call_id": id,
        "name": name,
        "args_redacted": { "images": images },
        "ms_to_result": 0,
        "is_error": false,
        "result_bytes": 0,
    })
}

fn record_body(session: &str, id: &str, kind: &str, stages: &[Value]) -> String {
    json!({
        "v": 1,
        "kind": kind,
        "id": id,
        "session": session,
        "started_ms": unix_ms(),
        "ended_ms": unix_ms(),
        "stages": stages,
    })
    .to_string()
}

fn unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|dur| dur.as_millis() as u64)
        .unwrap_or(0)
}

fn hex_session(session: &str) -> String {
    session.bytes().fold(String::new(), |mut acc, byte| {
        acc.push_str(&format!("{byte:02x}"));
        acc
    })
}

fn sanitize_id(id: &str) -> String {
    let mut out = String::new();
    for ch in id.chars().take(80) {
        if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    if out.is_empty() {
        out.push_str("turn");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redaction_hides_secret_keys_and_caps_strings() {
        let mut value = json!({
            "password": "hunter2",
            "note": "x".repeat(600),
            "nested": { "api_token": "abc", "room": "ok" }
        });
        redact_value(&mut value);
        assert_eq!(value["password"], "<redacted>");
        assert_eq!(value["nested"]["api_token"], "<redacted>");
        assert_eq!(value["nested"]["room"], "ok");
        assert_eq!(value["note"].as_str().unwrap().chars().count(), 512);
    }

    #[test]
    fn keep_drops_the_oldest_and_read_skips_unknown_stages() {
        let dir = std::env::temp_dir().join(format!("lav-trace-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let store = TraceStore::open_local(dir.clone(), 2);
        store.write_now(
            "room",
            "a",
            "Turn",
            vec![json!({"t": "ReplySent", "ms": 1})],
        );
        store.write_now(
            "room",
            "b",
            "Turn",
            vec![json!({"t": "Nope"}), json!({"t": "ModelCall", "round": 1})],
        );
        store.write_now(
            "room",
            "c",
            "Turn",
            vec![json!({"t": "ReplySent", "ms": 3})],
        );
        let records = store.read("room", 10);
        assert_eq!(records.len(), 2);
        let stages = records[0]["stages"].as_array().unwrap();
        assert!(stages.iter().all(|stage| stage["t"] != "Nope"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_trace_write_does_not_touch_the_transcript_file() {
        let dir = std::env::temp_dir().join(format!("lav-trace-bytes-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let transcript = dir.join("616263.json");
        let bytes = br#"[{"role":"user","content":"hi"}]"#.to_vec();
        std::fs::write(&transcript, &bytes).unwrap();
        let store = TraceStore::open_local(dir.clone(), 200);
        store.write_now(
            "abc",
            "t1",
            "Turn",
            vec![json!({"t": "ReplySent", "ms": 1})],
        );
        assert_eq!(std::fs::read(&transcript).unwrap(), bytes);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
