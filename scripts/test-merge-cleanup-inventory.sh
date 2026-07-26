#!/usr/bin/env bash
# Validation matrix for skills/merge-cleanup/worktree-inventory.sh.
#
# Every case here is a hazard that was reproduced against real git before the
# rule existed: the four imported from #83's evidence, plus the five review
# findings on #98 that the prose version of this inventory drew. A case that
# only passes is not enough, so the ones marked "discriminating" were also run
# against degraded copies of the script (flag-only, presence-only, and a
# line-wise unanchored read) and fail against them. Where a case does not
# discriminate, the comment says so rather than implying coverage it lacks.
#
# Usage: test-merge-cleanup-inventory.sh
# Exit codes: 0 all passed, 1 a case failed.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT="$ROOT/skills/merge-cleanup/worktree-inventory.sh"
TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

PASS=0
FAIL=0
SCEN=""
NAME=""

G() { local d="$1"; shift; git -C "$d" "$@" >/dev/null 2>&1; }

scenario() { # scenario <name>: a fresh repo with a linked worktree at $WT
  NAME="$1"
  SCEN=$(mktemp -d "$TMP/scen.XXXXXX")
  REPO="$SCEN/repo"
  WT="$SCEN/wt"
  git init -q -b main "$REPO"
  mkdir -p "$REPO/sub"
  printf 'a\n' > "$REPO/a.txt"
  printf 'b\n' > "$REPO/sub/b.txt"
  printf '.env\n' > "$REPO/.gitignore"
  G "$REPO" add .
  G "$REPO" commit -m seed
  G "$REPO" branch feat
  G "$REPO" worktree add "$WT" feat
}

run() { # run <args...>: captures OUT and RC
  OUT=$("$SUT" "$@" 2>&1)
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

# --- the clean baseline ------------------------------------------------------

scenario "a clean worktree reports OK"
run "$WT"
want_rc 0
want_out 'OK inventory'
if [ -d "$WT" ]; then ok; else bad "the inventory removed something"; fi

# --- status-visible state ----------------------------------------------------

scenario "an untracked file is hidden state"
printf 'scratch\n' > "$WT/untracked.txt"
run "$WT"
want_rc 2
want_out 'STOP dirty'

scenario "an ignored file is hidden state: git's own refusal misses it"
printf 'secret\n' > "$WT/.env"
run "$WT"
want_rc 2
want_out 'STOP dirty'

scenario "status.showUntrackedFiles=no cannot switch the guard off"
printf 'secret\n' > "$WT/.env"
printf 'scratch\n' > "$WT/untracked.txt"
G "$REPO" config status.showUntrackedFiles no
run "$WT"
want_rc 2
want_out 'STOP dirty'   # discriminating: a plain --porcelain read is empty here

# --- index-flagged state -----------------------------------------------------

scenario "an assume-unchanged edit is hidden state"
G "$WT" update-index --assume-unchanged a.txt
printf 'EDITED\n' > "$WT/a.txt"
run "$WT"
want_rc 2
want_out 'STOP flagged'

scenario "a skip-worktree edit is hidden state"
G "$WT" update-index --skip-worktree a.txt
printf 'EDITED\n' > "$WT/a.txt"
run "$WT"
want_rc 2
want_out 'STOP flagged'

scenario "an assume-unchanged deletion is hidden state"
G "$WT" update-index --assume-unchanged a.txt
rm "$WT/a.txt"
run "$WT"
want_rc 2
want_out 'STOP flagged'   # discriminating: a presence-only filter drops this

scenario "a skip-worktree deletion outside a sparse checkout is hidden state"
G "$WT" update-index --skip-worktree sub/b.txt
rm "$WT/sub/b.txt"
run "$WT"
want_rc 2
want_out 'STOP flagged'   # discriminating: absence alone would exempt it

scenario "a sparse checkout's absent paths are not hidden state"
G "$WT" sparse-checkout set --no-cone /a.txt
if [ -e "$WT/sub/b.txt" ]; then bad "the sparse fixture left the excluded path present"; fi
run "$WT"
want_rc 0
want_out 'OK inventory'   # discriminating: a flag-only filter stops here

scenario "an ordinary cached file is not hidden state"
run "$WT"
want_rc 0
want_out 'OK inventory'   # discriminating: an unfiltered ls-files read stops here

# --- path handling -----------------------------------------------------------

scenario "a flagged path holding a newline is reported by its real name"
printf 'x\n' > "$WT/$(printf 'odd\nname')"
G "$WT" add .
G "$WT" commit -m odd
G "$WT" update-index --assume-unchanged "$(printf 'odd\nname')"
printf 'EDITED\n' > "$WT/$(printf 'odd\nname')"
run "$WT"
want_rc 2
want_out 'STOP flagged'
# Discriminating on the reported path, not on the verdict: a non-`z` read
# names the C-quoted spelling (\"odd\\nname\"), which is what the caller would
# hand the user to go look at.
want_out 'starting with odd\nname'

scenario "a flagged dangling symlink is still found"
ln -s nowhere "$WT/link"
G "$WT" add .
G "$WT" commit -m link
G "$WT" update-index --assume-unchanged link
rm "$WT/link" && ln -s elsewhere "$WT/link"
run "$WT"
want_rc 2
want_out 'STOP flagged'
# Not discriminating on the verdict: with the deletion rule below, a path read
# that misses the file counts the row as a hidden deletion, so the failure
# direction is over-reporting. Pinned so a later refactor cannot go back to
# exempting what it cannot see.

scenario "a flagged path is resolved against the worktree, not the caller"
( cd "$WT" && printf 'only\n' > only-on-feat.txt && git add . \
  && git commit -qm only && git update-index --assume-unchanged only-on-feat.txt \
  && printf 'EDITED\n' > only-on-feat.txt ) >/dev/null 2>&1
( cd "$REPO" && "$SUT" "$WT" >/dev/null 2>&1 )
RC=$?
OUT=$( cd "$REPO" && "$SUT" "$WT" 2>&1 )
want_rc 2
want_out 'STOP flagged'   # over-reports rather than vanishes; see the note above

scenario "a worktree whose path ends in a newline is not confused with its sibling"
NL="$SCEN/wt"$'\n'
G "$REPO" worktree add "$NL" -b feat-nl
printf 'hidden\n' > "$NL/untracked.txt"
run "$NL"
want_rc 2
# Discriminating: a plain $( ) around --show-toplevel strips the trailing
# newline, so the clean sibling at $WT answers for the dirty target and the
# caller removes the wrong directory on an OK verdict.
want_out 'STOP dirty'

scenario "a sparse checkout spelled with a non-canonical boolean is still sparse"
G "$WT" sparse-checkout set --no-cone /a.txt
G "$WT" config --worktree core.sparseCheckout yes
run "$WT"
want_rc 0
want_out 'OK inventory'   # discriminating: `--get` returns yes, not true

scenario "a subdirectory argument is inventoried as its worktree"
G "$WT" update-index --assume-unchanged sub/b.txt
printf 'EDITED\n' > "$WT/sub/b.txt"
run "$WT/sub"
want_rc 2
want_out 'STOP flagged'

# --- refusals ----------------------------------------------------------------

scenario "the worktree the command runs in is never inventoried for removal"
OUT=$( cd "$WT" && "$SUT" "$WT" 2>&1 )
RC=$?
want_rc 2
want_out 'STOP self-target'

scenario "a path that is not a worktree fails the lookup rather than reporting clean"
run "$SCEN"
want_rc 4
want_out 'LOOKUP_FAILED worktree'   # a failed read is not an established absence

scenario "a missing argument is a usage error, not a clean report"
OUT=$("$SUT" 2>&1 >/dev/null); RC=$?
want_rc 0   # --help default prints usage on stdout and exits 0
run "$WT" extra
want_rc 64

echo "merge-cleanup inventory matrix: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
