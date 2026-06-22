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

use std::collections::{HashMap, HashSet, VecDeque};
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

    /// Resolve `user_id`/`device_id` for an access token via `GET /account/whoami`, retrying
    /// transient failures (the homeserver may be briefly unavailable while a fresh task boots).
    async fn whoami(&self, token: &str) -> Result<WhoAmI, GatewayError> {
        self.with_retry("whoami", || self.whoami_once(token)).await
    }

    /// One `GET /account/whoami` attempt. A 5xx/429/transport failure is classified `Io`
    /// (transient ⇒ retried); a 4xx (e.g. an invalid/expired token) is `Bind` (fatal ⇒ surfaced).
    async fn whoami_once(&self, token: &str) -> Result<WhoAmI, GatewayError> {
        let resp = self
            .http
            .get(self.url("/_matrix/client/v3/account/whoami"))
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        let status = resp.status();
        if !status.is_success() {
            let msg = resp.text().await.unwrap_or_default();
            return Err(classify_status(
                status,
                format!("matrix whoami {status}: {msg}"),
            ));
        }
        resp.json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))
    }

    /// Password-login (optionally pinning `device_id`); returns the access token + resolved ids.
    /// Like [`whoami`](Self::whoami), transient failures are retried with backoff.
    async fn login(&self, device_id: Option<&str>) -> Result<Session, GatewayError> {
        self.with_retry("login", || self.login_once(device_id))
            .await
    }

    /// One `POST /login` attempt; transient failures `Io`, auth/config failures `Bind` (see
    /// [`whoami_once`](Self::whoami_once)).
    async fn login_once(&self, device_id: Option<&str>) -> Result<Session, GatewayError> {
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
        let status = resp.status();
        if !status.is_success() {
            let msg = resp.text().await.unwrap_or_default();
            return Err(classify_status(
                status,
                format!("matrix login {status}: {msg}"),
            ));
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

    /// Run a startup operation, retrying *transient* failures (`GatewayError::Io` — transport
    /// errors, 5xx, 429) with exponential backoff so a homeserver that is briefly unavailable
    /// (e.g. restarting while a fresh task boots) doesn't kill the gateway before it ever connects.
    /// Mirrors the in-loop `/sync` retry, but with a growing delay. Fatal errors (`Bind`/`Protocol`
    /// — e.g. a bad token) propagate immediately so misconfiguration surfaces fast.
    async fn with_retry<T, F, Fut>(&self, what: &str, mut op: F) -> Result<T, GatewayError>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<T, GatewayError>>,
    {
        let mut delay = Duration::from_secs(1);
        let max = Duration::from_secs(30);
        loop {
            match op().await {
                Ok(v) => return Ok(v),
                Err(e @ GatewayError::Io(_)) => {
                    eprintln!(
                        "matrix: {what} failed ({e}); retrying in {}s",
                        delay.as_secs()
                    );
                    tokio::time::sleep(delay).await;
                    delay = (delay * 2).min(max);
                }
                Err(e) => return Err(e),
            }
        }
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

    /// Post a plain-text message to a room; returns the homeserver-assigned event id (so the
    /// caller can track its own messages for reply-detection).
    async fn send_message(
        &self,
        token: &str,
        room_id: &str,
        body: &str,
    ) -> Result<String, GatewayError> {
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
        let parsed: SendResponse = resp
            .json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))?;
        Ok(parsed.event_id)
    }

    /// React to an event with a single emoji (an `m.reaction` annotation). Reactions are sent in
    /// the clear — unencrypted by convention — in both plaintext and encrypted rooms.
    async fn react(
        &self,
        token: &str,
        room_id: &str,
        event_id: &str,
        emoji: &str,
    ) -> Result<(), GatewayError> {
        let txn = self.txn.fetch_add(1, Ordering::Relaxed);
        let path = format!(
            "/_matrix/client/v3/rooms/{}/send/m.reaction/lvz{}",
            urlencode(room_id),
            txn
        );
        let payload = serde_json::json!({
            "m.relates_to": { "rel_type": "m.annotation", "event_id": event_id, "key": emoji }
        });
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
            return Err(GatewayError::Io(format!("matrix react {status}: {msg}")));
        }
        Ok(())
    }

    /// Set (or clear) the bot's typing indicator in a room. `timeout` bounds how long the server
    /// shows it without a refresh; we re-assert it as work progresses (each tool-call notice).
    async fn set_typing(
        &self,
        token: &str,
        room_id: &str,
        user_id: &str,
        typing: bool,
    ) -> Result<(), GatewayError> {
        let path = format!(
            "/_matrix/client/v3/rooms/{}/typing/{}",
            urlencode(room_id),
            urlencode(user_id)
        );
        let payload = if typing {
            serde_json::json!({ "typing": true, "timeout": 30_000 })
        } else {
            serde_json::json!({ "typing": false })
        };
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
            return Err(GatewayError::Io(format!("matrix typing {status}: {msg}")));
        }
        Ok(())
    }

    /// Whether `room` is a 1:1 DM (exactly two joined members: the bot and one other). The result
    /// is cached in `cache` since membership rarely changes over a session; a transient lookup
    /// failure is treated as "not a DM" (fall back to requiring a mention) and not cached.
    async fn is_dm(&self, token: &str, room_id: &str, cache: &mut HashMap<String, bool>) -> bool {
        if let Some(&dm) = cache.get(room_id) {
            return dm;
        }
        match self.joined_member_count(token, room_id).await {
            Ok(n) => {
                let dm = n == 2;
                cache.insert(room_id.to_string(), dm);
                dm
            }
            Err(e) => {
                eprintln!("matrix: joined_members({room_id}) failed: {e}");
                false
            }
        }
    }

    /// Count the joined members of a room (`GET …/joined_members`).
    async fn joined_member_count(&self, token: &str, room_id: &str) -> Result<usize, GatewayError> {
        let path = format!(
            "/_matrix/client/v3/rooms/{}/joined_members",
            urlencode(room_id)
        );
        let resp = self
            .http
            .get(self.url(&path))
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Io(format!(
                "matrix joined_members {status}: {msg}"
            )));
        }
        let parsed: JoinedMembersResponse = resp
            .json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))?;
        Ok(parsed.joined.len())
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

    /// Decide whether to engage with a message and, if so, handle it. The bot engages in a 1:1 DM
    /// unconditionally, or in a group room only when @-mentioned or replied to (see
    /// [`message_triggers`]). The DM membership lookup is skipped when a mention/reply already
    /// settles it, so the common case costs no extra round-trip.
    #[allow(clippy::too_many_arguments)]
    async fn engage(
        &self,
        agent: &Arc<dyn AgentHandle>,
        token: &str,
        self_user: &str,
        reply: &Reply<'_>,
        msg: IncomingMessage,
        sent: &mut RecentIds,
        dm_cache: &mut HashMap<String, bool>,
    ) {
        let pre_triggered = msg.mentions_bot
            || msg
                .in_reply_to
                .as_deref()
                .is_some_and(|id| sent.contains(id));
        let is_dm = !pre_triggered && self.is_dm(token, &msg.room, dm_cache).await;
        if !message_triggers(is_dm, msg.mentions_bot, msg.in_reply_to.as_deref(), sent) {
            return;
        }
        self.handle_message(agent, token, self_user, reply, msg, sent)
            .await;
    }

    /// Send a message body to a room in the right modality for this turn — plaintext or (under
    /// the `e2ee` feature) encrypted — returning the event id. The single seam that lets the
    /// shared per-message handler stay modality-agnostic.
    async fn send_via(
        &self,
        reply: &Reply<'_>,
        token: &str,
        room: &str,
        body: String,
    ) -> Result<String, GatewayError> {
        match reply {
            Reply::Plain => self.send_message(token, room, &body).await,
            #[cfg(feature = "e2ee")]
            Reply::Encrypted(crypto) => crypto
                .encrypt_and_send(room.to_string(), body)
                .await
                .map_err(|e| GatewayError::Io(e.to_string())),
            #[cfg(not(feature = "e2ee"))]
            Reply::_Unused(_) => unreachable!(),
        }
    }

    /// Handle one engaged inbound message end to end: acknowledge with a reaction, show a typing
    /// indicator, run the agent — posting a concise notice for each tool call as it happens — and
    /// finally send the answer. Replies go out via `reply` (plaintext or encrypted); reactions and
    /// typing always use the plaintext API. Every message the bot sends is recorded in `sent` so a
    /// later reply to it re-engages the bot. The whole flow is best-effort: ack/typing failures are
    /// logged, not fatal.
    #[allow(clippy::too_many_arguments)]
    async fn handle_message(
        &self,
        agent: &Arc<dyn AgentHandle>,
        token: &str,
        self_user: &str,
        reply: &Reply<'_>,
        msg: IncomingMessage,
        sent: &mut RecentIds,
    ) {
        let room = msg.room;
        // 1. Acknowledge that we saw the message.
        if let Err(e) = self.react(token, &room, &msg.event_id, "👀").await {
            eprintln!("matrix: react in {room}: {e}");
        }
        // 2. Show "typing…" while we prepare a response.
        if let Err(e) = self.set_typing(token, &room, self_user, true).await {
            eprintln!("matrix: typing in {room}: {e}");
        }

        // Apply this room/member's tool permissions (if any) to the turn. The agent core enforces
        // the allowlist; the policy decision lives here.
        let mut turn = TurnRequest::new(room.clone(), msg.body);
        if let Some(tools) = self.tools_for(&room, &msg.sender) {
            turn = turn.with_allowed_tools(tools);
        }
        let mut stream = match agent.submit(turn).await {
            Ok(stream) => stream,
            Err(e) => {
                eprintln!("matrix: agent error in {room}: {e}");
                let _ = self.set_typing(token, &room, self_user, false).await;
                return;
            }
        };

        // 3. Stream the turn: accumulate the answer text, and post a notice for each tool call as
        //    it completes (buffering the streamed argument JSON to extract a short target hint).
        let mut answer = String::new();
        let mut tool_args: HashMap<String, (String, String)> = HashMap::new();
        while let Some(item) = stream.next().await {
            match item {
                Ok(Event::TextDelta(text)) => answer.push_str(&text),
                Ok(Event::ToolUseStart { id, name }) => {
                    tool_args.insert(id, (name, String::new()));
                }
                Ok(Event::ToolUseDelta { id, json }) => {
                    if let Some((_, args)) = tool_args.get_mut(&id) {
                        args.push_str(&json);
                    }
                }
                Ok(Event::ToolUseEnd { id }) => {
                    if let Some((name, args)) = tool_args.remove(&id) {
                        let notice = match tool_hint(&args) {
                            Some(hint) => format!("🔧 `{name}` · {hint}"),
                            None => format!("🔧 `{name}`"),
                        };
                        match self.send_via(reply, token, &room, notice).await {
                            Ok(eid) => sent.insert(eid),
                            Err(e) => eprintln!("matrix: tool notice in {room}: {e}"),
                        }
                        // Re-assert typing so the indicator survives a long multi-tool turn.
                        let _ = self.set_typing(token, &room, self_user, true).await;
                    }
                }
                Ok(_) => {}
                Err(e) => {
                    eprintln!("matrix: stream error in {room}: {e}");
                    break;
                }
            }
        }

        // 4. Stop typing and send the answer.
        let _ = self.set_typing(token, &room, self_user, false).await;
        let answer = answer.trim();
        if !answer.is_empty() {
            match self.send_via(reply, token, &room, answer.to_string()).await {
                Ok(eid) => sent.insert(eid),
                Err(e) => eprintln!("matrix: send error in {room}: {e}"),
            }
        }
    }
}

/// How a turn's outbound messages are delivered to the room — plaintext, or end-to-end encrypted
/// (under the `e2ee` feature). Built per message by the serve loop so the shared
/// [`MatrixGateway::handle_message`] stays modality-agnostic.
enum Reply<'a> {
    Plain,
    #[cfg(feature = "e2ee")]
    Encrypted(&'a e2ee::Crypto),
    #[cfg(not(feature = "e2ee"))]
    #[allow(dead_code)]
    _Unused(std::marker::PhantomData<&'a ()>),
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
        let baseline = self
            .with_retry("baseline sync", || self.sync_once(&token, None))
            .await?;
        self.auto_join_invites(&token, &baseline, &mut seen_invites)
            .await;
        let mut since = parse_next_batch(&baseline)?;

        // Per-session engagement state: the bot's own recent event ids (so a reply to one
        // re-engages it) and a per-room DM cache (so the "always answer in a 1:1" rule doesn't
        // re-query membership every message).
        let mut sent = RecentIds::new(256);
        let mut dm_cache: HashMap<String, bool> = HashMap::new();

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

            // Plaintext messages: engage (if triggered) and reply in the clear.
            for msg in extract_messages(
                resp,
                &self_user,
                self.allowed_users.as_ref(),
                self.allowed_rooms.as_ref(),
            ) {
                self.engage(
                    &agent,
                    &token,
                    &self_user,
                    &Reply::Plain,
                    msg,
                    &mut sent,
                    &mut dm_cache,
                )
                .await;
            }

            // Encrypted messages: decrypt, engage (if triggered), and reply encrypted.
            #[cfg(feature = "e2ee")]
            if let Some(c) = &crypto {
                for msg in c
                    .decrypt_messages(
                        &value,
                        self_user.clone(),
                        self.allowed_users.clone(),
                        self.allowed_rooms.clone(),
                    )
                    .await
                {
                    self.engage(
                        &agent,
                        &token,
                        &self_user,
                        &Reply::Encrypted(c),
                        msg,
                        &mut sent,
                        &mut dm_cache,
                    )
                    .await;
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
    /// The event id, so the bot can react to it / track reply targets.
    event_id: String,
    /// Whether this message @-mentions the bot (a trigger in a group room).
    mentions_bot: bool,
    /// If this is a reply, the event id it replies to (a trigger when it's one of ours).
    in_reply_to: Option<String>,
}

/// Pull the answerable `m.room.message`/`m.text` events out of a sync response, skipping the
/// bot's own messages (so it never replies to itself) and any sender not in `allowed` (when an
/// allowlist is configured). Each message also carries the signals — does it mention the bot, is
/// it a reply, what's its event id — the serve loop needs to decide whether to engage.
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
            let mentions_bot = mentions_bot(&event.content, self_user);
            let in_reply_to = reply_target(&event.content);
            if let Some(body) = message_text(&event.content) {
                out.push(IncomingMessage {
                    room: room_id.clone(),
                    sender: event.sender,
                    body,
                    event_id: event.event_id,
                    mentions_bot,
                    in_reply_to,
                });
            }
        }
    }
    out
}

/// Whether a message's content @-mentions the bot. The authoritative signal is `m.mentions`
/// (MSC3952, sent by modern clients on an explicit @-mention); we also accept a textual fallback
/// — the bot's full MXID or `@localpart` appearing as a token in the (plain or formatted) body —
/// for clients/users that type the handle without producing a pill.
pub(crate) fn mentions_bot(content: &EventContent, self_user: &str) -> bool {
    if content
        .mentions
        .as_ref()
        .is_some_and(|m| m.user_ids.iter().any(|u| u == self_user))
    {
        return true;
    }
    let localpart = self_user.strip_prefix('@').and_then(|s| s.split_once(':'));
    let handle = localpart.map(|(l, _)| format!("@{l}"));
    let texts = [content.body.as_deref(), content.formatted_body.as_deref()];
    texts.into_iter().flatten().any(|text| {
        text.split(|c: char| {
            !(c.is_alphanumeric() || c == '@' || c == ':' || c == '_' || c == '.' || c == '-')
        })
        .any(|tok| tok == self_user || handle.as_deref().is_some_and(|h| tok == h))
    })
}

/// The event id a message replies to, if any (`m.relates_to` → `m.in_reply_to`). Shared by the
/// plaintext and (post-decryption) encrypted paths so reply-detection is identical.
pub(crate) fn reply_target(content: &EventContent) -> Option<String> {
    content
        .relates_to
        .as_ref()
        .and_then(|r| r.in_reply_to.as_ref())
        .map(|r| r.event_id.clone())
        .filter(|id| !id.is_empty())
}

/// The text body of a message, but only when it's an `m.text` message (the bot answers text).
pub(crate) fn message_text(content: &EventContent) -> Option<String> {
    (content.msgtype.as_deref() == Some("m.text"))
        .then(|| content.body.clone())
        .flatten()
}

/// Decide whether the bot should engage with a message: always in a 1:1 DM; in a group room only
/// when it's @-mentioned or replies to one of the bot's own recent messages.
fn message_triggers(
    is_dm: bool,
    mentions_bot: bool,
    in_reply_to: Option<&str>,
    ours: &RecentIds,
) -> bool {
    is_dm || mentions_bot || in_reply_to.is_some_and(|id| ours.contains(id))
}

/// A short, human-readable hint at a tool call's target, pulled from its argument JSON — the first
/// of a few salient keys (path/file/command/…), else the first string field — truncated. Used to
/// annotate the per-tool-call room notice (`🔧 read_file · src/lib.rs`). Returns `None` when the
/// args don't parse or carry nothing worth showing.
fn tool_hint(args_json: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(args_json).ok()?;
    let obj = v.as_object()?;
    const SALIENT: &[&str] = &[
        "path",
        "file",
        "files",
        "command",
        "cmd",
        "pattern",
        "query",
        "name",
        "old_string",
    ];
    let pick = SALIENT
        .iter()
        .find_map(|k| obj.get(*k).and_then(|x| x.as_str()))
        .or_else(|| obj.values().find_map(|x| x.as_str()))?;
    let pick = pick.trim();
    if pick.is_empty() {
        return None;
    }
    Some(truncate_hint(pick, 60))
}

/// Single-line truncation for a tool hint: collapse to the first line and cap the length.
fn truncate_hint(s: &str, max: usize) -> String {
    let line = s.lines().next().unwrap_or(s);
    if line.chars().count() <= max {
        line.to_string()
    } else {
        let kept: String = line.chars().take(max).collect();
        format!("{kept}…")
    }
}

/// A bounded set of the bot's recently-sent event ids, for recognising replies to its own
/// messages. Insertion-ordered with a hard cap (oldest evicted) so it can't grow unbounded over a
/// long-lived session.
#[derive(Default)]
struct RecentIds {
    set: HashSet<String>,
    order: VecDeque<String>,
    cap: usize,
}

impl RecentIds {
    fn new(cap: usize) -> Self {
        Self {
            set: HashSet::new(),
            order: VecDeque::new(),
            cap,
        }
    }

    fn insert(&mut self, id: String) {
        if id.is_empty() || !self.set.insert(id.clone()) {
            return;
        }
        self.order.push_back(id);
        if self.order.len() > self.cap {
            if let Some(old) = self.order.pop_front() {
                self.set.remove(&old);
            }
        }
    }

    fn contains(&self, id: &str) -> bool {
        self.set.contains(id)
    }
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

/// Classify a non-success HTTP status from the startup auth calls into a [`GatewayError`]:
/// server errors (5xx) and `429 Too Many Requests` are *transient* (`Io` ⇒ retried with backoff);
/// everything else (4xx — bad/expired token, wrong password) is fatal (`Bind` ⇒ surfaced).
fn classify_status(status: reqwest::StatusCode, msg: String) -> GatewayError {
    if status.is_server_error() || status == reqwest::StatusCode::TOO_MANY_REQUESTS {
        GatewayError::Io(msg)
    } else {
        GatewayError::Bind(msg)
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

/// `PUT …/send/…` response — carries the `event_id` the homeserver assigned the event.
#[derive(Deserialize)]
struct SendResponse {
    event_id: String,
}

/// `GET …/joined_members` response — used only for its member count (DM detection).
#[derive(Deserialize)]
struct JoinedMembersResponse {
    #[serde(default)]
    joined: HashMap<String, serde_json::Value>,
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
    event_id: String,
    #[serde(default)]
    content: EventContent,
}

#[derive(Deserialize, Default)]
pub(crate) struct EventContent {
    #[serde(default)]
    msgtype: Option<String>,
    #[serde(default)]
    body: Option<String>,
    #[serde(default)]
    formatted_body: Option<String>,
    /// Intentional mentions (MSC3952 / Matrix 1.7): the authoritative "who was @-mentioned" signal.
    #[serde(default, rename = "m.mentions")]
    mentions: Option<Mentions>,
    #[serde(default, rename = "m.relates_to")]
    relates_to: Option<RelatesTo>,
}

#[derive(Deserialize, Default)]
struct Mentions {
    #[serde(default)]
    user_ids: Vec<String>,
}

#[derive(Deserialize, Default)]
struct RelatesTo {
    #[serde(default, rename = "m.in_reply_to")]
    in_reply_to: Option<InReplyTo>,
}

#[derive(Deserialize, Default)]
struct InReplyTo {
    #[serde(default)]
    event_id: String,
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
    fn classify_status_transient_vs_fatal() {
        use reqwest::StatusCode;
        // 5xx + 429 are transient ⇒ Io ⇒ retried with backoff.
        for s in [
            StatusCode::BAD_GATEWAY,
            StatusCode::SERVICE_UNAVAILABLE,
            StatusCode::GATEWAY_TIMEOUT,
            StatusCode::INTERNAL_SERVER_ERROR,
            StatusCode::TOO_MANY_REQUESTS,
        ] {
            assert!(
                matches!(classify_status(s, "x".into()), GatewayError::Io(_)),
                "{s} should be transient"
            );
        }
        // 4xx auth/config failures are fatal ⇒ Bind ⇒ surfaced immediately.
        for s in [
            StatusCode::UNAUTHORIZED,
            StatusCode::FORBIDDEN,
            StatusCode::BAD_REQUEST,
            StatusCode::NOT_FOUND,
        ] {
            assert!(
                matches!(classify_status(s, "x".into()), GatewayError::Bind(_)),
                "{s} should be fatal"
            );
        }
    }

    #[test]
    fn sender_allowed_semantics() {
        let allowed: HashSet<String> = ["@a:hs".to_string()].into_iter().collect();
        assert!(sender_allowed(None, "@anyone:hs")); // unset ⇒ everyone
        assert!(sender_allowed(Some(&allowed), "@a:hs"));
        assert!(!sender_allowed(Some(&allowed), "@b:hs"));
    }

    #[test]
    fn extract_messages_surfaces_mention_reply_and_event_id() {
        let sync = sync_from(serde_json::json!({
            "next_batch": "s9",
            "rooms": { "join": { "!room:hs": { "timeline": { "events": [
                // Plain message — no mention, no reply.
                { "type": "m.room.message", "event_id": "$plain", "sender": "@alice:hs",
                  "content": { "msgtype": "m.text", "body": "just chatting" } },
                // @-mention via m.mentions.
                { "type": "m.room.message", "event_id": "$ment", "sender": "@alice:hs",
                  "content": { "msgtype": "m.text", "body": "hey lav",
                               "m.mentions": { "user_ids": ["@lav:hs"] } } },
                // Reply to one of the bot's messages.
                { "type": "m.room.message", "event_id": "$rep", "sender": "@bob:hs",
                  "content": { "msgtype": "m.text", "body": "thanks",
                               "m.relates_to": { "m.in_reply_to": { "event_id": "$mine" } } } }
            ] } } } }
        }));
        let msgs = extract_messages(sync, "@lav:hs", None, None);
        assert_eq!(msgs.len(), 3);
        assert_eq!(msgs[0].event_id, "$plain");
        assert!(!msgs[0].mentions_bot && msgs[0].in_reply_to.is_none());
        assert!(msgs[1].mentions_bot);
        assert_eq!(msgs[2].in_reply_to.as_deref(), Some("$mine"));
    }

    #[test]
    fn mention_detection_via_text_fallback() {
        let mk = |body: &str| EventContent {
            msgtype: Some("m.text".into()),
            body: Some(body.into()),
            ..Default::default()
        };
        // Full MXID and @localpart as tokens both count.
        assert!(mentions_bot(&mk("hey @lav:hs can you help"), "@lav:hs"));
        assert!(mentions_bot(&mk("@lav please look"), "@lav:hs"));
        // A substring of a larger token does not (no false positive).
        assert!(!mentions_bot(&mk("email lavabit@example.com"), "@lav:hs"));
        assert!(!mentions_bot(&mk("nothing to see"), "@lav:hs"));
    }

    #[test]
    fn message_triggers_dm_vs_group() {
        let mut ours = RecentIds::new(8);
        ours.insert("$mine".into());
        // DM: always engage, even with no mention/reply.
        assert!(message_triggers(true, false, None, &ours));
        // Group: engage only on mention or reply-to-ours.
        assert!(!message_triggers(false, false, None, &ours));
        assert!(message_triggers(false, true, None, &ours));
        assert!(message_triggers(false, false, Some("$mine"), &ours));
        // Reply to a message that isn't ours doesn't engage.
        assert!(!message_triggers(false, false, Some("$other"), &ours));
    }

    #[test]
    fn tool_hint_prefers_salient_keys_and_truncates() {
        assert_eq!(
            tool_hint(r#"{"path":"src/lib.rs"}"#).as_deref(),
            Some("src/lib.rs")
        );
        assert_eq!(
            tool_hint(r#"{"command":"cargo test"}"#).as_deref(),
            Some("cargo test")
        );
        // Falls back to the first string value when no salient key is present.
        assert_eq!(
            tool_hint(r#"{"depth":3,"label":"x"}"#).as_deref(),
            Some("x")
        );
        // Non-string-only / unparseable → None.
        assert_eq!(tool_hint(r#"{"n":5}"#), None);
        assert_eq!(tool_hint("not json"), None);
        // Long values are truncated with an ellipsis.
        let long = format!(r#"{{"query":"{}"}}"#, "a".repeat(100));
        let hint = tool_hint(&long).unwrap();
        assert!(hint.ends_with('…') && hint.chars().count() == 61);
    }

    #[test]
    fn recent_ids_bounded_and_membership() {
        let mut ids = RecentIds::new(2);
        ids.insert("$a".into());
        ids.insert("$b".into());
        ids.insert("$c".into()); // evicts $a
        assert!(!ids.contains("$a"));
        assert!(ids.contains("$b") && ids.contains("$c"));
        ids.insert("".into()); // empty ignored
        assert!(!ids.contains(""));
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
