//! `lvz-memory` — session memory for the Hermes tier (§7.3).
//!
//! The agent core is per-turn stateless: [`Agent::submit`](lvz_agent::Agent) ignores
//! `TurnRequest::session`. This crate adds the *session* dimension behind a trait without
//! touching the core: a [`SessionStore`] persists each session's conversation transcript, and
//! [`SessionAgent`] wraps an [`Agent`] to load that transcript, seed the turn with it, run,
//! and persist the result — so a gateway's `session` field finally becomes load-bearing and
//! conversations continue across turns.
//!
//! Dependencies point inward only: this is a feature crate over `lvz-agent` + `lvz-protocol`.
//! Two stores ship: a bounded process-local [`InMemoryStore`] and a durable file-backed
//! [`FileStore`]. Long-term / vector recall would be further `SessionStore` implementations
//! behind the same trait.

#![warn(missing_docs)]

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_agent::Agent;
use lvz_protocol::{AgentError, AgentHandle, Event, Message, TurnRequest};
use tokio::sync::Mutex;

/// Trim `history` in place to its most recent `max` messages (no-op if `max` is `None` or the
/// history already fits). Shared by the bounded [`InMemoryStore`] and [`FileStore`].
fn trim_to(history: &mut Vec<Message>, max: Option<usize>) {
    if let Some(max) = max {
        if history.len() > max {
            history.drain(0..history.len() - max);
        }
    }
}

/// Persistence for per-session conversation transcripts. The transcript is the clean
/// user/assistant turn list (no intra-task tool blocks) — what a chat channel shows.
#[async_trait]
pub trait SessionStore: Send + Sync {
    /// Load a session's transcript, or an empty one for an unknown session.
    async fn load(&self, session: &str) -> Vec<Message>;

    /// Replace a session's transcript with `history`.
    async fn save(&self, session: &str, history: Vec<Message>);
}

/// A process-local [`SessionStore`]. Sessions live until the process exits; suitable for a
/// single-node gateway and for tests. Optionally **bounded**: `max_messages` trims each session's
/// transcript to its most recent N messages, and `max_sessions` keeps only the N
/// least-recently-used sessions (evicting the rest). Durable stores (see [`FileStore`]) implement
/// the same trait.
#[derive(Default)]
pub struct InMemoryStore {
    inner: Mutex<MemInner>,
    max_messages: Option<usize>,
    max_sessions: Option<usize>,
}

#[derive(Default)]
struct MemInner {
    sessions: HashMap<String, Vec<Message>>,
    /// LRU order: least-recently-used at the front, most-recently-used at the back.
    order: Vec<String>,
}

impl MemInner {
    /// Move `session` to the most-recently-used position.
    fn touch(&mut self, session: &str) {
        if let Some(i) = self.order.iter().position(|s| s == session) {
            self.order.remove(i);
        }
        self.order.push(session.to_string());
    }
}

impl InMemoryStore {
    /// An unbounded store (sessions and transcripts grow without limit).
    pub fn new() -> Self {
        Self::default()
    }

    /// A bounded store: cap each session to its most recent `max_messages`, and keep at most
    /// `max_sessions` sessions (evicting the least-recently-used). `None` means unbounded.
    pub fn with_limits(max_messages: Option<usize>, max_sessions: Option<usize>) -> Self {
        Self {
            inner: Mutex::new(MemInner::default()),
            max_messages,
            max_sessions,
        }
    }
}

#[async_trait]
impl SessionStore for InMemoryStore {
    async fn load(&self, session: &str) -> Vec<Message> {
        let mut inner = self.inner.lock().await;
        match inner.sessions.get(session).cloned() {
            Some(history) => {
                inner.touch(session); // reading counts as use, for LRU recency
                history
            }
            None => Vec::new(),
        }
    }

    async fn save(&self, session: &str, mut history: Vec<Message>) {
        trim_to(&mut history, self.max_messages);
        let mut inner = self.inner.lock().await;
        inner.sessions.insert(session.to_string(), history);
        inner.touch(session);
        if let Some(max) = self.max_sessions {
            while inner.order.len() > max {
                let evicted = inner.order.remove(0);
                inner.sessions.remove(&evicted);
            }
        }
    }
}

/// A durable, file-backed [`SessionStore`]: each session's transcript is a JSON file under `dir`,
/// so sessions survive process restarts. `max_messages` trims each transcript on save like
/// [`InMemoryStore`]. Session ids are hex-encoded into filenames, so any id (Matrix room ids
/// contain `!`, `:`, `@`) maps to a safe, collision-free path.
pub struct FileStore {
    dir: PathBuf,
    max_messages: Option<usize>,
}

impl FileStore {
    /// Persist sessions under `dir` (created on first save).
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self {
            dir: dir.into(),
            max_messages: None,
        }
    }

    /// Trim each session to its most recent `max_messages` on save (`None` = unbounded).
    pub fn with_max_messages(mut self, max_messages: Option<usize>) -> Self {
        self.max_messages = max_messages;
        self
    }

    fn path_for(&self, session: &str) -> PathBuf {
        let mut name = String::with_capacity(session.len() * 2 + 5);
        for b in session.bytes() {
            name.push_str(&format!("{b:02x}"));
        }
        name.push_str(".json");
        self.dir.join(name)
    }
}

/// Per-process write counter, so each [`atomic_write`] temp file has a unique name even under
/// concurrent writers (paired with the pid it is unique across processes on a shared dir too).
static WRITE_SEQ: AtomicU64 = AtomicU64::new(0);

/// Durably replace `path`'s contents with `bytes`: write a sibling temp file, flush it to disk, then
/// atomically `rename` it over the target.
///
/// `rename(2)` is atomic on POSIX and on EFS/NFS (within one filesystem — hence a temp file in the
/// *same* directory), so a crash mid-write can never leave a torn file, and a concurrent reader sees
/// either the old contents or the new, never a partial mix. This is what stops a mid-write
/// SIGKILL/OOM/task-replacement from truncating a transcript into unparseable JSON that [`load`](FileStore::load)
/// would then read as an empty session.
async fn atomic_write(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use tokio::io::AsyncWriteExt;

    let dir = path.parent().unwrap_or_else(|| Path::new("."));
    let stem = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("session");
    // Hidden, unique-per-write temp name in the same dir: pid + a monotonic counter.
    let tmp = dir.join(format!(
        ".{stem}.{}.{}.tmp",
        std::process::id(),
        WRITE_SEQ.fetch_add(1, Ordering::Relaxed)
    ));

    // Write + flush + fsync the temp file, then swap it in. Clean up the temp file on any failure so
    // a transient error can't litter the dir.
    let write = async {
        let mut f = tokio::fs::File::create(&tmp).await?;
        f.write_all(bytes).await?;
        f.sync_all().await?; // durable before the rename makes it visible
        Ok::<(), std::io::Error>(())
    };
    if let Err(e) = write.await {
        let _ = tokio::fs::remove_file(&tmp).await;
        return Err(e);
    }
    if let Err(e) = tokio::fs::rename(&tmp, path).await {
        let _ = tokio::fs::remove_file(&tmp).await;
        return Err(e);
    }
    Ok(())
}

#[async_trait]
impl SessionStore for FileStore {
    async fn load(&self, session: &str) -> Vec<Message> {
        let path = self.path_for(session);
        let bytes = match tokio::fs::read(&path).await {
            Ok(b) => b,
            // A missing file is the normal "fresh session" case — silent.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Vec::new(),
            // Any other read error (permissions, I/O) is worth surfacing, not swallowing silently.
            Err(e) => {
                tracing::error!(
                    session = %path.display(),
                    error = %e,
                    "cannot read session file; starting empty",
                );
                return Vec::new();
            }
        };
        match serde_json::from_slice(&bytes) {
            Ok(history) => history,
            // A file that exists but won't parse means corruption — a partial write from before
            // atomic saves, external tampering, or disk damage. Do NOT silently reset to empty and
            // let the next save overwrite the evidence: set it aside as `.corrupt` and log loudly, so
            // the transcript loss is visible and recoverable rather than a silent wipe.
            Err(e) => {
                let corrupt = path.with_extension("corrupt");
                tracing::error!(
                    session = %path.display(),
                    error = %e,
                    preserved_as = %corrupt.display(),
                    "session file is corrupt; preserving it and starting empty",
                );
                if let Err(re) = tokio::fs::rename(&path, &corrupt).await {
                    tracing::error!(
                        session = %path.display(),
                        error = %re,
                        "could not set aside corrupt session file",
                    );
                }
                Vec::new()
            }
        }
    }

    async fn save(&self, session: &str, mut history: Vec<Message>) {
        trim_to(&mut history, self.max_messages);
        if let Err(e) = tokio::fs::create_dir_all(&self.dir).await {
            tracing::error!(
                dir = %self.dir.display(),
                error = %e,
                "cannot create session dir",
            );
            return;
        }
        let path = self.path_for(session);
        let bytes = match serde_json::to_vec_pretty(&history) {
            Ok(b) => b,
            Err(e) => {
                tracing::error!(session = %session, error = %e, "cannot serialize session");
                return;
            }
        };
        if let Err(e) = atomic_write(&path, &bytes).await {
            tracing::error!(session = %path.display(), error = %e, "cannot write session");
        }
    }
}

/// A session-aware [`AgentHandle`]: wraps an [`Agent`] and a [`SessionStore`] so each
/// [`submit`](AgentHandle::submit) continues the named session's conversation.
pub struct SessionAgent {
    agent: Arc<Agent>,
    store: Arc<dyn SessionStore>,
}

impl SessionAgent {
    /// Wrap an [`Agent`] and a [`SessionStore`] so each `submit` continues a named session.
    pub fn new(agent: Arc<Agent>, store: Arc<dyn SessionStore>) -> Self {
        Self { agent, store }
    }
}

/// Threaded through the response stream so the conversational turn is persisted exactly once,
/// after a clean completion.
struct Tap {
    inner: BoxStream<'static, Result<Event, AgentError>>,
    store: Arc<dyn SessionStore>,
    session: String,
    /// prior transcript + this turn's user message; the assistant turn is appended on `Done`.
    transcript: Vec<Message>,
    answer: String,
    persisted: bool,
}

#[async_trait]
impl AgentHandle for SessionAgent {
    async fn submit(
        &self,
        turn: TurnRequest,
    ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError> {
        // Seed the task with the session's prior transcript + the new user turn.
        let mut transcript = self.store.load(&turn.session).await;
        transcript.push(Message::user(turn.input));
        let inner = self
            .agent
            .run_seeded_with_tools(transcript.clone(), turn.allowed_tools);

        let tap = Tap {
            inner,
            store: self.store.clone(),
            session: turn.session,
            transcript,
            answer: String::new(),
            persisted: false,
        };

        // Forward every event unchanged; accumulate the assistant's visible text; on the
        // terminal `Done`, append the assistant turn and persist the updated transcript.
        let stream = stream::unfold(tap, |mut tap| async move {
            let item = tap.inner.next().await?;
            if let Ok(Event::TextDelta(text)) = &item {
                tap.answer.push_str(text);
            }
            if matches!(item, Ok(Event::Done(_))) && !tap.persisted {
                tap.transcript
                    .push(Message::assistant(std::mem::take(&mut tap.answer)));
                tap.store
                    .save(&tap.session, std::mem::take(&mut tap.transcript))
                    .await;
                tap.persisted = true;
            }
            Some((item, tap))
        });

        Ok(stream.boxed())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_agent::{Agent, AgentConfig};
    use lvz_protocol::{
        Capabilities, ChatRequest, Provider, ProviderError, Role, StopReason, Usage,
    };
    use lvz_tools::ToolRegistry;
    use std::sync::Mutex as StdMutex;

    /// A provider that records how many messages each request carried, then replies with a
    /// fixed one-round-trip answer (no tool calls).
    struct StubProvider {
        seen: Arc<StdMutex<Vec<usize>>>,
    }

    #[async_trait]
    impl Provider for StubProvider {
        async fn stream(
            &self,
            req: ChatRequest,
        ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
            self.seen.lock().unwrap().push(req.messages.len());
            let events = vec![
                Ok(Event::TextDelta("reply".into())),
                Ok(Event::Usage(Usage::default())),
                Ok(Event::Done(StopReason::EndTurn)),
            ];
            Ok(stream::iter(events).boxed())
        }

        fn capabilities(&self) -> Capabilities {
            Capabilities::default()
        }
    }

    async fn drain(stream: BoxStream<'static, Result<Event, AgentError>>) {
        let mut stream = stream;
        while stream.next().await.is_some() {}
    }

    #[tokio::test]
    async fn in_memory_store_roundtrips() {
        let store = InMemoryStore::new();
        assert!(store.load("missing").await.is_empty());
        store.save("s", vec![Message::user("hi")]).await;
        let back = store.load("s").await;
        assert_eq!(back.len(), 1);
        assert!(matches!(back[0].role, Role::User));
    }

    #[tokio::test]
    async fn max_messages_keeps_most_recent() {
        let store = InMemoryStore::with_limits(Some(2), None);
        let history = vec![
            Message::user("1"),
            Message::assistant("2"),
            Message::user("3"),
        ];
        store.save("s", history).await;
        let back = store.load("s").await;
        assert_eq!(back.len(), 2);
        assert_eq!(back[0].text(), "2");
        assert_eq!(back[1].text(), "3");
    }

    #[tokio::test]
    async fn max_sessions_evicts_least_recently_used() {
        let store = InMemoryStore::with_limits(None, Some(2));
        store.save("a", vec![Message::user("a")]).await;
        store.save("b", vec![Message::user("b")]).await;
        // Touch `a` so `b` becomes the least-recently-used.
        let _ = store.load("a").await;
        store.save("c", vec![Message::user("c")]).await; // evicts `b`
        assert!(!store.load("a").await.is_empty());
        assert!(store.load("b").await.is_empty());
        assert!(!store.load("c").await.is_empty());
    }

    #[tokio::test]
    async fn file_store_persists_across_instances_and_trims() {
        let dir = std::env::temp_dir().join(format!("lvz-memtest-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let session = "!room:hs"; // exercises filename encoding of unsafe chars

        let writer = FileStore::new(&dir).with_max_messages(Some(2));
        writer
            .save(
                session,
                vec![
                    Message::user("1"),
                    Message::assistant("2"),
                    Message::user("3"),
                ],
            )
            .await;

        // A fresh instance over the same dir reads it back (durability), trimmed to 2.
        let reader = FileStore::new(&dir);
        let back = reader.load(session).await;
        assert_eq!(back.len(), 2);
        assert_eq!(back[1].text(), "3");
        assert!(reader.load("never-written").await.is_empty());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn file_store_corrupt_file_is_preserved_not_silently_wiped() {
        let dir = std::env::temp_dir().join(format!("lvz-memtest-corrupt-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let session = "!room:hs";

        let store = FileStore::new(&dir);
        let path = store.path_for(session);

        // Simulate a crash mid-write (pre-atomic behaviour): a truncated, unparseable file.
        std::fs::write(&path, b"[{\"role\":\"user\",\"con").unwrap();

        // load must not panic or return garbage — it starts empty …
        assert!(store.load(session).await.is_empty());
        // … and must NOT have silently discarded the evidence: the bad file is set aside, the live
        // path is freed for a fresh save.
        let corrupt = path.with_extension("corrupt");
        assert!(corrupt.exists(), "corrupt file preserved as .corrupt");
        assert!(!path.exists(), "corrupt file moved off the live path");

        // A subsequent save writes a valid transcript and leaves the preserved evidence intact.
        store.save(session, vec![Message::user("fresh")]).await;
        assert_eq!(store.load(session).await.len(), 1);
        assert!(
            corrupt.exists(),
            "preserved evidence survives the next save"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn file_store_atomic_write_leaves_no_temp_files() {
        let dir = std::env::temp_dir().join(format!("lvz-memtest-atomic-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let store = FileStore::new(&dir);

        store.save("s", vec![Message::user("hi")]).await;

        // The temp file was renamed into place, not left behind.
        let leftover: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .collect();
        assert!(leftover.is_empty(), "no .tmp litter after an atomic save");
        assert_eq!(store.load("s").await.len(), 1);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn session_agent_persists_and_seeds_the_next_turn() {
        let seen = Arc::new(StdMutex::new(Vec::new()));
        let provider = Arc::new(StubProvider { seen: seen.clone() });
        let agent = Arc::new(Agent::new(
            provider,
            ToolRegistry::with_builtins(),
            AgentConfig::default(),
        ));
        let store: Arc<dyn SessionStore> = Arc::new(InMemoryStore::new());
        let session = SessionAgent::new(agent, store.clone());

        drain(
            session
                .submit(TurnRequest::new("s", "first"))
                .await
                .unwrap(),
        )
        .await;
        drain(
            session
                .submit(TurnRequest::new("s", "second"))
                .await
                .unwrap(),
        )
        .await;

        // The transcript accumulated both exchanges: user/assistant/user/assistant.
        let transcript = store.load("s").await;
        assert_eq!(transcript.len(), 4);
        assert_eq!(transcript[0].text(), "first");
        assert_eq!(transcript[1].text(), "reply");
        assert_eq!(transcript[2].text(), "second");

        // The second turn was seeded with the prior exchange: 1 message first, 3 the second.
        assert_eq!(*seen.lock().unwrap(), vec![1, 3]);

        // Distinct sessions stay isolated.
        drain(
            session
                .submit(TurnRequest::new("other", "x"))
                .await
                .unwrap(),
        )
        .await;
        assert_eq!(store.load("other").await.len(), 2);
    }
}
