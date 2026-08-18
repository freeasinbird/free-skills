---
name: plan-work-unit
description: >-
  Plan a tracker issue as a planning-only work unit. Use when the user
  explicitly asks to plan or replan an issue, such as "Plan #N" or "complete
  the issue contract and file an implementation plan." Within a
  project-authorized planning-only workflow, produce the authoritative work
  contract and one code-grounded implementation-plan comment, then stop;
  otherwise report the failed planning precondition as an error. Do
  not use for "Handle #N, implementation plan in comments," where the plan is
  implementation input, or for read-only assessment, overlap, and in-chat
  proposal requests that do not explicitly authorize planning mutations.
---

# Plan Work Unit

Turn an explicitly assigned issue-planning operation into a durable work
contract and one current implementation plan that a fresh implementation task
can follow. When project workflow authorizes a planning-only stage, planning is
the finish line; it never authorizes implementation.

## Hold the routing boundary

- **Plan or replan an issue:** use this skill. "Plan #N" selects the planning
  operation; write authority remains conditional on the project-stage or
  workflow-override gate below.
- **Handle or implement an issue:** do not use this skill. A referenced
  implementation plan is input to that implementation operation.
- **Assess, check overlap, review, or propose here:** keep the operation
  read-only or in-chat unless the user explicitly authorizes planning
  mutations.
- **Treat referenced artifacts as input:** a plan, comment, issue, or
  specification does not become a mutation target unless the requested
  operation says to modify it.

Project instructions and explicit owner decisions govern this workflow. The
selected work-contract record is authoritative for the work unit; the issue
plan explains how to execute that contract and cannot silently change policy,
scope, dependencies, or authorization.

Use the planning-only finish line only when project instructions declare a
non-implementation planning stage, or another explicit project workflow
override, whose recorded allowed mutations cover every contemplated contract
record, plan comment, and invalidation target and whose exact finish line is
their verified handoff without a branch or pull request. A bare request to plan
an issue selects this operation but does not override the project's allowed
mutations or default finish line. Missing or partial authority is a failed
precondition of the invocation, not a planning outcome: report it as an error
that names the absent stage or override and the declaration that would supply
it, then stop before repository inspection or artifact preparation.

## Establish the planning surface

Verify the planning preconditions first, from the project instructions and the
forge alone, before inspecting the repository or preparing any artifact: the
planning-stage declaration or explicit override above covers the operation's
whole potential mutation surface, the contemplated contract record, plan
comments, and invalidation targets named above, and ends at the planning
finish line; a conflict guard satisfying "Write against fresh forge state" is
available; and the forge offers the write capabilities that surface needs.

That mutation surface is fixed by the operation, not discovered by
inspection: any run can find, only after inspecting code, that the contract
or a prior plan must change, so a stage authorizing only part of the surface
is partial authority even when a particular run would touch just the
authorized part. If any precondition fails, or project policy still routes
the handoff through a pull request, report the error above and stop: do not
perform even a permitted subset of the writes, do not begin that different
branch-and-PR operation, and do not prepare ready-to-post contract or plan
text.

With the preconditions verified, read the entire issue, including
existing plan comments and linked decisions. Inspect the relevant code,
interfaces, tests, documentation, declared dependencies, and verification
commands. Do not infer the implementation from the issue title or produce a
repository-agnostic outline.

Resolve and record the immutable repository revision used for that inspection,
such as a commit identifier or platform equivalent. Resolve it from the
project-declared planning base, or otherwise from the repository host's
authoritative default-branch reference. Query or refresh that authoritative
source directly; do not treat an unverified local branch, cached remote-tracking
reference, mutable working snapshot, or revision that cannot be checked again
as current. Also record the moving authoritative reference whose value selected
the inspected revision.

Identify the authoritative work-contract record from project instructions. Use
the project-designated record when one exists; otherwise select the issue body.
Keep that selection explicit and unchanged through preparation, guarded writes,
post-write verification, plan publication, and the final handoff.

Discover the project's current coordination model from its instructions,
records, code boundaries, architecture, and recent work-unit evidence. Plans
are evidence of intended work, not proof of safe concurrency or ordering. When
the evidence conflicts, name the conflict and use the project's safe default.

Confirm the requested operation, repository, issue state, forge write
capabilities, and any dependency or authorization blocker. Do not claim the
issue, create an implementation branch, edit implementation files, or open a
pull request.

## Write against fresh forge state

Before any planning write, require one conflict guard that covers both the
moving authoritative repository reference and the complete mutable
planning-input surface through every write and its verification. The planning
surface includes issue bodies, project-designated contract records, plan
comments, invalidation comments, every issue comment and other contract-bearing
record used to prepare the contract or plan, their collection membership, and
the complete current-plan set. Use either a project mechanism that grants
exclusive mutation ownership for the repository reference and that whole
planning surface, or an operation that atomically rejects the publication if
either the repository reference or any guarded planning resource changes. A
fresh read, a planning-only lock, or separate repository and forge checks do
not close the cross-system read/write race. If no guard spans both systems,
the guard precondition has failed: report the error and stop without mutating,
never a blocked planning outcome.

Immediately after entering the guarded boundary, query the authoritative
moving project reference again and require it to equal the inspected immutable
revision. If it moved before the guard took effect, repeat the affected
repository inspection at the new revision, reprepare the contract and plan,
and then enter a new full-surface guard and reread the planning records. Do not
publish artifacts prepared from the superseded revision.

Inside the guarded boundary, reread the issue, every issue comment, and every
other mutable contract-bearing record used during planning. Compare the
collection membership and each record's identity, status, and content or
version, including every write target and current plan, with the state used to
prepare the write. Reconcile any change and repeat the guarded read. If the
guard cannot cover every planning input, write target, and collection invariant
the operation affects, do not mutate: a guard that cannot span the discovered
surface is the same failed precondition, reported as an error even when it is
found this late, never as a blocked planning outcome.

Treat a write's returned object as untrusted until an authoritative post-write
reread confirms the exact target identity and persisted content, preserves
concurrent owner text, and shows one unambiguous current plan when a plan should
exist. A mismatch, failed guard, or cross-resource collision is an explicit
unsafe state: stop, report the affected resources, and never claim completion.
Do not attempt a compensating write unless it uses a newly verified guard that
satisfies the same full-surface requirements.

As part of that post-write verification, query the authoritative moving project
reference again while the full-surface guard remains in effect. If it no longer
matches the inspected revision, treat the guard as failed and do not claim a
code-grounded handoff. Under a newly verified full-surface guard, make every
artifact published from the superseded revision visibly non-current. Preserve
freshly reread owner text while marking the selected contract record's
code-grounded content blocked; never restore an earlier contract version as a
shortcut. Also block or deprecate the exact published plan, and name the
repository drift in both locations. Authoritatively reread both results; if
either compensation cannot be verified, report each still-actionable artifact
as an unsafe state. Repeat planning only after inspecting the new revision.

## Complete the authoritative contract

Bring the issue body, or the project-designated work-contract record, to the
shape the project requires. Preserve useful context and unrelated owner text.
At minimum, make these explicit when they apply:

- objective and testable acceptance criteria;
- non-goals and scope boundaries;
- affected public, data, configuration, workflow, or shared contracts;
- declared implementation, test, documentation, and generated paths;
- dependencies, blockers, and the evidence that satisfies them;
- serialization, mutual exclusion, branch ancestry, and integration order.

Reconcile stale claims against the repository before updating the contract.
If code reality changes the scope materially, update the contract rather than
letting the plan contradict it. If an owner decision is needed to resolve the
contract, record the precise blocker. On a blocked replan, before stopping,
prevent the previous plan from appearing current: edit it to mark it blocked
and name the invalidating fact, or post one linked invalidation comment when
editing is unavailable. Apply the guarded write and post-write verification
above, confirming that the exact former plan is visibly blocked or deprecated
and that no competing plan remains current. If verification fails, report the
still-actionable plan as an unsafe state requiring manual action. Do not invent
a replacement plan merely to retire the stale one.

On any replan, once evidence establishes that the existing plan is invalid,
prevent it from remaining actionable before attempting its replacement. Either
use one atomic guarded operation that persists the retirement, any changed
contract, and the replacement plan together, or first mark the exact current
plan blocked or deprecated and verify that retirement under the full-surface
guard. Only then update the contract when needed and publish the replacement
plan. If any later write or verification fails, stop with the old plan already
non-current and report the partial state; never rely on a later replacement
write to retire known-stale instructions.

A complete contract may describe a unit whose implementation is blocked. A
known dependency or ordering blocker does not prevent the planning handoff;
record it in the contract and plan. Stop planning only when missing information
or an owner decision prevents a truthful contract or code-grounded plan.

## Author one current implementation plan

Post the plan only after the contract is complete, whether implementation is
startable or explicitly blocked. Start it by naming the selected authoritative
work-contract record and stating that the plan is an implementation aid.
Include:

1. **Startability:** open blockers, satisfied dependencies, required
   serialization, and what event permits implementation to start.
2. **Change steps:** ordered edits grounded in real repository paths and
   current code, with the affected interfaces or contracts named at the step
   that changes them.
3. **Verification:** targeted behavioral checks plus the project's standard
   lint, format, build, test, generated-file, or integration checks.
4. **Risks and invalidation:** likely failure modes, assumptions, and concrete
   changes that require replanning.
5. **Finish line:** the project's implementation handoff endpoint, while
   stating that this planning operation does not begin it.

Make the plan startable by a fresh task. Name exact paths where evidence
supports them, distinguish confirmed facts from assumptions, and keep
alternatives or deferred work out of the execution sequence unless they block
the unit.

## Keep a single current plan

Search the issue for an existing implementation-plan comment before posting.
On replanning, apply the retirement-first rule above to any plan already known
invalid, then edit its comment into the replacement when the forge supports
comment editing. If editing is unavailable, post one superseding comment that
links to the retired plan and explicitly identifies itself as the only current
plan; do not leave competing comments that both appear current. Use whatever
forge API, CLI, or interface is available, without assuming a platform-specific
tool.

If the available environment cannot perform the authorized planning writes,
and no planning write has yet mutated state, that missing capability is a
failed precondition: report it as an error naming the capability, never as a
blocked or complete planning outcome, and do not present prepared text as a
handoff artifact. A publication path that fails only after earlier guarded
writes have persisted is not that precondition error: follow the
retirement-first rule above, stop with the old plan visibly non-current, and
report the partial unsafe state, including the prepared replacement text the
failed write was meant to publish.

## Report the handoff

Verify that the authoritative contract record selected earlier, either the
issue body or the project-designated record, contains the complete contract.
Separately verify that the issue contains one unambiguous current plan. When
both verifications succeed, report their locations and any implementation
blocker plus the verified repository revision, then explicitly state that
planning is finished and implementation was not started or authorized.

When missing information or an owner decision prevented a truthful contract or
code-grounded plan, verify any required prior-plan invalidation, report the
precise blocker, and state that planning is blocked, not finished. If the prior
plan remains actionable, identify that unsafe state and its location instead
of presenting a clean blocked handoff. Do not present an incomplete selected
contract record as the planning handoff. In either outcome, do not continue
into implementation in the same operation.

A failed planning precondition (missing or partial authority, no spanning
conflict guard, or absent write capability), detected before any planning
write has persisted, never reaches this handoff: report it as an error the
moment it is detected, not as a blocked or finished planning result, and never
with prepared artifacts standing in for the writes the environment refused.
Once a guarded write has persisted, a later write failure is the partial
unsafe state the rules above already report, not a precondition error.
