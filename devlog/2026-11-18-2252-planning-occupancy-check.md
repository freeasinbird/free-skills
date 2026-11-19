# Check Occupancy Before Planning, Without Reserving

Issue #420 asked whether planning should mark an issue as occupied before
anyone claims it. The claim rules from #417 start at implementation, so a
planner could retire the plan an implementer is working from. A standalone
"Plan #N" also checked nothing, while `plan-and-handle-batch` already left
out occupied issues before it launched planners.

## Decisions

- **The owner chose a read-only occupancy check in `plan-work-unit` over a
  planning reservation** (2026-11-18, in the batch request that assigned
  #420). A reservation would add a second claim-like writer, which #417 ruled
  out, and it would change the agent-setup claim record from #418. The check
  reads the same claim rules as the batch skill's Occupied Issues section and
  never writes a claim, a label, or a PR.
- **The owner chose the check over accepting the gap.** Without it, a
  standalone "Plan #N" can retire a plan an implementer is working from. A
  read-only check closes that case cheaply.
- **Chose to check twice: before inspection and right before the first
  write.** Inspection can take a while, and a claim posted during it would
  otherwise go unseen until the plan was already retired. A claim posted after
  the recheck can still slip through; closing that would need a lock, which
  the contract ruled out.
- **Accepted the race between two planners on an unclaimed issue.** Planning
  is short, and a retired plan is cheap to redo.
- **Chose to report occupancy as planning blocked, not a precondition
  error.** The operation is allowed; the issue is just held. The Status fits
  the `#N planning blocked: <blocker>` form the batch skill already parses.

Revisit when a project's claim rules give planners or orchestrators a role in
claims, or when either skill's occupancy definition changes; the two should
match.
