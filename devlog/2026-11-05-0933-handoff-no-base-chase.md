# Verify at Handoff, Don't Chase the Base

Issue #366. Under a merge queue or land command, §handing-off step 3 still
had the author check again if the base moved before the step 7 report. The
lander already integrates the PR with the tip it lands on, so that recheck
repeated its work, and a refresh it triggered cost a CI run and a review
restart.

The owner set the rule in a Freeside session on 2026-11-04: "a PR should be
verified before hand-off, and each time it's handed off again after that if
it's modified. But it shouldn't chase a moving main."

## Decisions

- **Chose "verify at handoff and after each change, never because the base
  moved" over "check again if the base moves before the step 7 report."** A
  base move between step 3 and the report is no different from one just
  after handoff: the lander covers both. This replaces one clause of
  `devlog/2026-10-23-1100-landing-check-handoff-refresh.md`, "checks again
  for the same reasons if the base moves before the step 7 report." That
  note's other decisions stand, including refreshing only for a conflict or
  a base change that needs a fix, and keeping the refresh for projects with
  only the up-to-date rule or no landing check.
- **Stated the rule once, as the bullet's principle.** The refresh
  conditions (a conflict the merge check finds, a base change that needs a
  fix, a lander hand-back, an owner request) now read as its cases, so the
  separate "after handoff, leave the PR waiting" sentence folded into it.
- **Retitled the core pull-requests bullet that points at step 3.** Its lead
  words, "Repeat integration checks when the base moves," told every
  project to recheck on a base move, so an agent in a lander project that
  read only the core would still chase the tip. The new lead, "Integrate the
  PR with the base as its landing check requires," holds for all three
  landing checks, and the bullet defers to step 3 for when a base move calls
  for another check. Rejected "Verify the PR against the base before
  handoff": projects with only the up-to-date rule or no landing check
  refresh on a base move after handoff too, and a core-only reader would
  stop at handoff.

## Revisit When

Revisit when a lander stops integrating the PR with the tip it lands on, or
when the landing check definitions in
`skills/agent-setup/references/coordination-discovery.md` §shapes change.
