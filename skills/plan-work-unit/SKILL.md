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

Turn one explicitly assigned issue into a complete contract and one current,
code-grounded implementation plan. The verified planning handoff is the finish
line. A fresh implementation task can use it, but planning never authorizes
implementation.

Use this skill for "Plan #N" or "replan #N." Do not use it for "Handle #N,
implementation plan in comments," where the plan is implementation input. Keep
assessment, overlap, review, and in-chat proposal requests read-only unless the
user explicitly authorizes planning writes.

Follow this procedure:

1. Verify preconditions from project instructions and the forge.
2. Read the whole issue, inspect the repository, and record the grounding
   revision.
3. Retire and verify any stale plan before changing the contract.
4. Complete the authoritative work-contract record, written plainly.
5. Post one current plan, written plainly.
6. Verify both writes, report the handoff, and stop.

## Hold the Routing Boundary

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

## Check Preconditions and Restrictions

Project instructions and explicit owner decisions govern this workflow. A
direct plan or replan request authorizes its planning-only writes. It does not
require a separately declared planning stage.

The authoritative work-contract record is the selected source of truth for the
unit. The issue plan is an implementation aid. It cannot silently change the
contract's policy, scope, dependencies, or authorization.

Planning-only writes have a fixed mutation surface: the contract, one plan
comment, and any required invalidation or retirement edit. The planning
handoff ends without a branch or pull request.

A project restriction governs when it does any of the following:

- Routes every issue or comment mutation through a pull request.
- Forbids planning-only writes.
- Declares an active stage whose allowed mutations exclude any part of the
  fixed surface.

Read each declaration for what it actually routes:

- A generic open-PR default for code, docs, assets, or project state does not
  restrict this operation.
- Only a declaration about issue or comment writes, or the planning handoff,
  restricts this surface.

A precondition failure is either a restriction on any part of the surface or
a forge that lacks a required write capability. Check these preconditions
first, using only project instructions and the forge.

Report the failure as an error. Name the restricting declaration and uncovered
targets, or name the missing capability. State what change would make the
precondition pass. Stop before repository inspection or artifact preparation.
Do not perform a permitted subset, start a branch-and-PR detour, or prepare
contract or plan text.

The operation fixes the whole mutation surface before inspection. A stage
that permits only one target still restricts the whole operation. If no such
restriction exists and the forge supports the writes, proceed.

Once a planning write persists, a later failure is not a precondition error.
It is the partial unsafe state covered under Replan.

## Inspect and Record the Revision

After preconditions pass:

1. Read the whole issue, including plan comments and linked decisions.
2. Inspect the relevant code, interfaces, tests, documentation, dependencies,
   and verification commands. Do not infer an implementation from the title or
   write a repository-agnostic outline.
3. Record a re-checkable grounding revision, such as a commit identifier or
   platform equivalent. Resolve it from the declared planning base or the
   repository host's authoritative default-branch reference. This revision is
   provenance for later staleness checks, not a mutable local branch or working
   snapshot.
4. Select the project-designated contract record. If none exists, select the
   issue body. Keep that selection explicit and fixed through the run.
5. Discover the coordination model from project instructions, records, code
   boundaries, architecture, and recent work-unit evidence. Plans show intent,
   not proof of safe concurrency or order. Name conflicting evidence and use
   the project's safe default.
6. Confirm the operation, repository, issue state, write capability,
   dependencies, and authorization blockers. Do not claim the issue, create an
   implementation branch, edit implementation files, or open a pull request.

## Write the Contract and Plan Plainly

The contract and the plan comment are read by people who did not watch the
planning. Write both so a busy reader understands them on the first pass.

Use the write-plainly skill when it is loaded or your platform can load it.
Apply it to the contract text and the plan comment, and read its plan example.
Apply it by default; don't wait for the user to ask for plain output. Keep
the required headings, terms, and order exact, whether they come from the
project's own format or from this skill. They are project wording, so
write-plainly leaves them alone: plain prose rewrites the sentences under a
heading, never the heading itself.

When no such skill is available, follow these rules instead:

- Lead with the point. Put the decision, blocker, or change first, and the
  reason after it.
- Put one thought in each sentence. Prefer a new sentence to a joined clause.
- Use ordinary words and active verbs: "edit," "run," "fix," not
  "remediate," "surface," or "make a determination."
- Cut agent jargon and process language. Say what changes, where, and what
  stays the same. Don't restate the issue in project-management terms.
- Name the exact path, command, or interface when the reader has to go there.
  Keep those identifiers exact.
- Keep every requirement, caveat, number, and step. Plain doesn't mean
  shorter at the cost of a fact.
- Write for a fresh task. Restore the context a later reader needs; a chat
  reply can lean on the conversation, a plan comment can't.

## Complete the Authoritative Contract

Bring the selected authoritative record to the shape the project requires.
Preserve useful context and unrelated owner text. At minimum, make these
explicit when they apply:

- Objective and testable acceptance criteria.
- Non-goals and scope boundaries.
- Affected public, data, configuration, workflow, or shared contracts.
- Declared implementation, test, documentation, and generated paths.
- Dependencies, blockers, and the evidence that satisfies them.
- Serialization, mutual exclusion, branch ancestry, and integration order.

Reconcile stale claims against the repository first. If code reality changes
the scope, update the contract instead of letting the plan contradict it. If
an owner decision is needed, record the precise blocker.

### Blocked Replan

When a blocker prevents a truthful replacement plan:

1. Edit the old plan to mark it blocked and name the invalidating fact. If
   editing is unavailable, post one linked invalidation comment.
2. Reread the exact plan. Confirm it is visibly blocked or deprecated and no
   competing plan remains current.
3. Report failed verification as an unsafe state that needs manual action.
4. Do not invent a replacement only to retire a stale plan.

A complete contract may describe a unit whose implementation is blocked. A
known dependency or ordering blocker does not stop the planning handoff. Record
it in the contract and plan. Stop planning only when missing information or an
owner decision prevents a truthful contract or code-grounded plan.

## Post One Current Plan

Post the plan only after the contract is complete, whether implementation is
startable or blocked. Start by naming the authoritative work-contract record
and saying the plan is an implementation aid. Include:

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

- Make the plan startable by a fresh task.
- Name exact paths where evidence supports them.
- Separate confirmed facts from assumptions.
- Keep alternatives and deferred work out of the sequence unless they block
  the unit.

Use the shape the project requires for plan comments. When it requires none,
use the template in `references/plan-comment.md` §plan-comment. Either shape
keeps the five parts above and writes their prose under Write the Contract and
Plan Plainly.

### Replan

Search the issue for an existing implementation-plan comment before posting.
Use retirement-first when evidence shows that the current plan is invalid:

1. Retire the exact current plan before publishing its replacement. Mark it
   blocked or deprecated, then confirm the retirement by reread. Update the
   contract if needed only after the old plan is non-current.
2. Edit the retired comment into the replacement when the forge supports it.
   Otherwise, post one superseding comment that links the retired plan and
   identifies itself as the only current plan. Never leave competing current
   comments.
3. If a later write or verification fails, stop with the old plan non-current.
   Report the partial unsafe state and include the prepared replacement text.
   State that planning is blocked, not complete.

Never rely on a later replacement write to retire stale instructions. Use any
available forge API, CLI, or interface without assuming a platform-specific
tool.

## Use Safe Write Hygiene

- Write the contract and plan with ordinary care, not an invented lock.
- Prefer an append or field-scoped edit over a whole-body replacement.
- On a last-write-wins forge, a whole-body write can lose a concurrent edit.
  No reread detects that loss, so do not claim otherwise.
- Confirm each write reached the intended target with the intended content.
  Also confirm that exactly one current plan exists.
- Report a failed, wrong-target, or duplicate result as an unsafe state.
- Treat the grounding revision as provenance, not a guarantee. Repository
  movement leaves a gap that no write-time check closes.
- Do not invent a lock, reinspect to chase a moving reference, or repair drift
  automatically. Follow any declared serialization or exclusive-ownership
  model.
- Put the grounding revision in the handoff and the invalidation criteria in
  the plan.

## Report the Handoff

### Finished

1. Verify that the selected authoritative record contains the complete
   contract.
2. Separately verify that the issue has one unambiguous current plan.
3. Report both locations, any implementation blocker, and the grounding
   revision.
4. If the default branch has advanced, say so and recommend verification or a
   replan. Do not reinspect and republish here.
5. State that planning is finished and implementation was not started or
   authorized.

### Blocked

1. Verify any required prior-plan invalidation and report the precise blocker.
2. State that planning is blocked, not finished.
3. If the prior plan remains actionable, report its location as an unsafe
   state.
4. Never hand off an incomplete authoritative record.

Precondition errors never reach this section. After a finished or blocked
handoff, do not continue into implementation in the same operation.
