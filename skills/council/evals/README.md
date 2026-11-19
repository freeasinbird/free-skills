# council evals

These fixtures test routing and the council contract. Keep transcripts,
simulated member output, and grading in a scratch workspace outside the
repository.

## Files

- `trigger-eval.json` separates council requests and skill invocations from
  an ordinary review, a code-review command, one named second opinion, risky
  work that doesn't ask for council, an automated-review wait, and an
  unrelated use of the word "council".
- `behavior-eval.json` describes platform and member inputs and the actions
  each case requires or forbids.

## Behavior Cases

- `rung-1-two-providers`: Seat one member per provider, other provider first,
  and name rung 1.
- `rung-2-one-provider-two-models`: Seat two fresh contexts with different
  focuses on different models.
- `rung-2-one-provider-one-model`: Seat two fresh contexts on one model rather
  than falling to rung 3.
- `rung-3-no-delegation`: Run no council and name the fallback reviewer.
- `rung-3-scoring`: Return no scores when no council can run.
- `cli-installed-not-allowed`: Treat a denied CLI as unreachable and drop a
  rung.
- `named-member-unavailable`: Seat only reachable named members, never
  substitute, and ask or stop when fewer than two remain.
- `cost-stated-first`: State rung, panel, models, effort, and staging before
  any launch.
- `third-seat-only-on-request`: Keep the default panel at one per provider.
- `staging-other-provider-first`: Launch the other provider's member first and
  hold the rest after a confirmed blocker.
- `staging-risk-class-full-panel`: Seat the full panel for risk-class work
  despite a blocker.
- `staging-fix-check-then-final`: Have one member check the fix; reseat the
  full panel only for the final version.
- `brief-without-lead-reasoning`: Brief members read-only with only the
  artifact, outcome, and mode instructions, and edit no checkout they read.
- `unconfirmed-findings-separate`: Count only confirmed findings, list the
  rest separately, and turn out-of-scope bugs into follow-ups.
- `scoring-blinding`: Hide the target, shuffle and unlabel candidates, score
  twice, and report the spread.
- `scores-never-gate`: Report scores without a pass or fail.
- `called-by-skill-scoring`: Run on a skill's call and return the scoring
  report fields.
- `called-by-skill-findings-report-only`: Run on a skill's call, stop after a
  first-member blocker, fix nothing, and return the findings report fields.
- `standing-request-covered`: Run on a project instruction that requests
  council for the change's class, without asking, and state the cost first.
- `standing-request-not-covered`: Suggest council, and launch no member, when
  the project instruction's classes leave out the change, here an untested
  behavior change.
- `member-out-of-usage-mid-run`: Treat a usage failure as an unreachable
  provider, re-state the cost before re-seating at rung 2, and report the
  failed member.
- `named-member-fails-mid-run`: Record an empty named member as failed, leave
  its seat empty, and ask or stop when fewer than two remain.
- `lone-member-short-reset`: Wait out a stated reset of 30 seconds on a member
  running alone with no time budget, retry it once, and count its review.
- `lone-member-long-reset`: Fail the seat of a member running alone when its
  stated reset is 10 minutes away, treat the provider as unreachable, and
  state the revised cost before any replacement.

## Rerunning Trigger Cases

Run each trigger query in a fresh context that sees only this skill's
`description` and the query. Ask whether the skill should load, and compare
the answer with `should_trigger`. Use a fresh delegate per query where the
platform offers one; otherwise use a new session per query.

## Rerunning Behavior Cases

Run each case in a fresh context with the skill, the case `request`, and its
`artifacts`. Keep `required_actions`, `forbidden_actions`, and this README out
of the task context. A controller plays the platform and the members: it lists
the tools the case names and returns each member's output from the artifacts.
Never start real members against real code for a behavior case.

## Structural Validation

Parse both JSON files with `python3 -m json.tool`, directing output to scratch
files. Confirm 24 unique behavior IDs match the inventory above. Parsing
validates structure only; it doesn't grade model behavior.
