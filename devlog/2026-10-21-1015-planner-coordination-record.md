# Let the Planner Write a Project-Required Coordination Record

plan-work-unit's planning surface gains a fourth target: a coordination record
the project requires before a unit is reserved or planned, when the project's
instructions name the planner as a permitted writer. The record may sit on the
assigned issue or on a partner issue the instructions name. When the project
reserves the write to another role, the planner reports planning blocked and
names that role. Issue #338; the owner wrote the change and acceptance.

The trigger was Freeside on 2026-10-21. freeside-ai/freeside#2115 was under a
`Plan` fiat while #2111 held an active claim, and the pair had no recorded
assessment. Freeside serializes contract units by a pairwise assessment kept
in both issues' Dependencies fields. The skill's surface stopped at the
contract, one plan comment, and invalidation edits, so the planner read the
missing record as a blocker and posted a block comment. Nothing else in the
workflow would then write the record.

- **Keep the surface fixed before inspection.** This revises
  `2026-08-18-1430-planning-gate-error.md`, where the surface was "fixed by
  the skill, not discovered by inspection." It is still fixed before
  inspection: whether the record is in the surface comes from project
  instructions alone, and inspection only finds which partner issue it lands
  on. So the precondition check keeps its fail-fast shape. A declared stage
  that excludes a record the project requires is still an error, not a
  blocked outcome. That error fires even on runs with no unassessed partner,
  so a project that names the planner as a writer must list the record in
  its planning stage's allowed mutations.
- **Block only on a record needed before planning.** A record the project
  requires only before reservation, and reserves to another role, is a start
  blocker recorded in the contract and plan, like any ordering blocker.
- **Touch only the record on a partner issue.** Rejected: refusing to write
  when only a whole-body edit is available. GitHub issue bodies offer nothing
  else, so that would disable the change on the forge that prompted it.
- **Require both conditions.** The project must require the record and name
  the planner as its writer. The skill supplies no rule of its own about who
  may assess; Freeside's rule is freeside-ai/freeside#2119.
- **Rejected: keep the partner-issue write out of bounds and fail closed.**
  The Freeside case showed that failing closed leaves no step that ever
  writes the record, so the unit stays blocked on bookkeeping its own rules
  let the planner do.
- **Rejected: let the planner write any record it judges useful.** That would
  make the surface depend on what inspection finds, which breaks the
  fail-fast precondition check the 2026-08-18 note set up.

Revisit when a project needs the planner to write a coordination record of
another shape than a pairwise assessment.
