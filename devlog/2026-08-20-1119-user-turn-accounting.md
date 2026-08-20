# Cancel shared user-answer turns from the conductor break-even

Issue #111 corrects one assumption in the whole-exchange cost model recorded
by `2026-08-02-1130-review-conductor.md`: a user's answer resumes the main
agent under either ownership model, not only when a conductor owns the
exchange. The earlier note remains frozen history; this note supersedes that
comparative accounting detail without changing its routing decision.

## Decision

Count main-owned orchestration wakes as `(N + J_user) × C_main` and
conductor-owned wakes as `(2 + J + J_user) × C_main`. Comparing the two
cancels the shared `J_user` term, so the wake-only conductor break-even is
`2 + J < N`. Retain `J_user` in both total-cost expressions because the
turns still occur and still matter to absolute cost; remove it only from the
ownership difference.

Keep the conductor-default routing rule unchanged. `SKILL.md` does not repeat
the cancelled term, and the cost-model formula is explicitly a hindsight
audit rather than an invocation-time route. The correction strengthens the
existing rationale by removing a term that could incorrectly reject conductor
ownership in a borderline retrospective comparison.

## Rejected alternatives

- **Drop `J_user` from the model.** Rejected because user-answer turns still
  replay the main context under both owners; cancellation in a comparison does
  not make them free.
- **Edit the merged 2026-08-02 note.** Rejected because merged decision notes
  are frozen. A new note preserves both the historical record and the current
  model.
- **Change the routing gate.** Rejected because routing already defaults to a
  conductor on capability grants alone and does not use this hindsight
  break-even.

Revisit when: user-routed decisions no longer resume the main agent under one
of the ownership models, or the conductor spawn and terminal report cease to
cost main-context turns.
