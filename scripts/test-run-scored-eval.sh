#!/usr/bin/env bash
# Offline tests for scripts/run-scored-eval.sh. A fake `claude` first on PATH
# records its arguments and environment and prints a scripted JSON result, so
# no model is called. A toy eval directory has a passing case, a failing case,
# and a held-out case; the fake fails the passing case on its second repeat,
# which gives the spread a known value.
#
# Usage: test-run-scored-eval.sh
# Exit codes: 0 all passed, 1 a check failed.
set -u
cd "$(dirname "$0")/.." || exit 1
RUNNER="$PWD/scripts/run-scored-eval.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $CASE: $1" >&2; }

# --- toy eval, skill, and fake agent -------------------------------------------
EVAL="$TMP/eval" SKILL="$TMP/skill/toy" FAKE="$TMP/fakebin"
mkdir -p "$EVAL/scored" "$SKILL" "$FAKE"
echo "# Toy skill" >"$SKILL/SKILL.md"
jq -n '{skill_name:"toy", evals:[
  {id:1, eval_name:"good", prompt:"Tidy <fixture-repo>.", expected_output:"", files:[], expectations:[]},
  {id:2, eval_name:"bad", prompt:"Tidy <fixture-repo>.", expected_output:"", files:[], expectations:[]},
  {id:3, eval_name:"held", prompt:"Tidy <fixture-repo>.", expected_output:"", files:[], expectations:[]}]}' \
  >"$EVAL/evals.json"
for c in 1-good 2-bad 3-held; do
  mkdir -p "$EVAL/scored/$c"
  printf '#!/usr/bin/env bash\nmkdir -p "$1/repo" "$1/bin"\nenv >"$1/setup-env"\n' >"$EVAL/scored/$c/setup"
  printf '#!/usr/bin/env bash\nenv >"$1/grade-env"\ngrep -q done "$2" || { echo "no done"; exit 1; }\n' \
    >"$EVAL/scored/$c/grade"
done
printf '#!/usr/bin/env bash\necho "always fails"; exit 1\n' >"$EVAL/scored/2-bad/grade"
chmod +x "$EVAL"/scored/*/setup "$EVAL"/scored/*/grade
printf '# never in a climb\n3-held\n' >"$EVAL/scored/held-out"

cat >"$FAKE/claude" <<'FAKE'
#!/usr/bin/env bash
# Records how it was started, then answers like
# `claude -p --output-format stream-json --verbose`: events, then a result.
printf '%s\n' "$@" >agent-args
env >agent-env
case "$PWD" in */r2/1-good/*) result="not finished" ;; *) result="done" ;; esac
# A hung agent with a child process, for the watchdog checks.
case "$PWD" in */1-good/*) [ ! -f "$PWD/../../../../hang" ] || { sleep 300 & sleep 300; } ;; esac
jq -nc '{type:"system", subtype:"init"}'
jq -nc '{type:"assistant", message:{content:[{type:"text", text:"working"}]}}'
jq -nc --arg r "$result" '{type:"result", result:$r, total_cost_usd:0.25}'
FAKE
chmod +x "$FAKE/claude"

run() { # run <args...>: sets RC, OUT, ERR
  OUT="$TMP/out.txt" ERR="$TMP/err.txt"
  PATH="$FAKE:$PATH" ANTHROPIC_API_KEY=test-key SECRET_SENTINEL=leak \
    SCORED_EVAL_STATE_DIR=/caller/leaked/state \
    CLAUDE_CONFIG_DIR="$TMP/claude-config" "$RUNNER" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
base_args() { echo --eval-dir "$EVAL" --skill-dir "$SKILL" --agent claude --model test-model; }
want_rc() { [ "$RC" -eq "$1" ] && ok || bad "exit $RC, want $1: $(cat "$ERR")"; }
want_out() { grep -qE -- "$1" "$OUT" && ok || bad "stdout lacks /$1/: $(cat "$OUT")"; }
want_no_out() { grep -qE -- "$1" "$OUT" && bad "stdout has /$1/" || ok; }
want_err() { grep -qE -- "$1" "$ERR" && ok || bad "stderr lacks /$1/: $(cat "$ERR")"; }
score_line() { tail -n 1 "$OUT"; }

# --- usage and gate --------------------------------------------------------------
CASE="usage: missing --model"
run --eval-dir "$EVAL" --skill-dir "$SKILL" --agent claude
want_rc 64
CASE="usage: bad split"
run $(base_args) --split some
want_rc 64
CASE="usage: zero repeats"
run $(base_args) --repeats 0
want_rc 64

CASE="gate: no claude on PATH"
nogate="$TMP/nogate"
mkdir -p "$nogate"
for t in bash git jq shasum; do ln -s "$(command -v "$t")" "$nogate/$t"; done
OUT="$TMP/out.txt" ERR="$TMP/err.txt"
PATH="$nogate:/usr/bin:/bin" ANTHROPIC_API_KEY=test-key "$RUNNER" $(base_args) >"$OUT" 2>"$ERR"
RC=$?
want_rc 69; want_err "claude CLI"
CASE="gate: unsupported agent"
run --eval-dir "$EVAL" --skill-dir "$SKILL" --agent codex --model m
want_rc 69; want_err "adapter for 'codex'"

# --- aggregation and held-out handling --------------------------------------------
CASE="climb split"
run $(base_args) --repeats 2 --out "$TMP/climb"
want_rc 0
want_out '^case 1-good 1/2$'; want_out '^case 2-bad 0/2$'; want_no_out '3-held'
want_out '^repeat 1 0\.500$'; want_out '^repeat 2 0\.000$'
want_out '^mean=0\.250 min=0\.000 max=0\.500 band=0\.500$'
score_line | grep -qE '^score=0\.250 band=0\.500 runs=4 cost_usd=1\.00 check=[0-9a-f]{64}$' \
  && ok || bad "score line: $(score_line)"
CHECK=$(score_line | sed 's/.*check=//')
[ -f "$TMP/climb/summary.txt" ] && ok || bad "no summary.txt"

CASE="held-out split"
run $(base_args) --split held-out --repeats 1
want_rc 0; want_out '^case 3-held 1/1$'; want_no_out '1-good'
CASE="all split"
run $(base_args) --split all --repeats 1
want_rc 0; want_out '^case 1-good'; want_out '^case 3-held'

CASE="parallel jobs"
run $(base_args) --repeats 2 --jobs 3
want_rc 0
score_line | grep -q '^score=0\.250 band=0\.500 runs=4 cost_usd=1\.00 ' && ok \
  || bad "score line: $(score_line)"

# --- check hash ---------------------------------------------------------------------
CASE="hash is stable and location-independent"
[ "$(score_line | sed 's/.*check=//')" = "$CHECK" ] && ok || bad "hash changed between runs"
cp -R "$EVAL" "$TMP/frozen"
run --eval-dir "$TMP/frozen" --skill-dir "$SKILL" --agent claude --model test-model --repeats 1
[ "$(score_line | sed 's/.*check=//')" = "$CHECK" ] && ok || bad "a frozen copy hashes differently"
CASE="hash follows eval content"
echo "# changed" >>"$TMP/frozen/scored/1-good/grade"
run --eval-dir "$TMP/frozen" --skill-dir "$SKILL" --agent claude --model test-model --repeats 1
[ "$(score_line | sed 's/.*check=//')" != "$CHECK" ] && ok || bad "an edited grade kept the hash"

# --- isolation -------------------------------------------------------------------------
CASE="agent isolation"
r="$TMP/climb/runs/r1/1-good"
envf="$r/fixture/agent-env" argf="$r/fixture/agent-args"
grep -qx "HOME=$HOME" "$envf" && ok || bad "HOME is not the login's home"
grep -qx "CLAUDE_CONFIG_DIR=$TMP/claude-config" "$envf" && ok || bad "CLAUDE_CONFIG_DIR was not passed"
grep -qx "HOME=$r/home" "$r/fixture/setup-env" && ok || bad "setup's HOME is not the run's home"
grep -qx "GH_TOKEN=scored-eval-dummy-token" "$envf" && ok || bad "GH_TOKEN is not the dummy"
grep -qx "GH_CONFIG_DIR=$r/gh-config" "$envf" && ok || bad "GH_CONFIG_DIR is not the run's"
[ -z "$(ls -A "$r/gh-config")" ] && ok || bad "GH_CONFIG_DIR is not empty"
grep -q "^PATH=$r/fixture/bin:" "$envf" && ok || bad "the case bin does not lead PATH"
grep -qx "ANTHROPIC_API_KEY=test-key" "$envf" && ok || bad "the API key was not passed"
grep -qx "CLAUDE_CODE_DISABLE_AUTO_MEMORY=1" "$envf" && ok || bad "auto memory is not off"
grep -q SECRET_SENTINEL "$envf" && bad "the runner's environment leaked" || ok
grep -q '^SCORED_EVAL_STATE_DIR=' "$envf" && bad "SCORED_EVAL_STATE_DIR leaked to the agent" || ok
sdir="$TMP/climb/state/r1/1-good"
grep -qx "SCORED_EVAL_STATE_DIR=$sdir" "$r/fixture/setup-env" && ok \
  || bad "setup did not receive the expected SCORED_EVAL_STATE_DIR"
grep -qx "SCORED_EVAL_STATE_DIR=$sdir" "$r/fixture/grade-env" && ok \
  || bad "grade did not receive the same SCORED_EVAL_STATE_DIR"
s_real=$(cd "$sdir" && pwd -P)
r_real=$(cd "$r" && pwd -P)
f_real=$(cd "$r/fixture" && pwd -P)
case "$s_real/" in
  "$f_real/"*|"$r_real/"*) bad "state dir sits inside fixture or its parent: $s_real" ;;
  *) ok ;;
esac
case "$r_real/" in
  "$s_real/"*) bad "state dir contains fixture parent: $s_real" ;;
  *) ok ;;
esac
grep -q test-key "$argf" && bad "the API key is on the command line" || ok
grep -q dangerously "$argf" && bad "permission checks were bypassed" || ok
[ "$(wc -l <"$r/transcript.jsonl")" -eq 3 ] && ok || bad "the transcript was not kept whole"
for a in -p --no-session-persistence test-model stream-json --verbose --disable-slash-commands \
    --strict-mcp-config "Bash Read Edit Write Glob Grep"; do
  grep -qx -- "$a" "$argf" && ok || bad "agent args lack $a"
done
grep -qx -- "--setting-sources" "$argf" && [ "$(grep -A1 -x -- --setting-sources "$argf" | tail -n 1)" = "" ] \
  && ok || bad "agent args lack an empty --setting-sources"
grep -qx "Read $r/skill/toy/SKILL.md and follow it. Tidy $r/fixture/repo." "$argf" \
  && ok || bad "prompt: $(sed -n 2p "$argf")"
[ -f "$r/skill/toy/SKILL.md" ] && ok || bad "the skill was not copied into the run"

CASE="state-dir bin leads PATH and takes precedence over fixture bin"
cp -R "$EVAL" "$TMP/statebin"
cat >"$TMP/statebin/scored/1-good/setup" <<'SETUP'
#!/usr/bin/env bash
mkdir -p "$1/repo" "$SCORED_EVAL_STATE_DIR/bin"
printf '#!/usr/bin/env bash\necho from-state\n' >"$SCORED_EVAL_STATE_DIR/bin/stub"
chmod +x "$SCORED_EVAL_STATE_DIR/bin/stub"
SETUP
cat >"$TMP/statebin/scored/2-bad/setup" <<'SETUP'
#!/usr/bin/env bash
mkdir -p "$1/repo" "$1/bin" "$SCORED_EVAL_STATE_DIR/bin"
printf '#!/usr/bin/env bash\necho from-fixture\n' >"$1/bin/stub"
printf '#!/usr/bin/env bash\necho from-state\n' >"$SCORED_EVAL_STATE_DIR/bin/stub"
chmod +x "$1/bin/stub" "$SCORED_EVAL_STATE_DIR/bin/stub"
SETUP
run --eval-dir "$TMP/statebin" --skill-dir "$SKILL" --agent claude --model test-model \
  --repeats 1 --out "$TMP/statebin-out"
want_rc 0
r1="$TMP/statebin-out/runs/r1/1-good"
s1="$TMP/statebin-out/state/r1/1-good"
[ ! -e "$r1/fixture/bin" ] && ok || bad "fixture/bin unexpectedly exists"
grep -q "^PATH=$s1/bin:" "$r1/fixture/agent-env" && ok \
  || bad "state-dir bin does not lead PATH when fixture/bin is absent"
grep -q "^PATH=.*$r1/fixture/bin" "$r1/fixture/agent-env" \
  && bad "absent fixture/bin appeared on PATH" || ok
grep -q '^SCORED_EVAL_STATE_DIR=' "$r1/fixture/agent-env" \
  && bad "SCORED_EVAL_STATE_DIR leaked to state-bin agent" || ok
r2="$TMP/statebin-out/runs/r1/2-bad"
s2="$TMP/statebin-out/state/r1/2-bad"
grep -q "^PATH=$s2/bin:$r2/fixture/bin:" "$r2/fixture/agent-env" && ok \
  || bad "state-dir bin does not take precedence over fixture/bin"

CASE="exported functions don't reach the agent"
leak_fn() { :; }
export -f leak_fn
run $(base_args) --repeats 1 --out "$TMP/fn"
unset -f leak_fn
grep -q leak_fn "$TMP/fn/runs/r1/1-good/fixture/agent-env" && bad "an exported function leaked" || ok

CASE="held-out names tolerate surrounding whitespace"
cp -R "$EVAL" "$TMP/spaced"
printf '  3-held  \n' >"$TMP/spaced/scored/held-out"
run --eval-dir "$TMP/spaced" --skill-dir "$SKILL" --agent claude --model test-model --repeats 1
want_rc 0; want_no_out '3-held'

# --- harness failures --------------------------------------------------------------------
CASE="setup failure is a harness error"
cp -R "$EVAL" "$TMP/broken"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/broken/scored/1-good/setup"
run --eval-dir "$TMP/broken" --skill-dir "$SKILL" --agent claude --model test-model --repeats 1
want_rc 3; want_out 'errors=1$'; want_err 'did not complete'

CASE="a finished run's watchdog never holds the output pipe"
start=$(date +%s)
OUT="$TMP/out.txt" ERR="$TMP/err.txt"
PATH="$FAKE:$PATH" SCORED_EVAL_RUN_LIMIT=60 "$RUNNER" $(base_args) --repeats 1 \
  2>"$ERR" | cat >"$OUT"
[ $(( $(date +%s) - start )) -lt 30 ] && ok || bad "the piped run took $(( $(date +%s) - start ))s"
want_out '^score='

CASE="watchdog stops a hung agent"
mkdir -p "$TMP/hang-out"
touch "$TMP/hang-out/hang"
start=$(date +%s)
OUT="$TMP/out.txt" ERR="$TMP/err.txt"
PATH="$FAKE:$PATH" SCORED_EVAL_RUN_LIMIT=2 "$RUNNER" $(base_args) --repeats 1 \
  --out "$TMP/hang-out" 2>"$ERR" | cat >"$OUT"
RC=${PIPESTATUS[0]}
[ $(( $(date +%s) - start )) -lt 20 ] && ok || bad "the piped run took $(( $(date +%s) - start ))s"
want_rc 3
[ "$(cat "$TMP/hang-out/runs/r1/1-good/status")" = error ] && ok || bad "the hung run is not an error"
pgrep -f "sleep 300" >/dev/null && bad "the hung agent's child survived" || ok

echo "test-run-scored-eval: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
