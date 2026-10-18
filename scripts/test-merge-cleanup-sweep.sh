#!/usr/bin/env bash
# Validation matrix for skills/merge-cleanup/worktree-sweep.sh.
#
# Every fixture is real git. Each removal case asserts that both the directory
# and the `git worktree list` entry are gone; each keep case asserts that both
# remain. Cases marked "discriminating" were run against degraded copies of
# the sweep and fail against them: one that trusts git's own refusal (status
# without --ignored and no flag read; `git worktree remove` without --force
# deletes ignored and index-flagged files), one without the primary or the
# self rule, one that treats every ancestor branch as landed, and one copy
# per guard the refute-first review added (nested worktree, submodule,
# nested repository, unreferenced detached HEAD, base branch, redirected
# worktree, inherited GIT_DIR). The newline case discriminates by
# construction, as in the inventory matrix.
#
# Usage: test-merge-cleanup-sweep.sh
# Exit codes: 0 all passed, 1 a case failed.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT="$ROOT/skills/merge-cleanup/worktree-sweep.sh"
# Physical path: git reports worktrees by their resolved path, and macOS's
# temporary directory sits behind the /var -> /private/var symlink.
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

PASS=0
FAIL=0
SCEN=""
NAME=""

G() { local d="$1"; shift; git -C "$d" "$@" >/dev/null 2>&1; }

# scenario <name>: a repo on main whose origin/HEAD names origin/main, with
# branch feat one commit ahead and checked out in a linked worktree at $WT.
scenario() {
  NAME="$1"
  SCEN=$(mktemp -d "$TMP/scen.XXXXXX")
  REPO="$SCEN/repo"
  WT="$SCEN/wt"
  git init -q -b main "$REPO"
  printf 'a\n' > "$REPO/a.txt"
  printf '.env\n' > "$REPO/.gitignore"
  G "$REPO" add .
  G "$REPO" commit -m seed
  sync_origin
  G "$REPO" worktree add -b feat "$WT"
  printf 'f\n' > "$WT/f.txt"
  G "$WT" add .
  G "$WT" commit -m "feat work"
}

sync_origin() { # point origin/main at main, and origin/HEAD at origin/main
  G "$REPO" update-ref refs/remotes/origin/main refs/heads/main
  G "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

land() { # land <branch>: merge it into main with a merge commit, as a PR lands
  G "$REPO" merge --no-ff -m "Merge $1 (#1)" "$1"
  sync_origin
}

run() { # run <args...>: run the sweep from the primary checkout
  OUT=$(cd "$REPO" && "$SUT" "$@" 2>&1)
  RC=$?
}

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $NAME: $1"; }

want_rc() {
  if [ "$RC" -eq "$1" ]; then ok; else bad "exit $RC, wanted $1 (got: $OUT)"; fi
}
want_out() {
  case "$OUT" in
    *"$1"*) ok ;;
    *) bad "output lacks '$1' (got: $OUT)" ;;
  esac
}

listed() { # listed <path>: is <path> a `git worktree list` entry?
  local field
  while IFS= read -r -d '' field; do
    [ "$field" = "worktree $1" ] && return 0
  done < <(git -C "$REPO" worktree list --porcelain -z)
  return 1
}
want_kept() { # want_kept <path>
  if [ -d "$1" ] && listed "$1"; then ok; else bad "$1 was removed"; fi
}
want_removed() { # want_removed <path>
  if [ ! -e "$1" ] && ! listed "$1"; then ok; else bad "$1 is still there"; fi
}

# --- a merged worktree ---------------------------------------------------------

scenario "a merged clean worktree is reported, and only --remove removes it"
land feat
MERGE=$(git -C "$REPO" rev-parse main)
run
want_rc 0
want_out 'WORKTREE clean {"path":"'"$WT"'","branch":"refs/heads/feat"'
want_out "\"merge\":{\"oid\":\"$MERGE\",\"subject\":\"Merge feat (#1)\"}"
want_out '"reason":"dry run"'
want_out '"candidates":1,"clean":1,"dirty":0,"removed":0,"kept":1'
want_kept "$WT"
run --remove
want_rc 0
want_out "WORKTREE removed {\"path\":\"$WT\""
want_out '"mode":"remove"'
want_out '"removed":1,"kept":0'
want_removed "$WT"
if git -C "$REPO" rev-parse --verify --quiet refs/heads/feat >/dev/null; then ok; else bad "the sweep deleted the branch"; fi

scenario "an unmerged branch is never a candidate"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE unmerged'
want_kept "$WT"

scenario "a fast-forwarded clean branch is a candidate with no landing merge"
G "$REPO" merge --ff-only feat
sync_origin
run --remove
want_rc 0
want_out '"merge":"none found"'
want_removed "$WT"

scenario "a dirty branch with no landing merge is kept even under --remove-dirty"
# A branch cut from the base tip with no commits yet looks exactly like a
# fast-forwarded one, and its uncommitted work is in progress.
G "$REPO" worktree add -b fresh "$SCEN/fresh"
printf 'wip\n' > "$SCEN/fresh/wip.txt"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE dirty {"path":"'"$SCEN/fresh"'"'
want_out 'no landing merge was found'
want_kept "$SCEN/fresh"   # discriminating: an ancestor test alone removes it

scenario "a base given with --base is used instead of origin/HEAD"
G "$REPO" symbolic-ref -d refs/remotes/origin/HEAD
G "$REPO" branch release
G "$REPO" checkout -q release
G "$REPO" merge --no-ff -m "Merge feat into release" feat
G "$REPO" checkout -q main
run --base release
want_rc 0
want_out 'WORKTREE clean'
want_out '"base":"release"'
want_out '"subject":"Merge feat into release"'

scenario "no origin/HEAD and no --base stops before reading any worktree"
land feat
G "$REPO" symbolic-ref -d refs/remotes/origin/HEAD
run --remove
want_rc 2
want_out 'STOP no-base'
want_out '--base'
want_kept "$WT"

# --- a detached worktree -------------------------------------------------------

scenario "a detached worktree under land's template is a candidate"
G "$REPO" worktree add --detach "$SCEN/land-wt.Ab12Cd/wt" main
run --remove
want_rc 0
want_out "WORKTREE removed {\"path\":\"$SCEN/land-wt.Ab12Cd/wt\",\"branch\":\"detached\""
want_removed "$SCEN/land-wt.Ab12Cd/wt"

scenario "a dirty worktree under land's template is removed only with --remove-dirty"
G "$REPO" worktree add --detach "$SCEN/land-wt.Ab12Cd/wt" main
printf 'hook\n' > "$SCEN/land-wt.Ab12Cd/wt/hook-artifact.txt"
run --remove
want_rc 0
want_out '"untracked":["hook-artifact.txt"]'
want_kept "$SCEN/land-wt.Ab12Cd/wt"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE removed'
want_removed "$SCEN/land-wt.Ab12Cd/wt"

scenario "a detached worktree outside the template is never a candidate"
G "$REPO" worktree add --detach "$SCEN/other/wt" main
G "$REPO" worktree add --detach "$SCEN/land-wt.Ab12Cd/nested/wt" main
G "$REPO" worktree add --detach "$SCEN/land-wt.personal/wt" main
G "$REPO" worktree add --detach "$SCEN/land-wt.Ab12C/wt" main
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE detached-other {"path":"'"$SCEN/other/wt"'"'
want_out 'WORKTREE detached-other {"path":"'"$SCEN/land-wt.Ab12Cd/nested/wt"'"'
want_out 'WORKTREE detached-other {"path":"'"$SCEN/land-wt.personal/wt"'"'
want_out 'WORKTREE detached-other {"path":"'"$SCEN/land-wt.Ab12C/wt"'"'
want_kept "$SCEN/other/wt"
want_kept "$SCEN/land-wt.Ab12Cd/nested/wt"
want_kept "$SCEN/land-wt.personal/wt"   # discriminating: land-wt.?* removed it
want_kept "$SCEN/land-wt.Ab12C/wt"

# --- what removal would delete -------------------------------------------------

scenario "an untracked file makes a merged worktree dirty and is listed"
land feat
printf 'scratch\n' > "$WT/scratch.txt"
run --remove
want_rc 0
want_out 'WORKTREE dirty'
want_out '"untracked":["scratch.txt"]'
want_out 'dirty; --remove-dirty would delete the files listed'
want_kept "$WT"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE removed'
want_out '"mode":"remove-dirty"'
want_removed "$WT"

scenario "a modified file is listed as modified"
land feat
printf 'EDITED\n' > "$WT/a.txt"
run
want_rc 0
want_out '"modified":["a.txt"]'

scenario "an ignored file alone makes a worktree dirty"
land feat
printf 'secret\n' > "$WT/.env"
run --remove
want_rc 0
want_out 'WORKTREE dirty'
want_out '"ignored":[".env"]'
want_kept "$WT"   # discriminating: git worktree remove deletes it with exit 0

scenario "an assume-unchanged edit makes a worktree dirty"
land feat
G "$WT" update-index --assume-unchanged a.txt
printf 'EDITED\n' > "$WT/a.txt"
run --remove
want_rc 0
want_out 'WORKTREE dirty'
want_out '"flagged":["a.txt"]'
want_kept "$WT"   # discriminating: status shows nothing, and git removes it

scenario "a paused operation makes a worktree dirty"
land feat
( cd "$WT" && git rev-parse HEAD > "$(git rev-parse --git-path CHERRY_PICK_HEAD)" )
run --remove
want_rc 0
want_out 'WORKTREE dirty'
want_out '"operation":"CHERRY_PICK_HEAD"'
want_kept "$WT"

# --- never a candidate ---------------------------------------------------------

scenario "the primary checkout is never a candidate"
land feat
# Run from the linked worktree, so the primary is not also the worktree the
# command runs in: main is merged into origin/main, so only the primary rule
# keeps it.
OUT=$(cd "$WT" && "$SUT" --remove --remove-dirty 2>&1); RC=$?
want_rc 0
want_out 'WORKTREE primary {"path":"'"$REPO"'"'
want_kept "$REPO"   # discriminating
if [ -f "$REPO/a.txt" ]; then ok; else bad "the primary checkout lost files"; fi

scenario "the worktree the command runs in is never a candidate"
land feat
OUT=$(cd "$WT" && "$SUT" --remove 2>&1); RC=$?
want_rc 0
want_out 'WORKTREE self {"path":"'"$WT"'"'
want_kept "$WT"   # discriminating

scenario "a locked worktree is never a candidate"
land feat
G "$REPO" worktree lock "$WT"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE locked'   # discriminating: without the field, git refuses and the run stops
want_kept "$WT"

scenario "a worktree whose directory is gone is reported, not pruned"
land feat
rm -rf "$WT"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE prunable'
if listed "$WT"; then ok; else bad "the sweep pruned the entry"; fi

scenario "a branch ref that no longer resolves is never a candidate"
land feat
G "$REPO" update-ref -d refs/heads/feat
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE unresolved-branch'
want_kept "$WT"

scenario "a worktree that holds another registered worktree is never a candidate"
land feat
G "$REPO" worktree add -b wip "$WT/nested"
printf 'work\n' > "$WT/nested/work.txt"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-worktree {"path":"'"$WT"'"'
want_kept "$WT"   # discriminating: --force on $WT deletes the nested work
if [ -f "$WT/nested/work.txt" ]; then ok; else bad "the nested worktree lost its files"; fi

scenario "a worktree that holds a populated submodule is never a candidate"
git -C "$SCEN" init -q -b main sub
printf 's\n' > "$SCEN/sub/s.txt"
G "$SCEN/sub" add .
G "$SCEN/sub" commit -m sub
G "$WT" -c protocol.file.allow=always submodule add "$SCEN/sub" sub
G "$WT" commit -m "add sub"
# An unpushed submodule commit, hidden from status by ignore = all.
printf 'only here\n' > "$WT/sub/new.txt"
G "$WT/sub" add .
G "$WT/sub" commit -m "only in this worktree"
G "$WT" config -f .gitmodules submodule.sub.ignore all
G "$WT" commit -am "ignore sub"
land feat
printf 'junk\n' > "$WT/junk"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-submodule'
want_kept "$WT"   # discriminating: --force deletes the submodule's repository

scenario "a deinitialized submodule's repository still keeps its worktree"
git -C "$SCEN" init -q -b main sub
printf 's\n' > "$SCEN/sub/s.txt"
G "$SCEN/sub" add .
G "$SCEN/sub" commit -m sub
G "$WT" -c protocol.file.allow=always submodule add "$SCEN/sub" sub
G "$WT" commit -m "add sub"
printf 'only here\n' > "$WT/sub/new.txt"
G "$WT/sub" add .
G "$WT/sub" commit -m "only in this worktree"
# deinit empties the checkout, so only the worktree's modules/ holds the commit.
G "$WT" submodule deinit -f sub
land feat
printf 'junk\n' > "$WT/junk"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-submodule'
want_kept "$WT"   # discriminating: --force deletes the submodule's repository

scenario "an untracked nested repository keeps its worktree"
land feat
git -C "$WT" init -q -b main nested
printf 'n\n' > "$WT/nested/n.txt"
G "$WT/nested" add .
G "$WT/nested" commit -m "only in the nested repository"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-repository'
want_kept "$WT"   # discriminating: --force deletes the nested repository

scenario "a repository nested inside an ignored directory keeps its worktree"
land feat
printf 'vendor/\n' > "$WT/.gitignore"
mkdir -p "$WT/vendor"
git -C "$WT/vendor" init -q -b main lib
printf 'l\n' > "$WT/vendor/lib/l.txt"
G "$WT/vendor/lib" add .
G "$WT/vendor/lib" commit -m "only in the ignored repository"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-repository'
want_kept "$WT"   # discriminating: status names only vendor/

scenario "a detached land-wt HEAD that no ref holds is dirty, not clean"
G "$REPO" worktree add --detach "$SCEN/land-wt.Ab12Cd/wt" main
printf 'x\n' > "$SCEN/land-wt.Ab12Cd/wt/x.txt"
G "$SCEN/land-wt.Ab12Cd/wt" add .
G "$SCEN/land-wt.Ab12Cd/wt" commit -m "nowhere else"
ORPHAN=$(git -C "$SCEN/land-wt.Ab12Cd/wt" rev-parse HEAD)
run --remove
want_rc 0
want_out "\"unreferenced_head\":\"$ORPHAN\""
want_kept "$SCEN/land-wt.Ab12Cd/wt"   # discriminating: plain --remove orphans it

scenario "the base branch's own worktree is never a candidate"
land feat
G "$REPO" checkout -q --detach
G "$REPO" worktree add "$SCEN/main-wt" main
run --remove
want_rc 0
want_out 'WORKTREE base-branch {"path":"'"$SCEN/main-wt"'"'
want_kept "$SCEN/main-wt"

scenario "the base branch's worktree is found under a remote whose name holds a slash"
land feat
G "$REPO" checkout -q --detach
G "$REPO" worktree add "$SCEN/main-wt" main
# One remote only: with up beside up/stream, this case failed on CI's git 2.55.
G "$REPO" remote add up/stream "$SCEN/none" || bad "git refused the remote name up/stream"
G "$REPO" update-ref refs/remotes/up/stream/main refs/heads/main
run --remove --base up/stream/main
want_rc 0
want_out 'WORKTREE base-branch {"path":"'"$SCEN/main-wt"'"'
want_kept "$SCEN/main-wt"   # discriminating: stripping up/ judged it stream/main

scenario "a worktree git resolves elsewhere is never a candidate"
land feat
mkdir "$SCEN/decoy"
G "$REPO" config extensions.worktreeConfig true
G "$WT" config --worktree core.worktree "$SCEN/decoy"
printf 'secret\n' > "$WT/.env"
run --remove
want_rc 0
want_out 'WORKTREE redirected'
want_kept "$WT"   # discriminating: the decoy reads clean and removal takes .env
if [ -f "$WT/.env" ]; then ok; else bad "the ignored file was deleted"; fi

scenario "an exported GIT_DIR does not point the reads at another index"
land feat
G "$WT" update-index --assume-unchanged a.txt
printf 'EDITED\n' > "$WT/a.txt"
OUT=$(cd "$REPO" && GIT_DIR="$REPO/.git" "$SUT" 2>&1); RC=$?
want_rc 0
want_out '"flagged":["a.txt"]'

# --- the recheck before each removal ------------------------------------------

# A git shim that, on the sweep's first removal, runs $SHIM_ACTION on whichever
# of $SHIM_A and $SHIM_B is not being removed, as a concurrent process would.
REAL_GIT=$(command -v git)
export REAL_GIT
shim() { # shim <action-body>: install the shim and the action for this scenario
  mkdir "$SCEN/bin"
  cat > "$SCEN/bin/git" <<'SHIM'
#!/usr/bin/env bash
if [ "$1" = worktree ] && [ "$2" = remove ] && [ ! -e "$SHIM_ONCE" ]; then
  : > "$SHIM_ONCE"
  case "${!#}" in "$SHIM_A") other="$SHIM_B" ;; *) other="$SHIM_A" ;; esac
  "$SHIM_ACTION" "$other"
fi
exec "$REAL_GIT" "$@"
SHIM
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$SCEN/action"
  chmod +x "$SCEN/bin/git" "$SCEN/action"
  export SHIM_ONCE="$SCEN/shim-ran" SHIM_A="$WT" SHIM_B="$SCEN/wt2" SHIM_ACTION="$SCEN/action"
}
run_shimmed() { # run_shimmed <args...>: run with the shim first on PATH
  local saved="$PATH"
  PATH="$SCEN/bin:$PATH"
  run "$@"
  PATH="$saved"
}

scenario "a candidate that turns dirty before its removal is kept and counted dirty"
G "$REPO" branch feat2 feat
land feat
G "$REPO" worktree add "$SCEN/wt2" feat2
shim 'printf "late\n" > "$1/late.txt"'
run_shimmed --remove
want_rc 0
want_out 'changed since the first pass and no longer authorized for removal'
want_out '"late.txt"'
# discriminating: the first-pass counts said clean:2, dirty:0
want_out '"candidates":2,"clean":1,"dirty":1,"removed":1,"kept":1'

scenario "a removal reports the branch the recheck found"
G "$REPO" branch feat2 feat
G "$REPO" branch spare main
land feat
G "$REPO" worktree add "$SCEN/wt2" feat2
shim '"$REAL_GIT" -C "$1" switch -q spare'
run_shimmed --remove
want_rc 0
want_out '"removed":2'
want_out '"branch":"refs/heads/spare"'   # discriminating: it reported feat or feat2

# --- path handling -------------------------------------------------------------

scenario "a worktree path ending in a newline is not confused with its sibling"
NL="$SCEN/wt"$'\n'
G "$REPO" worktree add -b nl "$NL"
land nl
printf 'unmerged\n' > "$WT/u.txt"
G "$WT" add .
G "$WT" commit -m "more feat work"
run --remove
want_rc 0
want_out 'WORKTREE removed {"path":"'"$SCEN"'/wt\n"'
want_out 'WORKTREE unmerged {"path":"'"$WT"'"'
# Discriminating: a line-wise read of the list strips the newline, so the
# sweep would judge or remove the sibling at $WT instead.
want_removed "$NL"
want_kept "$WT"

# --- refusals ------------------------------------------------------------------

scenario "a removal git refuses stops the run and attempts nothing after it"
land feat
# `git worktree list` sorts linked worktrees by path, so zlater comes after wt.
G "$REPO" worktree add -b later "$SCEN/zlater"
land later
# A shim refuses the first removal the way git refuses one it cannot do.
mkdir "$SCEN/bin"
REAL_GIT=$(command -v git)
cat > "$SCEN/bin/git" <<SHIM
#!/bin/sh
case "\$*" in
  *"worktree remove -- $WT") echo "fatal: refused by the test shim" >&2; exit 128 ;;
esac
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$SCEN/bin/git"
OUT=$(cd "$REPO" && PATH="$SCEN/bin:$PATH" "$SUT" --remove 2>&1); RC=$?
want_rc 2
want_out 'STOP remove-failed'
want_out 'refused by the test shim'
want_out 'not attempted: an earlier removal failed'
want_kept "$WT"
want_kept "$SCEN/zlater"

scenario "--remove-dirty without --remove is a usage error"
land feat
printf 'scratch\n' > "$WT/scratch.txt"
run --remove-dirty
want_rc 64
want_out 'Usage:'
want_kept "$WT"

scenario "an unknown argument or a missing --base value is a usage error"
run --force
want_rc 64
run --base
want_rc 64
run --base --remove
want_rc 64

scenario "--help prints the contract"
run --help
want_rc 0
want_out '--remove-dirty'

echo "merge-cleanup sweep matrix: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
