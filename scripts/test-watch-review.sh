#!/usr/bin/env bash
# Validation-matrix regression test for the await-pr-review watcher.
# Offline and deterministic: a PATH shim replaces gh with a command that
# always fails, so any input that passes validation runs one poll, finds
# nothing, and exits 2 (CAP_EXPIRED); any rejected input must exit 64
# before touching the network. Grown one adversarial case per review
# finding; add a case with every future validation fix so the class stops
# recurring one finding at a time.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/skills/await-pr-review/watch-review.sh"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT" >&2; exit 1; }

SHIM=$(mktemp -d)
trap 'rm -rf "$SHIM"' EXIT
printf '#!/bin/sh\nexit 1\n' > "$SHIM/gh"
chmod +x "$SHIM/gh"

BASE="--baseline 2026-07-02T05:07:30Z"
VALID="--pr 46 $BASE --login some-bot --repo owner/name --interval 1 --cap-minutes 0"

pass=0; fail=0
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
t 2 "explicit reaction login" $VALID --reaction-login 'some-bot[bot]'
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

# Paging behavior: canned-response shims emit exactly what each gh --jq
# call would produce, so the bash walk logic runs against controlled page
# layouts the dead shim above never reaches. The over-count cases model
# GraphQL totalCount exceeding the REST collection (pending reviews,
# removed reactions), where the backward walk's top page is empty and the
# real item lives on page 1: breaking there masks a real review or clean
# pass as CAP_EXPIRED.
mk_pageshim() {
  # $1: dir; $2: graphql counts "R X"; $3: reviews p2; $4: reviews p1;
  # $5: reactions p2; $6: reactions p1
  cat > "$1/gh" <<EOF
#!/bin/bash
case "\$*" in
  *graphql*) echo "$2" ;;
  *pulls/*/comments*) echo "0 0 none" ;;
  *pulls/*/reviews*page=2*) echo "$3" ;;
  *pulls/*/reviews*page=1*) echo "$4" ;;
  *issues/*/reactions*page=2*) echo "$5" ;;
  *issues/*/reactions*page=1*) echo "$6" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$1/gh"
}

PAGES=$(mktemp -d)
trap 'rm -rf "$SHIM" "$PAGES"' EXIT

# Review on page 1, reviews totalCount over-counted to 101 (top page empty).
mk_pageshim "$PAGES" "101 0" "0 0 none" "1 0 2026-07-02T09:00:00Z" "0 0 none" "0 0 none"
PATH="$PAGES:$PATH" bash "$SCRIPT" $VALID >/dev/null 2>&1
got=$?
if [ "$got" -eq 0 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL ($got != 0): over-counted reviews must still find the page-1 review" >&2
fi

# Clean-pass reaction on page 1, reactions totalCount over-counted to 101.
mk_pageshim "$PAGES" "0 101" "0 0 none" "0 0 none" "0 0 none" "1 0 2026-07-02T09:00:00Z"
PATH="$PAGES:$PATH" bash "$SCRIPT" $VALID >/dev/null 2>&1
got=$?
if [ "$got" -eq 3 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL ($got != 3): over-counted reactions must still find the page-1 clean pass" >&2
fi

# Empty collections (totalCounts 0): a completed all-zero scan caps out.
mk_pageshim "$PAGES" "0 0" "0 0 none" "0 0 none" "0 0 none" "0 0 none"
PATH="$PAGES:$PATH" bash "$SCRIPT" $VALID >/dev/null 2>&1
got=$?
if [ "$got" -eq 2 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL ($got != 2): empty collections must cap out, not error" >&2
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

echo "watch-review validation matrix: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
