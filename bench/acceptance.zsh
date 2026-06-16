#!/usr/bin/env zsh
# Live per-task ACCEPTANCE gate — run *inside the target repo* as the agent's --verify-cmd
# (via run.zsh --acceptance-gate). Exit 0 iff the task's concrete requirements are met on the
# CURRENT working tree. This is the real completeness signal --verify-and-fix needs: unlike the
# noisy lint proxy, it tests what the task actually asked for (files created, all targets edited,
# old name gone, real tests pass), so the agent iterates until the task is genuinely done.
#
# Mirrors the checks in verify.zsh, but operates on $PWD (no reset/patch). Usage: acceptance.zsh <n>
emulate -L zsh
set -uo pipefail
num=${1:?task number}

has() { grep -rqE "$1" "$2" 2>/dev/null }                 # regex present under a path
# tsc: pass iff no NEW type errors vs the pinned baseline (6) — the change must typecheck clean.
tsc_ok() { [ "$(node_modules/.bin/tsc --noEmit -p src/tsconfig.json 2>&1 | grep -c 'error TS')" -le 6 ] }
# ruff on the .py files this change touched (transformers/django baselines are ruff-clean).
ruff_changed() {
  local files=( ${(f)"$(git diff --name-only -- '*.py')"} )
  (( ${#files} )) || return 0
  .venv/bin/ruff check ${files} >/dev/null 2>&1
}
all_models() {  # every task-05 model dir mentions is_stale
  local m
  for m in llama4 mistral4 qwen3 gemma4 deepseek_v3 cohere2 olmo3 ministral3; do
    has is_stale src/transformers/models/$m || return 1
  done
}

case $num in
  1) [[ -s src/vs/workbench/contrib/extensions/browser/extension.ts \
        && -s src/vs/workbench/contrib/extensions/browser/extensions.ts ]] && tsc_ok ;;
  2) tsc_ok ;;
  3) has 'getName\(\): string' src/vs && tsc_ok ;;
  4) has 'console\.log' src/vs && tsc_ok ;;
  5) has is_stale src/transformers/cache_utils.py && all_models \
       && has UserWarning src/transformers/models && ruff_changed ;;
  6) has entropy_threshold src/transformers/generation \
       && has entropy_patience src/transformers/generation \
       && has 'class EntropyStoppingCriteria' src/transformers/generation \
       && has 'EntropyStoppingCriteria\(' src/transformers/generation && ruff_changed ;;
  7) has record_latency src/transformers/pipelines \
       && has 'Inference latency' src/transformers/pipelines \
       && has perf_counter src/transformers/pipelines && ruff_changed ;;
  8) has 'def extract_value_from_request' django/forms/widgets.py \
       && ! has 'def value_from_datadict' django/forms \
       && ( .venv/bin/pip -q install asgiref sqlparse >/dev/null 2>&1
            cd tests && PYTHONPATH=.. ../.venv/bin/python runtests.py forms_tests --parallel 1 >/dev/null 2>&1 ) ;;
  *) print -u2 "acceptance: unknown task $num"; exit 2 ;;
esac
