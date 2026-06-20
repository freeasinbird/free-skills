# Adopt `Closes #N` keyword as the issue-closing convention

Follow-up to the #11/#12 work. PR #12 said "Issue #11" without a closing
keyword, so the merge didn't auto-close or link the issue — it had to be
closed by hand. Captures the convention so it doesn't recur.

## What landed

- PR-body **Why** guidance (pull-requests canonical section + this repo's
  AGENTS.md mirror) now states the closing rule: a close keyword immediately
  before each issue number it fully resolves/finishes (`Closes #11`), plain
  `#N` for related-but-unfinished issues, closing left to a human.
- Same rule added to the PR template — both the scaffolding `§pr-template`
  source and this repo's live `.github/pull_request_template.md`.

## Decisions

- **Keyword as the mechanism, not a cleanup step.** The new handoff default
  means the agent isn't the one merging, so any post-merge "comment on the
  issue" step is unreliable. A closing keyword fires on merge regardless of
  who merges and creates the proper linkage. Rejected adding a manual
  comment step to the finish-line cleanup.
- **Guard the auto-close.** Only attach `Closes` to an issue the PR
  completely addresses or finishes; otherwise a plain `#N` so a multi-PR
  issue isn't closed early. Closing comment stays a judgment call for
  resolution nuance.
- **Phrase the rule, not cases.** One sentence ("close keyword immediately
  before each issue number") covers single, multiple, and mixed PRs and
  encodes both GitHub footguns: the keyword must be adjacent to `#N`
  (`Closes #11`, not `closes issue #11`), and a bare list (`Closes #11, #12`)
  closes only the first — repeat the keyword to close several.

## Deferred

- Nothing.
