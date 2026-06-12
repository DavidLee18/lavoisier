# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status: M0–M10 complete + optional tracks (lvz-tune ATO learner, lvz-claude-cli, advisor mode)

`RECIPE.md` is the authoritative **build blueprint** for **Lavoisier** (binary `lavoisier`,
alias `lav`) — a modular, token-efficient CLI coding agent in Rust with a provider-agnostic
core. **Read it before any work**: the decision log (§1), crate responsibilities (§4), core
contracts (§5), and milestone sequence (§9) define what to build and in what order. If a
request conflicts with `RECIPE.md`, surface the conflict rather than silently diverging.

Companion docs: `README.md` (user-facing overview + flags), `docs/ATO.md` (the tuner internals),
and `bench/README.md` (the measured head-to-head vs. the Dirac agent + the benchmark harness —
methodology, measured $/task on `gemini-3-flash-preview`, real-upstream-test correctness, and per-model
re-pricing; re-derive from its §3 prices when they move).

Milestones done (per §9): **M0** workspace + `lvz-protocol` contracts · **M1** xAI
OpenAI-compat first light · **M2** SSE streaming · **M3** `lvz-anthropic` native Messages API
+ caching + thinking · **M4** `lvz-agent` plan→act→observe loop + `lvz-tools` (fs + shell),
OpenAI tool-calling through `lvz-xai` · **M5** `lvz-context` token engine — tree-sitter
skeletons (Rust/Python/JS/TS), **recursive symbol-dependency graph** driving the
skeleton-radius knob `N`, hash-anchored edits, token-efficient diffs, plus the **budget-fixture
CI loop (§6.5)** (`tests/budget.rs`, committed per-archetype token ceilings). Surfaced to the
agent as `outline_file` (with optional `focus`/`radius`), `read_anchored`, `edit_anchored`.

Crates that exist today: `lvz-protocol`, `lvz-xai`, `lvz-anthropic`, `lvz-google`,
`lvz-claude-cli`, `lvz-context`, `lvz-tools`, `lvz-agent`, `lvz-memory`, `lvz-tune`, `lvz-gw-http`,
`lvz-gw-matrix`, `lvz-cli`. (A Discord gateway was considered and dropped — out of scope.
`lvz-google` was added 2026-06-12, relaxing the Anthropic+xAI-only provider scope — see §1.)

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
A **context-budget manager** (`AgentConfig.context_limit`) adds a soft *per-request* ceiling:
when the assembled history still exceeds it after compaction, `evict_to_fit` replaces the
oldest tool-result content with a `[evicted: N bytes …]` placeholder (oldest = least relevant),
preserving the task, the recent window, and all `tool_use`/`tool_result` pairing. Exposed on
the CLI as `--summary-model` / `--compact-after` / `--context-limit` (agent mode).
The tuner's `TaskContext` is now **real**, not stubbed: `classify_archetype` maps the prompt
to an `Archetype` via a deterministic keyword heuristic (no extra round-trip), and
`profile_repo` does a bounded, build-dir-skipping walk of `AgentConfig.repo_root` (set to cwd
by the CLI in agent mode) for a `RepoProfile` (file count, bytes, primary language). The
optional §6.3 extras also landed: **deduplication** (`dedup_tool_results` collapses
byte-identical repeated tool results, keeping the most recent copy) and **output
minimisation** (the system prompt now tells the model not to echo file contents/tool output
and to let `edit_anchored`'s diff stand as the change record). **64 tests passing**, clippy +
fmt clean. **Compaction verified live** against Anthropic
(`claude-sonnet-4-6` main,
`claude-haiku-4-5` summaries): a sequential edit task triggered a real Haiku-routed summary
call and the reshaped history (task + summary note + recent turns) was accepted by the API —
the agent compacted, continued, and finished cleanly. (Note observed live: the model batches
independent tool calls into one parallel turn, so compaction only fires on genuinely
sequential workflows that accumulate ≥3 turn-pairs.)

### What's left to do (milestone order, `RECIPE.md` §9)

- **M6 — efficiency hardening (complete).** ✅ Tuner/Knobs wired into the agent, history
  compaction (live-verified), model routing for summaries, tool-result truncation,
  context-budget manager (relevance-ranked eviction), task classification + repo profiling
  feeding a real `TaskContext`, and the optional §6.3 extras (context deduplication + output
  minimisation). (`--summary-model`/`--compact-after`/`--context-limit` exposed; all
  mechanisms unit-tested, compaction also live-verified.)
- **M7 — xAI gRPC (complete, live-verified 2026-06-11).**
  Done: `xai-org/xai-proto` vendored into `proto/` at pinned commit `543b901d` (Apache-2.0;
  provenance + update procedure in `proto/VENDOR.md`); `tonic-prost-build` codegen in
  `crates/lvz-xai/build.rs` (client-only tonic 0.14 stack:
  `tonic`/`tonic-prost`/`prost`/`prost-types` workspace deps; **requires `protoc`**, e.g.
  `brew install protobuf`; workspace **MSRV 1.88** for tonic 0.14); and the **gRPC transport
  itself**. `lvz-xai` is now split into modules: `grpc.rs` (native path + `pub mod pb {
  include_proto!("xai_api") }`), `http.rs` (the OpenAI-compat fallback, formerly `lib.rs`),
  and a thin `lib.rs` dispatcher. `XaiProvider` is an `enum { Grpc(GrpcTransport),
  Http(HttpTransport) }`; `from_env` reads **`XAI_TRANSPORT` (`grpc`|`http`, default `http`)**
  plus `XAI_GRPC_ENDPOINT` (default `https://api.x.ai`) / `XAI_BASE_URL`. The gRPC path opens
  a TLS `Channel` (`ClientTlsConfig::new().with_webpki_roots()`), calls server-streaming
  `Chat.GetCompletionChunk` with a per-request `authorization: Bearer` metadata header, and a
  `Decoder` normalises each `GetChatCompletionChunk`: `Delta{content}`→`TextDelta`,
  `reasoning_content`→`Thinking`, `tool_calls` (correlated by id; arg-only chunks attach to
  the last open id)→`ToolUseStart/Delta/End`, per-chunk cumulative `SamplingUsage`→`Usage`
  (`cached_prompt_text_tokens`→`cache_read_tokens`; `input_tokens = prompt − cached`; agent
  takes last-wins), `FinishReason`→`StopReason` (STOP→EndTurn, MAX_LEN/MAX_CONTEXT→MaxTokens,
  TOOL_CALLS→ToolUse, TIME_LIMIT→Other). Request mapping: system→`ROLE_SYSTEM`,
  assistant `ToolUse`→`tool_calls{FunctionCall}`, user `ToolResult`→`ROLE_TOOL` msg with
  `tool_call_id`, tooldefs→`Tool{Function{parameters: JSON-string}}`. `Capabilities` on the
  gRPC path: `server_side_tools=true`, `parallel_tool_use=true`, caching/thinking `false`
  (xAI caches automatically; we don't echo request-side cache markers or thinking blocks).
  **70 tests pass** (5 new gRPC mapping/decoder tests in `grpc.rs`), clippy + fmt clean; the
  generated `pb` module carries `#[allow(clippy::all, dead_code, rustdoc::all)]` (full service
  surface generated, only `Chat` streaming consumed). **Live-verified** against the real
  `XAI_API_KEY` with `XAI_TRANSPORT=grpc` (model `grok-4`): `api.x.ai` **is** publicly
  reachable over gRPC — a streaming turn produced text + reasoning(thinking) deltas, a
  populated `cache_read` usage (xAI returned cached prompt tokens), and a clean
  `Done(EndTurn)`; and the agent tool loop ran a `shell` call over gRPC (ToolUse args JSON
  reassembled, `ROLE_TOOL` result fed back, final answer) end-to-end. **gRPC is now the
  default transport** (`from_env` defaults `XAI_TRANSPORT` to `grpc`, per RECIPE §8 "primary
  transport"); set `XAI_TRANSPORT=http` for the OpenAI-compat fallback. Possible follow-up: a
  `--xai-transport` CLI flag (today it's env-only). Note: the protos' package is `xai_api`
  (path `xai/api/v1`) — the "outputs"-style API RECIPE calls "proto v6"
  (`repeated CompletionOutputChunk outputs`).
- **M8 — gateway layer (complete, live-verified 2026-06-11).** `lvz-gw-http` is the first
  concrete `Gateway`: an axum 0.8 HTTP server fronting the shared agent via `AgentHandle`,
  depending **only** on `lvz-protocol` (not on any provider or on `lvz-agent` internals).
  Surface: `GET /health`, `POST /v1/turns` (`{session?, input}` → the `Event` stream as
  **SSE**, one JSON event per `data:` frame), `GET /v1/ws` (a **WebSocket**: one turn JSON
  per message, events streamed back as JSON text frames, socket stays open for more turns).
  The wire format required making `Event` serializable: it was **internally** tagged
  (`#[serde(tag="kind")]`), which *errors at runtime* for newtype variants wrapping a
  primitive (`TextDelta(String)`, `Done(StopReason)`) — switched to **adjacent tagging**
  (`#[serde(tag="kind", content="data")]` → `{"kind":"text_delta","data":"hi"}`), with a
  per-variant round-trip test in `event.rs`. The CLI gained **`--serve <host:port>`** (builds
  the same tool-using agent as `--agent` via a shared `build_agent`, then runs the gateway;
  no prompt needed). **Live-verified**: `lavoisier --serve` over the default xAI gRPC
  transport answered a real `POST /v1/turns` with a correct SSE stream (thinking + text
  deltas, usage incl. `cache_read`, `done`). 78 tests pass (6 new in `lvz-gw-http`: unit
  encoders + a real-listener HTTP/SSE integration test against a stub `AgentHandle`), clippy +
  fmt clean. **Note:** the agent is still per-turn stateless — `submit` ignores `turn.session`
  (no persisted multi-session history yet; that's M9 `lvz-memory` + session isolation). No
  auth/quotas yet (M9). A `lvz-gateway` registry crate was *not* needed (the `Gateway` trait
  already lives in `lvz-protocol`).
- **M9 — Hermes gateways + features (complete, 2026-06-11).** Four units,
  each committed separately:
  - **`lvz-memory` (session continuity).** `Agent::run_seeded(Vec<Message>)` lets a caller
    seed a turn with prior history (`run` delegates to it; `run_loop` classifies against the
    latest user turn). New feature crate over `lvz-agent` + `lvz-protocol`: a `SessionStore`
    trait + `InMemoryStore`, and `SessionAgent` — an `AgentHandle` that loads a session's
    transcript, seeds the turn, runs, and (on clean `Done`) appends the assistant answer and
    persists. Transcript stays a clean user/assistant turn list (no intra-task tool blocks).
    `--serve` wraps the agent in `SessionAgent`+`InMemoryStore`, so `turn.session` is finally
    load-bearing. **Live-verified** over the HTTP gateway: same session recalled a fact across
    turns; a different session stayed isolated.
  - **Auth + quotas (`lvz-gw-http`).** `GatewayConfig{api_keys, rate_limit}` + a `route_layer`
    guard on `/v1/turns`+`/v1/ws`: API-key auth (`Authorization: Bearer`; empty set = open)
    then a per-principal fixed-window rate limiter (429 past quota). `/health`+`/metrics`
    stay open. CLI `--api-key` (repeatable) / `--rate-limit <N per 60s>`.
  - **Observability (`lvz-gw-http`).** A `Metrics` recorder (atomic counters: turns, errors,
    input/output tokens, cache read/creation, summed latency) fed by a per-turn stream tap
    (records the agent's single terminal `Usage`, last-wins). `GET /metrics` exposes
    Prometheus text (v0.0.4) — scrape directly or bridge to OTLP at the collector, no heavy
    exporter dep. *(This closes the §6.4 "no telemetry export" debt for the gateway path.)*
  - **`lvz-gw-matrix` (Matrix gateway).** A **thin reqwest** client over the Matrix
    client-server REST API (login + `/sync` long-poll + `m.room.message` send) — *not*
    `matrix-sdk` (chosen to honour the minimal-deps convention; **unencrypted rooms only, no
    E2EE**). Each inbound `m.text` from another user runs a turn with `session = room id`
    (per-room continuity via `lvz-memory`); the answer posts back. Depends only on
    `lvz-protocol`. CLI `--serve-matrix` (env `MATRIX_HOMESERVER`/`MATRIX_USER`/
    `MATRIX_PASSWORD`). **Not live-verified** (needs a homeserver + bot account); the wire
    mapping (sync→messages, self/non-text skipping, room-id encoding) is unit-tested.
  86 tests pass; clippy + fmt clean.
- **M10 — Hermes deployment (artifacts complete, local-verified 2026-06-11; AWS apply pending
  the user).** Packaging + IaC for the HTTP gateway on **AWS Fargate, arm64, us-west-2**, per
  RECIPE §10 (Podman not Docker; secrets via Secrets Manager). Deliverables:
  - **`Containerfile`** (+ `.containerignore`): multi-stage `linux/arm64`. Builder
    `rust:1.88-bookworm` installs `protoc` (needed by `lvz-xai/build.rs`) and `cargo build
    --release -p lvz-cli`; runtime `distroless/cc-debian12:nonroot` (glibc/libgcc for `ring`,
    CA certs, no shell; rustls/webpki so no OpenSSL), `CMD ["--serve","0.0.0.0:8080"]`.
  - **`infra/terraform/`** (Terraform ≥1.5, AWS provider ~5): ECR repo; minimal public-subnet
    VPC (2 AZs, IGW, no NAT — tasks get public IPs for egress); internet-facing ALB → target
    group on :8080 with `/health` checks (WS upgrades pass through); ECS Fargate cluster +
    task def with `runtime_platform.cpu_architecture = "ARM64"`, `awslogs`, env
    (`XAI_TRANSPORT=grpc`, `LVZ_RATE_LIMIT`) + **secrets from Secrets Manager**
    (`XAI_API_KEY`, `LVZ_API_KEYS`); service with `assign_public_ip`; locked SGs (ALB→task
    only); IAM execution role with scoped `secretsmanager:GetSecretValue`. `terraform validate`
    passes; `outputs` give the ALB DNS + ECR URL.
  - **`infra/scripts/`**: `build-and-push.zsh` (`podman build --platform linux/arm64` + ECR
    push) and `deploy.zsh` (`terraform apply` + force a fresh ECS deployment). **`infra/README.md`**
    is the runbook (create secrets → `apply -target` ECR → build/push → deploy → smoke-test →
    teardown), with cost + `/metrics`-exposure caveats.
  - **Code:** `--api-key`/`--rate-limit`/`--serve` gained clap `env=`
    (`LVZ_API_KEYS` comma-split / `LVZ_RATE_LIMIT` / `LVZ_SERVE_ADDR`) so Secrets Manager
    injects via env, not the task command line.
  - **Verified locally:** cargo build/test/clippy/fmt green (86 tests); `terraform fmt` +
    `validate` clean; the arm64 image builds with Podman and `--serve` answers a real
    `POST /v1/turns` over xAI gRPC (`/health`, `/metrics`, 401/429 all correct). **Not** applied
    to AWS (no creds/spend here) — the runbook drives that. HTTP gateway only; Matrix deploy
    deferred (no inbound port; separate service).
- **Optional tracks (done; live AWS apply + live Matrix still pending).**
  - **`lvz-tune` (ATO §6.6) — built, full §10 roadmap landed (incl. Bayesian opt).** `LearningTuner`:
    an ε-greedy hill-climb bandit over `Knobs`, keyed by `(archetype, caching, model-tier,
    model_id, repo_id)`, exploiting the cheapest *trusted* (success-rate ≥ target) vector — ties broken
    toward least context carried — and exploring one-step neighbours on a discrete grid centred
    on `Knobs::default()` (the floor it can't regress below). CLI `--tune` swaps it in (precedence
    over `--compact-after`). **Full mechanism in `docs/ATO.md`.** The 2026-06-11 ATO-roadmap
    increment wired the deferred items: **(1) a real success signal** — `--verify-cmd <cmd>` runs
    a post-task shell gate (e.g. `cargo test`); exit 0 ⇒ `Outcome.success`, else the coarse
    "completed without error" fallback; **(2) all four knobs now bite** — `skeleton_radius` is
    injected into focused `outline_file` calls, `batch_width` drives a parallel-tool-use
    system-prompt hint (alongside the already-live `compact_after`/`truncate_bytes`); **(3) two
    counterfactuals** — (a) the **exact** truncate one (always on): when truncation never fired,
    cheaper truncate-grid values still ≥ the largest tool result are credited with the identical
    (byte-for-byte) outcome, no live trial (`Outcome.max_tool_result_bytes` carries the signal);
    (b) the **estimated** radius one (opt-in `--radius-counterfactual`, off by default, *unsound*):
    `lvz-agent` snapshots knob-governed `outline_file` skeletons and, post-task, re-extracts them
    at smaller radii to estimate the saving and credits those radii with the optimistically-
    transferred success bit; **(4) model-version keying** — `TaskContext.model_id` in the
    `ContextKey` so a model upgrade starts a fresh profile; **(5) persistence** — `--tune-state
    <path>` (JSON save/load of profiles + PRNG across restarts via a `PersistentTuner` wrapper).
    Live-verified vs Anthropic: `--verify-cmd` exit-code gating (pass→successes 1, fail→0) and the
    radius counterfactual (a `skeleton_radius:0` row credited alongside the realised `:1`). The
    2026-06-12 batch closed the rest: **per-repo profiles** (`repo_id` in the `ContextKey`),
    **observation decay** (`TuneConfig.decay` EWMA, CLI `--tune-decay`), **downstream-effect
    modelling** (the radius counterfactual scales each saving by a *residency* factor — turns the
    skeleton was re-sent — collapsing to 1 under caching), and **Bayesian optimisation**:
    `BayesTuner` (`bayes.rs`), a Thompson-sampling alternative (Beta posterior over success +
    Gaussian over cost per knob vector; samples and picks the cheapest feasible draw; hand-rolled
    Box–Muller/Marsaglia–Tsang/Beta samplers, no extra deps), opt-in via `--tune-bayes` (implies
    `--tune`, precedence over it). It **persists** like the hill-climb: `BayesTuner::save`/`load`
    snapshot the posteriors, so `--tune-state` works with `--tune-bayes` too (both via the shared
    `PersistableTuner` wrapper). Pair `--tune` with `--verify-cmd` for a production-grade signal;
    `--tune`/`--tune-bayes` alone (and `--radius-counterfactual`) stay experimental. Only deferred
    now: the radius counterfactual modelling the model's altered *reasoning* (not just
    skeleton-input bytes).
  - **`lvz-claude-cli` — built, off by default.** A `Provider` shelling out to `claude -p`
    (`--output-format stream-json`), stream-json → `Event`; `Capabilities` all false (no
    caching). Selected only via `--provider claude-cli` (default model `sonnet`; `CLAUDE_CLI_BIN`
    overrides). Personal/low-volume only (Agent SDK credit cap, policy-fragile). Wire mapping
    unit-tested; not live-verified (needs a `claude` install + subscription).
  - **Advisor mode (§8 cost levers in `lvz-agent`) — built, live-verified vs Anthropic.**
    *Cheap-model-first* (`cheap_model` + `escalate_after`): the loop runs the first N
    round-trips on a cheap model, then escalates to `model`. *Advisor+executor split*
    (`advisor_model`): a tool-less pre-pass on a **smarter, more expensive** model (e.g. Opus)
    drafts a plan that seeds the **cheaper** executor (the main `model`, e.g. Sonnet) as its
    opening move — the expensive model is paid for once while the cheap model runs the many
    execution turns (advisor tokens count toward the task total). Provider-agnostic (model ids
    only). CLI `--cheap-model` / `--escalate-after` / `--advisor-model`, composable, opt-in.

### Known debts inside shipped code (pick up before/with the above)

- **Tuner: all four knobs now wired; success signal can now be real.** `lvz-agent` calls
  `Tuner::select`/`observe` with a **real** `TaskContext` (classified `Archetype` + walked
  `RepoProfile` + `model_id`) and honours all of `compact_after`, `truncate_bytes`,
  `skeleton_radius` (injected into focused `outline_file`/`outline_files` calls), and
  `batch_width` (caps the `read_files`/`outline_files` `paths` array + steers the prompt). The
  success signal is real when `--verify-cmd` is set (post-task exit-code gate), else the coarse
  completion fallback. Archetype classification defaults to the keyword heuristic but can use a
  model call (`--classify-with-model`, opt-in, routed to `--summary-model`). The default tuner is
  still `NoopTuner` (ATO is opt-in via `--tune`, or `--tune-bayes` for the Thompson-sampling
  variant). The §10 roadmap is fully landed (per-repo keying, observation decay, the radius
  counterfactual's residency-scaled downstream model, and Bayesian optimisation); only on-disk
  `BayesTuner` persistence and deeper (reasoning-level) radius modelling remain (`docs/ATO.md` §10).
- **Telemetry (§6.4).** Usage is aggregated, the `--budget` ceiling is enforced, the
  **HTTP gateway exports Prometheus `/metrics`** (tokens, cache read/creation, turns,
  errors, summed latency), and the **CLI/agent path now has an in-process hook** —
  `Agent::with_telemetry(Arc<dyn TelemetrySink>)` emits a per-task `TaskTelemetry`, surfaced
  by `--telemetry` (one-shot `--agent` runs print a stderr summary line). The per-task ATO
  success signal exists (`--verify-cmd`). Still missing: cache-hit-rate as its own `/metrics`
  gauge (it's derivable from the exported counters but not surfaced separately).
- **Skeleton fidelity.** Python docstrings are now **kept** when a body is elided
  (`LangSpec.keeps_docstring`; the skeletoniser elides only the post-docstring range and
  re-indents the placeholder). The symbol-dependency graph is now **AST-resolved + scope-aware**:
  edges come from real `identifier`/`type_identifier` nodes (not substring search) minus
  locally-bound names, so names in strings/comments and shadowing locals no longer create spurious
  edges (`lvz-context::symbols`, per-language `ref_ident_kinds`/`binder_kinds`). Still name-keyed,
  not a full semantic index — same-named symbols across files merge and there's no import/visibility
  resolution (fine for `N`). `outline_file --focus` builds a single-file graph (the multi-file graph
  is used by the budget loop, not the tool).
- **Multi-file batching (§6.1)** is implemented: `read_files`/`outline_files` batch tools (take a
  `paths` array, return per-file sections under `===== <path> =====` headers, inline per-file
  read errors), the `batch_width` knob caps the `paths` array agent-side (`apply_knobs_to_args`),
  and `system_with_knobs` steers the model to the batch tools. Live-verified (one `read_files`
  call fetched 3 files in one round-trip).
- **`find_references` tool (`lvz-tools::search`)** — repo-wide "where is this name used?" in one
  call: a bounded, build-dir-skipping walk that returns the **complete** reference set grouped by
  file with a total count. For known languages it matches identifier nodes via
  `lvz_context::symbols::find_identifier_lines` (AST-precise — mentions in strings/comments don't
  count; returns `Option`, `None` only on parse failure so callers don't text-fall-back on a clean
  parse), with a word-boundary text scan for other files. Added to fix the **convergence gap** the
  Dirac benchmark surfaced (the model otherwise loops on ad-hoc `grep -r`/`sed` with no "that's all
  of them" signal — see `bench/README.md` Findings #2); the default system prompt now steers to it
  and tells the model to stop once it has the full set. Unit-tested + scale-smoked vs the django
  checkout (`#[ignore]`d `find_references_scale_smoke`, `LVZ_SMOKE_DIR`/`LVZ_SMOKE_NAME`).
- **Cache-aware repo-skeleton prefix (§6.1) — implemented.** `AgentConfig.repo_skeleton:
  Option<usize>` (CLI `--repo-skeleton <TOKENS>`): `build_repo_skeleton` does a bounded, sorted
  (deterministic ⇒ byte-stable) walk of `repo_root`, tree-sitter–skeletonises every source file to
  a token budget, and the result is built **once** (memoised in an `Arc<OnceLock>` on the `Agent`)
  and injected by `build_request` as the **first content block of the first user message**, marked
  cacheable. Ordered immutable→stable→volatile, it extends the cached prefix (system + tool defs +
  skeleton) ahead of the volatile conversation, so a caching provider pays for it once and re-reads
  it cheaply each later round-trip / same-repo task. Off by default; most valuable with Anthropic
  caching + a long-running `--serve`. Unit-tested (determinism, budget, cached-prefix injection)
  and **live-verified vs Anthropic** (`claude-haiku-4-5`, `--repo-skeleton 4000`): a 2-round-trip
  task showed the prefix `cache_creation` on turn 1 then `cache_read` on turn 2 (~99% cache hit).
  Caching now marks the system prompt, the last tool def, **and** the repo-skeleton block.

### Gotchas

- **Building `lvz-xai` requires `protoc`** (`brew install protobuf`) — `build.rs` compiles the
  vendored `proto/xai/api/v1/chat.proto` via `tonic-prost-build`. Pinned upstream commit and
  update procedure live in `proto/VENDOR.md`.
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
XAI_API_KEY=… cargo run -p lvz-cli -- "your prompt"                 # one streaming turn (xAI, gRPC default)
ANTHROPIC_API_KEY=… cargo run -p lvz-cli -- --provider anthropic "…"  # Anthropic native
XAI_API_KEY=… cargo run -p lvz-cli -- --agent "edit task here"      # M4 tool-using agent loop
XAI_API_KEY=… cargo run -p lvz-cli -- --serve 127.0.0.1:8080        # M8/M9 HTTP/WS gateway (+ session memory)
MATRIX_HOMESERVER=… MATRIX_USER=… MATRIX_PASSWORD=… \
  XAI_API_KEY=… cargo run -p lvz-cli -- --serve-matrix              # M9 Matrix gateway (one room per session)
```

CLI flags: `--agent` (tool loop), `--serve <host:port>` (HTTP/WS gateway; sessions persisted
in-memory), `--serve-matrix` (Matrix gateway), `--api-key <KEY>` (repeatable) / `--rate-limit
<N per 60s>` (gateway auth/quota), `--provider xai|anthropic|claude-cli`, `--model`,
`--max-tokens`, `--system`, `--budget` (total-task token ceiling),
`--summary-model`/`--compact-after`/`--context-limit` (agent efficiency knobs), `--tune`
(ε-greedy ATO learner) or `--tune-bayes` (Thompson-sampling variant) with `--verify-cmd <cmd>`
(post-task success gate), `--tune-state <path>` (persist learned profiles; `--tune` only),
`--tune-decay <F>` (observation-decay EWMA) and `--radius-counterfactual` (opt-in, unsound radius
counterfactual), `--telemetry` (per-task stderr summary), `--classify-with-model` (model archetype
classification), `--repo-skeleton <TOKENS>` (cache-aware repo-skeleton prefix, §6.1),
`--cheap-model`/`--escalate-after` (cheap-model-first) and `--advisor-model` (advisor+executor
split) for §8 cost reduction. Gateway HTTP
routes: `GET /health`, `GET /metrics` (Prometheus), `POST /v1/turns` (SSE), `GET /v1/ws`
(WebSocket). Env: `XAI_API_KEY`/`XAI_BASE_URL`/`XAI_GRPC_ENDPOINT`, **`XAI_TRANSPORT=grpc|http`
(default `grpc`)**, `ANTHROPIC_API_KEY`/`ANTHROPIC_BASE_URL`,
`MATRIX_HOMESERVER`/`MATRIX_USER`/`MATRIX_PASSWORD`, `LVZ_PROVIDER`, `LVZ_MODEL`,
`LVZ_API_KEYS` (comma-separated gateway keys) / `LVZ_RATE_LIMIT` / `LVZ_SERVE_ADDR`. A local SSE
mock can be pointed at via `*_BASE_URL` to test the HTTP path without a live key.

```sh
# Deploy (M10 — AWS Fargate arm64, us-west-2; see infra/README.md for the full runbook):
podman build --platform linux/arm64 -f Containerfile -t lavoisier:dev .   # arm64 image (Podman)
./infra/scripts/build-and-push.zsh dev   # push to ECR   ./infra/scripts/deploy.zsh   # terraform apply
```

All M0–M10 milestones are complete. The optional tracks are built: `lvz-tune` (ATO; full §10
roadmap landed, both counterfactuals shipped), `lvz-claude-cli`, and advisor mode. A Discord
gateway is **out of scope** (dropped at user request — do not build it). Remaining: live
verification of `lvz-claude-cli` (needs a subscription) and the Matrix gateway (needs a
homeserver); the M10 AWS apply itself (artifacts ship local-verified — run `infra/README.md`
against a real account); and the deferred polish (Python docstring fidelity, on-disk `BayesTuner`
persistence, deeper reasoning-level radius modelling).

## Conventions

- **Rust** Cargo workspace; pin edition + MSRV in the root `Cargo.toml`. Correctness via
  sum types + exhaustive `match`.
- Async: **tokio**; HTTP: **reqwest**; JSON: **serde** / **serde_json**; gRPC: **tonic** +
  **prost** (xAI codegen from vendored `proto/`).
- Scripts: **zsh**. Local service shells: **Podman** (not Docker).
- Keep dependencies minimal and vendor-agnostic; avoid heavyweight agent frameworks. The
  stale Anthropic-native Rust crates (`anthropic*`, `clust`, `misanthropy`) are **not** to be
  depended on — hand-roll a thin `reqwest` adapter to retain caching + extended thinking.
- Providers in scope: **Anthropic + xAI native**, plus **Google Gemini** (`lvz-google`, added
  2026-06-12 at the owner's explicit request to enable same-model benchmarking vs. agents that run
  on `gemini-3-flash-preview` — see `bench/README.md`). OpenAI and other providers remain out of
  scope. (This relaxes the original "Anthropic + xAI native only" decision; `RECIPE.md` §1 records it.)
  **Live-verified** against the real Gemini API (`gemini-3-flash-preview`, `--thinking high`): a
  streaming turn plus the agent tool loop end-to-end (functionCall decode, tool-result round-trip,
  implicit `cache_read`, clean `EndTurn`). Live testing surfaced + fixed one bug: Gemini 3 thinking
  attaches a `thoughtSignature` to each functionCall that **must be echoed back on resend** (else a
  400) — `lvz-google` round-trips it through the opaque tool-call id (`call_{n}#{sig}`), contained
  to the adapter (no protocol change).
- Secrets: read from env / AWS Secrets Manager at runtime; never commit keys.
- License: prefer **Apache-2.0** (aligns with xai-proto) or MIT.
