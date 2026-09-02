#!/usr/bin/env bash
# Regression matrix for the self-merge script. Offline and deterministic:
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
# Set SELF_MERGE_SCRIPT to test a different copy of the script.
set -u

SCRIPT="${SELF_MERGE_SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/skills/self-merge/self-merge.sh}"
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
t 4 "valid cleanup reaches the forge read" cleanup --pr 83 --repo owner/name --head "$OID"
t 4 "uppercase head normalized" merge --pr 83 --repo owner/name --head "$(printf '%s' "$OID" | tr 'a-f' 'A-F')"

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
t 64 "cleanup without head" cleanup --pr 83 --repo owner/name
t 64 "head abbreviated" merge --pr 83 --repo owner/name --head 0123456
t 64 "head non-hex" merge --pr 83 --repo owner/name --head zz23456789abcdef0123456789abcdef01234567
t 64 "interval zero" check --pr 83 --repo owner/name --interval 0
t 64 "interval leading zeros" check --pr 83 --repo owner/name --interval 08
t 64 "interval beyond arithmetic bound" check --pr 83 --repo owner/name --interval 1000000000
t 64 "cap non-numeric" check --pr 83 --repo owner/name --cap-minutes xyz
t 64 "cap leading zeros" check --pr 83 --repo owner/name --cap-minutes 08
t 64 "cap beyond arithmetic bound" check --pr 83 --repo owner/name --cap-minutes 10000000
t 64 "base-remote leading hyphen" cleanup --pr 83 --repo owner/name --head "$OID" --base-remote --upload-pack=/x
t 64 "head-remote leading hyphen" cleanup --pr 83 --repo owner/name --head "$OID" --head-remote -r

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
    *headRefName*) fixture="$FIX/pr-full.json" ;;
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
[ -n "$fixture" ] && [ -f "$fixture" ] || exit 1
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
    "$FIX"/repo-read-once "$FIX"/rules-page2-fail
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
want_call() {
  if grep -qF -- "$1" "$FIX/calls.log" 2>/dev/null; then ok; else
    bad "no gh call contained '$1' (log: $(cat "$FIX/calls.log" 2>/dev/null | tr '\n' ';'))"
  fi
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
CLEAN=(cleanup --pr 83 --repo owner/name --base-remote origin --head-remote origin)

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

scenario "an open PR stacked on the branch stops check"
std_setup; std_fixtures
echo '[{"number":91}]' > "$FIX/stacked.json"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP stacked-prs'

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

scenario "duplicate base worktrees stop before cleanup"
std_setup; std_fixtures
G "$WORK" worktree add --force "$SCEN/basewt" "$BB"
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP duplicate-worktree'

scenario "duplicate head worktrees stop before cleanup"
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

# ---- merge phase ----

scenario "merge pins the head, passes a title-only message, and waits for MERGED"
std_setup; std_fixtures
printf '{"title":"Fix the thing"}' > "$FIX/title.json"
run_sm merge --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 0
want_out 'OK merge'
want_call "--match-head-commit=$FEAT_OID"
want_call "--subject=Fix the thing (#83)"

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

# ---- cleanup phase ----

scenario "same-repo cleanup deletes remote, resyncs, and keeps local branch"
std_setup; std_fixtures
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"deleted"'
want_out '"local_branch":"kept_manual"'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  bad "remote branch survived the lease delete"
else ok; fi
if git -C "$WORK" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the local branch was deleted automatically"; fi
if [ "$(git -C "$WORK" symbolic-ref -q HEAD)" = "refs/heads/$BB" ] \
   && [ "$(git -C "$WORK" rev-parse HEAD)" = "$(git -C "$BARE" rev-parse "refs/heads/$BB")" ]; then
  ok
else bad "work checkout did not land on the resynced base"; fi

# Discriminating against the old delete-first sequence: the remote exists while
# the feature branch is checked out and disappears from effective config on the
# base. The old sequence deleted the head, switched, then failed its base fetch.
scenario "a branch-conditioned base remote that disappears stops before delete"
std_setup; std_fixtures
G "$WORK" checkout "$HB"
INC="$SCEN/feature-remote.cfg"
G "$WORK" config --unset-all remote.origin.url
G "$WORK" config --add "includeIf.onbranch:$HB.path" "$INC"
git config --file "$INC" remote.origin.url "$BARE"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED base-remote'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote head was deleted before the post-landing remote stop"; fi

# Discriminating against carrying a remote name across checkout. The include is
# split across two mutually exclusive includes, so feature resolves origin to
# the real repository while main resolves it to a different, valid local
# repository whose main is a descendant. Without the identity pin, fetch and
# fast-forward both succeed against the wrong repository.
scenario "a branch-conditioned base remote cannot redirect the resync"
std_setup; std_fixtures
WRONG_BARE="$SCEN/wrong.git"
WRONG_WORK="$SCEN/wrong-work"
git clone -q --bare "$BARE" "$WRONG_BARE"
git clone -q "$WRONG_BARE" "$WRONG_WORK"
G "$WRONG_WORK" config user.email t@t; G "$WRONG_WORK" config user.name t
G "$WRONG_WORK" checkout "$BB"
echo wrong > "$WRONG_WORK/wrong.txt"; G "$WRONG_WORK" add .; G "$WRONG_WORK" commit -m wrong
G "$WRONG_WORK" push origin "$BB"
WRONG_OID=$(git -C "$WRONG_WORK" rev-parse HEAD)
G "$WORK" checkout "$HB"
INC="$SCEN/feature-remote.cfg"; MAIN_INC="$SCEN/base-remote.cfg"
G "$WORK" config --unset-all remote.origin.url
G "$WORK" config --add "includeIf.onbranch:$HB.path" "$INC"
G "$WORK" config --add "includeIf.onbranch:$BB.path" "$MAIN_INC"
git config --file "$INC" remote.origin.url "$BARE"
git config --file "$MAIN_INC" remote.origin.url "$WRONG_BARE"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-config-changed'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote head was deleted after the base remote redirected"; fi
if [ "$(git -C "$WORK" rev-parse HEAD)" != "$WRONG_OID" ]; then
  ok
else bad "the base fast-forwarded from the wrong repository"; fi

# A missing local base is created from the remote selected while the feature
# branch is checked out. The checkout must not retain that pre-landing remote
# as its upstream when base-conditioned configuration resolves the same
# repository through another remote after landing.
scenario "a created base tracks the post-landing remote"
std_setup; std_fixtures
G "$WORK" checkout "$HB"
G "$WORK" branch -D "$BB"
MAIN_INC="$SCEN/base-remote.cfg"
G "$WORK" remote add base "$BARE"
G "$WORK" config --add "includeIf.onbranch:$BB.path" "$MAIN_INC"
git config --file "$MAIN_INC" remote.origin.pushurl \
  https://github.invalid/other/name.git
GIT_REAL=$(command -v git)
GIT_SHIM="$SCEN/git-shim"
mkdir "$GIT_SHIM"
printf '#!/bin/sh\nif [ "$1" = remote ] && [ "$2" = get-url ]; then\n  out=$("%s" "$@") || exit\n  if [ "$out" = "%s" ]; then\n    out=https://github.invalid/owner/name.git\n  fi\n  printf "%%s\\n" "$out"\n  exit 0\nfi\nexec "%s" "$@"\n' \
  "$GIT_REAL" "$BARE" "$GIT_REAL" > "$GIT_SHIM/git"
chmod +x "$GIT_SHIM/git"
run_sm_with_git_shim "$GIT_SHIM" cleanup --pr 83 --repo owner/name \
  --head "$FEAT_OID"
want_rc 0
if [ "$(git -C "$WORK" config --get "branch.$BB.remote")" = base ] \
   && [ "$(git -C "$WORK" config --get "branch.$BB.merge")" = "refs/heads/$BB" ]; then
  ok
else bad "the created base did not track the post-landing remote"; fi

# Refute the asymmetric identity check: validating only a new hosted URL would
# still accept a checkout that replaces a forge-verified hosted remote with an
# arbitrary hostless path. The path is valid and fast-forwardable, so equality
# with the pre-checkout identity is the only available guard.
scenario "a hosted base remote cannot become an untrusted hostless path"
std_setup; std_fixtures
WRONG_BARE="$SCEN/wrong.git"
WRONG_WORK="$SCEN/wrong-work"
git clone -q --bare "$BARE" "$WRONG_BARE"
git clone -q "$WRONG_BARE" "$WRONG_WORK"
G "$WRONG_WORK" config user.email t@t; G "$WRONG_WORK" config user.name t
G "$WRONG_WORK" checkout "$BB"
echo wrong > "$WRONG_WORK/wrong.txt"; G "$WRONG_WORK" add .; G "$WRONG_WORK" commit -m wrong
G "$WRONG_WORK" push origin "$BB"
WRONG_OID=$(git -C "$WRONG_WORK" rev-parse HEAD)
G "$WORK" checkout "$HB"
INC="$SCEN/feature-remote.cfg"; MAIN_INC="$SCEN/base-remote.cfg"
G "$WORK" config --unset-all remote.origin.url
G "$WORK" config --add "includeIf.onbranch:$HB.path" "$INC"
G "$WORK" config --add "includeIf.onbranch:$BB.path" "$MAIN_INC"
git config --file "$INC" remote.origin.url https://github.invalid/owner/name.git
git config --file "$MAIN_INC" remote.origin.url "$WRONG_BARE"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-config-changed'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote head was deleted after the hosted remote became local"; fi
if [ "$(git -C "$WORK" rev-parse HEAD)" != "$WRONG_OID" ]; then
  ok
else bad "the base trusted a hostless replacement after checkout"; fi

scenario "a checkout-switched symlink cannot redirect head deletion"
std_setup; std_fixtures
WRONG_BARE="$SCEN/wrong.git"
G "$WORK" checkout "$HB"
ln -s "$BARE" "$WORK/remote.git"
G "$WORK" add remote.git; G "$WORK" commit -m feature-link
G "$WORK" push origin "$HB"
FEAT_OID=$(git -C "$WORK" rev-parse HEAD)
G "$MRG" fetch origin
G "$MRG" checkout "$BB"
G "$MRG" merge --no-ff -m redirected-head "origin/$HB"
rm "$MRG/remote.git"
ln -s "$WRONG_BARE" "$MRG/remote.git"
G "$MRG" add remote.git; G "$MRG" commit -m base-link
G "$MRG" push origin "$BB"
git clone -q --bare "$BARE" "$WRONG_BARE"
pr_full OPEN "$HB" "$BB" "$FEAT_OID" false owner name
G "$WORK" remote add base "$BARE"
G "$WORK" config remote.origin.url ./remote.git
mkdir "$WORK/subdir"
OUT=$(cd "$WORK/subdir" && PATH="$SHIMD:$PATH" bash "$SCRIPT" cleanup \
  --pr 83 --repo owner/name --base-remote base --head-remote origin \
  --head "$FEAT_OID" 2>"$FIX/stderr")
RC=$?
want_rc 2
want_out 'STOP remote-config-changed'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the trusted repository lost its head branch"; fi
if git -C "$WRONG_BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the symlink replacement lost its head branch"; fi

scenario "a Git-expanded tilde symlink cannot redirect head deletion"
std_setup; std_fixtures
WRONG_BARE="$SCEN/wrong.git"
G "$WORK" checkout "$HB"
ln -s "$BARE" "$WORK/remote.git"
G "$WORK" add remote.git; G "$WORK" commit -m feature-link
G "$WORK" push origin "$HB"
FEAT_OID=$(git -C "$WORK" rev-parse HEAD)
G "$MRG" fetch origin
G "$MRG" checkout "$BB"
G "$MRG" merge --no-ff -m redirected-head "origin/$HB"
rm "$MRG/remote.git"
ln -s "$WRONG_BARE" "$MRG/remote.git"
G "$MRG" add remote.git; G "$MRG" commit -m base-link
G "$MRG" push origin "$BB"
git clone -q --bare "$BARE" "$WRONG_BARE"
pr_full OPEN "$HB" "$BB" "$FEAT_OID" false owner name
G "$WORK" remote add base "$BARE"
G "$WORK" config remote.origin.url '~/remote.git'
mkdir "$WORK/subdir"
OUT=$(cd "$WORK/subdir" && HOME="$WORK" PATH="$SHIMD:$PATH" \
  bash "$SCRIPT" cleanup --pr 83 --repo owner/name \
  --base-remote base --head-remote origin --head "$FEAT_OID" 2>"$FIX/stderr")
RC=$?
want_rc 2
want_out 'STOP remote-config-changed'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the tilde path's trusted repository lost its head branch"; fi
if git -C "$WRONG_BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the tilde path's symlink replacement lost its head branch"; fi

scenario "a branch-conditioned head remote is revalidated after resync"
std_setup; std_fixtures
WRONG_BARE="$SCEN/wrong.git"
git clone -q --bare "$BARE" "$WRONG_BARE"
G "$WORK" remote add base "$BARE"
G "$WORK" checkout "$HB"
INC="$SCEN/feature-head.cfg"; MAIN_INC="$SCEN/base-head.cfg"
G "$WORK" config --add "includeIf.onbranch:$HB.path" "$INC"
G "$WORK" config --add "includeIf.onbranch:$BB.path" "$MAIN_INC"
git config --file "$INC" remote.head.url "$BARE"
git config --file "$MAIN_INC" remote.head.url "$WRONG_BARE"
run_sm cleanup --pr 83 --repo owner/name --base-remote base --head-remote head --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-config-changed'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the changed head remote deleted the original branch"; fi
if [ "$(git -C "$WORK" rev-parse HEAD)" = "$(git -C "$BARE" rev-parse "refs/heads/$BB")" ]; then
  ok
else bad "the head-remote stop happened before the base resync"; fi

scenario "a local branch created during cleanup reports kept_manual"
std_setup; std_fixtures
G "$WORK" update-ref -d "refs/heads/$HB"
HOOK="$WORK/.git/hooks/post-merge"
printf '#!/bin/sh\ngit update-ref "%s" "%s"\n' "refs/heads/$HB" "$FEAT_OID" > "$HOOK"
chmod +x "$HOOK"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"local_branch":"kept_manual"'
if git -C "$WORK" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the branch created during cleanup did not survive"; fi

scenario "a final prune failure cannot report cleanup complete"
std_setup; std_fixtures
G "$WORK" config --add remote.origin.fetch not-a-refspec
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED prune'

scenario "cleanup refuses while the forge says the PR is unmerged"
std_setup; std_fixtures
printf '{"state":"OPEN","mergedAt":null}' > "$FIX/pr-state.json"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pr-not-merged'

scenario "an auto-deleted remote branch reads as already gone"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"already"'

scenario "an unreachable head remote is unknown, never auto-deleted"
std_setup; std_fixtures
G "$WORK" remote add dead "$SCEN/nonexistent.git"
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote dead --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED ls-remote'

scenario "a decoy refs/heads/refs/heads ref is not the head branch"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
git -C "$BARE" update-ref "refs/heads/refs/heads/$HB" "$FEAT_OID"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"already"'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/refs/heads/$HB"; then
  ok
else bad "the decoy ref was deleted"; fi

scenario "a suffix-matching decoy makes the delete inexpressible: stop"
std_setup; std_fixtures
git -C "$BARE" update-ref "refs/heads/refs/heads/$HB" "$FEAT_OID"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP ambiguous-ref'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB" \
   && git -C "$BARE" show-ref --verify --quiet "refs/heads/refs/heads/$HB"; then
  ok
else bad "a ref was deleted despite the ambiguity"; fi

scenario "a moved remote branch stops on the OID guard"
std_setup; std_fixtures
G "$SRC" checkout "$HB"
echo later > "$SRC/later.txt"; G "$SRC" add .; G "$SRC" commit -m later
G "$SRC" push origin "refs/heads/$HB"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP oid-mismatch'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the moved branch was deleted anyway"; fi

scenario "consumers are re-checked at delete time"
std_setup; std_fixtures
echo '[{"number":90}]' > "$FIX/shared.json"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP shared-head'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "a shared head was deleted"; fi

scenario "a symbolic local base stops before remote deletion"
std_setup; std_fixtures
G "$WORK" branch base-target "refs/heads/$BB"
git -C "$WORK" symbolic-ref "refs/heads/$BB" refs/heads/base-target
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP local-base'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote head was deleted before the symbolic-base stop"; fi

scenario "a same-named tag cannot detach the landing"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
G "$WORK" tag "$BB" "$FEAT_OID"      # tag shadowing the base name
G "$WORK" checkout "$HB"
G "$WORK" branch -D "$BB"            # no local base: the create path runs
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
if [ "$(git -C "$WORK" symbolic-ref -q HEAD)" = "refs/heads/$BB" ]; then
  ok
else bad "HEAD detached at the shadowing tag"; fi

scenario "an ignored file the base tracks aborts the switch intact"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
G "$MRG" checkout "$BB"
echo remote-secret > "$MRG/.env"; G "$MRG" add -f .env
G "$MRG" commit -m env; G "$MRG" push origin "$BB"
G "$WORK" checkout "$HB"   # move off the base so the fetch below can update it
G "$WORK" fetch origin "refs/heads/$BB:refs/heads/$BB"  # local base now tracks .env
echo .env > "$WORK/.git/info/exclude"
echo local-secret > "$WORK/.env"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP checkout-refused'
if [ "$(cat "$WORK/.env")" = local-secret ]; then ok; else bad ".env was clobbered"; fi

scenario "an ignored file the resync starts tracking aborts the fast-forward intact"
std_setup; std_fixtures
G "$MRG" checkout "$BB"
echo remote-secret > "$MRG/.env"; G "$MRG" add -f .env
G "$MRG" commit -m env; G "$MRG" push origin "$BB"
echo .env > "$WORK/.git/info/exclude"
echo local-secret > "$WORK/.env"   # local base still pre-merge: hazard hits the merge
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP resync-failed'
if [ "$(cat "$WORK/.env")" = local-secret ]; then ok; else bad ".env was clobbered"; fi
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote head was deleted before the refused resync"; fi

scenario "a diverged base refuses the fast-forward"
std_setup; std_fixtures
echo local > "$WORK/local.txt"; G "$WORK" add .; G "$WORK" commit -m local
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP resync-failed'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote head was deleted before the diverged-base stop"; fi

scenario "worktree preservation targets the right record despite hostile names"
std_setup 'x$(touch${IFS}probe-file)' main
std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
DECOY="$SCEN/decoy wt"
G "$WORK" branch decoy "$BB"
G "$WORK" worktree add "$DECOY" decoy
TARGET="$SCEN/wt with space"$'\f\n'
G "$WORK" worktree add "$TARGET" "$HB"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP head-worktree-present'
want_out 'wt with space\u000c\n remains'   # form feed and trailing newline, both escaped
if [ -e "$WORK/probe-file" ] || [ -e "$SCEN/probe-file" ]; then
  bad "the hostile branch name executed"
else ok; fi
if [ -d "$TARGET" ]; then ok; else bad "the head worktree was removed"; fi
if [ -d "$DECOY" ]; then ok; else bad "the decoy sibling worktree was removed"; fi

scenario "a worktree holding only an ignored file is not removed"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
echo .env > "$WORK/.git/info/exclude"
echo secret > "$WT/.env"
G "$WORK" config status.showUntrackedFiles no   # must not blind the inventory
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP worktree-dirty'
if [ -f "$WT/.env" ]; then ok; else bad "the ignored file was destroyed"; fi

scenario "a paused operation inside the head worktree blocks its removal"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
( cd "$WT" && git rev-parse HEAD > "$(git rev-parse --git-path MERGE_HEAD)" )
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP worktree-op-in-progress'
if [ -d "$WT" ]; then ok; else bad "a worktree with a paused merge was removed"; fi

scenario "a dangling marker inside the head worktree blocks its removal"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
ln -s missing "$(cd "$WT" && git rev-parse --git-path MERGE_HEAD)"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP worktree-op-in-progress'
if [ -d "$WT" ]; then ok; else bad "a worktree with a dangling operation marker was removed"; fi

scenario "an assume-unchanged edit blocks worktree removal"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
G "$WT" update-index --assume-unchanged feat.txt
echo edited > "$WT/feat.txt"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP worktree-flagged'
if [ "$(cat "$WT/feat.txt")" = edited ]; then ok; else bad "the flagged edit was destroyed"; fi

scenario "a sparse checkout's absent skip-worktree paths are not flagged state"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
G "$WT" sparse-checkout set --no-cone /base.txt   # leaves feat.txt `S`, absent
if [ -e "$WT/feat.txt" ]; then bad "the sparse fixture left the excluded path present"; fi
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
# The preservation stop, not worktree-flagged: a sparse checkout marks every
# excluded path `S` while leaving it absent, so nothing is there to lose.
want_out 'STOP head-worktree-present'

scenario "a sparse checkout spelled with a non-canonical boolean is still sparse"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
G "$WT" sparse-checkout set --no-cone /base.txt
G "$WT" config --worktree core.sparseCheckout yes   # `--get` returns yes, not true
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP head-worktree-present'

scenario "an assume-unchanged deletion blocks worktree removal"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
G "$WT" update-index --assume-unchanged feat.txt
rm "$WT/feat.txt"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
# An absent flagged path is a hidden deletion unless sparse checkout explains
# it; status reports neither the flag nor the missing file.
want_out 'STOP worktree-flagged'

scenario "a skip-worktree deletion outside a sparse checkout blocks removal"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
G "$WT" update-index --skip-worktree feat.txt
rm "$WT/feat.txt"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP worktree-flagged'

scenario "a present skip-worktree file still blocks worktree removal"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
G "$WT" update-index --skip-worktree feat.txt
echo edited > "$WT/feat.txt"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP worktree-flagged'
if [ "$(cat "$WT/feat.txt")" = edited ]; then ok; else bad "the flagged edit was destroyed"; fi

scenario "a newline-bearing remote URL cannot be validated: stop"
std_setup; std_fixtures
G "$WORK" remote add nlrem "$SCEN/x"$'\n'
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote nlrem --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "an unmerged branch stops before its worktree is removed"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
( cd "$WT" && echo repurposed > new.txt && git add . && git commit -qm repurposed )
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP local-branch'
if [ -d "$WT" ]; then ok; else bad "the repurposed worktree was removed before the containment stop"; fi

scenario "a branch repointed backward stops before its worktree is removed"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
G "$WT" reset --hard "$BASE_PRE"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP local-branch'
if [ -d "$WT" ]; then ok; else bad "the backward-repointed worktree was removed"; fi
if [ "$(git -C "$WORK" rev-parse "refs/heads/$HB")" = "$BASE_PRE" ]; then
  ok
else bad "the backward-repointed branch was deleted or moved"; fi

scenario "a symbolic local head ref stops before its target is deleted"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
G "$WORK" branch pinned-alias "$FEAT_OID"
G "$WORK" symbolic-ref "refs/heads/$HB" refs/heads/pinned-alias
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP local-branch'
if git -C "$WORK" show-ref --verify --quiet refs/heads/pinned-alias; then
  ok
else bad "the symbolic head ref's target was deleted"; fi
if [ "$(git -C "$WORK" symbolic-ref "refs/heads/$HB")" = refs/heads/pinned-alias ]; then
  ok
else bad "the symbolic head ref was changed"; fi

scenario "a dangling symbolic local head ref is not mistaken for absence"
std_setup; std_fixtures
G "$WORK" update-ref -d "refs/heads/$HB"
G "$WORK" symbolic-ref "refs/heads/$HB" refs/heads/missing
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP local-branch'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote branch was deleted after a dangling local symref bypass"; fi
if [ "$(git -C "$WORK" symbolic-ref "refs/heads/$HB")" = refs/heads/missing ]; then
  ok
else bad "the dangling symbolic head ref was changed"; fi

scenario "a direct ref becoming a dangling symref between probes stops"
std_setup; std_fixtures
GIT_REAL=$(command -v git)
GIT_SHIM="$SCEN/git-shim"
MARKER="$SCEN/swapped"
mkdir "$GIT_SHIM"
printf '#!/bin/sh\nif [ "$1" = symbolic-ref ] && [ "$2" = -q ] && [ "$3" = "%s" ] && [ ! -f "%s" ]; then\n  "%s" "$@"\n  rc=$?\n  "%s" -C "%s" update-ref -d "%s"\n  "%s" -C "%s" symbolic-ref "%s" refs/heads/missing\n  : > "%s"\n  exit "$rc"\nfi\nexec "%s" "$@"\n' \
  "refs/heads/$HB" "$MARKER" "$GIT_REAL" "$GIT_REAL" "$WORK" \
  "refs/heads/$HB" "$GIT_REAL" "$WORK" "refs/heads/$HB" "$MARKER" \
  "$GIT_REAL" > "$GIT_SHIM/git"
chmod +x "$GIT_SHIM/git"
run_sm_with_git_shim "$GIT_SHIM" "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP local-branch'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote branch was deleted after the ref-probe race"; fi
if [ "$(git -C "$WORK" symbolic-ref "refs/heads/$HB")" = refs/heads/missing ]; then
  ok
else bad "the raced dangling symbolic ref was changed"; fi

scenario "a clean head worktree stops before any branch mutation"
std_setup; std_fixtures
WT="$SCEN/featwt"
G "$WORK" worktree add "$WT" "$HB"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP head-worktree-present'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote branch was deleted before the worktree stop"; fi
if git -C "$WORK" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the local branch was deleted before the worktree stop"; fi
if [ -d "$WT" ]; then ok; else bad "the clean head worktree was removed"; fi

scenario "a multibyte worktree path reports as its UTF-8 bytes"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"
G "$WORK" worktree add "$SCEN/wté" "$HB"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP head-worktree-present'
want_out 'wt\u00c3\u00a9 remains'   # e-acute is C3 A9: code points equal the bytes

scenario "unmerged local work survives the auto-delete path"
std_setup; std_fixtures
G "$SRC" push origin --delete "refs/heads/$HB"   # forge auto-delete already ran
G "$WORK" checkout "$HB"
echo unmerged > "$WORK/unmerged.txt"; G "$WORK" add .; G "$WORK" commit -m unmerged
G "$WORK" checkout "$BB"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP local-branch'
if git -C "$WORK" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the unmerged branch was deleted"; fi

scenario "a branch in a fork-owned repository can head an upstream PR: stop"
std_setup; std_fixtures
repo_fx "$BB" upstream/name
echo '[{"number":83}]' > "$FIX/fork-shared.json"   # same number, other repo, still counts
run_sm "${CHECK[@]}"
want_rc 2
want_out 'STOP shared-head'

scenario "a fork-owned repository keeps its branch at cleanup"
std_setup; std_fixtures
repo_fx "$BB" upstream/name
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"kept_fork_network"'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "a fork-owned repository's branch was deleted"; fi

scenario "a root repository with forks keeps its branch at cleanup"
std_setup; std_fixtures
repo_fx "$BB" "" false 1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"kept_fork_network"'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "a fork-network root branch was deleted"; fi

scenario "a first fork appearing during cleanup keeps the branch"
std_setup; std_fixtures
repo_fx "$BB" "" false 0
jq '.forks_count = 1' "$FIX/repo.json" > "$FIX/repo-next.json"
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"kept_fork_network"'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "a branch was deleted after its repository gained a fork"; fi

scenario "a fork head is kept and reported, never deleted"
std_setup; std_fixtures
pr_full MERGED "$HB" "$BB" "$FEAT_OID" true forker name
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"kept_fork"'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "a fork-named branch was deleted from a remote"; fi

scenario "a split fetch/push remote identity stops before any check"
std_setup; std_fixtures
git -C "$WORK" remote set-url --push origin "$SCEN/other.git" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "a branch was deleted across a fetch/push split"; fi

scenario "a hosted head override must identify the PR repository"
std_setup; std_fixtures
G "$WORK" remote add wrong https://github.invalid/other/name.git
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote wrong --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a hosted base override must identify the PR repository"
std_setup; std_fixtures
G "$WORK" remote add wrong https://github.invalid/other/name.git
run_sm cleanup --pr 83 --repo owner/name --base-remote wrong --head-remote origin --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a hosted override with an extra path prefix is not the PR repository"
std_setup; std_fixtures
G "$WORK" remote add wrong https://github.invalid/prefix/owner/name.git
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote wrong --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a userless SCP override must identify the PR repository"
std_setup; std_fixtures
G "$WORK" remote add wrong github.invalid:other/name.git
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote wrong --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "different SSH users are different push destinations"
std_setup; std_fixtures
G "$WORK" remote add split git@github.invalid:owner/name.git
git -C "$WORK" remote set-url --push split deploy@github.invalid:owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "different ssh-scheme users are different push destinations"
std_setup; std_fixtures
jq '.ssh_url = "ssh://git@github.invalid/owner/name.git"' \
  "$FIX/repo.json" > "$FIX/repo.new"
mv "$FIX/repo.new" "$FIX/repo.json"
G "$WORK" remote add split ssh://git@github.invalid/owner/name.git
git -C "$WORK" remote set-url --push split ssh://deploy@github.invalid/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "HTTPS and userless SSH are different push destinations"
std_setup; std_fixtures
G "$WORK" remote add split https://github.invalid/owner/name.git
git -C "$WORK" remote set-url --push split ssh://github.invalid/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "HTTPS and git transport are different push destinations"
std_setup; std_fixtures
G "$WORK" remote add split https://github.invalid/owner/name.git
git -C "$WORK" remote set-url --push split git://github.invalid/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "SCP and ssh scheme are different push destinations"
std_setup; std_fixtures
G "$WORK" remote add split git@github.invalid:owner/name.git
git -C "$WORK" remote set-url --push split ssh://git@github.invalid/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "auto-resolution skips an origin with the wrong SSH user"
std_setup; std_fixtures
G "$WORK" remote set-url origin deploy@github.invalid:owner/name.git
G "$WORK" remote add forge git@github.invalid:owner/name.git
run_sm cleanup --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED base-fetch'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote head was deleted before the selected base remote failed"; fi

scenario "a second configured push URL still stops the split"
std_setup; std_fixtures
git -C "$WORK" remote set-url --push origin "$BARE" >/dev/null 2>&1
git -C "$WORK" remote set-url --push --add origin "$SCEN/other.git" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "a branch was deleted despite a broadcast push URL"; fi

scenario "duplicate effective push URLs stop before the lease delete"
std_setup; std_fixtures
git -C "$WORK" remote set-url --push origin "$BARE" >/dev/null 2>&1
git -C "$WORK" remote set-url --push --add origin "$BARE" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the first duplicate destination deleted the branch before the stop"; fi

scenario "a blank push URL stops before the valid destination is mutated"
std_setup; std_fixtures
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
run_sm_with_git_shim "$BLANK_PUSH_SHIM" "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the valid destination deleted the branch before the blank-URL stop"; fi

scenario "two local paths sharing a tail are two repositories"
std_setup; std_fixtures
G "$WORK" remote add split "$SCEN/a/owner/name"
git -C "$WORK" remote set-url --push split "$SCEN/b/owner/name" >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "two hosted paths sharing a tail are two repositories"
std_setup; std_fixtures
G "$WORK" remote add split https://github.invalid/a/owner/name.git
git -C "$WORK" remote set-url --push split https://github.invalid/b/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "hosted path case is part of the endpoint identity"
std_setup; std_fixtures
G "$WORK" remote add split https://github.invalid/A/owner/name.git
git -C "$WORK" remote set-url --push split https://github.invalid/a/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a hosted .git suffix is part of the endpoint identity"
std_setup; std_fixtures
G "$WORK" remote add split https://github.invalid/prefix/owner/name
git -C "$WORK" remote set-url --push split https://github.invalid/prefix/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a hosted path prefix does not hide its forge repository tail"
std_setup; std_fixtures
G "$WORK" remote add prefixed https://github.invalid/prefix/owner/name.git
run_sm cleanup --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-unresolved'

scenario "a host named path cannot collide with the local-path marker"
std_setup; std_fixtures
jq '.url = "https://path/owner/name/pull/83"' \
  "$FIX/pr-full.json" > "$FIX/pr-full.new"
mv "$FIX/pr-full.new" "$FIX/pr-full.json"
G "$WORK" remote add colliding https://path/owner/name.git
run_sm cleanup --pr 83 --repo owner/name --head-remote missing --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-unresolved'

scenario "a bracketed IPv6 SCP host keeps its forge repository tail"
std_setup; std_fixtures
jq '.url = "https://[2001:db8::1]/owner/name/pull/83"' \
  "$FIX/pr-full.json" > "$FIX/pr-full.new"
mv "$FIX/pr-full.new" "$FIX/pr-full.json"
G "$WORK" remote add ipv6 'git@[2001:db8::1]:prefix/owner/name.git'
run_sm cleanup --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-unresolved'

scenario "two ports on one host are two endpoints"
std_setup; std_fixtures
G "$WORK" remote add split https://github.invalid:8443/owner/name.git
git -C "$WORK" remote set-url --push split https://github.invalid:9443/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "userinfo does not truncate the host at its colon"
std_setup; std_fixtures
G "$WORK" remote add auth https://u:p@github.invalid/owner/name.git
git -C "$WORK" remote set-url --push auth https://github.invalid/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote auth --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED ls-remote'   # identities agree; the dead host is next

scenario "a file:// URL and its plain path are one identity"
std_setup; std_fixtures
git -C "$WORK" remote set-url --push origin "file://$BARE" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"deleted"'

scenario "file://localhost and its absolute path are one identity"
std_setup; std_fixtures
git -C "$WORK" remote set-url --push origin "file://LOCALHOST$BARE" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"deleted"'

scenario "an uppercase FILE scheme is not Git's file transport"
std_setup; std_fixtures
git -C "$WORK" remote set-url --push origin "FILE://localhost$BARE" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "an uppercase FILE helper cannot collide with a hosted transport"
std_setup; std_fixtures
G "$WORK" remote add split FILE://github.invalid/prefix/owner/name.git
git -C "$WORK" remote set-url --push split https://github.invalid/prefix/owner/name.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a file URL preserves local path case"
std_setup; std_fixtures
G "$WORK" remote add split "file://$SCEN/A/repo.git"
git -C "$WORK" remote set-url --push split "$SCEN/a/repo.git" >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "a file URL preserves a doubled leading slash"
std_setup; std_fixtures
DOUBLE_BARE="/$BARE"
git -C "$WORK" remote set-url origin "$DOUBLE_BARE" >/dev/null 2>&1
git -C "$WORK" remote set-url --push origin "file://$DOUBLE_BARE" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 0
want_out '"remote_branch":"deleted"'

scenario "a doubled file path does not collapse to one leading slash"
std_setup; std_fixtures
DOUBLE_BARE="/$BARE"
git -C "$WORK" remote set-url --push origin "file://$DOUBLE_BARE" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "file://localhost cannot collide with a relative path"
std_setup; std_fixtures
git -C "$WORK" remote set-url origin "file://localhost$BARE" >/dev/null 2>&1
git -C "$WORK" remote set-url --push origin "localhost$BARE" >/dev/null 2>&1
run_sm "${CLEAN[@]}" --head "$FEAT_OID"
want_rc 2
want_out 'STOP pushurl-mismatch'

scenario "a non-local file authority cannot collide with a relative path"
std_setup; std_fixtures
G "$WORK" remote add split "file://server$BARE"
git -C "$WORK" remote set-url --push split "server$BARE" >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "two non-local file authorities stay distinct"
std_setup; std_fixtures
G "$WORK" remote add split "file://a$BARE"
git -C "$WORK" remote set-url --push split "file://b$BARE" >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "an authority-only file URL is not a relative path"
std_setup; std_fixtures
G "$WORK" remote add split file://rel.git
git -C "$WORK" remote set-url --push split rel.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a file URL with dot authority is not dot-relative"
std_setup; std_fixtures
G "$WORK" remote add split file://./rel.git
git -C "$WORK" remote set-url --push split ./rel.git >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a non-double-slash file form is not an absolute path"
std_setup; std_fixtures
G "$WORK" remote add split "file:$BARE"
git -C "$WORK" remote set-url --push split "$BARE" >/dev/null 2>&1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin --head-remote split --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-repo-mismatch'

scenario "a same-tail remote on another host never auto-resolves"
std_setup; std_fixtures
G "$WORK" remote add mirror https://gitlab.invalid/owner/name.git
run_sm cleanup --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 2
want_out 'STOP remote-unresolved'

scenario "a host-and-tail match is chosen and acted on"
std_setup; std_fixtures
G "$WORK" remote add forge https://github.invalid/owner/name.git
run_sm cleanup --pr 83 --repo owner/name --head "$FEAT_OID"
want_rc 4
want_out 'LOOKUP_FAILED base-fetch'   # resolution succeeded; resync reaches the dead host first
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the remote head was deleted before the selected base remote failed"; fi

scenario "fork consumer lookups use the owner-qualified encoded form"
std_setup 'feat#2' main
pr_full OPEN 'feat#2' main "$FEAT_OID" true forker name
repo_fx main; rules_fx '[]'; lists_empty
run_sm "${CHECK[@]}"
want_rc 0
want_call 'pulls?state=open&head=forker:feat%232'

# ---- SSH host alias cleanup ----
# A local ~/.ssh/config Host alias (label bnw.github.invalid, HostName
# github.invalid) names the forge's real endpoint. One ssh shim serves the
# alias both for `ssh -G` identity resolution and for the git transport that
# deletes over it, so the destructive path runs end to end. ALIAS_GHOST/GUSER/
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
alias_head_gone() { # assert BARE lost the head branch
  if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
    bad "remote head survived the aliased delete"
  else ok; fi
}
alias_head_kept() { # assert BARE still holds the head branch
  if git -C "$BARE" show-ref --verify --quiet "refs/heads/$HB"; then
    ok
  else bad "the aliased mismatch stop still deleted the remote head"; fi
}

scenario "explicit ssh host alias resolves to the forge and deletes"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE"
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE
want_rc 0
want_out '"remote_branch":"deleted"'
alias_head_gone

scenario "ssh host alias auto-resolves as the base and head remote"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE"
run_sm cleanup --pr 83 --repo owner/name --head "$FEAT_OID"
unset ALIAS_SERVE
want_rc 0
want_out '"remote_branch":"deleted"'
alias_head_gone

scenario "ssh alias destructive transport pins the verified endpoint"
std_setup; std_fixtures
ROGUE="$SCEN/rogue.git"
git clone -q --bare "$BARE" "$ROGUE"
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
ALIAS_TRANSPORT_LOG="$FIX/alias-transport.log"
: >"$ALIAS_TRANSPORT_LOG"
export ALIAS_SERVE="$BARE" ALIAS_SERVE_ROGUE="$ROGUE" ALIAS_TRANSPORT_LOG
# Discriminate the pin: the same lease-protected delete without HostName
# pinning routes to the rogue mirror and deletes its copy.
if UNPINNED_OID=$(PATH="$SHIMD:$PATH" git -C "$WORK" ls-remote \
    --exit-code --heads -- 'git@bnw.github.invalid:owner/name.git' \
    "refs/heads/$HB" | awk '{print $1}') \
    && [ "$UNPINNED_OID" = "$FEAT_OID" ] \
    && PATH="$SHIMD:$PATH" git -C "$WORK" push --delete \
      --force-with-lease="refs/heads/$HB:$FEAT_OID" -- \
      'git@bnw.github.invalid:owner/name.git' "refs/heads/$HB" >/dev/null 2>&1; then
  ok
else
  bad "the unpinned counter-run did not delete from the rogue repository"
fi
if git -C "$ROGUE" show-ref --verify --quiet "refs/heads/$HB"; then
  bad "the unpinned counter-run left the rogue head in place"
else ok; fi
git -C "$BARE" push -q "$ROGUE" "refs/heads/$HB:refs/heads/$HB"
: >"$ALIAS_TRANSPORT_LOG"
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_SERVE_ROGUE ALIAS_TRANSPORT_LOG
want_rc 0
want_out '"remote_branch":"deleted"'
alias_head_gone
if git -C "$ROGUE" show-ref --verify --quiet "refs/heads/$HB"; then
  ok
else bad "the pinned delete reached the rogue mirror"; fi
if awk '
    index($0, "HostName=github.invalid") && index($0, "User=git") &&
    index($0, "Port=22") && index($0, "CanonicalizeHostname=no") &&
    index($0, "bnw.github.invalid") { pinned++ }
    END { exit !(pinned == 2) }
  ' "$FIX/alias-transport.log"; then
  ok
else
  bad "ls-remote and push did not both pin the endpoint through the alias: $(paste -sd ';' "$FIX/alias-transport.log")"
fi

scenario "ssh alias to a different repository still stops"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/other.git'
export ALIAS_SERVE="$BARE"
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE
want_rc 2
want_out 'STOP remote-repo-mismatch'
alias_head_kept

scenario "ssh alias on a non-default port still stops"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" ALIAS_GPORT=2222
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_GPORT
want_rc 2
want_out 'STOP remote-repo-mismatch'
alias_head_kept

scenario "ssh alias resolver failure after plausible output still stops"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" ALIAS_GFAIL_AFTER=1
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_GFAIL_AFTER
want_rc 2
want_out 'STOP remote-repo-mismatch'
alias_head_kept

scenario "ssh alias with an unsafe resolved user still stops"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" ALIAS_GUSER_U='git;rogue'
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_GUSER_U
want_rc 2
want_out 'STOP remote-repo-mismatch'
alias_head_kept

# A user-dependent ssh config: the bare host resolves to the forge, but the
# user-qualified git@host Git actually connects through resolves elsewhere. The
# guard must resolve the same user@host Git uses; resolving the bare host would
# bless the forge yet delete via the other endpoint. Discriminating: neutering
# the user pass (querying only the bare host) resolves the forge and deletes.
scenario "ssh alias diverging by remote user still stops"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" ALIAS_GHOST_U=rogue.github.invalid
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE ALIAS_GHOST_U
want_rc 2
want_out 'STOP remote-repo-mismatch'
alias_head_kept

# Git honors an ssh-command override (GIT_SSH_COMMAND, core.sshCommand, GIT_SSH)
# for the transport, but the guard queries the plain ssh on PATH, so the offline
# resolution need not reflect the endpoint Git reaches. The guard fails closed
# whenever an override is active. Discriminating: without the fail-closed the
# alias resolves to the forge (via the shim) and the branch is deleted through
# the unverified endpoint.
scenario "ssh alias under GIT_SSH_COMMAND override still stops"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" GIT_SSH_COMMAND='ssh -F /dev/null'
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE GIT_SSH_COMMAND
want_rc 2
want_out 'STOP remote-repo-mismatch'
alias_head_kept

scenario "ssh alias under core.sshCommand override still stops"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
G "$WORK" config core.sshCommand 'ssh -F /dev/null'
export ALIAS_SERVE="$BARE"
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE
want_rc 2
want_out 'STOP remote-repo-mismatch'
alias_head_kept

scenario "ssh alias under GIT_SSH override still stops"
std_setup; std_fixtures
G "$WORK" remote add alias 'git@bnw.github.invalid:owner/name.git'
export ALIAS_SERVE="$BARE" GIT_SSH="$SHIMD/ssh"
run_sm cleanup --pr 83 --repo owner/name --base-remote origin \
  --head-remote alias --head "$FEAT_OID"
unset ALIAS_SERVE GIT_SSH
want_rc 2
want_out 'STOP remote-repo-mismatch'
alias_head_kept

rm -f "$SHIMD/ssh"

fi

note=""
[ "$skip" -eq 0 ] || note=", $skip skipped (see SKIP above)"
echo "self-merge matrix: $pass passed, $fail failed$note"
[ "$fail" -eq 0 ]
