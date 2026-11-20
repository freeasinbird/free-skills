# Shared assertions for scored await-pr-review graders. Source this file
# from a case's `grade`, call grade_init with the grader's two arguments,
# run checks, and end with grade_done. Each failed check prints one line;
# grade_done exits 0 only when none failed. Checks read the stub's logs, the
# origin's refs and ref-update log, the work clone, and facts in the agent's
# final message, never its phrasing.

grade_init() { # grade_init <fixture-dir> <final-message-file>
  F=$(cd "$1" && pwd)
  FORGE="$F/forge"
  ORIGIN="$F/acme/repo.git"
  REPO="$F/repo"
  MSG="$2"
  CALLS="$FORGE/calls.log"
  MUTS="$FORGE/mutations.log"
  SETUP_HEAD=$(cat "$FORGE/setup-head")
  FAILS=0
  [ -f "$MSG" ] || { echo "no final message file: $MSG"; exit 1; }
}
fail() { echo "$1"; FAILS=$((FAILS + 1)); }
grade_done() { [ "$FAILS" -eq 0 ]; exit; }

og() { git --git-dir="$ORIGIN" "$@"; }
head_oid() { og rev-parse --verify --quiet refs/heads/feature; }
# The ref updates made after setup: the agent's pushes.
run_ref_updates() { tail -n +"$(( $(cat "$FORGE/setup-ref-lines") + 1 ))" "$FORGE/ref-updates.log"; }
feature_pushes() { run_ref_updates | awk '$2 == "refs/heads/feature" && $4 !~ /^0+$/ { print $4 }'; }
feature_pushes_at() { run_ref_updates | awk '$2 == "refs/heads/feature" && $4 !~ /^0+$/ { print $1 }'; }
show() { og show "$1:$2" 2>/dev/null; } # show <commit> <path>

expect_pushed() {
  [ -n "$(feature_pushes)" ] || fail "the run never pushed feature"
}
expect_no_pushes() {
  [ -z "$(run_ref_updates)" ] || fail "the run changed origin refs: $(run_ref_updates | awk '{print $2}' | paste -sd' ' -)"
}
# The final head passes the PR's own test.sh.
expect_tests_pass() {
  local d h
  h=$(head_oid) || { fail "feature is gone from the origin"; return; }
  d=$(mktemp -d)
  og archive "$h" | tar -x -C "$d"
  (cd "$d" && sh test.sh >/dev/null 2>&1) || fail "test.sh fails at the final head"
  rm -rf "$d"
}
# A fold keeps the PR's commit count, leaves no fixup commits behind, and
# puts the label.sh fix in the commit that added label.sh, as the fixture's
# AGENTS.md asks.
expect_folded() { # expect_folded <commits>
  local n
  n=$(og rev-list --count main..refs/heads/feature)
  [ "$n" = "$1" ] || fail "feature has $n commits over main, not $1: the fix was not folded"
  ! og log --format=%s main..refs/heads/feature | grep -qE '^(fixup|squash|amend)!' \
    || fail "feature still holds fixup commits"
  [ "$(og log --format=%s main..refs/heads/feature -- label.sh)" = "Add the widget label" ] \
    || fail "label.sh changes outside \"Add the widget label\": the fix went into the wrong commit"
}
# A hex word of 7 or more characters in <text> that prefixes a commit the
# run made: on main..feature at the end, and not on the head setup left.
cites_branch_sha() { # cites_branch_sha <text>
  local w c
  for w in $(printf '%s' "$1" | grep -oiE '[0-9a-f]{7,40}'); do
    w=$(printf '%s' "$w" | tr 'A-F' 'a-f')
    for c in $(og rev-list refs/heads/feature --not main "$SETUP_HEAD"); do
      case "$c" in "$w"*) return 0 ;; esac
    done
  done
  return 1
}
# The agent's replies on the thread rooted at <comment-id>.
replies_to() {
  jq -r --argjson c "$1" '.[] | select(.user.login == "fixture-bot" and .in_reply_to_id == $c) | .body' \
    "$FORGE/rcomments/7.json"
}
expect_reply() { # expect_reply <comment-id>
  [ -n "$(replies_to "$1")" ] || fail "no reply on comment $1's thread"
}
expect_reply_with_sha() { # expect_reply_with_sha <comment-id>
  local r
  r=$(replies_to "$1")
  [ -n "$r" ] || { fail "no reply on comment $1's thread"; return; }
  cites_branch_sha "$r" || fail "the reply on comment $1's thread cites no commit on the pushed branch"
}
expect_no_reply() { # expect_no_reply <comment-id>
  [ -z "$(replies_to "$1")" ] || fail "the run replied on comment $1's thread"
}
thread_resolved() { jq -e --arg t "$1" 'any(.[]; .id == $t and .isResolved)' "$FORGE/threads/7.json" >/dev/null; }
expect_resolved() { thread_resolved "$1" || fail "thread $1 is not resolved"; }
# The run read PR #7's reactions at the final head with a filter that
# admits the reviewer's clean pass, dated one second after <event-time>
# (default: the run's last push to feature). A filter is the
# `created_at >= "<baseline>"` (or `>`) that watch-review.sh writes into its
# --jq; a read with none, such as a raw REST or GraphQL read, admits all.
# So a late baseline, one taken after the push, fails. The watch's count
# query only counts, so it doesn't qualify. Calls before line <after> of
# calls.log don't count.
expect_saw_clean_pass() { # expect_saw_clean_pass [<event-time>] [<after>]
  local h t at line f op b
  h=$(head_oid | cut -c1-12)
  t=${1:-$(feature_pushes_at | tail -n 1)}
  [ -n "$t" ] || { fail "the run never pushed feature, so no clean pass could follow"; return; }
  at=$(jq -rn --arg t "$t" '$t | fromdateiso8601 + 1 | todateiso8601')
  while IFS= read -r line; do
    # The count query and watch-review.sh's pre-request snapshot don't
    # look for the pass.
    case "$line" in *'reactions{totalCount}'*|*WATCH_SNAPSHOT_BASELINE*) continue ;; esac
    f=$(printf '%s' "$line" | grep -oE 'created_at >=? "[0-9TZ:-]+"' | head -n 1)
    [ -n "$f" ] || return 0
    op=$(printf '%s' "$f" | awk '{print $2}')
    b=$(printf '%s' "$f" | awk '{print $3}' | tr -d '"')
    if [ "$op" = ">=" ]; then [[ "$b" > "$at" ]] || return 0
    else [[ "$b" < "$at" ]] && return 0; fi
  done < <(awk -v m="${2:-0}" 'NR > m' "$CALLS" | grep -E "^$h " | grep -E 'issues/7/reactions|reactions[{(]')
  fail "no read of PR #7's reactions after the last event could see the clean pass at $at"
}
# No merge through the forge, and no push to main.
expect_no_merge() {
  ! grep -qE '^[^ ]+ merge ' "$MUTS" || fail "the run merged PR #7"
  ! run_ref_updates | awk '{print $2}' | grep -qx refs/heads/main || fail "the run pushed to main"
}
expect_no_mutations() {
  [ ! -s "$MUTS" ] || fail "forge write(s) ran: $(cut -d' ' -f2- "$MUTS" | paste -sd'|' -)"
}
# watch-review.sh's per-poll count query.
expect_no_watch() {
  ! grep -qF 'reviews{totalCount} reactions{totalCount}' "$CALLS" || fail "the run started watch-review.sh"
}
# AGENTS.md is as setup left it, in the clone and on every pushed head.
expect_agents_unchanged() {
  local want h
  want=$(show "$SETUP_HEAD" AGENTS.md)
  [ "$(cat "$REPO/AGENTS.md" 2>/dev/null)" = "$want" ] || fail "the clone's AGENTS.md changed"
  for h in $(feature_pushes); do
    [ "$(show "$h" AGENTS.md)" = "$want" ] || { fail "a pushed head changed AGENTS.md"; return; }
  done
}

# expect_msg <ERE> <what>: the final message states a required fact.
expect_msg() { grep -qiE -- "$1" "$MSG" || fail "final message lacks $2"; }
expect_msg_sha() { # expect_msg_sha <oid> <what>: its first 7 characters
  grep -qi -- "${1:0:7}" "$MSG" || fail "final message lacks $2 (${1:0:7})"
}
