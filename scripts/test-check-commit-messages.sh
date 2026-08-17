#!/usr/bin/env bash
# test-check-commit-messages.sh — fixtures for the commit-message policy.
#
# Builds isolated synthetic repositories with fixed identity and no network.
# Exit code: 0 when every assertion passes, 1 otherwise.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK=$SCRIPT_DIR/check-commit-messages.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z'
export GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
unset GIT_DIR GIT_WORK_TREE

pass=0
fail=0
case_number=0
CASE=''
OUT=''
RC=0

begin_case() {
  case_number=$((case_number + 1))
  CASE=$(printf '%02d %s' "$case_number" "$1")
  echo "case: $CASE"
}

report_failure() {
  fail=$((fail + 1))
  echo "FAIL [$CASE]: $*"
  printf '%s\n' "$OUT" | sed 's/^/    | /'
}

assert_rc() {
  if [ "$RC" -eq "$1" ]; then
    pass=$((pass + 1))
  else
    report_failure "expected rc=$1, got rc=$RC"
  fi
}

assert_contains() {
  case $OUT in
    *"$1"*) pass=$((pass + 1)) ;;
    *) report_failure "output does not contain: $1" ;;
  esac
}

assert_not_contains() {
  case $OUT in
    *"$1"*) report_failure "output unexpectedly contains: $1" ;;
    *) pass=$((pass + 1)) ;;
  esac
}

new_repo() { # <name>; prints repo path
  local repo=$TMP/$1
  git init -q -b main "$repo"
  commit_message "$repo" $'Establish fixture\n\nProvide a base commit for the test range.' >/dev/null
  printf '%s' "$repo"
}

commit_message() { # <repo> <message>; prints the new SHA
  local repo=$1 message=$2 message_file
  message_file=$repo/.git/test-message
  printf '%s' "$message" >"$message_file"
  git -C "$repo" commit -q --allow-empty --allow-empty-message \
    --cleanup=verbatim -F "$message_file"
  git -C "$repo" rev-parse HEAD
}

run_check() { # <repo> <base> <head>; sets OUT and RC
  local repo=$1 base=$2 head=$3
  set +e
  OUT=$( (cd "$repo" && "$CHECK" "$base" "$head") 2>&1 )
  RC=$?
  set -e
}

run_check_with_locale() { # <locale> <repo> <base> <head>; sets OUT and RC
  local locale_name=$1 repo=$2 base=$3 head=$4
  set +e
  OUT=$( (cd "$repo" && LC_ALL=$locale_name "$CHECK" "$base" "$head") 2>&1 )
  RC=$?
  set -e
}

reject_message() { # <case> <rule> <message>
  local label=$1 rule=$2 message=$3 repo base sha
  begin_case "$label"
  repo=$(new_repo "case$case_number")
  base=$(git -C "$repo" rev-parse HEAD)
  sha=$(commit_message "$repo" "$message")
  run_check "$repo" "$base" "$sha"
  assert_rc 1
  assert_contains "$sha"
  assert_contains "[$rule]"
}

begin_case "valid acronyms, identifiers, and unbreakable token"
repo=$(new_repo "case$case_number")
base=$(git -C "$repo" rev-parse HEAD)
long_url=https://example.invalid/a/very/long/path/that/cannot/be/wrapped/without/changing/the/token/0123456789
backtick='`'
sha=$(commit_message "$repo" "$(printf '%s\n\n%s\n%s\n%s' \
  "SHA256 IDs preserve ${backtick}StageDriver${backtick} behavior" \
  'Keep APIv2 and refs/heads/main explicit in diagnostic output.' \
  "$long_url" \
  "The ${backtick}ReviewSource${backtick} identifier remains mechanically readable.")")
run_check "$repo" "$base" "$sha"
assert_rc 0
assert_contains "PASS: checked 1 non-merge commit(s)"

reject_message "lowercase subject" sentence-case \
  $'reject a lowercase subject\n\nExplain why this fixture must fail.'
reject_message "trailing subject period" subject-period \
  $'Reject a trailing period.\n\nExplain why this fixture must fail.'
long_subject=$(printf 'A%.0s' {1..73})
reject_message "subject over 72 characters" subject-length \
  "$(printf '%s\n\n%s' "$long_subject" 'Explain why this fixture must fail.')"
reject_message "missing subject" subject-required \
  $'\n\nA body cannot replace the required subject.'

for item in \
  'fix: reject a prefix' \
  'feat(api): reject a scoped prefix' \
  'refactor!: reject a breaking prefix'; do
  reject_message "Conventional Commit form: $item" conventional-prefix \
    "$(printf '%s\n\n%s' "$item" 'Explain why this fixture must fail.')"
done

reject_message "fixup prefix" autosquash-prefix \
  $'fixup! Add the real behavior\n\nAutosquash commits must not reach review.'
reject_message "squash prefix" autosquash-prefix \
  $'squash! Add the real behavior\n\nAutosquash commits must not reach review.'
reject_message "WIP marker" wip-marker \
  $'Add WIP validation\n\nWork-in-progress markers must not reach review.'

for item in \
  'Address review comments' \
  'Address PR review findings' \
  'Apply review feedback' \
  'PR feedback'; do
  reject_message "review cleanup: $item" review-cleanup \
    "$(printf '%s\n\n%s' "$item" 'Review cleanup belongs in the owning commit.')"
done

reject_message "missing blank separator" blank-separator \
  $'Require a blank separator\nThe body starts on line two.'
reject_message "missing non-blank body" body-required \
  $'Require a body\n\n   '
reject_message "overlong body line" body-line-length \
  $'Wrap body prose\n\nThis body line deliberately contains enough ordinary words to exceed the seventy-two character policy limit.'

begin_case "72-character boundaries pass"
repo=$(new_repo "case$case_number")
base=$(git -C "$repo" rev-parse HEAD)
subject_72=$(printf 'A%.0s' {1..72})
body_72=$(printf 'B%.0s' {1..72})
sha=$(commit_message "$repo" "$(printf '%s\n\n%s' "$subject_72" "$body_72")")
run_check "$repo" "$base" "$sha"
assert_rc 0

begin_case "UTF-8 lengths ignore a byte-oriented caller locale"
repo=$(new_repo "case$case_number")
base=$(git -C "$repo" rev-parse HEAD)
unicode_subject=$(printf 'É%.0s' {1..40})
unicode_body=$(printf 'Motivé %.0s' {1..10})
unicode_body=${unicode_body% }
sha=$(commit_message "$repo" \
  "$(printf '%s\n\n%s' "$unicode_subject" "$unicode_body")")
run_check_with_locale C "$repo" "$base" "$sha"
assert_rc 0
assert_contains "PASS: checked 1 non-merge commit(s)"

begin_case "multi-commit range reports only the offender"
repo=$(new_repo "case$case_number")
base=$(git -C "$repo" rev-parse HEAD)
good_one=$(commit_message "$repo" $'Add the first valid change\n\nExplain the first change and its purpose.')
bad=$(commit_message "$repo" $'break the middle subject\n\nExplain the intentionally invalid change.')
good_two=$(commit_message "$repo" $'Add the final valid change\n\nExplain the final change and its purpose.')
run_check "$repo" "$base" "$good_two"
assert_rc 1
assert_contains "$bad"
assert_not_contains "$good_one"
assert_not_contains "$good_two"
assert_contains "[sentence-case]"

begin_case "merge commits are exempt"
repo=$(new_repo "case$case_number")
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch -q -c side
commit_message "$repo" $'Add valid side work\n\nGive the side branch a valid non-merge commit.' >/dev/null
git -C "$repo" switch -q -c feature "$base"
commit_message "$repo" $'Add valid feature work\n\nGive the feature branch a valid non-merge commit.' >/dev/null
git -C "$repo" merge -q --no-ff -m 'Merge side without a body' side
head=$(git -C "$repo" rev-parse HEAD)
run_check "$repo" "$base" "$head"
assert_rc 0
assert_contains "PASS: checked 2 non-merge commit(s)"

begin_case "base-freshness merge excludes mainline commits"
repo=$(new_repo "case$case_number")
git -C "$repo" switch -q -c feature
commit_message "$repo" $'Add valid feature work\n\nKeep the feature commit inside the checked range.' >/dev/null
git -C "$repo" switch -q main
commit_message "$repo" $'fix: simulate accepted mainline history\n\nKeep this known violation outside the feature range.' >/dev/null
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch -q feature
git -C "$repo" merge -q --no-ff -m 'Merge main without a body' main
head=$(git -C "$repo" rev-parse HEAD)
run_check "$repo" "$base" "$head"
assert_rc 0
assert_contains "PASS: checked 1 non-merge commit(s)"

begin_case "detached exact SHAs resolve"
repo=$(new_repo "case$case_number")
base=$(git -C "$repo" rev-parse HEAD)
head=$(commit_message "$repo" $'Check detached object IDs\n\nUse the exact base and head commits supplied by CI.')
git -C "$repo" checkout -q --detach "$head"
run_check "$repo" "$base" "$head"
assert_rc 0

begin_case "depth-one checkout restores exact-SHA ancestry"
source_repo=$(new_repo "case${case_number}-source")
base=$(git -C "$source_repo" rev-parse HEAD)
git -C "$source_repo" switch -q -c feature
head=$(commit_message "$source_repo" $'Check restored shallow history\n\nFetch exact event commits with their complete ancestry.')
bare_repo=$TMP/case${case_number}-remote.git
shallow_repo=$TMP/case${case_number}-shallow
git clone -q --bare "$source_repo" "$bare_repo"
git clone -q --depth 1 --branch feature "file://$bare_repo" "$shallow_repo"
if [ "$(git -C "$shallow_repo" rev-parse --is-shallow-repository)" != true ]; then
  report_failure "fixture clone is not shallow before the exact-SHA fetch"
fi
git -C "$shallow_repo" fetch -q --no-tags --unshallow origin "$base" "$head"
if [ "$(git -C "$shallow_repo" rev-parse --is-shallow-repository)" = false ]; then
  pass=$((pass + 1))
else
  report_failure "exact-SHA fetch did not restore complete history"
fi
run_check "$shallow_repo" "$base" "$head"
assert_rc 0

echo "assertions: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
