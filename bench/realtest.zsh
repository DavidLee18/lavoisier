#!/usr/bin/env zsh
# Real-upstream-test grader — the *direct* Lavoisier-vs-Dirac correctness check (not the
# tsc/ruff proxy). For each task that defines a REALTEST command, it applies an agent's actual
# diff to a clean checkout and runs the task's real upstream test target, for BOTH agents:
#   • Lavoisier — the patch captured by run.zsh into bench/results/<stamp>/<id>.patch
#   • Dirac     — the reference diff published at github.com/dirac-run/dirac
#                 evals/dirac/dirac_refactor_<name> (fetched via `gh api`)
# A task is only graded if it has a REALTEST field (today: 08_datadict — the django rename, whose
# own test suite exercises the renamed method, so a partial rename fails). Tasks without REALTEST
# (vscode: needs a full Electron build; transformers: torch/offline + additive features not
# covered upstream) are skipped here and stay on the proxy in run.zsh.
#
# Usage:
#   bench/realtest.zsh --lvz-results bench/results/<stamp>     # grade every REALTEST task
#   bench/realtest.zsh --lvz-results <dir> --tasks 8           # one task
#   bench/realtest.zsh --lvz-results <dir> --agent dirac       # only the Dirac side
emulate -L zsh
set -uo pipefail

SCRIPT_DIR=${0:A:h}
REPOS=$SCRIPT_DIR/repos
LVZ_RESULTS=""
TASK_FILTER=""
AGENTS="lavoisier dirac"

while [[ $# -gt 0 ]]; do
  case $1 in
    --lvz-results) LVZ_RESULTS=${2:A}; shift 2;;
    --tasks)       TASK_FILTER=$2; shift 2;;
    --agent)       AGENTS=$2; shift 2;;
    -h|--help)     sed -n '2,20p' $0; exit 0;;
    *) print -u2 "unknown arg: $1"; exit 2;;
  esac
done

command -v gh >/dev/null || { print -u2 "error: gh (GitHub CLI) required to fetch Dirac reference diffs"; exit 1; }

# Fetch a Dirac reference diff (raw git-diff blob) to stdout.
dirac_ref_patch() {  # $1 = task short name (e.g. datadict)
  gh api "repos/dirac-run/dirac/contents/evals/dirac/dirac_refactor_$1" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null
}

# Apply $patch to a clean $repo and run $realtest; echo pass|fail|apply-fail|no-patch.
grade() {  # $1=repo $2=patchfile $3=realtest
  local repo=$1 patch=$2 realtest=$3
  [[ -s $patch ]] || { print "no-patch"; return; }
  ( cd $repo; git reset -q --hard 2>/dev/null; git clean -qfd -e .venv 2>/dev/null )
  if ! ( cd $repo; git apply --whitespace=fix "$patch" 2>/dev/null ) \
     && ! ( cd $repo; git apply --3way "$patch" 2>/dev/null ); then
    ( cd $repo; git reset -q --hard; git clean -qfd -e .venv )
    print "apply-fail"; return
  fi
  local rc=0
  ( cd $repo; eval "$realtest" ) >/dev/null 2>&1 || rc=$?
  ( cd $repo; git reset -q --hard; git clean -qfd -e .venv )
  [[ $rc -eq 0 ]] && print "pass" || print "fail"
}

print "task\tlavoisier_realtest\tdirac_realtest"
graded=0
for f in $SCRIPT_DIR/tasks/*.task(N); do
  id=${f:t:r}; num=${id%%_*}; name=${id#*_}
  if [[ -n $TASK_FILTER && ",$TASK_FILTER," != *",${num#0},"* && ",$TASK_FILTER," != *",$num,"* ]]; then
    continue
  fi
  unset REPO_DIR REALTEST
  while IFS= read -r line; do
    [[ $line == '---INSTRUCTION---' ]] && break
    [[ -z $line || $line == \#* ]] && continue
    eval "$line"
  done < $f
  [[ -z ${REALTEST:-} ]] && { print -u2 "skip $id (no REALTEST — proxy-only; see run.zsh)"; continue; }
  repo=$REPOS/$REPO_DIR
  print -u2 "=== $id  (real test: $REALTEST) ==="

  lvz="—" dir="—"
  if [[ " $AGENTS " == *" lavoisier "* ]]; then
    if [[ -n $LVZ_RESULTS ]]; then
      lvz=$(grade $repo "$LVZ_RESULTS/$id.patch" "$REALTEST")
    else
      lvz="no-results-dir"
    fi
    print -u2 "  lavoisier: $lvz"
  fi
  if [[ " $AGENTS " == *" dirac "* ]]; then
    ref=$(mktemp); dirac_ref_patch "$name" > $ref
    dir=$(grade $repo "$ref" "$REALTEST"); rm -f $ref
    print -u2 "  dirac:     $dir"
  fi
  print "$id\t$lvz\t$dir"
  (( graded++ ))
done

print -u2 "\ngraded $graded task(s) with a real upstream test. Tasks without REALTEST stay on the run.zsh proxy."
