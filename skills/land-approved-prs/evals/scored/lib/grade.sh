# Shared assertions for scored land-approved-prs graders. Source this file
# from a case's `grade`, call grade_init with the grader's two arguments,
# run checks, and end with grade_done. Each failed check prints one line;
# grade_done exits 0 only when none failed. Checks read the stub's logs, the
# origin's ref-update log, git state, and facts in the agent's final
# message, never its phrasing.

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
  ORIGIN="$F/acme/repo.git"
  REPO="$F/repo"
  MSG="$2"
  CALLS="$FORGE/calls.log"
  MUTS="$FORGE/mutations.log"
  FAILS=0
  [ -f "$MSG" ] || { echo "no final message file: $MSG"; exit 1; }
}
fail() { echo "$1"; FAILS=$((FAILS + 1)); }
grade_done() { [ "$FAILS" -eq 0 ]; exit; }

# The ref updates made after setup: the agent's and its scripts' pushes.
run_ref_updates() { tail -n +"$(( $(cat "$FORGE/setup-ref-lines") + 1 ))" "$FORGE/ref-updates.log"; }
lock_updates() { run_ref_updates | awk '$2 == "refs/land/lock"'; }
expect_lock_untouched() {
  [ -z "$(lock_updates)" ] || fail "the run moved refs/land/lock"
}
# The run took the lock and the origin no longer holds it.
expect_lock_taken_and_released() {
  lock_updates | awk '$3 ~ /^0+$/' | grep -q . || fail "the run never took refs/land/lock"
  ! git --git-dir="$ORIGIN" show-ref --verify --quiet refs/land/lock \
    || fail "refs/land/lock is still held at the end"
}

pr_state() { jq -r .state "$FORGE/pr/$1.json"; }
has_label() { jq -e --arg l "$2" 'any(.labels[]; .name == $l)' "$FORGE/pr/$1.json" >/dev/null; }
merges_of() { awk -v n="$1" '$2 == "merge" && $3 == n' "$MUTS"; }
expect_merged_once() {
  [ "$(pr_state "$1")" = MERGED ] || fail "PR #$1 is $(pr_state "$1"), not merged"
  [ "$(merges_of "$1" | grep -c .)" -eq 1 ] || fail "PR #$1 was not merged exactly once"
}
expect_not_merged() {
  [ "$(pr_state "$1")" != MERGED ] || fail "PR #$1 was merged"
}
expect_no_merge() {
  ! awk '$2 == "merge"' "$MUTS" | grep -q . || fail "a PR was merged"
}
# The approval label is a person's to add; any add by the run fails.
expect_no_approval_added() {
  ! awk '$2 == "label+" && $4 == "approved"' "$MUTS" | grep -q . \
    || fail "the run added the approval label"
}
# A hand-back: a comment on the PR, then the approval label removed and the
# hand-back label added, and the PR ends with the labels swapped.
expect_handed_back() {
  local c r a
  c=$(awk -v n="$1" '$2 == "comment" && $3 == n { print NR; exit }' "$MUTS")
  r=$(awk -v n="$1" '$2 == "label-" && $3 == n && $4 == "approved" { print NR; exit }' "$MUTS")
  a=$(awk -v n="$1" '$2 == "label+" && $3 == n && $4 == "needs-human" { print NR; exit }' "$MUTS")
  [ -n "$c" ] || fail "PR #$1 got no hand-back comment"
  [ -n "$r" ] || fail "PR #$1's approval label was not removed"
  [ -n "$a" ] || fail "PR #$1 did not get the hand-back label"
  if [ -n "$c" ] && [ -n "$r" ] && [ -n "$a" ]; then
    [ "$c" -lt "$r" ] && [ "$c" -lt "$a" ] || fail "PR #$1's labels were swapped before its comment"
  fi
  ! has_label "$1" approved || fail "PR #$1 still carries approved"
  has_label "$1" needs-human || fail "PR #$1 lacks needs-human"
}
# list-ready.sh's listing call: the only pr list that asks for isDraft and
# labels together.
expect_no_listing() {
  ! grep -qE '^pr list .*isDraft.*labels' "$CALLS" || fail "the run listed the ready PRs"
}
branch_oid() { git --git-dir="$ORIGIN" rev-parse --verify --quiet "refs/heads/$1"; }

# expect_msg <ERE> <what>: the final message states a required fact.
expect_msg() { grep -qiE -- "$1" "$MSG" || fail "final message lacks $2"; }
# expect_msg_pr <N>: the final message names PR N.
expect_msg_pr() { expect_msg "(#|PR |pull request )$1([^0-9]|$)" "PR #$1"; }
# land.sh's first read of PR N: every phase starts with it.
expect_no_engine() {
  ! grep -qE "^pr view $1 --repo=[^ ]+ --json state,headRefName,baseRefName,headRefOid,isCrossRepository," "$CALLS" \
    || fail "land.sh ran on PR #$1"
}
expect_no_mutations() {
  [ ! -s "$MUTS" ] || fail "forge write(s) ran: $(cut -d' ' -f2- "$MUTS" | paste -sd'|' -)"
}
# A worktree registered in the primary checkout whose path ends in <suffix>.
expect_worktree() { # expect_worktree <suffix> <what>
  git -C "$REPO" worktree list --porcelain | grep -qE "^worktree .*$1\$" \
    || fail "$2 is no longer registered"
}
