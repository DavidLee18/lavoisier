//! Copy a StoreCipher SQLite crypto directory into Postgres once, under the fence.
//!
//! `SqliteCryptoStore::open` is pointed at a task-local copy, never at the EFS path.
//! The copy and the migration marker commit in one transaction.

use std::path::Path;
use std::time::Duration;

use matrix_sdk_crypto::store::types::{Changes, PendingChanges};
use matrix_sdk_crypto::store::CryptoStore;
use matrix_sdk_sqlite::SqliteCryptoStore;
use ruma::events::secret::request::SecretName;
use tracing::info;

use super::error::StoreError;
use super::store::PostgresCryptoStore;

const DATABASE_NAME: &str = "matrix-sdk-crypto.sqlite3";
const BUDGET: Duration = Duration::from_secs(60);

const CUSTOM_KEYS: &[&str] = &[
    "HAS_MIGRATED_VERIFICATION_LATCH",
    "generation-counter",
    "only_allow_trusted_devices",
];

/// Copy `source` (the EFS `crypto/` directory) through the 0.18 read API.
/// A null marker after this returns is a failed boot: do not call `with_store`.
pub async fn migrate_sqlite(
    store: &PostgresCryptoStore,
    source: &Path,
    passphrase: Option<&str>,
) -> Result<(), StoreError> {
    if store.migration_marker().await?.is_some() {
        return Ok(());
    }
    let copy = std::env::temp_dir().join(format!(
        "crypto-migrate-{}-{}",
        std::process::id(),
        uuid::Uuid::new_v4().simple()
    ));
    let result =
        tokio::time::timeout(BUDGET, copy_under_fence(store, source, passphrase, &copy)).await;
    let _ = std::fs::remove_dir_all(&copy);
    match result {
        Ok(Ok(())) => Ok(()),
        Ok(Err(e)) => {
            let _ = store.rollback_open().await;
            Err(e)
        }
        Err(_) => {
            let _ = store.rollback_open().await;
            Err(StoreError::Other("migration budget exceeded".into()))
        }
    }
}

async fn copy_under_fence(
    store: &PostgresCryptoStore,
    source: &Path,
    passphrase: Option<&str>,
    copy: &Path,
) -> Result<(), StoreError> {
    copy_dir(source, copy).map_err(|e| StoreError::Other(e.to_string()))?;
    let db = copy.join(DATABASE_NAME);
    if !db.is_file() {
        return Err(StoreError::Other(
            "sqlite crypto database missing from the migration copy".into(),
        ));
    }
    // Open the copy. A missing cipher row is written here, not on EFS.
    let sqlite = SqliteCryptoStore::open(copy, passphrase)
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?;

    store.begin_migration().await?;
    if let Err(e) = copy_records(store, &sqlite).await {
        let _ = store.rollback_open().await;
        let _ = sqlite.close().await;
        return Err(e);
    }
    let account = match sqlite.load_account().await {
        Ok(Some(account)) => account,
        Ok(None) => {
            let _ = store.rollback_open().await;
            let _ = sqlite.close().await;
            return Err(StoreError::MissingAccount);
        }
        Err(e) => {
            let _ = store.rollback_open().await;
            let _ = sqlite.close().await;
            return Err(StoreError::Other(e.to_string()));
        }
    };
    let user_id = account.user_id().to_string();
    let device_id = account.device_id().to_string();
    store.commit_migration(&user_id, &device_id).await?;
    let _ = sqlite.close().await;
    info!("e2ee: sqlite crypto store copied");
    Ok(())
}

async fn copy_records(
    store: &PostgresCryptoStore,
    sqlite: &SqliteCryptoStore,
) -> Result<(), StoreError> {
    if let Some(account) = sqlite
        .load_account()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?
    {
        store
            .save_pending_changes(PendingChanges {
                account: Some(account),
            })
            .await?;
    }
    let mut changes = Changes::default();
    if let Some(identity) = sqlite
        .load_identity()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?
    {
        changes.private_identity = Some(identity);
    }
    let backup = sqlite
        .load_backup_keys()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?;
    changes.backup_version = backup.backup_version;
    changes.backup_decryption_key = backup.decryption_key;
    changes.dehydrated_device_pickle_key = sqlite
        .load_dehydrated_device_pickle_key()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?;
    changes.next_batch_token = sqlite
        .next_batch_token()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?;

    let tracked = sqlite
        .load_tracked_users()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?;
    let tracked_pairs: Vec<_> = tracked
        .iter()
        .map(|u| (u.user_id.as_ref(), u.dirty))
        .collect();
    if !tracked_pairs.is_empty() {
        store.save_tracked_users(&tracked_pairs).await?;
    }

    let mut users: Vec<ruma::OwnedUserId> = tracked.iter().map(|u| u.user_id.clone()).collect();
    if let Some(account) = sqlite
        .load_account()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?
    {
        if !users.iter().any(|u| u == account.user_id()) {
            users.push(account.user_id().to_owned());
        }
    }

    let mut sender_keys = Vec::new();
    let mut rooms = Vec::new();
    for user in &users {
        let devices = sqlite
            .get_user_devices(user)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?;
        for device in devices.into_values() {
            if let Some(key) = device.curve25519_key() {
                sender_keys.push(key.to_base64());
            }
            changes.devices.new.push(device);
        }
        if let Some(identity) = sqlite
            .get_user_identity(user)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?
        {
            changes.identities.new.push(identity);
        }
    }

    let inbound = sqlite
        .get_inbound_group_sessions()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?;
    for session in &inbound {
        let sender = session.sender_key().to_base64();
        if !sender_keys.iter().any(|k| k == &sender) {
            sender_keys.push(sender);
        }
        let room = session.room_id().to_owned();
        if !rooms.iter().any(|r| r == &room) {
            rooms.push(room);
        }
    }
    changes.inbound_group_sessions = inbound;

    for sender in &sender_keys {
        if let Some(sessions) = sqlite
            .get_sessions(sender)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?
        {
            changes.sessions.extend(sessions);
        }
    }

    for room in &rooms {
        if let Some(outbound) = sqlite
            .get_outbound_group_session(room)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?
        {
            changes.outbound_group_sessions.push(outbound);
        }
        if let Some(settings) = sqlite
            .get_room_settings(room)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?
        {
            changes.room_settings.insert(room.clone(), settings);
        }
        let withheld = sqlite
            .get_withheld_sessions_by_room_id(room)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?;
        if !withheld.is_empty() {
            let map = changes
                .withheld_session_info
                .entry(room.clone())
                .or_default();
            for entry in withheld {
                let Some(session_id) = entry.content.megolm_session_id() else {
                    continue;
                };
                map.insert(session_id.to_owned(), entry);
            }
        }
        if sqlite
            .has_downloaded_all_room_keys(room)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?
        {
            changes
                .room_key_backups_fully_downloaded
                .insert(room.clone());
        }
        if let Some(details) = sqlite
            .get_pending_key_bundle_details_for_room(room)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?
        {
            changes
                .rooms_pending_key_bundle
                .insert(room.clone(), Some(details));
        }
        for user in &users {
            if let Some(bundle) = sqlite
                .get_received_room_key_bundle_data(room, user)
                .await
                .map_err(|e| StoreError::Other(e.to_string()))?
            {
                changes.received_room_key_bundles.push(bundle);
            }
        }
    }

    let unsent = sqlite
        .get_unsent_secret_requests()
        .await
        .map_err(|e| StoreError::Other(e.to_string()))?;
    changes.key_requests = unsent;

    for name in [
        SecretName::CrossSigningMasterKey,
        SecretName::CrossSigningSelfSigningKey,
        SecretName::CrossSigningUserSigningKey,
        SecretName::RecoveryKey,
    ] {
        let secrets = sqlite
            .get_secrets_from_inbox(&name)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?;
        for secret in secrets {
            changes
                .secrets
                .push(matrix_sdk_crypto::store::types::SecretsInboxItem {
                    secret_name: name.clone(),
                    secret,
                });
        }
    }

    for key in CUSTOM_KEYS {
        if let Some(value) = sqlite
            .get_custom_value(key)
            .await
            .map_err(|e| StoreError::Other(e.to_string()))?
        {
            store.set_custom_value(key, value).await?;
        }
    }

    store.save_changes(changes).await?;
    Ok(())
}

fn copy_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let to = dst.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir(&entry.path(), &to)?;
        } else {
            std::fs::copy(entry.path(), &to)?;
        }
    }
    Ok(())
}
