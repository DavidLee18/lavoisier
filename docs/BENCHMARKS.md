# Token-cost benchmark: Lavoisier vs. Dirac

**TL;DR.** On the *same* model, Lavoisier projects to roughly the same cost-per-task as
[Dirac](https://dirac.run) — both use the same token-efficiency techniques, so parity is expected,
not a surprise. The real lever is **model routing**, which Lavoisier exposes directly: a
Dirac-class refactor task costs an estimated **~$0.025 on `grok-4.1-fast`** and **~$0.12 on
`claude-haiku-4-5`** (1.5–7× under Dirac's $0.18 headline), **~$0.35 on `claude-sonnet-4-6`**
(parity with Dirac's most expensive task), and **~$0.59 on `claude-opus-4-8`** (premium quality).

> **This is a cost *estimate*, not a head-to-head run.** Dirac's numbers are *measured* on its
> public refactor suite; Lavoisier's are *projected* from real per-task telemetry (below) scaled to
> Dirac-class task size. We do not re-run Dirac's suite here — it needs Dirac's exact task
> definitions, the upstream repos pinned at the right commits, and non-trivial live spend. The
> per-model **relative ordering is robust**; the absolute figures carry roughly ±50%.

---

## 1. What Dirac is, and its published numbers

[Dirac](https://dirac.run) is an open-source (Apache-2.0), token-efficient coding agent — a fork of
Cline — that shares Lavoisier's exact design thesis: **context curation is the whole game.** It
advertises hash-anchored edits, AST-native precision, multi-file batching, and file-skeleton
extraction with symbol-dependency tracking — the same levers Lavoisier is built on. You bring your
own model (Anthropic / OpenAI / Google / OpenRouter / self-hosted).

Its published benchmark is a **public refactor eval suite of 8 real-world tasks** across
`huggingface/transformers`, `microsoft/vscode`, and `django/django`, scored on cost and success:

| Agent | Avg $/task | Suite success |
|---|---:|---|
| **Dirac** | **$0.18** | 8/8 |
| Opencode | ~$0.43 | 8/8 |
| Cline (parent fork) | $0.49 | — |
| Roo | $0.60 | — |
| Kilo | $0.73 | — |

Reported detail: on **Task 6** (a 25-file refactor in `huggingface/transformers`) Dirac finished for
**$0.34**, vs Cline $0.87 and Roo $1.44. Dirac is also reported at ~65% on Terminal-Bench.
(Sources: [dirac.run](https://dirac.run/),
[andrew.ooo review](https://andrew.ooo/posts/dirac-open-source-coding-agent-review/).)

Dirac's $0.18 average is on Anthropic-class models (its Cline lineage defaults to Claude), so it is
the natural apples-to-apples reference for Lavoisier on `claude-sonnet-4-6`.

## 2. Pricing used (June 2026, USD per million tokens)

| Model | Input | Cache write | Cache read | Output |
|---|---:|---:|---:|---:|
| `claude-opus-4-8` | 5.00 | 6.25 | 0.50 | 25.00 |
| `claude-sonnet-4-6` | 3.00 | 3.75 | 0.30 | 15.00 |
| `claude-haiku-4-5` | 1.00 | 1.25 | 0.10 | 5.00 |
| `grok-4` | 3.00 | — (auto) | 0.75 | 15.00 |
| `grok-4.1-fast` | 0.20 | — (auto) | 0.05 | 0.50 |

Anthropic: cache write = 1.25× input (5-min ephemeral), cache read = 0.1× input (the 90% caching
discount). xAI caches automatically server-side (no separate write charge; cached prompt tokens
billed at 0.25× input). Sources:
[Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing),
[xAI Grok pricing](https://docs.x.ai/developers/models).

## 3. Real Lavoisier anchors (measured this session)

Captured with `--telemetry` running the same multi-round-trip analysis task against the Lavoisier
repo itself (small repo → small absolute numbers; used here for the **token *ratios* and caching
behaviour**, then scaled in §4):

| Config | RT | input | output | cache_read | cache_creation | cache hit | **task cost** |
|---|---:|---:|---:|---:|---:|---:|---:|
| `claude-sonnet-4-6` + `--repo-skeleton 3000` | 3 | 1,075 | 512\* | 24,500 | 12,452 | 96% | **$0.065** |
| `claude-haiku-4-5` + `--repo-skeleton 4000` | 2 | 110 | 64 | 12,260 | 12,285 | 99% | **$0.017** |
| `grok-4` (gRPC, auto-cache) | 8 | 3,573 | 233 | 13,824 | 0 | 79% | **$0.025** |

\* output hit the `--max-tokens 512` cap. These confirm the core mechanic: after the first turn the
large system + tool-def + repo-skeleton prefix is served from cache (`cache_read`), so per-turn
*billable* input stays small — exactly the regime these agents are built to exploit.

## 4. Projecting to a Dirac-class task

We model **one representative Dirac-class refactor task** (multi-file, ~12 round-trips, caching on)
and hold its token profile fixed across models — same agent, same task, only the price/M changes.
The profile is scaled from the anchors above and anchored to Dirac's published task sizes (Task 6 =
25-file refactor at $0.34; suite avg $0.18):

| Component | Tokens | Rationale |
|---|---:|---|
| cache_read (prefix re-read each later turn) | 220,000 | ~20K cached prefix × ~11 turns |
| fresh input (growing transcript, tool results) | 30,000 | ~2.5K/turn × 12 |
| cache_creation (prefix built once + refresh) | 20,000 | repo-skeleton + tooldefs + system |
| output (thinking + minimal anchored diffs) | 8,000 | terse; hash-anchored edits, no file rewrites |

**Projected cost per Dirac-class task:**

| Model | $/task (est.) | vs Dirac $0.18 | Note |
|---|---:|---|---|
| `grok-4.1-fast` | **~$0.025** | **~7× cheaper** | cheapest; quality trade-off |
| `claude-haiku-4-5` | **~$0.12** | ~1.5× cheaper | strong cost/quality floor |
| **Dirac (measured)** | **$0.18** | baseline | ≈ Sonnet-class |
| `claude-sonnet-4-6` | **~$0.35** | ~parity | ≈ Dirac's Task 6 ($0.34) |
| `grok-4` | **~$0.44** | ~2.4× pricier | legacy flagship pricing |
| `claude-opus-4-8` | **~$0.59** | premium | highest quality |

Worked example (`claude-sonnet-4-6`): `30k·$3 + 8k·$15 + 220k·$0.30 + 20k·$3.75`, all per-M →
`$0.090 + $0.120 + $0.066 + $0.075 = $0.351`.

## 5. Findings

1. **Parity on like-for-like models is by design.** Lavoisier on Sonnet (~$0.35) lands on Dirac's
   *expensive* end ($0.34 Task 6) and within range of its $0.18 average — both curate context
   aggressively (skeletons, anchored edits, batching, caching), so neither has a structural token
   edge over the other. Both sit far under naive agents (Cline $0.49, Roo $0.60, Kilo $0.73).
2. **The dominant cost lever is model routing — and Lavoisier exposes it natively.** `--cheap-model`
   / `--escalate-after` (cheap-model-first), `--advisor-model` (expensive planner → cheap executor),
   and `--tune`/`--tune-bayes` (learn the cheapest knobs that still pass `--verify-cmd`) let a
   Dirac-class task run on `grok-4.1-fast` (~$0.025) or `claude-haiku-4-5` (~$0.12) — **1.5–7×
   under Dirac's headline** — escalating to Sonnet/Opus only when a task needs it.
3. **Prompt caching is the foundation, not a tweak.** Without it the 220K cached prefix re-reads
   bill at full input: Sonnet's prefix alone would jump from $0.066 to **$0.66** (~10×). This is why
   `lvz-anthropic` uses the native Messages API (not an OpenAI-compat shim, which drops caching) and
   why the cache-aware repo-skeleton prefix (`--repo-skeleton`) is ordered into the warm prefix.

## 6. Caveats & how to make it exact

- **Estimate, not a measured head-to-head.** The §4 token profile is the load-bearing assumption;
  ±50% on it moves every absolute figure proportionally but leaves the per-model ordering intact.
- **Task mix matters.** Dirac's $0.18 is an 8-task average spanning easy → 25-file refactors; a
  matched Lavoisier average would similarly be below its single-task figures here.
- **Quality is not modelled.** Cost-per-task is only half the story; cheaper models trade accuracy.
  The honest comparison pairs `$/task` with suite success — which needs a live run.
- **To turn this into a measurement:** point Lavoisier at the same upstream repos/commits Dirac
  uses, run each task under `--agent --telemetry --verify-cmd '<task test>'`, and sum the per-task
  `[telemetry]` token lines × the §2 prices. `--telemetry` already emits everything needed
  (input/output/cache_read/cache_creation/round_trips/success) per task.

_Last updated: 2026-06-12. Prices and Dirac figures are point-in-time; re-derive from §2 sources._
