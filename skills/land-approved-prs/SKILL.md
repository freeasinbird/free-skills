---
name: land-approved-prs
description: >-
  Land every pull request the owner has approved in one repository, one at a
  time under a forge-side lock. Use when the owner says "land the approved
  PRs", "land the approved PRs in <repo>", "land #A then #B", or "run a
  landing batch". Scripts list the ready PRs, take the lock, and gather what
  landed; the agent reads each PR against what landed, reworks it only when
  a landed change dictates the fix, lands it with the bundled engine, runs
  merge-cleanup, and hands back everything else with the record's hand-back
  label. The batch ends by sweeping landed branches' clean worktrees. Not
  for approving a PR (only the owner approves), merging one
  unapproved PR, or post-merge cleanup alone.
---

# Land Approved PRs

The owner reads a PR and approves it; that is their last decision about it.
Later, the owner asks an agent in the repository's primary checkout to land
the approved PRs. Scripts take the landing lock, list the ready PRs, and gather
what landed since each PR was opened. You read each ready PR against what
landed, decide whether it still holds, and land it. Anything that needs new
work or a decision goes back to the owner.

Never start a batch on your own. The owner starts each one.

## Requirements

This skill requires a shell, git, and a forge CLI (`gh`) authenticated for
the repository. It also requires the merge-cleanup skill installed beside it,
because merge-cleanup owns everything after each merge. If any one of these is
missing, stop before listing and hand the batch to the owner. There is no prose
fallback: the lock, the filters, and the landing engine exist only as
scripts.

Run from the repository's primary checkout, on its default branch, with a clean
tree. If the checkout is on another branch or has changes, stop and tell the
owner; don't stash, switch, or clean it. Every script call names the repository
as `--repo owner/name`, taken from the project's forge record. Set `GH_HOST` to
the recorded host when the CLI's default host differs.

The scripts `list-ready.sh`, `landed-since.sh`, and the landing engine
`land.sh` live in `<skill-dir>`, the directory that contains this file.

## Three Words

- **Land** means update the PR onto the tip, verify it on the exact commit,
  merge, and clean up. The engine's `land` phase does the first three, and
  merge-cleanup does the cleanup.
- **Approved** is the owner's judgment that the PR may land as it stands,
  expressed the way the landing record says.
- **Ready** is what `list-ready.sh` computes: approved and passing every other
  filter. A PR can be approved and not ready.

## The Landing Record

A project records how approval is expressed in an unmanaged section of its
`AGENTS.md`, shaped like its forge record. `list-ready.sh` reads it from the
fetched default-branch tip, never from the working tree, so a branch can't
loosen its own rules:

```markdown
- **Land approved PRs by label.** This project has the following landing
  record:

  - **Mechanism:** `label`.
  - **Approval:** `approved`, added by a collaborator with the Approver
    permission; agents never add it.
  - **Hand-back:** `needs-rework`.
  - **Approver permission:** `write`.
  - **Stale lock age:** `240` minutes.
  - **Base-advance checks:** none.
  - **Reviewer:** `chatgpt-codex-connector`.
  - **Reviewer completion marker:** `codex-pull-request-review-summary`.
  - **Consumer:** `land-approved-prs`.
```

Each value is the first backticked span on its bullet. Keep the bullets
together; the record ends at the first line of another shape, and the script
stops `bad-record` on a malformed one:

- **Mechanism** is `label`, the only mechanism this version lands.
- **Approval** and **Hand-back** name the two labels.
- **Approver permission** is the lowest repository role whose label counts:
  `write`, `maintain`, or `admin`, as held when the batch lists.
- **Stale lock age** defaults to 240 minutes.
- **Base-advance checks** is `none` or a list of backticked commands that
  `landed-since.sh` runs, so keep this bullet's prose free of backticks.
- **Reviewer** is the automated reviewer's login without any `[bot]` suffix,
  or `none`. The completion marker is the text its summary carries.

Both labels must exist on the forge before a batch. Create any missing one
with the commands below, using the record's label names and the project's
repository. The default colors are `#0e8a16` for `approved` and `#d93f0b` for
`needs-rework`. Keep a project's existing colors unless it wants these
defaults, and add `--force` only to replace them.

```sh
gh label create approved --repo owner/name --color 0e8a16 \
  --description "The owner approved this PR to land; the lander may take it"
gh label create needs-rework --repo owner/name --color d93f0b \
  --description "Lander hand-back: this pull request could not land; rework it, then re-approve"
```

Only a person adds the approval label. Any agent running under a
collaborator's account can add it, and the record is what makes doing so a
violation. Never add it, even to a PR you wrote, and never treat a chat
message as approval.

## The Batch

1. **Check the requirements.** Confirm the CLI, merge-cleanup, the checkout,
   and the landing record. Choose a run id unique to this batch: the host
   name, the start time, and a random suffix (`laptop-202610181430-7f3a`).
   The script treats a lock with this id as yours, so two sessions sharing
   an id would both hold it.
2. **List.** Run `list-ready.sh` with the run id. It takes the lock and prints
   the ready PRs in order, then every excluded PR with its filter and
   evidence. Read the list; never recompute it.
3. **Land the first ready PR** by "One PR" below.
4. **List again** after each PR lands or is handed back, never working from
   an older list. Listing also refreshes the lock, picks up new approvals,
   and drops revoked ones.
5. **Stop on an empty fresh list.** That call also releases the lock. Then
   run "The End-of-Batch Sweep" and write the batch report. Any other end
   follows "Ending Early."

```sh
<skill-dir>/list-ready.sh --repo <owner/name> --run <id>
<skill-dir>/list-ready.sh --repo <owner/name> --run <id> --order 12,9
<skill-dir>/list-ready.sh --repo <owner/name> --run <id> --pr <num> --pushed <oid>
<skill-dir>/list-ready.sh --repo <owner/name> --release <id>
```

Pass `--order` when the owner typed an order ("land #12, then #9"), and pass
the same `--order` on every list in the batch; a list without it falls back to
approval order. Pass `--base-remote <name>` when several remotes name the
repository, and pass the same value to `landed-since.sh`.

Run the PRs in sequence in the main session, which owns the engine's waits.
Where the platform supports delegation, hand only the bounded read and
decision of steps 1 and 2 in "One PR" to a subagent; otherwise do them inline.

## Readiness Filters

Each filter exists for a stated reason, and adding or removing one is the
owner's decision. `list-ready.sh` applies them and names the first one a PR
fails:

1. **Open and not a draft.** A draft is the author saying "not yet."
2. **Targets the default branch.** A stacked PR becomes eligible when its
   parent merges and the forge retargets it.
3. **Approved per the record and not handed back.** A collaborator at or
   above the Approver permission added the latest approval label event, and
   the PR lacks the hand-back label.
4. **The head is the approved one, or this run pushed it.** The owner read a
   specific version, so the script reconstructs it from push evidence, never
   from comments. A head recorded with `--pushed` counts only for its PR.
5. **No unresolved review threads.** The owner may have approved before the
   last round posted.
6. **The recorded reviewer's round is complete on the current head,** when
   the record names a reviewer.
7. **Not a fork head.** The engine doesn't rebase or push another
   repository's branch.

An excluded PR needs no action from you, with one exception: a filter 4
exclusion won't clear on its own, so hand that PR back. List every excluded PR
that still carries the approval label in the batch report, with its filter and
detail, because the owner may be waiting on it.

CI is deliberately not a filter. The engine checks CI on the exact commit it
will merge, after any rebase.

## The Lock

One lander runs per repository. Landing is serial on purpose: each PR is read
against what the previous one landed, and only the lock stops another lander
from merging between the engine's base read and its merge.

The lock is the ref `refs/land/lock` on the repository's remote, whose commit
date is the heartbeat. `list-ready.sh` acquires it on the first non-empty
list, refreshes it on every later list and `--pushed` record, and releases it
on an empty fresh list or `--release <id>`.

- **Stale** means a heartbeat older than the record's stale age, which must
  exceed the longest a live lander goes without listing: the engine's caps
  times its allowed runs, plus a `rerun` phase, a reviewer wait, and a margin.
- **Never take over.** A lock held by another run stops the list as
  `lock-held`, or `lock-stale` when it is past the stale age. Report its run
  id, machine, and age, and stop.

A stale lock means the run is suspected dead, not known dead, and a `land`
process it started may still be waiting on CI. Only the owner frees it: once
they confirm the old session and every process it launched are gone, they
release it with `--release` and that run's id.

Run `land.sh` only on a PR your current list reported ready, while your run
holds the lock. The engine checks neither the lock nor the labels, so running
it on any other PR lands it without approval: the same violation as adding
the approval label yourself. Never run its `merge` phase on its own.

## One PR

1. **Read it.** Title, body, diff, and review threads.
2. **Read what landed.** Run `landed-since.sh`. Open any commit
   that could bear on the PR, not only those touching the same paths, and
   decide whether the PR still holds.
3. **If it holds, land it** with `land.sh`, acting on each stop as "Acting on
   Each Stop" says.
4. **If it doesn't hold, rework it only when the landed change dictates the
   fix.** See "The Rework Rule."
5. **After the merge, run merge-cleanup.** See "After the Merge."
6. **Comment** when anything changed beyond a clean rebase. See "Comments and
   the Batch Report."
7. **Hand back cleanly** when anything needs a person. See "Hand-Back."

```sh
<skill-dir>/landed-since.sh --repo <owner/name> --pr <n>
<skill-dir>/landed-since.sh --repo <owner/name> --pr <n> --since <oid>
```

Without `--since`, the range starts at the PR's original fork point, so it
includes landings the author's merge or rebase absorbed. When the script stops
`original-base-unknown`, hand the PR back. Use `--since` with the tip from your
last read when re-reading after `rebased`. The base-advance checks' output and
exit status are evidence for your judgment; the script decides nothing.

### Running the Engine

Invoke the engine by path from the primary checkout. Its header comment
documents each phase's checks and its options, such as `--head-remote` and
`--interval`. Run `check` first; it returns
the verified head OID that `land` pins with `--head`:

```sh
<skill-dir>/land.sh check --pr <n> --repo <owner/name>
<skill-dir>/land.sh land  --pr <n> --repo <owner/name> --head <oid>
<skill-dir>/land.sh rerun --pr <n> --repo <owner/name> --head <oid>
```

Pin the head the list gave. The PR's pinned head is the `head_oid` from the
list you took it from, or the OID you last recorded with `--pushed`. Land
only a `check` that reports the pinned head. When it reports another, someone
pushed after the list: list again and let filter 4 decide.

`land` merges only when the head contains the base tip, CI is green on that
exact head, and the base hasn't moved; otherwise it stops. `rerun` runs only
after `land` stops `checks-failed`, and never merges.

Run `land` and `rerun` in the background with a completion wake where the
platform offers one. Otherwise keep each command under the platform's limit on a
single command: for `land`, `--ci-cap-minutes` plus `--cap-minutes` (30 and 15
by default); for `rerun`, twice `--ci-cap-minutes`. Either way, run the engine
again on `checks-pending` or `checks-missing` at most three times before handing
back. A `rerun` phase and the `land` run after it each count as one of those
three.

### Acting on Each Stop

Rerun the engine only where a bullet below says to. Never rerun it to get past
any other stop, and never bypass a guard with force, reset, or a manual merge.

- **`rebased`:** The engine pushed a rebased head. Record the result's
  `head_oid` with `list-ready.sh --pushed`; it is now the pinned head. Rerun
  `landed-since.sh` with `--since` set to the `tip` from your last
  `OK landed-since` result, repeat step 2 on the new commits, then read the
  range-diff. A clean rebase doesn't wait for the reviewer: read any finding
  already posted on the new head once, then run `check` and `land` again.
- **`rebase-conflict` or `rebase-failed`:** The engine left the branch
  unchanged. Rebase it by hand under the rework rule, taking only hunks the
  landed change dictates, in the head branch's existing worktree or a new one
  outside the primary checkout that you name in the batch report. If any hunk
  has two defensible resolutions, run `git rebase --abort` there, hand back,
  and name the paths and the choice needed. Otherwise push with a lease on the
  pinned head, record the push with `--pushed`, and review it under
  "Reviewing Rework."
- **`not-on-tip`:** A dry run found the head behind the tip. Run `land`
  without `--dry-run`.
- **`base-moved`:** If the PR's base changed, list again and let filter 2
  decide. Otherwise run `check` and `land` again.
- **`checks-failed`:** Read the failed jobs' logs and name the failing tests
  or steps. For each entry in the result's `failed` array with a `run_id`, run
  `gh run view <run_id> --job <job_id> --log-failed --repo <owner/name>`.
  Then classify the failure:

  - **Infrastructure:** A lost or cancelled runner, a failed setup step, a
    network or registry failure, or a forge 5xx. Rerun.
  - **Known flake:** Every failing test is named as flaky in an open issue in
    the project. Rerun, and comment on that issue with the run link.
  - **Suspected flake:** The failure is outside the PR's diff paths and the
    packages it touches, and the same check passed on the PR's previous head:
    the `old_head_oid` from this batch's `STOP rebased`, or else the head
    before the pinned one in the PR's push history. Rerun. If the rerun
    passes, file a flake issue naming the test and both runs, and link it in
    the batch report.
  - **Otherwise:** The failure is in the PR's paths, or no previous green run
    exists. Treat it under the rework rule, or hand back.

  To rerun, run `land.sh rerun` on the pinned head, then `land` again on the
  same head. The engine allows one rerun per pinned head; a rebase onto a new
  tip gets a fresh one. A second failure on that head hands back, with both
  runs and the classification in the comment, because a repeated failure is
  evidence against a flake.

- **`nothing-to-rerun`:** The failure cleared, for example after someone
  reran it. Run `land` again on the same head; if it stops `checks-failed`,
  hand back.
- **`checks-pending` or `checks-missing`:** Run the same phase again within
  the bound above, then hand back.
- **`no-local-branch` or `oid-mismatch`:** When the forge head is no longer
  the pinned head, list again. When it still is, and no worktree has the
  branch checked out with changes, update the local branch to the pinned head
  and run `check` again. Otherwise hand back.
- **`pr-closed` or `pr-not-open`:** The PR closed or merged since the list.
  List again.
- **`dirty-tree`:** When the primary checkout has changes, end the batch as
  "Ending Early" says, without stashing or cleaning them. When the head
  branch's worktree has them, hand back with its path.
- **`wrong-checkout`, `not-a-repo`, `remote-unresolved`, `remote-ambiguous`,
  `remote-repo-mismatch`, `pushurl-mismatch`, or `op-in-progress`:** The
  checkout or the invocation is wrong, not the PR, so don't hand the PR back.
  Fix the invocation if you can; otherwise end the batch as "Ending Early"
  says.
- **`no-landing-record`, `bad-record`, `unsupported-mechanism`,
  `queue-method`, or `queue-message`:** The landing record or a repository
  setting is wrong and would stop every PR alike, so don't hand the PR back.
  End the batch as "Ending Early" says, naming the guard and its detail.
- **`lease-failed`:** Someone else pushed to the branch after approval. Hand
  back and say so.
- **`ignored-clobber`:** Moving the head worktree would overwrite an ignored
  file there. Hand back with the path; the worktree is its owner's.
- **`stacked-prs`:** The PR is the parent of a stack on a cross-repository
  head. Hand back naming the guard; see "Stacks."
- **`rerun-spent`, `rerun-unsupported`, `rerun-refused`,
  `rerun-unconfirmed`, or any other `STOP`:** Hand back naming the guard, with
  any classification and run links. `rerun-spent` means a failed run on the
  head was already rerun; `rerun-unsupported`, that a failure isn't a GitHub
  Actions job.

A read failure isn't a guard stop. `LOOKUP_FAILED` means a script couldn't
read the forge or the remote, after the scripts' own retries of a transient
forge read. Read the `stderr` key first, when present. A timeout, an HTTP 5xx,
or a rate limit is transient: check that the forge and remote are reachable,
then rerun the same script once. A 404, a permission error, or an
authentication error won't clear, so end the batch as "Ending Early" says and
quote the error. With no `stderr` key, check reachability and rerun once.
Never act on your own reading in place of the script's result. If the rerun
fails, end the batch as "Ending Early" says.

### Ending Early

Any end other than an empty fresh list leaves the lock held. Release it with
`list-ready.sh --release <id>`, then run "The End-of-Batch Sweep" unless its
skip rules apply, write the batch report, and name what stopped the batch.
After `lock-lost`, release nothing and skip the sweep: the lock is no longer
yours.

### The Rework Rule

Rework a PR only when the landed change dictates the fix: a rename, a moved
file, a changed signature, or a test that now needs the new fixture. Make the
change in a worktree of the head branch outside the primary checkout, push it
with a lease on the pinned head, record the push with `--pushed`, get it
reviewed, wait for CI, then land. A failed lease means someone else pushed;
hand back.

Stop instead when the fix needs something the PR's issue or body didn't call
for, or a decision the landed change doesn't settle. Size is not the test. A
ten-line dictated fix proceeds, and a one-line fix that picks between two
defensible behaviors stops. Rework may make the PR true again on the new
default branch; it may not extend what the PR does.

### Reviewing Rework

A rework or a resolved conflict is new work, so it gets a review:

- **The project records an automated reviewer.** Wait for its completion
  signal on the reworked head, resolve any finding under the rework rule,
  then land.
- **No recorded reviewer, delegation available.** A fresh-context reviewer
  reads the range-diff of the rework against the landed change, given only
  that diff and the intended outcome, before `land`. Findings go through the
  rework rule; anything else hands back.
- **No recorded reviewer, no delegation.** The owner is the reviewer: hand
  back with the range-diff in the comment.

A clean rebase pushes no new work, so it needs none. Don't wait for a reviewer
round on a merged head; read whatever posted when the batch ends.

### Hand-Back

Hand back when the rework rule says stop, when a finding can't be resolved
under it, when CI stays red, or when anything else needs a person. Comment
why, then swap the labels the record names:

```sh
gh pr comment <n> --repo <owner/name> --body-file <comment-file>
gh pr edit <n> --repo <owner/name> --remove-label <approval label> --add-label <hand-back label>
```

The label is the record, because the owner gets no notification for comments
posted under their own account. Then list again and take the next PR. The
owner re-adds the approval label and removes the hand-back label to say "try
again."

### After the Merge

Once the forge reports the PR merged, stop any review watch on it, then run
the merge-cleanup skill's procedure for it from Resolve the Work Unit through
Summarize. Run it from the same checkout and pass:

- `--repo` as `<host>/<owner>/<name>`: the forge record's host joined to the
  slug. Name the host even when it is `github.com`.
- `--pr` as the merged PR's number.
- `--checkout` as the checkout's absolute root.

Merge-cleanup removes the PR's head worktree itself when it's clean. Never
remove a worktree any other way during a batch. If merge-cleanup stops
`head-worktree-present`, it kept that worktree; record the path. Then do the
parts it skipped that don't touch the worktree: fast-forward the checkout's
default branch from the remote, and confirm the issues the PR closes actually
closed. Leave the local branch; "The End-of-Batch Sweep" may free it.

Never print a bare `git worktree remove` line for the owner to paste: even
without `--force`, it deletes the worktree's ignored files and exits 0. For a
worktree the end-of-batch sweep keeps, point the owner at merge-cleanup's
worktree sweep, which reports what each removal would delete.

## The End-of-Batch Sweep

Every batch ends by removing landed branches' clean worktrees: this batch's,
and any earlier landing's still on disk. Run the sweep only after this run's
lock is released, by an empty fresh list or by `--release`, and before the
batch report. Skip it after `lock-lost`, `lock-held`, or `lock-stale`,
because another lander may be live, and when the run never held the lock.
Skip it when the owner says not to sweep for this batch.

From the primary checkout, fetch the base's remote, then run merge-cleanup's
sweep with `--remove-landed` and the base named. Here, `<merge-cleanup-dir>`
is the merge-cleanup skill's directory beside this one. The remote is
`origin`, or the `--base-remote` value when the batch passed one.

```sh
git fetch --prune <remote>
<merge-cleanup-dir>/worktree-sweep.sh --remove-landed --base <remote>/<default-branch>
```

`--remove-landed` removes only clean worktrees whose branch has a landing merge.
It keeps dirty worktrees, unmerged branches, and detached `land-wt` worktrees,
so a lander that starts after the release is safe. Never add `--remove` or
`--remove-dirty`: what this sweep keeps is the owner's to remove. A `STOP` or
`LOOKUP_FAILED` result goes in the batch report as it stands; never rerun the
sweep with other flags.

For each PR whose merge-cleanup stopped `head-worktree-present` and whose
worktree the sweep removed, rerun merge-cleanup's procedure with the same
arguments as "After the Merge." That deletes the local branch and retargets any
stacked children. A removed worktree whose PR this batch didn't land keeps its
local branch; name it in the report so the owner can run merge-cleanup for it.

## Ordering

Oldest approval first. A typed order overrides it, passed as `--order`. When
an ordered PR is open but not ready, the list holds back every PR sequenced
after it, naming the dependency. When you hand back an ordered PR, hand back
the PRs sequenced after it too, naming the PR they waited on. PRs the owner
didn't sequence follow in approval order.

## Stacks

Land a stack's parent like any other PR. The engine reports the open PRs based
on its branch, in `check`'s `stacked_prs`, and continues. When the merged
branch is deleted, the forge or merge-cleanup retargets each child onto the
parent's base, and the next list admits each approved child under filter 2.
Name the children in the batch report as unblocked by the parent.

When merge-cleanup stops `head-worktree-present` because it kept the parent's
worktree, and the repository doesn't auto-delete merged branches, nothing
retargets yet, so filter 2 keeps excluding the children. Name them in the batch
report as waiting on the owner's removal of that worktree; the cleanup run after
it retargets them.

A child's own `land` rebase drops the parent's pre-rebase commits that match
what merged. A conflict there is a `rebase-conflict` and follows that stop's
rule.

A native GitHub stack (one managed with `gh stack`) needs linear history
between its branches, so the parent's `merge` may stop `merge-refused`. Hand
the parent back naming the guard; the owner re-linearizes the stack with
`gh stack rebase --upstack`.

A cross-repository head still stops `stacked-prs`, because neither the forge
nor merge-cleanup can retarget its children onto this base. Hand the parent
back naming the guard; the owner retargets the children or merges the parent.

## Recovery After a Dead Lander

Once the owner has released a stale lock, the next run starts as usual. Report,
and leave in place, any temporary worktree the dead run's `land` left
registered, at a path ending in `land-wt.XXXXXX/wt`. The end-of-batch sweep
leaves it, so the owner removes it with merge-cleanup's
manual worktree sweep. The PR the dead run was on is in one of three states:

- **Not yet pushed:** it is still approved and starts over.
- **Rebased and pushed, not merged:** its head is neither the approved head
  nor in the new run's push log, so filter 4 excludes it; hand it back. The
  owner re-approves it by removing and re-adding the approval label.
- **Merged, not cleaned up:** run merge-cleanup on it.

## Revoking Approval

Tell the owner this when they ask how to stop a landing. Removing the
approval label is honored at the next list, so it stops a PR that hasn't
started. It doesn't stop one the engine is already carrying through its CI
wait, because the engine is label-blind.

To stop a landing in flight, stop the lander session and every `land` process
it launched. Ending a chat doesn't necessarily end a command it started in
the background, and a surviving `land` still merges when CI passes.

## Script Results

Every script's last stdout line is the machine-readable result: `OK`,
`STOP <guard>`, or `LOOKUP_FAILED`, each with JSON facts. Branch on it and on
the exit code, never on the prose above it. Each script's header comment
documents its results and exit codes. Exit 64 is a usage error: fix the call.
Exit 69 means no `gh` on PATH: hand the batch to the owner.

`list-ready.sh` stops `lock-lost` when the lock moved under this run: stop the
batch and report. It stops `lock-not-held` when a push was recorded without
the lock. Its record and remote stops follow "Acting on Each Stop."

## Comments and the Batch Report

Comment on a landed PR when anything changed beyond a clean rebase. Say what
changed and why, and include the range-diff.

A hand-back comment says which step stopped, the guard or finding, and what
the owner must decide. For a conflict, name the paths and the choice needed.

End every batch with a report:

- What landed, with each merged head.
- What changed beyond a clean rebase, and why.
- What was handed back, and the reason for each.
- Each CI rerun: its classification, any flake issue, and the result.
- Every excluded PR that still carries the approval label, with its filter
  and detail.
- The worktrees the end-of-batch sweep removed, by path, and the ones it
  kept, by path with the sweep's reason. If the sweep was skipped, say why.
- Any reviewer finding posted on a merged head.
- Any lock or lookup problem the owner should know about.
