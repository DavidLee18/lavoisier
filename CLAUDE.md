# CLAUDE.md

Guidance for Claude Code working in this repository.

**Lavoisier** (binary `lavoisier`, alias `lav`) is a modular, token-efficient CLI coding agent in
Rust with a provider-agnostic core (Anthropic + xAI native, plus Google Gemini). The same agent
brain drives the CLI today and a multi-gateway "Hermes" service (HTTP/WebSocket, Matrix) tomorrow.

Companion docs — read the relevant one before working in that area:
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — crate map, the dependency invariants, key design decisions.
- [`ATO.md`](ATO.md) — the adaptive-token-optimisation tuner internals.
- [`bench/README.md`](bench/README.md) — the measured head-to-head vs. the Dirac agent (cost +
  verifiable correctness), the harness, and per-model pricing.

## Status

Complete and live-verified against real `XAI_API_KEY`, `ANTHROPIC_API_KEY`, and `GOOGLE_API_KEY`:
all 13 crates, provider streaming (SSE + xAI gRPC), the agent loop, the token engine, session
memory, the HTTP/Matrix gateways, AWS packaging (`infra/`), and the ATO learner. `cargo test`,
`cargo clippy --all-targets`, and `cargo fmt --check` are kept green.

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
  codegen from vendored `proto/`).
- Scripts **zsh**; local container shells **Podman** (not Docker).
- Keep dependencies minimal; no heavyweight agent frameworks, no SDKs. The stale Anthropic-native
  crates (`anthropic*`, `clust`, `misanthropy`) are **not** to be used — hand-roll thin `reqwest`
  adapters to retain caching + thinking.
- **Providers in scope: Anthropic + xAI + Google Gemini, native.** OpenAI and others are out of
  scope. A Discord gateway is **out of scope** (do not build it).
- Secrets: read from env / AWS Secrets Manager at runtime; never commit keys.
- License: **MIT** (`LICENSE`).

## Gotchas

- **Building `lvz-xai` requires `protoc`** (`brew install protobuf`) — `build.rs` compiles the
  vendored `proto/xai/api/v1/chat.proto`. Pin + update procedure in `proto/VENDOR.md`.
- `lvz-context` tree-sitter grammar/core ABI versions are pinned in its `Cargo.toml` — bump together.
- The budget loop's committed per-fixture ceilings (`lvz-context/tests/budget.rs`) are the baseline;
  update them deliberately when skeleton output legitimately changes.
- Gemini 3 attaches a `thoughtSignature` to each functionCall that must be echoed on resend (else
  400); `lvz-google` round-trips it through the opaque tool-call id, contained to the adapter.

## Commands

```sh
cargo build                          # build all crates
cargo test                           # all tests
cargo test -p <crate> [name]         # one crate / one test
cargo clippy --all-targets           # lints (zero-warning)
cargo fmt                            # format

# Run the CLI (binary in lvz-cli):
XAI_API_KEY=…       cargo run -p lvz-cli -- "prompt"                 # one streaming turn (xAI gRPC default)
ANTHROPIC_API_KEY=… cargo run -p lvz-cli -- --provider anthropic "…"
XAI_API_KEY=…       cargo run -p lvz-cli -- --agent "edit task"      # tool-using agent loop
XAI_API_KEY=…       cargo run -p lvz-cli -- --serve 127.0.0.1:8080   # HTTP/WS gateway + session memory
```

Key flags: `--agent`, `--serve`/`--serve-matrix`, `--provider xai|anthropic|google|claude-cli`,
`--model`, `--thinking`, `--budget`, `--repo-skeleton`, `--tune`/`--tune-bayes` + `--verify-cmd`,
`--cheap-model`/`--advisor-model`, `--no-batch-edit`, `--telemetry`, gateway `--api-key`/
`--rate-limit`. Full list and env vars in `README.md`. Deploy: `infra/README.md`.
