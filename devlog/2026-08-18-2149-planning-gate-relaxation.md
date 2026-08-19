# Relax plan-work-unit's Default-Fail Preconditions

plan-work-unit refused to plan a work unit on a stock GitHub repo. A direct
"Plan #N" errored out on precondition 2 ("no spanning conflict guard") because
the skill demanded either exclusive cross-system mutation ownership or an
atomic write that aborts if `main` or any forge record moves, a primitive
GitHub does not offer, and it explicitly disqualified the achievable substitute
(fresh read-verify-write). Precondition 1 (a separately declared planning
stage) failed the same way by default. Net effect: on the platform the skill
targets, with no bespoke instrumentation, it could never plan an issue, its
sole purpose.

## Decision

This is the owner exercising the revisit condition recorded in
`2026-08-18-1430-planning-gate-error.md` (#136): "when precondition errors in
practice fire so often that the gate, not the reporting, is the defect." That
note deferred "relaxing the authority gate for owner-invoked single-writer
repos" as a separate owner decision; a live "Plan #N" run in this
single-writer repo made the gate itself the defect, so the decision is made
now.

Two changes, both narrowing the gate, not the safety:

- **Authorization.** A direct request to plan or replan an issue is its own
  authorization for the planning-only writes (contract record, one plan
  comment, invalidation/retirement edits), finish line at the planning handoff
  with no branch or PR. A separately declared planning stage is no longer
  required to _grant_; it can still _restrict_.
- **Concurrency and revisions.** The whole "publish safely" apparatus was a
  category error: it framed a per-issue planning write as a cross-system
  distributed transaction and grew prose to simulate a transaction manager
  GitHub cannot provide. It collapses to provenance plus write hygiene: record
  the inspected revision as the plan's provenance; prefer a scoped edit over a
  whole-body replace so a concurrent owner edit is not clobbered; confirm the
  write landed on the intended target and that one current plan exists; and at
  handoff report the grounding revision, flagging it when the base has advanced
  past it and recommending the implementer verify or replan. Removed entirely:
  the pre-write revision-equality check, the reinspect-and-reprepare loop, the
  post-write re-query gate, and the compensation choreography. A project that
  needs a hard concurrency guarantee declares a serialization/exclusivity model,
  which the skill then follows.

This landed in two passes: first a "thin read-verify-write" that still kept a
reread-before-write, a post-write re-query, and a drift flag; then the collapse
above, once the framing itself was named as the defect. The second pass is a
deliberate refusal to keep trimming clause by clause, because clause-trimming is
the same accretion in reverse. Findings that push the machinery back in (re-add
a lock, a race guard, compensation, a serialization requirement, or a post-write
revision re-check) are settled by this decision and get a reasoned decline, not
a fix; only genuine new defects (a real contradiction, a broken cross-reference,
lint, a factual doc error) earn a change.

What is unchanged: the fail-fast error shape from #136 still fires, up front,
for genuine configuration failures, a project restriction that routes all
mutations through a PR or forbids planning writes, an active stage whose
allowed mutations exclude part of the surface, or an absent forge write
capability. Retirement-first replan, single-current-plan, and the
no-implementation boundary are retained.

Why the downgrade is safe, stated honestly: the two prior guards protect
different things, so they fall differently. The teloleo-motivated shape-5
serialization work (#138) targets _concurrent implementation_ colliding on
shared code, which is not this skill's job (see Scope below), so scope alone
answers it. #136's spanning-guard precondition, by contrast, protected the
planning-time issue and comment writes themselves, so removing it must be
justified on the planning-time races, not on scope. Those races are two: a
repository advance that leaves the plan grounded in stale code, and a
last-write-wins overwrite of a concurrent issue-body edit. The first is handled by provenance, not a lock: the plan
reports its grounding revision and its invalidation criteria, so a later task
detects the staleness the seconds-wide planning-time window shares with the far
larger planning-to-implementation gap that no write-time check could close
anyway. The second is genuinely irreducible on a whole-body forge, a reread
cannot detect it, so the skill names it rather than claiming to catch it; a
scoped edit avoids it, and a project needing a hard guarantee declares
serialization. Neither race justifies a gate that bricks the skill on every
stock repo, and claiming a detection guarantee we cannot deliver is worse than
naming the residual race.

## Scope

plan-work-unit takes one already-existing issue (from wave planning or any
other mechanism) and makes it workable: a complete contract plus a code-grounded
plan. It is downstream of issue creation and upstream of implementation, so
cross-issue coordination (serialization across units, the shape-5 shared-contract
problem) belongs to the wave-planning/dispatch layer or to implementation, not
here. The skill may _record_ ordering and serialization constraints in the
contract as information for the implementer; it does not _enforce_ them with
cross-system locks. This scope is what makes the guard removal correct rather
than merely convenient.

## Rejected Alternatives

- **Declare fiat-dispatch exclusivity in free-skills' own AGENTS.md.** This
  would satisfy the gate for this repo only and leave every other stock GitHub
  repo unable to run the skill out of the box. The defect is in the skill's
  default, not in this repo's configuration.
- **Keep the guard, add a project-level exclusivity declaration requirement.**
  Same problem: it makes an unsatisfiable-by-default primitive a precondition
  for the skill's core function.

## Evidence

Live run in this repository: `/plan-work-unit` reported "Failed precondition 2:
no spanning conflict guard ... GitHub issue edits are last-write-wins with no
cross-system atomicity against main moving, and the project defines no such
mechanism." That is the gate refusing the skill's sole purpose, which is the
recorded revisit trigger.

## Refute-pass dispositions

A Codex review plus a fresh-context refute lens ran on PR 139's first draft.
All findings confirmed; none rejected-by-verification; the owner decision (no
lock, accept the residual race) was not reversed by any of them.

- **Confirmed, fixed:** SKILL.md routing bullet still made write authority
  "conditional on the stage gate," contradicting the relaxed model (Codex-F2 /
  Refute-F1).
- **Confirmed, fixed:** the prose claimed a post-write reread detects a lost
  concurrent edit, which it structurally cannot on a whole-body last-write-wins
  body (Codex-F1 / Refute-F2). Removed the claim; the skill now names the
  irreducible race instead. The eval case that asserted the same detection was
  corrected too (Refute-F3).
- **Confirmed, fixed:** the replan section offered a phantom "one atomic
  operation that persists retirement, contract, and replacement together,"
  which no forge provides (Refute-F5). Replaced with plain retirement-first.
- **Confirmed, corrected:** this note's own "worst case is a stale plan
  comment" rationale understated the surface (Refute-F4); see above.
- **Confirmed, fixed:** a later Codex round showed the restriction clause
  could read a generic open-PR work-unit finish line (this repo's own default)
  as routing planning writes through a PR, re-bricking the dogfood case the
  relaxation exists for. The clause now reads a declaration for what it
  actually routes: only one speaking to issue or comment writes, or to the
  planning handoff itself, restricts the surface.
- **Mooted by the collapse:** a later Codex round raised a revision-drift
  "completion gate" and a comment-collection-completeness finding, both asking
  to wire more of the machinery through the handoff. The second pass deletes
  that machinery, so these are declined per the decision above, not fixed. A
  separate doc-staleness finding on the main README skills table is handled on
  its own merits.

## Verification

Evals updated to match: the stale-contract case plans on a stock repo with no
declared stage and no lock; the concurrent whole-body-edit case proceeds without
refusing and without claiming a post-write reread detects a lost edit; the
former missing-stage error is reframed as a PR-routing restriction; the
repository-revision case records provenance and, when the base has advanced by
handoff, reports the plan grounded in the superseded revision and recommends
verify/replan without reinspecting or repairing (the redundant post-write
compensation case was removed). markdownlint, prettier, prose-tics,
skill-structure, and commit-message checks clean; eval JSON valid.

Revisit when a repo shows a real concurrent-planning collision that provenance
plus scoped-edit hygiene does not catch, which would argue for a
project-declared serialization model becoming the default rather than an opt-in
escalation.
