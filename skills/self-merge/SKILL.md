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

This skill assumes git, a shell, and a PR host CLI (such as `gh`)
authenticated for the PR's repository. Polling the required checks, merging,
confirming the merge landed, and the pre-delete guards have no git-only
substitute. Where no such CLI is available, stop at the open PR and hand the
merge to the user rather than merging on checks you could not verify.

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

- **Required checks are green.** Poll them until they complete
  (`gh pr checks <n> --repo '<base-repo>'`); never merge red or
  still-running. Fix failures on the branch, never merge around them. Pin
  every PR-record call to the PR's own repository like that: a bare number
  resolves against the CLI's default repository, which in a fork clone can
  be the fork or unset, so an unpinned call reports a different PR's checks
  and the merge would merge that PR.
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

The merge-and-cleanup sequence is destructive (it can delete a remote branch
and rewrites a working tree), and nearly every one of its hazards was found by
executing commands rather than reading them, so the sequence ships as an
executable: `self-merge.sh`, next to this file. It deliberately stops before
removing a separate linked worktree and always preserves the local branch for
a separately verified manual cleanup. Run it rather than re-deriving commands
by hand; its guards encode verified failure modes (ignored-file clobbering,
tag shadowing, case-folded ref collisions, worktree mis-parsing, merge queues
that squash) that a hand-rolled sequence re-opens. The regression matrix in
`scripts/test-self-merge.sh` exercises each guard against real scratch
repositories.

Invoke it **by path, from the checkout the cleanup will rewrite** (the one
that holds, or will hold, the base branch), where `<skill-dir>` is the
directory holding this file. Always pass `--repo`; it is required, for the
fork-clone reason in Guardrails. The sequence is three phases, with the
judgment between them left to you:

```sh
<skill-dir>/self-merge.sh check   --pr <n> --repo <owner/name>
<skill-dir>/self-merge.sh merge   --pr <n> --repo <owner/name> --head <oid>
<skill-dir>/self-merge.sh cleanup --pr <n> --repo <owner/name> --head <oid>
```

Four optional overrides exist for the cases where the defaults do not fit;
none is needed on an ordinary same-repository PR:

- `--base-remote <name>` and `--head-remote <name>`: name the remote for the
  base or head repository instead of letting the script resolve it, for a
  layout where the resolution is ambiguous (several remotes point at the same
  repository) or wrong.
- `--interval <seconds>` and `--cap-minutes <n>`: merge phase only, the
  spacing between MERGED polls and the total time to wait for the forge to
  report the merge (defaults 10 and 15). Raise the cap for a slow merge
  queue.

1. **check**, before merging: PR open, workspace clean, no git operation
   in progress, no competing worktree, no head/base name collision, no
   open PR sharing or stacked on the head branch, and any merge queue's
   method identified as merge-commit before anything is enqueued. Run it,
   like every phase, from the base-branch checkout named above, within the
   clone that pushed the head branch: worktrees share the repository's
   refs, so in a dedicated-worktree layout (head branch in a linked
   worktree, base in the primary checkout) the base checkout sees the head
   branch's tip, and running from the head worktree instead is what the
   `wrong-checkout` guard stops. The verified head OID check prints is
   that local tip, and it is what `merge` and `cleanup` pin with `--head`,
   so the merge is bound to the commit whose checks and diff you actually
   reviewed.
2. Confirm the Guardrails above hold (checks green, diff self-reviewed,
   artifacts attached). The script cannot judge these.
3. **merge**: re-verifies the queue and consumer guards (check's answers
   go stale while you verify the guardrails: a stacked PR's retarget can
   change the base and its queue, and a new PR can start sharing the
   head), then merges with a real merge commit and an explicit title-only
   message, and waits until the forge reports the PR merged. A zero exit
   from a merge command proves enqueueing, not merging, so the wait is
   part of the phase.
4. **cleanup**: checks whether auto-delete ran rather than assuming it,
   and stops before either branch is mutated when a separate linked head
   worktree remains: make that checkout idle, remove it as a deliberate
   step, then rerun cleanup. Otherwise it deletes the surviving remote
   branch behind OID, consumer, and lease guards (a fork's branch is never
   deleted, only reported), lands on and fast-forwards the base, prunes,
   and reports the local branch as `kept_manual`. Delete that local branch
   as a separate deliberate step after verifying no worktree uses it.

The last stdout line is the machine-readable result; branch on it and on
the exit code rather than parsing prose:

| Exit | Report                 | Meaning                                                               |
| ---- | ---------------------- | --------------------------------------------------------------------- |
| 0    | `OK <phase> {json}`    | phase complete; json carries the facts                                |
| 2    | `STOP <guard> {json}`  | a guard fired; surface it to the user                                 |
| 4    | `LOOKUP_FAILED <what>` | a read failed; unknown is never absence                               |
| 64   | usage on stderr        | bad or missing flags: fix the call                                    |
| 69   | note on stderr         | `gh` missing: stop unless an equivalent authenticated host CLI exists |

Treat every `STOP` as the user's decision, not an obstacle: the guards
stop exactly where proceeding would destroy work (uncommitted changes, a
branch other PRs depend on, a squash-configured merge queue, a worktree
holding invisible edits, unmerged local commits) or would leave the
repository in a state this skill promised not to create. Never re-run a
phase with the state "fixed" by force, reset, or a manual delete to get
past a guard; report what fired and let the user decide. `LOOKUP_FAILED`
means a listing or fetch did not complete: retry or investigate, and never
read the empty result as "nothing depends on this branch".

Where the platform has no `bash` but an authenticated PR-host CLI is
available, do not improvise the commands from memory: follow
`references/cleanup-sequence.md`, the prose specification the script
implements; its consumer, queue, merge, and merged-state guards still
require that CLI. Where no such CLI is available at all, no fallback
exists: stop at the open PR and hand the merge to the user, per the
prerequisite above. The specification is also the place to read when you
need to understand or explain why a guard stopped.

## Review-watch shutdown

Once the PR is merged, a review watch still running for it (a backgrounded
poller, a scheduled wake-up, or a delegated watcher from a skill like
await-pr-review) is watching a finished PR. Self-merge is the likeliest
place for one to outlive its PR, since the watch starts when the PR opens
and the merge follows minutes later. The trigger is the merge, not a clean
cleanup run: the watch is stale the moment the PR merges, so the step still
applies when a guard stopped the cleanup partway. Where the platform lets
you list and stop background tasks, stop the watch and say so. Where it
doesn't, don't invent a mechanism: note that the watch will end on its own
(such watchers self-terminate on activity or when their time cap expires)
so a later wake-up reporting nothing is expected noise, not a failure.

## Summarize

Summarize what merged, what was deleted and resynced, any watch stopped or
left to expire, and anything a guard stopped (dirty tree, worktree layout,
OID mismatch, diverged base) that now needs the user.
