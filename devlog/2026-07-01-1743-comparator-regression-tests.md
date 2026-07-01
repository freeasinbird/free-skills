# Regression tests for the managed-block comparator

Drains the first `## To promote` item from the frozen 2026-07-01-1727
entry (user approved doing both queued PRs).

## Decisions

- `scripts/test-compare-managed-blocks.sh`: 28 cases covering every
  failure mode the PR #36/#37 review cycle verified (lookalike variants,
  embedded fragments, marker order, nested structure including the moved
  pair and cross-block planting, the SIGPIPE large-block regression, the
  innocent-comment false positive, opt-out tolerant/strict splits).
  Fixtures are synthesized from canonical-sections.md so canonical text
  changes don't break the suite.
- Repo-local `scripts/`, not the skill directory: consumers installing
  the skill don't need its tests, and edits happen here.
- Mutation-tested the suite itself: seeding two comparator regressions
  (sentinel removal, scan anchor re-widened) each fails exactly one
  case. The second seeding initially passed, exposing that the
  embedded-fragment invariant shadows the scan for exact-case indented
  lookalikes; an indented+uppercase case now discriminates the scan.
- Wired into the done-checks block, scoped to comparator/sync-check
  changes.

## Verification

- Passed: `./scripts/test-compare-managed-blocks.sh` (28/28) on the
  intact comparator; each seeded regression fails its case; suite green
  again after restore.
- Passed: `npx markdownlint-cli2 '**/*.md'`,
  `npx prettier --check '**/*.md'`, `./scripts/check-managed-sync.sh`.
