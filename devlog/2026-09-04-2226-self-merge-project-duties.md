# Account for Project Duties After Self-Merge

Issue #244 adds a bounded project-duty handoff before self-merge's final
report. Git cleanup success doesn't establish that issue-close checks or
documented tracker work ran.

## Decision

Use the project's existing authorized procedure, or the relevant non-Git
stages of an available skill. Keep both Git executors unchanged and
independently installable. A project-local procedure needs no companion
skill or new obligation schema.

The [orchestration decision](2026-08-20-1451-merge-cleanup-orchestration.md)
keeps policy in prose and the executors separate. Reusing `merge-cleanup.sh`
would import different fork, local-branch, and stacked-PR policies. Its
reconciliation procedure can be reused only with its own evidence and ledger
requirements, plus authority applicable to the current task.

A successful merge, self-merge request, or issue mention grants no new tracker
or issue-closing authority. Existing task or project authority still applies
without reconfirmation. Issue-close verification observes outcomes; an open
closing target remains an owner action unless closure is separately authorized.

Discover policy from a fresh immutable base revision, including after a
cleanup STOP before resync. Readable absence adds no tracker machinery.
Unreadable policy leaves a named gap. A project procedure's own prerequisites
still control whether a duty can run after a Git stop.

Recheck that policy revision before each project mutation and the final duty
report. A project-local procedure can omit freshness checks while its only
tracker grant comes from base policy. A concurrent base change can revoke
that grant. Use an existing procedure's equivalent or stricter checks once;
otherwise apply the common check without importing a ledger or state machine.
Changed or unverifiable policy stops pending writes and requires rediscovery.
It doesn't erase observed results or mechanical guards.

The [readability decision](2026-08-28-1805-self-merge-readability.md) retains
ordered guards and exact interfaces. The
[worktree-authority decision](2026-09-04-2114-self-merge-worktree-authority.md)
keeps removal separately authorized and checked. The new handoff changes
neither boundary; completed Git work and outstanding guards remain visible.

## Refute-First Findings

- **Confirmed and fixed:** One fresh discovery didn't cover a later policy
  change when a project-local procedure supplied no freshness rule. The
  common pre-write and final-report checks close that gap. Separate cases
  cover revoked authority before a write and changed policy after a verified
  write, when the observed result must remain visible.
- **Confirmed and fixed:** The issue-close paragraph left its applicability
  implicit. It now requires an applicable project duty, and the absence case
  includes a close-keyword target to test that a PR mention creates no duty.
- **Confirmed and fixed:** The companion-procedure case supplied separate
  tracker authority, so it couldn't catch accidental authority inheritance.
  Its negative counterpart supplies the procedure and record without a grant.
- **Disproved by a byte comparison:** The handoff weakens existing cleanup
  guards. All prior guardrail, cleanup, STOP, and review-watch text remains
  verbatim, as do the executors and fallback sequence.
- **Disproved in simulated decisions:** Successful merge or issue references
  grant tracker or closure authority. The missing-authority case reads both
  recognized and unrecognized closing targets, then reports open issues and
  pending tracker work without proposing either mutation.
- **Disproved in simulated decisions:** A worktree STOP either blocks all
  project duties or permits bypassing their prerequisites. The STOP case
  preserves the worktree and branches, verifies an independent tracker duty,
  and leaves the resync-dependent audit blocked.
- **Disproved in simulated decisions:** A successful write call proves the
  duty complete. Failed target verification leaves the result unknown and
  requests a fresh read instead of repeating the mutation.

These simulations check proposed actions and reports from supplied
observations. They don't establish live tool behavior or race-free tracker
writes.

## Revisit When

Reconsider the short entry-point handoff if observed runs need a shared
executor or a new policy schema. That would require a separate decision
reconciling the skills' Git policies and authorization contracts first.
