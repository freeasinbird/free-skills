#!/usr/bin/env bash
# Regression matrix for land-approved-prs' landed-since.sh. Offline and
# deterministic: a PATH shim replaces gh, serving canned JSON per endpoint
# through the caller's own --jq filter, while git runs for real against a
# bare scratch remote whose default branch has a known first-parent history.
#
# The cases pin the fork-point choice (the oldest default-branch parent of
# any commit the PR has had, across its current head and every force-pushed
# head, never a later merge-in or rebase base), the stop when a force-pushed
# head is gone, the lookup failures on truncated or unreadable lists, the
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
  echo '{"head":{"sha":"'"$C2"'"},"commits":0}' > "$FIX/pull.json"
  echo '[]' > "$FIX/pr-commits.json"
  echo '{"data":{"repository":{"pullRequest":{"timelineItems":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}' > "$FIX/forcepushes.json"
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
    repos/*|graphql) [ -z "$api" ] && api="$a" ;;
  esac
  prev="$a"
done
fixture=''
if [ "$sub" = api ]; then
  case "$api" in
    graphql) fixture="$FIX/forcepushes.json" ;;
    */pulls/*/commits*) fixture="$FIX/pr-commits.json" ;;
    */pulls/*) fixture="$FIX/pull.json" ;;
    */compare/*) h="${api##*...}"; fixture="$FIX/compare-${h%%\?*}.json" ;;
    repos/*/*) fixture="$FIX/repo.json" ;;
  esac
fi
[ -n "$fixture" ] && [ -f "$fixture" ] || exit 1
if [ -n "$jqval" ]; then exec jq -r "$jqval" "$fixture"; fi
exec cat "$fixture"
SHIMEOF
} > "$SHIMD/gh"
chmod +x "$SHIMD/gh"

A1=a111111111111111111111111111111111111111
A2=a222222222222222222222222222222222222222
B1=b111111111111111111111111111111111111111
B2=b222222222222222222222222222222222222222
D1=d111111111111111111111111111111111111111
X1=e111111111111111111111111111111111111111

pr_commit() { # pr_commit <oid> <parent>...: add a commit to the current head
  local o="$1"; shift
  jq --arg o "$o" --args '. + [{sha:$o, parents:[$ARGS.positional[] | {sha:.}]}]' "$@" < "$FIX/pr-commits.json" > "$FIX/c.tmp" \
    && mv "$FIX/c.tmp" "$FIX/pr-commits.json"
  jq --arg o "$o" '.head.sha = $o | .commits += 1' "$FIX/pull.json" > "$FIX/p.tmp" && mv "$FIX/p.tmp" "$FIX/pull.json"
}
force_pushed() { # force_pushed <before-oid|null>
  jq --arg o "$1" '.data.repository.pullRequest.timelineItems.nodes += [{beforeCommit:(if $o == "null" then null else {oid:$o} end)}]' \
    "$FIX/forcepushes.json" > "$FIX/f.tmp" && mv "$FIX/f.tmp" "$FIX/forcepushes.json"
}
pushed_away() { # pushed_away <head> <merge-base> [<oid> <parent>[,<parent>]]...
  local h="$1" m="$2"; shift 2
  jq -n --arg m "$m" --args '{merge_base_commit:{sha:$m},
    commits:[$ARGS.positional | range(0; length; 2) as $i | {sha:.[$i], parents:[.[$i + 1] | split(",")[] | {sha:.}]}]}
    | .total_commits = (.commits | length)' "$@" > "$FIX/compare-$h.json"
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

# --- the fork-point choice ---

# The Problem scenario: the opening commit forks from c0, and a later merge
# of the newer main (c2) leaves no timeline event. Starting from the merge's
# parent would skip c1 and M.
new_repo
pr_commit "$A1" "$C0"; pr_commit "$D1" "$A1" "$C2"
ls_run
expect_field .from "$C0" "the range starts at the opening commit's fork point, not the merge-in parent"
expect_field .heads 1 "one head examined without force pushes"
expect_field .commits 3 "the count is first-parent commits since the original base"
expect_field .tip "$C2" "the range ends at the fetched tip"
expect_out "c1 first landing" "a landing the merge-in absorbed is shown"
expect_out "M merge side" "a merge commit is shown"
expect_out " two | 1 +" "the log carries --stat"
expect_no_out "s1 side work" "the log is first-parent only"
if grep -q 'actions/runs\|/timeline' "$FIX/calls.log"; then bad "no CI run or REST timeline read"; else ok; fi

new_repo
pr_commit "$D1" "$A1" "$C2"; pr_commit "$A1" "$C0"
ls_run
expect_field .from "$C0" "the oldest parent wins regardless of listing order"

# Rebased before any CI run: the pushed-away head forked from c0, the
# current one from c2.
new_repo
pushed_away "$B1" "$C0" "$B1" "$C0"
force_pushed "$B1"
pr_commit "$A1" "$C2"
ls_run
expect_field .from "$C0" "a rebase resolves to the pre-rebase fork point"
expect_field .heads 2 "the current head and one force-pushed head examined"

new_repo
pushed_away "$B1" "$C0" "$B1" "$C0" "$A2" "$B1"
pushed_away "$B2" "$C1" "$B2" "$C1"
force_pushed "$B1"; force_pushed "$B2"
pr_commit "$A1" "$C2"
ls_run
expect_field .from "$C0" "the oldest head's fork point wins across several force pushes"
expect_field .heads 3 "every force-pushed head is examined"
if [ "$(grep -c '/compare/' "$FIX/calls.log")" -eq 2 ]; then ok; else bad "one compare per force-pushed head"; fi

new_repo
pushed_away "$B1" "$C2" "$B1" "$C2"
force_pushed "$B1"
pr_commit "$A1" "$C1"
ls_run
expect_field .from "$C1" "the current head's fork point wins when it is the oldest"

new_repo
pushed_away "$B1" "$C0" "$B1" "$C0"
force_pushed "$B1"; force_pushed null
pr_commit "$A1" "$C2"
ls_run
expect_stop original-base-unknown "a force push from a commit the forge no longer has stops"

new_repo
echo '{"head":{"sha":"'"$C2"'"},"commits":0}' > "$FIX/pull.json"
pushed_away "$C2" "$C2"
ls_run
expect_field .from "$C2" "a head already on main forks at its merge base"
expect_field .commits 0 "nothing landed since the original base"
expect_out "0 first-parent commit(s)" "an empty range says so"

new_repo
pushed_away "$B1" "$C0" "$B1" "$C0"
jq '.total_commits = 2' "$FIX/compare-$B1.json" > "$FIX/x.tmp" && mv "$FIX/x.tmp" "$FIX/compare-$B1.json"
force_pushed "$B1"
pr_commit "$A1" "$C2"
ls_run
expect_lookup compare "a compare listing fewer commits than its total is a lookup failure"
expect_out "truncated" "a truncated compare says so"

new_repo
pr_commit "$A1" "$C0"
jq '.commits = 251' "$FIX/pull.json" > "$FIX/x.tmp" && mv "$FIX/x.tmp" "$FIX/pull.json"
ls_run
expect_lookup pr-commits "a PR over the forge's 250-commit list cap is a lookup failure"
expect_out "at most 250" "the cap failure names the forge's limit"
if grep -q 'pulls/5/commits' "$FIX/calls.log"; then bad "a capped PR reads no commit list"; else ok; fi

new_repo
pr_commit "$A1" "$C0"; pr_commit "$D1" "$A1" "$C2"
jq '.commits = 3' "$FIX/pull.json" > "$FIX/x.tmp" && mv "$FIX/x.tmp" "$FIX/pull.json"
ls_run
expect_lookup pr-commits "a commit list shorter than the PR's count is a lookup failure"

new_repo
pr_commit "$A1" "$C0"
jq '.[0].parents[0].sha = "c0"' "$FIX/pr-commits.json" > "$FIX/x.tmp" && mv "$FIX/x.tmp" "$FIX/pr-commits.json"
ls_run
expect_lookup pr-commits "an abbreviated parent oid is a lookup failure"

new_repo
pr_commit "$A1" "$C0"
force_pushed "${B1:0:12}"
ls_run
expect_lookup force-pushes "an abbreviated before-commit is a lookup failure"

new_repo
pr_commit "$A1" "$C0"
rm "$FIX/forcepushes.json"
ls_run
expect_lookup force-pushes "a failed force-push read is a lookup failure"

new_repo
force_pushed "$B1"
pr_commit "$A1" "$C0"
ls_run
expect_lookup compare "a failed compare read is a lookup failure"

new_repo
pr_commit "$A1" "$X1"
ls_run
expect_lookup merge-base "a fork point missing from the fetched branch is a lookup failure"

# A commit this checkout has that isn't on main: being an object is not
# being on the default branch.
new_repo
OFF=$(git -C "$WORK" commit-tree -p "$C0" -m "off main" "$C0^{tree}")
pr_commit "$A1" "$OFF"
ls_run
expect_lookup merge-base "a fork point off the fetched branch is a lookup failure"

# A head the list doesn't contain belongs to another push: a force push
# between the PR read and the list read would drop the first head's lineage.
new_repo
pr_commit "$A2" "$C2"
jq --arg h "$A1" '.head.sha = $h' "$FIX/pull.json" > "$FIX/x.tmp" && mv "$FIX/x.tmp" "$FIX/pull.json"
ls_run
expect_lookup pr-commits "a commit list without the PR's head is a lookup failure"

new_repo
pushed_away "$B1" "$C0" "$B2" "$C0"
force_pushed "$B1"
pr_commit "$A1" "$C2"
ls_run
expect_lookup compare "a compare without its own head is a lookup failure"

new_repo
pushed_away "$C1" "$C0"
force_pushed "$C1"
pr_commit "$A1" "$C2"
ls_run
expect_lookup compare "an empty compare whose merge base isn't its head is a lookup failure"

# A replaced head that has since landed has an empty compare whose merge
# base is the head itself, newer than its fork point. s1 forked from c1 and
# landed through M.
new_repo
S1=$(git -C "$WORK" rev-parse "$C2^1^2")
pushed_away "$S1" "$S1"
force_pushed "$S1"
pr_commit "$A1" "$C2"
ls_run
expect_field .from "$C1" "a replaced head that landed starts at its own fork point"

# landed_repo: new_repo, then a branch cut from c0 merges c1 in (OLD) and
# lands through X (TIPX), the new tip. A range from OLD would skip c1, the
# landing its merge-in absorbed.
landed_repo() {
  new_repo
  git -C "$SEED" checkout -q -b old "$C0"
  echo b > "$SEED/b"; git -C "$SEED" add b; git -C "$SEED" commit -qm "b1 old head work"
  git -C "$SEED" merge -q --no-ff -m "b2 merge main in" "$C1"
  OLD=$(git -C "$SEED" rev-parse HEAD)
  git -C "$SEED" checkout -q main
  git -C "$SEED" merge -q --no-ff -m "X land the old head" old
  TIPX=$(git -C "$SEED" rev-parse HEAD)
  git -C "$SEED" push -q "$SRV" main
  git -C "$WORK" fetch -q origin
}

landed_repo
pushed_away "$OLD" "$OLD"
force_pushed "$OLD"
pr_commit "$A1" "$TIPX"
ls_run
expect_field .from "$C0" "a replaced head that merged main in and landed starts at its fork point"
expect_out "c1 first landing" "a landing the replaced head's merge-in absorbed is shown"

# Only a prefix landed: the compare lists B1 alone, whose parent OLD is on
# main but off its first-parent line.
landed_repo
pushed_away "$B1" "$TIPX" "$B1" "$OLD"
force_pushed "$B1"
pr_commit "$A1" "$TIPX"
ls_run
expect_field .from "$C0" "a replaced head whose prefix landed starts at the prefix's fork point"
expect_out "c1 first landing" "a landing the landed prefix's merge-in absorbed is shown"

landed_repo
pr_commit "$A1" "$OLD"
ls_run
expect_field .from "$C0" "a current head whose prefix landed starts at the prefix's fork point"
expect_out "c1 first landing" "a landing the current head's landed prefix absorbed is shown"

# side_repo: main is c0 - c1 - c2 - M(side s1 - s2 - s3, cut from c0) - c3.
# Sets C0, C1, C2, C3, and SK, the side branch's tip. Counted in commits
# behind the tip, c1 (six) and c2 (five) look older than SK (four), yet a
# range from either skips c1, which a range from SK covers.
side_repo() {
  local i
  new_repo
  git -C "$SEED" checkout -q -b side2 "$C0"
  for i in 1 2 3; do echo "$i" > "$SEED/s$i"; git -C "$SEED" add "s$i"; git -C "$SEED" commit -qm "s$i side two"; done
  SK=$(git -C "$SEED" rev-parse HEAD)
  git -C "$SEED" checkout -q main
  git -C "$SEED" merge -q --no-ff -m "M2 merge side two" side2
  echo 3 > "$SEED/three"; git -C "$SEED" add three; git -C "$SEED" commit -qm "c3 third landing"
  C3=$(git -C "$SEED" rev-parse HEAD)
  git -C "$SEED" push -q "$SRV" main
  git -C "$WORK" fetch -q origin
}

side_repo
pr_commit "$A1" "$SK"; pr_commit "$D1" "$A1" "$C1"
ls_run
expect_field .from "$C0" "a branch cut from a side branch starts at the candidates' common ancestor"
expect_out "c1 first landing" "a landing older than the side branch's merge is shown"

side_repo
pushed_away "$B1" "$SK" "$B1" "$SK"
force_pushed "$B1"
pr_commit "$A1" "$C2"
ls_run
expect_field .from "$C0" "a force-pushed head cut from a side branch keeps the range wide"
expect_out "c2 second landing" "a landing the rebase absorbed is shown"

# --- the re-read after rebased ---

new_repo
ls_run --since "$C1"
expect_field .from "$C1" "--since starts the range at the earlier read's tip"
expect_field .commits 2 "--since counts only what landed after it"
expect_field .heads 0 "--since examines no heads"
if grep -q 'pulls/\|graphql' "$FIX/calls.log" 2>/dev/null; then bad "--since reads no PR history"; else ok; fi

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
