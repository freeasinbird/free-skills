# Plan and Handle a Batch of Issues in One Request

The new `plan-and-handle-batch` skill runs a set of issues from plan to
review-ready PR. It starts one `plan-work-unit` planner per issue, then gives
each startable plan its own implementer in an isolated checkout, at most N at
once. Issue #383 carries the contract. Before this, the owner opened every
planning and implementation session by hand and counted the running ones.

## Decisions

- **Chose stopping with an error over working in the orchestrator's own
  context** when background delegation, `plan-work-unit`, or isolated
  checkouts are missing. A fallback would plan and implement many issues in
  one context and one checkout, which is the manual workflow with worse
  isolation. The error points the owner to `Plan #N` and `Handle #N` by hand.
- **Chose leaving planners out of the window over counting them.** Planners
  only read the repository and write issue records, so running all of them at
  once costs no checkout and fills the dispatch queue sooner. The window
  limits the work the owner must review: implementations and their PRs.
- **Chose threads before subagents.** A top-level thread is a session the
  owner can open, read, and answer in, the same as a hand-started `Handle #N`
  session. A subagent's work is visible only through its report, so it is the
  fallback.
- **Chose not restarting a run that ended without a report over retrying
  it.** The run may already have pushed a branch or opened a PR, and a second
  run could duplicate either. The table names it, and the owner decides.
- **Chose not dispatching an issue that waits on another issue in the batch
  over chaining it.** The prerequisite needs a human merge, which this skill
  never performs, so the dependent can't start from a base that contains it.
- **Chose a default window of 3 over requiring a number.** The issue
  suggested it as the owner's call; the opening message states it as a default
  so the owner can change it before implementations start.
- **Chose accepting a set named earlier in the thread only when it is one
  explicit list of issue numbers.** Requiring numbers in the request would
  force the owner to retype a triage result. Confirming every referenced set
  would add a round trip to the common case. Building a set from criteria or
  picking between lists risks planners editing issues the owner didn't
  assign, so those cases ask instead. The opening message lists the numbers in
  dispatch order, so a wrong set can be stopped at once.

## Unchecked Pairing

The skill dispatches only on `plan-work-unit`'s status line
`#N planned, startable now` and sends its kickoff sentence
`Handle #N, implementation plan in comments.` No script checks this pairing.
A change to either form in `plan-work-unit` has to update this skill in the
same PR.

Revisit when a lessons comment from the 2026-11-18 Freeside run on #383
contradicts one of these choices, or when a first live batch shows the default
window or the thread-first order working against the owner.
