# visual-evidence evals

Eval definitions for the skill-creator loop
(`skill-creator` plugin: run test cases with and without the skill,
grade, aggregate, review in the eval viewer). Only the definitions
live in the repo; run outputs, the fixture app, and grading artifacts
belong in a session workspace outside the repo.

## Files

- `evals.json`: three task evals exercising capture quality. Each
  prompt forbids uploading or attaching images anywhere, so runs stop
  at local files plus composed markdown and no test image is ever
  published.
  1. `spacing-fix-pair`: fix exists as an uncommitted patch; expects a
     tight-cropped before/after pair (identical width; any height delta
     explained by the padding change), both themes.
  2. `net-new-component`: add an empty-state card; expects a single
     captioned after shot and no fabricated before.
  3. `before-already-committed`: fix already committed; expects the
     before state reconstructed from git history, then a comparable
     pair.
- `trigger-evals.json`: 20 user-approved queries (10 should-trigger,
  10 should-not-trigger) for the description-optimization loop
  (skill-creator's `scripts.run_loop`). The negatives are deliberate
  near-misses: attach-an-already-taken image (gh-imgup's trigger),
  backend or perf fixes, docs changes, desktop screenshots, UI test
  authoring.

## Re-running

1. Instantiate the fixture app in a scratch workspace: a tiny static
   site in its own git repo (an HTML card list with seeded fixture
   content, light/dark via `prefers-color-scheme`, a committed CSS
   spacing bug with the fix as an uncommitted `spacing-fix.patch`;
   for eval 3, commit the fix on top). Give each run its own copy of
   the fixture and its own HTTP port so parallel runs don't collide.
2. Replace the `<fixture-repo>` and `<outputs-dir>` placeholders in
   each prompt with the per-run paths.
3. Follow the skill-creator flow: spawn with-skill and baseline runs
   in the same turn, save outputs per run under
   `iteration-N/<eval-name>/{with_skill,old_skill}/outputs/`, grade
   against the `expectations`, aggregate with
   `scripts.aggregate_benchmark`, and review in the eval viewer.

The `expectations` in `evals.json` are the graded assertions;
programmatic ones (image existence, pixel variance, width parity plus
height-delta consistency, dimension bounds, markdown label order) are
best checked by a small script, the rest by a grader agent.
