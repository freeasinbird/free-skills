---
name: land-approved-prs
description: >-
  Land every pull request the owner has approved in one repository, one at a
  time under a forge-side lock. Use when the owner says "land the approved
  PRs", "land the approved PRs in <repo>", "land #A then #B", or "run a
  landing batch". Scripts list the ready PRs, take the lock, and gather what
  landed; the agent reads each PR against what landed, reworks it only when
  a landed change dictates the fix, lands it with the bundled engine, runs
  merge-cleanup, and hands back everything else with needs-human. Not for
  approving a PR (only the owner approves), merging one unapproved PR, or
  post-merge cleanup alone.
---

# Land Approved PRs

The owner reads a PR and approves it. That is the owner's last decision about
it. Later, the owner starts an agent in the repository's primary checkout and
asks it to land the approved PRs. This skill tells that agent how.

Scripts do the mechanical parts: take the landing lock, list the PRs that pass
the readiness filters, and gather what has landed on the default branch since
each PR was opened. The agent does the judging. It reads each ready PR against
what landed, decides whether the PR still holds, and lands it. Anything that
needs new work or a decision goes back to the owner.

Never start a batch on your own. The owner starts each one.

## Requirements

This skill requires a shell, git, and a forge CLI (`gh`) authenticated for
the repository. It also requires the merge-cleanup skill installed beside it,
because merge-cleanup owns everything after each merge. If any one of these is
missing, stop before listing and hand the batch to the owner. There is no prose
fallback: the lock, the filters, and the landing engine exist only as
scripts.

Run from the repository's primary checkout, on its default branch, with a
clean tree. If the checkout is on another branch or has changes, stop and tell
the owner; don't stash, switch, or clean it. Every script call names the repository as `--repo owner/name`,
taken from the project's forge record. Set `GH_HOST` to the recorded host when
the CLI's default host differs.

The scripts live next to this file. Here, `<skill-dir>` is the directory that
contains it:

- `list-ready.sh` takes the lock and lists the ready PRs.
- `landed-since.sh` prints what landed since a PR diverged and runs the
  project's base-advance checks.
- `land.sh` is the landing engine. It checks a PR, updates it onto the tip,
  waits for CI on the exact commit, and merges.

## Three Words

Each of these words means one thing here:

- **Land** is the procedure that gets a PR onto the default branch: update
  it, verify it on the exact commit, merge, and clean up. Merge is only the
  last git step. The engine's `land` phase does the first three, and
  merge-cleanup does the cleanup.
- **Approved** is the owner's judgment that the PR may land as it stands. A
  project expresses it the way its landing record says.
- **Ready** is what `list-ready.sh` computes: approved and passing every other
  filter. A PR can be approved and not ready.

## The Landing Record

A project records how approval is expressed in an unmanaged section of its
`AGENTS.md`, shaped like its forge record. `list-ready.sh` reads it from the
fetched default-branch tip, never from the working tree, so a branch can't
loosen its own rules. The record is a run of bold-key bullets that starts at
the Mechanism bullet:

```markdown
- **Land approved PRs by label.** This project has the following landing
  record:

  - **Mechanism:** `label`.
  - **Approval:** `approved`, added by a collaborator with the Approver
    permission; agents never add it.
  - **Hand-back:** `needs-human`.
  - **Approver permission:** `write`.
  - **Stale lock age:** `240` minutes.
  - **Base-advance checks:** none.
  - **Reviewer:** `chatgpt-codex-connector`.
  - **Reviewer completion marker:** `codex-pull-request-review-summary`.
  - **Consumer:** `land-approved-prs`.
```

Each value is the first backticked span on its bullet:

- **Mechanism** is `label`, the only mechanism this version lands. A review
  approval or an armed auto-merge each needs its own contract first, so the
  script stops `unsupported-mechanism` on them.
- **Approval** and **Hand-back** name the two labels.
- **Approver permission** is the lowest repository role whose label counts:
  `write`, `maintain`, or `admin`. The script reads each label actor's role
  from the collaborator permission endpoint: `role_name`, or for a custom
  role the base role its `user.permissions` flags report, with the legacy
  `permission` field as the last resort. A user with no role on the
  repository, or only read access, never approves. The role is
  the one held when the batch lists, not when the label was added. It has no
  default: a record naming one Approver login stops `bad-record`.
- **Stale lock age** defaults to 240 minutes when the bullet is absent. A
  bullet without a backticked value stops `bad-record`.
- **Base-advance checks** is `none`, bare or backticked, or a list of
  backticked commands, run by `landed-since.sh`. Every backticked span on
  this bullet runs as a command, so keep its prose free of backticks. It has
  no default: a missing bullet, or a value with no backticked command, stops
  `bad-record` rather than skip the checks.
- **Reviewer** is the automated reviewer's login without any `[bot]` suffix,
  or `none`. It has no default: a missing or unparsed bullet stops
  `bad-record` rather than drop filter 6. Only a bot account's summary
  counts. The completion marker is the text that summary carries; it mirrors
  the project's reviewer record.

The record ends at the first line that is neither a bullet of this shape nor
its four-space continuation, so keep its bullets together.

Both labels must exist on the forge before a batch. Use `#0e8a16` as the
default color for `approved` and `#d93f0b` for `needs-human`. Keep a project's
existing colors unless it wants these defaults. Replace `owner/name` with the
project's repository and use the record's Approval and Hand-back names if
they differ from the examples. Run the commands for missing labels. Add
`--force` only to replace an existing label's color and description with the
defaults below.

```sh
gh label create approved --repo owner/name --color 0e8a16 \
  --description "The owner approved this PR to land; the lander may take it"
gh label create needs-human --repo owner/name --color d93f0b \
  --description "The lander handed this PR back; it needs the owner"
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
   an older list. Each landing changes the default branch, so an older list
   plans against a branch that no longer exists. Listing also refreshes the
   lock, picks up new approvals, and drops revoked ones.
5. **Stop on an empty fresh list.** That call also releases the lock. Then
   write the batch report. Any other end follows "Ending Early."

```sh
<skill-dir>/list-ready.sh --repo <owner/name> --run <id>
<skill-dir>/list-ready.sh --repo <owner/name> --run <id> --order 12,9
<skill-dir>/list-ready.sh --repo <owner/name> --run <id> --pr <num> --pushed <oid>
<skill-dir>/list-ready.sh --repo <owner/name> --release <id>
```

Pass `--order` when the owner typed an order ("land #12, then #9"), and pass
the same `--order` on every list in the batch; a list without it falls back to
approval order. Pass `--base-remote <name>` when several remotes name the
repository, and pass the same value to `landed-since.sh`. A remote
whose fetch or push URL names another repository stops
`remote-repo-mismatch`, because the lock and the landing record must come
from the repository itself.

Run the PRs in sequence in the main session, which owns the engine's waits.
Where the platform supports delegation, hand only the bounded read and
decision of steps 1 and 2 in "One PR" to a subagent; otherwise do them inline.

## Readiness Filters

Each filter exists for a stated reason, and adding or removing one is the
owner's decision. `list-ready.sh` applies them cheapest first, in this
order except that filter 7 runs right after filter 3, and names the first one
a PR fails:

1. **Open and not a draft.** A draft is the author saying "not yet."
2. **Targets the default branch.** A stacked PR becomes eligible when its
   parent merges and the forge retargets it.
3. **Approved per the record and not handed back.** It carries the approval
   label, a collaborator at or above the Approver permission added the latest
   such label event, and it lacks the hand-back label.
4. **The head is the approved one, or this run pushed it.** The owner read a
   specific version, so the script reconstructs it from push evidence.
5. **No unresolved review threads.** An open thread is an open question, and
   the owner may have approved before the last round posted.
6. **The recorded reviewer's round is complete on the current head.** This
   filter applies only when the record names a reviewer.
7. **Not a fork head.** The engine doesn't rebase or push another
   repository's branch, so the list reports the case instead.

Filter 4 works from push evidence, never from comments or commit order. The
approval time T is the latest approval label event. The approved head H0 is
the head of the newest pull-request CI run, or force-push, at or before T.
The PR is ready only when its head is H0 or a head this run recorded for that
PR with `--pr` and `--pushed`. A head recorded for one PR never exempts
another, since two branches can point at one commit.

A force-push after T that this run didn't record excludes the PR, even if the
head later returns to H0. So does a PR whose H0 can't be found. GitHub runs no
pull-request CI while a PR has a merge conflict, so a push to a conflicted PR
can leave no evidence; the script excludes such a PR rather than guess.

An excluded PR needs no action from you, with one exception: a filter 4
exclusion won't clear on its own, so hand that PR back. List every excluded PR
that still carries the approval label in the batch report, with its filter and
detail, because the owner may be waiting on it.

CI is deliberately not a filter. The engine checks CI on the exact commit it
will merge, after any rebase, and a check on a stale head would say nothing
about that commit.

## The Lock

One lander runs per repository. Landing is serial on purpose: each PR is read
against what the previous one landed. The engine also reads the base tip and
merges in separate steps. Without branch protection that rejects merges onto a
moved tip, only the lock stops another lander from merging in between.

The lock is the ref `refs/land/lock` on the repository's remote. It points at
an orphan commit naming the run, the machine, and the PR in progress, and its
commit date is the heartbeat. The forge arbitrates it: a push leased on the
ref's absence succeeds for exactly one lander.

- **Acquire** on the first non-empty list.
- **Heartbeat** on every later list and every `--pushed` record. Each moves
  the ref with a lease on its previous value.
- **Release** on an empty fresh list. `--release <id>` ends a batch early.
- **Stale** means a heartbeat older than the record's stale age. That age
  must exceed the longest a live lander goes without listing: the engine's CI
  and merge caps times the number of allowed runs, plus a reviewer wait and a
  margin.
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
2. **Read what landed.** Run `landed-since.sh`. It prints the default
   branch's first-parent log with `--stat` from the PR's original fork point
   to the tip, then runs the record's base-advance checks. Open any commit
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

The original fork point is the common ancestor of the default-branch parents
of every commit the PR has had, across its current head and every head a force
push replaced. On one line, that's the oldest of those parents. It doesn't
move as the default branch advances or the author merges it in or rebases. A
later base is no substitute: it skips exactly the landings the author's merge
or rebase absorbed without anyone reading them against this PR. When a force
push replaced a head the forge no longer has, the script stops
`original-base-unknown`; hand the PR back.

Use `--since` with the tip from your last read when re-reading after
`rebased`. Base-advance checks see `LAND_PR`, `LAND_FROM`, and `LAND_TIP` in
their environment. Their output and exit status are evidence for your
judgment; the script decides nothing.

### Running the Engine

Invoke the engine by path from the primary checkout. Run `check` first; it
returns the verified head OID that `land` pins with `--head`:

```sh
<skill-dir>/land.sh check --pr <n> --repo <owner/name>
<skill-dir>/land.sh land  --pr <n> --repo <owner/name> --head <oid>
```

Pin the head the list gave. The PR's pinned head is the `head_oid` from the
list you took it from, or the OID you last recorded with `--pushed`. Land
only a `check` that reports the pinned head. When it reports another, someone
pushed after the list: list again and let filter 4 decide.

`check` verifies that the PR is open, the tree is clean, and no git operation
is paused. It also checks that no competing worktree layout exists, the head
and base names don't collide, no other open PR shares the head branch, and
any merge queue uses merge commits. Its `OK` result lists the open PRs
stacked on the head branch as `stacked_prs`; see "Stacks."

A private repository whose plan lacks rulesets, such as GitHub Free, counts
as having no queue. GitHub refuses its branch-rules read with a plan-limit
403, and that plan can't run a merge queue there. `check`, `land`, and
`merge` all read the rules, and any other failed read still stops with
`LOOKUP_FAILED queue-rules`.

One `land` run is one round of three checks, and it merges only when all
three pass:

1. **On the tip.** It fetches the base. If the head doesn't contain the tip,
   it rebases the head in a temporary detached worktree, pushes with a lease
   on the reviewed head, and stops `rebased` before CI and the merge.
2. **CI on the exact head.** It waits for every check run and commit status
   on the head commit to finish green on two consecutive reads. No CI, or a
   single green read, by the cap is a refusal.
3. **Base unmoved.** Just before merging, it rereads the base tip from the
   forge and refuses if the tip moved.

When all three pass, `land` runs its `merge` phase: a real merge commit with a
title-only message, followed by a wait until the forge reports the PR
merged. Its `OK land` result names the merged head as `head_oid`.

The engine's options:

- `--base-remote <name>` and `--head-remote <name>` name the base or head
  remote when several point at the repository.
- `--interval <seconds>` spaces the CI and merged-state polls (default 10).
- `--cap-minutes <n>` caps the wait for the merged state (default 15).
- `--ci-cap-minutes <n>` caps the CI wait in `land` (default 30).
- `--dry-run` reports `land`'s decision without rebasing, pushing, or
  merging.

Run `land` in the background with a completion wake where the platform offers
one. Otherwise pass `--ci-cap-minutes` and `--cap-minutes` that sum to less
than the platform's limit on a single command. Either way, rerun on
`checks-pending` or `checks-missing` at most three times before handing back.

### Acting on Each Stop

Rerun the engine only where a bullet below says to. Never rerun it to get past
any other stop, and never bypass a guard with force, reset, or a manual merge.

- **`rebased`:** The default branch moved after your read, and the engine
  pushed a rebased head. Record the `head_oid` from the `STOP rebased` result
  with `list-ready.sh --pushed`; it is now the pinned head. Rerun
  `landed-since.sh` with `--since` set to the `tip` from your last
  `OK landed-since` result, and repeat step 2 on the new commits, because the
  range-diff shows only this PR replayed. Then read the range-diff. A clean
  rebase doesn't wait for the reviewer: read any finding already posted on
  the new head once, then run `check` and `land` again.
- **`rebase-conflict` or `rebase-failed`:** The engine left the branch
  unchanged. Rebase it by hand under the rework rule, in a worktree of the
  head branch outside the primary checkout, taking only hunks the landed
  change dictates. Use the branch's existing worktree, or add one and name it
  in the batch report. If any hunk has two defensible resolutions, run
  `git rebase --abort` there, hand back, and name the paths and the choice
  needed. Otherwise push with a lease on the pinned head, record the push
  with `--pushed`, and review it under "Reviewing Rework."
- **`not-on-tip`:** A dry run found the head behind the tip. Run `land`
  without `--dry-run`.
- **`ignored-clobber`:** Moving the head worktree would overwrite an ignored
  file there. Hand back with the path; the worktree is its owner's.
- **`base-moved`:** Another merge landed, or the PR was retargeted. If the
  PR's base changed, list again and let filter 2 decide. Otherwise run
  `check` and `land` again.
- **`checks-failed`:** Diagnose. Fix only under the rework rule; otherwise
  hand back.
- **`checks-pending` or `checks-missing`:** Rerun within the bound above, then
  hand back.
- **`stacked-prs`:** The PR is the parent of a stack on a cross-repository
  head. Hand back naming the guard; see "Stacks."
- **`lease-failed`:** Someone else pushed to the branch after approval. Hand
  back and say so.
- **`pr-closed` or `pr-not-open`:** The PR closed or merged since the list.
  List again.
- **`no-local-branch` or `oid-mismatch`:** When the forge head is no longer
  the pinned head, list again. When it still is, and no worktree has the
  branch checked out with changes, update the local branch to the pinned head
  and run `check` again. Otherwise hand back.
- **`dirty-tree`:** When the primary checkout has changes, end the batch as
  "Ending Early" says, without stashing or cleaning them. When the head
  branch's worktree has them, hand back with its path.
- **`wrong-checkout`, `not-a-repo`, `remote-unresolved`, `remote-ambiguous`,
  `remote-repo-mismatch`, `pushurl-mismatch`, or `op-in-progress`:** The
  checkout or the invocation is wrong, not the PR, so don't hand the PR back.
  Fix the invocation if you can. Otherwise end the batch as "Ending Early"
  says.
- **`no-landing-record`, `bad-record`, `fork-auto-delete`, `queue-method`, or
  `queue-message`:** The landing record or a repository setting is wrong, not
  the PR, and it would stop every PR alike, so don't hand the PR back. End the
  batch as "Ending Early" says, naming the guard and its detail.
- **Any other `STOP`:** Hand back naming the guard.

A read failure isn't a guard stop. `LOOKUP_FAILED` means a script couldn't
read the forge or the remote. Read its `stderr` key first, when present. A
timeout, an HTTP 5xx, or a rate limit is transient: check that the forge and
remote are reachable, then rerun the same script once. A 404, a permission
error, or an authentication error won't clear on a rerun, so end the batch as
"Ending Early" says and quote the error. With no `stderr` key, the failed read
was git's or gh said nothing; check reachability and rerun once. Never act on
your own reading in place of the script's result. If the rerun fails, end the
batch as "Ending Early" says.

### Ending Early

Any end other than an empty fresh list leaves the lock held. Release it with
`list-ready.sh --release <id>`, then write the batch report and name what
stopped the batch. After `lock-lost`, release nothing: the lock is no longer
yours.

### The Rework Rule

Rework a PR only when the landed change dictates the fix: a rename, a moved
file, a changed signature, or a test that now needs the new fixture. Make the
change in a worktree of the head branch outside the primary checkout, push it
with a lease on the pinned head, record the push with `--pushed`, get it
reviewed, wait for CI, then land. A failed lease means
someone else pushed; hand back.

Stop instead when the fix needs something the PR's issue or body didn't call
for, or a decision the landed change doesn't settle. Size is not the test. A
ten-line dictated fix proceeds, and a one-line fix that picks between two
defensible behaviors stops. Rework may make the PR true again on the new
default branch; it may not extend what the PR does.

### Reviewing Rework

A rework or a resolved conflict is a push of new work, so it gets the review
any agent's push gets. Three cases:

- **The project records an automated reviewer.** Wait for its completion
  signal on the reworked head, resolve any finding under the rework rule,
  then land.
- **No recorded reviewer, delegation available.** A fresh-context reviewer
  reads the range-diff of the rework against the landed change, given only
  that diff and the intended outcome, before `land`. Findings go through the
  rework rule; anything else hands back.
- **No recorded reviewer, no delegation.** The owner is the reviewer: hand
  back with the range-diff in the comment.

A clean rebase is outside this. It pushes no new work, CI reruns on the exact
head, and the reviewed content is unchanged. Don't wait for a reviewer round
on a merged head; read whatever posted when the batch ends.

### Hand-Back

Hand back when the rework rule says stop, when a finding can't be resolved
under it, when CI stays red, or when anything else needs a person. Comment
why, then swap the labels the record names (here, the defaults):

```sh
gh pr comment <n> --repo <owner/name> --body-file <comment-file>
gh pr edit <n> --repo <owner/name> --remove-label approved --add-label needs-human
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

Never remove a worktree during a batch. If merge-cleanup stops
`head-worktree-present`, record the path. Then do the parts it skipped that
don't touch the worktree: fast-forward the checkout's default branch from the
remote, and confirm the issues the PR closes actually closed. Leave the local
branch.

Never print a bare `git worktree remove` line for the owner to paste: even
without `--force`, it deletes the worktree's ignored files and exits 0.
Removing worktrees is the owner's, after the batch: point them at
merge-cleanup's worktree sweep, which reports what each removal would delete.

## Ordering

Oldest approval first. A typed order overrides it, passed as `--order`. When
an ordered PR is open but not ready, the list holds back every PR sequenced
after it, naming the dependency. When you hand back an ordered PR, hand back
the PRs sequenced after it too, naming the PR they waited on. PRs the owner
didn't sequence follow in approval order.

## Stacks

Land a stack's parent like any other PR. The engine reports the open PRs
based on its branch, in `check`'s `stacked_prs` and a stderr line from every
phase, and continues: nothing it runs deletes the branch. The forge retargets
each child onto the parent's base when the merged branch is deleted, and
merge-cleanup retargets them itself before its own delete. The next
`list-ready.sh` call then admits each approved child under filter 2. Name the
children in the batch report as unblocked by the parent.

When the repository doesn't auto-delete merged branches and merge-cleanup
stops `head-worktree-present`, nothing deletes or retargets yet. The children
stay based on the merged branch, and filter 2 keeps excluding them. Name them
in the batch report as waiting on the owner's removal of that worktree; the
cleanup run after it retargets them.

A child's turn after a rebased parent starts from the parent's pre-rebase
commits. Its own `land` rebase drops the ones that match what merged, and the
range-diff shows them dropping. A conflict there is a `rebase-conflict` and
follows that stop's rule.

A native GitHub stack (one managed with `gh stack`) must have linear history
between its branches before it can merge. After `land` rebases only the
parent, its `merge` may stop `merge-refused`. Hand the parent back naming the
guard; the owner re-linearizes the stack with `gh stack rebase --upstack`.

A cross-repository head still stops `stacked-prs`. Its children live in the
head's repository, where neither the forge nor merge-cleanup can retarget them
onto this base. Hand the parent back naming the guard; the owner retargets the
children or merges the parent.

## Recovery After a Dead Lander

Once the owner has released a stale lock, the next run starts as usual. Report,
and leave in place, any temporary worktree the dead run's `land` left
registered, at a path ending in `land-wt.XXXXXX/wt`. It blocks nothing, and the
owner removes it with merge-cleanup's worktree sweep. The PR the dead run was
on is in one of three states:

- **Not yet pushed:** it is still approved and starts over.
- **Rebased and pushed, not merged:** its head is neither the approved head
  nor in the new run's push log, so filter 4 excludes it; hand it back. The
  owner re-approves it by removing and re-adding the approval label, which
  sets a new approval time: one gesture per crashed PR.
- **Merged, not cleaned up:** run merge-cleanup on it, the same path as the
  owner saying "PR merged, clean up."

## Revoking Approval

Tell the owner this when they ask how to stop a landing. Removing the
approval label is honored at the next list, so it stops a PR that hasn't
started. It doesn't stop one the engine is already carrying through its CI
wait, because the engine is label-blind.

To stop a landing in flight, stop the lander session and every `land` process
it launched. Ending a chat doesn't necessarily end a command it started in
the background, and a surviving `land` still merges when CI passes.

## Script Results

Every script's last stdout line is the machine-readable result. Branch on it
and on the exit code, never on the prose above it:

| Exit | Report                        | Meaning                                      |
| ---- | ----------------------------- | -------------------------------------------- |
| 0    | `OK <phase> {json}`           | Done; the JSON carries the facts             |
| 2    | `STOP <guard> {json}`         | A guard fired; act on it as described        |
| 4    | `LOOKUP_FAILED <what> {json}` | A read failed; unknown is never absence      |
| 64   | Usage on stderr               | Bad or missing flags; fix the call           |
| 69   | Note on stderr                | No `gh` on PATH; hand the batch to the owner |

A `LOOKUP_FAILED` from a failed forge read adds a `stderr` key: the first 300
bytes of gh's error output. The scripts turn off gh's and Go's debug output
for these reads, so no request header reaches it.

`list-ready.sh` reports `OK list` with `ready` and `excluded` arrays and the
lock's state: `acquired`, `refreshed`, `released`, or `absent`. It reports
`OK pushed` for a recorded push and `OK release` for a release. Its stops:

- `lock-held` and `lock-stale`: another run holds the lock.
- `lock-lost`: the lock moved under this run; stop the batch and report.
- `lock-not-held`: a push was recorded without the lock.
- `no-landing-record`, `bad-record`, or `unsupported-mechanism`: the record
  is missing, malformed, or names an unimplemented mechanism.
- `remote-unresolved`, `remote-ambiguous`, or `not-a-repo`: fix the
  invocation.

`landed-since.sh` reports `OK landed-since` with the range, the number of
heads it examined, the commit count, and each check's exit status. It stops
`original-base-unknown` when the original fork point can't be found.

## Comments and the Batch Report

Comment on a landed PR when anything changed beyond a clean rebase. Say what
changed and why, and include the range-diff. For example: "Rebased onto #2052.
Renamed the call in `foo.go` to match."

A hand-back comment says which step stopped, the guard or finding, and what
the owner must decide. For a conflict, name the paths and the choice needed.

End every batch with a report:

- What landed, with each merged head.
- What changed beyond a clean rebase, and why.
- What was handed back, and the reason for each.
- Every excluded PR that still carries the approval label, with its filter
  and detail.
- Which worktrees were kept, with their paths.
- Any reviewer finding posted on a merged head.
- Any lock or lookup problem the owner should know about.
