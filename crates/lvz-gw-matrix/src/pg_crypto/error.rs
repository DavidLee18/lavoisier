//! Store errors. `StaleFence` means the statement finished and rolled back.
//! `CommitUnknown` means the commit reply was lost. Neither is retried on the
//! same [`OlmMachine`](matrix_sdk_crypto::OlmMachine).

use std::fmt;

use matrix_sdk_crypto::store::CryptoStoreError;

/// Failure from the Postgres crypto store.
#[derive(Debug)]
pub enum StoreError {
    /// The fence predicate matched nothing. The transaction was rolled back.
    StaleFence,
    /// `COMMIT` was sent and the driver returned an I/O error, or a test lost the reply.
    CommitUnknown,
    /// Marker is set and the account pickle is missing or will not unpickle.
    MissingAccount,
    /// `crypto_meta.migration_marker` is null. Do not call `with_store`.
    NoMarker,
    /// Pickle bytes did not decrypt or did not deserialize.
    Unpickle,
    /// The account row has not been loaded, so a session cannot be restored.
    AccountUnset,
    /// The store was closed.
    Closed,
    /// A Postgres error whose outcome is known (the statement failed).
    Db(tokio_postgres::Error),
    /// Any other failure. The string is safe to log: no pickle, passphrase, or secret JSON.
    Other(String),
}

impl fmt::Display for StoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::StaleFence => write!(f, "stale fence"),
            Self::CommitUnknown => write!(f, "commit outcome unknown"),
            Self::MissingAccount => write!(f, "account pickle missing or failed to unpickle"),
            Self::NoMarker => write!(f, "aurora crypto store has no migration marker"),
            Self::Unpickle => write!(f, "unpickle failed"),
            Self::AccountUnset => write!(f, "account unset"),
            Self::Closed => write!(f, "crypto store closed"),
            Self::Db(e) => write!(f, "postgres crypto store: {e}"),
            Self::Other(s) => write!(f, "{s}"),
        }
    }
}

impl std::error::Error for StoreError {}

impl From<StoreError> for CryptoStoreError {
    fn from(value: StoreError) -> Self {
        match value {
            StoreError::Unpickle => CryptoStoreError::UnpicklingError,
            StoreError::AccountUnset | StoreError::MissingAccount => CryptoStoreError::AccountUnset,
            other => CryptoStoreError::backend(other),
        }
    }
}

/// How a lost commit reply reads once the fence row is visible again.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reconcile {
    /// `last_op_id` is ours. Do not ratchet again on the old machine.
    Committed,
    /// `commit_seq` is unchanged. The caller may re-feed after reload.
    Aborted,
    /// Exactly one foreign commit. Do not re-feed.
    ForeignCommit,
    /// `commit_seq >= before + 2` and the op id is not ours. Do not re-feed.
    DoNotRefeed,
    /// The fence `SELECT` failed, or the row does not match a known case.
    StillUnknown,
}

/// Classify a fence read against the `(commit_seq, op_id)` taken before `BEGIN`.
pub fn classify_lost(
    before_seq: i64,
    op_id: uuid::Uuid,
    seq: i64,
    last_op: Option<uuid::Uuid>,
) -> Reconcile {
    if last_op == Some(op_id) {
        if seq > before_seq + 1 {
            tracing::error!(
                before_seq,
                seq,
                "e2ee: fence commit_seq jumped while last_op_id is still ours"
            );
        }
        return Reconcile::Committed;
    }
    if seq == before_seq {
        return Reconcile::Aborted;
    }
    if seq == before_seq + 1 {
        return Reconcile::ForeignCommit;
    }
    if seq >= before_seq + 2 {
        return Reconcile::DoNotRefeed;
    }
    Reconcile::StillUnknown
}

pub(crate) fn db_err(err: tokio_postgres::Error, commit_was_sent: bool) -> StoreError {
    if commit_was_sent && err.is_closed() {
        StoreError::CommitUnknown
    } else {
        StoreError::Db(err)
    }
}
