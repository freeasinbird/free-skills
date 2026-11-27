#!/usr/bin/env bash
# land.sh: the landing engine of the land-approved-prs skill, its guarded
# merge sequence. It ends at the merge; post-merge cleanup belongs to the
# merge-cleanup skill. The skill's prose owns the judgment (which PRs are
# ready, whether one still holds, what to do when a guard
# fires); this script owns the mechanics, so no agent re-derives quoting,
# encoding, or parsing rules at runtime. Every forge- or git-sourced value
# stays in a shell variable and reaches commands through argv, behind an
# option terminator wherever the command takes a positional name; nothing
# here re-parses a value through a shell.
#
# Usage:
#   land.sh check   --pr N --repo owner/name
#   land.sh land    --pr N --repo owner/name --head <40-hex-oid>
#   land.sh merge   --pr N --repo owner/name --head <40-hex-oid>
#   land.sh rerun   --pr N --repo owner/name --head <40-hex-oid>
#   land.sh prepare --pr N --repo owner/name --head <40-hex-oid> --onto <40-hex-oid>
#                   [--worktree <path>]   # record a resolved conflict worktree
#   land.sh drop    --pr N --repo owner/name --worktree <path>
#     [--base-remote NAME]   # override remote resolution for the base repo
#     [--head-remote NAME]   # override remote resolution for the head repo
#     [--interval 10]        # land/merge/rerun: seconds between polls
#     [--cap-minutes 15]     # land/merge: total wait for MERGED
#     [--ci-cap-minutes 30]  # land: total wait for CI on the head; rerun:
#                            # each of its two waits
#     [--dry-run]            # land phase only: report, never rebase or merge
#     [--prepared <oid>]     # land phase only, not with --dry-run: the
#                            # prepare result to reuse when the head is
#                            # rebased
#
# Run each phase from the base-branch checkout, the one merge-cleanup will
# later rewrite. --repo is required, never defaulted: a bare PR number
# resolves against the CLI's default repository, which in a fork clone can
# act on a different PR entirely.
#
# check    Pre-merge guards: PR open, no head/base name collision, clean
#          workspace, no git operation in progress, no competing worktree
#          layout, no open PR sharing the head branch, and a merge queue's
#          method identified as merge-commit before anything is enqueued.
#          Prints the verified head OID the later phases pin and the open
#          PRs stacked on the head branch, which every phase reports
#          rather than refuses unless the head is cross-repository.
# land     One round of the landing procedure for a base without branch
#          protection: fetch the base. When the head is not on its tip,
#          rebase it, lease-push it against --head, and STOP rebased with
#          the new head: its range-diff needs reading before check and land
#          run again with it. On the tip, wait for CI on the exact head
#          commit, refuse if the forge's base tip moved since the fetch,
#          then run merge. A refusal is a STOP; rerunning land is the retry.
# merge    Merges pinned to --head with an explicit title-only message,
#          then polls until the forge reports the PR MERGED (a zero exit
#          from the merge command proves enqueueing, not merging).
# rerun    Reruns the failed jobs of the head's failed GitHub Actions runs
#          once, after land stopped checks-failed. Waits for every workflow
#          run on --head to finish (GitHub refuses to rerun a running one),
#          refuses when a failure is not an Actions job or its run was
#          already rerun, and reruns only the runs that own a failing
#          latest check run. It then waits until the rerun jobs replace the
#          failed check runs, so the next land reads the new attempt rather
#          than the old failure. It never merges.
# prepare  Rebases a copy of the head onto --onto, the pushed head of the
#          PR landing before this one, while that PR waits on CI. --onto
#          must contain the fetched base tip. The rebase runs in a
#          temporary detached worktree under the land-wt template, marked
#          for this PR. prepare never moves an existing local branch, never
#          pushes, never writes to the forge, and never touches the
#          checkout it runs from. A missing local head branch is created at
#          --head, only when the fetched head branch is that commit. A
#          clean rebase removes the worktree, prints the range-diff to
#          stderr, and reports prepared_oid and its tree. A conflict keeps
#          the worktree with the rebase paused and stops rebase-conflict
#          with its "worktree" and "conflicts", for the caller to resolve
#          there and finish with git rebase --continue. prepare --worktree
#          then records that worktree's HEAD as the prepared commit, after
#          checking its marker names this PR, --head, and --onto, and that
#          no rebase is paused. A clean prepare and a recorded worktree
#          write --head and the prepared commit to refs/land/prepared/<pr>/
#          head and commit; a prepare run that passes its checks deletes
#          both before it rebases, so only the latest preparation can be
#          used. Every result after a branch
#          was created carries "created_branch".
# drop     Removes a worktree prepare made for --pr: a registered, detached
#          worktree at <dir>/land-wt.XXXXXX/wt whose directory holds
#          prepare's marker naming this PR. Anything else stops
#          not-prepared and nothing is removed. It reads nothing from the
#          forge.
#
# land --prepared reads and deletes both refs, and ignores the preparation
# unless they are --head and --prepared: a conflict replay matches commits
# by author, date, and message, which an amend keeps, so an older head's
# preparation would otherwise land that head's content. It also reuses a
# preparation only when the fetched base tip has
# the tree of the prepared commit's base (its merge base with the tip). That
# check is what makes the reuse safe: the predecessor's merge commit of an
# up-to-date head has that head's tree, while a base that moved by more than
# that merge has another tree, and replaying a prepared tree onto it would
# silently revert the extra changes. A preparation that fails the check, or
# whose commit is gone, is ignored and land behaves as without it. When it
# is used: a clean rebase whose tree equals the prepared tree goes on to CI
# and the merge in the same run, and one whose tree differs stops rebased
# with "prepared":"tree-mismatch". At each conflict the rebase takes the
# matching prepared commit's tree, matched by position and by author, date,
# and message, after the state before that pick matched too. Any mismatch,
# a different commit count, or a final tree other than the prepared tree
# aborts, pushes nothing, and stops rebase-conflict. Every result printed
# after a --prepared run's push carries "pushed_head" and "old_head_oid".
# land prints "land.sh: waiting for CI on <oid>" to stderr when the CI wait
# starts. land and merge append the PR number to
# <git-common-dir>/land-approved-prs/cleanup-pending once the forge reports
# the merge; list-ready.sh reports and clears that file. A failed write adds
# "cleanup_recorded":false to the OK line rather than change the result.
#
# Last line on stdout is the machine-readable result:
#   OK <phase> <json>            phase completed; json carries the facts
#   STOP <guard> <json>          a guard fired: surface it, never work
#                                around it; the guard names are stable
#   LOOKUP_FAILED <what> <json>  a read failed; unknown is not absence, so
#                                nothing was decided from the empty result;
#                                a failed forge read or git fetch adds
#                                "stderr", the first 300 bytes of the tool's
#                                error output; both retry transient failures
# STOP checks-failed carries "failed", one entry per failed check:
# {name, run_id, job_id, url}. An entry for a GitHub Actions job also
# carries "failing_tests", up to 20 {name, line} objects read from the
# job's Go test output ("line" is the test's first _test.go:N: line, at
# most 300 bytes, absent when the log has none), plus
# "failing_tests_omitted" when more tests failed. When the log can't be
# fetched or names no Go test failure, the entry carries "log_error"
# instead. A log never changes the result type or exit code.
# Exit codes: 0 OK; 2 STOP; 4 LOOKUP_FAILED; 64 usage error; 69 gh
# (GitHub CLI) not found on PATH.
set -u

PHASE="" PR="" REPO="" HEAD_OID="" BASE_REMOTE_OPT="" HEAD_REMOTE_OPT=""
INTERVAL=10 CAP_MINUTES=15 CI_CAP_MINUTES=30 DRY_RUN=false
ONTO="" PREPARED="" DROP_WT="" HAVE_DROP_WT=false CREATED_BRANCH=false
# Set once a --prepared run has pushed, so every later result names the
# head it pushed and the one it replaced.
PUSHED_HEAD="" OLD_HEAD=""

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

case "${1:-}" in
  check|land|merge|rerun|prepare|drop) PHASE="$1"; shift ;;
  *) echo "land.sh: first argument must be check, land, merge, rerun, prepare, or drop" >&2; usage ;;
esac

# Recognize the option, then require its value, before reading $2: a
# trailing bare option must die as a usage error, not a set -u crash.
while [ $# -gt 0 ]; do
  opt="$1"
  # The one boolean flag. Land-only, so a mistyped `merge --dry-run` is a
  # usage error rather than a real merge.
  if [ "$opt" = --dry-run ]; then
    [ "$PHASE" = land ] || { echo "land.sh: --dry-run applies only to land" >&2; usage; }
    DRY_RUN=true; shift; continue
  fi
  case "$opt" in
    --pr|--repo|--head|--base-remote|--head-remote|--interval|--cap-minutes|--ci-cap-minutes) ;;
    # Phase-bound options refuse every other phase, so a mistyped phase
    # never runs without the option the caller meant.
    --onto) [ "$PHASE" = prepare ] || { echo "land.sh: --onto applies only to prepare" >&2; usage; } ;;
    --prepared) [ "$PHASE" = land ] || { echo "land.sh: --prepared applies only to land" >&2; usage; } ;;
    --worktree) case "$PHASE" in drop|prepare) ;; *) echo "land.sh: --worktree applies only to drop and prepare" >&2; usage ;; esac ;;
    *) echo "land.sh: unknown option: $opt" >&2; usage ;;
  esac
  [ $# -ge 2 ] || { echo "land.sh: $opt requires a value" >&2; usage; }
  val="$2"; shift 2
  case "$opt" in
    --pr) PR="$val" ;;
    --repo) REPO="$val" ;;
    --head) HEAD_OID="$val" ;;
    --onto) ONTO="$val" ;;
    --prepared) PREPARED="$val" ;;
    --worktree) DROP_WT="$val" HAVE_DROP_WT=true ;;
    --base-remote) BASE_REMOTE_OPT="$val" ;;
    --head-remote) HEAD_REMOTE_OPT="$val" ;;
    --interval) INTERVAL="$val" ;;
    --cap-minutes) CAP_MINUTES="$val" ;;
    --ci-cap-minutes) CI_CAP_MINUTES="$val" ;;
  esac
done

[ -n "$PR" ] && [ -n "$REPO" ] || usage
case "$PR" in ''|*[!0-9]*|0*)
  echo "land.sh: --pr must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$REPO" in
  */*/*|*[!A-Za-z0-9._/-]*) echo "land.sh: --repo must be owner/name" >&2; usage ;;
  ?*/?*) ;;
  *) echo "land.sh: --repo must be owner/name" >&2; usage ;;
esac
full_oid() { # full_oid <option> <value>: prints the lowercased 40-hex OID
  local v
  v=$(printf '%s' "$2" | tr 'A-F' 'a-f')
  case "$v" in *[!0-9a-f]*|'')
    echo "land.sh: $1 must be a full 40-hex commit OID" >&2; usage ;;
  esac
  [ "${#v}" -eq 40 ] || { echo "land.sh: $1 must be a full 40-hex commit OID" >&2; usage; }
  printf '%s' "$v"
}
case "$PHASE" in
  land|merge|rerun|prepare)
    case "$HEAD_OID" in '')
      echo "land.sh: --head must be the full 40-hex verified head OID" >&2; usage ;;
    esac
    HEAD_OID=$(full_oid --head "$HEAD_OID") || exit 64 ;;
esac
if [ "$PHASE" = prepare ]; then
  [ -n "$ONTO" ] || { echo "land.sh: prepare requires --onto, the pushed head it prepares onto" >&2; usage; }
  ONTO=$(full_oid --onto "$ONTO") || exit 64
fi
if [ -n "$PREPARED" ]; then
  [ "$DRY_RUN" = false ] || { echo "land.sh: --prepared and --dry-run are exclusive" >&2; usage; }
  PREPARED=$(full_oid --prepared "$PREPARED") || exit 64
fi
if [ "$PHASE" = drop ] && { [ "$HAVE_DROP_WT" = false ] || [ -z "$DROP_WT" ]; }; then
  echo "land.sh: drop requires --worktree, the path prepare reported" >&2; usage
fi
if [ "$PHASE" = prepare ] && [ "$HAVE_DROP_WT" = true ] && [ -z "$DROP_WT" ]; then
  echo "land.sh: prepare --worktree requires the path prepare reported" >&2; usage
fi
case "$INTERVAL" in ''|0|0*|*[!0-9]*)
  echo "land.sh: --interval must be a positive integer without leading zeros (seconds)" >&2; usage ;;
esac
case "$CAP_MINUTES" in ''|0?*|*[!0-9]*)
  echo "land.sh: --cap-minutes must be a non-negative integer without leading zeros" >&2; usage ;;
esac
# Keep later arithmetic inside a signed 32-bit range on every supported Bash.
# These limits are far beyond a useful interactive wait while rejecting values
# that could wrap only after the irreversible merge command has run.
[ "${#INTERVAL}" -le 9 ] || {
  echo "land.sh: --interval must be at most 999999999 seconds" >&2; usage
}
[ "${#CAP_MINUTES}" -le 7 ] || {
  echo "land.sh: --cap-minutes must be at most 9999999" >&2; usage
}
case "$CI_CAP_MINUTES" in ''|0?*|*[!0-9]*)
  echo "land.sh: --ci-cap-minutes must be a non-negative integer without leading zeros" >&2; usage ;;
esac
[ "${#CI_CAP_MINUTES}" -le 7 ] || {
  echo "land.sh: --ci-cap-minutes must be at most 9999999" >&2; usage
}
# Remote-name overrides: a leading hyphen would read as an option to git
# even behind our own parsing, and every use below passes them as
# positionals, so refuse the shape outright rather than trusting quoting.
for rn in "$BASE_REMOTE_OPT" "$HEAD_REMOTE_OPT"; do
  case "$rn" in -*)
    echo "land.sh: remote names must not begin with a hyphen" >&2; usage ;;
  esac
done

command -v gh >/dev/null 2>&1 || {
  echo "land.sh: gh (GitHub CLI) not found on PATH; stop and hand off unless another authenticated PR-host CLI can perform every required forge check" >&2
  exit 69
}

# --- reporting -------------------------------------------------------------

# Byte-wise escaper for report payloads. Not awk or sed: record splitting
# cannot represent a trailing newline, and the worktree path this
# serializes is exactly the kind of value the parser upstream is hardened
# to carry faithfully. Printable ASCII passes through; every other byte,
# control and high alike, encodes as \u00XX, so the emitted line is always
# valid UTF-8 JSON and the string's code points are the value's bytes
# (recover them by mapping code points 0-255 back to bytes). Raw high
# bytes must not pass through: a path byte outside UTF-8 would make the
# report unparseable, and a parser that substitutes U+FFFD loses the path.
json_escape() {
  local LC_ALL=C s="$1" out="" c i o
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      \\) out+='\\' ;;
      \") out+='\"' ;;
      $'\n') out+='\n' ;;
      $'\t') out+='\t' ;;
      $'\r') out+='\r' ;;
      # Printable ASCII skips the fork below: a job's failing tests run
      # to thousands of bytes, and a fork per byte costs seconds.
      [\ -~]) out+="$c" ;;
      *)
        o=$(( $(printf '%d' "'$c") & 255 ))
        if [ "$o" -ge 32 ] && [ "$o" -le 126 ]; then
          out+="$c"
        else
          out+=$(printf '\\u%04x' "$o")
        fi ;;
    esac
  done
  printf '%s' "$out"
}

# Capture stdout byte-faithfully except the final terminator: a bare $( )
# strips every trailing newline, erasing the byte that distinguishes a
# newline-ending value from its newline-less sibling.
out_exact() { # out_exact <var> <cmd...>: fails when the command fails
  local __v="$1"; shift
  local __o
  __o=$("$@" 2>/dev/null && printf x) || return 1
  __o="${__o%x}"
  printf -v "$__v" '%s' "${__o%$'\n'}"
}

physical_dir() { # physical_dir <path>
  cd -P -- "$1" 2>/dev/null || return 1
  pwd -P
}

# Reject a remote whose configured URLs carry a newline: every listing of
# them is line-based, so the distinguishing byte cannot survive any
# comparison, and a stripped comparison would accept a split destination.
# The raw config is read NUL-separated, so this test itself is
# byte-faithful.
remote_urls_newline_free() { # remote_urls_newline_free <remote>
  local raw
  raw=$(git config --null --get-all "remote.$1.url" 2>/dev/null; printf x)
  raw="$raw$(git config --null --get-all "remote.$1.pushurl" 2>/dev/null; printf x)"
  case "$raw" in *$'\n'*) return 1 ;; esac
  return 0
}
# After a --prepared run's push, every result names the pushed head, so the
# caller can record it with list-ready.sh --pushed before acting on a stop.
# After prepare creates a local branch, every later result says so, so the
# caller can delete the branch when it hands the PR back.
pushed_fields() {
  [ -z "$PUSHED_HEAD" ] || printf ',"pushed_head":"%s","old_head_oid":"%s"' "$PUSHED_HEAD" "$OLD_HEAD"
  [ "$CREATED_BRANCH" != true ] || printf ',"created_branch":true'
}
stop() { # stop <guard> <detail>
  echo "STOP $1 {\"detail\":\"$(json_escape "$2")\"$(pushed_fields)}"
  exit 2
}
# checks-failed also names each failed check, so the agent can fetch a
# failed job's log without searching for it, and for a GitHub Actions job
# it names the failing Go tests read from that log (job_log_fields).
# CI_FAILED_ENTRIES and CI_FAILED_ENTRY_JOBS are ci_read's.
stop_failed() { # stop_failed <detail>
  local i entry failed=""
  for (( i = 0; i < ${#CI_FAILED_ENTRIES[@]}; i++ )); do
    entry="${CI_FAILED_ENTRIES[i]}"
    if [ "${CI_FAILED_ENTRY_JOBS[i]}" != - ]; then
      job_log_fields "${CI_FAILED_ENTRY_JOBS[i]}"
      # gh's tojson built the entry, so it ends in the object's own brace.
      entry="${entry%\}}$LOG_FIELDS}"
    fi
    failed+=",$entry"
  done
  echo "STOP checks-failed {\"detail\":\"$(json_escape "$1")\",\"failed\":[${failed#,}]$(pushed_fields)}"
  exit 2
}

# Read one GitHub Actions job's log and set LOG_FIELDS to the JSON members
# stop_failed appends to its entry: ,"failing_tests":[{name, line}, ...],
# plus ,"failing_tests_omitted":N when more than FAILING_TESTS_CAP tests
# failed; or ,"log_error":"<why>" when the log can't be fetched or names no
# Go test failure. "line" is the test's first _test.go:N: line, absent
# when the log has none (a parent whose subtests failed). Every string is
# cut to FAILURE_LINE_CAP bytes and goes through json_escape, so a log
# can't break the one-line result. A failure here never becomes
# LOOKUP_FAILED: the checks failed whatever the log says, and the agent
# can still read the log itself.
FAILING_TESTS_CAP=20 FAILURE_LINE_CAP=300
job_log_fields() { # job_log_fields <job-id>
  local why parsed total name line tests="" n=0
  if ! gh_read api --allow-escape-sequences "repos/$REPO/actions/jobs/$1/logs" >"$GH_LOG"; then
    why=$(tr -d '\0' < "$GH_ERR" | head -n 1 | head -c 300)
    LOG_FIELDS=",\"log_error\":\"$(json_escape "could not fetch the job log: ${why:-gh exited nonzero}")\""
    return
  fi
  if ! parsed=$(LC_ALL=C tr -d '\0' < "$GH_LOG" \
      | LC_ALL=C awk -v esc=$'\033' -v bom=$'\357\273\277' \
          -v max="$FAILING_TESTS_CAP" -v cap="$FAILURE_LINE_CAP" "$GO_FAILURES_AWK"); then
    LOG_FIELDS=",\"log_error\":\"could not parse the job log\""
    return
  fi
  {
    IFS= read -r total
    while IFS= read -r name && IFS= read -r line; do
      tests+=",{\"name\":\"$(json_escape "$name")\""
      [ "$line" = - ] || tests+=",\"line\":\"$(json_escape "${line#L}")\""
      tests+="}"
      n=$((n + 1))
    done
  } <<< "$parsed"
  if [ "$n" -eq 0 ]; then
    LOG_FIELDS=",\"log_error\":\"no Go test failure found in the log\""
    return
  fi
  LOG_FIELDS=",\"failing_tests\":[${tests#,}]"
  [ "$total" -le "$n" ] || LOG_FIELDS+=",\"failing_tests_omitted\":$((total - n))"
}

# The job-log parser. Input: a GitHub Actions job log, NUL bytes removed.
# Output: the number of distinct failed tests, then for each of the first
# max of them two lines: its name, then "L" and its first failure line, or
# "-" when it has none. Both values are cut to cap bytes and hold no
# newline, so the pairs read back unambiguously.
#
# Each line first loses the log's BOM, its timestamp, a trailing CR, and
# ANSI escape sequences. go test -json events (lines starting with "{")
# name a failed test by an "Action":"fail" event that carries "Test"; a
# package-level fail event has none. Its failure line is the first output
# event for the same package and test that holds a _test.go:N: line. When
# the log has no such fail event, plain output is read in both orders Go
# prints: with -v the failure line streams under "=== RUN", "=== CONT",
# or "=== NAME <test>" before "--- FAIL: <test>"; without -v it follows
# "--- FAIL: <test>", indented, before the next marker or unindented line.
# A subtest counts as its own test. POSIX awk only: CI runs mawk or gawk,
# and macOS runs BSD awk.
GO_FAILURES_AWK='
function unescape(s,    out, p, c, h, code, i) {
  out = ""
  while ((p = index(s, "\\")) > 0) {
    out = out substr(s, 1, p - 1)
    c = substr(s, p + 1, 1)
    if (c == "n") out = out "\n"
    else if (c == "t") out = out "\t"
    else if (c == "r") out = out "\r"
    else if (c == "b") out = out sprintf("%c", 8)
    else if (c == "f") out = out sprintf("%c", 12)
    else if (c == "u") {
      h = tolower(substr(s, p + 2, 4))
      code = 0
      for (i = 1; i <= 4; i++) code = code * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
      # Decode ASCII only; any other code point stays as escaped text.
      if (h ~ /^[0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/ && code > 0 && code < 128) {
        out = out sprintf("%c", code)
        s = substr(s, p + 6)
        continue
      }
      out = out "\\u"
    } else out = out c
    s = substr(s, p + 2)
  }
  return out s
}
# The raw, still-escaped string value of "key" in one JSON event line.
function jraw(s, key) {
  if (!match(s, "\"" key "\":\"([^\"\\\\]|\\\\.)*\"")) return ""
  return substr(s, RSTART + length(key) + 4, RLENGTH - length(key) - 5)
}
function emit(name, line, has,    p) {
  gsub(/[\r\n]/, " ", name)
  print substr(name, 1, cap)
  if (!has) { print "-"; return }
  gsub(csi, "", line)
  if ((p = index(line, "\n")) > 0) line = substr(line, 1, p - 1)
  if ((p = index(line, "\r")) > 0) line = substr(line, 1, p - 1)
  sub(/^[ \t]+/, "", line)
  print "L" substr(line, 1, cap)
}
BEGIN { csi = esc "\\[[0-?]*[ -/]*[@-~]"; jn = 0; pn = 0; cur = ""; pending = "" }
{
  l = $0
  if (NR == 1 && index(l, bom) == 1) l = substr(l, length(bom) + 1)
  sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.]*Z ?/, "", l)
  sub(/\r$/, "", l)
  gsub(csi, "", l)
  if (substr(l, 1, 1) == "{") {
    if (index(l, "\"Action\":\"fail\"") > 0) {
      t = jraw(l, "Test")
      if (t != "") {
        k = jraw(l, "Package") SUBSEP t
        if (!(k in jfailed)) { jfailed[k] = 1; jorder[++jn] = k; jname[k] = t }
      }
    } else if (index(l, "\"Action\":\"output\"") > 0 && l ~ /_test\.go:[0-9]+:/) {
      t = jraw(l, "Test")
      o = jraw(l, "Output")
      if (t != "" && o ~ /_test\.go:[0-9]+:/) {
        k = jraw(l, "Package") SUBSEP t
        # 4096 escaped bytes always cover cap decoded bytes after the
        # indent, and keep unescape linear on a huge output line.
        if (!(k in jline)) jline[k] = substr(o, 1, 4096)
      }
    }
    next
  }
  t = l
  sub(/^[ \t]+/, "", t)
  if (pending != "" && t == l) pending = ""
  if (t ~ /^=== (RUN|CONT|NAME) /) {
    cur = t
    sub(/^=== [A-Z]+ +/, "", cur)
    sub(/[ \t]+$/, "", cur)
    pending = ""
    # A new run of a name that has not failed drops a line kept from an
    # earlier run: another package can hold a passing test of that name.
    if (t ~ /^=== RUN / && !(cur in pfailed)) delete pline[cur]
  } else if (substr(t, 1, 10) == "--- FAIL: ") {
    n = substr(t, 11)
    if ((p = index(n, " (")) > 0) n = substr(n, 1, p - 1)
    cur = ""
    pending = ""
    if (n != "") {
      if (!(n in pfailed)) { pfailed[n] = 1; porder[++pn] = n }
      if (!(n in pline)) pending = n
    }
  } else if (t ~ /^--- (PASS|SKIP): /) {
    cur = ""
    pending = ""
  } else if (t ~ /_test\.go:[0-9]+:/) {
    if (pending != "") { pline[pending] = t; pending = "" }
    else if (cur != "" && !(cur in pline)) pline[cur] = t
  }
}
END {
  if (jn > 0) {
    print jn
    for (i = 1; i <= jn && i <= max; i++) {
      k = jorder[i]
      if (k in jline) emit(unescape(jname[k]), unescape(jline[k]), 1)
      else emit(unescape(jname[k]), "", 0)
    }
  } else {
    print pn
    for (i = 1; i <= pn && i <= max; i++) {
      n = porder[i]
      if (n in pline) emit(n, pline[n], 1)
      else emit(n, "", 0)
    }
  }
}
'
lookup_failed() { # lookup_failed <what> <detail>
  local excerpt="" extra=""
  [ -s "${GH_ERR:-}" ] && excerpt=$(tr -d '\0' < "$GH_ERR" | head -c 300)
  [ -z "$excerpt" ] || extra=",\"stderr\":\"$(json_escape "$excerpt")\""
  echo "LOOKUP_FAILED $1 {\"detail\":\"$(json_escape "$2")\"$extra$(pushed_fields)}"
  exit 4
}

# Forge reads and git fetches keep their stderr here so lookup_failed can
# quote why a read failed. head, not tail: gh's summary line and git's
# fatal line come first, before any body or hint.
# GH_OUT holds one attempt's output, so a retry never follows a failed
# attempt's partial output (a page of a paginated read, an error body).
GH_ERR=$(mktemp) || lookup_failed tmp "mktemp failed"
GH_OUT=$(mktemp) || { rm -f -- "$GH_ERR"; lookup_failed tmp "mktemp failed"; }
# GH_LOG holds one fetched job log for stop_failed. A log can run to many
# megabytes, so it lives in a file, never in a shell variable.
GH_LOG=$(mktemp) || { rm -f -- "$GH_ERR" "$GH_OUT"; lookup_failed tmp "mktemp failed"; }
trap 'rm -f -- "$GH_ERR" "$GH_OUT" "$GH_LOG"' EXIT
# Go's http2debug trace prints the Authorization header unredacted. Drop
# that one setting and keep any other GODEBUG setting gh may rely on. Go
# turns the trace on when GODEBUG merely contains http2debug=1 or =2, so
# drop every element that mentions it, however it is spaced or nested.
GH_GODEBUG=$(printf '%s' "${GODEBUG:-}" | sed -E 's/(^|,)[^,]*http2debug[^,]*//g; s/^,//')
# Is the failure in GH_ERR an answer rather than a blip? gh exits 1 for
# every failure and names the HTTP status only in its stderr: gh api as
# "gh: Not Found (HTTP 404)", gh pr as "HTTP 401: Bad credentials (url)",
# and a GraphQL lookup of something absent as "GraphQL: Could not resolve
# to ...". GitHub answers a rate limit with a 403 that names it, so that
# 403 is transient.
gh_err_permanent() {
  grep -qi 'rate limit' "$GH_ERR" && return 1
  grep -qE '\(HTTP (401|403|404|422)\)|^HTTP (401|403|404|422):|^GraphQL: Could not resolve to ' "$GH_ERR"
}
# Run one forge read, keeping its stderr only when it fails, so a warning
# from a read that worked can't attach to a later failure. GH_DEBUG is set
# empty, not unset: gh falls back to the legacy DEBUG variable when
# GH_DEBUG is unset, and debug output carries headers and response bodies.
# A transient failure (a timeout, a dropped connection, truncated JSON, a
# 5xx, a rate limit) is retried after 1 s and then 2 s, so one blip
# doesn't end a batch; a permanent one fails at once. Each attempt
# overwrites GH_ERR, so lookup_failed quotes the last. A caller that
# already polls sets GH_READ_ATTEMPTS=1. Writes never come through here.
GH_READ_ATTEMPTS=3
gh_read() {
  local attempt=1 rc line
  while :; do
    GH_DEBUG= GODEBUG="$GH_GODEBUG" gh "$@" >"$GH_OUT" 2>"$GH_ERR" \
      && { : > "$GH_ERR"; cat -- "$GH_OUT"; return; }
    rc=$?
    { [ "$attempt" -lt "$GH_READ_ATTEMPTS" ] && ! gh_err_permanent; } || return "$rc"
    line=$(tr -d '\0' < "$GH_ERR" | head -n 1 | head -c 300)
    echo "${0##*/}: forge read failed (attempt $attempt of $GH_READ_ATTEMPTS): ${line:-gh exited $rc}; retrying in ${attempt}s" >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

# Is the git fetch failure in GH_ERR an answer rather than a blip? These
# are git's messages for a missing branch, a missing or unreadable
# repository (git names an HTTP 404 "repository '<url>' not found"), and
# refused credentials. Anything else (DNS, a refused or
# reset connection, a timeout, early EOF, an HTTP 5xx) is retried, as
# gh_read treats a failure it can't name.
git_fetch_err_permanent() {
  grep -qE "couldn't find remote ref|does not appear to be a git repository|Repository not found|repository '[^']*' not found|Authentication failed|Permission denied|could not read Username|The requested URL returned error: (401|403|404)" "$GH_ERR"
}
# Run one git fetch with gh_read's retry, keeping git's stderr only when
# the fetch fails, so a successful fetch's "From ..." lines can't attach
# to a later failure. Git's trace settings are dropped first: with
# GIT_TRACE or GIT_TRACE_CURL on and GIT_TRACE_REDACT=0, git writes the
# remote URL's userinfo and request headers to stderr, which
# lookup_failed would then quote. Git's own messages don't always hide
# userinfo either (a redirect error prints the asked-for URL whole), so
# everything from a "://" to the last "@" before whitespace is dropped
# from its stderr before anything reads it: a password may hold a raw "/"
# or quote, and a path's "@" costs only the host. If that pass fails, the
# text is dropped. The stderr goes to a file, not a pipe: a pipe waits
# for every process holding it, and an SSH ControlPersist master git
# leaves running can hold it open. Callers pass git fetch's arguments.
git_fetch() {
  local attempt=1 rc line v
  while :; do
    (
      for v in $(compgen -e); do
        case "$v" in GIT_TRACE*|GIT_CURL_VERBOSE) unset "$v" ;; esac
      done
      exec git fetch "$@"
    ) >/dev/null 2>"$GH_ERR"
    rc=$?
    [ "$rc" -ne 0 ] || { : > "$GH_ERR"; return 0; }
    if LC_ALL=C sed -E 's#(://)[^[:space:]]*@#\1#g' "$GH_ERR" > "$GH_OUT"; then
      cat -- "$GH_OUT" > "$GH_ERR"
    else
      : > "$GH_ERR"
    fi
    { [ "$attempt" -lt "$GH_READ_ATTEMPTS" ] && ! git_fetch_err_permanent; } || return "$rc"
    line=$(tr -d '\0' < "$GH_ERR" | head -n 1 | head -c 300)
    echo "${0##*/}: git fetch failed (attempt $attempt of $GH_READ_ATTEMPTS): ${line:-git exited $rc}; retrying in ${attempt}s" >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

# Percent-encode one URL path segment or query value. Forge-sourced branch
# names are parsed as URL syntax by the API client, so a branch legitimately
# named release#1 would otherwise query the rules for release (the #1 reads
# as a fragment), and a ? truncates the same way.
urlencode() {
  # LC_ALL=C makes the slice byte-wise, so multibyte names encode as their
  # UTF-8 bytes rather than mis-encoding a codepoint above 255.
  local LC_ALL=C s="$1" out="" c i
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [A-Za-z0-9.~_-]) out+="$c" ;;
      # Mask to one byte: bash 3.2 (the macOS system shell) sign-extends
      # high bytes through printf %X, which would corrupt every multibyte
      # name into a filter that matches nothing.
      *) out+=$(printf '%%%02X' "$(( $(printf '%d' "'$c") & 255 ))") ;;
    esac
  done
  printf '%s' "$out"
}

# --- drop -------------------------------------------------------------------

# The marker prepare writes beside its worktree. Its "pr: N" line is what
# lets drop tell a preparation for this PR from a land run's own scratch
# worktree, which shares the template.
PREPARE_MARKER=prepare
# The latest preparation's head and commit, which land --prepared requires
# to be --head and --prepared.
PREPARED_HEAD_REF="refs/land/prepared/$PR/head"
PREPARED_COMMIT_REF="refs/land/prepared/$PR/commit"

# Check that <path> is a worktree prepare made for this PR. Sets PW_WT, the
# resolved worktree, and PW_DIR, its land-wt directory; anything else stops
# not-prepared.
prepared_worktree_check() { # prepared_worktree_check <path>
  local wt dir tmp field cand="" detached=false found=false
  # Resolve symlinks first, so every check below and the delete name the
  # same directory.
  out_exact wt physical_dir "$1" \
    || stop not-prepared "$1 is not a directory; nothing changed"
  dir="${wt%/wt}"
  { [ "$dir" != "$wt" ] && [ -n "$dir" ]; } \
    || stop not-prepared "$wt does not end in /wt, so prepare did not make it; nothing changed"
  case "${dir##*/}" in
    land-wt.[[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]]) ;;
    *) stop not-prepared "$wt is not under the land-wt.XXXXXX template, so prepare did not make it; nothing changed" ;;
  esac
  # Registered in this repository and detached: a branch worktree is never
  # a preparation, whatever its path.
  tmp=$(mktemp) || lookup_failed worktree-scan "mktemp failed"
  git worktree list --porcelain -z > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed worktree-scan "git worktree list failed"; }
  while IFS= read -r -d '' field; do
    case "$field" in
      "worktree "*)
        cand="${field#worktree }"
        [ "$cand" -ef "$wt" ] && found=true ;;
      detached) [ "$cand" -ef "$wt" ] && detached=true ;;
    esac
  done < "$tmp"
  rm -f "$tmp"
  [ "$found" = true ] \
    || stop not-prepared "$wt is not a worktree registered in this repository; nothing changed"
  [ "$detached" = true ] \
    || stop not-prepared "$wt has a branch checked out, so prepare did not make it; nothing changed"
  { [ -f "$dir/$PREPARE_MARKER" ] && ! [ -L "$dir/$PREPARE_MARKER" ] \
      && grep -qxF -- "pr: $PR" "$dir/$PREPARE_MARKER"; } \
    || stop not-prepared "$dir carries no prepare marker for PR $PR; nothing changed"
  PW_WT="$wt" PW_DIR="$dir"
}

# drop is the one path that removes a prepared worktree during a batch, so
# it removes only what prepare made for this PR and refuses everything
# else. It needs no forge read, so it runs before the PR facts load, and a
# forge outage can't strand a worktree.
phase_drop() {
  local wt dir
  git rev-parse --git-dir >/dev/null 2>&1 || stop not-a-repo "not inside a git working tree"
  prepared_worktree_check "$DROP_WT"
  wt="$PW_WT" dir="$PW_DIR"
  # The worktree holds a detached checkout of commits already in the object
  # store, plus whatever a paused rebase left, so --force discards nothing
  # that a branch or the forge lacks.
  git worktree remove --force -- "$wt" >/dev/null 2>&1 \
    || stop drop-failed "git could not remove the worktree at $wt; nothing was removed"
  rm -rf -- "$dir" \
    || stop drop-failed "the worktree at $wt is unregistered, but its directory $dir could not be deleted"
  echo "OK drop {\"worktree\":\"$(json_escape "$wt")\"}"
  exit 0
}
[ "$PHASE" != drop ] || phase_drop

# --- PR facts ---------------------------------------------------------------

# Ref names cannot contain whitespace or control characters (git
# check-ref-format), so a tab-separated read is faithful for branch fields;
# the title, which can hold anything, is read separately where needed.
# The ~ sentinel keeps a null field (a deleted fork's owner or repo) from
# collapsing out of the tab-separated read and shifting every later field:
# tabs are IFS whitespace, so consecutive tabs read as one separator.
pr_fields=$(gh_read pr view "$PR" --repo="$REPO" \
  --json state,headRefName,baseRefName,headRefOid,isCrossRepository,headRepositoryOwner,headRepository,url \
  --jq '[.state,.headRefName,.baseRefName,.headRefOid,(.isCrossRepository|tostring),(.headRepositoryOwner.login // "~"),(.headRepository.name // "~"),.url] | @tsv') \
  || lookup_failed pr-view "could not read PR $PR from $REPO"
IFS=$'\t' read -r PR_STATE BRANCH BASE FORGE_HEAD_OID IS_FORK HEAD_OWNER HEAD_REPO_NAME PR_URL <<< "$pr_fields"
[ -n "$BRANCH" ] && [ -n "$BASE" ] || lookup_failed pr-view "PR $PR returned empty branch fields"
if [ "$HEAD_OWNER" != "~" ]; then
  case "$HEAD_OWNER" in *[!A-Za-z0-9-]*)
    lookup_failed pr-view "unexpected head-owner form: $HEAD_OWNER" ;;
  esac
fi
if [ "$IS_FORK" = true ]; then
  { [ "$HEAD_OWNER" != "~" ] && [ "$HEAD_REPO_NAME" != "~" ]; } \
    || lookup_failed pr-view "the fork's head repository is gone; its branch cannot be checked or cleaned from here"
  HEAD_REPO="$HEAD_OWNER/$HEAD_REPO_NAME"
else
  HEAD_REPO="$REPO"
fi
# The forge host this PR lives on, for matching configured remotes.
PR_HOST="${PR_URL#*://}"; PR_HOST="${PR_HOST%%/*}"
PR_HOST=$(printf '%s' "$PR_HOST" | tr 'A-Z' 'a-z')
[ -n "$PR_HOST" ] || lookup_failed pr-view "could not derive the forge host from $PR_URL"
# A leading-hyphen ref is valid at the ref level even though git branch
# refuses to create one, and git checkout's -- means pathspec rather than
# branch, so the bare-name switch below cannot be terminated: refuse the
# shape instead of guarding each use.
case "$BRANCH" in -*) stop bad-name "head branch begins with a hyphen: $BRANCH" ;; esac
case "$BASE" in -*) stop bad-name "base branch begins with a hyphen: $BASE" ;; esac

ENC_BRANCH=$(urlencode "$BRANCH")
ENC_BASE=$(urlencode "$BASE")

# --- shared guards ----------------------------------------------------------

probe_component_alias() { # probe_component_alias <directory> <name> <name>
  local probe left right rc=1
  probe=$(mktemp -d "$1/.self-merge-ref-alias.XXXXXX" 2>/dev/null) \
    || lookup_failed name-collision "could not create a same-filesystem ref-alias probe"
  left="$probe/$2"
  right="$probe/$3"
  if ! : > "$left" || ! : > "$right"; then
    rm -rf -- "$probe" >/dev/null 2>&1
    lookup_failed name-collision "could not write the same-filesystem ref-alias probe"
  fi
  [ "$left" -ef "$right" ] && rc=0
  rm -rf -- "$probe" >/dev/null 2>&1 \
    || lookup_failed name-collision "could not remove the same-filesystem ref-alias probe"
  return "$rc"
}

filesystem_names_alias() { # filesystem_names_alias <ref-name> <ref-name>
  # Filesystem casefolding can be directory-scoped. Walk equal or aliasing
  # path components through the real loose-ref hierarchy while it exists;
  # only use an inherited temporary directory once a packed-only prefix has
  # no directory whose effective semantics can be inspected.
  local common refs_dir current virtual_root=""
  local left_rest="$1" right_rest="$2" left_part right_part
  local left_more right_more next
  out_exact common git rev-parse --git-common-dir \
    || lookup_failed name-collision "could not locate the repository's common directory"
  refs_dir="$common/refs/heads"
  mkdir -p -- "$refs_dir" 2>/dev/null \
    || lookup_failed name-collision "could not locate the repository's loose-ref directory"
  current="$refs_dir"
  while :; do
    case "$left_rest" in
      */*) left_part="${left_rest%%/*}"; left_rest="${left_rest#*/}"; left_more=1 ;;
      *) left_part="$left_rest"; left_rest=""; left_more=0 ;;
    esac
    case "$right_rest" in
      */*) right_part="${right_rest%%/*}"; right_rest="${right_rest#*/}"; right_more=1 ;;
      *) right_part="$right_rest"; right_rest=""; right_more=0 ;;
    esac
    if [ "$left_part" != "$right_part" ] \
        && ! probe_component_alias "$current" "$left_part" "$right_part"; then
      [ -z "$virtual_root" ] || rm -rf -- "$virtual_root" >/dev/null 2>&1 \
        || lookup_failed name-collision "could not remove the inherited ref-alias probe"
      return 1
    fi
    if [ "$left_more" -eq 0 ] || [ "$right_more" -eq 0 ]; then
      [ -z "$virtual_root" ] || rm -rf -- "$virtual_root" >/dev/null 2>&1 \
        || lookup_failed name-collision "could not remove the inherited ref-alias probe"
      [ "$left_more" -eq "$right_more" ]
      return
    fi
    if [ -d "$current/$left_part" ]; then
      current="$current/$left_part"
    elif [ -d "$current/$right_part" ]; then
      current="$current/$right_part"
    else
      next=$(mktemp -d "$current/.self-merge-ref-alias.XXXXXX" 2>/dev/null) \
        || lookup_failed name-collision "could not create an inherited ref-alias probe"
      [ -n "$virtual_root" ] || virtual_root="$next"
      current="$next"
    fi
  done
}

ref_names_alias() { # ref_names_alias <ref-name> <ref-name>
  local left="$1" right="$2"
  [ "$left" = "$right" ] && return 0
  # Preserve the cheap, deterministic ASCII check even when a repository's
  # core.ignorecase setting was copied to a case-sensitive filesystem, but
  # never trust a false or missing setting to describe the actual filesystem.
  if [ "$(git config --type=bool --get core.ignorecase 2>/dev/null)" = true ] \
      && [ "$(printf '%s' "$left" | tr 'A-Z' 'a-z')" \
        = "$(printf '%s' "$right" | tr 'A-Z' 'a-z')" ]; then
    return 0
  fi
  filesystem_names_alias "$left" "$right"
}

# Facts about the base repository, loaded once per run: the default branch
# for the collision guard, the fork lineage for the consumer guards, the
# clone endpoints for remote identity, and the merge-commit settings for the
# queue message guard.
REPO_FACTS_LOADED=""
load_repo_facts() {
  [ -n "$REPO_FACTS_LOADED" ] && return 0
  local facts rn
  facts=$(gh_read api "repos/$REPO" \
    --jq '[.default_branch, (.fork|tostring), (.parent.full_name // "~"), (.source.full_name // "~"), (.clone_url // "~"), (.ssh_url // "~"), (.merge_commit_title // "~"), (.merge_commit_message // "~")] | @tsv') \
    || lookup_failed repo-facts "could not read repository facts for $REPO"
  IFS=$'\t' read -r DEFAULT_BRANCH REPO_IS_FORK PARENT_REPO SOURCE_REPO REPO_CLONE_URL REPO_SSH_URL MERGE_COMMIT_TITLE_SETTING MERGE_COMMIT_MESSAGE_SETTING <<< "$facts"
  [ -n "$DEFAULT_BRANCH" ] || lookup_failed repo-facts "empty default branch for $REPO"
  case "$REPO_IS_FORK" in true|false) ;; *)
    lookup_failed repo-facts "unexpected fork flag: $REPO_IS_FORK" ;;
  esac
  [ "$REPO_CLONE_URL" != "~" ] && [ "$REPO_SSH_URL" != "~" ] \
    || lookup_failed repo-facts "repository clone endpoints are missing"
  REPO_CLONE_ID=$(url_id "$REPO_CLONE_URL")
  REPO_SSH_ID=$(url_id "$REPO_SSH_URL")
  case "$REPO_CLONE_ID,$REPO_SSH_ID" in host\ *,host\ *) ;; *)
    lookup_failed repo-facts "repository clone endpoints are not hosted URL identities" ;;
  esac
  for rn in "$PARENT_REPO" "$SOURCE_REPO"; do
    case "$rn" in *[!A-Za-z0-9._/~-]*)
      lookup_failed repo-facts "unexpected repository name in fork lineage: $rn" ;;
    esac
  done
  REPO_FACTS_LOADED=1
}

collision_check() {
  load_repo_facts
  for ref_name in "$BRANCH" "$BASE" "$DEFAULT_BRANCH"; do
    git check-ref-format "refs/heads/$ref_name" >/dev/null 2>&1 \
      || lookup_failed name-collision "the forge returned an invalid branch name: $ref_name"
  done
  if ref_names_alias "$BRANCH" "$BASE"; then
    stop name-collision "head branch $BRANCH resolves to the same ref as base $BASE"
  fi
  if ref_names_alias "$BRANCH" "$DEFAULT_BRANCH"; then
    stop name-collision "head branch $BRANCH resolves to the same ref as default branch $DEFAULT_BRANCH"
  fi
}

# Workspace preflight, in the checkout this script runs from, which is the
# base checkout the later phases operate from. A clean tree elsewhere says
# nothing.
workspace_preflight() {
  # -uall on the command line overrides status.showUntrackedFiles=no; a
  # guard that inherits repository configuration can be switched off by the
  # repository it protects.
  local dirty
  dirty=$(git status -uall --porcelain 2>/dev/null) \
    || stop not-a-repo "not inside a git working tree"
  [ -z "$dirty" ] || stop dirty-tree "uncommitted changes present (git status -uall --porcelain)"
  if op_probe .; then
    stop op-in-progress "$OP_FOUND exists: a git operation is paused here"
  fi
}

# Is a git operation paused in the given worktree? Operation state is
# per-worktree, so this checkout's probes say nothing about another
# worktree. Probe the per-worktree paths, never the names as
# revisions: an ordinary refs/heads/MERGE_HEAD otherwise looks like a
# paused merge. out_exact preserves a trailing newline in a linked
# worktree's git-dir path; -L also catches a dangling marker symlink.
# rebase-apply covers an interrupted git am.
op_probe() { # op_probe <dir>: returns 0 and sets OP_FOUND when one is paused
  local d="$1" p gp
  OP_FOUND=""
  for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_START rebase-merge rebase-apply; do
    out_exact gp git -C "$d" rev-parse --git-path "$p" \
      || lookup_failed op-probe "could not resolve $p inside $d"
    if (cd "$d" && { [ -e "$gp" ] || [ -L "$gp" ]; }); then
      OP_FOUND="$p"; return 0
    fi
  done
  return 1
}

# Parse `git worktree list --porcelain -z` NUL-aware: the output is
# NUL-terminated fields, not paths, so the reader strips the leading
# "worktree " keyword and pairs each path with the branch field that
# follows it. A command substitution would strip a trailing newline from a
# path, and a line-oriented read mis-pairs on paths holding newlines, so
# the fields stream through a temp file into read -d ''.
worktree_scan() { # worktree_scan <ref>: sets WT_MATCH to the unique path
  # whose branch field is exactly <ref>, empty when none; duplicates stop
  local want="$1" tmp field cand="" count=0
  WT_MATCH=""
  tmp=$(mktemp) || lookup_failed worktree-scan "mktemp failed"
  git worktree list --porcelain -z > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed worktree-scan "git worktree list failed"; }
  while IFS= read -r -d '' field; do
    case "$field" in
      "worktree "*) cand="${field#worktree }" ;;
      branch*)
        if [ "$field" = "branch $want" ]; then
          count=$((count + 1))
          WT_MATCH="$cand"
        fi
        ;;
    esac
  done < "$tmp"
  rm -f "$tmp"
  [ "$count" -le 1 ] \
    || stop duplicate-worktree "$count worktrees check out $want; the sequence cannot choose one without leaving or moving another"
}

layout_check() {
  # The current worktree's root is compared by inode (-ef) against a
  # relative path: --show-cdup is dots and slashes and cannot end in a
  # newline, while --show-toplevel through a command substitution loses a
  # trailing newline the scanned worktree paths faithfully keep, so a
  # string comparison would misidentify the current worktree exactly when
  # the path is hostile.
  local base_wt
  CWD_CDUP=$(git rev-parse --show-cdup 2>/dev/null) \
    || stop not-a-repo "not inside a git working tree"
  CWD_CDUP="${CWD_CDUP:-.}"
  out_exact WORKTREE_ROOT physical_dir "$CWD_CDUP" \
    || stop not-a-repo "could not resolve the current worktree root"
  worktree_scan "refs/heads/$BASE"; base_wt="$WT_MATCH"
  if [ -n "$base_wt" ] && ! [ "$base_wt" -ef "$CWD_CDUP" ]; then
    stop wrong-checkout "the base branch is checked out in another worktree: run this phase from $base_wt"
  fi
  # Reject ambiguity at the layout boundary. land_rebase repeats this scan
  # immediately before moving the head worktree, retrieving the path afresh
  # and closing layout changes made during the earlier checks.
  worktree_scan "refs/heads/$BRANCH"
}

# Consumer guards, both directions. An error is unknown and unknown keeps
# the branch: a failed listing returns no rows, which would otherwise read
# as "nothing depends on this branch" moments before a delete.
consumer_checks() {
  load_repo_facts
  local shared stacked target seen="" n
  if [ "$IS_FORK" = true ]; then
    shared=$(gh_read api "repos/$REPO/pulls?state=open&head=$HEAD_OWNER:$ENC_BRANCH" \
      --jq "[.[] | select(.number != $PR) | .number] | length") \
      || lookup_failed shared-head "could not list open PRs sharing head $HEAD_OWNER:$BRANCH"
  else
    shared=$(gh_read pr list --repo="$REPO" --head="$BRANCH" --state=open --json=number \
      --jq "[.[] | select(.number != $PR) | .number] | length") \
      || lookup_failed shared-head "could not list open PRs sharing head $BRANCH"
  fi
  case "$shared" in ''|*[!0-9]*) lookup_failed shared-head "unparseable shared-head listing" ;; esac
  [ "$shared" -eq 0 ] || stop shared-head "$shared other open PR(s) use $BRANCH as their head; deleting or auto-deleting it closes them"
  # Stacked PRs are reported, not refused: nothing in these phases deletes
  # the branch. merge-cleanup owns the delete and retargets each
  # same-repository child onto the base first. A cross-repository head's
  # children live in the head's repository, where neither the forge nor
  # merge-cleanup can retarget them onto this base, so they still stop.
  stacked=$(gh_read pr list --repo="$HEAD_REPO" --base="$BRANCH" --state=open --json=number \
    --jq '[.[].number] | tojson') \
    || lookup_failed stacked-prs "could not list open PRs based on $BRANCH"
  n=${stacked#\[}; n=${n%\]}
  case "$stacked" in '['*']') ;; *) lookup_failed stacked-prs "unparseable stacked-PR listing" ;; esac
  case "$n" in *[!0-9,]*|,*|*,|*,,*) lookup_failed stacked-prs "unparseable stacked-PR listing" ;; esac
  STACKED_PRS=$stacked
  if [ -n "$n" ]; then
    [ "$IS_FORK" = false ] \
      || stop stacked-prs "open PR(s) $n in $HEAD_REPO are based on $BRANCH and cannot be retargeted onto $REPO/$BASE"
    echo "land.sh: PR $PR: open PR(s) $n are based on $BRANCH; they move onto $BASE when $BRANCH is deleted after the merge" >&2
  fi
  # A repository that is itself a fork: its branch can simultaneously head
  # a PR to the parent or root of its network, which the per-repository
  # listings above cannot see. Query the recorded lineage; no cross-repo
  # number exclusion, since another repository's PR can share this PR's
  # number without being it.
  if [ "$REPO_IS_FORK" = true ]; then
    for target in "$PARENT_REPO" "$SOURCE_REPO"; do
      [ "$target" != "~" ] || continue
      [ "$target" != "$REPO" ] || continue
      case " $seen " in *" $target "*) continue ;; esac
      seen="$seen $target"
      n=$(gh_read api "repos/$target/pulls?state=open&head=${REPO%%/*}:$ENC_BRANCH" --jq length) \
        || lookup_failed shared-head "could not list open PRs in $target sharing head $BRANCH"
      case "$n" in ''|*[!0-9]*) lookup_failed shared-head "unparseable listing from $target" ;; esac
      [ "$n" -eq 0 ] || stop shared-head "$n open PR(s) in $target use $BRANCH as their head; deleting or auto-deleting it closes them"
    done
  fi
}

# A queue owns the eventual commit message as well as the merge method:
# gh's enqueue operation cannot carry --subject/--body through to that
# commit. The repository settings therefore become part of the title-only
# history contract whenever a MERGE queue applies.
queue_message_check() {
  [ "${QUEUE:-absent}" = merge ] || return
  load_repo_facts
  if [ "$MERGE_COMMIT_TITLE_SETTING" != PR_TITLE ] \
     || [ "$MERGE_COMMIT_MESSAGE_SETTING" != BLANK ]; then
    stop queue-message "the merge queue on $BASE cannot honor command-line subject/body; repository merge-commit settings must be PR_TITLE and BLANK (got: $MERGE_COMMIT_TITLE_SETTING and $MERGE_COMMIT_MESSAGE_SETTING)"
  fi
}

# A merge queue picks the integration method itself, so --merge cannot
# promise first-parent history: identify the queue's method before anything
# is enqueued, from the branch-rules API (the CLI's ruleset commands have no
# JSON output and cannot report the method). Fail closed on any shape this
# read does not recognize: the payload belongs to the forge.
#
# One failure is an answer, not an unknown: GitHub refuses the read with a
# plan-limit 403 on a private repository whose plan lacks rulesets.
# GitHub's docs give rulesets on private repositories only to paid plans,
# and merge queues on private repositories only to Enterprise Cloud
# organizations, so no queue can apply there. See "Who can use this
# feature?" on
# https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
# https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue
# The match is gh's whole stderr, status and message together, so any
# other 403 (token scope, SSO, permission), 404, or 5xx stays a failure.
QUEUE_PLAN_GATED_ERR='gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)'
queue_check() {
  local methods row method="" count=0
  if ! methods=$(gh_read api --paginate "repos/$REPO/rules/branches/$ENC_BASE" \
    --jq '.[] | select(.type == "merge_queue") | (.parameters.merge_method // "unidentified")'); then
    if [ "$(cat "$GH_ERR")" = "$QUEUE_PLAN_GATED_ERR" ]; then
      # Clear it as gh_read does after a read that worked: an answered read
      # must not lend its stderr to a later failure's excerpt.
      : > "$GH_ERR"
      QUEUE=absent
      return
    fi
    lookup_failed queue-rules "could not read branch rules for $BASE"
  fi
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    count=$((count + 1))
    method="$row"
  done <<< "$methods"
  if [ "$count" -eq 0 ]; then
    QUEUE=absent
    return
  fi
  [ "$count" -eq 1 ] \
    || stop queue-method "multiple merge-queue rules apply to $BASE; the integration method is ambiguous"
  case "$method" in
    MERGE) QUEUE=merge ;;
    SQUASH|REBASE) stop queue-method "the merge queue on $BASE integrates by $method, not a merge commit" ;;
    *) stop queue-method "could not identify the merge queue's method on $BASE (got: $method)" ;;
  esac
  queue_message_check
}

# Normalized identity of a remote URL. Hosted forms
# (scheme://[user@]host[:port]/path, or the scp form user@host:path)
# yield "host <transport> <authority> <path>", with only the authority
# lowercased; the explicit type and transport tags cannot collide with a
# single-label hostname. The
# complete, case-preserved hosted path is load-bearing: /a/owner/name and
# /b/owner/name, /A/owner/name and /a/owner/name, or repo and repo.git can
# be different repositories behind one authority. A URL with no host is a
# local path and is identified by its full path, case preserved and with
# only a trailing slash normalized away. file:///path and
# file://localhost/path use Git's local absolute-path semantics; other
# file authorities and scheme spellings stay a distinct, fail-closed
# identity rather than being mistaken for a relative path or hosted
# transport.
url_id() {
  local raw="$1" host rest authority path after_user scheme transport="" ssh_user=""
  case "$raw" in
    file://*)
      rest="${raw#*://}"
      case "$rest" in
        /*) raw="$rest" ;;
        [Ll][Oo][Cc][Aa][Ll][Hh][Oo][Ss][Tt]/*) raw="/${rest#*/}" ;;
        *)
          printf 'file-url %s' "$rest"
          return
          ;;
      esac
      ;;
    [Ff][Ii][Ll][Ee]://*)
      printf 'file-url %s' "$raw"
      return
      ;;
  esac
  case "$raw" in
    *://*)
      # Authority = up to the first slash. Non-SSH userinfo is credentials
      # and does not change the repository endpoint; an SSH username does,
      # so preserve it. Split at the last @ first so a colon inside
      # user:pass cannot truncate the host to the username, then keep host
      # and port together: two ports are two endpoints.
      scheme="${raw%%://*}"
      rest="${raw#*://}"
      authority="${rest%%/*}"
      host="${authority##*@}"
      case "$scheme" in
        ssh|git+ssh|ssh+git)
          transport=ssh
          case "$authority" in *@*) ssh_user="${authority%"@$host"}" ;; esac
          ;;
        *) transport="$scheme" ;;
      esac
      if [ "$rest" = "$authority" ]; then path=""; else path="${rest#*/}"; fi
      ;;
    *:*)
      # Git's SCP form allows an optional user. A slash before the first
      # colon makes the value a local path instead, while userless
      # host:path and bracketed IPv6 forms are still hosted transports.
      transport=scp
      case "${raw%%:*}" in
        */*) host="" ;;
        *)
          after_user="${raw##*@}"
          case "$raw" in *@*) ssh_user="${raw%"@$after_user"}" ;; esac
          case "$after_user" in
            \[*\]:*)
              host="${after_user%%]:*}]"
              path="${after_user#*]:}"
              ;;
            *)
              host="${after_user%%:*}"
              path="${after_user#*:}"
              ;;
          esac
          ;;
      esac
      ;;
    *) host="" ;;
  esac
  if [ -z "$host" ]; then
    case "$raw" in /) ;; */) raw="${raw%/}" ;; esac
    printf 'path %s' "$raw"
    return
  fi
  host=$(printf '%s' "$host" | tr 'A-Z' 'a-z')
  [ -z "$ssh_user" ] || host="$ssh_user@$host"
  path="${path%/}"
  printf 'host %s %s %s' "$transport" "$host" "$path"
}

# Resolve a hostless URL to the filesystem destination Git will use now.
# Ask Git to expand its leading ~/ and ~user/ path syntax, root other relative
# paths at the worktree root, and follow every symlink before the identity
# crosses a checkout boundary. Keep the remaining resolution in shell so
# the script does not gain another executable dependency.
canonical_local_path() { # canonical_local_path <path>
  local path="$1" link dir base physical suffix="" hops=0
  case "$path" in
    ~*) out_exact path git -c "selfmerge.path=$path" config --path --get selfmerge.path \
      || return 1 ;;
  esac
  case "$path" in
    /*) ;;
    *)
      case "$WORKTREE_ROOT" in
        /) path="/$path" ;;
        *) path="$WORKTREE_ROOT/$path" ;;
      esac
      ;;
  esac
  while [ -L "$path" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 40 ] || return 1
    out_exact link readlink "$path" || return 1
    [ -n "$link" ] || return 1
    dir="${path%/*}"; [ -n "$dir" ] || dir=/
    case "$link" in /*) path="$link" ;; *) path="$dir/$link" ;; esac
  done
  while ! [ -d "$path" ]; do
    base="${path##*/}"
    [ -n "$base" ] || return 1
    suffix="/$base$suffix"
    dir="${path%/*}"; [ -n "$dir" ] || dir=/
    [ "$dir" != "$path" ] || return 1
    path="$dir"
  done
  cd -P -- "$path" 2>/dev/null || return 1
  out_exact physical pwd -P || return 1
  printf '%s%s' "${physical%/}" "$suffix"
}

remote_url_id() { # remote_url_id <effective-url>
  local id path resolved
  id=$(url_id "$1")
  case "$id" in
    path\ *)
      path="${id#path }"
      [ -n "$path" ] || return 1
      out_exact resolved canonical_local_path "$path" || return 1
      printf 'path %s' "$resolved"
      ;;
    *) printf '%s' "$id" ;;
  esac
}

# The forge identifies a repository by host plus owner/name even when the
# Git endpoint has a deployment-specific path prefix. Keep this derivation
# separate from url_id: it is for selecting a candidate remote, never for
# proving that its fetch and push destinations are the same repository.
url_forge_id() {
  local id transport host path forge_path parent owner name
  id=$(url_id "$1")
  case "$id" in
    host\ *) id="${id#host }" ;;
    *) return 1 ;;
  esac
  transport="${id%% *}"; id="${id#* }"
  host="${id%% *}"; path="${id#* }"
  # SSH users are endpoint-defining for fetch/push equality, but the forge
  # candidate match is deliberately only host plus owner/name.
  host="${host##*@}"
  forge_path=$(printf '%s' "$path" | tr 'A-Z' 'a-z')
  forge_path="${forge_path%.git}"
  name="${forge_path##*/}"; parent="${forge_path%/*}"
  [ "$parent" != "$forge_path" ] || return 1
  owner="${parent##*/}"
  [ -n "$owner" ] && [ -n "$name" ] || return 1
  printf '%s %s/%s' "$host" "$owner" "$name"
}

# Does a remote have exactly one push destination with the expected identity?
# --push --all is load-bearing: a remote can configure several push URLs,
# git push sends to every one of them, and the plain --push query returns
# only the first, so validating one URL blesses a broadcast. Even duplicate
# effective URLs are unsafe: the first lease delete succeeds and the second
# fails against stale lease information. The queries return
# insteadOf/pushInsteadOf-expanded URLs (verified), so config rewrites cannot
# smuggle in a different destination either.
push_ids_match() { # push_ids_match <remote> <expected-id>
  local purls pu count=0
  out_exact purls git remote get-url --push --all -- "$1" || return 1
  while IFS= read -r pu; do
    [ -n "$pu" ] || return 1
    count=$((count + 1))
    [ "$(url_id "$pu")" = "$2" ] || return 1
  done <<< "$purls"
  [ "$count" -eq 1 ]
}

# Resolve an SSH host, possibly a local ~/.ssh/config Host alias, to the
# concrete hostname, user, and port Git will actually connect to. The forge
# identity guards below compare a remote against the forge's authoritative
# clone endpoints; a local alias (HostName github.com behind the label
# bnw.github.com) names that same endpoint, so it must resolve before the
# comparison rather than read as a foreign host. `ssh -G` computes the
# effective config offline without connecting, and the user's own ssh config
# is the same trust domain as the git insteadOf rules the script already
# honors. Resolve the exact user@host target Git will reach: ~/.ssh/config can
# expand a different HostName/port per remote user (`Match user`, `%r` in
# HostName), so resolving a bare host could bless a userless endpoint while the
# delete routes through the user-qualified one. Fails closed (nonzero, empties
# left) when ssh is absent or cannot resolve. SSH_ALIAS_HOST/USER/PORT are the
# outputs.
SSH_ALIAS_HOST="" SSH_ALIAS_USER="" SSH_ALIAS_PORT=""
ssh_resolved_endpoint() { # ssh_resolved_endpoint <host> [user]
  local host="$1" user="${2:-}" target key val resolved
  SSH_ALIAS_HOST="" SSH_ALIAS_USER="" SSH_ALIAS_PORT=""
  command -v ssh >/dev/null 2>&1 || return 1
  # Git honors an ssh-command override (GIT_SSH_COMMAND, then core.sshCommand,
  # else GIT_SSH) for the fetch/ls-remote/push that deletes the branch, but this
  # guard queries the plain `ssh` on PATH. Under an override the offline `ssh -G`
  # no longer reflects the endpoint Git reaches, so fail closed rather than bless
  # a possibly-divergent host. The intersection that this stops (an alias that
  # needs resolving while an override is active) is narrow and errs safe.
  [ -n "${GIT_SSH_COMMAND:-}" ] && return 1
  [ -n "${GIT_SSH:-}" ] && return 1
  [ -n "$(git config --get core.sshCommand 2>/dev/null)" ] && return 1
  # An option-shaped host or user could be read as an ssh flag even after --, so
  # refuse it outright rather than trust a single guard.
  case "$host" in ''|-*) return 1 ;; esac
  # Query user@host when the URL names a user, matching Git's own connection; a
  # bare host otherwise, matching Git applying the config's User.
  target="$host"
  case "$user" in
    -*|*@*) return 1 ;;
    ?*) target="$user@$host" ;;
  esac
  resolved=$(ssh -G -- "$target" 2>/dev/null) || return 1
  while read -r key val; do
    case "$key" in
      hostname) [ -n "$SSH_ALIAS_HOST" ] || SSH_ALIAS_HOST="$val" ;;
      user) [ -n "$SSH_ALIAS_USER" ] || SSH_ALIAS_USER="$val" ;;
      port) [ -n "$SSH_ALIAS_PORT" ] || SSH_ALIAS_PORT="$val" ;;
    esac
  done <<< "$resolved"
  [ -n "$SSH_ALIAS_HOST" ] || return 1
  SSH_ALIAS_HOST=$(printf '%s' "$SSH_ALIAS_HOST" | tr 'A-Z' 'a-z')
}

# Rewrite an SSH remote URL whose host is a local alias into the concrete URL
# form that names the real endpoint, so the forge identity comparison sees the
# true host and user. Only ssh-family transports (scp-like host:path and the
# ssh:// schemes) carry aliases; every other URL is left to its existing
# mismatch. The rewrite substitutes the resolved hostname, fills in the
# resolved user when the URL states none (an alias commonly carries `User
# git`), and keeps the original transport form and path byte-for-byte. It
# fails, leaving the caller on its mismatch, when ssh cannot resolve, when the
# resolved port is not the default (a non-default port is a genuinely different
# endpoint than the forge's default-port ssh_url and must not be blessed), or
# when the host is unchanged (no alias in play). The rewritten URL feeds only
# the identity check; fetch and push keep the original alias URL so its ssh
# config still applies, while SSH_ALIAS_PIN_COMMAND pins the checked endpoint
# for the destructive head transports.
SSH_ALIAS_URL="" SSH_ALIAS_PIN_COMMAND=""
ssh_alias_resolve() { # ssh_alias_resolve <url>
  local raw="$1" scheme rest authority before after path="" host user="" newuser newauth
  SSH_ALIAS_URL="" SSH_ALIAS_PIN_COMMAND=""
  case "$raw" in
    *://*)
      scheme="${raw%%://*}"
      case "$scheme" in ssh|git+ssh|ssh+git) ;; *) return 1 ;; esac
      rest="${raw#*://}"
      authority="${rest%%/*}"
      case "$authority" in *@*) user="${authority%@*}"; host="${authority##*@}" ;;
        *) host="$authority" ;; esac
      [ "$rest" = "$authority" ] || path="${rest#*/}"
      ;;
    *:*)
      case "${raw%%:*}" in */*) return 1 ;; esac
      before="${raw%%:*}"; after="${raw#*:}"
      case "$before" in *@*) user="${before%@*}"; host="${before##*@}" ;;
        *) host="$before" ;; esac
      ;;
    *) return 1 ;;
  esac
  # A port or IPv6 literal in the host is not the simple alias this resolves.
  case "$host" in ''|*:*|\[*) return 1 ;; esac
  ssh_resolved_endpoint "$host" "$user" || return 1
  # GIT_SSH_COMMAND is parsed as a shell command by Git. Only literal endpoint
  # fields may enter it; quoting untrusted ssh -G output would be a weaker
  # boundary because another shell parses the value later.
  case "$SSH_ALIAS_HOST" in ''|*[!A-Za-z0-9.-]*) return 1 ;; esac
  case "$SSH_ALIAS_USER" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$SSH_ALIAS_PORT" in ''|*[!0-9]*) return 1 ;; esac
  [ "$SSH_ALIAS_PORT" = 22 ] || return 1
  [ "$SSH_ALIAS_HOST" != "$(printf '%s' "$host" | tr 'A-Z' 'a-z')" ] || return 1
  newuser="$user"; [ -n "$newuser" ] || newuser="$SSH_ALIAS_USER"
  case "$newuser" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  newauth="$SSH_ALIAS_HOST"; [ -z "$newuser" ] || newauth="$newuser@$SSH_ALIAS_HOST"
  SSH_ALIAS_PIN_COMMAND="ssh -o HostName=$SSH_ALIAS_HOST -o User=$newuser -o Port=$SSH_ALIAS_PORT -o CanonicalizeHostname=no"
  case "$raw" in
    *://*) [ -n "$path" ] && SSH_ALIAS_URL="$scheme://$newauth/$path" \
             || SSH_ALIAS_URL="$scheme://$newauth" ;;
    *) SSH_ALIAS_URL="$newauth:$after" ;;
  esac
}

# Run one Git transport with an optional command-scoped SSH endpoint pin. An
# empty pin runs plain git (the pin variable must never be exported as an empty
# GIT_SSH_COMMAND, which would break a non-alias SSH transport); a non-empty pin
# forces HostName/User/Port for this invocation only, so a Match-exec change
# after identity acceptance cannot redirect the destructive head transport.
git_with_ssh_pin() { # git_with_ssh_pin <ssh-command-or-empty> <git args...>
  local pin="$1"; shift
  if [ -n "$pin" ]; then
    GIT_SSH_COMMAND="$pin" git "$@"
  else
    git "$@"
  fi
}

# Resolve which configured remote points at a repository, matching the
# PR's forge host as well as the owner/name tail: a same-named repository
# on another host (a GitLab mirror of a GitHub repo) shares the tail, and
# deleting a branch there is the wrong remote's branch. Every push URL
# must carry the same identity as the fetch URL, because the existence
# checks read the fetch side while a push writes every configured push
# destination. A URL with no host (a local path or file://) never
# auto-resolves; pass the override flag for such a layout. Overridable
# because URL forms vary; unresolvable is a stop, not a guess.
resolve_remote() { # resolve_remote <owner/name>: sets RESOLVED_REMOTE
  local want r furl fid raw_fid forge_id resolved match=""
  want=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  RESOLVED_REMOTE=""
  while IFS= read -r r; do
    remote_urls_newline_free "$r" || continue
    out_exact furl git remote get-url -- "$r" || continue
    fid=$(url_id "$furl"); raw_fid="$fid"
    forge_id=$(url_forge_id "$furl") || forge_id=""
    # A local SSH host alias hides the true forge identity; resolve it and
    # retry the candidate match on the concrete endpoint when the raw URL
    # fails. push_ids_match still compares against the raw fetch id because
    # the configured push URLs carry the alias, not the resolved host.
    if { [ "$fid" != "$REPO_CLONE_ID" ] && [ "$fid" != "$REPO_SSH_ID" ]; } \
        || [ "$forge_id" != "$PR_HOST $want" ]; then
      ssh_alias_resolve "$furl" || continue
      resolved="$SSH_ALIAS_URL"
      fid=$(url_id "$resolved")
      forge_id=$(url_forge_id "$resolved") || continue
    fi
    case "$fid" in "$REPO_CLONE_ID"|"$REPO_SSH_ID") ;; *) continue ;; esac
    [ "$forge_id" = "$PR_HOST $want" ] || continue
    push_ids_match "$r" "$raw_fid" || continue
    if [ -z "$match" ] || [ "$r" = origin ]; then match="$r"; fi
  done < <(git remote)
  RESOLVED_REMOTE="$match"
}

# A hosted override must still identify the PR's repository. A hostless
# mapping cannot be matched to forge identity, so naming that remote
# explicitly is the separate trust decision. A hostless mapping that remains
# after checkout is pinned to that identity; a replacement hosted mapping can
# instead be validated against the forge. CHECKED_REMOTE_ID exposes the
# validated identity to that checkout boundary, and fetch/push identity is
# still checked before a destructive head push. PINNED_SSH_COMMAND carries the
# alias endpoint pin for the destructive head transports, empty otherwise.
CHECKED_REMOTE_ID="" PINNED_SSH_COMMAND=""
remote_repo_check() { # remote_repo_check <remote> <role>
  local remote="$1" role="$2" configured u have_url=false furl endpoint_id resolved_id
  PINNED_SSH_COMMAND=""
  remote_urls_newline_free "$remote" \
    || stop remote-repo-mismatch "$role remote $remote has a newline-bearing URL whose forge identity cannot be compared faithfully"
  out_exact configured git config --get-all "remote.$remote.url" \
    || lookup_failed "$role-remote" "could not read $remote's configured URLs"
  while IFS= read -r u; do
    [ -n "$u" ] && have_url=true
  done <<< "$configured"
  [ "$have_url" = true ] \
    || lookup_failed "$role-remote" "$remote has no URL configured"
  out_exact furl git remote get-url -- "$remote" \
    || lookup_failed "$role-remote" "could not read $remote's URL"
  out_exact endpoint_id remote_url_id "$furl" \
    || stop remote-repo-mismatch "$role remote $remote's effective local destination could not be resolved safely"
  CHECKED_REMOTE_ID="$endpoint_id"
  case "$endpoint_id" in
    path\ *) return 0 ;;
    "$REPO_CLONE_ID"|"$REPO_SSH_ID") return 0 ;;
  esac
  # A local SSH host alias resolves to the forge's real endpoint; compare that
  # resolved identity before refusing. CHECKED_REMOTE_ID stays the alias id so
  # the post-checkout path-change guard still sees a hosted id (not a hostless
  # path). Only a head alias earns the endpoint pin the destructive transports
  # apply; the base fetch and resync route through the alias's own ssh config.
  if ssh_alias_resolve "$furl" \
      && out_exact resolved_id remote_url_id "$SSH_ALIAS_URL"; then
    case "$resolved_id" in "$REPO_CLONE_ID"|"$REPO_SSH_ID")
      [ "$role" != head ] || PINNED_SSH_COMMAND="$SSH_ALIAS_PIN_COMMAND"
      return 0
      ;;
    esac
  fi
  stop remote-repo-mismatch "$role remote $remote does not match PR repository $REPO's authoritative clone endpoints"
}

# --- landing ----------------------------------------------------------------

# Without branch protection nothing stops a merge of a head that was never
# tested against the current base. land runs one round of the landing
# procedure itself: the head must contain the base tip it fetched, CI must
# be green on that exact head, and the forge's base tip must still be the
# fetched one when the merge starts. Each refusal is a STOP and rerunning
# land is the retry, so every refusal reaches the caller.
LAND_TIP="" LAND_TMP_WT="" LAND_WT="" NEW_HEAD="" MOVE_ERR="" MOVE_IGNORED=false
# Set only when --prepared passes the base-tree check in phase_land.
PREP_BASE="" PREP_TREE="" REPLAY_ERR=""

# Encode a branch for a forge path that takes it as slash-separated
# segments (git/ref/heads/<branch>): each segment percent-encoded, the
# slashes kept.
urlencode_ref_path() {
  local rest="$1" out=""
  while :; do
    case "$rest" in
      */*) out+="$(urlencode "${rest%%/*}")/"; rest="${rest#*/}" ;;
      *) out+="$(urlencode "$rest")"; break ;;
    esac
  done
  printf '%s' "$out"
}

forge_base_tip() { # sets FORGE_BASE_TIP to the forge's current tip of $BASE
  FORGE_BASE_TIP=$(gh_read api "repos/$REPO/git/ref/heads/$(urlencode_ref_path "$BASE")" \
    --jq '.object.sha') \
    || lookup_failed base-ref "could not read the tip of $BASE from $REPO"
  case "$FORGE_BASE_TIP" in *[!0-9a-f]*|'')
    lookup_failed base-ref "unexpected tip for $BASE: $FORGE_BASE_TIP" ;;
  esac
  [ "${#FORGE_BASE_TIP}" -eq 40 ] \
    || lookup_failed base-ref "unexpected tip for $BASE: $FORGE_BASE_TIP"
}

# Read CI for one commit once. Sets CI_STATE to passed, failed, pending, or
# missing, and CI_DETAIL to what is not green. Only success, neutral, and
# skipped pass; every other conclusion (cancelled, timed_out,
# action_required, stale) fails. No check run and no commit status is
# missing, never green: CI that has not reported has not passed. A failed
# read sets CI_STATE to unread, CI_WHAT to the read that failed, and
# CI_DETAIL to why, then returns 1; the caller decides whether to poll
# again.
#
# Each failed check also becomes a JSON entry in CI_FAILED_ENTRIES, built
# by gh's jq so any check name stays escaped: {name, run_id, job_id, url}.
# CI_FAILED_ENTRY_JOBS holds each entry's job id at the same index, or "-".
# A GitHub Actions job's check-run id is its job id, and its details URL
# names its workflow run; any other check, and every failing commit
# status, gets null ids and "-", and CI_UNRERUNNABLE turns true because
# `gh run rerun` cannot retry it. CI_FAILED_JOBS lists "<run> <job>" for
# each failed Actions job. Plain indexed arrays: macOS ships bash 3.2.
ci_read() { # ci_read <oid>
  local oid="$1" runs status st concl run job entry name line total=0 bad="" waiting=""
  local s_state="" s_total="" first=true
  local status_failed=()
  CI_FAILED_ENTRIES=() CI_FAILED_ENTRY_JOBS=() CI_FAILED_JOBS="" CI_UNRERUNNABLE=false
  # The entry sits before the name: every field before the name is never
  # empty, and an empty field would vanish from a tab-separated read.
  # tojson never emits a raw tab or newline, so the entry stays one field.
  if ! runs=$(gh_read api --paginate "repos/$REPO/commits/$oid/check-runs?per_page=100" \
    --jq '.check_runs[]
      | (if .app.slug == "github-actions"
         then ((.details_url // "") | capture("/actions/runs/(?<run>[0-9]+)/job/[0-9]+$") | .run) // null
         else null end) as $run
      | ([.status, (.conclusion // "none"), ($run // "-"),
          (if $run then (.id | tostring) else "-" end)] | @tsv)
        + "\t" + ({name, run_id: ($run | if . then tonumber else null end),
                   job_id: (if $run then .id else null end),
                   url: (.details_url // .html_url)} | tojson)
        + "\t" + ([.name] | @tsv)'); then
    CI_STATE=unread CI_WHAT=check-runs CI_DETAIL="could not read check runs for $oid"
    return 1
  fi
  while IFS=$'\t' read -r st concl run job entry name; do
    [ -n "$st" ] || continue
    total=$((total + 1))
    if [ "$st" != completed ]; then
      waiting+=", $name ($st)"
    else
      case "$concl" in
        success|neutral|skipped) ;;
        *)
          bad+=", $name ($concl)"
          CI_FAILED_ENTRIES+=("$entry") CI_FAILED_ENTRY_JOBS+=("$job")
          if [ "$run" = - ]; then CI_UNRERUNNABLE=true
          else CI_FAILED_JOBS+="$run $job"$'\n'
          fi ;;
      esac
    fi
  done <<< "$runs"
  # The combined status lists only the latest status per context. Its
  # first line is the state and count; each failing status follows as an
  # entry.
  if ! status=$(gh_read api "repos/$REPO/commits/$oid/status?per_page=100" \
    --jq '([.state, (.total_count|tostring)] | @tsv),
      (.statuses[]? | select(.state == "failure" or .state == "error")
       | {name: .context, run_id: null, job_id: null, url: .target_url} | tojson)'); then
    CI_STATE=unread CI_WHAT=commit-status CI_DETAIL="could not read the combined status for $oid"
    return 1
  fi
  while IFS= read -r line; do
    if [ "$first" = true ]; then
      IFS=$'\t' read -r s_state s_total <<< "$line"; first=false; continue
    fi
    [ -z "$line" ] || status_failed+=("$line")
  done <<< "$status"
  case "$s_total" in ''|*[!0-9]*)
    lookup_failed commit-status "unparseable status count for $oid: $s_total" ;;
  esac
  # The combined state reads pending when no status exists at all, so it
  # means something only when the count is nonzero.
  if [ "$s_total" -gt 0 ]; then
    total=$((total + s_total))
    case "$s_state" in
      success) ;;
      pending) waiting+=", commit statuses (pending)" ;;
      failure|error)
        bad+=", commit statuses ($s_state)"
        for line in ${status_failed[@]+"${status_failed[@]}"}; do
          CI_FAILED_ENTRIES+=("$line") CI_FAILED_ENTRY_JOBS+=(-)
        done
        CI_UNRERUNNABLE=true ;;
      *) lookup_failed commit-status "unexpected combined state for $oid: $s_state" ;;
    esac
  fi
  if [ -n "$bad" ]; then CI_STATE=failed; CI_DETAIL="${bad#, }"
  elif [ -n "$waiting" ]; then CI_STATE=pending; CI_DETAIL="${waiting#, }"
  elif [ "$total" -eq 0 ]; then CI_STATE=missing; CI_DETAIL="no check runs or commit statuses"
  else CI_STATE=passed; CI_DETAIL="$total check(s) green"
  fi
}

ci_wait() { # ci_wait <oid>: returns only once CI passed on <oid>
  local oid="$1" deadline remaining sleep_for seen_passing="" failed_polls=0
  # The caller starts its own work for the wait (merge-cleanup, the next
  # PR's preparation) only once it sees this line.
  echo "land.sh: waiting for CI on $oid" >&2
  deadline=$(( SECONDS + CI_CAP_MINUTES * 60 ))
  while :; do
    # The poll loop is the retry and --interval its backoff, so each poll
    # reads once. A failed poll is no read: it resets the green count below.
    # A permanent failure, or three failed polls in a row, ends the wait.
    if GH_READ_ATTEMPTS=1 ci_read "$oid"; then
      failed_polls=0
    else
      ! gh_err_permanent || lookup_failed "$CI_WHAT" "$CI_DETAIL"
      failed_polls=$((failed_polls + 1))
      [ "$failed_polls" -lt 3 ] \
        || lookup_failed "$CI_WHAT" "$CI_DETAIL; 3 CI polls in a row failed"
      echo "land.sh: CI poll failed ($failed_polls of 3 in a row): $CI_DETAIL" >&2
    fi
    [ "$CI_STATE" != failed ] \
      || stop_failed "CI failed on $oid: $CI_DETAIL; fix the branch, then run check and land again"
    # Workflows register their checks asynchronously after a push, so one
    # green read can be a fast check finishing before a slow one exists.
    # Pass only on the second consecutive green read with the same check
    # count; a first green read at the cap is still unconfirmed.
    if [ "$CI_STATE" = passed ]; then
      [ "$seen_passing" != "$CI_DETAIL" ] || return 0
      seen_passing="$CI_DETAIL"
    else
      seen_passing=""
    fi
    remaining=$(( deadline - SECONDS ))
    if [ "$remaining" -le 0 ]; then
      [ "$CI_STATE" != unread ] \
        || lookup_failed "$CI_WHAT" "$CI_DETAIL; the last CI poll before the $CI_CAP_MINUTES-minute cap failed"
      [ "$CI_STATE" != passed ] \
        || stop checks-pending "CI on $oid read green only once before the $CI_CAP_MINUTES-minute cap, so a slower check may not have registered yet; rerun land to confirm it"
      [ "$CI_STATE" != pending ] \
        || stop checks-pending "CI is still running on $oid after $CI_CAP_MINUTES minute(s): $CI_DETAIL; rerun land when it finishes"
      stop checks-missing "nothing reported CI on $oid within $CI_CAP_MINUTES minute(s); an unchecked commit is not green"
    fi
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

# Remove land's temporary worktree. It holds only a detached checkout of
# commits already in the object store, plus whatever hooks wrote there or a
# rebase left paused, so --force discards nothing of value.
remove_land_worktree() { # fails only when git cannot remove it
  local rc=0
  [ -n "$LAND_TMP_WT" ] || return 0
  if git worktree remove --force -- "$LAND_TMP_WT/wt" >/dev/null 2>&1; then
    rm -rf -- "$LAND_TMP_WT"
  else
    echo "land.sh: could not remove the temporary worktree at $LAND_TMP_WT/wt; remove it with git worktree remove --force" >&2
    rc=1
  fi
  LAND_TMP_WT=""
  return "$rc"
}

# Move local $BRANCH from <from> to <to>. A worktree that holds the branch
# moves with it through checkout --no-overwrite-ignore, which changes nothing
# when an ignored file is in the way: at a path <to> tracks, inside a
# directory <to> replaces with a file, or at a file <to> replaces with a
# directory. A plain rebase or reset overwrites or deletes such a file.
# Without a worktree only the ref moves, and only if it still holds <from>.
land_move_branch() { # land_move_branch <from> <to>; sets MOVE_ERR on failure
  local cur
  MOVE_ERR="" MOVE_IGNORED=false
  if [ -z "$LAND_WT" ]; then
    git update-ref "refs/heads/$BRANCH" "$2" "$1" >/dev/null 2>&1 && return 0
    MOVE_ERR="local $BRANCH no longer holds $1"
    return 1
  fi
  cur=$(git rev-parse --verify --quiet "refs/heads/$BRANCH")
  if [ "$cur" != "$1" ]; then
    MOVE_ERR="local $BRANCH is ${cur:-unreadable}, not $1"
    return 1
  fi
  # Submodule recursion would not pass --no-overwrite-ignore down. The C
  # locale keeps git's refusal text matchable. A failing post-checkout hook
  # fails the command after the move, so the ref and a clean index decide.
  MOVE_ERR=$(LC_ALL=C git -C "$LAND_WT" checkout --quiet --no-overwrite-ignore \
    --no-recurse-submodules -B "$BRANCH" "$2" 2>&1 >/dev/null) && return 0
  case "$MOVE_ERR" in *untracked*) MOVE_IGNORED=true ;; esac
  MOVE_ERR=$(printf '%s' "$MOVE_ERR" | tr -d '\0' | tr '\n\t' '  ' | tail -c 300)
  cur=$(git rev-parse --verify --quiet "refs/heads/$BRANCH")
  [ "$cur" = "$2" ] && [ -z "$(git -C "$LAND_WT" status --porcelain -uno --ignore-submodules=all 2>/dev/null)" ]
}

# Rebase the reviewed head onto LAND_TIP in a temporary detached worktree,
# so the rebase never runs where ignored files live, then move the local
# branch to the result. Sets NEW_HEAD and LAND_WT (the worktree that holds
# the branch, or empty). Every refusal here leaves $BRANCH at HEAD_OID and
# pushes nothing.
land_rebase() {
  local wt dirty err conflicts detail cur
  worktree_scan "refs/heads/$BRANCH"; LAND_WT="$WT_MATCH"
  if [ -n "$LAND_WT" ]; then
    dirty=$(git -C "$LAND_WT" status -uall --porcelain 2>/dev/null) \
      || lookup_failed head-worktree "could not read the status of the head worktree at $LAND_WT"
    [ -z "$dirty" ] \
      || stop dirty-tree "the head worktree at $LAND_WT has uncommitted changes; land does not move it under them"
    if op_probe "$LAND_WT"; then
      stop op-in-progress "$OP_FOUND exists in the head worktree at $LAND_WT"
    fi
  fi
  # The land-wt template is how merge-cleanup's worktree-sweep.sh tells a
  # worktree a dead lander left from any other detached worktree.
  LAND_TMP_WT=$(mktemp -d "${TMPDIR:-/tmp}/land-wt.XXXXXX") || lookup_failed rebase "mktemp failed"
  wt="$LAND_TMP_WT/wt"
  if ! git worktree add --quiet --detach -- "$wt" "$HEAD_OID" >/dev/null 2>&1; then
    # A failing post-checkout hook fails the add after registering it.
    git worktree remove --force -- "$wt" >/dev/null 2>&1
    rm -rf -- "$LAND_TMP_WT"; LAND_TMP_WT=""
    lookup_failed rebase "could not add a temporary worktree at $HEAD_OID"
  fi
  # This replaces the startup EXIT trap, so it keeps removing GH_ERR,
  # GH_OUT, and GH_LOG too.
  trap 'remove_land_worktree; rm -f -- "$GH_ERR" "$GH_OUT" "$GH_LOG"' EXIT
  err=$(mktemp) || lookup_failed rebase "mktemp failed"
  # Pin the settings that would let a rebase touch more than this commit:
  # autostash stashes and reapplies work, and updateRefs moves branches.
  if ! git -C "$wt" -c rebase.autoStash=false -c rebase.updateRefs=false -c rebase.backend=merge -c rerere.enabled=false \
      rebase --quiet "$LAND_TIP" >/dev/null 2>"$err"; then
    detail=$(tr -d '\0' < "$err" | tail -c 300); rm -f "$err"
    conflicts=$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
    [ -n "$conflicts" ] \
      || stop rebase-failed "rebasing $HEAD_OID onto $LAND_TIP failed without conflicts; $BRANCH is unchanged: $detail"
    [ -n "$PREP_BASE" ] \
      || stop rebase-conflict "rebasing $BRANCH onto $BASE tip $LAND_TIP conflicts in: ${conflicts% }. $BRANCH is unchanged at $HEAD_OID. Rebase it by hand, read git range-diff, push, then run check and land again"
    land_replay "$wt" \
      || { git -C "$wt" rebase --abort >/dev/null 2>&1
           stop rebase-conflict "rebasing $BRANCH onto $BASE tip $LAND_TIP conflicts in: ${conflicts% }, and the prepared resolution $PREPARED did not replay: $REPLAY_ERR. $BRANCH is unchanged at $HEAD_OID and nothing was pushed. Rebase it by hand, read git range-diff, push, then run check and land again"; }
  fi
  rm -f "$err"
  NEW_HEAD=$(git -C "$wt" rev-parse --verify HEAD 2>/dev/null) \
    || lookup_failed rebase "could not read the rebased head"
  # A leaked worktree would outlive the run unnoticed; stop while nothing
  # has moved.
  remove_land_worktree \
    || stop rebase-failed "the temporary worktree at $wt could not be removed; $BRANCH is unchanged at $HEAD_OID and nothing was pushed"
  # Every commit already on the base leaves nothing to land; pushing the
  # base tip as the head would empty the PR.
  [ "$NEW_HEAD" != "$LAND_TIP" ] \
    || stop rebase-failed "every commit on $BRANCH is already on $BASE, so there is nothing to land; $BRANCH is unchanged at $HEAD_OID"
  if ! land_move_branch "$HEAD_OID" "$NEW_HEAD"; then
    cur=$(git rev-parse --verify --quiet "refs/heads/$BRANCH")
    # A refusal leaves both the ref and the index at HEAD_OID; anything else
    # is a half-finished move that needs a person.
    [ "$cur" = "$HEAD_OID" ] && [ -z "$(git -C "${LAND_WT:-.}" status --porcelain -uno --ignore-submodules=all 2>/dev/null)" ] \
      || stop rebase-failed "moving $BRANCH to the rebased $NEW_HEAD failed partway: $BRANCH is ${cur:-unreadable} and nothing was pushed; inspect it by hand: $MOVE_ERR"
    [ "$MOVE_IGNORED" = false ] \
      || stop ignored-clobber "moving the head worktree at $LAND_WT to the rebased $NEW_HEAD would overwrite or remove ignored files, so nothing moved and nothing was pushed; move them aside, then rerun land: $MOVE_ERR"
    stop rebase-failed "could not move $BRANCH to the rebased $NEW_HEAD; it is unchanged at $HEAD_OID and nothing was pushed: $MOVE_ERR"
  fi
  # The agent judges the rebase from this, as it would a manual one.
  echo "land.sh: rebased $BRANCH onto $LAND_TIP; git range-diff $LAND_TIP $HEAD_OID $NEW_HEAD:" >&2
  git range-diff --no-color "$LAND_TIP" "$HEAD_OID" "$NEW_HEAD" >&2 2>/dev/null \
    || echo "land.sh: (git range-diff failed; compare the commits by hand)" >&2
}

# Is a rebase paused in <dir>? Its state directory is per-worktree.
rebase_paused() { # rebase_paused <dir>
  local gp
  out_exact gp git -C "$1" rev-parse --git-path rebase-merge || return 1
  (cd "$1" && [ -d "$gp" ])
}

# The facts a pick must share with the prepared commit it takes the tree
# of: rebase keeps the author and the message, so a different commit, or
# the same commits in another order, differs here.
pick_identity() { # pick_identity <dir> <rev>
  git -C "$1" log -1 --date=raw --format='%an%x00%ae%x00%ad%x00%B' "$2" 2>/dev/null
}

# Finish a conflicted rebase in <dir> with the preparation's resolutions.
# At each conflict stop, the k-th pick takes the tree of the preparation's
# k-th commit, but only when the commit being picked has that commit's
# identity and the rebase so far has the tree of the preparation's first
# k-1 commits. The rebase must then end with as many commits as the
# preparation and with its tree. Any other outcome returns 1 with
# REPLAY_ERR set and the rebase possibly still paused; nothing outside the
# temporary worktree has moved. The base-tree check in phase_land is what
# makes taking whole trees safe.
land_replay() { # land_replay <dir>
  local wt="$1" picks done_n k pick prev
  REPLAY_ERR=""
  picks=$(git rev-list --reverse "$PREP_BASE..$PREPARED" 2>/dev/null) \
    || { REPLAY_ERR="could not list the prepared commits"; return 1; }
  while rebase_paused "$wt"; do
    [ -n "$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null)" ] \
      || { REPLAY_ERR="the rebase paused without a conflict"; return 1; }
    done_n=$(git -C "$wt" rev-list --count "$LAND_TIP..HEAD" 2>/dev/null) \
      || { REPLAY_ERR="could not count the rebased commits"; return 1; }
    k=$((done_n + 1))
    pick=$(sed -n "${k}p" <<< "$picks")
    [ -n "$pick" ] || { REPLAY_ERR="the preparation has no commit $k"; return 1; }
    if [ "$k" -eq 1 ]; then prev="$PREP_BASE"; else prev=$(sed -n "$((k - 1))p" <<< "$picks"); fi
    [ "$(git -C "$wt" rev-parse 'HEAD^{tree}' 2>/dev/null)" = "$(git rev-parse "$prev^{tree}")" ] \
      || { REPLAY_ERR="the rebase before commit $k differs from the preparation"; return 1; }
    [ "$(pick_identity "$wt" REBASE_HEAD)" = "$(pick_identity "$wt" "$pick")" ] \
      || { REPLAY_ERR="commit $k of the rebase is not the preparation's commit $k"; return 1; }
    git -C "$wt" read-tree -u --reset "$pick" >/dev/null 2>&1 \
      || { REPLAY_ERR="could not check out the prepared tree of commit $k"; return 1; }
    # The loop reads the outcome: a later conflict pauses again, and any
    # other failure leaves a pause without conflicts.
    # GIT_EDITOR outranks core.editor, so only it keeps a waiting editor
    # from a caller's environment out of the run.
    GIT_EDITOR=true git -C "$wt" -c rerere.enabled=false rebase --continue >/dev/null 2>&1
  done
  [ "$(git -C "$wt" rev-list --count "$LAND_TIP..HEAD" 2>/dev/null)" = "$(sed -n '$=' <<< "$picks")" ] \
    || { REPLAY_ERR="the rebase made a different number of commits than the preparation"; return 1; }
  [ "$(git -C "$wt" rev-parse 'HEAD^{tree}' 2>/dev/null)" = "$PREP_TREE" ] \
    || { REPLAY_ERR="the rebased tree is not the prepared tree"; return 1; }
}

# Push the rebased branch with a lease on the reviewed head, so a push that
# landed after check fails instead of being overwritten. A refused push puts
# the local branch back at HEAD_OID, so check and land can run again from a
# state that agrees with the forge.
land_push() { # land_push <remote> <ssh-pin-or-empty>
  local err detail restored=yes
  err=$(mktemp) || lookup_failed push "mktemp failed"
  if ! git_with_ssh_pin "$2" push --quiet \
      --force-with-lease="refs/heads/$BRANCH:$HEAD_OID" \
      -- "$1" "refs/heads/$BRANCH:refs/heads/$BRANCH" >/dev/null 2>"$err"; then
    detail=$(tr -d '\0' < "$err" | tail -c 300); rm -f "$err"
    land_move_branch "$NEW_HEAD" "$HEAD_OID" || restored=no
    if [ "$restored" = yes ]; then
      stop lease-failed "the lease-protected push of rebased $BRANCH to $1 was refused, and local $BRANCH is back at $HEAD_OID; the remote branch may have moved since check: $detail"
    fi
    stop lease-failed "the lease-protected push of rebased $BRANCH to $1 was refused, and local $BRANCH could not be put back from $NEW_HEAD to $HEAD_OID: $detail"
  fi
  rm -f "$err"
}

# Wait for the forge's PR head to show the pushed commit; it updates
# asynchronously. Any third OID means someone else pushed.
land_await_forge_head() {
  local deadline remaining sleep_for fields state oid
  deadline=$(( SECONDS + CI_CAP_MINUTES * 60 ))
  while :; do
    fields=$(gh_read pr view "$PR" --repo="$REPO" --json state,headRefOid \
      --jq '[.state,.headRefOid] | @tsv') \
      || lookup_failed pr-view "could not reread PR $PR after the push"
    IFS=$'\t' read -r state oid <<< "$fields"
    [ "$state" = OPEN ] || stop pr-not-open "PR $PR is $state after land pushed $NEW_HEAD"
    [ "$oid" != "$NEW_HEAD" ] || return 0
    [ "$oid" = "$HEAD_OID" ] \
      || stop oid-mismatch "after land pushed $NEW_HEAD the forge reports head $oid; something else pushed to $BRANCH"
    remaining=$(( deadline - SECONDS ))
    [ "$remaining" -gt 0 ] \
      || lookup_failed pr-head "the forge still reports head $HEAD_OID after land pushed $NEW_HEAD; rerun check and land once it catches up"
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

# Use the preparation only when the fetched base tip has the tree of the
# commit it was prepared onto, its merge base with the tip. A base that
# moved by more than the predecessor's merge fails this, and the run goes
# on exactly as without --prepared.
prepared_check() {
  local base from made
  from=$(git rev-parse --verify --quiet "$PREPARED_HEAD_REF^{commit}") || from=""
  made=$(git rev-parse --verify --quiet "$PREPARED_COMMIT_REF^{commit}") || made=""
  prepared_refs_clear
  if [ "$from" != "$HEAD_OID" ] || [ "$made" != "$PREPARED" ]; then
    echo "land.sh: ignoring --prepared: the latest preparation of PR $PR is head ${from:-none} as ${made:-none}, not --head $HEAD_OID as $PREPARED" >&2
    return 0
  fi
  if ! git cat-file -e "$PREPARED^{commit}" 2>/dev/null; then
    echo "land.sh: ignoring --prepared: $PREPARED is not a commit in this repository" >&2
    return 0
  fi
  base=$(git merge-base "$PREPARED" "$LAND_TIP" 2>/dev/null) || base=""
  if [ -z "$base" ] \
      || [ "$(git rev-parse "$base^{tree}")" != "$(git rev-parse "$LAND_TIP^{tree}")" ]; then
    echo "land.sh: ignoring --prepared: $BASE tip $LAND_TIP has another tree than the base $PREPARED was prepared onto" >&2
    return 0
  fi
  PREP_BASE="$base"
  PREP_TREE=$(git rev-parse "$PREPARED^{tree}") \
    || lookup_failed prepared "could not read the tree of $PREPARED"
}

# Read every check once and report what land would do, changing nothing
# beyond the base fetch. The STOP or OK line is what a real run would hit
# first; stderr carries all three results either way.
land_dry_run() { # land_dry_run <on-tip>
  local on_tip="$1" tip_msg ci_msg base_msg summary
  ci_read "$HEAD_OID" || lookup_failed "$CI_WHAT" "$CI_DETAIL"
  forge_base_tip
  if [ "$on_tip" = true ]; then
    tip_msg="head $HEAD_OID contains the fetched $BASE tip $LAND_TIP"
  elif [ "$IS_FORK" = true ]; then
    tip_msg="head $HEAD_OID is not on the fetched $BASE tip $LAND_TIP, and a cross-repository head must be rebased by its author"
  else
    tip_msg="head $HEAD_OID is not on the fetched $BASE tip $LAND_TIP; land would rebase it, push it with a lease on $HEAD_OID, and stop for the new head's range-diff"
  fi
  ci_msg="CI on $HEAD_OID is $CI_STATE ($CI_DETAIL)"
  if [ "$FORGE_BASE_TIP" = "$LAND_TIP" ]; then
    base_msg="the forge's $BASE tip is still the fetched $LAND_TIP"
  else
    base_msg="the forge's $BASE tip $FORGE_BASE_TIP differs from the fetched $LAND_TIP"
  fi
  printf 'land.sh: land dry run, PR %s:\n  tip:    %s\n  checks: %s\n  base:   %s\n' \
    "$PR" "$tip_msg" "$ci_msg" "$base_msg" >&2
  summary="dry run, nothing changed. tip: $tip_msg. checks: $ci_msg. base: $base_msg"
  [ "$on_tip" = true ] || stop not-on-tip "$summary"
  case "$CI_STATE" in
    failed) stop_failed "$summary" ;;
    pending) stop checks-pending "$summary; a real run waits up to $CI_CAP_MINUTES minute(s)" ;;
    missing) stop checks-missing "$summary; a real run waits up to $CI_CAP_MINUTES minute(s)" ;;
  esac
  [ "$FORGE_BASE_TIP" = "$LAND_TIP" ] || stop base-moved "$summary"
  echo "OK land {\"dry_run\":true,\"head_oid\":\"$HEAD_OID\",\"base_tip\":\"$LAND_TIP\",\"checks\":\"$CI_STATE\",\"would\":\"merge\"}"
  exit 0
}

# --- prepare ----------------------------------------------------------------

# Create a missing local head branch at HEAD_OID, only when the head remote's
# branch is that commit. A branch pushed from another machine has no local
# ref, and check and land need one at the pinned head. Sets CREATED_BRANCH.
prepare_local_branch() { # prepare_local_branch <head-remote>
  local tmp_ref="refs/land/prepare-$PR" fetched
  CREATED_BRANCH=false
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    [ "$(git rev-parse "refs/heads/$BRANCH")" = "$HEAD_OID" ] \
      || stop oid-mismatch "local $BRANCH is $(git rev-parse "refs/heads/$BRANCH"), not the pinned head $HEAD_OID; prepare does not move an existing branch"
    return 0
  fi
  git_fetch -- "$1" "+refs/heads/$BRANCH:$tmp_ref" \
    || lookup_failed head-fetch "could not fetch $BRANCH from $1"
  fetched=$(git rev-parse --verify --quiet "$tmp_ref^{commit}")
  git update-ref -d "$tmp_ref" >/dev/null 2>&1
  [ "$fetched" = "$HEAD_OID" ] \
    || stop oid-mismatch "$1's $BRANCH is ${fetched:-unreadable}, not the pinned head $HEAD_OID; no local branch was created"
  # The empty old value creates the ref only if nothing made it meanwhile.
  git update-ref "refs/heads/$BRANCH" "$HEAD_OID" "" >/dev/null 2>&1 \
    || stop oid-mismatch "could not create local $BRANCH at $HEAD_OID; another run may have created it"
  CREATED_BRANCH=true
}

# Record the latest preparation, for land --prepared to match.
prepared_refs_write() { # prepared_refs_write <prepared-commit>
  git update-ref "$PREPARED_HEAD_REF" "$HEAD_OID" >/dev/null 2>&1 \
    && git update-ref "$PREPARED_COMMIT_REF" "$1" >/dev/null 2>&1 \
    || lookup_failed prepare "could not write $PREPARED_HEAD_REF and $PREPARED_COMMIT_REF"
}
prepared_refs_clear() {
  git update-ref -d "$PREPARED_HEAD_REF" >/dev/null 2>&1
  git update-ref -d "$PREPARED_COMMIT_REF" >/dev/null 2>&1
}

# Record a resolved conflict worktree as the preparation. The marker ties
# it to this PR, head, and onto; the rebase must be finished, so its HEAD
# is the whole prepared result.
prepare_record() {
  local wt prepared tree rc=0
  prepared_worktree_check "$DROP_WT"
  wt="$PW_WT"
  { grep -qxF -- "head: $HEAD_OID" "$PW_DIR/$PREPARE_MARKER" \
      && grep -qxF -- "onto: $ONTO" "$PW_DIR/$PREPARE_MARKER"; } \
    || stop not-prepared "$wt was prepared from another --head or --onto; nothing was recorded"
  ! rebase_paused "$wt" \
    || stop rebase-paused "the rebase in $wt is still paused; finish it with git rebase --continue there, then record it"
  prepared=$(git -C "$wt" rev-parse --verify HEAD 2>/dev/null) \
    || lookup_failed prepare "could not read the HEAD of $wt"
  git merge-base --is-ancestor "$ONTO" "$prepared" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] && [ "$prepared" != "$ONTO" ] \
    || stop rebase-failed "the HEAD of $wt, $prepared, is not a commit on top of --onto $ONTO; nothing was recorded"
  tree=$(git rev-parse "$prepared^{tree}") || lookup_failed prepare "could not read the prepared tree"
  prepared_refs_clear
  prepared_refs_write "$prepared"
  echo "land.sh: recorded $wt; git range-diff $ONTO $HEAD_OID $prepared:" >&2
  git range-diff --no-color "$ONTO" "$HEAD_OID" "$prepared" >&2 2>/dev/null \
    || echo "land.sh: (git range-diff failed; compare the commits by hand)" >&2
  echo "OK prepare {\"head_oid\":\"$HEAD_OID\",\"onto\":\"$ONTO\",\"prepared_oid\":\"$prepared\",\"tree\":\"$tree\",\"worktree\":\"$(json_escape "$wt")\",\"created_branch\":false}"
  exit 0
}

# Remove prepare's directory. Before the worktree exists only the marker
# is there; after, git removes the worktree first, as in land.
prepare_cleanup() {
  [ -n "$LAND_TMP_WT" ] || return 0
  if [ -e "$LAND_TMP_WT/wt" ]; then
    remove_land_worktree
  else
    rm -rf -- "$LAND_TMP_WT"; LAND_TMP_WT=""
  fi
}

# Rebase a copy of the head onto ONTO in a marked land-wt worktree. Only
# the base remote's tracking ref, a missing local head branch, and the
# worktree change; the reviewed branch, the forge, and the checkout this
# runs from stay as they were.
phase_prepare() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  [ "$FORGE_HEAD_OID" = "$HEAD_OID" ] \
    || stop oid-mismatch "the forge reports head $FORGE_HEAD_OID but --head pinned $HEAD_OID"
  [ "$IS_FORK" != true ] \
    || stop not-on-tip "PR $PR's head is in another repository, and land does not push to it, so there is nothing to prepare"
  [ "$HAVE_DROP_WT" = false ] || prepare_record
  collision_check
  local head_remote rc=0 wt err conflicts detail prepared tree
  if [ -n "$BASE_REMOTE_OPT" ]; then
    BASE_REMOTE="$BASE_REMOTE_OPT"
  else
    resolve_remote "$REPO"
    [ -n "$RESOLVED_REMOTE" ] \
      || stop remote-unresolved "no configured remote's URL matches $REPO; pass --base-remote"
    BASE_REMOTE="$RESOLVED_REMOTE"
  fi
  remote_repo_check "$BASE_REMOTE" base
  head_remote="${HEAD_REMOTE_OPT:-$BASE_REMOTE}"
  [ "$head_remote" = "$BASE_REMOTE" ] || remote_repo_check "$head_remote" head
  git_fetch -- "$BASE_REMOTE" "+refs/heads/$BASE:refs/remotes/$BASE_REMOTE/$BASE" \
    || lookup_failed base-fetch "could not fetch $BASE from $BASE_REMOTE"
  LAND_TIP=$(git rev-parse --verify --quiet "refs/remotes/$BASE_REMOTE/$BASE^{commit}") \
    || lookup_failed base-fetch "the fetched $BASE did not resolve to a commit"
  git cat-file -e "$ONTO^{commit}" 2>/dev/null \
    || stop onto-not-on-tip "--onto $ONTO is not a commit in this repository"
  git merge-base --is-ancestor "$LAND_TIP" "$ONTO" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) ;;
    1) stop onto-not-on-tip "--onto $ONTO does not contain the fetched $BASE tip $LAND_TIP, so its tree is not the tree $BASE will have after it merges" ;;
    *) lookup_failed ancestry "could not compare $ONTO with $BASE tip $LAND_TIP (git merge-base exit $rc)" ;;
  esac
  prepare_local_branch "$head_remote"
  # A new preparation supersedes the last, whatever this one's outcome.
  prepared_refs_clear

  # The marker goes in before the worktree, so a run killed in between
  # still leaves a directory drop accepts.
  LAND_TMP_WT=$(mktemp -d "${TMPDIR:-/tmp}/land-wt.XXXXXX") || lookup_failed prepare "mktemp failed"
  trap 'prepare_cleanup; rm -f -- "$GH_ERR" "$GH_OUT" "$GH_LOG"' EXIT
  printf 'pr: %s\nhead: %s\nonto: %s\n' "$PR" "$HEAD_OID" "$ONTO" > "$LAND_TMP_WT/$PREPARE_MARKER" \
    || lookup_failed prepare "could not write the prepare marker in $LAND_TMP_WT"
  wt="$LAND_TMP_WT/wt"
  git worktree add --quiet --detach -- "$wt" "$HEAD_OID" >/dev/null 2>&1 \
    || lookup_failed prepare "could not add a temporary worktree at $HEAD_OID"
  err=$(mktemp) || lookup_failed prepare "mktemp failed"
  if ! git -C "$wt" -c rebase.autoStash=false -c rebase.updateRefs=false -c rebase.backend=merge -c rerere.enabled=false \
      rebase --quiet "$ONTO" >/dev/null 2>"$err"; then
    detail=$(tr -d '\0' < "$err" | tail -c 300); rm -f "$err"
    conflicts=$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
    [ -n "$conflicts" ] \
      || stop rebase-failed "rebasing $HEAD_OID onto $ONTO failed without conflicts: $detail"
    # Keep the paused rebase for the caller to resolve; drop removes it.
    LAND_TMP_WT=""
    echo "STOP rebase-conflict {\"detail\":\"$(json_escape "rebasing $BRANCH onto $ONTO conflicts in: ${conflicts% }. Resolve them in the worktree under the rework rule, finish with git rebase --continue there, and record it with prepare --worktree; drop removes the worktree. Nothing else changed")\",\"worktree\":\"$(json_escape "$wt")\",\"conflicts\":\"$(json_escape "${conflicts% }")\",\"created_branch\":$CREATED_BRANCH}"
    exit 2
  fi
  rm -f "$err"
  prepared=$(git -C "$wt" rev-parse --verify HEAD 2>/dev/null) \
    || lookup_failed prepare "could not read the prepared head"
  tree=$(git rev-parse "$prepared^{tree}") || lookup_failed prepare "could not read the prepared tree"
  [ "$prepared" != "$ONTO" ] \
    || stop rebase-failed "every commit on $BRANCH is already in $ONTO, so there is nothing to land"
  echo "land.sh: prepared $BRANCH onto $ONTO; git range-diff $ONTO $HEAD_OID $prepared:" >&2
  git range-diff --no-color "$ONTO" "$HEAD_OID" "$prepared" >&2 2>/dev/null \
    || echo "land.sh: (git range-diff failed; compare the commits by hand)" >&2
  prepare_cleanup \
    || stop prepare-failed "the temporary worktree at $wt could not be removed"
  prepared_refs_write "$prepared"
  echo "OK prepare {\"head_oid\":\"$HEAD_OID\",\"onto\":\"$ONTO\",\"prepared_oid\":\"$prepared\",\"tree\":\"$tree\",\"created_branch\":$CREATED_BRANCH}"
}

# --- rerun ------------------------------------------------------------------

# Wait until every workflow run on HEAD_OID has finished: GitHub refuses
# to rerun a run that is still going, and land stops checks-failed at the
# first failed check. Sets RERUN_FAILED to "<run_id> <run_attempt>" lines
# for each run whose conclusion would fail ci_read. Polls like ci_wait: one
# attempt per poll, ending at a permanent error or three failed polls.
rerun_await_runs() {
  local deadline remaining sleep_for runs id st concl attempt busy="" unread failed_polls=0
  deadline=$(( SECONDS + CI_CAP_MINUTES * 60 ))
  while :; do
    if runs=$(GH_READ_ATTEMPTS=1 gh_read api --paginate \
        "repos/$REPO/actions/runs?head_sha=$HEAD_OID&per_page=100" \
        --jq '.workflow_runs[] | [(.id | tostring), .status, (.conclusion // "none"), (.run_attempt | tostring)] | @tsv'); then
      unread=false failed_polls=0 busy="" RERUN_FAILED=""
      while IFS=$'\t' read -r id st concl attempt; do
        [ -n "$id" ] || continue
        case "$id:$attempt" in *[!0-9:]*|:*|*:)
          lookup_failed workflow-runs "unexpected workflow run fields on $HEAD_OID: $id, attempt $attempt" ;;
        esac
        if [ "$st" != completed ]; then
          busy+=", run $id ($st)"
        else
          case "$concl" in
            success|neutral|skipped) ;;
            *) RERUN_FAILED+="$id $attempt"$'\n' ;;
          esac
        fi
      done <<< "$runs"
      [ -n "$busy" ] || return 0
    else
      ! gh_err_permanent || lookup_failed workflow-runs "could not read the workflow runs on $HEAD_OID"
      unread=true failed_polls=$((failed_polls + 1))
      [ "$failed_polls" -lt 3 ] \
        || lookup_failed workflow-runs "could not read the workflow runs on $HEAD_OID; 3 polls in a row failed"
      echo "land.sh: workflow-run poll failed ($failed_polls of 3 in a row)" >&2
    fi
    remaining=$(( deadline - SECONDS ))
    if [ "$remaining" -le 0 ]; then
      [ "$unread" = false ] \
        || lookup_failed workflow-runs "could not read the workflow runs on $HEAD_OID; the last poll before the $CI_CAP_MINUTES-minute cap failed"
      stop checks-pending "workflow runs on $HEAD_OID are still running after $CI_CAP_MINUTES minute(s): ${busy#, }; nothing was rerun"
    fi
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

# Wait until no check run in <job-ids> is still the latest for its name on
# HEAD_OID. Until GitHub registers the rerun jobs, the head's latest check
# runs still show the old failure, and a land run in that gap would stop
# checks-failed on a flake that was never retried. Sets RERUN_STALE to the
# ids still listed.
rerun_await_registration() { # rerun_await_registration <job-ids>
  local ids="$1" listed id deadline remaining sleep_for unread failed_polls=0
  deadline=$(( SECONDS + CI_CAP_MINUTES * 60 ))
  while :; do
    if listed=$(GH_READ_ATTEMPTS=1 gh_read api --paginate \
        "repos/$REPO/commits/$HEAD_OID/check-runs?per_page=100" --jq '.check_runs[].id'); then
      unread=false failed_polls=0 RERUN_STALE=""
      for id in $ids; do
        ! grep -qxF -- "$id" <<< "$listed" || RERUN_STALE+=" $id"
      done
      [ -n "$RERUN_STALE" ] || return 0
    else
      ! gh_err_permanent || lookup_failed check-runs "could not read check runs for $HEAD_OID after the rerun request"
      unread=true failed_polls=$((failed_polls + 1))
      [ "$failed_polls" -lt 3 ] \
        || lookup_failed check-runs "could not read check runs for $HEAD_OID after the rerun request; 3 polls in a row failed"
      echo "land.sh: check-run poll failed ($failed_polls of 3 in a row)" >&2
    fi
    remaining=$(( deadline - SECONDS ))
    if [ "$remaining" -le 0 ]; then
      [ "$unread" = false ] \
        || lookup_failed check-runs "could not read check runs for $HEAD_OID after the rerun request; the last poll before the $CI_CAP_MINUTES-minute cap failed"
      stop rerun-unconfirmed "the reruns were requested, but after $CI_CAP_MINUTES minute(s) the failed check run(s)$RERUN_STALE are still the latest on $HEAD_OID, so land would read the old failure"
    fi
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

# --- phases -----------------------------------------------------------------

phase_check() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  collision_check
  workspace_preflight
  layout_check
  consumer_checks
  queue_check
  # The verified head is the tip this session pushed: the local branch is
  # primary because a forge-reported head can move with a third party's
  # push, while nothing moves the local ref but this checkout. The forge
  # value is the cross-check; disagreement means the branch moved after
  # the review evidence was collected.
  local local_tip
  git show-ref --verify --quiet "refs/heads/$BRANCH" \
    || stop no-local-branch "no local $BRANCH in this repository: the verified head must be the tip this session pushed, so run the phases from the clone that pushed it (any of its worktrees sees the ref)"
  local_tip=$(git rev-parse "refs/heads/$BRANCH")
  [ "$local_tip" = "$FORGE_HEAD_OID" ] \
    || stop oid-mismatch "local $BRANCH is $local_tip but the forge reports $FORGE_HEAD_OID; the branch moved"
  echo "OK check {\"head_oid\":\"$FORGE_HEAD_OID\",\"head_branch\":\"$(json_escape "$BRANCH")\",\"base_branch\":\"$(json_escape "$BASE")\",\"fork\":$IS_FORK,\"queue\":\"$QUEUE\",\"stacked_prs\":$STACKED_PRS}"
}

phase_land() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  [ "$FORGE_HEAD_OID" = "$HEAD_OID" ] \
    || stop oid-mismatch "the forge reports head $FORGE_HEAD_OID but --head pinned $HEAD_OID; something was pushed since check"
  load_repo_facts
  layout_check
  # The local branch is what a rebase rewrites, so it must be the reviewed
  # head too, as check required.
  local local_tip rc=0 on_tip fields head_remote head_pin="" hr_furl
  git show-ref --verify --quiet "refs/heads/$BRANCH" \
    || stop no-local-branch "no local $BRANCH in this repository: run land from the clone that pushed it"
  local_tip=$(git rev-parse "refs/heads/$BRANCH")
  [ "$local_tip" = "$HEAD_OID" ] \
    || stop oid-mismatch "local $BRANCH is $local_tip, not the reviewed head $HEAD_OID"
  # merge repeats these at the end; asking first keeps a rebase push from
  # rewriting a branch that another PR heads or a cross-repository PR stacks
  # on. Same-repository children are only reported: the rebase leaves them on
  # the parent's pre-rebase commits, which their own land rebase drops.
  consumer_checks
  queue_check

  if [ -n "$BASE_REMOTE_OPT" ]; then
    BASE_REMOTE="$BASE_REMOTE_OPT"
  else
    resolve_remote "$REPO"
    [ -n "$RESOLVED_REMOTE" ] \
      || stop remote-unresolved "no configured remote's URL matches $REPO; pass --base-remote"
    BASE_REMOTE="$RESOLVED_REMOTE"
  fi
  remote_repo_check "$BASE_REMOTE" base
  # The + lets a base force-pushed to a non-descendant still update the
  # tracking ref, so the checks below judge the base as it is now.
  git_fetch -- "$BASE_REMOTE" "+refs/heads/$BASE:refs/remotes/$BASE_REMOTE/$BASE" \
    || lookup_failed base-fetch "could not fetch $BASE from $BASE_REMOTE"
  LAND_TIP=$(git rev-parse --verify --quiet "refs/remotes/$BASE_REMOTE/$BASE^{commit}") \
    || lookup_failed base-fetch "the fetched $BASE did not resolve to a commit"
  git merge-base --is-ancestor "$LAND_TIP" "$HEAD_OID" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) on_tip=true ;;
    1) on_tip=false ;;
    *) lookup_failed ancestry "could not compare $HEAD_OID with $BASE tip $LAND_TIP (git merge-base exit $rc)" ;;
  esac

  [ "$DRY_RUN" = false ] || land_dry_run "$on_tip"

  if [ "$on_tip" = false ]; then
    [ "$IS_FORK" != true ] \
      || stop not-on-tip "head $HEAD_OID is not on $BASE tip $LAND_TIP, and land does not push to another repository's branch; its author must rebase and push, then run check and land again"
    # A base remote that lags the forge would cost a rebase, a push, and a
    # CI wait before the final check caught it.
    forge_base_tip
    [ "$FORGE_BASE_TIP" = "$LAND_TIP" ] \
      || stop base-moved "the forge reports $BASE at $FORGE_BASE_TIP but $BASE_REMOTE fetched $LAND_TIP; nothing was rebased, so rerun land"
    # Validate the push destination before rewriting anything, so a remote
    # that fails here leaves the branch untouched.
    head_remote="${HEAD_REMOTE_OPT:-$BASE_REMOTE}"
    remote_repo_check "$head_remote" head
    head_pin="$PINNED_SSH_COMMAND"
    out_exact hr_furl git remote get-url -- "$head_remote" \
      || lookup_failed head-remote "could not read $head_remote's URL"
    push_ids_match "$head_remote" "$(url_id "$hr_furl")" \
      || stop pushurl-mismatch "$head_remote must have exactly one effective push destination matching its fetch URL; git broadcasts to every configured push URL"
    [ -z "$PREPARED" ] || prepared_check
    land_rebase
    land_push "$head_remote" "$head_pin"
    land_await_forge_head
    # A rebase that reproduced the reviewed preparation needs no second
    # read, so the run goes on to CI with the pushed head as its own.
    if [ -n "$PREP_BASE" ] \
        && [ "$(git rev-parse "$NEW_HEAD^{tree}" 2>/dev/null)" = "$PREP_TREE" ]; then
      PUSHED_HEAD="$NEW_HEAD" OLD_HEAD="$HEAD_OID"
      HEAD_OID="$NEW_HEAD" FORGE_HEAD_OID="$NEW_HEAD"
    else
      local prep_field=""
      if [ -n "$PREP_BASE" ]; then prep_field=',"prepared":"tree-mismatch"'
      elif [ -n "$PREPARED" ]; then prep_field=',"prepared":"ignored"'
      fi
      # CI reruns on the rebased commit, but nothing reviews its diff, so
      # the agent reads the range-diff printed above before landing it.
      echo "STOP rebased {\"head_oid\":\"$NEW_HEAD\",\"old_head_oid\":\"$HEAD_OID\",\"base_tip\":\"$LAND_TIP\"$prep_field,\"detail\":\"$(json_escape "rebased $BRANCH onto $BASE tip $LAND_TIP and pushed $NEW_HEAD; read the range-diff on stderr, then run check and land --head $NEW_HEAD")\"}"
      exit 2
    fi
  fi

  ci_wait "$HEAD_OID"

  # The CI wait can be long; merge's own guards need the PR as it is now.
  local base_now
  fields=$(gh_read pr view "$PR" --repo="$REPO" --json state,headRefOid,baseRefName \
    --jq '[.state,.headRefOid,.baseRefName] | @tsv') \
    || lookup_failed pr-view "could not reread PR $PR before the merge"
  IFS=$'\t' read -r PR_STATE FORGE_HEAD_OID base_now <<< "$fields"
  [ "$base_now" = "$BASE" ] \
    || stop base-moved "PR $PR now targets $base_now, not $BASE, which land checked the head against; run check and land again"
  phase_merge
}

# Record a merged PR until merge-cleanup for it finishes, so a lander that
# dies between the next PR's push and this cleanup finds it on its next
# list. list-ready.sh reads and clears the file.
record_cleanup() {
  local common
  common=$(git rev-parse --git-common-dir 2>/dev/null) && [ -n "$common" ] || return 1
  mkdir -p -- "$common/land-approved-prs" 2>/dev/null \
    && printf '%s\n' "$PR" >> "$common/land-approved-prs/cleanup-pending" 2>/dev/null
}

phase_merge() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  [ "$FORGE_HEAD_OID" = "$HEAD_OID" ] \
    || stop oid-mismatch "the forge reports head $FORGE_HEAD_OID but --head pinned $HEAD_OID; something was pushed since check"
  # Read the title before the last-moment destructive guards. No forge API
  # call sits between their final repository-settings refresh and merge.
  local title
  title=$(gh_read pr view "$PR" --repo="$REPO" --json title --jq .title) \
    || lookup_failed title "could not read the PR title"
  { [ -n "$title" ] && [ "$title" != null ]; } \
    || lookup_failed title "the PR title read back empty"
  # check's answers go stale in the gap where the caller verifies its own
  # guardrails: a retarget (a stacked PR's base merging) can change the
  # base branch and with it which merge queue applies, and a new PR can
  # start sharing the head branch, which the merge itself then auto-deletes.
  # Both are re-asked at the last moment before anything irreversible.
  queue_check
  consumer_checks
  # land's last refusal: the base tip it fetched and waited on must
  # still be the forge's tip. Only queue_message_check's settings reload,
  # which reads only under a merge queue, sits between this read and the
  # merge. The read and the merge are still not atomic; the landing design
  # accepts that while one person starts every merge.
  if [ -n "$LAND_TIP" ]; then
    forge_base_tip
    [ "$FORGE_BASE_TIP" = "$LAND_TIP" ] \
      || stop base-moved "$BASE moved from $LAND_TIP to $FORGE_BASE_TIP after land fetched it; $HEAD_OID was not checked against the new tip, so run check and land again"
  fi
  # consumer_checks loads repository facts for its lineage queries. Reload
  # them at the final boundary so a merge-commit setting changed while the
  # other guards ran cannot pass queue_message_check from the stale cache.
  REPO_FACTS_LOADED=""
  queue_message_check
  local err
  err=$(mktemp) || lookup_failed merge "mktemp failed"
  # A write, not a read: one attempt, kept outside gh_read, and its stderr
  # is quoted in STOP merge-refused, so gh's and Go's debug output stays
  # off as for every forge read.
  if ! GH_DEBUG= GODEBUG="$GH_GODEBUG" gh pr merge "$PR" --repo="$REPO" --merge \
      --match-head-commit="$HEAD_OID" \
      --subject="$title (#$PR)" --body="" 2>"$err"; then
    local detail; detail=$(tr -d '\0' < "$err" | tail -c 300); rm -f "$err"
    stop merge-refused "gh pr merge failed: $detail"
  fi
  rm -f "$err"
  # Zero exit proves enqueueing, not merging: on a queued base the command
  # returns once the PR is in the queue. Only the forge saying MERGED with
  # a non-null mergedAt is completion; deleting anything before that can
  # cancel the merge and take the branch's last copies with it.
  local deadline state merged_at remaining sleep_for
  deadline=$(( SECONDS + CAP_MINUTES * 60 ))
  while :; do
    # One attempt per poll: the loop already retries, and a failed poll's
    # stderr stays for the deadline's excerpt.
    if pr_fields=$(GH_READ_ATTEMPTS=1 gh_read pr view "$PR" --repo="$REPO" --json state,mergedAt \
        --jq '[.state,(.mergedAt // "null")] | @tsv'); then
      IFS=$'\t' read -r state merged_at <<< "$pr_fields"
      if [ "$state" = MERGED ] && [ "$merged_at" != null ]; then
        local cleanup_field=""
        record_cleanup || {
          echo "land.sh: merged, but could not record PR $PR in cleanup-pending; run merge-cleanup for it by hand" >&2
          cleanup_field=',"cleanup_recorded":false'
        }
        if [ "$PHASE" = land ]; then
          echo "OK land {\"head_oid\":\"$HEAD_OID\",\"merged_at\":\"$(json_escape "$merged_at")\"$(pushed_fields)$cleanup_field}"
        else
          echo "OK merge {\"merged_at\":\"$(json_escape "$merged_at")\"$cleanup_field}"
        fi
        return 0
      fi
      [ "$state" = OPEN ] || [ "$state" = MERGED ] \
        || stop pr-closed "PR $PR is $state after the merge command; nothing merged"
    else
      echo "land.sh: merge-state poll failed; retrying" >&2
    fi
    remaining=$(( deadline - SECONDS ))
    [ "$remaining" -gt 0 ] \
      || lookup_failed merge-pending "the forge has not reported PR $PR merged within $CAP_MINUTES minute(s); do not clean up until it does"
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

# One rerun of the head's failed Actions jobs. It touches no local ref, so
# it needs neither the repository facts nor a checkout guard. The budget
# lives in the forge, not in the caller's memory: a failed run whose
# run_attempt is above 1 was already rerun, by this skill or by hand.
phase_rerun() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  [ "$FORGE_HEAD_OID" = "$HEAD_OID" ] \
    || stop oid-mismatch "the forge reports head $FORGE_HEAD_OID but --head pinned $HEAD_OID; something was pushed since check"
  rerun_await_runs
  ci_read "$HEAD_OID" || lookup_failed "$CI_WHAT" "$CI_DETAIL"
  [ "$CI_UNRERUNNABLE" = false ] \
    || stop rerun-unsupported "a failure on $HEAD_OID is not a check traced to a GitHub Actions job, so gh run rerun cannot retry it: $CI_DETAIL; nothing was rerun"
  [ -n "$CI_FAILED_JOBS" ] \
    || stop nothing-to-rerun "no GitHub Actions job is failing on $HEAD_OID; CI is $CI_STATE ($CI_DETAIL)"
  # Rerun only the runs that own a failing latest check run. An older failed
  # run on the same commit (from a reopened PR, another branch, or a manual
  # dispatch) no longer decides CI: rerunning it could turn CI red again, and
  # its attempt count says nothing about this failure.
  local id a attempt run job targets="" orphan="" spent="" done_ids="" detail
  local runs_json="" jobs job_ids=""
  while read -r run job; do
    [ -n "$run" ] || continue
    case " $targets $orphan " in *" $run "*) continue ;; esac
    attempt=""
    while read -r id a; do
      [ "$id" != "$run" ] || attempt="$a"
    done <<< "$RERUN_FAILED"
    if [ -z "$attempt" ]; then orphan+=" $run"; continue; fi
    [ "$attempt" -le 1 ] || spent+=", run $run (attempt $attempt)"
    targets+=" $run"
  done <<< "$CI_FAILED_JOBS"
  [ -z "$orphan" ] \
    || stop rerun-unsupported "failing jobs on $HEAD_OID belong to workflow run(s)$orphan, which did not fail, so rerunning failed jobs cannot retry them; nothing was rerun"
  [ -z "$spent" ] \
    || stop rerun-spent "a failed run on $HEAD_OID was already rerun: ${spent#, }; a failure that repeats is evidence against a flake, so nothing was rerun"
  # A write, not a read: one attempt, and its stderr is quoted in the stop,
  # so gh's and Go's debug output stays off as for every forge read.
  for id in $targets; do
    if ! GH_DEBUG= GODEBUG="$GH_GODEBUG" gh run rerun "$id" --failed --repo="$REPO" \
        </dev/null >&2 2>"$GH_ERR"; then
      detail=$(tr -d '\0' < "$GH_ERR" | tail -c 300)
      stop rerun-refused "gh run rerun $id --failed failed: $detail; already rerun: ${done_ids:-none}"
    fi
    : > "$GH_ERR"
    done_ids+="${done_ids:+, }$id"
    jobs=""
    while read -r run job; do
      [ "$run" = "$id" ] || continue
      jobs+=",$job" job_ids+=" $job"
    done <<< "$CI_FAILED_JOBS"
    runs_json+=",{\"run_id\":$id,\"failed_jobs\":[${jobs#,}]}"
  done
  rerun_await_registration "$job_ids"
  echo "OK rerun {\"head_oid\":\"$HEAD_OID\",\"runs\":[${runs_json#,}]}"
}

case "$PHASE" in
  check) phase_check ;;
  land) phase_land ;;
  merge) phase_merge ;;
  rerun) phase_rerun ;;
  prepare) phase_prepare ;;
esac
