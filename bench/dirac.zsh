#!/usr/bin/env zsh
# Dirac side of the head-to-head — the mirror of run.zsh, so both agents run the SAME tasks, the
# SAME repos/resets, and the SAME --verify-cmd grading. Drives the installed `dirac` CLI over
# bench/tasks/*.task and records pass/fail; cost is read from Dirac's own reporting.
#
# Prereqs: `npm install -g dirac-cli` (Node 20/22/24, not 25); `export GEMINI_API_KEY="$GOOGLE_API_KEY"`;
#          set thinking/reasoning = HIGH in Dirac's model settings (the benchmark used high).
#
# Usage:
#   bench/dirac.zsh                      # all tasks, dirac -y (yolo/auto-approve), gemini-3-flash-preview
#   bench/dirac.zsh --tasks 5,6,7,8      # subset (skip the heavy vscode tasks)
#   bench/dirac.zsh --flags "-p"         # plan mode (benchmark-faithful, but interactive: you accept each plan)
#   bench/dirac.zsh --model gemini-3-flash-preview
#
# After it finishes, read PRECISE per-task cost from `dirac history` and fill the cost column.
emulate -L zsh
set -uo pipefail

SCRIPT_DIR=${0:A:h}
DIRAC=${DIRAC:-dirac}
MODEL=gemini-3-flash-preview
TASK_FILTER=""
DIRAC_FLAGS="-y"     # non-interactive auto-approve; use "-p" for plan mode (manual accept)

while [[ $# -gt 0 ]]; do
  case $1 in
    --model) MODEL=$2; shift 2;;
    --tasks) TASK_FILTER=$2; shift 2;;
    --flags) DIRAC_FLAGS=$2; shift 2;;
    --dirac) DIRAC=$2; shift 2;;
    -h|--help) sed -n '2,18p' $0; exit 0;;
    *) print -u2 "unknown arg: $1"; exit 2;;
  esac
done

command -v $DIRAC >/dev/null || { print -u2 "error: '$DIRAC' not found — npm install -g dirac-cli"; exit 1; }
[[ -n ${GEMINI_API_KEY:-} ]] || print -u2 "warning: GEMINI_API_KEY not set (try: export GEMINI_API_KEY=\"\$GOOGLE_API_KEY\")"

STAMP=$(date +%Y%m%d-%H%M%S)
RESULTS=$SCRIPT_DIR/results/dirac-$STAMP
REPOS=$SCRIPT_DIR/repos
mkdir -p $RESULTS $REPOS
SUMMARY=$RESULTS/summary.tsv
print "task\tverify\tdirac_cost_usd" > $SUMMARY
print -u2 "Reminder: set thinking=HIGH in Dirac's model settings; record per-task cost from \`dirac history\`.\n"

# Robust clone for huge repos: shallow + single-branch over HTTP/1.1, with retries (macOS system
# git's LibreSSL corrupts large HTTP/2 transfers → "bad decrypt"/early EOF).
clone_repo() {
  local url=$1 dest=$2 attempt
  for attempt in 1 2 3; do
    rm -rf $dest
    if git -c http.version=HTTP/1.1 -c http.postBuffer=1048576000 \
         clone --depth 1 --single-branch --no-tags $url $dest >&2; then
      return 0
    fi
    print -u2 "  clone attempt $attempt failed; retrying in 3s…"; sleep 3
  done
  return 1
}

pass=0 count=0
for f in $SCRIPT_DIR/tasks/*.task(N); do
  id=${f:t:r}; num=${id%%_*}
  if [[ -n $TASK_FILTER && ",$TASK_FILTER," != *",${num#0},"* && ",$TASK_FILTER," != *",$num,"* ]]; then
    continue
  fi

  unset REPO_URL REPO_DIR REF SETUP VERIFY SKELETON
  while IFS= read -r line; do
    [[ $line == '---INSTRUCTION---' ]] && break
    [[ -z $line || $line == \#* ]] && continue
    eval "$line"
  done < $f
  instruction=$(awk 'p; /^---INSTRUCTION---$/{p=1}' $f)
  repo=$REPOS/$REPO_DIR

  print -u2 "=== $id  ($REPO_DIR @ ${REF}) ==="
  if ! git -C $repo rev-parse HEAD >/dev/null 2>&1; then   # missing or partial → (re)clone
    print -u2 "  cloning $REPO_URL (shallow)…"
    clone_repo $REPO_URL $repo || { print -u2 "  clone failed after retries; skipping. Fix: 'brew install git' (OpenSSL), or pre-clone into $repo"; continue; }
  fi
  ( cd $repo
    git checkout -q $REF 2>/dev/null || print -u2 "  (ref '$REF' checkout failed; using HEAD)"
    git reset -q --hard; git clean -qfd
  )
  [[ -n ${SETUP:-} ]] && { print -u2 "  setup…"; ( cd $repo; eval "$SETUP" ) >&2 || print -u2 "  setup failed (continuing)"; }

  log=$RESULTS/$id.log
  print -u2 "  running: $DIRAC $DIRAC_FLAGS --model $MODEL  (plan mode is interactive if -p)"
  ( cd $repo; $DIRAC ${=DIRAC_FLAGS} --model $MODEL "$instruction" ) 2>&1 | tee $log

  # Grade with the SAME verify-cmd the Lavoisier harness uses.
  verdict=fail
  if ( cd $repo; eval "$VERIFY" ) >>$log 2>&1; then verdict=pass; (( pass++ )); fi
  (( count++ ))

  # Best-effort cost scrape from Dirac's output (confirm with `dirac history`).
  cost=$(grep -oiE '\$[0-9]+\.[0-9]+' $log | tail -1)
  print "$id\t$verdict\t${cost:-?}" >> $SUMMARY
  print -u2 "  → verify=$verdict  dirac_cost=${cost:-'(read from dirac history)'}"
done

print -u2 "\n==== DIRAC SUMMARY (model=$MODEL flags=$DIRAC_FLAGS) ===="
column -t -s $'\t' $SUMMARY >&2
print -u2 "\nverify passed: $pass/$count"
print -u2 "Dirac published reference: 8/8, \$1.48 total (0.13/0.23/0.16/0.08/0.17/0.34/0.25/0.12)."
print -u2 "Fill any '?' costs from \`dirac history\`. Logs: $RESULTS"
