#!/usr/bin/env bash
# tracker-reconcile.sh: run merge-cleanup's shared-format tracker
# reconciliation from a plan file and write its trace from what it observed,
# so an agent never hand-builds the glue between tracker-refresh.sh,
# tracker-write.sh, and reconciliation-ledger.sh.
#
# Usage:
#   tracker-reconcile.sh --repo host/owner/name --base BRANCH --plan PLAN
#     --trace TRACE
#   tracker-reconcile.sh --help
#
# PLAN holds one `policy` row and its `plan` rows in reconciliation-ledger.sh's
# trace grammar; the agent still chooses the trackers and their inputs. Each
# plan item names its tracker in --repo: `#N` for an issue body or `#N/ID` for
# a tracker kept in comment ID, optionally followed by `:LABEL` (letters,
# digits, `.`, `_`, `-`) so one tracker can carry two items, such as
# `#835:refresh` and `#835:startable`. BRANCH is the base branch whose tip the
# `pre`, `post`, and `final` rows observe, looked up with `gh api` each time;
# a failed or malformed lookup records `unverifiable`.
#
# The run:
#   1. Check PLAN with `reconciliation-ledger.sh --skeleton`. Refuse a policy
#      status other than complete or absent, an unverifiable policy tip, an
#      unsupported item, or an item name that does not parse. Nothing below
#      runs, and TRACE is not created, when PLAN is refused.
#   2. Copy PLAN's rows to TRACE, which must not exist yet.
#   3. For each write item in plan order: record `pre`, run tracker-write.sh
#      once, and transcribe its RESULT line as SKILL.md's result table says,
#      then record `post` after any `recheck`. Continue only after `written`
#      with the policy tip at `post`, or after `noop`; any other result, or a
#      moved or unverifiable tip, skips every remaining item (class `policy`
#      after a tip problem, `remaining` otherwise).
#   4. When nothing stopped, observe each noop item and then each report item
#      with a fresh tracker-refresh.sh run: `OK unchanged` is fresh,
#      `OK changed` is stale, anything else is unverifiable. A stale or
#      unverifiable observation skips the rest as `remaining`.
#   5. Record `final` and run reconciliation-ledger.sh on TRACE.
# A tracker-write.sh run whose RESULT line is missing, malformed, or does not
# match its exit code is recorded as an unknown write, never as written or
# skipped, unless it exited 64 or 69, which make no forge call.
#
# Stdout is exactly reconciliation-ledger.sh's output on TRACE, so its RESULT
# line is the verdict. Everything the underlying scripts print, and this
# script's progress, goes to stderr. Exit codes:
#   0   RESULT complete
#   1   any other valid result: incomplete, partial, restart, or unstable
#   2   the ledger rejected PLAN (no TRACE written) or the finished TRACE
#   64  usage, an existing TRACE, or a PLAN this script does not run; no gh
#       call and no TRACE
#   69  gh, awk, or a sibling script missing (no gh call and no TRACE), or
#       reconciliation-ledger.sh could not check the finished TRACE
#
# TRACKER_REFRESH_SCRIPT, TRACKER_WRITE_SCRIPT, and RECONCILIATION_LEDGER_SCRIPT
# override the sibling scripts, for tests.
# Runs under bash 3.2 (macOS /bin/bash) and BWK awk, as well as newer bash.
set -u

REPO_SPEC="" BASE="" PLAN="" TRACE=""

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}
say() { echo "tracker-reconcile.sh: $1" >&2; }
refuse() { say "refused: $1"; exit 64; }

case "${1:-}" in
  --help|-h) [ $# -eq 1 ] || usage; sed -n '2,/^set -u$/p' "$0" | sed '$d'; exit 0 ;;
esac

while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --repo|--base|--plan|--trace) ;;
    *) say "unknown option: $opt"; usage ;;
  esac
  [ $# -ge 2 ] || { say "$opt requires a value"; usage; }
  val="$2"; shift 2
  # An unset variable passed as a value must not drop the flag silently.
  [ -n "$val" ] || { say "$opt requires a non-empty value"; usage; }
  case "$opt" in
    --repo) REPO_SPEC="$val" ;;
    --base) BASE="$val" ;;
    --plan) PLAN="$val" ;;
    --trace) TRACE="$val" ;;
  esac
done

[ -n "$REPO_SPEC" ] && [ -n "$BASE" ] && [ -n "$PLAN" ] && [ -n "$TRACE" ] || usage
case "$REPO_SPEC" in
  */*/*/*|*[!A-Za-z0-9._/-]*) say "--repo must be host/owner/name"; usage ;;
  ?*/?*/?*) ;;
  *) say "--repo must be host/owner/name"; usage ;;
esac
FORGE_HOST="${REPO_SPEC%%/*}"
REPO="${REPO_SPEC#*/}"
case "$FORGE_HOST" in
  ''|*[!A-Za-z0-9.-]*|.*|-*|*..*|*.-*|*-.|*.)
    say "--repo has an invalid host"; usage ;;
esac
case "$BASE" in
  -*|/*|*/|*..*|*//*|*[!A-Za-z0-9._/-]*) say "--base is not a branch name this script accepts"; usage ;;
esac
# A leading `-` would reach the ledger as stdin or an option.
case "$PLAN" in -*) PLAN="./$PLAN" ;; esac
case "$TRACE" in -*) TRACE="./$TRACE" ;; esac
[ -f "$PLAN" ] && [ -r "$PLAN" ] || { say "--plan is not a readable file: $PLAN"; usage; }
if [ -e "$TRACE" ] || [ -L "$TRACE" ]; then refuse "--trace already exists: $TRACE"; fi

for tool in gh awk; do
  command -v "$tool" >/dev/null 2>&1 || { say "$tool not found on PATH"; exit 69; }
done
DIR=$(dirname "$0")
REFRESH="${TRACKER_REFRESH_SCRIPT:-$DIR/tracker-refresh.sh}"
WRITE="${TRACKER_WRITE_SCRIPT:-$DIR/tracker-write.sh}"
LEDGER="${RECONCILIATION_LEDGER_SCRIPT:-$DIR/reconciliation-ledger.sh}"
for script in "$REFRESH" "$WRITE" "$LEDGER"; do
  [ -f "$script" ] && [ -r "$script" ] || { say "sibling script not found: $script"; exit 69; }
done

TMPD=$(mktemp -d) || { say "mktemp failed"; exit 69; }
trap 'rm -rf "$TMPD"' EXIT

# --- check the plan before any forge call ----------------------------------------
bash "$LEDGER" --skeleton "$PLAN" >"$TMPD/skeleton" 2>"$TMPD/skeleton.err"
case $? in
  0) ;;
  2) sed -n '/^INVALID/p' "$TMPD/skeleton" >&2; cat "$TMPD/skeleton.err" >&2; exit 2 ;;
  *) cat "$TMPD/skeleton.err" >&2; say "reconciliation-ledger.sh could not check the plan"; exit 69 ;;
esac

# Items, in plan order, as parallel indexed arrays (bash 3.2 has no others).
COUNT=0 POLICY_TIP="" POLICY_STATUS=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in *[![:space:]]*) ;; *) continue ;; esac
  event=$(printf '%s\n' "$line" | cut -f1)
  if [ "$event" = policy ]; then
    POLICY_TIP=$(printf '%s\n' "$line" | cut -f2)
    POLICY_STATUS=$(printf '%s\n' "$line" | cut -f3)
    continue
  fi
  item=$(printf '%s\n' "$line" | cut -f2)
  kind=$(printf '%s\n' "$line" | cut -f3)
  [ "$kind" != unsupported ] || refuse "item $item is unsupported; dispose of it by hand"
  name="${item%%:*}" label=""
  case "$item" in *:*) label="${item#*:}" ;; esac
  case "$item" in
    *:) refuse "item $item has an empty label" ;;
  esac
  case "$label" in *[!A-Za-z0-9._-]*) refuse "item $item has a label with other characters" ;; esac
  case "$name" in '#'*) ;; *) refuse "item $item does not name a tracker as #N or #N/ID" ;; esac
  num="${name#\#}" cid=""
  case "$num" in */*) cid="${num#*/}"; num="${num%%/*}" ;; esac
  case "$num" in ''|*[!0-9]*|0*) refuse "item $item does not name a tracker as #N or #N/ID" ;; esac
  case "$name" in
    */*) case "$cid" in ''|*[!0-9]*|0*) refuse "item $item does not name a tracker as #N or #N/ID" ;; esac ;;
  esac
  ITEM[COUNT]="$item" KIND[COUNT]="$kind" NUM[COUNT]="$num" CID[COUNT]="$cid"
  INPUTS[COUNT]=$(printf '%s\n' "$line" | cut -f4-)
  COUNT=$((COUNT + 1))
done <"$PLAN"

case "$POLICY_STATUS" in
  complete|absent) ;;
  *) refuse "policy status $POLICY_STATUS needs the manual source-failure path" ;;
esac
[ "$POLICY_TIP" != unverifiable ] || refuse "the policy tip is unverifiable; rediscover policy first"

# --- trace -------------------------------------------------------------------------
# noclobber makes creating TRACE fail rather than overwrite one made meanwhile.
( set -C; : >"$TRACE" ) 2>/dev/null || refuse "--trace already exists or cannot be created: $TRACE"
grep '[^[:space:]]' "$PLAN" >>"$TRACE"

# row <field>...: append one tab-separated trace row.
row() { local IFS=$'\t'; printf '%s\n' "$*" >>"$TRACE"; }
# row_inputs <item index> <field>...: append a row ending in that item's inputs.
row_inputs() {
  local idx="$1" IFS=$'\t'
  shift
  printf '%s\t%s\n' "$*" "${INPUTS[idx]}" >>"$TRACE"
}
# clean <text>: one trace field, free of tabs and carriage returns.
clean() { printf '%s' "$1" | tr '\t\r' '  ' | sed 's/^ *//; s/ *$//'; }

# tip: set TIP to the base branch's commit SHA, or `unverifiable`.
tip() {
  TIP=$(gh api --hostname "$FORGE_HOST" "repos/$REPO/commits/$BASE" --jq .sha \
    </dev/null 2>"$TMPD/tip.err")
  local rc=$?
  case "$TIP" in
    *[!0-9a-f]*) TIP="" ;;
  esac
  if [ "$rc" -ne 0 ] || [ "${#TIP}" -ne 40 ]; then
    say "base tip lookup for $BASE failed (exit $rc): $(sed -n 1p "$TMPD/tip.err")"
    TIP=unverifiable
  fi
}

STOP_REASON="" STOP_CLASS=""
stop() { STOP_REASON="$1" STOP_CLASS="$2"; }
skip_stopped() { row skip "${ITEM[$1]}" "$STOP_REASON" "$STOP_CLASS"; }

# stderr_cause <file> <fallback>: the last stop, lookup, or refusal line.
stderr_cause() {
  local cause
  cause=$(grep -E ': (STOP|LOOKUP_FAILED|refused|--edited refused)' "$1" | tail -n 1)
  [ -n "$cause" ] || cause=$(grep '[^[:space:]]' "$1" | tail -n 1)
  cause=$(clean "$cause")
  [ -n "$cause" ] || cause="$2"
  printf '%s' "$cause"
}

# parse_result <file> <exit>: set R_RESULT and R_GUARD, R_ATTEMPT, R_VERIFY,
# R_RECHECK when the file is exactly one RESULT line whose values are a
# combination tracker-write.sh documents for that exit code. Fails otherwise.
parse_result() {
  local line g a v r extra vok=0 rok=0
  [ "$(grep -c '' "$1")" -eq 1 ] || return 1
  line=$(cat "$1")
  case "$line" in "tracker-write.sh: RESULT "*) ;; *) return 1 ;; esac
  read -r R_RESULT g a v r extra <<EOF
${line#tracker-write.sh: RESULT }
EOF
  [ -z "$extra" ] || return 1
  case "$g" in guard=*) R_GUARD="${g#guard=}" ;; *) return 1 ;; esac
  case "$a" in attempt=*) R_ATTEMPT="${a#attempt=}" ;; *) return 1 ;; esac
  case "$v" in verify=*) R_VERIFY="${v#verify=}" ;; *) return 1 ;; esac
  case "$r" in recheck=*) R_RECHECK="${r#recheck=}" ;; *) return 1 ;; esac
  case "$R_VERIFY" in changed|failed|unknown) vok=1 ;; esac
  case "$R_RECHECK" in fresh|changed|unverifiable) rok=1 ;; esac
  case "$2:$R_RESULT:$R_GUARD:$R_ATTEMPT" in
    0:written:complete:accepted)
      [ "$R_VERIFY:$R_RECHECK" = changed:fresh ] && return 0 ;;
    0:noop:complete:none|3:changed-since-read:complete:none|4:lookup-failed:unavailable:none|2:refused:unavailable:none)
      [ "$R_VERIFY:$R_RECHECK" = none:none ] && return 0 ;;
    5:write-failed:complete:failed)
      [ "$vok$rok" = 11 ] && return 0 ;;
    5:unverified:complete:accepted)
      # tracker-write.sh prints `written` for a changed and fresh write.
      [ "$vok$rok" = 11 ] && [ "$R_VERIFY:$R_RECHECK" != changed:fresh ] && return 0 ;;
  esac
  return 1
}

# write_item <item index>: run and record one write item; may call stop.
write_item() {
  local i="$1" item="${ITEM[$1]}" rc cause
  tip
  row pre "$TIP"
  if [ "$TIP" != "$POLICY_TIP" ]; then
    if [ "$TIP" = unverifiable ]; then cause="base tip was unverifiable before the write"
    else cause="base tip moved before the write"; fi
    row skip "$item" "$cause" policy
    stop "base tip moved or was unverifiable during reconciliation" policy
    return
  fi
  say "$item: running tracker-write.sh"
  bash "$WRITE" --repo "$REPO_SPEC" --issue "${NUM[i]}" ${CID[i]:+--comment "${CID[i]}"} \
    </dev/null >"$TMPD/write.out" 2>"$TMPD/write.err"
  rc=$?
  cat "$TMPD/write.err" "$TMPD/write.out" >&2
  if ! parse_result "$TMPD/write.out" "$rc"; then
    row guard unavailable
    case "$rc" in
      64|69)
        # tracker-write.sh documents no gh call on these exits.
        cause=$(stderr_cause "$TMPD/write.err" "no result line")
        row skip "$item" "tracker-write.sh exited $rc before any forge call: $cause" tooling
        stop "an earlier item stopped reconciliation" remaining
        return ;;
    esac
    # The write may or may not have run: record it as unknown, never skipped.
    say "$item: tracker-write.sh exited $rc without a result line this script can trust"
    row attempt failed "$item"
    row verify "$item" unknown
    row_inputs "$i" recheck unverifiable
    tip
    row post "$TIP"
    stop "an earlier item stopped reconciliation" remaining
    [ "$TIP" = "$POLICY_TIP" ] || stop "base tip moved or was unverifiable during reconciliation" policy
    return
  fi
  if [ "$R_GUARD" = complete ]; then row_inputs "$i" guard complete; else row guard unavailable; fi
  case "$R_RESULT" in
    written|write-failed|unverified)
      row attempt "$R_ATTEMPT" "$item"
      row verify "$item" "$R_VERIFY"
      row_inputs "$i" recheck "$R_RECHECK"
      tip
      row post "$TIP"
      if [ "$TIP" != "$POLICY_TIP" ]; then
        stop "base tip moved or was unverifiable during reconciliation" policy
      elif [ "$R_RESULT" != written ]; then
        stop "an earlier item stopped reconciliation" remaining
      fi ;;
    noop)
      row skip "$item" "already current at write time" remaining ;;
    changed-since-read)
      row skip "$item" "tracker changed since read" remaining
      stop "an earlier item stopped reconciliation" remaining ;;
    lookup-failed)
      row skip "$item" "$(stderr_cause "$TMPD/write.err" "a tracker read failed")" guard
      stop "an earlier item stopped reconciliation" remaining ;;
    refused)
      row skip "$item" "$(stderr_cause "$TMPD/write.err" "tracker-write.sh refused the write")" ambiguity
      stop "an earlier item stopped reconciliation" remaining ;;
  esac
}

# observe_item <item index>: rerun the refresh for a noop or report item.
observe_item() {
  local i="$1" item="${ITEM[$1]}" rc status
  say "$item: observing with tracker-refresh.sh"
  bash "$REFRESH" --repo "$REPO_SPEC" --issue "${NUM[i]}" ${CID[i]:+--comment "${CID[i]}"} \
    </dev/null >/dev/null 2>"$TMPD/refresh.err"
  rc=$?
  cat "$TMPD/refresh.err" >&2
  status=unverifiable
  # The status line is stderr's last line: read retries log before it.
  if [ "$rc" -eq 0 ]; then
    case "$(tail -n 1 "$TMPD/refresh.err")" in
      "tracker-refresh.sh: OK unchanged"*) status=fresh ;;
      "tracker-refresh.sh: OK changed"*) status=stale ;;
    esac
  fi
  row_inputs "$i" observe "$item" "$status"
  [ "$status" = fresh ] || stop "an earlier observation stopped reconciliation" remaining
}

# --- run -------------------------------------------------------------------------
i=0
while [ "$i" -lt "$COUNT" ]; do
  if [ "${KIND[i]}" = write ]; then
    if [ -n "$STOP_CLASS" ]; then skip_stopped "$i"; else write_item "$i"; fi
  fi
  i=$((i + 1))
done
for pass in noop report; do
  i=0
  while [ "$i" -lt "$COUNT" ]; do
    if [ "${KIND[i]}" = "$pass" ]; then
      if [ -n "$STOP_CLASS" ]; then skip_stopped "$i"; else observe_item "$i"; fi
    fi
    i=$((i + 1))
  done
done
tip
row final "$TIP"

bash "$LEDGER" "$TRACE" >"$TMPD/ledger" 2>"$TMPD/ledger.err"
lrc=$?
cat "$TMPD/ledger"
cat "$TMPD/ledger.err" >&2
case "$lrc" in
  0) [ "$(sed -n 1p "$TMPD/ledger")" = "RESULT complete" ] && exit 0; exit 1 ;;
  2) say "reconciliation-ledger.sh rejected the trace: $TRACE"; exit 2 ;;
  *) say "reconciliation-ledger.sh could not check the trace (exit $lrc)"; exit 69 ;;
esac
