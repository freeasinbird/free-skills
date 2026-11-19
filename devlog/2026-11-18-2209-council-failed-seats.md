# Report Council Members That Fail or Run Out of Usage

Issue #409 defines what council does when a member can't run or stops
partway. Before it, council checked reachability only at planning time, and
a member that errored or returned nothing could read as a quiet one. The
report contract changed, and downstream projects inherit it.

## Decisions

- **Chose to treat exhausted usage as an unreachable provider over retrying
  until it clears.** A quota or usage failure on the account blocks every
  member on that provider, and the reset can be hours away. Dropping the
  provider for the run keeps the panel moving and names the rung honestly. A
  failure tied to one model costs only that seat, since another model on the
  same provider may still run.
- **Chose one retry inside the run's own time over open-ended waiting.** A
  transient error, such as a rate limit with a stated reset, can clear while
  the other members work. Waiting longer than that stalls the caller for one
  seat; the seat is failed instead.
- **Chose to re-seat only when the rung drops, once per slot.** Re-seating
  whenever a member fails would buy a third seat on a provider already seated,
  which the default panel allows only on request, when the remaining members
  still hold the rung. Capping each slot at one replacement keeps a model that
  fails every time from consuming runs in a loop.
- **Chose a reported failed seat over a silent one.** A missing review that
  reads as "no findings" is worse than no council, because the caller trusts
  a check that didn't happen. The report lists each failed member and the
  rung the completed members achieved.
- **Chose re-seating only for an unnamed panel.** This follows the empty-seat
  decision in `2026-11-18-1850-council.md`: a named member's seat stays
  empty, since a substitute reports a panel the user didn't ask for. A default
  panel names no models, so re-seating it, with the revised cost stated first,
  keeps its independence without misreporting it.
- **Chose rung 3 for fewer than two completed members, keeping a lone
  member's confirmed findings.** One member isn't a council, but its
  confirmed findings are real defects. Labeling them a single review lets
  pre-push review fall back as it already does for rung 3, so
  `docs/agent-workflow.md` needed no edit.
- **Chose to have hill-climb rescore over scoring a degraded panel.** A score
  from a panel with a failed seat comes from a different check than the one
  the climb proved, so keeping or reverting on it compares unlike numbers.

Revisit when a provider exposes remaining usage cheaply before launch, or
when a caller needs to use a partial panel's scores.
