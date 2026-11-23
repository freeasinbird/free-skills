# Handoff Report

## §blocked-or-paused

A blocked report keeps **Status** and **What planning changed**, the latter
as Finished in `SKILL.md` defines it. Platform Gates there still apply. Status
says planning is blocked, not finished, and names the precise blocker, as in
`#N planning blocked: <blocker>`. This differs from a finished plan whose
implementation waits on another unit.

- Add one line on what clears the block.
- Give the recommended action before any options.
- Verify any required prior-plan invalidation before reporting.
- If the prior plan remains actionable, report its location as an unsafe
  state, unless the block is occupancy (see Check Occupancy in `SKILL.md`).
- Never hand off an incomplete authoritative record.
- Omit the implementation kickoff prompt.

A mid-planning question leads with your recommendation, then asks the
question, then stops. Send no partial report with it. Ask it only before any
planning write persists; after one does, report Blocked instead.
