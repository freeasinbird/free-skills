# agent-setup evals

Eval definitions for the skill-creator loop. Only the definitions live in the
repo; run outputs, fixture projects, and grading artifacts belong in a scratch
workspace outside the repo.

## Files

- `evals.json`: four task evals for optional work-unit stages.
  1. `single-stage-init`: initializes a plain project and expects the normal
     single implementation workflow with no stage record.
  2. `planning-implementation-handoff`: initializes a project with separate
     planning and implementation stages, a durable issue-backed handoff, and
     no implied implementation authorization.
  3. `later-review-integration-adoption`: updates an existing staged project,
     preserving its unmanaged record while adding review and integration.
  4. `first-stage-adoption-update`: updates an agent-ready project that has no
     stage record, adding an owner-requested planning-only record while
     preserving unrelated guidance and the undeclared implementation default.

## Re-running

1. Create one scratch git repository per eval with a README that documents
   simple build, test, lint, and format commands. For eval 1, omit AGENTS.md.
2. For eval 2, also provide project facts sufficient for a Standard-profile
   init. No committed stage record exists before the run.
3. For eval 3, first run eval 2's setup, then introduce a small drift in one
   managed block and add unrelated unmanaged project guidance. This makes
   managed refresh and unmanaged preservation observable together.
4. For eval 4, start with an agent-ready project whose AGENTS.md has current
   managed blocks and unrelated unmanaged guidance, but no stage record.
5. Replace `<fixture-repo>` in each prompt with its per-run path. Run each task
   with and without the revised skill, grade the outputs against the listed
   expectations, and keep every generated artifact outside this repository.
