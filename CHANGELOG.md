# Changelog

Notable changes to Lavoisier. Older release notes are in the git history and in
[`PUBLISHING.md`](PUBLISHING.md).

## [Unreleased]

## [0.18.12] — 2026-11-10

### Matrix crypto store

- `lvz-gw-matrix` can keep the bot's Olm/Megolm state in Postgres (`CryptoStore` on
  `matrix-sdk-crypto` 0.18) when `MATRIX_CRYPTO_STORE_SECRET` is set. SQLite remains
  the store when that variable is unset. Pickle bytes are AES-256-GCM. The key is
  HKDF-SHA256 from `MATRIX_CRYPTO_STORE_KEY`, info `lavoisier-crypto-store-v1`.
  Lookup columns (user, device, room, session, Curve25519 sender key) stay plaintext.
- Every mutating transaction updates `crypto.crypto_fence` in the same transaction
  and increases `commit_seq` by one. A predicate miss rolls back as a stale fence.
  A lost commit reply is reconciled from `(epoch, commit_seq, last_op_id)` and is
  not applied again on the machine that already advanced.
- `Crypto::receive_sync` brackets `receive_sync_changes` so the session write and
  the account write share one Postgres transaction. `since` advances only when that
  pair is known committed. An aborted pair may be re-fed once after reload. A
  committed pair is not re-fed.
- The CLI acquires the fence once before Slack, the schedule, or the memory store.
  `Crypto` uses that lease and does not run the incrementing acquire again. A null
  `migration_marker` copies `<MATRIX_STATE_DIR>/crypto` through the 0.18 read API
  from a `/tmp` copy, inside the marker transaction. `SqliteCryptoStore::open` is
  not pointed at the EFS path. If the marker does not commit, startup does not call
  `OlmMachine::with_store`.
- A Slack `Ok` after a requested handoff does not end the process before the release
  `UPDATE`. Any other Slack completion does. A parked holder does not re-acquire.
  A refreshed waiter claim, and the first lapsed foreign lease inside the load
  grace, keep `/tmp/e2ee-ready`.

### Lattice Phase 4 Port

- The Matrix gateway can dial the in-cluster wasmCloud homeserver
  `http://matrix-cs.wasmcloud.svc.cluster.local:80` with HTTP `Host`
  `matrix-cs.wasmcloud.svc` and server name `davidlee18.dev`. See
  [`docs/PHASE4-PORT.md`](docs/PHASE4-PORT.md).
- Gate G4 is `lav --matrix-probe` (send, then `/sync` read-back). Lattice
  `MATRIX_REGISTER` requires `MATRIX_REGISTRATION_TOKEN`
  (`m.login.registration_token`) and is refused without it.
- `lav --matrix-probe` creates a room when `MATRIX_PROBE_ROOM` is unset or the send
  is refused with `M_FORBIDDEN` / `not in room`, then reads that event back from
  `/sync`. A room that accepts the send is not recreated (`createRoom` is not
  idempotent). The image digest the lattice job runs is rolled separately.
- The ECS spider42 path is unchanged when the lattice variables are unset.

`lavoisier` 0.18.11 → 0.18.12. `lvz-gw-matrix` 0.7.5 → 0.7.6.

## [0.18.11] — 2026-10-22

### Security

- Matrix `MatrixGateway::tools_for` fails closed when `[gateway.matrix_user_tools]` is non-empty
  and the sender is not listed. The turn allowlist is `Some([])`, so no tools are advertised or
  callable — including in a room with no `[gateway.matrix_room_tools]` entry. An unlisted sender
  previously received that room's tool set, or an unconstrained set when the room had no entry.
- An empty or absent member map is unchanged: the room set applies, and a room with no entry stays
  unconstrained. A listed member is still the intersection of the room and member sets when both
  apply, and that member's own set when the room has no entry.
- Scheduled jobs still bypass the member map. A tool job dispatches through the shared registry,
  and a prompt job is submitted with no sender.

`lavoisier` 0.18.10 → 0.18.11. `lvz-gw-matrix` 0.7.4 → 0.7.5. No tag.
