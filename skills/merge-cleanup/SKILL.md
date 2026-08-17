---
name: merge-cleanup
description: >-
  Run post-merge cleanup when a user reports "merged", "PR merged, please
  clean up", "PR #N is merged", "just merged it, tidy up", or "the PR landed".
  Safely tidies branches and refs, verifies issue closure, performs documented
  project reconciliation, and stops review watches. Not for merging a PR or
  cleaning up one that remains open.
---

# Merge Cleanup

## Identify the merged PR and branch

Every guard below is keyed to the PR and branch resolved here, so resolve
them before anything else runs.

### Resolve the PR and the branch

- **Work out which PR merged and which local/remote branch carried it, from
  conversation context first** (the PR this session opened or handed off),
  otherwise from the PR host CLI.
- **Pin every PR-record lookup to the repository the PR lives in** (its base
  repository, resolved from the PR URL or session context) and pass it
  explicitly, because a bare `gh pr view <n>` resolves the number against the
  CLI's default repository, which in a fork clone can be the fork or unset:
  that silently returns a different PR's `headRefName`/`headRefOid` and aims
  the deletion guards at the wrong branch. For example
  `gh pr view <n> --repo '<base-repo>' --json state,mergedAt,headRefName,headRefOid,baseRefName,isCrossRepository,headRepository,headRepositoryOwner`.
- **Collect up front, in that same call**, the `headRefOid` the deletion
  guards below compare against and the head-repository fields that say which
  repository, and so which remote, owns the PR head.
- **The git-only alternative is
  `git branch --merged 'refs/remotes/<base-remote>/<base-branch>'`**, after
  fetching the base remote (the remote roles are resolved below), querying
  the branch the PR merged into rather than the default branch.
- **Treat that output as candidates to confirm, not as the answer**: a
  squash- or rebase-merged branch is omitted from it entirely
  (`references/hazards.md` §merged-not-ancestor).
- **Use it only when the just-merged branch is plainly present.** If the
  merge was squash or rebase, or the branch is not otherwise known from
  context or forge metadata, or the output is ambiguous, ask the user for the
  branch rather than picking from what remains, since filtering out the base
  and default can leave an older, stale merged branch as the only candidate
  and aim cleanup at the wrong branch.
- **When it does apply, ignore the default and the merged PR's base branch in
  the output, but keep the current branch as a candidate**, since the
  workspace often still sits on the just-merged branch and step 2 switches
  away before anything is deleted; the ref must name the base remote's copy,
  since a fork's copy of that branch is usually stale.
- **If the PR or branch cannot be determined unambiguously, ask the user
  rather than guessing.** Deleting the wrong branch is the one failure this
  skill must never risk.

### Hard rules on the resolved name

- **If `<branch>` resolves to the default branch or to the merged PR's base
  branch, abort**; this skill never deletes the branch it resyncs.
- **Fully qualify every ref a guard below resolves or compares, the base side
  included**: the branch as `refs/heads/<branch>`, a remote-tracking base as
  `refs/remotes/<base-remote>/<base-branch>`. A bare name tail-matches other
  refs in `git ls-remote`, and elsewhere a stray or malicious tag named
  `<branch>` or `<base-remote>/<base-branch>` can satisfy a guard the real
  ref would fail, just before a deletion (`references/hazards.md`
  §tag-shadow). A bare fetch or pull refspec is exposed the same way, so
  step 3 qualifies its ref too.
- **Exception: `git checkout` cannot be fully qualified**, and its bare form
  is safe only when a local branch already exists (`references/hazards.md`
  §checkout-detach), so step 2 ensures the local base branch exists (creating
  it from the remote-tracking ref) rather than trusting the bare name.
- **Treat every name the PR supplies** (the branch, the base branch, the head
  repository) **as untrusted shell input**: a valid ref name can contain `$`,
  `;`, or parentheses, so substitute each one single-quoted, as the command
  examples below show, and stop on a name single quotes cannot carry
  literally (one containing a single quote itself). The self-merge skill binds
  such a value into a shell variable instead of stopping, because it ships a
  script that has to run on whatever it resolves; these commands are templates
  a reader substitutes into, so stopping costs one rare cleanup rather than a
  capture step in every example.
- **Quoting stops at the shell, and git parses its own arguments after that**,
  so a name beginning with a hyphen reads there as an option. `git branch`
  refuses to create such a name, but `git update-ref` and a forge both can, so
  the shape reaches this skill. It stays expressible everywhere the sequence
  needs it, in specific forms only: a qualified ref carries it, `--` carries it
  past every command taking a positional remote or bare ref, and step 2 lands
  on such a base branch with `git switch` rather than `git checkout`
  (`references/hazards.md` §leading-hyphen-args). A leading hyphen is therefore
  not a stop by itself, and nothing below declines a cleanup git can express.
- **A base branch named `-`, `@`, or `HEAD` is the exception, and the plan
  script stops on it.** Those three are valid branch names that git resolves as
  revision shorthand before it reaches `refs/heads`, so no terminator helps and
  no spelling lands on them: two of the three switch somewhere else at exit 0
  (`references/hazards.md` §leading-hyphen-args). That is a refusal of what git
  cannot express, not of an awkward name; every other shape tested, `--` and
  `-h` and `--all` among them, plans normally.
- **Pass `--` before every positional remote and bare ref**, as the commands
  below do: `--` is what keeps a hyphen-leading name from reading as an option
  (`references/hazards.md` §leading-hyphen-args). The PR number is the
  exception the examples pass bare, to `gh pr view`, so confirm it is digits
  only before substituting it.

### Resolve the remote roles

- **Resolve the remotes before acting.** In a fork workflow
  (`isCrossRepository` true) the remote hosting the PR head, the one pointing
  at the head repository identified above, is not the remote whose base
  branch moved when the PR merged.
- **Use the head remote for the remote-branch existence check and deletion,
  and the base remote for merge verification and resync**; the commands below
  name `<head-remote>` and `<base-remote>` for those two roles explicitly,
  never a bare `origin`, since in a fork they are different remotes and the
  head role may have no configured remote at all.
- **In a single-remote clone the roles coincide only when that remote hosts
  the PR head** (a same-repository PR).
- **For a fork PR checked out without a fork remote** (for example via a
  forge CLI), no configured remote plays the head role, so run the
  head-remote steps against the fork directly (by URL, or through the forge
  CLI) rather than letting the base remote stand in: an existence check
  against the base repository reads as "already deleted" while the fork's
  branch survives, and a same-named base-repository branch is not the PR
  head.

## Verify the merge before deleting anything

- **Confirm the PR is actually merged, not merely closed, before any
  deletion**: a closed-unmerged PR's branch may hold the only copy of the
  work.
- **Check with the PR host CLI** (`mergedAt` non-null, state `MERGED`) **or
  by confirming the branch tip is reachable from the PR's base branch**,
  usually the default branch
  (`git merge-base --is-ancestor 'refs/heads/<branch>' 'refs/remotes/<base-remote>/<base-branch>'`,
  after fetching the base remote so the ref is current).
- **In a squash- or rebase-merge repo, only the forge's `MERGED` state counts
  as verification**, since there the branch tip never becomes an ancestor of
  the base (`references/hazards.md` §merged-not-ancestor).
- **When the tools can check, never proceed on the user's word alone.**
- **Step 1's guards match and lease the remote branch against a verified head
  OID**: with the CLI that is `headRefOid`; on the git-only ancestry path no
  CLI supplied it, so use the local branch tip you just confirmed merged
  (`git rev-parse 'refs/heads/<branch>'`), which on a merge-commit or
  fast-forward merge is the commit that merged. (The squash/rebase path has
  no git-only verification, so it always carries the CLI and its
  `headRefOid`, and a git-only run there stops at the verification
  requirement above rather than reaching step 1.)
- **If no tool can confirm the merge, do not delete the remote branch**: say
  so, and hand the user the exact deletion command to run once the forge
  shows the PR as merged (confirming a branch's name is not confirming that
  it merged).

## Git cleanup sequence

Run the sequence in order; each guard exists because the step after it is
destructive or history-changing.

**Before starting, check for linked worktrees** with `git worktree list`.
This project's own convention runs each work unit in a dedicated worktree,
so the base branch is often already checked out in the primary worktree
while cleanup runs in the feature branch's worktree. That layout breaks the
switch-and-resync steps below: the checkout, the fetch or merge into the
base branch, and the local branch delete all refuse
(`references/hazards.md` §worktree-refusals). So when `git worktree list`
shows the base branch, or `<branch>` itself, held by another worktree, do
not run the destructive sequence blindly here:

- **Relocate the sequence across the worktrees**: perform the resync
  (steps 2-3) in the worktree that already holds the base branch, **and**
  `git worktree remove` the feature branch's worktree before deleting that
  branch (step 4). Remove it from wherever the resync left you, never from
  inside the worktree being removed: git has no self-target check, so a
  worktree clean enough to remove is unlinked out from under its own session
  at exit 0, and a `-C` aimed elsewhere does not spare the session's own
  directory. Every later command then runs from a path that no longer exists
  (`references/hazards.md` §worktree-refusals).
- **Inventory that worktree before removing it, with this skill's
  `worktree-inventory.sh`, and treat any non-zero exit as a stop.** Removal
  deletes the directory outright, and git's own refusal covers less than it
  looks: an ignored file does not trigger it, and a tracked file flagged
  `assume-unchanged` or `skip-worktree` is invisible to every porcelain form
  while removal destroys its edit, or its deletion, with exit 0
  (`references/hazards.md` §worktree-remove-destroys). Run the script by
  path, from outside the worktree it names
  (`<skill-dir>/worktree-inventory.sh '<worktree-path>'`; `--help`, or `-h`,
  prints its contract). Exit 0 and `OK inventory` mean nothing is hidden and
  the removal is yours to make; `STOP <guard>` (exit 2) and `LOOKUP_FAILED`
  (exit 4) both mean do not remove it, and the line it printed is what to
  surface to the user; a path beginning with a hyphen is a usage error there
  (exit 64), since the script refuses an option-shaped path rather than passing
  it to git. That refusal costs nothing real: `git worktree list` reports
  absolute paths, so such an argument is a mistyped invocation rather than a
  worktree you would lose access to. Terminate the removal's own path anyway
  (`git worktree remove -- '<worktree-path>'`).
- **The inventory ships as a script because its rules are a program, not a
  checklist.** They are easy to state and easy to get wrong: the tag column
  decides (`H` is an ordinary cached file, so an unfiltered reading stops on
  every worktree), presence decides for most rows but not all (a sparse
  checkout marks each excluded path `S` and leaves it absent, while an absent
  `assume-unchanged` row is a hidden deletion), and every path has to be read
  NUL-terminated and resolved against the worktree rather than your own
  directory. Each of those is a reproduced hazard, listed in
  `references/hazards.md` §worktree-remove-destroys. **Where the script
  cannot run** (no bash, or a platform that will not execute it), stop and
  hand the worktree to the user rather than reconstructing the check by hand.
- **Take the worktree path itself from `git worktree list --porcelain -z`,
  read NUL-aware**, not from the human-readable listing: a command
  substitution drops NUL bytes and strips a trailing newline, and a
  line-oriented parse mis-pairs a path that contains one, which points the
  inventory and then the removal at a sibling worktree. `read -r -d ''` does
  this in bash and zsh but is not POSIX (dash rejects it); where no
  NUL-capable reader is available (that, or a tool such as python3), stop
  rather than removing on a parse you cannot trust.
- **If that cannot be arranged, stop and surface the worktree layout with the
  remaining steps rather than deleting the remote branch (step 1)** into a
  sequence that stalls half-done.

**Also before step 1, plan step 2's landing, with this skill's
`base-landing-plan.sh`, and treat any non-zero exit as a stop.** Landing on the
base branch chooses between two switching commands over three axes (the base
name's shape, whether a local branch exists, and whether that branch carries a
complete upstream), behind two guards: a clean tree, and a git that has
`git switch` where the name needs it. The script reads all of that and prints
the plan step 2 runs.

Run it by path, from the checkout the resync will run in,
which under the relocate rule above is the worktree already holding the base
branch (`<skill-dir>/base-landing-plan.sh '<base-remote>' '<base-branch>'`;
`--help`, or `-h`, prints its contract). Exit 0 and `OK landing` carry the plan
into step 2; `STOP <guard>` (exit 2) and `LOOKUP_FAILED` (exit 4) both mean do
not proceed, and the line it printed on stdout is what to surface to the user.
A usage error (exit 64) and an environment failure (exit 69) report on stderr
instead; 69 is the "cannot run" case below. Unlike the inventory above, an
option-shaped argument is not a usage error here: a base branch beginning with
a hyphen is the case this script exists for.

**Every config-derived field in the plan describes the branch that was checked
out when it ran.** Git evaluates an `includeIf "onbranch:…"` section against the
currently checked-out branch, so a repository that configures a remote URL or
tracking keys that way gives one answer before the landing and another after
(`references/hazards.md` §leading-hyphen-args). The tracking write is taken from
the post-landing run for that reason. The remote check cannot be: step 1 needs
it and step 1 runs first, so in such a repository the sequence can still strand
after the deletion. Treat a `LOOKUP_FAILED remote` from the post-landing run as
that case, and surface it rather than retrying.

**It runs here because one of its guards cannot be recovered from later.**
`git switch` is the only command the sequence needs that a still-supported git
may lack (it arrived in 2.23), and step 2 needs it for a base branch whose name
begins with a hyphen; discovering its absence after step 1 leaves the remote
branch gone and the workspace still on the merged branch. The script switches
nothing, creates nothing, fetches nothing, and writes no configuration, so
running it this early costs nothing. A `STOP dirty` here is an early exit
rather than a false alarm: the tree has to be clean at step 2 in any case, and
stopping now leaves the remote branch intact. Step 2 still runs the script
again, because the tree can change in between and the plan it executes has to
describe the tree it is about to switch.

**The landing ships as a script because its rules are a program, not a
checklist.** They are easy to state and easy to get wrong: `git checkout`
cannot spell an option-shaped name and neither creating form will create one,
so such a name has to arrive by fetching it straight into `refs/heads`
(`references/hazards.md` §leading-hyphen-args); a same-named tag turns a bare
checkout into a detached `HEAD` (`references/hazards.md` §checkout-detach); a
status read inherits repository configuration, so the repository can switch
that guard off from inside (`references/hazards.md` §status-config); and half a
tracking pair behaves exactly like none. Each of those is a reproduced hazard,
checked by the script rather than left as a clause a reader has to apply.

**Where the script cannot run** (no bash, or a platform that will not execute
it; exit 69 is that case), stop and hand step 2 to the user **rather than
deleting the remote branch (step 1)** and reconstructing the decision by hand.
The landing no longer exists in prose to fall back on, so a sequence that
starts anyway strands the cleanup exactly where the placement above is meant
to prevent.

Proceed straight into step 1 only when neither the base branch nor
`<branch>` is checked out in another worktree.

1. **Delete the remote branch only if auto-delete didn't.** Check whether
   it still exists and where it points, with
   `git ls-remote --heads -- '<head-remote>' 'refs/heads/<branch>'`, comparing
   each line's ref column (the text after the tab) against
   `refs/heads/<branch>` as a whole string and accepting only a single exact
   match; many repos auto-delete on merge. Qualifying the pattern does not
   make the match exact, and any further line it returns is a stop rather
   than noise to filter out: a ref that merely suffix-matches (one literally
   named `refs/heads/refs/heads/<branch>`) makes the delete inexpressible,
   since both `--delete` and the `:ref` form then refuse with "dst refspec
   matches more than one" (`references/hazards.md`
   §push-refspec-ambiguity). Surface that shape rather than reaching for a
   forge-API ref delete, which re-runs neither the OID check nor the lease
   below.
   If the ref exists, its OID
   must match the verified head OID from the verify section (`headRefOid`
   with a CLI, else the local verified branch tip): deleting a remote
   ref removes whatever it points at now, and a mismatch means the branch
   moved or was reused after the merge and may carry unmerged work, so
   stop and surface it instead of deleting. Also check for open PRs that
   target this branch as their base (for example
   `gh pr list --repo '<head-repo>' --base '<branch>' --state open`),
   pinning `--repo` to the repository that owns `<branch>` (the head
   repository collected at identify time): a bare `gh pr list` resolves
   against the CLI's default repo, which in a fork clone can be the fork or
   unset, and stacked PRs live where their base branch does, so an unpinned
   or wrong-repo check comes back falsely empty and the delete below
   orphans the PRs that stack on this branch. Retarget any to the
   merged PR's own base first, and verify the retarget landed rather than
   assuming it (GitHub retargets stacked PRs automatically when their base
   merges, but only within the same repository). When the head and base
   repositories differ this is a real hole: a PR stacked on `<branch>` in
   the fork has the fork as its base repository, and neither the automatic
   retarget nor `gh pr edit --base` can move a PR across repositories (the
   new base must be a branch in the PR's own repository), so a retarget
   only renames its base to the fork's copy of the merged base branch, not
   the upstream base that received the merge, silently aiming follow-up
   work at the wrong repo and diff. Where the retarget cannot reach the
   merged PR's base repository, surface those stacked PRs for the user to
   recreate against the correct base and delete only then, so the deletion
   never proceeds on the assumption the stack was rehomed.
   Without a PR host CLI, ask the user whether anything stacks on this
   branch before deleting it remotely. Then, with the merge verified and
   the OID matched, delete it with the guard made atomic:
   `git push --delete --force-with-lease='refs/heads/<branch>:<verified-head-oid>' -- '<head-remote>' 'refs/heads/<branch>'`.
   The lease pins the remote ref to the OID just verified, so a push
   that lands between the check and the delete fails the delete instead
   of losing the new work; a plain `--delete`, or a forge-CLI ref
   delete, re-runs no check and would re-open that race, so prefer the
   lease-protected push wherever git can reach the head remote.
2. **Land on the branch the PR merged into** (its base, usually the default
   branch); that is the branch that moved, and the later steps validate
   against the current `HEAD`. Treat every plan run below as a snapshot, and
   keep one exclusivity window from the first run through step 3's final fetch
   and fast-forward: do not let another Git process mutate refs in this
   repository. Do not release that window after the switch or the second plan.
   No read-only preflight can reserve a ref name across later commands, so a
   concurrent fetch, branch operation, or other ref writer can invalidate an
   `OK` after the destructive step has run. If exclusive control of the
   repository is unavailable for that whole interval, stop and surface the
   constraint rather than relying on the snapshot. Re-run
   `base-landing-plan.sh` (above) here,
   then run what it prints: it is read-only, and the plan taken before step 1
   describes the tree as it was before a push rather than the tree about to be
   switched. A `STOP dirty` means surface the uncommitted work rather than
   switching over it or stashing silently; the user decides what happens to
   their changes.
   Fetch first, running every refspec the plan's `fetch` lists in one command
   (`git fetch -- '<base-remote>' <refspec> …`). Skip the command entirely
   when the list is empty, which it is unless the landing has to create the
   branch; a bare `git fetch` would follow the clone's configured refspec
   instead of the base, the shape this sequence avoids everywhere else. Where
   the list is not empty, it is what makes the start-point exist: a clone that
   verified the merge through the forge
   `MERGED` state need never have fetched the base, so in a fresh,
   single-branch, or sparse clone the ref the create needs can be absent, and
   the create then aborts after step 1 already deleted the remote branch,
   leaving cleanup half-done.
   Then land with the command the plan's `verb` and `create` name. With
   `checkout` and `create` false,
   `git checkout --no-overwrite-ignore '<base-branch>'`; with `checkout` and
   `create` true,
   `git checkout --no-overwrite-ignore -b '<base-branch>' 'refs/remotes/<base-remote>/<base-branch>'`;
   with `switch`,
   `git switch --no-overwrite-ignore -- '<base-branch>'` either way: where
   `create` is true the fetch above put that name in place, and where it is
   false the branch was already there. Every form passes
   `--no-overwrite-ignore`, which aborts rather than overwriting an ignored
   file the base branch tracks (`references/hazards.md`
   §ignored-file-overwrite); treat that abort as a stop-and-surface, like a
   dirty tree.
   **Confirm `HEAD` is on the branch, not detached**, before resyncing, and do
   it whatever the plan said: step 3 would otherwise fast-forward a detached
   `HEAD` while step 4 validates and deletes against it, leaving the real base
   stale. None of the three commands above can detach (a bare checkout prefers
   an existing local branch, the creating form names its start-point, and
   `git switch` refuses a tag outright), so the plan's `tag_shadow` is context
   for reading a failure, not a branch in the instructions.
   Finally, **run the plan once more, now that the base branch is checked
   out**, and take `tracking` from that run rather than from the one before the
   switch. Configuration is not fixed across a checkout: an
   `includeIf "onbranch:…"` section applies only while its branch is the
   checked-out one, so tracking keys supplied that way are visible before the
   landing and gone after it, and a plan that read them earlier would say `ok`
   over a branch left with no upstream at all. This is the same reason step 2
   re-runs the plan rather than trusting the pre-step-1 one: read the state at
   the moment the decision turns on it.
   Where that last run says `write`, write both keys:
   `git config 'branch.<base-branch>.remote' '<base-remote>'` and
   `git config 'branch.<base-branch>.merge' 'refs/heads/<base-branch>'`. An
   untracked base branch is not merely unconfigured: a later plain `git pull`
   there follows the clone's configured refspec instead of this branch, and
   fast-forwards the branch onto whatever that fetched, silently and with exit
   0 (`references/hazards.md` §leading-hyphen-args). Where it says `ok`, leave
   the configuration alone even when it names something else; that is the
   user's, not a gap this skill should overwrite.
3. **Resync** by fetching the base, then fast-forwarding into it:
   `git fetch -- '<base-remote>' 'refs/heads/<base-branch>:refs/remotes/<base-remote>/<base-branch>'`
   then
   `git merge --ff-only --no-overwrite-ignore 'refs/remotes/<base-remote>/<base-branch>'`.
   A plain `git pull --ff-only` shares the checkout's ignored-file hole: its
   merge step updates ignored files by default, so a fast-forward whose base
   starts tracking a path the workspace holds as an ignored file overwrites
   it silently, and `git pull` itself rejects `--no-overwrite-ignore`
   (`references/hazards.md` §ignored-file-overwrite). The pull hazards still
   drive the rest of the shape: name the remote and qualify the source ref,
   because a bare `git pull` uses the branch's configured upstream, which in
   a fork clone can be the fork's stale copy rather than the repository that
   moved, and a bare `<base-branch>` refspec can fetch a same-named tag
   instead of the branch, leaving the base unmoved just before step 4 deletes
   against it. If the fast-forward refuses (divergence) or the merge aborts
   on an ignored-file conflict, report it and stop; never "fix" a diverged
   branch with reset or force, or clobber the ignored file, during cleanup.
4. **Delete the local branch, running the merge check yourself first**:
   `-d`'s own refusal is not the guard this step needs, because git checks
   the branch against its _upstream_ when one is set: it would delete with a
   mere warning whether or not the resynced base has the work
   (`references/hazards.md` §branch-d-upstream). So check
   first: if `git merge-base --is-ancestor 'refs/heads/<branch>' HEAD`
   holds, delete with `git branch -d -- '<branch>'`, treating a refusal as a
   signal to re-verify, not a prompt to escalate. If the ancestry check
   fails for a PR the forge reports `MERGED` (squash- and rebase-merge
   repos guarantee this, since the branch tip never becomes an ancestor:
   `references/hazards.md` §merged-not-ancestor), the forced form
   `git branch -D -- '<branch>'` is correct only after confirming the
   tip (`git rev-parse 'refs/heads/<branch>'`) matches the PR's head
   commit (`headRefOid`); never on the user's word alone. It carries the same
   terminator for the same reason as `-d` above, since it takes the branch
   name the same way. If neither
   check passes, stop and surface it.
5. **Prune stale tracking refs** with `git fetch --prune -- '<head-remote>'`,
   naming the head remote (a bare `git fetch --prune` prunes only the
   default remote, leaving a fork head remote's stale refs behind); prune
   the base remote too when it differs from the head remote.

## Issue-close verification

Merging is supposed to close the issues the PR body referenced with close
keywords ("Closes #N"), but the mechanism fails silently for cross-repo
references, merges to a non-default branch, and keyword typos.

- **List the linked closing references** with a PR host CLI, for example
  `gh pr view <n> --repo '<base-repo>' --json closingIssuesReferences,body`,
  the same base-repository pin as the identify step.
- **Request `body` in that same call.** The silent-failure cases (cross-repo
  references, a non-default base, keyword typos) are exactly when
  `closingIssuesReferences` comes back empty, leaving the merged PR body as
  the only text left to scan for the close keywords the forge did not parse.
- **Check each issue's state separately.** `closingIssuesReferences` returns
  each issue's identity (number, repository, url) but not its state, so look
  up each linked or body-scanned issue
  (`gh issue view '<n>' --repo '<issue-repo>' --json state`), pinning the
  repository the reference names, since a cross-repo issue lives outside the
  base repository.
- **Surface any still open for the user to close**; do not close them
  yourself unless asked, since whether an issue is truly resolved is the
  human's call.
- **Plain "Refs #N" mentions are intentionally non-closing**; don't flag
  them.
- **Without a PR host CLI**, say the check could not run instead of skipping
  it silently.

## Project post-merge obligations

After issue-close verification, and only when merge verification passed,
inspect the authoritative project instructions that govern the repository for
exactly one fixed-field `Post-merge obligations` record whose fields each
appear exactly once. An earlier git-cleanup stop does not prevent safe
reconciliation, but continuing requires a freshly resolved current base tip;
report the git and project results separately.

Before acting, read `references/project-obligations.md` §record,
`references/project-obligations.md` §discovery,
`references/project-obligations.md` §state-machine,
`references/project-obligations.md` §authorization,
`references/project-obligations.md` §trackers, and
`references/project-obligations.md` §failures. Use
`references/project-obligations.md` §freeside-example only as calibration.

Readable absence adds no behavior or summary text only after its final base-tip
check stays unchanged; an unreadable required source makes cleanup incomplete.
Reconcile only known trackers and authorized fields, observing every limit in
the reference. In particular, read the record
and mechanics from the same freshly resolved immutable base commit, never from
the checked-out feature tree or a stale local ref, and recheck that base tip
before every tracker write attempt and after its tracker verification attempt,
even when the write or verification failed. The record can authorize only
guarded transitions and listed refreshes for known containing trackers, never
another external or project mutation. The mutation guard or exclusive-writer
window must cover every external object whose state selected the tracker or
determined the computed edit, not only the tracker being written.

Use `reconciliation-ledger.sh` for every discovery result, including readable
absence. Enumerate work per tracker and per transition or refreshed field,
record each ordered freshness, guard, attempt, verification, and disposition
event. Name every external input used by a write, no-op, or report; after all
writes are dispositioned, reread and recompute no-op and report items before
recording them fresh. Then close the trace with a final base-tip observation
even when no write ran. A stable absence suppresses the complete ledger and
stays silent;
otherwise report the checker's ledger and owner action. Only `RESULT complete`
supports a full project-reconciliation claim. Run it as
`<skill-dir>/reconciliation-ledger.sh '<trace-file>'`; `--help`, or `-h`, prints
the trace contract. If the executable check cannot run, apply the referenced
state machine manually and report that verification gap.

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
unverifiable merge, undeletable branch) that now needs the user. When a
post-merge record exists or its required source was unreadable, also say which
project obligations ran, what changed, what remains ambiguous or failed, and
which owner must act.
