//! `lvz-gw-matrix` — a Matrix gateway (§7.2): a chat-driven frontend for the
//! shared agent on your homeserver (e.g. Continuwuity).
//!
//! Deliberately a small client over the Matrix client-server REST API (`reqwest` + JSON),
//! not the heavyweight `matrix-sdk` — mirroring the hand-rolled provider adapters and the
//! project's minimal-dependency convention. The lattice Phase 4 Port is this same client
//! pointed at `matrix-cs` (see `lattice`). It logs in with a password, long-polls `/sync`,
//! and for each inbound `m.room.message` (`m.text`) from another user runs an agent turn
//! (session = room id, so `lvz-memory` keeps per-room continuity) and posts the answer back.
//!
//! Scope: unencrypted rooms by default. **End-to-end encryption is opt-in** behind the `e2ee`
//! Cargo feature (Olm/Megolm via the crypto-only `matrix-sdk-crypto`, contained to the `e2ee`
//! module);
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
//!    E2EE (see the `e2ee` module).
//! 3. **Password login** (`MATRIX_PASSWORD`) — the fallback; the issued session is persisted to the
//!    state dir (if any) so the next start takes path 2. A configured device id (`MATRIX_DEVICE_ID`)
//!    or a previously-persisted one is reused on re-login so the device stays stable.

#![warn(missing_docs)]

use std::collections::{HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use futures::stream::StreamExt;
use lvz_protocol::{AgentHandle, Event, Gateway, GatewayError, ToolImage, TurnRequest};
use lvz_schedule::ScheduleRegistry;
use lvz_tools::ToolRegistry;
use serde::{Deserialize, Serialize};
use tracing::{error, info, warn};

#[cfg(feature = "e2ee")]
mod e2ee;
mod lattice;
mod media;

pub use lattice::{
    DialContract, ECS_EFS_VOLUME_ID, LATTICE_HOMESERVER, LATTICE_HTTP_HOST, LATTICE_SERVER_NAME,
};

/// Long-poll window for `/sync` (ms). The server holds the request open until an event
/// arrives or this elapses.
const SYNC_TIMEOUT_MS: u64 = 30_000;

/// UI language for notices this gateway *authors itself* — currently just the graceful-shutdown
/// message posted to the home room. Inbound turns and the agent's replies are unaffected; this only
/// picks the language of gateway-emitted copy. The CLI resolves it from `--lang`/`LANG` (only
/// `KO_KR` selects Korean), matching how the legion council localises its progress notices.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Language {
    /// English (the default).
    #[default]
    English,
    /// Korean, selected when the resolved locale is `KO_KR`.
    Korean,
}

impl Language {
    /// The friendly graceful-shutdown notice posted to the home room, in this language.
    fn shutdown_notice(self) -> &'static str {
        match self {
            Language::English => {
                "👋 Lavoisier is going offline for a bit — thanks for chatting, and see you soon!"
            }
            Language::Korean => {
                "👋 Lavoisier가 잠시 자리를 비웁니다 — 함께해 주셔서 고마워요. 곧 다시 올게요!"
            }
        }
    }
}

/// A Matrix gateway bound to a homeserver and a bot account.
pub struct MatrixGateway {
    homeserver: String,
    /// HTTP `Host` when it must differ from [`Self::homeserver`]'s authority. Lattice:
    /// [`LATTICE_HTTP_HOST`]. `None` leaves the header to the URL (the ECS path).
    http_host: Option<String>,
    /// When set, a resolved MXID must be on this server. Lattice: [`LATTICE_SERVER_NAME`].
    server_name: Option<String>,
    /// Opt-in `POST /register` before password login. Off by default.
    register: bool,
    /// `m.login.registration_token` secret. Env `MATRIX_REGISTRATION_TOKEN` only.
    registration_token: Option<String>,
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
    /// Refuse to start when E2EE cannot be initialised, instead of degrading to plaintext.
    ///
    /// Off by default, because for a general-purpose gateway serving a mix of plaintext and
    /// encrypted rooms, continuing without encryption is the useful behaviour. It is the **wrong**
    /// default for a deployment whose rooms are all encrypted: the process stays up, the task
    /// reports healthy, `/sync` runs — and the bot is silently unable to read or write anything in
    /// the rooms it exists to serve. A wrong `MATRIX_CRYPTO_STORE_KEY`, a store at the wrong path
    /// or a corrupt database all land in that one degrade arm.
    require_e2ee: bool,
    /// Built on first use. A lattice `http_host` resolves the dial host and pins `Host`.
    http_client: OnceLock<reqwest::Client>,
    /// Test-only URL port so a listener on a high port can stand in for `:80`.
    /// Production dials the URL port (80 on the lattice plane).
    #[cfg(test)]
    connect_port: Option<u16>,
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
    /// Per-member tool permissions: `user_id` → the tools permitted to them. When this map is
    /// non-empty, a sender absent from it is granted no tools (fail closed). When it is empty,
    /// members stay unconstrained and only [`Self::room_tools`] applies. A listed member is
    /// combined with the room policy by intersection. See [`Self::tools_for`].
    user_tools: HashMap<String, HashSet<String>>,
    /// The "home" room: the single room that receives the shutdown notice when the gateway is
    /// stopped (SIGTERM / Ctrl-C). `None` ⇒ no notice is sent.
    home_room: Option<String>,
    /// Scheduled jobs run *inside* this gateway's loop, reporting their outcome to a room. `None`
    /// ⇒ no schedule (the default). Shared with the `schedule_*` tools so chat can query it.
    schedule: Option<Arc<ScheduleRegistry>>,
    /// Tools a scheduled `Action::Tool` dispatches through — the *same* registry the agent uses,
    /// so a scheduled call and a model-issued call hit identical tool instances.
    schedule_tools: ToolRegistry,
    /// Default room for schedule reports, used when a job names none. Falls back to
    /// [`Self::home_room`].
    schedule_room: Option<String>,
    /// Directory inbound media (images/files) is downloaded to. `Some` **enables** media ingest:
    /// an engaged image/file message is fetched here and its local path handed to the agent so a
    /// tool can act on it. `None` (the default) ⇒ media messages are ignored, as before.
    media_dir: Option<PathBuf>,
    /// Language for gateway-authored notices (the shutdown message). Defaults to English.
    lang: Language,
}

impl MatrixGateway {
    /// Internal base constructor with all optional knobs unset.
    fn base(homeserver: impl Into<String>, user: impl Into<String>) -> Self {
        Self {
            homeserver: homeserver.into().trim_end_matches('/').to_string(),
            http_host: None,
            server_name: None,
            register: false,
            registration_token: None,
            user: user.into(),
            password: None,
            access_token: None,
            device_id: None,
            state_dir: None,
            crypto_passphrase: None,
            require_e2ee: false,
            http_client: OnceLock::new(),
            #[cfg(test)]
            connect_port: None,
            // Seed the transaction counter from the process-start time (nanos since the epoch) so
            // txn ids never reset to a value used by a prior run. Matrix dedupes sends by
            // (device, txn id); a counter that restarted at 0 each boot could collide with an
            // earlier event under the same device id and get silently dropped. The encrypted path
            // sidesteps this with `ruma::TransactionId::new()`, but `ruma` is e2ee-only (and needs
            // Rust ≥1.93), so the default build seeds the counter instead.
            txn: AtomicU64::new(process_seed()),
            auto_join: true,
            allowed_users: None,
            allowed_rooms: None,
            room_tools: HashMap::new(),
            user_tools: HashMap::new(),
            home_room: None,
            schedule: None,
            schedule_tools: ToolRegistry::new(),
            schedule_room: None,
            media_dir: None,
            lang: Language::English,
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

    /// Send this `Host` header instead of the homeserver URL's authority.
    ///
    /// Lattice sets [`LATTICE_HTTP_HOST`] while [`MATRIX_HOMESERVER`](Self::from_env) stays the
    /// ClusterIP dial URL. The client resolves that dial host and requests the `Host` name.
    pub fn with_http_host(mut self, host: impl Into<String>) -> Self {
        self.http_host = Some(host.into());
        self
    }

    /// Require the logged-in MXID to be `@localpart:<server_name>`.
    pub fn with_server_name(mut self, server_name: impl Into<String>) -> Self {
        self.server_name = Some(server_name.into());
        self
    }

    /// Try `POST /_matrix/client/v3/register` before password login.
    ///
    /// `M_USER_IN_USE` falls through to login, so a scripted boot is idempotent. Off unless
    /// `MATRIX_REGISTER` / `[gateway] matrix_register` says so. An access token still wins and
    /// skips registration. On a lattice dial this also requires
    /// [`Self::with_registration_token`] (`m.login.registration_token`).
    pub fn with_register(mut self, register: bool) -> Self {
        self.register = register;
        self
    }

    /// Registration-token auth (`m.login.registration_token`) for [`Self::with_register`].
    ///
    /// Required when registration is enabled on a lattice dial. Without it the dial is refused.
    /// A non-lattice `MATRIX_REGISTER` with no token uses `m.login.dummy` (lab only, not G4).
    pub fn with_registration_token(mut self, token: impl Into<String>) -> Self {
        self.registration_token = Some(token.into());
        self
    }

    /// Replace the login user (localpart or MXID).
    pub fn with_user(mut self, user: impl Into<String>) -> Self {
        self.user = user.into();
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

    /// Make E2EE **mandatory**: a failure to initialise the crypto store aborts the gateway with
    /// the underlying error rather than degrading to plaintext.
    ///
    /// For an all-encrypted deployment this converts "boots clean, cannot decrypt" — which looks
    /// healthy to ECS and to any liveness check — into a loud startup failure.
    pub fn with_require_e2ee(mut self, required: bool) -> Self {
        self.require_e2ee = required;
        self
    }

    /// Set the directory inbound media (images/files) is downloaded to, **enabling** media ingest.
    /// An engaged `m.image`/`m.file`/`m.audio`/`m.video` message is then fetched here and its local
    /// path handed to the agent (as a line appended to the turn) so a tool can act on it. Unset ⇒
    /// media messages are ignored (the default). Note: encrypted-room media (whose reference lives
    /// under `file` with decryption keys, not a plaintext `url`) is not yet ingested.
    pub fn with_media_dir(mut self, dir: impl Into<PathBuf>) -> Self {
        self.media_dir = Some(dir.into());
        self
    }

    /// Set the language for gateway-authored notices (currently the graceful-shutdown message).
    /// Defaults to [`Language::English`]. Inbound turns and the agent's replies are unaffected.
    pub fn with_language(mut self, lang: Language) -> Self {
        self.lang = lang;
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
    /// Rooms absent from the map are unconstrained. See `Self::tools_for`.
    pub fn with_room_tools(mut self, map: impl IntoIterator<Item = (String, Vec<String>)>) -> Self {
        self.room_tools = map
            .into_iter()
            .map(|(k, v)| (k, v.into_iter().collect()))
            .collect();
        self
    }

    /// Set per-member tool permissions: each `user_id` maps to the tools permitted to that member.
    /// An empty map leaves members unconstrained (room policy only). A non-empty map is an
    /// allowlist: a sender it does not name gets no tools. Listed members are intersected with
    /// the room policy. See [`Self::tools_for`].
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

    /// Run `schedule`'s jobs inside this gateway's loop, dispatching `Action::Tool` fires through
    /// `tools`. Pass the *same* [`ToolRegistry`] the agent was built with so a scheduled tool call
    /// and a model-issued one are indistinguishable.
    pub fn with_schedule(mut self, schedule: Arc<ScheduleRegistry>, tools: ToolRegistry) -> Self {
        self.schedule = Some(schedule);
        self.schedule_tools = tools;
        self
    }

    /// Default room for schedule reports, for jobs that don't name their own. Without this (and
    /// without a home room) a job's report has nowhere to go and is logged to stderr instead.
    pub fn with_schedule_room(mut self, room: impl Into<String>) -> Self {
        let room = room.into();
        self.schedule_room = (!room.is_empty()).then_some(room);
        self
    }

    /// Where a report for `job_room` should be posted: the job's own room, else the configured
    /// schedule room, else the home room.
    fn report_room(&self, job_room: Option<&str>) -> Option<String> {
        job_room
            .map(str::to_string)
            .or_else(|| self.schedule_room.clone())
            .or_else(|| self.home_room.clone())
    }

    /// The effective per-turn tool allowlist for a `(room, sender)`, or `None` when the turn is
    /// unconstrained (the agent's full tool set).
    ///
    /// When [`Self::user_tools`] is empty, behaviour is unchanged: a room absent from
    /// [`Self::room_tools`] yields `None`, and a listed room yields that room's set. When the
    /// member map is non-empty and `sender` is absent from it, the result is `Some(Vec::new())`
    /// — no tools are advertised or callable, including in a room with no room entry (fail
    /// closed). A listed member is intersected with the room set when the room is also listed;
    /// otherwise that member's own set is used. An empty `Some` means "no tools".
    ///
    /// Scheduled jobs do not call this. A tool job dispatches through the shared registry and a
    /// prompt job carries no member identity, so both bypass the member map.
    fn tools_for(&self, room: &str, sender: &str) -> Option<Vec<String>> {
        // A non-empty member map is an allowlist. A sender it does not name must not inherit the
        // room's tools or the unconstrained catalogue.
        if !self.user_tools.is_empty() && !self.user_tools.contains_key(sender) {
            return Some(Vec::new());
        }
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
    /// `MATRIX_ALLOWED_USERS`, `MATRIX_ALLOWED_ROOMS` (comma-separated), `MATRIX_HOME_ROOM`,
    /// `MATRIX_MEDIA_DIR` (enables downloading inbound images/files for tool use).
    /// Lattice Port (optional, off unless set): `MATRIX_HTTP_HOST`, `MATRIX_SERVER_NAME`,
    /// `MATRIX_REGISTER`, `MATRIX_REGISTRATION_TOKEN`. See [`DialContract`].
    /// Per-room/per-member tool permissions are richer than env can cleanly express and are set
    /// only via the TOML config (`with_room_tools`/`with_user_tools`).
    pub fn from_env() -> Result<Self, GatewayError> {
        let homeserver = std::env::var("MATRIX_HOMESERVER")
            .map_err(|_| GatewayError::Bind("MATRIX_HOMESERVER is not set".into()))?;
        let gw = Self::from_env_with_homeserver(homeserver)?;
        gw.ensure_login_user()?;
        Ok(gw)
    }

    /// Password login needs a user. Access-token auth does not. Called after the config file
    /// has had a chance to supply `matrix_user`.
    pub fn ensure_login_user(&self) -> Result<(), GatewayError> {
        if self.access_token.is_none() && self.user.is_empty() {
            return Err(GatewayError::Bind(
                "MATRIX_USER is required for password login".into(),
            ));
        }
        Ok(())
    }

    /// [`Self::from_env`], with the homeserver URL supplied by the caller.
    ///
    /// The CLI uses this so `[gateway] matrix_homeserver` can fill in when
    /// `MATRIX_HOMESERVER` is unset. Every other `MATRIX_*` variable is still read from the
    /// environment. Lattice completeness is checked by [`Self::revalidate_lattice`] after the
    /// config file overlays, not here.
    pub fn from_env_with_homeserver(homeserver: impl Into<String>) -> Result<Self, GatewayError> {
        let opt = |k: &str| std::env::var(k).ok().filter(|v| !v.is_empty());

        let homeserver = homeserver.into();
        let access_token = opt("MATRIX_ACCESS_TOKEN");
        let password = opt("MATRIX_PASSWORD");
        let user = opt("MATRIX_USER").unwrap_or_default();

        if access_token.is_none() && password.is_none() {
            return Err(GatewayError::Bind(
                "set MATRIX_ACCESS_TOKEN, or MATRIX_USER + MATRIX_PASSWORD".into(),
            ));
        }

        let mut gw = Self::base(homeserver, user);
        gw.access_token = access_token;
        gw.password = password;
        gw.device_id = opt("MATRIX_DEVICE_ID");
        gw.state_dir = opt("MATRIX_STATE_DIR").map(PathBuf::from);
        if let Some(host) = opt("MATRIX_HTTP_HOST") {
            lattice::check_http_host(&host)?;
            gw.http_host = Some(host);
        }
        if let Some(name) = opt("MATRIX_SERVER_NAME") {
            lattice::check_server_name(&name)?;
            gw.server_name = Some(name);
        }
        if let Some(flag) = opt("MATRIX_REGISTER") {
            gw.register = lattice::parse_register_flag(&flag)?.unwrap_or(false);
        }
        gw.registration_token = opt("MATRIX_REGISTRATION_TOKEN");
        gw.crypto_passphrase = opt("MATRIX_CRYPTO_STORE_KEY");
        gw.media_dir = opt("MATRIX_MEDIA_DIR").map(PathBuf::from);
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

    /// Lattice completeness, after env and the config file have both been applied.
    ///
    /// A deployment that sets none of the lattice markers skips the check, so the ECS
    /// spider42 path is unchanged. Any one marker requires the full pin.
    pub fn revalidate_lattice(&self) -> Result<(), GatewayError> {
        self.dial_contract().validate()
    }

    fn dial_contract(&self) -> lattice::DialContract {
        lattice::DialContract {
            homeserver: self.homeserver.clone(),
            http_host: self.http_host.clone(),
            server_name: self.server_name.clone(),
            user: self.user.clone(),
            device_id: self.device_id.clone(),
            state_dir: self.state_dir.as_ref().map(|p| p.display().to_string()),
            has_access_token: self.access_token.is_some(),
            has_password: self.password.is_some(),
            register: self.register,
            has_registration_token: self.registration_token.is_some(),
        }
    }

    fn enforce_server_name(&self, user_id: &str) -> Result<(), GatewayError> {
        if let Some(name) = &self.server_name {
            lattice::user_on_server(user_id, name)?;
        }
        Ok(())
    }

    /// Base URL for client-server requests. Lattice rewrites the authority to [`Self::http_host`]
    /// so the `Host` header is the wasmCloud host, while [`Self::homeserver`] stays the dial URL
    /// recorded in `session.json`.
    fn request_base(&self) -> Result<String, GatewayError> {
        let base = lattice::request_base(&self.homeserver, self.http_host.as_deref())?;
        #[cfg(test)]
        if let Some(port) = self.connect_port {
            let Some((scheme, rest)) = base.split_once("://") else {
                return Ok(base);
            };
            let host = rest.split_once('/').map(|(h, _)| h).unwrap_or(rest);
            let host = host.split_once(':').map(|(h, _)| h).unwrap_or(host);
            return Ok(format!("{scheme}://{host}:{port}"));
        }
        Ok(base)
    }

    /// Point request URLs at a test listener. The `Host` header stays [`Self::http_host`].
    #[cfg(test)]
    fn with_connect_port(mut self, port: u16) -> Self {
        self.connect_port = Some(port);
        self
    }

    fn url(&self, path: &str) -> Result<String, GatewayError> {
        Ok(format!("{}{path}", self.request_base()?))
    }

    async fn ensure_client(&self) -> Result<(), GatewayError> {
        if self.http_client.get().is_some() {
            return Ok(());
        }
        let client = self.build_client().await?;
        let _ = self.http_client.set(client);
        Ok(())
    }

    fn http(&self) -> Result<&reqwest::Client, GatewayError> {
        self.http_client
            .get()
            .ok_or_else(|| GatewayError::Io("matrix http client used before it was built".into()))
    }

    /// Build a request. [`Self::ensure_client`] must have finished; the builder borrows the
    /// stored client, which an `async` fn cannot return across an `.await`.
    fn call(
        &self,
        method: reqwest::Method,
        path: &str,
    ) -> Result<reqwest::RequestBuilder<'_>, GatewayError> {
        let url = self.url(path)?;
        let mut req = self.http()?.request(method, url);
        if let Some(host) = &self.http_host {
            req = req.header(reqwest::header::HOST, host.as_str());
        }
        Ok(req)
    }

    async fn build_client(&self) -> Result<reqwest::Client, GatewayError> {
        let Some(host) = self.http_host.clone() else {
            return Ok(reqwest::Client::new());
        };
        let (dial_host, dial_port) = lattice::dial_host_port(&self.homeserver)?;
        // `std` DNS, off the runtime. The workspace tokio features do not include `net`,
        // and a lattice boot resolves one name.
        let lookup_name = dial_host.clone();
        let addrs = tokio::task::spawn_blocking(move || {
            use std::net::ToSocketAddrs;
            (lookup_name.as_str(), dial_port)
                .to_socket_addrs()
                .map(|iter| iter.collect::<Vec<_>>())
        })
        .await
        .map_err(|e| GatewayError::Io(format!("resolving {dial_host}: {e}")))?
        .map_err(|e| GatewayError::Io(format!("resolving {dial_host}: {e}")))?;
        if addrs.is_empty() {
            return Err(GatewayError::Io(format!("no addresses for {dial_host}")));
        }
        let mut headers = reqwest::header::HeaderMap::new();
        let value = reqwest::header::HeaderValue::from_str(&host).map_err(|e| {
            GatewayError::Bind(format!("MATRIX_HTTP_HOST is not a header value: {e}"))
        })?;
        headers.insert(reqwest::header::HOST, value);
        // `resolve` replaces the list; pass every address in one call. The URL port
        // still wins over these ports (reqwest), which is port 80 for the lattice dial.
        let builder = reqwest::Client::builder()
            .default_headers(headers)
            .resolve_to_addrs(&host, &addrs);
        builder
            .build()
            .map_err(|e| GatewayError::Io(format!("matrix http client: {e}")))
    }

    /// Install a client that already resolves [`Self::http_host`]. Tests use this so they do
    /// not need cluster DNS.
    #[cfg(test)]
    fn install_client(&self, client: reqwest::Client) {
        let _ = self.http_client.set(client);
    }

    /// Gate G4: log in, send one `m.text`, and `/sync` until that event id is in a joined
    /// timeline. The read-back includes the bot's own event (a normal turn would skip it).
    ///
    /// Two sync rounds at most. The first is the baseline sync; the second uses `next_batch`
    /// if the send has not landed yet.
    pub async fn probe_send_sync(&self, room_id: &str, body: &str) -> Result<String, GatewayError> {
        let session = self.resolve_session().await?;
        let event_id = self
            .send_message(&session.access_token, room_id, body)
            .await?;
        let mut since: Option<String> = None;
        for _ in 0..2 {
            let raw = self
                .sync_once(&session.access_token, since.as_deref())
                .await?;
            if sync_has_event(&raw, &event_id) {
                return Ok(event_id);
            }
            since = raw
                .get("next_batch")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string);
            if since.is_none() {
                break;
            }
        }
        Err(GatewayError::Protocol(format!(
            "probe did not read back {event_id}"
        )))
    }

    /// Resolve the session to serve under, following the documented precedence: explicit access
    /// token → persisted session → optional registration → password login. The chosen session
    /// is persisted to the state dir (if configured) so a later restart reuses the same device.
    async fn resolve_session(&self) -> Result<Session, GatewayError> {
        self.revalidate_lattice()?;
        // 1. Explicit access token: resolve the identity via whoami (no login).
        if let Some(token) = &self.access_token {
            let who = self.whoami(token).await?;
            let device_id = self.pick_device(who.device_id);
            return self.accept_session(Session {
                access_token: token.clone(),
                user_id: who.user_id,
                device_id,
            });
        }

        // 2. Persisted session from a previous run (validated against whoami). On success the
        //    device id is stable across restarts; on failure we fall through to password login,
        //    reusing the persisted device id so even a re-login keeps the same device.
        let persisted = self.load_session();
        if let Some(saved) = &persisted {
            match self.whoami(&saved.access_token).await {
                Ok(who) => {
                    let device_id = match who.device_id.filter(|d| !d.is_empty()) {
                        Some(got) => self.pick_device(Some(got)),
                        None => saved.device_id.clone(),
                    };
                    info!(%device_id, "reusing persisted session");
                    return self.accept_session(Session {
                        access_token: saved.access_token.clone(),
                        user_id: who.user_id,
                        device_id,
                    });
                }
                Err(e) => {
                    warn!(error = %e, "persisted token rejected; falling back to password login")
                }
            }
        }

        // 3. Optional registration, then password login. Reuse a configured or previously
        //    persisted device id so the device stays stable. `M_USER_IN_USE` is not a failure:
        //    the account already exists and login below reuses it.
        let reuse_device = self
            .device_id
            .clone()
            .or_else(|| persisted.as_ref().map(|s| s.device_id.clone()));
        if self.register {
            if let Some(session) = self.register(reuse_device.as_deref()).await? {
                return self.accept_session(session);
            }
        }
        let session = self.login(reuse_device.as_deref()).await?;
        self.accept_session(session)
    }

    /// Prefer the homeserver-reported device. Fall back to the configured id when whoami omits
    /// one (the lattice pin). A disagreement is logged; the token's device wins.
    fn pick_device(&self, reported: Option<String>) -> String {
        match (reported.filter(|d| !d.is_empty()), self.device_id.clone()) {
            (Some(got), Some(want)) if got != want => {
                warn!(
                    got = %got,
                    configured = %want,
                    "whoami device id differs from MATRIX_DEVICE_ID; using the homeserver's"
                );
                got
            }
            (Some(got), _) => got,
            (None, Some(want)) => want,
            (None, None) => String::new(),
        }
    }

    fn accept_session(&self, session: Session) -> Result<Session, GatewayError> {
        self.enforce_server_name(&session.user_id)?;
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
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::GET, "/_matrix/client/v3/account/whoami")?
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
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::POST, "/_matrix/client/v3/login")?
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

    /// `POST /register`, then fall through on `M_USER_IN_USE`. `Some` is a fresh session.
    async fn register(&self, device_id: Option<&str>) -> Result<Option<Session>, GatewayError> {
        self.with_retry("register", || self.register_once(device_id))
            .await
    }

    async fn register_once(
        &self,
        device_id: Option<&str>,
    ) -> Result<Option<Session>, GatewayError> {
        let first = self.post_register(device_id, None).await?;
        if first.status == reqwest::StatusCode::UNAUTHORIZED {
            if let Some(session) = first
                .body
                .get("session")
                .and_then(serde_json::Value::as_str)
            {
                let second = self.post_register(device_id, Some(session)).await?;
                return interpret_register(second);
            }
        }
        interpret_register(first)
    }

    async fn post_register(
        &self,
        device_id: Option<&str>,
        uia_session: Option<&str>,
    ) -> Result<RegisterHttp, GatewayError> {
        let password = self.password.as_deref().ok_or_else(|| {
            GatewayError::Bind(
                "MATRIX_REGISTER requires MATRIX_PASSWORD (an access token skips registration)"
                    .into(),
            )
        })?;
        let localpart = lattice::register_localpart(&self.user);
        if localpart.is_empty() {
            return Err(GatewayError::Bind(
                "MATRIX_REGISTER requires MATRIX_USER".into(),
            ));
        }
        let mut auth = if let Some(token) = &self.registration_token {
            serde_json::json!({ "type": "m.login.registration_token", "token": token })
        } else if self.dial_contract().is_lattice() {
            return Err(GatewayError::Bind(
                "lattice MATRIX_REGISTER requires MATRIX_REGISTRATION_TOKEN \
                 (m.login.registration_token)"
                    .into(),
            ));
        } else {
            // Non-lattice lab only. G4 does not use m.login.dummy.
            serde_json::json!({ "type": "m.login.dummy" })
        };
        if let Some(session) = uia_session {
            auth["session"] = serde_json::Value::String(session.to_string());
        }
        let mut body = serde_json::json!({
            "username": localpart,
            "password": password,
            "initial_device_display_name": "Lavoisier lattice",
            "auth": auth,
        });
        if let Some(d) = device_id {
            body["device_id"] = serde_json::Value::String(d.to_string());
        }
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::POST, "/_matrix/client/v3/register")?
            .json(&body)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        let body = serde_json::from_str(&text).unwrap_or(serde_json::Value::Null);
        Ok(RegisterHttp { status, body, text })
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
                    warn!(
                        what,
                        error = %e,
                        retry_in_secs = delay.as_secs(),
                        "request failed; retrying"
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
                error!(dir = %dir.display(), error = %e, "could not create state dir");
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
                    error!(path = %path.display(), error = %e, "could not persist session");
                }
            }
            Err(e) => error!(error = %e, "could not serialise session"),
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
        self.ensure_client().await?;
        let mut req = self
            .call(reqwest::Method::GET, "/_matrix/client/v3/sync")?
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
        self.send_content(
            token,
            room_id,
            serde_json::json!({ "msgtype": "m.text", "body": body }),
        )
        .await
    }

    /// Post an `m.room.message` with caller-supplied content (`m.text`, `m.image`, …).
    async fn send_content(
        &self,
        token: &str,
        room_id: &str,
        payload: serde_json::Value,
    ) -> Result<String, GatewayError> {
        let txn = self.txn.fetch_add(1, Ordering::Relaxed);
        let path = format!(
            "/_matrix/client/v3/rooms/{}/send/m.room.message/lvz{}",
            urlencode(room_id),
            txn
        );
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::PUT, &path)?
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

    /// Upload raw bytes to the homeserver media repo (`POST /_matrix/media/v3/upload`).
    /// Returns the `content_uri` (`mxc://…`).
    ///
    /// Upload stayed on the media v3 route when MSC3916 moved **download** to
    /// `/_matrix/client/v1/media/*`. Continuwuity has no client-v1 upload.
    async fn upload_media(
        &self,
        token: &str,
        bytes: &[u8],
        content_type: &str,
        filename: &str,
    ) -> Result<String, GatewayError> {
        let path = format!("/_matrix/media/v3/upload?filename={}", urlencode(filename));
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::POST, &path)?
            .bearer_auth(token)
            .header(reqwest::header::CONTENT_TYPE, content_type)
            .body(bytes.to_vec())
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Io(format!(
                "matrix media upload {status}: {msg}"
            )));
        }
        let parsed: UploadResponse = resp
            .json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))?;
        if parsed.content_uri.is_empty() {
            return Err(GatewayError::Protocol(
                "matrix media upload missing content_uri".into(),
            ));
        }
        Ok(parsed.content_uri)
    }

    /// Send a **gateway-initiated** message (the shutdown notice, a schedule report) to `room`,
    /// encrypting it when the room is encrypted and a `crypto` handle is available, else plaintext.
    /// Unlike a reply, these have no inbound event to infer the room's modality from, so we consult
    /// the room's `m.room.encryption` state ([`Self::room_encrypted`]) to decide. Returns the
    /// event id. Without the `e2ee` feature this is always a plaintext send.
    async fn send_gateway_message(
        &self,
        token: &str,
        room: &str,
        body: String,
        #[cfg(feature = "e2ee")] crypto: Option<&e2ee::Crypto>,
    ) -> Result<String, GatewayError> {
        #[cfg(feature = "e2ee")]
        if let Some(c) = crypto {
            if self.room_encrypted(token, room).await {
                return c
                    .encrypt_and_send(room.to_string(), body)
                    .await
                    .map_err(|e| GatewayError::Io(e.to_string()));
            }
        }
        self.send_message(token, room, &body).await
    }

    /// Gateway-initiated image (a schedule report JPEG). Encrypts the attachment when the room
    /// is encrypted; otherwise uploads plaintext. Best-effort at the caller.
    async fn send_gateway_image(
        &self,
        token: &str,
        room: &str,
        name: &str,
        image: &ToolImage,
        #[cfg(feature = "e2ee")] crypto: Option<&e2ee::Crypto>,
    ) -> Result<String, GatewayError> {
        #[cfg(feature = "e2ee")]
        if let Some(c) = crypto {
            if self.room_encrypted(token, room).await {
                return self.send_encrypted_image(c, token, room, name, image).await;
            }
        }
        self.send_plaintext_image(token, room, name, image).await
    }

    /// Whether `room` has encryption enabled — i.e. carries an `m.room.encryption` state event with
    /// an algorithm. Used to pick the modality for gateway-initiated messages. Any failure (a `404`
    /// for an unencrypted room, or a transient error) is treated as **unencrypted**, so the caller
    /// falls back to a spec-valid plaintext send rather than blocking on the notice.
    #[cfg(feature = "e2ee")]
    async fn room_encrypted(&self, token: &str, room: &str) -> bool {
        let path = format!(
            "/_matrix/client/v3/rooms/{}/state/m.room.encryption/",
            urlencode(room)
        );
        if self.ensure_client().await.is_err() {
            return false;
        }
        let Ok(req) = self.call(reqwest::Method::GET, &path) else {
            return false;
        };
        let Ok(resp) = req.bearer_auth(token).send().await else {
            return false;
        };
        if !resp.status().is_success() {
            return false;
        }
        resp.json::<serde_json::Value>()
            .await
            .ok()
            .and_then(|v| {
                v.get("algorithm")
                    .and_then(serde_json::Value::as_str)
                    .map(|_| ())
            })
            .is_some()
    }

    /// Download a piece of Matrix media (`mxc://server/mediaId`) into `dir`, returning the saved
    /// path. Uses the **authenticated** media endpoint (`/_matrix/client/v1/media/download`, Matrix
    /// 1.11+) — the bot holds a token and unauthenticated media is being retired. The saved name is
    /// the event id joined with the sender-supplied filename, both sanitised, so two downloads never
    /// collide and nothing escapes `dir`.
    async fn download_media(
        &self,
        token: &str,
        mxc: &str,
        dir: &Path,
        event_id: &str,
        filename: &str,
    ) -> Result<PathBuf, GatewayError> {
        let (server, media_id) = mxc
            .strip_prefix("mxc://")
            .and_then(|s| s.split_once('/'))
            .filter(|(s, m)| !s.is_empty() && !m.is_empty())
            .ok_or_else(|| GatewayError::Protocol(format!("not an mxc uri: {mxc}")))?;
        let path = format!(
            "/_matrix/client/v1/media/download/{}/{}",
            urlencode(server),
            urlencode(media_id)
        );
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::GET, &path)?
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Io(format!(
                "matrix media download {status}: {msg}"
            )));
        }
        let bytes = resp
            .bytes()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        tokio::fs::create_dir_all(dir)
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        let dest = dir.join(format!(
            "{}_{}",
            sanitize_component(event_id),
            sanitize_component(filename)
        ));
        tokio::fs::write(&dest, &bytes)
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        Ok(dest)
    }

    /// React to an event with a single emoji (an `m.reaction` annotation); returns the reaction's
    /// own event id (so a transient ack reaction can later be redacted). Reactions are sent in the
    /// clear — unencrypted by convention — in both plaintext and encrypted rooms.
    async fn react(
        &self,
        token: &str,
        room_id: &str,
        event_id: &str,
        emoji: &str,
    ) -> Result<String, GatewayError> {
        let txn = self.txn.fetch_add(1, Ordering::Relaxed);
        let path = format!(
            "/_matrix/client/v3/rooms/{}/send/m.reaction/lvz{}",
            urlencode(room_id),
            txn
        );
        let payload = serde_json::json!({
            "m.relates_to": { "rel_type": "m.annotation", "event_id": event_id, "key": emoji }
        });
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::PUT, &path)?
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
        let parsed: SendResponse = resp
            .json()
            .await
            .map_err(|e| GatewayError::Protocol(e.to_string()))?;
        Ok(parsed.event_id)
    }

    /// Redact (remove) an event the bot sent — used to retract the transient 👀 ack reaction once
    /// the turn resolves to a success/failure indicator. Best-effort; reactions go out in the clear
    /// so their redaction is a plaintext call too.
    async fn redact(&self, token: &str, room_id: &str, event_id: &str) -> Result<(), GatewayError> {
        let txn = self.txn.fetch_add(1, Ordering::Relaxed);
        let path = format!(
            "/_matrix/client/v3/rooms/{}/redact/{}/lvz{}",
            urlencode(room_id),
            urlencode(event_id),
            txn
        );
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::PUT, &path)?
            .bearer_auth(token)
            .json(&serde_json::json!({}))
            .send()
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(GatewayError::Io(format!("matrix redact {status}: {msg}")));
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
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::PUT, &path)?
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
                error!(%room_id, error = %e, "joined_members failed");
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
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::GET, &path)?
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

    /// Post the shutdown notice to the home room (if one is configured). Best-effort — a friendly
    /// "going offline" line (localised via [`Self::with_language`]), **encrypted when the home room
    /// is encrypted** (under the `e2ee` feature), else plaintext, via [`Self::send_gateway_message`].
    async fn send_shutdown_notice(
        &self,
        token: &str,
        #[cfg(feature = "e2ee")] crypto: Option<&e2ee::Crypto>,
    ) {
        let Some(home) = &self.home_room else {
            return;
        };
        let body = self.lang.shutdown_notice().to_string();
        if let Err(e) = self
            .send_gateway_message(
                token,
                home,
                body,
                #[cfg(feature = "e2ee")]
                crypto,
            )
            .await
        {
            error!(room = %home, error = %e, "failed to send shutdown notice");
        }
    }

    /// Accept a room invite (join the room).
    async fn join_room(&self, token: &str, room_id: &str) -> Result<(), GatewayError> {
        let path = format!("/_matrix/client/v3/join/{}", urlencode(room_id));
        self.ensure_client().await?;
        let resp = self
            .call(reqwest::Method::POST, &path)?
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
                Ok(()) => info!(%room, "auto-joined invited room"),
                Err(e) => {
                    error!(%room, error = %e, "auto-join failed");
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

    /// Fire every due scheduled job and post its report.
    ///
    /// Scheduled fires do not consult [`Self::tools_for`]. A tool job is dispatched through the
    /// shared registry, and a prompt job is submitted with no member identity, so the member tool
    /// map does not apply.
    ///
    /// A report is **encrypted when its report room is encrypted** (under the `e2ee` feature), else
    /// sent in the clear — unlike a reply, a scheduled fire has no inbound event to infer the room's
    /// modality from, so [`Self::send_gateway_message`] consults the room's encryption state. Each
    /// report's event id is recorded in `sent` so **replying to a report re-engages the bot** — that
    /// is what makes "why did this fail?" work in a group room, reusing the existing reply-trigger
    /// gate rather than adding new machinery.
    async fn run_scheduled(
        &self,
        agent: &Arc<dyn AgentHandle>,
        token: &str,
        due: &[usize],
        sent: &mut RecentIds,
        #[cfg(feature = "e2ee")] crypto: Option<&e2ee::Crypto>,
    ) {
        let Some(schedule) = &self.schedule else {
            return;
        };
        for &idx in due {
            let Some(report) = schedule.fire(idx, &self.schedule_tools, agent).await else {
                continue;
            };
            match self.report_room(report.room.as_deref()) {
                Some(room) => {
                    match self
                        .send_gateway_message(
                            token,
                            &room,
                            report.body,
                            #[cfg(feature = "e2ee")]
                            crypto,
                        )
                        .await
                    {
                        Ok(eid) => sent.insert(eid),
                        Err(e) => {
                            error!(
                                job = %report.job_id,
                                %room,
                                error = %e,
                                "schedule: sending job report failed"
                            )
                        }
                    }
                    for image in &report.images {
                        match self
                            .send_gateway_image(
                                token,
                                &room,
                                &report.job_id,
                                image,
                                #[cfg(feature = "e2ee")]
                                crypto,
                            )
                            .await
                        {
                            Ok(eid) => sent.insert(eid),
                            Err(e) => error!(
                                job = %report.job_id,
                                %room,
                                media_type = %image.media_type,
                                len = image.data.len(),
                                error = %e,
                                "schedule: sending job image failed"
                            ),
                        }
                    }
                }
                // Nowhere to report: still surface the outcome so a misconfigured room can't
                // silently swallow a failing job.
                None => info!(
                    job = %report.job_id,
                    report = %report.body,
                    "schedule: job report (no report room configured)"
                ),
            }
        }
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

    /// Decode, upload, and post one tool-result image. Best-effort at the caller.
    async fn send_image_via(
        &self,
        reply: &Reply<'_>,
        token: &str,
        room: &str,
        name: &str,
        image: &ToolImage,
    ) -> Result<String, GatewayError> {
        #[cfg(feature = "e2ee")]
        if let Reply::Encrypted(crypto) = reply {
            return self
                .send_encrypted_image(crypto, token, room, name, image)
                .await;
        }
        let _ = reply;
        self.send_plaintext_image(token, room, name, image).await
    }

    async fn send_plaintext_image(
        &self,
        token: &str,
        room: &str,
        name: &str,
        image: &ToolImage,
    ) -> Result<String, GatewayError> {
        let bytes = media::decode_tool_image(image).ok_or_else(|| {
            warn!(
                tool = %name,
                media_type = %image.media_type,
                len = image.data.len(),
                "tool image base64 did not decode"
            );
            GatewayError::Protocol("tool image base64 did not decode".into())
        })?;
        let filename = media::image_filename(name, &image.media_type);
        let mxc = self
            .upload_media(token, &bytes, &image.media_type, &filename)
            .await?;
        let content = media::plaintext_image_content(&filename, &mxc, &image.media_type, &bytes);
        self.send_content(token, room, content).await
    }

    #[cfg(feature = "e2ee")]
    async fn send_encrypted_image(
        &self,
        crypto: &e2ee::Crypto,
        token: &str,
        room: &str,
        name: &str,
        image: &ToolImage,
    ) -> Result<String, GatewayError> {
        let bytes = media::decode_tool_image(image).ok_or_else(|| {
            warn!(
                tool = %name,
                media_type = %image.media_type,
                len = image.data.len(),
                "tool image base64 did not decode"
            );
            GatewayError::Protocol("tool image base64 did not decode".into())
        })?;
        let filename = media::image_filename(name, &image.media_type);
        let enc = e2ee::encrypt_attachment(&bytes).map_err(|e| GatewayError::Io(e.to_string()))?;
        let mxc = self
            .upload_media(
                token,
                &enc.ciphertext,
                "application/octet-stream",
                &filename,
            )
            .await?;
        let content = media::encrypted_image_content(
            &filename,
            enc.with_url(&mxc),
            &image.media_type,
            &bytes,
        );
        crypto
            .encrypt_and_send_content(room.to_string(), content)
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))
    }

    /// Post each admitted tool-result image. Failures are logged; they never fail the turn.
    async fn post_tool_images(
        &self,
        reply: &Reply<'_>,
        token: &str,
        room: &str,
        sent: &mut RecentIds,
        name: &str,
        images: &[ToolImage],
    ) {
        for image in images {
            match self.send_image_via(reply, token, room, name, image).await {
                Ok(eid) => sent.insert(eid),
                Err(e) => error!(
                    %room,
                    tool = %name,
                    media_type = %image.media_type,
                    len = image.data.len(),
                    error = %e,
                    "tool result image failed"
                ),
            }
        }
    }

    /// Handle one engaged inbound message end to end: acknowledge with a transient 👀 reaction,
    /// show a typing indicator, run the agent — posting a concise notice for each tool call as it
    /// happens — send the answer, and finally swap the 👀 for a ✅/❌ outcome indicator. Replies go
    /// out via `reply` (plaintext or encrypted); reactions and typing always use the plaintext API.
    /// Every message the bot sends is recorded in `sent` so a later reply to it re-engages the bot.
    /// The whole flow is best-effort: ack/typing/reaction failures are logged, not fatal.
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
        // 1. Acknowledge that we saw the message with a transient 👀 reaction; we redact it and
        //    replace it with a ✅/❌ outcome indicator once the turn resolves. Keep its event id so
        //    we can retract it later.
        let ack = match self.react(token, &room, &msg.event_id, "👀").await {
            Ok(eid) => Some(eid),
            Err(e) => {
                error!(%room, error = %e, "react failed");
                None
            }
        };
        // 2. Show "typing…" while we prepare a response.
        if let Err(e) = self.set_typing(token, &room, self_user, true).await {
            error!(%room, error = %e, "typing indicator failed");
        }

        // If this message carried a file and media ingest is enabled, download it and tell the
        // agent where it landed so a tool can act on the bytes (the "bytes-to-tool" path — the model
        // never sees the image, it just receives a local path to hand to a tool).
        let mut body = msg.body;
        if let (Some(att), Some(dir)) = (&msg.attachment, self.media_dir.as_deref()) {
            match self
                .download_media(token, &att.mxc, dir, &msg.event_id, &att.filename)
                .await
            {
                Ok(path) => {
                    let mime = att
                        .mimetype
                        .as_deref()
                        .unwrap_or("application/octet-stream");
                    let note = format!(
                        "\n\n[attachment] The user shared a file, now saved locally at:\n  {}\n\
                         (original name: {}, type: {}). Use your available tools to act on this \
                         file as the user asks.",
                        path.display(),
                        att.filename,
                        mime,
                    );
                    if body.trim().is_empty() {
                        body = format!("The user sent a file with no other message.{note}");
                    } else {
                        body.push_str(&note);
                    }
                    info!(%room, path = %path.display(), "media downloaded for turn");
                }
                Err(e) => {
                    warn!(%room, error = %e, "media download failed");
                    body.push_str(
                        "\n\n[attachment] The user shared a file, but downloading it failed. \
                         Tell them it couldn't be retrieved.",
                    );
                }
            }
        }

        // Apply this room/member's tool permissions (if any) to the turn. The agent core enforces
        // the allowlist; the policy decision lives here.
        let mut turn = TurnRequest::new(room.clone(), body);
        if let Some(tools) = self.tools_for(&room, &msg.sender) {
            turn = turn.with_allowed_tools(tools);
        }
        let mut stream = match agent.submit(turn).await {
            Ok(stream) => stream,
            Err(e) => {
                error!(%room, error = %e, "agent error");
                let _ = self.set_typing(token, &room, self_user, false).await;
                self.finish_reaction(token, &room, &msg.event_id, ack.as_deref(), false)
                    .await;
                return;
            }
        };

        // 3. Stream the turn: accumulate the answer text; post a notice for each tool call as it
        //    completes (buffering the streamed argument JSON to extract a short target hint) and for
        //    each `Event::Notice` progress line (e.g. a legion council's deliberation phases). A
        //    background keep-alive re-asserts the typing indicator on a timer — the server's typing
        //    timeout is 30s, and a silent legion deliberation emits no tool events for ~60s+, so
        //    without this the "typing…" indicator lapses into dead air mid-turn.
        let mut answer = String::new();
        let mut tool_args: HashMap<String, (String, String)> = HashMap::new();
        let mut ok = true;
        let mut keepalive = tokio::time::interval(std::time::Duration::from_secs(20));
        keepalive.tick().await; // consume the immediate first tick; the next fires at +20s
        loop {
            tokio::select! {
                biased;
                item = stream.next() => {
                    let Some(item) = item else { break };
                    match item {
                        Ok(Event::TextDelta(text)) => answer.push_str(&text),
                        Ok(Event::Notice(text)) => {
                            match self.send_via(reply, token, &room, text).await {
                                Ok(eid) => {
                                    sent.insert(eid);
                                }
                                Err(e) => error!(%room, error = %e, "progress notice failed"),
                            }
                            // A notice is progress — keep the indicator alive.
                            let _ = self.set_typing(token, &room, self_user, true).await;
                        }
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
                                self.post_tool_notice(reply, token, &room, self_user, sent, &name, &args)
                                    .await;
                            }
                        }
                        // Provider-run tools (xAI web search, code interpreter, …) never become a
                        // client `ToolUse*`. Without this arm a Grok turn that searched or ran code
                        // on the provider side posts no 🔧 line, so the room cannot tell a tool ran.
                        Ok(Event::ServerToolUse { name, hint, .. }) => {
                            // The hint is the glimpse (a query, a first line of code), shaped as
                            // argument JSON so `tool_hint` truncates it the same way as a client call.
                            let args = if hint.is_empty() {
                                String::new()
                            } else {
                                serde_json::json!({ "query": hint }).to_string()
                            };
                            self.post_tool_notice(reply, token, &room, self_user, sent, &name, &args)
                                .await;
                        }
                        Ok(Event::ToolResultImages { name, images, .. }) => {
                            // JPEG on the human channel. A send failure is logged here and
                            // does not flip `ok` — the model already has the image.
                            self.post_tool_images(reply, token, &room, sent, &name, &images)
                                .await;
                            let _ = self.set_typing(token, &room, self_user, true).await;
                        }
                        Ok(_) => {}
                        Err(e) => {
                            error!(%room, error = %e, "stream error");
                            ok = false;
                            break;
                        }
                    }
                }
                _ = keepalive.tick() => {
                    // No output for a while (e.g. mid-deliberation) — refresh "typing…".
                    let _ = self.set_typing(token, &room, self_user, true).await;
                }
            }
        }

        // A call that streamed a start but never an end (a provider that delivers the tool call
        // whole, or a stream that died mid-call) is still a call the room should see. Post it
        // before the answer so it isn't buried under the final text.
        let leftover: Vec<(String, String)> = tool_args.into_values().collect();
        for (name, args) in leftover {
            self.post_tool_notice(reply, token, &room, self_user, sent, &name, &args)
                .await;
        }

        // 4. Stop typing and send the answer.
        let _ = self.set_typing(token, &room, self_user, false).await;
        let answer = answer.trim();
        if !answer.is_empty() {
            match self.send_via(reply, token, &room, answer.to_string()).await {
                Ok(eid) => sent.insert(eid),
                Err(e) => {
                    error!(%room, error = %e, "send error");
                    ok = false;
                }
            }
        }

        // 5. Swap the 👀 ack for a ✅/❌ outcome indicator on the original message.
        self.finish_reaction(token, &room, &msg.event_id, ack.as_deref(), ok)
            .await;
    }

    /// Post one `🔧 name · hint` line and keep the typing indicator alive. Best-effort.
    #[allow(clippy::too_many_arguments)]
    async fn post_tool_notice(
        &self,
        reply: &Reply<'_>,
        token: &str,
        room: &str,
        self_user: &str,
        sent: &mut RecentIds,
        name: &str,
        args_json: &str,
    ) {
        match self
            .send_via(reply, token, room, tool_notice(name, args_json))
            .await
        {
            Ok(eid) => {
                sent.insert(eid);
            }
            Err(e) => error!(%room, error = %e, "tool notice failed"),
        }
        let _ = self.set_typing(token, room, self_user, true).await;
    }

    /// Retract the transient 👀 ack (if it was sent) and react to the original message with a
    /// success/failure indicator. Best-effort: each step is logged, never fatal.
    async fn finish_reaction(
        &self,
        token: &str,
        room: &str,
        event_id: &str,
        ack: Option<&str>,
        ok: bool,
    ) {
        if let Some(ack) = ack {
            if let Err(e) = self.redact(token, room, ack).await {
                error!(%room, error = %e, "redact ack failed");
            }
        }
        let emoji = if ok { "✅" } else { "❌" };
        if let Err(e) = self.react(token, room, event_id, emoji).await {
            error!(%room, error = %e, "outcome react failed");
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
        info!(
            user_id = %session.user_id,
            device_id = %session.device_id,
            homeserver = %self.homeserver,
            http_host = self.http_host.as_deref().unwrap_or(""),
            "matrix gateway online"
        );
        if let Some(allowed) = &self.allowed_users {
            info!(
                senders = allowed.len(),
                "answering only allowlisted sender(s)"
            );
        }
        if let Some(rooms) = &self.allowed_rooms {
            info!(rooms = rooms.len(), "acting only in allowlisted room(s)");
        }
        if !self.room_tools.is_empty() || !self.user_tools.is_empty() {
            info!(
                rooms = self.room_tools.len(),
                members = self.user_tools.len(),
                "tool permissions set"
            );
        }
        if let Some(home) = &self.home_room {
            info!(room = %home, "home room (receives the shutdown notice)");
        }
        if let Some(schedule) = &self.schedule {
            info!(jobs = schedule.len(), "scheduled job(s)");
            for job in schedule.jobs() {
                match job.schedule.next_after_now() {
                    Some(_) => info!(
                        job = %job.id,
                        expr = %job.expr,
                        action = %job.action.summary(),
                        report_to = %self.report_room(job.room.as_deref())
                            .unwrap_or_else(|| "(stderr — no report room)".to_string()),
                        "schedule: job registered"
                    ),
                    None => warn!(
                        job = %job.id,
                        "schedule: job never fires (impossible schedule) — skipping"
                    ),
                }
            }
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
            self.request_base()?,
            token.clone(),
            &session.user_id,
            &session.device_id,
            self.state_dir.as_ref().map(|d| d.join("crypto")).as_deref(),
            self.crypto_passphrase.as_deref(),
            self.http()?.clone(),
            self.http_host.clone(),
        )
        .await
        {
            Ok(c) => {
                info!("e2ee: matrix E2EE enabled");
                Some(c)
            }
            Err(e) if self.require_e2ee => {
                // Asked for mandatory E2EE and we cannot provide it: fail loudly at startup rather
                // than run deaf in encrypted rooms.
                error!(error = %e, "e2ee: init failed and require_e2ee is set — refusing to start");
                return Err(GatewayError::Bind(format!(
                    "matrix E2EE is required but could not be initialised: {e}"
                )));
            }
            Err(e) => {
                // Degrading is only safe where some rooms are plaintext. `error!`, not `warn!`:
                // in an encrypted deployment this single line is the whole signal that the bot is
                // about to be silently unable to read or write anything.
                error!(error = %e, "e2ee: init failed, continuing WITHOUT encryption (set require_e2ee to make this fatal)");
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
            // Three-way race: shutdown, a due scheduled job, or the next `/sync`. Running the
            // scheduler as a branch of this loop (rather than a spawned task) keeps it on the same
            // task as `crypto`, which is not `Send` in the higher-ranked form a spawn would need.
            let value = tokio::select! {
                biased;
                _ = &mut shutdown => {
                    info!("shutdown signal received, stopping");
                    self.send_shutdown_notice(
                        &token,
                        #[cfg(feature = "e2ee")]
                        crypto.as_ref(),
                    )
                    .await;
                    return Ok(());
                }
                due = wait_schedule(self.schedule.as_ref()) => {
                    self.run_scheduled(
                        &agent,
                        &token,
                        &due,
                        &mut sent,
                        #[cfg(feature = "e2ee")]
                        crypto.as_ref(),
                    )
                    .await;
                    continue;
                }
                res = self.sync_once(&token, Some(&since)) => match res {
                    Ok(value) => value,
                    Err(e) => {
                        // Transient sync failure: back off briefly and retry rather than exit.
                        warn!(error = %e, "sync failed; retrying");
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
                    error!(error = %e, "e2ee: receive_sync failed");
                }
            }

            let next = parse_next_batch(&value)?;
            let resp = match SyncResponse::deserialize(&value) {
                Ok(resp) => resp,
                Err(e) => {
                    error!(error = %e, "malformed sync");
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
                self.media_dir.is_some(),
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
                        self.media_dir.is_some(),
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

/// Wait for the next due scheduled job. With no schedule configured this never resolves, so the
/// serve loop's `select!` simply never picks the branch.
async fn wait_schedule(schedule: Option<&Arc<ScheduleRegistry>>) -> Vec<usize> {
    match schedule {
        Some(s) => s.wait_due().await,
        None => futures::future::pending().await,
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
    /// A downloadable file this message carried (image/file/audio/video), captured only when media
    /// ingest is enabled. `handle_message` fetches the bytes and hands the agent a local path.
    attachment: Option<Attachment>,
}

/// A file referenced by an inbound message, to be downloaded for tool use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Attachment {
    /// The `mxc://server/mediaId` content URI to download.
    mxc: String,
    /// A human filename for the saved file (`content.filename`, else `content.body`).
    filename: String,
    /// The declared MIME type, if the sender's client included one (`content.info.mimetype`).
    mimetype: Option<String>,
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
    media: bool,
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
            let Some((body, attachment)) = message_content(&event.content, media) else {
                continue;
            };
            let mentions_bot = mentions_bot(&event.content, self_user);
            let in_reply_to = reply_target(&event.content);
            out.push(IncomingMessage {
                room: room_id.clone(),
                sender: event.sender,
                body,
                event_id: event.event_id,
                mentions_bot,
                in_reply_to,
                attachment,
            });
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

/// Message types that carry a downloadable file the bot will ingest when media is enabled.
const MEDIA_MSGTYPES: &[&str] = &["m.image", "m.file", "m.audio", "m.video"];

/// Extract the answerable `(body, attachment)` from a message's content. An `m.text` message →
/// `(body, None)`. A media message (image/file/audio/video) → `(caption, Some(attachment))`, but
/// only when `media` ingest is enabled and the content carries a plaintext `url` — encrypted-room
/// media puts the reference under `file` with decryption keys, which isn't ingested yet. Anything
/// else (a non-text message with media off, or an unknown type) → `None`, so the bot ignores it.
pub(crate) fn message_content(
    content: &EventContent,
    media: bool,
) -> Option<(String, Option<Attachment>)> {
    match content.msgtype.as_deref() {
        Some("m.text") => content.body.clone().map(|b| (b, None)),
        Some(t) if media && MEDIA_MSGTYPES.contains(&t) => {
            let mxc = content.url.clone()?;
            // Per the spec, when a separate `filename` is present `body` is a caption; otherwise
            // `body` *is* the filename (and there's no caption).
            let (filename, caption) = match (&content.filename, &content.body) {
                (Some(name), body) => (name.clone(), body.clone().unwrap_or_default()),
                (None, Some(name)) => (name.clone(), String::new()),
                (None, None) => ("attachment".to_string(), String::new()),
            };
            let mimetype = content.info.as_ref().and_then(|i| i.mimetype.clone());
            Some((
                caption,
                Some(Attachment {
                    mxc,
                    filename,
                    mimetype,
                }),
            ))
        }
        _ => None,
    }
}

/// Sanitise one path component for a downloaded-media filename: keep alphanumerics and `.-_`,
/// replace everything else with `_`, and cap the length so a hostile filename can't blow up the
/// path. Never returns an empty string (so a fully-stripped name still yields a usable component).
fn sanitize_component(s: &str) -> String {
    let cleaned: String = s
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || matches!(c, '.' | '-' | '_') {
                c
            } else {
                '_'
            }
        })
        .take(96)
        .collect();
    if cleaned.is_empty() {
        "file".to_string()
    } else {
        cleaned
    }
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

/// The room line for one tool call: `🔧 \`name\`` plus a short target hint when the arguments
/// carry one.
fn tool_notice(name: &str, args_json: &str) -> String {
    match tool_hint(args_json) {
        Some(hint) => format!("🔧 `{name}` · {hint}"),
        None => format!("🔧 `{name}`"),
    }
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

struct RegisterHttp {
    status: reqwest::StatusCode,
    body: serde_json::Value,
    text: String,
}

/// `Some` is a new session. `None` means the localpart is already registered (`M_USER_IN_USE`),
/// which the caller treats as "log in instead".
fn interpret_register(resp: RegisterHttp) -> Result<Option<Session>, GatewayError> {
    if resp.status.is_success() {
        let login: LoginResponse = serde_json::from_value(resp.body).map_err(|e| {
            GatewayError::Protocol(format!("matrix register body: {e}; {}", resp.text))
        })?;
        return Ok(Some(Session {
            access_token: login.access_token,
            user_id: login.user_id,
            device_id: login.device_id,
        }));
    }
    let errcode = resp
        .body
        .get("errcode")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("");
    if errcode == "M_USER_IN_USE" {
        return Ok(None);
    }
    Err(classify_status(
        resp.status,
        format!("matrix register {}: {}", resp.status, resp.text),
    ))
}

/// Classify a non-success HTTP status from the startup auth calls into a [`GatewayError`]:
/// server errors (5xx) and `429 Too Many Requests` are *transient* (`Io` ⇒ retried with backoff);
/// everything else (4xx — bad/expired token, wrong password) is fatal (`Bind` ⇒ surfaced).
fn sync_has_event(sync: &serde_json::Value, event_id: &str) -> bool {
    let Some(rooms) = sync
        .get("rooms")
        .and_then(|r| r.get("join"))
        .and_then(serde_json::Value::as_object)
    else {
        return false;
    };
    rooms.values().any(|room| {
        room.get("timeline")
            .and_then(|t| t.get("events"))
            .and_then(serde_json::Value::as_array)
            .is_some_and(|events| {
                events.iter().any(|ev| {
                    ev.get("event_id").and_then(serde_json::Value::as_str) == Some(event_id)
                })
            })
    })
}

fn classify_status(status: reqwest::StatusCode, msg: String) -> GatewayError {
    if status.is_server_error() || status == reqwest::StatusCode::TOO_MANY_REQUESTS {
        GatewayError::Io(msg)
    } else {
        GatewayError::Bind(msg)
    }
}

/// Seed value for the per-process transaction counter: nanoseconds since the Unix epoch, so a
/// fresh process starts well past any txn id a prior run could have emitted (the counter only ever
/// increments). Falls back to 0 if the clock is somehow before the epoch.
fn process_seed() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
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

/// `POST /_matrix/media/v3/upload` response.
#[derive(Deserialize)]
struct UploadResponse {
    content_uri: String,
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
    /// Content URI (`mxc://…`) of an unencrypted media message (`m.image`/`m.file`/…).
    #[serde(default)]
    url: Option<String>,
    /// Original filename of a media message, when the client sends `body` as a caption instead.
    #[serde(default)]
    filename: Option<String>,
    /// Media metadata block; we read `mimetype` from it.
    #[serde(default)]
    info: Option<MediaInfo>,
}

#[derive(Deserialize, Default)]
struct MediaInfo {
    #[serde(default)]
    mimetype: Option<String>,
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
    use std::io::{Read, Write};
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

    fn sync_from(json: serde_json::Value) -> SyncResponse {
        serde_json::from_value(json).unwrap()
    }

    struct Hit {
        host: String,
        path: String,
        body: String,
    }

    fn spawn_matrix(
        handler: impl Fn(&Hit) -> (u16, String) + Send + Sync + 'static,
    ) -> std::net::SocketAddr {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let handler = Arc::new(handler);
        std::thread::spawn(move || {
            for conn in listener.incoming() {
                let Ok(mut sock) = conn else { break };
                let _ = sock.set_read_timeout(Some(Duration::from_secs(2)));
                let handler = handler.clone();
                loop {
                    let Some(hit) = read_http(&mut sock) else {
                        break;
                    };
                    let (code, body) = handler(&hit);
                    let reason = if code == 200 { "OK" } else { "ERR" };
                    let resp = format!(
                        "HTTP/1.1 {code} {reason}\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: keep-alive\r\n\r\n{body}",
                        body.len()
                    );
                    if sock.write_all(resp.as_bytes()).is_err() {
                        break;
                    }
                }
            }
        });
        addr
    }

    fn read_http(sock: &mut std::net::TcpStream) -> Option<Hit> {
        let mut buf = Vec::new();
        let mut tmp = [0u8; 2048];
        let header_end = loop {
            let n = sock.read(&mut tmp).ok()?;
            if n == 0 {
                return None;
            }
            buf.extend_from_slice(&tmp[..n]);
            if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                break i + 4;
            }
            if buf.len() > 128 * 1024 {
                return None;
            }
        };
        let head = String::from_utf8_lossy(&buf[..header_end]).to_string();
        let mut lines = head.split("\r\n");
        let req = lines.next()?.to_string();
        let mut host = String::new();
        let mut content_len = 0usize;
        for line in lines {
            let Some((k, v)) = line.split_once(':') else {
                continue;
            };
            if k.eq_ignore_ascii_case("host") {
                host = v.trim().to_string();
            }
            if k.eq_ignore_ascii_case("content-length") {
                content_len = v.trim().parse().unwrap_or(0);
            }
        }
        let mut body = buf[header_end..].to_vec();
        while body.len() < content_len {
            let n = sock.read(&mut tmp).ok()?;
            if n == 0 {
                break;
            }
            body.extend_from_slice(&tmp[..n]);
        }
        body.truncate(content_len);
        let path = req.split_whitespace().nth(1).unwrap_or("").to_string();
        Some(Hit {
            host,
            path,
            body: String::from_utf8_lossy(&body).to_string(),
        })
    }

    fn lattice_client(addr: std::net::SocketAddr) -> reqwest::Client {
        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::HOST,
            reqwest::header::HeaderValue::from_static(LATTICE_HTTP_HOST),
        );
        reqwest::Client::builder()
            .default_headers(headers)
            .resolve(LATTICE_HTTP_HOST, addr)
            .timeout(Duration::from_secs(2))
            .build()
            .unwrap()
    }

    fn lattice_gw(user: &str) -> MatrixGateway {
        MatrixGateway::new(LATTICE_HOMESERVER, user, "pw")
            .with_device_id("LAVOISIER_LATTICE")
            .with_http_host(LATTICE_HTTP_HOST)
            .with_server_name(LATTICE_SERVER_NAME)
    }

    #[tokio::test]
    async fn lattice_probe_dials_with_wasmcloud_host_and_reads_back() {
        let hits = Arc::new(Mutex::new(Vec::<Hit>::new()));
        let seen = hits.clone();
        let addr = spawn_matrix(move |hit| {
            seen.lock().unwrap().push(Hit {
                host: hit.host.clone(),
                path: hit.path.clone(),
                body: hit.body.clone(),
            });
            if hit.path.contains("/login") {
                (
                    200,
                    r#"{"access_token":"tok","user_id":"@lav:davidlee18.dev","device_id":"LAVOISIER_LATTICE"}"#.into(),
                )
            } else if hit.path.contains("/send/") {
                (200, r#"{"event_id":"$g4"}"#.into())
            } else if hit.path.contains("/sync") {
                (
                    200,
                    r#"{"next_batch":"s1","rooms":{"join":{"!room:davidlee18.dev":{"timeline":{"events":[{"type":"m.room.message","sender":"@lav:davidlee18.dev","event_id":"$g4","content":{"msgtype":"m.text","body":"g4"}}]}}}}}"#.into(),
                )
            } else {
                (404, r#"{"errcode":"M_UNRECOGNIZED"}"#.into())
            }
        });
        let gw = lattice_gw("@lav:davidlee18.dev").with_connect_port(addr.port());
        gw.install_client(lattice_client(addr));
        let event = tokio::time::timeout(
            Duration::from_secs(3),
            gw.probe_send_sync("!room:davidlee18.dev", "g4"),
        )
        .await
        .expect("probe timed out")
        .expect("probe");
        assert_eq!(event, "$g4");
        let hits = hits.lock().unwrap();
        assert!(
            hits.len() >= 3,
            "expected login, send, sync; got {}",
            hits.len()
        );
        for hit in hits.iter() {
            assert_eq!(hit.host, LATTICE_HTTP_HOST, "path {}", hit.path);
            assert!(
                !hit.path.contains("cluster.local"),
                "request URL must use the hostInterfaces host, path {}",
                hit.path
            );
        }
        let login = hits.iter().find(|h| h.path.contains("/login")).unwrap();
        assert!(login.body.contains("LAVOISIER_LATTICE"), "{}", login.body);
        assert!(login.body.contains("@lav:davidlee18.dev"), "{}", login.body);
    }

    #[tokio::test]
    async fn lattice_register_falls_through_when_user_exists_then_syncs() {
        let hits = Arc::new(Mutex::new(Vec::<(String, String)>::new()));
        let seen = hits.clone();
        let addr = spawn_matrix(move |hit| {
            seen.lock()
                .unwrap()
                .push((hit.path.clone(), hit.body.clone()));
            if hit.path.contains("/register") {
                (400, r#"{"errcode":"M_USER_IN_USE","error":"taken"}"#.into())
            } else if hit.path.contains("/login") {
                (
                    200,
                    r#"{"access_token":"tok","user_id":"@lav:davidlee18.dev","device_id":"LAVOISIER_LATTICE"}"#.into(),
                )
            } else if hit.path.contains("/send/") {
                (200, r#"{"event_id":"$back"}"#.into())
            } else {
                (
                    200,
                    r#"{"next_batch":"s","rooms":{"join":{"!r:davidlee18.dev":{"timeline":{"events":[{"event_id":"$back"}]}}}}}"#.into(),
                )
            }
        });
        let gw = lattice_gw("@lav:davidlee18.dev")
            .with_register(true)
            .with_registration_token("g4-reg-token")
            .with_connect_port(addr.port());
        gw.install_client(lattice_client(addr));
        let event = tokio::time::timeout(
            Duration::from_secs(3),
            gw.probe_send_sync("!r:davidlee18.dev", "again"),
        )
        .await
        .expect("probe timed out")
        .unwrap();
        assert_eq!(event, "$back");
        let hits = hits.lock().unwrap();
        let register = hits
            .iter()
            .find(|(path, _)| path.contains("/register"))
            .expect("register");
        assert!(
            register.1.contains("\"username\":\"lav\""),
            "{}",
            register.1
        );
        assert!(register.1.contains("LAVOISIER_LATTICE"), "{}", register.1);
        assert!(
            register.1.contains("m.login.registration_token"),
            "{}",
            register.1
        );
        assert!(register.1.contains("g4-reg-token"), "{}", register.1);
        assert!(!register.1.contains("m.login.dummy"), "{}", register.1);
        assert!(hits.iter().any(|(path, _)| path.contains("/login")));
    }

    #[tokio::test]
    async fn lattice_rejects_spider42_identity_from_whoami() {
        let hosts = Arc::new(Mutex::new(Vec::<String>::new()));
        let seen = hosts.clone();
        let addr = spawn_matrix(move |hit| {
            seen.lock().unwrap().push(hit.host.clone());
            (
                200,
                r#"{"user_id":"@lav:matrix.spider42.com","device_id":"DEV"}"#.into(),
            )
        });
        let gw = lattice_gw("@lav:davidlee18.dev")
            .with_access_token("tok")
            .with_connect_port(addr.port());
        gw.install_client(lattice_client(addr));
        let err = tokio::time::timeout(
            Duration::from_secs(3),
            gw.probe_send_sync("!r:davidlee18.dev", "x"),
        )
        .await
        .expect("timed out")
        .unwrap_err()
        .to_string();
        assert!(err.contains("matrix.spider42.com"), "{err}");
        assert!(err.contains(LATTICE_SERVER_NAME), "{err}");
        let hosts = hosts.lock().unwrap();
        assert_eq!(hosts.as_slice(), [LATTICE_HTTP_HOST]);
    }

    #[test]
    fn lattice_register_without_token_is_refused() {
        let gw = lattice_gw("@lav:davidlee18.dev").with_register(true);
        let err = gw.revalidate_lattice().unwrap_err().to_string();
        assert!(err.contains("MATRIX_REGISTRATION_TOKEN"), "{err}");
        assert!(gw
            .with_registration_token("g4-reg-token")
            .revalidate_lattice()
            .is_ok());
    }

    #[test]
    fn ecs_gateway_does_not_grow_lattice_requirements() {
        let gw = MatrixGateway::new(
            "https://matrix.spider42.com",
            "@lav:matrix.spider42.com",
            "pw",
        )
        .with_state_dir(format!("/mnt/{ECS_EFS_VOLUME_ID}/matrix"));
        assert!(gw.revalidate_lattice().is_ok());
        assert!(gw.http_host.is_none());
        assert!(gw.server_name.is_none());
        assert!(!gw.register);
    }

    #[test]
    fn shutdown_notice_localises_and_defaults_to_english() {
        // Default is English; the gateway builder can switch it to Korean.
        assert_eq!(Language::default(), Language::English);
        // "Lavoisier" is a name — kept verbatim in both languages, not transliterated.
        assert!(Language::English.shutdown_notice().contains("Lavoisier"));
        assert!(Language::Korean.shutdown_notice().contains("Lavoisier"));
        assert!(Language::Korean
            .shutdown_notice()
            .contains("자리를 비웁니다"));
        // A gateway carries English unless told otherwise, and `with_language` overrides it.
        let gw = MatrixGateway::new("https://hs", "@bot:hs", "pw");
        assert_eq!(gw.lang, Language::English);
        assert_eq!(gw.with_language(Language::Korean).lang, Language::Korean);
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

        // media off ⇒ the m.image is skipped, only the text survives.
        let msgs = extract_messages(sync, "@bot:hs", None, None, false);
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].room, "!room:hs");
        assert_eq!(msgs[0].sender, "@alice:hs");
        assert_eq!(msgs[0].body, "hello bot");
        assert!(msgs[0].attachment.is_none());
    }

    #[test]
    fn extracts_media_message_as_attachment_when_media_on() {
        let sync = sync_from(serde_json::json!({
            "next_batch": "s2",
            "rooms": { "join": { "!room:hs": { "timeline": { "events": [
                { "type": "m.room.message", "sender": "@alice:hs", "event_id": "$img",
                  "content": { "msgtype": "m.image", "body": "prayer.png",
                               "url": "mxc://hs/media123",
                               "info": { "mimetype": "image/png" } } },
                { "type": "m.room.message", "sender": "@alice:hs",
                  "content": { "msgtype": "m.image", "body": "no-url.png" } }
            ] } } } }
        }));

        // media on ⇒ the image with a url becomes an attachment; the one without a url is dropped.
        let msgs = extract_messages(sync, "@bot:hs", None, None, true);
        assert_eq!(msgs.len(), 1);
        let att = msgs[0].attachment.as_ref().expect("attachment captured");
        assert_eq!(att.mxc, "mxc://hs/media123");
        assert_eq!(att.filename, "prayer.png");
        assert_eq!(att.mimetype.as_deref(), Some("image/png"));
        // no caption (filename came from body), so the turn body is empty until augmented.
        assert_eq!(msgs[0].body, "");
    }

    #[test]
    fn media_caption_is_kept_and_filename_taken_from_filename_field() {
        let sync = sync_from(serde_json::json!({
            "next_batch": "s2",
            "rooms": { "join": { "!room:hs": { "timeline": { "events": [
                { "type": "m.room.message", "sender": "@alice:hs", "event_id": "$img",
                  "content": { "msgtype": "m.image", "body": "start the broadcast",
                               "filename": "shot.jpg", "url": "mxc://hs/xyz" } }
            ] } } } }
        }));
        let msgs = extract_messages(sync, "@bot:hs", None, None, true);
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].body, "start the broadcast");
        let att = msgs[0].attachment.as_ref().unwrap();
        assert_eq!(att.filename, "shot.jpg");
    }

    #[test]
    fn sanitize_component_strips_and_bounds() {
        assert_eq!(sanitize_component("$abc/def:ghi"), "_abc_def_ghi");
        assert_eq!(sanitize_component("ok.name-1_2.png"), "ok.name-1_2.png");
        assert_eq!(sanitize_component(""), "file");
        assert_eq!(sanitize_component("/////"), "_____");
        assert!(sanitize_component(&"x".repeat(500)).len() <= 96);
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
            extract_messages(sync_from(json.clone()), "@bot:hs", None, None, false).len(),
            2
        );
        // Allowlist ⇒ only the listed sender.
        let allowed: HashSet<String> = ["@alice:hs".to_string()].into_iter().collect();
        let msgs = extract_messages(sync_from(json), "@bot:hs", Some(&allowed), None, false);
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
            extract_messages(sync_from(json.clone()), "@bot:hs", None, None, false).len(),
            2
        );
        // Room allowlist ⇒ only the listed room.
        let rooms: HashSet<String> = ["!ok:hs".to_string()].into_iter().collect();
        let msgs = extract_messages(
            sync_from(json.clone()),
            "@bot:hs",
            None,
            Some(&rooms),
            false,
        );
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].room, "!ok:hs");
        // Conjunction: an allowed sender in a disallowed room is still dropped.
        let users: HashSet<String> = ["@alice:hs".to_string()].into_iter().collect();
        let only_other: HashSet<String> = ["!nope:hs".to_string()].into_iter().collect();
        // alice is allowed, but the only allowed room here is !nope:hs, so her !ok:hs message and
        // the !nope:hs one both pass the *sender* check — but room-wise only !nope:hs survives.
        let msgs = extract_messages(
            sync_from(json),
            "@bot:hs",
            Some(&users),
            Some(&only_other),
            false,
        );
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

    fn sorted_tools(gw: &MatrixGateway, room: &str, sender: &str) -> Vec<String> {
        let mut t = gw.tools_for(room, sender).unwrap();
        t.sort();
        t
    }

    #[test]
    fn tool_policy_listed_member_intersects_room_set() {
        let gw = MatrixGateway::new("https://hs", "@bot:hs", "pw")
            .with_room_tools([(
                "!ops:hs".to_string(),
                vec!["shell".to_string(), "read_file".to_string()],
            )])
            .with_user_tools([(
                "@admin:hs".to_string(),
                vec!["read_file".to_string(), "write_file".to_string()],
            )]);

        // Both constrained ⇒ intersection (only read_file is in both).
        assert_eq!(
            sorted_tools(&gw, "!ops:hs", "@admin:hs"),
            vec!["read_file".to_string()]
        );
        // Listed member, room absent from the room map ⇒ the member's own set.
        assert_eq!(
            sorted_tools(&gw, "!other:hs", "@admin:hs"),
            vec!["read_file".to_string(), "write_file".to_string()]
        );
    }

    #[test]
    fn tool_policy_unlisted_member_with_nonempty_user_map_gets_no_tools() {
        let gw = MatrixGateway::new("https://hs", "@bot:hs", "pw")
            .with_room_tools([(
                "!ops:hs".to_string(),
                vec!["shell".to_string(), "read_file".to_string()],
            )])
            .with_user_tools([(
                "@admin:hs".to_string(),
                vec!["read_file".to_string(), "write_file".to_string()],
            )]);

        // The room would grant shell + read_file; the sender is not on the member map.
        assert_eq!(gw.tools_for("!ops:hs", "@guest:hs"), Some(Vec::new()));
    }

    #[test]
    fn tool_policy_empty_user_map_keeps_room_set() {
        let gw = MatrixGateway::new("https://hs", "@bot:hs", "pw").with_room_tools([(
            "!ops:hs".to_string(),
            vec!["shell".to_string(), "read_file".to_string()],
        )]);

        assert_eq!(
            sorted_tools(&gw, "!ops:hs", "@guest:hs"),
            vec!["read_file".to_string(), "shell".to_string()]
        );
        // No room entry and no member map ⇒ unconstrained.
        assert!(gw.tools_for("!other:hs", "@guest:hs").is_none());
    }

    #[test]
    fn tool_policy_unlisted_member_in_unmapped_room_gets_no_tools() {
        let gw = MatrixGateway::new("https://hs", "@bot:hs", "pw")
            .with_user_tools([("@admin:hs".to_string(), vec!["read_file".to_string()])]);

        // No room policy, but the member map is non-empty and this sender is absent.
        // `None` would advertise the full catalogue; the closed result is an empty allowlist.
        assert_eq!(gw.tools_for("!other:hs", "@guest:hs"), Some(Vec::new()));
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
        let msgs = extract_messages(sync, "@lav:hs", None, None, false);
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
    fn tool_notice_names_the_call_and_its_target() {
        assert_eq!(
            tool_notice("read_file", r#"{"path":"src/lib.rs"}"#),
            "🔧 `read_file` · src/lib.rs"
        );
        // A provider-run tool has no client arguments; the name alone is the signal.
        assert_eq!(tool_notice("web_search", ""), "🔧 `web_search`");
        assert_eq!(
            tool_notice("web_search", r#"{"query":"grok 4.7 release"}"#),
            "🔧 `web_search` · grok 4.7 release"
        );
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
        assert!(extract_messages(sync, "@bot:hs", None, None, false).is_empty());
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
