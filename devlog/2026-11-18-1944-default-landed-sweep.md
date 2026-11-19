# Sweep Landed Branches' Clean Worktrees at the End of Every Landing Batch

Chose to have the lander end every batch with
`worktree-sweep.sh --remove-landed` over keeping all worktree removal
owner-run. Issue #400 carries the contract. This revises one decision in
`2026-10-18-1846-worktree-sweep.md`, "Owner-run, never on a normal path,"
for clean worktrees of landed branches only; its other rules stand.

## What Changed

- **The owner asked for the default on 2026-11-18.** Session logs from
  2026-11-05 to 2026-11-18 show 12 of 34 landing sessions ending in an
  explicit sweep request, 11 of them worded "sweep clean worktrees." None
  asked for dirty worktrees.
- **The old reason doesn't reach clean worktrees.** The 2026-10-18 rule rested
  on `git worktree remove` deleting ignored and index-flagged files. The sweep
  calls a worktree clean only when it has none of those, no untracked or
  modified file, no paused operation, and no detached HEAD that no ref holds.
  Removing a clean one loses only the checkout.

## Decisions

- **Removal needs the landing merge, not just ancestry.** Chose a new
  `--remove-landed` rule over reusing `--remove`, which removes every clean
  ancestor branch. A branch cut from the base tip with no commits passes the
  ancestry test, and before its first edit it's clean too: a T3 thread, a
  `plan-and-handle-batch` implementer, or any session that has made its
  worktree but not yet written a file. Such a branch points at a commit on the
  base's first-parent line, never at a merge's second parent, so
  `find_landing` reports no landing merge and the worktree stays. The cost is
  that fast-forward projects get no default sweep; that's intended.
- **Detached `land-wt` worktrees stay manual.** The sweep runs after the lock
  is released, so another lander can start in that gap. It works in a detached
  `land-wt` worktree or on an unmerged branch, and `--remove-landed` removes
  neither. A dead lander's leftover `land-wt` worktree is therefore still the
  owner's, through the manual sweep.
- **The sweep runs after release, not before.** The normal end is an empty
  fresh list, and that same `list-ready.sh` call releases the lock, so the
  lander learns the batch is over only once the lock is gone. Sweeping under
  the lock would need a new `list-ready.sh` mode, which this unit leaves
  unchanged. The detached-worktree rule makes the order safe instead. The
  lander skips the sweep after `lock-lost`, `lock-held`, or `lock-stale`,
  since another lander may be live.
- **`--remove-landed` stands alone.** It's a narrower rule, not a widening of
  `--remove`, so combining it with `--remove` or `--remove-dirty` is a usage
  error. The lander never passes either; what the default keeps is the
  owner's to remove.
- **Merge-cleanup reruns after the sweep.** A PR whose cleanup stopped
  `head-worktree-present` gets its local branch deleted and stacked children
  retargeted once its worktree is gone, so a clean stack parent no longer
  waits on the owner.

## Accepted Risks

- **A live session in a landed worktree loses its directory.** A thread whose
  PR landed, in this batch or an earlier one, may still be open there. The
  owner's manual sweeps already do this, and the thread's work is merged.
- **A branch cut at a landed tip borrows its landing merge.** A new branch
  made from a merged branch's tip is credited with that merge, so if it's
  clean, `--remove-landed` removes it even if a session just started in it.
  Topology can't tell the two apart; the 2026-10-18 note allows the same case
  for dirty removal.

## Refute-First Findings

A fresh-context reviewer tried to make `--remove-landed` remove something
outside its contract, or change another mode, reproducing each claim with
real git. It confirmed no defect.

- **Disproved: state leaking between worktrees.** `classify` resets
  `C_LANDED` for every worktree, and a detached one never sets it.
- **Disproved: flag combinations.** Every order of `--remove-landed` with
  `--remove` or `--remove-dirty` exits 64.
- **Disproved: changes between passes.** A worktree that gains a file, a
  staged edit, a bisect, or a commit, or that switches to a fresh branch,
  detaches, or locks before its removal is kept.
- **Disproved: other modes changed.** On a mixed fixture, the dry run,
  `--remove`, and `--remove --remove-dirty` print the same lines as the
  sweep at `39b8b54`.
- **Disproved: a concurrent lander's worktrees.** `land` creates its rebase
  worktree detached, and its head branch is unmerged; both are kept.
- **Allowed: a commit held only in a worktree's HEAD reflog is lost.** A
  commit made on a detached HEAD, then left by switching back to the landed
  branch, becomes unreachable when the worktree goes; `git fsck` finds it
  until gc. `--remove` has always done this, and the clean test is shared
  with it. The batch now does it unattended, but reaching this state takes a
  deliberate detour in an already-landed worktree.
- **Allowed: the recheck follows a branch switch.** A worktree that moves to
  another landed, clean branch between passes is removed, and its line names
  the new branch. That still meets every removal condition.
- **Allowed: a long-lived branch's checkout can go.** A clean worktree of a
  branch such as `develop`, just merged into the base with a merge commit,
  is landed by this test and removed. Nothing is lost but the checkout.

Revisit when a project that lands by fast-forward wants a default sweep, or
when sessions commonly start work on a branch cut from a landed tip.
