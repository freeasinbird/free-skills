# prepare-hill-climb evals

Trigger fixtures check skill selection; behavior fixtures check how the
skill builds, proves, and hands off a check. Only definitions and rerun
instructions live here. Keep model outputs, simulated transcripts, and
grades in a session workspace outside the repository.

## Files

- `trigger-eval.json`: 16 queries (8 should-trigger, 8 should-not-trigger).
  The positives cover "set up scoring for X", "build a scored eval for X",
  "how do we score X", "find comps for this design", "set a performance
  target", and implicit asks to build or prove a check before a climb. The
  negatives are near-misses: "hill-climb X" and "keep improving X until"
  (`hill-climb`), a one-off council score (`council`), a single eval run,
  `Plan #N` (`plan-work-unit`), ordinary unit tests, "improve this README"
  with no score, and a one-off benchmark.
- `behavior-eval.json`: Sixteen cases, each with a `request`, `artifacts`
  that describe the project, platform, and simulated scores or state, and
  nonempty `required_actions` and `forbidden_actions` lists.

## Behavior Cases

- `cost-before-proving-runs`: State the proving cost and wait for the
  owner's go-ahead before any proving run.
- `uncovered-rule-to-blind-spot`: List a rule no case fails without in the
  blind-spot map.
- `single-section-known-bad`: Use a one-section variant as the known-bad
  case, not only a frontmatter-only copy.
- `gap-inside-noise`: Report a gap inside the noise band and write no proof
  record.
- `held-out-split`: Hold out a few cases that run once, at the end.
- `score-without-evals`: Score from a copy of the skill without `evals/`.
- `freeze-after-last-edit`: Freeze after the last edit to a hashed file and
  take the recorded scores from the frozen copy.
- `guards-marked-by-cost`: List each guard with its baseline and mark it
  cheap or expensive.
- `blind-spot-as-constraint`: Propose a binding blind spot as a Constraint
  sourced to the proof record, apart from the owner's limits.
- `target-basis-recorded`: Propose a target with its basis and record the
  basis.
- `no-signoff-no-climb`: Stop before the climb: no sign-off, no attempt, no
  artifact change.
- `human-only-check`: Mark a goal only a human can judge as not climbable.
- `council-anchors-apart`: Keep anchors apart from the known-good and
  known-bad cases, mark the rubric tier unpiloted, and record the panel.
- `unpiloted-tier-named`: Say performance measurement is not yet piloted,
  pin the environment, and wait for the go-ahead.
- `hill-climb-not-installed`: Stop when `hill-climb` isn't installed beside
  the skill.
- `no-runner-in-project`: Name a missing runner and offer the three paths.

## Rerunning Trigger Cases

Run each query in a fresh context that sees only this skill's
`description` and the query. Ask whether the skill should load, and compare
the answer with `should_trigger`. Use a fresh delegate per query where the
platform offers one; otherwise use a new session per query. Include the
descriptions of `hill-climb`, `council`, and `plan-work-unit` beside this
one when testing the negatives that should route there. Repeat after any
description change.

## Rerunning Behavior Cases

Run each case in a fresh context with `skills/prepare-hill-climb/SKILL.md`,
its `references/`, `skills/hill-climb/SKILL.md`, and
`skills/hill-climb/references/goal-file.md`, plus the case `request` and its
`artifacts`. Keep `required_actions`, `forbidden_actions`, and this README
out of the task context. A controller plays the platform, every scoring
run, and the owner: it returns scores and state from the artifacts. Never
run real proving runs, start real council members, or edit real files for a
behavior case.

Grade the tier choice, the goal file draft, the cost statement, the proving
order, the blind-spot map, the proof record, and the report against the
case. A case passes only when it performs every required action and no
forbidden action. Report each case's result with the model, settings, and
tested revision. If no permitted fresh-context runner is available, report
that gap; a syntax check doesn't replace a behavior run.

## Structural Validation

From the repository root, check JSON syntax:

```sh
python3 -m json.tool skills/prepare-hill-climb/evals/trigger-eval.json > /dev/null
python3 -m json.tool skills/prepare-hill-climb/evals/behavior-eval.json > /dev/null
```

Check the behavior fixture's structure and case IDs with the standard library:

```sh
python3 - <<'PY'
import json
from pathlib import Path

fixture = json.loads(Path("skills/prepare-hill-climb/evals/behavior-eval.json").read_text())
assert fixture["version"] == 1
assert isinstance(fixture["purpose"], str) and fixture["purpose"].strip()
for key in ("case_pass", "target"):
    assert isinstance(fixture["scoring"][key], str) and fixture["scoring"][key].strip()
expected = {
    "cost-before-proving-runs", "uncovered-rule-to-blind-spot",
    "single-section-known-bad", "gap-inside-noise", "held-out-split",
    "score-without-evals", "freeze-after-last-edit", "guards-marked-by-cost",
    "blind-spot-as-constraint", "target-basis-recorded",
    "no-signoff-no-climb", "human-only-check", "council-anchors-apart",
    "unpiloted-tier-named", "hill-climb-not-installed",
    "no-runner-in-project",
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

triggers = json.loads(Path("skills/prepare-hill-climb/evals/trigger-eval.json").read_text())
assert sum(t["should_trigger"] for t in triggers) == 8
assert sum(not t["should_trigger"] for t in triggers) == 8
print("Behavior fixture structure: passed (sixteen unique cases); triggers 8/8")
PY
```

These checks validate fixture structure, not model behavior.
