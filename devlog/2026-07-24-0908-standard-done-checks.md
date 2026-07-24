# Standard build, test, and lint done checks

The shared `done` block predates the template's use in code projects and did
not state its standard build, test, and lint expectations outside the nested
project placeholder. Freeside issue #24 surfaced the gap.

## Decision

- State once in the shared canonical body that the build succeeds, tests pass,
  and lint and formatting are clean before work is done. Keep the wording
  tool-agnostic; project commands remain in the nested
  `agents-md:project:done-checks` block.
- Preserve the nested placeholder and its TODO exactly so a managed-block sync
  can refresh the shared text without replacing project verification commands.
- Update `SKILL.md` wherever it describes the done block. Scaffolding does not
  describe the block and needs no change.
- Sync the shared sentence into free-skills' own `AGENTS.md`, which dogfoods
  the canonical template and must retain managed-block parity. Do not sync any
  other consuming repository in this work unit; those updates remain a later
  maintainer-run operation.

Revisit when a maintainer syncs the updated canonical block into consuming
repositories.
