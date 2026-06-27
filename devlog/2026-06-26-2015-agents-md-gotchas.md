# Promote three session gotchas to AGENTS.md

End-of-session sweep for generalizable gotchas not already captured (the
frontmatter `>-`, fix-the-class, and self-review/fresh-context learnings were
already promoted in #22/#24/#25). Three remained, all in **non-managed**
AGENTS.md sections, so free-skills-only — no canonical dual-sync.

## Added

- **Architecture invariant #2 extended.** The platform-agnostic rule applied to
  SKILL.md prompts only; the #25 P2 showed it must also cover the agent-setup
  canonical conventions (copied downstream, run by arbitrary agents).
  **Subagents/delegation named as the canonical trap** — gate on platform
  support + state a fallback; never emit steps the running agent can't perform.
  Generalizes the one-off #25 fix into a standing rule.
- **Conventions: dogfooding sync note.** free-skills builds its own AGENTS.md
  from agent-setup, so managed blocks mirror
  `skills/agent-setup/references/canonical-sections.md`. Editing a managed
  convention means changing both places, in sync (`diff` them). Non-managed
  sections are free-skills-only. Bit me on #22/#24/#25. Review-round fix (Codex
  P2): carved out the exception — a managed block may wrap a nested
  `project:*` sub-block (`done-checks`) that is project-specific and must stay
  local, so "in sync" is not "byte-identical" for the `done` section.
- **Lint: MD038 gotcha.** Inline code spans can't carry a leading/trailing
  space; quoting a colon-then-space in backticks fails the lint — describe it
  in prose. Bit me three times in devlogs this session. (The note is worded to
  avoid reproducing the failing token.)

## Dropped

- The stacked-PR "base merged before opening → rebase onto main" half-sentence:
  it belongs in the `managed:pull-requests` block (dual-sync) and is marginal —
  skipped rather than complicate this free-skills-only change.
- `gh pr create` cross-repo `--head` and "gate commit on checks": too niche /
  already implied by Definition of done.

## Verification

Markdownlint + prettier --check clean (incl. the MD038 note itself).
