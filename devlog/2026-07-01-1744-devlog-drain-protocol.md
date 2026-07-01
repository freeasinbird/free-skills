# Document how frozen To promote entries drain

Drains the second `## To promote` item from the frozen 2026-07-01-1727
entry (user approved doing both queued PRs). The gap was exercised
before it was written down: that entry itself drained the audit entry's
queue by reference, with no protocol backing the move.

## Decisions

- New protocol bullet in scaffolding.md §devlog-readme (and the repo's
  scaffolded devlog/README.md, resynced from the template): a queue item
  in a merged entry drains by reference, the promoting entry records the
  drain and names the source; the queue grep checks later entries for a
  drain record before re-raising.
- Kept it in the README template only: the canonical devlog section
  points there for protocol per the audit's one-home decision.

## Verification

- Passed: `npx markdownlint-cli2 '**/*.md'`,
  `npx prettier --check '**/*.md'`, `./scripts/check-managed-sync.sh`.
- Checked: devlog/README.md is byte-identical to the updated template
  (resynced by the same extraction the skill's update mode describes).
