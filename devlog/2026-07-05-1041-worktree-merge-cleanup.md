# Make the merge-cleanup recipe worktree-aware

The worktree-per-work-unit convention (#56, commit 28056d1) added
dedicated-worktree guidance to the `branches` block, but the "if the user
asks you to merge" cleanup recipe in the `pull-requests` canonical block, and
the parallel steps in the self-merge skill, still assumed a single checkout.
From a linked worktree that recipe breaks: `git checkout main` refuses with
"already used by worktree", and `git branch -d` refuses while the branch is
still checked out in a worktree (both verified in the merge-cleanup skill's
own review rounds). So the two conventions the same repo now ships contradict
each other on the merge path.

## Discovery

Surfaced downstream: freeasinbird.com ran `/agent-setup` (update mode) to
resync its managed blocks to canonical, which pulled in the new worktree
guidance; its Codex reviewer then flagged the merge recipe on
`AGENTS.md` as incompatible with that guidance (PR
freeasinbird/freeasinbird.com#26, P2). Declined there as verbatim
canonical text, tracked to here. Distinct from #57 (screenshot deadline).

## Fixed

- `canonical-sections.md` pull-requests merge recipe: keep the single-checkout
  `git checkout main && git pull --ff-only` as the default, add the worktree
  case (resync `main` in the primary checkout, `git worktree remove <path>`
  the feature worktree before deleting its branch). Cross-references Branches.
- `AGENTS.md` pull-requests block: identical edit, so `check-managed-sync`
  stays byte-clean (verified `ok` on all six blocks).
- `self-merge` SKILL.md steps 2-3: same worktree caveat on Resync and Clean up.

## Decisions

- Kept the fix self-contained in each recipe rather than pointing callers at
  the merge-cleanup skill: the canonical text seeds downstream projects that
  may not have that skill, and self-merge should stand alone. The merge-cleanup
  skill already handles the worktree layout (and remote-scoped prune /
  ignored-file safety); those richer refinements stay out of scope here.
- Dogfooded the worktree convention: this work unit ran in
  `.claude/worktrees/worktree-merge-cleanup`, the workflow the fix documents.

## Verification

- Passed: `npx prettier --check`, `npx markdownlint-cli2`,
  `./scripts/check-prose-tics.sh`, `./scripts/check-managed-sync.sh`.

## To promote

- None; this closes the branches-vs-merge-recipe gap that #56 opened.
