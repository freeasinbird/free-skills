#!/usr/bin/env bash
# check-commit-messages.sh — mechanical commit-message policy check.
#
# Usage: check-commit-messages.sh <base-ref> <head-ref>
#
# Resolves both refs, finds their merge base, and checks every non-merge
# commit in <merge-base>..<head-ref>. This keeps mainline commits brought
# into a feature branch by a base-freshness merge out of the checked set.
# The script performs no network I/O and does not mutate the repository.
#
# Local example:
#   bash scripts/check-commit-messages.sh origin/main HEAD
#
# Exit codes:
#   0  every checked commit satisfies the mechanical policy
#   1  one or more commit messages violate the policy
#   2  usage/environment error or git could not check the requested range
set -euo pipefail

PROG=check-commit-messages

usage() {
  echo "usage: $PROG <base-ref> <head-ref>" >&2
}

fail_git() {
  echo "$PROG: $*" >&2
  exit 2
}

find_utf8_locale() {
  local candidate charmap
  for candidate in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if charmap=$(LC_ALL=$candidate locale charmap 2>/dev/null) \
      && [ "$charmap" = UTF-8 ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

character_length() { # <value>; prints its locale-independent character count
  local value=$1
  (
    export LC_ALL=$UTF8_LOCALE
    printf '%d' "${#value}"
  )
}

if [ "$#" -ne 2 ]; then
  usage
  exit 2
fi

git rev-parse --git-dir >/dev/null 2>&1 \
  || fail_git "not inside a git repository"

UTF8_LOCALE=$(find_utf8_locale) \
  || fail_git "no supported UTF-8 locale for character-length checks"

resolve_commit() { # <ref> <role>; prints the resolved commit SHA
  local ref=$1 role=$2 sha
  sha=$(git rev-parse --verify --quiet --end-of-options "${ref}^{commit}") \
    || fail_git "cannot resolve $role ref '$ref' to a commit"
  printf '%s' "$sha"
}

BASE_SHA=$(resolve_commit "$1" base)
HEAD_SHA=$(resolve_commit "$2" head)
MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA") \
  || fail_git "no merge base between $BASE_SHA and $HEAD_SHA; fetch complete history"
COMMITS=$(git rev-list --reverse --no-merges "$MERGE_BASE..$HEAD_SHA") \
  || fail_git "cannot enumerate commits in $MERGE_BASE..$HEAD_SHA"

MESSAGE_FILE=$(mktemp)
trap 'rm -f "$MESSAGE_FILE"' EXIT

violations=0
checked=0

report_violation() { # <sha> <subject> <rule> <detail>
  local sha=$1 subject=$2 rule=$3 detail=$4
  printf '%s "%s": [%s] %s\n' "$sha" "$subject" "$rule" "$detail" >&2
  violations=$((violations + 1))
}

shopt -s nocasematch
CONVENTIONAL_RE='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([^)]*\))?!?:'
WIP_RE='(^|[^[:alnum:]_])wip([^[:alnum:]_]|$)'
ADDRESS_RE='^address ((pr|pull request) )?review([[:space:]]|$)'
APPLY_RE='^apply ((pr|pull request) )?review feedback([[:space:]]|$)'
PR_FEEDBACK_RE='^(pr|pull request) feedback([[:space:]]|$)'

for sha in $COMMITS; do
  checked=$((checked + 1))
  if ! git cat-file commit "$sha" >"$MESSAGE_FILE"; then
    fail_git "cannot read commit object $sha"
  fi

  lines=()
  while IFS= read -r line || [ -n "$line" ]; do
    lines+=("$line")
  done < <(sed '1,/^$/d' "$MESSAGE_FILE")

  subject=${lines[0]-}
  subject_length=$(character_length "$subject")
  if [ -z "$subject" ]; then
    report_violation "$sha" "$subject" subject-required \
      "subject must be present"
  fi
  if [ "$subject_length" -gt 72 ]; then
    report_violation "$sha" "$subject" subject-length \
      "subject is $subject_length characters; maximum is 72"
  fi
  if [[ $subject == *. ]]; then
    report_violation "$sha" "$subject" subject-period \
      "subject must not end with a period"
  fi
  shopt -u nocasematch
  if [[ $subject =~ ^[a-z] ]]; then
    report_violation "$sha" "$subject" sentence-case \
      "subject must not start with a lowercase ASCII letter"
  fi
  shopt -s nocasematch
  if [[ $subject =~ $CONVENTIONAL_RE ]]; then
    report_violation "$sha" "$subject" conventional-prefix \
      "Conventional Commit prefixes are not allowed"
  fi
  if [[ $subject =~ ^(fixup!|squash!) ]]; then
    report_violation "$sha" "$subject" autosquash-prefix \
      "fixup! and squash! subjects are not allowed"
  fi
  if [[ $subject =~ $WIP_RE ]]; then
    report_violation "$sha" "$subject" wip-marker \
      "standalone WIP markers are not allowed"
  fi
  if [[ $subject =~ $ADDRESS_RE ]] \
    || [[ $subject =~ $APPLY_RE ]] \
    || [[ $subject =~ $PR_FEEDBACK_RE ]]; then
    report_violation "$sha" "$subject" review-cleanup \
      "review-cleanup subjects must be folded into the owning commit"
  fi

  if [ "${#lines[@]}" -lt 2 ] || [ -n "${lines[1]-}" ]; then
    report_violation "$sha" "$subject" blank-separator \
      "line 2 must be blank"
  fi

  body_present=0
  i=2
  while [ "$i" -lt "${#lines[@]}" ]; do
    body_line=${lines[$i]}
    body_line_length=$(character_length "$body_line")
    if [[ $body_line =~ [^[:space:]] ]]; then
      body_present=1
    fi
    if [ "$body_line_length" -gt 72 ] \
      && [[ $body_line =~ [[:space:]] ]]; then
      report_violation "$sha" "$subject" body-line-length \
        "body line $((i + 1)) is $body_line_length characters; maximum is 72"
    fi
    i=$((i + 1))
  done
  if [ "$body_present" -ne 1 ]; then
    report_violation "$sha" "$subject" body-required \
      "body must contain a non-blank line after the separator"
  fi
done

if [ "$violations" -ne 0 ]; then
  echo "FAIL: $violations violation(s) across $checked non-merge commit(s)" >&2
  exit 1
fi

echo "PASS: checked $checked non-merge commit(s)"
