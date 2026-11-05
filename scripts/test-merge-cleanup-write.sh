#!/usr/bin/env bash
# Offline validation matrix for skills/merge-cleanup/tracker-write.sh.
# A gh shim serves issue and comment JSON from fixture files, applies writes
# to them, and logs every call, so each case pins the exit code, the result
# line, and whether a write reached the forge. The shim can also swap in a
# fixture on a chosen call, to model a concurrent edit or a unit that merges
# mid-run. The real tracker-refresh.sh computes every refresh.
#
# Usage: test-merge-cleanup-write.sh
#
# To run it under macOS /bin/bash 3.2, put a `bash` symlink to /bin/bash
# first on PATH, as test-merge-cleanup-refresh.sh describes:
#   d=$(mktemp -d) && ln -s /bin/bash "$d/bash" &&
#     PATH="$d:$PATH" ./scripts/test-merge-cleanup-write.sh
# Exit codes: 0 all passed, 1 a case failed.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT="${TRACKER_WRITE_SCRIPT:-$ROOT/skills/merge-cleanup/tracker-write.sh}"
[ -x "$SUT" ] || { echo "not executable: $SUT" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SHIMD="$TMP/shim" FIX="$TMP/fix"
mkdir -p "$SHIMD" "$FIX/issue" "$FIX/comment"
export FIX
pass=0 fail=0
REPO=github.invalid/acme/app

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $CASE: $1" >&2; }

run() { # run <args...>: sets RC, OUT (file), ERR (file)
  OUT="$TMP/out" ERR="$TMP/err"
  : >"$FIX/calls.log"
  rm -f "$FIX"/count.*
  PATH="$SHIMD:$PATH" bash "$SUT" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
want_rc() {
  [ "$RC" -eq "$1" ] && ok || bad "exit $RC, want $1; stderr: $(cat "$ERR")"
}
want_result() { # want_result <result line after the prefix>
  [ "$(cat "$OUT")" = "tracker-write.sh: RESULT $1" ] && ok \
    || bad "result '$(cat "$OUT")', want '$1'; stderr: $(cat "$ERR")"
}
want_err() {
  case "$(cat "$ERR")" in *"$1"*) ok ;; *) bad "stderr lacks '$1': $(cat "$ERR")" ;; esac
}
writes() { grep -cE '^(issue edit|api .*-X PATCH)' "$FIX/calls.log"; }
want_writes() {
  [ "$(writes)" -eq "$1" ] && ok || bad "$(writes) write calls, want $1: $(cat "$FIX/calls.log")"
}
want_no_calls() {
  [ -s "$FIX/calls.log" ] && bad "gh was called: $(cat "$FIX/calls.log")" || ok
}
want_body() { # want_body <text-file>: the tracker body now holds that text
  jq -j .body "$FIX/issue/acme~app~1.json" >"$TMP/now"
  cmp -s "$TMP/now" "$1" && ok || bad "tracker body differs:$(diff "$1" "$TMP/now" | sed 's/^/  /')"
}

# --- validation: no forge needed ----------------------------------------------
cat >"$SHIMD/gh" <<'GH'
#!/bin/sh
echo "$*" >>"$FIX/calls.log"
exit 1
GH
chmod +x "$SHIMD/gh"
CASE=validation
v() {
  desc="$1"; shift
  run "$@"
  [ "$RC" -eq 64 ] && ok || bad "$desc: exit $RC, want 64"
  [ -s "$FIX/calls.log" ] && bad "$desc: gh was called" || ok
  [ -s "$OUT" ] && bad "$desc: printed a result" || ok
}
# zsh passes an unquoted variable as one argument, as in the incident.
v "all arguments in one" "--repo $REPO --issue 1"
v "no arguments"
v "missing issue" --repo "$REPO"
v "missing repo" --issue 1
v "zero issue" --repo "$REPO" --issue 0
v "non-numeric comment" --repo "$REPO" --issue 1 --comment abc
v "hostless repo" --repo acme/app --issue 1
v "unknown option" --repo "$REPO" --issue 1 --bogus x
v "trailing bare option" --repo "$REPO" --issue 1 --edited
: >"$TMP/base.md"
v "missing edited file" --repo "$REPO" --issue 1 --edited "$TMP/absent.md" --base "$TMP/base.md"
v "missing base file" --repo "$REPO" --issue 1 --edited "$TMP/base.md" --base "$TMP/absent.md"
v "edited without base" --repo "$REPO" --issue 1 --edited "$TMP/base.md"
v "base without edited" --repo "$REPO" --issue 1 --base "$TMP/base.md"
# An unset variable passed as a value: `--edited "$F"` with F unset.
v "empty edited value" --repo "$REPO" --issue 1 --edited "" --base "$TMP/base.md"
v "empty comment value" --repo "$REPO" --issue 1 --comment ""
run --repo "$REPO" --issue 1
[ "$RC" -eq 4 ] && ok || bad "valid invocation: exit $RC, want 4"
want_result "lookup-failed guard=unavailable attempt=none verify=none recheck=none"
want_writes 0
run --help
[ "$RC" -eq 0 ] && grep -q -- '--edited FILE' "$OUT" && ok || bad "--help failed"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: behavior cases require jq; validation only" >&2
  echo "test-merge-cleanup-write: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]; exit
fi

# --- gh shim ------------------------------------------------------------------
# Reads serve fixtures through jq. `issue edit` and a comment PATCH store the
# file as the body, unless $FIX/fail-write exists; with $FIX/write-adds-newline
# they store one more newline than the file holds. When the call's key (the
# --jq filter, or `write`) equals $SWAP_KEY for the $SWAP_NTH time, the shim
# first copies $FIX/swap.src over $FIX/swap.dst.
cat >"$SHIMD/gh" <<'GH'
#!/usr/bin/env bash
set -u
echo "$*" >>"$FIX/calls.log"
sub="$1" verb="${2:-}" repo="" num="" path="" jqf="" file="" prev=""
for arg in "$@"; do
  case "$prev" in
    --repo) repo="$arg" ;; --jq) jqf="$arg" ;; --body-file) file="$arg" ;;
    -F) file="${arg#body=@}" ;;
  esac
  case "$arg" in [0-9]*) [ "$sub" = issue ] && [ -z "$num" ] && num="$arg" ;;
    repos/*) path="$arg" ;; esac
  prev="$arg"
done
if [ "$sub" = issue ]; then
  r="${repo#*/}"
  fixture="$FIX/issue/$(printf '%s' "$r" | tr '/A-Z' '~a-z')~$num.json"
else
  fixture="$FIX/comment/${path##*/}.json"
fi
key="${jqf:-write}"
count="$FIX/count.$(printf '%s' "$key" | tr -c 'a-z' '_')"
n=$(( $(cat "$count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$count"
if [ "$key" = "${SWAP_KEY:-}" ] && [ "$n" = "${SWAP_NTH:-}" ]; then
  cp "$FIX/swap.src" "$FIX/swap.dst"
fi
[ -f "$fixture" ] || exit 1
if [ -n "$file" ]; then
  [ ! -f "$FIX/fail-write" ] || { echo "HTTP 502" >&2; exit 1; }
  extra=""; [ ! -f "$FIX/write-adds-newline" ] || extra=$'\n'
  jq --rawfile b "$file" --arg x "$extra" '.body = $b + $x' "$fixture" >"$fixture.new" \
    && mv "$fixture.new" "$fixture"
  echo '{}'
  exit
fi
case "$sub $verb" in "issue view" | "api "*) ;; *) exit 1 ;; esac
exec jq -r "$jqf" "$fixture"
GH
chmod +x "$SHIMD/gh"

issue() { # issue <N> <state> <reason> <body-file>
  jq -n --arg s "$2" --arg r "$3" --rawfile b "$4" \
    '{state:$s, stateReason:(if $r == "" then null else $r end), body:$b}' \
    >"$FIX/issue/acme~app~$1.json"
}
comment() { # comment <ID> <body-file>
  jq -n --rawfile b "$2" \
    '{issue_url:"https://api.github.invalid/repos/acme/app/issues/1", body:$b}' \
    >"$FIX/comment/$1.json"
}
swap() { # swap <key> <nth> <source-json> <fixture-json>
  export SWAP_KEY="$1" SWAP_NTH="$2"
  cp "$3" "$FIX/swap.src"
  rm -f "$FIX/swap.dst"; ln -s "$4" "$FIX/swap.dst"
}
noswap() { unset SWAP_KEY SWAP_NTH; }

# tracker <ticked/merged units> <startable ids> <bullet>: #10 and #12 have no
# prerequisite; #11 starts after #10.
tracker() {
  local m=" $1 "
  cat <<EOF
**Fixture tracker.** One tracker for the write matrix.

## Status

\`\`\`mermaid
flowchart LR
    $(node i10 10 '#10 Schema')
    $(node i11 11 '#11 Reader')
    $(node i12 12 '#12 Docs')
    i10 --> i11
    classDef startable stroke:#15803d,stroke-width:3px
    class $2 startable
\`\`\`

- **Startable now:** $3.

## Units

- [$(tick 10)] #10
- [$(tick 11)] #11
- [$(tick 12)] #12
EOF
}
node() { case "$m" in *" $2 "*) printf '%s[["%s"]]' "$1" "$3" ;; *) printf '%s["%s"]' "$1" "$3" ;; esac; }
tick() { case "$m" in *" $1 "*) printf x ;; *) printf ' ' ;; esac; }
# printf '%s' "$(...)" drops the final newline, as gh stores a body.
make() { printf '%s' "$(tracker "$2" "$3" "$4")" >"$TMP/$1.md"; }

printf '### Dependencies\n\nnone\n' >"$TMP/dep-none.md"
printf '### Dependencies\n\n- starts-after #10\n' >"$TMP/dep-10.md"
units() { # units <state:reason of #10> <of #12>
  issue 10 "${1%%:*}" "${1#*:}" "$TMP/dep-none.md"
  issue 11 OPEN "" "$TMP/dep-10.md"
  issue 12 "${2%%:*}" "${2#*:}" "$TMP/dep-none.md"
}
OPEN=OPEN: MERGED=CLOSED:COMPLETED

make stale '' i10,i12 '#10, #12'     # before #10 merged
make fresh 10 i11,i12 '#11, #12'     # its refresh after #10 merged
make current 10 i11,i12 '#11, #12'
units $MERGED $OPEN
WRITTEN="written guard=complete attempt=accepted verify=changed recheck=fresh"

# --- refresh failures ---------------------------------------------------------
CASE="closed tracker: refresh stops, no write"
issue 1 CLOSED COMPLETED "$TMP/stale.md"
run --repo "$REPO" --issue 1
want_rc 2; want_result "refused guard=unavailable attempt=none verify=none recheck=none"
want_err "STOP tracker #1 is closed"; want_writes 0

CASE="unit read fails: refresh lookup fails, no write"
issue 1 OPEN "" "$TMP/stale.md"
mv "$FIX/issue/acme~app~11.json" "$TMP/unit11.json"
run --repo "$REPO" --issue 1
want_rc 4; want_result "lookup-failed guard=unavailable attempt=none verify=none recheck=none"
want_err "LOOKUP_FAILED issue acme/app#11"; want_writes 0
mv "$TMP/unit11.json" "$FIX/issue/acme~app~11.json"

CASE="refresh exits 0 with empty stdout: no write"
printf '#!/bin/sh\necho "tracker-refresh.sh: OK changed; ticked none" >&2\nexit 0\n' >"$TMP/stub-empty"
TRACKER_REFRESH_SCRIPT="$TMP/stub-empty" run --repo "$REPO" --issue 1
want_rc 2; want_result "refused guard=unavailable attempt=none verify=none recheck=none"
want_err "the refresh printed nothing"; want_writes 0

CASE="refresh exits 0 with no OK line: no write"
printf '#!/bin/sh\ncat "$0"\nexit 0\n' >"$TMP/stub-silent"
TRACKER_REFRESH_SCRIPT="$TMP/stub-silent" run --repo "$REPO" --issue 1
want_rc 2; want_err "no OK status line"; want_writes 0

CASE="refresh exits 69: refused, no write"
printf '#!/bin/sh\necho "awk not found" >&2\nexit 69\n' >"$TMP/stub-tools"
TRACKER_REFRESH_SCRIPT="$TMP/stub-tools" run --repo "$REPO" --issue 1
want_rc 2; want_result "refused guard=unavailable attempt=none verify=none recheck=none"
want_writes 0

# --- guard --------------------------------------------------------------------
CASE="body changed before the last read: no write"
cp "$FIX/issue/acme~app~1.json" "$TMP/stale.json"
make edited '' i10,i12 '#10, #12, owner note'
issue 1 OPEN "" "$TMP/edited.md"; cp "$FIX/issue/acme~app~1.json" "$TMP/edited.json"
cp "$TMP/stale.json" "$FIX/issue/acme~app~1.json"
swap .body 2 "$TMP/edited.json" "$FIX/issue/acme~app~1.json"
run --repo "$REPO" --issue 1
want_rc 3; want_result "changed-since-read guard=complete attempt=none verify=none recheck=none"
want_err "changed since it was read"; want_writes 0; want_body "$TMP/edited.md"

CASE="body changed before the refresh read it: no write"
cp "$TMP/stale.json" "$FIX/issue/acme~app~1.json"
swap '.state, .body' 1 "$TMP/edited.json" "$FIX/issue/acme~app~1.json"
run --repo "$REPO" --issue 1
want_rc 3; want_writes 0; want_body "$TMP/edited.md"
noswap

CASE="already current: noop"
issue 1 OPEN "" "$TMP/current.md"
run --repo "$REPO" --issue 1
want_rc 0; want_result "noop guard=complete attempt=none verify=none recheck=none"
want_writes 0

# --- writes -------------------------------------------------------------------
CASE="body write is verified"
issue 1 OPEN "" "$TMP/stale.md"
run --repo "$REPO" --issue 1
want_rc 0; want_result "$WRITTEN"; want_writes 1; want_body "$TMP/fresh.md"
want_err "tracker-refresh.sh: OK changed; ticked #10"
grep -qF -- "issue edit 1 --repo $REPO --body-file" "$FIX/calls.log" && ok || bad "no body edit call"

CASE="comment write is verified"
issue 1 OPEN "" "$TMP/dep-none.md"
comment 777 "$TMP/stale.md"
run --repo "$REPO" --issue 1 --comment 777
want_rc 0; want_result "$WRITTEN"; want_writes 1
grep -qF -- "api --hostname github.invalid -X PATCH repos/acme/app/issues/comments/777 -F body=@" \
  "$FIX/calls.log" && ok || bad "no comment PATCH call"
jq -j .body "$FIX/comment/777.json" >"$TMP/now"
cmp -s "$TMP/now" "$TMP/fresh.md" && ok || bad "comment body differs from the refresh"

CASE="write call fails"
issue 1 OPEN "" "$TMP/stale.md"
touch "$FIX/fail-write"
run --repo "$REPO" --issue 1
want_rc 5; want_result "write-failed guard=complete attempt=failed verify=failed recheck=changed"
want_err "write call exited 1"; want_body "$TMP/stale.md"
rm "$FIX/fail-write"

CASE="stored text differs from the text written"
touch "$FIX/write-adds-newline"
run --repo "$REPO" --issue 1
want_rc 5; want_result "unverified guard=complete attempt=accepted verify=unknown recheck=changed"
rm "$FIX/write-adds-newline"

CASE="a unit merges during the write: unverified"
issue 1 OPEN "" "$TMP/stale.md"
cp "$FIX/issue/acme~app~12.json" "$TMP/unit12.json"
issue 12 CLOSED COMPLETED "$TMP/dep-none.md"; cp "$FIX/issue/acme~app~12.json" "$TMP/unit12-merged.json"
cp "$TMP/unit12.json" "$FIX/issue/acme~app~12.json"
swap write 1 "$TMP/unit12-merged.json" "$FIX/issue/acme~app~12.json"
run --repo "$REPO" --issue 1
want_rc 5; want_result "unverified guard=complete attempt=accepted verify=changed recheck=changed"
want_err "rerun: tracker-refresh.sh: OK changed; ticked #12"
noswap
cp "$TMP/unit12.json" "$FIX/issue/acme~app~12.json"

# --- --edited -----------------------------------------------------------------
# A project rule that keeps #11 out of the startable set.
make project 10 i12 '#12 (#11 waits on its stack)'

CASE="edited startable lines are written and verified"
issue 1 OPEN "" "$TMP/stale.md"
run --repo "$REPO" --issue 1 --edited "$TMP/project.md" --base "$TMP/fresh.md"
want_rc 0; want_result "$WRITTEN"; want_writes 1; want_body "$TMP/project.md"

CASE="edited file already current: noop"
run --repo "$REPO" --issue 1 --edited "$TMP/project.md" --base "$TMP/fresh.md"
want_rc 0; want_result "noop guard=complete attempt=none verify=none recheck=none"
want_writes 0

CASE="an editor's final newline changes nothing"
issue 1 OPEN "" "$TMP/stale.md"
{ cat "$TMP/project.md"; echo; } >"$TMP/project-nl.md"
run --repo "$REPO" --issue 1 --edited "$TMP/project-nl.md" --base "$TMP/fresh.md"
want_rc 0; want_result "$WRITTEN"; want_body "$TMP/project.md"

CASE="edited file from a stale refresh: no write"
# FILE was made before #12 gained a Blocker line, which now holds it.
issue 1 OPEN "" "$TMP/stale.md"
printf '### Dependencies\n\nnone\n\nBlocker: the owner decides.\n' >"$TMP/dep-blocked.md"
cp "$FIX/issue/acme~app~12.json" "$TMP/unit12.json"
issue 12 OPEN "" "$TMP/dep-blocked.md"
run --repo "$REPO" --issue 1 --edited "$TMP/project.md" --base "$TMP/fresh.md"
want_rc 3; want_result "changed-since-read guard=complete attempt=none verify=none recheck=none"
want_err "no longer matches --base"; want_writes 0; want_body "$TMP/stale.md"
cp "$TMP/unit12.json" "$FIX/issue/acme~app~12.json"

refused() { # refused <description> <file>
  CASE="edited: $1 is refused"
  issue 1 OPEN "" "$TMP/stale.md"
  run --repo "$REPO" --issue 1 --edited "$2" --base "$TMP/fresh.md"
  want_rc 2; want_result "refused guard=unavailable attempt=none verify=none recheck=none"
  want_err "--edited refused"; want_writes 0; want_body "$TMP/stale.md"
}
sed 's/^- \[x\] #10$/- [ ] #10/' "$TMP/project.md" >"$TMP/bad-tick.md"
refused "another changed line" "$TMP/bad-tick.md"
sed '/^- \[ \] #12$/d' "$TMP/project.md" >"$TMP/bad-drop.md"
refused "a dropped line" "$TMP/bad-drop.md"
{ cat "$TMP/project.md"; printf '\n\n- [ ] #13'; } >"$TMP/bad-extra.md"
refused "an added line" "$TMP/bad-extra.md"
want_err "the refresh output has"
: >"$TMP/bad-empty.md"
refused "an empty file" "$TMP/bad-empty.md"
sed 's/class i12 startable/class i12 fenced/' "$TMP/project.md" >"$TMP/bad-class.md"
refused "a class line that is no longer startable" "$TMP/bad-class.md"
sed 's/^- \*\*Startable now:\*\*.*/- Startable now: #12./' "$TMP/project.md" >"$TMP/bad-bullet.md"
refused "a bullet that is no longer the Startable now bullet" "$TMP/bad-bullet.md"

echo "test-merge-cleanup-write: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
