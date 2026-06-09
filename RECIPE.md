# RECIPE.md — Lavoisier

> A modular, **token-efficient** CLI coding agent in Rust with a provider-agnostic core
> (Anthropic + xAI native).
> Designed for reuse as the core of a Hermes-level multi-gateway agent.
> This is a **build blueprint** for a later Claude-coding session — it specifies
> interfaces and decisions, not implementations.

---

## 0. Naming

- **Project / binary:** `lavoisier` (short alias `lav`).
  - Physicist-surname-encodes-the-concept pattern, mirroring Dirac. Lavoisier coined
    "oxidation" → the origin of the rust concept.
- **Namespace status (verified):** crate `lavoisier` free on crates.io; GitHub handle
  `lavoisier` free. Reserve both before first push.
- **Crates:** workspace members prefixed `lvz-`.
- Distinct from the separate Haskell compiler project (acronym ending in `HC`); no overlap.

---

## 1. Decision log (with calibration)

| Decision | Choice | Confidence | Rationale |
|---|---|---|---|
| Language | Rust | 0.70 | CLI-first → single static binary, instant cold start, no venv/node_modules. Correctness via sum types + exhaustive match. Speed is *not* the reason (workload is I/O-bound). |
| Why not dynamic | Rejected for shipping | 0.75 | Dynamic typing only wins the exploratory prompt-tuning phase; cost fades once design stabilises. |
| Why not TypeScript | Rejected | 0.60 | TS is only forced if VS-Code-extension-first. This is CLI-only, so the extension-host constraint does not apply. |
| OCaml (alt) | Considered, not chosen | 0.40 | Faster compiles + ADTs suit the FP mental model; loses on single-binary distribution and ecosystem breadth. |
| Anthropic transport | Native Messages API over **SSE** | 0.95 | Anthropic has **no gRPC**. SSE is streaming-native and adequate. Native path required to keep **prompt caching** + extended thinking. |
| xAI transport | gRPC (codegen from official protos) + **in-crate** OpenAI-compat fallback | 0.65 | Public protos exist (`xai-org/xai-proto`, Apache-2.0). gRPC exposes native server-side tools (proto v6 "outputs"). Fallback transport lives inside `lvz-xai`, still hitting `api.x.ai`. |
| xAI client strategy | Generate from official `.proto` via `tonic-build` | 0.70 | Avoids depending on the 3-week-old community `xai-sdk` crate (single maintainer). Full control, official source. |
| gRPC as architecture | **No** — isolate behind normalised stream | 0.90 | Anthropic can't speak gRPC. Transport must not leak into the agent core, or cross-provider reuse breaks. |
| "gRPC is faster" premise | Largely irrelevant here | 0.85 | LLM latency is dominated by TTFT + tokens/sec (seconds), not transport (sub-ms). gRPC shines for high-frequency small RPCs — the opposite profile. |
| Token efficiency | First-class design goal (Dirac-parity+) | 0.90 | Single biggest cost/latency lever for this workload. Concentrated in `lvz-context` + caching; see §6. |
| Provider scope | Anthropic + xAI **native only** | 0.90 | Drop the generic OpenAI/multi-provider crate. Fewer deps, matches minimalist taste. Other providers explicitly out of scope. |
| Claude subscription | Optional `lvz-claude-cli`, no caching | 0.60 | Rides Claude Code `claude -p`; capped by Agent SDK credit (from 2026-06-15) and cannot cache. Personal/low-volume only — never Hermes. |
| Adaptive token optimisation | Online knob-tuning loop, **quality-gated** | 0.70 | Measure the variables efficiency depends on + realised tokens, adapt knobs toward lower usage. Only safe with a task-success constraint; seeded/bounded by the §6.5 offline loop. See §6.6. |
| Multi-gateway | Deferred to Hermes tier, designed-for now | 0.85 | A `Gateway` trait (peer to `Tool`) keeps the core frontend-agnostic; see §7. |

---

## 2. SDK landscape (verified, June 2026)

**Anthropic official SDKs:** Python, TypeScript, Java, Go, Ruby, C#, PHP, CLI. **No Rust.**
Transport: HTTP/REST + SSE streaming (`content_block_delta` etc.). No gRPC.

**xAI:** official Python SDK (gRPC-native, `api.x.ai:443`); Vercel AI SDK for JS/TS.
Public protobufs at `xai-org/xai-proto` (Apache-2.0). Anthropic-SDK *compatibility* is
**deprecated** — do not build on it. OpenAI-compat REST (`https://api.x.ai/v1`) is stable.

**Rust crate health (crates.io):**

| Crate | Downloads | Last update | Use? |
|---|---|---|---|
| `async-openai` | 5.4M | 2026-06-04 | ~ optional for the xAI OpenAI-compat fallback; hand-rolling the single POST is lighter |
| `tonic` + `prost` | — | active | ✓ gRPC codegen for xAI |
| `anthropic*` / `clust` / `misanthropy` | tiny | 2024–25, stale | ✗ all pre-1.0 / abandoned — do not depend |

**Implication:** every Anthropic-native Rust crate is stale. Hand-roll a thin Anthropic
adapter over `reqwest` to retain caching + thinking. This matches the minimal-footprint goal.

**Claude subscription path (optional, see §8):** a third-party agent can ride Claude Code's
`claude -p` (subscription OAuth) instead of an API key. From **2026-06-15** this draws from a
capped monthly Agent SDK credit ($20 Pro), then API rates — not flat-rate — and **cannot use
prompt caching**. Useful for personal low-volume runs only.

---

## 3. Architecture overview

Cargo workspace, trait-segmented so the agent core is reusable by both the CLI and a
future Fargate-hosted Hermes agent with many gateways.

```
lavoisier/
├─ Cargo.toml            # [workspace]
├─ RECIPE.md
├─ crates/
│  ├─ lvz-protocol/      # contracts + normalised types. ZERO provider deps.
│  ├─ lvz-anthropic/     # Messages API over SSE + cache-control
│  ├─ lvz-xai/           # gRPC (tonic, codegen from xai-proto) + in-crate OpenAI-compat fallback
│  ├─ lvz-claude-cli/    # [optional] shells `claude -p`; subscription auth, NO caching
│  ├─ lvz-context/       # token-efficiency engine: skeletons, AST edits, diffs, batching
│  ├─ lvz-agent/         # plan→act→observe loop. Provider- & gateway-agnostic.
│  ├─ lvz-tune/          # [optional] adaptive token optimisation: learns knob settings from telemetry
│  ├─ lvz-tools/         # Tool trait + built-ins (fs, shell, browser). Pluggable.
│  ├─ lvz-gateway/       # Gateway trait + registry. Frontends/channels. [Hermes tier]
│  ├─ lvz-gw-http/       # HTTP/REST + WebSocket gateway
│  ├─ lvz-gw-matrix/     # Matrix (Continuwuity) gateway
│  ├─ lvz-gw-discord/    # Discord gateway
│  └─ lvz-cli/           # thin binary `lavoisier` (the first gateway)
└─ proto/                # vendored xai-proto (git submodule or pinned copy)
```

Dependency direction (only inward → core); `lvz-tune` is an optional advisor feeding `lvz-agent`:

```
            ┌──────────── gateways (peers) ────────────┐
  lvz-cli   lvz-gw-http   lvz-gw-matrix   lvz-gw-discord
     └──────────┴───────────┬───────────────┘
                            ▼
   lvz-tune  ⇄  lvz-agent ──► lvz-protocol ◄── lvz-anthropic
   [optional]      │              ▲     ▲ ◄── lvz-xai
                   ├──► lvz-tools ┘     │ ◄── lvz-claude-cli [opt]
                   └──► lvz-context ────┘
```

`lvz-protocol` is the keystone: every other crate depends on it; it depends on nothing
provider- or gateway-specific. Swapping a transport, adding a provider, or adding a gateway
never touches the core. `lvz-tune` only reads telemetry and returns knob settings — the agent
runs fine without it.

---

## 4. Crate responsibilities

- **`lvz-protocol`** — the only stable public contract. Defines `Provider`, `Tool`,
  `Gateway`, `Tuner`, `Capabilities`, the normalised `Event` stream, request/response message
  types, and error types. No I/O. No provider/gateway knowledge.
- **`lvz-anthropic`** — implements `Provider` for the Claude Messages API. Owns SSE
  parsing, `cache_control` blocks, extended-thinking blocks, fine-grained tool streaming.
- **`lvz-xai`** — implements `Provider` for xAI. Primary path: gRPC via `tonic-build`
  codegen from `proto/` (supports v6 "outputs" / server-side tools). Fallback: an **in-crate**
  OpenAI-compat transport against `api.x.ai/v1` (runtime switch) — no separate crate.
- **`lvz-claude-cli`** *(optional)* — implements `Provider` by shelling out to Claude Code
  `claude -p` (subscription OAuth, not an API key). Reports `prompt_caching: false`. Subject
  to the Agent SDK credit cap from 2026-06-15 (§8). Personal/low-volume only.
- **`lvz-context`** — token-efficiency engine (§6): file-skeleton extraction, recursive
  symbol dependency tracking, hash-anchored + AST-native edits, token-efficient diffs,
  multi-file batching, context budgeting/eviction. Exposes the tunable knobs (§6.5–6.6).
- **`lvz-agent`** — the reasoning loop. Consumes only `Event`, `Tool`, and a curated
  context. Owns turn orchestration, model routing, history compaction, tool dispatch,
  retries, cancellation, token/cost accounting. Asks `lvz-tune` (if present) for `Knobs` per
  task and reports `Outcome` back. Never sees a wire protocol or a gateway.
- **`lvz-tune`** *(optional)* — adaptive token optimisation (§6.6). Consumes per-task
  telemetry (context features + realised tokens + success signal), maintains per-archetype /
  per-repo knob profiles, and advises `lvz-agent` which `Knobs` to use next. Pure bookkeeping;
  near-zero token overhead. Off by default.
- **`lvz-tools`** — `Tool` trait + registry. Built-ins: filesystem I/O, terminal/shell,
  headless browser. Extensible: web search, memory, PiKVM, OBS — each a new `Tool`.
- **`lvz-gateway`** — `Gateway` trait + registry. A gateway is a frontend/channel that
  drives the same agent core. [Hermes tier]
- **`lvz-gw-*`** — concrete gateways (HTTP/WebSocket, Matrix/Continuwuity, Discord, …).
  Each depends only on `lvz-agent` + `lvz-protocol`.
- **`lvz-cli`** — the first gateway: argument parsing, config resolution, terminal
  rendering. Thin; one frontend among several.

---

## 5. Core contracts (interface spec — implement later)

> Signatures are the *design contract*. Bodies are intentionally omitted.

### 5.1 Provider

```rust
// lvz-protocol
#[async_trait]
pub trait Provider: Send + Sync {
    /// Stream a chat turn as normalised events, regardless of wire protocol.
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError>;

    /// Declares optional features so the agent can negotiate / degrade gracefully.
    fn capabilities(&self) -> Capabilities;
}
```

### 5.2 Normalised event stream

```rust
// lvz-protocol
pub enum Event {
    TextDelta(String),
    Thinking(String),                              // Anthropic extended thinking
    ToolUseStart { id: String, name: String },
    ToolUseDelta { id: String, json: String },     // incremental argument JSON
    ToolUseEnd   { id: String },
    Usage(Usage),                                  // tokens in/out, incl. cache hits
    Done(StopReason),
}
```

Each adapter is the **only** place that maps its wire format → `Event`:
- `lvz-anthropic`: SSE `content_block_delta` / `message_delta` → `Event`.
- `lvz-xai`: gRPC streamed messages (v6 outputs) → `Event`.
- `lvz-xai` (fallback): OpenAI chat completion chunks → `Event`.
- `lvz-claude-cli` (optional): `claude -p` stream-json → `Event` (no cache-hit usage).

### 5.3 Capability negotiation

```rust
// lvz-protocol
pub struct Capabilities {
    pub prompt_caching: bool,       // Anthropic: true ; claude-cli: false
    pub extended_thinking: bool,    // Anthropic: true
    pub parallel_tool_use: bool,
    pub server_side_tools: bool,    // xAI gRPC v6: true
}
```

### 5.4 Tool

```rust
// lvz-protocol
#[async_trait]
pub trait Tool: Send + Sync {
    fn name(&self) -> &str;
    fn schema(&self) -> serde_json::Value;        // JSON Schema for the model
    async fn invoke(&self, args: serde_json::Value) -> Result<ToolOutput, ToolError>;
}
```

### 5.5 Gateway  [Hermes tier]

```rust
// lvz-protocol
#[async_trait]
pub trait Gateway: Send + Sync {
    fn name(&self) -> &str;
    /// Run the gateway event loop, dispatching inbound requests to the shared agent
    /// and rendering outbound `Event`s back to the channel.
    async fn serve(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError>;
}
```

`AgentHandle` is the gateway-facing facade over `lvz-agent`: submit a session/turn, receive
an `Event` stream. CLI, HTTP, Matrix, and Discord all implement `Gateway` over the *same*
agent. The core stays unaware of any gateway.

### 5.6 Tuner  [adaptive token optimisation — §6.6]

```rust
// lvz-protocol  (implemented in lvz-tune)
pub struct TaskContext {
    pub archetype: Archetype,       // single-file edit | refactor | rename | feature | ...
    pub repo: RepoProfile,          // size, language, file count
    pub caps: Capabilities,         // caching on/off is a major confounder — condition on it
    pub model: ModelTier,
}
pub struct Knobs {                  // the efficiency dials, tuned per context
    pub skeleton_radius: u8,        // N: include bodies within N dependency hops
    pub truncate_bytes: usize,      // tool-result truncation threshold
    pub compact_after: usize,       // history-compaction trigger
    pub batch_width: u8,            // multi-file batching width
}
pub struct Outcome {
    pub total_tokens: u64,          // objective (across ALL round-trips)
    pub round_trips: u32,           // diagnostic
    pub cache_hit_rate: f32,        // diagnostic
    pub success: bool,              // the constraint: compile/tests pass, diff accepted, ...
}

#[async_trait]
pub trait Tuner: Send + Sync {
    /// Pick knob settings for a task (exploit + bounded explore); never below the CI baseline.
    fn select(&self, ctx: &TaskContext) -> Knobs;
    /// Update profiles from the realised outcome of a completed task.
    fn observe(&self, ctx: &TaskContext, used: &Knobs, out: &Outcome);
}
```

The default `Tuner` is a no-op returning the static §6.5 defaults. Enabling ATO swaps in the
learning implementation in `lvz-tune`; nothing else in the system changes.

---

## 6. Token efficiency (Dirac-parity and beyond)

Goal: minimise tokens **in every layer**. Priority ≈ expected saving × frequency.

### 6.1 Context construction — `lvz-context` (largest lever)

| Mechanism | What it does | Priority |
|---|---|---|
| File-skeleton extraction | Send signatures/types/docstrings only; omit bodies until needed | 0.95 |
| Recursive symbol dependency tracking | Pull only the symbols a task transitively references | 0.9 |
| Need-only curation | Read the minimum file set; never dump whole trees | 0.9 |
| Hash-anchored edits | Stable per-line hashes target edits without resending the file | 0.85 |
| AST-native structural edits | Syntactically correct edits → avoid retry loops that re-burn tokens | 0.85 |
| Token-efficient diffs | Emit minimal diffs, never full-file rewrites | 0.9 |
| Multi-file batching | Many reads/edits in one roundtrip → amortise system-prompt + tool overhead | 0.8 |

### 6.2 Caching & protocol — `lvz-protocol` + adapters

| Mechanism | What it does | Priority |
|---|---|---|
| Prompt caching | `cache_control: ephemeral` on stable prefix (system, tool defs, repo skeleton) | 0.95 |
| Cache-aware prefix ordering | Order context immutable → stable → volatile to maximise cache hits | 0.85 |
| No-resend of unchanged context | Rely on cache breakpoints instead of re-sending | 0.85 |
| Capability-gated | Enable only where `Capabilities.prompt_caching` is true; else skip cleanly | 0.8 |

> Note: Anthropic's OpenAI-compat shim drops caching — this is *the* reason `lvz-anthropic`
> uses the native Messages API (§1, §6).

### 6.3 Agent loop — `lvz-agent`

| Mechanism | What it does | Priority |
|---|---|---|
| Model tiering / routing | Cheap model (Haiku) for routing/classification/summaries; expensive (Opus) for hard reasoning | 0.85 |
| History compaction | Summarise old turns once over budget; keep recent turns verbatim | 0.8 |
| Tool-result truncation & summarisation | Cap large outputs (shell stdout, file reads) with head/tail + summary | 0.85 |
| Early-abort on malformed streamed tool args | Cancel generation as soon as arg JSON is unrecoverable | 0.6 |
| Output minimisation | Terse system prompt; request diffs/structured output, not prose | 0.8 |
| Context budget manager | Hard token ceiling + relevance-ranked eviction policy | 0.8 |
| Deduplication | Collapse repeated context (same file referenced twice) | 0.65 |
| Native tool calling, no MCP | Avoid MCP framing/schema overhead (matches Dirac) | 0.7 |

### 6.4 Measurement & guardrails

- Instrument per-turn tokens in/out, **cache-hit rate**, and cost; expose via telemetry.
- A `--budget <tokens>` runtime ceiling; refuse/trim turns that would exceed it.
- The metric that governs tuning is **total task tokens across all round-trips**, never
  per-call input. Optimising per-call input alone hides round-trip blowback.

### 6.5 Budget-fixture loop (token-efficiency CI)

Skeleton depth (§6.1) trades per-call input against retrieval round-trips; the optimum is
U-shaped and task/model/caching-dependent, so it is **measured, not guessed**.

- **Knob:** skeleton inclusion radius `N` = "include full bodies for symbols within `N`
  dependency hops of the edit target." Config-exposed and sweepable.
- **Fixture:** `(repo snapshot + prompt + expected result)` with an asserted **total-token
  ceiling**.
- **Three metrics/run:** total task tokens (the gate); round-trip count + cache-hit rate
  (diagnostics that explain *why* the total moved when `N` changes).
- **Per-archetype `N`:** fixtures span single-file edit, cross-file refactor (Dirac shape),
  symbol rename, new-feature; expect per-archetype defaults, not one global `N` (≈0.7).
- **Caching coupling:** with caching live, re-sent cached prefixes cost ~10% of input, so
  round-trips hurt less → skeletonise more aggressively. Run fixtures in **both** cached and
  uncached modes so the coupling is visible.
- **Gate:** fail CI on >X% regression vs baseline; track the trend line.
- **Timing:** stand up at **M5** alongside `lvz-context`, not after — retrofitting once the
  context engine ossifies is painful (≈0.65).

### 6.6 Adaptive token optimisation (ATO) — `lvz-tune` [optional]

§6.5 finds good *static* knob defaults offline. ATO closes the loop **at runtime**: it
measures the variables efficiency depends on and the realised token usage, then moves the
knobs toward lower usage — per archetype and per repo. It is the same idea as §6.5, run online
against real traffic and seeded by §6.5's offline results.

- **Objective (constrained):** minimise **total task tokens** *subject to* a task-success rate
  ≥ target. Unconstrained minimisation degenerates to context-starvation → failed/retried
  tasks that cost *more*. The constraint is non-negotiable (≈0.9).
- **Success signal (the keystone):** for a coding agent this is cheap and strong — compile /
  tests pass, diff accepted, no correction turn needed. **Without a quality signal, do not
  enable ATO.**
- **Context features (the "things it varies on"):** archetype, repo profile (size, language,
  file count), provider capabilities (**caching on/off — a major confounder; condition on
  it**), model tier.
- **Knobs tuned (`Knobs`):** skeleton radius `N`, tool-result truncation, history-compaction
  trigger, batch width, cache-breakpoint placement.
- **Mechanism (start simple):** a per-archetype contextual bandit / hill-climb over the knob
  vector with ε-exploration, seeded by §6.5 defaults and **bounded so it can never regress
  below the CI-gated baseline**. Defer heavy Bayesian optimisation until data justifies it
  (≈0.65 the simple loop suffices).
- **Counterfactual learning (de-risks exploration):** much adaptation needs no live
  experiment — from a logged trace you can recompute what a different `N` would have included
  and estimate its token cost offline. Prefer counterfactual updates over live A/Bs on real
  tasks.
- **Non-stationarity:** a model upgrade shifts the optimum; key profiles by model version, or
  decay/expire old observations on change.
- **Composition with §6.5:** offline fixtures set safe priors **and** the regression floor;
  ATO refines online within those bounds. Both share the §6.4 telemetry.
- **Overhead:** pure bookkeeping — the controller adds negligible tokens/compute.

---

## 7. Hermes-level features & gateways

The Hermes tier reuses `lvz-agent` + `lvz-protocol` unchanged and adds breadth via gateways
and feature crates. Nothing here touches the provider or context layers.

### 7.1 Gateway abstraction

A gateway (§5.5) is a frontend/channel driving the shared agent. The CLI is just the first.
Adding a channel = one new `lvz-gw-*` crate implementing `Gateway`; the core is untouched.

### 7.2 Candidate gateways

| Gateway | Crate | Notes |
|---|---|---|
| CLI | `lvz-cli` | First frontend; terminal rendering |
| HTTP / REST + WebSocket | `lvz-gw-http` | API surface; streaming over WS/SSE |
| Matrix (Continuwuity) | `lvz-gw-matrix` | Chat-driven agent on your homeserver |
| Discord | `lvz-gw-discord` | Bot frontend (migration target) |
| Webhook / scheduled | `lvz-gw-cron` | Triggered/automated runs |

### 7.3 Hermes-tier features

| Feature | Where | Notes |
|---|---|---|
| Persistent memory / store | new `lvz-memory` crate | Session + long-term recall behind a trait |
| RAG over repo + docs | `lvz-context` extension | Reuse skeleton/symbol index for retrieval |
| Adaptive token optimisation | `lvz-tune` (§6.6) | Per-repo knob profiles; pays off most at Hermes traffic volume |
| Multi-session / multi-tenant | `lvz-agent` + gateway | Session IDs, isolation, per-tenant config |
| Auth & quotas | `lvz-gateway` middleware | API keys, rate limits, per-tenant budgets |
| Observability / telemetry | cross-cutting | Tokens, cost, latency, cache-hit; OTel export |
| Secrets | runtime | AWS Secrets Manager; never committed |
| Deployment | infra | AWS Fargate, arm64, us-west-2 |
| Model fallback / routing | `lvz-agent` | Provider/model failover; cost-aware routing |
| Tool sandboxing | `lvz-tools` | Constrain shell/fs/browser blast radius |

### 7.4 Architecture invariant

Gateways and feature crates depend only on `lvz-agent` + `lvz-protocol`; never on providers
directly. The agent core remains unaware of which gateway invoked it. This is what lets the
Lavoisier CLI and the Hermes multi-gateway agent share one brain.

---

## 8. Provider adapter notes

### Anthropic (`lvz-anthropic`)
- Endpoint: `POST https://api.anthropic.com/v1/messages`, `stream: true`.
- Required headers: `x-api-key`, `anthropic-version`; betas via `anthropic-beta`.
- **Caching:** attach `cache_control: { type: "ephemeral" }` to stable prefix blocks
  (system prompt, tool defs, large context). Biggest single cost lever — do not skip.
- Parse SSE; account for tokens on mid-stream cancel; handle mid-stream error events.

### xAI primary (`lvz-xai`, gRPC)
- Vendor `xai-org/xai-proto` into `proto/` (pin a commit). Codegen with `tonic-build`
  in `build.rs`.
- Endpoint `api.x.ai:443`; auth `Authorization: Bearer <key>`.
- Use proto **v6** for server-side tool execution ("outputs" sequencing).
- License: protos are Apache-2.0 — compatible.

### xAI fallback (OpenAI-compat, **in-crate** in `lvz-xai`)
- Base URL `https://api.x.ai/v1`, OpenAI chat-completions schema; selected by runtime switch.
- Lower-risk, fewer features (no native server-side tools). Good first milestone (M1).

### Claude subscription (`lvz-claude-cli`, optional)
- Mechanism: shell out to Claude Code `claude -p` (subscription OAuth), **not** the API.
- **No caching:** subscription/setup tokens cannot use `cache_control` — mutually exclusive
  with §6.2. Reports `prompt_caching: false`.
- **Credit model (from 2026-06-15):** programmatic `claude -p` draws from a monthly Agent SDK
  credit ($20 on Pro) first, then API rates if enabled. Not flat-rate, not unlimited.
- Scope: personal/low-volume convenience only; never Hermes/production. Policy-fragile
  (account-suspension history). Config-gated and off by default.

---

## 9. Build sequence (milestones for the Claude-coding session)

1. **M0 — workspace skeleton.** Workspace `Cargo.toml` + `lvz-protocol` with `Provider`,
   `Event`, `Capabilities`, `Tool`, `Gateway`, `Tuner` contracts compiling.
2. **M1 — first light.** `lvz-xai` OpenAI-compat fallback transport + minimal `lvz-cli` →
   one non-streaming turn against `api.x.ai/v1` (fastest path; no gRPC codegen yet).
3. **M2 — streaming.** Normalise SSE → `Event`; render token deltas in the CLI.
4. **M3 — Anthropic native + caching.** `lvz-anthropic` with SSE + `cache_control`; wire
   `Capabilities`; begin token-efficiency instrumentation (§6.4).
5. **M4 — agent loop + tools.** `lvz-agent` plan→act→observe; `lvz-tools` fs + shell.
6. **M5 — context engine + budget-fixture loop.** `lvz-context`: skeletons, symbol tracking,
   hash-anchored AST edits, token-efficient diffs, multi-file batching (§6.1). Stand up the
   budget-fixture CI harness now (§6.5) — the skeleton-depth knob `N` is tuned against it.
7. **M6 — efficiency hardening.** Model routing, history compaction, tool-result
   truncation, budget manager, CI token-budget assertions (§6.3–6.5).
8. **M7 — xAI gRPC.** `lvz-xai` via `tonic-build` from vendored protos; v6 outputs.
9. **M8 — gateway layer.** `lvz-gateway` trait + `lvz-gw-http` (REST + WebSocket).
10. **M9 — Hermes gateways + features.** `lvz-gw-matrix`, `lvz-gw-discord`; `lvz-memory`,
    auth/quotas, observability.
11. **M10 — Hermes deployment.** Validate the shared core on Fargate (arm64, us-west-2)
    behind multiple gateways.

> **Optional track — `lvz-claude-cli`** (any time after M3): shell-out provider, config-gated,
> off by default; see §8 for the caching loss and the 2026-06-15 Agent SDK credit cap.
>
> **Optional track — `lvz-tune` / ATO** (after M6): needs the §6.4 telemetry + §6.5 fixtures
> in place and a task-success signal wired; only pays off once real traffic accrues, so it
> lands naturally around the Hermes tier. Ship the no-op `Tuner` first; swap in the learner
> later (§6.6).

---

## 10. Toolchain & conventions

- Shell: **zsh** for all scripts.
- Build: `cargo` workspace; pin Rust edition + MSRV in root `Cargo.toml`.
- Containers: **Podman** (not Docker) for any local service shells.
- Async runtime: `tokio`; HTTP: `reqwest`; JSON: `serde` / `serde_json`; gRPC: `tonic` + `prost`.
- Secrets: AWS Secrets Manager; never commit keys; read from env at runtime.
- Licensing: prefer **Apache-2.0** (aligns with Dirac and xai-proto) or MIT — both OSI-approved.
- Keep dependencies minimal and vendor-agnostic; avoid heavyweight agent frameworks.

---

## 11. Open questions / risks

- **xAI gRPC streaming shape (v5 vs v6):** confirm the v6 "outputs" message sequence maps
  to `Event` without lossy flattening before committing M7. (≈0.3 minor remap needed.)
- **Claude subscription path:** from **2026-06-15**, `claude -p` is capped by a monthly Agent
  SDK credit and cannot cache; treat `lvz-claude-cli` as personal convenience, not a cost
  strategy. Account-suspension risk if driven at scale. (≈0.85 wrong for Hermes.)
- **Community `xai-sdk` crate:** single maintainer, 3 weeks old. Treat as reference only;
  prefer first-party codegen.
- **Anthropic beta headers:** caching/thinking feature flags drift; pin `anthropic-version`
  and gate betas behind config.
- **gRPC through proxies/CDNs:** HTTP/2 sometimes mishandled by intermediaries; keep the
  in-crate OpenAI-compat fallback wired as a runtime switch.
- **Cache-hit erosion:** any volatile content leaking into the stable prefix silently kills
  caching savings; assert prefix stability in tests (§6.2).
- **Skeleton fidelity:** overly aggressive skeletoning can omit context the model needs,
  causing extra round-trips that *cost* tokens; tune the depth knob `N` against the
  budget-fixture loop (§6.5), measuring **total task tokens**, not per-call input.
- **ATO reward-hacking:** without a task-success constraint the tuner starves context to cut
  tokens, collapsing quality; never run ATO without the quality gate (≈0.9).
- **ATO confounding / non-stationarity:** cache availability and model upgrades shift the
  optimum; condition on cache state and key/decay profiles by model version, or the loop
  learns garbage.

---

## 12. One-line thesis

Abstract at the **semantic** layer (a normalised `Event` stream + `Capabilities`), squeeze
tokens at **every** layer (skeletons, caching, routing, budgets) and let the agent **learn to
squeeze harder** within a quality gate (ATO), and let gateways be peers of the CLI — so the
same self-tuning, token-thrifty core serves Lavoisier today and the many-gateway Hermes agent
tomorrow, gRPC included, as a contained detail rather than a foundation.
