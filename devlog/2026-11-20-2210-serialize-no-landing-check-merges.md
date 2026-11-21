# Serialize No-Landing-Check Merges in the Managed Workflow

Issue #321. PR #320 dropped agent-setup's width-one fallback
(`devlog/2026-10-18-2050-drop-width-one-fallback.md`) and replaced it with a
merge-only rule: run merges one at a time until a landing check exists, while
development and PR starts stay parallel. That rule lived only in agent-setup's
setup references, so downstream agents never read it. Meanwhile, PR #366
(`devlog/2026-11-05-0933-handoff-no-base-chase.md`) split landing-check
behavior across the managed `pull-requests` block and `docs/agent-workflow.md`
§handing-off step 3. Neither those lines nor §merge-and-resync step 1
serialized merges when a project has no landing check.

## Decisions

- **Chose the managed `pull-requests` block and `docs/agent-workflow.md` over
  a per-project coordination record.** Every project without a landing check
  faces the same merge race: two landers can each pass a manual base-moved
  recheck against the same tip and merge an untested combination. Putting the
  rule in the managed workflow puts it where downstream authors and landers
  read it, without turning a missing check into a coordination model or
  reintroducing a coordination record for the landing baseline. Manual
  serialization is a best-effort guardrail that narrows the race until a real
  landing check exists; without a shared lock or up-to-date rule, independent
  sessions cannot observe each other's merges.
- **Placed the rule in both `§handing-off` step 3 and `§merge-and-resync`
  step 1, failing safe when the check is unconfirmed.** Handoff sets the
  contract for authors preparing a PR under the no-landing-check case, while
  merge-and-resync governs direct merges. Because forge merge state (such as
  GitHub's `mergeStateStatus`) does not distinguish strict mode from an
  unprotected base, §merge-and-resync step 1 fetches the base branch and
  checks tip containment whenever a landing check is not confirmed.
- **Kept the rule platform-agnostic.** The serialization rule and behind-tip
  check apply to any forge, sitting beside the existing GitHub `gh pr view`
  example rather than assuming a GitHub-specific setting or tool.
- **Pointed `coordination-discovery.md` §shapes at the managed rule.** Setup
  no longer states merge serialization on its own; it refers to the managed
  `pull-requests` rule and workflow steps so both layers stay aligned.

## Rejected Options

- **Restore a width-one coordination record for missing landing checks.**
  Throttles all development and PR starts to guard a race that happens only at
  merge, reversing the owner decision recorded in
  `devlog/2026-10-18-2050-drop-width-one-fallback.md`.
- **Keep merge serialization only in `§handing-off` step 3.** Leaves a direct
  lander following `§merge-and-resync` step 1 relying on forge merge state
  that passes a behind-tip branch when no landing check exists.
- **Keep merge serialization only in agent-setup's setup report.** Downstream
  agents running later work units never read the initial setup report.

## Revisit When

Revisit when agent-setup changes its landing-check taxonomy in
`skills/agent-setup/references/coordination-discovery.md` §shapes, or when
downstream workflow sections move out of the managed `pull-requests` block
(tracked in #328).
