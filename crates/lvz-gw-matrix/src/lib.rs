//! `lvz-gw-matrix` — a Matrix gateway (§7.2): a chat-driven frontend for the
//! shared agent on your homeserver (e.g. Continuwuity).
//!
//! Deliberately a **thin** client over the Matrix client-server REST API (`reqwest` + JSON),
//! not the heavyweight `matrix-sdk` — mirroring the hand-rolled provider adapters and the
//! project's minimal-dependency convention. It logs in with a password, long-polls `/sync`,
//! and for each inbound `m.room.message` (`m.text`) from another user runs an agent turn
//! (session = room id, so [`lvz-memory`] keeps per-room continuity) and posts the answer back.
//!
//! Scope: **unencrypted rooms only** (no E2EE — that is what `matrix-sdk` exists for). Depends
//! only on `lvz-protocol`; the agent core stays unaware of Matrix.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use futures::stream::StreamExt;
use lvz_protocol::{AgentHandle, Event, Gateway, GatewayError, TurnRequest};
use serde::Deserialize;

/// Long-poll window for `/sync` (ms). The server holds the request open until an event
/// arrives or this elapses.
const SYNC_TIMEOUT_MS: u64 = 30_000;

/// A Matrix gateway bound to a homeserver and a bot account.
pub struct MatrixGateway {
    homeserver: String,
    user: String,
    password: String,
    http: reqwest::Client,
    txn: AtomicU64,
}

impl MatrixGateway {
    /// Construct against a homeserver base URL (e.g. `https://matrix.example.org`) and the
    /// bot's login (`user` may be a localpart or a full `@user:server` id).
    pub fn new(
        homeserver: impl Into<String>,
        user: impl Into<String>,
        password: impl Into<String>,
    ) -> Self {
        Self {
            homeserver: homeserver.into().trim_end_matches('/').to_string(),
            user: user.into(),
            password: password.into(),
            http: reqwest::Client::new(),
            txn: AtomicU64::new(0),
        }
    }

    /// Construct from the environment: `MATRIX_HOMESERVER`, `MATRIX_USER`, `MATRIX_PASSWORD`.
    pub fn from_env() -> Result<Self, GatewayError> {
        let var =
            |k: &str| std::env::var(k).map_err(|_| GatewayError::Bind(format!("{k} is not set")));
        Ok(Self::new(
            var("MATRIX_HOMESERVER")?,
            var("MATRIX_USER")?,
            var("MATRIX_PASSWORD")?,
        ))
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.homeserver, path)
    }

    /// Password-login; returns the access token + resolved user id.
    async fn login(&self) -> Result<Session, GatewayError> {
        let body = serde_json::json!({
            "type": "m.login.password",
            "identifier": { "type": "m.id.user", "user": self.user },
            "password": self.password,
        });
        let resp = self
            .http
            .post(self.url("/_matrix/client/v3/login"))
            .json(&body)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Bind(format!("matrix login {status}: {msg}")));
        }
        let login: LoginResponse = resp
            .json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))?;
        Ok(Session {
            access_token: login.access_token,
            user_id: login.user_id,
        })
    }

    /// One `/sync` round-trip. `since = None` establishes a baseline (backlog discarded).
    async fn sync_once(
        &self,
        session: &Session,
        since: Option<&str>,
    ) -> Result<SyncResponse, GatewayError> {
        let mut req = self
            .http
            .get(self.url("/_matrix/client/v3/sync"))
            .bearer_auth(&session.access_token)
            .query(&[("timeout", SYNC_TIMEOUT_MS.to_string())]);
        if let Some(since) = since {
            req = req.query(&[("since", since)]);
        }
        let resp = req
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Io(format!("matrix sync {status}: {msg}")));
        }
        resp.json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))
    }

    /// Post a plain-text message to a room.
    async fn send_message(
        &self,
        session: &Session,
        room_id: &str,
        body: &str,
    ) -> Result<(), GatewayError> {
        let txn = self.txn.fetch_add(1, Ordering::Relaxed);
        let path = format!(
            "/_matrix/client/v3/rooms/{}/send/m.room.message/lvz{}",
            urlencode(room_id),
            txn
        );
        let payload = serde_json::json!({ "msgtype": "m.text", "body": body });
        let resp = self
            .http
            .put(self.url(&path))
            .bearer_auth(&session.access_token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Io(format!("matrix send {status}: {msg}")));
        }
        Ok(())
    }

    /// Run one inbound message through the agent and post the answer back to its room.
    async fn handle_message(
        &self,
        session: &Session,
        agent: &Arc<dyn AgentHandle>,
        msg: IncomingMessage,
    ) {
        let turn = TurnRequest::new(msg.room.clone(), msg.body);
        let mut stream = match agent.submit(turn).await {
            Ok(stream) => stream,
            Err(e) => {
                eprintln!("matrix: agent error in {}: {e}", msg.room);
                return;
            }
        };
        let mut answer = String::new();
        while let Some(item) = stream.next().await {
            match item {
                Ok(Event::TextDelta(text)) => answer.push_str(&text),
                Ok(_) => {}
                Err(e) => {
                    eprintln!("matrix: stream error in {}: {e}", msg.room);
                    break;
                }
            }
        }
        let answer = answer.trim();
        if !answer.is_empty() {
            if let Err(e) = self.send_message(session, &msg.room, answer).await {
                eprintln!("matrix: send error in {}: {e}", msg.room);
            }
        }
    }
}

#[async_trait]
impl Gateway for MatrixGateway {
    fn name(&self) -> &str {
        "matrix"
    }

    async fn serve(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError> {
        let session = self.login().await?;
        eprintln!(
            "lavoisier: matrix gateway online as {} on {}",
            session.user_id, self.homeserver
        );

        // Baseline sync: take a `since` token and discard any backlog so we only act on
        // messages that arrive from now on.
        let mut since = self.sync_once(&session, None).await?.next_batch;

        loop {
            let resp = match self.sync_once(&session, Some(&since)).await {
                Ok(resp) => resp,
                Err(e) => {
                    // Transient sync failure: back off briefly and retry rather than exit.
                    eprintln!("matrix: {e}; retrying");
                    tokio::time::sleep(Duration::from_secs(3)).await;
                    continue;
                }
            };
            let next = resp.next_batch.clone();
            for msg in extract_messages(resp, &session.user_id) {
                self.handle_message(&session, &agent, msg).await;
            }
            since = next;
        }
    }
}

/// A logged-in session.
struct Session {
    access_token: String,
    user_id: String,
}

/// One inbound text message worth answering.
#[derive(Debug, PartialEq, Eq)]
struct IncomingMessage {
    room: String,
    sender: String,
    body: String,
}

/// Pull the answerable `m.room.message`/`m.text` events out of a sync response, skipping the
/// bot's own messages (so it never replies to itself).
fn extract_messages(sync: SyncResponse, self_user: &str) -> Vec<IncomingMessage> {
    let mut out = Vec::new();
    for (room_id, room) in sync.rooms.join {
        for event in room.timeline.events {
            if event.kind != "m.room.message" || event.sender == self_user {
                continue;
            }
            if event.content.msgtype.as_deref() != Some("m.text") {
                continue;
            }
            if let Some(body) = event.content.body {
                out.push(IncomingMessage {
                    room: room_id.clone(),
                    sender: event.sender,
                    body,
                });
            }
        }
    }
    out
}

/// Percent-encode a path segment (room ids contain `!`, `:` and `@`).
fn urlencode(segment: &str) -> String {
    let mut out = String::with_capacity(segment.len());
    for byte in segment.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

// --- Matrix client-server wire types (the only place this shape is known) ---

#[derive(Deserialize)]
struct LoginResponse {
    access_token: String,
    user_id: String,
}

#[derive(Deserialize)]
struct SyncResponse {
    next_batch: String,
    #[serde(default)]
    rooms: Rooms,
}

#[derive(Deserialize, Default)]
struct Rooms {
    #[serde(default)]
    join: HashMap<String, JoinedRoom>,
}

#[derive(Deserialize, Default)]
struct JoinedRoom {
    #[serde(default)]
    timeline: Timeline,
}

#[derive(Deserialize, Default)]
struct Timeline {
    #[serde(default)]
    events: Vec<SyncEvent>,
}

#[derive(Deserialize)]
struct SyncEvent {
    #[serde(rename = "type")]
    kind: String,
    sender: String,
    #[serde(default)]
    content: EventContent,
}

#[derive(Deserialize, Default)]
struct EventContent {
    #[serde(default)]
    msgtype: Option<String>,
    #[serde(default)]
    body: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sync_from(json: serde_json::Value) -> SyncResponse {
        serde_json::from_value(json).unwrap()
    }

    #[test]
    fn extracts_text_messages_and_skips_self_and_non_text() {
        let sync = sync_from(serde_json::json!({
            "next_batch": "s2",
            "rooms": { "join": { "!room:hs": { "timeline": { "events": [
                { "type": "m.room.message", "sender": "@alice:hs",
                  "content": { "msgtype": "m.text", "body": "hello bot" } },
                { "type": "m.room.message", "sender": "@bot:hs",
                  "content": { "msgtype": "m.text", "body": "my own message" } },
                { "type": "m.room.message", "sender": "@alice:hs",
                  "content": { "msgtype": "m.image", "body": "pic.png" } },
                { "type": "m.room.member", "sender": "@alice:hs",
                  "content": { "membership": "join" } }
            ] } } } }
        }));

        let msgs = extract_messages(sync, "@bot:hs");
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].room, "!room:hs");
        assert_eq!(msgs[0].sender, "@alice:hs");
        assert_eq!(msgs[0].body, "hello bot");
    }

    #[test]
    fn empty_sync_yields_no_messages_and_keeps_next_batch() {
        let sync = sync_from(serde_json::json!({ "next_batch": "s5" }));
        assert_eq!(sync.next_batch, "s5");
        assert!(extract_messages(sync, "@bot:hs").is_empty());
    }

    #[test]
    fn urlencodes_room_id_special_chars() {
        assert_eq!(urlencode("!abc:hs"), "%21abc%3Ahs");
        assert_eq!(urlencode("plain-id_1.0~"), "plain-id_1.0~");
    }
}
