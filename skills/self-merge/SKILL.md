---
name: self-merge
description: >-
  This skill should be used when a user explicitly opts into letting the
  agent carry a pull request all the way to merged `main` itself: "merge it
  yourself", "self-merge", "merge my own PR", "carry the PR through to
  merge", "land the PR without waiting for me". It is an opt-in override of
  the safe default (stop at an open, review-ready PR for a human to merge)
  and assumes the user accepts that no second party reviews before merge.
---

# Self-Merge

Opt-in workflow that lets an agent merge its own pull request and clean up,
rather than stopping at an open PR for a human to review and merge. This is
a deliberate override of the safe default, not a convenience to reach for on
your own.

## When this applies

The default agent finish line is an open, review-ready PR; merging is a
human decision. Use this skill **only** when one of these is true:

- The user has explicitly asked the agent to merge its own work, or
- The project has adopted self-merge as a standing policy, recorded in
  AGENTS.md (or the equivalent contributor guide).

Do not self-merge by inference. "Address the issue", "open a PR", or
"fix it" is not a request to merge. If you are unsure whether self-merge
is in effect, stop at the open PR and ask.

## Guardrails

Merging your own PR removes the second pair of eyes before merge, so the
agent carries the full review burden. Do not merge until all of these hold:

- **Required checks are green.** Poll `gh pr checks <n>` until they
  complete; never merge red or still-running. Fix failures on the branch,
  never merge around them.
- **Self-review the diff in the PR files view.** Look for stray hunks,
  leftover debug code, scope creep, and anything the editor view hid.
- **Required review artifacts are attached**, for example GitHub-hosted
  screenshots for a visible UI change. If you cannot attach them yourself,
  stop and ask the user rather than merging without them.
- **The change is reversible and low-blast-radius.** For irreversible or
  destructive actions (data migrations, force-pushes, release tags,
  production config), stop at the PR even under self-merge and confirm
  with the user first.

If any guardrail fails and cannot be resolved in the session, stop at the
open PR and say exactly what is blocking the merge.

## Merging and cleanup

Once the guardrails hold:

1. **Merge** with `gh pr merge <n> --merge`: a real merge commit, so
   `git log --first-parent` reads as the work-unit narrative. Where the
   repo's title-only merge-message settings aren't confirmed set, pass
   the message explicitly instead of inheriting the forge default:
   `gh pr merge <n> --merge --subject '<PR title> (#<n>)' --body ''`.
   Squash and
   rebase are typically disabled to preserve atomic history; don't re-enable
   them to work around this. The remote branch auto-deletes when the repo is
   configured for it.
2. **Resync**: `git checkout main && git pull --ff-only`. If the work ran
   in a dedicated worktree, `git checkout main` refuses with "already used
   by worktree"; resync `main` in the primary checkout instead.
3. **Clean up**: delete the local branch (`git branch -d <branch>`; from a
   worktree, `git worktree remove <path>` first, since a branch checked out
   in a worktree can't be deleted) and `git fetch --prune`. A stacked
   follow-up PR retargets to `main` on its own once its base merges.

Then summarize what merged and what, if anything, remains.
