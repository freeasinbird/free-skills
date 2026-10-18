#!/usr/bin/env bash
# Regression matrix for land-approved-prs' landed-since.sh. Offline and
# deterministic: a PATH shim replaces gh, serving canned JSON per endpoint
# through the caller's own --jq filter, while git runs for real against a
# bare scratch remote whose default branch has a known first-parent history.
#
# The cases pin the merge-base choice (the first pushed head's base, never a
# later rebased head's), the stops when the first head is unknown, the
# --since re-read, and the base-advance checks read from the default-branch
# tip.
#
# Set LANDED_SINCE_SCRIPT to test a different copy of the script.
set -u

SCRIPT="${LANDED_SINCE_SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/skills/land-approved-prs/landed-since.sh}"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
DEAD="$TMP/dead"; FIX="$TMP/fix"; SHIMD="$TMP/shim"
mkdir -p "$DEAD" "$FIX" "$SHIMD"
printf '#!/bin/sh\nexit 1\n' > "$DEAD/gh"
chmod +x "$DEAD/gh"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

pass=0; fail=0; skip=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*" >&2; }

SRV="$TMP/srv/owner/name.git"
WORK="$TMP/work"
SEED="$TMP/seed"

# new_repo [checks-bullet-value]: main is c0 - c1 - M(side s1) - c2, with the
# landing record's Base-advance checks bullet set to the argument ("" drops
# the record entirely). Sets C0, C1, and C2.
new_repo() {
  local checks="${1-none.}"
  rm -rf "$TMP/srv" "$WORK" "$SEED" "$FIX"
  mkdir -p "$TMP/srv/owner" "$FIX"
  git init -q --bare -b main "$SRV"
  git init -q -b main "$SEED"
  {
    echo "# Project"
    echo
    if [ -n "$checks" ]; then
      echo "- **Land approved PRs by label.** This project has the following"
      echo "  landing record:"
      echo
      echo '  - **Mechanism:** `label`.'
      echo '  - **Approver:** `owner1`.'
      echo "  - **Base-advance checks:** $checks"
      echo '  - **Consumer:** `land-approved-prs`.'
      echo
    fi
    echo "## Other"
  } > "$SEED/AGENTS.md"
  git -C "$SEED" add AGENTS.md
  git -C "$SEED" commit -q -m "c0 seed"
  C0=$(git -C "$SEED" rev-parse HEAD)
  echo 1 > "$SEED/one"; git -C "$SEED" add one; git -C "$SEED" commit -q -m "c1 first landing"
  C1=$(git -C "$SEED" rev-parse HEAD)
  git -C "$SEED" checkout -q -b side
  echo s > "$SEED/side"; git -C "$SEED" add side; git -C "$SEED" commit -q -m "s1 side work"
  git -C "$SEED" checkout -q main
  git -C "$SEED" merge -q --no-ff -m "M merge side" side
  echo 2 > "$SEED/two"; git -C "$SEED" add two; git -C "$SEED" commit -q -m "c2 second landing"
  C2=$(git -C "$SEED" rev-parse HEAD)
  git -C "$SEED" push -q "$SRV" main
  git clone -q "$SRV" "$WORK"
  echo '{"default_branch":"main"}' > "$FIX/repo.json"
  echo '{"createdAt":"2026-10-01T00:00:00Z","headRefName":"feat/one"}' > "$FIX/pr.json"
  echo '[]' > "$FIX/timeline.json"
  echo '{"workflow_runs":[]}' > "$FIX/runs.json"
}

# --- validation half: dead gh shim ------------------------------------------

new_repo
OID=0123456789abcdef0123456789abcdef01234567

t() {
  expected="$1"; desc="$2"; shift 2
  (cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" "$@") >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$expected" ]; then ok; else bad "($got != $expected) $desc: $*"; fi
}

t 4 "valid call reaches the forge read" --repo owner/name --pr 5
t 4 "valid since reaches the forge read" --repo owner/name --pr 5 --since "$OID"
t 4 "uppercase since normalized" --repo owner/name --pr 5 --since "$(printf '%s' "$OID" | tr 'a-f' 'A-F')"
t 4 "explicit base remote accepted" --repo owner/name --pr 5 --base-remote origin
t 64 "no arguments at all"
t 64 "unknown option" --repo owner/name --pr 5 --bogus x
t 64 "trailing bare option" --repo owner/name --pr
t 64 "missing repo" --pr 5
t 64 "missing pr" --repo owner/name
t 64 "pr zero" --repo owner/name --pr 0
t 64 "pr leading zeros" --repo owner/name --pr 05
t 64 "pr non-numeric" --repo owner/name --pr x
t 64 "repo extra segment" --repo a/b/c --pr 5
t 64 "since abbreviated" --repo owner/name --pr 5 --since 0123456
t 64 "since non-hex" --repo owner/name --pr 5 --since zz23456789abcdef0123456789abcdef01234567
t 64 "base remote leading hyphen" --repo owner/name --pr 5 --base-remote -x
t 2 "an unknown base remote stops" --repo owner/name --pr 5 --base-remote nosuch
git -C "$WORK" remote add fork "$TMP/srv/forker/name.git"
(cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --pr 5 --base-remote fork) > "$TMP/out" 2>/dev/null
got=$?
if [ "$got" -eq 2 ] && grep -q '^STOP remote-repo-mismatch ' "$TMP/out"; then ok; else bad "a base remote naming another repository stops remote-repo-mismatch ($got)"; fi
git -C "$WORK" remote add mirror "$SRV"
t 2 "two remotes naming the repository are ambiguous" --repo owner/name --pr 5
t 4 "the override picks among remotes that name the repository" --repo owner/name --pr 5 --base-remote mirror
git -C "$WORK" remote remove fork
git -C "$WORK" remote remove mirror
ORIGIN_URL=$(git -C "$WORK" remote get-url origin)
# The URL matcher: a suffix-trap URL doesn't name the repository, while the
# scp form in another case does, so it makes the remotes ambiguous.
dead_stop() { # dead_stop <guard> <desc>: last run's result is STOP <guard>
  if [ "$got" -eq 2 ] && grep -q "^STOP $1 " "$TMP/out"; then ok; else bad "$2 ($got): $(tail -n 1 "$TMP/out")"; fi
}
git -C "$WORK" remote add trap "$TMP/srv/xowner/name.git"
t 4 "a suffix-trap URL does not name the repository" --repo owner/name --pr 5
git -C "$WORK" remote set-url trap git@github.com:Owner/Name.git
(cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --pr 5) > "$TMP/out" 2>/dev/null
got=$?
dead_stop remote-ambiguous "an scp URL in another case names the repository"
git -C "$WORK" remote remove trap
git -C "$WORK" remote set-url origin "$TMP/srv/forker/name.git"
(cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --pr 5) > "$TMP/out" 2>/dev/null
got=$?
dead_stop remote-unresolved "no remote naming the repository stops remote-unresolved"
git -C "$WORK" remote set-url origin "$ORIGIN_URL"

(cd "$TMP" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --pr 5) > "$TMP/out" 2>/dev/null
got=$?
if [ "$got" -eq 2 ] && grep -q '^STOP not-a-repo ' "$TMP/out"; then ok; else bad "outside a repository stops not-a-repo ($got)"; fi

NOGH=$(mktemp -d)
(cd "$WORK" && PATH="$NOGH" "$(command -v bash)" "$SCRIPT" --repo owner/name --pr 5) >/dev/null 2>"$TMP/err"
got=$?
rm -rf "$NOGH"
if [ "$got" -eq 69 ] && grep -qF 'hand the batch to the owner' "$TMP/err"; then ok; else bad "missing gh exits 69 and hands off ($got)"; fi

# --- behavior half -----------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  skip=1
  echo "SKIP: behavior cases need jq on PATH; only validation ran" >&2
else

{
  echo '#!/bin/bash'
  echo "FIX=\"$FIX\""
  cat <<'SHIMEOF'
echo "$*" >> "$FIX/calls.log"
sub='' verb='' api='' jqval='' prev=''
for a in "$@"; do
  case "$prev" in --jq) jqval="$a" ;; esac
  case "$a" in
    pr|api) [ -z "$sub" ] && sub="$a" ;;
    view|list) [ "$sub" = pr ] && [ -z "$verb" ] && verb="$a" ;;
    repos/*) [ -z "$api" ] && api="$a" ;;
  esac
  prev="$a"
done
fixture=''
if [ "$sub" = api ]; then
  case "$api" in
    */issues/*/timeline*) fixture="$FIX/timeline.json" ;;
    */actions/runs*) fixture="$FIX/runs.json" ;;
    */compare/*) fixture="$FIX/compare-${api##*...}.json" ;;
    repos/*/*) fixture="$FIX/repo.json" ;;
  esac
elif [ "$sub" = pr ] && [ "$verb" = view ]; then
  fixture="$FIX/pr.json"
fi
[ -n "$fixture" ] && [ -f "$fixture" ] || exit 1
if [ -n "$jqval" ]; then exec jq -r "$jqval" "$fixture"; fi
exec cat "$fixture"
SHIMEOF
} > "$SHIMD/gh"
chmod +x "$SHIMD/gh"

F1=f111111111111111111111111111111111111111
R1=e111111111111111111111111111111111111111
X1=d111111111111111111111111111111111111111

ci_run() { # ci_run <at> <oid> [head-repository]
  jq --arg at "$1" --arg o "$2" --arg r "${3:-Owner/Name}" \
    '.workflow_runs += [{created_at:$at, head_sha:$o, head_repository:{full_name:$r}}]' "$FIX/runs.json" > "$FIX/r.tmp" \
    && mv "$FIX/r.tmp" "$FIX/runs.json"
}
force_pushed() { # force_pushed <at> <oid>
  jq --arg at "$1" --arg o "$2" '. + [{event:"head_ref_force_pushed", created_at:$at, commit_id:$o}]' "$FIX/timeline.json" > "$FIX/t.tmp" \
    && mv "$FIX/t.tmp" "$FIX/timeline.json"
}
merge_base_of() { # merge_base_of <head> <base>
  jq -n --arg b "$2" '{merge_base_commit:{sha:$b}}' > "$FIX/compare-$1.json"
}

RC=0 LAST="" JSON=""
ls_run() {
  (cd "$WORK" && PATH="$SHIMD:$PATH" bash "$SCRIPT" --repo owner/name --pr 5 "$@") > "$TMP/out" 2> "$TMP/err"
  RC=$?
  LAST=$(tail -n 1 "$TMP/out")
  JSON="${LAST#* }"; JSON="${JSON#* }"
}
expect_field() { # expect_field <jq-path> <value> <desc>
  local got
  got=$(printf '%s' "$JSON" | jq -r "$1" 2>/dev/null)
  if [ "$RC" -eq 0 ] && [ "$got" = "$2" ]; then ok; else bad "$3: $1 = '$got', want '$2' (exit $RC): $LAST"; fi
}
expect_stop() {
  case "$LAST" in "STOP $1 "*) [ "$RC" -eq 2 ] && { ok; return; } ;; esac
  bad "$2: want STOP $1, got exit $RC: $LAST"
}
expect_lookup() {
  case "$LAST" in "LOOKUP_FAILED $1 "*) [ "$RC" -eq 4 ] && { ok; return; } ;; esac
  bad "$2: want LOOKUP_FAILED $1, got exit $RC: $LAST"
}
expect_out() { if grep -qF -- "$1" "$TMP/out"; then ok; else bad "$2: output lacks '$1'"; fi; }
expect_no_out() { if grep -qF -- "$1" "$TMP/out"; then bad "$2: output has '$1'"; else ok; fi; }

# --- the merge-base choice ---

# The author rebased from c0 onto c2 before handoff: the first head's base
# is c0, the rebased head's is c2. Starting from c2 would skip c1 and M.
new_repo
ci_run 2026-10-01T00:00:05Z "$F1"; merge_base_of "$F1" "$C0"
force_pushed 2026-10-03T00:00:00Z "$R1"; ci_run 2026-10-03T00:00:05Z "$R1"; merge_base_of "$R1" "$C2"
ls_run
expect_field .from "$C0" "the range starts at the first pushed head's merge base"
expect_field .first_head "$F1" "the first pushed head is the earliest CI run's head"
expect_field .commits 3 "the count is first-parent commits since the original base"
expect_field .tip "$C2" "the range ends at the fetched tip"
expect_out "c1 first landing" "a landing the handoff rebase absorbed is shown"
expect_out "M merge side" "a merge commit is shown"
expect_out " two | 1 +" "the log carries --stat"
expect_no_out "s1 side work" "the log is first-parent only"

new_repo
ci_run 2026-10-03T00:00:05Z "$R1"; merge_base_of "$R1" "$C2"
ci_run 2026-10-01T00:00:05Z "$F1"; merge_base_of "$F1" "$C1"
ls_run
expect_field .from "$C1" "the earliest run wins regardless of listing order"

new_repo
ci_run 2026-09-20T00:00:00Z "$X1"; merge_base_of "$X1" "$C0"
ci_run 2026-10-01T00:00:05Z "$F1"; merge_base_of "$F1" "$C1"
ls_run
expect_field .first_head "$F1" "a run from before the PR existed belongs to another PR"
expect_field .from "$C1" "the reused branch name's old run does not move the base"

new_repo
ci_run 2026-10-01T00:00:01Z "$X1" stranger/name; merge_base_of "$X1" "$C2"
ci_run 2026-10-01T00:00:05Z "$F1"; merge_base_of "$F1" "$C1"
ls_run
expect_field .first_head "$F1" "a fork's run on a same-named branch is not the first head"
expect_field .from "$C1" "a fork's run does not move the base"

new_repo
ls_run
expect_stop first-head-unknown "a PR with no CI run has no known first head"

new_repo
force_pushed 2026-10-01T00:00:03Z "$R1"
ci_run 2026-10-01T00:00:05Z "$R1"; merge_base_of "$R1" "$C2"
ls_run
expect_stop first-head-unknown "a force-push before the earliest run hides the first head"

new_repo
ci_run 2026-10-01T00:00:05Z "$F1"; merge_base_of "$F1" "$C2"
force_pushed 2026-10-02T00:00:00Z "$R1"
ls_run
expect_field .from "$C2" "a force-push after the earliest run leaves the first head known"
expect_field .commits 0 "nothing landed since the original base"
expect_out "0 first-parent commit(s)" "an empty range says so"

new_repo
ci_run 2026-10-01T00:00:05Z "$F1"
ls_run
expect_lookup compare "a failed compare read is a lookup failure"

new_repo
ci_run 2026-10-01T00:00:05Z "$F1"; merge_base_of "$F1" "$X1"
ls_run
expect_lookup merge-base "a merge base missing from the fetched branch is a lookup failure"

# --- the re-read after rebased ---

new_repo
ls_run --since "$C1"
expect_field .from "$C1" "--since starts the range at the earlier read's tip"
expect_field .commits 2 "--since counts only what landed after it"
expect_field .first_head "" "--since needs no first head"
if grep -q '^pr view\|actions/runs' "$FIX/calls.log" 2>/dev/null; then bad "--since reads no PR history"; else ok; fi

new_repo
ls_run --since "$X1"
expect_lookup since "an unknown --since commit is a lookup failure"

# --- base-advance checks ---

new_repo '`printf '"'"'hello-%s\n'"'"' "$LAND_PR"`, `false`, and
    `pwd -P`.'
ls_run --since "$C1"
expect_field '[.checks[].exit] | map(tostring) | join(",")' "0,1,0" "each recorded check runs and reports its exit"
expect_out "hello-5" "a check sees LAND_PR"
expect_out "$(cd "$WORK" && pwd -P)" "checks run from the checkout root"
expect_out "base-advance check exit 1: false" "a failing check is printed, not decided on"

new_repo '`cat`, then `echo second-ran-$((40 + 2))`.'
ls_run --since "$C1"
expect_out "second-ran-42" "a check that reads stdin cannot swallow the next check"

new_repo '`printf '"'"'%s %s\n'"'"' "$LAND_FROM" "$LAND_TIP"`.'
ls_run --since "$C1"
expect_out "$C1 $C2" "a check sees LAND_FROM and LAND_TIP"

new_repo
ls_run --since "$C1"
expect_out "base-advance checks: none recorded" "a record with no checks says so"
expect_field '.checks | length' 0 "no checks ran"

new_repo '`none`.'
ls_run --since "$C1"
expect_out "base-advance checks: none recorded" "a backticked none means no checks"
expect_field '.checks | length' 0 "a backticked none runs nothing"

new_repo 'make test.'
ls_run --since "$C1"
expect_stop bad-record "a checks value with no backticked command stops rather than run none"

new_repo ""
ls_run --since "$C1"
expect_stop no-landing-record "a repository without a landing record stops rather than skip the checks"

new_repo
sed '/Base-advance/d' "$SEED/AGENTS.md" > "$TMP/agents" && mv "$TMP/agents" "$SEED/AGENTS.md"
git -C "$SEED" commit -qam "drop the checks bullet"
git -C "$SEED" push -q "$SRV" main
ls_run --since "$C1"
expect_stop bad-record "a record without a Base-advance checks bullet stops rather than run none"

new_repo
git -C "$SEED" rm -q AGENTS.md
git -C "$SEED" commit -qm "drop the record"
git -C "$SEED" push -q "$SRV" main
ls_run --since "$C1"
expect_stop no-landing-record "a tip without AGENTS.md stops rather than skip the checks"

new_repo
sed -i.bak 's/Base-advance checks:\*\* none\./Base-advance checks:** `touch planted`./' "$WORK/AGENTS.md"
ls_run --since "$C1"
if [ -e "$WORK/planted" ]; then bad "checks are read from the default-branch tip, not the working tree"; else ok; fi

fi

echo "landed-since matrix: $pass passed, $fail failed$([ "$skip" -eq 0 ] || echo ", behavior half skipped")"
[ "$fail" -eq 0 ]
