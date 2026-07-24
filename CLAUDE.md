# CLAUDE.md

Guidance for Claude Code working in this repository.

**Lavoisier** (crate `lavoisier`, installed command `lav`) is a modular, token-efficient CLI coding agent in
Rust with a provider-agnostic core (Anthropic + xAI native, plus Google Gemini). The same agent
brain drives the CLI today and a multi-gateway "Hermes" service (HTTP/WebSocket, Matrix) tomorrow.

Companion docs — read the relevant one before working in that area:
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — crate map, the dependency invariants, key design decisions.
- [`ATO.md`](ATO.md) — the adaptive-token-optimisation tuner internals.
- [`bench/README.md`](bench/README.md) — the measured head-to-head vs. the Dirac agent (cost +
  verifiable correctness), the harness, and per-model pricing.

## Status

Complete and live-verified against real `XAI_API_KEY`, `ANTHROPIC_API_KEY`, and `GOOGLE_API_KEY`:
all 16 crates, provider streaming (SSE + xAI gRPC), the agent loop, the token engine, session
memory, the HTTP/Matrix/Slack/cron gateways, AWS packaging (`infra/`), and the ATO learner. `cargo
test`, `cargo clippy --all-targets`, and `cargo fmt --check` are kept green.

The **cron gateway** (`lvz-gw-cron`, `--cron`/`--cron-file`) is an in-process scheduler shaped as a
`Gateway`: it fires `TurnRequest`s on a hand-rolled UTC cron schedule (no `chrono`/`cron` dep) into
the shared agent. It composes with `--serve`/`--serve-matrix` (all gateways run concurrently over one
agent, via `futures::join_all` over each `Gateway::serve`). Every gateway drives the full tool-using
loop, so cron jobs run tools. Each job keeps a fixed session, so it accrues memory across fires. A
**failed fire is retryable** (a rejected `submit` or a mid-turn stream error — a *completed* turn is a
success even if its answer is weak, since that's semantic): `fire` returns a success bool and `run_job`
retries up to `retry_max` times with a fixed `retry_wait`, then waits for the next slot. Global defaults
come from `--cron-retry-max`/`--cron-retry-wait` (env `LVZ_CRON_RETRY_*`, or `[gateway]
cron_retry_max`/`cron_retry_wait`); a `--cron-file` job may override either per-job. The next scheduled
slot is recomputed from "now" *after* retries finish, so a retry's wait never double-fires the next slot.

**Matrix schedules** (`lvz-schedule`, `--schedule-file`) are the cron gateway's in-gateway sibling:
jobs run *inside* the Matrix serve loop (a third `select!` branch alongside `/sync` and shutdown, so
it shares the task with the non-`Send` `crypto`) and **report each outcome to a room**. A job's
`Action` is either a **direct tool call** — dispatched straight through the shared `ToolRegistry`, so
it runs *unconditionally* with no model round-trip and no tokens — or a **prompt turn** (the cron
shape). `lvz-schedule` is a **leaf library** (no gateway→gateway edge); it owns the cron engine
(moved here from `lvz-gw-cron`, which now re-exports `CronSchedule`/`CronError` unchanged), the job
model, and the `ScheduleRegistry` holding live per-job state. Retry mirrors cron
(`--schedule-retry-max`/`-wait`, per-job overridable, next slot recomputed once the chain resolves)
but a pending retry is just another due time, not a blocking sleep. The chat surface is **tools**,
not commands — `schedule_list`/`schedule_status`/`schedule_run` are registered into the agent so
"how's the disk job?" and "run it again" work in natural language; reports are sent in the clear
(like the shutdown notice — a scheduled fire has no inbound event to infer modality from) and their
event ids go into `RecentIds`, so **replying to a report re-engages the bot** via the existing
reply gate. `build_tool_registry` in `lvz-cli` is the composition root: the *same* registry goes to
the agent and to the gateway's scheduler. Job state is in-memory (history resets on restart). The
room report is a *summary* (600-char cap); the **full account goes to stderr** per fire via
`log_verbose` — untruncated output, duration, attempt, tools used, and token usage (kept even when a
turn dies mid-stream, since it still cost tokens). That lives in `lvz-schedule`, not the gateway, so
every frontend gets the same operator log.

The **Matrix gateway auto-accepts room invites** by default (`rooms.invite` → `/join`, deduped across
syncs); disable with `--matrix-no-auto-join` or `[gateway] matrix_auto_join = false`. E2EE is
live-verified end-to-end (cross-implementation, against both Synapse and Continuwuity).

**Matrix auth/identity** (`crates/lvz-gw-matrix/src/lib.rs`): authenticates by **access token**
(`MATRIX_ACCESS_TOKEN`, identity via `/account/whoami`, no login) **or** password (`MATRIX_USER` +
`MATRIX_PASSWORD`), precedence: explicit token > persisted session > password. `MATRIX_STATE_DIR`
(or `[gateway] matrix_state_dir`) persists `session.json` (token + device id) so the **device id is
stable across restarts** (and under `e2ee` the `<dir>/crypto` SQLite store persists the whole crypto
identity — no re-verification after restart). Password login reuses a configured/persisted
`MATRIX_DEVICE_ID`. A **per-sender allowlist** (`MATRIX_ALLOWED_USERS` / `[gateway]
matrix_allowed_users`) gates both plaintext and encrypted paths (enforced pre-decrypt on the
cleartext `sender`); empty ⇒ answer everyone.

**Matrix access control / tool permissions** (same file): a **room allowlist** (`MATRIX_ALLOWED_ROOMS`
/ `[gateway] matrix_allowed_rooms`) combines with the sender allowlist as a **conjunction** (a turn
runs only if sender *and* room are allowed). **Per-room / per-member tool permissions**
(`[gateway.matrix_room_tools]` / `[gateway.matrix_user_tools]`, config-file only) restrict which tools
a turn may use; a room/user absent from a map is unconstrained, and when both apply the effective set
is their **intersection**. The mechanism is a keystone change — a new
`TurnRequest.allowed_tools: Option<Vec<String>>` enforced in the agent's `run_loop` (filters the
advertised `tool_defs` *and* refuses a non-allowed `invoke`); the *policy* (`tools_for(room, sender)`)
stays in the Matrix gateway. A **home room** (`MATRIX_HOME_ROOM` / `[gateway] matrix_home_room`) gets a
plaintext "shutting down" notice on SIGTERM/Ctrl-C — the serve loop races `/sync` against a shutdown
signal and returns `Ok`, and the CLI joins gateways with `select_all` (not `join_all`) so the first to
finish ⇒ a clean whole-process exit. **Startup resilience**: the bind path (`whoami`/`login` and the
baseline `/sync`) retries *transient* failures (5xx/429/transport, classified to `GatewayError::Io`)
with exponential backoff (`with_retry`, 1s→30s cap), mirroring the in-loop `/sync` retry, so a
homeserver that's briefly down while a fresh task boots doesn't kill the gateway; genuine auth/config
errors (4xx ⇒ `GatewayError::Bind`) still surface immediately.

**Matrix engagement & feedback** (Matrix gateway only — Slack unchanged): the bot is **addressable**,
not a firehose. In a **1:1 DM** (room with exactly two joined members, detected via `/joined_members`
and cached per room) it answers every message; in a **group room** it engages only when **@-mentioned**
(authoritative `m.mentions`, MSC3952; plus a textual `@localpart`/MXID-token fallback) **or** when the
message **replies to one of the bot's own recent messages** (tracked in a bounded `RecentIds` of sent
event ids — `message_triggers` is the decision fn; this composes *on top of* the sender/room
allowlists). On an engaged message the gateway gives **immediate feedback**: it reacts 👀 (`m.reaction`,
sent in the clear even in encrypted rooms), shows a **typing** indicator (`PUT …/typing`, re-asserted
on each tool call so it survives long turns), and posts a concise **per-tool-call notice** as the agent
works (`🔧 \`name\` · hint`, the hint pulled from the streamed `Event::ToolUseStart/Delta/End` args via
`tool_hint`). When the turn resolves it **swaps the 👀 for a ✅/❌ outcome reaction** — `finish_reaction`
redacts the transient ack (`PUT …/redact/…`) and reacts ✅ on success or ❌ when the agent errored, the
event stream errored, or the answer failed to send (`react` now returns the reaction's event id so the
ack can be retracted). The shared `handle_message` runs this whole flow; `Reply::{Plain,Encrypted}` is the one
seam that picks plaintext vs E2EE for the outbound messages, so the orchestration stays
modality-agnostic. Mention/reply signals on encrypted messages are read post-decrypt (they live inside
the ciphertext), reusing the same `mentions_bot`/`reply_target`/`message_text` helpers as the plaintext
path so detection is identical.

The **Slack gateway** (`lvz-gw-slack`, `--serve-slack`) is a thin **Socket Mode** client (no inbound
port): `apps.connections.open` → `tokio-tungstenite` WebSocket → `message`/`app_mention` events →
turn → `chat.postMessage`. Auth: `SLACK_APP_TOKEN` (`xapp-`) + `SLACK_BOT_TOKEN` (`xoxb-`). Session
per channel (or thread `thread_ts`); replies thread when triggered in a thread. Same allowlist
mechanism (`SLACK_ALLOWED_USERS` / `[gateway] slack_allowed_users`). Events are acked immediately and
the turn runs spawned off the read loop (keeps acks/pings flowing). Reconnects on `disconnect`/error.

**Persona prompt** (`--persona <PATH>`, default `./PERSONA.md`): a persistent persona/priorities file
layered *above* `DEFAULT_SYSTEM` in `build_agent`, so it sits in the cached prefix. `--no-persona`
disables auto-load.

**Logging** (`--log-level <FILTER>`, env `LVZ_LOG_LEVEL`, or `[log] level`): operator diagnostics are
structured **`tracing`** events on stderr. The `tracing` *facade* is free — already in every build
because axum/tonic/tower/h2 emit through it — so instrumenting library crates costs no new
dependency; only `tracing-subscriber` (at the CLI) is added weight. **The collector is installed in
exactly one place**: `init_logging` in `lvz-cli`. Library crates emit through the facade and **never
install a collector**, which is what keeps `lavoisier`-as-a-library from hijacking a host app's
logging.

The filter is a `RUST_LOG`-style `EnvFilter` directive set. **`DEFAULT_LOG_FILTER` scopes our own
crates to `info` and everything else to `warn`** — the messages these events replaced used to print
unconditionally, so a quiet default would be a silent regression for a long-running gateway; the
scoping is what stops the shared facade from surfacing tonic/hyper chatter. `EnvFilter` has no glob
for `lvz_*`, so the default is an explicit roll-call — **a new crate must be added to it**, or its
`info` events silently vanish. A malformed filter is reported and falls back to the default rather
than silencing the process. The facade is **re-exported as `lavoisier::tracing`** so a private
downstream tools crate can instrument itself without its own `tracing` dependency (its events land
under its own crate name, so reach them with e.g. `--log-level 'my_tools=debug'`).

**What is *not* logging**: the CLI's streamed interface (`[tool]`, `[tool args]`, `[server tool]`,
`[citation]`, `[usage]`, `[done]`), the `--telemetry` summary, the fatal `error:` lines, and the
invalid-filter message stay plain `eprintln!`. They are product output, not diagnostics — never
level-filtered, never suppressible by a log filter (and the invalid-filter message can't route
through the logging it is reporting broken). Answer text stays on **stdout**.

**TOML config** (`--config <PATH>`, else auto `./lavoisier.toml`): `crates/lvz-cli/src/config.rs`
parses `[provider]`/`[agent]`/`[memory]`/`[gateway]` and fills any flag the user left unset
(precedence: CLI/env > file > default; `deny_unknown_fields`). It's a CLI-layer concern — library
crates still take explicit config. **Memory** gained real bounds: `InMemoryStore::with_limits`
(`max_messages` per session, `max_sessions` LRU) plus a durable `FileStore` (JSON per session,
hex-encoded filenames); `[memory] store = "memory"|"file"` selects between them. Sample:
`lavoisier.example.toml`.

The **`lavoisier` crate is lib + bin**: `src/lib.rs` holds everything (CLI, config, gateways) behind
`pub fn main_with(extra_tools: Vec<Arc<dyn Tool>>)` / `pub async fn run_with(..)`, and `src/main.rs`
is a thin shim calling `main_with(Vec::new())`. This is the **custom-tool extension point**: a private
downstream crate depends on the published `lavoisier`, implements `Tool` (re-exported as
`lavoisier::{Tool, ToolOutput, ToolError}`), and calls `main_with(vec![...])` to get the whole CLI
with its own tools registered alongside the built-ins (`build_agent` registers `extra_tools` after the
builtins). Template + compile check: `examples/private-tools/` (a `publish=false` workspace member).
Tools remain compiled-in Rust — there is no dynamic plugin loading.

**Matrix E2EE** is opt-in behind `lvz-gw-matrix`'s `e2ee` feature (and the `lavoisier` crate's
passthrough `e2ee` feature): Olm/Megolm via the crypto-only `matrix-sdk-crypto`, contained to
`crates/lvz-gw-matrix/src/e2ee.rs` (drives an `OlmMachine` over the hand-rolled REST transport, bridging
ruma request types with `try_into_http_request`). The `OlmMachine` is backed by a durable
`matrix-sdk-sqlite` `SqliteCryptoStore` when `MATRIX_STATE_DIR` is set (`OlmMachine::with_store`,
`bundled` SQLite so no runtime libsqlite3; optional at-rest passphrase via `MATRIX_CRYPTO_STORE_KEY`),
else in-memory. On first init `Crypto::new` also **bootstraps the bot's cross-signing identity once**
(`OlmMachine::bootstrap_cross_signing`, gated on `cross_signing_status().is_complete()` so it never
re-uploads — a second upload would need UIA the token-auth bot can't do; relies on MSC3967 waiving UIA
for the first upload) so peers see a signed identity, not an unverified standalone device; best-effort
(logged, never fatal). **Off by default** — the default build stays minimal-dep and MSRV-1.88; the feature
requires Rust ≥ 1.93. Crypto round-trip is unit-tested where offline-testable; full live verification
needs a homeserver (like the rest of the Matrix gateway).

Remaining/deferred: full **module-qualified** symbol resolution (the cross-file graph is scope-aware
but not import-path resolved — fine for the radius knob); an unambiguous line-range/occurrence edit
path so weaker models can do repeated-symbol renames (today they're steered to `sed`); live
verification of `lvz-claude-cli` (needs a subscription) and the Matrix gateway (needs a homeserver);
and the actual AWS `terraform apply` (artifacts ship local-verified — run `infra/README.md`).

## Architecture invariants (do not violate)

The whole design keeps one agent core reusable by every frontend. Full detail in
[`ARCHITECTURE.md`](ARCHITECTURE.md); the rules in one line each:

1. **`lvz-protocol` is the keystone** — defines the `Event` stream + `Provider`/`Tool`/`Gateway`/
   `Tuner`/`Capabilities` contracts, with zero provider/gateway deps.
2. **Dependencies point inward only** — adapters and gateways depend on the core, never the reverse;
   each adapter is the only place its wire format maps to `Event`.
3. **Abstract at the semantic layer** — gRPC vs SSE vs OpenAI-compat is contained behind the `Event`
   stream + `Capabilities`; gRPC is never an architectural assumption (Anthropic has none).

## Token efficiency is the central design lever

The optimisation metric is **cost-weighted total task tokens across all round-trips**
(`Usage::cost(&CostWeights)` — input·1 + output·~5 + cache-write·1.25 + cache-read·0.1), never
per-call input. Both the `--budget` ceiling and the ATO objective use it, so caching and output cost
register. Mechanisms, all live:

- **Prompt caching** (Anthropic native Messages API + `cache_control`) on stable prefixes, ordered
  immutable → stable → volatile. A **rolling 4th breakpoint on the conversation tail** bills the
  growing transcript as `cache_read`, not fresh input. Prior-turn thinking is dropped on resend
  (zero tokens < cache-read). 1-hour TTL on the immutable prefix under `--serve`.
- **Cache-aware repo-skeleton prefix** (`--repo-skeleton`) — whole-repo tree-sitter outline, built
  once and relevance-ranked against the task, pinned in the cached prefix.
- **File-skeleton extraction** + an **AST-resolved, scope-aware symbol-dependency graph** driving the
  skeleton-radius knob `N`; **hash-anchored edits** and **diffs** over full-file rewrites.
- **Multi-file batching** (`read_files`/`outline_files`/`edit_files`), **`find_references`** (one
  AST-precise call for a complete reference set), **`batch_edit`** (independent mechanical edits via
  the provider's discounted batch API; Anthropic/Google only, on by default).
- **History compaction**, staleness eviction, dedup, context-budget eviction; **thinking-budget
  dial** (mechanical archetypes think less); model routing (cheap-model-first, advisor+executor).
- **ATO** (`--tune` ε-greedy / `--tune-bayes` Thompson) tunes the knobs against a real success
  signal (`--verify-cmd`); convergence levers (`--in-loop-verify`, `--no-progress-limit`,
  `--budget-awareness`) are on by default. The **budget-fixture CI loop** (`lvz-context/tests/
  budget.rs`) gates skeleton-size regressions against committed token ceilings.

## Conventions

- **Rust** Cargo workspace; edition 2021, MSRV 1.88 (pinned in the root `Cargo.toml`). Correctness
  via sum types + exhaustive `match`.
- Async **tokio**; HTTP **reqwest**; JSON **serde**/**serde_json**; gRPC **tonic**+**prost** (xAI
  codegen from vendored `crates/lvz-xai/proto/`).
- Scripts **zsh**; local container shells **Podman** (not Docker).
- Keep dependencies minimal; no heavyweight agent frameworks, no SDKs. The stale Anthropic-native
  crates (`anthropic*`, `clust`, `misanthropy`) are **not** to be used — hand-roll thin `reqwest`
  adapters to retain caching + thinking.
- **Providers in scope: Anthropic + xAI + Google Gemini, native.** OpenAI and others are out of
  scope. A Discord gateway is **out of scope** (do not build it).
- Secrets: read from env / AWS Secrets Manager at runtime; never commit keys.
- **GitHub Actions are pinned to a full commit SHA**, never a tag/branch (`uses: owner/action@<40-char-sha>
  # vX.Y.Z`) — supply-chain hardening; the trailing comment records the human-readable version. When
  adding or bumping an action, resolve the tag to its commit (`gh api repos/<owner>/<repo>/commits/<tag>
  --jq .sha`), pin that, and update the comment. Prefer versions on the current Node runtime to avoid
  deprecation warnings. `dtolnay/rust-toolchain` is pinned to a `master` SHA **with** an explicit
  `toolchain:` input (the `@stable` ref-name signal is lost once pinned).
- License: **MIT** (`LICENSE`).

## Gotchas

- **`lvz-xai`'s gRPC bindings are committed** (`crates/lvz-xai/src/generated/xai_api.rs`, included
  by `src/grpc.rs`), so an ordinary build — including docs.rs and `cargo install` — needs **no
  `protoc`**. `build.rs` regenerates them only under `LVZ_XAI_REGEN=1` (which needs
  `protoc`/`brew install protobuf`), e.g. after bumping the vendored proto. Pin + update procedure
  in `crates/lvz-xai/proto/VENDOR.md`.
- `lvz-context` tree-sitter grammar/core ABI versions are pinned in its `Cargo.toml` — bump together.
- The budget loop's committed per-fixture ceilings (`lvz-context/tests/budget.rs`) are the baseline;
  update them deliberately when skeleton output legitimately changes.
- Gemini 3 attaches a `thoughtSignature` to each functionCall that must be echoed on resend (else
  400); `lvz-google` round-trips it through the opaque tool-call id, contained to the adapter.
- **Inside a `tracing` macro, fully qualify `serde_json::Value`.** The macro expansion brings
  `tracing::field::Value` (a *trait*) into scope, so a bare `Value::as_str` path resolves to it and
  fails with `expected a type, found a trait` — even though the identical expression compiles fine
  elsewhere in the same file. Write `.and_then(serde_json::Value::as_str)` (see
  `lvz-gw-slack/src/lib.rs:149`). Only the `Value::method` *path* form breaks; passing a `Value`
  as a field value is fine. Bites any crate that parses JSON and logs — i.e. the gateways.
- **Add every new crate to `DEFAULT_LOG_FILTER`** (`lvz-cli/src/lib.rs`). `EnvFilter` has no glob,
  so "our crates at `info`, dependencies at `warn`" is an explicit 16-crate roll-call. A crate
  missing from it silently falls to the `warn` floor and its `info!` milestones vanish — no error,
  just absent output. A unit test guards the list. Directives match the event target by **prefix**,
  so `lvz_gw_matrix=info` also covers `lvz_gw_matrix::e2ee` (also unit-tested).

## Commands

```sh
cargo build                          # build all crates
cargo test                           # all tests
cargo test -p <crate> [name]         # one crate / one test
cargo clippy --all-targets           # lints (zero-warning)
cargo fmt                            # format

# Run the CLI (crate `lavoisier` in crates/lvz-cli):
XAI_API_KEY=…       cargo run -p lavoisier -- "prompt"                 # one streaming turn (xAI gRPC default)
ANTHROPIC_API_KEY=… cargo run -p lavoisier -- --provider anthropic "…"
XAI_API_KEY=…       cargo run -p lavoisier -- --agent "edit task"      # tool-using agent loop
XAI_API_KEY=…       cargo run -p lavoisier -- --serve 127.0.0.1:8080   # HTTP/WS gateway + session memory
```

Key flags: `--agent`, `--serve`/`--serve-matrix`, `--provider xai|anthropic|google|claude-cli`,
`--model`, `--thinking`, `--budget`, `--repo-skeleton`, `--tune`/`--tune-bayes` + `--verify-cmd`,
`--cheap-model`/`--advisor-model`, `--no-batch-edit`, `--telemetry`, gateway `--api-key`/
`--rate-limit`. **Efficiency-by-default: accuracy levers are opt-in** — `--require-edit` (don't finish
an edit task with no change) and `--verify-and-fix` (don't finish while `--verify-cmd` fails, bounded).
Full list and env vars in `README.md`. Deploy: `infra/README.md`.
