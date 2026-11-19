# Climb Delivery Events and Stale Tracker Exit Bullets

A reflect pass on the #393 session found two gaps that left the agent to
improvise. The owner approved both fixes.

## Decisions

- **A held-out regression goes to the owner.** In #393 the final candidate
  scored 0.889 on held-out against a 1.000 baseline. The agent restored two
  cut sentences on its own and rescored. `hill-climb` said only to score
  held-out once, at the end. It now says to stop and ask before any fix,
  and to report a guided rescore as a confirmation, not an independent test.
  Rejected: forbid any fix after held-out. A real dropped rule must go back,
  and the owner can judge the cost.
- **A change after the final score means a rescore.** Review then changed
  three sentences in the scored file. The attempt commits still claimed
  scores for text that was never scored. `hill-climb` now requires a rescore
  of the check, its guards, and held-out before handoff, counted against the
  budget, and a note in each touched commit. A fall goes to the owner.
- **A change that alters an open tracker's Exit bullet rewords it.** #431
  reversed #391's council routing and referenced tracker #394. But #394's
  Exit bullet still asked for the old behavior, so the owner couldn't tick
  it. `tracker-format.md` §exit now asks the changing work unit to reword
  the bullet, unticked, and name the change in its PR. Ticking stays the
  owner's. Rejected: a mechanical check. Nothing reliably links a PR to the
  Exit bullet whose meaning it changes.
