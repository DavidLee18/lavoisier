# Dirac refactor-suite harness

Drives `lavoisier --agent` over the **8 real Dirac refactor tasks**, tallies token cost from each
task's `--telemetry` line at current model prices, and uses each task's `--verify-cmd` (ruff/tsc)
as the pass/fail signal — producing a cost + success report directly comparable to Dirac's published
**$1.48 total (8/8)** on `gemini-3-flash-preview`. See `docs/BENCHMARKS.md` for the analysis.

## Provenance — these are the *actual* tasks

The 8 task prompts in `tasks/*.task` are transcribed **verbatim** from Dirac's own eval suite:
[`dirac-run/dirac` → `evals/README.md`](https://github.com/dirac-run/dirac/tree/master/evals).
The expected result diffs live under `evals/dirac/dirac_refactor_*` in that repo for manual audit.

| # | Task | Repo | In Dirac's run |
|--|------|------|---------------:|
| 01 | extensionswb_service | vscode | $0.17 (T5)¹ |
| 02 | sendRequest | vscode | — |
| 03 | IOverlayWidget | vscode | — |
| 04 | addLogging | vscode | — |
| 05 | DynamicCache | transformers | — |
| 06 | stoppingcriteria | transformers | $0.34 (T6)¹ |
| 07 | latency | transformers | — |
| 08 | datadict | django | — |

¹ Dirac published per-task costs ($0.13/$0.23/$0.16/$0.08/$0.17/$0.34/$0.25/$0.12, total $1.48) but
not a name↔number mapping, so only the obvious anchors are noted. Dirac ran on
`gemini-3-flash-preview`, reasoning = **high**, each agent alone, starting in plan mode.

## Run it

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
```

Output: `bench/results/<timestamp>/summary.tsv` (per-task `success`, tokens, `cost_usd`) plus a full
`<task>.log` per task. Cloned repos are cached under `bench/repos/` (both git-ignored).

Prereqs: a built `lavoisier` (the harness builds `--release` once, or pass `--bin`), the relevant
**API key** (`GOOGLE_API_KEY` for the default), `git`, and per-repo tooling — `python3` (+ auto
`venv`/`ruff` for transformers/django) and `npm` (a heavy `npm ci` for the vscode tasks).

## How cost & success are computed

- **Cost** = `Σ tokens × price/M` from the per-task `[telemetry]` line, using the table in
  `run.zsh` (kept in sync with `docs/BENCHMARKS.md` §2). Edit `PRICING` there when rates move.
- **Success (proxy)** = the `--verify-cmd` exit code (the same gate ATO uses): the agent runs it on
  clean completion; exit 0 ⇒ `success=true`. A per-task `--budget 4M` tokens caps a runaway loop.
- **Success (real)** = `bench/realtest.zsh` — the *direct correctness* check. `run.zsh` now captures
  each agent's actual diff to `results/<stamp>/<id>.patch`; `realtest.zsh` applies it (and Dirac's
  published reference diff, fetched via `gh api`) to a clean checkout and runs the task's **real
  upstream test** (the `REALTEST` field in the `.task`). Only tasks whose upstream suite exercises
  the change qualify — today **`08_datadict`** (django `forms_tests`; both agents pass, see
  `docs/BENCHMARKS.md` §3a). Run: `./bench/realtest.zsh --lvz-results bench/results/<stamp>`.

## Caveats — read before trusting the numbers

- **Commits aren't pinned.** Dirac didn't publish the repo commits, so `REF` defaults to each repo's
  branch HEAD. Results won't be bit-identical to Dirac's run; **pin a commit** in each `.task` for
  reproducibility (the codebases drift, which can change task difficulty).
- **`VERIFY` is a reconstructed proxy.** Dirac graded via the in-prompt linter checks plus a manual
  audit against its checked-in diffs. Here `--verify-cmd` runs `ruff check <scope>` (transformers/
  django) or `tsc --noEmit` (vscode) — a real signal, but a *pass* means "lints/typechecks clean",
  not "semantically equivalent to Dirac's diff". For rigorous grading use `realtest.zsh` (above) where
  the upstream suite covers the change, or diff the agent's output against `evals/dirac/dirac_refactor_*`.
- **Plan mode differs.** Dirac started in plan mode (accept plan → act). Lavoisier has no separate
  plan mode; `--extra "--advisor-model …"` adds a plan pre-pass to approximate it.
- **vscode tasks are heavy.** Tasks 1–4 need a full `npm ci` (large, slow) and a whole-project
  `tsc`; tasks 5–8 (transformers/django) only need `ruff` and are far cheaper to run. Use `--tasks`
  to subset.
- **This measures cost, not quality parity.** Pair the cost table with the success column, and for a
  real verdict, audit the diffs.
