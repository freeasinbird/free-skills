# Stacked PRs Are Reported Before the Merge, Not Refused

Chose to have `land.sh`'s `check`, `land`, and `merge` report the open PRs
based on a same-repository head branch and continue, over stopping
`stacked-prs`. The stop protected a branch delete that the engine no longer
performs: since #306, merge-cleanup owns the delete, and it retargets each
same-repository child onto the base, verifies the new base, and only then
deletes. With the stop in place the lander could never land a stack's parent.
Issue #309 carries the contract.

## Decisions

- **Report in all three phases, including `land`'s rebase.** The rejected
  option kept the stop only when `land` must rebase the parent, since the
  rebase rewrites commits the child stacks on. A parent behind the base tip is
  the common case in a batch, so that option would still hand back most
  stacks. The child's own `land` rebase at its turn drops the parent's
  pre-rebase commits when their patches match what merged, and a conflict
  there is an ordinary `rebase-conflict` hand-back. A native GitHub stack
  (`gh stack`) was considered too: it must have linear history between its
  branches before it can merge, so after a parent-only rebase the parent's
  merge may stop `merge-refused`. That is a loud hand-back, not data loss,
  and the owner re-linearizes with `gh stack rebase --upstack`. GitHub's docs
  don't confirm that the merge is blocked, and nothing here can yet tell a
  native stack from an ordinary one.
- **The report is a stderr line from every phase plus `stacked_prs` on
  `OK check`.** `OK land` and `OK merge` keep their fields; the lander already
  has the numbers from `check`. The listing now returns PR numbers instead of
  a count.
- **A failed or unparseable listing stays `LOOKUP_FAILED stacked-prs`.** A
  read failure is unknown, as with every other listing in the engine.
- **Agent decision, owner may veto: a cross-repository head still stops.**
  The contract said "report" without a fork carve-out. For a fork head the
  children live in the head's repository: the forge can't retarget them onto
  this repository's base, and merge-cleanup stops `stacked-cross-repo` after
  the merge. Reporting would land the parent and then hand back at cleanup
  with the children stranded on a fork branch. Stopping before the merge keeps
  the earlier behavior for the case the contract's non-goals exclude.
- **`shared-head` and `fork-auto-delete` are unchanged.** Deleting a branch
  that heads another PR closes that PR, and an auto-delete can run before any
  cleanup guard; both still refuse.

## Refute-First Findings

`consumer_checks` runs right before the irreversible merge, so the pass tried
to show that reporting instead of stopping can delete or close a child.

- **Disproved: the merge or `land`'s push closes a child.** A merge commit
  and a lease push change the parent branch's history, not the child's base
  ref. GitHub closes a PR only when its base branch is deleted without a
  retarget.
- **Disproved: some phase deletes the branch.** `land.sh` has no branch
  delete. The deletes are merge-cleanup's, which retargets first and stops
  `stacked-retarget` when a retarget fails or doesn't take ("failed stack
  retarget preserves the remote branch" in `scripts/test-merge-cleanup.sh`),
  and the forge's auto-delete. GitHub documents that deleting a merged PR's
  head retargets same-repository children onto that PR's base. No test here
  exercises the forge's behavior; merge-cleanup's retarget still runs after an
  auto-delete ("auto-deleted head still retargets a same-repo stack").
- **Allowed: the report lists at most 30 children.** `gh pr list` defaults to
  30 rows. The field is a report, and merge-cleanup paginates its own listing
  before the delete, so a longer stack loses only report lines.
- **Disproved: a malformed listing can reach the `OK check` JSON.** The field
  is admitted only as a bracketed, comma-separated list of digits; anything
  else is `LOOKUP_FAILED stacked-prs`, pinned by the unparseable-listing case
  in `scripts/test-land.sh`.
- **Allowed: a parent in a linked worktree can land with its children left
  behind.** Without auto-delete, merge-cleanup stops `head-worktree-present`
  before it retargets, so the children stay on the merged branch and filter 2
  excludes them until the owner removes the worktree. Stopping `stacked-prs`
  for that layout was rejected: the children would stay excluded either way,
  and the parent would be handed back too. SKILL.md's Stacks section tells
  the lander to report them as waiting on the worktree.
- **Confirmed and handled: fork children can't be retargeted.** See the
  cross-repository decision above.

## Revisit When

- A forge other than GitHub runs the lander and doesn't retarget children
  when it auto-deletes a merged branch. Merge-cleanup's retarget covers only
  its own delete.
- A forge API exposes native-stack membership, or a native-stack parent is
  observed stopping `merge-refused` in a batch. Either would justify stopping
  such a parent before the rebase.
- A stack two deep lands in one batch. The middle PR is both child and parent;
  the report path covers it, but nobody has run that case.
