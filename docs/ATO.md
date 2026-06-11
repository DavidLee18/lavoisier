# Adaptive Token Optimisation (ATO)

ATO is Lavoisier's **online, quality-gated knob-tuning loop** (`RECIPE.md` §6.6). It learns,
per task context, which efficiency settings minimise the **total tokens a task costs** without
letting task success drop. This document is the exact mechanism as implemented.

- Contract: `crates/lvz-protocol/src/tune.rs` (`Tuner`, `TaskContext`, `Knobs`, `Outcome`).
- Learner: `crates/lvz-tune/src/lib.rs` (`LearningTuner`).
- Agent integration: `crates/lvz-agent/src/lib.rs` (`run_loop` → `select`/`observe`).
- Enable it: CLI `--tune`, or `Agent::with_tuner(Arc::new(LearningTuner::new()))`.

---

## 1. Where it sits: two loops, one objective

The optimisation metric is **total task tokens across all round-trips** — never per-call input
(`RECIPE.md` §6). Two loops drive the knobs toward that minimum:

- **Offline (§6.5), the budget-fixture CI loop.** Committed per-archetype token ceilings in
  `crates/lvz-context/tests/budget.rs` set good *static* defaults and a regression floor. This
  is where `Knobs::default()` comes from.
- **Online (§6.6), ATO — this document.** At runtime, against real traffic, it nudges the knobs
  *below* the static defaults where the data shows it's safe, per context. It is seeded by the
  offline defaults and **bounded so it can never regress below them**.

ATO is **optional and off by default**: the agent ships with `NoopTuner` (returns the static
defaults, ignores observations), so behaviour is identical whether or not the learner is wired.

---

## 2. The contract: `select` then `observe`

```rust
pub trait Tuner: Send + Sync {
    fn select(&self, ctx: &TaskContext) -> Knobs;          // before a task
    fn observe(&self, ctx: &TaskContext, used: &Knobs, out: &Outcome); // after it
}
```

Both methods are **synchronous** — they are in-memory profile lookups/updates, not model calls.
The agent calls them exactly once per task (`run_loop`):

1. **At task start** it builds the `TaskContext`, calls `select(ctx)` to get a `Knobs`, and uses
   that knob vector for the whole task.
2. **At every task exit** (success, provider error, budget exceeded, or out of steps) it calls
   `observe(ctx, knobs, outcome)` with the realised result.

```
            TaskContext                       Outcome
   task ───────────────▶ select() ─▶ Knobs ─▶ run the task ─▶ observe()
                              ▲                                   │
                              └──────── learned profiles ◀────────┘
```

---

## 3. What it conditions on: the profile key

Knob optima differ by context, so each context is its own little learning problem. The
`TaskContext` carries:

| Field | Meaning | Used in the key? |
|-------|---------|------------------|
| `archetype` | `SingleFileEdit \| Refactor \| Rename \| Feature \| Other` (classified from the latest user turn by a keyword heuristic) | **yes** |
| `caps.prompt_caching` | whether the provider caches the prefix | **yes** — the dominant confounder |
| `model` (`ModelTier`) | `Fast \| Balanced \| Deep` | **yes** |
| `model_id` | the concrete model id (e.g. `"claude-sonnet-4-6"`) | **yes** — non-stationarity guard |
| `repo` (`RepoProfile`) | file count, bytes, primary language | carried, not yet keyed |

`LearningTuner` keys profiles on `ContextKey { archetype, caching, model, model_id }`. **Caching
is keyed explicitly** because it dominates token economics: the cheapest knobs with a warm cache
are not the cheapest without one, so the two must not be averaged together (`RECIPE.md` §6.6).
The concrete **`model_id` is keyed alongside the coarse tier** so a model upgrade — which shifts
the knob optimum (non-stationarity, §6.6) — starts a fresh profile instead of polluting the old
model's learned optimum. Same model, same key; new model, new key.

---

## 4. The knobs and their grids

`Knobs` are the efficiency dials (`lvz-protocol`):

```rust
pub struct Knobs {
    pub skeleton_radius: u8,   // include full bodies within N dependency hops of the edit target
    pub truncate_bytes: usize, // truncate tool results larger than this
    pub compact_after: usize,  // compact history once it exceeds this many tokens
    pub batch_width: u8,       // file reads/edits batched per round-trip
}
// Default (the §6.5 baseline / floor): { 1, 8192, 24000, 4 }
```

ATO explores a **discrete grid** centred on the default, so the candidate space stays small and
learning stays tractable:

| Knob | Grid | Default |
|------|------|---------|
| `skeleton_radius` | `0, 1, 2, 3` | `1` |
| `truncate_bytes` | `2048, 4096, 8192, 16384, 32768` | `8192` |
| `compact_after` | `8000, 16000, 24000, 32000, 48000, 64000` | `24000` |
| `batch_width` | `1, 2, 4, 8` | `4` |

A neighbour move steps **one** knob to an adjacent grid cell (clamped at the ends). Exploration
can therefore never leave this envelope — that is the hard bound.

> State: all four knobs are now consumed by the loop. `compact_after` and `truncate_bytes` gate
> compaction and tool-result truncation directly. `skeleton_radius` is injected into focused
> `outline_file` calls when the model leaves the radius unset (so ATO's choice governs how much
> dependency context a skeleton carries). `batch_width` is surfaced as a system-prompt hint
> (only when the provider advertises `parallel_tool_use` and the width > 1) telling the model to
> issue independent reads/edits together, collapsing round-trips.

---

## 5. The objective (and the non-negotiable constraint)

ATO minimises **total task tokens subject to a success constraint**:

> minimise `Outcome.total_tokens`  **subject to**  task-success rate ≥ `success_target`.

The constraint is not optional (`RECIPE.md` §6.6, ≈0.9 confidence). Unconstrained token
minimisation degenerates to *context starvation*: too-small skeletons / too-aggressive
truncation make the model fail or need correction turns, which cost **more** than the tokens
saved. So a knob vector is only ever chosen if it is **trusted** (see below); the cheapest
vector that fails is never selected.

`Outcome` carries the objective and the constraint signal:

```rust
pub struct Outcome {
    pub total_tokens: u64,   // objective — summed over ALL round-trips
    pub round_trips: u32,    // diagnostic
    pub cache_hit_rate: f32, // diagnostic
    pub success: bool,       // the constraint
}
```

`total_tokens` is the *true* task cost: the agent accumulates every round-trip's usage **plus**
the history-compaction summary call **plus** the advisor pre-pass call (§6.4). ATO optimises the
whole bill, not one turn.

---

## 6. The algorithm: a per-context ε-greedy hill-climb

`LearningTuner` runs an independent **contextual bandit** per `ContextKey`. Per key it keeps a
map `Knobs → Stats`:

```rust
struct Stats { trials: u32, successes: u32, success_tokens: u64 }

success_rate() = successes / trials                         // 0 when no trials
mean_tokens()  = success_tokens / successes                 // None when no successes
trusted(cfg)   = trials >= min_trials && success_rate >= success_target
```

Only **successful** runs contribute to `success_tokens`, so `mean_tokens()` is "cost when it
works" — the quantity we compare.

### `select(ctx)`

1. Look up the key's candidate map; **ensure `Knobs::default()` is always present** as a
   candidate.
2. `best` = the **cheapest trusted** candidate (lowest `mean_tokens()` among those meeting the
   constraint), or `Knobs::default()` if nothing is trusted yet. **Ties on mean tokens break
   toward the least context carried** (smaller `truncate_bytes`, then `skeleton_radius`, then
   `compact_after`) — carrying less context is weakly better for cache/overrun pressure and never
   worse on the measured objective, and it makes selection deterministic (independent of hash-map
   order). This tie-break is what lets counterfactual crediting (below) actually change the pick.
3. Draw `r ∈ [0, 1)` from the PRNG:
   - **Exploit** (`r ≥ epsilon`): return `best`.
   - **Explore** (`r < epsilon`): pick a random knob and direction, step `best` one grid cell,
     register the neighbour as a candidate, and return it.

### `observe(ctx, used, out)`

Find-or-insert the `used` candidate for the key; `trials += 1`; on `out.success`,
`successes += 1` and `success_tokens += out.total_tokens`.

There are **two counterfactual mechanisms**, on opposite ends of the soundness/impact trade-off:
one is exact-but-modest and always on; the other is impactful-but-unsound and opt-in.

**(a) Truncate counterfactual — exact, always on.** `observe` (inside `LearningTuner`) credits the
*provably-equivalent* cheaper truncate settings without a live trial. If `out.max_tool_result_bytes`
(the largest untruncated tool result the task produced) is `≤ used.truncate_bytes` — i.e.
truncation never actually fired — then every grid value `b` with
`max_tool_result_bytes ≤ b < used.truncate_bytes` would have produced a **byte-identical
transcript**: same tokens, same success. Each such `b` is folded in with the *same* outcome. This
is exact, not a monotonicity assumption — the transcript is literally unchanged — so it can never
falsely credit a starved setting (one that *would* have truncated). Its effect: tighter truncate
limits build trust quickly, and the tie-break above then selects them over the (equal-cost)
default. It only runs when truncation didn't fire; if it did, a different limit changes the
transcript and no counterfactual is sound. Because the credited transcript is identical, this is
**not an immediate token win** — it proves *equivalence*, and the saving only materialises later,
on a task where the (now-trusted, tighter) limit actually bites.

**(b) Radius counterfactual — estimated, opt-in (`--radius-counterfactual`).** Unlike (a), this
one *does* estimate a real token saving on the same task — and pays for it with soundness. When
enabled, the agent snapshots every knob-governed `outline_file` skeleton (a `focus` with no
model-supplied radius, so the tuner's radius was injected). After the task, for each radius `t`
below the one used, it **re-extracts those skeletons at `t`** (`skeleton_with_radius` +
`estimate_tokens`), sums the tokens that smaller radius would have saved, and credits
`Knobs { skeleton_radius: t, .. }` with `(realised.total − saving, realised.success)`. The token
delta is real; the **success bit is optimistically transferred** — we cannot prove the model
wouldn't have failed with less dependency context, so this *can* falsely credit a starved radius.
That is the whole reason it is off by default and behind a flag. It accelerates discovery of
smaller radii at the cost of (a)'s safety guarantee. (`max_tool_result_bytes` is cleared on these
synthetic outcomes so they don't compound with mechanism (a).) Snapshots are taken at outline time
because the agent may edit the file later in the same task. Lives in `lvz-agent` — it needs
`lvz-context` to re-extract, which the minimal-deps `lvz-tune` learner deliberately doesn't pull
in; the learner just records the synthetic observations the agent emits.

### Defaults (`TuneConfig`)

`epsilon = 0.1` · `success_target = 0.9` · `min_trials = 3`.

---

## 7. Safety: three guarantees it can't violate

1. **Baseline floor.** `Knobs::default()` (the CI-gated §6.5 baseline) is always a live
   candidate, and until *something* is trusted, `select` returns it. So in expectation the
   chosen knobs are never worse than the baseline — ATO can only match or beat it.
2. **Constraint.** Only `trusted` candidates (enough trials *and* success rate ≥ target) are
   eligible as `best`. A cheaper-but-failing vector is structurally excluded.
3. **Bounded envelope.** Exploration moves only along the discrete grid above. The knobs can
   never wander to pathological values, no matter how the bandit evolves.

---

## 8. The success signal — the keystone

ATO is only as safe as the `success` bit it learns from. RECIPE §6.6 is blunt: **"Without a
quality signal, do not enable ATO."** For a coding agent the *right* signal is cheap and strong
— compile/tests pass, the diff is accepted, no correction turn was needed.

**The real signal: a verify command.** `AgentConfig.verify_command` (CLI `--verify-cmd`) is a
shell command run **after a task completes normally** — `cargo test --quiet`, a type-check, a
lint — in the agent's `repo_root`, stdio discarded. Its exit status *is* `Outcome.success`: exit
0 ⇒ the change is good, non-zero ⇒ failed. This is the quality gate §6.6 demands. It runs **only
on an otherwise-clean completion** (the model ended without tool calls); a provider error, budget
overrun, or step-cap is `success = false` regardless, and the verify command is not run.

**Fallback.** With no `verify_command` set, `success` falls back to the coarse "**completed
without erroring**" flag (clean finish ⇒ true; error/overrun/step-cap ⇒ false). That's a
reasonable placeholder but it does *not* satisfy the §6.6 bar — it doesn't check the change is
*correct*. So `--tune` remains **opt-in**, and `--tune` without `--verify-cmd` stays experimental;
pair the two for a production-grade signal.

---

## 9. Operational properties

- **Enabling.** CLI `--tune` swaps `NoopTuner` → `LearningTuner` (it takes precedence over a
  fixed `--compact-after`). Most useful in a long-running `--serve` gateway, which accrues many
  tasks; a one-shot CLI run starts cold and mostly just returns the baseline.
- **Persistence.** `--tune-state <path>` loads profiles at start (a missing file ⇒ cold) and
  saves the full snapshot (profiles + PRNG cursor) as JSON after every observation, so a
  restarted or redeployed gateway keeps what it learned. `LearningTuner::save`/`load` flatten the
  struct-keyed maps to a row list (struct keys can't be JSON object keys); the PRNG cursor is
  persisted too so exploration doesn't replay the same sequence after a restart. Without the
  flag, profiles stay **process-local** and are lost on exit.
- **Concurrency.** State sits behind a `Mutex`; `select`/`observe` are synchronous and safe
  under concurrent gateway sessions.
- **Determinism.** A fixed-seed xorshift64 PRNG (`0x9E37_79B9_7F4A_7C15`) drives ε-exploration,
  so a given history replays identically. ε-greedy needs no cryptographic RNG, and no `rand`
  dependency is pulled in.
- **Overhead.** Pure bookkeeping — a couple of hash-map operations per task. Negligible tokens,
  negligible compute (`RECIPE.md` §6.6).

---

## 10. Roadmap

**Implemented (this iteration).**

- **A real success signal** (§8) — `--verify-cmd` gates `Outcome.success` on an exit code (tests
  / type-check / lint), the quality gate §6.6 requires; coarse "completed without error" remains
  the fallback.
- **Counterfactual learning** (§6) — *both* mechanisms now ship. (a) The **exact** byte-identical
  truncate counterfactual (always on): when truncation never fired, every cheaper truncate grid
  value still ≥ the largest result is credited with the same outcome, no live trial — sound, can't
  mislabel a starved setting. (b) The **estimated** radius counterfactual (opt-in,
  `--radius-counterfactual`): re-extracts snapshotted skeletons at smaller radii to estimate the
  token saving and credits those radii with the optimistically-transferred success bit — impactful
  but unsound, hence flag-gated and off by default.
- **Non-stationarity / model-version keying** (§3) — `ContextKey` now carries the concrete
  `model_id`, so a model upgrade starts a fresh profile instead of averaging a shifted optimum.
- **Profile persistence** (§9) — `--tune-state <path>` saves/loads profiles + PRNG across restarts.
- **Wiring the inert knobs** (§4) — `skeleton_radius` is injected into focused `outline_file`
  calls; `batch_width` drives a parallel-tool-use system-prompt hint. All four knobs now bite.

**Still deferred.**

- **Per-repo profiles & observation decay** — key profiles by repo as well as archetype, and decay
  stale observations on a model change (beyond the fresh `model_id` keying). The radius
  counterfactual could also estimate *downstream* token effects (it currently models only the
  skeleton-input delta, not the model's altered subsequent turns).
- **Bayesian optimisation** over the knob vector — deferred until the data justifies it; the
  simple ε-greedy hill-climb is expected to suffice (`RECIPE.md` §6.6, ≈0.65).

---

## 11. Worked example

Context: `SingleFileEdit`, caching **on**, `Balanced` model. Cold start:

1. `select` → `Knobs::default()` `{1, 8192, 24000, 4}` (nothing trusted yet). Task runs, costs
   ~1000 tokens, succeeds. `observe` records it.
2. After ≥ `min_trials` such tasks, the default becomes *trusted* (mean ≈ 1000).
3. ε-exploration occasionally returns a neighbour, e.g. `skeleton_radius = 0`. Say those tasks
   succeed at ~700 tokens. After `min_trials`, that neighbour is trusted and cheaper.
4. `select` now **exploits** `{0, 8192, 24000, 4}` (700 < 1000) for this context — a real
   per-context saving, learned online.
5. If a later neighbour (say `truncate_bytes = 2048`) starts *failing* (success rate < 0.9), it
   is excluded as untrusted; `select` falls back to the best trusted vector. The floor holds.

A different context — e.g. caching **off**, or archetype `Feature` — has its **own** profile and
converges to its **own** optimum, independently.
