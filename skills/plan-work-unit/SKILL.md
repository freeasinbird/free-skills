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
2. Check the issue for occupancy, and stop if someone holds it.
3. Read the whole issue, resolve the grounding revision, then inspect that
   exact repository tree.
4. Retire and verify any stale plan before changing the contract.
5. Complete the authoritative work-contract record, written plainly, and
   check any Dependencies field you wrote.
6. Post one current plan, written plainly.
7. Verify the writes, report the handoff, and stop.

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
comment, and any required invalidation or retirement edit. The surface also
includes a coordination record when two conditions hold. The project's
instructions require that record before a unit is reserved or planned, and
they name the planner as a permitted writer. That record sits on the assigned
issue or on a partner issue the project's rule identifies, such as the active
unit it pairs with. Whether it is part of the surface comes from project
instructions alone; inspection only finds the partner issue. The planning handoff ends without a branch or pull request.

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
It is the partial unsafe state covered under `references/replan.md` §replan.

## Check Occupancy

After the write preconditions pass, check the assigned issue for occupancy
before source inspection or any planning write. Check only the assigned
issue, even when a planning write targets a partner issue. Use the project's
claim rules. Find those rules in its agent instructions, such as a Claiming
section in AGENTS.md or the coordination document it points to. Read them
before you check, and apply their lease expiry and release markers as
written.

An issue is occupied when it has an active claim or an open PR that links it.
Where the project defines no claim rules, an open PR that links the issue is
the only sign. Planning an occupied issue would replace the plan or contract
its holder is working from.

When the assigned issue is occupied, stop before inspection and before any
write. Send the blocked report (see
`references/handoff-report.md` §blocked-or-paused) with the Status
`#N planning blocked: occupied by <claim or PR>`. Name every claim and PR you
found, and say what clears each: the holder releases, the claim expires, or
the PR closes or merges. Planning can proceed only once all of them clear.
This is not a precondition error.

Leave any existing plan as it is, even one you found stale: its holder is
working from it, so don't mark it blocked or report it as an unsafe state. If
you already found it stale, say so in the report so the holder learns of it.

Check again right before the first planning write of any kind, such as a plan
retirement, a contract edit, a coordination record, an invalidation comment,
or the plan comment. If the assigned issue is now occupied, stop without
writing and report planning blocked the same way.

- **Only read.** Never post, edit, or release a claim, a claim label, or a
  PR. An expired claim doesn't block planning; leave it as it is.
- **Owner requests don't override.** An explicit "Plan #N" doesn't override
  an active claim or a linked open PR. The owner clears each claim through
  the project's release rule and closes or merges each PR, then asks again.
- **Partly checked occupancy.** Any occupancy you can see blocks. When the
  forge can't show claims or linked PRs, check what it can show, and proceed
  if nothing there occupies the issue. Either way, name each source you
  couldn't check in one line of the report. In a finished report, put it
  under **Not verified**, outside that section's two-bullet cap.

## Inspect and Record the Revision

After preconditions pass and the occupancy check lets planning proceed:

1. Read the whole issue, including plan comments and linked decisions.
2. Resolve and record an immutable grounding revision from the declared
   planning base or the repository host's authoritative default-branch
   reference. Use a commit identifier or platform equivalent before inspecting
   source content. A mutable local branch or working snapshot is not provenance.
3. Inspect that exact tree's relevant code, interfaces, tests, documentation,
   dependencies, and verification commands. Use revision-specific file reads,
   a read-only isolated snapshot, or the forge's source view, according to
   available capabilities. Ground every source-based claim in those reads;
   distinguish proposed paths and interfaces from ones that already exist.
   Do not infer an implementation from the title or write a generic outline.
4. Select the project-designated contract record. If none exists, select the
   issue body. Keep that selection explicit and fixed through the run.
5. Discover the coordination model from project instructions, records, code
   boundaries, architecture, and recent work-unit evidence. Plans show intent,
   not proof of safe concurrency or order. Name conflicting evidence and use
   the project's safe default. Project instructions may require a pairwise
   assessment against active units, and the assigned unit may lack one. If
   they name the planner as a writer, record the assessment on both issues in
   the project's form, then reread the conflict set. Otherwise name the
   missing record and the role the project says writes it. Report planning
   blocked when the record must exist before planning. When it must exist
   only before reservation, record it as a start blocker instead.
6. Confirm the operation, repository, issue state, write capability,
   dependencies, and authorization blockers. Do not post, edit, or release a
   claim on the issue, create an implementation branch, edit implementation
   files, or open a pull request.

A coordination record written in step 5 is a planning write like the others.
On a partner issue, change only the record: append it or edit that one field,
and leave the rest of the issue as it was. Follow Use Safe Write Hygiene, and
confirm both issues by reread. When the record lands in the selected contract record and a
stale plan exists, retire that plan first, as `references/replan.md` §replan requires.

Current forge records supply issue state, authorization, and coordination
evidence. Source-based claims about those boundaries still come from the
selected tree. An unchecked mutable checkout cannot stand in for that tree.

If no available route can read the selected tree, report planning blocked and
name the missing source access as a grounding gap. Do not substitute another
checkout or publish an unsupported contract or replacement plan. Apply
`references/replan.md` §blocked-replan when a prior plan needs invalidation.
This is not a write-precondition error.

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

When no such skill is available, read and follow the fallback rules in
`references/plan-comment.md` §plain-writing-fallback.

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

After writing or changing a Dependencies field (including on a partner issue
when planning changed its coordination record), read and follow
`references/dependencies-check.md` §dependencies-check before posting the plan.

When a blocker prevents a truthful replacement plan on an unoccupied issue,
read and follow `references/replan.md` §blocked-replan.

A complete contract may describe a unit whose implementation is blocked. A
known dependency or ordering blocker does not stop the planning handoff.
Record it in the contract and plan. Stop planning only when missing
information or an owner decision prevents a truthful contract or code-grounded
plan, or when the issue is occupied (see Check Occupancy). A coordination
record the project requires before planning, but reserves to another role, is
such missing information.

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

Search the issue for an existing implementation-plan comment before posting.
When evidence shows that the current plan is invalid, read and follow
`references/replan.md` §replan to retire it before changing the contract or
publishing a replacement.

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
- Put the grounding revision in the plan comment and the invalidation
  criteria in the plan.

## Report the Handoff

Before a finished report, verify that the selected authoritative record
contains the complete contract. Separately verify that the issue has one
unambiguous current plan. For every Dependencies field planning wrote, confirm
that any applicable check passed, or name it under **Not verified** when it
could not run. If verification fails, report the unsafe state under
`references/handoff-report.md` §blocked-or-paused instead.

- **Finished handoff:** read and follow `references/handoff-report.md`
  §finished.
- **Blocked or paused handoff (or mid-planning question):** read and follow
  `references/handoff-report.md` §blocked-or-paused.
- **Platform gates:** apply `references/handoff-report.md` §platform-gates to
  every handoff report.

Precondition errors never reach this section. After a finished, blocked, or
paused handoff, do not continue into implementation in the same operation.
