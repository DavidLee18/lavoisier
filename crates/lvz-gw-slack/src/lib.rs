//! `lvz-gw-slack` — a Slack gateway (§7) driving the shared agent over **Socket Mode**.
//!
//! Like the Matrix gateway it is a deliberately **thin** client — no heavyweight Slack SDK, just
//! `reqwest` for the Web API and `tokio-tungstenite` for the Socket Mode WebSocket — mirroring the
//! hand-rolled provider adapters and the project's minimal-dependency convention. Socket Mode means
//! there is **no inbound port**: the bot opens an outbound WebSocket (`apps.connections.open`),
//! receives `message`/`app_mention` events over it, runs an agent turn, and posts the reply with
//! `chat.postMessage`.
//!
//! Sessions are keyed per channel (or per thread, when a message is in a thread), so [`lvz-memory`]
//! gives each conversation continuity — the same way the Matrix gateway keys a session per room.
//! Depends only on [`lvz_protocol`]; the agent core stays unaware of Slack.
//!
//! ## Auth
//! Two tokens (Socket Mode apps): an **app-level token** (`xapp-…`, `SLACK_APP_TOKEN`) to open the
//! socket, and a **bot token** (`xoxb-…`, `SLACK_BOT_TOKEN`) for Web API calls. An optional
//! `SLACK_ALLOWED_USERS` allowlist restricts who can drive the agent (shared semantics with the
//! Matrix gateway).

use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use futures::{SinkExt, StreamExt};
use lvz_protocol::{AgentHandle, Event, Gateway, GatewayError, TurnRequest};
use serde_json::Value;
use tokio_tungstenite::tungstenite::Message;

const WEB_API: &str = "https://slack.com/api";

/// A Slack gateway bound to a workspace via an app-level token (Socket Mode) and a bot token.
pub struct SlackGateway {
    /// App-level token (`xapp-…`) used to open the Socket Mode connection.
    app_token: String,
    /// Bot token (`xoxb-…`) used for Web API calls (`auth.test`, `chat.postMessage`).
    bot_token: String,
    http: reqwest::Client,
    /// If set, only answer messages whose sender is in this allowlist. `None` ⇒ answer everyone.
    allowed_users: Option<HashSet<String>>,
}

impl SlackGateway {
    /// Construct from the two tokens.
    pub fn new(app_token: impl Into<String>, bot_token: impl Into<String>) -> Self {
        Self {
            app_token: app_token.into(),
            bot_token: bot_token.into(),
            http: reqwest::Client::new(),
            allowed_users: None,
        }
    }

    /// Construct from the environment: `SLACK_APP_TOKEN`, `SLACK_BOT_TOKEN`, and the optional
    /// comma-separated `SLACK_ALLOWED_USERS`.
    pub fn from_env() -> Result<Self, GatewayError> {
        let require =
            |k: &str| std::env::var(k).map_err(|_| GatewayError::Bind(format!("{k} is not set")));
        let mut gw = Self::new(require("SLACK_APP_TOKEN")?, require("SLACK_BOT_TOKEN")?);
        if let Ok(users) = std::env::var("SLACK_ALLOWED_USERS") {
            gw = gw.with_allowed_users(users.split(',').map(|s| s.trim().to_string()));
        }
        Ok(gw)
    }

    /// Restrict which senders the bot answers. An empty list clears the restriction (answer
    /// everyone); any non-empty list means only those Slack user ids drive the agent.
    pub fn with_allowed_users(mut self, users: impl IntoIterator<Item = String>) -> Self {
        let set: HashSet<String> = users.into_iter().filter(|u| !u.is_empty()).collect();
        self.allowed_users = (!set.is_empty()).then_some(set);
        self
    }

    /// `POST {WEB_API}/<method>` with the bot token and a JSON body; returns the parsed response.
    /// Slack signals app-level failure with `{"ok": false, "error": ...}` even on HTTP 200, so the
    /// caller must check `ok`.
    async fn web_post(&self, method: &str, body: &Value) -> Result<Value, GatewayError> {
        let resp = self
            .http
            .post(format!("{WEB_API}/{method}"))
            .bearer_auth(&self.bot_token)
            .json(body)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        resp.json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))
    }

    /// Resolve our own bot user id (so we never answer our own messages) via `auth.test`.
    async fn bot_user_id(&self) -> Result<String, GatewayError> {
        let resp = self.web_post("auth.test", &serde_json::json!({})).await?;
        if resp.get("ok").and_then(Value::as_bool) != Some(true) {
            return Err(GatewayError::Bind(format!(
                "slack auth.test failed: {}",
                resp.get("error")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
            )));
        }
        resp.get("user_id")
            .and_then(Value::as_str)
            .map(String::from)
            .ok_or_else(|| GatewayError::Protocol("auth.test missing user_id".into()))
    }

    /// Open a Socket Mode connection and return its `wss://` URL (`apps.connections.open` is an
    /// **app-level-token** call, so it doesn't use [`web_post`]'s bot token).
    async fn open_connection(&self) -> Result<String, GatewayError> {
        let resp = self
            .http
            .post(format!("{WEB_API}/apps.connections.open"))
            .bearer_auth(&self.app_token)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?
            .json::<Value>()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))?;
        if resp.get("ok").and_then(Value::as_bool) != Some(true) {
            return Err(GatewayError::Bind(format!(
                "slack apps.connections.open failed: {}",
                resp.get("error")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
            )));
        }
        resp.get("url")
            .and_then(Value::as_str)
            .map(String::from)
            .ok_or_else(|| GatewayError::Protocol("connections.open missing url".into()))
    }

    /// Post a reply to a channel, threading it under `thread_ts` when the trigger was in a thread.
    async fn post_message(&self, channel: &str, thread_ts: Option<&str>, text: &str) {
        let mut body = serde_json::json!({ "channel": channel, "text": text });
        if let Some(ts) = thread_ts {
            body["thread_ts"] = Value::String(ts.to_string());
        }
        match self.web_post("chat.postMessage", &body).await {
            Ok(resp) if resp.get("ok").and_then(Value::as_bool) == Some(true) => {}
            Ok(resp) => eprintln!(
                "slack: chat.postMessage failed: {}",
                resp.get("error")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
            ),
            Err(e) => eprintln!("slack: chat.postMessage error: {e}"),
        }
    }

    /// Run one inbound message through the agent and post the reply. Spawned per message so the
    /// read loop stays responsive (Socket Mode requires prompt acks + ping/pong keepalive while a
    /// turn — which can be slow — runs).
    async fn handle_turn(self: Arc<Self>, agent: Arc<dyn AgentHandle>, msg: SlackMessage) {
        let turn = TurnRequest::new(msg.session(), msg.text.clone());
        let mut stream = match agent.submit(turn).await {
            Ok(s) => s,
            Err(e) => {
                eprintln!("slack: agent error in {}: {e}", msg.channel);
                return;
            }
        };
        let mut answer = String::new();
        while let Some(item) = stream.next().await {
            match item {
                Ok(Event::TextDelta(t)) => answer.push_str(&t),
                Ok(_) => {}
                Err(e) => {
                    eprintln!("slack: stream error in {}: {e}", msg.channel);
                    break;
                }
            }
        }
        let answer = answer.trim();
        if !answer.is_empty() {
            self.post_message(&msg.channel, msg.thread_ts.as_deref(), answer)
                .await;
        }
    }
}

#[async_trait]
impl Gateway for SlackGateway {
    fn name(&self) -> &str {
        "slack"
    }

    async fn serve(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError> {
        self.serve_loop(agent).await
    }
}

impl SlackGateway {
    /// The serve loop: resolve our identity, then keep a Socket Mode connection alive (reconnecting
    /// on the periodic `disconnect` refresh or on error), dispatching each event to the agent.
    async fn serve_loop(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError> {
        let bot_user = self.bot_user_id().await?;
        eprintln!("lavoisier: slack gateway online as {bot_user}");
        if let Some(allowed) = &self.allowed_users {
            eprintln!(
                "slack: answering only {} allowlisted user(s)",
                allowed.len()
            );
        }
        loop {
            if let Err(e) = self.clone().run_connection(&agent, &bot_user).await {
                // Transient connection failure: back off briefly and reconnect rather than exit.
                eprintln!("slack: {e}; reconnecting in 3s");
                tokio::time::sleep(Duration::from_secs(3)).await;
            }
        }
    }

    /// Open one Socket Mode WebSocket and pump it until it closes or the server asks us to
    /// reconnect (`disconnect`). Errors bubble up so [`serve_loop`] can back off and retry.
    async fn run_connection(
        self: Arc<Self>,
        agent: &Arc<dyn AgentHandle>,
        bot_user: &str,
    ) -> Result<(), GatewayError> {
        let url = self.open_connection().await?;
        let (ws, _) = tokio_tungstenite::connect_async(&url)
            .await
            .map_err(|e| GatewayError::Io(format!("slack socket connect: {e}")))?;
        let (mut write, mut read) = ws.split();
        eprintln!("slack: socket connected");

        while let Some(frame) = read.next().await {
            let msg = frame.map_err(|e| GatewayError::Io(format!("slack socket read: {e}")))?;
            match msg {
                Message::Text(text) => {
                    let Ok(value) = serde_json::from_str::<Value>(&text) else {
                        continue;
                    };
                    match value.get("type").and_then(Value::as_str) {
                        Some("hello") => {}
                        // The server periodically refreshes the connection; reopen a new one.
                        Some("disconnect") => return Ok(()),
                        Some("events_api") => {
                            // ACK first (Slack expects it within ~3s), then handle out-of-band.
                            if let Some(id) = value.get("envelope_id").and_then(Value::as_str) {
                                let ack = serde_json::json!({ "envelope_id": id }).to_string();
                                write
                                    .send(Message::Text(ack.into()))
                                    .await
                                    .map_err(|e| GatewayError::Io(format!("slack ack: {e}")))?;
                            }
                            if let Some(payload) = value.get("payload") {
                                if let Some(parsed) =
                                    parse_event(payload, bot_user, self.allowed_users.as_ref())
                                {
                                    // Run the turn off the read loop so acks/pings keep flowing.
                                    let me = Arc::clone(&self);
                                    let agent = agent.clone();
                                    tokio::spawn(me.handle_turn(agent, parsed));
                                }
                            }
                        }
                        // slash_commands / interactive / unknown: acked-and-ignored (out of scope).
                        _ => {
                            if let Some(id) = value.get("envelope_id").and_then(Value::as_str) {
                                let ack = serde_json::json!({ "envelope_id": id }).to_string();
                                let _ = write.send(Message::Text(ack.into())).await;
                            }
                        }
                    }
                }
                Message::Ping(payload) => {
                    write
                        .send(Message::Pong(payload))
                        .await
                        .map_err(|e| GatewayError::Io(format!("slack pong: {e}")))?;
                }
                Message::Close(_) => return Ok(()),
                _ => {}
            }
        }
        Ok(())
    }
}

/// One inbound Slack message worth answering.
#[derive(Debug, PartialEq, Eq)]
struct SlackMessage {
    channel: String,
    /// Present when the message is in a thread; the reply is threaded under it and the session is
    /// keyed by it (so a thread is its own conversation).
    thread_ts: Option<String>,
    text: String,
}

impl SlackMessage {
    /// Session id: per-thread when threaded, else per-channel.
    fn session(&self) -> String {
        match &self.thread_ts {
            Some(ts) => format!("slack:{}:{ts}", self.channel),
            None => format!("slack:{}", self.channel),
        }
    }
}

/// Whether `user` may drive the agent: true if no allowlist is configured, else membership.
fn sender_allowed(allowed: Option<&HashSet<String>>, user: &str) -> bool {
    allowed.is_none_or(|set| set.contains(user))
}

/// Parse a Socket Mode `events_api` payload into an answerable message, or `None` to skip it.
/// Skips non-`message`/`app_mention` events, bot/edited/system messages, our own messages, and
/// (when an allowlist is set) non-allowlisted senders. A leading bot @mention is stripped.
fn parse_event(
    payload: &Value,
    bot_user: &str,
    allowed: Option<&HashSet<String>>,
) -> Option<SlackMessage> {
    let event = payload.get("event")?;
    let etype = event.get("type").and_then(Value::as_str)?;
    if etype != "message" && etype != "app_mention" {
        return None;
    }
    // Skip bot messages and message edits/joins/etc. (subtyped events).
    if event.get("bot_id").is_some() || event.get("subtype").is_some() {
        return None;
    }
    let user = event
        .get("user")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if user.is_empty() || user == bot_user || !sender_allowed(allowed, user) {
        return None;
    }
    let channel = event.get("channel").and_then(Value::as_str)?.to_string();
    let thread_ts = event
        .get("thread_ts")
        .and_then(Value::as_str)
        .map(String::from);
    // Strip the bot's own @mention (`<@BOTID>`) so the agent sees a clean prompt.
    let text = event
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .replace(&format!("<@{bot_user}>"), "")
        .trim()
        .to_string();
    if text.is_empty() {
        return None;
    }
    Some(SlackMessage {
        channel,
        thread_ts,
        text,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload(event: Value) -> Value {
        serde_json::json!({ "event": event })
    }

    #[test]
    fn parses_a_plain_message() {
        let p = payload(serde_json::json!({
            "type": "message", "user": "U_ALICE", "text": "hello bot", "channel": "C1"
        }));
        let m = parse_event(&p, "U_BOT", None).unwrap();
        assert_eq!(m.channel, "C1");
        assert_eq!(m.text, "hello bot");
        assert_eq!(m.thread_ts, None);
        assert_eq!(m.session(), "slack:C1");
    }

    #[test]
    fn app_mention_strips_the_bot_mention_and_threads() {
        let p = payload(serde_json::json!({
            "type": "app_mention", "user": "U_ALICE", "text": "<@U_BOT> do a thing",
            "channel": "C1", "thread_ts": "1700000000.0001"
        }));
        let m = parse_event(&p, "U_BOT", None).unwrap();
        assert_eq!(m.text, "do a thing");
        assert_eq!(m.thread_ts.as_deref(), Some("1700000000.0001"));
        assert_eq!(m.session(), "slack:C1:1700000000.0001");
    }

    #[test]
    fn skips_self_bots_subtypes_and_non_text() {
        // Our own message.
        assert!(parse_event(
            &payload(
                serde_json::json!({"type":"message","user":"U_BOT","text":"hi","channel":"C1"})
            ),
            "U_BOT",
            None
        )
        .is_none());
        // Bot message.
        assert!(parse_event(
            &payload(
                serde_json::json!({"type":"message","bot_id":"B1","text":"hi","channel":"C1"})
            ),
            "U_BOT",
            None
        )
        .is_none());
        // Edited message (subtype set).
        assert!(parse_event(
            &payload(serde_json::json!({"type":"message","subtype":"message_changed","user":"U_A","text":"hi","channel":"C1"})),
            "U_BOT",
            None
        )
        .is_none());
        // Non-message event.
        assert!(parse_event(
            &payload(serde_json::json!({"type":"reaction_added","user":"U_A","channel":"C1"})),
            "U_BOT",
            None
        )
        .is_none());
        // Empty text.
        assert!(parse_event(
            &payload(
                serde_json::json!({"type":"message","user":"U_A","text":"   ","channel":"C1"})
            ),
            "U_BOT",
            None
        )
        .is_none());
    }

    #[test]
    fn allowlist_filters_senders() {
        let allowed: HashSet<String> = ["U_ALICE".to_string()].into_iter().collect();
        let msg = serde_json::json!({"type":"message","user":"U_ALICE","text":"hi","channel":"C1"});
        let mallory =
            serde_json::json!({"type":"message","user":"U_MALLORY","text":"hi","channel":"C1"});
        assert!(parse_event(&payload(msg.clone()), "U_BOT", Some(&allowed)).is_some());
        assert!(parse_event(&payload(mallory.clone()), "U_BOT", Some(&allowed)).is_none());
        // No allowlist ⇒ both answered.
        assert!(parse_event(&payload(mallory), "U_BOT", None).is_some());
    }

    #[test]
    fn sender_allowed_semantics() {
        let allowed: HashSet<String> = ["U_A".to_string()].into_iter().collect();
        assert!(sender_allowed(None, "U_ANYONE"));
        assert!(sender_allowed(Some(&allowed), "U_A"));
        assert!(!sender_allowed(Some(&allowed), "U_B"));
    }
}
