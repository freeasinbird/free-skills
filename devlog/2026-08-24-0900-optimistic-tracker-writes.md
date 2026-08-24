# Use Optimistic Rereads for Tracker Writes

Issue #175 revises the full-input tracker-write guard chosen in issue #124 and
recorded in `2026-08-15-1327-merge-cleanup-project-obligations.md`.

## Decision

Use an optimistic protocol as merge-cleanup's default forge behavior. Resolve
the current base tip, freshly reread and record every selector and computation
input immediately before a tracker write, recompute from those states, apply
only the documented idempotent transition, then reread the target and every
selector and computation input. Verify each field only when the post-write
inputs still support the computation. A changed or unverifiable input makes
every otherwise verified field from that attempt unknown.

A successful post-write reread verifies current state only. It does not prove
that an unconditional whole-body replacement avoided overwriting a concurrent
edit landed after the pre-write reread. Report that weaker guarantee honestly;
forge edit history is the recovery path if the residual race occurs. When
project mechanics document a real lock or compare-and-set interface across
every input, use that stronger mechanism too.

## Rationale

The earlier decision assumed supported tracker interfaces could condition a
write on immutable revisions for every input. GitHub GraphQL schema
introspection on 2026-08-24 showed that `UpdateIssueInput` exposes no body
version, ETag, or expected revision. Whole-body issue updates are unconditional,
and no documented project currently supplies an exclusive writer. The old gate
therefore turned a recoverable concurrency risk into a guaranteed skipped
reconciliation.

The fresh-reread protocol preserves the implementable safeguards: current-base
brackets, complete input enumeration, recomputation from current inputs,
idempotent transitions, full-input post-write revalidation, per-field
verification, and unknown classification for inconclusive results. The
destructive git sequence and its guards do not change.

## Rejected Alternative

Do not add conditional, exclusive-writer, and optimistic configuration modes.
Only the optimistic mode is available on the target forge today; a mode surface
would imply choices projects cannot actually use. A stronger documented
mechanism is an additive project requirement, not a global taxonomy.

## Refute-First Verification

Accepted the residual whole-body overwrite race as the explicit tradeoff above.
Rejected a stale-selector regression by verifying that the ledger still
requires every planned input in `guard complete` and now permits a changed
selector to skip the write before `attempt`. Rejected incomplete-reread,
post-write input-change, unknown-outcome, and moved-policy regressions through
the reconciliation matrix; each still stops or downgrades the run. Rejected a
destructive-cleanup regression because the git sequence and its identity,
lease, worktree, and object-ID guards are unchanged.

Revisit when the target forge exposes compare-and-set issue updates, or when a
project adopts a real lock that covers every selector and computation input.
