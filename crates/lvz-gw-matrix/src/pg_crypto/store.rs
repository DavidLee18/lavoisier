//! Fenced Postgres [`CryptoStore`](matrix_sdk_crypto::store::CryptoStore).
//!
//! One connection. Every mutating transaction bumps `crypto.crypto_fence.commit_seq`
//! by one. The `receive_sync` pair bracket and the SQLite migration defer `COMMIT`
//! so both halves share that one bump.

use std::collections::HashMap;
use std::ops::Deref;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::Arc;

use async_trait::async_trait;
use matrix_sdk_common::cross_process_lock::CrossProcessLockGeneration;
use matrix_sdk_crypto::olm::{
    InboundGroupSession, OlmMessageHash, OutboundGroupSession, PrivateCrossSigningIdentity,
    SenderDataType, Session,
};
use matrix_sdk_crypto::store::types::{
    BackupKeys, Changes, DehydratedDeviceKey, PendingChanges, RoomKeyCounts, RoomKeyWithheldEntry,
    RoomPendingKeyBundleDetails, RoomSettings, StoredRoomKeyBundleData, TrackedUser,
};
use matrix_sdk_crypto::store::CryptoStore;
use matrix_sdk_crypto::{olm::StaticAccountData, vodozemac::Curve25519PublicKey};
use matrix_sdk_crypto::{
    types::DeviceKeys, Account, DeviceData, GossipRequest, SecretInfo, UserIdentityData,
};
use ruma::{
    events::secret::request::SecretName, DeviceId, MilliSecondsSinceUnixEpoch, OwnedDeviceId,
    RoomId, TransactionId, UserId,
};
use serde::de::DeserializeOwned;
use serde::Serialize;
use tokio::task::JoinHandle;
use tokio_postgres::Client;
use tracing::{error, info, warn};
use uuid::Uuid;
use zeroize::Zeroizing;

use super::codec::StoreCodec;
use super::error::{classify_lost, db_err, Reconcile, StoreError};

const DEFER_OFF: u8 = 0;
const DEFER_PAIR: u8 = 1;
const DEFER_MIGRATION: u8 = 2;

const FIRST_LEASE: &str = "120 seconds";
const LEASE: &str = "20 seconds";
const WAITER_FOR: &str = "60 seconds";

const KEY_ACCOUNT: &str = "account";
const KEY_IDENTITY: &str = "identity";
const KEY_NEXT_BATCH: &str = "next_batch_token";
const KEY_RECOVERY: &str = "recovery_key_v1";
const KEY_BACKUP_VERSION: &str = "backup_version_v1";
const KEY_DEHYDRATED: &str = "dehydrated_device_pickle_key";

struct Inflight {
    op_id: Uuid,
    before_seq: i64,
}

struct Writer {
    client: Client,
    task: JoinHandle<()>,
    txn_open: bool,
    inflight: Option<Inflight>,
    closed: bool,
}

#[derive(Clone)]
struct AccountCache {
    static_data: StaticAccountData,
    device_keys: DeviceKeys,
}

enum TlsMode {
    Off,
    Verify,
}

struct ConnectSpec {
    config: tokio_postgres::Config,
    tls: TlsMode,
}

/// Postgres crypto store. Pool size is 1. The fence holder is `holder`.
pub struct PostgresCryptoStore {
    writer: tokio::sync::Mutex<Writer>,
    spec: ConnectSpec,
    codec: StoreCodec,
    holder: String,
    epoch: AtomicU64,
    defer: AtomicU8,
    boot_load: AtomicBool,
    fail_account: AtomicBool,
    lose_commit: AtomicBool,
    increment_calls: AtomicU64,
    cache: tokio::sync::Mutex<Option<AccountCache>>,
}

impl std::fmt::Debug for PostgresCryptoStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PostgresCryptoStore")
            .field("holder", &self.holder)
            .field("epoch", &self.epoch())
            .finish()
    }
}

impl PostgresCryptoStore {
    /// Connect without TLS. Tests and a local Postgres use this.
    pub async fn connect_no_tls(
        config: tokio_postgres::Config,
        passphrase: &str,
        holder: impl Into<String>,
    ) -> Result<Arc<Self>, StoreError> {
        Self::open(
            ConnectSpec {
                config,
                tls: TlsMode::Off,
            },
            passphrase,
            holder.into(),
        )
        .await
    }

    /// Connect from the `MATRIX_CRYPTO_STORE_SECRET` JSON. The password is not logged.
    pub async fn connect_secret(
        secret_json: &str,
        passphrase: &str,
        holder: impl Into<String>,
    ) -> Result<Arc<Self>, StoreError> {
        let v: serde_json::Value = serde_json::from_str(secret_json)
            .map_err(|_| StoreError::Other("aurora crypto secret is not json".into()))?;
        let host = json_str(&v, "host")?;
        let user = json_str(&v, "username")?;
        let password = json_str(&v, "password")?;
        let dbname = json_str(&v, "dbname")?;
        let port = v
            .get("port")
            .and_then(|p| p.as_u64())
            .ok_or_else(|| StoreError::Other("aurora crypto secret missing port".into()))?;
        let mut config = tokio_postgres::Config::new();
        config.host(host);
        config.port(u16::try_from(port).unwrap_or(5432));
        config.user(user);
        config.password(password);
        config.dbname(dbname);
        Self::open(
            ConnectSpec {
                config,
                tls: TlsMode::Verify,
            },
            passphrase,
            holder.into(),
        )
        .await
    }

    async fn open(
        spec: ConnectSpec,
        passphrase: &str,
        holder: String,
    ) -> Result<Arc<Self>, StoreError> {
        let (client, task) = dial(&spec).await?;
        let store = Arc::new(Self {
            writer: tokio::sync::Mutex::new(Writer {
                client,
                task,
                txn_open: false,
                inflight: None,
                closed: false,
            }),
            spec,
            codec: StoreCodec::from_passphrase(passphrase)?,
            holder,
            epoch: AtomicU64::new(0),
            defer: AtomicU8::new(DEFER_OFF),
            boot_load: AtomicBool::new(false),
            fail_account: AtomicBool::new(false),
            lose_commit: AtomicBool::new(false),
            increment_calls: AtomicU64::new(0),
            cache: tokio::sync::Mutex::new(None),
        });
        Ok(store)
    }

    /// Epoch this process acquired. Zero before the first acquire.
    pub fn epoch(&self) -> i64 {
        self.epoch.load(Ordering::SeqCst) as i64
    }

    /// Holder id recorded on the fence.
    pub fn holder(&self) -> &str {
        &self.holder
    }

    /// Renew between boot-load batches. `OlmMachine::with_store` calls reads one at a time.
    pub fn set_boot_load(&self, on: bool) {
        self.boot_load.store(on, Ordering::SeqCst);
    }

    /// How many times the incrementing acquire `UPDATE` has run. A second acquire
    /// by the current holder must leave this unchanged.
    pub fn increment_calls(&self) -> u64 {
        self.increment_calls.load(Ordering::SeqCst)
    }

    /// Next account write rolls the open transaction back.
    pub fn fail_next_account_write(&self) {
        self.fail_account.store(true, Ordering::SeqCst);
    }

    /// Next commit lands on the server and is reported as [`StoreError::CommitUnknown`].
    pub fn lose_next_commit(&self) {
        self.lose_commit.store(true, Ordering::SeqCst);
    }

    /// Record this process as the waiter. Does not take the epoch.
    pub async fn record_waiter(&self) -> Result<(), StoreError> {
        let guard = self.writer.lock().await;
        if guard.closed {
            return Err(StoreError::Closed);
        }
        guard
            .client
            .execute(
                "UPDATE crypto.crypto_fence
                 SET waiter = $1, waiter_until = clock_timestamp() + interval '60 seconds'
                 WHERE id = 1
                   AND (waiter IS NULL OR waiter = $1 OR waiter_until < clock_timestamp())",
                &[&self.holder],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let _ = WAITER_FOR;
        Ok(())
    }

    /// Acquire when this process is not the holder. A second call by the current
    /// holder renews and returns the same epoch. It does not run the incrementing `UPDATE`.
    pub async fn acquire(&self) -> Result<i64, StoreError> {
        let guard = self.writer.lock().await;
        if guard.closed {
            return Err(StoreError::Closed);
        }
        let row = guard
            .client
            .query_one(
                "SELECT holder, epoch FROM crypto.crypto_fence WHERE id = 1",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let holder: String = row.get(0);
        let epoch: i64 = row.get(1);
        if holder == self.holder && epoch > 0 {
            drop(guard);
            return self.renew_lease().await;
        }
        self.increment_calls.fetch_add(1, Ordering::SeqCst);
        let updated = guard
            .client
            .query_opt(
                &format!(
                    "UPDATE crypto.crypto_fence
                     SET epoch = epoch + 1, holder = $1, waiter = NULL,
                         lease_until = clock_timestamp() + interval '{FIRST_LEASE}'
                     WHERE id = 1 AND holder <> $1 AND lease_until < clock_timestamp()
                     RETURNING epoch"
                ),
                &[&self.holder],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = updated else {
            return Err(StoreError::Other("fence held".into()));
        };
        let epoch: i64 = row.get(0);
        self.epoch.store(epoch as u64, Ordering::SeqCst);
        info!(epoch, "e2ee: fence acquired");
        Ok(epoch)
    }

    /// Extend the lease. Does not change the epoch. Zero rows is [`StoreError::StaleFence`].
    pub async fn renew_lease(&self) -> Result<i64, StoreError> {
        let epoch = self.epoch();
        let guard = self.writer.lock().await;
        if guard.txn_open {
            return Ok(epoch);
        }
        let row = guard
            .client
            .query_opt(
                "UPDATE crypto.crypto_fence
                 SET lease_until = clock_timestamp() + interval '20 seconds'
                 WHERE id = 1 AND holder = $1 AND epoch = $2
                 RETURNING epoch",
                &[&self.holder, &epoch],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            error!(epoch, "e2ee: stale fence");
            return Err(StoreError::StaleFence);
        };
        let _ = LEASE;
        Ok(row.get(0))
    }

    /// Heartbeat. Returns the waiter when one is recorded. `None` from the outer
    /// option means the connection was busy.
    pub async fn heartbeat_if_idle(&self) -> Option<Result<Option<String>, StoreError>> {
        let guard = self.writer.try_lock().ok()?;
        if guard.txn_open || guard.closed {
            return None;
        }
        let epoch = self.epoch();
        let row = match guard
            .client
            .query_opt(
                "UPDATE crypto.crypto_fence
                 SET lease_until = clock_timestamp() + interval '20 seconds'
                 WHERE id = 1 AND holder = $1 AND epoch = $2
                 RETURNING waiter",
                &[&self.holder, &epoch],
            )
            .await
        {
            Ok(row) => row,
            Err(e) => return Some(Err(db_err(e, false))),
        };
        let Some(row) = row else {
            error!(epoch, "e2ee: stale fence");
            return Some(Err(StoreError::StaleFence));
        };
        let waiter: Option<String> = row.get(0);
        Some(Ok(waiter))
    }

    /// Read the fence for the park loop. Does not renew.
    pub async fn fence_snapshot(
        &self,
    ) -> Result<crate::fence_supervisor::FenceSnapshot, StoreError> {
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_one(
                "SELECT holder,
                        lease_until > clock_timestamp(),
                        waiter,
                        COALESCE(waiter_until > clock_timestamp(), false)
                 FROM crypto.crypto_fence WHERE id = 1",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(crate::fence_supervisor::FenceSnapshot {
            holder: row.get(0),
            lease_live: row.get(1),
            waiter: row.get(2),
            waiter_live: row.get(3),
        })
    }

    /// Release the epoch. The parked process must not acquire again.
    pub async fn release(&self) -> Result<(), StoreError> {
        let epoch = self.epoch();
        let guard = self.writer.lock().await;
        guard
            .client
            .execute(
                "UPDATE crypto.crypto_fence
                 SET lease_until = clock_timestamp(), holder = ''
                 WHERE id = 1 AND holder = $1 AND epoch = $2",
                &[&self.holder, &epoch],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        info!(epoch, "e2ee: fence released");
        Ok(())
    }

    /// `crypto_meta.migration_marker`, if the cutover committed.
    pub async fn migration_marker(&self) -> Result<Option<Uuid>, StoreError> {
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT migration_marker FROM crypto.crypto_meta WHERE id = 1",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(row.and_then(|r| r.get(0)))
    }

    /// Refuses `with_store` while the marker is null or the account cannot be loaded.
    pub async fn ready_for_machine(&self) -> Result<(), StoreError> {
        if self.migration_marker().await?.is_none() {
            return Err(StoreError::NoMarker);
        }
        match self.load_account().await? {
            Some(_) => Ok(()),
            None => Err(StoreError::MissingAccount),
        }
    }

    /// Start the `receive_sync` pair bracket.
    pub fn begin_pair(&self) {
        self.defer.store(DEFER_PAIR, Ordering::SeqCst);
    }

    /// Leave the bracket. Commits if the account transaction never arrived.
    pub async fn end_pair(&self) -> Result<(), StoreError> {
        let result = self.flush_deferred().await;
        self.defer.store(DEFER_OFF, Ordering::SeqCst);
        result
    }

    /// Commit a deferred transaction, if one is open.
    pub async fn flush_deferred(&self) -> Result<(), StoreError> {
        let mut guard = self.writer.lock().await;
        if !guard.txn_open {
            return Ok(());
        }
        self.finish(&mut guard).await
    }

    /// Open the one-shot migration transaction and bump the fence once.
    pub async fn begin_migration(&self) -> Result<(), StoreError> {
        self.defer.store(DEFER_MIGRATION, Ordering::SeqCst);
        let guard = self.begin_mutation().await?;
        drop(guard);
        Ok(())
    }

    /// Write the marker and commit the migration transaction.
    pub async fn commit_migration(&self, user_id: &str, device_id: &str) -> Result<(), StoreError> {
        let mut guard = self.writer.lock().await;
        if !guard.txn_open {
            self.defer.store(DEFER_OFF, Ordering::SeqCst);
            return Err(StoreError::Other(
                "migration transaction is not open".into(),
            ));
        }
        let marker = Uuid::new_v4();
        if let Err(e) = guard
            .client
            .execute(
                "UPDATE crypto.crypto_meta
                 SET migration_marker = $1, user_id = $2, device_id = $3
                 WHERE id = 1",
                &[&marker, &user_id, &device_id],
            )
            .await
        {
            self.rollback(&mut guard).await;
            self.defer.store(DEFER_OFF, Ordering::SeqCst);
            return Err(db_err(e, false));
        }
        let finished = self.finish(&mut guard).await;
        self.defer.store(DEFER_OFF, Ordering::SeqCst);
        finished
    }

    /// Roll back an open migration or pair transaction.
    pub async fn rollback_open(&self) -> Result<(), StoreError> {
        let mut guard = self.writer.lock().await;
        if guard.txn_open {
            self.rollback(&mut guard).await;
        }
        self.defer.store(DEFER_OFF, Ordering::SeqCst);
        Ok(())
    }

    /// Reconcile the in-flight op after [`StoreError::CommitUnknown`].
    pub async fn reconcile_inflight(&self) -> Result<Reconcile, StoreError> {
        let guard = self.writer.lock().await;
        let Some(inflight) = guard.inflight.as_ref() else {
            return Err(StoreError::Other("no in-flight commit to reconcile".into()));
        };
        let op = inflight.op_id;
        let before = inflight.before_seq;
        drop(guard);
        let outcome = self.reconcile_with(before, op).await?;
        match outcome {
            Reconcile::Committed => {
                info!("e2ee: commit outcome unknown, reconciled committed")
            }
            Reconcile::Aborted => info!("e2ee: commit outcome unknown, reconciled aborted"),
            Reconcile::ForeignCommit | Reconcile::DoNotRefeed => {
                info!("e2ee: commit outcome unknown, reconciled foreign")
            }
            Reconcile::StillUnknown => {
                warn!("e2ee: commit outcome unknown, reconcile select failed")
            }
        }
        Ok(outcome)
    }

    /// Classify the fence against a recorded baseline. Does not write.
    pub async fn reconcile_with(
        &self,
        before_seq: i64,
        op_id: Uuid,
    ) -> Result<Reconcile, StoreError> {
        let guard = self.writer.lock().await;
        let row = match guard
            .client
            .query_one(
                "SELECT commit_seq, last_op_id FROM crypto.crypto_fence WHERE id = 1",
                &[],
            )
            .await
        {
            Ok(row) => row,
            Err(_) => return Ok(Reconcile::StillUnknown),
        };
        let seq: i64 = row.get(0);
        let last: Option<Uuid> = row.get(1);
        Ok(classify_lost(before_seq, op_id, seq, last))
    }

    /// `(epoch, commit_seq)` as currently committed.
    pub async fn baseline(&self) -> Result<(i64, i64), StoreError> {
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_one(
                "SELECT epoch, commit_seq FROM crypto.crypto_fence WHERE id = 1",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok((row.get(0), row.get(1)))
    }

    async fn begin_mutation(&self) -> Result<tokio::sync::MutexGuard<'_, Writer>, StoreError> {
        let mut guard = self.writer.lock().await;
        if guard.closed {
            return Err(StoreError::Closed);
        }
        if guard.txn_open {
            return Ok(guard);
        }
        guard
            .client
            .batch_execute("BEGIN")
            .await
            .map_err(|e| db_err(e, false))?;
        guard.txn_open = true;
        let row = match guard
            .client
            .query_one(
                "SELECT commit_seq FROM crypto.crypto_fence WHERE id = 1",
                &[],
            )
            .await
        {
            Ok(row) => row,
            Err(e) => {
                self.rollback(&mut guard).await;
                return Err(db_err(e, false));
            }
        };
        let before_seq: i64 = row.get(0);
        let op_id = Uuid::new_v4();
        let epoch = self.epoch();
        let updated = match guard
            .client
            .query_opt(
                "UPDATE crypto.crypto_fence
                 SET commit_seq = commit_seq + 1, last_op_id = $1
                 WHERE id = 1 AND holder = $2 AND epoch = $3
                 RETURNING commit_seq",
                &[&op_id, &self.holder, &epoch],
            )
            .await
        {
            Ok(row) => row,
            Err(e) => {
                self.rollback(&mut guard).await;
                return Err(db_err(e, false));
            }
        };
        if updated.is_none() {
            error!(epoch, "e2ee: stale fence");
            self.rollback(&mut guard).await;
            return Err(StoreError::StaleFence);
        }
        guard.inflight = Some(Inflight { op_id, before_seq });
        Ok(guard)
    }

    async fn finish(&self, guard: &mut Writer) -> Result<(), StoreError> {
        let epoch = self.epoch();
        let n = match guard
            .client
            .execute(
                "UPDATE crypto.crypto_fence
                 SET lease_until = clock_timestamp() + interval '20 seconds'
                 WHERE id = 1 AND holder = $1 AND epoch = $2",
                &[&self.holder, &epoch],
            )
            .await
        {
            Ok(n) => n,
            Err(e) => {
                self.rollback(guard).await;
                return Err(db_err(e, false));
            }
        };
        if n == 0 {
            error!(epoch, "e2ee: stale fence");
            self.rollback(guard).await;
            return Err(StoreError::StaleFence);
        }
        let lose = self.lose_commit.swap(false, Ordering::SeqCst);
        match guard.client.batch_execute("COMMIT").await {
            Ok(()) => {
                guard.txn_open = false;
                if lose {
                    return Err(StoreError::CommitUnknown);
                }
                guard.inflight = None;
                Ok(())
            }
            Err(e) if e.is_closed() => {
                guard.txn_open = false;
                Err(StoreError::CommitUnknown)
            }
            Err(e) => {
                self.rollback(guard).await;
                Err(db_err(e, false))
            }
        }
    }

    async fn rollback(&self, guard: &mut Writer) {
        let _ = guard.client.batch_execute("ROLLBACK").await;
        guard.txn_open = false;
        guard.inflight = None;
    }

    async fn maybe_renew_for_load(&self) {
        if self.boot_load.load(Ordering::SeqCst) {
            let _ = self.renew_lease().await;
        }
    }

    fn seal_rmp<T: Serialize>(&self, value: &T) -> Result<(Vec<u8>, Vec<u8>), StoreError> {
        let bytes = rmp_serde::to_vec_named(value).map_err(|_| StoreError::Unpickle)?;
        self.codec.seal(&bytes)
    }

    fn open_rmp<T: DeserializeOwned>(&self, nonce: &[u8], ct: &[u8]) -> Result<T, StoreError> {
        let plain = self.codec.open(nonce, ct)?;
        rmp_serde::from_slice(&plain).map_err(|_| StoreError::Unpickle)
    }

    fn seal_json<T: Serialize>(&self, value: &T) -> Result<(Vec<u8>, Vec<u8>), StoreError> {
        let bytes = serde_json::to_vec(value).map_err(|_| StoreError::Unpickle)?;
        self.codec.seal(&bytes)
    }

    fn open_json<T: DeserializeOwned>(&self, nonce: &[u8], ct: &[u8]) -> Result<T, StoreError> {
        let plain = self.codec.open(nonce, ct)?;
        serde_json::from_slice(&plain).map_err(|_| StoreError::Unpickle)
    }

    async fn put_kv(&self, client: &Client, key: &str, plain: &[u8]) -> Result<(), StoreError> {
        let (nonce, value) = self.codec.seal(plain)?;
        client
            .execute(
                "INSERT INTO crypto.crypto_kv (key, nonce, value) VALUES ($1, $2, $3)
                 ON CONFLICT (key) DO UPDATE SET nonce = EXCLUDED.nonce, value = EXCLUDED.value",
                &[&key, &nonce, &value],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(())
    }

    async fn get_kv(&self, client: &Client, key: &str) -> Result<Option<Vec<u8>>, StoreError> {
        let row = client
            .query_opt(
                "SELECT nonce, value FROM crypto.crypto_kv WHERE key = $1",
                &[&key],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        let nonce: Vec<u8> = row.get(0);
        let value: Vec<u8> = row.get(1);
        Ok(Some(self.codec.open(&nonce, &value)?))
    }

    async fn remember_account(&self, account: &Account) {
        *self.cache.lock().await = Some(AccountCache {
            static_data: account.static_data().clone(),
            device_keys: account.device_keys(),
        });
    }

    async fn device_keys(&self) -> Result<DeviceKeys, StoreError> {
        if let Some(cache) = self.cache.lock().await.clone() {
            return Ok(cache.device_keys);
        }
        Err(StoreError::AccountUnset)
    }

    async fn static_account(&self) -> Result<StaticAccountData, StoreError> {
        self.cache
            .lock()
            .await
            .as_ref()
            .map(|c| c.static_data.clone())
            .ok_or(StoreError::AccountUnset)
    }

    async fn apply_changes(&self, client: &Client, changes: Changes) -> Result<(), StoreError> {
        if let Some(identity) = changes.private_identity {
            let pickle = identity.pickle().await;
            let (nonce, value) = self.seal_rmp(&pickle)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_kv (key, nonce, value) VALUES ($1, $2, $3)
                     ON CONFLICT (key) DO UPDATE SET nonce = EXCLUDED.nonce, value = EXCLUDED.value",
                    &[&KEY_IDENTITY, &nonce, &value],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        if let Some(token) = &changes.next_batch_token {
            let (nonce, value) = self.seal_rmp(token)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_kv (key, nonce, value) VALUES ($1, $2, $3)
                     ON CONFLICT (key) DO UPDATE SET nonce = EXCLUDED.nonce, value = EXCLUDED.value",
                    &[&KEY_NEXT_BATCH, &nonce, &value],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        if let Some(key) = &changes.backup_decryption_key {
            let (nonce, value) = self.seal_rmp(key)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_kv (key, nonce, value) VALUES ($1, $2, $3)
                     ON CONFLICT (key) DO UPDATE SET nonce = EXCLUDED.nonce, value = EXCLUDED.value",
                    &[&KEY_RECOVERY, &nonce, &value],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        if let Some(version) = &changes.backup_version {
            let (nonce, value) = self.seal_rmp(version)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_kv (key, nonce, value) VALUES ($1, $2, $3)
                     ON CONFLICT (key) DO UPDATE SET nonce = EXCLUDED.nonce, value = EXCLUDED.value",
                    &[&KEY_BACKUP_VERSION, &nonce, &value],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        if let Some(pickle_key) = &changes.dehydrated_device_pickle_key {
            let (nonce, value) = self.seal_rmp(pickle_key)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_kv (key, nonce, value) VALUES ($1, $2, $3)
                     ON CONFLICT (key) DO UPDATE SET nonce = EXCLUDED.nonce, value = EXCLUDED.value",
                    &[&KEY_DEHYDRATED, &nonce, &value],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for device in changes.devices.new.iter().chain(&changes.devices.changed) {
            let (nonce, data) = self.seal_rmp(device)?;
            let user_id = device.user_id().to_string();
            let device_id = device.device_id().to_string();
            client
                .execute(
                    "INSERT INTO crypto.crypto_device (user_id, device_id, nonce, data)
                     VALUES ($1, $2, $3, $4)
                     ON CONFLICT (user_id, device_id)
                     DO UPDATE SET nonce = EXCLUDED.nonce, data = EXCLUDED.data",
                    &[&user_id, &device_id, &nonce, &data],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for device in &changes.devices.deleted {
            client
                .execute(
                    "DELETE FROM crypto.crypto_device WHERE user_id = $1 AND device_id = $2",
                    &[
                        &device.user_id().to_string(),
                        &device.device_id().to_string(),
                    ],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for identity in changes
            .identities
            .new
            .iter()
            .chain(&changes.identities.changed)
        {
            let (nonce, data) = self.seal_rmp(identity)?;
            let user_id = identity.user_id().to_string();
            client
                .execute(
                    "INSERT INTO crypto.crypto_identity (user_id, nonce, data) VALUES ($1, $2, $3)
                     ON CONFLICT (user_id) DO UPDATE SET nonce = EXCLUDED.nonce, data = EXCLUDED.data",
                    &[&user_id, &nonce, &data],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for session in changes.sessions {
            let session_id = session.session_id().to_owned();
            let sender_key = session.sender_key().to_base64();
            let pickle = session.pickle().await;
            let (nonce, bytes) = self.seal_rmp(&pickle)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_session (session_id, sender_key, nonce, pickle)
                     VALUES ($1, $2, $3, $4)
                     ON CONFLICT (session_id)
                     DO UPDATE SET sender_key = EXCLUDED.sender_key, nonce = EXCLUDED.nonce, pickle = EXCLUDED.pickle",
                    &[&session_id, &sender_key, &nonce, &bytes],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for session in changes.inbound_group_sessions {
            let session_id = session.session_id().to_owned();
            let room_id = session.room_id().to_string();
            let sender_key = session.sender_key().to_base64();
            let pickle = session.pickle().await;
            let sender_data_type = sender_type_id(pickle.sender_data.to_type());
            let backed_up = pickle.backed_up;
            let (nonce, bytes) = self.seal_rmp(&pickle)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_inbound_group_session
                        (session_id, room_id, sender_key, sender_data_type, backed_up, nonce, pickle)
                     VALUES ($1, $2, $3, $4, $5, $6, $7)
                     ON CONFLICT (session_id) DO UPDATE SET
                        room_id = EXCLUDED.room_id,
                        sender_key = EXCLUDED.sender_key,
                        sender_data_type = EXCLUDED.sender_data_type,
                        backed_up = EXCLUDED.backed_up,
                        nonce = EXCLUDED.nonce,
                        pickle = EXCLUDED.pickle",
                    &[
                        &session_id,
                        &room_id,
                        &sender_key,
                        &sender_data_type,
                        &backed_up,
                        &nonce,
                        &bytes,
                    ],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for session in changes.outbound_group_sessions {
            let room_id = session.room_id().to_string();
            let pickle = session.pickle().await;
            let (nonce, bytes) = self.seal_json(&pickle)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_outbound_group_session (room_id, nonce, pickle)
                     VALUES ($1, $2, $3)
                     ON CONFLICT (room_id) DO UPDATE SET nonce = EXCLUDED.nonce, pickle = EXCLUDED.pickle",
                    &[&room_id, &nonce, &bytes],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for hash in &changes.message_hashes {
            let encoded = rmp_serde::to_vec_named(hash).map_err(|_| StoreError::Unpickle)?;
            let text = base64_hash(&encoded);
            client
                .execute(
                    "INSERT INTO crypto.crypto_olm_hash (hash) VALUES ($1) ON CONFLICT DO NOTHING",
                    &[&text],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for request in changes.key_requests {
            let request_id = request.request_id.to_string();
            let sent_out = request.sent_out;
            let (nonce, body) = self.seal_rmp(&request)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_key_request (request_id, sent_out, nonce, body)
                     VALUES ($1, $2, $3, $4)
                     ON CONFLICT (request_id)
                     DO UPDATE SET sent_out = EXCLUDED.sent_out, nonce = EXCLUDED.nonce, body = EXCLUDED.body",
                    &[&request_id, &sent_out, &nonce, &body],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for (room_id, sessions) in changes.withheld_session_info {
            for (session_id, entry) in sessions {
                let (nonce, body) = self.seal_json(&entry)?;
                let room = room_id.to_string();
                client
                    .execute(
                        "INSERT INTO crypto.crypto_withheld (session_id, room_id, nonce, body)
                         VALUES ($1, $2, $3, $4)
                         ON CONFLICT (session_id)
                         DO UPDATE SET room_id = EXCLUDED.room_id, nonce = EXCLUDED.nonce, body = EXCLUDED.body",
                        &[&session_id, &room, &nonce, &body],
                    )
                    .await
                    .map_err(|e| db_err(e, false))?;
            }
        }
        for (room_id, settings) in changes.room_settings {
            let (nonce, body) = self.seal_rmp(&settings)?;
            let room = room_id.to_string();
            client
                .execute(
                    "INSERT INTO crypto.crypto_room_settings (room_id, nonce, settings)
                     VALUES ($1, $2, $3)
                     ON CONFLICT (room_id) DO UPDATE SET nonce = EXCLUDED.nonce, settings = EXCLUDED.settings",
                    &[&room, &nonce, &body],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for secret in changes.secrets {
            let name = secret.secret_name.to_string();
            let hmac = self.codec.secret_hmac(secret.secret.as_str())?;
            let plain = secret.secret.deref().to_owned();
            let (nonce, body) = self.seal_json(&plain)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_secrets_inbox (secret_name, secret_hmac, nonce, secret)
                     VALUES ($1, $2, $3, $4)
                     ON CONFLICT (secret_name, secret_hmac) DO NOTHING",
                    &[&name, &hmac, &nonce, &body],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for bundle in changes.received_room_key_bundles {
            let room = bundle.bundle_data.room_id.to_string();
            let user = bundle.sender_user.to_string();
            let (nonce, body) = self.seal_rmp(&bundle)?;
            client
                .execute(
                    "INSERT INTO crypto.crypto_room_key_bundle (room_id, sender_user_id, nonce, bundle)
                     VALUES ($1, $2, $3, $4)
                     ON CONFLICT (room_id, sender_user_id)
                     DO UPDATE SET nonce = EXCLUDED.nonce, bundle = EXCLUDED.bundle",
                    &[&room, &user, &nonce, &body],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for room in changes.room_key_backups_fully_downloaded {
            client
                .execute(
                    "INSERT INTO crypto.crypto_backup_downloaded (room_id) VALUES ($1)
                     ON CONFLICT DO NOTHING",
                    &[&room.to_string()],
                )
                .await
                .map_err(|e| db_err(e, false))?;
        }
        for (room, details) in changes.rooms_pending_key_bundle {
            let room = room.to_string();
            if let Some(details) = details {
                let (nonce, body) = self.seal_rmp(&details)?;
                client
                    .execute(
                        "INSERT INTO crypto.crypto_pending_key_bundle (room_id, nonce, details)
                         VALUES ($1, $2, $3)
                         ON CONFLICT (room_id) DO UPDATE SET nonce = EXCLUDED.nonce, details = EXCLUDED.details",
                        &[&room, &nonce, &body],
                    )
                    .await
                    .map_err(|e| db_err(e, false))?;
            } else {
                client
                    .execute(
                        "DELETE FROM crypto.crypto_pending_key_bundle WHERE room_id = $1",
                        &[&room],
                    )
                    .await
                    .map_err(|e| db_err(e, false))?;
            }
        }
        Ok(())
    }

    fn should_commit(&self, pending: bool) -> bool {
        match self.defer.load(Ordering::SeqCst) {
            DEFER_PAIR => pending,
            DEFER_MIGRATION => false,
            _ => true,
        }
    }

    async fn write_mutation<T>(
        &self,
        pending: bool,
        body: impl AsyncFnOnce(&Client) -> Result<T, StoreError>,
    ) -> Result<T, StoreError> {
        let mut guard = self.begin_mutation().await?;
        let value = match body(&guard.client).await {
            Ok(v) => v,
            Err(e) => {
                self.rollback(&mut guard).await;
                return Err(e);
            }
        };
        if self.should_commit(pending) {
            self.finish(&mut guard).await?;
        }
        Ok(value)
    }

    async fn unpickle_inbound(
        &self,
        nonce: Vec<u8>,
        pickle: Vec<u8>,
        backed_up: bool,
    ) -> Result<InboundGroupSession, StoreError> {
        let mut pickled: matrix_sdk_crypto::olm::PickledInboundGroupSession =
            self.open_rmp(&nonce, &pickle)?;
        pickled.backed_up = backed_up;
        InboundGroupSession::from_pickle(pickled).map_err(|_| StoreError::Unpickle)
    }
}

fn sender_type_id(kind: SenderDataType) -> String {
    (kind as u8).to_string()
}

fn base64_hash(bytes: &[u8]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

fn json_str<'a>(v: &'a serde_json::Value, key: &str) -> Result<&'a str, StoreError> {
    v.get(key)
        .and_then(|s| s.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| StoreError::Other(format!("aurora crypto secret missing {key}")))
}

async fn dial(spec: &ConnectSpec) -> Result<(Client, JoinHandle<()>), StoreError> {
    match spec.tls {
        TlsMode::Off => {
            let (client, conn) = spec
                .config
                .connect(tokio_postgres::NoTls)
                .await
                .map_err(|e| db_err(e, false))?;
            let task = tokio::spawn(async move {
                if let Err(e) = conn.await {
                    warn!(error = %e, "e2ee: postgres crypto connection ended");
                }
            });
            Ok((client, task))
        }
        TlsMode::Verify => {
            let tls = rustls_connector()?;
            let (client, conn) = spec
                .config
                .connect(tls)
                .await
                .map_err(|e| db_err(e, false))?;
            let task = tokio::spawn(async move {
                if let Err(e) = conn.await {
                    warn!(error = %e, "e2ee: postgres crypto connection ended");
                }
            });
            Ok((client, task))
        }
    }
}

fn rustls_connector() -> Result<tokio_postgres_rustls::MakeRustlsConnect, StoreError> {
    let mut roots = rustls::RootCertStore::empty();
    let path = std::env::var("MATRIX_CRYPTO_STORE_SSL_ROOT")
        .unwrap_or_else(|_| "/etc/ssl/certs/rds-global-bundle.pem".to_string());
    if let Ok(file) = std::fs::File::open(&path) {
        let mut reader = std::io::BufReader::new(file);
        let certs = rustls_pemfile::certs(&mut reader);
        for cert in certs {
            let cert = cert.map_err(|e| StoreError::Other(e.to_string()))?;
            roots
                .add(cert)
                .map_err(|_| StoreError::Other("rds ca rejected".into()))?;
        }
    } else {
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    }
    let config = rustls::ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    Ok(tokio_postgres_rustls::MakeRustlsConnect::new(config))
}

// AsyncFnOnce is not stable on our MSRV for the e2ee crate's callers... the
// workspace MSRV is 1.88 and e2ee needs 1.93, so AsyncFn is available. If the
// compiler rejects it, the write path below is the only user.

#[async_trait]
impl CryptoStore for PostgresCryptoStore {
    type Error = StoreError;

    async fn load_account(&self) -> Result<Option<Account>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let marker: Option<Uuid> = guard
            .client
            .query_one(
                "SELECT migration_marker FROM crypto.crypto_meta WHERE id = 1",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?
            .get(0);
        let plain = self.get_kv(&guard.client, KEY_ACCOUNT).await?;
        drop(guard);
        let Some(plain) = plain else {
            if marker.is_some() {
                return Err(StoreError::MissingAccount);
            }
            return Ok(None);
        };
        let pickle = rmp_serde::from_slice(&plain).map_err(|_| StoreError::Unpickle)?;
        let account = Account::from_pickle(pickle).map_err(|_| StoreError::Unpickle)?;
        self.remember_account(&account).await;
        Ok(Some(account))
    }

    async fn load_identity(&self) -> Result<Option<PrivateCrossSigningIdentity>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let Some(plain) = self.get_kv(&guard.client, KEY_IDENTITY).await? else {
            return Ok(None);
        };
        let pickle = rmp_serde::from_slice(&plain).map_err(|_| StoreError::Unpickle)?;
        PrivateCrossSigningIdentity::from_pickle(pickle)
            .map(Some)
            .map_err(|_| StoreError::Unpickle)
    }

    async fn save_changes(&self, changes: Changes) -> Result<(), Self::Error> {
        self.save_changes_real(changes).await
    }

    async fn save_pending_changes(&self, changes: PendingChanges) -> Result<(), Self::Error> {
        self.save_pending_real(changes).await
    }

    async fn save_inbound_group_sessions(
        &self,
        sessions: Vec<InboundGroupSession>,
        _backed_up_to_version: Option<&str>,
    ) -> Result<(), Self::Error> {
        self.save_changes(Changes {
            inbound_group_sessions: sessions,
            ..Changes::default()
        })
        .await
    }

    async fn get_sessions(&self, sender_key: &str) -> Result<Option<Vec<Session>>, Self::Error> {
        self.maybe_renew_for_load().await;
        let keys = self.device_keys().await?;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, pickle FROM crypto.crypto_session WHERE sender_key = $1",
                &[&sender_key],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            let nonce: Vec<u8> = row.get(0);
            let pickle: Vec<u8> = row.get(1);
            let pickled = self.open_rmp(&nonce, &pickle)?;
            out.push(
                Session::from_pickle(keys.clone(), pickled)
                    .map_err(|_| StoreError::AccountUnset)?,
            );
        }
        if out.is_empty() {
            Ok(None)
        } else {
            Ok(Some(out))
        }
    }

    async fn get_inbound_group_session(
        &self,
        room_id: &RoomId,
        session_id: &str,
    ) -> Result<Option<InboundGroupSession>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT room_id, nonce, pickle, backed_up
                 FROM crypto.crypto_inbound_group_session WHERE session_id = $1",
                &[&session_id],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        let stored_room: String = row.get(0);
        if stored_room != room_id.as_str() {
            return Ok(None);
        }
        let nonce: Vec<u8> = row.get(1);
        let pickle: Vec<u8> = row.get(2);
        let backed_up: bool = row.get(3);
        Ok(Some(self.unpickle_inbound(nonce, pickle, backed_up).await?))
    }

    async fn get_withheld_info(
        &self,
        room_id: &RoomId,
        session_id: &str,
    ) -> Result<Option<RoomKeyWithheldEntry>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT nonce, body FROM crypto.crypto_withheld WHERE session_id = $1 AND room_id = $2",
                &[&session_id, &room_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(self.open_json(
            &row.get::<_, Vec<u8>>(0),
            &row.get::<_, Vec<u8>>(1),
        )?))
    }

    async fn get_withheld_sessions_by_room_id(
        &self,
        room_id: &RoomId,
    ) -> Result<Vec<RoomKeyWithheldEntry>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, body FROM crypto.crypto_withheld WHERE room_id = $1",
                &[&room_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(self.open_json(&row.get::<_, Vec<u8>>(0), &row.get::<_, Vec<u8>>(1))?);
        }
        Ok(out)
    }

    async fn get_inbound_group_sessions(&self) -> Result<Vec<InboundGroupSession>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, pickle, backed_up FROM crypto.crypto_inbound_group_session",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(
                self.unpickle_inbound(row.get(0), row.get(1), row.get(2))
                    .await?,
            );
        }
        Ok(out)
    }

    async fn inbound_group_session_counts(
        &self,
        _backup_version: Option<&str>,
    ) -> Result<RoomKeyCounts, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_one(
                "SELECT count(*)::bigint, count(*) FILTER (WHERE backed_up)::bigint
                 FROM crypto.crypto_inbound_group_session",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let total: i64 = row.get(0);
        let backed_up: i64 = row.get(1);
        Ok(RoomKeyCounts {
            total: total as usize,
            backed_up: backed_up as usize,
        })
    }

    async fn get_inbound_group_sessions_by_room_id(
        &self,
        room_id: &RoomId,
    ) -> Result<Vec<InboundGroupSession>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, pickle, backed_up FROM crypto.crypto_inbound_group_session WHERE room_id = $1",
                &[&room_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(
                self.unpickle_inbound(row.get(0), row.get(1), row.get(2))
                    .await?,
            );
        }
        Ok(out)
    }

    async fn get_inbound_group_sessions_for_device_batch(
        &self,
        curve_key: Curve25519PublicKey,
        sender_data_type: SenderDataType,
        after_session_id: Option<String>,
        limit: usize,
    ) -> Result<Vec<InboundGroupSession>, Self::Error> {
        self.maybe_renew_for_load().await;
        let sender = curve_key.to_base64();
        let kind = sender_type_id(sender_data_type);
        let guard = self.writer.lock().await;
        let rows = if let Some(after) = after_session_id {
            guard
                .client
                .query(
                    "SELECT nonce, pickle, backed_up, session_id
                     FROM crypto.crypto_inbound_group_session
                     WHERE sender_key = $1 AND sender_data_type = $2 AND session_id > $3
                     ORDER BY sender_key, sender_data_type, session_id
                     LIMIT $4",
                    &[&sender, &kind, &after, &(limit as i64)],
                )
                .await
        } else {
            guard
                .client
                .query(
                    "SELECT nonce, pickle, backed_up, session_id
                     FROM crypto.crypto_inbound_group_session
                     WHERE sender_key = $1 AND sender_data_type = $2
                     ORDER BY sender_key, sender_data_type, session_id
                     LIMIT $3",
                    &[&sender, &kind, &(limit as i64)],
                )
                .await
        }
        .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(
                self.unpickle_inbound(row.get(0), row.get(1), row.get(2))
                    .await?,
            );
        }
        Ok(out)
    }

    async fn inbound_group_sessions_for_backup(
        &self,
        _backup_version: &str,
        limit: usize,
    ) -> Result<Vec<InboundGroupSession>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, pickle FROM crypto.crypto_inbound_group_session
                 WHERE backed_up = false LIMIT $1",
                &[&(limit as i64)],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(self.unpickle_inbound(row.get(0), row.get(1), false).await?);
        }
        Ok(out)
    }

    async fn mark_inbound_group_sessions_as_backed_up(
        &self,
        _backup_version: &str,
        room_and_session_ids: &[(&RoomId, &str)],
    ) -> Result<(), Self::Error> {
        let ids: Vec<String> = room_and_session_ids
            .iter()
            .map(|(_, s)| (*s).to_string())
            .collect();
        self.write_mutation(false, async move |client| {
            client
                .execute(
                    "UPDATE crypto.crypto_inbound_group_session SET backed_up = true
                     WHERE session_id = ANY($1)",
                    &[&ids],
                )
                .await
                .map_err(|e| db_err(e, false))?;
            Ok(())
        })
        .await
    }

    async fn reset_backup_state(&self) -> Result<(), Self::Error> {
        self.write_mutation(false, async move |client| {
            client
                .execute(
                    "UPDATE crypto.crypto_inbound_group_session SET backed_up = false",
                    &[],
                )
                .await
                .map_err(|e| db_err(e, false))?;
            Ok(())
        })
        .await
    }

    async fn load_backup_keys(&self) -> Result<BackupKeys, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let backup_version = self
            .get_kv(&guard.client, KEY_BACKUP_VERSION)
            .await?
            .map(|b| rmp_serde::from_slice(&b).map_err(|_| StoreError::Unpickle))
            .transpose()?;
        let decryption_key = self
            .get_kv(&guard.client, KEY_RECOVERY)
            .await?
            .map(|b| rmp_serde::from_slice(&b).map_err(|_| StoreError::Unpickle))
            .transpose()?;
        Ok(BackupKeys {
            backup_version,
            decryption_key,
        })
    }

    async fn load_dehydrated_device_pickle_key(
        &self,
    ) -> Result<Option<DehydratedDeviceKey>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let Some(plain) = self.get_kv(&guard.client, KEY_DEHYDRATED).await? else {
            return Ok(None);
        };
        rmp_serde::from_slice(&plain)
            .map(Some)
            .map_err(|_| StoreError::Unpickle)
    }

    async fn delete_dehydrated_device_pickle_key(&self) -> Result<(), Self::Error> {
        self.write_mutation(false, async move |client| {
            client
                .execute(
                    "DELETE FROM crypto.crypto_kv WHERE key = $1",
                    &[&KEY_DEHYDRATED],
                )
                .await
                .map_err(|e| db_err(e, false))?;
            Ok(())
        })
        .await
    }

    async fn get_outbound_group_session(
        &self,
        room_id: &RoomId,
    ) -> Result<Option<OutboundGroupSession>, Self::Error> {
        self.maybe_renew_for_load().await;
        let account = self.static_account().await?;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT nonce, pickle FROM crypto.crypto_outbound_group_session WHERE room_id = $1",
                &[&room_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        let pickle = self.open_json::<matrix_sdk_crypto::olm::PickledOutboundGroupSession>(
            &row.get::<_, Vec<u8>>(0),
            &row.get::<_, Vec<u8>>(1),
        )?;
        OutboundGroupSession::from_pickle(account.device_id, account.identity_keys, pickle)
            .map(Some)
            .map_err(|_| StoreError::Unpickle)
    }

    async fn load_tracked_users(&self) -> Result<Vec<TrackedUser>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query("SELECT user_id, dirty FROM crypto.crypto_tracked_user", &[])
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            let user_id: String = row.get(0);
            let dirty: bool = row.get(1);
            let user_id = UserId::parse(&user_id).map_err(|e| StoreError::Other(e.to_string()))?;
            out.push(TrackedUser { user_id, dirty });
        }
        Ok(out)
    }

    async fn save_tracked_users(&self, users: &[(&UserId, bool)]) -> Result<(), Self::Error> {
        let rows: Vec<(String, bool)> = users.iter().map(|(u, d)| (u.to_string(), *d)).collect();
        self.write_mutation(false, async move |client| {
            for (user_id, dirty) in &rows {
                client
                    .execute(
                        "INSERT INTO crypto.crypto_tracked_user (user_id, dirty) VALUES ($1, $2)
                         ON CONFLICT (user_id) DO UPDATE SET dirty = EXCLUDED.dirty",
                        &[user_id, dirty],
                    )
                    .await
                    .map_err(|e| db_err(e, false))?;
            }
            Ok(())
        })
        .await
    }

    async fn get_device(
        &self,
        user_id: &UserId,
        device_id: &DeviceId,
    ) -> Result<Option<DeviceData>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT nonce, data FROM crypto.crypto_device WHERE user_id = $1 AND device_id = $2",
                &[&user_id.as_str(), &device_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(self.open_rmp(
            &row.get::<_, Vec<u8>>(0),
            &row.get::<_, Vec<u8>>(1),
        )?))
    }

    async fn get_user_devices(
        &self,
        user_id: &UserId,
    ) -> Result<HashMap<OwnedDeviceId, DeviceData>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, data FROM crypto.crypto_device WHERE user_id = $1",
                &[&user_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = HashMap::new();
        for row in rows {
            let device: DeviceData =
                self.open_rmp(&row.get::<_, Vec<u8>>(0), &row.get::<_, Vec<u8>>(1))?;
            out.insert(device.device_id().to_owned(), device);
        }
        Ok(out)
    }

    async fn get_own_device(&self) -> Result<DeviceData, Self::Error> {
        let account = self.static_account().await?;
        self.get_device(&account.user_id, &account.device_id)
            .await?
            .ok_or(StoreError::AccountUnset)
    }

    async fn get_user_identity(
        &self,
        user_id: &UserId,
    ) -> Result<Option<UserIdentityData>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT nonce, data FROM crypto.crypto_identity WHERE user_id = $1",
                &[&user_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(self.open_rmp(
            &row.get::<_, Vec<u8>>(0),
            &row.get::<_, Vec<u8>>(1),
        )?))
    }

    async fn is_message_known(&self, message_hash: &OlmMessageHash) -> Result<bool, Self::Error> {
        self.maybe_renew_for_load().await;
        let encoded = rmp_serde::to_vec_named(message_hash).map_err(|_| StoreError::Unpickle)?;
        let text = base64_hash(&encoded);
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT 1 FROM crypto.crypto_olm_hash WHERE hash = $1",
                &[&text],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(row.is_some())
    }

    async fn get_outgoing_secret_requests(
        &self,
        request_id: &TransactionId,
    ) -> Result<Option<GossipRequest>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT sent_out, nonce, body FROM crypto.crypto_key_request WHERE request_id = $1",
                &[&request_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        let sent_out: bool = row.get(0);
        let mut request: GossipRequest =
            self.open_rmp(&row.get::<_, Vec<u8>>(1), &row.get::<_, Vec<u8>>(2))?;
        request.sent_out = sent_out;
        Ok(Some(request))
    }

    async fn get_secret_request_by_info(
        &self,
        secret_info: &SecretInfo,
    ) -> Result<Option<GossipRequest>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT sent_out, nonce, body FROM crypto.crypto_key_request",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        for row in rows {
            let sent_out: bool = row.get(0);
            let mut request: GossipRequest =
                self.open_rmp(&row.get::<_, Vec<u8>>(1), &row.get::<_, Vec<u8>>(2))?;
            request.sent_out = sent_out;
            if request.info == *secret_info {
                return Ok(Some(request));
            }
        }
        Ok(None)
    }

    async fn get_unsent_secret_requests(&self) -> Result<Vec<GossipRequest>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, body FROM crypto.crypto_key_request WHERE sent_out = false",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            let mut request: GossipRequest =
                self.open_rmp(&row.get::<_, Vec<u8>>(0), &row.get::<_, Vec<u8>>(1))?;
            request.sent_out = false;
            out.push(request);
        }
        Ok(out)
    }

    async fn delete_outgoing_secret_requests(
        &self,
        request_id: &TransactionId,
    ) -> Result<(), Self::Error> {
        let id = request_id.to_string();
        self.write_mutation(false, async move |client| {
            client
                .execute(
                    "DELETE FROM crypto.crypto_key_request WHERE request_id = $1",
                    &[&id],
                )
                .await
                .map_err(|e| db_err(e, false))?;
            Ok(())
        })
        .await
    }

    async fn get_secrets_from_inbox(
        &self,
        secret_name: &SecretName,
    ) -> Result<Vec<Zeroizing<String>>, Self::Error> {
        self.maybe_renew_for_load().await;
        let name = secret_name.to_string();
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, secret FROM crypto.crypto_secrets_inbox WHERE secret_name = $1",
                &[&name],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            let secret: String =
                self.open_json(&row.get::<_, Vec<u8>>(0), &row.get::<_, Vec<u8>>(1))?;
            out.push(Zeroizing::new(secret));
        }
        Ok(out)
    }

    async fn delete_secrets_from_inbox(&self, secret_name: &SecretName) -> Result<(), Self::Error> {
        let name = secret_name.to_string();
        self.write_mutation(false, async move |client| {
            client
                .execute(
                    "DELETE FROM crypto.crypto_secrets_inbox WHERE secret_name = $1",
                    &[&name],
                )
                .await
                .map_err(|e| db_err(e, false))?;
            Ok(())
        })
        .await
    }

    async fn get_room_settings(
        &self,
        room_id: &RoomId,
    ) -> Result<Option<RoomSettings>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT nonce, settings FROM crypto.crypto_room_settings WHERE room_id = $1",
                &[&room_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(self.open_rmp(
            &row.get::<_, Vec<u8>>(0),
            &row.get::<_, Vec<u8>>(1),
        )?))
    }

    async fn get_received_room_key_bundle_data(
        &self,
        room_id: &RoomId,
        user_id: &UserId,
    ) -> Result<Option<StoredRoomKeyBundleData>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT nonce, bundle FROM crypto.crypto_room_key_bundle
                 WHERE room_id = $1 AND sender_user_id = $2",
                &[&room_id.as_str(), &user_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(self.open_rmp(
            &row.get::<_, Vec<u8>>(0),
            &row.get::<_, Vec<u8>>(1),
        )?))
    }

    async fn get_pending_key_bundle_details_for_room(
        &self,
        room_id: &RoomId,
    ) -> Result<Option<RoomPendingKeyBundleDetails>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT nonce, details FROM crypto.crypto_pending_key_bundle WHERE room_id = $1",
                &[&room_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let Some(row) = row else {
            return Ok(None);
        };
        let nonce: Option<Vec<u8>> = row.get(0);
        let details: Option<Vec<u8>> = row.get(1);
        match (nonce, details) {
            (Some(n), Some(d)) => Ok(Some(self.open_rmp(&n, &d)?)),
            _ => Ok(None),
        }
    }

    async fn get_all_rooms_pending_key_bundles(
        &self,
    ) -> Result<Vec<RoomPendingKeyBundleDetails>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let rows = guard
            .client
            .query(
                "SELECT nonce, details FROM crypto.crypto_pending_key_bundle
                 WHERE nonce IS NOT NULL AND details IS NOT NULL",
                &[],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        let mut out = Vec::new();
        for row in rows {
            let nonce: Option<Vec<u8>> = row.get(0);
            let details: Option<Vec<u8>> = row.get(1);
            if let (Some(n), Some(d)) = (nonce, details) {
                out.push(self.open_rmp(&n, &d)?);
            }
        }
        Ok(out)
    }

    async fn has_downloaded_all_room_keys(&self, room_id: &RoomId) -> Result<bool, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT 1 FROM crypto.crypto_backup_downloaded WHERE room_id = $1",
                &[&room_id.as_str()],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(row.is_some())
    }

    async fn get_custom_value(&self, key: &str) -> Result<Option<Vec<u8>>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        self.get_kv(&guard.client, key).await
    }

    async fn set_custom_value(&self, key: &str, value: Vec<u8>) -> Result<(), Self::Error> {
        self.set_custom_real(key, value).await
    }

    async fn remove_custom_value(&self, key: &str) -> Result<(), Self::Error> {
        let key = key.to_owned();
        self.write_mutation(false, async move |client| {
            client
                .execute("DELETE FROM crypto.crypto_kv WHERE key = $1", &[&key])
                .await
                .map_err(|e| db_err(e, false))?;
            Ok(())
        })
        .await
    }

    async fn try_take_leased_lock(
        &self,
        lease_duration_ms: u32,
        key: &str,
        holder: &str,
    ) -> Result<Option<CrossProcessLockGeneration>, Self::Error> {
        let key = key.to_owned();
        let holder = holder.to_owned();
        let now: u64 = MilliSecondsSinceUnixEpoch::now().get().into();
        let expiration = now + u64::from(lease_duration_ms);
        self.write_mutation(false, async move |client| {
            let row = client
                .query_opt(
                    "INSERT INTO crypto.crypto_lease_lock (key, holder, expiration, generation)
                     VALUES ($1, $2, to_timestamp($3::double precision / 1000.0), 1)
                     ON CONFLICT (key) DO UPDATE SET
                        holder = EXCLUDED.holder,
                        expiration = EXCLUDED.expiration,
                        generation = CASE
                            WHEN crypto.crypto_lease_lock.holder = EXCLUDED.holder
                            THEN crypto.crypto_lease_lock.generation
                            ELSE crypto.crypto_lease_lock.generation + 1
                        END
                     WHERE crypto.crypto_lease_lock.holder = EXCLUDED.holder
                        OR crypto.crypto_lease_lock.expiration < to_timestamp($4::double precision / 1000.0)
                     RETURNING generation",
                    &[&key, &holder, &(expiration as f64), &(now as f64)],
                )
                .await
                .map_err(|e| db_err(e, false))?;
            Ok(row.map(|r| {
                let g: i64 = r.get(0);
                g as u64
            }))
        })
        .await
    }

    async fn next_batch_token(&self) -> Result<Option<String>, Self::Error> {
        self.maybe_renew_for_load().await;
        let guard = self.writer.lock().await;
        let Some(plain) = self.get_kv(&guard.client, KEY_NEXT_BATCH).await? else {
            return Ok(None);
        };
        rmp_serde::from_slice(&plain).map_err(|_| StoreError::Unpickle)
    }

    async fn close(&self) -> Result<(), Self::Error> {
        let epoch = self.epoch();
        let mut guard = self.writer.lock().await;
        if !guard.closed && epoch > 0 {
            let _ = guard
                .client
                .execute(
                    "UPDATE crypto.crypto_fence
                     SET lease_until = clock_timestamp(), holder = ''
                     WHERE id = 1 AND holder = $1 AND epoch = $2",
                    &[&self.holder, &epoch],
                )
                .await;
        }
        guard.closed = true;
        guard.task.abort();
        Ok(())
    }

    async fn reopen(&self) -> Result<(), Self::Error> {
        let (client, task) = dial(&self.spec).await?;
        let mut guard = self.writer.lock().await;
        guard.task.abort();
        guard.client = client;
        guard.task = task;
        guard.closed = false;
        guard.txn_open = false;
        drop(guard);
        let row_holder = {
            let guard = self.writer.lock().await;
            let row = guard
                .client
                .query_one("SELECT holder FROM crypto.crypto_fence WHERE id = 1", &[])
                .await
                .map_err(|e| db_err(e, false))?;
            let holder: String = row.get(0);
            holder
        };
        if row_holder == self.holder {
            self.renew_lease().await?;
        } else {
            self.acquire().await?;
        }
        Ok(())
    }

    async fn get_size(&self) -> Result<Option<usize>, Self::Error> {
        Ok(None)
    }
}

impl PostgresCryptoStore {
    async fn save_changes_real(&self, changes: Changes) -> Result<(), StoreError> {
        let defer_commit = self.should_commit(false);
        let mut guard = self.begin_mutation().await?;
        if let Err(e) = self.apply_changes(&guard.client, changes).await {
            self.rollback(&mut guard).await;
            return Err(e);
        }
        if defer_commit {
            self.finish(&mut guard).await?;
        }
        Ok(())
    }

    async fn save_pending_real(&self, changes: PendingChanges) -> Result<(), StoreError> {
        if self.fail_account.swap(false, Ordering::SeqCst) {
            let mut guard = self.writer.lock().await;
            if guard.txn_open {
                self.rollback(&mut guard).await;
            }
            return Err(StoreError::Other("account write failed".into()));
        }
        let account = changes.account;
        let defer_commit = self.should_commit(true);
        let mut guard = self.begin_mutation().await?;
        let mut remembered = None;
        if let Some(account) = account {
            let pickle = account.pickle();
            let bytes = rmp_serde::to_vec_named(&pickle).map_err(|_| StoreError::Unpickle)?;
            if let Err(e) = self.put_kv(&guard.client, KEY_ACCOUNT, &bytes).await {
                self.rollback(&mut guard).await;
                return Err(e);
            }
            remembered = Some(account);
        }
        if defer_commit {
            self.finish(&mut guard).await?;
        }
        if let Some(account) = remembered {
            self.remember_account(&account).await;
        }
        Ok(())
    }

    async fn set_custom_real(&self, key: &str, value: Vec<u8>) -> Result<(), StoreError> {
        let (nonce, sealed) = self.codec.seal(&value)?;
        let key = key.to_owned();
        let defer_commit = self.should_commit(false);
        let mut guard = self.begin_mutation().await?;
        let result = guard
            .client
            .execute(
                "INSERT INTO crypto.crypto_kv (key, nonce, value) VALUES ($1, $2, $3)
                 ON CONFLICT (key) DO UPDATE SET nonce = EXCLUDED.nonce, value = EXCLUDED.value",
                &[&key, &nonce, &sealed],
            )
            .await
            .map_err(|e| db_err(e, false));
        if let Err(e) = result {
            self.rollback(&mut guard).await;
            return Err(e);
        }
        if defer_commit {
            self.finish(&mut guard).await?;
        }
        Ok(())
    }

    /// Count of Olm session rows. Tests use this to prove a rollback.
    pub async fn session_count(&self) -> Result<i64, StoreError> {
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_one("SELECT count(*)::bigint FROM crypto.crypto_session", &[])
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(row.get(0))
    }

    /// Whether the account kv row exists.
    pub async fn account_row_present(&self) -> Result<bool, StoreError> {
        let guard = self.writer.lock().await;
        let row = guard
            .client
            .query_opt(
                "SELECT 1 FROM crypto.crypto_kv WHERE key = $1",
                &[&KEY_ACCOUNT],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(row.is_some())
    }
}

impl PostgresCryptoStore {
    /// Test helper: move the fence to another holder and add `steps` to `commit_seq`.
    pub async fn debug_foreign_advance(&self, steps: i64, op: Uuid) -> Result<(), StoreError> {
        let guard = self.writer.lock().await;
        guard
            .client
            .execute(
                "UPDATE crypto.crypto_fence
                 SET epoch = epoch + 1, holder = 'other', commit_seq = commit_seq + $1,
                     last_op_id = $2, lease_until = clock_timestamp() + interval '1 hour'
                 WHERE id = 1",
                &[&steps, &op],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(())
    }

    /// Test helper: set the migration marker without an account row.
    pub async fn debug_set_marker(&self) -> Result<(), StoreError> {
        let guard = self.writer.lock().await;
        let marker = Uuid::new_v4();
        guard
            .client
            .execute(
                "UPDATE crypto.crypto_meta SET migration_marker = $1, user_id = $2, device_id = $3 WHERE id = 1",
                &[&marker, &"@bot:example.org", &"DEVICE"],
            )
            .await
            .map_err(|e| db_err(e, false))?;
        Ok(())
    }
}
