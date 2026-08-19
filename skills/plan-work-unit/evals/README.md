# plan-work-unit evals

These fixtures test routing and the planning handoff. Keep generated issue
copies, transcripts, and grading output in a scratch workspace outside the
repository.

## Files

- `trigger-eval.json` distinguishes explicit planning operations from
  implementation, assessment, overlap, review, and in-chat proposal requests.
- `planning-eval.json` covers a stale issue contract planned on a stock repo
  with no declared planning stage and no lock, a dependency-blocked unit, a
  shared-contract unit, a plan invalidated by current code, and an owner
  decision that blocks contract completion. It also covers a concurrent
  whole-body issue edit on a last-write-wins forge, where the run proceeds
  without refusing and without claiming a post-write reread can detect a lost
  edit, and replacement-plan publication failing after the prior
  plan is retired, reported as a partial unsafe state because earlier writes
  have already persisted, both when the contract changes and when only the plan
  is stale. A designated-contract-record case verifies that the handoff does not
  require duplicating the authoritative contract into the issue body. A
  PR-routing-restriction case reports a precondition error, with no mutation or
  prepared artifacts, when project policy forbids direct planning writes, and a
  partial-stage case reports the same error class when an active stage's allowed
  mutations exclude part of the surface rather than mutating only its authorized
  subset. A repository-revision case records the inspected revision as
  provenance and, when the default branch has advanced past it by handoff,
  reports the plan as grounded in the superseded revision and recommends the
  implementer verify or replan, without reinspecting, republishing, or repairing
  drift automatically.

## Forward-testing

Run each case in a fresh context with the skill and only the raw request and
artifacts named by the fixture. Do not include the required actions, forbidden
actions, intended answer, or prior run conclusions in the task context. Grade
the resulting selected contract record, issue plan comment, and completion
report against the fixture afterward.

When the platform supports isolated tasks or agents, use a fresh one for every
presentation and repeat the battery without the skill as a baseline. When it
does not, use a new user-controlled session per presentation and review the
transcript manually. In either path, do not let one run's generated artifacts
become inputs to the next run.
