<p align="center">
  <img src="lavoisier-logo.png" alt="Lavoisier" width="200">
</p>

# Lavoisier

A modular, **token-efficient** CLI coding agent with a provider-agnostic core (**Anthropic, xAI,
and Google Gemini — all native**). One agent brain drives the CLI and every gateway: HTTP/WebSocket,
Matrix, Slack, cron, A2A, ACP, and an inline TUI.

> **Lavoisier is written in Haskell** — a Cabal package at the repo root.
>
> It was a Rust workspace through **v0.15.0**. That implementation is retired but preserved: the
> `rust` branch and the `v0.7.1`..`v0.15.0` tags, and the 20 `lvz-*` crates still on crates.io, which
> remain frozen at Rust v0.15.0. `cargo install lavoisier` therefore still gets you the *old* Rust
> build; releases from **v0.16.0** on are Haskell binaries from this tree.
>
> Status: providers, context engine, ATO, tools, and all gateways including Matrix E2EE, live-verified
> on 7 surfaces against real `ANTHROPIC_API_KEY`, `XAI_API_KEY`, and `GOOGLE_API_KEY` (Slack is
> offline-tested only, for want of tokens). See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the design.

## Why

LLM coding workloads are token-bound, and **the optimisation metric is total task tokens across
all round-trips, never per-call input.** Lavoisier treats token efficiency as a first-class design
goal at every layer:

- **Prompt caching** on stable prefixes via Anthropic's native Messages API (`cache_control:
  ephemeral`) — context is ordered immutable → stable → volatile so the cached prefix stays warm.
- **File-skeleton extraction** — `outline_file`/`outline_files` send signatures and type definitions
  and elide bodies (doc comments kept), so structure costs a fraction of the source.
- **AST-resolved symbol-dependency graph** drives the skeleton-radius knob `N` ("include full
  bodies for symbols within `N` hops of the edit target") — references resolved from identifier
  nodes, scope-aware (string/comment mentions and shadowing locals don't create edges). Across files
  a same-named symbol is disambiguated by **import evidence**: candidate definers are ranked by how
  much of their path the referencing file's imports name, and only the best-matching tier is linked.
  This ranks rather than resolves — with no evidence it links every definer, as before — so it can
  narrow the skeleton but never drop an edge a resolver would have got wrong. `outline_files` with
  `focus` follows the graph across every path you pass. It buys precision more than tokens: on a
  whole repo the skeleton floor dominates, so the measured saving is small — the point is that the
  radius stops expanding an unrelated symbol that merely shares a name.
- **Hash-anchored edits** and **token-efficient diffs** instead of re-emitting whole files. Repeated
  lines and repeated snippets stay addressable *without* line numbers: both `edit_anchored`/
  `edit_files` and `str_replace` take an `after` landmark (and `str_replace` a `before` too) — itself
  a verbatim snippet or anchor that must occur exactly once — and edit the first match past it. An
  edit that cannot be pinned to exactly one target is refused with a message naming the fix, never
  applied to a guess.
- **Multi-file batching** — `read_files`/`outline_files` fetch several files in one round-trip.
- **Adaptive Token Optimisation (ATO)** — an online tuner that learns per-archetype knob settings
  from realised outcomes (ε-greedy hill-climb or Thompson sampling), gated by a real success signal.
- **History compaction**, context-budget eviction, and model routing (cheap-model-first, advisor+
  executor) for long tasks.
- A **budget-sweep test suite** over the context engine that pins the radius lever's behaviour — the
  kept set grows monotonically with radius and a wider radius really does cost more tokens — so a
  regression in the size/relevance trade is a test failure, not a slow cost creep. On top of it,
  `tests/budget/ceilings.txt` commits the estimated context tokens each fixture costs at each
  radius, with no headroom, and CI gates on it: any growth in what the engine constructs fails with
  the numbers attached.

**Two modes.** By default Lavoisier is **efficiency-first** — lean context, caching, minimal
round-trips. When you have a real test gate, opt into **accuracy-mode** (`--verify-cmd <tests>
--require-edit --verify-and-fix`): the agent iterates until the tests pass. In the measured
head-to-head this matches or beats the comparison agent on task completion *while costing less per
completed task* — see [`bench/README.md`](bench/README.md) (cost + reproducible correctness via
`bench/verify.zsh`). That benchmark was run against the Rust build at v0.15.0; this tree shares the
design but has not been re-benchmarked. Tuner internals: [`ATO.md`](ATO.md).

## Architecture

One Cabal package whose module tree follows the old crate split (`lvz-protocol` →
`Lavoisier.Protocol.*`, and so on), segmented so the agent core never depends on a wire protocol or a
frontend. The keystone is `Lavoisier.Protocol.*`, which defines the `Event` stream and the
`Provider`/`Tool`/`Gateway`/`Tuner`/`Deliberator` contracts; dependencies point inward only. Those
contracts are **records of functions** held as ordinary values, and `EventStream` is a hand-rolled
pull stream. Plain `IO`, no effect framework. See
[`ARCHITECTURE.md`](ARCHITECTURE.md) for the module map, the invariants, and the key design decisions.

## Install

The package is `lavoisier`; the built command is **`lav`**. It is **not on Hackage** — take a
self-contained tarball from a [release](https://github.com/DavidLee18/lavoisier/releases)
(macOS arm64, Linux x86_64/arm64), or build from source below.

## Quickstart (from source)

Requires **GHC 9.10** + Cabal, and the native libraries the engine links: `tree-sitter` (0.26.x, for
grammar ABI 15), `snappy`, and — only under the `e2ee` flag — `libolm` (3.2.x). No `protoc`: the xAI
gRPC bindings are committed under `gen/`.

```sh
cabal build
cabal build -fe2ee          # + Matrix end-to-end encryption (Olm/Megolm via the olm/ FFI package)

# One streaming turn (no tools):
ANTHROPIC_API_KEY=… cabal run lav -- "explain a monad in one sentence"
XAI_API_KEY=…       cabal run lav -- --provider xai-grpc "…"

# The multi-step agent with filesystem + shell + context tools:
ANTHROPIC_API_KEY=… cabal run lav -- --agent "add a doc comment to the add() fn in src/Lib.hs"

# Serve the shared agent as an HTTP/WebSocket gateway (+ in-memory session continuity):
ANTHROPIC_API_KEY=… cabal run lav -- --serve 8080

# Run scheduled agent turns (in-process cron, UTC) — standalone or alongside --serve/--serve-matrix:
ANTHROPIC_API_KEY=… cabal run lav -- --cron "*/30 9-17 * * 1-5 summarise new CI failures"

# Chat gateways: Matrix (one room per session) and Slack (Socket Mode, one channel/thread per session):
ANTHROPIC_API_KEY=… cabal run lav -- --serve-matrix
ANTHROPIC_API_KEY=… cabal run lav -- --serve-slack
```

The built-in tools are `read_file` · `read_files` · `write_file` · `str_replace` · `edit_files` ·
`list_dir` · `shell` · `outline_file` · `outline_files`, plus `batch_edit` on a provider with a
discounted batch API, and `schedule_list`/`schedule_status`/`schedule_run` inside a Matrix schedule.

Gateways compose: `--serve`, `--serve-matrix`, `--serve-slack`, and `--cron`/`--cron-file` all drive
**one** shared agent and run concurrently in the same process, so a single low-resource host can
answer HTTP/Matrix/Slack requests *and* fire scheduled jobs. Every gateway — cron included — drives
the full tool-using agent loop, so scheduled jobs can read, edit, and run commands just like an
interactive turn. Each cron job keeps a fixed session, so it accrues memory across fires (like the
Matrix per-room / Slack per-channel sessions). A failed fire (a rejected submit or a mid-turn stream
error) can be **retried**: `--cron-retry-max N` + `--cron-retry-wait SECS` set global defaults, and a
`--cron-file` job may override either per-job (`retryMax`/`retryWait`); the next scheduled slot
is recomputed only after retries finish, so a retry never double-fires the following slot.

**Schedules (Matrix).** Where `--cron` fires a *prompt* into stderr, `--schedule-file` runs jobs
**inside the Matrix gateway** and reports each outcome to a room. A job is either a **direct tool
call** — which runs *unconditionally*, with no model round-trip and so no tokens — or a prompt turn:

```dhall
-- jobs.dhall — a Dhall list of job records, type-checked at load. Dhall records carry no
-- defaults, so every field must be present: name the shape once and override per job.
-- Note `jobId`/`toolArgs`, not `id`/`args` — Dhall selectors are top-level, so `id` and
-- `args` would collide with function parameters. `toolArgs` is a JSON-object *string*.
let Job =
      { jobId : Text, schedule : Text, room : Optional Text, session : Optional Text
      , tool : Optional Text, toolArgs : Optional Text, prompt : Optional Text
      , summarize : Optional Text, retryMax : Optional Natural, retryWait : Optional Natural }

let empty : Job =
      { jobId = "", schedule = "* * * * *", room = None Text, session = None Text
      , tool = None Text, toolArgs = None Text, prompt = None Text
      , summarize = None Text, retryMax = None Natural, retryWait = None Natural }

in  [ -- Deterministic: the tool always runs, no model round-trip and so no tokens.
      empty // { jobId = "disk", schedule = "0 9 * * *", room = Some "!ops:example.org"
               , tool = Some "shell", toolArgs = Some "{\"command\":\"df -h\"}"
               , retryMax = Some 2, retryWait = Some 60 }
    , -- Model-driven: fires an agent turn, which may chain tools.
      empty // { jobId = "build", schedule = "*/15 * * * *"
               , prompt = Some "check the build and summarise failures" }
    ]
```

A tool job may also carry `summarize`, an instruction that rewrites the raw output into prose for the
room (the full output still goes to stderr). `tool` and `prompt` are mutually exclusive, and one of
them is required.

```sh
ANTHROPIC_API_KEY=… cabal run lav -- --serve-matrix --schedule-file jobs.dhall
```

There is no `--schedule-room`: each job names its own `room`.

Every fire posts a result (`✅ \`disk\` · …`); failures are louder, carrying the error plus the retry
countdown or a give-up notice. Reports are **addressable**: the bot registers `schedule_list`,
`schedule_status`, and `schedule_run` as tools, so you can ask *"how's the disk job doing?"* or
*"run it again"* in plain language — and because each report is one of the bot's own messages,
**replying to one re-engages it** under the usual mention/reply gate. Retry semantics match cron
(global `--schedule-retry-max`/`--schedule-retry-wait`, per-job overridable, next slot recomputed
once the chain resolves); job state is in-memory, so history resets on restart.

A room is a bad log, so the chat report is only ever a summary — the **full account goes to stderr**
on every fire: untruncated output, duration, attempt, tools used, and (for prompt jobs) token usage.

```
lavoisier[schedule]: greet fired ok in 5ms (attempt 1) tools=[shell]
--- output (53 bytes) ---
exit=0
--- stdout ---
scheduled-hello

lavoisier[schedule]: build FAILED in 8123ms (attempt 2/3) tools=[shell, read_file] usage=[in 4210 / out 388 / cache_read 2048]
--- error ---
stream error: provider error: 503 upstream unavailable
```

**Persona / priorities.** Point `--persona <PATH>` at a file (or drop a `PERSONA.md` in the working
dir, or set `persona` in the config) to give a long-running gateway a stable identity and standing
instructions. It is layered **above** the operating instructions rather than replacing them — the
tool-loop steering survives — and rides in the cached prefix, so it costs almost nothing per turn.
`--no-persona` suppresses the `./PERSONA.md` auto-load; `--system` replaces the operating
instructions themselves, with the persona still layered above whatever that leaves.

**Matrix auth & identity.** The Matrix gateway authenticates with either an **access token**
(`MATRIX_ACCESS_TOKEN` — identity resolved via `whoami`, no login) or **password**
(`MATRIX_USER` + `MATRIX_PASSWORD`). Set `MATRIX_STATE_DIR` to persist the session (token + device
id) and keep a **stable device identity across restarts** — a prerequisite for durable E2EE. Restrict
who can drive the bot with `MATRIX_ALLOWED_USERS`.

**Matrix access control & tool permissions.** Three layers, all opt-in and applied uniformly to
plaintext and encrypted rooms:
- **Allowed rooms** — `MATRIX_ALLOWED_ROOMS` limits the rooms
  the bot acts in. Combined with the sender allowlist as a **conjunction**: a turn runs only if the
  sender is allowed *and* the room is allowed — so an allowed user is answered only inside allowed rooms.
- **Per-room / per-member tool permissions** — `matrixRoomTools` maps a room to the tools permitted
  there, and `matrixUserTools` maps a member to the tools permitted to them (config-file only: these
  are nested maps, richer than env can express cleanly). A room/user absent from a map is
  unconstrained; when both apply, the effective set is their **intersection** (a tool must be allowed
  by the room *and* the member). Enforced in the agent core per turn, so a disallowed tool is neither
  advertised to the model nor runnable. Pair with allowed-rooms/-users for a deny-by-default perimeter.
- **Home room** — `MATRIX_HOME_ROOM` names one room that receives a
  friendly "going offline" notice when the gateway is stopped (SIGTERM / Ctrl-C); the process then exits
  cleanly. The notice is localised (Korean when `--lang`/`LANG` is `KO_KR`, English otherwise).
- **Media ingest** — `MATRIX_MEDIA_DIR` **enables** inbound image/file handling: when the bot is engaged by a message carrying a file, it
  downloads the bytes to `<DIR>` and appends the local path to the turn so a tool can act on it — the
  "bytes-to-tool" path (the model never sees the image, it just gets a path to hand to a tool, e.g. a
  custom upload tool). Unset ⇒ media messages are ignored, as before. Unencrypted rooms only for now
  (encrypted media, whose reference lives under `file` with decryption keys, isn't ingested yet).
- **E2EE session recovery** — a peer that still holds an Olm session the bot no longer has (a restored
  backup, a migrated or rolled-back crypto store) keeps sending normal — not pre-key — messages, which
  are undecryptable and therefore invisible. The gateway repairs this rather than waiting it out: an
  unreadable Olm message triggers an `m.dummy` over a fresh session (rate-limited per device, 5 min),
  which makes the peer replace its own, and a Megolm event with no known session triggers an
  `m.room_key_request` to the sender's devices — cancelled once the key arrives, since repairing the
  channel alone does not make a peer re-share a key it believes it already delivered. Both failures are
  logged at `warn` with the `sender_key`/`session_id` needed to identify the missing key. Note that
  current clients (matrix-nio, Element) forward keys only to **their own** other devices, so a request
  to a different user is accepted and dropped — the reliable path back is the unwedge plus that peer's
  next room key; the request is what recovers the multi-device case, and costs nothing otherwise.

A worked example — a deny-by-default perimeter where the bot answers only Alice and Bob, only in the
`!ops` and `!general` rooms, runs the shell only in `!ops`, treats `!general` as read-only, and limits
Bob to reads. The simple gates are env vars; the per-room/-member tool maps are config-file only:

```sh
# Perimeter: who + where. (env wins over the config file)
export MATRIX_ACCESS_TOKEN=…                        # bot identity (or MATRIX_USER + MATRIX_PASSWORD)
export MATRIX_ALLOWED_USERS="@alice:hs,@bob:hs"      # answer only these senders
export MATRIX_ALLOWED_ROOMS="!ops:hs,!general:hs"    # …and only in these rooms (AND'd with the above)
export MATRIX_HOME_ROOM="!ops:hs"                    # gets the friendly "going offline" notice on SIGTERM
ANTHROPIC_API_KEY=… lav --serve-matrix --config lavoisier.dhall
```

```dhall
-- lavoisier.dhall — per-room / per-member tool permissions (no env equivalent).
-- Absent from a map ⇒ unconstrained; when a room AND a member both apply, the effective
-- set is their INTERSECTION (a tool must be permitted by the room *and* the member).
-- `toMap` turns a record into the assoc list the decoder reads.
{ matrixRoomTools = Some (toMap
    { `!ops:hs`     = [ "shell", "read_file", "write_file", "str_replace" ]
    , `!general:hs` = [ "read_file", "read_files", "outline_file" ]   -- read-only room
    })
, matrixUserTools = Some (toMap
    { `@alice:hs` = [ "shell", "read_file", "write_file", "str_replace" ]
    , `@bob:hs`   = [ "read_file", "read_files" ]                     -- bob: reads only
    })
}
```

**Leaving these unset means no restriction at all** — every allowed sender is offered the whole tool
registry in every room they can reach. They fail open by design (a room absent from the map is
unconstrained), so a deployment that relies on them must set them in the config file.

Resulting effective tool sets (room ∩ member):
- **Alice in `!ops`** → `shell, read_file, write_file, str_replace` (both sets agree — full power).
- **Alice in `!general`** → `read_file` only (the read-only room masks her write tools).
- **Bob in `!general`** → `read_file, read_files` (his reads, both permitted by the read-only room).
- **Bob in `!ops`** → `read_file` only (his reads intersected with the room, which omits `read_files`).
- **Anyone else, or any room outside the allowlist** → ignored entirely (no turn runs).

A disallowed tool is never even advertised to the model, so it can't be called — the gate is enforced
in the agent core, not just hidden in the prompt.

**Matrix engagement & feedback.** The Matrix bot is addressable rather than a firehose. In a **1:1 DM**
it answers everything; in a **group room** it engages only when you **@-mention it** or **reply to one
of its messages** (this is on top of any sender/room allowlist). When it does engage it gives live
feedback: it **reacts 👀** to your message, shows a **typing** indicator while it works, and posts a
short **notice for each tool call** as it runs them (e.g. `🔧 `read_file` · src/lib.rs`), so you can see
what it's doing before the answer arrives. When the turn finishes it **replaces the 👀 with ✅** (success)
or **❌** (the agent or the answer failed), so the reaction on your message tells you the outcome at a
glance. (These behaviours are Matrix-only; the Slack gateway answers `message`/`app_mention` as before.)

**Matrix encryption.** The Matrix gateway targets unencrypted rooms by default; build with
`-fe2ee` for Olm/Megolm end-to-end encryption, orchestrated here over the `olm/` FFI package against
the system `libolm`. With `MATRIX_STATE_DIR`
set, the account and its sessions are **pickled** to that directory — optionally encrypted at rest
with `MATRIX_CRYPTO_STORE_KEY` — so the bot keeps its keys and decrypts existing rooms after a
restart, no re-verification. Use a **fresh `MATRIX_DEVICE_ID` for each new live run**: reusing one
leaves stale one-time keys on the homeserver and peers fail with `BAD_MESSAGE_KEY_ID`. The gateway
**auto-accepts room invites** so you can just invite the bot; disable by setting
`MATRIX_NO_AUTO_JOIN`.

**Slack.** The Slack gateway uses **Socket Mode** (no inbound port): a Slack app with an app-level
token (`SLACK_APP_TOKEN`, `xapp-…`) and a bot token (`SLACK_BOT_TOKEN`, `xoxb-…`). It answers
`message` and `app_mention` events, threads replies in threads, keys a session per channel (or
thread), and can be restricted with `SLACK_ALLOWED_USERS`.

### Configuration file

For long-running deployments, a **Dhall config** sets defaults for most flags so you don't pass a
long command line. (Dhall; the retired Rust tree used TOML.) `--config <PATH>` — or an auto-loaded
`./lavoisier.dhall` — is one flat record whose keys are the flag names in camelCase; **an explicit
CLI flag or env var always wins over the file**, which wins over the built-in default. Every field is
optional: the file is merged over an all-`None` defaults record, so write only what you set, and
Dhall type-checks it at load, making a typo or a wrong type a clear error rather than a silent
default. See [`lavoisier.dhall.example`](lavoisier.dhall.example) for the annotated full schema.

The Matrix per-room/per-member tool maps (above) have **no flag and no env var** — the config file is
the only way to set them. Sessions are durable when `sessionDir` is set (a file store under that
directory) and in-memory otherwise, capped at the most recent 200 messages per session either way.

```dhall
-- lavoisier.dhall
{ provider = Some "anthropic"
, contextLimit = Some 120000        -- evict oldest tool output to fit
, summaryModel = Some "claude-haiku-4-5-20251001"
, sessionDir = Some "./.lavoisier/sessions"   -- durable; survives restarts
, persona = Some "/etc/lavoisier/PERSONA.md"
, serve = Some 8080
}
```

### Flags

`--config <PATH>` (Dhall defaults; see above) ·
`--agent` (tool loop) · `--serve <PORT>` (HTTP/WS gateway, all interfaces) · `--serve-matrix` (Matrix) ·
`--serve-slack` (Slack Socket Mode) ·
`--cron "<min hour dom month dow> <prompt>"` (in-process scheduler, UTC; repeatable) ·
`--cron-file <path>` (a Dhall list of `{schedule, session, prompt, retryMax, retryWait}` — the
`Optional` fields must still be present as `None`) ·
`--cron-retry-max <N>` / `--cron-retry-wait <SECS>` (retry a failed cron fire; per-job overridable) ·
`--schedule-file <path>` (Matrix schedules: a Dhall list of
`{jobId, schedule, room, session, tool, toolArgs, prompt, summarize, retryMax, retryWait}`, as
above; requires `--serve-matrix`) ·
`--schedule-retry-max <N>` / `--schedule-retry-wait <SECS>` (per-job overridable) ·
`--provider anthropic|google|xai|xai-grpc|claude-cli` · `--model` · `--max-tokens` · `--max-steps` ·
`--system` · `--persona <PATH>` / `--no-persona` (persona layered above the operating instructions;
`./PERSONA.md` auto-loads when present) ·
`--thinking <off|low|medium|high>` · `--budget` (total-task token ceiling) ·
`--session-dir <DIR>` (durable gateway sessions).

Efficiency / cost levers: `--summary-model` / `--context-limit` (compaction + eviction) ·
`--cheap-model` / `--escalate-after` (cheap-model-first) · `--advisor-model` (advisor+executor split) ·
`--no-progress-limit <N>` (hard-stop after 2N edit-free round-trips) · `--budget-awareness` (show the
model its own ceilings) · `--classify-with-model` (model the task archetype instead of the keyword
heuristic) · `--no-batch-edit` (don't offer the `batch_edit` fan-out).

Resilience: `--fallback <PROVIDER:MODEL>` (repeatable, ordered) sets a **fallback chain** — if the
primary model is unresponsive or errors *before streaming any output* for a round-trip (a connect
timeout, an open error, or a stall/error before the first token), the in-flight request is cancelled
and the agent transparently reroutes to the next model, so a slow or down provider doesn't hang the
turn. Cross-provider is first-class (each named provider needs its API key in the env). A failed
model is demoted by a **circuit breaker** (`--fallback-cooldown <SECONDS>`, default 60): it is
skipped from the start of subsequent turns for the cooldown — so a persistently-down provider isn't
re-tried every turn — then re-probed once it elapses (a probe success clears it, a failure re-trips
it). `--fallback-cooldown 0` re-probes every turn. Configurable via `fallback` /
`fallbackCooldown`. E.g. `--fallback anthropic:claude-sonnet-4-6 --fallback google:gemini-3-flash-preview`.

Legion (multi-model council): `--legion-debater <PROVIDER:MODEL>` (repeatable — pass two or more,
e.g. `--legion-debater anthropic:claude-opus-4-8 --legion-debater xai:grok-4`) makes those models
**argue the task out before the agent acts**: each drafts a position, they critique each other
(`--legion-rounds <N>`, default 1), and a judge (`--legion-judge <PROVIDER:MODEL>`, default the first
debater) synthesises one agreed plan that seeds the executor (deliberate-then-act). Cross-provider is
first-class; each named provider needs its API key in the env. Configurable via `legionDebaters` /
`legionJudge` / `legionRounds`. Supersedes `--advisor-model`; the debate itself is internal (see it
with `--log-level debug`). The
council streams short progress notices per phase (`🧠 council convened…` → `🗣 critique round…` →
`⚖️ judge synthesising…`); these **localise** via `--lang <LOCALE>` (falls back to the `LANG` env var)
— `KO_KR` renders them in Korean, anything else keeps English.

A2A (Agent-to-Agent server): `--serve-a2a <PORT>` exposes Lavoisier as a Google **A2A** agent — an
Agent Card at `/.well-known/agent-card.json` plus a JSON-RPC endpoint (`message/send`,
`message/stream` over SSE, `tasks/get`) so other agents can delegate tasks to it. Reuses `--api-key`
for auth; runs alongside the other gateways. Configurable via `serveA2a`. Takes a **port**, not an
address.

ACP (Zed **Agent Client Protocol** agent — the *editor* protocol): `--acp` runs Lavoisier as an ACP
agent over **stdio** (JSON-RPC 2.0), so an ACP-capable editor (Zed, or Neovim via a bridge) launches
it as a subprocess and drives the full tool loop from its agent panel. It owns stdin/stdout for the
protocol (diagnostics stay on stderr); point your editor's agent command at `lav --acp`. Implements
`initialize`, `session/new`, `session/prompt` (streaming `session/update`s — message/thought chunks
and tool-call updates), and `session/cancel`. Configurable via `acp`. (For agent-to-agent interop —
the role IBM/BeeAI's *Agent Communication Protocol* played before it folded into A2A — use
`--serve-a2a`.)

TUI (interactive inline terminal UI): `--tui` launches a scrollback-native REPL — the coding-agent
shell, modelled on Claude Code / Grok CLI — driving the same shared agent. It keeps an *inline*
viewport (not fullscreen), so output flows into the terminal's normal scrollback while an input box,
status line, and footer stay pinned at the bottom. Assistant output is **markdown-rendered** (bold,
italic, code, headings, bordered fenced code blocks, and column-aligned tables); the **footer shows a
token breakdown and an estimated USD cost**. Slash commands `/help` `/model <name|reset>`
`/session <id>` `/new` `/clear` `/quit` — `/model` switches the model mid-session; `Ctrl-C` cancels a
turn, `Ctrl-D` quits, `Ctrl-L` clears the screen, `Alt+Enter` inserts a newline. **Tool approval**
follows Claude Code's default — read-only tools run unattended, mutating tools and shells prompt (the
call's full arguments are shown, then `y` allow once · `a` always · `n` deny); waive it with
`--tui-auto-approve`. Logs are routed to `$LVZ_LOG_FILE` (or suppressed) so they don't corrupt the
display. Configurable via `tui` / `tuiAutoApprove`.

The port drives the terminal with ANSI escapes directly rather than through a TUI framework: the
inline viewport is what makes this scrollback-native, and it has no Haskell equivalent (brick and vty
are alt-screen shaped), so it is implemented as cursor arithmetic in the same hand-rolled spirit as
the rest of the adapters.

MCP (Model Context Protocol client): `--mcp-server <LABEL:TARGET>` (repeatable) connects to an
external MCP server and exposes **its** tools as Lavoisier tools, so the agent and every gateway gain
them. `TARGET` is either a command to spawn (stdio transport) or an `http(s)://` URL (Streamable
HTTP). Tools are namespaced `<label>_<tool>` so they never shadow the built-ins. E.g.
`--mcp-server 'fs: npx -y @modelcontextprotocol/server-filesystem .'`. Configurable via `mcpServers`.

ATO: `--tune` (ε-greedy) or `--tune-bayes` (Thompson sampling) · `--verify-cmd <cmd>` (real
success gate, e.g. `cabal test`) · `--tune-state <path>` (persist learned profiles, saved after an
`--agent` turn).

Accuracy levers (opt-in — Lavoisier is efficient by default, so these trade cost for completion and
are **off** unless asked for): `--require-edit` (don't let an edit task finish having changed nothing)
· `--verify-and-fix` (when finishing, if `--verify-cmd` fails, feed the failure back and keep fixing,
bounded — best with a real test gate) · `--in-loop-verify` (stop as soon as an edit makes
`--verify-cmd` pass).

Gateway: `--api-key <KEY>` (repeatable) · `--rate-limit <N per 60s>`.

Logging: operator diagnostics go to **stderr** through `Lavoisier.Log`, the port's stand-in for the
`tracing` facade the Rust tree used — one process-wide threshold rather than per-target filters.
`--log-level <error|warn|info|debug>` (env `LVZ_LOG_LEVEL`) retunes it; the default is `info`. An
unrecognised value falls back to `info`, so a typo can't silence a running daemon. Downstream
`mainWith` binaries get `logError`/`logWarn`/`logInfo`/`logDebug` re-exported from `Lavoisier.CLI`,
so custom tools instrument themselves through the same threshold. Never log a secret — lengths and
counters only.

Note the CLI's own interface — the streamed `[tool]` / `[usage]` / `[done]` rendering — is **not**
routed through logging: it's product output, so it always prints and no log filter can suppress it.

Env: `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` · `XAI_API_KEY` / `XAI_BASE_URL` (transport is
picked by `--provider xai` vs `xai-grpc`) · `GOOGLE_API_KEY` / `GOOGLE_BASE_URL` · `CLAUDE_CLI_BIN` ·
Matrix: `MATRIX_HOMESERVER` / `MATRIX_USER` / `MATRIX_ACCESS_TOKEN` / `MATRIX_PASSWORD` /
`MATRIX_DEVICE_ID` / `MATRIX_STATE_DIR` / `MATRIX_CRYPTO_STORE_KEY` / `MATRIX_ALLOWED_USERS` /
`MATRIX_ALLOWED_ROOMS` / `MATRIX_HOME_ROOM` / `MATRIX_MEDIA_DIR` / `MATRIX_NO_AUTO_JOIN` ·
Slack: `SLACK_APP_TOKEN` / `SLACK_BOT_TOKEN` / `SLACK_ALLOWED_USERS` · `LVZ_LOG_LEVEL` · `LANG`
(locale for the localised notices).

## Custom (private) tools

Tools are compiled in (no dynamic plugins), so your own tools are just Haskell code — and they can
stay **private**: depend on this package as a git dependency and inject your tools, without forking
or touching the public repo.

```haskell
-- your-private-package/app/Main.hs   (private repo; never published)
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Text (Text)
import Lavoisier.CLI (Tool (..), mainWith, toolErr, toolOk)

queryDb :: Tool
queryDb =
  Tool
    { toolName = "query_db",
      toolDescription = "Run a read-only SQL query.",
      toolSchema =
        object
          [ "type" .= String "object",
            "properties" .= object ["sql" .= object ["type" .= String "string"]],
            "required" .= [String "sql"]
          ],
      -- Errors are values: a recoverable failure is `Right (toolErr …)`, model-visible, and the
      -- loop continues. `setChanged True` on the output only if it mutated the workspace.
      toolInvoke = \args -> pure $ case strArg "sql" args of
        Nothing -> Right (toolErr "query_db: missing `sql`")
        Just sql -> Right (toolOk ("ran: " <> sql))
    }

main :: IO ()
main = mainWith [queryDb]    -- your tools, plus all the built-ins

strArg :: Text -> Value -> Maybe Text
strArg k (Object o) = case KM.lookup (K.fromText k) o of Just (String v) -> Just v; _ -> Nothing
strArg _ _ = Nothing
```

```cabal
-- your-private-package/cabal.project — pin a release tag; `olm` is needed for the e2ee flag.
source-repository-package
  type: git
  location: https://github.com/DavidLee18/lavoisier
  tag: v0.16.0
  subdir: . olm
```

Your binary then behaves exactly like `lav` — same flags, config, and gateways (HTTP/Matrix/Slack/
cron, E2EE, persona) — with your tools additionally available to the agent. The full recipe, including
the native-library paths and how to turn the engine's `e2ee` flag on from a consumer, is in
[`CUSTOM_TOOL_INSTRUCTIONS.md`](CUSTOM_TOOL_INSTRUCTIONS.md).

## Deployment

Container + Terraform IaC for the HTTP gateway on **AWS Fargate (arm64, us-west-2)** ship in
[`infra/`](infra/) (colima + nerdctl, not Docker; secrets via AWS Secrets Manager). See
[`infra/README.md`](infra/README.md) for the runbook.

```sh
nerdctl build --platform linux/arm64 -f Containerfile -t lavoisier:dev .
./infra/scripts/build-and-push.zsh dev   # push to ECR
./infra/scripts/deploy.zsh               # terraform apply
```

## Development

```sh
cabal build && cabal test                      # -Wall -Werror; tasty (240+ tests)
cabal build -fe2ee && cabal test lavoisier-e2ee-test
ormolu --mode inplace $(git ls-files '*.hs')   # formatting; run before every commit
```

`gen/` holds the committed xAI proto-lens bindings — generated code, so leave it out of the ormolu
sweep. To read the retired Rust implementation, `git worktree add ../lavoisier-rust rust`.

## License

MIT — see [`LICENSE`](LICENSE).
