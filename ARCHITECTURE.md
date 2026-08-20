# Architecture

A single Cabal package (GHC 9.10, `GHC2021`), module-segmented so the agent core never depends on a
wire protocol or a frontend. The keystone is `Lavoisier.Protocol.*`.

The module names below carry the crate names of the Rust implementation this was ported from
(retired at v0.15.0; see the `rust` branch), because the segmentation is the same and the older
design notes and commit history are still worth reading against it. Where Haskell needs a different
mechanism than a Rust trait object, that is called out.

## The three rules (do not violate)

1. **`Lavoisier.Protocol.*` (`lvz-protocol`) is the keystone.** It defines the normalised `Event` stream and the `Provider`,
   `Tool`, `Gateway`, `Tuner`, and `Capabilities` contracts, and has **zero** provider- or
   gateway-specific dependencies. Everything depends on it; it depends on nothing of theirs.
2. **Dependencies point inward only.** Provider adapters (`Lavoisier.Provider.*`) and gateways
   (`Lavoisier.Gateway.*`) depend on the core, never the reverse. A
   transport/provider/gateway must never leak into `lvz-agent`. Each adapter is the *only* place that
   maps its wire format to `Event`.
3. **Abstract at the semantic layer.** gRPC vs SSE vs OpenAI-compat is a contained transport detail
   behind the `Event` stream + `Capabilities`. Anthropic has no gRPC, so gRPC must not become an
   architectural assumption.

This is what lets one agent brain serve the CLI today and a multi-gateway "Hermes" service tomorrow.

## Modules

| Module (Rust crate it was ported from) | Role |
|---|---|
| `Lavoisier.Protocol.*` (`lvz-protocol`) | Normalised contracts: `Event` stream, `Provider`, `Tool`, `Gateway`, `Tuner`, `Deliberator`, `ToolGate` (pre-invoke approval hook), `Capabilities`, telemetry. Zero provider/gateway deps. |
| `Lavoisier.Provider.Xai` (`lvz-xai`) | xAI provider: native **gRPC** (grapesy + committed proto-lens bindings under `gen/`, default) with an OpenAI-compat SSE fallback. |
| `Lavoisier.Provider.Anthropic` (`lvz-anthropic`) | Anthropic provider: native Messages API over SSE, prompt caching, extended thinking. |
| `Lavoisier.Provider.Google` (`lvz-google`) | Google Gemini provider: native Generative Language API over SSE, configurable thinking effort. |
| `Lavoisier.Provider.ClaudeCli` (`lvz-claude-cli`) | Optional provider shelling out to `claude -p` (subscription; no caching). Off by default. |
| `Lavoisier.Context.*` (`lvz-context`) | Token engine: tree-sitter skeletons, AST symbol-dependency graph (radius `N`, cross-file edges ranked by import evidence), hash-anchored edits (landmark-disambiguated), diffs, budget-fixture loop. |
| `Lavoisier.Tool.*` (`lvz-tools`) | Tool registry + built-ins: `read_file(s)`, `write_file`, `list_dir`, `shell`, `outline_file(s)`, `read_anchored`, **`str_replace`** (primary exact-string edit), `edit_anchored`, `edit_files`, `find_references`, `batch_edit`. |
| `Lavoisier.Agent` (`lvz-agent`) | The plan→act→observe loop: tool dispatch, capability-gated caching, compaction, model routing, per-task budget, telemetry. |
| `Lavoisier.Memory` (`lvz-memory`) | Session continuity: a `SessionStore` + `SessionAgent` so each session keeps its own transcript. |
| `Lavoisier.Tune.*` (`lvz-tune`) | The ATO learner: `LearningTuner` (ε-greedy) and `BayesTuner` (Thompson sampling), with on-disk persistence. See [`ATO.md`](ATO.md). |
| `Lavoisier.Legion` (`lvz-legion`) | The **legion council** (library): a `Panel` of provider+model `Debater`s that argue a task out — draft → critique → judge — and return one agreed plan. Implements the `Deliberator` contract; the agent runs it as a pre-pass (deliberate-then-act) that supersedes the single advisor. The agent hands it a `DeliberationContext` (the executor's system prompt + this turn's tools) via `deliberate_with_context`, so the debate is grounded in the agent's persona and real capabilities rather than refusing in a vacuum. Leaf module: depends only on the protocol layer. |
| `Lavoisier.Mcp` (`lvz-mcp`) | **MCP client** (library): connect to external Model Context Protocol servers (stdio child process or Streamable-HTTP URL) and adapt each remote tool into an `McpTool` satisfying the `Tool` contract. Hand-rolled JSON-RPC 2.0 behind a `Transport` record; tools are namespaced `<label>_<tool>`. Leaf module: depends only on the protocol layer. The CLI merges its tools into the shared registry, so every frontend gains them. |
| `Lavoisier.Gateway.Http` (`lvz-gw-http`) | HTTP/WebSocket gateway (axum): `/v1/turns` (SSE), `/v1/ws`, `/health`, Prometheus `/metrics`, API-key auth + rate limits. |
| `Lavoisier.Gateway.A2A` (`lvz-gw-a2a`) | **A2A (Agent-to-Agent) server** gateway (axum): an Agent Card at `/.well-known/agent-card.json` + a JSON-RPC 2.0 endpoint (`message/send`, `message/stream` over SSE, `tasks/get`), so other agents delegate to Lavoisier. A2A `contextId` ↔ session. Hand-rolled JSON-RPC; optional API-key auth. |
| `Lavoisier.Gateway.Acp` (`lvz-gw-acp`) | **ACP (Zed Agent Client Protocol) agent** gateway: JSON-RPC 2.0 over **stdio** (`--acp`) so an editor launches Lavoisier as a subprocess — `initialize`, `session/new`, `session/prompt` (streaming `session/update`s), `session/cancel`. ACP `sessionId` ↔ session. Hand-rolled JSON-RPC. (Not IBM/BeeAI's *Agent Communication Protocol*, which folded into A2A → `lvz-gw-a2a`.) |
| `Lavoisier.Gateway.Tui` (`lvz-gw-tui`) | **Inline TUI** gateway (`--tui`): an interactive, scrollback-native terminal REPL (an *inline* viewport, not fullscreen) driving the shared agent — streaming assistant text, tool-call cards, markdown rendering, slash commands, and a token/cost footer. Tool-approval prompts (Claude-Code default: reads auto, mutations ask) via the `ToolGate` contract, bridged to the render loop by a `ChannelGate`. The turn runs on its own task so cancel/approval never deadlock the stream. Leaf module. The terminal is driven with ANSI escapes directly — an inline viewport has no Haskell framework equivalent (brick/vty are alt-screen shaped); the retired Rust used ratatui/crossterm/tui-textarea. |
| `Lavoisier.Gateway.Matrix` (`lvz-gw-matrix`) | Matrix gateway (one room per session). Access-token or password auth with a stable, persistable device identity; optional per-sender allowlist. End-to-end encryption (Olm/Megolm via `matrix-sdk-crypto`, durable SQLite crypto store via `matrix-sdk-sqlite`) is opt-in behind the `e2ee` feature; off by default. |
| `Lavoisier.Gateway.Cron` (`lvz-gw-cron`) | Cron gateway: an in-process UTC scheduler that fires turns on a cron schedule; composes with the other gateways over one agent. The cron engine itself lives in `lvz-schedule` and is re-exported here. |
| `Lavoisier.Schedule` (`lvz-schedule`) | Scheduled **actions** (library, not a gateway): the hand-rolled UTC cron engine (no date deps), a job model whose action is either a *direct tool call* (unconditional, no model round-trip) or a prompt turn, a registry of live per-job state with bounded history, and the `schedule_*` tools. Frontend-agnostic — it returns a report and lets the caller deliver it; the Matrix gateway hosts it today. |
| `Lavoisier.Gateway.Slack` (`lvz-gw-slack`) | Slack gateway (Socket Mode, one session per channel/thread): thin `tokio-tungstenite` WebSocket client, no inbound port; `message`/`app_mention` → turn → `chat.postMessage`; optional per-user allowlist. |
| `Lavoisier.CLI` (`lvz-cli`) | The `lavoisier` binary — the first gateway. |

## Key decisions

- **Compiled, CLI-first** — one native binary, instant cold start, no venv/node_modules; correctness
  via ADTs + exhaustive `case`. The workload is I/O-bound, so raw speed is not the reason. (Rust
  through v0.15.0, Haskell since; the argument did not change, only the language.)
- **Anthropic over native SSE** (no gRPC exists) — required to keep **prompt caching** and extended
  thinking; an OpenAI-compat shim would drop caching, the single biggest cost lever.
- **xAI over native gRPC** (codegen from the official `xai-org/xai-proto`) with an in-module
  OpenAI-compat fallback. gRPC is *not* an architectural assumption — it's isolated behind the
  `Event` stream, because Anthropic can't speak it.
- **Provider scope: Anthropic + xAI + Google Gemini, native, hand-rolled thin adapters.** No SDKs, no
  generic multi-provider layer. Gemini was added to enable same-model benchmarking vs. competing
  agents (see [`bench/README.md`](bench/README.md)); OpenAI and others remain out of scope.
- **Token efficiency is a first-class design goal**, concentrated in `lvz-context` + caching. The
  optimisation metric is **cost-weighted total task tokens across all round-trips**, never per-call
  input.
- **Multi-gateway is designed-for now, deferred in scope** — a `Gateway` contract (peer to `Tool`)
  keeps the core frontend-agnostic.
