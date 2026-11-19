# Close Hours-Long Gaps in the Claim Rules

PR #428 shipped the claim-record template and kept free-skills' Claiming
section as its source. A pre-push council review of a parallel
implementation of #418 (PR #430, Codex and Claude) confirmed four defects
that the merged text still had. This note records why they're fixed rather
than left among the races `2026-11-18-2233-claim-record-offer.md` accepted.

## Decisions

- **Chose to fix these over treating them as accepted races.** That note
  accepted races that need a crash or an expiry inside a window of seconds.
  The three rule defects below stay open for hours, so the same reasoning
  doesn't cover them.
- **Chose "any unexpired claim comment" over "the newest" for occupancy.** A
  run that loses the reread and crashes before deleting its comment leaves
  the newest comment. Once that comment expires, "newest" reads the issue as
  free while the winner, which may have extended its own claim, still works.
- **Added a linked-PR check to the reread.** A run that checks occupancy and
  then pauses before posting can miss a PR another run opened and released
  in between. Its reread found no earlier claim comment, so it started a
  duplicate.
- **Chose a fresh claim over extending for an expired holder.** The 24-hour
  reason expects overnight waits. A holder that returns after its claim
  lapsed, unreplaced, used to resume with an expired claim, so another run
  could claim and start too. Extending the old comment would skip the
  reread, so the holder deletes it, posts a new one, and rereads.
- **Chose to name the open-comment risk in the offer over restricting
  posters.** `2026-11-18-2238-claim-rules.md` accepted that anyone can post
  the marker on a public repository. A downstream owner accepting the
  template now hears that they accept the same risk.

Revisit when a forge offers an atomic claim, which would make the reread and
these ordering rules unnecessary.
