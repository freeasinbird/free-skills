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

- **Plan or replan an issue:** use this skill. "Plan #N" or "replan #N"
  selects and authorizes planning; a project restriction can still narrow it
  (see below).
- **Handle or implement an issue:** do not use this skill. For requests like
  "Handle #N, implementation plan in comments," a referenced plan is
  implementation input.
- **Assess, check overlap, review, or propose here:** keep the request
  read-only or in-chat unless the user explicitly authorizes planning writes.
- **Treat referenced artifacts as input:** a plan, comment, issue, or spec is
  not a mutation target unless the request says to modify it.

## Check Preconditions and Restrictions

Project instructions and explicit owner decisions govern this workflow. A
direct plan or replan request authorizes planning-only writes without a
separately declared planning stage.

The authoritative work-contract record is the unit's source of truth. The
issue plan is an implementation aid and cannot silently change the contract's
policy, scope, dependencies, or authorization.

Planning-only writes have a fixed mutation surface: the contract, one plan
comment, and any required invalidation or retirement edit. It also includes a
coordination record when project instructions both require that record before
reservation or planning and name the planner as a permitted writer. That
record sits on the assigned issue or a partner issue the rule identifies, such
as the paired active unit. Project instructions alone decide whether it joins
the surface; inspection only finds the partner issue. Planning ends without a
branch or pull request.

A project restriction governs when it:

- Routes every issue or comment mutation through a pull request.
- Forbids planning-only writes.
- Declares an active stage whose allowed mutations exclude any part of the
  fixed surface.

Read each declaration for what it routes: a generic open-PR default for code,
docs, assets, or project state does not restrict planning. Only a declaration
about issue or comment writes, or the planning handoff, restricts this
surface.

Check preconditions first, using only project instructions and the forge. The
whole surface is fixed before inspection, so a stage permitting only one
target still restricts the whole operation. A precondition failure is a
restriction on any part of the surface or a forge lacking a required write
capability.

Report a precondition failure as an error: name the restricting declaration
and uncovered targets, or the missing capability, and state what change lets
it pass. Stop before inspection or drafting; do not perform a permitted
subset, start a branch-and-PR detour, or prepare contract or plan text. If no
restriction applies and the forge supports the writes, proceed.

Once a planning write persists, a later failure is not a precondition error;
it is the partial unsafe state under `references/replan.md` §replan.

## Check Occupancy

After preconditions pass, check the assigned issue for occupancy before source
inspection or any planning write. Check only the assigned issue, even when a
write targets a partner issue. Read the project's claim rules first (such as a
Claiming section in AGENTS.md or its linked coordination doc) and apply their
lease expiry and release markers as written.

An issue is occupied when it has an active claim or a linked open PR. Without
project claim rules, a linked open PR is the only sign. Planning an occupied
issue would replace the contract or plan its holder works from.

If occupied, stop before inspection and before any write. Send the blocked
report (`references/handoff-report.md` §blocked-or-paused) with Status
`#N planning blocked: occupied by <claim or PR>`. Name every claim and PR
found and what clears each: the holder releases, the claim expires, or the PR
closes or merges. Planning proceeds only once all clear. This is not a
precondition error.

Leave any existing plan untouched, even if stale: its holder works from it, so
don't mark it blocked or report an unsafe state. If you already found it
stale, say so in the report so the holder learns of it.

Recheck right before the first planning write of any kind (plan retirement,
contract edit, coordination record, invalidation comment, or plan comment). If
the issue is now occupied, stop without writing and send the same blocked
report.

- **Only read.** Never post, edit, or release a claim, claim label, or PR. An
  expired claim doesn't block planning; leave it as it is.
- **Owner requests don't override.** "Plan #N" doesn't override an active
  claim or linked open PR. The owner clears each claim under the project's
  release rule and closes or merges each PR, then asks again.
- **Partly checked occupancy.** Any visible occupancy blocks. If the forge
  can't show claims or linked PRs, check what it can show and proceed if
  nothing there occupies the issue. Either way, name each unchecked source in
  one line of the report; in a finished report, put it under **Not verified**,
  outside that section's two-bullet cap.

## Inspect and Record the Revision

After preconditions pass and occupancy lets planning proceed:

1. Read the whole issue, including plan comments and linked decisions.
2. Resolve and record an immutable grounding revision (commit ID or platform
   equivalent) from the declared planning base or the host's authoritative
   default-branch ref before reading source. A mutable local branch or working
   snapshot is not provenance.
3. Inspect that exact tree's relevant code, interfaces, tests, docs,
   dependencies, and verification commands via revision-specific reads, a
   read-only isolated snapshot, or the forge's source view. Ground every
   source claim in those reads and distinguish proposed paths and interfaces
   from existing ones. Don't infer an implementation from the title or write a
   generic outline.
4. Select the project-designated contract record, or the issue body if none
   exists; keep that choice explicit and fixed for the run.
5. Discover the coordination model from project instructions, records, code
   boundaries, architecture, and recent work-unit evidence. Plans show intent,
   not proof of safe concurrency or order; name conflicts and use the
   project's safe default. When project instructions require a missing
   pairwise assessment against active units, record it on both issues in the
   project's form and reread the conflict set if they name the planner as a
   writer. If they don't, name the missing record and its owning role: report
   planning blocked if required before planning, or record a start blocker if
   required only before reservation.
6. Confirm the operation, repository, issue state, write capability,
   dependencies, and authorization blockers. Never post, edit, or release a
   claim, create an implementation branch, edit implementation files, or open
   a PR.

A step 5 coordination record is a planning write like the others. On a partner
issue, change only that record (append or edit that field) and leave the rest
intact. Follow Use Safe Write Hygiene and confirm both issues by reread. If it
lands in the selected contract record while a stale plan exists, retire that
plan first (`references/replan.md` §replan).

Current forge records supply issue state, authorization, and coordination
evidence, while source-based claims about those boundaries still come from the
selected tree; an unchecked mutable checkout cannot stand in for it.

If no available route can read the selected tree, report planning blocked and
name the missing source access as a grounding gap. Never substitute another
checkout or publish an unsupported contract or replacement plan. Apply
`references/replan.md` §blocked-replan if a prior plan needs invalidation.
This is not a write-precondition error.

## Write the Contract and Plan Plainly

Write both the contract and the plan comment so a busy reader who did not
watch the planning understands them on the first pass.

Apply the write-plainly skill by default whenever it is loaded or loadable;
read its plan example, and don't wait to be asked. Keep required headings,
terms, and order exact (whether from the project's format or this skill):
plain prose rewrites sentences under a heading, never the heading itself.

When write-plainly is unavailable, read and follow
`references/plan-comment.md` §plain-writing-fallback.

## Complete the Authoritative Contract

Bring the selected authoritative record to the project's required shape while
preserving useful context and unrelated owner text. At minimum, make these
explicit when they apply:

- Objective and testable acceptance criteria.
- Non-goals and scope boundaries.
- Affected public, data, configuration, workflow, or shared contracts.
- Declared implementation, test, documentation, and generated paths.
- Dependencies, blockers, and the evidence that satisfies them.
- Serialization, mutual exclusion, branch ancestry, and integration order.

Reconcile stale claims against the repository first. Update the contract when
code reality changes scope rather than letting the plan contradict it, and
record the precise blocker when an owner decision is needed.

After writing or changing a Dependencies field (including on a partner issue
whose coordination record changed), read and follow
`references/dependencies-check.md` §dependencies-check before posting the
plan.

When a blocker prevents a truthful replacement plan on an unoccupied issue,
read and follow `references/replan.md` §blocked-replan.

A complete contract may describe an implementation-blocked unit: a known
dependency or ordering blocker does not stop the planning handoff, so record
it in the contract and plan. Stop planning only when missing information or an
owner decision prevents a truthful contract or code-grounded plan, or when the
issue is occupied (see Check Occupancy). A coordination record required before
planning but reserved to another role counts as missing information. Ask a
mid-planning question only before any planning write persists; after one does,
report planning blocked instead
(`references/handoff-report.md` §blocked-or-paused).

## Post One Current Plan

Post the plan only after the contract is complete, whether implementation is
startable or blocked. Open by naming the authoritative work-contract record
and stating the plan is an implementation aid. Include:

1. **Startability:** open blockers, satisfied dependencies, required
   serialization, and what event permits implementation to start.
2. **Change steps:** ordered edits grounded in real paths and current code,
   naming affected interfaces or contracts at the step that changes them.
3. **Verification:** targeted behavioral checks plus the project's standard
   lint, format, build, test, generated-file, or integration checks.
4. **Risks and invalidation:** likely failure modes, assumptions, and concrete
   changes since the grounding revision that require replanning; a later task
   uses this list to detect staleness.
5. **Finish line:** the project's implementation handoff endpoint, stating
   that this planning operation does not start it.

Make the plan startable by a fresh task: name exact paths where evidence
supports them, separate confirmed facts from assumptions, and keep
alternatives and deferred work out of the sequence unless they block the unit.

Use the project's required plan-comment shape, or
`references/plan-comment.md` §plan-comment when none is required. Either shape
keeps the five parts above and follows Write the Contract and Plan Plainly.

Check the issue for an existing implementation-plan comment before posting.
When evidence shows the current plan is invalid, read and follow
`references/replan.md` §replan to retire it before changing the contract or
publishing a replacement.

## Use Safe Write Hygiene

- Prefer an append or field-scoped edit over a whole-body replacement.
- On a last-write-wins forge, a whole-body write can lose a concurrent edit;
  no reread detects that loss, so don't claim otherwise.
- Confirm each write reached its target with the intended content and that
  exactly one current plan exists; report any failed, wrong-target, or
  duplicate result as an unsafe state.
- Treat the grounding revision as provenance, not a guarantee: repository
  movement leaves a gap no write-time check closes.
- Write with ordinary care and follow any declared serialization or
  exclusive-ownership model; never invent a lock, reinspect to chase a moving
  ref, or repair drift automatically.
- Record the grounding revision and invalidation criteria in the plan comment.

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
