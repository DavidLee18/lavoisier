# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status: M0–M5 built; M6 efficiency hardening in progress

`RECIPE.md` is the authoritative **build blueprint** for **Lavoisier** (binary `lavoisier`,
alias `lav`) — a modular, token-efficient CLI coding agent in Rust with a provider-agnostic
core. **Read it before any work**: the decision log (§1), crate responsibilities (§4), core
contracts (§5), and milestone sequence (§9) define what to build and in what order. If a
request conflicts with `RECIPE.md`, surface the conflict rather than silently diverging.

Milestones done (per §9): **M0** workspace + `lvz-protocol` contracts · **M1** xAI
OpenAI-compat first light · **M2** SSE streaming · **M3** `lvz-anthropic` native Messages API
+ caching + thinking · **M4** `lvz-agent` plan→act→observe loop + `lvz-tools` (fs + shell),
OpenAI tool-calling through `lvz-xai` · **M5** `lvz-context` token engine — tree-sitter
skeletons (Rust/Python/JS/TS), **recursive symbol-dependency graph** driving the
skeleton-radius knob `N`, hash-anchored edits, token-efficient diffs, plus the **budget-fixture
CI loop (§6.5)** (`tests/budget.rs`, committed per-archetype token ceilings). Surfaced to the
agent as `outline_file` (with optional `focus`/`radius`), `read_anchored`, `edit_anchored`.

Crates that exist today: `lvz-protocol`, `lvz-xai`, `lvz-anthropic`, `lvz-context`,
`lvz-tools`, `lvz-agent`, `lvz-cli`. Not yet built (future milestones): `lvz-tune`,
`lvz-gateway` + `lvz-gw-*`, `lvz-claude-cli`.

**Current state (saved 2026-06-09):** M0–M5 complete, committed and pushed to
`origin/main` (initial commit + author/copyright set to Jaehyun Lee). 7 crates,
**59 tests passing**, clippy clean, `cargo fmt` clean. Verified live against the real
`XAI_API_KEY`: streaming turns, the agent tool loop, and the token-efficient
outline→anchor→edit workflow. Anthropic path now **verified live** against the real
`ANTHROPIC_API_KEY` (model `claude-sonnet-4-6`): a streaming turn plus the agent
`read_anchored`→batched `edit_anchored` loop, with **prompt caching confirmed working**
(non-zero `cache_read`/`cache_creation` once the system+tooldefs prefix clears the
2048-token Sonnet cache minimum). Working tree clean.

**M6 increment (2026-06-10):** `lvz-agent` now consults a `Tuner` (default `NoopTuner` =
static §6.5 knobs; `FixedTuner` for explicit knobs) and reports the realised `Outcome` back,
making `Knobs` live. **History compaction** is implemented — once estimated transcript tokens
exceed `Knobs.compact_after`, the middle turns are summarised into one note via a **separate
tool-less provider call routed to `AgentConfig.summary_model`** (model tiering for the
summary workload), keeping the original task + last `KEEP_RECENT_TURNS` pairs verbatim on a
turn boundary (never orphaning a `tool_use`/`tool_result`). The summary call's tokens count
toward the task total/budget (§6.4). Tool-result truncation now reads `Knobs.truncate_bytes`.
**60 tests passing**, clippy + fmt clean.

### What's left to do (milestone order, `RECIPE.md` §9)

- **M6 — efficiency hardening (in progress).** ✅ Tuner/Knobs wired into the agent, history
  compaction, model routing for summaries, tool-result truncation. **Remaining:** a
  **context-budget manager** with relevance-ranked eviction (hard per-request ceiling, drop
  oldest/largest tool results — distinct from the whole-task `--budget`), context
  **deduplication** (collapse a file referenced twice), and output-minimisation polish.
  `--summary-model`/`--compact-after` are not yet exposed as CLI flags. Compaction is covered
  by a unit test (`FixedTuner` + recording provider) but not yet by a live run.
- **M7 — xAI gRPC.** Vendor `xai-org/xai-proto` into `proto/`, `tonic-build` codegen, v6
  "outputs" server-side tools. Today only the in-crate OpenAI-compat fallback exists in
  `lvz-xai`; the gRPC path is a runtime switch beside it.
- **M8 — gateway layer.** `lvz-gw-http` (REST + WebSocket). The `Gateway`/`AgentHandle`
  contracts already exist in `lvz-protocol` and `Agent` implements `AgentHandle`; this is
  about concrete gateway crates.
- **M9 — Hermes gateways + features.** `lvz-gw-matrix`, `lvz-gw-discord`; `lvz-memory`,
  auth/quotas, observability (OTel).
- **M10 — Hermes deployment.** Fargate arm64, us-west-2.
- **Optional tracks.** `lvz-tune` (ATO §6.6 — the *online* half; needs §6.4 telemetry + a
  task-success signal wired first; ship the no-op `Tuner` path, then swap in the learner).
  `lvz-claude-cli` (shell out to `claude -p`, no caching, off by default).

### Known debts inside shipped code (pick up before/with the above)

- **Tuner partially wired.** `lvz-agent` now calls `Tuner::select`/`observe` and honours
  `Knobs.compact_after` + `truncate_bytes`. Still unwired: `skeleton_radius` (the agent never
  calls `outline_file` with a tuner-chosen radius — that's the tool/model's choice today) and
  `batch_width` (no multi-file batching yet, §6.1). The `TaskContext` is hard-coded to
  `Archetype::Other` + empty `RepoProfile` — no task classification or repo profiling feeds
  the tuner yet, so even an `lvz-tune` learner would see undifferentiated context.
- **Telemetry (§6.4).** Usage is aggregated and the `--budget` ceiling is enforced, but there
  is no telemetry export / cache-hit-rate surfacing — a prerequisite for ATO.
- **Skeleton fidelity.** Python docstrings are currently elided with the body (RECIPE wants
  them kept). The symbol-dependency graph is a name-based heuristic (no scope/name
  resolution; same-named symbols across files merge) — fine for `N`, not a semantic index.
  `outline_file --focus` builds a single-file graph (the multi-file graph in
  `lvz-context::symbols` is used by the budget loop, not the tool).
- **Multi-file batching (§6.1)** and **cache-aware repo-skeleton prefix** are not implemented;
  caching currently marks only the system prompt + last tool def.

### Gotchas

- `lvz-context` parses with tree-sitter; grammar/core ABI versions are pinned in its
  `Cargo.toml` — bump them together and re-run tests.
- The budget loop's per-fixture ceilings in `crates/lvz-context/tests/budget.rs` are the
  committed baseline; update them deliberately when skeleton output legitimately changes
  (`cargo test -p lvz-context --test budget -- --nocapture` prints the trend line).

## Architecture invariants (do not violate)

The whole design exists to keep one agent core reusable by the CLI today and a future
multi-gateway "Hermes" agent tomorrow. Three rules enforce that:

- **`lvz-protocol` is the keystone.** It defines the normalised `Event` stream, `Provider`,
  `Tool`, `Gateway`, `Tuner`, and `Capabilities` contracts and has **zero** provider- or
  gateway-specific dependencies. Everything depends on it; it depends on nothing.
- **Dependencies point inward only.** Provider adapters (`lvz-anthropic`, `lvz-xai`,
  `lvz-claude-cli`) and gateways (`lvz-gw-*`) depend on the core, never the reverse. A
  transport/provider/gateway must never leak into `lvz-agent`. Each adapter is the *only*
  place that maps its wire format to `Event`.
- **Abstract at the semantic layer.** gRPC vs SSE vs OpenAI-compat is a contained transport
  detail behind the `Event` stream + `Capabilities`. Anthropic has no gRPC, so gRPC must not
  become an architectural assumption.

Planned workspace (crates prefixed `lvz-`; see `RECIPE.md` §3–§4 for the full map):
`lvz-protocol`, `lvz-anthropic`, `lvz-xai`, `lvz-context`, `lvz-agent`, `lvz-tools`,
`lvz-cli`, plus optional/Hermes-tier `lvz-claude-cli`, `lvz-tune`, `lvz-gateway`, `lvz-gw-*`.

## Token efficiency is a first-class goal

This is the project's central design lever (`RECIPE.md` §6), not an afterthought. When
implementing the context/agent/protocol layers, preserve these:

- Prompt caching via Anthropic native Messages API + `cache_control: ephemeral` on stable
  prefixes — this is the single biggest cost lever and the reason `lvz-anthropic` does **not**
  use any OpenAI-compat shim (the shim drops caching).
- Order context immutable → stable → volatile to maximise cache hits; never let volatile
  content leak into the cached prefix.
- File-skeleton extraction, symbol-dependency tracking, hash-anchored/AST-native edits, and
  token-efficient diffs over full-file rewrites (`lvz-context`).
- The optimisation metric is **total task tokens across all round-trips**, never per-call
  input. The skeleton-depth knob `N` is tuned against the budget-fixture CI loop (§6.5), not
  guessed.

## Commands

```sh
cargo build                          # build all workspace crates
cargo test                           # run all tests
cargo test -p <crate>                # test a single crate, e.g. -p lvz-agent
cargo test -p <crate> <name>         # run a single test by name
cargo clippy --all-targets           # lints (keep zero-warning)
cargo fmt                            # format

# Run the CLI (the `lavoisier` binary lives in lvz-cli):
XAI_API_KEY=… cargo run -p lvz-cli -- "your prompt"                 # one streaming turn (xAI)
ANTHROPIC_API_KEY=… cargo run -p lvz-cli -- --provider anthropic "…"  # Anthropic native
XAI_API_KEY=… cargo run -p lvz-cli -- --agent "edit task here"      # M4 tool-using agent loop
```

CLI flags: `--agent` (tool loop), `--provider xai|anthropic`, `--model`, `--max-tokens`,
`--system`, `--budget` (total-task token ceiling). Env: `XAI_API_KEY`/`XAI_BASE_URL`,
`ANTHROPIC_API_KEY`/`ANTHROPIC_BASE_URL`, `LVZ_PROVIDER`, `LVZ_MODEL`. A local SSE mock can
be pointed at via `*_BASE_URL` to test without a live key.

Continue building in `RECIPE.md` §9 milestone order (next is M5: context engine +
budget-fixture CI).

## Conventions

- **Rust** Cargo workspace; pin edition + MSRV in the root `Cargo.toml`. Correctness via
  sum types + exhaustive `match`.
- Async: **tokio**; HTTP: **reqwest**; JSON: **serde** / **serde_json**; gRPC: **tonic** +
  **prost** (xAI codegen from vendored `proto/`).
- Scripts: **zsh**. Local service shells: **Podman** (not Docker).
- Keep dependencies minimal and vendor-agnostic; avoid heavyweight agent frameworks. The
  stale Anthropic-native Rust crates (`anthropic*`, `clust`, `misanthropy`) are **not** to be
  depended on — hand-roll a thin `reqwest` adapter to retain caching + extended thinking.
- Providers in scope: **Anthropic + xAI native only**. Other providers are out of scope.
- Secrets: read from env / AWS Secrets Manager at runtime; never commit keys.
- License: prefer **Apache-2.0** (aligns with xai-proto) or MIT.
