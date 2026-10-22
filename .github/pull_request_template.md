<!-- Title: imperative, ≤ 72 chars, names the outcome; it becomes the
     merge-commit subject, so write it for `git log --first-parent`. -->

## Why

<!-- One to three short prose sentences. Link the decision note when one
     exists; don't duplicate it. Add a close keyword immediately before each
     issue number the PR fully resolves or finishes: `Closes #11`, repeating
     the keyword to close several (`Closes #11, closes #12`), since a bare
     list `Closes #11, #12` closes only the first. Reference
     related-but-unfinished issues with a plain `#N` (e.g. `Refs #N`) and
     leave those for a human. -->

## Scope

<!-- Required. One line naming the areas touched, for example
     `Scope: skills/agent-setup, scripts/`. -->

## What

<!-- Bullets required. One outcome bullet per change, in behavior terms:
     what a user, agent, or caller can now do or see. When the issue has
     numbered acceptance criteria, write one bullet per criterion, in the
     issue's order, and add a change bullet only for an outcome no criterion
     covers. No bullet cap; about 25 words is the shape of a bullet, not a
     limit. No file lists and no commit map. Say rejected alternatives live
     in the decision note when they do; don't duplicate them. -->

## Departures

<!-- Required. Up to three bullets, or the single word "None". Each bullet
     names a change from the issue, plan, or contract and why; an addition
     beyond it; or a criterion left unmet or work left undone, with the
     issue that tracks it. -->

## Screenshots

<!-- Required for PRs with visible UI changes; delete for non-visual PRs.
     Replace this section with actual forge-hosted, reviewer-visible image or
     recording attachments before handing off, and in every case before merge.
     Local paths, textual descriptions, and "checked locally" notes do not
     satisfy this section. -->

## Review Notes

<!-- Optional; delete it when empty. Up to three bullets, each a place to
     look (a file to read first, a mechanical commit to skip, a risky edge)
     or a call the reviewer must make (an assumption to veto, a criterion to
     judge). Review rounds, folded findings, coordination, and merge-order
     notes stay in the threads and on the issue. Add a commit map only for four or more
     commits or a mechanical commit to skip, keyed by commit subject not SHA
     (folding review fixes rewrites SHAs). -->

## Verification

<!-- Bullets required, up to five. Start each bullet with Passed:, Checked:,
     Attempted:, or Not run:. List only what CI does not show:
     change-specific checks with counts as deltas ("82 to 86 cases"), manual
     or device checks, and schema round-trips. Add one Not run: bullet per
     check the change needs and could not get, never for suites of untouched
     components. No standard-check inventory, base SHA, or audit command.
     When CI shows everything, write the single bullet "Passed: required
     checks." Facts only, never "should work". -->
