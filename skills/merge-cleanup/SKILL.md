---
name: merge-cleanup
description: >-
  Run the post-merge cleanup after a pull request has merged. Use when the
  user reports a merge and wants the workspace tidied: "merged", "PR merged,
  please clean up", "PR #N is merged", "just merged it, tidy up", "the PR
  landed". Deletes the remote branch if the forge's auto-delete didn't,
  resyncs the branch the PR merged into, deletes the local branch, prunes
  stale tracking refs, verifies that issues the PR claimed to close actually
  closed (surfacing any that need manual closing), and shuts down any
  still-running review watch for that PR where the platform has one. Not
  for performing the merge itself (that is the self-merge skill's job), and
  not for cleaning up branches of PRs that are still open.
---

# Merge Cleanup

Post-merge housekeeping for a pull request that has already merged: restore
the workspace to a clean state on the branch the PR merged into (its base,
usually the default branch), check that the PR's
issue-closing keywords actually closed their issues, and stop any review
watch still running for the PR.

This skill assumes git and a shell. A PR host CLI (such as `gh`) enables
the verification steps; every step that needs one states the fallback. It
never performs the merge itself: when the user asks the agent to merge its
own PR, that is the self-merge skill's territory.

## Identify the merged PR and branch

Work out which PR merged and which local/remote branch carried it, from
conversation context first (the PR this session opened or handed off),
otherwise from the PR host CLI (for example
`gh pr view <n> --json state,mergedAt,headRefName,baseRefName`) or from
`git branch --merged origin/<default-branch>` after a fetch (ignore the
default and current branches in its output). If the PR or branch cannot be
determined unambiguously, ask the user rather than guessing; deleting the
wrong branch is the one failure this skill must never risk. Two hard rules
on the resolved name: if `<branch>` resolves to the default branch or to
the merged PR's base branch, abort; this skill never deletes the branch it
resyncs. And resolve the remotes before acting: in a fork workflow the
remote hosting the PR head is not the remote whose base branch moved when
the PR merged. Use the head remote for the remote-branch existence check
and deletion, and the base remote for merge verification and resync;
`origin` below stands for whichever of those two roles the step names,
and in a single-remote clone they are the same remote.

## Verify the merge before deleting anything

Confirm the PR is actually merged, not merely closed, before any deletion:
a closed-unmerged PR's branch may hold the only copy of the work. Check
with the PR host CLI (`mergedAt` non-null, state `MERGED`) or by confirming
the branch tip is reachable from the PR's base branch, usually the default
branch (`git merge-base --is-ancestor <branch> origin/<base-branch>` after
a fetch). In a squash- or rebase-merge repo the branch tip never becomes an
ancestor of the base, so there only the forge's `MERGED` state counts as
verification. When the tools can check, never proceed on the user's word
alone. If no tool can confirm the merge, do not delete the remote branch:
say so, and hand the user the exact deletion command to run once the forge
shows the PR as merged (confirming a branch's name is not confirming that
it merged).

## Git cleanup sequence

Run the sequence in order; each guard exists because the step after it is
destructive or history-changing.

1. **Delete the remote branch only if auto-delete didn't.** Check whether
   it still exists and where it points, with
   `git ls-remote --heads origin <branch>`; many repos auto-delete on
   merge. If the ref exists, its OID
   must match the merged PR's head commit (`headRefOid`): deleting a remote
   ref removes whatever it points at now, and a mismatch means the branch
   moved or was reused after the merge and may carry unmerged work, so
   stop and surface it instead of deleting. Also check for open PRs that
   target this branch as their base (for example
   `gh pr list --base <branch> --state open`) and retarget any to the
   merged PR's own base branch first (GitHub retargets them automatically
   when their base merges; verify rather than assume) so the deletion
   doesn't orphan them or point follow-up work at the wrong branch.
   Without a PR host CLI, ask the user whether anything stacks on this
   branch before deleting it remotely. Then, with the merge verified and
   the OID matched, delete it (`git push origin --delete <branch>`, or the
   forge CLI).
2. **Check the tree is clean, then switch to the branch the PR merged
   into** (its base, usually the default branch); that is the branch that
   moved, and the later steps validate against the current `HEAD`. A
   checkout can succeed over uncommitted changes and silently carry them
   along, so check first (`git status --porcelain`). If the tree is dirty,
   stop and surface the uncommitted work rather than switching over it or
   stashing silently; the user decides what happens to their changes. Only
   then `git checkout <base-branch>`.
3. **Resync** with `git pull --ff-only`. If the pull refuses to
   fast-forward, report it and stop; never "fix" a diverged branch with
   reset or force operations during cleanup.
4. **Delete the local branch** with `git branch -d <branch>` (lowercase
   `-d`, so git itself refuses if the branch isn't merged into HEAD; treat
   that refusal as a signal to re-verify, not a prompt to escalate). One
   exception: when `-d` refuses for a PR the forge reports `MERGED`
   (squash- and rebase-merge repos guarantee this refusal, since the
   branch tip never becomes an ancestor), deleting with `-D` is correct
   only after confirming the local tip matches the PR's head commit
   (`headRefOid`); never on the user's word or an ancestor check alone.
5. **Prune stale tracking refs** with `git fetch --prune`.

## Issue-close verification

Merging is supposed to close the issues the PR body referenced with close
keywords ("Closes #N"), but the mechanism fails silently for cross-repo
references, merges to a non-default branch, and keyword typos. With a PR
host CLI, list the issues the forge linked as closing references (for
example `gh pr view <n> --json closingIssuesReferences`), also scanning the
merged PR body for close keywords the forge may not have parsed, and check
each referenced issue's state. Surface any still open for the user to
close; do not close them yourself unless asked, since whether an issue is
truly resolved is the human's call. Plain "Refs #N" mentions are
intentionally non-closing; don't flag them. Without a PR host CLI, say the
check could not run instead of skipping it silently.

## Review-watch shutdown

If a review watch for this PR is still running (a backgrounded poller, a
scheduled wake-up, or a delegated watcher from a skill like
await-pr-review), it is now watching a finished PR. Where the platform lets
you list and stop background tasks, stop the watch and say so. Where it
doesn't, don't invent a mechanism: note that the watch will end on its own
(such watchers self-terminate on activity or when their time cap expires)
so a later wake-up reporting nothing is expected noise, not a failure.

## Summarize

Close with a short report: what was deleted and resynced, what the merge
verification showed, any issues that still need manual closing, any watch
stopped or left to expire, and anything that blocked a step (dirty tree,
unverifiable merge, undeletable branch) that now needs the user.
