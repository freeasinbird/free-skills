# The Guarded Merge-and-Cleanup Sequence: Prose Specification

`self-merge.sh`, bundled beside `SKILL.md`, is the canonical executable form
of this sequence. Use it when possible. This file explains the sequence and
the guards it implements.

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
shared head during the merge, before any cleanup guard runs.

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
branch used elsewhere in the fork network before cleanup can keep it.

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
2. Repeat the queue, consumer, and auto-delete guards.
3. Refresh repository settings after the consumer queries.
4. Make no more forge reads before merging.

This order narrows the window in which auto-delete can change after its check.

### Wait for the Merge

A zero exit proves only that the PR was enqueued. Start cleanup only after the
forge reports state `MERGED` and a non-null `mergedAt`.

Deleting the branch while a queued PR waits can cancel the merge and destroy
the branch's last copies. Cap every retry sleep by the time left before the
deadline. A long polling interval must not extend the deadline.

## 2. Preflight the Workspace

Run these checks in the checkout that cleanup will rewrite. Stop if any check
fails.

- Require an empty `git status -uall --porcelain`. The `-uall` is required
  because `status.showUntrackedFiles=no` can hide untracked files from plain
  `--porcelain` output.
- Require no git operation in progress. `--porcelain` doesn't report these
  operations.
- Use `git rev-parse --git-path` to locate `MERGE_HEAD`, `CHERRY_PICK_HEAD`,
  `REVERT_HEAD`, `BISECT_START`, `rebase-merge`, and `rebase-apply` for this
  worktree. Treat a symlink at any path as active state. `rebase-apply` also
  covers interrupted `git am` work.
- Don't test operation names as revisions. A normal local branch named
  `MERGE_HEAD` resolves through `refs/heads/` and isn't a paused merge.
- Require that no other worktree holds the base branch. Run cleanup from that
  worktree instead.
- Require that the head branch doesn't resolve to the base or default branch.

Probe the checkout filesystem instead of trusting `core.ignorecase`. On a
case-insensitive filesystem, `refs/heads/Main` and `refs/heads/main` can be one
file even when that setting is false. Deleting the case-spelled head would
then delete the base branch.

Probe candidate names one path component at a time. Use temporary, invalid-ref
children inside the matching existing loose-head directories. Their filesystem
rules may fold Unicode case or composed and decomposed forms. An ASCII-only
case transform can't detect those collisions. Directory-scoped case folding
makes each existing branch-prefix directory load-bearing, not only
`refs/heads`.

## 3. Preflight Linked Worktrees

### Find the Head and Base Worktrees

Read `git worktree list --porcelain -z`. Its output contains NUL-terminated
fields, not NUL-terminated records.

1. Strip the `worktree` keyword.
2. Pair each path with the following `branch` field.
3. Match the branch against the PR head received from the forge. Never infer
   it from `HEAD`.
4. Accept zero or one head match. Zero means no worktree checks out the head;
   several matches are ambiguous and must stop.
5. Apply the same count check to the base branch before resync. When one base
   match exists, require it to be the current checkout.

Don't send a path through command substitution because it strips a trailing
newline. Don't use a line-based parser because spaces and newlines can
mis-target another worktree. Don't use macOS `awk` with a NUL record separator
because it silently returns nothing. Use a NUL-capable reader such as
`read -d ''` in bash or zsh, use python3, or stop.

### Validate Local Refs and Repeat the Scan

Reject a symbolic local base before resolving remotes. Checkout follows the
symbolic target, so a later mismatch check is already too late.

Validate the local head before trusting its worktree path. A symbolic head ref
is a stop. A direct head ref must equal the pinned merged head.

Repeat the head-worktree scan immediately before remote resolution or any
mutation. This closes layout changes during the local-ref checks. Use only the
fresh unique match for the remaining inventory and stop decisions.

### Check the Other Worktree's Operation State

When the unique head match is a separate worktree, inspect its operation
state. Operation state belongs to each worktree. A clean preflight in the
cleanup checkout says nothing about another checkout.

A paused merge can have no tree delta and an empty file inventory. Run the
same operation probes against the other worktree. Otherwise, manual removal
can delete its paused state and still exit 0.

### Inventory Hidden Files

Inventory the other worktree from outside it. Removal deletes its directory.
Ignored files don't trigger git's untracked-file refusal. Tracked files marked
`assume-unchanged` or `skip-worktree` are also hidden from porcelain output.
Removal can destroy those hidden files and still exit 0.

1. Read `git ls-files -vz --full-name`.
2. Keep rows whose first column is a lowercase letter or `S`. Lowercase marks
   `assume-unchanged`; `S` marks `skip-worktree`. Ignore `H`, which marks a
   normal cached file.
3. Test each kept row with `[ -e ]` or `[ -L ]`. Prefix its path with that
   worktree's path because rows are relative to the worktree, not the caller.
4. Keep the symlink check because a dangling symlink fails `-e` but removal
   still deletes it.
5. Exempt an absent path only when its tag is `S` and that worktree reports
   `core.sparseCheckout=true`. Sparse checkout omits excluded paths. An absent
   assume-unchanged path is an uncommitted deletion.
6. Keep `-z` through the full read. Plain output C-quotes paths containing a
   newline or tab, so an existence test on the displayed spelling fails.
7. Stop when the inventory finds anything.

Never remove the worktree in which the shell is running. Git can delete that
worktree without complaint.

### Stop Before Removing a Separate Worktree

A separate linked head worktree is a stop before any local or remote branch
mutation. Inventory its operation and file state to give a specific diagnosis,
but leave even a clean worktree intact.

Git has no portable atomic operation that verifies a worktree's detached
`HEAD`, inventories files, removes the worktree, verifies the branch OID, and
enforces the checked-out guard. A concurrent reset can move a clean detached
`HEAD` after the check. Removal can then drop its only ref and reflog.

Stop concurrent users. Remove that worktree as a separate, deliberate step,
then rerun cleanup. This stop doesn't apply when cleanup starts inside the
clean head checkout. The later base switch releases that same worktree from
the head. No head match also proceeds normally.

## 4. Land on the Base Branch

- After rejecting symbolic refs, check for a direct local base with
  `git show-ref --verify --quiet refs/heads/<base>`. Don't use
  `rev-parse --verify`; a same-named tag satisfies it, and a bare checkout can
  detach `HEAD` at the tag while the real base stays stale.
- For an existing branch, run `git checkout --no-overwrite-ignore <base>`.
- For a missing branch, first fetch `refs/heads/<base>` into the
  remote-tracking ref. The start point may be absent in a fresh,
  single-branch, or sparse clone. Then run
  `git checkout --no-overwrite-ignore --no-track -b` from that ref.
- Suppress automatic tracking on branch creation. A branch-conditioned remote
  change must not preserve the pre-landing remote.
- Stop when either checkout would overwrite an ignored file tracked by the
  base. A plain `git checkout` silently overwrites that file.
- Confirm that `git symbolic-ref -q HEAD` reports `refs/heads/<base>` after
  either checkout path.

Resolve the base remote again after checkout. An
`includeIf "onbranch:…"` rule can remove the old mapping or reveal another
URL.

For a hosted remote, require its URL to match the repository API's
authoritative clone endpoints. For a hostless path, make an explicit trust
decision before checkout:

- Expand Git's leading `~/` and `~user/` path syntax.
- Resolve other relative paths from the worktree root.
- Follow every symlink before and after checkout.
- Require the post-checkout destination to equal the trusted canonical
  destination.

A hosted replacement can be checked against the forge. A different hostless
destination isn't a new implicit trust decision and must stop.

When cleanup creates the local base, set both tracking keys after validation.
Set `branch.<base>.remote` to the post-landing remote. Set
`branch.<base>.merge` to `refs/heads/<base>`. Don't retain the pre-landing
remote or leave the new branch untracked.

## 5. Resync

Fetch the base explicitly. Then run
`git merge --ff-only --no-overwrite-ignore refs/remotes/<remote>/<base>`.

Don't use `git pull`. Its merge step overwrites ignored files by default, and
it rejects `--no-overwrite-ignore`. A bare pull also follows the configured
upstream, which can be a fork's stale copy.

A refused fast-forward is a stop. Causes include divergence or an ignored file
that the base started tracking. Never resolve it with reset or force.

## 6. Delete the Remote Head Branch

Reach this step only after base resync succeeds. Resolve the head remote again
under the base branch's active configuration before any existence check or
delete. No remote name or URL read before checkout proves the current mapping.

### Require One Read-and-Write Destination

The remote you inspect must be the repository you write. Git uses configured
`pushurl` entries for pushes, while `ls-remote` reads the fetch URL. A push
writes to every configured push URL, but a plain push-URL query shows only the
first.

- Require exactly one effective push destination.
- Require that destination to have the fetch URL's identity.
- Reject two different destinations because they broadcast the delete.
- Reject two identical destinations because one delete succeeds and the
  second lease fails against stale data.
- Read the full set with `git remote get-url --push --all`.
- Reject blank records before mutation. A valid URL followed by a blank can
  delete at the valid destination before Git reports failure.
- Treat `insteadOf` and `pushInsteadOf` rewrites as already expanded in the
  returned URL.
- Capture URLs without stripping trailing newlines. A path ending in a
  newline and its newline-less sibling are different repositories.
- Stop when raw configured URLs contain a newline. No line-based listing can
  compare them safely.

### Compare Hosted Identities

Compare hosted URLs by these full components:

- Keep the transport. HTTP(S), git, SSH URL, and SCP transports are distinct
  endpoints even when host and path match.
- Lowercase the authority. Keep the complete repository path with its case.
- For non-SSH schemes, strip credential userinfo at the last `@`. A colon in
  `user:pass` must not truncate the host.
- For SSH and SCP, keep the username. Different remote users can resolve the
  same relative path to different repositories.
- Treat userless SCP `host:path` forms as hosted.
- Parse bracketed IPv6 SCP hosts through their closing bracket.
- Keep the port. Different ports are distinct, and alternate spellings of a
  default port fail closed.
- Keep deployment prefixes, path case, and a terminal `.git`.

For example, `https://host/a/owner/name.git` and
`https://host/b/owner/name.git` can name different repositories. Paths that
differ only by case or `.git` can also differ. When auto-resolving a remote,
derive and normalize the forge's `owner/name` tail separately.

### Compare Local and File Identities

A URL with no host is a local path. Compare its full path. Truncating to the
tail would equate `/a/owner/name` with `/b/owner/name`. Removing `.git` would
equate sibling directories `repo` and `repo.git`.

Normalize only the exact lowercase-scheme forms `file:///path` and
`file://localhost/path` to Git's local absolute-path rules. The `localhost`
authority is case-insensitive.

Keep other file authorities and scheme spellings as distinct identities.
Don't strip the scheme. For example, `file://localhost/tmp/a.git` and the
relative path `localhost/tmp/a.git` name different repositories.

### Compare Against the Forge

Before auto-selecting a base or head remote, compare its fetch URL with the
repository API's authoritative HTTPS and SSH clone identities. Apply the same
check to an explicit hosted remote. Compare the complete hosted path. Host plus
`owner/name` alone can accept a deployment prefix or SSH user that names
another repository.

Only a true hostless path is a local-remote trust decision. Resolve relative
paths from the worktree root and follow symlinks on both sides of checkout.
Require any active hostless mapping to equal the canonical destination trusted
before checkout.

Stop for a split identity, hosted mismatch, changed local destination,
non-local file authority, or malformed hosted form.

An SSH remote may use a local `~/.ssh/config` `Host` alias whose label differs
from the forge host, such as `git@bnw.github.com:owner/name.git` mapping to
`HostName github.com`. The alias names the same endpoint, so resolve it before
refusing. Run `ssh -G` on the URL's user and host, since a per-user config can
expand a different host. Rewrite the URL to the resolved host and user and
compare that against the forge's clone identities. Accept only a resolved
default port; a non-default port is a different endpoint. Feed the rewrite to
the identity check alone. Keep the alias URL for fetch and push so its ssh
config still applies.

Fail closed when `ssh` is absent, when `ssh -G` errors or returns odd output,
or when an ssh-command override is set (`GIT_SSH_COMMAND`, `core.sshCommand`, or
`GIT_SSH`). Under an override the offline resolution need not name the endpoint
Git reaches. On an accepted head alias, pin the resolved `HostName`, `User`, and
`Port` on the head `ls-remote` and the lease-protected delete with command-scoped
`ssh -o` options. A config change after acceptance then can't reroute the
destructive push.

### Check Whether Auto-Delete Ran

Run
`git ls-remote --exit-code --heads -- <remote> refs/heads/<branch>`.

- Exit 2 proves absence.
- Exit 128 means transport or authentication failure and must stop.
- On exit 0, accept only a line whose ref column exactly equals
  `refs/heads/<branch>`. The pattern also matches a branch literally named
  `refs/heads/<branch>`.

If that suffix-matching sibling exists beside the real branch, stop. Git
suffix-matches push destinations, so both `--delete` and the `:ref` form fail
with "dst refspec matches more than one". This was verified on git 2.50. A
forge API delete is unsafe because it doesn't repeat the lease check.

### Recheck the Branch Before Deletion

- Require the surviving ref's OID to equal the verified merged head.
- Require the forge-reported head to match. Any mismatch means the branch
  moved or was reused and may contain unmerged work.
- Repeat the branch-consumer checks because the pre-merge answer can go stale.
- Refresh fork-network membership at the same boundary.
- Keep a fork's branch unconditionally because repository-local queries can't
  enumerate its network.
- Also keep a same-repository branch when the repository is a fork or a root
  with forks.
- Before merging, list open PRs in the recorded parent and source lineage
  whose head is this branch. Don't exclude matching PR numbers across
  repositories because another repository's PR can share this PR's number.

When every guard passes, delete atomically with
`git push --delete --force-with-lease='refs/heads/<branch>:<verified-oid>' -- <remote> refs/heads/<branch>`.
The lease makes a concurrent push fail the delete instead of losing new work.

## 7. Preserve the Local Branch and Prune

Keep the local branch and report `kept_manual`. Git has no portable deletion
that combines an expected-old OID with the checked-out-worktree guard.

- `git update-ref -d` checks the old OID, but it can delete a branch that
  another worktree just checked out. That leaves its symbolic `HEAD` dangling.
- `git branch -d` protects checked-out branches, but it can delete a ref moved
  backward after an exact-tip check.

Delete the local branch only as a separate, deliberate step. First verify its
tip and confirm that no worktree uses it.

Determine raw ref presence without dereferencing:

1. Run `git symbolic-ref -q <ref>`.
2. If it isn't symbolic, run `git show-ref --verify --quiet <ref>` for a direct
   ref.
3. Repeat the symbolic probe before reporting absence. A direct ref can become
   a dangling symbolic ref between reads.
4. Don't require the newer `git show-ref --exists`.
5. Recompute presence when reporting. A branch created during cleanup must
   also be reported `kept_manual`.

Prune only the named remote with `git fetch --prune -- <remote>`. A bare
`--prune` touches only the default remote. If pruning fails, report cleanup as
unknown or partial, never successful.
