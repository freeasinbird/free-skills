# Worktree Sweep Reads the HEAD Reflog Past a File Named HEAD

Chose to end the sweep's `git rev-list -g HEAD` call with `--` over leaving it
as is. This corrects
`2026-11-20-2235-sweep-worktree-refs-reflog.md`, which added the call without
a separator.

## Problem

A worktree with a file or directory named `HEAD` at its root makes git read
the argument as both a revision and a path. Git then exits 128 with "ambiguous
argument 'HEAD'", and the sweep stops with `LOOKUP_FAILED reflog` for the
whole run. It failed closed, so nothing was removed, but one such worktree
blocked the sweep of every other worktree. The land-approved-prs batch found
this when #488's plain-`HEAD` scenario failed after rebasing onto #487.

## Refute-First Checks

- **Same output:** in a repository without a `HEAD` file, `rev-list -g HEAD`
  and `rev-list -g HEAD --` print identical lists. The trailing `--` adds no
  path limit. Confirmed.
- **No other ambiguous call:** a search of the sweep and the other skill
  scripts found no other revision argument that a worktree file can shadow.
  The rest pass object IDs, use `rev-parse --verify`, or call
  `merge-base` or `reflog exists`, which take no pathspec. Disproved for
  every other call.
- **Detection kept:** with a tracked root `HEAD` file, a post-`HEAD` reflog
  commit still marks the worktree dirty, and a clean merged worktree is
  removed. Both new scenarios fail against the sweep before this change.
  Confirmed.
