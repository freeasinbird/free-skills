# Worktree-per-work-unit convention

The user asked where "develop in a git worktree" should live so both
Claude and Codex sessions follow it: global system prompts, project
AGENTS.md via agent-setup, or a harness mechanism. Motivation scoped in
session: parallel agent sessions on one repo must not collide with each
other or with the user's own checkout; scope is all projects. The
practice was already dogfooded here (2026-07-01-2351 worked "in a
dedicated worktree so the main checkout stays free for other work", and
this session did the same) but written down nowhere.

## Decisions

- **Home: the canonical `branches` managed section**, mirrored into this
  repo's AGENTS.md block per the two-place rule. Why: it is the one
  layer both agents read (Codex reads AGENTS.md natively; Claude Code
  reads it through the scaffolded CLAUDE.md pointer), and agent-setup's
  update mode propagates it to every downstream project, matching the
  all-projects scope. Worktree creation is per-work-unit workflow, the
  `branches` section's subject. Unlike the prose-tics check (ruled
  project-specific in 2026-07-02-2151 because agent-setup ships markdown
  only and cannot deliver scripts), this is pure instruction text, so
  the canonical section fits.
- **Instruction-only, capability-gated; no hooks or settings
  automation.** Surveyed mechanisms: Claude Code has a per-invocation
  worktree flag, worktree tools, and subagent worktree isolation, but no
  "always start in a worktree" default; hooks could warn at session
  start but only for Claude; Codex has no worktree mechanism at all. A
  hard gate therefore cannot be expressed platform-agnostically
  (invariant 2), and a blocking hook would also fight legitimate
  single-session work in the primary checkout. The convention follows
  the fresh-context-review gating template: "Where your platform and
  session support X / Where they don't, fall back to Y", with the
  fallback being a branch in the primary checkout.
- **Rejected: global-prompt-only.** The user's global Claude config
  reaches only Claude sessions and only their machine; it can't cover
  Codex or collaborators. A short global line remains a useful
  belt-and-braces layer for projects that haven't run agent-setup; left
  to the user, outside this repo.
- **Rejected: a standalone skill.** This is a standing convention, not
  an invocable procedure; the skill surface adds discovery cost without
  adding capability.

## Deferred

- **Warn-only session-start hook** (detect work starting in the primary
  checkout) as an escalation if the instruction proves leaky in
  practice. Claude-only, per-user; needs evidence of leakage first.
- Re-deferred from earlier queues, out of scope here: the skill-creator
  upstream bug report (needs-human, 2026-07-01-2212) and the
  net-new-component eval assertions (same entry).

## Verification

- Managed-sync, markdownlint, prettier, and prose-tics checks run over
  the repo; results recorded in the PR.
