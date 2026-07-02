# Commit map by subject, not SHA

Third of the leverage-ordered follow-ups from the frozen
`2026-07-02-0003-await-review-cost-signals.md` retrospective (#1). A canonical
pull-requests convention tweak, so it lands in the canonical source and this
repo's synced managed block together.

## Fixed

- **What** bullet: the commit-map guidance now says to reference each commit
  **by subject, not SHA**. Folding a review fix into its commit (the Commits
  "Fold review fixes" rule) rewrites every downstream SHA, so a SHA-keyed map
  forces a full body rewrite each review round; subjects don't go stale.
- **Keep the body current** bullet: mirrored ("by subject as above") and made
  the contrast explicit so the two bullets don't read as contradictory: the
  standing body uses subjects, while the inline per-finding reply keeps its
  fixing SHA because that reply is written once, post-fold, so it doesn't
  churn.
- Both PR-body scaffolds agents actually fill in (the `.github` PR template and
  agent-setup's `scaffolding.md`): the same subject-not-SHA rule, so following
  the template can't reproduce a SHA-keyed map. Codex flagged this on PR 48
  (the convention text alone didn't reach the scaffolds); folded into the
  content commit.

## Decisions

- Scoped to the two body-related bullets plus the scaffolds that operationalize
  them; deliberately left the "Responding to automated review" bullet's
  `Fixed in <sha>` reply unchanged (that SHA is the located per-finding record
  and is churn-free by write-once timing).
- Edited canonical `references/canonical-sections.md` and the `pull-requests`
  managed block in AGENTS.md identically; `check-managed-sync.sh` green.

## Deferred queue drain

Drains #1 from the frozen `2026-07-02-0003` retrospective queue. Still open
there: class-sweep auto-trigger (#5, next PR this session). Close-out script
(#2) deferred by user decision; the two non-actionable notes remain
observation-only.

## Verification

- Passed: `./scripts/check-managed-sync.sh` (all six blocks ok).
- Passed: `npx markdownlint-cli2` and `npx prettier --check` on all four files.
- Checked: the two convention hunks byte-identical across canonical and the
  managed block; the two scaffold hunks byte-identical across the PR template
  and `scaffolding.md`; no em dashes in added prose.
