# Plan-work-unit plain writing: skill gate plus inline fallback

Issue #206 makes plan-work-unit write the work contract and the
implementation-plan comment plainly by default. This note is mandatory
because the change is a cross-project prompt decision: every project that
loads plan-work-unit inherits the new writing rules and the plan-comment
shape.

## Decisions

- Gate on a loadable write-plainly skill, and carry an inline fallback list
  of its core rules. The gate names the capability (a skill the platform can
  load) rather than a platform, so an agent without skills still gets the
  rules.
- Keep the fallback short. It carries the rules that fix the observed
  failure: lead with the point, one thought per sentence, ordinary words and
  active verbs, no agent jargon, exact paths, no dropped facts, and enough
  context for a fresh reader.
- Pin the required headings, terms, and order as project wording that plain
  writing leaves exact. Plain prose must not rename the parts a later task
  looks for.
- Put the plan-comment template in `references/plan-comment.md` instead of
  `SKILL.md`. The template is filled in at one step, so it does not need to
  sit in the procedure.
- Treat the template as the default, not the law. A project that requires its
  own plan-comment format wins; the required plan content moves into that
  shape. The heading-preservation rule follows the same line: write-plainly
  never rewrites a heading, but which headings apply comes from the project
  format when it has one.
- Split shape from content, and say so in the template. `SKILL.md` governs
  what each plan part must contain; `references/plan-comment.md` carries only
  the shape and prompts for those elements. The template's placeholders are a
  prompt, never the content spec.

## Rejected Options

- **Inline the rules only, with no skill gate.** The inline list would drift
  from write-plainly, and an agent that can load the skill would get the
  weaker copy.
- **Require write-plainly outright.** That breaks the platform-agnostic
  prompt invariant. An agent with no skill loader could not follow the
  instruction at all.
- **Point at write-plainly with no fallback.** Same failure, quieter: the
  instruction becomes a no-op wherever the skill is absent.
- **Impose the template unconditionally.** A downstream project with its own
  plan format would then hold two incompatible shapes, its own and this
  skill's. The template is the fallback instead, and the plain-writing
  section's heading rule defers the same way.
- **Let the template's placeholders enumerate the required content.** A
  placeholder that lists elements reads as the complete set, so any element it
  omits is silently dropped from the posted plan. Three placeholders had
  already drifted below what `SKILL.md` requires: satisfied dependencies,
  generated-file and integration checks, and likely failure modes. Naming
  `SKILL.md` as the content authority removes the second source of truth
  rather than resynchronizing the copy.

Revisit when write-plainly's core rules change, since the inline fallback is a
hand-kept copy of them, or when a project reports that the template's headings
conflict with a format it must use. Revisit the shape/content split if a
placeholder drifts below `SKILL.md` again; that would mean the split is not
holding and the template should stop paraphrasing the spec at all.
