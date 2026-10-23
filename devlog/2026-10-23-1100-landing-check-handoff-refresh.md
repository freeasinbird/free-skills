# Who Refreshes a PR Before Handoff

Issue #347. The canonical §handing-off step 3 told every author to refresh
the PR onto the latest tip before handoff, whatever the landing check. Under
a merge queue or land command that repeats the lander's work. In
freeside-ai/freeside, which lands with `land-approved-prs`, agents rebased
before handoff and again whenever the tip moved during the handoff wait.

## Decisions

- **Chose "check against the tip, refresh only when needed" over "always
  refresh" before handoff under a merge queue or land command.** The lander
  tests the PR combined with the tip it selects and reruns CI there.
  `land-approved-prs`'s `landed-since.sh` reads every landing since the PR's
  original fork point, so an author rebase doesn't shrink what the lander
  reads. An author refresh still costs a CI run, a restarted review watch,
  and one more force-pushed head for the lander to trace; if the forge drops
  one, the lander stops `original-base-unknown`. The author refreshes only
  for a conflict or a base change that needs a fix in the PR, and checks
  again for the same reasons if the base moves before the step 7 report.
- **Extended `devlog/2026-10-21-0941-handoff-refresh-ownership.md`, without
  overturning it.** That note chose "the lander integrates, the author
  waits" for handoff to approval. This one applies the same reasoning to the
  time before handoff. Its other choices stand: the up-to-date rule alone
  still has the author refresh until approval, and the condition is still
  keyed on what the project's instructions name, since no managed field
  records a merge queue.
- **Kept the refresh for projects with only the up-to-date rule or no
  landing check.** Nothing else brings the branch up to date there, so the
  author still does before handoff, as before.
- **Made the merge check, not the refresh, the step's opening action.** The
  author uses the project's merge-result audit when it has one, else
  `git merge-tree --write-tree`, which builds the merge without a checkout.
  It needs Git 2.38 or later. An older Git can fall back to a scratch merge;
  the text leaves that caveat out to stay inside the readability budget.
- **Renamed Status's first fact to the tip step 3 checked.**
  `devlog/2026-10-21-2302-handoff-report-contract.md` kept a base commit in
  Status because the PR body no longer carries one. A PR handed off behind
  the tip has a different merge-base, so "the base commit" would be wrong for
  it. Status keeps the fact under the new name.
- **Limited the stale-branch report to a needed refresh.** A PR left behind
  the tip on purpose isn't stale.

## Revisit When

Revisit when the landing check definitions in
`skills/agent-setup/references/coordination-discovery.md` §shapes change, or
when a managed field starts recording a merge queue.
