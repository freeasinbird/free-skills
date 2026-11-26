# Lander Prepares the Next PR During the CI Wait

`land-approved-prs` now prepares the next ready PR against the current PR's
pushed head while that PR waits on CI, and runs merge-cleanup during the next
PR's wait (#497). Chose replaying the prepared tree, guarded by a base-tree
check, over `git rerere`, because the check makes a whole-tree replay exact
and `rerere` is neither exact nor local to the run.

## Decisions

- **Replay whole trees, only onto a base with the prepared base's tree.**
  `land --prepared` reuses a preparation only when the fetched base tip has
  the tree of the commit B was prepared onto (A's pushed head). The forge's
  merge commit of an up-to-date head has that head's tree, so the check holds
  exactly when nothing but A's merge landed. A base that moved further has
  another tree, and replaying a prepared tree there would silently revert the
  extra change, so the run ignores the preparation. At each conflict the
  replay also requires the commit being picked to match the prepared commit
  (author, date, message) and the rebase so far to have the prepared tree,
  then checks the commit count and final tree before the branch moves. A
  mutation test showed the per-pick tree check catches a moved base on its
  own, so the replay has two independent guards.
- **The engine, not the agent, binds a preparation to its head and
  result.** Pre-push review found that `git commit --amend --no-edit` keeps
  author, date, and message, so an amended head passes the replay's
  identity check and the replay would land the old head's resolved content.
  A second round found the same hole through an earlier preparation's
  commit. Each `prepare` run now deletes `refs/land/prepared/<pr>/head` and
  `/commit`, and a clean prepare writes both. On a conflict the engine never
  sees the resolved commit, so `prepare --worktree` records it after the
  agent's `rebase --continue`, once the worktree's marker matches the head
  and onto. `land --prepared` reads and deletes both refs and ignores the
  preparation unless they are `--head` and `--prepared`. Chose refs over a
  `--prepared-from` flag because the agent would supply the flag from the
  same memory whose slip it guards against.
- **Rejected: `git rerere`.** It matches conflict hunks fuzzily, replays
  only those hunks rather than the reviewed result, and writes shared
  `rr-cache` state into the clone that outlives the batch.
- **Clean rebases compare trees after the push.** A clean rebase whose tree
  differs from the preparation still pushes and stops `rebased`, as before,
  with `"prepared":"tree-mismatch"`. Only a conflict replay is checked before
  the branch moves, because only there does the run write content of its own.
- **Cleanup tracking is a local file, not a lock-commit field.**
  `land.sh` appends each merged PR to
  `<git-common-dir>/land-approved-prs/cleanup-pending`, and `list-ready.sh`
  reports and clears it. The lock is a poor home: the owner's `--release`
  deletes it, and a dead lander's stale lock is exactly when the list is
  needed. The file lives beside the push log and survives a release.
- **Prepared worktrees reuse the `land-wt.XXXXXX` template.** merge-cleanup's
  worktree sweep already keeps and reports detached `land-wt` worktrees, so it
  needed no change. A `prepare` marker file beside `wt` names the PR.
- **`drop` is the only remover, and it is narrow.** It is the new destructive
  path. It removes a worktree only when the resolved path ends in `/wt` under
  an exact `land-wt.XXXXXX` directory, the worktree is registered and
  detached, and the marker names this PR. A land run's own scratch worktree
  (no marker), a branch worktree, another PR's preparation, and a path outside
  the template all stop `not-prepared`. It reads nothing from the forge, so a
  forge outage can't strand a worktree.
- **The steps live in `references/prepare-next.md`.** Preparation runs only
  where the platform can read a background command's output, so it is a
  conditional branch, the kind of text the 2026-11-22 note says may sit
  behind a pointer. `SKILL.md` keeps the rules that every run needs (cleanup
  order, `--cleaned`, Recovery) and stays at #440's 4,386-word budget.

## Refute-First Findings

A fresh-context reviewer tried to break `drop` and the replay, in three
rounds. The third found no blocker.

- **Confirmed, fixed:** an amended head, or an earlier preparation's
  commit, lands old content (above).
- **Confirmed, fixed:** `landed-since.sh --through` walked the first-parent
  line of A's head, which skips the base commits a merge of main into A's
  branch brought in. It now walks the fetched tip's stretch and the stretch
  past it separately.
- **Confirmed, fixed:** a caller's `rebase.backend=apply`, `rerere` with
  `autoUpdate`, or waiting `GIT_EDITOR` made the replay fail or hang. The
  engine's rebases now pin the merge backend and turn `rerere` off, and the
  replay's continue sets `GIT_EDITOR=true`.
- **Allowed:** continuing a conflicted pick strips message lines that start
  with `#`, so such a commit's identity check fails and the run takes the
  ordinary conflict path. Keeping them would also keep git's own comment
  lines.
- **Confirmed, fixed:** `prepare` created a missing local branch before its
  `--onto` checks, and only two results reported it. It now creates the
  branch after them, and every later stop carries `created_branch`.
- **Allowed:** `--cleaned` rewrites the cleanup file by rename, so an append
  from A's merge in the same millisecond is lost. The file only matters
  after a crash, and the agent holds A's `OK land` anyway.
- **Allowed:** `drop` removes a marked prepare worktree that someone
  switched to a branch mid-rebase. That needs a deliberate `git switch`
  inside it, and the branch survives.
- **Allowed:** `landed-since.sh --through` accepts any descendant of the
  tip. Passing anything but A's head is a caller error.
- **Allowed:** the cleanup file holds bare PR numbers, so a clone landing
  into two repositories mixes them. merge-cleanup stops `pr-not-merged`
  unless the PR merged in `--repo`, so a stray number can't clean up an
  open PR.
- **Disproved by trace:** a replay can't revert a base change. The base
  tree, each pick's prior tree, and the final tree are all pinned.

Development also found that a test's `git -C "$PWT"` with an empty `$PWT`
ran in the checkout and amended its tip. The three lander suites now run
from their scratch directory, and the conflict scenarios stop when
`prepare` reports no worktree.

Revisit when a forge or merge setting makes a merge commit's tree differ from
the merged head's tree. Every preparation would then fall back to `rebased`,
which is safe but saves nothing.
