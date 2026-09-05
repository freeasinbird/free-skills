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

Self-merge lets an agent merge its own pull request and clean up afterward.
It overrides the safe default of stopping at an open PR for a human to merge.
Never choose this workflow on your own.

This skill needs git, a shell, and a PR host CLI such as `gh`. The CLI must be
authenticated for the PR's repository. Git alone cannot poll required checks,
merge the PR, confirm the merge, or run the forge guards before deletion.
Without the CLI, stop at the open PR and hand the merge to the user.

## When This Applies

Use this skill only when one of these is true:

- The user has explicitly asked the agent to merge its own work, or
- The project has adopted self-merge as a standing policy, recorded in
  AGENTS.md (or the equivalent contributor guide).

Don't infer permission from "Address the issue," "open a PR," or "fix it."
Those requests still end at an open, review-ready PR. If permission is
unclear, stop there and ask.

## Procedure

1. Confirm that the user or project explicitly allows self-merge.
2. Run the script's `check` phase from the base-branch checkout.
3. Confirm the review guardrails that the script can't judge.
4. Run `merge` with the head OID returned by `check`.
5. Run `cleanup` with the same head OID.
6. Stop any review watch that became stale when the PR merged.
7. Follow Project Duties for applicable post-merge work, including after a
   cleanup STOP when its independent prerequisites hold.
8. Report what merged, what cleanup changed, and each duty's outcome or blocker.

## Guardrails

Merging your own PR removes the second pair of eyes. Don't merge until every
guardrail below holds.

- Required checks are green. Poll with
  `gh pr checks <n> --repo '<base-repo>'` until every check finishes. Never
  merge while a check is red or running. Fix failures on the branch.
- Every PR-record call names the PR's repository. A bare number uses the
  CLI's default repository, which may be the fork or unset in a fork clone.
  An unpinned call can inspect or merge a different PR.
- The `--repo` value comes from the project's forge record, an AGENTS.md
  entry naming the forge host and `owner/name` slug, before inferring them
  from a remote: a remote on an SSH host alias hides both. Never take them
  from a sibling project. Pass the slug as `--repo owner/name` and set
  `GH_HOST` to the recorded host when the CLI's default differs.
- The diff has a final self-review in the PR files view. Check for stray
  hunks, debug code, scope creep, and changes the editor view hid.
- Required review artifacts are attached. This includes forge-hosted
  screenshots for visible UI changes. If you can't attach them, stop and ask
  the user.
- The change is reversible and has a low blast radius. For a data migration,
  force-push, release tag, production configuration, or another destructive
  action, stop at the PR and confirm with the user again.

If a guardrail fails and can't be fixed in the session, stop at the open PR.
Tell the user exactly what blocks the merge.

## Merging and Cleanup

The merge-and-cleanup sequence can delete a remote branch and rewrite a
working tree. Use `self-merge.sh`, next to this file, instead of rebuilding the
commands by hand. Its guards cover ignored-file clobbering, tag shadowing,
case-folded ref collisions, worktree mis-parsing, and squash merge queues.

Most of these hazards were found by running the commands, not by reading them.

The script stops before removing a separate linked worktree. It also keeps the
local branch for separate, verified cleanup. The regression matrix in
`scripts/test-self-merge.sh` tests each guard against real scratch repositories.

Invoke the script by path from the checkout that cleanup will rewrite. That
checkout holds, or will hold, the base branch. Here, `<skill-dir>` is the
directory that contains this file. Always pass `--repo` for the fork-clone
reason in Guardrails, with the slug and `GH_HOST` set there. The script takes
`owner/name` alone and resolves it against the CLI's default host.

```sh
<skill-dir>/self-merge.sh check   --pr <n> --repo <owner/name>
<skill-dir>/self-merge.sh merge   --pr <n> --repo <owner/name> --head <oid>
<skill-dir>/self-merge.sh cleanup --pr <n> --repo <owner/name> --head <oid>
```

Ordinary same-repository PRs need no overrides. Use these only when the
defaults don't fit:

- `--base-remote <name>` and `--head-remote <name>` name the base or head
  remote. Use them when several remotes point to the same repository or the
  script resolves the wrong remote.
- `--interval <seconds>` and `--cap-minutes <n>` apply only to `merge`. They
  set the spacing between `MERGED` polls and the total wait. Defaults are 10
  seconds and 15 minutes. Raise the cap for a slow merge queue.

A base or head remote may use a local `~/.ssh/config` `Host` alias, such as
`git@bnw.github.com:owner/name.git` where the alias sets `HostName github.com`.
The script resolves the alias with `ssh -G` and accepts it only when the
resolved host, user, and default port name the PR's forge endpoint. The
destructive head delete then pins that resolved endpoint, so a later config
change can't reroute it. The check stops `remote-repo-mismatch` when `ssh` is
absent, an ssh-command override is active (`GIT_SSH_COMMAND`, `core.sshCommand`,
or `GIT_SSH`), or the alias resolves elsewhere. To proceed then, add a remote
whose URL names the forge host directly (`git@github.com:owner/name.git`) and
pass it with `--base-remote` or `--head-remote`.

### 1. Run `check`

Run `check` before reviewing the final guardrails. It verifies:

- The PR is open.
- The workspace is clean and no git operation is running.
- No competing worktree exists.
- The head and base names don't collide.
- No open PR shares the head branch or stacks on it.
- Any merge queue uses merge commits before the PR is enqueued.

Run every phase from the base-branch checkout in the clone that pushed the
head branch. Worktrees in one clone share refs. The primary checkout can
therefore see a head branch checked out in a linked worktree. Running from the
head worktree is the error that the `wrong-checkout` guard stops.

The result includes the local head tip. Pass that OID to `merge` and `cleanup`
with `--head`. This binds the merge to the commit whose checks and diff you
reviewed.

### 2. Confirm the Guardrails

Confirm that checks are green, the diff is self-reviewed, and required
artifacts are attached. The script can't judge these conditions.

### 3. Run `merge`

The `merge` phase repeats the queue and branch-consumer checks. Earlier answers
can go stale while you review. A stacked PR may be retargeted to another base,
or a new PR may start using the head branch.

The phase creates a real merge commit with an explicit title-only message. It
then waits for the forge to report the PR as merged. A zero exit from the merge
command proves only that the PR was enqueued, so the wait is required.

### 4. Run `cleanup`

If a separate linked worktree still holds the head branch, `cleanup` stops
before changing either branch. Report its path and STOP reason for owner
removal or explicit task-specific cleanup authorization. Self-merge permission
alone doesn't authorize removing it.

Honor applicable cleanup authority already granted in the task without asking
again. Removal remains a separate step outside `self-merge.sh`:

- Stop concurrent users, then refresh all linked-worktree checks through
  read-only inspection outside `cleanup`. Confirm the unique worktree path and
  that both its branch and `HEAD` still match the pinned merged head. Recheck
  ownership, operation state, and the full file inventory, including hidden
  files and index flags. Authorization, clean status, or an idle assertion
  doesn't waive these checks.
- Keep the worktree and report failed or unresolved checks. Removal authority
  alone doesn't authorize moving, changing, or deleting its contents to clear
  a STOP.
- Remove it only when separately authorized and all checks pass. Never remove
  the worktree in which the shell is running.

Rerun `cleanup` only after the separately authorized step has cleared the stop.

Otherwise, `cleanup` runs this order:

1. Land on the base branch.
2. Resolve and validate the base remote under that checkout's configuration.
3. Fast-forward the base before touching the remote feature branch.
4. Check whether forge auto-delete already removed the remote branch.
5. Resolve and validate the head remote again.
6. Keep a fork's branch and report it instead of deleting it.
7. Otherwise, delete a surviving branch behind OID, consumer, and lease
   guards.
8. Prune remote-tracking refs.
9. Report the local branch as `kept_manual`.

Delete the local branch only as a separate step. First verify its tip and
confirm that no worktree uses it.

## Handle Script Results

The last stdout line is the machine-readable result; branch on it and on
the exit code rather than parsing prose:

| Exit | Report                 | Meaning                                                               |
| ---- | ---------------------- | --------------------------------------------------------------------- |
| 0    | `OK <phase> {json}`    | phase complete; json carries the facts                                |
| 2    | `STOP <guard> {json}`  | a guard fired; surface it to the user                                 |
| 4    | `LOOKUP_FAILED <what>` | a read failed; unknown is never absence                               |
| 64   | usage on stderr        | bad or missing flags: fix the call                                    |
| 69   | note on stderr         | `gh` missing: stop unless an equivalent authenticated host CLI exists |

- Report every `STOP`. It marks a state where continuing could destroy work
  or break this skill's cleanup promises. Leave the decision to the user
  unless applicable task-specific worktree cleanup authority already covers
  the separate step described in "4. Run `cleanup`".
- Examples include uncommitted changes, dependent PRs, a squash merge queue,
  hidden worktree edits, and unmerged local commits.
- Never bypass a guard with force, reset, or unauthorized manual deletion.
  Separately authorized worktree cleanup must satisfy the preservation and
  ownership checks; authorization alone doesn't clear the stop.
- `LOOKUP_FAILED` means a listing or fetch did not complete. Retry or
  investigate. Never treat an empty result as proof that nothing depends on
  the branch.

Without `bash`, use `references/cleanup-sequence.md` only when an authenticated
PR-host CLI remains available. Don't improvise the commands from memory. The
consumer, queue, merge, and merged-state guards still need that CLI.

Without any authenticated PR-host CLI, no fallback exists. Stop at the open
PR and hand the merge to the user. Read the specification when you need to
understand or explain a guard.

## Review-Watch Shutdown

A review watch becomes stale when the PR merges. This includes a background
poller, scheduled wake-up, or delegated watcher from a skill such as
await-pr-review.

Self-merge watches often outlive their PR. The watch starts when the PR opens,
and the merge may follow only minutes later.

The trigger is the merge, not a successful cleanup. Stop the watch even when
a guard stops cleanup partway. If the platform can list and stop background
tasks, stop the watch and report it.

If the platform can't stop the watch, don't invent a mechanism. Say that it
will end after activity or its time cap. A later empty wake-up is expected
noise, not a failure.

## Project Duties

After a verified merge, read the governing project instructions and their
named post-merge procedures from one freshly resolved, immutable base commit.
Use the PR host or a fresh fetch, even if cleanup stopped before resync.
Don't discover policy from the feature checkout, stale refs, or issue comments.

- **Readable absence:** Continue to the ordinary summary without new
  mutations, tracker machinery, or a required companion skill.
- **Unreadable or ambiguous policy:** Make no dependent project mutation.
  Report the exact source or rule that prevents determining the duties.
- **Applicable duties:** Name them before acting. Perform only work already
  authorized by the task or governing project policy; reuse prior authority
  without asking again. A self-merge request, issue reference, or successful
  merge alone doesn't authorize issue closure or tracker writes.

Reuse an available project procedure or the relevant non-Git sections of an
available skill. Preserve that procedure's authorization, freshness, input
rereads, verification, ledger, and reporting requirements. Don't require a new
obligation schema or an installed skill when the project supplies its own
procedure.

For applicable duties, resolve the current base tip immediately before each
project mutation and before the final duty report. Use the procedure's
equivalent or stricter checks when supplied; don't duplicate them. If the tip
differs from the policy revision or can't be verified, stop pending writes.
Retain observed completed or unknown results and every mechanical guard.
Report that current policy must be rediscovered before further work or a
claim that all project duties are complete.

When using merge-cleanup, read its Verify Issue Closure through Reconcile
Project Obligations sections and Summarize, including the referenced
`project-obligations.md` procedure. Its merge-cleanup-request authority doesn't
come from a self-merge request. Reuse only those non-Git stages; never run
`merge-cleanup.sh` to obtain duty results or import its fork, local-branch,
or stacked-PR cleanup policy.

When an applicable project duty requires issue-close verification, read the
merged PR body and `closingIssuesReferences` with the forge host and repository
pinned. Check each close-keyword target in its own repository, including those the
forge didn't recognize. Self-merge's result has no `closing_refs`; obtain
this evidence from the forge. Plain `Refs #N` is non-closing. Report still-open
issues; close one only with separate applicable authority.

A mechanical STOP preserves completed Git results and every outstanding
guard. Carry out only safe, independent duties whose own merge, authority,
and evidence prerequisites hold. This handoff never clears a worktree STOP,
changes `kept_manual`, or deletes a retained fork branch.

If a required procedure, tool, authority, or verification is unavailable,
report the affected duty and concrete blocker. Name the next action needed
to obtain current inputs and complete it safely; don't invent an executor or
hand off an edit computed from stale inputs.

## Summarize

Report what merged, what was deleted and resynced, and whether a watch stopped
or will expire. Name any guard that still needs the user, such as a dirty tree,
worktree conflict, OID mismatch, or diverged base.

Account for each applicable project duty separately: verified changes or
no-ops, skipped work with its reason, and blocked or unknown outcomes with
the required next action. An unreadable policy is a named gap, not proof of
no duties. Git cleanup success alone never proves project duties complete.
