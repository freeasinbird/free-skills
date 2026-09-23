# Revision Evals

`revision-evals.json` holds seven cases outside the calibration reference's
story examples. They test causal preservation, scope and subject, useful
parallelism, and a second pass guided by author feedback. They also test a
connected section and its exercise, fluent but flat prose, and improving an
awkward parallel sequence. Unchanged text can be the right outcome.

## Run

Give a permitted fresh-context evaluator the skill, its calibration reference,
and each case's `request` and `source_text`. Keep `required_outcomes` and
`forbidden_outcomes` for grading afterward. Keep outputs outside the repository.

Prefer a fresh context per case. If cases share a context or the evaluator
inherits other writing instructions, record that limit. A bundled smoke test
can expose mistakes, but doesn't establish the skill's isolated effect.

## Grade

Grade preservation first against both outcome lists. A rewrite that invents
facts, loses a condition, or changes the subject fails regardless of fluency.

For the connected section, also read the revision without its source beside
it. Check the progression and the exercise as a whole; an isolated good
sentence does not establish that the explanation works.

Then judge naturalness separately: can the intended reader follow the thought
without reconstructing its relationships? Does the passage communicate why
the point matters where that is its purpose? Accept faithful alternatives
rather than comparing against a single preferred sentence.

For the parallelism case, retaining the source is a successful editorial
decision. The separate awkward-sequence case needs changes while preserving
the comparison. Don't score fewer words or more edits as improvement.

Report the model, settings, revision, actual instruction inputs, outcomes,
and limitations. A structural JSON check is not a behavioral evaluation.

## Selection Checks

Before changing the skill description, check these boundaries in a fresh
context using only that description:

| Request                                                                   | Expected     |
| ------------------------------------------------------------------------- | ------------ |
| Revise this essay so it reads naturally without losing the argument.      | Select       |
| Apply the feedback from these comparisons to the rest of my guide.        | Select       |
| Compare my original with both rewrite attempts and explain what improved. | Select       |
| Make another pass for the kinds of corrections I gave earlier.            | Select       |
| Write a two-sentence status update.                                       | Don't select |
| Fix spelling mistakes only.                                               | Don't select |
| Write a sonnet about a river.                                             | Don't select |
| Review this Python function for correctness.                              | Don't select |
