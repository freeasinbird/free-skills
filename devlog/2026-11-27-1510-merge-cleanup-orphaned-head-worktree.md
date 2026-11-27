# Merge-Cleanup Records a Head Worktree's Path Before Removing It

`merge-cleanup.sh` now writes the head worktree's path to a removal record
under the common git directory before `worktree-sweep.sh --remove-head` runs,
and deletes it once the removal is verified (#503). While the recorded path is
on disk and no registered worktree holds it, every run stops
`head-worktree-orphaned` before mutation. This closes the gap where a rerun
after a partial removal reported `worktree: absent` and deleted the local
branch while the half-removed directory stayed on disk.

## Decisions

- **Record before removing, not after a failure.** A record written only when
  the sweep reports `remove-failed` misses a run killed mid-removal, which
  leaves the same orphan. Writing first costs one small file per removal
  attempt.
- **The record, not the `.git` file, is the evidence.** Treating a leftover
  `.git` file that names a missing admin directory as the orphan's mark
  needs no state, but git may delete that file during the same partial
  removal (`references/hazards.md` §worktree-partial-remove), so the stop
  would fail open on exactly the case it exists for.
- **No disk scan.** Looking for orphans without a record has no bounded
  place to look: worktrees live anywhere the owner put them, and once the
  admin directory is gone nothing in the repository names the path.
- **Check on every run, whatever the head worktree's state.** The plan
  checked the record only when no worktree holds the branch. Checking first
  on every run also keeps a new worktree for the same branch from
  overwriting the record of an older orphan. A stale record, whose path is
  gone or registered again, is deleted and the run continues.
- **One file per branch, named by a hash.** The file name is
  `git hash-object` of `refs/heads/<branch>`, so any branch name maps to one
  safe file and `feat` never collides with `feat/x`. The only deletion the
  change adds is that fixed file; its path is never built from the recorded
  value.
- **The owner deletes the directory.** The script never removes the
  leftover: it's no longer a worktree, so none of the sweep's clean-worktree
  checks can judge what it holds.

Known gaps, accepted because each falls back to the behavior before this
change and deletes nothing from the orphan:

- **No record, no stop.** Orphans left before this change, and partial
  removals by `worktree-sweep.sh --remove-landed` or `--remove`, write no
  record and stay unreported (teaching the sweep is a #503 non-goal).
- **An invisible path reads as gone.** A recorded path on an unmounted
  volume, or under a parent that denies search, fails the existence test, so
  the record is cleared as stale. Telling that apart from a deleted parent
  would add a stop with no clean exit.
- **Earlier guards win.** A guard that runs before the record check, such
  as `local-branch`, can stop a rerun first. It stops before mutation too.

Revisit when `worktree-sweep.sh --remove-head` stops making a single
`git worktree remove` attempt per run, or when git stops deleting the admin
directory before the tree.
