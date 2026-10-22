# Plan Report Contract

`plan-work-unit` now ends every finished run with a fixed six-part report:
Status, Result, What planning changed, Your call, Not verified, and Kickoff.
Chose a fixed, outcome-led report over the old location-led one because the
old section asked for record locations, the grounding revision, and a
"nothing was started" statement, but never for the outcome, the contract
changes, or one clear startability line. Each session improvised those, and
the owner kept asking for them. The owner specified the shape in #341.

## Evidence

An analysis of 383 planning sessions across freeside, straylight, teloleo,
and free-skills (2026-08-21 to 2026-10-22, 338 with a substantive final
report) found:

- **Shape varied widely.** Median length was about 280 to 350 words, with 25
  distinct opening lines; 30% used headings.
- **Location blocks restated the kickoff.** 29% carried a "where things are"
  block under eight labels, and 79% carried two or more GitHub links.
- **Verification narration and SHAs crowded the report.** 33% narrated
  read-back checks, and 46% printed a full 40-character SHA.
- **The outcome was mostly missing.** Only 9% said what the change would do
  once built, 42% said what changed in the contract, and 57% stated startable
  or blocked plainly.
- **Follow-up questions named the gaps.** The owner asked what a plan would
  result in, whether anything blocked it, whether a "no blocker" unit should
  really start, whether the tracker was updated, and for a recommendation
  after blocked reports that listed options without choosing.
- **Some turns ended on the wrong message.** Four ended on a status line or a
  session card instead of the report.

## Settled Points

- **Grounding revision leaves the chat report.** The plan comment carries it.
  Not verified reports only an advance of the default branch during planning.
  Rejected: keeping it in the report, where no owner decision uses it and it
  duplicates the plan comment.
- **Contract record is named only when it isn't the issue body.** A
  project-designated record such as WC-103 still needs naming; the issue body
  is implied by the Status link.
- **No new eval case.** The existing cases already grade the completion
  report, so their expectation strings were rewritten to the new shape.

Revisit when forward tests show reports drifting from the shape, or the owner
asks for a dropped part back.
