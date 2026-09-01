# Plan Comment

## §plan-comment

Use this shape when the project requires no plan-comment format of its own. A
project format wins; keep the required plan content inside it. This file fixes
the shape, not the content. Post One Current Plan in `SKILL.md` lists what each
part must contain, and it governs; the placeholders below prompt for those
elements rather than replace them. Fill each heading with plain sentences: lead
with the point, put one thought in each sentence, use ordinary words, and name
real paths. Keep the headings and their order so a later task can find each
part. Replace the angle-bracket text.

```markdown
Plan for #<N>. The contract lives in <the authoritative record, such as "the
issue body">. This plan is an implementation aid; it does not change the
contract.

Grounded in <commit or platform revision> on <the declared planning base, or
the default branch when none is declared>.

## Startability

<Startable now, or blocked on #<M> until <event>. Name the satisfied
dependencies and the evidence that settled them. Name any serialization or
ordering rule in one sentence.>

## Change steps

1. <Edit `path/to/file`: what changes and why. Name the interface or contract
   this step changes.>
2. <Next edit.>

## Verification

- <Targeted check that shows the behavior works.>
- <Every standard check the project applies to this change: lint, format,
  build, and test commands, plus any generated-file or integration gate.>

## Risks and invalidation

- <Likely failure mode, and what it would break.>
- <Assumption, and what happens if it's wrong.>
- <Replan if `path/to/file` or <interface> changes after the grounding
  revision.>

## Finish line

<The project's implementation handoff endpoint, such as "an open, green,
review-ready PR." This planning operation does not start it.>
```

Write it so a fresh task can start from the comment alone. Keep confirmed
facts and assumptions in separate sentences. Leave alternatives and deferred
work out unless they block the unit.

The example below shows one filled step. It says what changes, where, and
what stays the same. It doesn't restate the issue in project-management
language.

```markdown
1. Edit `src/parser.ts`: replace the tokenizer behind `parse()`. The exported
   signature and output format stay the same.
```
