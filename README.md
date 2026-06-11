# Lavoisier

A modular, **token-efficient** CLI coding agent in Rust with a provider-agnostic core
(**Anthropic + xAI**, both native). The same agent brain drives the CLI today and a
multi-gateway "Hermes" service (HTTP/WebSocket, Matrix) tomorrow.

> Status: **M0–M10 complete** plus the optional tracks — the full [build blueprint](RECIPE.md)
> is implemented and tested (provider streaming over SSE **and** xAI gRPC, the agent loop, fs/
> shell/context tools, the token-efficiency engine, session memory, gateways, AWS packaging, and
> the adaptive-token-optimisation learner). Live-verified against real `XAI_API_KEY` and
> `ANTHROPIC_API_KEY`. See [`RECIPE.md`](RECIPE.md) for the full design and milestone log.

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

See [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md) for a token-cost analysis (vs. the Dirac agent) and
[`docs/ATO.md`](docs/ATO.md) for the tuner internals.

## Architecture

A Cargo workspace, trait-segmented so the agent core never depends on a wire protocol or a
frontend. The keystone is `lvz-protocol`; **dependencies point inward only** — provider adapters and
gateways depend on the core, never the reverse, and each transport (gRPC vs SSE vs OpenAI-compat)
is contained behind the normalised `Event` stream + `Capabilities`.

| Crate | Role |
|---|---|
| `lvz-protocol` | Normalised contracts: `Event` stream, `Provider`, `Tool`, `Gateway`, `Tuner`, `Capabilities`, telemetry. Zero provider/gateway deps. |
| `lvz-xai` | xAI provider: native **gRPC** (tonic, default) with an OpenAI-compat SSE fallback. |
| `lvz-anthropic` | Anthropic provider: native Messages API over SSE, prompt caching, extended thinking. |
| `lvz-claude-cli` | Optional provider shelling out to `claude -p` (subscription; no caching). Off by default. |
| `lvz-context` | Token engine: tree-sitter skeletons, AST symbol-dependency graph (radius `N`), hash-anchored edits, diffs, budget-fixture loop. |
| `lvz-tools` | Tool registry + built-ins: `read_file(s)`, `write_file`, `list_dir`, `shell`, `outline_file(s)`, `read_anchored`, `edit_anchored`. |
| `lvz-agent` | The plan→act→observe loop: tool dispatch, capability-gated caching, compaction, model routing, per-task budget, telemetry. |
| `lvz-memory` | Session continuity: a `SessionStore` + `SessionAgent` so each session keeps its own transcript. |
| `lvz-tune` | The ATO learner: `LearningTuner` (ε-greedy) and `BayesTuner` (Thompson sampling), with on-disk persistence. |
| `lvz-gw-http` | HTTP/WebSocket gateway (axum): `/v1/turns` (SSE), `/v1/ws`, `/health`, Prometheus `/metrics`, API-key auth + rate limits. |
| `lvz-gw-matrix` | Matrix gateway (one room per session). |
| `lvz-cli` | The `lavoisier` binary — the first gateway. |

## Quickstart

Requires a recent Rust toolchain (**edition 2021, MSRV 1.88**) and **`protoc`**
(`brew install protobuf`) — `lvz-xai`'s build compiles the vendored xAI protos.

```sh
cargo build

# One streaming turn (no tools). xAI uses gRPC by default (XAI_TRANSPORT=grpc):
XAI_API_KEY=…       cargo run -p lvz-cli -- "explain a monad in one sentence"
ANTHROPIC_API_KEY=… cargo run -p lvz-cli -- --provider anthropic "…"

# The multi-step agent with filesystem + shell + context tools:
XAI_API_KEY=… cargo run -p lvz-cli -- --agent "add a doc comment to the add() fn in src/lib.rs"

# Serve the shared agent as an HTTP/WebSocket gateway (+ in-memory session continuity):
XAI_API_KEY=… cargo run -p lvz-cli -- --serve 127.0.0.1:8080
```

### Flags

`--agent` (tool loop) · `--serve <host:port>` (HTTP/WS gateway) · `--serve-matrix` (Matrix) ·
`--provider xai|anthropic|claude-cli` · `--model` · `--max-tokens` · `--system` · `--budget`
(total-task token ceiling).

Efficiency / cost levers: `--repo-skeleton <TOKENS>` (cache-aware repo-skeleton prefix) ·
`--summary-model` / `--compact-after` / `--context-limit` (compaction + eviction) ·
`--cheap-model` / `--escalate-after` (cheap-model-first) · `--advisor-model` (advisor+executor split).

ATO: `--tune` (ε-greedy) or `--tune-bayes` (Thompson sampling) · `--verify-cmd <cmd>` (real
success gate, e.g. `cargo test`) · `--tune-state <path>` (persist learned profiles) · `--tune-decay`
· `--telemetry` (per-task token/cost summary to stderr).

Gateway: `--api-key <KEY>` (repeatable) · `--rate-limit <N per 60s>`.

Env: `XAI_API_KEY` / `XAI_TRANSPORT=grpc|http` (default `grpc`) / `XAI_GRPC_ENDPOINT` /
`XAI_BASE_URL` · `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` · `MATRIX_HOMESERVER` / `MATRIX_USER` /
`MATRIX_PASSWORD` · `LVZ_PROVIDER` / `LVZ_MODEL` / `LVZ_API_KEYS` / `LVZ_RATE_LIMIT` /
`LVZ_SERVE_ADDR`.

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
