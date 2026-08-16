# Separate Issue Planning from Implementation

Issue #125 establishes `plan-work-unit` as a reusable planning-only workflow
boundary for projects that hand an authoritative work contract and issue plan
to a fresh implementation task.

## Decision

Chose an explicitly triggered planning skill over interpreting any mention of
an implementation plan as a planning request. "Plan #N" selects the planning
operation and expresses user intent, subject to the project's declared allowed
mutations and planning-only finish line. "Handle #N, implementation plan in
comments" instead treats that comment as implementation input and does not
invoke the planning skill. Assessment, overlap, review, and in-chat proposal
requests remain non-mutating unless they explicitly authorize planning
mutations.

Chose the project-selected work-contract record as authority over the plan
because dependencies, scope, affected contracts, and coordination constraints
need one durable source of truth. A project designation wins; otherwise the
issue body is the selected record. The issue plan is a code-grounded execution
aid. It can reveal that the contract is stale, but must update the selected
record rather than silently override it.

Chose one current implementation-plan comment over an accumulating plan
history. Replanning edits the current comment when possible. A forge without
comment editing may receive one linked superseding comment that explicitly
deprecates the old plan, preserving one unambiguous current plan without
assuming a platform-specific API.

Chose an explicit conflict guard plus pre-write refresh at the forge boundary
because issue and comment updates may replace whole resources after a long
investigation. A fresh read alone leaves a read/write race. The planner needs
exclusive mutation ownership or a conditional operation that rejects a changed
resource or current-plan set, then independently rereads the persisted state.
Without a guard covering every affected invariant, planning blocks instead of
risking lost owner text or competing plans.

Chose explicit invalidation for a blocked replan. When missing information or
an owner decision prevents a replacement plan, the prior plan is marked blocked
or receives a linked invalidation comment so it cannot remain actionable by
accident.

Chose retirement before contract publication for a replan that cannot persist
all resources atomically. The planner first makes the exact old plan visibly
non-current under the full planning-surface guard, then publishes the changed
contract and replacement. A failure in either later write therefore leaves an
incomplete handoff, but never stale instructions that still appear current
against the new contract.

Rejected folding planning into agent-setup's canonical conventions. Project
setup defines workflow capabilities, while issue planning is an explicitly
assigned operation over one work unit. Coupling them would make setup larger
and could imply that every implementation requires a separate planning stage.

Rejected a paired `implement-work-unit` skill in this work unit. The observed
failure is the planning and implementation routing boundary, and the repository
already defines implementation workflow and PR finish lines. A second skill
would add an unproven abstraction and broaden issue #125.

## Refute-First Verification

- **Confirmed:** an independent lens found that pre-write refresh alone still
  permits a concurrent owner edit between the read and whole-object write. The
  rule now requires exclusive ownership or an atomic version guard and blocks
  mutation when neither is available.
- **Confirmed:** a successful invalidation response does not prove the prior
  plan stopped appearing current. The rule now distrusts returned objects and
  requires an authoritative post-write reread of the exact target and complete
  current-plan set.
- **Rejected by verification:** post-write reconciliation alone is not an
  adequate primary guard because it discovers lost text only after data loss.
- **Accepted by decision:** plan creation uses the same guard as replacement
  writes because the one-current-plan rule is a cross-resource invariant.
- **Recurrence root cause:** the first trust-boundary sweep updated the skill
  and its two new edge cases but treated the older successful-write fixtures as
  inert examples. They are consumers of the same guard contract. The wider
  sweep now gives every mutation case an explicit full-surface guard and
  persisted-state reread.
- **Second recurrence root cause:** the guard-only sweep still treated each
  fixture's repository prose as sufficient without mapping every required
  path, interface, verification command, and integration surface back to a
  named artifact. The wider consumer audit now makes every code-grounded case
  self-contained. A structural validator needs a deliberately designed fixture
  schema rather than a brittle prose grep.
- **Third recurrence root cause:** the operational-input audit covered how and
  where to implement but not what behavior and testable outcome the unit should
  produce. The complete matrix now supplies objective behavior, acceptance
  outcomes, non-goals, contracts, paths and interfaces, verification commands,
  mutation guards, and the implementation finish line for every case that must
  produce plan text. Repeated semantic omissions reinforce the need for
  follow-up #132.
- **Fourth recurrence root cause:** the cross-resource guard modeled issue-body
  and plan-comment mutations but omitted non-plan comments and other mutable
  contract-bearing records that informed the prepared contract. The guard and
  every successful mutation fixture now cover the full planning-input surface,
  including collection membership, across the complete write sequence.
- **Confirmed:** a contract-first replan could persist a changed contract and
  then fail before retiring the old current plan. Replans now either persist
  retirement, contract, and replacement atomically or verify the old plan as
  non-current before publishing the changed contract.
- **Confirmed by the recurrence refute pass:** the widened guard's lead-in
  still named only issue-body and plan-comment writes, omitting a designated
  contract record or invalidation comment. The trigger now covers every
  planning write and names all four target classes.
- **Confirmed by the recurrence refute pass:** fixtures asserted a
  full-surface lock without exercising either changed non-plan comment
  membership or a replacement-plan failure after contract publication. Two
  adversarial cases now require reconciliation of the former and a blocked,
  non-actionable partial state for the latter.
- **Fifth recurrence root cause:** retirement-first was scoped to changed
  contracts even though the safety condition is a plan already known invalid.
  The rule now retires every invalid plan before replacement, whether or not
  its authoritative contract changes, and an unchanged-contract failure case
  holds that boundary.
- **Sixth recurrence root cause:** the workflow supported a project-designated
  contract record during writes but hard-coded the issue body at handoff. The
  selected authority now flows through final verification, while the issue
  independently retains the single current implementation plan. A dedicated
  case prevents contract duplication into the issue from masquerading as a
  fix.
- **Seventh recurrence root cause:** the skill treated a planning request as
  sufficient authority for a no-PR finish line even where project defaults
  route every state change through a pull request. Planning-only mutation now
  requires a declared non-implementation stage or explicit project workflow
  override whose recorded scope covers every target and the exact no-PR
  handoff. Missing or partial authority reports the policy conflict without any
  partial mutation or a different branch-and-PR operation. The request selects
  the operation; it does not supply that project authority.
- **Convergence checkpoint, go:** the late findings remain distinct policy
  boundaries with shrinking local patches, the full fixture matrix gains one
  adversarial case per boundary, and follow-up #132 already owns migration from
  prose-only semantic coverage to a designed validator. Continue review while
  blockers still produce net, testable progress; revisit the go decision if a
  fixed class recurs or another round only moves the contradiction.
- **Eighth recurrence root cause:** forge freshness covered the contract and
  plan records but not the repository revision that supplied their code facts.
  Planning now pins an immutable inspected revision from the authoritative
  project reference and requires one publication guard to cover that reference
  and every planning record. It re-inspects and reprepares when the reference
  advances, and verifies the revision again after writes before reporting
  completion. A failed guard makes both the published contract content and plan
  non-current, or reports each still-actionable artifact as unsafe.
- **Ninth recurrence and renewed convergence checkpoint, go:** the first
  repository-drift fix left an unsafe restoration branch for contract content
  that could already have been stale before the inspected revision moved. The
  compensation path now always preserves freshly reread owner text while
  marking code-grounded contract content blocked, and the guard-failure fixture
  forbids restoration. This is a narrow removal of an unsafe alternative with
  direct regression coverage; another recurrence in repository-drift
  compensation would show that this class has not converged and should pause
  for owner review.

Follow-up: #132

Revisit when free-prompts changes the operation-versus-input boundary,
agent-setup changes how projects declare coordination, or an independently
justified implementation skill redraws the handoff.
