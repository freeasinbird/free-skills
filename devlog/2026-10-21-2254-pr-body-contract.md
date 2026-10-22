# PR Body Contract

The PR template and `docs/agent-workflow.md` §pr-body now set a fixed body:
Why, Scope, What, Departures, Screenshots, Review Notes, and Verification, in
that order, with a 150 to 300 word target outside Screenshots. Chose a
bounded seven-section body over the open-ended five-section one because the
old sections were right but unbounded. Verification and Review Notes absorbed
whatever each author improvised, departures had no slot, and nothing tied the
body to the issue's acceptance criteria. The owner specified the shape in #343.

## Evidence

An analysis of 1,640 agent-authored PRs across freeside, straylight,
free-skills, teloleo, gh-imgup, freeasinbird.com, and free-prompts
(2026-06-12 to 2026-10-22; 910 since 2026-08-21), plus the owner's first reply
after 372 PR handoffs, found:

- **Bodies more than doubled.** The median grew from 206 words in June to 580
  in October. Since 2026-08-21 the median is 535 and p90 is 1,171.
- **Verification dominated.** It held 33% of body words (median 193, 8
  bullets) and was longer than What in 61% of PRs. 44% of its bullets named a
  standard tool CI already runs. 68% of PRs carried a "Not run" bullet, most
  for untouched components.
- **SHAs and audit lines were redundant.** 80% of bodies carried a full
  40-character SHA, almost all from the merge-result audit line and
  base-commit bullets. Freeside's CI has run that audit since freeside #2084.
- **Review Notes became a catch-all.** It appeared in 78% of PRs. Of 2,116
  bullets, 8% routed the reviewer, 15% stated a call to veto, 14% narrated
  review rounds, and 10% carried coordination or deferral text.
- **Departures had no home.** They appeared in 20% of PRs, in 283 sentences.
  63% of those sentences sat inside Review Notes under at least seven ad hoc
  labels.
- **Commit maps restated What.** 53% of PRs carried one, yet 70% had at most
  two commits.
- **Acceptance went unchecked.** Only 24% of bodies referred to the issue's
  acceptance criteria.
- **Why, titles, and Screenshots worked.** Why's median was 48 words with a
  close keyword in 76%. 96% of Screenshots sections carried hosted images.
- **The owner's questions named the gaps.** Of 185 replies after a handoff,
  37 were questions: what the change does, what remains, whether anything
  needs filing, and departures.

## Revised Decisions

- **straylight `2026-06-12-2241-pr-body-format`:** Review Notes as routing
  only. Kept and tightened: up to three bullets, each a place to look or a
  call the reviewer must make. Review rounds and coordination stay out.
- **free-skills `2026-07-02-0323-commit-map-by-subject`:** the map stays
  keyed by subject, not SHA, but moves to Review Notes and appears only for
  four or more commits or a mechanical commit to skip.

## Settled Points

- **Departures is required, with "None" as its empty form.** Rejected: an
  optional section, which gets deleted and brings back "is this done?"
- **Scope is one line in every project.** Rejected: monorepos only. It is the
  fastest size signal, and a non-monorepo names directories or skill folders.
- **Verification is written as exclusions.** Rejected: a fixed bullet list,
  which every project with a different check set would need to edit.
- **The word target is guidance, not a check.** A reviewer can cite it; no
  script enforces it.
- **What has no bullet cap.** The savings come from Verification, Review
  Notes, and the commit map, so the target flexes with What.
- **"Keep the PR body current" drops "mark commits that resolve review
  findings."** That marking lived in the commit map, and finding outcomes
  already live in the inline replies. It adds Scope to the sections to
  refresh, since a scope change makes that line stale.
- **The base commit moves to the handoff.** §handing-off step 3 had allowed
  it in Verification, the source of the base-commit bullets.
- **Verification's empty form is "Passed: required checks."** Without one,
  a PR whose checks all run in CI would pad the section or break the rule.

Revisit when a sweep shows bodies back over the target, or the owner asks for
a dropped part back.
