//! Fence tests against a local Postgres. Skipped when the server is not reachable
//! so CI without Postgres still passes. Set nothing: the default URL is
//! `postgres://postgres:postgres@127.0.0.1:5432/postgres`.

use std::sync::Arc;

use matrix_sdk_crypto::olm::Account;
use matrix_sdk_crypto::store::types::{Changes, PendingChanges};
use matrix_sdk_crypto::store::CryptoStore;
use matrix_sdk_crypto::OlmMachine;
use ruma::{device_id, user_id};
use tokio_postgres::NoTls;
use uuid::Uuid;

use super::error::{classify_lost, Reconcile, StoreError};
use super::store::PostgresCryptoStore;
use crate::pg_crypto::migrate_sqlite;

const SCHEMA: &str = r#"
CREATE SCHEMA IF NOT EXISTS crypto;
CREATE TABLE IF NOT EXISTS crypto.crypto_kv (
    key text PRIMARY KEY, nonce bytea NOT NULL, value bytea NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_session (
    session_id text PRIMARY KEY, sender_key text NOT NULL, nonce bytea NOT NULL, pickle bytea NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_inbound_group_session (
    session_id text PRIMARY KEY, room_id text NOT NULL, sender_key text NOT NULL,
    sender_data_type text NOT NULL, backed_up boolean NOT NULL DEFAULT false,
    nonce bytea NOT NULL, pickle bytea NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_outbound_group_session (
    room_id text PRIMARY KEY, nonce bytea NOT NULL, pickle bytea NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_device (
    user_id text NOT NULL, device_id text NOT NULL, nonce bytea NOT NULL, data bytea NOT NULL,
    PRIMARY KEY (user_id, device_id)
);
CREATE TABLE IF NOT EXISTS crypto.crypto_identity (
    user_id text PRIMARY KEY, nonce bytea NOT NULL, data bytea NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_tracked_user (
    user_id text PRIMARY KEY, dirty boolean NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_olm_hash (hash text PRIMARY KEY);
CREATE TABLE IF NOT EXISTS crypto.crypto_key_request (
    request_id text PRIMARY KEY, sent_out boolean NOT NULL, nonce bytea NOT NULL, body bytea NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_withheld (
    session_id text PRIMARY KEY, room_id text NOT NULL, nonce bytea NOT NULL, body bytea NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_room_settings (
    room_id text PRIMARY KEY, nonce bytea NOT NULL, settings bytea NOT NULL
);
CREATE TABLE IF NOT EXISTS crypto.crypto_secrets_inbox (
    secret_name text NOT NULL, secret_hmac bytea NOT NULL, nonce bytea NOT NULL, secret bytea NOT NULL,
    PRIMARY KEY (secret_name, secret_hmac)
);
CREATE TABLE IF NOT EXISTS crypto.crypto_room_key_bundle (
    room_id text NOT NULL, sender_user_id text NOT NULL, nonce bytea NOT NULL, bundle bytea NOT NULL,
    PRIMARY KEY (room_id, sender_user_id)
);
CREATE TABLE IF NOT EXISTS crypto.crypto_backup_downloaded (room_id text PRIMARY KEY);
CREATE TABLE IF NOT EXISTS crypto.crypto_pending_key_bundle (
    room_id text PRIMARY KEY, nonce bytea, details bytea
);
CREATE TABLE IF NOT EXISTS crypto.crypto_lease_lock (
    key text PRIMARY KEY, holder text, expiration timestamptz, generation bigint
);
CREATE TABLE IF NOT EXISTS crypto.crypto_fence (
    id integer PRIMARY KEY CHECK (id = 1),
    epoch bigint NOT NULL, holder text NOT NULL, lease_until timestamptz NOT NULL,
    commit_seq bigint NOT NULL, last_op_id uuid, waiter text, waiter_until timestamptz
);
CREATE TABLE IF NOT EXISTS crypto.crypto_meta (
    id integer PRIMARY KEY CHECK (id = 1),
    schema_version integer NOT NULL, migration_marker uuid, user_id text, device_id text
);
INSERT INTO crypto.crypto_fence (id, epoch, holder, lease_until, commit_seq, last_op_id, waiter, waiter_until)
VALUES (1, 0, '', '-infinity', 0, NULL, NULL, NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO crypto.crypto_meta (id, schema_version, migration_marker, user_id, device_id)
VALUES (1, 1, NULL, NULL, NULL) ON CONFLICT (id) DO NOTHING;
"#;

struct TestDb {
    name: String,
    store: Arc<PostgresCryptoStore>,
}

impl TestDb {
    async fn open() -> Option<Self> {
        let admin = std::env::var("LVZ_PG_URL")
            .unwrap_or_else(|_| "postgres://postgres:postgres@127.0.0.1:5432/postgres".to_string());
        let (client, conn) = match tokio_postgres::connect(&admin, NoTls).await {
            Ok(pair) => pair,
            Err(e) => {
                eprintln!("skip postgres crypto test: {e}");
                return None;
            }
        };
        tokio::spawn(async move {
            let _ = conn.await;
        });
        let name = format!("lvz_{}", Uuid::new_v4().simple());
        if client
            .batch_execute(&format!("CREATE DATABASE {name}"))
            .await
            .is_err()
        {
            eprintln!("skip postgres crypto test: create database failed");
            return None;
        }
        let mut cfg = tokio_postgres::Config::new();
        cfg.host("127.0.0.1");
        cfg.port(5432);
        cfg.user("postgres");
        cfg.password("postgres");
        cfg.dbname(&name);
        let (schema, schema_conn) = match cfg.connect(NoTls).await {
            Ok(pair) => pair,
            Err(e) => {
                eprintln!("skip postgres crypto test: {e}");
                return None;
            }
        };
        tokio::spawn(async move {
            let _ = schema_conn.await;
        });
        if schema.batch_execute(SCHEMA).await.is_err() {
            eprintln!("skip postgres crypto test: schema failed");
            return None;
        }
        drop(schema);
        let store = PostgresCryptoStore::connect_no_tls(cfg, "test-passphrase", "holder-a")
            .await
            .ok()?;
        Some(Self { name, store })
    }

    async fn close(self) {
        let _ = self.store.close().await;
        let admin = std::env::var("LVZ_PG_URL")
            .unwrap_or_else(|_| "postgres://postgres:postgres@127.0.0.1:5432/postgres".to_string());
        if let Ok((client, conn)) = tokio_postgres::connect(&admin, NoTls).await {
            tokio::spawn(async move {
                let _ = conn.await;
            });
            let _ = client
                .batch_execute(&format!("DROP DATABASE IF EXISTS {}", self.name))
                .await;
        }
    }
}

fn session_for(alice: &Account, bob: &mut Account) -> matrix_sdk_crypto::olm::Session {
    bob.generate_one_time_keys(1);
    let otk = *bob.one_time_keys().values().next().unwrap();
    alice
        .create_outbound_session_helper(
            matrix_sdk_crypto::vodozemac::olm::SessionConfig::version_1(),
            bob.identity_keys().curve25519,
            otk,
            false,
            alice.device_keys(),
        )
        .unwrap()
}

#[test]
fn lost_reply_table_includes_a_jump_of_two() {
    let ours = Uuid::new_v4();
    let other = Uuid::new_v4();
    assert_eq!(classify_lost(4, ours, 4, Some(other)), Reconcile::Aborted);
    assert_eq!(classify_lost(4, ours, 5, Some(ours)), Reconcile::Committed);
    assert_eq!(classify_lost(4, ours, 7, Some(ours)), Reconcile::Committed);
    assert_eq!(
        classify_lost(4, ours, 5, Some(other)),
        Reconcile::ForeignCommit
    );
    assert_eq!(
        classify_lost(4, ours, 6, Some(other)),
        Reconcile::DoNotRefeed
    );
}

#[tokio::test]
async fn stale_epoch_rolls_back() {
    let Some(db) = TestDb::open().await else {
        return;
    };
    db.store.acquire().await.unwrap();
    let before = db.store.baseline().await.unwrap();
    db.store
        .debug_foreign_advance(0, Uuid::new_v4())
        .await
        .unwrap();
    let err = db
        .store
        .set_custom_value("k", b"v".to_vec())
        .await
        .unwrap_err();
    assert!(matches!(err, StoreError::StaleFence));
    let after = db.store.baseline().await.unwrap();
    assert_eq!(after.1, before.1);
    assert!(!db.store.get_custom_value("k").await.unwrap().is_some());
    db.close().await;
}

#[tokio::test]
async fn second_acquire_does_not_increment() {
    let Some(db) = TestDb::open().await else {
        return;
    };
    let first = db.store.acquire().await.unwrap();
    let calls = db.store.increment_calls();
    let second = db.store.acquire().await.unwrap();
    assert_eq!(first, second);
    assert_eq!(db.store.increment_calls(), calls);
    assert_eq!(first, 1);
    db.close().await;
}

#[tokio::test]
async fn lost_reply_does_not_take_a_second_step() {
    let Some(db) = TestDb::open().await else {
        return;
    };
    db.store.acquire().await.unwrap();
    let (_epoch, before) = db.store.baseline().await.unwrap();
    db.store.lose_next_commit();
    let err = db
        .store
        .set_custom_value("k", b"v".to_vec())
        .await
        .unwrap_err();
    assert!(matches!(err, StoreError::CommitUnknown));
    let outcome = db.store.reconcile_inflight().await.unwrap();
    assert_eq!(outcome, Reconcile::Committed);
    let (_epoch, after) = db.store.baseline().await.unwrap();
    assert_eq!(after, before + 1);
    db.close().await;
}

#[tokio::test]
async fn foreign_jump_of_two_is_not_refed() {
    let Some(db) = TestDb::open().await else {
        return;
    };
    db.store.acquire().await.unwrap();
    let (_epoch, before) = db.store.baseline().await.unwrap();
    let ours = Uuid::new_v4();
    db.store
        .debug_foreign_advance(2, Uuid::new_v4())
        .await
        .unwrap();
    let outcome = db.store.reconcile_with(before, ours).await.unwrap();
    assert_eq!(outcome, Reconcile::DoNotRefeed);
    let (_epoch, after) = db.store.baseline().await.unwrap();
    assert_eq!(after, before + 2);
    db.close().await;
}

#[tokio::test]
async fn empty_database_does_not_mint_an_account() {
    let Some(db) = TestDb::open().await else {
        return;
    };
    db.store.acquire().await.unwrap();
    let err = db.store.ready_for_machine().await.unwrap_err();
    assert!(matches!(err, StoreError::NoMarker));
    assert!(!db.store.account_row_present().await.unwrap());

    db.store.debug_set_marker().await.unwrap();
    let user = user_id!("@bot:example.org");
    let device = device_id!("DEVICE");
    let err = OlmMachine::with_store(user, device, Arc::clone(&db.store), None).await;
    assert!(err.is_err());
    assert!(!db.store.account_row_present().await.unwrap());
    db.close().await;
}

#[tokio::test]
async fn pair_bracket_rolls_back_then_refeed_writes_once() {
    let Some(db) = TestDb::open().await else {
        return;
    };
    db.store.acquire().await.unwrap();
    let alice = Account::with_device_id(user_id!("@alice:example.org"), device_id!("ALICE"));
    let mut bob = Account::with_device_id(user_id!("@bob:example.org"), device_id!("BOB"));
    let session = session_for(&alice, &mut bob);

    db.store.begin_pair();
    db.store
        .save_changes(Changes {
            sessions: vec![session],
            ..Changes::default()
        })
        .await
        .unwrap();
    db.store.fail_next_account_write();
    let err = db
        .store
        .save_pending_changes(PendingChanges {
            account: Some(alice),
        })
        .await
        .unwrap_err();
    assert!(err.to_string().contains("account write failed"));
    let _ = db.store.end_pair().await;
    assert_eq!(db.store.session_count().await.unwrap(), 0);

    let alice = Account::with_device_id(user_id!("@alice:example.org"), device_id!("ALICE"));
    let mut bob = Account::with_device_id(user_id!("@bob:example.org"), device_id!("BOB"));
    db.store.begin_pair();
    db.store
        .save_changes(Changes {
            sessions: vec![session_for(&alice, &mut bob)],
            ..Changes::default()
        })
        .await
        .unwrap();
    db.store
        .save_pending_changes(PendingChanges {
            account: Some(alice),
        })
        .await
        .unwrap();
    let _ = db.store.end_pair().await;
    assert_eq!(db.store.session_count().await.unwrap(), 1);
    db.close().await;
}

#[tokio::test]
async fn sqlite_copy_roundtrips_plaintext_indexes() {
    let Some(db) = TestDb::open().await else {
        return;
    };
    db.store.acquire().await.unwrap();
    let dir = tempfile_dir();
    let user = user_id!("@bot:example.org");
    let device = device_id!("DEVICE");
    let account = Account::with_device_id(user, device);
    {
        let sqlite = matrix_sdk_sqlite::SqliteCryptoStore::open(dir.path(), Some("efs-pass"))
            .await
            .unwrap();
        sqlite
            .save_pending_changes(PendingChanges {
                account: Some(account),
            })
            .await
            .unwrap();
        sqlite.save_tracked_users(&[(user, true)]).await.unwrap();
        sqlite.close().await.unwrap();
    }
    migrate_sqlite(&db.store, dir.path(), Some("efs-pass"))
        .await
        .unwrap();
    assert!(db.store.migration_marker().await.unwrap().is_some());
    let loaded = db.store.load_tracked_users().await.unwrap();
    assert_eq!(loaded.len(), 1);
    assert_eq!(loaded[0].user_id, user);
    assert!(loaded[0].dirty);
    let account = db.store.load_account().await.unwrap().unwrap();
    assert_eq!(account.user_id(), user);
    assert_eq!(account.device_id(), device);
    db.close().await;
}

fn tempfile_dir() -> tempfile::TempDir {
    tempfile::tempdir().unwrap()
}
