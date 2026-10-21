# Who Refreshes a Handed-Off PR

Issue #334. The canonical §handing-off step 3 told the author to refresh a
handed-off PR whenever the base moved under the up-to-date rule, and only then
deferred to a merge queue or land command. A project with both, such as
free-skills itself, matched both sentences. An agent following the text
rebased and force-pushed a waiting PR on every advance of `main`.

## Decisions

- **Chose "the lander integrates, the author waits" over "the author always
  refreshes" when a merge queue or land command exists.** Author refreshes
  restart CI and the review watch on every base advance and gain nothing,
  because the lander tests the PR against the tip it selects anyway. The
  author refreshes only when the lander hands the PR back (a merge queue does
  so by removing it) or the owner asks.
- **Kept "refresh again" for projects with only the up-to-date rule, until
  approval.** That rule blocks merge until the branch contains the tip, but
  nothing else pushes the update, so the author still does before approval.
  After approval, step 7's freeze applies and whoever lands the PR updates
  the branch. The old text said "before merge," which collided with step 7 in
  these projects.
- **Dropped the lease argument from issue #334.** The issue said an author
  push defeats the `land-approved-prs` engine's lease. That harm exists only
  after approval: filter 4 excludes a PR pushed after its approval, and a
  lease failure hands the PR back. Step 7 already forbids those pushes, so the
  lease doesn't justify waiting before approval; the wasted CI does.
- **Revised the reasoning in `devlog/2026-10-14-2300-landing-check-main.md`.**
  Its claim that `strict: true` makes GitHub rerun CI on the combined branch
  was the source of the conflation; the up-to-date rule reruns nothing by
  itself. The managed pull-requests bullet that repeated the claim became a
  pointer to step 3 in #331, so step 3 is now the only place the rule lives.
  The choice of protection in that note stands.
- **Keyed the condition on what the project names, not a recorded field.**
  A landing record names a land command; no managed field records a merge
  queue, so the text relies on the project's instructions naming one.

Step 3 now covers handoff to approval. The existing step 7 rule, stop pushing
once the approver approves unless you are the landing batch, covers approval
to merge; the two read as one rule.

## Revisit When

Revisit when the landing check definitions in
`skills/agent-setup/references/coordination-discovery.md` change, or when a
managed field starts recording a merge queue.
