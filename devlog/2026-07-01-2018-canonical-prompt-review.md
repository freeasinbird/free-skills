# Prompt-crafter review of the canonical sections

Applied the prompt-crafter skill's review workflow to
`skills/agent-setup/references/canonical-sections.md` (own taxonomy
pass, mechanical battery, fresh-context adversarial critique with the
decided/deferred list fenced off). Findings filtered on merits; three
judgment calls surfaced to the user, all approved as recommended.

## Decisions

- **Settings and forge claims gated as a class**: repo settings and
  GitHub behavior were asserted as unconditional fact for arbitrary
  downstream repos (merge-commit message, squash-off, auto-delete,
  stacked-PR auto-retarget, PR-template path). Now "intended setup"
  with a stated manual fallback. Companion: the repo-settings audit in
  SKILL.md now checks/aligns `merge_commit_title`/`merge_commit_message`
  (the one claimed setting it never audited).
- **Contradiction fixes**: Branches' lifecycle sentence no longer reads
  as an imperative to merge (it cited-fired against the finish line's
  human-merges rule); Screenshots' deadline moved from "before merging"
  (never arrives on the agent's watch) to handoff; "Opening the PR is
  the finish line" became "An open PR, not a merged one, is".
- **Structure**: the diminishing-returns rule moved from the tail of
  fix-the-class into its natural pair, now one "Converge deliberately,
  and don't under-converge" bullet. The decided validator-enumeration
  sentence stayed put.
- **Coverage**: one commit-time secrets bullet added to Commits (the
  only gap surviving the tool-neutral / 1-2 lines / genuine-gate bar).
- Smaller accepted findings: `main` defined once as the default branch;
  review-watch trigger keyed to a recorded/observed reviewer instead of
  "active"; Reviewing-a-PR got a no-tooling fallback (read the diff);
  trust-boundary risk class got a recognizing instance; "keep the
  current style" dropped (empty referent in a fresh repo); fold-fix
  pointer in Stacked PRs fixed (wrong direction, unnamed rule).

## Rejected by verification / decision (don't re-raise)

- "`## To promote` write path undefined": the scaffolded devlog README
  defines the exact heading; entry mechanics live there by the
  one-home decision.
- "done's 'actively used' contradicts the open-PR endpoint": the
  sentence already self-clarifies with "running and exercised"; a
  rewording doesn't earn its tokens.

## Verification

- Passed: `./scripts/check-managed-sync.sh`,
  `npx markdownlint-cli2 '**/*.md'`, `npx prettier --check '**/*.md'`
  after every commit; em-dash grep 0 on the payload; jq syntax of the
  new settings-check snippet exercised.
- Checked: full pointer-payoff sweep and a read-as-the-agent pass of
  the final payload.
