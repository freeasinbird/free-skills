#!/usr/bin/env bash
# Offline validation matrix for skills/merge-cleanup/tracker-reconcile.sh.
# A gh shim serves issue and comment JSON from fixture files, applies writes
# to them, serves the base tip from a list read one line per lookup, and logs
# every call. The real tracker-refresh.sh, tracker-write.sh, and
# reconciliation-ledger.sh do the work, so each case pins the exit code, the
# ledger's RESULT line, the write calls, and the trace rows, and checks that
# the ledger accepts every trace the script writes.
#
# Usage: test-merge-cleanup-reconcile.sh
#
# To run it under macOS /bin/bash 3.2, put a `bash` symlink to /bin/bash
# first on PATH, as test-merge-cleanup-refresh.sh describes:
#   d=$(mktemp -d) && ln -s /bin/bash "$d/bash" &&
#     PATH="$d:$PATH" ./scripts/test-merge-cleanup-reconcile.sh
# Exit codes: 0 all passed, 1 a case failed.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT="$ROOT/skills/merge-cleanup/tracker-reconcile.sh"
LEDGER="$ROOT/skills/merge-cleanup/reconciliation-ledger.sh"
[ -x "$SUT" ] || { echo "not executable: $SUT" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SHIMD="$TMP/shim" FIX="$TMP/fix"
mkdir -p "$SHIMD" "$FIX/issue" "$FIX/comment"
export FIX
pass=0 fail=0
REPO=github.invalid/acme/app
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
T=$(printf '\t')

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $CASE: $1" >&2; }

# plan <row>...: write the plan file, one row per argument, `|` for a tab.
plan() {
  : >"$TMP/plan"
  for r in "$@"; do printf '%s\n' "$r" | tr '|' '\t' >>"$TMP/plan"; done
}
run() { # run <args...>: sets RC, OUT (file), ERR (file); TRACE is fresh
  OUT="$TMP/out" ERR="$TMP/err" TRACE="$TMP/trace"
  : >"$FIX/calls.log"
  rm -f "$FIX"/count.* "$TRACE"
  PATH="$SHIMD:$PATH" bash "$SUT" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
go() { run --repo "$REPO" --base main --plan "$TMP/plan" --trace "$TMP/trace"; }
want_rc() {
  [ "$RC" -eq "$1" ] && ok || bad "exit $RC, want $1; stderr: $(cat "$ERR")"
}
want_result() { # want_result <word>: the ledger verdict on stdout
  [ "$(sed -n 1p "$OUT")" = "RESULT $1" ] && ok \
    || bad "stdout '$(sed -n 1p "$OUT")', want 'RESULT $1'; stderr: $(cat "$ERR")"
}
want_err() {
  case "$(cat "$ERR")" in *"$1"*) ok ;; *) bad "stderr lacks '$1': $(cat "$ERR")" ;; esac
}
want_row() { # want_row <row with | for tab>: the trace holds that exact row
  local r
  r=$(printf '%s' "$1" | tr '|' '\t')
  grep -qxF -- "$r" "$TRACE" && ok || bad "trace lacks row '$1':$(sed 's/^/  /' "$TRACE")"
}
want_trace() { # want_trace <row>...: the trace is exactly these rows
  local r
  : >"$TMP/want"
  for r in "$@"; do printf '%s\n' "$r" | tr '|' '\t' >>"$TMP/want"; done
  cmp -s "$TMP/want" "$TRACE" && ok || bad "trace differs:$(diff "$TMP/want" "$TRACE" | sed 's/^/  /')"
}
# The ledger, run on its own, accepts the trace and gives the same verdict.
want_ledger_ok() {
  bash "$LEDGER" "$TRACE" >"$TMP/ledger" 2>&1 && cmp -s "$TMP/ledger" "$OUT" && ok \
    || bad "the ledger rejects or disagrees: $(cat "$TMP/ledger")"
}
writes() { grep -cE '^(issue edit|api .*-X PATCH)' "$FIX/calls.log"; }
want_writes() {
  [ "$(writes)" -eq "$1" ] && ok || bad "$(writes) write calls, want $1: $(cat "$FIX/calls.log")"
}
want_no_calls() {
  [ -s "$FIX/calls.log" ] && bad "gh was called: $(cat "$FIX/calls.log")" || ok
}
want_no_trace() {
  [ -e "$TRACE" ] && bad "a trace was written: $(cat "$TRACE")" || ok
}

# --- refusals: no forge needed --------------------------------------------------
cat >"$SHIMD/gh" <<'GH'
#!/bin/sh
echo "$*" >>"$FIX/calls.log"
exit 1
GH
chmod +x "$SHIMD/gh"
refused() { # refused <description> <exit> <args...>
  CASE="refused: $1"; want="$2"; shift 2
  run "$@"
  want_rc "$want"; want_no_calls; want_no_trace
  [ -s "$OUT" ] && bad "printed to stdout: $(cat "$OUT")" || ok
}
plan "policy|$A|complete|initial" "plan|#1|write|#1|#10"
# zsh passes an unquoted variable as one argument.
refused "all flags in one argument" 64 "--repo $REPO --base main --plan $TMP/plan --trace $TMP/trace"
refused "no arguments" 64
refused "missing base" 64 --repo "$REPO" --plan "$TMP/plan" --trace "$TMP/trace"
refused "missing trace" 64 --repo "$REPO" --base main --plan "$TMP/plan"
refused "empty plan value" 64 --repo "$REPO" --base main --plan "" --trace "$TMP/trace"
refused "unknown option" 64 --repo "$REPO" --base main --plan "$TMP/plan" --trace "$TMP/trace" --pr 5
refused "hostless repo" 64 --repo acme/app --base main --plan "$TMP/plan" --trace "$TMP/trace"
refused "option-like base" 64 --repo "$REPO" --base -x --plan "$TMP/plan" --trace "$TMP/trace"
refused "missing plan file" 64 --repo "$REPO" --base main --plan "$TMP/absent" --trace "$TMP/trace"

CASE="refused: existing trace"
echo keep >"$TMP/trace"
PATH="$SHIMD:$PATH" bash "$SUT" --repo "$REPO" --base main --plan "$TMP/plan" \
  --trace "$TMP/trace" >"$TMP/out" 2>"$TMP/err"
RC=$? ERR="$TMP/err"
want_rc 64; want_err "already exists"
[ "$(cat "$TMP/trace")" = keep ] && ok || bad "the existing trace was changed"
rm -f "$TMP/trace"

refused_plan() { # refused_plan <description> <expected stderr> <row>...
  local desc="$1" text="$2"; shift 2
  plan "$@"
  refused "$desc" 64 --repo "$REPO" --base main --plan "$TMP/plan" --trace "$TMP/trace"
  want_err "$text"
}
refused_plan "unreadable policy" "manual source-failure path" \
  "policy|$A|unreadable|initial"
refused_plan "unverifiable policy tip" "policy tip is unverifiable" \
  "policy|unverifiable|complete|initial" "plan|#1|write|#1"
refused_plan "unsupported item" "unsupported" \
  "policy|$A|complete|initial" "plan|#1|write|#1" "plan|close-epic|unsupported"
for name in tracker '#0' '#01' '#1/' '#/5' '#1/0' '#1/2/3' '#1:' '#1:a b' '#1:x:y' '1'; do
  refused_plan "item name '$name'" "item $name" \
    "policy|$A|complete|initial" "plan|$name|write|#1"
done

CASE="invalid plan: duplicate item"
plan "policy|$A|complete|initial" "plan|#1|write|#1" "plan|#1|noop|#1"
go
want_rc 2; want_no_calls; want_no_trace; want_err "INVALID"
[ -s "$OUT" ] && bad "printed to stdout: $(cat "$OUT")" || ok

CASE="missing sibling script"
plan "policy|$A|complete|initial" "plan|#1|write|#1"
TRACKER_WRITE_SCRIPT="$TMP/absent.sh" go
want_rc 69; want_no_calls; want_no_trace

CASE="--help"
run --help
[ "$RC" -eq 0 ] && grep -q -- '--trace TRACE' "$OUT" && ok || bad "--help failed"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: behavior cases require jq; refusals only" >&2
  echo "test-merge-cleanup-reconcile: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]; exit
fi

# --- gh shim ------------------------------------------------------------------
# Reads serve fixtures through jq; `issue edit` and a comment PATCH store the
# file as the body. A commits/<branch> lookup prints line n of $FIX/tips on
# the nth lookup (the last line once they run out), and fails on `fail`.
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
case "$path" in
  repos/acme/app/commits/main)
    n=$(( $(cat "$FIX/count.tip" 2>/dev/null || echo 0) + 1 ))
    echo "$n" >"$FIX/count.tip"
    t=$(sed -n "${n}p" "$FIX/tips"); [ -n "$t" ] || t=$(sed -n '$p' "$FIX/tips")
    [ "$t" != fail ] || { echo "HTTP 502" >&2; exit 1; }
    echo "$t"; exit ;;
  repos/*/commits/*) exit 1 ;;
esac
if [ "$sub" = issue ]; then
  r="${repo#*/}"
  fixture="$FIX/issue/$(printf '%s' "$r" | tr '/A-Z' '~a-z')~$num.json"
else
  fixture="$FIX/comment/${path##*/}.json"
fi
[ -f "$fixture" ] || exit 1
if [ -n "$file" ]; then
  jq --rawfile b "$file" '.body = $b' "$fixture" >"$fixture.new" && mv "$fixture.new" "$fixture"
  echo '{}'
  exit
fi
case "$sub $verb" in "issue view" | "api "*) ;; *) exit 1 ;; esac
exec jq -r "$jqf" "$fixture"
GH
chmod +x "$SHIMD/gh"
tips() { printf '%s\n' "$@" >"$FIX/tips"; }

issue() { # issue <N> <state> <reason> <body-file>
  jq -n --arg s "$2" --arg r "$3" --rawfile b "$4" \
    '{state:$s, stateReason:(if $r == "" then null else $r end), body:$b}' \
    >"$FIX/issue/acme~app~$1.json"
}
comment() { # comment <ID> <issue> <body-file>
  jq -n --arg u "https://api.github.invalid/repos/acme/app/issues/$2" --rawfile b "$3" \
    '{issue_url:$u, body:$b}' >"$FIX/comment/$1.json"
}

# tracker <ticked/merged units> <startable ids> <bullet>: #10 and #12 have no
# prerequisite; #11 starts after #10. The same shape as the write matrix.
tracker() {
  local m=" $1 "
  cat <<EOF
**Fixture tracker.** One tracker for the reconcile matrix.

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
issue 10 CLOSED COMPLETED "$TMP/dep-none.md"
issue 11 OPEN "" "$TMP/dep-10.md"
issue 12 OPEN "" "$TMP/dep-none.md"
make stale '' i10,i12 '#10, #12'     # before #10 merged
make current 10 i11,i12 '#11, #12'   # its refresh after #10 merged
# A tracker whose Units section lists no unit, so the refresh stops.
sed '/^- \[.\] #1[0-2]$/d' "$TMP/stale.md" >"$TMP/nounits.md"
stale() { issue "$1" OPEN "" "$TMP/stale.md"; }
current() { issue "$1" OPEN "" "$TMP/current.md"; }
IN='#1|#10|#11|#12'     # the inputs every tracker-1 item names
IN2='#2|#10|#11|#12'

# --- behavior -----------------------------------------------------------------
CASE="written tracker"
stale 1; tips "$A"
plan "policy|$A|complete|initial" "plan|#1|write|$IN"
go
want_rc 0; want_result complete; want_writes 1; want_ledger_ok
want_trace "policy|$A|complete|initial" "plan|#1|write|$IN" \
  "pre|$A" "guard|complete|$IN" "attempt|accepted|#1" "verify|#1|changed" \
  "recheck|fresh|$IN" "post|$A" "final|$A"
want_err "tracker-write.sh: RESULT written"

CASE="written comment tracker"
issue 3 OPEN "" "$TMP/dep-none.md"; comment 777 3 "$TMP/stale.md"; tips "$A"
plan "policy|$A|complete|initial" "plan|#3/777|write|#3/777|#10|#11|#12"
go
want_rc 0; want_result complete; want_writes 1; want_ledger_ok
grep -qF -- "-X PATCH repos/acme/app/issues/comments/777" "$FIX/calls.log" && ok \
  || bad "no comment PATCH call: $(cat "$FIX/calls.log")"

CASE="noop tracker"
current 1; tips "$A"
plan "policy|$A|complete|initial" "plan|#1|noop|$IN"
go
want_rc 0; want_result complete; want_writes 0; want_ledger_ok
want_trace "policy|$A|complete|initial" "plan|#1|noop|$IN" "observe|#1|fresh|$IN" "final|$A"

CASE="write item already current at write time continues"
current 1; stale 2; tips "$A"
plan "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2"
go
want_rc 1; want_result partial; want_writes 1; want_ledger_ok
want_row "skip|#1|already current at write time|remaining"
want_row "attempt|accepted|#2"

CASE="tracker lists no unit: refused"
issue 1 OPEN "" "$TMP/nounits.md"; stale 2; tips "$A"
plan "policy|$A|complete|initial" "plan|#1|write|#1" "plan|#2|write|$IN2"
go
want_rc 1; want_result incomplete; want_writes 0; want_ledger_ok
want_err "tracker-refresh.sh: STOP"
want_row "guard|unavailable"
grep -qE "^skip${T}#1${T}tracker-refresh.sh: STOP [^$T]+${T}ambiguity\$" "$TRACE" && ok \
  || bad "no ambiguity skip naming the STOP: $(cat "$TRACE")"
want_row "skip|#2|an earlier item stopped reconciliation|remaining"

CASE="failed lookup"
stale 1; stale 2; tips "$A"
mv "$FIX/issue/acme~app~11.json" "$TMP/unit11.json"
plan "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2"
go
want_rc 1; want_result incomplete; want_writes 0; want_ledger_ok
want_err "LOOKUP_FAILED issue acme/app#11"
grep -qE "^skip${T}#1${T}tracker-refresh.sh: LOOKUP_FAILED issue acme/app#11[^$T]*${T}guard\$" \
  "$TRACE" && ok || bad "no guard skip naming the failed read: $(cat "$TRACE")"
want_row "skip|#2|an earlier item stopped reconciliation|remaining"
mv "$TMP/unit11.json" "$FIX/issue/acme~app~11.json"

CASE="base tip moves between items"
stale 1; stale 2; tips "$A" "$A" "$B"
plan "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2" "plan|#1:board|report|$IN"
go
want_rc 1; want_result partial; want_writes 1; want_ledger_ok
want_trace "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2" \
  "plan|#1:board|report|$IN" \
  "pre|$A" "guard|complete|$IN" "attempt|accepted|#1" "verify|#1|changed" \
  "recheck|fresh|$IN" "post|$A" \
  "pre|$B" "skip|#2|base tip moved before the write|policy" \
  "skip|#1:board|base tip moved or was unverifiable during reconciliation|policy" \
  "final|$B"

CASE="base tip moves during a write"
stale 1; stale 2; tips "$A" "$B"
plan "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2"
go
want_rc 1; want_result partial; want_writes 1; want_ledger_ok
want_row "post|$B"
want_row "skip|#2|base tip moved or was unverifiable during reconciliation|policy"

CASE="base tip unverifiable before the first write"
stale 1; tips fail "$A"
plan "policy|$A|complete|initial" "plan|#1|write|$IN"
go
want_rc 1; want_result restart; want_writes 0; want_ledger_ok
want_row "pre|unverifiable"; want_row "skip|#1|base tip was unverifiable before the write|policy"
want_err "base tip lookup for main failed"

CASE="report item after a write"
stale 1; tips "$A"
plan "policy|$A|complete|initial" "plan|#1:refresh|write|$IN" "plan|#1:startable|report|$IN"
go
want_rc 0; want_result complete; want_writes 1; want_ledger_ok
want_row "observe|#1:startable|fresh|$IN"
grep -qF -- "issue edit 1 --repo $REPO --body-file" "$FIX/calls.log" && ok || bad "no body edit of #1"

CASE="stale observation stops the rest"
stale 1; current 2; tips "$A"
plan "policy|$A|complete|initial" "plan|#1|noop|$IN" "plan|#2|report|$IN2"
go
want_rc 1; want_result incomplete; want_writes 0; want_ledger_ok
want_row "observe|#1|stale|$IN"
want_row "skip|#2|an earlier observation stopped reconciliation|remaining"

CASE="refresh stops while observing: unverifiable"
issue 1 CLOSED COMPLETED "$TMP/current.md"; current 2; tips "$A"
plan "policy|$A|complete|initial" "plan|#1|noop|$IN" "plan|#2|report|$IN2"
go
want_rc 1; want_result incomplete; want_writes 0; want_ledger_ok
want_err "tracker-refresh.sh: STOP tracker #1 is closed"
want_row "observe|#1|unverifiable|$IN"
want_row "skip|#2|an earlier observation stopped reconciliation|remaining"

CASE="a trace named - is a file, not stdin"
stale 1; tips "$A"
plan "policy|$A|complete|initial" "plan|#1|write|$IN"
( cd "$TMP" && rm -f ./- && PATH="$SHIMD:$PATH" bash "$SUT" --repo "$REPO" --base main \
    --plan plan --trace - </dev/null >"$TMP/out" 2>"$TMP/err" )
RC=$? OUT="$TMP/out" ERR="$TMP/err" TRACE="$TMP/-"
want_rc 0; want_result complete; want_ledger_ok

CASE="absent policy records only final"
tips "$A"
plan "policy|$A|absent|initial"
go
want_rc 0; want_result complete; want_writes 0; want_ledger_ok
want_trace "policy|$A|absent|initial" "final|$A"

CASE="empty complete plan records only final"
plan "policy|$A|complete|initial"
go
want_rc 0; want_result complete; want_ledger_ok
want_trace "policy|$A|complete|initial" "final|$A"

# --- an untrustworthy tracker-write.sh ------------------------------------------
stub() { # stub <name> <exit> <stdout line or empty>
  { printf '#!/bin/sh\necho "stub stderr line" >&2\n'
    [ -z "$3" ] || printf 'echo "%s"\n' "$3"
    printf 'exit %s\n' "$2"; } >"$TMP/$1"
}

for code in 64 69; do
  CASE="write exits $code with no result line: tooling skip"
  stale 1; tips "$A"
  stub "w$code" "$code" ""
  plan "policy|$A|complete|initial" "plan|#1|write|$IN"
  TRACKER_WRITE_SCRIPT="$TMP/w$code" go
  want_rc 1; want_result incomplete; want_ledger_ok
  want_row "guard|unavailable"
  want_row "skip|#1|tracker-write.sh exited $code before any forge call: stub stderr line|tooling"
done

CASE="a tab in a refusal cause becomes a space"
stale 1; tips "$A"
printf '#!/bin/sh\nprintf "tracker-refresh.sh: STOP a\\tb\\n" >&2\n%s\nexit 2\n' \
  'echo "tracker-write.sh: RESULT refused guard=unavailable attempt=none verify=none recheck=none"' \
  >"$TMP/wtab"
plan "policy|$A|complete|initial" "plan|#1|write|$IN"
TRACKER_WRITE_SCRIPT="$TMP/wtab" go
want_rc 1; want_result incomplete; want_ledger_ok
want_row "skip|#1|tracker-refresh.sh: STOP a b|ambiguity"

CASE="base tip moves after an untrusted result"
stale 1; stale 2; tips "$A" "$B"
stub wbad 1 ""
plan "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2"
TRACKER_WRITE_SCRIPT="$TMP/wbad" go
want_rc 1; want_ledger_ok
want_row "post|$B"
want_row "skip|#2|base tip moved or was unverifiable during reconciliation|policy"

# Well-formed results the fixtures above don't reach, transcribed as SKILL.md's
# result table says, each stopping the next item.
transcribed() { # transcribed <result> <exit> <fields> <want result> <row>...
  CASE="transcribed: $1"
  local result="$1" code="$2" fields="$3" verdict="$4"; shift 4
  stale 1; stale 2; tips "$A"
  stub wok "$code" "tracker-write.sh: RESULT $result $fields"
  plan "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2"
  TRACKER_WRITE_SCRIPT="$TMP/wok" go
  want_rc 1; want_result "$verdict"; want_ledger_ok
  want_trace "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2" \
    "pre|$A" "$@" "skip|#2|an earlier item stopped reconciliation|remaining" "final|$A"
}
transcribed changed-since-read 3 "guard=complete attempt=none verify=none recheck=none" \
  incomplete "guard|complete|$IN" "skip|#1|tracker changed since read|remaining"
transcribed write-failed 5 "guard=complete attempt=failed verify=failed recheck=changed" \
  incomplete "guard|complete|$IN" "attempt|failed|#1" "verify|#1|failed" \
  "recheck|changed|$IN" "post|$A"
transcribed unverified 5 "guard=complete attempt=accepted verify=unknown recheck=fresh" \
  partial "guard|complete|$IN" "attempt|accepted|#1" "verify|#1|unknown" \
  "recheck|fresh|$IN" "post|$A"

malformed() { # malformed <description> <exit> <stdout line>
  CASE="untrusted write result: $1"
  stale 1; stale 2; tips "$A"
  stub wbad "$2" "$3"
  plan "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2"
  TRACKER_WRITE_SCRIPT="$TMP/wbad" go
  want_rc 1; want_result incomplete; want_ledger_ok
  grep -qxF "UNKNOWN #1: attempted after guard unavailable" "$OUT" && ok \
    || bad "no UNKNOWN row for #1: $(cat "$OUT")"
  want_trace "policy|$A|complete|initial" "plan|#1|write|$IN" "plan|#2|write|$IN2" \
    "pre|$A" "guard|unavailable" "attempt|failed|#1" "verify|#1|unknown" \
    "recheck|unverifiable|$IN" "post|$A" \
    "skip|#2|an earlier item stopped reconciliation|remaining" "final|$A"
  want_err "without a result line this script can trust"
}
malformed "no line, killed" 137 ""
malformed "garbage" 0 "all good"
malformed "written with exit 5" 5 \
  "tracker-write.sh: RESULT written guard=complete attempt=accepted verify=changed recheck=fresh"
malformed "written with a stale recheck" 0 \
  "tracker-write.sh: RESULT written guard=complete attempt=accepted verify=changed recheck=changed"
malformed "an extra field" 0 \
  "tracker-write.sh: RESULT written guard=complete attempt=accepted verify=changed recheck=fresh x=1"
malformed "unverified that reads as written" 5 \
  "tracker-write.sh: RESULT unverified guard=complete attempt=accepted verify=changed recheck=fresh"
malformed "a colon inside a value" 5 \
  "tracker-write.sh: RESULT write-failed guard=complete:failed attempt=zzz verify=failed recheck=changed"
malformed "fields out of order" 0 \
  "tracker-write.sh: RESULT written attempt=accepted guard=complete verify=changed recheck=fresh"

echo "test-merge-cleanup-reconcile: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
