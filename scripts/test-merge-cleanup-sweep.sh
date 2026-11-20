#!/usr/bin/env bash
# Validation matrix for skills/merge-cleanup/worktree-sweep.sh.
#
# Every fixture is real git. Each removal case asserts that both the directory
# and the `git worktree list` entry are gone; each keep case asserts that both
# remain. Cases marked "discriminating" were run against degraded copies of
# the sweep and fail against them: one that trusts git's own refusal (status
# without --ignored and no flag read; `git worktree remove` without --force
# deletes ignored and index-flagged files), one without the primary or the
# self rule, one that treats every ancestor branch as landed, one whose
# --remove-landed skips the landing-merge test, and one copy
# per guard the refute-first review added (nested worktree, submodule,
# nested repository, unreferenced detached HEAD, base branch, redirected
# worktree, inherited GIT_DIR). The disposables cases marked discriminating
# were run against copies without the clean-acceptance rule, with every
# ignored path disposable, without the nested-repository skip or its
# check-ignore, with one disposable per file, with the file read from the
# working tree, and with the pathspec and find code a review found unsafe;
# with the nested-repository probe asking about the repository's path, with
# or without its slash; skipping the check that a matched part is ignored or
# stopping at the first matching entry; reading a failed lookup as no
# entries; without --full-tree, the NUL-check reader's status, or the
# per-prefix newline guard; refusing every path with a newline; comparing
# through a pipe; matching any part named .DS_Store, or skipping that rule
# under --remove-head; reading a file under --remove-head; dropping a last
# line without a newline; stripping a carriage return; accepting a
# non-regular file; reading a comment as an entry, or skipping comments
# before the whitespace check; applying the .DS_Store rule before the
# entries; and without the NUL check. The newline case discriminates by construction, as in the
# inventory matrix. The large-listing cases were run against the sweep
# before --ignored=matching and subshell-free escaping, and the
# empty-directory case against a copy that lists every ignored dir/ record.
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
# No global excludes file: a developer's own ignore of .DS_Store would turn
# the untracked-.DS_Store case into an ignored one.
export GIT_CONFIG_GLOBAL=/dev/null XDG_CONFIG_HOME="$TMP/xdg"

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

scenario "a quote, a backslash, a tab, and UTF-8 in a listed path are escaped"
printf '*.log\n' >> "$REPO/.git/info/exclude"
land feat
for p in 'a"b.log' 'c\d.log' "e"$'\t'"f.log" 'é.log'; do : > "$WT/$p"; done
run --remove
want_rc 0
want_out '"ignored":["a\"b.log","c\\d.log","e\tf.log","é.log"],"flagged":[]'
want_kept "$WT"

# --- the end-of-batch sweep (--remove-landed) ---------------------------------

scenario "--remove-landed removes a landed clean branch"
land feat
run --remove-landed
want_rc 0
want_out "WORKTREE removed {\"path\":\"$WT\""
want_out '"mode":"remove-landed"'
want_out '"removed":1,"kept":0'
want_removed "$WT"

scenario "--remove-landed keeps a fast-forwarded clean branch"
G "$REPO" merge --ff-only feat
sync_origin
run --remove-landed
want_rc 0
want_out 'WORKTREE clean {"path":"'"$WT"'"'
want_out '"merge":"none found"'
want_out 'clean, but no landing merge was found'
want_out '"mode":"remove-landed"'
want_kept "$WT"   # discriminating: a sweep that skips the landing-merge test removes it

scenario "--remove-landed keeps a clean branch cut from the base tip"
# A session that has created its worktree but not yet edited a file.
G "$REPO" worktree add -b fresh "$SCEN/fresh"
run --remove-landed
want_rc 0
want_out 'WORKTREE clean {"path":"'"$SCEN/fresh"'"'
want_out 'a session may be starting work in it'
want_kept "$SCEN/fresh"   # discriminating: a sweep that skips the landing-merge test removes it

scenario "--remove-landed keeps a landed dirty branch"
land feat
printf 'scratch\n' > "$WT/scratch.txt"
run --remove-landed
want_rc 0
want_out 'WORKTREE dirty {"path":"'"$WT"'"'
want_out '"untracked":["scratch.txt"]'
want_out 'dirty; --remove-landed removes only clean worktrees'
want_kept "$WT"

scenario "--remove-landed keeps a clean detached land-wt worktree"
# A lander that starts after the batch's release works in one of these.
G "$REPO" worktree add --detach "$SCEN/land-wt.Ab12Cd/wt" main
run --remove-landed
want_rc 0
want_out 'WORKTREE clean {"path":"'"$SCEN/land-wt.Ab12Cd/wt"'","branch":"detached"'
want_out "left for the owner's sweep"
want_kept "$SCEN/land-wt.Ab12Cd/wt"   # discriminating: a sweep that skips the landing-merge test removes it

# --- disposables ---------------------------------------------------------------

disposables() { # disposables <line...>: commit .worktree-disposables on main and sync origin
  printf '%s\n' "$@" > "$REPO/.worktree-disposables"
  G "$REPO" add .worktree-disposables
  G "$REPO" commit -m "worktree disposables"
  sync_origin
}
commit_file() { # commit_file: commit .worktree-disposables as written, and sync origin
  G "$REPO" add .worktree-disposables
  G "$REPO" commit -m "worktree disposables"
  sync_origin
}
ignore() { # ignore <pattern...>: ignore in every worktree, without a commit
  local p
  for p in "$@"; do printf '%s\n' "$p" >> "$REPO/.git/info/exclude"; done
}

scenario "an ignored .DS_Store leaves a landed worktree clean without a file"
ignore .DS_Store
land feat
mkdir "$WT/sub"
: > "$WT/.DS_Store"
: > "$WT/sub/.DS_Store"
run
want_rc 0
want_out 'WORKTREE clean {"path":"'"$WT"'"'   # discriminating: the inventory's STOP dirty decides alone
want_out '"ignored":[],"flagged":[],"disposable":[".DS_Store","sub/.DS_Store"]'
want_out '"disposables":[]'   # the built-in rule is not listed
run --remove-landed
want_rc 0
want_out "WORKTREE removed {\"path\":\"$WT\""
want_removed "$WT"

scenario "an ignored .DS_Store directory is not built in"
ignore .DS_Store/
land feat
mkdir "$WT/.DS_Store"
printf 'mine\n' > "$WT/.DS_Store/note"
run --remove
want_rc 0
want_out 'WORKTREE dirty'
want_out '"ignored":[".DS_Store/"],"flagged":[],"disposable":[]'
want_kept "$WT"   # discriminating: matching any part named .DS_Store removes it

scenario "an untracked .DS_Store is never disposable"
land feat
: > "$WT/.DS_Store"
run --remove-landed
want_rc 0
want_out 'WORKTREE dirty'
want_out '"untracked":[".DS_Store"]'
want_kept "$WT"

scenario "an undeclared ignored file beside a .DS_Store keeps the worktree dirty"
ignore .DS_Store
land feat
: > "$WT/.DS_Store"
printf 'secret\n' > "$WT/.env"
run --remove-landed
want_rc 0
want_out 'WORKTREE dirty {"path":"'"$WT"'"'
want_out '"ignored":[".env"],"flagged":[],"disposable":[".DS_Store"]'
want_kept "$WT"   # discriminating: a sweep that accepts any disposable removes it

scenario "without a file ignored build output keeps the worktree dirty"
ignore .build/
land feat
mkdir "$WT/.build"
printf 'o\n' > "$WT/.build/obj.o"
run --remove
want_rc 0
want_out 'WORKTREE dirty'
want_out '"ignored":[".build/"],"flagged":[],"disposable":[]'
want_out '"disposables":[]'
want_kept "$WT"

scenario "comments and blank lines in the file are skipped"
disposables '# SwiftPM build output' '' '.build/' '#notes/'
ignore .build/ notes/
land feat
mkdir "$WT/.build" "$WT/notes"
printf 'o\n' > "$WT/.build/obj.o"
printf 'mine\n' > "$WT/notes/todo"
run --remove
want_rc 0
want_out '"disposables":[".build/"]'
want_out '"ignored":["notes/"],"flagged":[],"disposable":[".build/"]'
want_kept "$WT"   # discriminating: reading a comment as an entry removes it

scenario "a file of comments alone declares nothing"
disposables '# Nothing here yet'
ignore .build/
land feat
mkdir "$WT/.build"
printf 'o\n' > "$WT/.build/obj.o"
run --remove
want_rc 0
want_out '"disposables":[]'
want_out 'WORKTREE dirty'
want_kept "$WT"

scenario "an empty file declares nothing"
: > "$REPO/.worktree-disposables"
commit_file
ignore .DS_Store .build/
land feat
mkdir "$WT/.build"
: > "$WT/.DS_Store"
printf 'o\n' > "$WT/.build/obj.o"
run --remove
want_rc 0
want_out '"disposables":[]'
want_out '"ignored":[".build/"],"flagged":[],"disposable":[".DS_Store"]'
want_kept "$WT"

scenario "a .DS_Store under a declared directory reports the directory"
disposables cache/
ignore cache/
land feat
mkdir -p "$WT/cache/sub"
printf 'a\n' > "$WT/cache/a"
: > "$WT/cache/sub/.DS_Store"
printf 'z\n' > "$WT/cache/z"
run --remove
want_rc 0
want_out '"disposable":["cache/"]'   # discriminating: the built-in rule first split the run
want_out 'WORKTREE removed'
want_removed "$WT"

scenario "a last line without a newline is read"
printf '.build/' > "$REPO/.worktree-disposables"
commit_file
ignore .build/
land feat
mkdir "$WT/.build"
printf 'o\n' > "$WT/.build/obj.o"
run --remove
want_rc 0
want_out '"disposables":[".build/"]'   # discriminating: read without || [ -n "$line" ] drops it
want_out 'WORKTREE removed'
want_removed "$WT"

scenario "a repository inside a declared ignored directory does not hold the worktree"
disposables .build/
ignore .build/
land feat
mkdir -p "$WT/.build/checkouts"
git -C "$WT/.build/checkouts" init -q -b main x
printf 'x\n' > "$WT/.build/checkouts/x/x.txt"
G "$WT/.build/checkouts/x" add .
G "$WT/.build/checkouts/x" commit -m "package checkout"
printf 'o\n' > "$WT/.build/obj.o"
run
want_rc 0
want_out 'WORKTREE clean {"path":"'"$WT"'"'   # discriminating: every nested .git held it
want_out '"disposable":[".build/"]'   # discriminating: one entry per prefix, not per file
want_out '"disposables":[".build/"]'
run --remove
want_rc 0
want_out "WORKTREE removed {\"path\":\"$WT\""
want_removed "$WT"   # plain git worktree remove takes the nested repository

scenario "a repository inside a declared directory that is not ignored still holds it"
disposables .build/
land feat
mkdir -p "$WT/.build/checkouts"
git -C "$WT/.build/checkouts" init -q -b main x
printf 'x\n' > "$WT/.build/checkouts/x/x.txt"
G "$WT/.build/checkouts/x" add .
G "$WT/.build/checkouts/x" commit -m "only here"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-repository'
want_kept "$WT"   # discriminating: --force deletes the untracked repository

scenario "an anchored entry matches only at the worktree root"
disposables app/.build/
ignore .build/
land feat
mkdir -p "$WT/app/.build" "$WT/other/app/.build"
printf 'o\n' > "$WT/app/.build/o"
printf 'o\n' > "$WT/other/app/.build/o"
run --remove
want_rc 0
want_out 'WORKTREE dirty'
want_out '"ignored":["other/app/.build/"],"flagged":[],"disposable":["app/.build/"]'
want_kept "$WT"

scenario "a directory-only entry does not match a file of that name"
disposables cache/
ignore cache
land feat
printf 'mine\n' > "$WT/cache"
run --remove
want_rc 0
want_out '"ignored":["cache"],"flagged":[],"disposable":[]'
want_kept "$WT"

scenario "a file only on a branch has no effect"
land feat
# The primary checkout, where the sweep runs, holds a file the base lacks.
G "$REPO" checkout -q -b record
printf '.build/\n' > "$REPO/.worktree-disposables"
G "$REPO" add .worktree-disposables
G "$REPO" commit -m "file off the base"
ignore .build/
mkdir "$WT/.build"
printf 'o\n' > "$WT/.build/obj.o"
run --remove
want_rc 0
want_out '"disposables":[]'
want_out 'WORKTREE dirty'
want_kept "$WT"   # discriminating: reading the working tree's file removes it

scenario "an untracked repository named like pathspec magic still holds its worktree"
disposables .build/
ignore /scratch/.build/
land feat
mkdir -p "$WT/:scratch"
git -C "$WT/:scratch" init -q -b main .build
printf 'x\n' > "$WT/:scratch/.build/x.txt"
G "$WT/:scratch/.build" add .
G "$WT/:scratch/.build" commit -m "only here"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-repository'
want_kept "$WT"   # discriminating: check-ignore read :scratch as magic and --force deleted it

# nested_repo <dir>: a repository with a commit found nowhere else, at <dir>
# in the worktree.
nested_repo() {
  mkdir -p "$WT/$1"
  git -C "$WT/$1" init -q -b main
  printf 'x\n' > "$WT/$1/x.txt"
  G "$WT/$1" add x.txt
  G "$WT/$1" commit -m "only here"
}

scenario "a repository at a declared directory whose contents alone are ignored still holds it"
disposables cache/
ignore 'cache/*'
land feat
nested_repo cache
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-repository'
want_kept "$WT"   # discriminating: check-ignore on cache/ with its slash answered ignored

scenario "a repository whose own .gitignore ignores everything still holds it"
disposables deps/
land feat
nested_repo deps/tool
printf '*\n!x.txt\n' > "$WT/deps/tool/.gitignore"
run --remove --remove-dirty
want_rc 0
want_out 'WORKTREE holds-repository'
want_kept "$WT"   # discriminating: with the slash, the nested .gitignore answered ignored

scenario "a repository in an ignored directory under a declared one that is not ignored still holds it"
disposables notes/
ignore notes/private/
land feat
nested_repo notes/private
run --remove-landed
want_rc 0
want_out 'WORKTREE holds-repository'
want_kept "$WT"   # discriminating: checking the repository's own directory removes it

scenario "ignored files under a declared directory that is not ignored keep the worktree"
disposables notes/
ignore notes/private/
land feat
mkdir -p "$WT/notes/private"
printf 'mine\n' > "$WT/notes/private/todo.md"
git init -q --bare "$WT/notes/private/store.git"
run --remove-landed
want_rc 0
want_out 'WORKTREE dirty'
want_out '"disposable":[]'
want_kept "$WT"   # discriminating: matching notes/ alone removed it, bare repository and all

scenario "a repository under the narrower of two declared directories is disposable"
disposables notes/ notes/private/
ignore notes/private/
land feat
nested_repo notes/private
run --remove
want_rc 0
want_out 'WORKTREE removed'
want_removed "$WT"   # discriminating: stopping at the first matching entry held it

scenario "a path holding a newline never reads another path's ignore answer"
disposables cache/
ignore 'aa*/' unused/cache/private/
land feat
mkdir -p "$WT/aa"$'\n'"unused/cache" "$WT/unused/cache/private"
printf 'x\n' > "$WT/aa"$'\n'"unused/cache/file"
printf 'mine\n' > "$WT/unused/cache/private/note"
run --remove-landed
want_rc 0
want_out 'WORKTREE dirty'
want_kept "$WT"   # discriminating: the newline-delimited cache matched unused/cache

scenario "a newline in a name under a declared directory leaves it disposable"
disposables build/
ignore build/
land feat
mkdir -p "$WT/build"
printf 'x\n' > "$WT/build/log"$'\n'"old"
run --remove
want_rc 0
want_out 'WORKTREE removed'
want_removed "$WT"   # discriminating: refusing any path with a newline kept it

scenario "an unreadable nested repository is still reported, not a failed read"
land feat
git -C "$WT" init -q -b main inner
chmod 000 "$WT/inner/.git/objects"
run --remove --remove-dirty
chmod 755 "$WT/inner/.git/objects"
want_rc 0
want_out 'WORKTREE holds-repository'
want_kept "$WT"

scenario "a bad file stops the run before any worktree is read"
land feat
for entry in '../x' '/abs' '.git/' 'a/.GIT' '*.pyc' 'a//b' '!keep' 'a\b' 'x/./y'; do
  NAME="a bad file stops the run: entry '$entry'"
  disposables .build/ "$entry"
  run --remove
  want_rc 2
  want_out 'STOP bad-record'
  want_out "line 2, entry"
  case "$OUT" in *WORKTREE*) bad "a worktree was judged" ;; *) ok ;; esac
  want_kept "$WT"
done
for line in ' x' 'x ' ' ' ' # note' '# note '; do
  NAME="a bad file stops the run: line '$line'"
  disposables .build/ "$line"
  run --remove
  want_rc 2
  want_out 'line 2 has a leading or trailing space'
  want_kept "$WT"   # discriminating: skipping comments first accepted '# note '
done
NAME="a bad file stops the run: a carriage return"
printf '.build/\r\n' > "$REPO/.worktree-disposables"
commit_file
run --remove
want_rc 2
want_out 'line 1 holds a carriage return'
want_kept "$WT"   # discriminating: a stripped CR read .build/ as the entry
NAME="a bad file stops the run: a carriage return on a comment line"
printf '# Build output\r\n.build/\n' > "$REPO/.worktree-disposables"
commit_file
run --remove
want_rc 2
want_out 'line 1 holds a carriage return'
want_kept "$WT"
NAME="a bad file stops the run: a symbolic link"
G "$REPO" rm -q .worktree-disposables
ln -s notes "$REPO/.worktree-disposables"
commit_file
run --remove
want_rc 2
want_out 'is not a regular file'
want_kept "$WT"   # discriminating: the link's blob, its target name, read as an entry
NAME="a bad file stops the run: a directory"
G "$REPO" rm -q .worktree-disposables
mkdir "$REPO/.worktree-disposables"
printf 'x\n' > "$REPO/.worktree-disposables/x"
commit_file
run --remove
want_rc 2
want_out 'is not a regular file'
want_kept "$WT"
G "$REPO" rm -q -r .worktree-disposables
G "$REPO" commit -m "drop the directory"
NAME="a bad file stops the run: run from a subdirectory"
disposables ../x
mkdir -p "$REPO/sub"
OUT=$(cd "$REPO/sub" && "$SUT" --remove 2>&1)
RC=$?
want_rc 2
want_out 'STOP bad-record'
want_kept "$WT"   # discriminating: ls-tree read sub/.worktree-disposables and found no file
NAME="a bad file stops the run: a file that cannot be read"
disposables .build/
blob=$(git -C "$REPO" rev-parse origin/main:.worktree-disposables)
mv "$REPO/.git/objects/${blob:0:2}/${blob:2}" "$SCEN/blob"
run --remove
mv "$SCEN/blob" "$REPO/.git/objects/${blob:0:2}/${blob:2}"
want_rc 4
want_out 'LOOKUP_FAILED record'
want_kept "$WT"   # discriminating: a failed read counted as no entries
for script in 'exit 1' 'cat; exit 1'; do
  NAME="a bad file stops the run: a NUL check whose reader runs '$script'"
  disposables ../x
  mkdir -p "$SCEN/tr"
  printf '#!/bin/sh\n%s\n' "$script" > "$SCEN/tr/tr"
  chmod +x "$SCEN/tr/tr"
  PATH="$SCEN/tr:$PATH" run --remove
  want_rc 4
  want_out 'LOOKUP_FAILED record'
  want_kept "$WT"   # discriminating: the reader's status was ignored
done
NAME="a bad file stops the run: a NUL byte before a long file"
{ printf 'zero\000\n'; head -c 1048576 /dev/zero | tr '\000' a; printf '\n'; } > "$REPO/.worktree-disposables"
commit_file
run --remove
want_rc 2
want_out 'holds a NUL byte'
want_kept "$WT"   # discriminating: cmp exited early and tr's broken pipe read as a failed read
NAME="a bad file stops the run: a NUL byte"
printf '.build/\nnotes\000x\n' > "$REPO/.worktree-disposables"
commit_file
run --remove
want_rc 2
want_out 'holds a NUL byte'
want_kept "$WT"   # discriminating: read drops the NUL or ends the line there, and accepts the entry

# --- refusals ------------------------------------------------------------------

# --- merge-cleanup's head removal (--remove-head) ----------------------------

scenario "--remove-head removes the clean worktree at the head, with no base test"
# feat is not merged into origin/main: the caller vouches for the oid.
TIP=$(git -C "$REPO" rev-parse feat)
G "$REPO" worktree add -b other "$SCEN/other"
run --remove-head feat --head-oid "$TIP"
want_rc 0
want_out "WORKTREE removed {\"path\":\"$WT\""
want_out '"mode":"remove-head"'
want_out '"removed":1,"kept":0'
case "$OUT" in *"$SCEN/other"* | *"WORKTREE primary"*) bad "printed a worktree on another branch" ;; *) ok ;; esac
want_removed "$WT"
want_kept "$SCEN/other"

scenario "--remove-head keeps a dirty head worktree"
TIP=$(git -C "$REPO" rev-parse feat)
printf 'secret\n' > "$WT/.env"
run --remove-head feat --head-oid "$TIP"
want_rc 0
want_out 'WORKTREE dirty {"path":"'"$WT"'"'
want_out '"ignored":[".env"]'
want_out 'not clean; --remove-head removes only a clean worktree'
want_kept "$WT"

scenario "--remove-head removes a worktree whose only ignored file is a .DS_Store"
TIP=$(git -C "$REPO" rev-parse feat)
ignore .DS_Store
: > "$WT/.DS_Store"
run --remove-head feat --head-oid "$TIP"
want_rc 0
want_out "WORKTREE removed {\"path\":\"$WT\""
want_removed "$WT"   # discriminating: skipping the built-in rule under --remove-head keeps it

scenario "--remove-head reads no disposables file"
disposables .build/
ignore .build/
TIP=$(git -C "$REPO" rev-parse feat)
mkdir "$WT/.build"
printf 'o\n' > "$WT/.build/obj.o"
run --remove-head feat --head-oid "$TIP"
want_rc 0
want_out '"disposables":[]'
want_out 'WORKTREE dirty'
want_kept "$WT"   # discriminating: a copy that reads origin/main's file removes it

scenario "--remove-head keeps a branch that moved past the head"
TIP=$(git -C "$REPO" rev-parse feat)
printf 'g\n' > "$WT/g.txt"
G "$WT" add .
G "$WT" commit -m "after the merge"
run --remove-head feat --head-oid "$TIP"
want_rc 0
want_out 'WORKTREE moved {"path":"'"$WT"'"'
want_out "not the merged head $TIP"
want_kept "$WT"

scenario "--remove-head keeps the worktree that holds the caller's directory"
TIP=$(git -C "$REPO" rev-parse feat)
mkdir "$WT/sub"
run --remove-head feat --head-oid "$TIP" --caller-dir "$WT/sub"
want_rc 0
want_out 'WORKTREE self {"path":"'"$WT"'"'
want_out "the caller's directory $WT/sub is inside it"
want_kept "$WT"

scenario "--caller-dir protects a worktree in the owner's sweep too"
land feat
run --remove --caller-dir "$WT"
want_rc 0
want_out 'WORKTREE self {"path":"'"$WT"'"'
want_kept "$WT"

scenario "--remove-head usage errors"
TIP=$(git -C "$REPO" rev-parse feat)
run --remove-head feat
want_rc 64
run --head-oid "$TIP"
want_rc 64
run --remove-head feat --head-oid "$TIP" --base origin/main
want_rc 64
run --remove-head feat --head-oid "$TIP" --remove
want_rc 64
run --remove-head feat --head-oid "$TIP" --remove-landed
want_rc 64
run --remove-head feat --head-oid "${TIP:0:12}"
want_rc 64
run --remove-head feat --head-oid "$(printf '%s' "$TIP" | tr a-f A-F)"
want_rc 64
run --remove-head feat --head-oid "$TIP" --caller-dir "$SCEN/missing"
want_rc 4
want_kept "$WT"

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

scenario "--remove-landed with --remove or --remove-dirty is a usage error"
land feat
run --remove-landed --remove
want_rc 64
want_out 'Usage:'
run --remove --remove-landed
want_rc 64
run --remove-landed --remove-dirty
want_rc 64
run --remove --remove-dirty --remove-landed
want_rc 64
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
want_out '--remove-landed'
want_out '--remove-head'

# --- large listings ------------------------------------------------------------
# The bounds are generous: these finish in seconds, and the sweep they guard
# against took many minutes.

scenario "an undeclared ignored directory of 36,000 files is listed once"
ignore big/
land feat
TIP=$(git -C "$REPO" rev-parse feat)
mkdir -p "$WT/big/sub"
(cd "$WT/big/sub" && seq -f 'f%05g' 1 36000 | xargs touch)
SECONDS=0
run
if [ "$SECONDS" -lt 30 ]; then ok; else bad "the dry run took ${SECONDS}s"; fi
want_rc 0
want_out 'WORKTREE dirty {"path":"'"$WT"'"'
want_out '"ignored":["big/"],"flagged":[]'   # discriminating: --ignored lists every file
SECONDS=0
run --remove-head feat --head-oid "$TIP"
if [ "$SECONDS" -lt 30 ]; then ok; else bad "--remove-head took ${SECONDS}s"; fi
want_rc 0
want_out 'WORKTREE dirty {"path":"'"$WT"'"'
want_out '"ignored":["big/"],"flagged":[]'
want_kept "$WT"

scenario "a worktree of 20,000 untracked files is read in seconds"
land feat
(cd "$WT" && seq -f 'an-untracked-file-%05g.txt' 1 20000 | xargs touch)
SECONDS=0
run
# Discriminating: the old sweep forked per character and copied the list per path.
if [ "$SECONDS" -lt 30 ]; then ok; else bad "the dry run took ${SECONDS}s"; fi
want_rc 0
want_out '"untracked":["an-untracked-file-00001.txt","an-untracked-file-00002.txt",'
want_out '"an-untracked-file-20000.txt"],"modified":[]'
want_kept "$WT"

scenario "a declared disposable inside an undeclared ignored directory keeps it dirty"
# The accepted cost of listing a matched directory once: out/ hides the
# __pycache__/ inside it, so the worktree reads dirty where it once read clean.
disposables __pycache__/
ignore out/ __pycache__/
land feat
mkdir -p "$WT/out/__pycache__"
: > "$WT/out/__pycache__/x.pyc"
run --remove
want_rc 0
want_out 'WORKTREE dirty {"path":"'"$WT"'"'
want_out '"ignored":["out/"],"flagged":[],"disposable":[]'
want_kept "$WT"

scenario "an undeclared ignored directory of empty directories leaves it clean"
ignore build/
land feat
mkdir -p "$WT/build/sub"
run --remove
want_rc 0
want_out '"ignored":[],"flagged":[],"disposable":[]'   # discriminating: listing every dir/ record keeps it
want_out "WORKTREE removed {\"path\":\"$WT\""
want_removed "$WT"

echo "merge-cleanup sweep matrix: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
