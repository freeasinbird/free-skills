# write-plainly evals

Trigger fixtures check skill selection; preservation fixtures check rewrite
outcomes. Only definitions and rerun instructions live here. Keep model
outputs and grading artifacts in a session workspace outside the repository.

## Files

- `trigger-evals.json`: 16 queries (8 should-trigger, 8 should-not-trigger).
  The positives cover explicit asks ("plain English", "tighten", "readable")
  and implicit ones, such as drafting a status update, issue, or commit body
  that a person will read. The negatives are deliberate near-misses: code
  edits with no prose, imitating a named author's voice, creative forms,
  translation, and the neighboring skills that own AGENTS.md scaffolding,
  prompt audits, and licensing.
- `preservation-evals.json`: Six source-to-rewrite cases covering vague
  verification, supported checks, vague workflow status, caveats and
  exceptions, exact identifiers, and numbers with required steps.

## Re-Running Trigger Cases

Run each query in a fresh context with only the skill description available,
and record whether the skill triggers. Grade against `should_trigger`. Repeat
after any description change; the implicit positives are the ones most likely
to regress when the description is shortened.

## Preservation Format and Rubric

The preservation fixture has `version`, `purpose`, `scoring`, and `cases`.
Each case has a unique `id`, a `request`, a `source_text`, and nonempty
`required_outcomes` and `forbidden_outcomes` lists. Only `request` and
`source_text` are model inputs; the other fields belong to the grader.

Grade factual preservation as pass or fail against the source and both
outcome lists. Invented evidence, stronger certainty, or a lost requirement
fails preservation. The supported-verification control also fails when a
rewrite removes checks that the source actually supplies.

Grade readability separately: 2 for clear on first reading, 1 for
understandable but wordy or awkward, and 0 for hard to understand. Look for
direct, ordinary wording and active verbs where the meaning permits them.
Accept faithful alternatives, not just one reference sentence. A readable
rewrite can't compensate for a preservation failure.

## Validate Preservation Fixtures

From the repository root, check JSON syntax:

```sh
python3 -m json.tool skills/write-plainly/evals/preservation-evals.json > /dev/null
```

Check the declared structure and six-case coverage with the standard library:

```sh
python3 - <<'PY'
import json
from pathlib import Path

fixture = json.loads(Path("skills/write-plainly/evals/preservation-evals.json").read_text())
assert fixture["version"] == 1
assert isinstance(fixture["purpose"], str) and fixture["purpose"].strip()
for key in ("preservation", "readability", "interpretation"):
    assert isinstance(fixture["scoring"][key], str) and fixture["scoring"][key].strip()
expected = {
    "vague-verification", "supported-verification", "vague-workflow-status",
    "caveats-and-exceptions", "exact-identifiers", "numbers-and-steps",
}
cases = fixture["cases"]
assert len(cases) == len(expected)
assert {case["id"] for case in cases} == expected
for case in cases:
    for key in ("id", "request", "source_text"):
        assert isinstance(case[key], str) and case[key].strip()
    for key in ("required_outcomes", "forbidden_outcomes"):
        assert isinstance(case[key], list) and case[key]
        assert all(isinstance(item, str) and item.strip() for item in case[key])
print("Preservation fixture structure: passed (six unique cases)")
PY
```

These checks validate fixture syntax and structure, not model behavior.

## Re-Running Preservation Cases

1. Record the tested commit and any uncommitted prompt or fixture changes.
   Save exact input copies outside the repository. Use the same model and
   settings for both conditions and record their names and values.
2. Run each case once per condition, sequentially by default, for 12 outputs.
   Give every presentation a fresh context through a supported runner or
   permitted delegation. Don't reuse a conversation between cases.
3. Build the baseline input from the case's `request`, followed by a
   `Source text:` label and its `source_text`. Supply no skill text. For the
   with-skill condition, prepend the full `skills/write-plainly/SKILL.md` and
   `skills/write-plainly/references/examples.md` to that identical input.
4. Keep grading fields, expected answers, prior outputs, and implementation
   discussions out of both conditions. Disable automatic skill loading and
   inherited writing guidance, including user and project agent instructions.
   A different working directory alone does not establish isolation.
5. Record actual instruction inputs and any limits on inspecting them.
   If shared writing guidance remains, describe the result as the skill's
   incremental effect over that guidance. Unequal guidance or baseline skill
   exposure confounds the comparison; disclose it and don't claim an isolated
   skill effect.
6. After generation, grade each output against its case. Prefer shuffled,
   anonymous output labels so the grader doesn't know the condition. Keep
   the label-to-condition map separate until grading is complete. Save outputs,
   grades, and brief reasons outside the repository.
7. Report preservation and readability separately for every case and condition,
   with model/settings, tested revision, setup, and limitations. One
   presentation per condition is directional evidence, not a general success
   rate. Missing runs remain unmet evaluation criteria, not passes.

If no permitted fresh-context runner is available, report that gap. Don't
replace an unavailable behavioral run with a syntax-check result.
