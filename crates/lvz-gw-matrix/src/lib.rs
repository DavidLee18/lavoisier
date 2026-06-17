//! `lvz-gw-matrix` — a Matrix gateway (§7.2): a chat-driven frontend for the
//! shared agent on your homeserver (e.g. Continuwuity).
//!
//! Deliberately a **thin** client over the Matrix client-server REST API (`reqwest` + JSON),
//! not the heavyweight `matrix-sdk` — mirroring the hand-rolled provider adapters and the
//! project's minimal-dependency convention. It logs in with a password, long-polls `/sync`,
//! and for each inbound `m.room.message` (`m.text`) from another user runs an agent turn
//! (session = room id, so [`lvz-memory`] keeps per-room continuity) and posts the answer back.
//!
//! Scope: unencrypted rooms by default. **End-to-end encryption is opt-in** behind the `e2ee`
//! Cargo feature (Olm/Megolm via the crypto-only `matrix-sdk-crypto`, contained to [`e2ee`]);
//! without it the gateway is a thin REST client. Depends only on `lvz-protocol`; the agent core
//! stays unaware of Matrix.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use futures::stream::StreamExt;
use lvz_protocol::{AgentHandle, Event, Gateway, GatewayError, TurnRequest};
use serde::Deserialize;

#[cfg(feature = "e2ee")]
mod e2ee;

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
            device_id: login.device_id,
        })
    }

    /// One `/sync` round-trip, returned as raw JSON. `since = None` establishes a baseline
    /// (backlog discarded). The raw value is parsed into [`SyncResponse`] for message extraction
    /// and (under `e2ee`) fed to the crypto layer for to-device/device-list processing.
    async fn sync_once(
        &self,
        token: &str,
        since: Option<&str>,
    ) -> Result<serde_json::Value, GatewayError> {
        let mut req = self
            .http
            .get(self.url("/_matrix/client/v3/sync"))
            .bearer_auth(token)
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
        token: &str,
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
            .bearer_auth(token)
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

    /// Run one inbound message through the agent; return its trimmed answer (or `None` if the
    /// agent errored or produced nothing). Sending the answer is the caller's job, so plaintext
    /// and encrypted rooms share this path and differ only in how the reply goes out.
    async fn run_agent(
        &self,
        agent: &Arc<dyn AgentHandle>,
        room: &str,
        body: String,
    ) -> Option<String> {
        let turn = TurnRequest::new(room.to_string(), body);
        let mut stream = match agent.submit(turn).await {
            Ok(stream) => stream,
            Err(e) => {
                eprintln!("matrix: agent error in {room}: {e}");
                return None;
            }
        };
        let mut answer = String::new();
        while let Some(item) = stream.next().await {
            match item {
                Ok(Event::TextDelta(text)) => answer.push_str(&text),
                Ok(_) => {}
                Err(e) => {
                    eprintln!("matrix: stream error in {room}: {e}");
                    break;
                }
            }
        }
        let answer = answer.trim();
        (!answer.is_empty()).then(|| answer.to_string())
    }
}

#[async_trait]
impl Gateway for MatrixGateway {
    fn name(&self) -> &str {
        "matrix"
    }

    async fn serve(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError> {
        // `#[async_trait]` boxes this method's future and requires it `Send` for *every* lifetime
        // of the borrows awaited within — a higher-ranked form the matrix-sdk-crypto futures don't
        // satisfy. Delegating to a plain inherent async fn (whose `Send` is inferred concretely,
        // and which owns its arguments) sidesteps it.
        self.serve_loop(agent).await
    }
}

impl MatrixGateway {
    /// The gateway's serve loop, as a plain (non-`async_trait`) async fn — see [`Gateway::serve`].
    async fn serve_loop(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError> {
        let session = self.login().await?;
        eprintln!(
            "lavoisier: matrix gateway online as {} on {}",
            session.user_id, self.homeserver
        );
        // Own the fields used across awaits so a `&Session` is never held across one (keeps the
        // async_trait future unconditionally `Send`).
        let token = session.access_token.clone();
        let self_user = session.user_id.clone();

        // Opt-in E2EE: bind an OlmMachine to this session and publish keys. If init fails we log
        // and continue in plaintext-only mode rather than abort the gateway.
        #[cfg(feature = "e2ee")]
        let crypto = match e2ee::Crypto::new(
            self.homeserver.clone(),
            token.clone(),
            &session.user_id,
            &session.device_id,
        )
        .await
        {
            Ok(c) => {
                eprintln!("lavoisier: matrix E2EE enabled");
                Some(c)
            }
            Err(e) => {
                eprintln!("matrix[e2ee]: init failed, continuing without encryption: {e}");
                None
            }
        };

        // Baseline sync: take a `since` token and discard any backlog so we only act on
        // messages that arrive from now on.
        let baseline = self.sync_once(&token, None).await?;
        let mut since = parse_next_batch(&baseline)?;

        loop {
            let value = match self.sync_once(&token, Some(&since)).await {
                Ok(value) => value,
                Err(e) => {
                    // Transient sync failure: back off briefly and retry rather than exit.
                    eprintln!("matrix: {e}; retrying");
                    tokio::time::sleep(Duration::from_secs(3)).await;
                    continue;
                }
            };

            // Feed encryption changes (to-device, device lists, key counts) before acting.
            #[cfg(feature = "e2ee")]
            if let Some(c) = &crypto {
                if let Err(e) = c.receive_sync(&value).await {
                    eprintln!("matrix[e2ee]: {e}");
                }
            }

            let next = parse_next_batch(&value)?;
            let resp = match SyncResponse::deserialize(&value) {
                Ok(resp) => resp,
                Err(e) => {
                    eprintln!("matrix: malformed sync: {e}");
                    since = next;
                    continue;
                }
            };

            // Plaintext messages: run the agent and reply in the clear.
            for msg in extract_messages(resp, &self_user) {
                if let Some(answer) = self.run_agent(&agent, &msg.room, msg.body).await {
                    if let Err(e) = self.send_message(&token, &msg.room, &answer).await {
                        eprintln!("matrix: send error in {}: {e}", msg.room);
                    }
                }
            }

            // Encrypted messages: decrypt, run the agent, and reply encrypted.
            #[cfg(feature = "e2ee")]
            if let Some(c) = &crypto {
                for (room, body) in c.decrypt_messages(&value, self_user.clone()).await {
                    if let Some(answer) = self.run_agent(&agent, &room, body).await {
                        if let Err(e) = c.encrypt_and_send(room.clone(), answer).await {
                            eprintln!("matrix[e2ee]: send error in {room}: {e}");
                        }
                    }
                }
            }

            since = next;
        }
    }
}

/// Pull the `next_batch` token out of a raw sync response.
fn parse_next_batch(sync: &serde_json::Value) -> Result<String, GatewayError> {
    sync.get("next_batch")
        .and_then(|v| v.as_str())
        .map(String::from)
        .ok_or_else(|| GatewayError::Protocol("sync response missing next_batch".into()))
}

/// A logged-in session.
struct Session {
    access_token: String,
    user_id: String,
    /// The device id the homeserver assigned this login (needed to bind the E2EE `OlmMachine`).
    #[cfg_attr(not(feature = "e2ee"), allow(dead_code))]
    device_id: String,
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
pub(crate) fn urlencode(segment: &str) -> String {
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
    #[serde(default)]
    device_id: String,
}

#[derive(Deserialize)]
struct SyncResponse {
    // `next_batch` is read from the raw sync JSON via `parse_next_batch` (so the sync token still
    // advances even if this typed view fails to deserialize); this struct is just for messages.
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
    fn empty_sync_yields_no_messages_and_parses_next_batch() {
        let value = serde_json::json!({ "next_batch": "s5" });
        assert_eq!(parse_next_batch(&value).unwrap(), "s5");
        let sync: SyncResponse = serde_json::from_value(value).unwrap();
        assert!(extract_messages(sync, "@bot:hs").is_empty());
    }

    #[test]
    fn missing_next_batch_is_an_error() {
        assert!(parse_next_batch(&serde_json::json!({})).is_err());
    }

    #[test]
    fn urlencodes_room_id_special_chars() {
        assert_eq!(urlencode("!abc:hs"), "%21abc%3Ahs");
        assert_eq!(urlencode("plain-id_1.0~"), "plain-id_1.0~");
    }
}
