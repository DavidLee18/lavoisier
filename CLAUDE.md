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
all 14 crates, provider streaming (SSE + xAI gRPC), the agent loop, the token engine, session
memory, the HTTP/Matrix/cron gateways, AWS packaging (`infra/`), and the ATO learner. `cargo test`,
`cargo clippy --all-targets`, and `cargo fmt --check` are kept green.

The **cron gateway** (`lvz-gw-cron`, `--cron`/`--cron-file`) is an in-process scheduler shaped as a
`Gateway`: it fires `TurnRequest`s on a hand-rolled UTC cron schedule (no `chrono`/`cron` dep) into
the shared agent. It composes with `--serve`/`--serve-matrix` (all gateways run concurrently over one
agent, via `futures::join_all` over each `Gateway::serve`). Every gateway drives the full tool-using
loop, so cron jobs run tools. Each job keeps a fixed session, so it accrues memory across fires.

The **Matrix gateway auto-accepts room invites** by default (`rooms.invite` → `/join`, deduped across
syncs); disable with `--matrix-no-auto-join` or `[gateway] matrix_auto_join = false`. E2EE is
live-verified end-to-end (cross-implementation, against both Synapse and Continuwuity).

**Persona prompt** (`--persona <PATH>`, default `./PERSONA.md`): a persistent persona/priorities file
layered *above* `DEFAULT_SYSTEM` in `build_agent`, so it sits in the cached prefix. `--no-persona`
disables auto-load.

**TOML config** (`--config <PATH>`, else auto `./lavoisier.toml`): `crates/lvz-cli/src/config.rs`
parses `[provider]`/`[agent]`/`[memory]`/`[gateway]` and fills any flag the user left unset
(precedence: CLI/env > file > default; `deny_unknown_fields`). It's a CLI-layer concern — library
crates still take explicit config. **Memory** gained real bounds: `InMemoryStore::with_limits`
(`max_messages` per session, `max_sessions` LRU) plus a durable `FileStore` (JSON per session,
hex-encoded filenames); `[memory] store = "memory"|"file"` selects between them. Sample:
`lavoisier.example.toml`.

**Matrix E2EE** is opt-in behind `lvz-gw-matrix`'s `e2ee` feature (and the `lavoisier` crate's
passthrough `e2ee` feature): Olm/Megolm via the crypto-only `matrix-sdk-crypto`, contained to
`crates/lvz-gw-matrix/src/e2ee.rs` (drives an `OlmMachine` over the hand-rolled REST transport, bridging
ruma request types with `try_into_http_request`). **Off by default** — the default build stays minimal-dep
and MSRV-1.88; the feature requires Rust ≥ 1.93. Crypto round-trip is unit-tested where offline-testable;
full live verification needs a homeserver (like the rest of the Matrix gateway).

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

- **Building `lvz-xai` requires `protoc`** (`brew install protobuf`) — `build.rs` compiles the
  vendored `crates/lvz-xai/proto/xai/api/v1/chat.proto`. Pin + update procedure in that dir's `VENDOR.md`.
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
