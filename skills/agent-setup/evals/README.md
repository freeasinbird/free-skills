# agent-setup evals

Eval definitions for the skill-creator loop. Only the definitions live in the
repo; run outputs, fixture projects, and grading artifacts belong in a scratch
workspace outside the repo.

## Files

- `evals.json`: nine task evals for optional work-unit stages and progressive
  coordination discovery.
  1. `single-stage-init`: initializes a plain project and expects the normal
     single implementation workflow with no stage record.
  2. `planning-implementation-handoff`: initializes a project with separate
     planning and implementation stages, a durable issue-backed handoff, and
     no implied implementation authorization.
  3. `later-review-integration-adoption`: updates an existing staged project,
     preserving its stage and coordination records while adding review and
     integration.
  4. `first-stage-adoption-update`: updates an agent-ready project that has no
     stage record, adding an owner-requested planning-only record while
     preserving unrelated guidance and the undeclared implementation default.
  5. `empty-repository-serial-baseline`: initializes an empty project with the
     safe serial default and no invented coordination structure.
  6. `speculative-plan-is-evidence`: keeps an uncorroborated draft plan from
     becoming lanes, a graph, or unsupported parallel width.
  7. `mature-simple-adoption`: adopts management while preserving demonstrated
     serial behavior in a mature project that needs no richer coordination.
  8. `recurring-independent-streams`: derives stable named streams from
     recurring history and caps width at proven integration capacity.
  9. `shared-contract-integration-spine`: separates serialized shared-contract
     work from component ownership and keeps typed relations distinct.

## Re-running

1. Create one scratch git repository per eval with a README that documents
   simple build, test, lint, and format commands. For eval 1, omit AGENTS.md.
2. For eval 2, also provide project facts sufficient for a Standard-profile
   init. No committed stage record exists before the run.
3. For eval 3, first run eval 2's setup, then introduce a small drift in one
   managed block, add a complete four-field coordination model record, and add
   unrelated unmanaged project guidance. This makes managed refresh and both
   record-preservation paths observable together.
4. For eval 4, start with an agent-ready project whose AGENTS.md has current
   managed blocks and unrelated unmanaged guidance, but no stage record.
5. For eval 5, provide only the basic README. Do not add a plan, code,
   architecture document, work-unit history, or AGENTS.md.
6. For eval 6, add only the speculative PLAN.md described by the prompt. Its
   proposed lanes and graph must have no corroborating code or history.
7. For eval 7, provide a mature code tree, architecture notes, serial work-unit
   history with no recurring independent boundaries or bottleneck, and an
   unmarked AGENTS.md containing project guidance that adoption must preserve.
8. For eval 8, provide architecture notes and six completed work-unit records
   that demonstrate the same two independent boundaries. Directory names must
   not be the only evidence.
9. For eval 9, provide code, architecture notes, and work-unit history showing
   independent components, a serialized shared schema, one integration role,
   and examples of all four typed relations.
10. Replace `<fixture-repo>` in each prompt with its per-run path. Run each task
    with and without the revised skill, grade the outputs against the listed
    expectations, and keep every generated artifact outside this repository.
