# Architecture

A Cargo workspace (edition 2021, MSRV 1.88), trait-segmented so the agent core never depends on a
wire protocol or a frontend. The keystone is `lvz-protocol`.

## The three rules (do not violate)

1. **`lvz-protocol` is the keystone.** It defines the normalised `Event` stream and the `Provider`,
   `Tool`, `Gateway`, `Tuner`, and `Capabilities` contracts, and has **zero** provider- or
   gateway-specific dependencies. Everything depends on it; it depends on nothing of theirs.
2. **Dependencies point inward only.** Provider adapters (`lvz-anthropic`, `lvz-xai`, `lvz-google`,
   `lvz-claude-cli`) and gateways (`lvz-gw-*`) depend on the core, never the reverse. A
   transport/provider/gateway must never leak into `lvz-agent`. Each adapter is the *only* place that
   maps its wire format to `Event`.
3. **Abstract at the semantic layer.** gRPC vs SSE vs OpenAI-compat is a contained transport detail
   behind the `Event` stream + `Capabilities`. Anthropic has no gRPC, so gRPC must not become an
   architectural assumption.

This is what lets one agent brain serve the CLI today and a multi-gateway "Hermes" service tomorrow.

## Crates

| Crate | Role |
|---|---|
| `lvz-protocol` | Normalised contracts: `Event` stream, `Provider`, `Tool`, `Gateway`, `Tuner`, `Capabilities`, telemetry. Zero provider/gateway deps. |
| `lvz-xai` | xAI provider: native **gRPC** (tonic, default) with an OpenAI-compat SSE fallback. |
| `lvz-anthropic` | Anthropic provider: native Messages API over SSE, prompt caching, extended thinking. |
| `lvz-google` | Google Gemini provider: native Generative Language API over SSE, configurable thinking effort. |
| `lvz-claude-cli` | Optional provider shelling out to `claude -p` (subscription; no caching). Off by default. |
| `lvz-context` | Token engine: tree-sitter skeletons, AST symbol-dependency graph (radius `N`), hash-anchored edits, diffs, budget-fixture loop. |
| `lvz-tools` | Tool registry + built-ins: `read_file(s)`, `write_file`, `list_dir`, `shell`, `outline_file(s)`, `read_anchored`, **`str_replace`** (primary exact-string edit), `edit_anchored`, `edit_files`, `find_references`, `batch_edit`. |
| `lvz-agent` | The plan→act→observe loop: tool dispatch, capability-gated caching, compaction, model routing, per-task budget, telemetry. |
| `lvz-memory` | Session continuity: a `SessionStore` + `SessionAgent` so each session keeps its own transcript. |
| `lvz-tune` | The ATO learner: `LearningTuner` (ε-greedy) and `BayesTuner` (Thompson sampling), with on-disk persistence. See [`ATO.md`](ATO.md). |
| `lvz-gw-http` | HTTP/WebSocket gateway (axum): `/v1/turns` (SSE), `/v1/ws`, `/health`, Prometheus `/metrics`, API-key auth + rate limits. |
| `lvz-gw-matrix` | Matrix gateway (one room per session). Access-token or password auth with a stable, persistable device identity; optional per-sender allowlist. End-to-end encryption (Olm/Megolm via `matrix-sdk-crypto`, durable SQLite crypto store via `matrix-sdk-sqlite`) is opt-in behind the `e2ee` feature; off by default. |
| `lvz-gw-cron` | Cron gateway: an in-process UTC scheduler (hand-rolled, no date deps) that fires turns on a cron schedule; composes with the other gateways over one agent. |
| `lvz-gw-slack` | Slack gateway (Socket Mode, one session per channel/thread): thin `tokio-tungstenite` WebSocket client, no inbound port; `message`/`app_mention` → turn → `chat.postMessage`; optional per-user allowlist. |
| `lvz-cli` | The `lavoisier` binary — the first gateway. |

## Key decisions

- **Rust, CLI-first** — single static binary, instant cold start, no venv/node_modules; correctness
  via sum types + exhaustive `match`. The workload is I/O-bound, so speed is not the reason.
- **Anthropic over native SSE** (no gRPC exists) — required to keep **prompt caching** and extended
  thinking; an OpenAI-compat shim would drop caching, the single biggest cost lever.
- **xAI over native gRPC** (codegen from the official `xai-org/xai-proto`) with an in-crate
  OpenAI-compat fallback. gRPC is *not* an architectural assumption — it's isolated behind the
  `Event` stream, because Anthropic can't speak it.
- **Provider scope: Anthropic + xAI + Google Gemini, native, hand-rolled thin adapters.** No SDKs, no
  generic multi-provider crate. Gemini was added to enable same-model benchmarking vs. competing
  agents (see [`bench/README.md`](bench/README.md)); OpenAI and others remain out of scope.
- **Token efficiency is a first-class design goal**, concentrated in `lvz-context` + caching. The
  optimisation metric is **cost-weighted total task tokens across all round-trips**, never per-call
  input.
- **Multi-gateway is designed-for now, deferred in scope** — a `Gateway` trait (peer to `Tool`)
  keeps the core frontend-agnostic.
