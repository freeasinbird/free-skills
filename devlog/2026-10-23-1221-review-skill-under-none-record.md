# Invoke the Review-Watch Skill Under a `none` Reviewer Record

On Straylight PR #387, an agent handed a PR off with its required checks
still pending and never invoked `await-pr-review`. §handing-off step 1 put
"when the reviewer record is `none`, start no watch" ahead of the paragraph
that says to look for a review-watch skill. The agent read the first
paragraph as settling the question. Step 4 said "Poll until they finish,"
and the host's own rule against polling CI pulled the other way, so the
checks wait was dropped as well. `await-pr-review` already handles a `none`
record correctly: it skips the review exchange and waits on CI only. The
agent never reached it.

## Decisions

- **Chose "check for the skill first, under any reviewer record" over
  keeping the `none` clause first.** The skill reads the reviewer record
  itself and routes `none` to a CI-only wait, so the template doesn't need
  to decide that case before invoking it. Putting the check first leaves no
  order in which a reader can stop early. The `none` clause stays, scoped to
  projects without the skill, and it now says step 4 still applies.
- **Made the skill own the checks wait, not just the review watch.** A
  review watch and a checks wait are separate under a `none` record, and the
  old wording assigned only the first to the skill. Naming both means a host
  CI monitor can't stand in for the skill's wait. That matches the existing
  "even when the host offers its own PR or CI monitor" rule.
- **Rewrote step 4 as a wait under any reviewer record, with an ordered
  mechanism.** The order is the skill's wait, then a host monitor that
  re-enters the agent, then `gh pr checks --watch`. "Poll" read as forbidden
  on hosts that ban polling CI, which let the step lapse. A PR with pending
  checks is never called ready; when no wait fits the turn, step 7's Status
  reports them pending, matching `await-pr-review`'s own fallback.
- **Said the same in §reviewer-record.** Its `none` bullet now names the
  skill too, so a reader who lands there first can't skip it either.
- **Scoped re-invocation to pushes the skill didn't make.** The skill's own
  fix-round pushes restart its watch internally; re-invoking it after them
  would start the duplicate watchers step 2 forbids.
- **Left `await-pr-review` unchanged.** Its routing for a `none` record was
  already right; the defect was in the handoff text that decides whether it
  runs at all.

Revisit when: a review-watch skill stops owning the checks wait under a
`none` record, or a host offers a CI wait that the skill should defer to.
