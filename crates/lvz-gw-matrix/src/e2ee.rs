//! Opt-in end-to-end encryption for the Matrix gateway (`e2ee` feature).
//!
//! Wraps `matrix-sdk-crypto`'s [`OlmMachine`] — the crypto-only state machine, no full
//! `matrix-sdk` — and drives it over the gateway's hand-rolled REST transport. The flow follows
//! the `matrix-sdk-crypto` custom-client tutorial:
//!
//! 1. **Init** ([`Crypto::new`]) builds an in-memory [`OlmMachine`] for the bot's user/device and
//!    runs the initial outgoing requests (device-key + one-time-key upload).
//! 2. On every `/sync` ([`Crypto::receive_sync`]) the to-device events, device-list changes and
//!    one-time-key counts are pushed into the machine, then the requests it produces are sent.
//! 3. Inbound `m.room.encrypted` timeline events are decrypted ([`Crypto::decrypt_messages`]).
//! 4. Outbound replies are encrypted ([`Crypto::encrypt_and_send`]): establish Olm sessions,
//!    share the Megolm room key with the room's members, encrypt, and send as `m.room.encrypted`.
//!
//! This module is compiled only with the `e2ee` feature; the agent core and the rest of the
//! gateway are unaware of it.

use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::{self, Display};
use std::ops::Deref;

use matrix_sdk_crypto::{
    types::events::room::encrypted::EncryptedEvent, types::requests::AnyOutgoingRequest,
    DecryptionSettings, EncryptionSettings, EncryptionSyncChanges, OlmMachine, TrustRequirement,
};
use ruma::{
    api::{
        auth_scheme::{AccessToken, SendAccessToken},
        client::{keys::get_keys, sync::sync_events::DeviceLists, to_device::send_event_to_device},
        path_builder::VersionHistory,
        IncomingResponse as RumaIncomingResponse, MatrixVersion,
        OutgoingRequest as RumaOutgoingRequest, SupportedVersions,
    },
    events::{AnyMessageLikeEventContent, AnyToDeviceEvent},
    serde::Raw,
    OneTimeKeyAlgorithm, OwnedDeviceId, OwnedUserId, RoomId, UInt, UserId,
};
use serde_json::Value;

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

/// The crypto layer bound to a logged-in bot session.
pub struct Crypto {
    machine: OlmMachine,
    http: reqwest::Client,
    homeserver: String,
    token: String,
    /// Matrix versions we advertise when serialising ruma requests (selects the `v3` endpoints).
    versions: SupportedVersions,
}

impl Crypto {
    /// Build the [`OlmMachine`] for `user_id`/`device_id` and publish the bot's keys.
    pub async fn new(
        homeserver: String,
        token: String,
        user_id: &str,
        device_id: &str,
    ) -> Result<Self, E2eeError> {
        let user = UserId::parse(user_id).map_err(estr)?;
        let device: OwnedDeviceId = device_id.into();
        let machine = OlmMachine::new(&user, &device).await;
        let versions = SupportedVersions {
            versions: BTreeSet::from([MatrixVersion::V1_1]),
            features: BTreeSet::new(),
        };
        let crypto = Self {
            machine,
            http: reqwest::Client::new(),
            homeserver,
            token,
            versions,
        };
        // Initial device-key + one-time-key upload.
        crypto.process_outgoing().await?;
        Ok(crypto)
    }

    /// Feed a `/sync` response's encryption-relevant parts into the machine, then flush the
    /// requests it produces. `sync` is the raw sync JSON.
    pub async fn receive_sync(&self, sync: &Value) -> Result<(), E2eeError> {
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
        self.machine
            .receive_sync_changes(changes, &settings)
            .await
            .map_err(estr)?;
        self.process_outgoing().await
    }

    /// Decrypt every inbound `m.room.encrypted` text message in a sync response, skipping our own.
    /// Returns `(room_id, plaintext_body)` pairs for messages worth answering.
    pub async fn decrypt_messages(&self, sync: &Value, self_user: String) -> Vec<(String, String)> {
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
                if ev.get("sender").and_then(|s| s.as_str()) == Some(self_user.as_str()) {
                    continue;
                }
                let raw: Raw<EncryptedEvent> = match serde_json::from_value(ev.clone()) {
                    Ok(r) => r,
                    Err(_) => continue,
                };
                let parsed_room = match RoomId::parse(room_id) {
                    Ok(r) => r,
                    Err(_) => continue,
                };
                match self
                    .machine
                    .decrypt_room_event(&raw, &parsed_room, &settings)
                    .await
                {
                    Ok(decrypted) => {
                        if let Some(body) = text_body(&decrypted.event) {
                            out.push((room_id.clone(), body));
                        }
                    }
                    Err(e) => eprintln!("matrix[e2ee]: decrypt failed in {room_id}: {e}"),
                }
            }
        }
        out
    }

    /// Encrypt `body` as an `m.text` message and send it to `room_id` as `m.room.encrypted`.
    /// Takes its arguments by value so the future borrows nothing lifetime-generic (keeps the
    /// gateway's serve future `Send`).
    pub async fn encrypt_and_send(&self, room_id: String, body: String) -> Result<(), E2eeError> {
        let room = RoomId::parse(&room_id).map_err(estr)?;
        let users = self.joined_members(&room_id).await?;
        // Pass a fresh `&UserId` iterator per call (the `Deref::deref` fn item is lifetime-generic,
        // unlike a closure) so the borrow of `users` doesn't span every await — which would make
        // this future's `Send` lifetime-dependent and break the gateway's serve future.

        // Track the room's members, establish missing Olm sessions, then share the room key.
        self.machine
            .update_tracked_users(users.iter().map(Deref::deref))
            .await
            .map_err(estr)?;
        if let Some((id, req)) = self
            .machine
            .get_missing_sessions(users.iter().map(Deref::deref))
            .await
            .map_err(estr)?
        {
            let resp = self.send_ruma(req).await?;
            self.machine
                .mark_request_as_sent(&id, &resp)
                .await
                .map_err(estr)?;
        }
        let key_requests = self
            .machine
            .share_room_key(
                &room,
                users.iter().map(Deref::deref),
                EncryptionSettings::default(),
            )
            .await
            .map_err(estr)?;
        for req in key_requests {
            let resp = self.send_to_device(&req).await?;
            self.machine
                .mark_request_as_sent(&req.txn_id, &resp)
                .await
                .map_err(estr)?;
        }

        // Encrypt and send.
        let content: Raw<AnyMessageLikeEventContent> =
            Raw::new(&serde_json::json!({ "msgtype": "m.text", "body": body }))
                .map_err(estr)?
                .cast_unchecked();
        let encrypted = self
            .machine
            .encrypt_room_event_raw(&room, "m.room.message", &content)
            .await
            .map_err(estr)?;
        self.send_encrypted_event(&room_id, &encrypted.content)
            .await
    }

    /// Drain and dispatch the machine's outgoing requests until none remain.
    async fn process_outgoing(&self) -> Result<(), E2eeError> {
        for request in self.machine.outgoing_requests().await.map_err(estr)? {
            let id = request.request_id().to_owned();
            match request.request() {
                AnyOutgoingRequest::KeysUpload(r) => {
                    let resp = self.send_ruma(r.clone()).await?;
                    self.machine
                        .mark_request_as_sent(&id, &resp)
                        .await
                        .map_err(estr)?;
                }
                AnyOutgoingRequest::KeysQuery(r) => {
                    let mut req = get_keys::v3::Request::new();
                    req.device_keys = r.device_keys.clone();
                    req.timeout = r.timeout;
                    let resp = self.send_ruma(req).await?;
                    self.machine
                        .mark_request_as_sent(&id, &resp)
                        .await
                        .map_err(estr)?;
                }
                AnyOutgoingRequest::KeysClaim(r) => {
                    let resp = self.send_ruma(r.clone()).await?;
                    self.machine
                        .mark_request_as_sent(&id, &resp)
                        .await
                        .map_err(estr)?;
                }
                AnyOutgoingRequest::ToDeviceRequest(r) => {
                    let resp = self.send_to_device(r).await?;
                    self.machine
                        .mark_request_as_sent(&id, &resp)
                        .await
                        .map_err(estr)?;
                }
                AnyOutgoingRequest::SignatureUpload(r) => {
                    let resp = self.send_ruma(r.clone()).await?;
                    self.machine
                        .mark_request_as_sent(&id, &resp)
                        .await
                        .map_err(estr)?;
                }
                AnyOutgoingRequest::RoomMessage(_) => {
                    // Only emitted for in-room interactive verification, which this bot neither
                    // initiates nor supports — so there is nothing to send. (Left unmarked; the
                    // machine simply re-lists it, but a non-verifying bot never produces one.)
                    eprintln!("matrix[e2ee]: ignoring in-room verification message (unsupported)");
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
            .http
            .request(parts.method, parts.uri.to_string())
            .headers(parts.headers)
            .body(body)
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

    /// `PUT` an already-encrypted payload as an `m.room.encrypted` timeline event.
    async fn send_encrypted_event<T>(
        &self,
        room_id: &str,
        content: &Raw<T>,
    ) -> Result<(), E2eeError> {
        let txn = ruma::TransactionId::new();
        let url = format!(
            "{}/_matrix/client/v3/rooms/{}/send/m.room.encrypted/{}",
            self.homeserver,
            crate::urlencode(room_id),
            txn
        );
        let resp = self
            .http
            .put(url)
            .bearer_auth(&self.token)
            .json(content)
            .send()
            .await
            .map_err(estr)?;
        if !resp.status().is_success() {
            let status = resp.status();
            let msg = resp.text().await.unwrap_or_default();
            return Err(E2eeError(format!("send m.room.encrypted {status}: {msg}")));
        }
        Ok(())
    }

    /// Fetch the joined members of a room (recipients for room-key sharing).
    async fn joined_members(&self, room_id: &str) -> Result<Vec<OwnedUserId>, E2eeError> {
        let url = format!(
            "{}/_matrix/client/v3/rooms/{}/joined_members",
            self.homeserver,
            crate::urlencode(room_id)
        );
        let resp = self
            .http
            .get(url)
            .bearer_auth(&self.token)
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

/// Pull the `m.text` body out of a decrypted timeline event, if that's what it is.
fn text_body<T>(event: &Raw<T>) -> Option<String> {
    let v: Value = serde_json::from_str(event.json().get()).ok()?;
    let content = v.get("content")?;
    if content.get("msgtype").and_then(|m| m.as_str()) != Some("m.text") {
        return None;
    }
    content
        .get("body")
        .and_then(|b| b.as_str())
        .map(String::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raw(json: &str) -> Raw<Value> {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn text_body_extracts_plain_text() {
        let ev = raw(r#"{"type":"m.room.message","content":{"msgtype":"m.text","body":"hello"}}"#);
        assert_eq!(text_body(&ev), Some("hello".to_string()));
    }

    #[test]
    fn text_body_ignores_non_text_and_missing_body() {
        assert_eq!(
            text_body(&raw(r#"{"content":{"msgtype":"m.image","body":"p.png"}}"#)),
            None
        );
        assert_eq!(text_body(&raw(r#"{"content":{"msgtype":"m.text"}}"#)), None);
        assert_eq!(text_body(&raw(r#"{"type":"m.room.member"}"#)), None);
    }
}
