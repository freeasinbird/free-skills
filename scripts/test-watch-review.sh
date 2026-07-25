#!/usr/bin/env bash
# Regression matrix for the await-pr-review watcher. Offline and
# deterministic: PATH shims replace gh, so no test touches the network.
#
# Two halves. The validation half points gh at a command that always fails,
# so any input that passes validation runs one poll, finds nothing, and
# exits 2 (CAP_EXPIRED), while any rejected input exits 64 before touching
# the network. The detection half serves canned JSON pages and runs the
# script's own JQ_* filters over them with the real jq, so a wrong field
# name, a wrong login, or a missing predicate fails a test instead of
# silently matching nothing in production.
#
# Grown one adversarial case per review finding; add a case with every
# future fix so the class stops recurring one finding at a time.
#
# Set WATCH_REVIEW_SCRIPT to test a different copy of the script (used to
# check that this matrix actually fails against a pre-fix watcher).
set -u

SCRIPT="${WATCH_REVIEW_SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/skills/await-pr-review/watch-review.sh}"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT" >&2; exit 1; }

SHIM=$(mktemp -d)
FIX=$(mktemp -d)
SHIMD=$(mktemp -d)
trap 'rm -rf "$SHIM" "$FIX" "$SHIMD"' EXIT
printf '#!/bin/sh\nexit 1\n' > "$SHIM/gh"
chmod +x "$SHIM/gh"

BASE="--baseline 2026-07-02T05:07:30Z"
VALID="--pr 46 $BASE --login some-bot --repo owner/name --interval 1 --cap-minutes 0"

pass=0; fail=0; skip=0
t() {
  expected="$1"; desc="$2"; shift 2
  PATH="$SHIM:$PATH" bash "$SCRIPT" "$@" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL ($got != $expected): $desc: $*" >&2
  fi
}

# Valid inputs pass validation and cap out against the dead shim (exit 2).
t 2 "minimal valid invocation" --pr 46 $BASE --login some-bot --repo owner/name --interval 1 --cap-minutes 0
t 2 "login in [bot] form" --pr 46 $BASE --login 'some-bot[bot]' --repo owner/name --interval 1 --cap-minutes 0
t 2 "explicit rest login" $VALID --rest-login 'some-bot[bot]'
t 2 "deprecated reaction-login alias" $VALID --reaction-login 'some-bot[bot]'
t 2 "full-length lowercase head" $VALID --head 9c346ab0eeaba5e706345c12fabeb1ceddec8be0
t 2 "abbreviated head" $VALID --head 9c346ab
t 2 "uppercase head normalized" $VALID --head 9C346AB
t 2 "every reaction constant maps" $VALID --clean-content ROCKET --progress-content EYES

# Parser: options without values are usage errors, never set -u crashes.
t 64 "no arguments at all"
t 64 "trailing bare --pr" --pr
t 64 "trailing bare --baseline" --pr 46 --baseline
t 64 "trailing bare --head" $VALID --head
t 64 "unknown option" $VALID --bogus x

# --pr: positive integer, no zero, no leading zeros, digits only.
t 64 "pr zero" --pr 0 $BASE --login some-bot --repo owner/name
t 64 "pr leading zeros" --pr 007 $BASE --login some-bot --repo owner/name
t 64 "pr non-numeric" --pr abc $BASE --login some-bot --repo owner/name

# --interval / --cap-minutes: positive / non-negative integers.
t 64 "interval zero" --pr 46 $BASE --login some-bot --repo owner/name --interval 0
t 64 "interval non-numeric" --pr 46 $BASE --login some-bot --repo owner/name --interval abc
t 64 "cap non-numeric" --pr 46 $BASE --login some-bot --repo owner/name --cap-minutes xyz
t 64 "cap negative" --pr 46 $BASE --login some-bot --repo owner/name --cap-minutes -5

# --baseline: full whole-second ISO-8601 UTC shape, not fragments.
t 64 "baseline missing date part" --pr 46 --baseline T00:00:00Z --login some-bot --repo owner/name
t 64 "baseline prose" --pr 46 --baseline yesterday --login some-bot --repo owner/name
t 64 "baseline fractional seconds" --pr 46 --baseline 2026-07-02T05:07:30.000Z --login some-bot --repo owner/name
t 64 "baseline letters in shape" --pr 46 --baseline abcd-ef-ghTij:kl:mnZ --login some-bot --repo owner/name

# Logins: plain login with optional literal [bot] suffix only.
t 64 "login mid-string bracket" --pr 46 $BASE --login 'bad[form]' --repo owner/name
t 64 "login bracket not suffix" --pr 46 $BASE --login 'a[bot]b' --repo owner/name
t 64 "login bare suffix" --pr 46 $BASE --login '[bot]' --repo owner/name
t 64 "login quote injection" --pr 46 $BASE --login 'foo"bar' --repo owner/name
t 64 "rest-login quote injection" $VALID --rest-login 'a" or true or "'
t 64 "rest-login malformed bracket" $VALID --rest-login 'bad[form]x'
t 64 "reaction-login quote injection" $VALID --reaction-login 'a" or true or "'
t 64 "reaction-login malformed bracket" $VALID --reaction-login 'bad[form]x'

# --repo: exactly owner/name, safe charset.
t 64 "repo extra segment" --pr 46 $BASE --login some-bot --repo a/b/c
t 64 "repo query injection" --pr 46 $BASE --login some-bot --repo 'a/b?x=1'
t 64 "repo missing name" --pr 46 $BASE --login some-bot --repo a/

# --head: 7-40 hex chars.
t 64 "head non-hex" $VALID --head xyz
t 64 "head too short" $VALID --head abc123
t 64 "head too long" $VALID --head 9c346ab0eeaba5e706345c12fabeb1ceddec8be00

# Reaction constants: fixed GitHub set, no jq injection.
t 64 "unknown reaction constant" $VALID --clean-content SPARKLES
t 64 "reaction constant injection" $VALID --clean-content 'THUMBS_UP" or true or "'

# ---------------------------------------------------------------------------
# Detection: the JQ_* filters run for real against canned JSON pages.
#
# The shim serves one fixture file per endpoint and page, and executes the
# caller's own --jq filter over it. A request with no fixture exits 1, which
# is how the script sees an API failure. Fixtures therefore describe the API
# the same way the filters read it: paging, author field, timestamps, commit
# anchors. gh embeds gojq rather than jq, but these filters use only
# constructs the two share.
# ---------------------------------------------------------------------------

BOT='some-bot[bot]'      # the REST form --login some-bot derives
OTHER='other-bot[bot]'
AFTER=2026-07-02T09:00:00Z
BEFORE=2026-07-01T09:00:00Z

write_gh_shim() {
  {
    echo '#!/bin/bash'
    echo "FIX=\"$FIX\""
    cat <<'SHIMEOF'
filter='.' target='' page=1 prev=''
for a in "$@"; do
  [ "$prev" = "--jq" ] && filter="$a"
  case "$a" in
    graphql) target=graphql ;;
    repos/*) target="$a" ;;
  esac
  prev="$a"
done
if [ "$target" = graphql ]; then
  fixture="$FIX/graphql.json"
else
  # Anchor on the separator: an unanchored page=N would read per_page=100.
  [[ "$target" =~ [?\&]page=([0-9]+) ]] && page="${BASH_REMATCH[1]}"
  case "$target" in
    *pulls/*/comments*) fixture="$FIX/comments-$page.json" ;;
    *pulls/*/reviews*) fixture="$FIX/reviews-$page.json" ;;
    *issues/*/reactions*) fixture="$FIX/reactions-$page.json" ;;
    *) exit 1 ;;
  esac
fi
[ -f "$fixture" ] || exit 1
exec jq -r "$filter" "$fixture"
SHIMEOF
  } > "$SHIMD/gh"
  chmod +x "$SHIMD/gh"
}

# scenario <name>: drop every fixture, so each case declares exactly the
# pages its API is meant to serve and any other request reads as a failure.
scenario() { SCENARIO="$1"; rm -f "$FIX"/*.json; }

# The GraphQL count query, which sizes the backward page walks.
counts() {
  printf '{"data":{"repository":{"pullRequest":{"reviews":{"totalCount":%s},"reactions":{"totalCount":%s}}}}}' \
    "$1" "$2" > "$FIX/graphql.json"
}
# page <endpoint> <n> [item...]: an empty page is a real, valid response.
page() {
  ep="$1"; n="$2"; shift 2
  ( IFS=,; echo "[$*]" ) > "$FIX/$ep-$n.json"
}
review() {   # review <login> <submitted_at|null> [commit_id]
  rv_at="$2"; [ "$rv_at" = null ] || rv_at="\"$rv_at\""
  printf '{"user":{"login":"%s"},"submitted_at":%s,"commit_id":"%s"}' \
    "$1" "$rv_at" "${3:-deadbeefcafe1234567890abcdef1234567890ab}"
}
comment() {  # comment <login> <created_at> [commit_id] [in_reply_to_id]
  printf '{"user":{"login":"%s"},"created_at":"%s","commit_id":"%s","in_reply_to_id":%s}' \
    "$1" "$2" "${3:-deadbeefcafe1234567890abcdef1234567890ab}" "${4:-null}"
}
reaction() { # reaction <login> <content> <created_at>
  printf '{"user":{"login":"%s"},"content":"%s","created_at":"%s"}' "$1" "$2" "$3"
}

# run_watch [args...]: capture exit code, stdout and stderr for assertion.
run_watch() {
  OUT=$(PATH="$SHIMD:$PATH" bash "$SCRIPT" "$@" 2>"$FIX/stderr")
  RC=$?
  ERR=$(cat "$FIX/stderr")
}
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $SCENARIO: $1" >&2; }
want_rc() {
  if [ "$RC" -eq "$1" ]; then ok; else bad "exit $RC, want $1 (out: $OUT)"; fi
}
want_out() {
  case "$OUT" in *"$1"*) ok ;; *) bad "stdout lacks '$1' (got: $OUT)" ;; esac
}
want_err() {
  case "$ERR" in *"$1"*) ok ;; *) bad "stderr lacks '$1' (got: $ERR)" ;; esac
}
want_not_out() {
  case "$OUT" in *"$1"*) bad "stdout has '$1' (got: $OUT)" ;; *) ok ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  skip=1
  echo "SKIP: detection cases need jq on PATH; only validation ran" >&2
else
write_gh_shim

# The reviewer's own review, matched through the REST author field.
scenario "reviewer review past baseline"
counts 1 0; page reviews 1 "$(review "$BOT" "$AFTER")"; page comments 1
run_watch $VALID
want_rc 0
want_out 'REVIEW_ACTIVITY {"new_reviews":1'

# Author filtering: only the configured reviewer finishes the round.
scenario "another bot's review is not the awaited pass"
counts 1 0; page reviews 1 "$(review "$OTHER" "$AFTER")"
page comments 1; page reactions 1
run_watch $VALID
want_rc 2

scenario "review predating the baseline is already-seen"
counts 1 0; page reviews 1 "$(review "$BOT" "$BEFORE")"
page comments 1; page reactions 1
run_watch $VALID
want_rc 2

# PENDING reviews carry no submitted_at and are not submitted work.
scenario "pending review does not finish the round"
counts 1 0; page reviews 1 "$(review "$BOT" null)"
page comments 1; page reactions 1
run_watch $VALID
want_rc 2

# --rest-login drives review matching, not just reactions: a machine-user
# reviewer configured with its plain login must not match a [bot] author,
# and must match its own.
scenario "rest-login rejects the [bot] form it was not given"
counts 1 0; page reviews 1 "$(review "$BOT" "$AFTER")"
page comments 1; page reactions 1
run_watch $VALID --rest-login some-bot
want_rc 2

scenario "rest-login matches a machine-user review author"
counts 1 0; page reviews 1 "$(review some-bot "$AFTER")"; page comments 1
run_watch $VALID --rest-login some-bot
want_rc 0

scenario "rest-login wins over the deprecated alias"
counts 1 0; page reviews 1 "$(review "$BOT" "$AFTER")"; page comments 1
run_watch $VALID --reaction-login "$OTHER" --rest-login "$BOT"
want_rc 0

# Status-signal reactions, both gated on the baseline: they are mutable and
# one-per-user-per-emoji, so a leftover from an earlier round means nothing.
scenario "stale in-progress reaction does not extend the wait"
counts 0 1; page reviews 1; page comments 1
page reactions 1 "$(reaction "$BOT" eyes "$BEFORE")"
run_watch $VALID
want_rc 2
want_out '"in_progress_seen":false'

scenario "fresh in-progress reaction is reported"
counts 0 1; page reviews 1; page comments 1
page reactions 1 "$(reaction "$BOT" eyes "$AFTER")"
run_watch $VALID
want_rc 2
want_out '"in_progress_seen":true'

scenario "clean-pass reaction past the baseline ends the wait"
counts 0 1; page reviews 1; page comments 1
page reactions 1 "$(reaction "$BOT" '+1' "$AFTER")"
run_watch $VALID
want_rc 3
want_out 'CLEAN_PASS {"clean_reactions":1}'

scenario "stale clean-pass reaction is not this round's pass"
counts 0 1; page reviews 1; page comments 1
page reactions 1 "$(reaction "$BOT" '+1' "$BEFORE")"
run_watch $VALID
want_rc 2

scenario "another user's thumbs-up is not the reviewer's clean pass"
counts 0 1; page reviews 1; page comments 1
page reactions 1 "$(reaction "$OTHER" '+1' "$AFTER")"
run_watch $VALID
want_rc 2

# A reply lands on an existing thread: no new review, no new thread.
scenario "reviewer reply on an existing thread counts"
counts 0 0; page reviews 1
page comments 1 "$(comment "$BOT" "$AFTER")"
run_watch $VALID
want_rc 0
want_out '"new_review_comments":1'

# The newest-first comment feed is a window: the match can sit past page 1.
scenario "comment walk pages until the baseline is crossed"
counts 0 0; page reviews 1
page comments 1 "$(comment "$OTHER" "$AFTER")" "$(comment "$OTHER" "$AFTER")"
page comments 2 "$(comment "$BOT" "$AFTER")"
page comments 3
run_watch $VALID
want_rc 0
want_out '"new_review_comments":1'

# --head: a pass against a superseded head must not end the wait, but a
# reply keeps its old anchor and is still a genuine signal.
scenario "review of a superseded head does not count"
counts 1 0; page reviews 1 "$(review "$BOT" "$AFTER" beefbeefbeefbeefbeefbeefbeefbeefbeefbeef)"
page comments 1; page reactions 1
run_watch $VALID --head 9c346ab
want_rc 2

scenario "abbreviated head matches by prefix"
counts 1 0; page reviews 1 "$(review "$BOT" "$AFTER" 9c346ab0eeaba5e706345c12fabeb1ceddec8be0)"
page comments 1
run_watch $VALID --head 9c346ab
want_rc 0

scenario "reply with a stale anchor still counts under --head"
counts 0 0; page reviews 1
page comments 1 "$(comment "$BOT" "$AFTER" beefbeefbeefbeefbeefbeefbeefbeefbeefbeef 42)"
run_watch $VALID --head 9c346ab
want_rc 0

scenario "non-reply comment on a superseded head does not count"
counts 0 0; page reviews 1
page comments 1 "$(comment "$BOT" "$AFTER" beefbeefbeefbeefbeefbeefbeefbeefbeefbeef)"
page reactions 1
run_watch $VALID --head 9c346ab
want_rc 2

# GraphQL totalCount over-counts the REST collection (pending reviews,
# removed reactions), so the backward walk's top page is empty while the
# real item sits on page 1. Breaking there would mask it as CAP_EXPIRED.
scenario "over-counted reviews still find the page-1 review"
counts 101 0; page reviews 2; page reviews 1 "$(review "$BOT" "$AFTER")"
page comments 1
run_watch $VALID
want_rc 0

scenario "over-counted reactions still find the page-1 clean pass"
counts 0 101; page reviews 1; page comments 1
page reactions 2; page reactions 1 "$(reaction "$BOT" '+1' "$AFTER")"
run_watch $VALID
want_rc 3

scenario "empty collections cap out rather than erroring"
counts 0 0; page reviews 1; page comments 1; page reactions 1
run_watch $VALID
want_rc 2
want_out '"polls_ok":1'
want_out '"last_poll_ok":true'

# Failure must never masquerade as a completed observation: an absence-based
# verdict needs a scan that finished, and a run that observed nothing at all
# must say so rather than reporting a quiet reviewer. Coverage rests on the
# last poll, since every poll rescans from the baseline.
scenario "failed comment scan suppresses the clean-pass verdict"
counts 0 1; page reviews 1
page reactions 1 "$(reaction "$BOT" '+1' "$AFTER")"
run_watch $VALID
want_rc 2
want_out '"polls_ok":0'
want_out '"last_poll_ok":false'
want_err 'scan failed'

scenario "unreadable reactions do not count as a completed poll"
counts 0 1; page reviews 1; page comments 1
run_watch $VALID
want_rc 2
want_out '"polls_ok":0'
want_out '"last_poll_ok":false'
want_err 'reactions scan failed'

scenario "total API failure is not a clean pass"
run_watch $VALID
want_rc 2
want_out '"polls_ok":0'
want_out '"last_poll_ok":false'
want_err 'count query failed'

# A successful poll followed by failures: coverage ends at that poll, so the
# tail of the wait is unobserved and polls_ok alone would call it quiet.
# Needs a second poll, and the shortest run with one is --cap-minutes 1, so
# this case costs ~60s of wall clock and stays opt-in. Set
# WATCH_REVIEW_SLOW=1 to run it (the CAP_EXPIRED assertions above cover the
# single-poll branches of the same flag).
if [ "${WATCH_REVIEW_SLOW:-0}" = 1 ]; then
  scenario "an early success does not cover a failing tail"
  counts 0 0; page reviews 1; page comments 1; page reactions 1
  # Let the first polls succeed, then pull the fixtures out from under the
  # watcher so every later poll fails through to the cap.
  PATH="$SHIMD:$PATH" bash "$SCRIPT" --pr 46 $BASE --login some-bot \
    --repo owner/name --interval 1 --cap-minutes 1 \
    >"$FIX/out" 2>"$FIX/stderr" &
  slow_pid=$!
  sleep 3
  rm -f "$FIX"/*.json
  wait "$slow_pid"; RC=$?
  OUT=$(cat "$FIX/out"); ERR=$(cat "$FIX/stderr")
  want_rc 2
  want_not_out '"polls_ok":0'
  want_out '"last_poll_ok":false'
else
  skip=$((skip + 1))
  echo "SKIP: multi-poll tail case (set WATCH_REVIEW_SLOW=1; costs ~60s)" >&2
fi
fi

# Missing gh: preflight must exit 69 immediately, not sit out the cap.
# Resolve bash first, since the emptied PATH is used for command lookup.
BASH_BIN=$(command -v bash)
NOGH=$(mktemp -d)
PATH="$NOGH" "$BASH_BIN" "$SCRIPT" --pr 46 $BASE --login some-bot --repo owner/name >/dev/null 2>&1
got=$?
if [ "$got" -eq 69 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL ($got != 69): missing gh preflight" >&2
fi
rm -rf "$NOGH"

note=""
[ "$skip" -eq 0 ] || note=", $skip skipped (see SKIP above)"
echo "watch-review matrix: $pass passed, $fail failed$note"
[ "$fail" -eq 0 ]
