# Bound Project Post-Merge Reconciliation

Issue #124 extends merge-cleanup with project-specific reconciliation after a
verified merge.

## Decisions

- Chose a fixed-field record in authoritative, unmanaged project instructions
  over scanning prose, issues, PRs, comments, trackers, or web content. Absence
  therefore preserves generic cleanup, while a present record makes its one
  repository-contained mechanics document the only delegated policy source.
- Kept the record local to merge-cleanup over adding a universal agent-setup
  convention. One consumer does not establish a cross-project hook protocol,
  and canonical promotion would impose unused structure downstream.
- Treated a cleanup request as authorization only for documented completion
  transitions and listed refreshes on known containing trackers, after merge
  verification. It does not authorize unrelated issue closure, work selection
  or start, inferred dependencies or trackers, non-tracker mutations, or
  policy changes.
- Limited mutation to known containing trackers whose exact unit entry and
  completion transition are documented. Start and merge readiness remain
  distinct where the project distinguishes them; ambiguity goes to the owner,
  and newly unblocked work is reported without being claimed.
- Kept project reconciliation after the git sequence and issue-close check.
  The merge makes project state stale, so a safe reconciliation may proceed
  after an earlier git stop, while a tracker failure never rolls back or
  repeats completed git cleanup. The summary reports both result sets.
- Required a conditional revision or documented exclusive-writer guard for
  tracker mutations across every external object whose state selects the
  target or determines the computed edit. A refute-first lens confirmed that
  an unconditional read-compute-whole-object write could erase a concurrent
  owner edit, while review exposed that guarding only the target leaves source
  issues and dependency trackers stale. A plain immediate reread still leaves
  a race, so an incomplete guard set yields exact owner steps to rediscover and
  recompute under a complete guard, never an edit derived from stale inputs.
- Confined the mechanics pointer to a repository-relative regular file whose
  resolved target remains inside the repository. The refute-first lens
  confirmed that accepting an absolute path, parent traversal, or escaping
  symlink would delegate mutation authority to outside content.
- Required closing-issue-derived tracker discovery to stop when issue-close
  verification is incomplete, while independently enumerated trackers may
  proceed on verified inputs. Required mechanics to define check-off rather
  than assuming every tracker represents completion as a checkbox.
- Required exactly one obligations record with each field exactly once. Review
  exposed that two complete records or a repeated field could otherwise make
  competing mechanics pointers and tracker rules look authoritative, so either
  duplicate now fails closed before project discovery or mutation.
- Bound the governing instructions and mechanics document to one freshly
  resolved immutable base commit, with base-tip checks bracketing every tracker
  write. Review exposed that a pre-resync git stop could otherwise read
  superseded policy, one initial check could mix policy versions across a
  multi-tracker sequence, and pre-write-only checks miss a move during the final
  mutation. The ordered write protocol is pre-check, guarded write, tracker
  reread and verification attempt, then post-check even on failure. A moved or
  unverifiable post-check preserves verified results, marks unverified writes
  unknown, makes reconciliation partial, and stops anything remaining.
- Replaced write-local freshness prose with one checked reconciliation state
  machine. The earlier assumption that bracketing every write closed policy
  freshness was wrong: zero trackers, no-ops, report-only work, ambiguity,
  missing tooling, guard refusal, and other zero-write exits had no closing
  observation, while a later pre-write move after an earlier completion had no
  deterministic classification. The mechanism now enumerates each tracker,
  transition, refreshed field, no-op, report, and unsupported request; orders
  pre-tip, full-input guard, attempt, per-field reread verification, and
  post-tip; and requires a final tip on every applicable exit. Its ledger
  distinguishes completed changes, no-ops, reports, verified failures, unknown
  outcomes, and skipped work. Successful writes, multiple and partial writes,
  zero-write completion, source and tooling failures, ambiguity, pre-write and
  post-write freshness failures, conditional rejection, mutation failure, and
  unverifiable reads therefore share one terminal rule instead of independent
  prose branches.
- Closed readable absence against the current base too. Stable absence remains
  silent and preserves generic cleanup, but an advance that adds a record now
  restarts discovery once rather than silently treating stale absence as
  authoritative. The replacement trace carries that restart history, so a
  second move stops as unstable policy instead of inviting an unbounded loop.
- Made rediscovery and recomputation the only safe handoff after any stale or
  unguarded input. Review found that the earlier eval wording could hand the
  owner an edit computed from a removed containing-tracker link, accept a
  dependency revision mismatch, or omit the closing issue from the guarded
  input set. The state machine carries completed, unknown, and skipped work but
  never a stale payload; its owner action reacquires current policy and every
  selector or computation input under a complete guard before recomputing.
- Required no-op and report inputs to be explicit and freshly re-observed after
  all planned writes. Review demonstrated that a report completed before its
  tracker transition, or a no-op inferred from an old tracker read, could still
  produce a complete ledger under an unchanged policy tip. The checked order
  now prevents both stale derived results without widening mutation authority.

The refute-first pass rejected three suspected regressions by verification:
the destructive git sequence remains unchanged and behind its existing gates;
issue-closing authority remains surface-only unless the user asks; and absent,
incomplete, or ambiguous project policy fails closed.

Revisit when a second skill needs the same project-hook discovery record, when
supported tracker interfaces provide a portable conditional-mutation contract
that can replace project-documented writer exclusivity, or when real tracker
APIs expose another deterministic exit state that the trace grammar cannot
represent.
