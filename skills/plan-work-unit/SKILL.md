---
name: plan-work-unit
description: >-
  Plan a tracker issue as a planning-only work unit. Use when the user
  explicitly asks to plan or replan an issue, such as "Plan #N" or "complete
  the issue contract and file an implementation plan." Treat the request as
  authorization for the planning-only writes, produce the authoritative work
  contract and one code-grounded implementation-plan comment, then stop; when a
  project restriction forbids those writes or the forge cannot perform them,
  report that as an error. Do
  not use for "Handle #N, implementation plan in comments," where the plan is
  implementation input, or for read-only assessment, overlap, and in-chat
  proposal requests that do not explicitly authorize planning mutations.
---

# Plan Work Unit

Turn an explicitly assigned issue-planning operation into a durable work
contract and one current implementation plan that a fresh implementation task
can follow. Planning is this operation's finish line; it never authorizes
implementation.

## Hold the routing boundary

- **Plan or replan an issue:** use this skill. "Plan #N" both selects and
  authorizes the planning operation; a project restriction can still narrow
  it (see below).
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

An explicit request to plan or replan an issue authorizes this operation's
planning-only writes: bringing the authoritative work-contract record to shape,
posting one implementation-plan comment, and making any invalidation or
retirement edit those require. Its finish line is the verified planning handoff,
with no branch or pull request; planning never authorizes implementation. A
directly assigned planning request is its own authorization, so it does not
require a separately declared planning stage.

Honor a project declaration that narrows this. When project instructions route
every issue or comment mutation through a pull request, forbid planning-only
writes, or declare an active stage whose allowed mutations exclude part of this
operation's surface, that restriction governs: report the conflict as an error
that names the restricting declaration, and stop before repository inspection or
artifact preparation rather than performing a permitted subset of the writes.
Read a declaration for what it actually routes. A generic default that ends
work units changing code, docs, assets, or project state at an open pull
request governs those deliverables, not this operation: a workflow that itself
directs contracts or deferred work into tracker issues has not routed issue or
comment mutations through pull requests. Only a declaration that speaks to
issue or comment writes, or to this operation's planning handoff, restricts
this surface. Absent such a restriction, proceed.

## Establish the planning surface

Verify the planning preconditions first, from the project instructions and the
forge alone, before inspecting the repository or preparing any artifact: no
project restriction above forbids the operation's mutation surface, the
contemplated contract record, plan comments, and invalidation targets named
above; and the forge offers the write capabilities that surface needs.

That mutation surface is fixed by the operation, not discovered by
inspection: any run can find, only after inspecting code, that the contract
or a prior plan must change, so an active stage authorizing only part of the
surface is a restriction on the whole surface even when a particular run would
touch just the authorized part. If a restriction covers any part of the
surface, or project policy routes this operation's writes or its handoff
through a pull request, report
the error above and stop: do not perform even a permitted subset of the writes,
do not begin that different branch-and-PR operation, and do not prepare
ready-to-post contract or plan text.

With the preconditions verified, read the entire issue, including
existing plan comments and linked decisions. Inspect the relevant code,
interfaces, tests, documentation, declared dependencies, and verification
commands. Do not infer the implementation from the issue title or produce a
repository-agnostic outline.

Record the repository revision you inspected, such as a commit identifier or
platform equivalent, resolved from the project-declared planning base or the
repository host's authoritative default-branch reference. This revision is the
plan's provenance: it lets a later implementer check whether the plan has gone
stale, so record one that can be re-checked, not a mutable local branch or
working snapshot.

Identify the authoritative work-contract record from project instructions. Use
the project-designated record when one exists; otherwise select the issue body.
Keep that selection explicit and unchanged through preparation, planning writes,
post-write verification, plan publication, and the final handoff.

Discover the project's current coordination model from its instructions,
records, code boundaries, architecture, and recent work-unit evidence. Plans
are evidence of intended work, not proof of safe concurrency or ordering. When
the evidence conflicts, name the conflict and use the project's safe default.

Confirm the requested operation, repository, issue state, forge write
capabilities, and any dependency or authorization blocker. Do not claim the
issue, create an implementation branch, edit implementation files, or open a
pull request.

## Write the contract and plan

Write the contract record and the plan comment with ordinary care, not a lock.
Prefer an append or field-scoped edit over a whole-body replacement, so a
concurrent owner edit is not overwritten; on a last-write-wins forge a
whole-body write can still lose a concurrent edit and no reread detects that, so
do not claim it cannot happen. After writing, confirm the write reached the
intended target with the intended content, and that exactly one current plan
exists where a plan should; report a failed, wrong-target, or duplicate-plan
result as an unsafe state rather than claiming completion.

The plan is grounded in the revision you recorded, and that grounding is
provenance, not a guarantee: the repository moves between planning and
implementation, and no write-time check closes that gap. Do not invent a lock
the project has not defined, re-inspect to chase a moving reference, or repair
drift automatically; when a project declares a serialization or
exclusive-ownership model, follow it. Carry the grounding revision into the
handoff and the invalidation criteria into the plan, so a later task can tell
whether the plan still holds.

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
editing is unavailable. Reread to confirm the exact former plan is visibly
blocked or deprecated and that no competing plan remains current. If that
verification fails, report the still-actionable plan as an unsafe state
requiring manual action. Do not invent a replacement plan merely to retire the
stale one.

On any replan, once evidence establishes that the existing plan is invalid,
retire it before publishing a replacement: mark the exact current plan blocked
or deprecated and confirm that retirement by reread, then update the contract
if needed and publish the replacement plan. If any later write or verification
fails, stop with the old plan already non-current and report the partial state;
never rely on a later replacement write to retire known-stale instructions.

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
4. **Risks and invalidation:** likely failure modes, assumptions, and the
   concrete changes since the grounding revision that require replanning; this
   is how a later task detects the plan has gone stale.
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
handoff artifact. A publication path that fails only after earlier planning
writes have persisted is not that precondition error: follow the
retirement-first rule above, stop with the old plan visibly non-current, and
report the partial unsafe state, including the prepared replacement text the
failed write was meant to publish.

## Report the handoff

Verify that the authoritative contract record selected earlier, either the
issue body or the project-designated record, contains the complete contract.
Separately verify that the issue contains one unambiguous current plan. When
both verifications succeed, report their locations and any implementation
blocker plus the repository revision the plan is grounded in. If the
authoritative default-branch reference has advanced past that revision, say so
and recommend the implementer verify the plan against current code or request a
replan; do not reinspect and republish here. Then explicitly state that planning
is finished and implementation was not started or authorized.

When missing information or an owner decision prevented a truthful contract or
code-grounded plan, verify any required prior-plan invalidation, report the
precise blocker, and state that planning is blocked, not finished. If the prior
plan remains actionable, identify that unsafe state and its location instead
of presenting a clean blocked handoff. Do not present an incomplete selected
contract record as the planning handoff. In either outcome, do not continue
into implementation in the same operation.

A failed planning precondition (a project restriction that forbids part of the
mutation surface, or an absent forge write capability), detected before any
planning write has persisted, never reaches this handoff: report it as an error
the moment it is detected, not as a blocked or finished planning result, and
never with prepared artifacts standing in for the writes the environment
refused.
Once a planning write has persisted, a later write failure is the partial
unsafe state the rules above already report, not a precondition error.
