# Merge-Cleanup Removes the Merged Branch's Clean Worktree

Chose to have `merge-cleanup.sh` remove the linked worktree that holds the
merged head branch, when it's clean, over stopping `head-worktree-present`
for the owner every time. The owner asked for it on 2026-11-18, after the
lander's default sweep (`2026-11-18-1944-default-landed-sweep.md`) left the
standalone cleanup as the one path that still always stopped.

This revises two earlier decisions, for clean head worktrees only:

- **`2026-08-20-1451-merge-cleanup-orchestration.md`** stopped because no Git
  primitive couples a clean inventory with removal, and said to revisit
  automatic removal when one exists. None exists yet. The 2026-11-18 lander
  note accepted the same race for clean worktrees: the sweep rechecks right
  before removal, which narrows the window but can't close it. This note
  accepts it on the same terms.
- **`2026-10-18-1846-worktree-sweep.md`** rejected removal inside
  merge-cleanup because it "would make every cleanup request a deletion
  request." Removing a clean worktree deletes the checkout and little else,
  the reason the lander note gave for revising the same rule; Accepted Risks
  names the rest.

## Decisions

- **The sweep owns the clean test.** Chose a new `--remove-head` mode in
  `worktree-sweep.sh`, which takes the branch and `--head-oid`, over a second
  clean check in `merge-cleanup.sh`. Every guard the sweep's refute-first review added
  (ignored and index-flagged files, submodules, nested repositories, nested
  worktrees, locks, redirection, the recheck) applies without a copy.
- **The merged head replaces the landing-merge test.** `--remove-landed`
  needs a landing merge to tell a landed branch from a fresh one cut at the
  base tip. Here the caller already verified on the forge that the PR merged
  at this exact head, so the branch must sit at that oid and nothing else.
  Squash and rebase merges qualify too, which `--remove-landed` can't see.
- **The session's own directory is never removed.** A standalone cleanup is
  usually run by the session that wrote the PR, often from inside the head
  worktree. `merge-cleanup.sh` reads its starting directory before it moves
  to `--checkout` and passes it as `--caller-dir`; the sweep reports the
  worktree holding it as `self` and keeps it. The skill tells the agent to
  run the script from its own directory so the guard sees it.
- **Removal ends the preflight.** Chose that over removing at the
  local-branch step, so a kept worktree still stops the run before any
  mutation, not after the remote delete. It runs after the remote checks
  and the read-only base-landing plan, so a run that another read-only
  guard stops has removed nothing. A refused checkout of the base can still
  follow a removal; it can't be checked in advance.
- **The owner can opt out per run.** `--keep-worktree` restores the old stop,
  matching the lander's "skip it when the owner says not to sweep."
- **The lander inherits it.** A batch's merge-cleanup now removes a landed
  clean head worktree during the batch, so a stack parent's children
  retarget in the same run instead of after the end-of-batch sweep. The
  lander's own "never remove a worktree" rule now names merge-cleanup as the
  one exception.

## Accepted Risks

- **Another live session in the head worktree loses its directory.** The
  caller guard protects only the session that runs the cleanup. The lander
  note accepted the same risk; the work there is merged.
- **An ignored file written between the recheck and removal is lost.** That
  needs a process writing into a merged branch's worktree at that moment.
- **A commit held only by the worktree's own refs or reflog is lost.** The
  clean test doesn't read `refs/worktree/*`, `refs/bisect/*`, or the
  worktree's HEAD reflog, so a commit made in the merged worktree and then
  reset away goes with it; `git fsck` finds it until gc. The lander note
  allowed the reflog case for `--remove-landed`, and reaching it takes the
  same deliberate detour. The refute-first reviewer reproduced both.

Revisit when Git gains a removal that leases a clean inventory, or when
cleanups commonly run while another session works in the merged worktree.
