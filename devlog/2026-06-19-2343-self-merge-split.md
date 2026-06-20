# Move self-merge out of the default finish line

Addresses issue #11: agent-setup's canonical workflow made "merged `main`"
the default endpoint and told the agent to `gh pr merge` its own PR. That
is a self-approved merge with no second reviewer — an unsafe default.

## What landed

- Reworked the `finish-line` and `pull-requests` canonical sections so the
  default endpoint is an **open, review-ready PR with checks green**; the
  agent self-reviews and hands off rather than merging. Mirrored the same
  text into this repo's own AGENTS.md (markers stay in sync).
- "Landing a PR" → "Handing off the PR". Merge mechanics are kept only for
  the explicit "merge it for me" case, not as the default.
- Added a new opt-in `self-merge` skill carrying the merge-it-yourself
  workflow plus guardrails (green checks, self-review, artifacts attached,
  reversible/low-blast-radius). Listed it in the README table.

## Decisions

- **Split, not delete.** Issue left it as "consider"; user chose to split.
  The full self-merge workflow lives in its own skill so projects/users opt
  in deliberately instead of inheriting it.
- **Named `self-merge`, not `self-approve`.** The issue said "self-approve",
  but the skill's job is the merge action and "self-merge" maps to natural
  opt-in phrasing while dodging the GitHub "approve review" ambiguity.
- **Generic reference.** Canonical sections say "the project has adopted an
  opt-in self-merge workflow" without naming the skill — they get pasted
  into projects that won't have it. agent-setup SKILL.md left unchanged; it
  never named self-merge itself, only the canonical sections did.
- **This repo follows the new default now.** Opening this PR and handing
  off for review rather than self-merging.

## Deferred

- Nothing. Issue #10 (installation guidelines) is separate.
