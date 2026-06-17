# AI contribution guidance

## What landed

- Added AI-assisted contribution accountability language to
  `CONTRIBUTING.md`.
- Updated the README contributing note to point only to `CONTRIBUTING.md`.
- Updated the agent-setup skill's CONTRIBUTING scaffold to include the
  same AI-assisted contribution section.

## Decisions

- **Keep AGENTS as the workflow source, but not the whole contribution
  doc.** `CONTRIBUTING.md` remains the human entry point and still links
  to AGENTS for mechanics; AI-accountability policy belongs directly in
  the contributor-facing file.
- **Mirror the policy in the skill scaffold.** New projects initialized
  by `agent-setup` should get the same expectation that human
  contributors understand, review, and maintain AI-assisted work.

## Deferred

- No CODE_OF_CONDUCT or issue-template policy changes.
