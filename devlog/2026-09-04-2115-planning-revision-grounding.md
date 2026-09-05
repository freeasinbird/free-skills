# Bind Planning Claims to the Inspected Tree

Issue #237 corrects the provenance step in plan-work-unit. The old sequence
inspected source before resolving the authoritative revision, so checkout A
could supply a plan labeled as revision B.

Choose the immutable planning revision first, then inspect that tree. Allow
revision-specific reads, an isolated read-only snapshot, or a forge source
view. No particular platform or implementation branch is required. If that
tree cannot be read, planning is blocked by missing source evidence.

This preserves the decision in
`2026-08-18-2149-planning-gate-relaxation.md`: provenance without locks or
moving-base loops, planning-only authorization, retirement-first replan, one
current plan, and honest whole-body-write limits. A later base move keeps the
original provenance and requires a handoff warning, not another inspection.
The plain-writing and fixed-heading decisions in
`2026-09-01-1445-plan-work-unit-plain-writing.md` also remain in force.

Rejected recording the remote SHA after local inspection because an identifier
cannot establish which content supplied a claim. Rejected a mandatory worktree
because revision-specific reads can provide the same evidence without one.
Current forge records still establish authorization and coordination; immutable
source reads establish code facts.

The revision fixtures use real commits with different source and test paths.
Their setup helper prepares runnable inputs, while the evaluation runner owns
isolation, tracker operations, and read traces. Structural checks cannot prove
that an agent used the selected tree.

Independent review confirmed two fixture leaks: the advance clone exposed B
through its local main, and task inputs disclosed the source layout being
tested. Create advance before B exists and keep source-layout answers in the
trees and grading criteria. The helper's removal path only touches two files
it created inside a new temporary repository; review found no caller-supplied
deletion target.

Revisit when exact-tree reads still produce misattributed claims in observed
runs, or a host cannot expose immutable source content through any available
capability.
