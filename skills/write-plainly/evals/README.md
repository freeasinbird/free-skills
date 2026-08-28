# write-plainly evals

Trigger fixtures for the skill-creator description-optimization loop. Only
the definitions live in the repo; run outputs and grading artifacts belong in
a session workspace outside the repo.

## Files

- `trigger-evals.json`: 16 queries (8 should-trigger, 8 should-not-trigger).
  The positives cover explicit asks ("plain English", "tighten", "readable")
  and implicit ones, such as drafting a status update, issue, or commit body
  that a person will read. The negatives are deliberate near-misses: code
  edits with no prose, imitating a named author's voice, creative forms,
  translation, and the neighboring skills that own AGENTS.md scaffolding,
  prompt audits, and licensing.

## Re-Running

Run each query in a fresh context with only the skill description available,
and record whether the skill triggers. Grade against `should_trigger`. Repeat
after any description change; the implicit positives are the ones most likely
to regress when the description is shortened.
