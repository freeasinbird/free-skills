#!/usr/bin/env bash
# Offline validation matrix for skills/merge-cleanup/tracker-refresh.sh.
# A gh shim serves issue and comment JSON from fixture files, so every case
# pins the refreshed text exactly. The lane fixture is modeled on
# freeside-ai/freeside#2021 (a subgraph, a labeled fence edge, a node that is
# not a unit, a cross-repository unit, a label with a second reference); the
# flat fixture has no lanes, no startable line, and CRLF line endings.
#
# Usage: test-merge-cleanup-refresh.sh
# Exit codes: 0 all passed, 1 a case failed.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT="${TRACKER_REFRESH_SCRIPT:-$ROOT/skills/merge-cleanup/tracker-refresh.sh}"
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
  PATH="$SHIMD:$PATH" bash "$SUT" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
want_rc() {
  [ "$RC" -eq "$1" ] && ok || bad "exit $RC, want $1; stderr: $(cat "$ERR")"
}
want_out() { # want_out <expected-body-file>: stdout is the body exactly
  if cmp -s "$OUT" "$1"; then ok
  else bad "stdout differs from expected:$(diff "$1" "$OUT" | sed 's/^/  /')"; fi
}
want_err() {
  case "$(cat "$ERR")" in *"$1"*) ok ;; *) bad "stderr lacks '$1': $(cat "$ERR")" ;; esac
}
want_call() {
  grep -qF -- "$1" "$FIX/calls.log" && ok || bad "no gh call matching '$1'"
}

# --- validation: no forge needed ---------------------------------------------
printf '#!/bin/sh\nexit 1\n' >"$SHIMD/gh"
chmod +x "$SHIMD/gh"
CASE=validation
v() {
  want="$1" desc="$2"; shift 2
  run "$@"
  [ "$RC" -eq "$want" ] && ok || bad "$desc: exit $RC, want $want"
}
v 4 "valid invocation reaches the forge" --repo "$REPO" --issue 1
v 64 "no arguments"
v 64 "missing issue" --repo "$REPO"
v 64 "missing repo" --issue 1
v 64 "zero issue" --repo "$REPO" --issue 0
v 64 "leading-zero issue" --repo "$REPO" --issue 01
v 64 "non-numeric comment" --repo "$REPO" --issue 1 --comment abc
v 64 "hostless repo" --repo acme/app --issue 1
v 64 "extra repo segment" --repo "$REPO/x" --issue 1
v 64 "invalid host" --repo .invalid/acme/app --issue 1
v 64 "unknown option" --repo "$REPO" --issue 1 --bogus x
v 64 "trailing bare option" --repo "$REPO" --issue 1 --comment
run --help
[ "$RC" -eq 0 ] && grep -q -- '--comment ID' "$OUT" && ok || bad "--help failed"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: behavior cases require jq; validation only" >&2
  echo "test-merge-cleanup-refresh: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]; exit
fi

# --- gh shim ------------------------------------------------------------------
cat >"$SHIMD/gh" <<'GH'
#!/usr/bin/env bash
set -u
echo "$*" >>"$FIX/calls.log"
sub="$1" repo="" num="" path="" jqf="" prev=""
for arg in "$@"; do
  case "$prev" in --repo) repo="$arg" ;; --jq) jqf="$arg" ;; esac
  case "$arg" in [0-9]*) [ "$sub" = issue ] && [ -z "$num" ] && num="$arg" ;;
    repos/*) path="$arg" ;; esac
  prev="$arg"
done
case "$sub" in
  issue)
    [ "$2" = view ] || exit 1
    r="${repo#*/}"
    fixture="$FIX/issue/$(printf '%s' "$r" | tr '/A-Z' '~a-z')~$num.json" ;;
  api) fixture="$FIX/comment/${path##*/}.json" ;;
  *) exit 1 ;;
esac
[ -f "$fixture" ] || exit 1
exec jq -r "$jqf" "$fixture"
GH
chmod +x "$SHIMD/gh"

issue() { # issue <owner/repo> <N> <state> <reason> <body-file>
  jq -n --arg s "$3" --arg r "$4" --rawfile b "$5" \
    '{state:$s, stateReason:(if $r == "" then null else $r end), body:$b}' \
    >"$FIX/issue/$(printf '%s' "$1" | tr '/' '~')~$2.json"
}
body() { printf '%s' "$2" >"$TMP/$1.md"; }
tracker() { issue acme/app 1 "${2:-OPEN}" "" "$1"; }
# A later run reads the refreshed text as the current body.
retracker() { cp "$OUT" "$TMP/again.md"; tracker "$TMP/again.md"; }

# --- unit issues -------------------------------------------------------------
body dep-none $'### Dependencies\n\n_No response_\n'
# Freeside's prose notes: the Reverse line names starts-after for other
# issues, so reading it as an entry would make #10 wait on itself.
body dep-reverse $'### Dependencies\n\n- starts-after: none.\n\nReverse: #11 and #12 declare `starts-after` #10.\nRefs #99.\n\n### Scope\n\n- starts-after #13\n'
body dep-on-10 $'### Dependencies\n\n- `starts-after` #10: the reader needs the schema.\n- merges-after #13\n- `exclusive-with` other open contract units.\n'
body dep-fenced $'### Dependencies\n\n- starts-after #10\n\nFence: the owner lifts it.\n'
body dep-tools $'### Dependencies\n\n- starts-after acme/tools#5\n'
body dep-lead-none $'**Objective.** A helper.\n\n**Dependencies.** none. The proposal\nmerged earlier.\n'
body dep-bad $'### Dependencies\n\n- starts after #10\n'
body dep-bad-lead $'**Dependencies.** after #10 lands.\n'
body dep-lead-20 $'**Dependencies:** starts-after #20.\n'

units() { # units <state of #10> <#11> <#12> <#13> <acme/tools#5>, each STATE[:REASON]
  local s
  set -- 10 "$1" dep-reverse 11 "$2" dep-on-10 12 "$3" dep-fenced 13 "$4" dep-tools 5 "$5" dep-lead-none
  while [ $# -gt 0 ]; do
    s="$2"
    if [ "$1" = 5 ]; then issue acme/tools 5 "${s%%:*}" "${s#*:}" "$TMP/$3.md"
    else issue acme/app "$1" "${s%%:*}" "${s#*:}" "$TMP/$3.md"; fi
    shift 3
  done
}
OPEN=OPEN: MERGED=CLOSED:COMPLETED DROPPED=CLOSED:NOT_PLANNED

# --- lane fixture -------------------------------------------------------------
LEGEND='**Legend:** thick arrow critical path · arrow starts-after · dotted arrow soft dependency · double border merged · green outline startable now · orange contract · grey dashed owner-run · dashed outline fenced.'
# lane_tracker <merged units> <ticked units> <startable line> <bullet>: a unit
# list such as "10 5" double-borders or ticks those units.
lane_tracker() {
  local m=" $1 " t=" $2 " sl=""
  [ -z "$3" ] || sl="$3"$'\n'
  cat <<EOF
**Fixture tracker.** One tracker for the refresh matrix.

- **Plan:** the fixture.

## Status

\`\`\`mermaid
flowchart LR
    subgraph spine["Spine work"]
    $(node i10 10 '#10 Schema change')
    $(node i11 11 '#11 Reader for schema (#10)')
    end
    $(node i12 12 '#12 Fenced switch')
    $(node i13 13 '#13 Docs pass')
    $(node fs5 5 'tools#5 Shared helper')
    i90["#90 Other tracker work"]
    i10 ==> i11
    i10 ==> i12
    i90 -- fence --> i12
    fs5 --> i13
    classDef contract fill:#fde2c8,stroke:#c2410c,color:#000
    classDef owner fill:#e5e7eb,stroke:#6b7280,stroke-dasharray:5 5,color:#000
    classDef fenced stroke-dasharray:5 5
    classDef startable stroke:#15803d,stroke-width:3px
    class i10 contract
    class i12 fenced
$sl\`\`\`

$LEGEND

- **Startable now:** $4.
- **Fenced:** #12 until the owner lifts it.

## Units

### lane:spine

- [$(tick 10)] #10
- [$(tick 11)] #11
- [$(tick 12)] #12

### lane:docs

- [$(tick 13)] #13

### tools

- [$(tick 5)] acme/tools#5

## Exit

- [ ] The schema lands. Evidence: #10.
EOF
}
node() { case "$m" in *" $2 "*) printf '%s[["%s"]]' "$1" "$3" ;; *) printf '%s["%s"]' "$1" "$3" ;; esac; }
tick() { case "$t" in *" $1 "*) printf x ;; *) printf ' ' ;; esac; }
rev_br() { [ "$1" = '[[' ] && printf ']]' || printf ']'; }
SL() { printf '    class %s startable\n' "$1"; }

lane_tracker '' '' "$(SL i10,fs5)" '#10 (spine, contract), acme/tools#5' >"$TMP/lane-open.md"

CASE="unchanged tracker diffs empty"
tracker "$TMP/lane-open.md"; units $OPEN $OPEN $OPEN $OPEN $OPEN
run --repo "$REPO" --issue 1
want_rc 0; want_out "$TMP/lane-open.md"; want_err "OK unchanged; ticked none"
if grep -qE ' edit |-X|PATCH|POST' "$FIX/calls.log"; then bad "a gh call writes"; else ok; fi

CASE="merge ticks, double-borders, and moves startable"
units $MERGED $OPEN $OPEN $OPEN $OPEN
run --repo "$REPO" --issue 1
lane_tracker 10 10 "$(SL i11,fs5)" '#11 (spine), acme/tools#5' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"; want_err "OK changed; ticked #10; double-bordered i10"

CASE="second run changes nothing"
retracker
run --repo "$REPO" --issue 1
want_rc 0; want_out "$TMP/want.md"; want_err "OK unchanged; ticked none; double-bordered none"
tracker "$TMP/lane-open.md"

CASE="non-unit node keeps its own startable class"
lane_tracker '' '' "$(SL i10,i90,fs5)" '#10 (spine, contract), acme/tools#5' >"$TMP/nonunit.md"
tracker "$TMP/nonunit.md"
run --repo "$REPO" --issue 1
lane_tracker 10 10 "$(SL i11,fs5,i90)" '#11 (spine), acme/tools#5' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"
tracker "$TMP/lane-open.md"

CASE="closed as not planned is not merged"
units $DROPPED $OPEN $OPEN $OPEN $OPEN
run --repo "$REPO" --issue 1
lane_tracker '' '' "$(SL fs5)" 'acme/tools#5' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"

CASE="cross-repository unit is looked up in its own repository"
units $MERGED $OPEN $OPEN $OPEN $MERGED
run --repo "$REPO" --issue 1
lane_tracker '10 5' '10 5' "$(SL i11,i13)" '#11 (spine), #13 (docs)' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"; want_call "issue view 5 --repo github.invalid/acme/tools"

CASE="fenced unit never gains startable"
grep -q 'i12' "$OUT" && ! grep -q 'class .*i12.* startable' "$OUT" && ok \
  || bad "i12 gained startable"

CASE="all merged drops the startable line"
units $MERGED $MERGED $MERGED $MERGED $MERGED
run --repo "$REPO" --issue 1
lane_tracker '10 11 12 13 5' '10 11 12 13 5' '' 'all units merged' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"; want_err "startable now all units merged"
grep -q 'i90\["#90 Other tracker work"\]' "$OUT" && ok || bad "non-unit node changed"

CASE="open units waiting on unmerged prerequisites"
units $DROPPED $OPEN $MERGED $OPEN $DROPPED
run --repo "$REPO" --issue 1
lane_tracker 12 12 '' 'every open unit waits on #10, acme/tools#5' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"

# The fenced #12 waits on nothing named in the reason, so the reason must
# not claim every open unit waits.
CASE="open units fenced or waiting"
units $DROPPED $OPEN $OPEN $OPEN $DROPPED
run --repo "$REPO" --issue 1
lane_tracker '' '' '' 'every open unit is fenced or waits on #10, acme/tools#5' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"

CASE="ticked but unmerged line is left and reported"
lane_tracker '' 11 "$(SL i10,fs5)" '#10 (spine, contract), acme/tools#5' >"$TMP/ticked.md"
tracker "$TMP/ticked.md"; units $OPEN $OPEN $OPEN $OPEN $OPEN
run --repo "$REPO" --issue 1
want_rc 0; want_out "$TMP/ticked.md"; want_err "left #11 ticked but not merged"

CASE="double border without a merge is left and reported"
lane_tracker 10 '' "$(SL i10,fs5)" '#10 (spine, contract), acme/tools#5' >"$TMP/bordered.md"
tracker "$TMP/bordered.md"
run --repo "$REPO" --issue 1
want_rc 0; want_out "$TMP/bordered.md"; want_err "i10 double-bordered but not merged"

CASE="unparseable Dependencies entry stops and names the unit"
tracker "$TMP/lane-open.md"; units $OPEN $OPEN $OPEN $OPEN $OPEN
issue acme/app 11 OPEN "" "$TMP/dep-bad.md"
run --repo "$REPO" --issue 1
want_rc 4; want_err "#11"
[ -s "$OUT" ] && bad "printed text on failure" || ok

CASE="unparseable bold-lead Dependencies stops and names the unit"
issue acme/app 11 OPEN "" "$TMP/dep-bad-lead.md"
run --repo "$REPO" --issue 1
want_rc 4; want_err "Dependencies field of #11"

CASE="a closed unit's Dependencies field is never read"
units $DROPPED $MERGED $OPEN $OPEN $OPEN
issue acme/app 11 CLOSED COMPLETED "$TMP/dep-bad.md"
run --repo "$REPO" --issue 1
lane_tracker 11 11 "$(SL fs5)" 'acme/tools#5' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"

# Dependencies shapes from the refute-first review. #13 waits on #11, which
# is open, in every shape: the run must either stop or keep #13 off the
# startable set. Dropping #11 would list #13 as startable.
units $MERGED $OPEN $OPEN $OPEN $MERGED
dep13() { # dep13 <want: stop|block> <desc> <body>
  CASE="Dependencies shape ($2)"
  body d13 "$3"
  issue acme/app 13 OPEN "" "$TMP/d13.md"
  run --repo "$REPO" --issue 1
  case "$1" in
    stop) want_rc 4; want_err "#13" ;;
    block)
      want_rc 0
      case "$(cat "$ERR")" in *"startable now"*"#13"*) bad "#13 listed startable: $(cat "$ERR")" ;; *) ok ;; esac ;;
  esac
}
dep13 stop "two bare references" $'### Dependencies\n\n- starts-after #10 #11\n'
dep13 stop "or" $'### Dependencies\n\n- starts-after #10 or #11\n'
dep13 stop "ampersand" $'### Dependencies\n\n- starts-after #10 & #11\n'
dep13 stop "slash" $'### Dependencies\n\n- starts-after #10/#11\n'
dep13 stop "bare reference line" $'### Dependencies\n\n#11\n'
dep13 stop "then" $'**Dependencies.** starts-after #10, then #11.\n'
dep13 stop "lead none with a prerequisite" $'**Dependencies.** None besides starts-after #11.\n'
dep13 stop "prose prerequisite" $'### Dependencies\n\nThis also starts-after #11.\n'
dep13 stop "subhead list item" $'## Dependencies\n\n### Starts after\n\n- #11\n'
dep13 stop "missing field" $'### Scope\n\nNothing about order.\n'
dep13 stop "empty section" $'### Dependencies\n\n### Scope\n\nNothing about order.\n'
dep13 stop "section of notes only" $'### Dependencies\n\nRefs #99.\n'
dep13 block "parenthetical" $'### Dependencies\n\n- starts-after #10 (schema), #11\n'
dep13 block "continuation line" $'### Dependencies\n\n- starts-after #10,\n  #11\n'
dep13 block "continuation and" $'### Dependencies\n\n- starts-after #10,\n  and #11\n'
dep13 block "after another relation" $'### Dependencies\n\n- merges-after #10, starts-after #11\n'
dep13 block "after exclusive-with" $'### Dependencies\n\n- exclusive-with #20; starts-after #11\n'
dep13 block "numbered item" $'### Dependencies\n\n1. starts-after #11\n'
dep13 block "quoted line" $'### Dependencies\n\n> starts-after #11\n'
dep13 block "heading with a qualifier" $'### Dependencies (hard)\n\n- starts-after #11\n'
dep13 block "unbolded lead" $'Dependencies: starts-after #11.\n'
dep13 stop "note after a period" $'### Dependencies\n\n- starts-after #10. Also starts-after #11\n'
dep13 stop "note after a colon" $'### Dependencies\n\n- starts-after #10: and starts-after #11\n'
dep13 stop "lead note after a period" $'**Dependencies.** starts-after #10. Also starts-after #11.\n'
dep13 stop "fence line naming a prerequisite" $'### Dependencies\n\n- starts-after #10\n\nFence: starts-after #11 too.\n'
dep13 stop "none, then an entry" $'### Dependencies\n\nnone\n\n- starts-after #11\n'
dep13 stop "none, then a bare reference" $'### Dependencies\n\nnone\n\n- #11\n'
units $MERGED $OPEN $OPEN $OPEN $MERGED
CASE="none, then notes that name starts-after"
body d13 $'### Dependencies\n\nnone\n\nNo `starts-after` or `merges-after`. Context:\n\n- #12\'s notes say "#13 declares `starts-after` #11"; that is stale.\n'
issue acme/app 13 OPEN "" "$TMP/d13.md"
run --repo "$REPO" --issue 1
want_rc 0
case "$(cat "$ERR")" in *"startable now"*"#13"*) ok ;; *) bad "#13 not startable: $(cat "$ERR")" ;; esac
issue acme/app 13 OPEN "" "$TMP/dep-tools.md"

# Chart and Units lines the command cannot read exactly stop the run, since
# a unit drawn another way could carry a fence it would miss.
units $OPEN $OPEN $OPEN $OPEN $OPEN
chart_stop() { # chart_stop <desc> <sed expression>
  CASE="unreadable tracker line stops ($1)"
  sed "$2" "$TMP/lane-open.md" >"$TMP/odd.md"
  tracker "$TMP/odd.md"
  run --repo "$REPO" --issue 1
  want_rc 2; [ -s "$OUT" ] && bad "printed text on a stop" || ok
}
chart_stop "inline class" 's/^    i12\["#12 Fenced switch"\]$/    i12["#12 Fenced switch"]:::fenced/'
chart_stop "round node" 's/^    i12\["#12 Fenced switch"\]$/    i12("#12 Fenced switch")/'
chart_stop "edge defines nodes" '/^    i12\["#12 Fenced switch"\]$/d; s/^    i10 ==> i12$/    i10 ==> i12["#12 Fenced switch"]/'
chart_stop "spaced class list" 's/^    class i10,fs5 startable$/    class i10, fs5 startable/'
chart_stop "titled unit line" 's/^- \[ \] #11$/- [ ] #11 Reader/'
chart_stop "asterisk unit line" 's/^- \[ \] #13$/* [ ] #13/'
tracker "$TMP/lane-open.md"

CASE="a node drawn twice for one unit is ambiguous"
units $OPEN $OPEN $OPEN $OPEN $OPEN
sed 's/^    i90\["#90 Other tracker work"\]$/    i10b["#10 Drawn again"]/' "$TMP/lane-open.md" >"$TMP/dup.md"
tracker "$TMP/dup.md"
run --repo "$REPO" --issue 1
want_rc 4; want_err "has two nodes"

CASE="one node ID shared by two units is ambiguous"
sed 's/^    i90\["#90 Other tracker work"\]$/    i10["#13 Docs pass"]/; /^    i13\["#13 Docs pass"\]$/d' "$TMP/lane-open.md" >"$TMP/dup.md"
tracker "$TMP/dup.md"
run --repo "$REPO" --issue 1
want_rc 4; want_err "node i10 of unit #"

CASE="a unit's node ID reused by another node is ambiguous"
sed 's/^    i90\["#90 Other tracker work"\]$/    i10["#90 Other tracker work"]/' "$TMP/lane-open.md" >"$TMP/dup.md"
tracker "$TMP/dup.md"
run --repo "$REPO" --issue 1
want_rc 4; want_err "node i10 of unit #10 is declared more than once"

# A redeclaration inline on an edge is ambiguous the same way; a mention of
# the ID in front matter, a comment, a label, edge text, a keyword statement,
# or a longer ID is not a declaration.
redeclared() { # redeclared <desc> <sed expression>
  CASE="a unit's node ID redeclared inline is ambiguous ($1)"
  sed "$2" "$TMP/lane-open.md" >"$TMP/dup.md"
  tracker "$TMP/dup.md"
  run --repo "$REPO" --issue 1
  want_rc 4; want_err "node i11 of unit #11 is declared more than once"
  [ -s "$OUT" ] && bad "printed text on a stop" || ok
}
redeclared "edge target" 's/^    i10 ==> i11$/    i10 ==> i11["#90 Relabeled"]/'
redeclared "edge source" 's/^    i10 ==> i11$/    i11["#90 Relabeled"] --> i13/'
redeclared "no spaces" 's/^    i10 ==> i11$/    i10==>i11["#90 Relabeled"]/'
redeclared "pipe edge text" 's/^    i10 ==> i11$/    i10 -->|after schema| i11["#90 Relabeled"]/'
redeclared "unquoted edge text" 's/^    i10 ==> i11$/    i10 -- after schema --> i11["#90 Relabeled"]/'
redeclared "dotted edge text" 's/^    i10 ==> i11$/    i10 -. after schema .-> i11("#90 Relabeled")/'
redeclared "after &" 's/^    i10 ==> i11$/    i10 \& i11["#90 Relabeled"] --> i13/'
redeclared "after a multi-line Markdown string" 's/^    i90\["#90 Other tracker work"\]$/    i90["`#90 Other\
    tracker work`"] --> i11["#90 Relabeled"]/'

mentioned() { # mentioned <desc> <sed expression>
  CASE="a mention of a unit's node ID is not a declaration ($1)"
  sed "$2" "$TMP/lane-open.md" >"$TMP/dup.md"
  tracker "$TMP/dup.md"
  run --repo "$REPO" --issue 1
  want_rc 0; want_out "$TMP/dup.md"
}
I90='^    i90\["#90 Other tracker work"\]$'
mentioned "comment" "s/$I90/&\\
    %% i11[\"#11 old label\"] was moved/"
mentioned "hyphenated ID" "s/$I90/&\\
    lane-i11[\"Lane note\"]/"
mentioned "punctuated IDs" 's/^    i90\["#90 Other tracker work"\]$/&\
    lane.i11["Lane note"] --> a\&i11["Joined note"]/'
mentioned "front matter" 's/^flowchart LR$/---\
title: Reader i11(x)\
---\
&/'
mentioned "unquoted edge text" "s/$I90/&\\
    i90 -- after i11 (reader) --> i13/"
mentioned "edge text with a shape" "s/$I90/&\\
    i90 -- after i11[x] --> i13/"
mentioned "pipe edge text" "s/$I90/&\\
    i90 -->|after i11>x| i13/"
mentioned "subgraph title" 's/^    subgraph spine\["Spine work"\]$/    subgraph spine [Spine for i11>x]/'
mentioned "accTitle and accDescr" 's/^flowchart LR$/&\
    accTitle: chart for i11[Reader]\
    accDescr: i11[Reader] waits on i10\
    accDescr {\
    i11[Reader] waits\
    }/'
mentioned "quoted label" "s/$I90/    i90[\"#90 see i11[Reader]\"]/"
mentioned "multi-line Markdown string" 's/^    i90\["#90 Other tracker work"\]$/    i90["`#90 Other\
    i11[Reader] follows`"]/'

CASE="closed tracker is refused"
tracker "$TMP/lane-open.md" CLOSED
run --repo "$REPO" --issue 1
want_rc 2; want_err "closed"

CASE="text not on the shared format is refused"
body plain $'## Status\n\nNothing here.\n'
tracker "$TMP/plain.md"
run --repo "$REPO" --issue 1
want_rc 2; want_err "shared tracker format"

CASE="unreadable unit issue is a lookup failure"
tracker "$TMP/lane-open.md"; rm "$FIX/issue/acme~app~13.json"
run --repo "$REPO" --issue 1
want_rc 4; want_err "issue acme/app#13"

# --- flat fixture, CRLF, bold-lead Dependencies, comment tracker -------------
flat() { # flat <i20 brackets> <tick20> <class line> <bullet>
  { cat <<EOF
**Flat tracker.** No lanes.

## Status

\`\`\`mermaid
flowchart LR
  i20$1"#20 First step"$(rev_br "$1")
  i21["#21 Second step"]
  i20 --> i21
  classDef startable stroke:#15803d,stroke-width:3px
$3\`\`\`

$LEGEND

- **Startable now:** $4.

## Units

- [$2] #20
- [ ] #21
EOF
  } | sed 's/$/\r/'
}
flat '[' ' ' '' 'every open unit waits on #20' >"$TMP/flat.md"
issue acme/app 20 CLOSED COMPLETED "$TMP/dep-none.md"
issue acme/app 21 OPEN "" "$TMP/dep-lead-20.md"

CASE="flat tracker with CRLF gains a startable line"
tracker "$TMP/flat.md"
run --repo "$REPO" --issue 1
flat '[[' x '  class i21 startable
' '#21' >"$TMP/want.md"
want_rc 0; want_out "$TMP/want.md"

CASE="flat tracker second run changes nothing"
retracker
run --repo "$REPO" --issue 1
want_rc 0; want_out "$TMP/want.md"; want_err "OK unchanged"

CASE="comment tracker is refreshed like a body"
tracker "$TMP/lane-open.md"
jq -n --rawfile b "$TMP/flat.md" \
  '{issue_url:"https://api.github.invalid/repos/acme/app/issues/1", body:$b}' \
  >"$FIX/comment/777.json"
run --repo "$REPO" --issue 1 --comment 777
want_rc 0; want_out "$TMP/want.md"; want_call "api --hostname github.invalid repos/acme/app/issues/comments/777"

CASE="comment on another issue is refused"
jq -n --rawfile b "$TMP/flat.md" \
  '{issue_url:"https://api.github.invalid/repos/acme/app/issues/2", body:$b}' \
  >"$FIX/comment/778.json"
run --repo "$REPO" --issue 1 --comment 778
want_rc 2; want_err "not on tracker #1"

echo "test-merge-cleanup-refresh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
