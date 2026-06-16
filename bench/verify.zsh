#!/usr/bin/env zsh
# Deterministic, reproducible correctness verifier for the benchmark.
#
# The lint `--verify-cmd` in run.zsh/dirac.zsh is a noisy proxy (a clean lint can pass on an
# UNCHANGED tree). This grader instead applies a captured agent diff to a clean, PINNED checkout
# (bench/PINS.txt) and runs a per-task ACCEPTANCE CHECK encoding the task's concrete, objective
# requirements — plus a real gate where one isolates the change (ruff for Python, the django test
# suite for 08, a tsc error-count delta for the vscode/TS tasks). No model calls: it grades the
# already-captured patches, so it is cheap and anyone can re-run it to confirm every result.
#
# Usage:
#   bench/verify.zsh --results bench/results/<stamp>          # grade one run's patches
#   bench/verify.zsh --results <dir> --tasks 5,6,8            # subset
#   bench/verify.zsh --results <dir> --skip-tsc               # structural+ruff only (fast; skip vscode tsc)
#
# A task PASSES iff every applicable check passes. Output: one row per task + a total.
emulate -L zsh
set -uo pipefail
SCRIPT_DIR=${0:A:h}
REPOS=$SCRIPT_DIR/repos
RESULTS=""; TASK_FILTER=""; SKIP_TSC=0
while [[ $# -gt 0 ]]; do case $1 in
  --results) RESULTS=${2:A}; shift 2;;
  --tasks)   TASK_FILTER=$2; shift 2;;
  --skip-tsc) SKIP_TSC=1; shift;;
  -h|--help) sed -n '2,20p' $0; exit 0;;
  *) print -u2 "unknown arg: $1"; exit 2;; esac
done
[[ -n $RESULTS && -d $RESULTS ]] || { print -u2 "error: --results <dir> required (a run's results dir with <task>.patch files)"; exit 2; }

# pinned SHAs (bench/PINS.txt) — assert the local clones are at them, so checks are reproducible.
typeset -A PIN
PIN[django]=f1440a752ec034277ccdad914995c3f164308e41
PIN[transformers]=801413961815dad5f943b77bb83645c5ef7bcc82
PIN[vscode]=588cbae5ac25eda4c1f07e9a64e9bd96d2e49bad

# Restore a repo to its pinned commit, then apply the captured patch. Returns 1 if the patch
# doesn't apply (a malformed/empty diff fails closed — that's a fail, not a silent pass).
prepare() {  # $1=repo  $2=patch
  local repo=$REPOS/$1 patch=$2
  [[ $(git -C $repo rev-parse HEAD) == ${PIN[$1]} ]] || { print -u2 "  ! $1 not at pinned $PIN[$1]"; }
  ( cd $repo && git reset -q --hard ${PIN[$1]} && git clean -qfd -e .venv -e node_modules )
  [[ -s $patch ]] || return 1
  ( cd $repo && git apply --whitespace=nowarn "$patch" 2>/dev/null ) || return 1
  return 0
}

# tsc error count for the vscode src project (cached per HEAD state). Empty patch baseline is
# computed once; a task passes the tsc gate iff it adds no NEW type errors.
tsc_errors() { ( cd $REPOS/vscode && node_modules/.bin/tsc --noEmit -p src/tsconfig.json 2>&1 | grep -cE "error TS" ) }
TSC_BASE="${TSC_BASE:-}"   # honour an inherited baseline (driver computes once across dirs)
tsc_gate() {  # returns 0 if applying the patch added no new tsc errors
  (( SKIP_TSC )) && { print -n "tsc:skipped "; return 0; }
  [[ -n $TSC_BASE ]] || { ( cd $REPOS/vscode && git reset -q --hard ${PIN[vscode]} && git clean -qfd -e .venv -e node_modules ); TSC_BASE=$(tsc_errors); }
  local after=$(tsc_errors)
  print -n "tsc:$TSC_BASE→$after "
  (( after <= TSC_BASE ))
}

# Run ruff on the .py files the applied patch actually changed (so pre-existing repo lint can't
# fail a clean edit). Pass = exit 0; vacuously passes if no .py changed.
ruff_changed() {
  local files; files=( ${(f)"$( cd $REPOS/transformers && git diff --name-only -- '*.py' )"} )
  (( ${#files} )) || return 0
  ( cd $REPOS/transformers && .venv/bin/ruff check ${files} >/dev/null 2>&1 )
}
has() { grep -rqE "$2" $REPOS/$1 2>/dev/null }          # regex present somewhere under repo path
hasf() { grep -qE "$2" $REPOS/$1 2>/dev/null }          # regex present in a specific file

# ---- per-task acceptance checks (objective requirements from the task prompts) ----
# Each prints a short reason and returns 0 (pass) / 1 (fail).
check_01() {  # split extensionsWorkbenchService.ts into extension.ts + extensions.ts
  local b=$REPOS/vscode/src/vs/workbench/contrib/extensions/browser
  [[ -s $b/extension.ts && -s $b/extensions.ts ]] || { print -n "files-missing "; return 1; }
  tsc_gate
}
check_02() {  # chat sendRequest → single param object, all call sites updated → must typecheck
  tsc_gate
}
check_03() {  # IOverlayWidget gains getName(): string; all implementors updated → must typecheck
  hasf "vscode/src/vs/editor/browser/editorBrowser.ts" "getName\\(\\): string" || has "vscode/src" "getName\\(\\): string" || { print -n "getName-absent "; return 1; }
  tsc_gate
}
check_04() {  # console.log entry/exit added to runCommand defs (logging; must still typecheck)
  has "vscode/src" "console\\.log" || { print -n "no-logging "; return 1; }
  tsc_gate
}
check_05() {  # DynamicCache.is_stale + 8 models bypass with UserWarning; ruff clean
  hasf "transformers/src/transformers/cache_utils.py" "is_stale" || { print -n "is_stale-absent "; return 1; }
  local m models=(llama4 mistral4 qwen3 gemma4 deepseek_v3 cohere2 olmo3 ministral3) miss=0
  for m in $models; do has "transformers/src/transformers/models/$m" "is_stale" || (( miss++ )); done
  (( miss == 0 )) || { print -n "models-missing:$miss "; return 1; }
  has "transformers/src/transformers/models" "UserWarning" || { print -n "no-UserWarning "; return 1; }
  ruff_changed || { print -n "ruff-fail "; return 1; }
}
check_06() {  # GenerationConfig entropy params + EntropyStoppingCriteria class + wired in
  has "transformers/src/transformers/generation" "entropy_threshold" || { print -n "no-entropy_threshold "; return 1; }
  has "transformers/src/transformers/generation" "entropy_patience" || { print -n "no-entropy_patience "; return 1; }
  has "transformers/src/transformers/generation" "class EntropyStoppingCriteria" || { print -n "no-class "; return 1; }
  has "transformers/src/transformers/generation" "EntropyStoppingCriteria\\(" || { print -n "not-wired "; return 1; }
  ruff_changed || { print -n "ruff-fail "; return 1; }
}
check_07() {  # record_latency on base pipeline + the exact latency log message
  has "transformers/src/transformers/pipelines" "record_latency" || { print -n "no-record_latency "; return 1; }
  has "transformers/src/transformers/pipelines" "Inference latency" || { print -n "no-log-msg "; return 1; }
  has "transformers/src/transformers/pipelines" "perf_counter" || { print -n "no-perf_counter "; return 1; }
  ruff_changed || { print -n "ruff-fail "; return 1; }
}
check_08() {  # rename value_from_datadict → extract_value_from_request + real forms_tests
  hasf "django/django/forms/widgets.py" "def extract_value_from_request" || { print -n "new-name-absent "; return 1; }
  ! has "django/django/forms" "def value_from_datadict" || { print -n "old-name-remains "; return 1; }
  print -n "forms_tests… "
  ( cd $REPOS/django && .venv/bin/pip -q install asgiref sqlparse >/dev/null 2>&1; cd tests && PYTHONPATH=.. ../.venv/bin/python runtests.py forms_tests --parallel 1 >/dev/null 2>&1 )
}

typeset -A REPO_OF
REPO_OF=(01 vscode 02 vscode 03 vscode 04 vscode 05 transformers 06 transformers 07 transformers 08 django)

pass=0 count=0
print -u2 "verifying $RESULTS (pinned repos; real acceptance checks)\n"
for f in $SCRIPT_DIR/tasks/*.task(N); do
  id=${f:t:r}; num=${id%%_*}; n=${num#0}
  [[ -n $TASK_FILTER && ",$TASK_FILTER," != *",$n,"* && ",$TASK_FILTER," != *",$num,"* ]] && continue
  patch=$RESULTS/$id.patch
  [[ -f $patch ]] || { print -u2 "  $id: NO PATCH (skipped)"; continue; }
  printf -- "  %-24s " $id
  if ! prepare ${REPO_OF[$num]} $patch; then print -u2 "FAIL (empty/non-applying patch)"; (( count++ )); continue; fi
  if check_$num; then print -u2 "PASS"; (( pass++ )); else print -u2 "FAIL"; fi
  (( count++ ))
done
# Leave repos clean at their pins.
for r in django transformers vscode; do ( cd $REPOS/$r && git reset -q --hard ${PIN[$r]} && git clean -qfd -e .venv -e node_modules ); done
print -u2 "\nVERIFIED: $pass/$count tasks pass real acceptance checks."
