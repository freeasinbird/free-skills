#!/usr/bin/env bash
# tracker-write.sh: write the merge-time refresh of one tracker on the shared
# tracker format, so an agent never composes the whole-body overwrite itself.
# It runs tracker-refresh.sh, writes its output only when that run succeeded
# and the tracker text has not changed since this command first read it, then
# reruns the refresh to verify the write.
#
# Usage:
#   tracker-write.sh --repo host/owner/name --issue N [--comment ID]
#     [--edited FILE --base REFRESH]
#   tracker-write.sh --help
#
# Without --comment it writes the issue body; with it, that one comment on the
# issue. The sequence:
#   1. Read the tracker text.
#   2. Run tracker-refresh.sh with the same --repo, --issue, and --comment. On
#      a non-zero exit, empty stdout, or a stderr line that does not begin
#      `tracker-refresh.sh: OK `, write nothing.
#   3. Take the refresh output as the text to write. With --edited, take FILE
#      instead, for a project's own Startable now rule. REFRESH is the
#      unedited tracker-refresh.sh output FILE was made from; when it differs
#      from this run's refresh output, an input changed since FILE was made,
#      and nothing is written. FILE must have the refresh output's line count
#      and may differ from it only on the `class ... startable` chart line
#      and the **Startable now** bullet. Anything else, including an empty
#      FILE, is refused. The text written is the refresh output with those
#      two lines taken from FILE, so a final newline an editor adds changes
#      nothing.
#   4. When the tracker already holds that text, write nothing.
#   5. Reread the tracker right before the write. When it differs from the
#      first read, write nothing.
#   6. Write with `gh issue edit --body-file` or a PATCH of the comment body.
#   7. Reread the tracker and rerun the refresh. The write is verified when the
#      tracker holds the text written and the rerun prints the same refresh
#      output, with `OK unchanged` when --edited is absent.
#
# GitHub updates are unconditional, so an edit that lands between step 5 and
# step 6 is still overwritten; the forge's edit history is the recovery path.
#
# Stderr carries the refresh's status line and any reason for stopping.
# Stdout is one result line whose fields name the reconciliation ledger's
# guard, attempt, verify, and recheck values, `none` where no row applies:
#   tracker-write.sh: RESULT <result> guard=<complete|unavailable>
#     attempt=<none|accepted|failed> verify=<none|changed|failed|unknown>
#     recheck=<none|fresh|changed|unverifiable>
# (printed on one line). Results and exit codes:
#   0   noop (already current) or written (write verified)
#   2   refused: the refresh exited other than 0 or 4 (2 is its STOP),
#       printed nothing, or reported no OK line, or FILE changes more than
#       the startable lines
#   3   changed-since-read: the tracker changed before the write, or the
#       refresh output no longer matches REFRESH
#   4   lookup-failed: a tracker read failed, in this command or the refresh
#   5   write-failed (the write call failed) or unverified (it exited 0, but
#       the reread or the rerun does not confirm it)
#   64  usage on stderr
#   69  gh, awk, cmp, or tracker-refresh.sh missing; no result line
# Exit 64 and 69 print no result line and make no gh call.
#
# TRACKER_REFRESH_SCRIPT overrides the sibling tracker-refresh.sh, for tests.
# Runs under bash 3.2 (macOS /bin/bash) and BWK awk, as well as newer bash.
set -u

ISSUE="" REPO_SPEC="" COMMENT="" EDITED="" BASE=""

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

case "${1:-}" in
  --help|-h) [ $# -eq 1 ] || usage; sed -n '2,/^set -u$/p' "$0" | sed '$d'; exit 0 ;;
esac

while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --repo|--issue|--comment|--edited|--base) ;;
    *) echo "tracker-write.sh: unknown option: $opt" >&2; usage ;;
  esac
  [ $# -ge 2 ] || { echo "tracker-write.sh: $opt requires a value" >&2; usage; }
  val="$2"; shift 2
  # An unset variable passed as a value must not drop the flag silently.
  [ -n "$val" ] || { echo "tracker-write.sh: $opt requires a non-empty value" >&2; usage; }
  case "$opt" in
    --repo) REPO_SPEC="$val" ;;
    --issue) ISSUE="$val" ;;
    --comment) COMMENT="$val" ;;
    --edited) EDITED="$val" ;;
    --base) BASE="$val" ;;
  esac
done

[ -n "$REPO_SPEC" ] && [ -n "$ISSUE" ] || usage
case "$ISSUE" in ''|*[!0-9]*|0*)
  echo "tracker-write.sh: --issue must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$COMMENT" in
  '') ;;
  *[!0-9]*|0*)
    echo "tracker-write.sh: --comment must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$REPO_SPEC" in
  */*/*/*|*[!A-Za-z0-9._/-]*)
    echo "tracker-write.sh: --repo must be host/owner/name" >&2; usage ;;
  ?*/?*/?*) ;;
  *) echo "tracker-write.sh: --repo must be host/owner/name" >&2; usage ;;
esac
FORGE_HOST="${REPO_SPEC%%/*}"
REPO="${REPO_SPEC#*/}"
case "$FORGE_HOST" in
  ''|*[!A-Za-z0-9.-]*|.*|-*|*..*|*.-*|*-.|*.)
    echo "tracker-write.sh: --repo has an invalid host" >&2; usage ;;
esac
if [ -n "$EDITED" ] || [ -n "$BASE" ]; then
  [ -n "$EDITED" ] && [ -n "$BASE" ] \
    || { echo "tracker-write.sh: --edited and --base go together" >&2; usage; }
  for f in "$EDITED" "$BASE"; do
    [ -f "$f" ] && [ -r "$f" ] || { echo "tracker-write.sh: not a readable file: $f" >&2; usage; }
  done
fi

for tool in gh awk cmp; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "tracker-write.sh: $tool not found on PATH" >&2
    exit 69
  }
done
REFRESH="${TRACKER_REFRESH_SCRIPT:-$(dirname "$0")/tracker-refresh.sh}"
[ -f "$REFRESH" ] && [ -r "$REFRESH" ] || {
  echo "tracker-write.sh: tracker-refresh.sh not found: $REFRESH" >&2
  exit 69
}

TMPD=$(mktemp -d) || { echo "tracker-write.sh: mktemp failed" >&2; exit 69; }
trap 'rm -rf "$TMPD"' EXIT

# result <exit> <result> <guard> <attempt> <verify> <recheck>
result() {
  echo "tracker-write.sh: RESULT $2 guard=$3 attempt=$4 verify=$5 recheck=$6"
  exit "$1"
}
say() { echo "tracker-write.sh: $1" >&2; }

# read_target <file>: save the tracker text as `gh --jq .body` prints it, with
# one newline after the text. Every read uses this, so reads compare bytewise.
read_target() {
  if [ -z "$COMMENT" ]; then
    gh issue view "$ISSUE" --repo "$REPO_SPEC" --json body --jq .body \
      </dev/null >"$1" 2>/dev/null
  else
    gh api --hostname "$FORGE_HOST" "repos/$REPO/issues/comments/$COMMENT" \
      --jq .body </dev/null >"$1" 2>/dev/null
  fi
}

# holds <text-file> <read-file>: whether a read shows exactly that text.
holds() { { cat "$1"; printf '\n'; } | cmp -s - "$2"; }

# refresh <out> <err>: run the refresh; set RRC to its exit code and RSTATUS
# to its stderr status line.
refresh() {
  bash "$REFRESH" --repo "$REPO_SPEC" --issue "$ISSUE" ${COMMENT:+--comment "$COMMENT"} \
    </dev/null >"$1" 2>"$2"
  RRC=$?
  RSTATUS=$(sed -n 1p "$2")
}

# Splice FILE's startable lines into the refresh output. The lines it may
# change are found as tracker-refresh.sh finds them: the first `## Status`
# section, its first mermaid fence, the `class <ids> startable` lines inside
# that fence, and the first **Startable now** bullet after the fence. The
# patterns match tracker-refresh.sh's parse_tracker; keep them in step.
IFS= read -r -d '' SPLICE_PROG <<'AWK' || true
function refuse(msg) { print "tracker-write.sh: --edited refused: " msg > "/dev/stderr"; failed = 1; exit 1 }
function bare(s) { sub(/\r$/, "", s); return s }
function class_line(s,   t) {
  s = bare(s)
  if (s !~ /^[ \t]*class[ \t]+[^ \t]+[ \t]+[A-Za-z0-9_-]+[ \t]*;?[ \t]*$/) return 0
  t = s; sub(/^[ \t]*class[ \t]+/, "", t); sub(/[ \t]*;?[ \t]*$/, "", t)
  match(t, /[ \t]+/)
  return substr(t, RSTART + RLENGTH) == "startable"
}
function bullet_line(s) { return bare(s) ~ /^- \*\*Startable now:\*\*/ }
function locate(   i, s0, s1, f0, f1) {
  s0 = s1 = f0 = f1 = 0
  for (i = 1; i <= nr; i++) {
    if (bare(R[i]) !~ /^## /) continue
    if (s0 && !s1) s1 = i
    if (!s0 && bare(R[i]) ~ /^## Status[ \t]*$/) s0 = i
  }
  if (!s0) refuse("the refresh output has no ## Status section")
  if (!s1) s1 = nr + 1
  for (i = s0 + 1; i < s1; i++) {
    if (!f0) { if (bare(R[i]) ~ /^[ \t]*```[ \t]*mermaid[ \t]*$/) f0 = i; continue }
    if (bare(R[i]) ~ /^[ \t]*```[ \t]*$/) { f1 = i; break }
  }
  if (!f1) refuse("the refresh output has no mermaid chart under ## Status")
  for (i = f0 + 1; i < f1; i++) if (class_line(R[i])) KIND[i] = "class"
  for (i = f1 + 1; i < s1; i++) if (bullet_line(R[i])) { KIND[i] = "bullet"; break }
}
FNR == NR { nr++; R[nr] = $0; next }
{ nc++; C[nc] = $0 }
END {
  if (failed) exit 1
  if (nc != nr) refuse("FILE has " nc " lines; the refresh output has " nr)
  locate()
  for (i = 1; i <= nr; i++) {
    if (C[i] == R[i]) continue
    if (!(i in KIND))
      refuse("FILE changes line " i ", which is not the startable class line or the Startable now bullet")
    if (KIND[i] == "class" && !class_line(C[i])) refuse("FILE line " i " is not a `class <ids> startable` line")
    if (KIND[i] == "bullet" && !bullet_line(C[i])) refuse("FILE line " i " is not a **Startable now** bullet")
  }
  for (i = 1; i <= nr; i++) printf "%s%s", ((i in KIND) ? C[i] : R[i]), (i < nr || final_nl ? "\n" : "")
}
AWK

# --- read, compute, and guard --------------------------------------------------
read_target "$TMPD/first" || {
  say "LOOKUP_FAILED the tracker text could not be read"
  result 4 lookup-failed unavailable none none none
}

refresh "$TMPD/refresh" "$TMPD/refresh.err"
cat "$TMPD/refresh.err" >&2
case "$RRC" in
  0) ;;
  4) result 4 lookup-failed unavailable none none none ;;
  *) result 2 refused unavailable none none none ;;
esac
[ -s "$TMPD/refresh" ] || { say "refused: the refresh printed nothing"; result 2 refused unavailable none none none; }
case "$RSTATUS" in
  "tracker-refresh.sh: OK "*) ;;
  *) say "refused: the refresh printed no OK status line"; result 2 refused unavailable none none none ;;
esac

if [ -n "$EDITED" ]; then
  cmp -s "$BASE" "$TMPD/refresh" || {
    say "the refresh no longer matches --base; rerun tracker-refresh.sh and reapply the rule"
    result 3 changed-since-read complete none none none
  }
  # The refresh output's last line has a newline only when the body's does.
  final_nl=0
  [ -z "$(tail -c 1 "$TMPD/refresh")" ] && final_nl=1
  awk -v final_nl="$final_nl" "$SPLICE_PROG" "$TMPD/refresh" "$EDITED" >"$TMPD/write" \
    || result 2 refused unavailable none none none
else
  cp "$TMPD/refresh" "$TMPD/write"
fi

holds "$TMPD/write" "$TMPD/first" && result 0 noop complete none none none

read_target "$TMPD/guard" || {
  say "LOOKUP_FAILED the tracker text could not be reread before the write"
  result 4 lookup-failed unavailable none none none
}
cmp -s "$TMPD/first" "$TMPD/guard" || {
  say "the tracker changed since it was read; nothing was written"
  result 3 changed-since-read complete none none none
}

# --- write -----------------------------------------------------------------------
if [ -z "$COMMENT" ]; then
  gh issue edit "$ISSUE" --repo "$REPO_SPEC" --body-file "$TMPD/write" \
    </dev/null >/dev/null 2>"$TMPD/write.err"
else
  gh api --hostname "$FORGE_HOST" -X PATCH "repos/$REPO/issues/comments/$COMMENT" \
    -F "body=@$TMPD/write" </dev/null >/dev/null 2>"$TMPD/write.err"
fi
WRC=$?
attempt=accepted
[ "$WRC" -eq 0 ] || { attempt=failed; say "the write call exited $WRC: $(sed -n 1p "$TMPD/write.err")"; }

# --- verify ----------------------------------------------------------------------
if ! read_target "$TMPD/after"; then verify=unknown
elif holds "$TMPD/write" "$TMPD/after"; then verify=changed
elif cmp -s "$TMPD/first" "$TMPD/after"; then verify=failed
else verify=unknown
fi

refresh "$TMPD/rerun" "$TMPD/rerun.err"
if [ "$RRC" -ne 0 ]; then recheck=unverifiable
else
  case "$RSTATUS" in
    "tracker-refresh.sh: OK unchanged"*) recheck=fresh ;;
    "tracker-refresh.sh: OK changed"*) [ -n "$EDITED" ] && recheck=fresh || recheck=changed ;;
    *) recheck=unverifiable ;;
  esac
  [ "$recheck" = fresh ] && ! cmp -s "$TMPD/refresh" "$TMPD/rerun" && recheck=changed
fi
[ "$recheck" = fresh ] || say "rerun: ${RSTATUS:-exit $RRC}"

if [ "$attempt" = failed ]; then
  result 5 write-failed complete "$attempt" "$verify" "$recheck"
fi
if [ "$verify" = changed ] && [ "$recheck" = fresh ]; then
  result 0 written complete "$attempt" "$verify" "$recheck"
fi
say "the write is not verified: the tracker reread is $verify and the rerun is $recheck"
result 5 unverified complete "$attempt" "$verify" "$recheck"
