# Report Failed Planning Preconditions as Errors

Issue #136 reclassifies plan-work-unit's precondition failures (missing or
partial planning authority, no cross-system conflict guard, absent forge
write capability) from a blocked-with-artifacts planning handoff to a
fail-fast error.

## Decision

An explicit owner decision revises the seventh-recurrence rule recorded in
`2026-08-15-1327-plan-work-unit-boundary.md`, which required the planner to
"return ready-to-post artifacts and report planning as blocked" when project
authority was missing. The changed assumption: that graceful path was designed
as a safe degradation, but a live "Plan #135" run in this repository showed it
degrades the wrong thing. A precondition failure is a configuration error of
the invocation, not a planning outcome, and the blocked-with-artifacts shape
masked it as a normal workflow state, spent a full investigation preparing
artifacts the workflow forbids posting, and handed the user a
paste-around-the-gate temptation.

The revised rule: verify authority, guard availability, and write capability
up front, from project instructions and the forge alone, and report a failure
as an error naming the failed precondition and its remediation, with no
repository inspection and no artifact preparation. A precondition failure
detected late but before any planning write has persisted (a guard that
cannot span the discovered surface, a write capability that proves absent)
reports the same error class, never a blocked outcome, and never presents
prepared text as a handoff artifact. Once a guarded write has persisted, a
later publication failure stays under the unchanged mid-run rules: retire
first, report the partial unsafe state with the prepared replacement text,
planning blocked. That pre- versus post-mutation boundary was sharpened by
Codex review on PR #137, which caught the first wording sweeping mid-run
write failures into the fail-fast error. "Blocked" remains reserved for
planning blockers inside an authorized run: missing information or an owner
decision preventing a truthful contract or code-grounded plan, with the
existing invalidation and unsafe-state handling unchanged.

## Rejected Alternatives

- **Keeping blocked-with-artifacts:** rejected by the live evidence above;
  the artifacts invite bypassing the gate the skill just enforced.
- **Error with prepared artifacts attached:** rejected because preparing them
  requires the full planning pass the error exists to avoid, and the attached
  text recreates the bypass temptation.
- **Relaxing the authority gate for owner-invoked single-writer repos:**
  out of scope here; a project can already grant authority with a small
  declared planning stage, and weakening the gate is a separate owner
  decision.
- **Splitting the authority check into an upfront stage check plus a
  post-inspection per-target check** (Codex P2 on PR #137): rejected because
  the operation's potential mutation surface (contract record, plan comments,
  invalidation targets) is fixed by the skill, not discovered by inspection,
  so full coverage is checkable up front; the split would reinstate the
  late-blocked shape this decision removed.

The guard requirements, write-safety rules, and mid-run unsafe-state handling
for authorized runs are unchanged; only the outcome classification and the
check's position moved.

Revisit when a project demonstrates a legitimate need for planning artifacts
without planning authority (for example, a review-only forge role that asks
for paste-ready text), or when precondition errors in practice fire so often
that the gate, not the reporting, is the defect.
