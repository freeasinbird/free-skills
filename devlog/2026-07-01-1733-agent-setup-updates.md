# Apply the gh-imgup session's agent-setup proposals

Input: `~/proj/freeasinbird/agent-setup-updates.md` (written by the
gh-imgup 2026-07-01 session; can be deleted once this merges).

## Decisions

- Required-checks/CI-matrix audit added to SKILL.md's Repo settings
  section: context-name matching plus skipped-check-passes semantics,
  the two matrix failure modes (rename blocks merging, bare fan-in
  fails open), the `if: always()` fan-in fix, and a gated `gh api`
  audit command. Stays within the 2026-06-20 branch-protection
  deferral: audits and warns, creates nothing.
- Equivalence-harness lens added to the canonical refute-first
  paragraph (finish-line), gated on the platform executing code per
  invariant 2. Adjusted the paragraph's closing scope from "pure
  refactor" to "a refactor off these paths"; the old wording would
  have contradicted the new on-path refactor guidance.
- The source doc's own non-proposals honored: no dependabot opinion,
  no review-watch changes.

## Verification

- Passed: `./scripts/check-managed-sync.sh` after the managed-block
  edit; `npx markdownlint-cli2 '**/*.md'`;
  `npx prettier --check '**/*.md'`; em-dash grep 0 on touched files.
