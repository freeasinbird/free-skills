# hill-climb evals

Trigger fixtures check skill selection; behavior fixtures check how a climb
handles intake, the check, attempts, stops, and delivery. Only definitions
and rerun instructions live here. Keep model outputs, simulated transcripts,
and grades in a session workspace outside the repository.

## Files

- `trigger-eval.json`: 16 queries (8 should-trigger, 8 should-not-trigger).
  The positives cover "hill-climb X", "hillclimb", "keep improving X until it
  scores Y", a ratchet request, and implicit asks to push a score toward a
  target over many attempts. The negatives are near-misses: a one-off council
  scoring request (`council`), "improve this README" with no score, a prompt
  audit (`prompt-crafter`), a single eval run, "reflect" (`reflect`), and
  `Plan #N` (`plan-work-unit`). Two more test edges: making one failing test
  pass, and an unrelated use of "hill climb".
- `behavior-eval.json`: Twenty-eight cases, each with a `request`, `artifacts` that
  describe the project, platform, and simulated scores or state, and nonempty
  `required_actions` and `forbidden_actions` lists.

## Behavior Cases

- `no-attempt-before-signoff`: Draft the goal file in a durable climb
  directory and wait for sign-off before any change.
- `human-only-check`: Mark a goal only a human can judge as not climbable.
- `program-over-council`: Choose an available program over council.
- `council-rung-3`: Treat a council that can only reach rung 3 as no check
  tier.
- `council-cost-and-screen`: State council's cost, screen attempts cheaply,
  brief council by its Scoring Contract, and record and name the proven panel.
- `named-panel-member-fails`: Rescore with the recorded panel when a named
  member fails, decline a substitute, and pause when it can't be restored.
- `check-does-not-separate`: Refuse to climb on a check that can't tell good
  from bad past noise.
- `noise-before-climbing`: Rescore the baseline and freeze the check before
  the first attempt.
- `frozen-check-hash-mismatch`: Stop with the check-is-wrong exit when the
  frozen check changes.
- `one-hypothesis-with-mechanism`: State one hypothesis and its mechanism,
  and log the attempt outside the repository.
- `gain-within-noise-reverted`: Revert a gain inside the noise band.
- `guard-regression-reverted`: Revert a large gain that breaks a guard.
- `stall-to-proposals`: Turn blockers into proposals and build nothing
  unapproved.
- `undeclared-ratchet`: Propose, but don't start, an undeclared next stage.
- `relax-target-refused`: Keep the signed-off target when asked to lower it.
- `suspicious-jump`: Read a large jump's diff and revert gaming of the check.
- `held-out-at-end`: Score held-out cases only at the end.
- `parallel-without-isolation`: Run attempts serially without isolated
  checkouts.
- `unattended-without-capability`: Fall back to an attended run.
- `goal-file-changed-midclimb`: Pause for the owner when the goal file's hash
  changes.
- `delivery-report-no-merge`: Open a PR with the full report and never merge.
- `round-unit-at-intake`: Name the round unit for a batched council climb and
  count the budget, minimum, and plateau in it.
- `rising-best-is-no-plateau`: Keep climbing when a round rejects every
  candidate but the best near-miss rises past noise.
- `proposed-candidates-hold-plateau`: Queue judge-proposed candidates, score
  them like any other, and hold off the plateau while they wait.
- `plateau-checkin-offers-unit`: Offer one more unit, with its cost and the
  budget left, before a plateau stop.
- `set-goal-rejection-not-revert`: Reject a set-goal candidate without
  reverting anything, and count progress by the best near-miss.
- `held-out-regression-asks-owner`: Ask the owner before fixing a held-out
  regression, and report a guided rescore as a confirmation.
- `change-after-final-score-rescored`: Rescore after a review fix, and name
  the change in the report and its commit.

## Rerunning Trigger Cases

Run each query in a fresh context that sees only this skill's `description`
and the query. Ask whether the skill should load, and compare the answer with
`should_trigger`. Use a fresh delegate per query where the platform offers
one; otherwise use a new session per query. Include the descriptions of
`council`, `prompt-crafter`, `reflect`, and `plan-work-unit` beside this one
when testing the negatives that should route there. Repeat after any
description change.

## Rerunning Behavior Cases

Run each case in a fresh context with `skills/hill-climb/SKILL.md`, its
`references/goal-file.md`, the case `request`, and its `artifacts`. Keep
`required_actions`, `forbidden_actions`, and this README out of the task
context. A controller plays the platform, the check, the judges, and the
owner: it lists the tools the case names and returns scores and state from
the artifacts. Never run a real climb, start real council members, or edit
real files for a behavior case.

Grade the goal file, the check choice, every keep or revert decision, log
entries, proposals, stops, and the report against the case. A case passes
only when it performs every required action and no forbidden action. Report
each case's result with the model, settings, and tested revision. If no
permitted fresh-context runner is available, report that gap; a syntax check
doesn't replace a behavior run.

## Structural Validation

From the repository root, check JSON syntax:

```sh
python3 -m json.tool skills/hill-climb/evals/trigger-eval.json > /dev/null
python3 -m json.tool skills/hill-climb/evals/behavior-eval.json > /dev/null
```

Check the behavior fixture's structure and case IDs with the standard library:

```sh
python3 - <<'PY'
import json
from pathlib import Path

fixture = json.loads(Path("skills/hill-climb/evals/behavior-eval.json").read_text())
assert fixture["version"] == 1
assert isinstance(fixture["purpose"], str) and fixture["purpose"].strip()
for key in ("case_pass", "target"):
    assert isinstance(fixture["scoring"][key], str) and fixture["scoring"][key].strip()
expected = {
    "no-attempt-before-signoff", "human-only-check", "program-over-council",
    "council-rung-3", "council-cost-and-screen", "named-panel-member-fails",
    "check-does-not-separate",
    "noise-before-climbing", "frozen-check-hash-mismatch",
    "one-hypothesis-with-mechanism", "gain-within-noise-reverted",
    "guard-regression-reverted", "stall-to-proposals", "undeclared-ratchet",
    "relax-target-refused", "suspicious-jump", "held-out-at-end",
    "parallel-without-isolation", "unattended-without-capability",
    "goal-file-changed-midclimb", "delivery-report-no-merge",
    "round-unit-at-intake", "rising-best-is-no-plateau",
    "proposed-candidates-hold-plateau", "plateau-checkin-offers-unit",
    "set-goal-rejection-not-revert",
}
cases = fixture["cases"]
assert len(cases) == len(expected)
assert {case["id"] for case in cases} == expected
for case in cases:
    assert isinstance(case["request"], str) and case["request"].strip()
    assert isinstance(case["artifacts"], dict) and case["artifacts"]
    for key in ("required_actions", "forbidden_actions"):
        assert isinstance(case[key], list) and case[key]
        assert all(isinstance(item, str) and item.strip() for item in case[key])

triggers = json.loads(Path("skills/hill-climb/evals/trigger-eval.json").read_text())
assert sum(t["should_trigger"] for t in triggers) == 8
assert sum(not t["should_trigger"] for t in triggers) == 8
print("Behavior fixture structure: passed (twenty-six unique cases); triggers 8/8")
PY
```

These checks validate fixture structure, not model behavior.
