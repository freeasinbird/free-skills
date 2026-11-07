# Drop the Fork Auto-Delete Stop

The owner chose on 2026-11-07 to remove `land.sh`'s `fork-auto-delete` stop
rather than turn off auto-delete or merge by hand, because the only PRs it
protects are PRs in other people's forks, and the owner doesn't want to
protect those. Issue #375 carries the contract.

This reverses the keep-the-stop decision recorded in
`2026-07-24-2311-self-merge-resync-guards.md` and reaffirmed in
`2026-10-15-0959-self-merge-hands-off-cleanup.md` and
`2026-10-18-1825-stacked-prs-report.md`.

## What Changed

Those notes treated a PR in another fork as a consumer worth a full stop: a
fork's PR can use one of our branches as its head, no repository-scoped query
can list every such PR, and the forge's auto-delete removes the branch before
merge-cleanup's consumer checks run. That reasoning still holds. What changed
is the owner's weighting of the harm.

The stop fired on the existence of a fork, not on a PR at risk. On
2026-11-07 a stranger forked `freeside-ai/freeside`; the fork had no open
PRs, yet every approved PR in a landing batch stopped. The owner wants
auto-delete on and said plainly that PRs in forks aren't their concern.

## Decisions

- **Remove the stop, not narrow it.** A narrower stop that lists open PRs in
  each direct fork was rejected: forks of forks are still unlisted, so it
  keeps the complexity without closing the gap, and it guards a case the
  owner doesn't want guarded.
- **No per-project switch.** A landing-record field to restore the stop was
  rejected as speculative. A project that wants fork PRs protected can turn
  auto-delete off; merge-cleanup then checks branch consumers before it
  deletes.
- **What is given up.** With auto-delete on, merging can close a PR in
  another fork that uses one of our branches as its head. This applies both
  to a root repository with forks and to a repository that is itself a fork,
  where sibling forks go unchecked.
- **What stays.** `shared-head` still stops a merge when another open PR in
  this repository, or in a fork base's parent and root, uses the branch as
  its head. `stacked-prs` still stops a cross-repository head with stacked
  children. Same-repository stacked PRs are still retargeted.

## Refute-First Findings

A fresh-context review tried to prove the removal wrong.

- **Confirmed and fixed:** a comment in the merge phase still described the
  removed auto-delete refresh, and deleting the guard's scenarios would have
  dropped the only `merge`-phase test of a cross-repository head on a fork
  base passing `consumer_checks`. That scenario stays as a positive case.
- **Disproved by checks:** no code outside the removed lines read
  `forks_count` or `delete_branch_on_merge`; the repository-facts `jq` list
  and `read` still align field for field; the final-boundary reload is still
  tested through `queue_message_check`; and the two new guard scenarios fail
  against the old engine.

Revisit when a project that relies on contributions from forks wants their
PRs protected while keeping auto-delete on.
