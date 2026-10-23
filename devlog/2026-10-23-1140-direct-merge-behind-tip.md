# Direct Merge of a PR Left Behind the Tip

Issue #349. Under a land command plus the up-to-date rule, an author may hand
a PR off behind the tip (#348). If the owner then asks the agent to merge it
directly instead of landing it, §merge-and-resync ran `gh pr merge` first,
and GitHub refuses that merge until the branch contains the tip. The
procedure had no refresh step, and §handing-off step 7's Status called the
PR "ready to merge."

## Decisions

- **Chose "refresh by hand on a direct merge request" over "hand the PR back
  to the lander."** The owner's merge request already authorizes the merge,
  so the agent refreshes from the tip, waits for the required checks, and
  merges. A hand-back would only add a round trip before the same refresh.
- **Treated a direct merge request as making the agent the lander for that
  PR.** The step 7 freeze from
  `devlog/2026-10-21-0941-handoff-refresh-ownership.md` stands: after
  approval, only the lander pushes. A direct merge request is its second
  exception, beside the landing batch. Both the new step and the freeze
  paragraph in step 7 say so; otherwise a reader following §handing-off
  literally would refuse the owner's request. The managed pull-requests
  block keeps its wording, since its pointer already routes a merge request
  to §merge-and-resync.
- **Required the owner's confirmation after a conflicted rebase.** The owner
  asked to merge the PR they saw. A conflict resolution is new code they
  haven't seen, so the agent reports what it changed and waits. A clean
  rebase merges once the required checks pass, after the agent repeats the
  merge-state check in case the base moved again.
- **Read the forge's merge state instead of checking the tip locally.**
  `gh pr view <n> --json mergeStateStatus` reports what the forge will
  enforce: `BEHIND` under the up-to-date rule, `DIRTY` for a conflict. A
  local check can't tell whether the project requires an up-to-date branch.
  Any other state goes straight to the merge, so a PR on the tip merges as
  before. `UNKNOWN` means the forge is still computing, so the agent asks
  again rather than merging on a guess.
- **Chose a local rebase and push over `gh pr update-branch --rebase`.** The
  forge-side rebase leaves the local branch stale, and the cleanup step's
  `git branch -d` then refuses to delete it. Refreshing as §handing-off
  step 3 describes keeps one refresh procedure.
- **Added a new step 1 and renumbered the rest over folding the check into
  the merge step.** No pointer in the tree cites a §merge-and-resync step
  number, so renumbering breaks nothing, and the check reads as its own
  gate before the merge.
- **Added one Status wording for a PR behind the tip.** The Status contract
  from `devlog/2026-10-21-2302-handoff-report-contract.md` keeps its shape.
  A PR handed off behind the tip under
  `devlog/2026-10-23-1100-landing-check-handoff-refresh.md` now reports
  "open and green, behind the tip, waiting for the lander" instead of "ready
  to merge," since a direct merge needs a refresh first.

## Revisit When

Revisit when a landing batch can hold a PR the owner asks to merge directly
(left out of scope here), or when a supported forge reports merge state
without an equivalent of `mergeStateStatus`.

Also revisit if direct merges under a land command without the up-to-date
rule cause trouble. There the forge reports a PR behind the tip as
mergeable, so the step merges it without the lander's combined CI. That
matches the behavior before this change and was left out of scope.
