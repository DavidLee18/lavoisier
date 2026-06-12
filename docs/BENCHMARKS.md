# Token-cost benchmark: Lavoisier vs. Dirac

**TL;DR.** [Dirac](https://dirac.run)'s headline **$0.18/task** is measured on Google's
**`gemini-3-flash-preview`** (thinking = High) — a cheap "flash"-tier model. Lavoisier now ships a
native **`lvz-google`** provider (`--provider google --thinking high`), so we ran a **real
head-to-head on the identical model** — both agents over Dirac's own 8-task refactor suite, same
repos, same `--verify-cmd` grading (§3). The measured suite totals on this machine were
**Lavoisier ≈ $1.69 vs Dirac ≈ $2.78** — but with a large caveat: **Lavoisier did not self-terminate
on 6/8 of the big multi-file refactors** (it ran to its `max_steps=60` ceiling), so its lower total
is partly a *capped* cost, not a *completed* one. On the one task both agents finished cleanly and
Lavoisier passed verify (`django` datadict), Lavoisier cost **$0.026 vs Dirac's $0.123 (~4.8×
cheaper)** — the cleanest apples-to-apples point. The cross-model projection still holds for the
*other* providers (re-pricing the same token volume): **~$0.5 on `grok-4.1-fast`**, **~$2.7 on
`claude-haiku-4-5`**, **~$8.5 on `claude-sonnet-4-6`**, **~$10 on `grok-4`**, **~$13.5 on
`claude-opus-4-8`** — that spread is **model price, not agent efficiency**.

> **§3 is now a *measured* head-to-head** (both agents, identical model, this machine, 2026-06-12);
> §4 (other models) remains a *projection* by re-pricing the measured Gemini token volume. Two
> honesty caveats run through it: (a) the `--verify-cmd` pass/fail is a noisy `tsc`/`ruff` proxy on
> **both** sides (cost is trustworthy, pass/fail is not), and (b) Lavoisier hit its turn ceiling on
> most tasks rather than converging — so treat the suite totals as *order-of-magnitude*, and the
> per-task / single-clean-task numbers as the firmer signal.

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

## 3. Measured head-to-head (identical model, 2026-06-12)

Both agents were run over **Dirac's own 8 refactor tasks** (`bench/tasks/*.task`, transcribed from
`dirac-run/dirac` `evals/README.md`), on the **same cloned repos** at branch HEAD, on the **identical
model** `gemini-3-flash-preview` (thinking = **High**), graded by the **same** `--verify-cmd`
(`tsc --noEmit` for vscode, `ruff check` for transformers/django). Lavoisier via
`bench/run.zsh` (`--max-steps 60 --max-tokens 16384 --repo-skeleton`); Dirac via `bench/dirac.zsh`
(`dirac -y`). Cost is from each agent's own token accounting (Lavoisier's `--telemetry` line priced
at §2 rates; Dirac's `Total Cost:` line).

| # | Task | Repo | **Lavoisier $** | LVZ stop | **Dirac $** | Dirac verify |
|--|------|------|--:|---|--:|:--:|
| 01 | extensionswb_service | vscode | 0.247 | max_steps | 0.288 | fail\* |
| 02 | sendRequest | vscode | 0.202 | max_steps | 0.722 | fail\* |
| 03 | IOverlayWidget | vscode | 0.153 | max_steps | 0.872 | fail\* |
| 04 | addLogging | vscode | 0.221 | **EndTurn** | 0.317 | fail\* |
| 05 | DynamicCache | transformers | 0.191 | max_steps | 0.177 | fail\* |
| 06 | stoppingcriteria | transformers | 0.334 | max_steps | 0.111 | pass |
| 07 | latency | transformers | 0.315 | max_steps | 0.572 | pass |
| 08 | datadict | django | **0.026** | **EndTurn ✓** | 0.123 | pass |
| | **Total** | | **$1.69** | 2/8 clean | **$2.78** | 3/8 |

**Read this carefully — the totals are not directly comparable:**

1. **Lavoisier capped out on 6/8.** Only tasks 04 and 08 reached a clean `EndTurn`; the rest ran to
   the `max_steps=60` ceiling without the agent deciding it was done. So Lavoisier's $1.69 is a
   *turn-bounded* spend, not a *task-completed* spend — it would rise if allowed to converge, and is
   **not** evidence of "same work for less". Dirac terminated on all 8 (it produces a diff and stops).
2. **The one clean apples-to-apples point** is task 08 (`django` datadict): both finished, Lavoisier
   passed verify, at **$0.026 vs Dirac's $0.123 — ~4.8× cheaper**. Task 04 also completed cleanly for
   Lavoisier ($0.221) but failed the (proxy) verify.
3. **Verify pass/fail is a noisy proxy on both sides** (see §6 caveats): the vscode `tsc` "fails" are
   missing `@types` packages (`mocha`/`semver`/`sinon` — an incomplete `npm ci`), and task 05's
   `ruff` flags 18 **pre-existing** whole-repo lint errors in files the refactor never touched. Cost
   is trustworthy; **pass/fail is not** — for a real verdict, diff against `evals/dirac/dirac_refactor_*`.
4. **Caching is doing its job.** Per task Lavoisier served 0.6M–1.15M tokens from cache (`cache_read`)
   against ~0.2–0.46M billable input — the warm system+tooldef+`--repo-skeleton` prefix. Cost is
   dominated by *output* (thinking=High) and uncached fresh input, exactly as the model pricing predicts.
5. **Dirac measured $2.78 here vs its published $1.48** (~1.9×): repos drifted to branch HEAD
   (unpinned) and we ran `-y` (auto-approve) rather than the published plan-mode protocol, so absolute
   Dirac costs are higher than its headline. The *shape* (vscode tasks dominate its spend) is the
   signal.

**Bottom line:** on identical model + tasks, the two agents are in the **same cost order of
magnitude**; Lavoisier is cheaper per task on the vscode set and on the one task it cleanly completed,
but it has a real **convergence gap** on large multi-file refactors (6/8 hit the turn ceiling) that
Dirac does not. That's an agent-loop finding, not a pricing one — and the lever to close it
(`--max-steps`, better stop-criteria, `--advisor-model` planning) is the subject of §5.

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

1. **On the identical model, cost is the same order of magnitude — neither agent has a runaway edge.**
   The measured suite (§3) was Lavoisier ~$1.69 vs Dirac ~$2.78 on `gemini-3-flash-preview`, but
   Lavoisier capped out on 6/8, so that gap is not a clean win. On the one cleanly-completed,
   verify-passing task it was ~4.8× cheaper ($0.026 vs $0.123). The cross-model suite spread in §4 is
   dominated by **model price** (Gemini-Flash output $3/M vs Claude $15–25/M under thinking=High), not
   agent technique — both use the same curation playbook.
2. **Lavoisier has a convergence gap on large multi-file refactors.** 6/8 tasks ran to `max_steps=60`
   without the agent self-terminating (it over-uses `shell` to re-verify and keeps exploring; one task
   logged 47 shell calls alongside 4 real edits). This is the headline *agent* finding from the run —
   independent of price. Levers to close it: a higher `--max-steps` (now exposed), tighter stop-criteria
   in the loop, and `--advisor-model` (a plan pre-pass that front-loads the exploration). The earlier
   `max_steps=12` default and `--max-tokens=2048` (which truncated thinking=High turns) were both
   measurement bugs found and fixed during this run.
3. **Only `grok-4.1-fast` undercuts Dirac among Lavoisier-supported models** (~$0.5 vs $1.48 suite)
   — because xAI's fast tier ($0.20/$0.50) is cheaper than Gemini Flash. It's the natural like-for-
   like (cheap, fast, strong tool-calling). Haiku is ~1.8× Dirac; Sonnet ~5.7×; Opus ~9×.
4. **Model routing is the lever, and Lavoisier exposes it.** `--cheap-model`/`--escalate-after`,
   `--advisor-model` (expensive planner → cheap executor), and `--tune`/`--tune-bayes` (learn the
   cheapest knobs that still pass `--verify-cmd`) let you run most of a suite on `grok-4.1-fast` or
   Haiku and escalate only the hard tasks — landing a blended cost near or below Dirac's.
5. **Caching is foundational.** The run served 0.6M–1.15M cached tokens/task against ~0.2–0.46M
   billable input; without it those re-reads bill at full input and a Sonnet suite would roughly
   double. This is why `lvz-anthropic` uses the native Messages API (an OpenAI-compat shim drops
   caching) and why `--repo-skeleton` pins the repo outline in the warm prefix.

## 6. Running the full suite — what it costs and requires

> The Gemini-Flash row below was **run** (§3): a measured ~$1.69 for Lavoisier and ~$2.78 for Dirac
> on this machine, both above the ~$1.5 clean estimate because tasks hit caps / repos drifted to HEAD.
> The other rows remain estimates pending a run.

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
3. **A per-task harness — built: [`bench/`](../bench/).** `bench/run.zsh` drives `lavoisier --agent
   --telemetry --verify-cmd … --repo-skeleton …` over the 8 tasks (transcribed verbatim from
   Dirac's `evals/README.md` into `bench/tasks/*.task`), parses each `[telemetry]` line, prices it
   from the §2 table, and prints a per-task + total cost/success report. Run `./bench/run.zsh` for
   identical-model parity (gemini-3-flash-preview, thinking=high) or `--model …` for any other;
   `--smoke` self-tests the plumbing. See [`bench/README.md`](../bench/README.md) for provenance and
   the grading/commit-pinning caveats.
4. **API keys + `protoc`** (build dep) and the binary. Keys for whichever provider(s) above.
5. **Time.** 8 tasks × multiple round-trips; the 25-file Task 6 alone is many turns — roughly 1–3
   hours wall-clock for one clean pass.
6. **True model parity is built in.** Run the suite under `--provider google --model
   gemini-3-flash-preview --thinking high` (the `lvz-google` provider) to compare on Dirac's *exact*
   model and thinking effort — isolating agent efficiency from model price. `grok-4.1-fast` is the
   cheapest supported alternative (flash-tier vs flash-tier) if you want lower cost at some quality
   trade-off.

_Last updated: 2026-06-12 (§3 measured head-to-head added — Lavoisier ~$1.69 vs Dirac ~$2.78 on
`gemini-3-flash-preview`). Prices and Dirac figures are point-in-time; re-derive from §2 sources._
