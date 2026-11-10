//! Opt-in end-to-end encryption for the Matrix gateway (`e2ee` feature).
//!
//! Wraps `matrix-sdk-crypto`'s [`OlmMachine`] — the crypto-only state machine, no full
//! `matrix-sdk` — and drives it over the gateway's hand-rolled REST transport. The flow follows
//! the `matrix-sdk-crypto` custom-client tutorial:
//!
//! 1. **Init** ([`Crypto::new`]) builds an [`OlmMachine`] for the bot's user/device and runs the
//!    initial outgoing requests (device-key + one-time-key upload). The machine is backed by a
//!    durable SQLite crypto store when a store path is given (so the crypto identity — device keys,
//!    Olm/Megolm sessions, tracked devices — survives restarts), or in-memory otherwise.
//! 2. On every `/sync` ([`Crypto::receive_sync`]) the to-device events, device-list changes and
//!    one-time-key counts are pushed into the machine, then the requests it produces are sent.
//! 3. Inbound `m.room.encrypted` timeline events are decrypted ([`Crypto::decrypt_messages`]).
//! 4. Outbound replies are encrypted ([`Crypto::encrypt_and_send`]): establish Olm sessions,
//!    share the Megolm room key with the room's members, encrypt, and send as `m.room.encrypted`.
//!
//! This module is compiled only with the `e2ee` feature; the agent core and the rest of the
//! gateway are unaware of it.

use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::fmt::{self, Display};
use std::ops::Deref;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use aes::cipher::{KeyIvInit, StreamCipher};
use aes::Aes256;
use base64::engine::general_purpose::{STANDARD_NO_PAD, URL_SAFE_NO_PAD};
use base64::Engine;
use ctr::Ctr64BE;
use matrix_sdk_crypto::{
    types::events::room::encrypted::EncryptedEvent, types::requests::AnyOutgoingRequest,
    DecryptionSettings, EncryptionSettings, EncryptionSyncChanges, OlmMachine, TrustRequirement,
};
use matrix_sdk_sqlite::SqliteCryptoStore;
use ruma::{
    api::{
        auth_scheme::{AccessToken, SendAccessToken},
        client::{
            keys::{get_keys, upload_signing_keys},
            sync::sync_events::DeviceLists,
            to_device::send_event_to_device,
        },
        path_builder::VersionHistory,
        IncomingResponse as RumaIncomingResponse, MatrixVersion,
        OutgoingRequest as RumaOutgoingRequest, SupportedVersions,
    },
    events::{AnyMessageLikeEventContent, AnyToDeviceEvent},
    serde::Raw,
    OneTimeKeyAlgorithm, OwnedDeviceId, OwnedUserId, RoomId, UInt, UserId,
};
use serde_json::Value;
use sha2::{Digest, Sha256};
use tokio::sync::{MappedMutexGuard, Mutex, MutexGuard};
use tracing::{error, info, warn};

use crate::pg_crypto::{migrate_sqlite, Reconcile, StoreError};

/// An end-to-end-encryption error. We collapse the many `matrix-sdk-crypto`/`ruma` error types to
/// a string at the boundary — the gateway only logs them, and this avoids leaking those types
/// (and the `thiserror` dependency) into this crate.
#[derive(Debug)]
pub struct E2eeError(pub String);

impl Display for E2eeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "e2ee: {}", self.0)
    }
}

impl std::error::Error for E2eeError {}

fn estr(e: impl Display) -> E2eeError {
    E2eeError(e.to_string())
}

type Aes256Ctr64Be = Ctr64BE<Aes256>;

/// AES-256-CTR ciphertext plus the Matrix EncryptedFile v2 object (without `url`;
/// the caller fills `url` after uploading the ciphertext).
pub(crate) struct EncryptedAttachment {
    pub ciphertext: Vec<u8>,
    file: Value,
}

impl EncryptedAttachment {
    /// Attach the mxc of the uploaded ciphertext.
    pub(crate) fn with_url(mut self, mxc: &str) -> Value {
        self.file["url"] = serde_json::json!(mxc);
        self.file
    }
}

/// Encrypt attachment bytes per the Matrix spec: AES-256-CTR, 16-byte IV (first 8 random,
/// last 8 zero), SHA-256 of the ciphertext, JWK key as unpadded url-safe base64.
pub(crate) fn encrypt_attachment(plaintext: &[u8]) -> Result<EncryptedAttachment, E2eeError> {
    let mut key = [0u8; 32];
    getrandom::getrandom(&mut key).map_err(estr)?;
    let mut iv = [0u8; 16];
    getrandom::getrandom(&mut iv[..8]).map_err(estr)?;

    let mut ciphertext = plaintext.to_vec();
    let mut cipher = Aes256Ctr64Be::new((&key).into(), (&iv).into());
    cipher.apply_keystream(&mut ciphertext);

    let hash = Sha256::digest(&ciphertext);
    let file = serde_json::json!({
        "v": "v2",
        "key": {
            "kty": "oct",
            "key_ops": ["encrypt", "decrypt"],
            "alg": "A256CTR",
            "k": URL_SAFE_NO_PAD.encode(key),
            "ext": true
        },
        "iv": STANDARD_NO_PAD.encode(iv),
        "hashes": { "sha256": STANDARD_NO_PAD.encode(hash) }
    });
    Ok(EncryptedAttachment { ciphertext, file })
}

/// The crypto layer bound to a logged-in bot session.
pub struct Crypto {
    machine: Mutex<Option<OlmMachine>>,
    /// Set when a stale fence or an unknown commit has dropped the machine.
    poisoned: AtomicBool,
    /// Set when this process holds the Aurora fence. SQLite leaves this empty.
    pg: Option<Arc<crate::pg_crypto::PostgresCryptoStore>>,
    user: OwnedUserId,
    device: OwnedDeviceId,
    http: reqwest::Client,
    /// When set, forced onto every request after ruma's own headers so a lattice `Host`
    /// is not replaced by the dial URL's authority.
    http_host: Option<String>,
    homeserver: String,
    token: String,
    /// Matrix versions we advertise when serialising ruma requests (selects the `v3` endpoints).
    versions: SupportedVersions,
}

impl Crypto {
    /// Build the [`OlmMachine`] for `user_id`/`device_id` and publish the bot's keys. When
    /// `store_path` is given the machine is backed by a durable SQLite crypto store opened there
    /// (created if absent, reused if present), optionally encrypted at rest with `passphrase`;
    /// otherwise it is in-memory.
    #[allow(clippy::too_many_arguments)]
    pub async fn new(
        homeserver: String,
        token: String,
        user_id: &str,
        device_id: &str,
        store_path: Option<&Path>,
        passphrase: Option<&str>,
        http: reqwest::Client,
        http_host: Option<String>,
    ) -> Result<Self, E2eeError> {
        let user = UserId::parse(user_id).map_err(estr)?;
        let device: OwnedDeviceId = device_id.into();
        let machine = match store_path {
            Some(path) => {
                let store = SqliteCryptoStore::open(path, passphrase)
                    .await
                    .map_err(estr)?;
                info!(store = %path.display(), "e2ee: using persistent crypto store");
                OlmMachine::with_store(&user, &device, store, None)
                    .await
                    .map_err(estr)?
            }
            None => OlmMachine::new(&user, &device).await,
        };
        Self::finish(
            machine, None, user, device, homeserver, token, http, http_host,
        )
        .await
    }

    /// Open the machine on a fence the CLI already acquired. Does not run the
    /// incrementing acquire. A null marker copies the SQLite directory once, or
    /// refuses to call `with_store` when there is nothing to copy.
    #[allow(clippy::too_many_arguments)]
    pub async fn with_leadership(
        homeserver: String,
        token: String,
        user_id: &str,
        device_id: &str,
        store: Arc<crate::pg_crypto::PostgresCryptoStore>,
        sqlite_source: Option<&Path>,
        passphrase: Option<&str>,
        http: reqwest::Client,
        http_host: Option<String>,
    ) -> Result<Self, E2eeError> {
        let user = UserId::parse(user_id).map_err(estr)?;
        let device: OwnedDeviceId = device_id.into();
        if store.migration_marker().await.map_err(estr)?.is_none() {
            if let Some(path) = sqlite_source {
                if path.join("matrix-sdk-crypto.sqlite3").is_file() {
                    migrate_sqlite(&store, path, passphrase)
                        .await
                        .map_err(estr)?;
                }
            }
            if store.migration_marker().await.map_err(estr)?.is_none() {
                return Err(estr("e2ee: aurora crypto store has no migration marker"));
            }
        }
        store.ready_for_machine().await.map_err(estr)?;
        store.set_boot_load(true);
        let machine = OlmMachine::with_store(&user, &device, Arc::clone(&store), None)
            .await
            .map_err(estr)?;
        store.set_boot_load(false);
        let _ = store.renew_lease().await;
        info!(epoch = store.epoch(), "e2ee: using postgres crypto store");
        Self::finish(
            machine,
            Some(store),
            user,
            device,
            homeserver,
            token,
            http,
            http_host,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    async fn finish(
        machine: OlmMachine,
        pg: Option<Arc<crate::pg_crypto::PostgresCryptoStore>>,
        user: OwnedUserId,
        device: OwnedDeviceId,
        homeserver: String,
        token: String,
        http: reqwest::Client,
        http_host: Option<String>,
    ) -> Result<Self, E2eeError> {
        let versions = SupportedVersions {
            versions: BTreeSet::from([MatrixVersion::V1_1]),
            features: BTreeSet::new(),
        };
        let crypto = Self {
            machine: Mutex::new(Some(machine)),
            poisoned: AtomicBool::new(false),
            pg,
            user,
            device,
            http,
            http_host,
            homeserver,
            token,
            versions,
        };
        crypto.process_outgoing().await?;
        crypto.bootstrap_cross_signing().await;
        Ok(crypto)
    }

    /// This process is using the fenced store.
    pub fn uses_postgres(&self) -> bool {
        self.pg.is_some()
    }

    /// The machine was dropped after a stale fence or an unknown commit.
    pub fn is_poisoned(&self) -> bool {
        self.poisoned.load(Ordering::SeqCst)
    }

    /// Publish the bot's **cross-signing identity** the first time it's set up, so other users'
    /// clients see the bot's device as part of a signed identity rather than an unverified
    /// standalone device. Done once: we bootstrap only when the private keys aren't already in the
    /// store, because re-uploading an existing identity requires User-Interactive Auth (the
    /// homeserver waives UIA only for the *first* cross-signing upload, per MSC3967), which a
    /// token-authenticated bot can't complete. Best-effort — on any failure we log and carry on
    /// (encryption still works; only cross-signing is skipped, e.g. on a server that demands UIA).
    async fn bootstrap_cross_signing(&self) {
        if let Err(e) = self.try_bootstrap_cross_signing().await {
            warn!(error = %e, "e2ee: cross-signing bootstrap skipped");
        }
    }

    async fn try_bootstrap_cross_signing(&self) -> Result<(), E2eeError> {
        let complete = {
            let machine = self.lock_machine().await?;
            machine.cross_signing_status().await.is_complete()
        };
        if complete {
            return Ok(()); // already have an identity (persistent store / earlier run)
        }
        let reqs = {
            let machine = self.lock_machine().await?;
            machine.bootstrap_cross_signing(false).await.map_err(estr)?
        };
        // 1. Device-key upload, if the machine asks for one (its response is fed back). Usually
        //    `None` here since `process_outgoing` already uploaded the device keys.
        if let Some(req) = reqs.upload_keys_req {
            let id = req.request_id().to_owned();
            if let AnyOutgoingRequest::KeysUpload(r) = req.request() {
                let resp = self.send_ruma(r.clone()).await?;
                let marked = {
                    let machine = self.lock_machine().await?;
                    machine.mark_request_as_sent(&id, &resp).await
                };
                self.map_store(marked).await?;
            }
        }
        // 2. Upload the public cross-signing key triplet (no UIA on this first upload).
        let triplet = reqs.upload_signing_keys_req;
        let mut signing = upload_signing_keys::v3::Request::new();
        signing.master_key = triplet.master_key.as_ref().map(raw_cast).transpose()?;
        signing.self_signing_key = triplet
            .self_signing_key
            .as_ref()
            .map(raw_cast)
            .transpose()?;
        signing.user_signing_key = triplet
            .user_signing_key
            .as_ref()
            .map(raw_cast)
            .transpose()?;
        self.send_ruma(signing).await?;
        // 3. Upload the signatures over those keys (already a ruma request).
        self.send_ruma(reqs.upload_signatures_req).await?;
        info!("e2ee: cross-signing identity published");
        Ok(())
    }

    /// Feed a `/sync` response's encryption-relevant parts into the machine, then flush the
    /// requests it produces. `sync` is the raw sync JSON.
    ///
    /// `Ok(true)` means the paired sync transaction is known committed and `since` may advance.
    /// `Ok(false)` means the pair aborted or a lost reply must not be re-fed, so `since` stays.
    pub async fn receive_sync(&self, sync: &Value) -> Result<bool, E2eeError> {
        let from = |key: &str| -> Option<&Value> { sync.get(key) };

        let to_device_events: Vec<Raw<AnyToDeviceEvent>> = from("to_device")
            .and_then(|t| t.get("events"))
            .and_then(|e| serde_json::from_value(e.clone()).ok())
            .unwrap_or_default();
        let changed_devices: DeviceLists = from("device_lists")
            .and_then(|d| serde_json::from_value(d.clone()).ok())
            .unwrap_or_default();
        let one_time_keys_counts: BTreeMap<OneTimeKeyAlgorithm, UInt> =
            from("device_one_time_keys_count")
                .and_then(|c| serde_json::from_value(c.clone()).ok())
                .unwrap_or_default();
        let unused_fallback_keys: Option<Vec<OneTimeKeyAlgorithm>> =
            from("device_unused_fallback_key_types")
                .and_then(|f| serde_json::from_value(f.clone()).ok());
        let next_batch_token = from("next_batch")
            .and_then(|v| v.as_str())
            .map(String::from);

        let changes = EncryptionSyncChanges {
            to_device_events,
            changed_devices: &changed_devices,
            one_time_keys_counts: &one_time_keys_counts,
            unused_fallback_keys: unused_fallback_keys.as_deref(),
            next_batch_token,
        };
        let settings = DecryptionSettings {
            sender_device_trust_requirement: TrustRequirement::Untrusted,
        };
        if self.pg.is_some() {
            return self.receive_sync_fenced(sync).await;
        }
        {
            let machine = self.lock_machine().await?;
            machine
                .receive_sync_changes(changes, &settings)
                .await
                .map_err(estr)?;
        }
        self.process_outgoing().await?;
        // SQLite has no fence. The gateway still advances `since` on this `Ok`,
        // including when a later caller treats an `Err` as "advance anyway".
        Ok(true)
    }

    /// Decrypt every inbound `m.room.encrypted` text message in a sync response, skipping our own,
    /// any sender not in `allowed`, and any room not in `allowed_rooms` (when those allowlists are
    /// configured — the `m.room.encrypted` event's `sender` and the room id are cleartext, so both
    /// are enforced *before* decryption, identically to the plaintext path). The mention/reply
    /// signals live inside the encrypted payload, so they're read from the *decrypted* content —
    /// the cleartext `event_id` (needed to react) comes from the wrapper. Returns the same
    /// [`IncomingMessage`](crate::IncomingMessage) shape as the plaintext path.
    pub async fn decrypt_messages(
        &self,
        sync: &Value,
        self_user: String,
        allowed: Option<HashSet<String>>,
        allowed_rooms: Option<HashSet<String>>,
        media: bool,
    ) -> Vec<crate::IncomingMessage> {
        let mut out = Vec::new();
        let settings = DecryptionSettings {
            sender_device_trust_requirement: TrustRequirement::Untrusted,
        };
        let Some(join) = sync
            .get("rooms")
            .and_then(|r| r.get("join"))
            .and_then(|j| j.as_object())
        else {
            return out;
        };
        for (room_id, room) in join {
            if !crate::room_allowed(allowed_rooms.as_ref(), room_id) {
                continue;
            }
            let Some(events) = room
                .get("timeline")
                .and_then(|t| t.get("events"))
                .and_then(|e| e.as_array())
            else {
                continue;
            };
            for ev in events {
                if ev.get("type").and_then(|t| t.as_str()) != Some("m.room.encrypted") {
                    continue;
                }
                let sender = ev.get("sender").and_then(|s| s.as_str());
                if sender == Some(self_user.as_str()) {
                    continue;
                }
                if !crate::sender_allowed(allowed.as_ref(), sender.unwrap_or_default()) {
                    continue;
                }
                let sender = sender.unwrap_or_default().to_string();
                let event_id = ev
                    .get("event_id")
                    .and_then(|e| e.as_str())
                    .unwrap_or_default()
                    .to_string();
                let raw: Raw<EncryptedEvent> = match serde_json::from_value(ev.clone()) {
                    Ok(r) => r,
                    Err(_) => continue,
                };
                let parsed_room = match RoomId::parse(room_id) {
                    Ok(r) => r,
                    Err(_) => continue,
                };
                let decrypted = {
                    let machine = match self.lock_machine().await {
                        Ok(machine) => machine,
                        Err(_) => return out,
                    };
                    machine
                        .decrypt_room_event(&raw, &parsed_room, &settings)
                        .await
                };
                match decrypted {
                    Ok(decrypted) => {
                        if let Some(msg) = to_incoming(
                            &decrypted.event,
                            room_id.clone(),
                            sender.clone(),
                            event_id.clone(),
                            &self_user,
                            media,
                        ) {
                            out.push(msg);
                        }
                    }
                    Err(e) => error!(%room_id, error = %e, "e2ee: decrypt failed"),
                }
            }
        }
        out
    }

    /// Encrypt `body` as an `m.text` message and send it to `room_id` as `m.room.encrypted`;
    /// returns the event id the homeserver assigned (so the gateway can track its own messages
    /// for reply-detection). Takes its arguments by value so the future borrows nothing
    /// lifetime-generic (keeps the gateway's serve future `Send`).
    pub async fn encrypt_and_send(
        &self,
        room_id: String,
        body: String,
    ) -> Result<String, E2eeError> {
        self.encrypt_and_send_content(
            room_id,
            serde_json::json!({ "msgtype": "m.text", "body": body }),
        )
        .await
    }

    /// Encrypt arbitrary `m.room.message` content (text, `m.image` with a `file` object, …)
    /// and send it as `m.room.encrypted`. Same session/key-sharing path as
    /// [`Self::encrypt_and_send`].
    pub async fn encrypt_and_send_content(
        &self,
        room_id: String,
        content: Value,
    ) -> Result<String, E2eeError> {
        let room = RoomId::parse(&room_id).map_err(estr)?;
        let users = self.joined_members(&room_id).await?;
        // Pass a fresh `&UserId` iterator per call (the `Deref::deref` fn item is lifetime-generic,
        // unlike a closure) so the borrow of `users` doesn't span every await — which would make
        // this future's `Send` lifetime-dependent and break the gateway's serve future.

        // Track the room's members, then **flush the resulting /keys/query** so we actually hold
        // their device lists before establishing sessions and sharing the key. `update_tracked_users`
        // only marks them dirty; without running the outgoing requests it triggers, the first reply
        // to a room is encrypted to zero devices and the recipient can't decrypt it.
        let tracked = {
            let machine = self.lock_machine().await?;
            machine
                .update_tracked_users(users.iter().map(Deref::deref))
                .await
        };
        self.map_store(tracked).await?;
        self.process_outgoing().await?;
        let missing = {
            let machine = self.lock_machine().await?;
            machine
                .get_missing_sessions(users.iter().map(Deref::deref))
                .await
        };
        if let Some((id, req)) = self.map_store(missing).await? {
            let resp = self.send_ruma(req).await?;
            let marked = {
                let machine = self.lock_machine().await?;
                machine.mark_request_as_sent(&id, &resp).await
            };
            self.map_store(marked).await?;
        }
        let shared = {
            let machine = self.lock_machine().await?;
            machine
                .share_room_key(
                    &room,
                    users.iter().map(Deref::deref),
                    EncryptionSettings::default(),
                )
                .await
        };
        let key_requests = self.map_store(shared).await?;
        for req in key_requests {
            let resp = self.send_to_device(&req).await?;
            let marked = {
                let machine = self.lock_machine().await?;
                machine.mark_request_as_sent(&req.txn_id, &resp).await
            };
            self.map_store(marked).await?;
        }

        let content: Raw<AnyMessageLikeEventContent> =
            Raw::new(&content).map_err(estr)?.cast_unchecked();
        let encrypted_result = {
            let machine = self.lock_machine().await?;
            machine
                .encrypt_room_event_raw(&room, "m.room.message", &content)
                .await
        };
        let encrypted = self.map_store(encrypted_result).await?;
        self.send_encrypted_event(&room_id, &encrypted.content)
            .await
    }

    /// Drain and dispatch the machine's outgoing requests until none remain.
    async fn process_outgoing(&self) -> Result<(), E2eeError> {
        let outgoing = {
            let machine = self.lock_machine().await?;
            machine.outgoing_requests().await
        };
        let requests = self.map_store(outgoing).await?;
        for request in requests {
            let id = request.request_id().to_owned();
            match request.request() {
                AnyOutgoingRequest::KeysUpload(r) => {
                    let resp = self.send_ruma(r.clone()).await?;
                    let marked = {
                        let machine = self.lock_machine().await?;
                        machine.mark_request_as_sent(&id, &resp).await
                    };
                    self.map_store(marked).await?;
                }
                AnyOutgoingRequest::KeysQuery(r) => {
                    let mut req = get_keys::v3::Request::new();
                    req.device_keys = r.device_keys.clone();
                    req.timeout = r.timeout;
                    let resp = self.send_ruma(req).await?;
                    let marked = {
                        let machine = self.lock_machine().await?;
                        machine.mark_request_as_sent(&id, &resp).await
                    };
                    self.map_store(marked).await?;
                }
                AnyOutgoingRequest::KeysClaim(r) => {
                    let resp = self.send_ruma(r.clone()).await?;
                    let marked = {
                        let machine = self.lock_machine().await?;
                        machine.mark_request_as_sent(&id, &resp).await
                    };
                    self.map_store(marked).await?;
                }
                AnyOutgoingRequest::ToDeviceRequest(r) => {
                    let resp = self.send_to_device(r).await?;
                    let marked = {
                        let machine = self.lock_machine().await?;
                        machine.mark_request_as_sent(&id, &resp).await
                    };
                    self.map_store(marked).await?;
                }
                AnyOutgoingRequest::SignatureUpload(r) => {
                    let resp = self.send_ruma(r.clone()).await?;
                    let marked = {
                        let machine = self.lock_machine().await?;
                        machine.mark_request_as_sent(&id, &resp).await
                    };
                    self.map_store(marked).await?;
                }
                AnyOutgoingRequest::RoomMessage(_) => {
                    // Only emitted for in-room interactive verification, which this bot neither
                    // initiates nor supports — so there is nothing to send. (Left unmarked; the
                    // machine simply re-lists it, but a non-verifying bot never produces one.)
                    warn!("e2ee: ignoring in-room verification message (unsupported)");
                }
            }
        }
        Ok(())
    }

    /// Send a crypto to-device request (room-key sharing, verification, …).
    async fn send_to_device(
        &self,
        r: &matrix_sdk_crypto::types::requests::ToDeviceRequest,
    ) -> Result<send_event_to_device::v3::Response, E2eeError> {
        let req = send_event_to_device::v3::Request::new_raw(
            r.event_type.clone(),
            r.txn_id.clone(),
            r.messages.clone(),
        );
        self.send_ruma(req).await
    }

    async fn lock_machine(&self) -> Result<MappedMutexGuard<'_, OlmMachine>, E2eeError> {
        if self.poisoned.load(Ordering::SeqCst) {
            return Err(E2eeError("olm machine poisoned".into()));
        }
        let guard = self.machine.lock().await;
        MutexGuard::try_map(guard, |slot| slot.as_mut())
            .map_err(|_| E2eeError("olm machine poisoned".into()))
    }

    async fn map_store<T, E: Display>(&self, result: Result<T, E>) -> Result<T, E2eeError> {
        match result {
            Ok(value) => Ok(value),
            Err(e) => {
                let msg = e.to_string();
                if msg.contains("commit outcome unknown") {
                    if let Some(store) = &self.pg {
                        let _ = store.reconcile_inflight().await;
                    }
                    self.poison_machine().await;
                } else if msg.contains("stale fence") {
                    self.poison_machine().await;
                }
                Err(estr(msg))
            }
        }
    }

    async fn poison_machine(&self) {
        self.poisoned.store(true, Ordering::SeqCst);
        *self.machine.lock().await = None;
        if self.pg.is_some() {
            let _ = std::fs::remove_file("/tmp/e2ee-ready");
        }
    }

    async fn reload_machine(&self) -> Result<(), E2eeError> {
        let store = self
            .pg
            .clone()
            .ok_or_else(|| E2eeError("no postgres crypto store".into()))?;
        *self.machine.lock().await = None;
        self.poisoned.store(false, Ordering::SeqCst);
        store.set_boot_load(true);
        let machine = OlmMachine::with_store(&self.user, &self.device, Arc::clone(&store), None)
            .await
            .map_err(estr)?;
        store.set_boot_load(false);
        let _ = store.renew_lease().await;
        *self.machine.lock().await = Some(machine);
        Ok(())
    }

    async fn receive_sync_fenced(&self, sync: &Value) -> Result<bool, E2eeError> {
        let first = self.drive_pair(sync).await?;
        match first {
            Reconcile::Committed => {
                if self.is_poisoned() {
                    self.reload_machine().await?;
                }
                if let Err(e) = self.process_outgoing().await {
                    warn!(error = %e, "e2ee: process_outgoing failed after committed pair");
                }
                Ok(true)
            }
            Reconcile::Aborted => {
                self.reload_machine().await?;
                let second = self.drive_pair(sync).await?;
                if second == Reconcile::Committed {
                    if self.is_poisoned() {
                        self.reload_machine().await?;
                    }
                    let _ = self.process_outgoing().await;
                    Ok(true)
                } else {
                    self.poison_machine().await;
                    Ok(false)
                }
            }
            Reconcile::ForeignCommit | Reconcile::DoNotRefeed | Reconcile::StillUnknown => {
                self.poison_machine().await;
                Ok(false)
            }
        }
    }

    async fn drive_pair(&self, sync: &Value) -> Result<Reconcile, E2eeError> {
        let store = self
            .pg
            .as_ref()
            .ok_or_else(|| E2eeError("no postgres crypto store".into()))?;
        let settings = DecryptionSettings {
            sender_device_trust_requirement: TrustRequirement::Untrusted,
        };
        store.begin_pair();
        let sdk = {
            let parts = sync_parts(sync);
            let changes = EncryptionSyncChanges {
                to_device_events: parts.to_device_events,
                changed_devices: &parts.changed_devices,
                one_time_keys_counts: &parts.one_time_keys_counts,
                unused_fallback_keys: parts.unused_fallback_keys.as_deref(),
                next_batch_token: parts.next_batch_token,
            };
            let machine = self.lock_machine().await?;
            machine.receive_sync_changes(changes, &settings).await
        };
        let flush = store.end_pair().await;
        let sdk_msg = sdk
            .as_ref()
            .err()
            .map(|e| e.to_string())
            .unwrap_or_default();
        let unknown = sdk_msg.contains("commit outcome unknown")
            || matches!(flush, Err(StoreError::CommitUnknown));
        let stale = sdk_msg.contains("stale fence") || matches!(flush, Err(StoreError::StaleFence));
        if unknown {
            let outcome = store
                .reconcile_inflight()
                .await
                .unwrap_or(Reconcile::StillUnknown);
            self.poison_machine().await;
            return Ok(outcome);
        }
        if stale || sdk_msg.contains("account write failed") {
            self.poison_machine().await;
            return Ok(Reconcile::Aborted);
        }
        match (sdk, flush) {
            (Ok(_), Ok(())) => Ok(Reconcile::Committed),
            (Err(e), _) => {
                self.poison_machine().await;
                Err(estr(e))
            }
            (Ok(_), Err(e)) => {
                self.poison_machine().await;
                Err(estr(e))
            }
        }
    }

    fn stamp(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match &self.http_host {
            Some(host) => req.header(reqwest::header::HOST, host.as_str()),
            None => req,
        }
    }

    /// Serialise a ruma request to HTTP, send it over the gateway's `reqwest` client, and parse
    /// the typed response back — bridging `matrix-sdk-crypto`'s ruma types to our transport.
    async fn send_ruma<R>(&self, req: R) -> Result<R::IncomingResponse, E2eeError>
    where
        R: RumaOutgoingRequest<Authentication = AccessToken, PathBuilder = VersionHistory>,
    {
        let http_req = req
            .try_into_http_request::<Vec<u8>>(
                &self.homeserver,
                SendAccessToken::IfRequired(&self.token),
                Cow::Borrowed(&self.versions),
            )
            .map_err(estr)?;
        let (parts, body) = http_req.into_parts();
        let resp = self
            .stamp(
                self.http
                    .request(parts.method, parts.uri.to_string())
                    .headers(parts.headers)
                    .body(body),
            )
            .send()
            .await
            .map_err(estr)?;
        let status = resp.status();
        let bytes = resp.bytes().await.map_err(estr)?;
        let http_resp = http::Response::builder()
            .status(status)
            .body(bytes.to_vec())
            .map_err(estr)?;
        R::IncomingResponse::try_from_http_response(http_resp).map_err(estr)
    }

    /// `PUT` an already-encrypted payload as an `m.room.encrypted` timeline event; returns the
    /// homeserver-assigned event id.
    async fn send_encrypted_event<T>(
        &self,
        room_id: &str,
        content: &Raw<T>,
    ) -> Result<String, E2eeError> {
        let txn = ruma::TransactionId::new();
        let url = format!(
            "{}/_matrix/client/v3/rooms/{}/send/m.room.encrypted/{}",
            self.homeserver,
            crate::urlencode(room_id),
            txn
        );
        let resp = self
            .stamp(self.http.put(url).bearer_auth(&self.token).json(content))
            .send()
            .await
            .map_err(estr)?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(E2eeError(format!("send m.room.encrypted {status}: {msg}")));
        }
        let v: Value = resp.json().await.map_err(estr)?;
        Ok(v.get("event_id")
            .and_then(|e| e.as_str())
            .unwrap_or_default()
            .to_string())
    }

    /// Fetch the joined members of a room (recipients for room-key sharing).
    async fn joined_members(&self, room_id: &str) -> Result<Vec<OwnedUserId>, E2eeError> {
        let url = format!(
            "{}/_matrix/client/v3/rooms/{}/joined_members",
            self.homeserver,
            crate::urlencode(room_id)
        );
        let resp = self
            .stamp(self.http.get(url).bearer_auth(&self.token))
            .send()
            .await
            .map_err(estr)?;
        let v: Value = resp.json().await.map_err(estr)?;
        let mut users = Vec::new();
        if let Some(joined) = v.get("joined").and_then(|j| j.as_object()) {
            for key in joined.keys() {
                if let Ok(u) = UserId::parse(key) {
                    users.push(u);
                }
            }
        }
        Ok(users)
    }
}

struct SyncParts {
    to_device_events: Vec<Raw<AnyToDeviceEvent>>,
    changed_devices: DeviceLists,
    one_time_keys_counts: BTreeMap<OneTimeKeyAlgorithm, UInt>,
    unused_fallback_keys: Option<Vec<OneTimeKeyAlgorithm>>,
    next_batch_token: Option<String>,
}

fn sync_parts(sync: &Value) -> SyncParts {
    let from = |key: &str| -> Option<&Value> { sync.get(key) };
    SyncParts {
        to_device_events: from("to_device")
            .and_then(|t| t.get("events"))
            .and_then(|e| serde_json::from_value(e.clone()).ok())
            .unwrap_or_default(),
        changed_devices: from("device_lists")
            .and_then(|d| serde_json::from_value(d.clone()).ok())
            .unwrap_or_default(),
        one_time_keys_counts: from("device_one_time_keys_count")
            .and_then(|c| serde_json::from_value(c.clone()).ok())
            .unwrap_or_default(),
        unused_fallback_keys: from("device_unused_fallback_key_types")
            .and_then(|f| serde_json::from_value(f.clone()).ok()),
        next_batch_token: from("next_batch")
            .and_then(|v| v.as_str())
            .map(String::from),
    }
}

/// Re-encode a `matrix-sdk-crypto` value as a ruma [`Raw<T>`] by serialising and reparsing — both
/// sides emit the same spec JSON, so this bridges the crate's `CrossSigningKey` into ruma's request
/// type without depending on a direct `From` impl.
fn raw_cast<T>(v: &impl serde::Serialize) -> Result<Raw<T>, E2eeError> {
    Ok(Raw::from_json(
        serde_json::value::to_raw_value(v).map_err(estr)?,
    ))
}

/// Build an [`IncomingMessage`](crate::IncomingMessage) from a decrypted timeline event, when it's
/// an answerable message. The mention/reply signals live in the (now-cleartext) content, so they're
/// read here via the same shared [`message_content`](crate::message_content) helper the plaintext
/// path uses — keeping detection identical. Returns `None` for events the bot won't answer. The
/// `event_id` is the cleartext wrapper's, passed in. (Encrypted media has no plaintext `url`, so
/// `message_content` yields no attachment for it even with `media` on — see its docs.)
fn to_incoming<T>(
    event: &Raw<T>,
    room: String,
    sender: String,
    event_id: String,
    self_user: &str,
    media: bool,
) -> Option<crate::IncomingMessage> {
    let v: Value = serde_json::from_str(event.json().get()).ok()?;
    let content: crate::EventContent = serde_json::from_value(v.get("content")?.clone()).ok()?;
    let (body, attachment) = crate::message_content(&content, media)?;
    Some(crate::IncomingMessage {
        room,
        sender,
        body,
        event_id,
        mentions_bot: crate::mentions_bot(&content, self_user),
        in_reply_to: crate::reply_target(&content),
        attachment,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raw(json: &str) -> Raw<Value> {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn to_incoming_extracts_text_with_mention_and_reply() {
        let ev = raw(r#"{"type":"m.room.message","content":{
                "msgtype":"m.text","body":"@lav:hs help",
                "m.mentions":{"user_ids":["@lav:hs"]},
                "m.relates_to":{"m.in_reply_to":{"event_id":"$prev"}}}}"#);
        let msg = to_incoming(
            &ev,
            "!r:hs".into(),
            "@alice:hs".into(),
            "$e1".into(),
            "@lav:hs",
            false,
        )
        .unwrap();
        assert_eq!(msg.body, "@lav:hs help");
        assert_eq!(msg.event_id, "$e1");
        assert!(msg.mentions_bot);
        assert_eq!(msg.in_reply_to.as_deref(), Some("$prev"));
    }

    #[test]
    fn to_incoming_skips_media_when_media_off() {
        let img = raw(r#"{"content":{"msgtype":"m.image","body":"p.png","url":"mxc://hs/abc"}}"#);
        assert!(to_incoming(
            &img,
            "!r:hs".into(),
            "@a:hs".into(),
            "$e".into(),
            "@lav:hs",
            false
        )
        .is_none());
    }

    #[test]
    fn to_incoming_captures_media_when_on() {
        let img = raw(r#"{"content":{"msgtype":"m.image","body":"p.png","url":"mxc://hs/abc"}}"#);
        let msg = to_incoming(
            &img,
            "!r:hs".into(),
            "@a:hs".into(),
            "$e".into(),
            "@lav:hs",
            true,
        )
        .unwrap();
        let att = msg.attachment.expect("attachment captured");
        assert_eq!(att.mxc, "mxc://hs/abc");
        assert_eq!(att.filename, "p.png");
    }

    #[test]
    fn encrypt_attachment_is_encrypted_file_v2_and_roundtrips() {
        let plain = b"jpeg-bytes";
        let enc = encrypt_attachment(plain).expect("encrypt");
        let ciphertext = enc.ciphertext.clone();
        let file = enc.with_url("mxc://hs/abc");
        assert_eq!(file["v"], "v2");
        assert_eq!(file["url"], "mxc://hs/abc");
        assert_eq!(file["key"]["alg"], "A256CTR");
        assert_eq!(file["key"]["kty"], "oct");
        assert_eq!(file["key"]["ext"], true);

        let key = URL_SAFE_NO_PAD
            .decode(file["key"]["k"].as_str().unwrap())
            .unwrap();
        let iv = STANDARD_NO_PAD
            .decode(file["iv"].as_str().unwrap())
            .unwrap();
        assert_eq!(key.len(), 32);
        assert_eq!(iv.len(), 16);
        assert!(iv[8..].iter().all(|&b| b == 0));

        let hash = STANDARD_NO_PAD
            .decode(file["hashes"]["sha256"].as_str().unwrap())
            .unwrap();
        assert_eq!(hash, Sha256::digest(&ciphertext).as_slice());

        let mut out = ciphertext;
        let key: [u8; 32] = key.try_into().unwrap();
        let iv: [u8; 16] = iv.try_into().unwrap();
        let mut cipher = Aes256Ctr64Be::new((&key).into(), (&iv).into());
        cipher.apply_keystream(&mut out);
        assert_eq!(out, plain);
    }
}
