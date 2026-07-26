# The guarded merge-and-cleanup sequence: prose specification

`self-merge.sh`, bundled alongside `SKILL.md`, is the **canonical
executable form** of this sequence; prefer it over re-deriving anything
here, because most of the hazards below were found by executing the
commands, not by reading them. This file is the specification the script
implements. Read it when the script cannot run and an equivalent
authenticated PR-host CLI can still perform every forge guard, or to
understand why a guard stopped. Without such a CLI, stop at the open PR
and hand the merge to the user. Evidence for every claim lives in the
work unit's decision note
(`devlog/2026-07-24-2311-self-merge-resync-guards.md`).

Two rules govern every step. **Bind, don't paste**: every value that
reaches a command (branch, remote, path, OID, title) is untrusted input;
capture it from the command that produces it into a variable and reference
it double-quoted, never retype or single-quote it (a contained single
quote breaks out, and a pasted name is evaluated by the shell: a ref named
with a command substitution executed when substituted into a snippet's
source). Pass `--` before positional remotes, paths, and bare refs so a
leading-hyphen value cannot read as an option; `git checkout` cannot be
terminated that way (`--` means pathspec there), so a leading-hyphen
branch name is a stop, not a quoting exercise. The PR number is the one
pass-as-is exception, and only after confirming it is digits only. **An
empty result is not a negative result**: a listing that failed (auth,
network, API) returns nothing, exactly like a listing that found nothing;
read exit codes, and treat unknown as "keep the branch, stop".

## 1. Merge

- Ask the branch-consumer questions **before** merging: where the
  repository auto-deletes head branches, the merge itself destroys a
  shared head before any cleanup guard can look. Check both directions,
  excluding the PR itself: open PRs whose **head** is this branch (one
  branch can back several PRs; for a fork head use the API's
  `head=<owner>:<branch>` filter, since `gh pr list --head` rejects that
  form) and open PRs whose **base** is this branch (stacked work). Any hit
  is a stop for the user, and the questions are re-asked immediately
  before the merge command runs: the answers go stale while checks and
  the self-review happen.
- Where the base branch carries a merge queue, identify the queue's
  integration method before enqueueing, from the branch-rules API
  (`gh api --paginate
"repos/<repo>/rules/branches/<url-encoded-branch>"`, the
  `merge_queue` rule's parameters): the queue, not the `--merge` flag,
  picks the merge shape, and a squash queue flattens the history
  irreversibly. Percent-encode the branch (a `#` or `?` in the name
  truncates the URL path and reads the wrong branch's rules). The CLI's
  `ruleset` commands have no JSON output and cannot report the method.
  Aggregate every page before treating an empty result as no queue.
  Multiple queue rules, any method other than a merge commit, or a
  payload shape you cannot identify is a stop. Re-identify the queue on
  the base the PR has at merge time: a stacked PR's auto-retarget can
  change the base branch, and with it which queue applies, between the
  pre-merge checks and the merge itself. A queue enqueue cannot carry the
  command's explicit subject and body through to the eventual commit, so
  a `MERGE` queue also requires repository merge-commit settings
  `PR_TITLE` and `BLANK`; refresh those settings at the final pre-enqueue
  boundary or stop.
- Read the base repository's `fork`, `forks_count`, and
  `delete_branch_on_merge` fields from the forge. When the repository is
  a fork or a root with forks, the same-repository head lives in a fork
  network whose consumers cannot be enumerated. If auto-delete is
  enabled, stop before a direct merge or queue enqueue: the branch can
  also head PRs elsewhere in the network, and the forge would delete it
  before cleanup reaches the keep-fork-network path.
- Merge pinned to the reviewed head:
  `gh pr merge <n> --repo <repo> --merge --match-head-commit <verified-oid>`,
  where the verified OID is the local branch tip this session pushed
  (a forge-reported head can move with a third party's push; a missing
  local branch is therefore a stop, not a fallback to the forge's value).
  Pass a title-only message explicitly, reading the title from the forge
  and refusing an empty or `null` read, or a failed lookup writes
  `null (#<n>)` permanently into history. Read the title before the final
  queue, consumer, and auto-delete guards; refresh repository settings
  after the consumer queries, then make no further forge read before the
  merge command, minimizing the window where auto-delete can change after
  it was checked.
- A zero exit proves enqueueing, not merging. Only the forge reporting
  state `MERGED` with a non-null `mergedAt` releases the cleanup; deleting
  a branch while the PR waits in a queue can cancel the merge and take the
  branch's last copies with it. Cap each retry sleep by the time remaining
  before the configured deadline, so a long polling interval cannot extend
  that deadline.

## 2. Preflight the workspace

In the checkout the cleanup will rewrite, all of these hold or the
sequence stops:

- `git status -uall --porcelain` is empty. The `-uall` is load-bearing:
  `status.showUntrackedFiles=no` empties a plain `--porcelain`, so a guard
  that inherits repository configuration can be switched off by the
  repository it protects.
- No git operation is in progress. `--porcelain` reports none of them, so
  test the per-worktree paths returned by `git rev-parse --git-path` for
  `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `BISECT_START`,
  `rebase-merge`, and `rebase-apply` (including a symlink at one of those
  paths); `rebase-apply` also covers an interrupted `git am`. Do not test
  the names as revisions: an ordinary local branch named `MERGE_HEAD`
  resolves through `refs/heads/` and is not a paused merge.
- No other worktree holds the base branch (run the sequence from that
  worktree instead), and the head branch does not resolve to the same ref
  as the base or default branch. Probe the checkout filesystem rather than
  trusting mutable `core.ignorecase`: when the filesystem is case-insensitive,
  `refs/heads/Main` and `refs/heads/main` are one ref file even if that setting
  is false, and the case-spelled delete removes the base branch that git
  refuses to delete under its own name.
  Probe candidate names component by component in temporary, invalid-ref
  children of the corresponding existing loose-head directories, because
  their inherited filesystem semantics may also fold Unicode case or composed
  and decomposed forms that an ASCII transform cannot detect. Directory-scoped
  casefolding makes the existing branch-prefix directory, not only
  `refs/heads`, load-bearing.

## 3. Preflight linked worktrees

- Find the head branch's worktree from `git worktree list --porcelain -z`,
  which emits NUL-terminated **fields**: strip the `worktree` keyword,
  pair each path with the `branch` field that follows, and verify the path
  is the record whose branch is the PR's head (bound from the forge, never
  inferred from `HEAD`). Allow zero or one matching record; zero means no
  worktree currently checks out that branch, while several are ambiguous and
  must stop. Apply the same cardinality guard to the base branch before
  resync, and require its unique match, when present, to be the current
  checkout. Never route a path through a command substitution (it strips a
  trailing newline) or a line-oriented parse (a spaced or newline-bearing path
  mis-targets a sibling worktree), and do not substitute macOS `awk` with a
  NUL record separator (it silently returns nothing). A NUL-capable reader
  (`read -d ''` in bash or zsh, or python3) or a stop are the options.
- Reject a symbolic local base before remote resolution: checkout follows its
  target, so discovering the mismatch afterward is already too late. Validate
  any local head ref before relying on the path too: a symbolic ref is a stop,
  and an ordinary ref must still equal the pinned merged head. Then repeat the
  head-worktree scan immediately before remote resolution and any mutation,
  closing layout changes during the local-ref checks. Use this fresh unique
  match for the inventory and stop below.
- When the unique head match is a separate worktree, probe its own operation
  state before handing off its removal:
  operation state is per-worktree, so the cleanup checkout's preflight says
  nothing about the other worktree, and a merge paused there with no tree
  delta leaves every file inventory empty while manual removal would delete
  the worktree and its paused state with exit 0. Run the same probes as the
  preflight, against the worktree.
- Inventory the other worktree from outside it: removal deletes the directory
  outright, an ignored file does not trigger git's own untracked-file refusal,
  and a tracked file carrying `assume-unchanged` or `skip-worktree`
  (`git ls-files -v`, lowercase letters or `S`) is invisible to every
  porcelain form while removal destroys it with exit 0. Anything found is a
  stop; never remove the worktree the shell stands in (git deletes the current
  worktree without complaint).
- A separate linked head worktree is a stop **before any remote or local
  branch mutation**. Inventory its operation and file state so hidden work
  gets a specific diagnosis, but leave even a clean worktree intact. Git
  exposes no portable operation that atomically verifies a worktree's
  detached `HEAD`, inventories its files, removes it, verifies the branch
  OID, and enforces the checked-out-worktree guard: a concurrent reset can
  otherwise move a clean detached `HEAD` after the check, and removal drops
  its only ref and reflog. Stop concurrent users, remove that worktree as a
  separate deliberate step, then rerun cleanup. This does not stop cleanup
  when it starts inside the clean head checkout itself: the later base-branch
  switch makes that same worktree cease to hold the head. No head match also
  proceeds normally.

## 4. Delete the remote head branch

- The remote consulted and the remote written must be the same
  repository: git prefers configured `pushurl` entries for pushes while
  `ls-remote` reads the fetch URL, and a push sends to **every**
  configured push URL while a plain push-URL query returns only the
  first. Require **exactly one** effective push destination and require it
  to carry the fetch URL's identity: two different destinations broadcast
  the delete, while two identical destinations delete successfully once
  and then fail the second lease against stale information. Query the full
  set (`git remote get-url --push --all`) and reject blank records before
  mutation; a valid URL followed by an empty one still makes Git delete at
  the valid destination before failing. The returned URL is already
  `insteadOf`/`pushInsteadOf`-expanded (verified), so config rewrites are
  covered by the same comparison, captured without stripping trailing
  newlines (a newline-ending path and its newline-less sibling are two
  repositories); a remote whose raw configured URLs contain a newline
  cannot be compared through any line-based listing at all, and is a
  stop. Compare hosted URLs by transport, lowercased authority, and their
  complete, case-preserved repository path: HTTP(S), git, SSH URL, and SCP
  transports are distinct endpoints even with the same host and path.
  Strip credential userinfo at its last `@` for non-SSH schemes (a colon
  in `user:pass` must not truncate the host), but retain the SSH/SCP
  username because different remote users can resolve the same relative
  path to different repositories. Treat userless SCP `host:path` forms as
  hosted, parse bracketed IPv6 SCP hosts through their closing bracket,
  and keep the port (two ports are two endpoints; differing spellings of
  a default port fail closed).
  Deployment-specific prefixes, path case, and a terminal `.git` remain
  part of this identity, since
  `https://host/a/owner/name.git` and
  `https://host/b/owner/name.git` can name different repositories, as can
  paths that differ only by case or `.git`; derive and normalize the
  forge's `owner/name` tail separately when auto-resolving a remote.
  A URL with no host is a local path and compares by its full path, since
  truncating to a tail equates `/a/owner/name` with
  `/b/owner/name` and stripping `.git` equates the sibling directories
  `repo` and `repo.git`. Normalize the exact lowercase-scheme forms
  `file:///path` and `file://localhost/path` to Git's local absolute-path
  semantics (the `localhost` authority is case-insensitive); keep other
  file authorities and scheme spellings under a distinct identity rather
  than stripping the scheme, since `file://localhost/tmp/a.git` and the
  relative path `localhost/tmp/a.git` address different repositories. A
  split identity is a stop. Before auto-selecting a base or head remote,
  or accepting an explicit hosted one, compare its fetch URL against the
  repository API's authoritative HTTPS and SSH clone endpoint identities,
  including the complete hosted path; matching only host plus
  `owner/name` can accept a deployment prefix or SSH user that names
  another repository. Only a true hostless path is an explicit
  local-remote trust decision. A hosted mismatch, non-local file
  authority, or malformed hosted form is a stop.
- Check whether auto-delete already ran:
  `git ls-remote --exit-code --heads -- <remote> refs/heads/<branch>`.
  Exit 2 is a genuine absence; exit 128 is a transport or auth failure and
  must stop the sequence (an unreachable remote otherwise reads as
  auto-delete having done its job). On exit 0, accept only a line whose
  ref column equals `refs/heads/<branch>` full-string: the pattern also
  matches a branch literally named `refs/heads/<branch>`.
- If such a suffix-matching sibling exists alongside the real branch, the
  delete itself is inexpressible: git suffix-matches push destinations, so
  both `--delete` and the `:ref` form refuse with "dst refspec matches
  more than one" (verified on git 2.50), and a forge-API delete re-runs no
  lease check. Stop and surface it.
- The surviving ref's OID must equal the verified head that merged, and
  the forge's reported head must agree; any disagreement means the branch
  moved or was reused after the merge and may carry unmerged work.
- Re-ask the consumer questions at delete time (the pre-merge answer can
  go stale), and refresh fork-network membership at the same boundary.
  Keep a fork's branch unconditionally (per-repository queries cannot
  enumerate a fork network), and keep a same-repository branch too when
  the repository is a fork or a root with forks, since its branches live
  in the same unenumerable network; before merging, additionally list
  open PRs in the recorded lineage (parent and source) whose head is this
  branch, with no cross-repository number exclusion, because another
  repository's PR can share this PR's number without being it. Then
  delete atomically:
  `git push --delete --force-with-lease='refs/heads/<branch>:<verified-oid>' -- <remote> refs/heads/<branch>`,
  so a push landing between check and delete fails the delete instead of
  losing the new work.

## 5. Land on the base branch

- After the pre-mutation symbolic-ref rejection, test for a direct local base
  branch with `git show-ref --verify --quiet refs/heads/<base>`;
  `rev-parse --verify` is satisfied by a same-named tag, and a bare checkout
  then detaches `HEAD` at the tag while the real base stays stale.
- Existing local branch: `git checkout --no-overwrite-ignore <base>`.
  Missing: fetch `refs/heads/<base>` into the remote-tracking ref first
  (the start-point can be absent in a fresh, single-branch, or sparse
  clone), then `git checkout --no-overwrite-ignore -b` from it. Both
  switches refuse to overwrite an ignored file the base tracks; that
  refusal is a stop, and a plain checkout clobbers the file silently.
- Confirm `git symbolic-ref -q HEAD` reports `refs/heads/<base>` after the
  switch, whichever path ran.

## 6. Resync

Fetch the base explicitly, then
`git merge --ff-only --no-overwrite-ignore refs/remotes/<remote>/<base>`.
Not `git pull`: its merge step updates ignored files by default, it
rejects `--no-overwrite-ignore`, and a bare pull follows the configured
upstream, which in a fork clone can be the fork's stale copy. A refused
fast-forward (divergence, or an ignored file the base started tracking) is
a stop; never resolve it with reset or force.

## 7. Preserve the local branch and prune

- Keep the local branch and report `kept_manual`. Git exposes no portable
  deletion that combines an expected-old OID with the
  checked-out-worktree guard: `git update-ref -d` supplies the former but
  can delete a branch another worktree just checked out and leave its
  symbolic `HEAD` dangling; `git branch -d` supplies the latter but can
  delete a backward-repointed ref after an exact-tip check. Delete the
  local branch as a separate deliberate step after verifying its tip and
  that no worktree uses it. Determine raw ref presence without
  dereferencing so a dangling symbolic ref cannot masquerade as absence:
  ask `git symbolic-ref -q <ref>` first, then
  `git show-ref --verify --quiet <ref>` for an ordinary direct ref, then
  repeat the symbolic probe before declaring absence so a direct ref
  replaced between reads by a dangling symref remains present. Do not
  require the newer `git show-ref --exists`. Recompute presence at
  reporting time so a branch created during cleanup is also reported
  `kept_manual`.
- Prune with the remote named (`git fetch --prune -- <remote>`); a bare
  `--prune` prunes only the default remote. A prune failure leaves cleanup
  incomplete and must be reported as unknown or partial, never as a
  successful cleanup.
