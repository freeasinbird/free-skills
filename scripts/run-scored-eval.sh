#!/usr/bin/env bash
# Score a skill by running its scored eval cases with a real agent, several
# times each in fresh, isolated sessions, and grading each run by program.
#
# Usage:
#   run-scored-eval.sh --eval-dir DIR --skill-dir DIR --agent claude --model ID
#                      [--repeats N] [--split climb|held-out|all] [--out DIR]
#                      [--jobs N]
#
#   --eval-dir   A skill's evals directory: evals.json plus scored/<id>-<name>/
#                case directories, each with executable `setup` and `grade`,
#                and an optional scored/held-out list of case directory names.
#   --skill-dir  The candidate skill directory. Each run reads its own copy.
#   --agent      The agent CLI adapter. Only `claude` (Claude Code) exists.
#   --model      The model id passed to the agent CLI.
#   --repeats    Runs per case (default 3, hill-climb's minimum).
#   --split      climb (default) skips held-out cases, held-out runs only
#                them, all runs both.
#   --out        Where run directories, transcripts, and the summary go
#                (default: a new temporary directory). Keep it outside any
#                repository.
#   --jobs       Runs in parallel (default 1).
#
# Case contract: `setup <fixture-dir>` builds the fixture; when it leaves a
# <fixture-dir>/bin, that directory leads the agent's PATH. The agent starts
# in <fixture-dir> with the case's evals.json prompt, `<fixture-repo>`
# replaced by <fixture-dir>/repo, behind "Read <skill-copy>/SKILL.md and follow
# it." Then `grade <fixture-dir> <final-message-file>` exits 0 for a pass and
# prints one line per failed assertion.
#
# Isolation: every setup, agent, and grade runs in an emptied environment with
# a fresh TMPDIR, an empty GH_CONFIG_DIR, a dummy GH_TOKEN, and a PATH of the
# case's bin, links to this runner's bash, git, and jq, and the system
# directories. Setup and grade also get a fresh HOME. The agent keeps the real
# HOME and CLAUDE_CONFIG_DIR, because Claude Code finds its login through them
# (ANTHROPIC_API_KEY passes through when set). It runs `claude -p` with
# `--setting-sources ""`, which loads no settings and no user or project
# CLAUDE.md, `--disable-slash-commands`, which hides installed skills, and
# `--strict-mcp-config`, which loads no MCP servers, with auto memory off.
# Permission checks stay on: `--allowedTools` pre-approves only the file and
# shell tools. Each run is capped at $10 and 20 minutes.
#
# Output: one line per case (passes out of runs), one per repeat (its pass
# rate), the spread, cost, and time, then a final parseable line:
#   score=<mean> band=<max-min> runs=<n> cost_usd=<sum> check=<sha256>
# The check hash covers this runner and every file under --eval-dir, by path
# relative to each, so a frozen copy elsewhere hashes the same.
#
# Exit codes: 0 every run completed (whatever the score), 3 a setup or agent
# run failed to complete (the score line still prints, counting each such run
# as a failure, so don't use it), 64 usage, 69 a required capability is
# missing. A grader that crashes counts as a failed run, not an error.
set -u

RUNNER="$0"
usage() { sed -n '5,8p' "$RUNNER" | sed 's/^# \{0,1\}//' >&2; exit 64; }
die64() { echo "run-scored-eval.sh: $1" >&2; usage; }

EVAL_DIR="" SKILL_DIR="" AGENT="" MODEL="" REPEATS=3 SPLIT=climb OUT="" JOBS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --eval-dir|--skill-dir|--agent|--model|--repeats|--split|--out|--jobs)
      [ $# -ge 2 ] && [ -n "$2" ] || die64 "$1 needs a value"
      case "$1" in
        --eval-dir) EVAL_DIR="$2" ;;
        --skill-dir) SKILL_DIR="$2" ;;
        --agent) AGENT="$2" ;;
        --model) MODEL="$2" ;;
        --repeats) REPEATS="$2" ;;
        --split) SPLIT="$2" ;;
        --out) OUT="$2" ;;
        --jobs) JOBS="$2" ;;
      esac
      shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$RUNNER"; exit 0 ;;
    *) die64 "unknown argument: $1" ;;
  esac
done
[ -n "$EVAL_DIR" ] && [ -n "$SKILL_DIR" ] && [ -n "$AGENT" ] && [ -n "$MODEL" ] \
  || die64 "--eval-dir, --skill-dir, --agent, and --model are required"
case "$REPEATS" in ''|*[!0-9]*|0*) die64 "--repeats must be a positive integer" ;; esac
case "$JOBS" in ''|*[!0-9]*|0*) die64 "--jobs must be a positive integer" ;; esac
case "$SPLIT" in climb|held-out|all) ;; *) die64 "--split must be climb, held-out, or all" ;; esac

# --- platform gate ----------------------------------------------------------
missing=""
need() { missing="$missing${missing:+, }$1"; }
command -v bash >/dev/null 2>&1 || need "bash"
command -v git >/dev/null 2>&1 || need "git"
command -v jq >/dev/null 2>&1 || need "jq"
if command -v shasum >/dev/null 2>&1; then SHA="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"
else need "shasum or sha256sum"; fi
case "$AGENT" in
  claude)
    CLAUDE=$(command -v claude 2>/dev/null) || need "the claude CLI (Claude Code) on PATH, logged in" ;;
  *) need "an agent adapter for '$AGENT' (only claude is supported)" ;;
esac
if [ -n "$missing" ]; then
  echo "run-scored-eval.sh: missing required capabilities: $missing" >&2
  exit 69
fi

# --- eval directory ----------------------------------------------------------
[ -d "$EVAL_DIR" ] || die64 "not a directory: $EVAL_DIR"
[ -f "$SKILL_DIR/SKILL.md" ] || die64 "no SKILL.md in --skill-dir: $SKILL_DIR"
EVAL_DIR=$(cd "$EVAL_DIR" && pwd)
SKILL_DIR=$(cd "$SKILL_DIR" && pwd)
EVALS="$EVAL_DIR/evals.json"
jq -e '.evals | type == "array"' "$EVALS" >/dev/null 2>&1 \
  || die64 "no readable evals.json with an evals array in $EVAL_DIR"

# held_out_list: case names from scored/held-out, comments and blank lines
# dropped and surrounding whitespace trimmed.
held_out_list() {
  [ ! -f "$EVAL_DIR/scored/held-out" ] \
    || awk '!/^[[:space:]]*#/ && NF { print $1 }' "$EVAL_DIR/scored/held-out"
}
held_out() { held_out_list | grep -qxF "$1"; }
CASES=""
for d in $(ls "$EVAL_DIR/scored" 2>/dev/null | grep -E '^[0-9]+-' | sort -n); do
  id="${d%%-*}" name="${d#*-}"
  [ -x "$EVAL_DIR/scored/$d/setup" ] && [ -x "$EVAL_DIR/scored/$d/grade" ] \
    || die64 "case $d lacks an executable setup or grade"
  [ "$(jq -r --argjson id "$id" '.evals[] | select(.id == $id) | .eval_name' "$EVALS")" = "$name" ] \
    || die64 "case $d has no evals.json entry with id $id and eval_name $name"
  if held_out "$d"; then h=1; else h=0; fi
  case "$SPLIT:$h" in climb:0|held-out:1|all:*) CASES="$CASES $d" ;; esac
done
if [ -f "$EVAL_DIR/scored/held-out" ]; then
  for d in $(held_out_list); do
    [ -d "$EVAL_DIR/scored/$d" ] || die64 "held-out lists a missing case: $d"
  done
fi
[ -n "$CASES" ] || die64 "no scored cases in the $SPLIT split under $EVAL_DIR/scored"

# --- check hash ----------------------------------------------------------------
# A manifest of "<sha> <relative path>" lines, the runner first, hashed once.
CHECK=$(
  {
    printf '%s  run-scored-eval.sh\n' "$($SHA <"$RUNNER" | cut -d' ' -f1)"
    (cd "$EVAL_DIR" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$($SHA <"$f" | cut -d' ' -f1)" "${f#./}"
    done)
  } | $SHA | cut -d' ' -f1
)

# --- runs ---------------------------------------------------------------------
if [ -z "$OUT" ]; then
  OUT=$(mktemp -d "${TMPDIR:-/tmp}/scored-eval.XXXXXX")
else
  mkdir -p "$OUT"
fi
OUT=$(cd "$OUT" && pwd)
echo "run-scored-eval.sh: writing runs to $OUT" >&2
TOOLBIN="$OUT/toolbin"
mkdir -p "$TOOLBIN"
for t in bash git jq; do ln -sf "$(command -v "$t")" "$TOOLBIN/$t"; done
SYSPATH="$TOOLBIN:/usr/bin:/bin:/usr/sbin:/sbin"
SKILL_NAME=$(basename "$SKILL_DIR")
# SCORED_EVAL_RUN_LIMIT shortens the per-run limit for the runner's own tests.
RUN_LIMIT="${SCORED_EVAL_RUN_LIMIT:-1200}"
RUN_USER="${USER:-eval}"
REAL_HOME="$HOME"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
API_KEY="${ANTHROPIC_API_KEY:-}"
AGENT_TOOLS="Bash Read Edit Write Glob Grep"

# isolate <run-dir> <path> <home>: replace this subshell's whole environment
# with the sandbox's.
isolate() {
  local v
  for v in $(compgen -e); do unset "$v" 2>/dev/null; done
  # Exported functions are not variables; un-export them too, so a wrapper
  # named git or gh can't shadow the sandbox's tools.
  for v in $(compgen -A function); do export -n -f "$v" 2>/dev/null; done
  export HOME="$3" USER="$RUN_USER" LOGNAME="$RUN_USER" TERM=dumb \
    LANG=en_US.UTF-8 SHELL=/bin/bash PATH="$2" TMPDIR="$1/tmp" \
    GH_CONFIG_DIR="$1/gh-config" GH_TOKEN=scored-eval-dummy-token \
    GH_PROMPT_DISABLED=1 GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1
}

run_one() { # run_one <repeat> <case>: leaves status, cost, seconds in the run dir
  local r="$1" c="$2" run fix prompt path start rc pid watchdog
  run="$OUT/runs/r$r/$c"
  fix="$run/fixture"
  mkdir -p "$fix" "$run/home" "$run/tmp" "$run/gh-config" "$run/skill"
  if ! (isolate "$run" "$SYSPATH" "$run/home"; exec "$EVAL_DIR/scored/$c/setup" "$fix") \
      >"$run/setup.log" 2>&1; then
    echo error >"$run/status"; echo "setup failed" >"$run/grade.txt"; return
  fi
  cp -R "$SKILL_DIR" "$run/skill/$SKILL_NAME"
  prompt=$(jq -r --argjson id "${c%%-*}" '.evals[] | select(.id == $id) | .prompt' "$EVALS")
  prompt="Read $run/skill/$SKILL_NAME/SKILL.md and follow it. ${prompt//<fixture-repo>/$fix/repo}"
  printf '%s\n' "$prompt" >"$run/prompt.txt"
  path="$SYSPATH"
  [ ! -d "$fix/bin" ] || path="$fix/bin:$SYSPATH"
  start=$(date +%s)
  # The subshell execs the agent, so $! is the agent and the watchdog can stop it.
  # Exporting the key here, not on a command line, keeps it out of process
  # listings.
  (cd "$fix" || exit 1; isolate "$run" "$path" "$REAL_HOME"
    [ -z "$CONFIG_DIR" ] || export CLAUDE_CONFIG_DIR="$CONFIG_DIR"
    [ -z "$API_KEY" ] || export ANTHROPIC_API_KEY="$API_KEY"
    # Auto memory would let a run read an earlier run's notes when an --out
    # path is reused, and leaves a directory in the login's config per run.
    export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
    exec "$CLAUDE" -p "$prompt" --output-format stream-json --verbose \
      --no-session-persistence \
      --model "$MODEL" --setting-sources "" --disable-slash-commands \
      --strict-mcp-config --allowedTools "$AGENT_TOOLS" \
      --add-dir "$run/skill" --max-budget-usd 10) \
    </dev/null >"$run/transcript.jsonl" 2>"$run/agent.stderr" &
  pid=$!
  # The watchdog owns its sleep and kills it when stopped, and holds no
  # output, so a caller piping this runner's output never waits on it. On
  # timeout it stops the agent's children first, then the agent.
  (
    sleep "$RUN_LIMIT" & s=$!
    trap 'kill "$s" 2>/dev/null; exit 0' TERM
    wait "$s"
    pkill -TERM -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid"; rc=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  echo $(( $(date +%s) - start )) >"$run/seconds"
  # The transcript keeps every tool call, so a reader can see which files a
  # run read; its last result event is the run's outcome.
  jq -c 'select(type == "object" and .type == "result")' "$run/transcript.jsonl" \
    2>/dev/null | tail -n 1 >"$run/agent.json"
  if ! jq -e 'type == "object" and has("result")' "$run/agent.json" >/dev/null 2>&1; then
    echo error >"$run/status"; echo "agent exited $rc without a JSON result" >"$run/grade.txt"
    echo 0 >"$run/cost"; return
  fi
  jq -r '.total_cost_usd // 0' "$run/agent.json" >"$run/cost"
  jq -r '.result // ""' "$run/agent.json" >"$run/message.txt"
  if (isolate "$run" "$SYSPATH" "$run/home"; exec "$EVAL_DIR/scored/$c/grade" "$fix" "$run/message.txt") \
      >"$run/grade.txt" 2>&1; then
    echo pass >"$run/status"
  else
    echo fail >"$run/status"
  fi
}

pids=""
started=$(date +%s)
for r in $(seq 1 "$REPEATS"); do
  for c in $CASES; do
    run_one "$r" "$c" &
    pids="$pids $!"
    set -- $pids
    if [ $# -ge "$JOBS" ]; then wait "$1"; shift; pids="$*"; fi
  done
done
wait
elapsed=$(( $(date +%s) - started ))

# --- summary ------------------------------------------------------------------
{
  errors=0 runs=0 cost=0 seconds=0 rates=""
  for c in $CASES; do
    p=0
    for r in $(seq 1 "$REPEATS"); do
      s=$(cat "$OUT/runs/r$r/$c/status" 2>/dev/null || echo error)
      [ "$s" != pass ] || p=$((p + 1))
      [ "$s" != error ] || errors=$((errors + 1))
    done
    echo "case $c $p/$REPEATS"
  done
  for r in $(seq 1 "$REPEATS"); do
    p=0 n=0
    for c in $CASES; do
      n=$((n + 1)) runs=$((runs + 1))
      [ "$(cat "$OUT/runs/r$r/$c/status" 2>/dev/null)" != pass ] || p=$((p + 1))
      cost=$(awk -v a="$cost" -v b="$(cat "$OUT/runs/r$r/$c/cost" 2>/dev/null || echo 0)" 'BEGIN { print a + b }')
      seconds=$((seconds + $(cat "$OUT/runs/r$r/$c/seconds" 2>/dev/null || echo 0)))
    done
    rate=$(awk -v p="$p" -v n="$n" 'BEGIN { printf "%.3f", p / n }')
    rates="$rates $rate"
    echo "repeat $r $rate"
  done
  stats=$(printf '%s\n' $rates | awk '
    NR == 1 { min = $1; max = $1 }
    { sum += $1; if ($1 < min) min = $1; if ($1 > max) max = $1 }
    END { printf "%.3f %.3f %.3f %.3f", sum / NR, min, max, max - min }')
  set -- $stats
  echo "mean=$1 min=$2 max=$3 band=$4"
  echo "cost_usd=$(printf '%.2f' "$cost") agent_seconds=$seconds elapsed_seconds=$elapsed errors=$errors"
  echo "score=$1 band=$4 runs=$runs cost_usd=$(printf '%.2f' "$cost") check=$CHECK"
} | tee "$OUT/summary.txt"

errors=$(sed -n 's/.* errors=\([0-9]*\)$/\1/p' "$OUT/summary.txt")
if [ "${errors:-0}" -gt 0 ]; then
  echo "run-scored-eval.sh: $errors run(s) did not complete; see grade.txt under $OUT/runs" >&2
  exit 3
fi
exit 0
