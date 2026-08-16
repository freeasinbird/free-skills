# plan-work-unit evals

These fixtures test routing and the planning handoff. Keep generated issue
copies, transcripts, and grading output in a scratch workspace outside the
repository.

## Files

- `trigger-eval.json` distinguishes explicit planning operations from
  implementation, assessment, overlap, review, and in-chat proposal requests.
- `planning-eval.json` covers a stale issue contract, a dependency-blocked
  unit, a shared-contract unit, a plan invalidated by current code, and an
  owner decision that blocks contract completion. It also covers a concurrent
  issue edit without a safe guard, a contract-bearing non-plan comment added
  during a guarded write, and replacement-plan publication failing after the
  prior plan is retired, both when the contract changes and when only the plan
  is stale. A designated-contract-record case verifies that the handoff does
  not require duplicating the authoritative contract into the issue body. A
  missing-planning-stage case blocks mutation when project policy still routes
  every state change through a pull request, and a partial-permission case
  blocks the whole write set rather than mutating only its authorized subset.
  Repository-revision cases require re-inspection when the default branch moves
  before publication, verification of the inspected revision before handoff,
  and retirement of both stale contract content and plan when a claimed
  cross-system guard fails.

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
