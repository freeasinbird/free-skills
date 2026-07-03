# Mechanical prose-tic check

Motivation: manual em-dash/claude-ism sweeps were requested in 5 sessions
across 4 projects despite the written Conventions rule, and recent entries
here hand-assert "no em dashes in added prose" every session
(2026-07-02-0003 explicitly calls it the check "the repo convention lint
cannot catch"). This session makes the rule mechanical:
`scripts/check-prose-tics.sh` flags em dashes, misused en dashes, and stock
AI openers ("You're absolutely right", "Great question", "Perfect!",
case-insensitive, both apostrophe forms) in markdown, with
`scripts/test-check-prose-tics.sh` as its regression matrix and a
done-checks bullet wiring it in.

## Decisions

- **Project-specific, not canonical.** The check is a free-skills
  `scripts/` check plus a `project:done-checks` bullet; the canonical
  `done` section in agent-setup is untouched. Why: (1) the no-em-dash rule
  lives in this repo's unmanaged Conventions section and the user's
  personal global config, not in the canonical sections, so a canonical
  done-check would enforce a convention agent-setup doesn't ship; (2)
  agent-setup distributes markdown text only, with no mechanism for
  shipping scripts downstream, and a canonical bullet pointing at a script
  the project doesn't have violates the platform-agnostic invariant's
  spirit (never emit steps the running agent can't perform); (3) the
  canonical `done` block deliberately keeps concrete commands in the
  per-project placeholder; (4) precedent: 2026-07-02-0335 scoped a similar
  improvement away from growing a canonical convention in the same PR.
- **`devlog/` is exempt.** Merged entries are frozen by the devlog
  protocol, so the ~126 historical em dashes there can't be swept.
  Tradeoff accepted: new devlog entries rely on the writing convention and
  review, not the mechanical check. Rejected alternative: a baseline list
  of legacy files (complexity without covering new entries either).
- **En-dash rule: allowed only as a tight range joiner**, both neighbors
  non-whitespace and at least one a digit. Chosen over digit-on-both-sides
  because unit-bearing ranges ("2m54s-4m46s", "1.5-3x") are legitimate and
  present in await-pr-review's prose; spaced or word-joining en dashes are
  em-dash substitutes and flagged.
- **No CI wiring.** The repo has no CI (`.github/` holds only the PR
  template), so enforcement is checklist-only via the done-checks bullet,
  consistent with every other check here. Adding CI was out of scope.
- **Code spans are not exempt.** An em dash inside backticks is flagged
  too; strictness is intentional and enumerated in the matrix. The MD038
  gotcha already pushes whitespace-bearing sequences into prose
  descriptions, and the opener literals live only in `.sh` files, which
  the check never scans, so the check cannot flag itself.
- **`.claude/` is excluded** from the no-args file set: stale session
  worktrees under the main checkout are untracked and unignored, so
  `--others` would otherwise scan their duplicate trees.

## Fixed

- Swept the 49 em dashes from the five non-devlog files (README,
  LICENSING-PHILOSOPHY and its license-philosopher reference copy,
  license-philosopher and self-merge SKILL.md); mechanical-churn commit
  added to `.git-blame-ignore-revs`. self-merge's frontmatter description
  gained a colon in the sweep, unsafe in a plain YAML scalar, so it was
  converted to the `>-` block scalar form Conventions already recommend.
  If review folds rewrite the sweep commit, update its SHA in
  `.git-blame-ignore-revs` in the same operation.

## Deferred

- **Cross-project distribution.** The motivating pain is cross-project,
  but shipping the check via agent-setup (scaffolding the script
  downstream, per-project exemptions) is a new mechanism needing its own
  design and user sign-off. Revisit if the manual-sweep requests continue
  in other repos.

## Verification

- Prose-tics matrix: 27/27 passed; repo scan clean (21 files).
- markdownlint, prettier, managed-sync green (AGENTS.md edits stayed
  inside the `project:done-checks` sub-block).
- Both LICENSING-PHILOSOPHY copies verified byte-identical; both touched
  SKILL.md frontmatters re-parsed as YAML.
