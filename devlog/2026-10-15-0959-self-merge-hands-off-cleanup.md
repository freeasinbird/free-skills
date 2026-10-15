# Self-Merge Hands Post-Merge Cleanup to merge-cleanup

Chose to end `self-merge.sh` at the merge and hand everything after it to the
merge-cleanup skill, over keeping a second cleanup implementation in
`self-merge.sh`. The two scripts implemented the same post-merge sequence with
separate guards, and `devlog/2026-07-26-1047-merge-cleanup-imported-guards.md`
records fixes ported by hand between them and one defect introduced that way.
Self-merge's prose already reused merge-cleanup's non-Git stages, so half the
handoff existed. Issue #306 carries the contract; the owner decided the points
below there.

## Decisions

- **Revised, not overturned: "Keep `self-merge` separate"
  (`devlog/2026-08-20-1451-merge-cleanup-orchestration.md`).** That decision
  rejected one policy-flag executor doing both merge and cleanup, because it
  would couple two contracts and make the safer path harder to review. A
  sequential handoff at the merge boundary is a different shape: each script
  keeps one contract, and the boundary is the forge reporting `MERGED`. The
  reasons that note listed for separation were the merge and check phases,
  the pre-merge queue and fork-network policy, stacked-consumer timing, and
  the `kept_manual` local-branch disposition. The first three still belong to
  self-merge's pre-merge phases. The `kept_manual` reason is withdrawn with the
  rest; see the local-branch disposition below.
- **Closed: the "divergences that remain deliberate" of the 2026-07-26 note.**
  Stacked PRs now follow merge-cleanup: it retargets each open child PR onto
  the base, verifies the new base, then deletes the branch. Self-merge's
  post-merge `stacked-prs` stop, which asked for a hand-confirmed retarget
  before the delete, went with the phase; its pre-merge consumer check still
  refuses to merge while an open PR stacks on the head. A retarget is
  reversible, and the delete behind it keeps its OID and lease guards. The dirty-tree order was already settled in `merge-cleanup.sh`: its
  `workspace_preflight` runs after loading PR facts and before base landing,
  resync, and the remote delete, pinned by "dirty preflight preserves refs" in
  `scripts/test-merge-cleanup.sh`. Nothing moved.
- **Local head branch: deleted, not `kept_manual`.** Merge-cleanup
  compare-and-deletes it at the forge-verified OID with `git update-ref -d`
  and retains `branch.<name>` config. Self-merge kept it because Git has no
  portable delete that combines an expected-old OID with the checked-out
  worktree guard; merge-cleanup's `head-worktree-present` stop runs before
  any mutation and covers the worktree half of that concern.
- **Fork head branch: deleted behind merge-cleanup's guards.** Self-merge kept
  and reported a fork branch. Merge-cleanup deletes it in the fork behind its
  OID, consumer, and lease guards ("fork PR deletes the fork remote only" in
  `scripts/test-merge-cleanup.sh`). Self-merge's pre-merge `fork-auto-delete`
  stop in `check` and `merge` stays: it protects consumers that the forge's
  auto-delete would remove before any cleanup guard runs.
- **Linked head worktree: unchanged.** Both scripts stop
  `head-worktree-present` and leave removal to the owner.
- **Authority: a self-merge request grants merge-cleanup's cleanup for the PR
  it merged.** Self-merge is already the opt-in override of the stop-at-open-PR
  default; the cleanup is the same grant. The sentences in
  `skills/self-merge/SKILL.md` that forbade running `merge-cleanup.sh` from a
  self-merge request are deleted. Issue closure and tracker writes still need
  their own authority, as merge-cleanup's reconciliation procedure requires.
- **Guards that `land` shares with the removed phase keep their coverage.**
  The cleanup matrix cases for remote identity (`remote-repo-mismatch`,
  `pushurl-mismatch`, `remote-unresolved`, the ssh host-alias stops and the
  alias endpoint pin) are re-expressed through `land` on a behind head, which
  reaches the same `remote_repo_check` and `push_ids_match` calls before its
  lease push. Cases that only tested the deleted delete path (OID and consumer
  rechecks at delete time, `kept_fork_network`, worktree preservation
  inventory, branch-conditioned remotes across the resync checkout) are
  dropped; merge-cleanup's matrix owns those paths.
- **Merge-cleanup's presence is a pre-merge guardrail, not an assumption.**
  Issue #306 deferred the case of self-merge installed without merge-cleanup,
  but the README's per-skill install (`npx skills add ... --skill self-merge`)
  makes it ordinary, and a companion found missing after the irreversible
  merge leaves no guarded cleanup. `SKILL.md` now confirms the companion and
  runs its Check Prerequisites before `land`, and stops at the open PR when
  either fails. Rejected: bundling merge-cleanup's executor with self-merge,
  which restores the duplication this unit removes. Found by the automated
  review of PR 308.
- **`OK merge` still prints only `merged_at`.** The contract's acceptance
  line says `OK merge` reports the merged head OID; it never did, since
  `--head` is that OID and `merge` is a non-goal here. Left as is.

## Refute-First Findings

A fresh-context reviewer read the diff with instructions to prove it wrong.

- **Confirmed: ssh alias auto-resolution lost its only test.** Every
  re-expressed alias case passed `--head-remote alias`, which bypasses the
  `ssh_alias_resolve` retry inside `resolve_remote`. Fixed by re-adding the
  auto-resolve case through `land` with no remote overrides.
- **Confirmed: stale text named guards the phase took with it.** The
  `SKILL.md` guard list claimed tag shadowing (the removed `detached` stop),
  two comments described the cleanup phase's scan and rewrite, and one
  scenario name said "lease delete". All reworded.
- **Disproved: the re-expressed identity cases could pass without the
  guards.** With `push_ids_match` forced to succeed in a scratch copy, the
  thirteen `pushurl-mismatch` cases fail, so the land path exercises the
  guard. The `lease-failed` expectation for the userinfo case discriminates
  from `remote-repo-mismatch`, and the alias pin case proves an unpinned push
  reaches the rogue mirror.
- **Disproved: the handoff case could pass on a stub.** Its gh shim serves
  every call `merge-cleanup.sh` makes, and the asserted dispositions are the
  script's real `deleted` and `resynced` values.
- **Allowed: `## 1. Merge` is the only numbered section left** in
  `references/merge-sequence.md`. The number is the contract's wording and
  keeps the section findable from older notes.

## Revisit when

- A project wants self-merge to merge without merge-cleanup installed and
  clean up by hand. The guardrail stops at the open PR instead; relaxing it
  needs a documented manual cleanup path.
