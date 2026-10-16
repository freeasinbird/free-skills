# The Guarded Merge Sequence: Prose Specification

`self-merge.sh`, bundled beside `SKILL.md`, is the canonical executable form
of this sequence: its `check`, `land`, and `merge` phases. Use it when
possible. This file explains the sequence and the guards it implements. It
ends at the merge; post-merge cleanup belongs to the merge-cleanup skill.
Confirm that skill is installed before `land`, as `SKILL.md`'s Guardrails
require, because a merge is irreversible and a companion found missing after
it leaves no guarded cleanup.

Most hazards below were found by running commands, not by reading them.

Read this file when the script can't run but an authenticated PR-host CLI can
still perform every forge guard. Also read it to understand why a guard
stopped. Without that CLI, stop at the open PR and hand the merge to the user.

Evidence for every claim lives in the work unit's decision note:
`devlog/2026-07-24-2311-self-merge-resync-guards.md`.

## Rules for Every Step

Bind values instead of pasting them:

- Treat every branch, remote, path, OID, and title as untrusted input.
- Capture each value from the command that produces it. Store it in a variable
  and reference it double-quoted.
- Never retype or single-quote a captured value. A contained single quote
  breaks out. A pasted name is evaluated by the shell, so a ref containing a
  command substitution can run when inserted into a snippet.
- Pass `--` before positional remotes, paths, and bare refs. This stops a
  leading-hyphen value from becoming an option.
- Treat `git checkout` as the exception. There, `--` starts a pathspec, so a
  leading-hyphen branch name is a stop instead of a quoting problem.
- Pass the PR number as-is only after confirming that it contains digits only.
- Take `<repo>` from the project's forge record, an AGENTS.md entry naming the
  forge host and `owner/name` slug, before inferring it from a remote. Never
  take it from a sibling project.
- Set `GH_HOST` to the recorded host whenever the CLI's default differs.

An empty result doesn't prove absence:

- A failed listing can return nothing, just like a successful empty listing.
- Read each exit code. Treat an unknown result as "keep the branch, stop."

## 1. Merge

### Check Branch Consumers

Ask the branch-consumer questions before merging. Auto-delete can remove a
shared head during the merge, before merge-cleanup's consumer guards run.

- Check open PRs whose head is this branch. One branch can back several PRs.
- For a fork head, use the API filter `head=<owner>:<branch>`. The command
  `gh pr list --head` rejects that form.
- Check open PRs whose base is this branch. These are stacked PRs.
- Exclude the current PR from both checks.
- Stop for the user when either check finds a consumer.
- Ask both questions again immediately before merging. The answers can change
  while checks and self-review run.

### Verify the Merge Queue

If the base branch has a merge queue, identify its integration method before
enqueueing. The queue chooses the merge shape, not the `--merge` flag. A
squash queue destroys the intended history.

- Query the branch-rules API with `gh api --paginate
"repos/<repo>/rules/branches/<url-encoded-branch>"`.
- Read the `merge_queue` rule's parameters.
- Percent-encode the branch. A `#` or `?` in the name can truncate an
  unencoded URL and read another branch's rules.
- Don't use the CLI's `ruleset` commands. They have no JSON output and can't
  report the integration method.
- Aggregate every page before treating an empty result as no queue.
- Stop on multiple queue rules, any method other than a merge commit, or a
  payload shape you can't identify.

Check the queue again on the PR's base at merge time. Auto-retargeting a
stacked PR can change its base and queue after the first check.

A queued merge can't carry the command's explicit subject and body into the
eventual commit. A `MERGE` queue therefore also needs the repository settings
`PR_TITLE` and `BLANK`. Refresh both settings at the final pre-enqueue boundary
or stop.

### Check the Fork Network and Auto-Delete

Read the repository's `fork`, `forks_count`, and `delete_branch_on_merge`
fields from the forge.

A fork, or a root repository with forks, has branch consumers that
same-repository queries can't enumerate. If auto-delete is enabled, stop
before a direct merge or queue enqueue. Otherwise, the merge can delete a
branch used elsewhere in the fork network before merge-cleanup can check
its consumers.

### Land on the Current Base

On a base without branch protection, nothing else checks that the head was
tested against the current base. Run one landing round before the merge:

1. Repeat the consumer and queue guards. A rebase push rewrites the branch
   under any PR that heads or stacks on it.
2. Fetch the base into its remote-tracking ref with a forced refspec
   (`+refs/heads/<base>:refs/remotes/<remote>/<base>`), so a force-pushed
   base still updates it, and record that tip. Stop if the forge reports a
   different tip.
3. Test `git merge-base --is-ancestor <tip> <verified-oid>`. When it fails,
   rebase the verified OID onto the tip in a temporary detached worktree, then
   remove that worktree. Stop when the rebase leaves no commits beyond the
   tip. A rebase or reset can silently overwrite or delete ignored files. In
   the worktree that holds the branch, confirm it is clean with no paused
   operation. Then move the branch with
   `git checkout --no-overwrite-ignore --no-recurse-submodules -B <branch> <new-oid>`.
   Submodule recursion doesn't pass the ignored-file protection down.
   Without such a worktree, use `git update-ref` with the verified OID as the
   old value. Stop when the move is refused.
4. On a conflict, stop. The branch is untouched. The author rebases by hand,
   reads `git range-diff`, pushes, and starts again from `check`.
5. Push the rebased branch with
   `--force-with-lease=refs/heads/<branch>:<verified-oid>`. A refused lease
   means someone pushed after `check`: move the local branch back to the
   verified OID the same way, and stop. Otherwise, the round ends here without a merge. Read
   `git range-diff <tip> <verified-oid> <new-oid>`, because CI reruns on the
   new head but nothing reviews its diff. Then start again from `check` with
   the new head as the verified OID.
6. On the tip, wait for CI on that exact commit. Read
   `repos/<repo>/commits/<oid>/check-runs` with `--paginate` and
   `repos/<repo>/commits/<oid>/status`. Pass only when every check run and
   status finished as success, neutral, or skipped, on two consecutive reads.
   A commit with no check runs and no statuses by the deadline is a stop, and
   so is one green read without a second before it.
7. Reread the PR and stop if its base changed. Just before merging, read
   `repos/<repo>/git/ref/heads/<branch>` for the base. Stop when its OID
   differs from the recorded tip, and start the round again.

One round is one attempt. The final read and the merge aren't atomic, which
this procedure accepts while one person starts every merge. Clean up with the
head that merged.

### Pin the Merge to the Reviewed Head

Run
`gh pr merge <n> --repo <repo> --merge --match-head-commit <verified-oid>`.
The verified OID must be the local branch tip this session pushed. A
forge-reported head can move after a third-party push, so a missing local
branch is a stop.

Pass an explicit title-only message. Read the title from the forge, and refuse
an empty or `null` result. Otherwise, a failed lookup can write
`null (#<n>)` permanently into history.

Keep the final reads in this order:

1. Read the title.
2. Repeat the queue and consumer guards.
3. When landing, confirm that the base tip hasn't moved.
4. Refresh repository settings and repeat the auto-delete guard.
5. Make no more forge reads before merging.

This order narrows the window in which auto-delete can change after its check.

### Wait for the Merge

A zero exit proves only that the PR was enqueued. Hand off to merge-cleanup
only after the forge reports state `MERGED` and a non-null `mergedAt`.

Deleting the branch while a queued PR waits can cancel the merge and destroy
the branch's last copies. Cap every retry sleep by the time left before the
deadline. A long polling interval must not extend the deadline.
