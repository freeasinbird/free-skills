#!/usr/bin/env bash
# Regression matrix for land-approved-prs' landing engine, land.sh. Offline and deterministic:
# a PATH shim replaces gh (serving canned JSON through the caller's own
# --jq filter, so a wrong field name fails a test rather than silently
# matching nothing), while git runs for real against scratch repositories
# with file:// remotes, because the hazards this script guards (ignored
# files, tag shadowing, worktree parsing, ancestry) live in git itself.
#
# Grown one adversarial case per verified hazard in the work unit's
# decision note (devlog/2026-07-24-2311-self-merge-resync-guards.md); add
# a case with every future fix so the class stops recurring one finding
# at a time.
#
# Set LAND_SCRIPT to test a different copy of the script.
set -u

SCRIPT="${LAND_SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/skills/land-approved-prs/land.sh}"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SHIM="$TMP/dead"; FIX="$TMP/fix"; SHIMD="$TMP/shim"
mkdir -p "$SHIM" "$FIX" "$SHIMD"
printf '#!/bin/sh\nexit 1\n' > "$SHIM/gh"
chmod +x "$SHIM/gh"

pass=0; fail=0; skip=0

# --- validation half: dead gh shim ------------------------------------------
# Any input that passes validation reaches the first forge read against the
# dead shim and exits 4 (LOOKUP_FAILED); rejected input exits 64 first.

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

OID=0123456789abcdef0123456789abcdef01234567

t 4 "valid check reaches the forge read" check --pr 83 --repo owner/name
t 4 "valid merge reaches the forge read" merge --pr 83 --repo owner/name --head "$OID"
t 64 "cleanup is no longer a phase" cleanup --pr 83 --repo owner/name --head "$OID"
t 4 "uppercase head normalized" merge --pr 83 --repo owner/name --head "$(printf '%s' "$OID" | tr 'a-f' 'A-F')"
t 4 "valid land reaches the forge read" land --pr 83 --repo owner/name --head "$OID"
t 4 "land dry run reaches the forge read" land --pr 83 --repo owner/name --head "$OID" --dry-run
t 4 "zero CI cap is accepted" land --pr 83 --repo owner/name --head "$OID" --ci-cap-minutes 0

t 64 "no arguments at all"
t 64 "unknown phase" tidy --pr 83 --repo owner/name
t 64 "missing repo" check --pr 83
t 64 "missing pr" check --repo owner/name
t 64 "trailing bare option" check --pr 83 --repo
t 64 "unknown option" check --pr 83 --repo owner/name --bogus x
t 64 "pr zero" check --pr 0 --repo owner/name
t 64 "pr leading zeros" check --pr 007 --repo owner/name
t 64 "pr non-numeric" check --pr abc --repo owner/name
t 64 "pr negative reads as usage error" check --pr -5 --repo owner/name
t 64 "repo extra segment" check --pr 83 --repo a/b/c
t 64 "repo query injection" check --pr 83 --repo 'a/b?x=1'
t 64 "repo missing name" check --pr 83 --repo a/
t 64 "merge without head" merge --pr 83 --repo owner/name
t 64 "land without head" land --pr 83 --repo owner/name
t 64 "dry run takes no value" land --pr 83 --repo owner/name --head "$OID" --dry-run yes
t 64 "dry run outside land never merges" merge --pr 83 --repo owner/name --head "$OID" --dry-run
t 64 "ci cap non-numeric" land --pr 83 --repo owner/name --head "$OID" --ci-cap-minutes xyz
t 64 "ci cap leading zeros" land --pr 83 --repo owner/name --head "$OID" --ci-cap-minutes 08
t 64 "ci cap beyond arithmetic bound" land --pr 83 --repo owner/name --head "$OID" --ci-cap-minutes 10000000
t 64 "head abbreviated" merge --pr 83 --repo owner/name --head 0123456
t 64 "head non-hex" merge --pr 83 --repo owner/name --head zz23456789abcdef0123456789abcdef01234567
t 64 "interval zero" check --pr 83 --repo owner/name --interval 0
t 64 "interval leading zeros" check --pr 83 --repo owner/name --interval 08
t 64 "interval beyond arithmetic bound" check --pr 83 --repo owner/name --interval 1000000000
t 64 "cap non-numeric" check --pr 83 --repo owner/name --cap-minutes xyz
t 64 "cap leading zeros" check --pr 83 --repo owner/name --cap-minutes 08
t 64 "cap beyond arithmetic bound" check --pr 83 --repo owner/name --cap-minutes 10000000
t 64 "base-remote leading hyphen" land --pr 83 --repo owner/name --head "$OID" --base-remote --upload-pack=/x
t 64 "head-remote leading hyphen" land --pr 83 --repo owner/name --head "$OID" --head-remote -r

# Missing gh: preflight must exit 69 immediately.
BASH_BIN=$(command -v bash)
NOGH=$(mktemp -d)
MISSING_GH_ERR="$TMP/missing-gh.err"
PATH="$NOGH" "$BASH_BIN" "$SCRIPT" check --pr 83 --repo owner/name \
  >/dev/null 2>"$MISSING_GH_ERR"
got=$?
if [ "$got" -eq 69 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL ($got != 69): missing gh preflight" >&2
fi
if grep -qF 'stop and hand off unless another authenticated PR-host CLI' \
  "$MISSING_GH_ERR"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: missing gh preflight did not stop and hand off" >&2
fi
rm -rf "$NOGH"

# Git before 2.42 has no show-ref --exists. Keep raw-ref detection on the
# older symbolic-ref plus show-ref --verify primitives.
if grep -qF 'git show-ref --exists' "$SCRIPT"; then
  fail=$((fail + 1))
  echo "FAIL: script requires version-new git show-ref --exists" >&2
else
  pass=$((pass + 1))
fi

# --- behavior half: fixture-serving gh shim + real scratch git repos --------

if ! command -v jq >/dev/null 2>&1; then
  skip=1
  echo "SKIP: behavior cases need jq on PATH; only validation ran" >&2
else

{
  echo '#!/bin/bash'
  echo "FIX=\"$FIX\""
  cat <<'SHIMEOF'
echo "$*" >> "$FIX/calls.log"
jsonval='' jqval='' prev='' sub='' api='' paginate=''
for a in "$@"; do
  case "$prev" in
    --json) jsonval="$a" ;;
    --jq) jqval="$a" ;;
  esac
  case "$a" in
    --json=*) jsonval="${a#--json=}" ;;
    --jq=*) jqval="${a#--jq=}" ;;
    pr|api) [ -z "$sub" ] && sub="$a" ;;
    view|list|merge) [ "$sub" = pr ] && [ -z "${verb:-}" ] && verb="$a" ;;
    repos/*) api="$a" ;;
    --paginate) paginate=1 ;;
    --head=*) headflag=1 ;;
    --base=*) baseflag=1 ;;
  esac
  prev="$a"
done
fixture=''
if [ "$sub" = api ]; then
  case "$api" in
    */rules/branches/*) fixture="$FIX/rules.json" ;;
    */commits/*/check-runs*) fixture="$FIX/checks.json" ;;
    */commits/*/status) fixture="$FIX/status.json" ;;
    */git/ref/heads/*) fixture="$FIX/base-ref.json" ;;
    */pulls\?*) fixture="$FIX/fork-shared.json" ;;
    repos/*/*)
      if [ -f "$FIX/repo-next.json" ]; then
        if [ -f "$FIX/repo-read-once" ]; then
          fixture="$FIX/repo-next.json"
        else
          fixture="$FIX/repo.json"
          : > "$FIX/repo-read-once"
        fi
      else
        fixture="$FIX/repo.json"
      fi
      ;;
  esac
elif [ "$sub" = pr ] && [ "${verb:-}" = view ]; then
  case "$jsonval" in
    *headRefName*|*headRefOid*) fixture="$FIX/pr-full.json" ;;
    *mergedAt*) fixture="$FIX/pr-state.json" ;;
    title) fixture="$FIX/title.json" ;;
  esac
elif [ "$sub" = pr ] && [ "${verb:-}" = list ]; then
  if [ -n "${headflag:-}" ]; then fixture="$FIX/shared.json"
  elif [ -n "${baseflag:-}" ]; then fixture="$FIX/stacked.json"; fi
elif [ "$sub" = pr ] && [ "${verb:-}" = merge ]; then
  rc=0
  [ -f "$FIX/merge-rc" ] && rc=$(cat "$FIX/merge-rc")
  [ "$rc" -eq 0 ] || echo "merge refused by fixture" >&2
  exit "$rc"
fi
if [ "$fixture" = "$FIX/pr-full.json" ] && [ -f "$FIX/pr-next-armed" ]; then
  if [ -f "$FIX/pr-read-once" ]; then fixture="$FIX/pr-next.json"
  else : > "$FIX/pr-read-once"; fi
fi
[ -n "$fixture" ] && [ -f "$fixture" ] || exit 1
# A live head: report the scratch remote's current head OID, as the forge
# would after a push.
if [ "$fixture" = "$FIX/pr-full.json" ] && [ -f "$FIX/live-remote" ]; then
  live=$(git -C "$(cat "$FIX/live-remote")" rev-parse \
    "refs/heads/$(jq -r .headRefName "$fixture")") || exit 1
  jq --arg o "$live" '.headRefOid = $o' "$fixture" > "$FIX/pr-live.json"
  fixture="$FIX/pr-live.json"
fi
if [ -n "$jqval" ]; then
  if [ -n "$paginate" ] \
     && [ "$fixture" = "$FIX/rules.json" ] \
     && [ -f "$FIX/rules-page2-fail" ]; then
    jq -r "$jqval" "$fixture"
    exit 1
  fi
  if [ -n "$paginate" ] \
     && [ "$fixture" = "$FIX/rules.json" ] \
     && [ -f "$FIX/rules-page2.json" ]; then
    exec jq -r "$jqval" "$fixture" "$FIX/rules-page2.json"
  fi
  exec jq -r "$jqval" "$fixture"
fi
exec cat "$fixture"
SHIMEOF
} > "$SHIMD/gh"
chmod +x "$SHIMD/gh"

SCENARIO=""
scenario() {
  SCENARIO="$1"
  rm -f "$FIX"/*.json "$FIX"/calls.log "$FIX"/merge-rc \
    "$FIX"/repo-read-once "$FIX"/rules-page2-fail "$FIX"/live-remote \
    "$FIX"/pr-next-armed "$FIX"/pr-read-once
  SCEN="$TMP/scen-$((pass + fail))"
  mkdir -p "$SCEN"
}
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $SCENARIO: $1" >&2; }
run_sm() {
  OUT=$(cd "$WORK" && PATH="$SHIMD:$PATH" bash "$SCRIPT" "$@" 2>"$FIX/stderr")
  RC=$?
}
run_sm_with_git_shim() { # run_sm_with_git_shim <shim-dir> <args...>
  local git_shim="$1"
  shift
  OUT=$(cd "$WORK" && PATH="$SHIMD:$git_shim:$PATH" bash "$SCRIPT" "$@" 2>"$FIX/stderr")
  RC=$?
}
want_rc() { if [ "$RC" -eq "$1" ]; then ok; else bad "exit $RC, want $1 (out: $OUT; err: $(tail -c 200 "$FIX/stderr" 2>/dev/null))"; fi; }
want_out() { case "$OUT" in *"$1"*) ok ;; *) bad "stdout lacks '$1' (got: $OUT)" ;; esac; }
want_err() { grep -qF -- "$1" "$FIX/stderr" && ok || bad "stderr lacks '$1' (got: $(tail -c 200 "$FIX/stderr"))"; }
want_call() {
  if grep -qF -- "$1" "$FIX/calls.log" 2>/dev/null; then ok; else
    bad "no gh call contained '$1' (log: $(cat "$FIX/calls.log" 2>/dev/null | tr '\n' ';'))"
  fi
}
want_no_call() {
  if grep -qF -- "$1" "$FIX/calls.log" 2>/dev/null; then
    bad "a gh call contained '$1'"
  else ok; fi
}

# pr_full <state> <head> <base> <headOid> <fork> <owner> <name>
# The url's host is what remote auto-resolution matches; .invalid is the
# RFC 2606 reserved TLD, so nothing here can ever touch a real network.
pr_full() {
  jq -n --arg s "$1" --arg h "$2" --arg b "$3" --arg o "$4" \
        --argjson f "$5" --arg ow "$6" --arg rn "$7" \
    '{state:$s, headRefName:$h, baseRefName:$b, headRefOid:$o,
      isCrossRepository:$f,
      headRepositoryOwner:{login:$ow}, headRepository:{name:$rn},
      url:"https://github.invalid/owner/name/pull/83"}' \
    > "$FIX/pr-full.json"
}
repo_fx() { # repo_fx <default-branch> [parent-full-name] [delete-on-merge] [forks-count]
  local delete="${3:-false}" forks="${4:-0}"
  if [ -n "${2:-}" ]; then
    jq -n --arg d "$1" --arg p "$2" --argjson delete "$delete" --argjson forks "$forks" \
      '{default_branch:$d, fork:true, forks_count:$forks, delete_branch_on_merge:$delete,
        parent:{full_name:$p}, source:{full_name:$p},
        clone_url:"https://github.invalid/owner/name.git",
        ssh_url:"git@github.invalid:owner/name.git",
        merge_commit_title:"PR_TITLE", merge_commit_message:"BLANK"}' \
      > "$FIX/repo.json"
  else
    jq -n --arg d "$1" --argjson delete "$delete" --argjson forks "$forks" \
      '{default_branch:$d, fork:false, forks_count:$forks, delete_branch_on_merge:$delete,
        clone_url:"https://github.invalid/owner/name.git",
        ssh_url:"git@github.invalid:owner/name.git",
        merge_commit_title:"PR_TITLE", merge_commit_message:"BLANK"}' \
      > "$FIX/repo.json"
  fi
}
rules_fx() { printf '%s' "$1" > "$FIX/rules.json"; }
lists_empty() { echo '[]' > "$FIX/shared.json"; echo '[]' > "$FIX/stacked.json"; echo '[]' > "$FIX/fork-shared.json"; }
merged_fx() { printf '{"state":"MERGED","mergedAt":"2026-07-25T12:00:00Z"}' > "$FIX/pr-state.json"; }

# Scratch layout: a bare "forge" remote holding main (base) and feat
# (head), with feat merged into main remotely via a real merge commit,
# and a work clone whose local main is still at the pre-merge tip.
G() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
std_setup() { # std_setup [headbranch] [basebranch]
  HB="${1:-feat}"; BB="${2:-main}"
  BARE="$SCEN/remote.git"; WORK="$SCEN/work"
  git init --bare -q -b "$BB" "$BARE"
  SRC="$SCEN/src"
  git init -q -b "$BB" "$SRC"
  G "$SRC" config user.email t@t; G "$SRC" config user.name t
  echo base > "$SRC/base.txt"; G "$SRC" add .; G "$SRC" commit -m A
  G "$SRC" checkout -b "$HB"
  echo feat > "$SRC/feat.txt"; G "$SRC" add .; G "$SRC" commit -m B
  G "$SRC" remote add origin "$BARE"
  G "$SRC" push origin "$BB" "refs/heads/$HB"
  FEAT_OID=$(git -C "$SRC" rev-parse "refs/heads/$HB")
  BASE_PRE=$(git -C "$SRC" rev-parse "refs/heads/$BB")
  # merge on the "forge": a real merge commit on the remote base
  MRG="$SCEN/mrg"
  git clone -q "$BARE" "$MRG"
  G "$MRG" config user.email t@t; G "$MRG" config user.name t
  G "$MRG" checkout "$BB"
  G "$MRG" merge --no-ff -m "merge $HB" "origin/$HB"
  G "$MRG" push origin "$BB"
  # the work clone: local base at the pre-merge tip, local head branch
  git clone -q "$BARE" "$WORK"
  G "$WORK" config user.email t@t; G "$WORK" config user.name t
  G "$WORK" branch "$HB" "origin/$HB"
  G "$WORK" checkout "$BB"
  G "$WORK" reset --hard "$BASE_PRE"
}
std_fixtures() { # std_fixtures [state]: fixtures matching std_setup
  pr_full "${1:-OPEN}" "$HB" "$BB" "$FEAT_OID" false owner name
  repo_fx "$BB"
  rules_fx '[]'
  lists_empty
  merged_fx
}
CHECK=(check --pr 83 --repo owner/name)

# ---- check phase ----

scenario "clean check passes and reports the verified head"
std_setup; std_fixtures
run_sm "${CHECK[@]}"
want_rc 0
want_out "OK check {\"head_oid\":\"$FEAT_OID\""

scenario "closed PR stops check"
std_setup; std_fixtures MERGED
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP pr-not-open'

scenario "local branch moved past the forge head stops check"
std_setup; std_fixtures
G "$WORK" checkout "$HB"
echo more > "$WORK/more.txt"; G "$WORK" add .; G "$WORK" commit -m C
G "$WORK" checkout "$BB"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP oid-mismatch'

scenario "case-folded name collision stops on an ignorecase checkout"
std_setup Main main   # head Main onto base main: one ref file on APFS/NTFS
std_fixtures
G "$WORK" config core.ignorecase true
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP name-collision'

scenario "head matching the default branch stops"
std_setup release main
pr_full OPEN release main "$FEAT_OID" false owner name
repo_fx release   # default branch shares the head's name
rules_fx '[]'; lists_empty
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP name-collision'

scenario "leading-hyphen head branch is refused outright"
std_setup; std_fixtures
pr_full OPEN '-r' main "$FEAT_OID" false owner name
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP bad-name'

scenario "dirty tree stops check"
std_setup; std_fixtures
echo stray > "$WORK/stray.txt"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP dirty-tree'

scenario "showUntrackedFiles=no cannot hide the dirty tree"
std_setup; std_fixtures
G "$WORK" config status.showUntrackedFiles no
echo stray > "$WORK/stray.txt"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP dirty-tree'

scenario "paused merge stops check"
std_setup; std_fixtures
git -C "$WORK" rev-parse HEAD > "$WORK/.git/MERGE_HEAD"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP op-in-progress'

scenario "operation pseudoref names can be ordinary branches"
std_setup; std_fixtures
for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  git -C "$WORK" branch "$p" >/dev/null 2>&1 || bad "could not create branch $p"
done
run_sm "${CHECK[@]}"
want_rc 0
want_out 'OK check'

scenario "a dangling operation-marker symlink still stops"
std_setup; std_fixtures
ln -s missing "$WORK/.git/MERGE_HEAD"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP op-in-progress'

scenario "a corrupt operation-marker file still stops"
std_setup; std_fixtures
printf 'not-an-object\n' > "$WORK/.git/MERGE_HEAD"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP op-in-progress'

scenario "active bisect stops check"
std_setup; std_fixtures
echo main > "$WORK/.git/BISECT_START"   # holds a branch name, not an OID
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP op-in-progress'

scenario "interrupted rebase or am stops check"
std_setup; std_fixtures
mkdir "$WORK/.git/rebase-apply"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP op-in-progress'

scenario "base held by another worktree stops with its path"
std_setup; std_fixtures
G "$WORK" checkout "$HB"
G "$WORK" worktree add "$SCEN/basewt" "$BB"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP wrong-checkout'

scenario "an open PR sharing the head branch stops check"
std_setup; std_fixtures
echo '[{"number":90}]' > "$FIX/shared.json"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP shared-head'

scenario "a failed shared-head listing is unknown, not absence"
std_setup; std_fixtures
rm "$FIX/shared.json"
run_sm "${CHECK[@]}"
want_rc 4
want_out 'LOOKUP_FAILED shared-head'

scenario "check reports open PRs stacked on the branch and passes"
std_setup; std_fixtures
echo '[{"number":91},{"number":92}]' > "$FIX/stacked.json"
run_sm "${CHECK[@]}"
want_rc 0
want_out '"stacked_prs":[91,92]}'
want_err 'open PR(s) 91,92 are based on feat; they move onto main'

scenario "check reports an empty stacked list when nothing stacks"
std_setup; std_fixtures
run_sm "${CHECK[@]}"
want_rc 0
want_out '"stacked_prs":[]}'
if grep -qF 'are based on' "$FIX/stderr"; then bad "stderr reported a stack that is not there"; else ok; fi

scenario "a failed stacked-PR listing is unknown, not absence"
std_setup; std_fixtures
rm "$FIX/stacked.json"
run_sm "${CHECK[@]}"
want_rc 4
want_out 'LOOKUP_FAILED stacked-prs'

scenario "an unparseable stacked-PR listing is unknown, not absence"
std_setup; std_fixtures
echo '[{"number":"x"}]' > "$FIX/stacked.json"
run_sm "${CHECK[@]}"
want_rc 4
want_out 'LOOKUP_FAILED stacked-prs'

scenario "merge-commit queue passes and is reported"
std_setup; std_fixtures
rules_fx '[{"type":"merge_queue","parameters":{"merge_method":"MERGE"}}]'
run_sm "${CHECK[@]}"
want_rc 0
want_out '"queue":"merge"'

scenario "a merge queue with non-title subject settings stops"
std_setup; std_fixtures
rules_fx '[{"type":"merge_queue","parameters":{"merge_method":"MERGE"}}]'
jq '.merge_commit_title = "MERGE_MESSAGE"' "$FIX/repo.json" > "$FIX/repo.new"
mv "$FIX/repo.new" "$FIX/repo.json"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP queue-message'

scenario "a merge queue with a nonblank body setting stops"
std_setup; std_fixtures
rules_fx '[{"type":"merge_queue","parameters":{"merge_method":"MERGE"}}]'
jq '.merge_commit_message = "PR_BODY"' "$FIX/repo.json" > "$FIX/repo.new"
mv "$FIX/repo.new" "$FIX/repo.json"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP queue-message'

scenario "non-title merge settings do not block a branch without a queue"
std_setup; std_fixtures
jq '.merge_commit_title = "MERGE_MESSAGE" | .merge_commit_message = "PR_BODY"' \
  "$FIX/repo.json" > "$FIX/repo.new"
mv "$FIX/repo.new" "$FIX/repo.json"
run_sm "${CHECK[@]}"
want_rc 0
want_out '"queue":"absent"'

scenario "squash queue stops before anything is enqueued"
std_setup; std_fixtures
rules_fx '[{"type":"merge_queue","parameters":{"merge_method":"SQUASH"}}]'
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP queue-method'

scenario "a squash queue on a later rules page still stops"
std_setup; std_fixtures
rules_fx '[{"type":"required_status_checks"}]'
printf '[{"type":"merge_queue","parameters":{"merge_method":"SQUASH"}}]' \
  > "$FIX/rules-page2.json"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP queue-method'
want_call '--paginate'

scenario "duplicate queue rules across pages stop as ambiguous"
std_setup; std_fixtures
rules_fx '[{"type":"merge_queue","parameters":{"merge_method":"MERGE"}}]'
printf '[{"type":"merge_queue","parameters":{"merge_method":"MERGE"}}]' \
  > "$FIX/rules-page2.json"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP queue-method'

scenario "a later branch-rules page failure is unknown, not queue-free"
std_setup; std_fixtures
rules_fx '[]'
: > "$FIX/rules-page2-fail"
run_sm "${CHECK[@]}"
want_rc 4
want_out 'LOOKUP_FAILED queue-rules'

scenario "unidentifiable queue shape stops rather than guessing"
std_setup; std_fixtures
rules_fx '[{"type":"merge_queue","parameters":{"strategy":"who-knows"}}]'
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP queue-method'

scenario "unreadable branch rules are unknown, not queue-free"
std_setup; std_fixtures
rm "$FIX/rules.json"
run_sm "${CHECK[@]}"
want_rc 4
want_out 'LOOKUP_FAILED queue-rules'

scenario "a hash-bearing base branch is percent-encoded in the rules path"
std_setup feat 'release#1'
std_fixtures
run_sm "${CHECK[@]}"
want_rc 0
want_call 'rules/branches/release%231'

scenario "a multibyte base branch encodes as UTF-8 bytes, not sign-extended garbage"
std_setup feat 'relé'
std_fixtures
run_sm "${CHECK[@]}"
want_rc 0
want_call 'rules/branches/rel%C3%A9'

scenario "an alternate ignorecase spelling still folds the collision"
std_setup Main main
std_fixtures
G "$WORK" config core.ignorecase yes
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP name-collision'

filesystem_alias_case() { # filesystem_alias_case <head> <base> <core.ignorecase>
  local head="$1" base="$2" ignorecase="$3"
  local common refs_dir probe probe_head probe_base
  std_setup "$head" "$base"; std_fixtures
  common=$(git -C "$WORK" rev-parse --git-common-dir)
  case "$common" in /*) ;; *) common="$WORK/$common" ;; esac
  refs_dir="$common/refs/heads"
  if [ "${head%/*}" = "${base%/*}" ] && [ "$head" != "${head%/*}" ] \
      && [ -d "$refs_dir/${head%/*}" ]; then
    probe="$refs_dir/${head%/*}/.test-ref-alias"
    probe_head="${head##*/}"
    probe_base="${base##*/}"
  else
    probe="$refs_dir/.test-ref-alias"
    probe_head="$head"
    probe_base="$base"
  fi
  mkdir -p "$probe"
  case "$probe_head" in */*) mkdir -p "$probe/${probe_head%/*}" ;; esac
  case "$probe_base" in */*) mkdir -p "$probe/${probe_base%/*}" ;; esac
  printf x > "$probe/$probe_head"
  printf y > "$probe/$probe_base"
  if [ "$probe/$probe_head" -ef "$probe/$probe_base" ]; then
    aliases=1
  else
    aliases=0
  fi
  rm -rf "$probe"
  G "$WORK" config core.ignorecase "$ignorecase"
  run_sm "${CHECK[@]}"
  if [ "$aliases" -eq 1 ]; then
    want_rc 2
    want_out 'STOP name-collision'
  else
    want_rc 0
    want_out 'OK check'
  fi
}

scenario "Unicode case collision follows the checkout filesystem"
filesystem_alias_case "team/$(printf '\303\211')" "team/$(printf '\303\251')" true

scenario "Unicode normalization collision follows the checkout filesystem"
filesystem_alias_case "$(printf '\303\251')" "$(printf 'e\314\201')" true

scenario "a false ignorecase setting does not override the checkout filesystem"
filesystem_alias_case Feature feature false

scenario "a newline-ending common-directory path is preserved in the alias probe"
head_name=$(printf '\303\211')
base_name=$(printf '\303\251')
std_setup "$head_name" "$base_name"; std_fixtures
# If the script strips the trailing newline, refs_dir lands under this
# non-directory sibling and the scenario must fail rather than passing
# against equivalent filesystem semantics at the wrong path.
printf obstruction > "$SCEN/common"
COMMON_NL="$SCEN/common"$'\n'
mkdir -p "$COMMON_NL/refs/heads"
probe="$COMMON_NL/refs/heads/.test-ref-alias"
mkdir -p "$probe"
printf x > "$probe/$head_name"
printf y > "$probe/$base_name"
if [ "$probe/$head_name" -ef "$probe/$base_name" ]; then
  aliases=1
else
  aliases=0
fi
rm -rf "$probe"
G "$WORK" config core.ignorecase true
COMMON_GIT_SHIM="$SCEN/common-git-shim"
mkdir -p "$COMMON_GIT_SHIM"
REAL_GIT=$(command -v git)
{
  echo '#!/bin/bash'
  printf 'COMMON_DIR=%q\n' "$COMMON_NL"
  printf 'REAL_GIT=%q\n' "$REAL_GIT"
  echo 'if [ "$#" -eq 2 ] && [ "$1" = rev-parse ] && [ "$2" = --git-common-dir ]; then'
  echo '  printf "%s\n" "$COMMON_DIR"'
  echo '  exit 0'
  echo 'fi'
  echo 'exec "$REAL_GIT" "$@"'
} > "$COMMON_GIT_SHIM/git"
chmod +x "$COMMON_GIT_SHIM/git"
run_sm_with_git_shim "$COMMON_GIT_SHIM" "${CHECK[@]}"
if [ "$aliases" -eq 1 ]; then
  want_rc 2
  want_out 'STOP name-collision'
else
  want_rc 0
  want_out 'OK check'
fi

scenario "check passes from the base checkout of a worktree layout"
std_setup; std_fixtures
G "$WORK" worktree add "$SCEN/featwt" "$HB"   # head in a linked worktree
run_sm "${CHECK[@]}"
want_rc 0
want_out 'OK check'

scenario "duplicate base worktrees stop at check"
std_setup; std_fixtures
G "$WORK" worktree add --force "$SCEN/basewt" "$BB"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP duplicate-worktree'

scenario "duplicate head worktrees stop at check"
std_setup; std_fixtures
G "$WORK" worktree add "$SCEN/featwt" "$HB"
G "$WORK" worktree add --force "$SCEN/featwt2" "$HB"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP duplicate-worktree'

scenario "check refuses when the session holds no local head branch"
std_setup; std_fixtures
G "$WORK" branch -D "$HB"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP no-local-branch'

scenario "a branch in a fork-owned repository can head an upstream PR: stop"
std_setup; std_fixtures
repo_fx "$BB" upstream/name
echo '[{"number":83}]' > "$FIX/fork-shared.json"   # same number, other repo, still counts
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP shared-head'

scenario "fork consumer lookups use the owner-qualified encoded form"
std_setup 'feat#2' main
pr_full OPEN 'feat#2' main "$FEAT_OID" true forker name
repo_fx main; rules_fx '[]'; lists_empty
run_sm "${CHECK[@]}"
want_rc 0
want_call 'pulls?state=open&head=forker:feat%232'

scenario "a PR stacked on a cross-repository head still stops check"
std_setup
pr_full OPEN feat main "$FEAT_OID" true forker name
repo_fx main; rules_fx '[]'; lists_empty
echo '[{"number":91}]' > "$FIX/stacked.json"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP stacked-prs'

# ---- merge phase ----

scenario "merge pins the head, passes a title-only message, and waits for MERGED"
std_setup; std_fixtures
printf '{"title":"Fix the thing"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 0
want_out 'OK merge'
want_call "--match-head-commit=$FEAT_OID"
want_call "--subject=Fix the thing (#83)"

scenario "merge reports a stacked PR and still merges"
std_setup; std_fixtures
printf '{"title":"Fix the thing"}' > "$FIX/title.json"
echo '[{"number":90}]' > "$FIX/stacked.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 0
want_out 'OK merge'
want_call 'pr merge'
want_err 'open PR(s) 90 are based on feat'

scenario "merge polling caps a long interval at the remaining deadline"
std_setup; std_fixtures
printf '{"title":"Fix the thing"}' > "$FIX/title.json"
printf '{"state":"OPEN","mergedAt":null}' > "$FIX/pr-state.json"
printf '{"state":"MERGED","mergedAt":"2026-07-25T12:00:00Z"}' \
  > "$FIX/pr-state-next.json"
SLEEP_SHIM="$SCEN/sleep-shim"
mkdir -p "$SLEEP_SHIM"
{
  echo '#!/bin/sh'
  printf 'printf "%%s\\n" "$1" > %q\n' "$FIX/sleep-arg"
  printf 'cp %q %q\n' "$FIX/pr-state-next.json" "$FIX/pr-state.json"
} > "$SLEEP_SHIM/sleep"
chmod +x "$SLEEP_SHIM/sleep"
run_sm_with_git_shim "$SLEEP_SHIM" merge --pr 83 --repo owner/name \
  --head "$FEAT_OID" --cap-minutes 1 --interval 999
want_rc 0
want_out 'OK merge'
sleep_arg=$(cat "$FIX/sleep-arg" 2>/dev/null)
case "$sleep_arg" in
  ''|*[!0-9]*) bad "sleep received a non-integer duration: $sleep_arg" ;;
  *)
    if [ "$sleep_arg" -le 0 ] || [ "$sleep_arg" -gt 60 ]; then
      bad "sleep $sleep_arg exceeded the one-minute cap"
    else
      ok
    fi
    ;;
esac

scenario "a null title never reaches the merge message"
std_setup; std_fixtures
printf '{"title":null}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED title'

scenario "a push since check fails the merge's head pin"
std_setup; std_fixtures
run_sm merge --pr 83 --repo owner/name --head 9999999999999999999999999999999999999999
want_rc 2
want_out 'STOP oid-mismatch'

scenario "a refused merge is reported, not tidied around"
std_setup; std_fixtures
printf '{"title":"T"}' > "$FIX/title.json"
echo 1 > "$FIX/merge-rc"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP merge-refused'

scenario "a PR sharing the head after check still stops the merge"
std_setup; std_fixtures
printf '{"title":"T"}' > "$FIX/title.json"
echo '[{"number":90}]' > "$FIX/shared.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP shared-head'
if grep -q 'pr merge' "$FIX/calls.log" 2>/dev/null; then
  bad "the merge command ran despite the shared head"
else ok; fi

scenario "fork-base auto-delete stops before the merge"
std_setup; std_fixtures
repo_fx "$BB" upstream/name true
rules_fx '[{"type":"merge_queue","parameters":{"merge_method":"MERGE"}}]'
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP fork-auto-delete'
if grep -q 'pr merge' "$FIX/calls.log" 2>/dev/null; then
  bad "the merge ran despite unenumerable fork-network consumers"
else ok; fi

scenario "a last-moment auto-delete change still stops the merge"
std_setup; std_fixtures
repo_fx "$BB" upstream/name false
jq '.delete_branch_on_merge = true' "$FIX/repo.json" > "$FIX/repo-next.json"
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP fork-auto-delete'
if grep -q 'pr merge' "$FIX/calls.log" 2>/dev/null; then
  bad "the merge ran after auto-delete changed between repository reads"
else ok; fi

scenario "a fork base without auto-delete can still merge"
std_setup; std_fixtures
repo_fx "$BB" upstream/name false
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 0
want_out 'OK merge'

scenario "a non-fork base with auto-delete can still merge"
std_setup; std_fixtures
repo_fx "$BB" "" true
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 0
want_out 'OK merge'

scenario "a root repository with forks and auto-delete stops the merge"
std_setup; std_fixtures
repo_fx "$BB" "" true 1
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP fork-auto-delete'

scenario "a last-moment first fork still stops auto-delete"
std_setup; std_fixtures
repo_fx "$BB" "" true 0
jq '.forks_count = 1' "$FIX/repo.json" > "$FIX/repo-next.json"
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP fork-auto-delete'
if grep -q 'pr merge' "$FIX/calls.log" 2>/dev/null; then
  bad "the merge ran after the first fork appeared between repository reads"
else ok; fi

scenario "a root repository with forks can merge when auto-delete is off"
std_setup; std_fixtures
repo_fx "$BB" "" false 1
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 0
want_out 'OK merge'

scenario "a cross-repository head is outside the base auto-delete guard"
std_setup; std_fixtures
pr_full OPEN "$HB" "$BB" "$FEAT_OID" true forker name
repo_fx "$BB" upstream/name true
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 0
want_out 'OK merge'

scenario "a missing auto-delete field is unknown"
std_setup; std_fixtures
jq 'del(.delete_branch_on_merge)' "$FIX/repo.json" > "$FIX/repo.new"
mv "$FIX/repo.new" "$FIX/repo.json"
run_sm "${CHECK[@]}"
want_rc 4
want_out 'LOOKUP_FAILED repo-facts'

scenario "a missing forks count is unknown"
std_setup; std_fixtures
jq 'del(.forks_count)' "$FIX/repo.json" > "$FIX/repo.new"
mv "$FIX/repo.new" "$FIX/repo.json"
run_sm "${CHECK[@]}"
want_rc 4
want_out 'LOOKUP_FAILED repo-facts'

scenario "a negative forks count is unknown"
std_setup; std_fixtures
jq '.forks_count = -1' "$FIX/repo.json" > "$FIX/repo.new"
mv "$FIX/repo.new" "$FIX/repo.json"
run_sm "${CHECK[@]}"
want_rc 4
want_out 'LOOKUP_FAILED repo-facts'

scenario "a retarget onto a squash queue after check still stops the merge"
std_setup; std_fixtures
printf '{"title":"T"}' > "$FIX/title.json"
rules_fx '[{"type":"merge_queue","parameters":{"merge_method":"SQUASH"}}]'
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP queue-method'

scenario "a last-moment queue message setting change stops the merge"
std_setup; std_fixtures
rules_fx '[{"type":"merge_queue","parameters":{"merge_method":"MERGE"}}]'
jq '.merge_commit_message = "PR_BODY"' "$FIX/repo.json" > "$FIX/repo-next.json"
printf '{"title":"T"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP queue-message'
if grep -q 'pr merge' "$FIX/calls.log" 2>/dev/null; then
  bad "the merge ran after queued merge-message settings changed"
else ok; fi

scenario "enqueued is not merged: the wait caps out as pending"
std_setup; std_fixtures
printf '{"title":"T"}' > "$FIX/title.json"
printf '{"state":"OPEN","mergedAt":null}' > "$FIX/pr-state.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID" --cap-minutes 0 --interval 1
want_rc 4
want_out 'LOOKUP_FAILED merge-pending'

# ---- land phase ----

# Scratch layout for land: a bare "forge" remote holding main (A) and feat
# (B on A), unmerged. "behind" adds C to the remote main after the branch
# point; "conflict" makes C change feat.txt too. The work clone has main
# checked out and a local feat at B.
land_setup() { # land_setup [behind|conflict]
  HB=feat; BB=main
  BARE="$SCEN/remote.git"; WORK="$SCEN/work"; SRC="$SCEN/src"
  git init --bare -q -b main "$BARE"
  git init -q -b main "$SRC"
  G "$SRC" config user.email t@t; G "$SRC" config user.name t
  echo base > "$SRC/base.txt"; G "$SRC" add .; G "$SRC" commit -m A
  G "$SRC" checkout -b feat
  echo feat > "$SRC/feat.txt"; G "$SRC" add .; G "$SRC" commit -m B
  G "$SRC" remote add origin "$BARE"
  G "$SRC" push origin main feat
  FEAT_OID=$(git -C "$SRC" rev-parse feat)
  case "${1:-}" in
    behind|conflict)
      G "$SRC" checkout main
      if [ "$1" = conflict ]; then echo other > "$SRC/feat.txt"
      else echo more > "$SRC/more.txt"; fi
      G "$SRC" add .; G "$SRC" commit -m C
      G "$SRC" push origin main
      ;;
  esac
  BASE_TIP=$(git -C "$SRC" rev-parse main)
  git clone -q "$BARE" "$WORK"
  G "$WORK" config user.email t@t; G "$WORK" config user.name t
  G "$WORK" branch feat origin/feat
}
checks_fx() { # checks_fx <status> <conclusion-json>
  jq -n --arg s "$1" --argjson c "$2" \
    '{total_count:1, check_runs:[{name:"ci", status:$s, conclusion:$c}]}' \
    > "$FIX/checks.json"
}
status_fx() { # status_fx <state> <count>
  jq -n --arg s "$1" --argjson n "$2" '{state:$s, total_count:$n}' > "$FIX/status.json"
}
base_ref_fx() { jq -n --arg o "$1" '{object:{sha:$o, type:"commit"}}' > "$FIX/base-ref.json"; }
land_fixtures() { # green CI, an unmoved base, and a live forge head
  pr_full OPEN feat main "$FEAT_OID" false owner name
  repo_fx main; rules_fx '[]'; lists_empty; merged_fx
  printf '{"title":"T"}' > "$FIX/title.json"
  checks_fx completed '"success"'
  status_fx pending 0
  base_ref_fx "$BASE_TIP"
  echo "$BARE" > "$FIX/live-remote"
}
LAND=(land --pr 83 --repo owner/name --base-remote origin --head-remote origin --interval 1)
remote_feat() { git -C "$BARE" rev-parse refs/heads/feat; }
local_feat() { git -C "$WORK" rev-parse refs/heads/feat; }
worktree_count() { git -C "$WORK" worktree list --porcelain | grep -c '^worktree '; }
# A stop before the rebase must leave both copies of the head where check
# saw them; a push proves the guard ran too late.
want_land_untouched() { # want_land_untouched <message>
  if [ "$(remote_feat)" = "$FEAT_OID" ] && [ "$(local_feat)" = "$FEAT_OID" ]; then
    ok
  else bad "$1"; fi
}
want_land_pushed() { # the rebased head reached the forge
  if [ "$(remote_feat)" != "$FEAT_OID" ] && [ "$(local_feat)" = "$(remote_feat)" ]; then
    ok
  else bad "the rebased head was not pushed (remote $(remote_feat), local $(local_feat))"; fi
}

scenario "land merges a head already on the tip once CI is green"
land_setup; land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 0
want_out "OK land {\"head_oid\":\"$FEAT_OID\",\"merged_at\":"
want_call "commits/$FEAT_OID/check-runs"
want_call "commits/$FEAT_OID/status"
want_call "git/ref/heads/main"
want_call "--match-head-commit=$FEAT_OID"
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "an on-tip land rewrote the remote branch"

scenario "land rebases a behind head, lease-pushes it, and stops for its range-diff"
land_setup behind; land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
NEW_OID=$(remote_feat)
[ "$NEW_OID" != "$FEAT_OID" ] && ok || bad "the remote branch was not rewritten"
git -C "$BARE" merge-base --is-ancestor "$BASE_TIP" "$NEW_OID" && ok \
  || bad "the pushed head does not contain the fetched tip"
[ "$(local_feat)" = "$NEW_OID" ] && ok || bad "local feat is not the pushed head"
want_out "STOP rebased {\"head_oid\":\"$NEW_OID\",\"old_head_oid\":\"$FEAT_OID\",\"base_tip\":\"$BASE_TIP\","
want_no_call "commits/$NEW_OID/check-runs"
want_no_call 'pr merge'
[ "$(worktree_count)" -eq 1 ] && ok || bad "the temporary worktree was left behind"
grep -qF 'git range-diff' "$FIX/stderr" && ok || bad "stderr lacks the range-diff"
# The rerun with the new head finds it on the tip, waits for CI, and merges.
run_sm "${LAND[@]}" --head "$NEW_OID"
want_rc 0
want_out "OK land {\"head_oid\":\"$NEW_OID\",\"merged_at\":"
want_call "commits/$NEW_OID/check-runs"
want_call "--match-head-commit=$NEW_OID"
[ "$(remote_feat)" = "$NEW_OID" ] && ok || bad "the rerun rewrote the remote branch"

scenario "land moves the worktree that holds the head to the rebased head"
land_setup behind; land_fixtures
G "$WORK" worktree add "$SCEN/feat-wt" feat
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebased'
NEW_OID=$(remote_feat)
[ "$(git -C "$SCEN/feat-wt" rev-parse HEAD)" = "$NEW_OID" ] && ok \
  || bad "the head worktree is not at the rebased head"
[ "$(git -C "$SCEN/feat-wt" symbolic-ref HEAD)" = refs/heads/feat ] && ok \
  || bad "the head worktree no longer has feat checked out"
[ -z "$(git -C "$SCEN/feat-wt" status --porcelain)" ] && ok || bad "the head worktree was left dirty"
[ "$(worktree_count)" -eq 2 ] && ok || bad "the temporary worktree was left behind"

scenario "files a hook writes in the temporary worktree do not leak it"
land_setup behind; land_fixtures
printf '#!/bin/sh\necho hook > hook-artifact.txt\n' > "$WORK/.git/hooks/post-checkout"
chmod +x "$WORK/.git/hooks/post-checkout"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebased'
[ "$(worktree_count)" -eq 1 ] && ok || bad "the temporary worktree was left behind"

scenario "land refuses to rebase a dirty head worktree"
land_setup behind; land_fixtures
G "$WORK" worktree add "$SCEN/feat-wt" feat
echo wip > "$SCEN/feat-wt/wip.txt"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP dirty-tree'
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "the remote branch moved"

scenario "a conflicting rebase is aborted and leaves both branches untouched"
land_setup conflict; land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebase-conflict'
want_out 'feat.txt'
[ "$(local_feat)" = "$FEAT_OID" ] && ok || bad "local feat moved"
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "the remote branch moved"
[ "$(worktree_count)" -eq 1 ] && ok || bad "the temporary worktree was left behind"
want_no_call 'pr merge'

scenario "a push since check fails the rebase lease and restores the local branch"
land_setup behind; land_fixtures
rm -f "$FIX/live-remote"   # the forge read still shows the reviewed head
G "$SRC" checkout feat
echo late > "$SRC/late.txt"; G "$SRC" add .; G "$SRC" commit -m late
G "$SRC" push origin feat
LATE_OID=$(git -C "$SRC" rev-parse feat)
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP lease-failed'
[ "$(remote_feat)" = "$LATE_OID" ] && ok || bad "the lease did not protect the later push"
[ "$(local_feat)" = "$FEAT_OID" ] && ok || bad "local feat was not restored"
want_no_call 'pr merge'

scenario "a failed check stops land"
land_setup; land_fixtures
checks_fx completed '"failure"'
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP checks-failed'
want_no_call 'pr merge'

scenario "a failed commit status stops land even with green check runs"
land_setup; land_fixtures
status_fx failure 1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP checks-failed'
want_no_call 'pr merge'

scenario "a green read waits for a second read before it passes"
land_setup; land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 0
[ "$(grep -c "commits/$FEAT_OID/check-runs" "$FIX/calls.log")" -ge 2 ] && ok \
  || bad "land passed CI on a single read"

scenario "a single green read at the cap is pending, not passed"
land_setup; land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID" --ci-cap-minutes 0
want_rc 2
want_out 'STOP checks-pending'
want_no_call 'pr merge'

scenario "a check still running at the cap stops land"
land_setup; land_fixtures
checks_fx in_progress null
run_sm "${LAND[@]}" --head "$FEAT_OID" --ci-cap-minutes 0
want_rc 2
want_out 'STOP checks-pending'
want_no_call 'pr merge'

scenario "a commit with no CI at the cap is missing, not green"
land_setup; land_fixtures
echo '{"total_count":0,"check_runs":[]}' > "$FIX/checks.json"
run_sm "${LAND[@]}" --head "$FEAT_OID" --ci-cap-minutes 0
want_rc 2
want_out 'STOP checks-missing'
want_no_call 'pr merge'

scenario "an unreadable check list is unknown, not green"
land_setup; land_fixtures
rm -f "$FIX/checks.json"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED check-runs'
want_no_call 'pr merge'

scenario "a base that moved after the fetch stops land before the merge"
land_setup; land_fixtures
base_ref_fx 9999999999999999999999999999999999999999
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP base-moved'
want_no_call 'pr merge'

scenario "an ignored file the base starts tracking stops the worktree move"
land_setup behind; land_fixtures
G "$WORK" worktree add "$SCEN/feat-wt" feat
echo more.txt >> "$WORK/.git/info/exclude"
echo mine > "$SCEN/feat-wt/more.txt"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP ignored-clobber'
[ "$(cat "$SCEN/feat-wt/more.txt")" = mine ] && ok || bad "the ignored file was overwritten"
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "the remote branch moved"
[ "$(local_feat)" = "$FEAT_OID" ] && ok || bad "local feat moved"

# Git's refusal names every blocking file; a long list must still classify.
scenario "many ignored files in the way still stop ignored-clobber"
land_setup
G "$SRC" checkout main
for i in $(seq 1 40); do echo "$i" > "$SRC/generated-file-with-a-long-name-$i.out"; done
G "$SRC" add .; G "$SRC" commit -m many; G "$SRC" push origin main
BASE_TIP=$(git -C "$SRC" rev-parse main)
G "$WORK" worktree add "$SCEN/feat-wt" feat
echo '*.out' >> "$WORK/.git/info/exclude"
for i in $(seq 1 40); do echo mine > "$SCEN/feat-wt/generated-file-with-a-long-name-$i.out"; done
land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP ignored-clobber'
[ "$(cat "$SCEN/feat-wt/generated-file-with-a-long-name-40.out")" = mine ] && ok || bad "an ignored file was overwritten"
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "the remote branch moved"

# The base replaces a tracked directory with a file, or adds a path under an
# ignored file. A rebase or reset deletes the ignored file in both shapes.
for shape in dir-to-file file-to-dir; do
  scenario "an ignored file in the way of a $shape change stops the worktree move"
  land_setup
  G "$SRC" checkout main
  if [ "$shape" = dir-to-file ]; then
    mkdir "$SRC/d"; echo x > "$SRC/d/x"; G "$SRC" add d; G "$SRC" commit -m M1
    G "$SRC" checkout feat; G "$SRC" rebase main; G "$SRC" push -f origin feat
    G "$SRC" checkout main
    G "$SRC" rm -r d; echo file > "$SRC/d"; G "$SRC" add d; G "$SRC" commit -m M2
    keep=d/keep.log; echo '*.log' >> "$WORK/.git/info/exclude"
  else
    mkdir "$SRC/d"; echo x > "$SRC/d/x"; G "$SRC" add d; G "$SRC" commit -m M1
    keep=d; echo /d >> "$WORK/.git/info/exclude"
  fi
  G "$SRC" push origin main
  BASE_TIP=$(git -C "$SRC" rev-parse main); FEAT_OID=$(git -C "$SRC" rev-parse feat)
  G "$WORK" fetch origin; G "$WORK" branch -f feat origin/feat
  G "$WORK" worktree add "$SCEN/feat-wt" feat
  mkdir -p "$(dirname "$SCEN/feat-wt/$keep")"; echo mine > "$SCEN/feat-wt/$keep"
  land_fixtures
  run_sm "${LAND[@]}" --head "$FEAT_OID"
  want_rc 2
  want_out 'STOP ignored-clobber'
  [ "$(cat "$SCEN/feat-wt/$keep" 2>/dev/null)" = mine ] && ok || bad "the ignored file was overwritten or removed"
  [ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "the remote branch moved"
  [ "$(local_feat)" = "$FEAT_OID" ] && ok || bad "local feat moved"
done

# The head stops tracking base.txt and keeps it as an ignored local file. An
# in-place rebase would check out the base tip over it and then delete it.
# Rebased elsewhere, an unchanged base lands with the file intact, and a
# modify/delete conflict stops with it intact.
for base_edit in unchanged modified; do
  scenario "an ignored file the head untracked survives land (base $base_edit)"
  land_setup behind
  if [ "$base_edit" = modified ]; then
    G "$SRC" checkout main
    echo changed > "$SRC/base.txt"; G "$SRC" commit -am D
    G "$SRC" push origin main
    BASE_TIP=$(git -C "$SRC" rev-parse main)
  fi
  G "$WORK" worktree add "$SCEN/feat-wt" feat
  G "$SCEN/feat-wt" rm --cached base.txt
  echo base.txt > "$SCEN/feat-wt/.gitignore"
  G "$SCEN/feat-wt" add .gitignore; G "$SCEN/feat-wt" commit -m untrack
  G "$SCEN/feat-wt" push origin feat
  FEAT_OID=$(git -C "$SCEN/feat-wt" rev-parse HEAD)
  echo mine > "$SCEN/feat-wt/base.txt"
  land_fixtures
  run_sm "${LAND[@]}" --head "$FEAT_OID"
  if [ "$base_edit" = modified ]; then
    want_rc 2
    want_out 'STOP rebase-conflict'
    [ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "the remote branch moved"
  else
    want_rc 2
    want_out 'STOP rebased'
    [ "$(git -C "$SCEN/feat-wt" rev-parse HEAD)" = "$(remote_feat)" ] && ok \
      || bad "the head worktree is not at the rebased head"
  fi
  [ "$(cat "$SCEN/feat-wt/base.txt" 2>/dev/null)" = mine ] && ok || bad "the ignored file was overwritten or removed"
done

scenario "a push since check restores the branch in its own worktree"
land_setup behind; land_fixtures
rm -f "$FIX/live-remote"
G "$WORK" worktree add "$SCEN/feat-wt" feat
G "$SRC" checkout feat
echo late > "$SRC/late.txt"; G "$SRC" add .; G "$SRC" commit -m late
G "$SRC" push origin feat
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP lease-failed'
[ "$(git -C "$SCEN/feat-wt" rev-parse HEAD)" = "$FEAT_OID" ] && ok \
  || bad "the head worktree was not reset to the reviewed head"
[ -z "$(git -C "$SCEN/feat-wt" status --porcelain)" ] && ok || bad "the head worktree was left dirty"

scenario "a rebase that leaves nothing to land never pushes the base tip"
land_setup behind; land_fixtures
G "$SRC" checkout main
G "$SRC" cherry-pick "$FEAT_OID"
G "$SRC" push origin main
BASE_TIP=$(git -C "$SRC" rev-parse main); base_ref_fx "$BASE_TIP"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebase-failed'
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "the base tip was pushed as the head"
[ "$(local_feat)" = "$FEAT_OID" ] && ok || bad "local feat was not restored"

scenario "land rebases a behind head under a stacked PR and reports it"
land_setup behind; land_fixtures
echo '[{"number":90}]' > "$FIX/stacked.json"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebased'
want_land_pushed
want_err 'open PR(s) 90 are based on feat'

scenario "a base force-pushed to a non-descendant still lands against its new tip"
land_setup behind
G "$SRC" checkout main
G "$SRC" commit --amend -m C-rewritten
G "$SRC" push -f origin main
BASE_TIP=$(git -C "$SRC" rev-parse main)
land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebased'
want_out "\"base_tip\":\"$BASE_TIP\""
git -C "$BARE" merge-base --is-ancestor "$BASE_TIP" "$(remote_feat)" && ok \
  || bad "the pushed head does not contain the rewritten tip"

scenario "a lagging base remote stops before the rebase"
land_setup behind; land_fixtures
base_ref_fx 9999999999999999999999999999999999999999
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP base-moved'
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "land rebased against a stale base"

scenario "neutral and skipped checks pass, a cancelled one fails"
land_setup; land_fixtures
echo '{"total_count":2,"check_runs":[{"name":"a","status":"completed","conclusion":"neutral"},{"name":"b","status":"completed","conclusion":"skipped"}]}' > "$FIX/checks.json"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 0
scenario "a cancelled check fails land"
land_setup; land_fixtures
checks_fx completed '"cancelled"'
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP checks-failed'

scenario "a pending commit status holds land at the cap"
land_setup; land_fixtures
status_fx pending 1
run_sm "${LAND[@]}" --head "$FEAT_OID" --ci-cap-minutes 0
want_rc 2
want_out 'STOP checks-pending'

scenario "a third head after the push stops land"
land_setup behind; land_fixtures
rm -f "$FIX/live-remote"
pr_full OPEN feat main "$FEAT_OID" false owner name
# The forge reports neither the reviewed head nor the pushed one after the
# push: the shim serves this fixture to every read after the first.
jq '.headRefOid = "8888888888888888888888888888888888888888"' "$FIX/pr-full.json" > "$FIX/pr-next.json"
: > "$FIX/pr-next-armed"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP oid-mismatch'
want_no_call 'pr merge'

scenario "a retarget during the CI wait stops land"
land_setup; land_fixtures
: > "$FIX/pr-next-armed"
jq '.baseRefName = "release"' "$FIX/pr-full.json" > "$FIX/pr-next.json"
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP base-moved'
want_no_call 'pr merge'

scenario "a dry run on a behind head reports not-on-tip and changes nothing"
land_setup behind; land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID" --dry-run
want_rc 2
want_out 'STOP not-on-tip'
want_out 'dry run'
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "a dry run pushed"
[ "$(local_feat)" = "$FEAT_OID" ] && ok || bad "a dry run rebased"
grep -qF 'checks:' "$FIX/stderr" && grep -qF 'base:' "$FIX/stderr" && ok \
  || bad "the dry run did not report every check"
want_no_call 'pr merge'

scenario "a dry run on a ready head reports the merge it would make"
land_setup; land_fixtures
run_sm "${LAND[@]}" --head "$FEAT_OID" --dry-run
want_rc 0
want_out "OK land {\"dry_run\":true,\"head_oid\":\"$FEAT_OID\""
want_no_call 'pr merge'

scenario "a cross-repository head behind the tip is the author's to rebase"
land_setup behind; land_fixtures
pr_full OPEN feat main "$FEAT_OID" true someone fork
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP not-on-tip'
[ "$(remote_feat)" = "$FEAT_OID" ] && ok || bad "land pushed a fork's branch"

# ---- remote identity on the land push ----
# Each case configures a remote whose identity land must refuse (or accept)
# before its lease push rewrites the head branch. A behind head makes land
# reach the push path; a stop there leaves both copies of the head untouched.

scenario "a newline-bearing remote URL cannot be validated: stop"
land_setup behind; land_fixtures
G "$WORK" remote add nlrem "$SCEN/x"$'\n'
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote nlrem --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a split fetch/push remote identity stops before any check"
land_setup behind; land_fixtures
git -C "$WORK" remote set-url --push origin "$SCEN/other.git" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "a branch was pushed across a fetch/push split"

scenario "a hosted head override must identify the PR repository"
land_setup behind; land_fixtures
G "$WORK" remote add wrong https://github.invalid/other/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote wrong --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a hosted base override must identify the PR repository"
land_setup behind; land_fixtures
G "$WORK" remote add wrong https://github.invalid/other/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote wrong --head-remote origin --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a hosted override with an extra path prefix is not the PR repository"
land_setup behind; land_fixtures
G "$WORK" remote add wrong https://github.invalid/prefix/owner/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote wrong --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a userless SCP override must identify the PR repository"
land_setup behind; land_fixtures
G "$WORK" remote add wrong github.invalid:other/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote wrong --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "different SSH users are different push destinations"
land_setup behind; land_fixtures
G "$WORK" remote add split git@github.invalid:owner/name.git
git -C "$WORK" remote set-url --push split deploy@github.invalid:owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "different ssh-scheme users are different push destinations"
land_setup behind; land_fixtures
jq '.ssh_url = "ssh://git@github.invalid/owner/name.git"' \
  "$FIX/repo.json" > "$FIX/repo.new"
mv "$FIX/repo.new" "$FIX/repo.json"
G "$WORK" remote add split ssh://git@github.invalid/owner/name.git
git -C "$WORK" remote set-url --push split ssh://deploy@github.invalid/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "HTTPS and userless SSH are different push destinations"
land_setup behind; land_fixtures
G "$WORK" remote add split https://github.invalid/owner/name.git
git -C "$WORK" remote set-url --push split ssh://github.invalid/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "HTTPS and git transport are different push destinations"
land_setup behind; land_fixtures
G "$WORK" remote add split https://github.invalid/owner/name.git
git -C "$WORK" remote set-url --push split git://github.invalid/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "SCP and ssh scheme are different push destinations"
land_setup behind; land_fixtures
G "$WORK" remote add split git@github.invalid:owner/name.git
git -C "$WORK" remote set-url --push split ssh://git@github.invalid/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "auto-resolution skips an origin with the wrong SSH user"
land_setup behind; land_fixtures
G "$WORK" remote set-url origin deploy@github.invalid:owner/name.git
G "$WORK" remote add forge git@github.invalid:owner/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED base-fetch'
want_land_untouched "the remote head was pushed before the selected base remote failed"

scenario "a second configured push URL still stops the split"
land_setup behind; land_fixtures
git -C "$WORK" remote set-url --push origin "$BARE" >/dev/null 2>&1
git -C "$WORK" remote set-url --push --add origin "$SCEN/other.git" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "a branch was pushed despite a broadcast push URL"

scenario "duplicate effective push URLs stop before the lease push"
land_setup behind; land_fixtures
git -C "$WORK" remote set-url --push origin "$BARE" >/dev/null 2>&1
git -C "$WORK" remote set-url --push --add origin "$BARE" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the first duplicate destination pushed the branch before the stop"

scenario "a blank push URL stops before the valid destination is mutated"
land_setup behind; land_fixtures
git -C "$WORK" remote set-url --push origin "$BARE" >/dev/null 2>&1
BLANK_PUSH_SHIM="$SCEN/blank-push-shim"
mkdir -p "$BLANK_PUSH_SHIM"
REAL_GIT=$(command -v git)
{
  echo '#!/bin/bash'
  printf 'PUSH_URL=%q\n' "$BARE"
  printf 'REAL_GIT=%q\n' "$REAL_GIT"
  echo 'if [ "$#" -eq 6 ] && [ "$1" = remote ] && [ "$2" = get-url ] && [ "$3" = --push ] && [ "$4" = --all ] && [ "$5" = -- ] && [ "$6" = origin ]; then'
  echo '  printf "%s\n\n" "$PUSH_URL"'
  echo '  exit 0'
  echo 'fi'
  echo 'exec "$REAL_GIT" "$@"'
} > "$BLANK_PUSH_SHIM/git"
chmod +x "$BLANK_PUSH_SHIM/git"
run_sm_with_git_shim "$BLANK_PUSH_SHIM" "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the valid destination pushed the branch before the blank-URL stop"

scenario "two local paths sharing a tail are two repositories"
land_setup behind; land_fixtures
G "$WORK" remote add split "$SCEN/a/owner/name"
git -C "$WORK" remote set-url --push split "$SCEN/b/owner/name" >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "two hosted paths sharing a tail are two repositories"
land_setup behind; land_fixtures
G "$WORK" remote add split https://github.invalid/a/owner/name.git
git -C "$WORK" remote set-url --push split https://github.invalid/b/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "hosted path case is part of the endpoint identity"
land_setup behind; land_fixtures
G "$WORK" remote add split https://github.invalid/A/owner/name.git
git -C "$WORK" remote set-url --push split https://github.invalid/a/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a hosted .git suffix is part of the endpoint identity"
land_setup behind; land_fixtures
G "$WORK" remote add split https://github.invalid/prefix/owner/name
git -C "$WORK" remote set-url --push split https://github.invalid/prefix/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a hosted path prefix does not hide its forge repository tail"
land_setup behind; land_fixtures
G "$WORK" remote add prefixed https://github.invalid/prefix/owner/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-unresolved'
want_land_untouched "the stop still rewrote the head branch"

scenario "a host named path cannot collide with the local-path marker"
land_setup behind; land_fixtures
jq '.url = "https://path/owner/name/pull/83"' \
  "$FIX/pr-full.json" > "$FIX/pr-full.new"
mv "$FIX/pr-full.new" "$FIX/pr-full.json"
G "$WORK" remote add colliding https://path/owner/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --head-remote missing --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-unresolved'
want_land_untouched "the stop still rewrote the head branch"

scenario "a bracketed IPv6 SCP host keeps its forge repository tail"
land_setup behind; land_fixtures
jq '.url = "https://[2001:db8::1]/owner/name/pull/83"' \
  "$FIX/pr-full.json" > "$FIX/pr-full.new"
mv "$FIX/pr-full.new" "$FIX/pr-full.json"
G "$WORK" remote add ipv6 'git@[2001:db8::1]:prefix/owner/name.git'
run_sm land --pr 83 --repo owner/name --interval 1 --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-unresolved'
want_land_untouched "the stop still rewrote the head branch"

scenario "two ports on one host are two endpoints"
land_setup behind; land_fixtures
G "$WORK" remote add split https://github.invalid:8443/owner/name.git
git -C "$WORK" remote set-url --push split https://github.invalid:9443/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "userinfo does not truncate the host at its colon"
land_setup behind; land_fixtures
G "$WORK" remote add auth https://u:p@github.invalid/owner/name.git
git -C "$WORK" remote set-url --push auth https://github.invalid/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote auth --head "$FEAT_OID"
want_rc 2
want_out 'STOP lease-failed'   # identities agree; the push reaches the dead host next
want_land_untouched "the refused push did not restore the local branch"

scenario "a file:// URL and its plain path are one identity"
land_setup behind; land_fixtures
git -C "$WORK" remote set-url --push origin "file://$BARE" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebased'
want_land_pushed

scenario "file://localhost and its absolute path are one identity"
land_setup behind; land_fixtures
git -C "$WORK" remote set-url --push origin "file://LOCALHOST$BARE" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebased'
want_land_pushed

scenario "an uppercase FILE scheme is not Git's file transport"
land_setup behind; land_fixtures
git -C "$WORK" remote set-url --push origin "FILE://localhost$BARE" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "an uppercase FILE helper cannot collide with a hosted transport"
land_setup behind; land_fixtures
G "$WORK" remote add split FILE://github.invalid/prefix/owner/name.git
git -C "$WORK" remote set-url --push split https://github.invalid/prefix/owner/name.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a file URL preserves local path case"
land_setup behind; land_fixtures
G "$WORK" remote add split "file://$SCEN/A/repo.git"
git -C "$WORK" remote set-url --push split "$SCEN/a/repo.git" >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a file URL preserves a doubled leading slash"
land_setup behind; land_fixtures
DOUBLE_BARE="/$BARE"
git -C "$WORK" remote set-url origin "$DOUBLE_BARE" >/dev/null 2>&1
git -C "$WORK" remote set-url --push origin "file://$DOUBLE_BARE" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP rebased'
want_land_pushed

scenario "a doubled file path does not collapse to one leading slash"
land_setup behind; land_fixtures
DOUBLE_BARE="/$BARE"
git -C "$WORK" remote set-url --push origin "file://$DOUBLE_BARE" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "file://localhost cannot collide with a relative path"
land_setup behind; land_fixtures
git -C "$WORK" remote set-url origin "file://localhost$BARE" >/dev/null 2>&1
git -C "$WORK" remote set-url --push origin "localhost$BARE" >/dev/null 2>&1
run_sm "${LAND[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a non-local file authority cannot collide with a relative path"
land_setup behind; land_fixtures
G "$WORK" remote add split "file://server$BARE"
git -C "$WORK" remote set-url --push split "server$BARE" >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "two non-local file authorities stay distinct"
land_setup behind; land_fixtures
G "$WORK" remote add split "file://a$BARE"
git -C "$WORK" remote set-url --push split "file://b$BARE" >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "an authority-only file URL is not a relative path"
land_setup behind; land_fixtures
G "$WORK" remote add split file://rel.git
git -C "$WORK" remote set-url --push split rel.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a file URL with dot authority is not dot-relative"
land_setup behind; land_fixtures
G "$WORK" remote add split file://./rel.git
git -C "$WORK" remote set-url --push split ./rel.git >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a non-double-slash file form is not an absolute path"
land_setup behind; land_fixtures
G "$WORK" remote add split "file:$BARE"
git -C "$WORK" remote set-url --push split "$BARE" >/dev/null 2>&1
run_sm land --pr 83 --repo owner/name --interval 1 --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the stop still rewrote the head branch"

scenario "a same-tail remote on another host never auto-resolves"
land_setup behind; land_fixtures
G "$WORK" remote add mirror https://gitlab.invalid/owner/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-unresolved'
want_land_untouched "the stop still rewrote the head branch"

scenario "a host-and-tail match is chosen and acted on"
land_setup behind; land_fixtures
G "$WORK" remote add forge https://github.invalid/owner/name.git
run_sm land --pr 83 --repo owner/name --interval 1 --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED base-fetch'   # resolution succeeded; the base fetch reaches the dead host first
want_land_untouched "the remote head was pushed before the selected base remote failed"

# ---- SSH host alias on the land push ----
# A local ~/.ssh/config Host alias (label bnw.github.invalid, HostName
# github.invalid) names the forge's real endpoint. One ssh shim serves the
# alias both for `ssh -G` identity resolution and for the git transport that
# land's lease push rewrites the head over, so the destructive path runs end
# to end. ALIAS_GHOST/GUSER/
# GPORT perturb the resolved endpoint; ALIAS_SERVE is the verified bare repo.
# When ALIAS_SERVE_ROGUE is set, an unpinned transport (HostName not pinned to
# ALIAS_EXPECT_HOST) is routed there instead. The `-G` target is the last
# argument; when it names a user (`user@host`) the shim can resolve differently
# via ALIAS_GHOST_U/GUSER_U/GPORT_U, mirroring a user-dependent ssh config
# (`Match user`, `%r`) so a case can prove the guard resolves the same user@host
# Git connects through, not a bare host.
install_ssh_shim() {
  cat >"$SHIMD/ssh" <<'SSH'
#!/usr/bin/env bash
for a in "$@"; do
  [ "$a" = -G ] && {
    case "${!#}" in
      *@*) printf 'hostname %s\nuser %s\nport %s\n' \
             "${ALIAS_GHOST_U:-${ALIAS_GHOST:-github.invalid}}" \
             "${ALIAS_GUSER_U:-${ALIAS_GUSER:-git}}" \
             "${ALIAS_GPORT_U:-${ALIAS_GPORT:-22}}" ;;
      *) printf 'hostname %s\nuser %s\nport %s\n' \
           "${ALIAS_GHOST:-github.invalid}" \
           "${ALIAS_GUSER:-git}" "${ALIAS_GPORT:-22}" ;;
    esac
    [ "${ALIAS_GFAIL_AFTER:-}" != 1 ] || exit 1
    exit 0
  }
done
host=""
for a in "$@"; do
  case "$a" in HostName=*) host="${a#HostName=}" ;; esac
done
serve="$ALIAS_SERVE"
if [ -n "${ALIAS_SERVE_ROGUE:-}" ] \
    && [ "$host" != "${ALIAS_EXPECT_HOST:-github.invalid}" ]; then
  serve="$ALIAS_SERVE_ROGUE"
fi
[ -z "${ALIAS_TRANSPORT_LOG:-}" ] || printf '%s\n' "$*" >>"$ALIAS_TRANSPORT_LOG"
cmd="${!#}"; verb="${cmd%% *}"
exec "$verb" "$serve"
SSH
  chmod +x "$SHIMD/ssh"
}
install_ssh_shim

scenario "ssh alias to a different repository still stops"
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/other.git'
export ALIAS_SERVE="$BARE"
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the aliased mismatch stop still rewrote the head branch"

scenario "ssh alias on a non-default port still stops"
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" ALIAS_GPORT=2222
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_GPORT
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the aliased mismatch stop still rewrote the head branch"

scenario "ssh alias resolver failure after plausible output still stops"
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" ALIAS_GFAIL_AFTER=1
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_GFAIL_AFTER
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the aliased mismatch stop still rewrote the head branch"

scenario "ssh alias with an unsafe resolved user still stops"
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" ALIAS_GUSER_U='git;rogue'
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_GUSER_U
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the aliased mismatch stop still rewrote the head branch"

# A user-dependent ssh config: the bare host resolves to the forge, but the
# user-qualified git@host Git actually connects through resolves elsewhere. The
# guard must resolve the same user@host Git uses; resolving the bare host would
# bless the forge yet push via the other endpoint. Discriminating: neutering
# the user pass (querying only the bare host) resolves the forge and pushes.
scenario "ssh alias diverging by remote user still stops"
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" ALIAS_GHOST_U=rogue.github.invalid
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_GHOST_U
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the aliased mismatch stop still rewrote the head branch"

# Git honors an ssh-command override (GIT_SSH_COMMAND, core.sshCommand, GIT_SSH)
# for the transport, but the guard queries the plain ssh on PATH, so the offline
# resolution need not reflect the endpoint Git reaches. The guard fails closed
# whenever an override is active. Discriminating: without the fail-closed the
# alias resolves to the forge (via the shim) and the branch is rewritten through
# the unverified endpoint.
scenario "ssh alias under GIT_SSH_COMMAND override still stops"
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" GIT_SSH_COMMAND='ssh -F /dev/null'
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE GIT_SSH_COMMAND
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the aliased mismatch stop still rewrote the head branch"

scenario "ssh alias under core.sshCommand override still stops"
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
G "$WORK" config core.sshCommand 'ssh -F /dev/null'
export ALIAS_SERVE="$BARE"
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the aliased mismatch stop still rewrote the head branch"

scenario "ssh alias under GIT_SSH override still stops"
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" GIT_SSH="$SHIMD/ssh"
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE GIT_SSH
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_land_untouched "the aliased mismatch stop still rewrote the head branch"

scenario "ssh host alias auto-resolves as the base and head remote"
# origin is a hostless path remote, so it never auto-resolves; the alias is
# the only candidate, and resolve_remote must see through it for both the
# base fetch and the lease push.
land_setup behind; land_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE"
run_sm land --pr 83 --repo owner/name --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE
want_rc 2
want_out 'STOP rebased'
want_land_pushed

scenario "ssh alias land push pins the verified endpoint"
land_setup behind; land_fixtures
ROGUE="$SCEN/rogue.git"
git clone -q --bare "$BARE" "$ROGUE"
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
ALIAS_TRANSPORT_LOG="$FIX/alias-transport.log"
: >"$ALIAS_TRANSPORT_LOG"
export ALIAS_SERVE="$BARE" ALIAS_SERVE_ROGUE="$ROGUE" ALIAS_TRANSPORT_LOG
# Discriminate the pin: the same lease push without HostName pinning routes
# to the rogue mirror and rewrites its copy.
if PATH="$SHIMD:$PATH" git -C "$WORK" push --quiet \
    --force-with-lease="refs/heads/$HB:$FEAT_OID" -- \
    'git@bnw.github.invalid:owner/name.git' "refs/heads/$BB:refs/heads/$HB" >/dev/null 2>&1; then
  ok
else
  bad "the unpinned counter-run did not push to the rogue repository"
fi
if [ "$(git -C "$ROGUE" rev-parse "refs/heads/$HB")" = "$FEAT_OID" ]; then
  bad "the unpinned counter-run left the rogue head in place"
else ok; fi
git -C "$BARE" push -q -f "$ROGUE" "refs/heads/$HB:refs/heads/$HB"
: >"$ALIAS_TRANSPORT_LOG"
run_sm land --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --interval 1 --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_SERVE_ROGUE ALIAS_TRANSPORT_LOG
want_rc 2
want_out 'STOP rebased'
want_land_pushed
if [ "$(git -C "$ROGUE" rev-parse "refs/heads/$HB")" = "$FEAT_OID" ]; then
  ok
else bad "the pinned push reached the rogue mirror"; fi
if awk '
    index($0, "HostName=github.invalid") && index($0, "User=git") &&
    index($0, "Port=22") && index($0, "CanonicalizeHostname=no") &&
    index($0, "bnw.github.invalid") { pinned++ }
    END { exit !(pinned == 1) }
  ' "$FIX/alias-transport.log"; then
  ok
else
  bad "the land push did not pin the endpoint through the alias: $(paste -sd ';' "$FIX/alias-transport.log")"
fi

rm -f "$SHIMD/ssh"

# ---- handoff to merge-cleanup ----
# After `merge`, the land-approved-prs skill hands the merged PR to merge-cleanup.
# std_setup already leaves the scratch forge in the state merge-cleanup
# requires (a real merge commit on the bare's base, the work clone's base at
# the pre-merge tip), so one scenario runs both scripts in sequence against
# their own gh shims. The second shim mirrors scripts/test-merge-cleanup.sh's
# routing so merge-cleanup.sh's own --jq filters run against the fixtures.

MC_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/skills/merge-cleanup/merge-cleanup.sh"
if ! [ -f "$MC_SCRIPT" ]; then
  skip=$((skip + 1))
  echo "SKIP: handoff case needs $MC_SCRIPT" >&2
else
MCSHIM="$TMP/mc-shim"; MCFIX="$TMP/mc-fix"
mkdir -p "$MCSHIM" "$MCFIX"
{
  echo '#!/bin/bash'
  echo "FIX=\"$MCFIX\""
  cat <<'MCEOF'
echo "$*" >> "$FIX/calls.log"
sub="" verb="" api="" json="" jqf="" head=false base=false slurp=false prev=""
for arg in "$@"; do
  case "$prev" in --json) json="$arg" ;; --jq) jqf="$arg" ;; esac
  case "$arg" in
    pr|api) [ -n "$sub" ] || sub="$arg" ;;
    view|list|edit) [ "$sub" != pr ] || [ -n "$verb" ] || verb="$arg" ;;
    graphql|repos/*) api="$arg" ;;
    --json=*) json="${arg#--json=}" ;;
    --jq=*) jqf="${arg#--jq=}" ;;
    --head=*) head=true ;;
    --base=*) base=true ;;
    --slurp) slurp=true ;;
  esac
  prev="$arg"
done
fixture=""
if [ "$sub" = api ]; then
  case "$api" in
    graphql) fixture="$FIX/associated.json" ;;
    *"/pulls?"*"head="*) fixture="$FIX/shared.json" ;;
    *"/pulls?"*"base="*) fixture="$FIX/stacked.json" ;;
    repos/*)
      case "$jqf" in *default_branch*) fixture="$FIX/repo-base.json" ;; *)
        fixture="$FIX/repo-head.json" ;; esac ;;
  esac
elif [ "$sub" = pr ] && [ "$verb" = view ]; then
  case "$json" in *headRefName*) fixture="$FIX/pr.json" ;; *)
    fixture="$FIX/stacked-view.json" ;; esac
elif [ "$sub" = pr ] && [ "$verb" = list ]; then
  [ "$head" = false ] || fixture="$FIX/shared.json"
  [ "$base" = false ] || fixture="$FIX/stacked.json"
elif [ "$sub" = pr ] && [ "$verb" = edit ]; then
  exit 0
fi
[ -n "$fixture" ] && [ -f "$fixture" ] || exit 1
if [ -n "$jqf" ]; then
  [ "$slurp" = false ] && exec jq -r "$jqf" "$fixture"
  exec jq -s -r "$jqf" "$fixture"
fi
[ "$slurp" = false ] || exec jq -s '.' "$fixture"
exec cat "$fixture"
MCEOF
} > "$MCSHIM/gh"
chmod +x "$MCSHIM/gh"

scenario "merge-cleanup tidies the PR land.sh just merged"
std_setup; std_fixtures
printf '{"title":"Fix the thing"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 0
want_out 'OK merge {"merged_at":'
# merge-cleanup reads the merged head from the forge, not from OK merge.
jq -n --arg b "$HB" --arg o "$FEAT_OID" \
  '{state:"MERGED",mergedAt:"2026-07-25T12:00:00Z",headRefName:$b,
    baseRefName:"main",headRefOid:$o,isCrossRepository:false,
    headRepositoryOwner:{login:"owner"},headRepository:{name:"name"},
    url:"https://github.invalid/owner/name/pull/83",
    closingIssuesReferences:[]}' > "$MCFIX/pr.json"
jq -n '{default_branch:"main",fork:false,forks_count:0,
    delete_branch_on_merge:false,parent:null,source:null,
    clone_url:"https://github.invalid/owner/name.git",
    ssh_url:"git@github.invalid:owner/name.git",
    merge_commit_title:"PR_TITLE",merge_commit_message:"BLANK"}' \
  | tee "$MCFIX/repo-base.json" > "$MCFIX/repo-head.json"
printf '[]\n' > "$MCFIX/shared.json"
printf '[]\n' > "$MCFIX/stacked.json"
printf '{"baseRefName":"main"}\n' > "$MCFIX/stacked-view.json"
jq -n --arg oid "$FEAT_OID" \
  '{data:{repository:{object:{associatedPullRequests:{
    pageInfo:{hasNextPage:false,endCursor:"cursor"},
    nodes:[{number:83,state:"MERGED",headRefName:"feat",headRefOid:$oid,
      baseRepository:{nameWithOwner:"owner/name"},
      headRepository:{nameWithOwner:"owner/name"}}]}}}}}' \
  > "$MCFIX/associated.json"
OUT=$(cd "$WORK" && PATH="$MCSHIM:$PATH" bash "$MC_SCRIPT" \
  --repo github.invalid/owner/name --pr 83 --checkout "$WORK" \
  --base-remote origin --head-remote origin 2>"$FIX/stderr")
RC=$?
want_rc 0
want_out 'OK cleanup'
want_out '"remote_branch":"deleted"'
want_out '"base_resync":"resynced"'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  bad "the remote head survived merge-cleanup"
else ok; fi
if git -C "$WORK" show-ref --verify --quiet "refs/heads/$HB"; then
  bad "the local head survived merge-cleanup"
else ok; fi
[ "$(git -C "$WORK" symbolic-ref --short HEAD)" = "$BB" ] && ok || bad "HEAD left $BB"
[ "$(git -C "$WORK" rev-parse HEAD)" = "$(git -C "$BARE" rev-parse "refs/heads/$BB")" ] \
  && ok || bad "local $BB was not resynced to the merged base"
fi

fi

note=""
[ "$skip" -eq 0 ] || note=", $skip skipped (see SKIP above)"
echo "land matrix: $pass passed, $fail failed$note"
[ "$fail" -eq 0 ]
