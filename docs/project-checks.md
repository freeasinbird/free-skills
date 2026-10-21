# Project Checks

These details apply only to free-skills. Read the section named by AGENTS.md
at the step where it applies.

## Readability

```sh
./scripts/check-readability.sh [file ...]
```

The report prints one row per Markdown file. It includes word count, median
and maximum sentence length, sentences over 40 words, and maximum paragraph
length.

All lengths use whitespace-separated word counts. The report exits 0 after
any successful run and doesn't enforce readability thresholds.

Gate prose changed since a branch or commit's merge base with:

```sh
./scripts/check-readability.sh --gate --base origin/main [file ...]
```

Touched sentences may have at most 40 words, and touched paragraphs may have
at most 120. Put `<!-- readability: allow -->` on its own line to start an
exempt region. End it with `<!-- readability: end -->`, or let it continue to
the end of the file. For an untracked file, run `git add -N <path>` before a
local gate check. Gate mode prints per-file word deltas without enforcing
them. It exits 1 for length violations and 2 for usage or environment errors.

## CI

Pull requests run two workflows. `.github/workflows/commit-messages.yml`
publishes the `check` context for the exact feature-branch commit range against
the commit-message rules below. `.github/workflows/markdown.yml`
publishes `markdown-checks` for Markdown lint and formatting, the touched-prose
gate, prose-tic, list-capitalization, skill-structure, managed-sync, and
review-convergence layer checks, plus one context for every script test matrix.
Its `markdown-required` context passes only when `markdown-checks` and every
matrix context pass.

Branch protection on `main` requires `check` and `markdown-required`, both
from GitHub Actions, and requires branches to be up to date before merging.
Adding a script test matrix therefore needs no protection change. Keep the
fan-in job's `if: always()`: a skipped required check counts as passing.

## Commit Messages

Pull-request CI runs
`bash scripts/check-commit-messages.sh <base-ref> <head-ref>`. Locally, run
`bash scripts/check-commit-messages.sh origin/main HEAD`.

The script resolves the merge base and checks every non-merge commit in
`merge-base..head`. It exempts merge commits and mainline commits from a
base-freshness merge. One run reports every offending commit and rule.

Every checked commit must satisfy all of these mechanical rules:

- **Require a subject and body.** Line 2 must be blank. At least one non-blank
  body line must follow.
- **Constrain the subject.** Use at most 72 characters, no ending period, and
  no lowercase ASCII letter at the start. Acronym-, identifier-, and
  digit-led subjects are valid.
- **Forbid Conventional Commit prefixes, regardless of case.** The forbidden
  types are:

  - `build`, `chore`, `ci`, `docs`, `feat`, and `fix`.
  - `perf`, `refactor`, `revert`, `style`, and `test`.

  Scoped and breaking forms, such as `feat(api):` and `refactor!:`, are also
  forbidden.

- **Forbid temporary markers, regardless of case.** This covers `fixup!` and
  `squash!` prefixes and standalone `WIP` markers.
- **Forbid review-cleanup prefixes, regardless of case.** The forbidden
  prefixes are:

  - `Address review`, `Address PR review`, and `Address pull request review`.
  - `Apply review feedback`, with optional `PR` or `pull request` before
    `review`.
  - `PR feedback` and `Pull request feedback`.

  Fold that work into its owning commit instead.

- **Limit body lines to 72 characters.** A line without whitespace is exempt,
  so an unbreakable URL, object ID, or ref can remain intact.

## Conditional Tests

Run each suite when its stated trigger applies.

- Watcher validation matrix green when await-pr-review's `watch-review.sh`
  changed (`./scripts/test-watch-review.sh`)
- Review-routing matrix green when await-pr-review's routing text or fixtures
  changed (`./scripts/test-await-pr-review-routing.sh`)
- Prose-tics matrix green when the prose-tic check changed
  (`./scripts/test-check-prose-tics.sh`)
- List-capitalization matrix green when the check changed
  (`./scripts/test-check-list-capitalization.sh`)
- Readability matrix green when `check-readability.sh` changed
  (`./scripts/test-check-readability.sh`)
- Commit-message validation matrix green when the commit-message check changed
  (`./scripts/test-check-commit-messages.sh`)
- Skill-structure matrix green when the structure check changed
  (`./scripts/test-check-skill-structure.sh`)
- Prompt-verification matrix green when the documented snippets or their
  regression script changed (`./scripts/test-prompt-verification.sh`)
- Capture validation matrix green when visual-evidence's `capture.mjs`
  changed (`./scripts/test-capture.sh`)
- Landing engine matrix green when land-approved-prs' `land.sh` changed
  (`./scripts/test-land.sh`)
- Readiness-list matrix green when land-approved-prs' `list-ready.sh`
  changed (`./scripts/test-list-ready.sh`)
- Landed-since matrix green when land-approved-prs' `landed-since.sh`
  changed (`./scripts/test-landed-since.sh`)
- Reconciliation validation matrix green when merge-cleanup's
  `reconciliation-ledger.sh` changed
  (`./scripts/test-merge-cleanup-reconciliation.sh`)
- Inventory validation matrix green when merge-cleanup's
  `worktree-inventory.sh` changed
  (`./scripts/test-merge-cleanup-inventory.sh`)
- Sweep validation matrix green when merge-cleanup's `worktree-sweep.sh`
  changed (`./scripts/test-merge-cleanup-sweep.sh`)
- Landing validation matrix green when merge-cleanup's
  `base-landing-plan.sh` changed
  (`./scripts/test-merge-cleanup-landing.sh`)
- Orchestration validation matrix green when merge-cleanup's
  `merge-cleanup.sh` changed (`./scripts/test-merge-cleanup.sh`)
- Refresh validation matrix green when merge-cleanup's
  `tracker-refresh.sh` changed (`./scripts/test-merge-cleanup-refresh.sh`)
