#!/usr/bin/env bash
# Validation matrix for skills/agent-setup/scripts/pre-push-clean-worktree.sh.
#
# Every case is a real push to a bare remote. The hook is installed the way
# agent-setup's references/audit.md §clean-push-hook installs it: copied to
# the path `git rev-parse --git-path hooks/pre-push` prints, here run from the
# linked worktree, so the cases also show that every worktree shares it. Each
# refusal case asserts that the remote branch did not move; each allow case
# asserts that it now holds the pushed commit.
#
# To run it under macOS /bin/bash 3.2, put a `bash` symlink to /bin/bash
# first on PATH; the hook's shebang resolves `bash` from PATH:
#   d=$(mktemp -d) && ln -s /bin/bash "$d/bash" &&
#     PATH="$d:$PATH" ./scripts/test-agent-setup-pre-push-hook.sh
#
# Usage: test-agent-setup-pre-push-hook.sh
# Exit codes: 0 all passed, 1 a case failed.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT="$ROOT/skills/agent-setup/scripts/pre-push-clean-worktree.sh"
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
# No system or global configuration: a developer's global excludes file would
# turn an untracked case into an ignored one.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null XDG_CONFIG_HOME="$TMP/xdg" \
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

PASS=0
FAIL=0
NAME=""

G() { local d="$1"; shift; git -C "$d" "$@" >/dev/null 2>&1; }

# scenario <name>: a bare remote, a primary checkout on main, and branch feat
# one commit ahead in a linked worktree at $WT, with the hook installed.
scenario() {
  NAME="$1"
  SCEN=$(mktemp -d "$TMP/scen.XXXXXX")
  REMOTE="$SCEN/remote.git"
  REPO="$SCEN/repo"
  WT="$SCEN/wt"
  git init -q --bare -b main "$REMOTE"
  git init -q -b main "$REPO"
  printf 'a\n' > "$REPO/a.txt"
  printf '.env\n' > "$REPO/.gitignore"
  G "$REPO" add .
  G "$REPO" commit -m seed
  G "$REPO" remote add origin "$REMOTE"
  G "$REPO" push -q origin main
  G "$REPO" worktree add -b feat "$WT"
  printf 'f\n' > "$WT/f.txt"
  G "$WT" add f.txt
  G "$WT" commit -m "feat work"
  local hook
  hook=$(cd "$WT" && git rev-parse --git-path hooks/pre-push) || { bad "no hook path"; return; }
  mkdir -p "$(dirname "$hook")"
  cp "$SUT" "$hook"
  chmod +x "$hook"
}

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $NAME: $1"; }

push() { # push <dir> <branch>: push it to origin from <dir>
  OUT=$(git -C "$1" push -q origin "$2" 2>&1)
  RC=$?
}

want_rc() {
  if [ "$RC" -eq "$1" ]; then ok; else bad "exit $RC, wanted $1 (got: $OUT)"; fi
}
want_refused() {
  if [ "$RC" -ne 0 ]; then ok; else bad "the push went through (got: $OUT)"; fi
}
want_out() {
  case "$OUT" in
    *"$1"*) ok ;;
    *) bad "output lacks '$1' (got: $OUT)" ;;
  esac
}
want_remote() { # want_remote <branch> <dir>: the remote holds <dir>'s HEAD
  local want got
  want=$(git -C "$2" rev-parse HEAD)
  got=$(git -C "$REMOTE" rev-parse --verify --quiet "refs/heads/$1")
  if [ "$got" = "$want" ]; then ok; else bad "remote $1 is '${got:-absent}', wanted $want"; fi
}
want_no_remote() { # want_no_remote <branch>
  if git -C "$REMOTE" rev-parse --verify --quiet "refs/heads/$1" >/dev/null; then
    bad "the remote has $1"
  else
    ok
  fi
}

scenario "a clean linked worktree pushes"
push "$WT" feat
want_rc 0
want_remote feat "$WT"

scenario "an untracked file in a linked worktree refuses the push and is named"
printf 'scratch\n' > "$WT/scratch.txt"
push "$WT" feat
want_refused
want_out 'push refused'
want_out '?? scratch.txt'
want_no_remote feat

scenario "a modified file in a linked worktree refuses the push"
printf 'EDITED\n' > "$WT/a.txt"
push "$WT" feat
want_refused
want_out ' M a.txt'
want_no_remote feat

scenario "a staged rename is named once, by its new path"
G "$WT" mv f.txt g.txt
push "$WT" feat
want_refused
want_out 'R  g.txt'
case "$OUT" in *"  f.txt"*) bad "the rename's source was listed as a file" ;; *) ok ;; esac
want_no_remote feat

scenario "an untracked file hidden by status configuration still refuses the push"
G "$WT" config status.showUntrackedFiles no
mkdir "$WT/notes"
printf 'n\n' > "$WT/notes/n.txt"
push "$WT" feat
want_refused
want_out '?? notes/n.txt'   # discriminating: plain status shows nothing
want_no_remote feat

scenario "a linked worktree holding only ignored files pushes"
printf 'secret\n' > "$WT/.env"
push "$WT" feat
want_rc 0
want_remote feat "$WT"

scenario "the primary checkout pushes with an untracked file"
printf 'mine\n' > "$REPO/notes.txt"
printf 'b\n' > "$REPO/b.txt"
G "$REPO" add b.txt
G "$REPO" commit -m "more main"
push "$REPO" main
want_rc 0
want_remote main "$REPO"

echo "pre-push hook matrix: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
