#!/usr/bin/env bash
# pre-push-clean-worktree.sh: an optional git pre-push hook that refuses a
# push from a linked worktree holding modified or untracked files, naming
# them. A pushed worktree with leftovers is one the worktree sweep keeps, and
# the leftovers are often work that belongs in the PR. Ignored files pass:
# the project's ignore rules and its worktree disposables record decide what
# happens to those. The primary checkout always passes, since it is the
# owner's own working copy.
#
# Install by copying it, executable, to the path that
# `git rev-parse --git-path hooks/pre-push` prints. Never copy it over an
# existing hook. references/audit.md §clean-push-hook gives the rule.
#
# Exit codes:
#   0   the push may go ahead
#   1   refused: the files are named on stderr, or status could not be read
set -u

# git writes the refs being pushed on stdin. Read them all, so git never
# meets a closed pipe.
cat > /dev/null

git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) \
  || { echo "pre-push-clean-worktree: could not resolve the git directory" >&2; exit 1; }
common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || { echo "pre-push-clean-worktree: could not resolve the common git directory" >&2; exit 1; }
[ "$git_dir" != "$common_dir" ] || exit 0

# -uall so status.showUntrackedFiles=no cannot hide a file, and
# core.fsmonitor=false so the check runs no configured hook of its own.
tmp=$(mktemp) || { echo "pre-push-clean-worktree: mktemp failed" >&2; exit 1; }
trap 'rm -f "$tmp"' EXIT
git -c core.fsmonitor=false status --porcelain -uall -z > "$tmp" 2>/dev/null \
  || { echo "pre-push-clean-worktree: could not read the worktree's status; push refused" >&2; exit 1; }
[ -s "$tmp" ] || exit 0

{
  echo "pre-push-clean-worktree: push refused; this worktree holds files git status reports:"
  skip=false
  while IFS= read -r -d '' rec; do
    # A rename or copy record is followed by its source path.
    if [ "$skip" = true ]; then skip=false; continue; fi
    echo "  $rec"
    case "${rec:0:2}" in R? | C? | ?R | ?C) skip=true ;; esac
  done < "$tmp"
  echo "Commit what belongs in the PR, and move scratch files to the session workspace."
} >&2
exit 1
