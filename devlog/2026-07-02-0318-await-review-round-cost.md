# Refine await-pr-review round-cost guidance (persistent fixer + cadence)

Two of the leverage-ordered follow-ups deferred in the frozen
`2026-07-02-0003-await-review-cost-signals.md` entry, both pure `SKILL.md`
prose refinements to the fix-round cost model.

## Fixed

- **Persistent fixer across rounds (#3), step 4.** The delegated-fixer
  break-even was stated per round, so short rounds always looked like they
  never justify delegation. Added the multi-round distinction: a fresh fixer
  re-pays context rebuild every round (`N × R_rebuild`), a fixer kept alive
  across the loop pays it once (`1 × R_rebuild`) and keeps per-round debris
  out of the main context. Consequence: a persistent fixer likely wins on
  ~4+ round exchanges even when each round is individually below the
  per-round break-even; the per-round rule still governs one-shot rounds.
  Cross-referenced from step 5's convergence loop.
- **Cadence vs cache TTL (#4), step 3.** Added the empirical justification
  for the tight no-model cadence: observed Codex latency (2m54s–4m46s, near a
  5-min cache TTL) means a ~75s poll tends to fire its single wake while the
  main context is still cache-warm, where a coarse ~270s grid wakes it cold, a
  ~12x swing on that one read. Also softened the "usually cache-cold" wake line
  so
  it no longer contradicts this.

## Decisions

- Kept #3 gated exactly like the existing delegated-fixer path (subagent
  resumable across the main agent's turns; fall back to in-main rounds),
  honoring invariant 2 (platform-agnostic, no unconditional Claude-only step).
- #4 framed as observed-not-guaranteed justification, not a new rule; the
  60–90s / 270s cadence numbers were already in the skill.
- Numbers stated explicitly (`N × R_rebuild` vs `1 × R_rebuild`, ~12x wake
  swing) per the standing "quantify token-cost claims" discipline.

## Deferred queue drain

Drains #3 and #4 from the frozen `2026-07-02-0003` retrospective queue. Still
open there and out of scope here (own PRs, user-selected): commit-map-by-subject
(#1), class-sweep auto-trigger (#5). Deferred by user decision: the round
close-out script (#2). The two non-actionable notes (keepalive re-derivation on
pricing shift; Codex 👍 `createdAt` refresh) remain observation-only.

## Verification

- Passed: `npx markdownlint-cli2 'skills/await-pr-review/SKILL.md'` (0 errors).
- Passed: `npx prettier --check 'skills/await-pr-review/SKILL.md'`.
- Checked: no em dashes in added prose; frontmatter untouched.
