#!/usr/bin/env zsh
# Lavoisier × Dirac refactor-suite harness.
#
# Drives `lavoisier --agent` over the reconstructed Dirac refactor tasks (bench/tasks/*.task),
# tallies token cost from the per-task `--telemetry` line, and uses each task's `--verify-cmd`
# (ruff/tsc) as the pass/fail signal — the same exit-code gate ATO uses. Prints a per-task and
# total cost+success table comparable to Dirac's published $1.48 suite (8/8) on
# `gemini-3-flash-preview` (see docs/BENCHMARKS.md, bench/README.md).
#
# Usage:
#   bench/run.zsh                                   # full suite, gemini-3-flash-preview, thinking=high
#   bench/run.zsh --model claude-sonnet-4-6 --provider anthropic
#   bench/run.zsh --tasks 5,6,8                     # only those task numbers (skip the heavy vscode ones)
#   bench/run.zsh --extra "--advisor-model claude-opus-4-8"   # pass-through lavoisier flags (e.g. plan pre-pass)
#   bench/run.zsh --smoke                           # cheap end-to-end self-test (no heavy repos)
#
# Identical-model parity with Dirac: --provider google --model gemini-3-flash-preview --thinking high.
emulate -L zsh
set -uo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}

PROVIDER=google
MODEL=gemini-3-flash-preview
THINKING=high
TASK_FILTER=""
EXTRA_FLAGS=""
BUDGET=4000000      # per-task token ceiling (safety net against a runaway loop)
MAX_STEPS=60        # agent round-trip ceiling — real refactors need many explore→edit turns
MAX_TOKENS=16384    # per-turn output cap — thinking=high needs headroom or turns truncate (MaxTokens)
BIN=""
SMOKE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --provider)  PROVIDER=$2; shift 2;;
    --model)     MODEL=$2; shift 2;;
    --thinking)  THINKING=$2; shift 2;;
    --tasks)     TASK_FILTER=$2; shift 2;;
    --extra)     EXTRA_FLAGS=$2; shift 2;;
    --budget)    BUDGET=$2; shift 2;;
    --max-steps) MAX_STEPS=$2; shift 2;;
    --max-tokens) MAX_TOKENS=$2; shift 2;;
    --bin)       BIN=$2; shift 2;;
    --smoke)     SMOKE=1; shift;;
    -h|--help)  sed -n '2,20p' $0; exit 0;;
    *) print -u2 "unknown arg: $1"; exit 2;;
  esac
done

# --- pricing per million tokens: "input cache_write cache_read output" (docs/BENCHMARKS.md §2) ---
typeset -A PRICING
PRICING[gemini-3-flash-preview]="0.50 0.50 0.05 3.00"
PRICING[grok-4.1-fast]="0.20 0.20 0.05 0.50"
PRICING[grok-4]="3.00 3.00 0.75 15.00"
PRICING[claude-haiku-4-5]="1.00 1.25 0.10 5.00"
PRICING[claude-sonnet-4-6]="3.00 3.75 0.30 15.00"
PRICING[claude-opus-4-8]="5.00 6.25 0.50 25.00"
price=${PRICING[$MODEL]:-}
[[ -z $price ]] && print -u2 "warning: no pricing for '$MODEL' — cost column will be blank (add it to PRICING in $0)."

# --- build the binary once (release, for speed) unless one was supplied ---
if [[ -z $BIN ]]; then
  print -u2 "building lavoisier (release)…"
  ( cd $REPO_ROOT && cargo build --release -p lvz-cli ) >&2 || { print -u2 "build failed"; exit 1; }
  BIN=$REPO_ROOT/target/release/lavoisier
fi
BIN=${BIN:A}   # absolute — the runner cd's into each repo before invoking it
[[ -x $BIN ]] || { print -u2 "binary not found/executable: $BIN"; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
RESULTS=$SCRIPT_DIR/results/$STAMP
REPOS=$SCRIPT_DIR/repos
mkdir -p $RESULTS $REPOS
SUMMARY=$RESULTS/summary.tsv
print "task\tsuccess\tin\tout\tcache_read\tcache_creation\tround_trips\tcost_usd" > $SUMMARY

typeset -F total_cost=0
pass=0 count=0

# Parse the last `[telemetry]` line of a log into the global token vars + success.
parse_telemetry() {
  local log=$1 tline
  # Not anchored to ^: the agent's final answer often lacks a trailing newline, so the stderr
  # telemetry line can be concatenated onto it (e.g. "done[telemetry] …").
  tline=$(grep '\[telemetry\]' $log 2>/dev/null | tail -1)
  T_IN=$(print -r -- "$tline"  | sed -nE 's/.*[ (]in=([0-9]+).*/\1/p');         : ${T_IN:=0}
  T_OUT=$(print -r -- "$tline" | sed -nE 's/.* out=([0-9]+).*/\1/p');           : ${T_OUT:=0}
  T_CR=$(print -r -- "$tline"  | sed -nE 's/.* cache_read=([0-9]+).*/\1/p');     : ${T_CR:=0}
  T_CW=$(print -r -- "$tline"  | sed -nE 's/.* cache_creation=([0-9]+).*/\1/p'); : ${T_CW:=0}
  T_RT=$(print -r -- "$tline"  | sed -nE 's/.* round_trips=([0-9]+).*/\1/p');    : ${T_RT:=0}
  T_OK=$(print -r -- "$tline"  | sed -nE 's/.* success=(true|false).*/\1/p');    : ${T_OK:=unknown}
}

# Compute USD cost from the parsed tokens + the model price; appends to total_cost.
cost_usd() {
  [[ -z $price ]] && { print ""; return; }
  local pi pcw pcr po; read pi pcw pcr po <<< "$price"
  # Just print the cost — `total_cost` is accumulated by the caller, since this runs in `$(…)`
  # (a subshell), where any mutation here would be lost.
  awk -v i=$T_IN -v o=$T_OUT -v cr=$T_CR -v cw=$T_CW -v pi=$pi -v po=$po -v pcr=$pcr -v pcw=$pcw \
    'BEGIN{ printf "%.4f", (i*pi + o*po + cr*pcr + cw*pcw)/1000000 }'
}

run_one() {
  local id=$1 repo=$2 verify=$3 skeleton=$4 instruction=$5
  local log=$RESULTS/$id.log
  ( cd $repo
    "$BIN" --agent --provider $PROVIDER --model $MODEL --thinking $THINKING \
      --telemetry --repo-skeleton $skeleton --budget $BUDGET --max-steps $MAX_STEPS \
      --max-tokens $MAX_TOKENS --verify-cmd "$verify" ${=EXTRA_FLAGS} "$instruction"
  ) > $log 2>&1
  parse_telemetry $log
  local c=$(cost_usd)
  [[ -n $c ]] && total_cost=$(( total_cost + c ))
  print "$id\t$T_OK\t$T_IN\t$T_OUT\t$T_CR\t$T_CW\t$T_RT\t$c" >> $SUMMARY
  [[ $T_OK == true ]] && (( pass++ ))
  (( count++ ))
  print -u2 "  → success=$T_OK  cost=\$$c  (in=$T_IN out=$T_OUT cache_read=$T_CR cache_creation=$T_CW rt=$T_RT)"
}

# --- smoke mode: a throwaway repo + trivial task, to validate the whole pipeline cheaply ---
if (( SMOKE )); then
  smoke=$(mktemp -d)
  ( cd $smoke && git init -q && print "fn main() {}" > main.rs && git add -A && git -c user.email=b@b -c user.name=b commit -qm init )
  print -u2 "=== smoke (throwaway repo $smoke) ==="
  run_one "00_smoke" $smoke "true" 800 "Use the shell tool to run 'echo ok', then reply with the single word done."
  rm -rf $smoke
  print -u2 "\npassed: $pass/$count   total cost: \$$(printf '%.4f' $total_cost)   results: $RESULTS"
  column -t -s $'\t' $SUMMARY >&2
  exit 0
fi

# Robust clone for huge repos: shallow + single-branch over HTTP/1.1, with retries. macOS system
# git's LibreSSL corrupts large HTTP/2 transfers ("bad decrypt" / early EOF) and the blob:none
# filter's on-demand blob fetches make it worse, so we pull the full tree at the tip in one shot.
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

# --- the real suite ---
for f in $SCRIPT_DIR/tasks/*.task(N); do
  id=${f:t:r}
  num=${id%%_*}
  if [[ -n $TASK_FILTER && ",$TASK_FILTER," != *",${num#0},"* && ",$TASK_FILTER," != *",$num,"* ]]; then
    continue
  fi

  unset REPO_URL REPO_DIR REF SETUP VERIFY SKELETON
  while IFS= read -r line; do
    [[ $line == '---INSTRUCTION---' ]] && break
    [[ -z $line || $line == \#* ]] && continue
    eval "$line"
  done < $f
  : ${SKELETON:=1500}
  instruction=$(awk 'p; /^---INSTRUCTION---$/{p=1}' $f)
  repo=$REPOS/$REPO_DIR

  print -u2 "=== $id  ($REPO_DIR @ ${REF}) ==="
  if ! git -C $repo rev-parse HEAD >/dev/null 2>&1; then   # missing or partial → (re)clone
    print -u2 "  cloning $REPO_URL (shallow)…"
    clone_repo $REPO_URL $repo || { print -u2 "  clone failed after retries; skipping. Fix: 'brew install git' (OpenSSL), or pre-clone into $repo"; continue; }
  fi
  ( cd $repo
    git checkout -q $REF 2>/dev/null || print -u2 "  (ref '$REF' checkout failed; using current HEAD)"
    git reset -q --hard
    git clean -qfd
  )
  if [[ -n ${SETUP:-} ]]; then
    print -u2 "  setup…"; ( cd $repo; eval "$SETUP" ) >&2 || print -u2 "  setup failed (continuing; verify may not run)"
  fi

  run_one "$id" "$repo" "$VERIFY" "$SKELETON" "$instruction"
done

print -u2 "\n==== SUMMARY  (model=$MODEL provider=$PROVIDER thinking=$THINKING) ===="
column -t -s $'\t' $SUMMARY >&2
print -u2 "\npassed: $pass/$count   total cost: \$$(printf '%.4f' $total_cost)"
print -u2 "Dirac reference (gemini-3-flash-preview): 8/8, \$1.48 total (\$0.185/task)."
print -u2 "results + per-task logs: $RESULTS"
