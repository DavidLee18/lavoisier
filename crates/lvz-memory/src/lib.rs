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
//! Long-term / vector recall would be further `SessionStore` implementations behind the same
//! trait; only the in-memory store ships today.

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_agent::Agent;
use lvz_protocol::{AgentError, AgentHandle, Event, Message, TurnRequest};
use tokio::sync::Mutex;

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
/// single-node gateway and for tests. Durable stores implement the same trait.
#[derive(Default)]
pub struct InMemoryStore {
    sessions: Mutex<HashMap<String, Vec<Message>>>,
}

impl InMemoryStore {
    pub fn new() -> Self {
        Self::default()
    }
}

#[async_trait]
impl SessionStore for InMemoryStore {
    async fn load(&self, session: &str) -> Vec<Message> {
        self.sessions
            .lock()
            .await
            .get(session)
            .cloned()
            .unwrap_or_default()
    }

    async fn save(&self, session: &str, history: Vec<Message>) {
        self.sessions
            .lock()
            .await
            .insert(session.to_string(), history);
    }
}

/// A session-aware [`AgentHandle`]: wraps an [`Agent`] and a [`SessionStore`] so each
/// [`submit`](AgentHandle::submit) continues the named session's conversation.
pub struct SessionAgent {
    agent: Arc<Agent>,
    store: Arc<dyn SessionStore>,
}

impl SessionAgent {
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
        let inner = self.agent.run_seeded(transcript.clone());

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
