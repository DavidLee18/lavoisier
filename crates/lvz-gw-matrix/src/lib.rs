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
//!
//! ## Authentication & identity
//!
//! Three ways to authenticate, in precedence order (highest first):
//! 1. **Access token** (`MATRIX_ACCESS_TOKEN`) — skip `/login` entirely; the user/device id are
//!    resolved via `GET /account/whoami`. Best for a long-lived bot provisioned once.
//! 2. **Persisted session** — if a state directory is configured ([`MatrixGateway::with_state_dir`])
//!    and holds a saved `{access_token, device_id}` from a previous run, it's reused (validated with
//!    `whoami`), keeping the **device id stable across restarts** — a prerequisite for persistent
//!    E2EE (see [`e2ee`]).
//! 3. **Password login** (`MATRIX_PASSWORD`) — the fallback; the issued session is persisted to the
//!    state dir (if any) so the next start takes path 2. A configured device id (`MATRIX_DEVICE_ID`)
//!    or a previously-persisted one is reused on re-login so the device stays stable.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use futures::stream::StreamExt;
use lvz_protocol::{AgentHandle, Event, Gateway, GatewayError, TurnRequest};
use serde::{Deserialize, Serialize};

#[cfg(feature = "e2ee")]
mod e2ee;

/// Long-poll window for `/sync` (ms). The server holds the request open until an event
/// arrives or this elapses.
const SYNC_TIMEOUT_MS: u64 = 30_000;

/// A Matrix gateway bound to a homeserver and a bot account.
pub struct MatrixGateway {
    homeserver: String,
    user: String,
    /// Password for the `m.login.password` fallback. `None` when authenticating by access token.
    password: Option<String>,
    /// Pre-provisioned access token; when set, login is skipped and identity is resolved via
    /// `whoami` (precedence path 1).
    access_token: Option<String>,
    /// Device id to pin on the password-login path (and to reuse on re-login) so the crypto
    /// identity stays stable across restarts.
    device_id: Option<String>,
    /// Directory holding the persisted session (`session.json`) and, under `e2ee`, the SQLite
    /// crypto store (`crypto/`). The single on-disk home of the bot's Matrix identity.
    state_dir: Option<PathBuf>,
    /// Passphrase encrypting the E2EE crypto store at rest (`MATRIX_CRYPTO_STORE_KEY`).
    crypto_passphrase: Option<String>,
    http: reqwest::Client,
    txn: AtomicU64,
    /// Auto-accept room invites for the bot account (on by default).
    auto_join: bool,
    /// If set, only answer messages whose sender is in this allowlist (applied to plaintext and
    /// encrypted rooms alike). `None` ⇒ answer everyone (the default).
    allowed_users: Option<HashSet<String>>,
    /// If set, only act on messages in these rooms. Combined with [`Self::allowed_users`] as a
    /// conjunction: a turn runs only if the sender is allowed **and** the room is allowed. `None`
    /// ⇒ any room the bot is in (the default).
    allowed_rooms: Option<HashSet<String>>,
    /// Per-room tool permissions: `room_id` → the tools permitted there. A room absent from the
    /// map is unconstrained. See [`Self::tools_for`].
    room_tools: HashMap<String, HashSet<String>>,
    /// Per-member tool permissions: `user_id` → the tools permitted to them. A user absent from
    /// the map is unconstrained. Combined with [`Self::room_tools`] by intersection.
    user_tools: HashMap<String, HashSet<String>>,
    /// The "home" room: the single room that receives the shutdown notice when the gateway is
    /// stopped (SIGTERM / Ctrl-C). `None` ⇒ no notice is sent.
    home_room: Option<String>,
}

impl MatrixGateway {
    /// Internal base constructor with all optional knobs unset.
    fn base(homeserver: impl Into<String>, user: impl Into<String>) -> Self {
        Self {
            homeserver: homeserver.into().trim_end_matches('/').to_string(),
            user: user.into(),
            password: None,
            access_token: None,
            device_id: None,
            state_dir: None,
            crypto_passphrase: None,
            http: reqwest::Client::new(),
            txn: AtomicU64::new(0),
            auto_join: true,
            allowed_users: None,
            allowed_rooms: None,
            room_tools: HashMap::new(),
            user_tools: HashMap::new(),
            home_room: None,
        }
    }

    /// Construct against a homeserver base URL (e.g. `https://matrix.example.org`) and the
    /// bot's login (`user` may be a localpart or a full `@user:server` id) with a password.
    pub fn new(
        homeserver: impl Into<String>,
        user: impl Into<String>,
        password: impl Into<String>,
    ) -> Self {
        let mut gw = Self::base(homeserver, user);
        gw.password = Some(password.into());
        gw
    }

    /// Enable or disable auto-accepting room invites (default `true`). When off, an operator must
    /// join the bot to rooms out-of-band before it will respond there.
    pub fn with_auto_join(mut self, auto_join: bool) -> Self {
        self.auto_join = auto_join;
        self
    }

    /// Authenticate with a pre-provisioned access token instead of a password (precedence path 1).
    pub fn with_access_token(mut self, token: impl Into<String>) -> Self {
        self.access_token = Some(token.into());
        self
    }

    /// Pin the Matrix device id (password-login path), keeping the crypto identity stable across
    /// restarts.
    pub fn with_device_id(mut self, device_id: impl Into<String>) -> Self {
        self.device_id = Some(device_id.into());
        self
    }

    /// Set the state directory: where the session (token + device id) is persisted and where the
    /// E2EE crypto store lives. Enables stable-identity restarts.
    pub fn with_state_dir(mut self, dir: impl Into<PathBuf>) -> Self {
        self.state_dir = Some(dir.into());
        self
    }

    /// Set the passphrase used to encrypt the E2EE crypto store at rest.
    pub fn with_crypto_passphrase(mut self, passphrase: impl Into<String>) -> Self {
        self.crypto_passphrase = Some(passphrase.into());
        self
    }

    /// Restrict which senders the bot answers. An empty list clears the restriction (answer
    /// everyone); any non-empty list means only those `@user:server` ids drive the agent.
    pub fn with_allowed_users(mut self, users: impl IntoIterator<Item = String>) -> Self {
        let set: HashSet<String> = users.into_iter().collect();
        self.allowed_users = (!set.is_empty()).then_some(set);
        self
    }

    /// Restrict which rooms the bot acts in. An empty list clears the restriction (any room); a
    /// non-empty list means only those room ids are served. Combined with the user allowlist as a
    /// conjunction (sender allowed **and** room allowed).
    pub fn with_allowed_rooms(mut self, rooms: impl IntoIterator<Item = String>) -> Self {
        let set: HashSet<String> = rooms.into_iter().collect();
        self.allowed_rooms = (!set.is_empty()).then_some(set);
        self
    }

    /// Set per-room tool permissions: each `room_id` maps to the tools permitted in that room.
    /// Rooms absent from the map are unconstrained. See [`Self::tools_for`].
    pub fn with_room_tools(mut self, map: impl IntoIterator<Item = (String, Vec<String>)>) -> Self {
        self.room_tools = map
            .into_iter()
            .map(|(k, v)| (k, v.into_iter().collect()))
            .collect();
        self
    }

    /// Set per-member tool permissions: each `user_id` maps to the tools permitted to that member.
    /// Users absent from the map are unconstrained. Intersected with the room policy.
    pub fn with_user_tools(mut self, map: impl IntoIterator<Item = (String, Vec<String>)>) -> Self {
        self.user_tools = map
            .into_iter()
            .map(|(k, v)| (k, v.into_iter().collect()))
            .collect();
        self
    }

    /// Set the home room — the one room that receives a "shutting down" notice on graceful
    /// shutdown (SIGTERM / Ctrl-C). The bot must already be joined to it.
    pub fn with_home_room(mut self, room: impl Into<String>) -> Self {
        let room = room.into();
        self.home_room = (!room.is_empty()).then_some(room);
        self
    }

    /// The effective per-turn tool allowlist for a `(room, sender)`, or `None` when neither a room
    /// nor a member policy applies (⇒ the agent's full tool set). When both apply the result is
    /// their **intersection** (a tool must be permitted by the room *and* the member); when only
    /// one applies, that one is used. An empty result means "no tools".
    fn tools_for(&self, room: &str, sender: &str) -> Option<Vec<String>> {
        let room_set = self.room_tools.get(room);
        let user_set = self.user_tools.get(sender);
        match (room_set, user_set) {
            (None, None) => None,
            (Some(r), None) => Some(r.iter().cloned().collect()),
            (None, Some(u)) => Some(u.iter().cloned().collect()),
            (Some(r), Some(u)) => Some(r.intersection(u).cloned().collect()),
        }
    }

    /// Construct from the environment. Required: `MATRIX_HOMESERVER`, plus **either**
    /// `MATRIX_ACCESS_TOKEN` or (`MATRIX_USER` + `MATRIX_PASSWORD`). Optional:
    /// `MATRIX_DEVICE_ID`, `MATRIX_STATE_DIR`, `MATRIX_CRYPTO_STORE_KEY`,
    /// `MATRIX_ALLOWED_USERS`, `MATRIX_ALLOWED_ROOMS` (comma-separated), `MATRIX_HOME_ROOM`.
    /// Per-room/per-member tool permissions are richer than env can cleanly express and are set
    /// only via the TOML config (`with_room_tools`/`with_user_tools`).
    pub fn from_env() -> Result<Self, GatewayError> {
        let require =
            |k: &str| std::env::var(k).map_err(|_| GatewayError::Bind(format!("{k} is not set")));
        let opt = |k: &str| std::env::var(k).ok().filter(|v| !v.is_empty());

        let homeserver = require("MATRIX_HOMESERVER")?;
        let access_token = opt("MATRIX_ACCESS_TOKEN");
        let password = opt("MATRIX_PASSWORD");
        let user = opt("MATRIX_USER").unwrap_or_default();

        if access_token.is_none() && password.is_none() {
            return Err(GatewayError::Bind(
                "set MATRIX_ACCESS_TOKEN, or MATRIX_USER + MATRIX_PASSWORD".into(),
            ));
        }
        if access_token.is_none() && user.is_empty() {
            return Err(GatewayError::Bind(
                "MATRIX_USER is required for password login".into(),
            ));
        }

        let mut gw = Self::base(homeserver, user);
        gw.access_token = access_token;
        gw.password = password;
        gw.device_id = opt("MATRIX_DEVICE_ID");
        gw.state_dir = opt("MATRIX_STATE_DIR").map(PathBuf::from);
        gw.crypto_passphrase = opt("MATRIX_CRYPTO_STORE_KEY");
        if let Some(users) = opt("MATRIX_ALLOWED_USERS") {
            gw = gw.with_allowed_users(users.split(',').map(|s| s.trim().to_string()));
        }
        if let Some(rooms) = opt("MATRIX_ALLOWED_ROOMS") {
            gw = gw.with_allowed_rooms(rooms.split(',').map(|s| s.trim().to_string()));
        }
        if let Some(home) = opt("MATRIX_HOME_ROOM") {
            gw = gw.with_home_room(home);
        }
        Ok(gw)
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.homeserver, path)
    }

    /// Resolve the session to serve under, following the documented precedence: explicit access
    /// token → persisted session → password login. The chosen session is persisted to the state
    /// dir (if configured) so a later restart reuses the same device.
    async fn resolve_session(&self) -> Result<Session, GatewayError> {
        // 1. Explicit access token: resolve the identity via whoami (no login).
        if let Some(token) = &self.access_token {
            let who = self.whoami(token).await?;
            let device_id = who
                .device_id
                .or_else(|| self.device_id.clone())
                .unwrap_or_default();
            let session = Session {
                access_token: token.clone(),
                user_id: who.user_id,
                device_id,
            };
            self.save_session(&session);
            return Ok(session);
        }

        // 2. Persisted session from a previous run (validated against whoami). On success the
        //    device id is stable across restarts; on failure we fall through to password login,
        //    reusing the persisted device id so even a re-login keeps the same device.
        let persisted = self.load_session();
        if let Some(saved) = &persisted {
            match self.whoami(&saved.access_token).await {
                Ok(who) => {
                    let device_id = who
                        .device_id
                        .filter(|d| !d.is_empty())
                        .unwrap_or_else(|| saved.device_id.clone());
                    eprintln!("matrix: reusing persisted session (device {device_id})");
                    return Ok(Session {
                        access_token: saved.access_token.clone(),
                        user_id: who.user_id,
                        device_id,
                    });
                }
                Err(e) => eprintln!(
                    "matrix: persisted token rejected ({e}); falling back to password login"
                ),
            }
        }

        // 3. Password login. Reuse a configured or previously-persisted device id so the device
        //    stays stable, then persist the issued session.
        let reuse_device = self
            .device_id
            .clone()
            .or_else(|| persisted.as_ref().map(|s| s.device_id.clone()));
        let session = self.login(reuse_device.as_deref()).await?;
        self.save_session(&session);
        Ok(session)
    }

    /// Resolve `user_id`/`device_id` for an access token via `GET /account/whoami`.
    async fn whoami(&self, token: &str) -> Result<WhoAmI, GatewayError> {
        let resp = self
            .http
            .get(self.url("/_matrix/client/v3/account/whoami"))
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Bind(format!("matrix whoami {status}: {msg}")));
        }
        resp.json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))
    }

    /// Password-login (optionally pinning `device_id`); returns the access token + resolved ids.
    async fn login(&self, device_id: Option<&str>) -> Result<Session, GatewayError> {
        let password = self.password.as_deref().ok_or_else(|| {
            GatewayError::Bind("no MATRIX_PASSWORD set and no usable access token".into())
        })?;
        let mut body = serde_json::json!({
            "type": "m.login.password",
            "identifier": { "type": "m.id.user", "user": self.user },
            "password": password,
        });
        if let Some(d) = device_id {
            body["device_id"] = serde_json::Value::String(d.to_string());
        }
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

    /// Path to the persisted-session file under the state dir, if a state dir is configured.
    fn session_path(&self) -> Option<PathBuf> {
        self.state_dir.as_ref().map(|d| d.join("session.json"))
    }

    /// Load a previously-persisted session, if any. A session for a different homeserver is
    /// ignored (so changing `MATRIX_HOMESERVER` doesn't reuse a stale token).
    fn load_session(&self) -> Option<PersistedSession> {
        let path = self.session_path()?;
        let text = std::fs::read_to_string(&path).ok()?;
        let saved: PersistedSession = serde_json::from_str(&text).ok()?;
        (saved.homeserver == self.homeserver).then_some(saved)
    }

    /// Persist the session (token + device id) to the state dir, if configured. Best-effort: a
    /// write failure is logged, not fatal (the gateway still runs, just without restart stability).
    fn save_session(&self, session: &Session) {
        let Some(path) = self.session_path() else {
            return;
        };
        if let Some(dir) = &self.state_dir {
            if let Err(e) = std::fs::create_dir_all(dir) {
                eprintln!("matrix: could not create state dir {}: {e}", dir.display());
                return;
            }
        }
        let saved = PersistedSession {
            homeserver: self.homeserver.clone(),
            user_id: session.user_id.clone(),
            access_token: session.access_token.clone(),
            device_id: session.device_id.clone(),
        };
        match serde_json::to_string_pretty(&saved) {
            Ok(json) => {
                if let Err(e) = std::fs::write(&path, json) {
                    eprintln!(
                        "matrix: could not persist session to {}: {e}",
                        path.display()
                    );
                }
            }
            Err(e) => eprintln!("matrix: could not serialise session: {e}"),
        }
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

    /// Post the shutdown notice to the home room (if one is configured). Best-effort and sent in
    /// plaintext — an innocuous "shutting down" line, kept simple so it works in both encrypted and
    /// unencrypted home rooms without tracking per-room encryption state.
    async fn send_shutdown_notice(&self, token: &str) {
        let Some(home) = &self.home_room else {
            return;
        };
        if let Err(e) = self
            .send_message(token, home, "⚠️ Lavoisier gateway shutting down.")
            .await
        {
            eprintln!("matrix: failed to send shutdown notice to {home}: {e}");
        }
    }

    /// Accept a room invite (join the room).
    async fn join_room(&self, token: &str, room_id: &str) -> Result<(), GatewayError> {
        let path = format!("/_matrix/client/v3/join/{}", urlencode(room_id));
        let resp = self
            .http
            .post(self.url(&path))
            .bearer_auth(token)
            .json(&serde_json::json!({}))
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Io(format!("matrix join {status}: {msg}")));
        }
        Ok(())
    }

    /// Auto-accept any pending invites in a sync response (no-op when disabled). `seen` dedupes
    /// join attempts across syncs so a still-propagating invite isn't joined repeatedly; a failed
    /// join is removed from `seen` so it retries on the next sync.
    async fn auto_join_invites(
        &self,
        token: &str,
        sync: &serde_json::Value,
        seen: &mut std::collections::HashSet<String>,
    ) {
        if !self.auto_join {
            return;
        }
        for room in extract_invites(sync) {
            if !seen.insert(room.clone()) {
                continue;
            }
            match self.join_room(token, &room).await {
                Ok(()) => eprintln!("matrix: auto-joined invited room {room}"),
                Err(e) => {
                    eprintln!("matrix: auto-join {room} failed: {e}");
                    seen.remove(&room);
                }
            }
        }
    }

    /// Run one inbound message through the agent; return its trimmed answer (or `None` if the
    /// agent errored or produced nothing). Sending the answer is the caller's job, so plaintext
    /// and encrypted rooms share this path and differ only in how the reply goes out.
    async fn run_agent(
        &self,
        agent: &Arc<dyn AgentHandle>,
        room: &str,
        sender: &str,
        body: String,
    ) -> Option<String> {
        // Apply this room/member's tool permissions (if any) to the turn. The agent core enforces
        // the allowlist; the policy decision lives here.
        let mut turn = TurnRequest::new(room.to_string(), body);
        if let Some(tools) = self.tools_for(room, sender) {
            turn = turn.with_allowed_tools(tools);
        }
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
        let session = self.resolve_session().await?;
        eprintln!(
            "lavoisier: matrix gateway online as {} (device {}) on {}",
            session.user_id, session.device_id, self.homeserver
        );
        if let Some(allowed) = &self.allowed_users {
            eprintln!(
                "matrix: answering only {} allowlisted sender(s)",
                allowed.len()
            );
        }
        if let Some(rooms) = &self.allowed_rooms {
            eprintln!("matrix: acting only in {} allowlisted room(s)", rooms.len());
        }
        if !self.room_tools.is_empty() || !self.user_tools.is_empty() {
            eprintln!(
                "matrix: tool permissions set for {} room(s) and {} member(s)",
                self.room_tools.len(),
                self.user_tools.len()
            );
        }
        if let Some(home) = &self.home_room {
            eprintln!("matrix: home room {home} (receives the shutdown notice)");
        }
        // Own the fields used across awaits so a `&Session` is never held across one (keeps the
        // async_trait future unconditionally `Send`).
        let token = session.access_token.clone();
        let self_user = session.user_id.clone();

        // Opt-in E2EE: bind an OlmMachine to this session and publish keys. If init fails we log
        // and continue in plaintext-only mode rather than abort the gateway. A configured state
        // dir backs the OlmMachine with a durable SQLite crypto store (`<state_dir>/crypto`) so the
        // crypto identity survives restarts; without one the machine is in-memory (single-session).
        #[cfg(feature = "e2ee")]
        let crypto = match e2ee::Crypto::new(
            self.homeserver.clone(),
            token.clone(),
            &session.user_id,
            &session.device_id,
            self.state_dir.as_ref().map(|d| d.join("crypto")).as_deref(),
            self.crypto_passphrase.as_deref(),
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
        // messages that arrive from now on. Pending invites *are* accepted (a backlog message is
        // noise, but a pending invite is a standing request to join).
        let mut seen_invites = std::collections::HashSet::new();
        let baseline = self.sync_once(&token, None).await?;
        self.auto_join_invites(&token, &baseline, &mut seen_invites)
            .await;
        let mut since = parse_next_batch(&baseline)?;

        // Race each `/sync` against a shutdown signal so the gateway can stop gracefully (and post
        // the home-room notice) on SIGTERM / Ctrl-C rather than being hard-killed.
        let shutdown = shutdown_signal();
        tokio::pin!(shutdown);

        loop {
            let value = tokio::select! {
                biased;
                _ = &mut shutdown => {
                    eprintln!("matrix: shutdown signal received, stopping");
                    self.send_shutdown_notice(&token).await;
                    return Ok(());
                }
                res = self.sync_once(&token, Some(&since)) => match res {
                    Ok(value) => value,
                    Err(e) => {
                        // Transient sync failure: back off briefly and retry rather than exit.
                        eprintln!("matrix: {e}; retrying");
                        tokio::time::sleep(Duration::from_secs(3)).await;
                        continue;
                    }
                },
            };

            // Accept any new room invites before processing messages.
            self.auto_join_invites(&token, &value, &mut seen_invites)
                .await;

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
            for msg in extract_messages(
                resp,
                &self_user,
                self.allowed_users.as_ref(),
                self.allowed_rooms.as_ref(),
            ) {
                if let Some(answer) = self
                    .run_agent(&agent, &msg.room, &msg.sender, msg.body)
                    .await
                {
                    if let Err(e) = self.send_message(&token, &msg.room, &answer).await {
                        eprintln!("matrix: send error in {}: {e}", msg.room);
                    }
                }
            }

            // Encrypted messages: decrypt, run the agent, and reply encrypted.
            #[cfg(feature = "e2ee")]
            if let Some(c) = &crypto {
                for (room, sender, body) in c
                    .decrypt_messages(
                        &value,
                        self_user.clone(),
                        self.allowed_users.clone(),
                        self.allowed_rooms.clone(),
                    )
                    .await
                {
                    if let Some(answer) = self.run_agent(&agent, &room, &sender, body).await {
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

/// Room ids the bot has been invited to (the keys of `rooms.invite` in a sync response).
fn extract_invites(sync: &serde_json::Value) -> Vec<String> {
    sync.get("rooms")
        .and_then(|r| r.get("invite"))
        .and_then(|i| i.as_object())
        .map(|rooms| rooms.keys().cloned().collect())
        .unwrap_or_default()
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
/// bot's own messages (so it never replies to itself) and any sender not in `allowed` (when an
/// allowlist is configured).
fn extract_messages(
    sync: SyncResponse,
    self_user: &str,
    allowed: Option<&HashSet<String>>,
    allowed_rooms: Option<&HashSet<String>>,
) -> Vec<IncomingMessage> {
    let mut out = Vec::new();
    for (room_id, room) in sync.rooms.join {
        if !room_allowed(allowed_rooms, &room_id) {
            continue;
        }
        for event in room.timeline.events {
            if event.kind != "m.room.message" || event.sender == self_user {
                continue;
            }
            if !sender_allowed(allowed, &event.sender) {
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

/// Whether `sender` may drive the agent: true if no allowlist is configured, else membership.
/// Shared by the plaintext and E2EE paths so encryption can't bypass the allowlist.
pub(crate) fn sender_allowed(allowed: Option<&HashSet<String>>, sender: &str) -> bool {
    allowed.is_none_or(|set| set.contains(sender))
}

/// Whether `room` may be served: true if no room allowlist is configured, else membership.
/// Shared by the plaintext and E2EE paths so encryption can't bypass the room restriction.
pub(crate) fn room_allowed(allowed: Option<&HashSet<String>>, room: &str) -> bool {
    allowed.is_none_or(|set| set.contains(room))
}

/// Resolve when the process is asked to terminate — SIGTERM (e.g. an ECS task stop) or Ctrl-C on
/// Unix, Ctrl-C elsewhere — so the serve loop can shut down gracefully and post its home-room
/// notice instead of being hard-killed.
async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        match signal(SignalKind::terminate()) {
            Ok(mut term) => {
                tokio::select! {
                    _ = term.recv() => {}
                    _ = tokio::signal::ctrl_c() => {}
                }
            }
            // If the SIGTERM handler can't be installed, still honour Ctrl-C.
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
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

/// `GET /account/whoami` response. `device_id` is optional (added to the spec later; some
/// homeservers omit it for non-token logins).
#[derive(Deserialize)]
struct WhoAmI {
    user_id: String,
    #[serde(default)]
    device_id: Option<String>,
}

/// The on-disk session artifact (`<state_dir>/session.json`): the token + device id (and the
/// homeserver it belongs to) reused across restarts to keep a stable device/crypto identity.
#[derive(Serialize, Deserialize)]
struct PersistedSession {
    homeserver: String,
    user_id: String,
    access_token: String,
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

        let msgs = extract_messages(sync, "@bot:hs", None, None);
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].room, "!room:hs");
        assert_eq!(msgs[0].sender, "@alice:hs");
        assert_eq!(msgs[0].body, "hello bot");
    }

    #[test]
    fn allowlist_filters_senders() {
        let json = serde_json::json!({
            "next_batch": "s3",
            "rooms": { "join": { "!room:hs": { "timeline": { "events": [
                { "type": "m.room.message", "sender": "@alice:hs",
                  "content": { "msgtype": "m.text", "body": "from alice" } },
                { "type": "m.room.message", "sender": "@mallory:hs",
                  "content": { "msgtype": "m.text", "body": "from mallory" } }
            ] } } } }
        });
        // No allowlist ⇒ both senders answered.
        assert_eq!(
            extract_messages(sync_from(json.clone()), "@bot:hs", None, None).len(),
            2
        );
        // Allowlist ⇒ only the listed sender.
        let allowed: HashSet<String> = ["@alice:hs".to_string()].into_iter().collect();
        let msgs = extract_messages(sync_from(json), "@bot:hs", Some(&allowed), None);
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].sender, "@alice:hs");
    }

    #[test]
    fn allowed_rooms_filter_and_combine_with_senders() {
        let json = serde_json::json!({
            "next_batch": "s4",
            "rooms": { "join": {
                "!ok:hs": { "timeline": { "events": [
                    { "type": "m.room.message", "sender": "@alice:hs",
                      "content": { "msgtype": "m.text", "body": "in ok room" } }
                ] } },
                "!nope:hs": { "timeline": { "events": [
                    { "type": "m.room.message", "sender": "@alice:hs",
                      "content": { "msgtype": "m.text", "body": "in blocked room" } }
                ] } }
            } }
        });
        // No room allowlist ⇒ both rooms answered.
        assert_eq!(
            extract_messages(sync_from(json.clone()), "@bot:hs", None, None).len(),
            2
        );
        // Room allowlist ⇒ only the listed room.
        let rooms: HashSet<String> = ["!ok:hs".to_string()].into_iter().collect();
        let msgs = extract_messages(sync_from(json.clone()), "@bot:hs", None, Some(&rooms));
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].room, "!ok:hs");
        // Conjunction: an allowed sender in a disallowed room is still dropped.
        let users: HashSet<String> = ["@alice:hs".to_string()].into_iter().collect();
        let only_other: HashSet<String> = ["!nope:hs".to_string()].into_iter().collect();
        // alice is allowed, but the only allowed room here is !nope:hs, so her !ok:hs message and
        // the !nope:hs one both pass the *sender* check — but room-wise only !nope:hs survives.
        let msgs = extract_messages(sync_from(json), "@bot:hs", Some(&users), Some(&only_other));
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].room, "!nope:hs");
    }

    #[test]
    fn room_allowed_semantics() {
        let allowed: HashSet<String> = ["!a:hs".to_string()].into_iter().collect();
        assert!(room_allowed(None, "!anything:hs")); // unset ⇒ every room
        assert!(room_allowed(Some(&allowed), "!a:hs"));
        assert!(!room_allowed(Some(&allowed), "!b:hs"));
    }

    #[test]
    fn tool_policy_intersects_room_and_member() {
        let gw = MatrixGateway::new("https://hs", "@bot:hs", "pw")
            .with_room_tools([(
                "!ops:hs".to_string(),
                vec!["shell".to_string(), "read_file".to_string()],
            )])
            .with_user_tools([(
                "@admin:hs".to_string(),
                vec!["read_file".to_string(), "write_file".to_string()],
            )]);

        // Neither room nor member constrained ⇒ unrestricted (None).
        assert!(gw.tools_for("!other:hs", "@guest:hs").is_none());

        // Only the room is constrained ⇒ the room's set.
        let mut t = gw.tools_for("!ops:hs", "@guest:hs").unwrap();
        t.sort();
        assert_eq!(t, vec!["read_file".to_string(), "shell".to_string()]);

        // Only the member is constrained ⇒ the member's set.
        let mut t = gw.tools_for("!other:hs", "@admin:hs").unwrap();
        t.sort();
        assert_eq!(t, vec!["read_file".to_string(), "write_file".to_string()]);

        // Both constrained ⇒ intersection (only read_file is in both).
        let t = gw.tools_for("!ops:hs", "@admin:hs").unwrap();
        assert_eq!(t, vec!["read_file".to_string()]);
    }

    #[test]
    fn sender_allowed_semantics() {
        let allowed: HashSet<String> = ["@a:hs".to_string()].into_iter().collect();
        assert!(sender_allowed(None, "@anyone:hs")); // unset ⇒ everyone
        assert!(sender_allowed(Some(&allowed), "@a:hs"));
        assert!(!sender_allowed(Some(&allowed), "@b:hs"));
    }

    #[test]
    fn empty_sync_yields_no_messages_and_parses_next_batch() {
        let value = serde_json::json!({ "next_batch": "s5" });
        assert_eq!(parse_next_batch(&value).unwrap(), "s5");
        let sync: SyncResponse = serde_json::from_value(value).unwrap();
        assert!(extract_messages(sync, "@bot:hs", None, None).is_empty());
    }

    #[test]
    fn missing_next_batch_is_an_error() {
        assert!(parse_next_batch(&serde_json::json!({})).is_err());
    }

    #[test]
    fn extracts_invited_room_ids() {
        let sync = serde_json::json!({
            "next_batch": "s1",
            "rooms": { "invite": {
                "!a:hs": { "invite_state": { "events": [] } },
                "!b:hs": { "invite_state": { "events": [] } }
            } }
        });
        let mut invites = extract_invites(&sync);
        invites.sort();
        assert_eq!(invites, vec!["!a:hs".to_string(), "!b:hs".to_string()]);
        // No invite section ⇒ nothing to join.
        assert!(extract_invites(&serde_json::json!({ "next_batch": "s2" })).is_empty());
    }

    #[test]
    fn urlencodes_room_id_special_chars() {
        assert_eq!(urlencode("!abc:hs"), "%21abc%3Ahs");
        assert_eq!(urlencode("plain-id_1.0~"), "plain-id_1.0~");
    }
}
