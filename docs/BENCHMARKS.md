# Token-cost benchmark: Lavoisier vs. Dirac

**TL;DR.** [Dirac](https://dirac.run)'s headline **$0.18/task** is measured on Google's
**`gemini-3-flash-preview`** (thinking = High) — a cheap "flash"-tier model. Lavoisier now ships a
native **`lvz-google`** provider (`--provider google --thinking high`), so the **identical model at
identical thinking effort is directly runnable** — turning the comparison below from an estimate into
a measurable head-to-head. As a *projection* (until the suite is run): holding token volume ≈
Dirac's and re-pricing on each model, the full 8-task suite is ~$1.5 on `gemini-3-flash-preview`
(matching Dirac's measured $1.48, since it's the same model), **~$0.5 on `grok-4.1-fast`** (the only
option that undercuts Gemini Flash), **~$2.7 on `claude-haiku-4-5`**, **~$8.5 on
`claude-sonnet-4-6`**, **~$10 on `grok-4`**, and **~$13.5 on `claude-opus-4-8`**. The spread is
**model price, not agent efficiency** — Dirac and Lavoisier use the same token-curation techniques;
Gemini Flash is simply cheaper per token (especially on output) than the Claude tiers.

> **This is a cost *estimate*, not a head-to-head run.** Dirac's numbers are *measured*; Lavoisier's
> are *projected* by anchoring to Dirac's real per-task costs (known, below) and Gemini's pricing,
> then re-pricing the same token volume on each Lavoisier-supported model. Per-model **ratios are
> robust**; absolute figures carry ~±40%.

---

## 1. Dirac's actual benchmark

[Dirac](https://dirac.run) is an open-source (Apache-2.0), token-efficient coding agent — a fork of
Cline — that shares Lavoisier's exact thesis (**context curation is the whole game**): hash-anchored
edits, AST precision, multi-file batching, skeleton extraction + symbol tracking. BYO model.

Its public refactor suite is **8 real-world tasks** across `huggingface/transformers`,
`microsoft/vscode`, and `django/django`. Crucially, **all agents were run on
`gemini-3-flash-preview` with thinking set to "High"** ("All agents used `gemini-3-flash-preview`
with thinking set to 'High'") — so the comparison is agent-vs-agent on a fixed model.

| Task | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | **Total** | Avg |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| Dirac $ | 0.13 | 0.23 | 0.16 | 0.08 | 0.17 | **0.34** | 0.25 | 0.12 | **1.48** | 0.185 |

8/8 success. Task 6 is a 25-file refactor in `huggingface/transformers`. vs. other agents on the
same model: Cline $0.49/task, Roo $0.60, Kilo $0.73; Opencode also 8/8 (~$0.43). Dirac is also
~65% on Terminal-Bench 2.0 (`gemini-3-flash-preview`). The resulting diffs are checked into Dirac's
repo for audit, but task specs, the eval harness, and the grading method are **not** clearly
published. (Sources: [dirac.run](https://dirac.run/),
[andrew.ooo review](https://andrew.ooo/posts/dirac-open-source-coding-agent-review/).)

**Identical-model reproduction is now supported.** Lavoisier originally scoped providers to
Anthropic + xAI native, but the `lvz-google` provider was added (2026-06-12) precisely so the same
model Dirac benchmarks on — `gemini-3-flash-preview`, thinking=High — can be driven directly:
`lavoisier --agent --provider google --model gemini-3-flash-preview --thinking high …` (set
`GOOGLE_API_KEY`). That makes a *true* head-to-head possible (same model, same thinking effort,
isolating agent efficiency). The other models below are then the cost trade-offs you'd pick *instead*
of Gemini once you accept a different quality/price point.

## 2. Pricing used (June 2026, USD per million tokens)

| Model | Input | Cache write | Cache read | Output |
|---|--:|--:|--:|--:|
| `gemini-3-flash-preview` (Dirac's model) | 0.50 | ~0.50 | ~0.05 | 3.00 |
| `grok-4.1-fast` | 0.20 | — (auto) | 0.05 | 0.50 |
| `claude-haiku-4-5` | 1.00 | 1.25 | 0.10 | 5.00 |
| `claude-sonnet-4-6` | 3.00 | 3.75 | 0.30 | 15.00 |
| `grok-4` | 3.00 | — (auto) | 0.75 | 15.00 |
| `claude-opus-4-8` | 5.00 | 6.25 | 0.50 | 25.00 |

Anthropic: cache write 1.25× input, cache read 0.1× input. xAI caches automatically (no separate
write; cached reads 0.25× input). Gemini Flash: implicit caching (~0.1× read, no separate write).
Note `gemini-3-flash-preview` is **cheaper than every Claude tier on output** ($3/M vs $5–25/M) —
and thinking="High" makes runs output-heavy, which is where that gap bites. Sources:
[Anthropic](https://platform.claude.com/docs/en/about-claude/pricing),
[xAI](https://docs.x.ai/developers/models),
[Gemini](https://ai.google.dev/gemini-api/docs/pricing).

## 3. Real Lavoisier anchors (measured this session)

Captured with `--telemetry` on a multi-round-trip task against the Lavoisier repo (small repo →
small absolute numbers; used for the **token ratios + caching behaviour**):

| Config | RT | input | output | cache_read | cache_creation | cache hit | task cost |
|---|--:|--:|--:|--:|--:|--:|--:|
| `claude-sonnet-4-6` + `--repo-skeleton 3000` | 3 | 1,075 | 512\* | 24,500 | 12,452 | 96% | $0.065 |
| `claude-haiku-4-5` + `--repo-skeleton 4000` | 2 | 110 | 64 | 12,260 | 12,285 | 99% | $0.017 |
| `grok-4` (gRPC, auto-cache) | 8 | 3,573 | 233 | 13,824 | 0 | 79% | $0.025 |

\* hit the `--max-tokens 512` cap. These confirm the mechanic: after turn 1 the system + tool-def +
repo-skeleton prefix is served from cache (`cache_read`), so per-turn *billable* input stays small.

## 4. Re-pricing the suite on Lavoisier-supported models

The token *volume* of a task is roughly model-independent (the same refactor needs the same context
and produces a similar edit), so we anchor to Dirac's **measured $1.48** on Gemini and re-price that
volume on each model. Using a representative thinking-High refactor mix (≈70% cached re-reads, 12%
fresh input, 8% cache-creation, 10% output incl. thinking), the blended $/M and the resulting
suite total scale by each model's price ratio vs. Gemini Flash:

| Model | blended $/M | ratio vs Gemini | **8-task suite** | per task | vs Dirac $1.48 |
|---|--:|--:|--:|--:|--:|
| `grok-4.1-fast` | 0.13 | 0.28 | **~$0.5** | ~$0.06 | **~3× cheaper** |
| `gemini-3-flash-preview` *(Dirac, measured)* | 0.44 | 1.0 | **$1.48** | $0.185 | baseline |
| `claude-haiku-4-5` | 0.79 | 1.8 | **~$2.7** | ~$0.34 | ~1.8× |
| `claude-sonnet-4-6` | 2.37 | 5.3 | **~$8.5** | ~$1.05 | ~5.7× |
| `grok-4` | 2.63 | 5.9 | **~$10** | ~$1.25 | ~6.6× |
| `claude-opus-4-8` | 3.95 | 8.9 | **~$13.5** | ~$1.70 | ~9× |

The ranking is stable for any output fraction in the ~3–15% range; a more output-heavy run (higher
thinking budget) widens the gap for the costly-output models (Sonnet/Opus/grok-4) and barely moves
the cheap ones.

## 5. Findings

1. **Dirac's low headline is mostly the model, not a unique agent edge.** It runs on
   `gemini-3-flash-preview` — a cheap flash tier. On the *same* model, Dirac and Lavoisier would be
   close (same curation techniques); the suite-cost spread above is dominated by Gemini-Flash-vs-
   Claude **price**, especially output ($3/M vs $15–25/M under thinking=High).
2. **Only `grok-4.1-fast` undercuts Dirac among Lavoisier-supported models** (~$0.5 vs $1.48 suite)
   — because xAI's fast tier ($0.20/$0.50) is cheaper than Gemini Flash. It's the natural like-for-
   like (cheap, fast, strong tool-calling). Haiku is ~1.8× Dirac; Sonnet ~5.7×; Opus ~9×.
3. **Model routing is the lever, and Lavoisier exposes it.** `--cheap-model`/`--escalate-after`,
   `--advisor-model` (expensive planner → cheap executor), and `--tune`/`--tune-bayes` (learn the
   cheapest knobs that still pass `--verify-cmd`) let you run most of a suite on `grok-4.1-fast` or
   Haiku and escalate only the hard tasks — landing a blended cost near or below Dirac's.
4. **Caching is foundational.** Without it the ~70% cached re-reads bill at full input: a Sonnet
   suite would roughly double. This is why `lvz-anthropic` uses the native Messages API (an
   OpenAI-compat shim drops caching) and why `--repo-skeleton` pins the repo outline in the warm
   prefix.

## 6. Running the full suite — what it would cost and require

**Estimated spend (one clean pass, 8 tasks):**

| Model | Suite cost (est.) | + dev/retries (~2.5×) |
|---|--:|--:|
| `grok-4.1-fast` | ~$0.5 | ~$1.25 |
| `gemini-3-flash-preview` *(Dirac's model — true parity)* | ~$1.5 | ~$3.7 |
| `claude-haiku-4-5` | ~$2.7 | ~$7 |
| `claude-sonnet-4-6` | ~$8.5 | ~$21 |
| `grok-4` | ~$10 | ~$25 |
| `claude-opus-4-8` | ~$13.5 | ~$34 |

Real runs need debugging/retries — budget ~2–3× a clean pass.

**What's required:**

1. **The 8 task definitions.** Dirac checks in the *result diffs* but not clear task specs/harness.
   You'd reconstruct each: the repo, the commit, the natural-language instruction, and the
   acceptance check (expected patch or the area's test suite).
2. **The upstream repos at the right commits** — `huggingface/transformers` (Python),
   `django/django` (Python), `microsoft/vscode` (TypeScript; large checkout). All three are
   in-language for Lavoisier's skeletoniser (Rust/Python/JS/TS).
3. **A per-task harness (zsh).** For each task: `lavoisier --agent --telemetry --verify-cmd
   '<task acceptance test>' --repo-skeleton <N> "<instruction>"` run in the repo, then sum the
   `[telemetry]` token lines × the §2 prices. `--verify-cmd` exit 0 = success (the same grading the
   ATO success signal uses); `--tune-state` if you want it to learn across tasks.
4. **API keys + `protoc`** (build dep) and the binary. Keys for whichever provider(s) above.
5. **Time.** 8 tasks × multiple round-trips; the 25-file Task 6 alone is many turns — roughly 1–3
   hours wall-clock for one clean pass.
6. **True model parity is built in.** Run the suite under `--provider google --model
   gemini-3-flash-preview --thinking high` (the `lvz-google` provider) to compare on Dirac's *exact*
   model and thinking effort — isolating agent efficiency from model price. `grok-4.1-fast` is the
   cheapest supported alternative (flash-tier vs flash-tier) if you want lower cost at some quality
   trade-off.

_Last updated: 2026-06-12. Prices and Dirac figures are point-in-time; re-derive from §2 sources._
