# Keep Worktree Removal Separately Authorized

Issue #239 retains the owner's decision in #234: self-merge permission alone
doesn't authorize removing a separate linked worktree. Report the path and
STOP reason for owner removal or explicit task-specific cleanup authority.
Honor applicable authority already granted without asking again.

## Decision

Keep removal outside `self-merge.sh` and its fallback sequence. Align the
cleanup instruction, STOP policy, and diagnostics with that boundary.
Authorization permits the separate task; it doesn't establish that removal
is safe or waive preservation and ownership checks.

Rejected automatic removal based on clean status or an idle assertion. The
[resync guard record](2026-07-24-2311-self-merge-resync-guards.md) documents
ignored-file loss, hidden index edits, paused operations, and concurrent
detached-HEAD changes. Ordinary Git removal and a clean inventory don't
provide an atomic ownership or preservation guarantee.

The [readability decision](2026-08-28-1805-self-merge-readability.md) retains
ordered guards and literal interfaces. This change preserves them: only two
human-readable script diagnostics change. The dirty-worktree message no
longer directs file movement; the clean-worktree message no longer directs
removal without separate authority.

## Refute-First Findings

- **Confirmed and fixed:** The cleanup instruction directed removal while
  the STOP policy forbade manual deletion. Both now require separate
  task-specific authority and preserve authority already granted.
- **Allowed by explicit decision:** The owner may remove the worktree or
  authorize the agent to do so separately. This is the retained #239
  contract, not a new automatic-removal exception.
- **Disproved by a check:** The script gained a removal path or changed a
  guard. After normalizing the two diagnostic arguments, the old and new
  scripts are byte-identical. The regression suite is unchanged.
- **Confirmed and fixed:** A simulated agent proposed moving an ignored
  file under worktree-removal authority. The instructions now distinguish
  removal authority from authority to change contents to clear a stop.
- **Confirmed and fixed:** A simulated agent proposed rerunning cleanup to
  refresh stale inspection before clearing the stop. Recovery now refreshes
  only read-only checks outside cleanup, then permits removal if authorized
  and safe, then reruns cleanup.
- **Confirmed and fixed:** The recovery checklist initially named only a
  subset of the existing checks. A worktree could detach and gain a commit
  after STOP while still passing those checks. Recovery now refreshes the
  full inventory and unique path, and checks both branch and worktree `HEAD`
  against the pinned merged head after concurrent users stop.

## Revisit When

Reconsider the removal boundary only with an explicit owner policy change
and evidence that addresses the recorded preservation and ownership hazards.
Clean status, an idle assertion, or ordinary Git refusal behavior alone
doesn't supply that evidence.
