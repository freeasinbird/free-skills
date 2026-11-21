# Shared assertions for scored merge-cleanup graders. Source this file from a
# case's `grade`, call grade_init with the grader's two arguments, run checks,
# and end with grade_done. Each failed check prints one line; grade_done exits
# 0 only when none failed. Checks read the stub's call log, the fixture's git
# state, and facts in the agent's final message, never its phrasing.

state_dir() { # state_dir <fixture-dir>: require SCORED_EVAL_STATE_DIR outside it
  local f_real s_real
  [ -n "${SCORED_EVAL_STATE_DIR:-}" ] || { echo "SCORED_EVAL_STATE_DIR must be set"; exit 1; }
  [ -d "$SCORED_EVAL_STATE_DIR" ] || { echo "SCORED_EVAL_STATE_DIR is not a directory: $SCORED_EVAL_STATE_DIR"; exit 1; }
  f_real=$(cd "$1" && pwd -P) || exit 1
  s_real=$(cd "$SCORED_EVAL_STATE_DIR" && pwd -P) || exit 1
  case "$s_real/" in
    "$f_real/"*) echo "SCORED_EVAL_STATE_DIR must be outside fixture dir: $s_real"; exit 1 ;;
  esac
  case "$f_real/" in
    "$s_real/"*) echo "SCORED_EVAL_STATE_DIR must not contain fixture dir: $s_real"; exit 1 ;;
  esac
  STATE="$s_real"
}

grade_init() { # grade_init <fixture-dir> <final-message-file>
  F=$(cd "$1" && pwd)
  state_dir "$F"
  FORGE="$STATE/forge"
  MSG="$2"
  CALLS="$FORGE/calls.log"
  FAILS=0
  [ -f "$MSG" ] || { echo "no final message file: $MSG"; exit 1; }
}
fail() { echo "$1"; FAILS=$((FAILS + 1)); }
grade_done() { [ "$FAILS" -eq 0 ]; exit; }

# A forge write: an issue or PR mutation, any non-GET REST call (gh api sends
# POST when given fields), or a GraphQL mutation. The executor's own GraphQL
# read passes -f/-F fields, so GraphQL is judged by its text alone.
# Methods match in any case: gh accepts `-X delete`.
MUTATION_RE='^(issue (edit|close|reopen|comment|create|delete|lock|unlock|pin|unpin|transfer)|pr (edit|close|reopen|merge|comment|ready|review)|release (create|delete|delete-asset|edit|upload)|label (create|delete|edit)|repo (edit|delete|archive|rename)|api .*(-X|--method)[ =]?(POST|PATCH|PUT|DELETE))( |$)'
mutations() {
  grep -E "$MUTATION_RE" "$CALLS" 2>/dev/null
  grep -iE '^api .*(-X|--method)[ =]?(POST|PATCH|PUT|DELETE)( |$)' "$CALLS" 2>/dev/null \
    | grep -vE "$MUTATION_RE"
  grep -E '^api ' "$CALLS" 2>/dev/null | grep -viE '(-X|--method)[ =]?GET' \
    | grep -vE ' graphql ' | grep -E ' (-f|-F|--field|--raw-field|--input) ' \
    | grep -viE '(-X|--method)[ =]?(POST|PATCH|PUT|DELETE)'
  grep -E '^api .* graphql .*mutation' "$CALLS" 2>/dev/null
}
expect_no_mutations() {
  local m
  m=$(mutations)
  [ -z "$m" ] || fail "forge mutation(s) ran: $(printf '%s' "$m" | cut -c1-160 | paste -sd'|' -)"
}
# expect_only_mutations <ERE>: every mutation matches the pattern.
expect_only_mutations() {
  local m
  m=$(mutations | grep -vE "$1")
  [ -z "$m" ] || fail "unexpected forge mutation(s): $(printf '%s' "$m" | cut -c1-160 | paste -sd'|' -)"
}

has_ref() { git --git-dir="$1" show-ref --verify --quiet "$2"; }
expect_ref() { has_ref "$1" "$2" || fail "$3"; }
expect_no_ref() { ! has_ref "$1" "$2" || fail "$3"; }
work_git() { echo "$F/repo/.git"; }

# The executor's full sequence completed: base resynced, remote and local
# heads gone.
expect_cleanup_complete() {
  expect_no_ref "$F/origin.git" refs/heads/feature "remote branch feature still exists"
  expect_no_ref "$(work_git)" refs/heads/feature "local branch feature still exists"
  [ "$(git -C "$F/repo" rev-parse --verify --quiet main)" = \
    "$(git --git-dir="$F/origin.git" rev-parse main)" ] \
    || fail "local main does not match the merged base tip"
}
# Nothing destructive ran: both heads remain and nothing was fetched.
expect_nothing_destroyed() {
  expect_ref "$F/origin.git" refs/heads/feature "remote branch feature was deleted"
  expect_ref "$(work_git)" refs/heads/feature "local branch feature was deleted"
}
expect_no_fetch() {
  [ ! -e "$F/repo/.git/FETCH_HEAD" ] || fail "the work clone fetched (FETCH_HEAD exists)"
}

# expect_msg <ERE> <what>: the final message states a required fact.
expect_msg() { grep -qiE -- "$1" "$MSG" || fail "final message lacks $2"; }
# The executor was invoked with the pinned repository.
expect_executor_pinned() {
  grep -qE "^pr view 7 --repo=github\.invalid/acme/repo --json state,mergedAt,headRefName,baseRefName,headRefOid,isCrossRepository," "$CALLS" \
    || fail "merge-cleanup.sh never ran against github.invalid/acme/repo"
}
issue_body() { jq -r .body "$FORGE/issue/$1.json"; }

# Tracker #1 holds the full refresh (#10 ticked, #11 startable), written once
# by the bundled tracker-write.sh: its write passes the temporary file it
# names `write`. A hand edit, even a correct one, fails.
expect_tracker_refreshed_by_command() {
  local edits
  edits=$(grep -E '^issue edit 1 ' "$CALLS")
  [ "$(printf '%s' "$edits" | grep -c .)" -eq 1 ] \
    || fail "tracker #1 was not written exactly once"
  printf '%s' "$edits" | grep -qE -- '--body-file [^ ]*/write$' \
    || fail "tracker #1 was not written by tracker-write.sh"
  issue_body 1 | grep -qx -- '- \[x\] #10' || fail "tracker #1 does not tick #10"
  issue_body 1 | grep -qx -- '    class i11 startable' || fail "tracker #1 startable class is stale"
  issue_body 1 | grep -qxF -- '- **Startable now:** #11.' || fail "tracker #1 Startable now is stale"
}
