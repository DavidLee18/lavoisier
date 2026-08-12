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
the original 17 crates, provider streaming (SSE + xAI gRPC), the agent loop, the token engine,
session memory, the HTTP/Matrix/Slack/cron gateways, AWS packaging (`infra/`), and the ATO learner.
The protocol-interop crates added since — `lvz-mcp` (MCP client), `lvz-gw-a2a` (A2A server), and
`lvz-gw-acp` (**Zed Agent Client Protocol** agent over stdio, `--acp`) — are unit-tested offline
(in-process mock servers/pipes) **and live-smoke-verified**: MCP against a real stdio MCP server (the
model called a discovered, namespaced tool) and the A2A gateway over `curl` (agent card, sync
`message/send`, SSE streaming, error paths), both end-to-end with real Anthropic turns; the ACP
gateway over a `tokio::io::duplex` mock client and the real `lav --acp` binary (initialize /
session-new / error handshake on stdout). (IBM/BeeAI's *Agent Communication Protocol* server was
dropped — that project folded into A2A, whose server `lvz-gw-a2a` already covers; `lvz-gw-acp` now
names the editor-facing Agent **Client** Protocol.) An **inline TUI** frontend followed —
`lvz-gw-tui` (`--tui`), a scrollback-native interactive REPL (ratatui inline viewport) with streaming
output, tool-call cards, and Claude-Code-style tool-approval prompts on a new `ToolGate` contract —
unit-tested offline (the render engine needs a real terminal to verify, like Matrix). 21 crates in
all. `cargo test`, `cargo clippy --all-targets`, and `cargo fmt --check` are kept green.

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
shape). A tool job may carry a **`summarize` instruction** (a `ScheduleJob`/`JobSpec` field, *not* an
`Action` variant, so it's a reporting concern sibling to `room`/`session`): the tool still runs
deterministically, then a **successful** result is rewritten as prose for the room by a **tool-less**
`summarise` turn — submitted with an **empty `allowed_tools`** so the model can only write text, never
act (this is what keeps it safe where `Action::Prompt` — which carries no room/sender and so escapes
`matrix_room_tools` scoping — is not). The verdict stays the **tool's** (retry semantics untouched);
only the posted body changes — the raw output is still stored in `Outcome.detail`/history. A **failure
is never summarised** (its retry countdown must reach the room verbatim) and any summary failure
degrades to the raw output. `lvz-schedule` is a **leaf library** (no gateway→gateway edge); it owns the cron engine
(moved here from `lvz-gw-cron`, which now re-exports `CronSchedule`/`CronError` unchanged), the job
model, and the `ScheduleRegistry` holding live per-job state. Retry mirrors cron
(`--schedule-retry-max`/`-wait`, per-job overridable, next slot recomputed once the chain resolves)
but a pending retry is just another due time, not a blocking sleep. The chat surface is **tools**,
not commands — `schedule_list`/`schedule_status`/`schedule_run` are registered into the agent so
"how's the disk job?" and "run it again" work in natural language; a report is **encrypted when its
report room is encrypted** (under the `e2ee` feature), else sent in the clear — like the shutdown
notice, a scheduled fire has no inbound event to infer modality from, so the gateway consults the
room's `m.room.encryption` state (`room_encrypted` → `send_gateway_message`) to decide. Their event
ids go into `RecentIds`, so **replying to a report re-engages the bot** via the existing reply gate. `build_tool_registry` in `lvz-cli` is the composition root: the *same* registry goes to
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
friendly "going offline" notice on SIGTERM/Ctrl-C — the serve loop races `/sync` against a shutdown
signal and returns `Ok`, and the CLI joins gateways with `select_all` (not `join_all`) so the first to
finish ⇒ a clean whole-process exit. Both this notice and schedule reports are **gateway-initiated**
(no inbound event to infer modality from), so they route through `send_gateway_message`, which
**encrypts when the target room is encrypted** (under the `e2ee` feature — it checks the room's
`m.room.encryption` state via `room_encrypted`) and falls back to a plaintext send otherwise. The
notice is also **localised** the same way the council notices are: a `lvz_gw_matrix::Language` (English
default, Korean only when `--lang`/`LANG` resolves to `KO_KR`, via the shared `Language::from_locale`
rule) set on the gateway with `with_language`; the CLI maps its resolved locale onto it. Only the
shutdown notice localises — inbound turns and the agent's replies are unaffected. Reactions and typing
indicators are still always plaintext (conventional, and they carry no message content). **Startup resilience**: the bind path (`whoami`/`login` and the
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
sent in the clear even in encrypted rooms), shows a **typing** indicator (`PUT …/typing`), and posts a
concise **per-tool-call notice** as the agent works (`🔧 \`name\` · hint`, the hint pulled from the
streamed `Event::ToolUseStart/Delta/End` args via `tool_hint`). The typing indicator is kept alive by a
**20 s keep-alive timer** in `handle_message`'s stream loop (a `tokio::select!` branch, not just on tool
calls) — the homeserver's typing timeout is 30 s, and a **silent legion deliberation emits no tool
events for ~60 s+**, so without the timer the indicator would lapse into dead air mid-turn. The gateway
also renders **`Event::Notice`** progress lines as short messages (and refreshes typing) — the agent
streams these for the council's deliberation phases (`🧠 council convened…` → `🗣 critique round…` →
`⚖️ judge synthesising…`, **localised** — Korean when `--lang`/`LANG` is `KO_KR`, else English; see the
legion section), so a slow multi-model debate shows visible progress instead of silence. When the turn resolves it **swaps the 👀 for a ✅/❌ outcome reaction** — `finish_reaction`
redacts the transient ack (`PUT …/redact/…`) and reacts ✅ on success or ❌ when the agent errored, the
event stream errored, or the answer failed to send (`react` now returns the reaction's event id so the
ack can be retracted). The shared `handle_message` runs this whole flow; `Reply::{Plain,Encrypted}` is the one
seam that picks plaintext vs E2EE for the outbound messages, so the orchestration stays
modality-agnostic. Mention/reply signals on encrypted messages are read post-decrypt (they live inside
the ciphertext), reusing the same `mentions_bot`/`reply_target`/`message_content` helpers as the plaintext
path so detection is identical.

**Matrix media ingest** (`--matrix-media-dir <DIR>` / `MATRIX_MEDIA_DIR` / `[gateway]
matrix_media_dir`): setting a media dir **enables** inbound image/file handling — otherwise
`m.image`/`m.file`/`m.audio`/`m.video` messages are ignored as before. The shared `message_content`
helper (which replaced `message_text`) returns `(body, Option<Attachment>)`: an `m.text` yields
`(body, None)`; a media message with a plaintext `url` yields `(caption, Some(Attachment{mxc,
filename, mimetype}))`. When enabled and a message is engaged, `handle_message` downloads the bytes
via the **authenticated** media endpoint (`/_matrix/client/v1/media/download`, Matrix 1.11+) to
`<DIR>/<event-id>_<filename>` (both `sanitize_component`'d so nothing escapes the dir), then appends
an `[attachment] …saved locally at <path>…` line to the turn text. This is the **bytes-to-tool**
path: the model never *sees* the image, it just receives a local path to hand to a tool (e.g. a
custom upload tool via the `main_with` extension point). No `lvz-protocol`/`lvz-agent` change — it's
contained to the Matrix gateway. **Unencrypted rooms only** for now: E2EE media puts the reference
under `content.file` with AES-CTR keys (not a plaintext `url`), so `message_content` yields no
attachment for it even with media on — decrypting attachments is a deferred follow-up.

The **Slack gateway** (`lvz-gw-slack`, `--serve-slack`) is a thin **Socket Mode** client (no inbound
port): `apps.connections.open` → `tokio-tungstenite` WebSocket → `message`/`app_mention` events →
turn → `chat.postMessage`. Auth: `SLACK_APP_TOKEN` (`xapp-`) + `SLACK_BOT_TOKEN` (`xoxb-`). Session
per channel (or thread `thread_ts`); replies thread when triggered in a thread. Same allowlist
mechanism (`SLACK_ALLOWED_USERS` / `[gateway] slack_allowed_users`). Events are acked immediately and
the turn runs spawned off the read loop (keeps acks/pings flowing). Reconnects on `disconnect`/error.

**Persona prompt** (`--persona <PATH>`, default `./PERSONA.md`): a persistent persona/priorities file
layered *above* `DEFAULT_SYSTEM` in `build_agent`, so it sits in the cached prefix. `--no-persona`
disables auto-load.

**Legion council** (`lvz-legion`, `--legion-debater <PROVIDER:MODEL>` repeatable, `--legion-judge`,
`--legion-rounds`, env `LVZ_LEGION_ROUNDS`, `[legion]` config): a panel of models that **argue a
task out before the agent acts**. It generalises the advisor pre-pass: each debater (a
`provider:model` spec — cross-provider is first-class, e.g. `anthropic:opus` vs `xai:grok-4`) drafts
a position, then critiques the others (`--legion-rounds`, default 1), then a **judge** synthesises
one agreed plan-of-action + reply points. That plan seeds the executor as its opening move
(**deliberate-then-act**) — the debaters are tool-less; the normal loop runs the tools **once**. The
council is a new **`Deliberator` contract** in `lvz-protocol` (mirroring `Tuner`) implemented by
`lvz-legion`'s `Panel`; the agent holds it as `Arc<dyn Deliberator>` on the `Agent` struct (the tuner
pattern — *not* in the Debug-derived `AgentConfig`) and runs it at the single advisor seam in
`run_loop`, which it **supersedes**. **The council is grounded in the executor's context**, not left
to argue in a vacuum: the agent calls `deliberate_with_context(task, &DeliberationContext { system,
tools })`, handing the debaters the executor's **system prompt** (the `PERSONA.md` layer + operating
instructions) and **this turn's advertised tools** (already filtered by any per-turn permission
allowlist). Each phase's system prompt appends that grounding, so the debaters plan *as the agent*
and *to use its tools* — without it a persona-less, tool-less council can synthesise a **refusal**
("I'm not that bot / I can't do that") that then seeds and dooms the executor even though it holds
the tools. `deliberate_with_context` is an **additive, backward-compatible** method on the trait: it
defaults to delegating to the bare `deliberate(task)`, so pre-existing `Deliberator` impls are
unaffected (`DeliberationContext::EMPTY` is the no-grounding fallback). The council also **streams
progress**: `DeliberationContext.progress` is an optional callback the `Panel` fires per phase
(`council convened…` / `critique round…` / `judge synthesising…`), which the agent wires to the
turn's **`Event::Notice`** stream so a slow debate (which produces no answer text until the executor
runs) shows visible progress on every frontend (the CLI prints `[notice] …`; the Matrix gateway posts
a short message and refreshes typing) instead of ~60 s of silence. The notices are **localised** via a
`lvz_legion::Language` (default `English`, `Korean` when the resolved locale is `KO_KR`) set on the
`Panel` with `with_language`; the CLI resolves it from **`--lang`** (env `LANG`) through
`Language::from_locale` — only `KO_KR` (case-insensitive, `.encoding` suffix ignored) selects Korean.
Only these phase notices localise; the debate transcript and the executor's answer are unaffected. It is **best-effort**: a failed deliberation is logged (`warn!`)
and the turn proceeds unseeded, never dying. The debate is **internal** — the round-by-round
transcript goes to `tracing` (`lvz_legion=debug`), and only the judge's synthesis (and the reply the
executor then produces) is user-visible. The panel needs **≥2 debaters** (one is just
`--advisor-model`); the CLI builds each debater's provider fresh from env, so a missing key fails
fast with a clear message. Cross-provider token costs are summed under one `CostWeights` set (an
accepted approximation — the budget is a single ceiling regardless). `lvz-legion` is a **leaf
library** (depends only on `lvz-protocol`); the CLI composition root (`build_legion`) is the one
place that builds the concrete `Panel` and injects it via `build_agent`.

**Model fallback** (`--fallback <PROVIDER:MODEL>` repeatable/ordered, `--fallback-cooldown <SECONDS>`,
`[provider] fallback`/`fallback_cooldown`): an ordered chain the executor reroutes to when the
**primary model is unresponsive or errors before streaming any output** for a round-trip — a connect
timeout, an open error, or a stall/error *before the first token*. On timeout the in-flight request
is **cancelled by drop** (verified: all three providers wrap the live reqwest/tonic response with no
detached `spawn`, so dropping the future aborts the HTTP/gRPC request — no zombie call keeps billing).
Cross-provider is first-class (each spec builds its own provider from env, reusing the legion
`parse_provider_spec`). Held on the `Agent` struct as `fallbacks: Vec<(Arc<dyn Provider>, String)>`
(the `provider`/`legion` pattern — *not* in the Debug-derived `AgentConfig`) and threaded into
`run_loop`, which wraps the per-round-trip send in an `'attempt` loop over a cursor (0 = primary with
cheap-model-first applied; `i>0` = `fallbacks[i-1]`). **Within** a turn the cursor only advances (a
failed model is skipped for the rest of the turn). **Across** turns a shared `Arc<CircuitBreaker>`
(lock-free `AtomicU64` deadline per chain position, monotonic base, `0` = healthy) demotes a failed
position for `--fallback-cooldown` (default 60s): each turn *starts* at `breaker.first_available()`
(skipping still-demoted positions, so a persistently-down provider's timeout isn't re-paid every
turn), a pre-token failure `trip`s the position, a success `reset`s it, and once the cooldown elapses
the position is re-probed (half-open). `--fallback-cooldown 0` ⇒ re-probe every turn (per-turn-only
demotion). The switch is gated on `forwarded_any`: **only before the first event is forwarded** — once
output is streaming a restart would double the user-visible text, so a later mid-stream failure
surfaces as an error exactly as before (and does **not** trip the breaker — the model *was*
responding). Each candidate's request is built with *its own* provider `Capabilities` (so e.g.
Anthropic `cache_control` is never attached to an xAI request); the turn-level `caps` (for
observation/compaction) stays the primary's. Contained to `lvz-agent` + the CLI composition root
(`build_fallbacks`) — no protocol/gateway change, so every frontend gets it for free. Empty chain ⇒
byte-identical to before.

**MCP client** (`lvz-mcp`, `--mcp-server <LABEL:TARGET>` repeatable, `[mcp] servers`): Lavoisier as a
**Model Context Protocol client** — connect to external MCP servers and expose *their* tools as
Lavoisier tools, so every frontend (CLI + all gateways) gains them with **zero core change**. It is a
**leaf crate** (depends only on `lvz-protocol`): each remote tool is wrapped as an `McpTool`
implementing the core `Tool` contract, and the tools flow through the *same* `ToolRegistry` the
built-ins use. Each `--mcp-server` spec is `label: target` — `target` is either a command to spawn
(**stdio** transport: a child process, newline-delimited JSON-RPC 2.0 over its stdin/stdout,
`kill_on_drop`) or an `http(s)://` URL (**Streamable HTTP** transport: POST JSON-RPC, accept a JSON or
SSE reply, carry any `Mcp-Session-Id`). The two sit behind a `Transport` trait so the JSON-RPC client
(`McpClient`: `initialize` → `tools/list` paginated → `tools/call`) is transport-agnostic; the stdio
path is a generic `PipeTransport` over any reader/writer, so it's unit-tested offline against an
in-process mock server over a `tokio::io::duplex`. Remote tool names are **namespaced `<label>_<tool>`**
(and coerced to the provider tool-name charset `^[A-Za-z0-9_-]{1,64}$`) so they never silently shadow
a built-in (the registry is last-registration-wins). A tool-level `isError` maps onto
`ToolOutput::error` (model-visible, recoverable), never aborting the turn. The protocol is
**hand-rolled** over `tokio`/`reqwest` — no MCP SDK. The CLI composition root is the one wiring site:
`build_mcp_tools` connects every configured server (failing fast with the offending label on a bad
spec / dead server) and merges the tools ahead of `main_with`'s `extra_tools`; it only runs when the
tools can be used (a gateway, or `--agent`), so a plain one-shot ask spawns nothing.

**A2A server gateway** (`lvz-gw-a2a`, `--serve-a2a <ADDR>` / `[gateway] serve_a2a`): Lavoisier as a
Google **A2A (Agent-to-Agent) server** — a new `Gateway` (axum, modelled on `lvz-gw-http`) so other
agents can discover and delegate to it, driving the *same* shared agent as every other gateway. It
serves an **Agent Card** at `/.well-known/agent-card.json` (`capabilities.streaming = true`, one
skill; name/description/url overridable) and a **JSON-RPC 2.0** endpoint at `POST /`:
`message/send` (fold the turn's `TextDelta`s → a completed `Task`, the Slack reduce-to-answer
pattern), `message/stream` (SSE: a `working` status-update → one `artifact-update` per delta →
a final `completed` status-update), `tasks/get` (from a bounded in-memory store), `tasks/cancel`
(best-effort), else JSON-RPC `-32601`. The A2A **`contextId` maps to a Lavoisier session** so a
multi-turn A2A conversation accrues memory through the shared `SessionAgent`. Reuses `--api-key` as an
optional `Authorization: Bearer` gate on the endpoint (the card stays public). Own `shutdown_signal()`
+ `axum::serve(..).with_graceful_shutdown(..)` so SIGTERM exits cleanly under the CLI's `select_all`
join. JSON-RPC is hand-rolled over `axum`/`serde_json` — no A2A SDK; no protocol/agent change.

**ACP agent gateway** (`lvz-gw-acp`, `--acp` / `[gateway] acp`): Lavoisier as a **Zed Agent Client
Protocol** agent — the editor-facing protocol (<https://agentclientprotocol.com>), **JSON-RPC 2.0 over
stdio**, where the editor is the *client* that launches `lav --acp` as a subprocess and drives the
tool loop from its agent panel. (This ACP is the *Agent Client Protocol*. IBM/BeeAI's *Agent
Communication Protocol* shared the acronym but folded into A2A, so `--serve-a2a` is the agent-to-agent
interop surface now — Lavoisier ships no BeeAI-ACP server.) A `Gateway` (like every other) driving the
same shared agent, but over stdio rather than a socket: the serve loop reads newline-framed JSON-RPC
from **stdin** and writes responses +
`session/update` notifications to **stdout** (so nothing else may touch stdout — product/log output
already lives on stderr, which the protocol relies on). Surface (client→agent): `initialize`
(advertises protocol version `1`, text prompts, **no** auth methods — Lavoisier authenticates to model
providers itself via env keys), `session/new` (allocates `acp-<n>`, mapped straight onto a **Lavoisier
session** so a multi-turn conversation accrues memory), `session/prompt` (runs one turn — `TextDelta`→
`agent_message_chunk`, `Thinking`/`Notice`→`agent_thought_chunk`, `ToolUse*`→`tool_call`/
`tool_call_update` with a best-effort `kind` + accumulated `rawInput`, resolving with a `stopReason`
mapped from `StopReason`), and `session/cancel` (a notification; a per-session `Notify` armed
*before* submit — `notify_one` so the cancel is race-proof — is `select!`ed against the event stream,
and cancelling **drops the stream** to cancel the provider request, resolving `stopReason:
"cancelled"`). `session/prompt` is **spawned** off the reader loop so a concurrent `session/cancel`
is still read; a shared `Arc<Mutex<writer>>` serialises whole JSON-RPC lines. Ends cleanly on stdin
**EOF** (the editor closing the pipe). **Deferred** (documented): editor-delegated fs
(`fs/read_text_file`/`fs/write_text_file`) and `session/request_permission` — for now the agent runs
its own tools, a valid ACP posture; `session/load` is not offered (`loadSession: false`). Leaf crate
(depends only on `lvz-protocol`), JSON-RPC hand-rolled over `tokio`/`serde_json` — no ACP SDK, no
protocol/agent change; unit-tested offline over a `tokio::io::duplex` with a mock client, and
smoke-verified end-to-end through the real `lav --acp` binary. **21 crates in all.**

**Inline TUI gateway** (`lvz-gw-tui`, `--tui` / `[gateway] tui`): Lavoisier as an **interactive
terminal UI** — a scrollback-native REPL modelled on Claude Code / Grok CLI, another `Gateway` driving
the *same* shared agent. It uses ratatui's **inline viewport** (`Viewport::Inline`), *not* a
fullscreen alt-screen: finalized output is pushed into the terminal's own scrollback via
`insert_before` (so native scroll/copy/`Ctrl-L` all work), while a small live region holds the input
box (`tui-textarea`), a status/spinner line, and a token/cost footer. It renders the normalised
[`Event`] stream as a chat — `TextDelta`→streamed assistant text (line-buffered to scrollback with
**markdown rendering**: inline `**bold**`/`*italic*`/`` `code` ``/`~~strike~~` via a hand-rolled styler
with width-aware styled-span wrapping, plus block-level headings and fenced code), `Thinking`/`Notice`
→status, `ToolUse*`→tool-call cards, `Usage`→the footer. The **footer shows real spend** — a token
breakdown (`↑in ↓out ⚡cache`) and an estimated **USD cost** from a per-model price table (`price.rs`;
approximate list prices, matched by model-name substring, `~$` = estimate), not an abstract
token-equivalent. **Slash commands** (`/help`, `/model <name|reset>`, `/session <id>`, `/new`,
`/clear`, `/quit`) are handled locally; `/session`/`/new` switch the Lavoisier session so memory forks,
and **`/model` switches the model mid-session** — backed by a new **additive `TurnRequest.model:
Option<String>`** the agent applies per turn (overriding the executor model + suppressing
cheap-model-first for that turn; within the primary provider), so the switch needs no rebuild.
**Concurrency is the load-bearing bit**: the current turn runs on a **spawned task** feeding the
render loop over an mpsc channel, so the loop stays responsive — `Ctrl-C` cancels a turn (dropping the
stream cancels the provider request), and the approval prompt (below) can be answered mid-turn without
deadlocking the stream that's waiting on it. Depends only on `lvz-protocol` (+ ratatui/crossterm/
tui-textarea/unicode-width); deps are MSRV-safe. Logs would corrupt the viewport, so under `--tui`
`init_logging` routes `tracing` to `$LVZ_LOG_FILE` (or a sink) instead of stderr. Unit-tested offline
(state reducers, wrapping, command parsing, the gate); full interactive behaviour needs a real
terminal (raw mode fails cleanly on a non-tty), the same live-verification caveat as Matrix/e2ee.

**Tool-approval gate** (a **keystone change**, `lvz-protocol`'s new `ToolGate`): the TUI's
Claude-Code-style "allow this edit?" prompts rest on a new `ToolGate` contract — `async fn review(name,
args) -> ToolDecision::{Allow, Deny(reason)}` — held on the `Agent` as `Option<Arc<dyn ToolGate>>` (the
`Deliberator`/tuner injection pattern, *not* in the `Debug`-derived config) and consulted in `run_loop`
immediately before each `invoke`, right after the static `allowed_tools` defence-in-depth check. A
`Deny` is fed back to the model as an `is_error` tool result (the turn continues, never aborts — the
model adapts). `None` gate ⇒ **byte-identical** to before, so it's additive and backward-compatible
(every other frontend is unaffected). The TUI's `ChannelGate` implements it by bridging the agent's
question to the render loop over a channel (a `oneshot` carries the answer back); **policy mirrors
Claude Code** — read-only tools (`read`/`list`/`find`/`grep`/`search`/`outline`/…) run unattended,
mutating tools and shells (and any unrecognised/namespaced MCP tool — safe default) prompt, with an
"always allow this tool" set to suppress repeats. `--tui-auto-approve` / `[gateway] tui_auto_approve`
waives prompting (no gate installed → the fast path). Contained to `lvz-protocol` (the contract) +
`lvz-agent` (the seam) + `lvz-gw-tui`/CLI (the policy) — no gateway change.

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
`[citation]`, `[notice]`, `[usage]`, `[done]`), the `--telemetry` summary, the fatal `error:` lines, and the
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
  so "our crates at `info`, dependencies at `warn`" is an explicit 20-crate roll-call. A crate
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
