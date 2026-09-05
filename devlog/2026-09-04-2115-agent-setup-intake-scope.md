# Keep Agent Setup Within the Request

Issue #240 separates two decisions: whether the user requested agent setup,
and which setup facts the repository already supplies.

Chose a scope check before file-state routing over a scaffold-only mode.
A standalone PR-template or CONTRIBUTING.md request should not enter Init
because AGENTS.md is absent, or Update because it is managed. Explicitly
loading the skill does not expand that request. The skill exits without
directing scaffold execution or importing setup policy into the task.

Chose source inspection before factual questions over asking the owner to
repeat build, test, run, lint, format, runtime, and CI facts. Intake checks
definitions and paths without requiring full builds or tests. Source
verification and successful execution remain separate claims. Conflicting
sources and missing facts need questions; profile and policy choices still
belong to the owner.

Rejected a prescriptive intake gate in the entry point. An earlier revision
added a five-category inventory, a wait-for-answers rule, and an adoption
clause after model runs completed setup without asking about a missing run
command. Runs at two effort levels ignored the longer text too, so the extra
rules bought no compliance and drew review findings about adoption ordering.
The entry point keeps one sentence on evidence-first intake and the reference
carries the detail; the missing-fact case stays in the evals as a known gap.

The [core split](2026-09-01-1445-agent-setup-core-split.md) keeps routing in the
short entry point and intake detail in its step-local reference. The
[profile and boundary decisions](2026-07-24-2308-agent-setup-instruction-defects.md)
still protect Standard's absent devlog, marker validation, and existing
scaffold content. [Explicit reassessment](2026-08-15-1326-explicit-coordination-reassessment.md)
remains a separate request; intake does not authorize coordination changes
or rewrites of unmanaged build guidance during ordinary updates.

Revisit when a separately requested scaffold workflow needs its own skill,
source inspection repeatedly cannot distinguish current command guidance
from stale project documentation, or the missing-fact intake case gains a
fix that a model run demonstrates rather than more prompt text.
