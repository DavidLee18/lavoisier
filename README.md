# Lavoisier

A modular, **token-efficient** CLI coding agent in Rust with a provider-agnostic core
(**Anthropic + xAI native, plus Google Gemini**). The same agent brain drives the CLI today and a
multi-gateway "Hermes" service (HTTP/WebSocket, Matrix) tomorrow.

> Status: **complete** — provider streaming over SSE **and** xAI gRPC, the agent loop, fs/shell/
> context tools, the token-efficiency engine, session memory, gateways, AWS packaging, and the
> adaptive-token-optimisation learner are all implemented and tested. Live-verified against real
> `XAI_API_KEY`, `ANTHROPIC_API_KEY`, and `GOOGLE_API_KEY`. See [`ARCHITECTURE.md`](ARCHITECTURE.md)
> for the design.

## Why

LLM coding workloads are token-bound, and **the optimisation metric is total task tokens across
all round-trips, never per-call input.** Lavoisier treats token efficiency as a first-class design
goal at every layer:

- **Prompt caching** on stable prefixes via Anthropic's native Messages API (`cache_control:
  ephemeral`) — context is ordered immutable → stable → volatile so the cached prefix stays warm.
- **Cache-aware repo-skeleton prefix** — a tree-sitter outline of the whole repo, built once and
  pinned in the cached prefix, so the model has whole-repo structure without per-task reads.
- **File-skeleton extraction** — send signatures, elide bodies; Python docstrings kept.
- **AST-resolved symbol-dependency graph** drives the skeleton-radius knob `N` ("include full
  bodies for symbols within `N` hops of the edit target") — references resolved from identifier
  nodes, scope-aware (string/comment mentions and shadowing locals don't create edges).
- **Hash-anchored edits** and **token-efficient diffs** instead of re-emitting whole files.
- **Multi-file batching** — `read_files`/`outline_files` fetch several files in one round-trip.
- **Adaptive Token Optimisation (ATO)** — an online tuner that learns per-archetype knob settings
  from realised outcomes (ε-greedy hill-climb or Thompson sampling), gated by a real success signal.
- **History compaction**, context-budget eviction, and model routing (cheap-model-first, advisor+
  executor) for long tasks.
- A **budget-fixture CI loop** that gates skeleton-size regressions against committed token ceilings.

**Two modes.** By default Lavoisier is **efficiency-first** — lean context, caching, minimal
round-trips. When you have a real test gate, opt into **accuracy-mode** (`--verify-cmd <tests>
--require-edit --verify-and-fix`): the agent iterates until the tests pass. In the measured
head-to-head this matches or beats the comparison agent on task completion *while costing less per
completed task* — see [`bench/README.md`](bench/README.md) (cost + reproducible correctness via
`bench/verify.zsh`). Tuner internals: [`ATO.md`](ATO.md).

## Architecture

A Cargo workspace, trait-segmented so the agent core never depends on a wire protocol or a frontend.
The keystone is `lvz-protocol`; dependencies point inward only. See [`ARCHITECTURE.md`](ARCHITECTURE.md)
for the crate map, the invariants, and the key design decisions.

## Install

The crate is `lavoisier`; the installed command is **`lav`**.

```sh
cargo binstall lavoisier   # prebuilt binary, no toolchain/protoc needed
cargo install lavoisier    # from source (needs protoc: brew install protobuf)

# Opt-in Matrix end-to-end encryption (Olm/Megolm); needs Rust >= 1.93:
cargo install lavoisier --features e2ee
```

## Quickstart (from source)

Requires a recent Rust toolchain (**edition 2021, MSRV 1.88**) and **`protoc`**
(`brew install protobuf`) — `lvz-xai`'s build compiles the vendored xAI protos.

```sh
cargo build

# One streaming turn (no tools). xAI uses gRPC by default (XAI_TRANSPORT=grpc):
XAI_API_KEY=…       cargo run -p lavoisier -- "explain a monad in one sentence"
ANTHROPIC_API_KEY=… cargo run -p lavoisier -- --provider anthropic "…"

# The multi-step agent with filesystem + shell + context tools:
XAI_API_KEY=… cargo run -p lavoisier -- --agent "add a doc comment to the add() fn in src/lib.rs"

# Serve the shared agent as an HTTP/WebSocket gateway (+ in-memory session continuity):
XAI_API_KEY=… cargo run -p lavoisier -- --serve 127.0.0.1:8080

# Run scheduled agent turns (in-process cron, UTC) — standalone or alongside --serve/--serve-matrix:
XAI_API_KEY=… cargo run -p lavoisier -- --cron "*/30 9-17 * * 1-5 summarise new CI failures"

# Chat gateways: Matrix (one room per session) and Slack (Socket Mode, one channel/thread per session):
ANTHROPIC_API_KEY=… cargo run -p lavoisier -- --serve-matrix
ANTHROPIC_API_KEY=… cargo run -p lavoisier -- --serve-slack
```

Gateways compose: `--serve`, `--serve-matrix`, `--serve-slack`, and `--cron`/`--cron-file` all drive
**one** shared agent and run concurrently in the same process, so a single low-resource host can
answer HTTP/Matrix/Slack requests *and* fire scheduled jobs. Every gateway — cron included — drives
the full tool-using agent loop, so scheduled jobs can read, edit, and run commands just like an
interactive turn. Each cron job keeps a fixed session, so it accrues memory across fires (like the
Matrix per-room / Slack per-channel sessions).

**Persona / priorities.** Point `--persona <PATH>` at a file (or drop a `PERSONA.md` in the working
dir) to give a long-running gateway a stable identity and standing instructions: it's layered above
the operating system-prompt and rides in the cached prefix, so it costs almost nothing per turn.

**Matrix auth & identity.** The Matrix gateway authenticates with either an **access token**
(`MATRIX_ACCESS_TOKEN` — identity resolved via `whoami`, no login) or **password**
(`MATRIX_USER` + `MATRIX_PASSWORD`). Set `MATRIX_STATE_DIR` to persist the session (token + device
id) and keep a **stable device identity across restarts** — a prerequisite for durable E2EE. Restrict
who can drive the bot with `MATRIX_ALLOWED_USERS` (or `[gateway] matrix_allowed_users`).

**Matrix access control & tool permissions.** Three layers, all opt-in and applied uniformly to
plaintext and encrypted rooms:
- **Allowed rooms** — `MATRIX_ALLOWED_ROOMS` (or `[gateway] matrix_allowed_rooms`) limits the rooms
  the bot acts in. Combined with the sender allowlist as a **conjunction**: a turn runs only if the
  sender is allowed *and* the room is allowed — so an allowed user is answered only inside allowed rooms.
- **Per-room / per-member tool permissions** — `[gateway.matrix_room_tools]` maps a room to the tools
  permitted there, and `[gateway.matrix_user_tools]` maps a member to the tools permitted to them
  (config-file only; richer than env can express cleanly). A room/user absent from a map is
  unconstrained; when both apply, the effective set is their **intersection** (a tool must be allowed
  by the room *and* the member). Enforced in the agent core per turn, so a disallowed tool is neither
  advertised to the model nor runnable. Pair with allowed-rooms/-users for a deny-by-default perimeter.
- **Home room** — `MATRIX_HOME_ROOM` (or `[gateway] matrix_home_room`) names one room that receives a
  "shutting down" notice when the gateway is stopped (SIGTERM / Ctrl-C); the process then exits cleanly.

**Matrix encryption.** The Matrix gateway targets unencrypted rooms by default; build with
`--features e2ee` (needs Rust ≥ 1.93) for Olm/Megolm end-to-end encryption via `matrix-sdk-crypto`.
With `MATRIX_STATE_DIR` set, the crypto store is persisted to SQLite (`<dir>/crypto`,
optionally encrypted at rest with `MATRIX_CRYPTO_STORE_KEY`) so the bot keeps its keys and decrypts
existing rooms after a restart — no re-verification. The gateway **auto-accepts room invites** so you
can just invite the bot; disable with `--matrix-no-auto-join` or `[gateway] matrix_auto_join = false`.

**Slack.** The Slack gateway uses **Socket Mode** (no inbound port): a Slack app with an app-level
token (`SLACK_APP_TOKEN`, `xapp-…`) and a bot token (`SLACK_BOT_TOKEN`, `xoxb-…`). It answers
`message` and `app_mention` events, threads replies in threads, keys a session per channel (or
thread), and can be restricted with `SLACK_ALLOWED_USERS` (or `[gateway] slack_allowed_users`).

### Configuration file

For long-running deployments, a **TOML config** sets defaults for most flags so you don't pass a
long command line. `--config <PATH>` (or an auto-loaded `./lavoisier.toml`) is split into
`[provider]`, `[agent]`, `[memory]`, and `[gateway]` sections; **an explicit CLI flag or env var
always wins over the file**, which wins over the built-in default. Unknown keys are rejected.
See [`lavoisier.example.toml`](lavoisier.example.toml).

**Memory** is configured here. The in-memory session store is unbounded by default; `[memory]` can
cap it — `max_messages` (most-recent-N per session) and `max_sessions` (LRU eviction) — or switch to
a **durable file store** (`store = "file"`, `path = "..."`) so sessions survive restarts.

```toml
# lavoisier.toml
[provider]
provider = "anthropic"
[agent]
compact_after = 60000          # compact history past ~this many tokens
context_limit = 120000         # evict oldest tool output to fit
[memory]
store = "file"                 # durable; survives restarts
path  = "./.lavoisier/sessions"
max_messages = 200             # cap each session's transcript
[gateway]
serve = "0.0.0.0:8080"
api_keys = ["secret"]
```

### Flags

`--config <PATH>` (TOML defaults; see above) ·
`--agent` (tool loop) · `--serve <host:port>` (HTTP/WS gateway) · `--serve-matrix` (Matrix) ·
`--serve-slack` (Slack Socket Mode) · `--matrix-no-auto-join` (don't auto-accept Matrix invites) ·
`--cron "<min hour dom month dow> <prompt>"` (in-process scheduler, UTC; repeatable) ·
`--cron-file <path>` (JSON jobs: `[{"schedule","session"?,"prompt"}]`) ·
`--provider xai|anthropic|google|claude-cli` · `--model` · `--max-tokens` · `--system` ·
`--persona <PATH>` (persistent persona/priorities layered above the system prompt; defaults to
`./PERSONA.md` if present, `--no-persona` to disable) ·
`--thinking <low|high|dynamic|N>` (Gemini thinking effort) · `--budget` (total-task token ceiling).

Efficiency / cost levers: `--repo-skeleton <TOKENS>` (cache-aware repo-skeleton prefix) ·
`--summary-model` / `--compact-after` / `--context-limit` (compaction + eviction) ·
`--cheap-model` / `--escalate-after` (cheap-model-first) · `--advisor-model` (advisor+executor split).

ATO: `--tune` (ε-greedy) or `--tune-bayes` (Thompson sampling) · `--verify-cmd <cmd>` (real
success gate, e.g. `cargo test`) · `--tune-state <path>` (persist learned profiles) · `--tune-decay`
· `--telemetry` (per-task token/cost summary to stderr).

Accuracy levers (opt-in — Lavoisier is efficient by default, so these trade cost for completion and
are **off** unless asked for): `--require-edit` (don't let an edit task finish having changed nothing)
· `--verify-and-fix` (when finishing, if `--verify-cmd` fails, feed the failure back and keep fixing,
bounded — best with a real test gate).

Gateway: `--api-key <KEY>` (repeatable) · `--rate-limit <N per 60s>`.

Env: `XAI_API_KEY` / `XAI_TRANSPORT=grpc|http` (default `grpc`) / `XAI_GRPC_ENDPOINT` /
`XAI_BASE_URL` · `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` · `GOOGLE_API_KEY` (or `GEMINI_API_KEY`)
/ `GOOGLE_THINKING` · Matrix: `MATRIX_HOMESERVER` / `MATRIX_ACCESS_TOKEN` /
`MATRIX_USER` / `MATRIX_PASSWORD` / `MATRIX_DEVICE_ID` / `MATRIX_STATE_DIR` /
`MATRIX_CRYPTO_STORE_KEY` / `MATRIX_ALLOWED_USERS` / `MATRIX_ALLOWED_ROOMS` / `MATRIX_HOME_ROOM` ·
Slack: `SLACK_APP_TOKEN` / `SLACK_BOT_TOKEN` /
`SLACK_ALLOWED_USERS` · `LVZ_PROVIDER` / `LVZ_MODEL` / `LVZ_API_KEYS` / `LVZ_RATE_LIMIT` /
`LVZ_SERVE_ADDR`.

## Custom (private) tools

Tools are compiled-in Rust (no dynamic plugins), so your own tools are just Rust code — and they
can stay **private**: depend on the published `lavoisier` crate as a library and inject your tools,
without forking or touching the public repo.

```rust
// your-private-crate/src/main.rs   (private repo; never published)
use std::sync::Arc;
use async_trait::async_trait;
use lavoisier::{Tool, ToolError, ToolOutput};   // tool types re-exported by lavoisier
use serde_json::{json, Value};

struct QueryDb;
#[async_trait]
impl Tool for QueryDb {
    fn name(&self) -> &str { "query_db" }
    fn description(&self) -> &str { "Run a read-only SQL query." }
    fn schema(&self) -> Value {
        json!({"type":"object","properties":{"sql":{"type":"string"}},"required":["sql"]})
    }
    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let sql = args["sql"].as_str().ok_or_else(|| ToolError::InvalidArgs("sql".into()))?;
        Ok(ToolOutput::ok(format!("ran: {sql}")))   // .changed(true) only if it mutates the workspace
    }
}

fn main() -> std::process::ExitCode {
    lavoisier::main_with(vec![Arc::new(QueryDb)])    // your tools, plus all the built-ins
}
```

```toml
# your-private-crate/Cargo.toml
[dependencies]
lavoisier   = "0.4"
async-trait = "0.1"
serde_json  = "1"
```

Your binary then behaves exactly like `lav` — same flags, config, and gateways (HTTP/Matrix/Slack/cron,
E2EE, persona) — with your tools additionally available to the agent. A ready-to-copy template is in
[`examples/private-tools/`](examples/private-tools). (`main_with` builds the tokio runtime for you;
use `run_with` if you manage your own.)

## Deployment

Container + Terraform IaC for the HTTP gateway on **AWS Fargate (arm64, us-west-2)** ship in
[`infra/`](infra/) (Podman, not Docker; secrets via AWS Secrets Manager). See
[`infra/README.md`](infra/README.md) for the runbook.

```sh
podman build --platform linux/arm64 -f Containerfile -t lavoisier:dev .
./infra/scripts/build-and-push.zsh dev   # push to ECR
./infra/scripts/deploy.zsh               # terraform apply
```

## Development

```sh
cargo test                                               # all tests (125+)
cargo clippy --all-targets                               # lints (kept zero-warning)
cargo fmt --check                                        # formatting
cargo test -p lvz-context --test budget -- --nocapture   # token-budget trend line (§6.5)
```

## License

MIT — see [`LICENSE`](LICENSE).
