# Lavoisier gaps to close before it can replace `hermes-agent`

> **Status (2026-06-19): all four items implemented and green** (`cargo fmt`/`clippy
> --all-targets`/`test`, plus `--features e2ee` clippy + test). Item 1 (token/whoami auth + stable,
> persistable device id), item 2 (durable SQLite crypto store via `matrix-sdk-sqlite`, `MATRIX_STATE_DIR`
> /`MATRIX_CRYPTO_STORE_KEY`), and item 3 (`MATRIX_ALLOWED_USERS` allowlist over plaintext + E2EE) all
> shipped in `lvz-gw-matrix` 0.3.0. Item 5 is the new `lvz-gw-slack` crate (Socket Mode, `--serve-slack`).
> Wired through `lvz-cli` 0.5.0 (flags + `[gateway]` config). **Live verification still pending**: the
> restart-stability / decrypt-after-restart acceptance checks need a throwaway homeserver, and the
> Slack path needs a real Socket Mode app (offline parsing/logic is unit-tested). Original gap analysis
> below, for reference.


Work items for the **Lavoisier** repo (`DavidLee18/lavoisier`), derived from a gap analysis of
this infra against `lavoisier` 0.4.0 / `lvz-gw-matrix` 0.2.2 (`main`). Each item blocks a drop-in
swap of the `hermes-agent` ECS service. Source citations are `path:line` in the Lavoisier repo
unless noted as (infra) for this repo.

Not included here: the **builder offload** (gap 4) — that's a *downstream* custom tool registered
via `main_with`, not a crate change, so it stays in the infra-side image and needs no Lavoisier
work. Slack (gap 5) is optional for the current swap but tracked below for parity.

---

## 1. Matrix gateway: support access-token auth and a stable device identity

**Problem.** The gateway can only authenticate by **password login** and logs in fresh on every
start, so (a) an existing bot access token can't be reused, and (b) the Matrix `device_id` changes
on every restart. (b) is a hard prerequisite for persistent E2EE (item 2).

**Current behavior.**
- `MatrixGateway::from_env()` requires `MATRIX_HOMESERVER` / `MATRIX_USER` / `MATRIX_PASSWORD`
  — `crates/lvz-gw-matrix/src/lib.rs:68-77`.
- `serve_loop` calls `self.login()` every start, POSTing `m.login.password` and accepting whatever
  `device_id` the server mints — `lib.rs:84-111`, `lib.rs:268-269`.
- No access-token path; no way to pin/reuse a device id.

**Why it matters.** A long-lived ECS/Fargate bot is usually provisioned once with an access token
in secrets (this infra stores `hermes/matrix_access_token`, not a password — infra `main.tf:17`,
`ecs.tf:53`). Today that token is unusable. And every restart = new password login = **new device**;
for E2EE that means a fresh crypto identity each restart (clients must re-verify; Megolm sessions lost).

**Proposed solution.**
- [ ] If `MATRIX_ACCESS_TOKEN` is set, skip `/login`; resolve `user_id`/`device_id` via
      `GET /_matrix/client/v3/account/whoami`. Keep password login as fallback.
- [ ] On password login, support a configured/persisted `MATRIX_DEVICE_ID` so re-logins reuse the
      same device; persist the issued `{access_token, device_id}` and restore on next start.
- [ ] Document precedence: explicit token > persisted session > password login.

**Acceptance.**
- [ ] Starts with only `MATRIX_HOMESERVER` + `MATRIX_ACCESS_TOKEN` (no password) and answers in a room.
- [ ] `user_id`/`device_id` resolved without a password login.
- [ ] `device_id` stable across restarts on the password path.

**Notes.** Share one on-disk "matrix session" artifact (token + device id + crypto store, item 2)
under a single configurable directory.

---

## 2. Matrix E2EE: persist the crypto store across restarts

**Problem.** With `--features e2ee` the `OlmMachine` is **in-memory** and discarded on exit, so the
bot loses its entire crypto identity (device keys, Olm/Megolm sessions, tracked devices) on every
restart. No option to persist it to disk.

**Current behavior.**
- `Crypto::new` builds the machine with `OlmMachine::new(&user, &device)`
  — `crates/lvz-gw-matrix/src/e2ee.rs:79`.
- Module doc is explicit: *"builds an **in-memory** `OlmMachine`"* — `e2ee.rs:7`.
- No store path / `matrix-sdk-sqlite` / config knob anywhere (`config.rs` `[gateway]` has none).

**Why it matters.** On any restart the bot mints a new device, re-uploads keys, **loses all inbound
Megolm sessions** (can't decrypt messages encrypted to its old device), and forces peers to re-verify
("unable to decrypt" / unverified-device warnings). The agent's other state already persists on EFS;
the crypto identity is expected to persist alongside it but currently can't, making E2EE single-session.

**Proposed solution.**
- [ ] Back the machine with a durable store (e.g. `matrix-sdk-sqlite` crypto store, or the
      `matrix-sdk-crypto` store trait over SQLite/sled) opened at a configured directory.
- [ ] Add config/env: `[gateway] crypto_store = "/path"` / `MATRIX_CRYPTO_STORE`, with optional
      passphrase `MATRIX_CRYPTO_STORE_KEY` for encryption-at-rest.
- [ ] Reuse the stable `device_id` from item 1 so the store matches the logged-in device.

**Acceptance.**
- [ ] Configured store path is created if absent, reused if present.
- [ ] After a full restart with the same store + device id, the bot decrypts in an existing room
      **without** re-verification.
- [ ] Account keys / device id stable across restarts (no new device).
- [ ] Clear error (or documented fallback) if the store is unreadable.
- [ ] Docs note MSRV: e2ee already needs Rust ≥ 1.93 (`crates/lvz-cli/Cargo.toml:46-50`).

**Notes.** Depends on item 1. Ideally token + device id + crypto store live under one directory so a
single persistent volume captures the whole Matrix identity.

---

## 3. Matrix gateway: per-user sender allowlist

**Problem.** The gateway answers **every** text message from any sender but itself, in any room it's
in. No way to restrict who can drive the agent — risky for a tool-using agent with shell/file access.

**Current behavior.**
- `extract_messages` collects every `m.room.message`/`m.text`, skipping only the bot's own messages;
  each triggers an agent turn — `crates/lvz-gw-matrix/src/lib.rs:404-424`, serve loop `lib.rs:343-349`.
- No sender filter; nothing reads an allowlist. Only adjacent controls are room-level
  (`matrix_auto_join`, `lib.rs:476-481`) and homeserver policy (closed registration / federation off).

**Why it matters.** The agent exposes shell, file edits, and (downstream) build/deploy tools over
shared state. Any account in a shared room can command it. The Hermes deployment scoped this with
`MATRIX_ALLOWED_USERS = "@a…,@b…,@c…"` (infra `ecs.tf:42`); Lavoisier has no equivalent.

**Proposed solution.**
- [ ] Config/env: `[gateway] matrix_allowed_users = ["@a:hs", ...]` / `MATRIX_ALLOWED_USERS`
      (comma-separated).
- [ ] In `extract_messages` **and** the E2EE decrypt path (`lib.rs:352-361`), drop messages whose
      `sender` isn't allowlisted when a list is configured.
- [ ] Empty/unset = today's "answer everyone" (backwards compatible).
- [ ] Apply uniformly to plaintext and encrypted so encryption can't bypass it.

**Acceptance.**
- [ ] With the list set, non-listed senders are ignored (no turn, no reply) in plaintext + encrypted rooms.
- [ ] With it unset, behavior unchanged.
- [ ] Unit test for allowed/denied senders, mirroring existing `extract_messages` tests (`lib.rs:501-522`).
- [ ] Documented in `lavoisier.example.toml` + README.

**Notes.** Consider a shared allowlist abstraction reusable by a future Slack gateway (item 5).

---

## 5. New Slack gateway (Socket Mode) implementing the `Gateway` trait

> Optional for the current Matrix-only swap; tracked for parity with the old Hermes service.

**Problem.** Lavoisier ships HTTP / Matrix / cron gateways but no **Slack** gateway. Deployments
replacing a Slack-connected bot can't migrate without dropping Slack.

**Current behavior.** Gateways: `lvz-gw-http`, `lvz-gw-matrix`, `lvz-gw-cron`, wired in the CLI serve
path (`crates/lvz-cli/src/lib.rs:434-491`). No Slack transport, no `SLACK_*` hooks.

**Why it matters.** The Hermes service served Slack alongside Matrix (`SLACK_BOT_TOKEN` /
`SLACK_APP_TOKEN`, Socket Mode, egress-only — infra `ecs.tf:55-56`). Slack-first teams need parity.

**Proposed solution.** Add `lvz-gw-slack` implementing `lvz_protocol::Gateway`, mirroring the Matrix
gateway (thin client, minimal deps, session-per-conversation):
- [ ] Transport: Slack **Socket Mode** (WebSocket via `apps.connections.open`) — no inbound port.
      Auth from `SLACK_APP_TOKEN` (`xapp-…`) + `SLACK_BOT_TOKEN` (`xoxb-…`).
- [ ] Inbound: `message` / `app_mention` events; ignore own + non-text events.
- [ ] Sessions keyed by channel (or thread `thread_ts`) via `lvz-memory`, as Matrix keys on `room_id`
      (`lib.rs:221-248`).
- [ ] Outbound: `chat.postMessage` (thread the reply when triggered in a thread).
- [ ] Access control: `SLACK_ALLOWED_USERS` allowlist (share the item-3 mechanism).
- [ ] CLI: `--serve-slack` / `[gateway] serve_slack`, concurrent with other gateways
      (`lib.rs:490-491`).

**Acceptance.**
- [ ] `--serve-slack` connects via Socket Mode and answers a DM / mention.
- [ ] Per-channel/thread session continuity.
- [ ] Ignores own + non-text events.
- [ ] Optional `SLACK_ALLOWED_USERS` gating.
- [ ] Runs alongside `--serve` / `--serve-matrix` in one process.
- [ ] Minimal-dependency footprint (no heavyweight Slack SDK if avoidable).

**Notes.** Scope = inbound chat → turn → text reply. Blocks/attachments, reactions, file uploads are
follow-ups.

---

### Dependency order
1 → 2 (stable device id is a prerequisite for a persistent crypto store). 3 and 5 are independent;
3's allowlist abstraction is worth sharing with 5.
