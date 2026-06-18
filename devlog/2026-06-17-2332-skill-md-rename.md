# Rename prompt.md to SKILL.md

## What landed

- Renamed skill entry points from `prompt.md` to `SKILL.md` in both
  `agent-setup` and `license-philosopher`.
- Updated AGENTS.md and README.md to reflect the new convention.

## Decisions

- **SKILL.md is the cross-platform standard.** Both Claude Code and
  Codex discover skills by this filename. The repo was using `prompt.md`
  incorrectly — fixed to match the actual platform convention.
- **Historical devlog references left as-is.** The earlier devlog entry
  mentioning `prompt.md` is accurate for when it was written; no rewrite.

## Deferred

- Nothing.
