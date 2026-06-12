# Lavoisier × Dirac — refactor-suite benchmark (harness + analysis)

This is both the **harness** (scripts under `bench/`) and the **analysis** of a measured head-to-head
against [Dirac](https://dirac.run), a token-efficient coding agent (a Cline fork) that shares
Lavoisier's thesis — *context curation is the whole game*. Both were run on the **identical model**
`gemini-3-flash-preview` (thinking = High) over Dirac's own 8-task refactor suite.

## TL;DR — how efficient is Lavoisier vs Dirac?

**Competitive, not a clear win — with one honest caveat that matters more than the headline.**

- **Measured suite totals** (identical model, this machine): **Lavoisier ≈ $1.69 vs Dirac ≈ $2.78.**
  Do **not** read that as "Lavoisier is 1.6× cheaper" — **Lavoisier failed to self-terminate on 6 of
  8 tasks** (it ran to its turn ceiling, `max_steps=60`, and gave up mid-refactor), so its lower total
  is a *capped* cost, not a *completed* one. Dirac terminated cleanly on all 8.
- **The one fair, complete comparison** is the django `datadict` rename — the only task where both
  agents finished *and* we can grade correctness with the real upstream test suite. There:
  **both pass `forms_tests` (1058 tests)**, and Lavoisier's diff is **verified correct** (it renamed
  every call site, including 8 test files — a complete refactor, not just lint-clean). Cost there is
  **noisy/stochastic**: two Lavoisier runs of that task came in at **$0.026 (11 round-trips)** and
  **$0.20 (42 round-trips)** — i.e. anywhere from ~5× cheaper to ~1.6× *more* than Dirac's $0.123.
- **Net:** on the one task we can fully trust, Lavoisier is **as correct as Dirac and competitive on
  cost**. Its per-round-trip **token efficiency (caching) is excellent** — 0.6M–1.15M tokens/task
  served from cache. But it has a real **agent-convergence weakness** on large multi-file refactors
  that Dirac doesn't, so **we cannot claim a suite-wide efficiency win.** That convergence gap — not
  price — is the thing to fix (see [Findings](#findings)).

> Two honesty caveats run through everything below: (a) the cheap `--verify-cmd` pass/fail is a noisy
> `tsc`/`ruff` proxy on **both** sides (cost is trustworthy; proxy pass/fail is not — that's why we
> added the real-test grader); (b) Lavoisier hit its turn ceiling on most tasks, so treat suite
> totals as *order-of-magnitude* and the single fully-completed task as the firmer signal.

---

## 1. The tasks (provenance — these are the *actual* Dirac tasks)

The 8 prompts in `tasks/*.task` are transcribed **verbatim** from Dirac's own eval suite,
[`dirac-run/dirac` → `evals/README.md`](https://github.com/dirac-run/dirac/tree/master/evals). The
expected result diffs live at `evals/dirac/dirac_refactor_*` in that repo (raw git-diff blobs) — we
fetch them via `gh api` for the correctness grader (§5).

| # | Task | Repo | Kind |
|--|------|------|------|
| 01 | extensionswb_service | vscode | split a large file into modules |
| 02 | sendRequest | vscode | refactor signature → param object, update call sites |
| 03 | IOverlayWidget | vscode | add a mandatory interface method, update all impls |
| 04 | addLogging | vscode | add entry/exit logging to every `runCommand` |
| 05 | DynamicCache | transformers | add a property + edit 8 models' attention |
| 06 | stoppingcriteria | transformers | add `GenerationConfig` params + a new criteria class |
| 07 | latency | transformers | add latency telemetry across all pipelines |
| 08 | datadict | django | rename a Widget method + all call sites repo-wide |

Dirac ran all agents on `gemini-3-flash-preview`, reasoning = **high**, one agent at a time, starting
in plan mode, `git reset --hard && git clean -fd` before each, ≥3 tries for failures.

## 2. Run it

```sh
# Identical-model parity with Dirac (default: provider google, gemini-3-flash-preview, thinking high):
./bench/run.zsh

# A cheaper model (same tasks, same harness):
./bench/run.zsh --provider xai --model grok-4.1-fast --thinking ""    # (xai ignores --thinking)
./bench/run.zsh --provider anthropic --model claude-sonnet-4-6

# Subset by task number (skip the heavy vscode tasks 1–4):
./bench/run.zsh --tasks 5,6,7,8

# Approximate Dirac's "plan mode" with an advisor pre-pass:
./bench/run.zsh --extra "--advisor-model gemini-3-flash-preview"

# Validate the harness plumbing cheaply (throwaway repo, trivial task):
./bench/run.zsh --smoke

# Direct correctness check (apply each agent's diff, run real upstream tests):
./bench/realtest.zsh --lvz-results bench/results/<timestamp>

# Dirac side (drives the installed `dirac` CLI over the same tasks):
./bench/dirac.zsh
```

Output: `bench/results/<timestamp>/summary.tsv` (per-task `success`, tokens, `cost_usd`), a full
`<task>.log`, and `<task>.patch` (the agent's captured diff, used by `realtest.zsh`). Cloned repos
are cached under `bench/repos/` (both git-ignored).

Prereqs: a built `lavoisier` (the harness builds `--release` once, or pass `--bin`), the relevant
**API key** (`GOOGLE_API_KEY` for the default), `git`, `gh` (for `realtest.zsh`), and per-repo tooling
— `python3` (+ auto `venv`/`ruff` for transformers/django) and `npm` (a heavy `npm ci` for vscode).

## 3. Pricing used (June 2026, USD per million tokens)

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
`gemini-3-flash-preview` is **cheaper than every Claude tier on output** ($3/M vs $5–25/M) — and
thinking="High" makes runs output-heavy, which is where that gap bites. The `PRICING` table in
`run.zsh` mirrors this; edit both together when rates move. Sources:
[Anthropic](https://platform.claude.com/docs/en/about-claude/pricing),
[xAI](https://docs.x.ai/developers/models), [Gemini](https://ai.google.dev/gemini-api/docs/pricing).

Dirac's **published** reference (its own measured numbers, for context): 8/8 success at per-task
`0.13/0.23/0.16/0.08/0.17/0.34/0.25/0.12 = $1.48 total`. vs other agents on the same model: Cline
$0.49/task, Roo $0.60, Kilo $0.73, Opencode ~$0.43.

## 4. Measured head-to-head (identical model, 2026-06-12)

Both agents over the 8 tasks, same cloned repos at branch HEAD, same model, graded by the same
`--verify-cmd` (`tsc --noEmit` for vscode, `ruff check` for transformers/django). Lavoisier via
`run.zsh` (`--max-steps 60 --max-tokens 16384 --repo-skeleton`); Dirac via `dirac.zsh` (`dirac -y`).
Cost from each agent's own token accounting (Lavoisier's `--telemetry` line priced at §3; Dirac's
`Total Cost:` line).

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

**The totals are not directly comparable:**

1. **Lavoisier capped out on 6/8.** Only tasks 04 and 08 reached a clean `EndTurn`; the rest ran to
   `max_steps=60` without the agent deciding it was done. So $1.69 is a *turn-bounded* spend, not a
   *task-completed* one — it would rise if allowed to converge. Dirac terminated on all 8.
2. **The one clean apples-to-apples point** is task 08 (`django` datadict): both finished, both later
   verified correct by real tests (§5). Task 04 also completed cleanly for Lavoisier but failed the
   (proxy) verify.
3. **Verify pass/fail is a noisy proxy on both sides:** the vscode `tsc` "fails" are missing `@types`
   packages (`mocha`/`semver`/`sinon` — incomplete `npm ci`), and task 05's `ruff` flags 18
   **pre-existing** whole-repo lint errors in files the refactor never touched. Cost is trustworthy;
   proxy pass/fail is not — hence the real-test grader in §5.
4. **Caching is doing its job.** Per task Lavoisier served 0.6M–1.15M tokens from cache against
   ~0.2–0.46M billable input — the warm system+tooldef+`--repo-skeleton` prefix. Cost is dominated by
   *output* (thinking=High) and uncached fresh input, exactly as the pricing predicts.
5. **Dirac measured $2.78 here vs its published $1.48** (~1.9×): repos drifted to branch HEAD
   (unpinned) and we ran `-y` (auto-approve) rather than published plan-mode, so absolute Dirac costs
   run higher than its headline. The *shape* (vscode tasks dominate its spend) is the signal.

## 5. Direct correctness — real upstream tests (not the lint proxy)

The `--verify-cmd` proxy only proves "compiles / lints clean." `bench/realtest.zsh` grades
*correctness* directly: it applies each agent's **actual diff** (Lavoisier's captured
`results/<stamp>/<id>.patch`; Dirac's published reference diff fetched via `gh api`) to a clean
checkout and runs the task's **real upstream test suite** (the `REALTEST` field in the `.task`).

This is only sound where the upstream suite exercises the change. **One task qualifies cleanly:
`08 datadict`** (django) — the rename `value_from_datadict → extract_value_from_request`, whose own
test files call the method, so an incomplete rename fails with `AttributeError`. We validated the gate
discriminates: full reference patch → **0 errors**; a source-only rename (tests left unmodified) →
**22 errors**.

| Task | gate | **Lavoisier** | **Dirac** | notes |
|---|---|:--:|:--:|---|
| 08 datadict (django) | `runtests.py forms_tests` (1058 tests) | **pass** | **pass** | both renamed **all** call sites incl. 8 test files — a *complete* refactor, not just lint-clean |

So on the one task with a real, discriminating correctness gate, **Lavoisier's output is verified
correct and matches Dirac.** (Cost note: a dedicated re-run of task 08 cost Lavoisier **$0.20 at 42
round-trips** vs the §4 run's $0.026 at 11 — the agent is **stochastic** in how long it explores, so
any single per-task cost is a sample, not a constant.)

**Why only one task gets a real gate here** (the rest stay on the §4 proxy):
- **vscode (01–04):** the real suite needs a full Electron build + headless run — impractical to
  stand up; `tsc --noEmit` is the available signal (and for tasks 02/03 it's meaningful — a missed
  call site / unimplemented interface method *is* a type error).
- **transformers (05–07):** torch installs here (cp314 wheel), but the baseline
  `test_stopping_criteria` suite is **already red on a clean tree** (6/13 fail — dev-version drift +
  offline tokenizer), and the tasks are *additive* features the upstream tests don't cover — so a
  pass/fail wouldn't isolate the agent's change. Documented as infeasible-here rather than run.

## 6. Re-pricing the suite on other Lavoisier-supported models

A task's token *volume* is roughly model-independent (same refactor → same context + similar edit),
so anchor to Dirac's measured $1.48 on Gemini and re-price that volume on each model. Using a
representative thinking-High mix (≈70% cached re-reads, 12% fresh input, 8% cache-creation, 10% output
incl. thinking):

| Model | blended $/M | ratio vs Gemini | **8-task suite** | per task | vs Dirac $1.48 |
|---|--:|--:|--:|--:|--:|
| `grok-4.1-fast` | 0.13 | 0.28 | **~$0.5** | ~$0.06 | **~3× cheaper** |
| `gemini-3-flash-preview` *(Dirac, measured)* | 0.44 | 1.0 | **$1.48** | $0.185 | baseline |
| `claude-haiku-4-5` | 0.79 | 1.8 | **~$2.7** | ~$0.34 | ~1.8× |
| `claude-sonnet-4-6` | 2.37 | 5.3 | **~$8.5** | ~$1.05 | ~5.7× |
| `grok-4` | 2.63 | 5.9 | **~$10** | ~$1.25 | ~6.6× |
| `claude-opus-4-8` | 3.95 | 8.9 | **~$13.5** | ~$1.70 | ~9× |

These rows are a **projection** (only the Gemini row is measured); per-model **ratios are robust**,
absolute figures carry ~±40%. The spread is dominated by **model price**, not agent technique. With
retries, budget ~2–3× a clean pass.

## Findings

1. **On the identical model, cost is the same order of magnitude — neither agent has a runaway edge.**
   Measured suite Lavoisier ~$1.69 vs Dirac ~$2.78, but Lavoisier capped on 6/8 so that gap isn't a
   clean win. On the one cleanly-completed, **correctness-verified** task they tie (both pass real
   tests) at comparable, noisy cost. The cross-model spread (§6) is **model price**, not technique.
2. **Lavoisier's headline weakness is agent convergence, not tokens.** 6/8 tasks ran to `max_steps=60`
   without self-terminating — it over-uses `shell` to re-verify and keeps exploring (e.g. task 02
   spent **57 of 60 turns** on `grep -r`/`sed -n` and made **zero edits**). The root cause is no
   authoritative "that's all of them" signal: ad-hoc `grep` never tells the model when it has covered
   every call site, so it keeps searching. The earlier `max_steps=12` default and `--max-tokens=2048`
   (which truncated thinking=High turns) were measurement bugs found + fixed here. Two fixes for the
   *gap itself* were then tried:
   - **`--advisor-model` plan pre-pass (≈ Dirac's plan mode) — measured, did NOT fix it.** A full
     suite run with `--advisor-model gemini-3-flash-preview` converged 3/8 (`EndTurn`) vs the 2/8
     baseline and passed 2/8 verify vs 1/8, but cost **+32% ($2.23 vs $1.69)** and even *regressed*
     one task (04: `EndTurn`→`max_steps`). 5/8 still hit the cap. A plan doesn't remove the reason the
     loop spins, so it's a nudge, not a fix.
   - **`find_references` tool — measured: helps *action*, does NOT fix *termination*.** One call
     returns the complete, AST-precise reference set, grouped by file with a count. A full suite run
     with it (tasks 01–06 valid; 07–08 hit Gemini 429s) showed it **was adopted** (4/4 rename/call-site
     tasks used it; the two additive transformers tasks correctly didn't) and **broke analysis
     paralysis**: task 02 went from **0 edits to 7**, and task 04 collapsed from **rt=55 → rt=18,
     $0.22 → $0.055** (4× cheaper, clean `EndTurn`). But the model uses it to *locate* sites and then
     **still keeps grepping/re-verifying** (35–43 shell calls alongside it) and rides to `max_steps`
     anyway — 5/6 valid tasks still capped. Finding the set doesn't make the agent stop.
   - **`edit_files` tool — built (write-side batch), not yet benched.** Applies anchored edits across
     many files in one call (vs one `edit_anchored` per file); collapses the *edit* phase of a rename
     from ~N round-trips to 1. Reduces turns spent editing, but — like the above — does not by itself
     add a stop condition.
   - **The validated conclusion: the unsolved lever is *termination*.** Three levers (advisor,
     find_references, edit_files) each improve the *action* phase; none makes the agent decide it is
     **done**. The loop has no "I'm finished" condition, so it finds the sites, edits them, then keeps
     going. The remaining fix is an explicit stop-criterion — a **no-progress circuit-breaker** (force
     a conclusion after N edit-free turns) and **in-loop verify** (run `--verify-cmd` mid-loop and stop
     when green; today it only runs after `Done`). That, paired with the batch tools, is what should
     close the gap.
3. **Token efficiency (caching) is genuinely strong.** 0.6M–1.15M cached tokens/task vs ~0.2–0.46M
   billable input; without caching those re-reads bill at full input and a Sonnet suite would roughly
   double. This is why `lvz-anthropic` uses the native Messages API (an OpenAI-compat shim drops
   caching) and why `--repo-skeleton` pins the repo outline in the warm prefix.
4. **Only `grok-4.1-fast` undercuts Dirac among supported models** (~$0.5 vs $1.48 suite). Haiku
   ~1.8× Dirac; Sonnet ~5.7×; Opus ~9×. Model routing is the lever and Lavoisier exposes it:
   `--cheap-model`/`--escalate-after`, `--advisor-model`, `--tune`/`--tune-bayes` (learn the cheapest
   knobs that still pass `--verify-cmd`) — run most of a suite cheap, escalate only the hard tasks.

## Caveats — read before trusting the numbers

- **Commits aren't pinned.** Dirac didn't publish the repo commits, so `REF` defaults to each repo's
  branch HEAD. Results won't be bit-identical to Dirac's run; **pin a commit** in each `.task` for
  reproducibility (the codebases drift, which changes task difficulty).
- **`VERIFY` is a reconstructed proxy.** A *pass* means "lints/typechecks clean," not "semantically
  equivalent to Dirac's diff." For rigorous grading use `realtest.zsh` (§5) where the upstream suite
  covers the change, or diff the agent's output against `evals/dirac/dirac_refactor_*`.
- **Per-task cost is stochastic.** The agent varies how long it explores (task 08: 11 vs 42
  round-trips across two runs) — treat single per-task costs as samples, not constants.
- **Plan mode differs.** Dirac started in plan mode; Lavoisier has no separate plan mode —
  `--extra "--advisor-model …"` adds a plan pre-pass to approximate it.
- **vscode tasks are heavy.** Tasks 1–4 need a full `npm ci` + whole-project `tsc`; tasks 5–8 only
  need `ruff`. Use `--tasks` to subset.

_Last updated: 2026-06-12. Measured §4 head-to-head (Lavoisier ~$1.69 vs Dirac ~$2.78 on
`gemini-3-flash-preview`) + §5 real-upstream-test correctness (both pass django `forms_tests`). Prices
and Dirac figures are point-in-time; re-derive from §3 sources._
