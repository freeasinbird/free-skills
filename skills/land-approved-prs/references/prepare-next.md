# Prepare the Next PR

## §prepare-next

While PR A's `land` waits on CI, prepare the next ready PR B against A's
pushed head, so that after A merges one `land` run rebases, pushes, waits on
CI, and merges B. Preparation moves work into the wait; it changes nothing
you judge. Read B, apply the rework rule, review, comment, and hand back
exactly as `SKILL.md` says.

### When to Prepare

Prepare B only when all of these hold:

- **The platform can run a command in the background** and let you read its
  output while it runs. Otherwise skip this file and take the ordinary path.
- **A's `land` printed `land.sh: waiting for CI on <oid>`** to stderr. That
  OID is A's pushed head, the `--onto` below. The first PR of a batch is
  never prepared.
- **B is the next ready PR** on the list you took A from, and its head is in
  the same repository.

Run the steps below one at a time while A's `land` waits. They share its
clone, so never run two of them at once.

### During A's Wait

1. **Clean up the previous merge,** if one is pending, as "After the Merge"
   in `SKILL.md` says, then clear it with `list-ready.sh --cleaned <n>`.
2. **Read B against what will have landed.** Read B as step 1 of "One PR"
   says, then run `landed-since.sh` with `--through` set to A's pushed head.
   The range then includes A, so read A's diff too. When B doesn't hold, or
   holds only with rework, don't prepare it: rework pushes, so it waits for
   the ordinary path after A merges.
3. **Prepare B** with the pinned head from the list. `prepare` never pushes,
   never moves an existing branch, and never touches the primary checkout.
   When B has no local branch, it creates one at the pinned head, only if the
   head remote's branch is that commit.

```sh
<skill-dir>/landed-since.sh --repo <owner/name> --pr <B> --through <A's head>
<skill-dir>/land.sh prepare --pr <B> --repo <owner/name> --head <B's head> --onto <A's head>
<skill-dir>/land.sh prepare --pr <B> --repo <owner/name> --head <B's head> --onto <A's head> --worktree <path>
<skill-dir>/land.sh drop    --pr <B> --repo <owner/name> --worktree <path>
```

Act on what `prepare` returns:

- **`OK prepare`:** Read the range-diff on stderr as you would after
  `rebased`. Keep `prepared_oid`.
- **`STOP rebase-conflict`:** The rebase is paused in the reported
  `worktree`. Resolve it there under the rework rule, taking only hunks the
  landed change dictates, then run `GIT_EDITOR=true git rebase --continue`
  there. Record the result with `prepare --worktree <path>`; its `OK prepare`
  gives the `prepared_oid` to keep and prints the range-diff to stderr. Get
  the resolution reviewed as "Reviewing Rework" says, from that range-diff.
  If a hunk has two defensible resolutions, abort the rebase, `drop` the
  worktree, and hand B back after A's `land` returns. When the landing record
  names an automated reviewer, don't resolve a conflict here: it can't review
  a commit that was never pushed, so `drop` the worktree and take the
  ordinary path.
- **Any other `STOP` or a `LOOKUP_FAILED`:** Discard the preparation, `drop`
  any worktree it reported, and take the ordinary path after A merges. A
  `prepare` result is never a reason to hand B back.

Preparation never comments, labels, hands back, or pushes. Act on what it
found only after A's `land` returns.

### After A's Land Returns

- **`OK land`:** List again. If B is the first ready PR and its `head_oid` is
  the head you prepared, run `check` on it, then start its `land` with
  `--prepared <prepared_oid>`. Once that run prints its CI-wait line, clean
  up A and prepare the PR after B the same way.
- **Anything else:** When A stopped, was handed back, or lost approval, or
  the fresh list's first ready PR or its head isn't the one you prepared,
  discard the preparation, `drop` its worktree, and take the ordinary path.

`drop` removes only a worktree `prepare` made for that PR. Use it on a kept
conflict worktree once B's `land --prepared` returns, too. Never remove a
prepared worktree any other way.

### Reading a Prepared Land

`land --prepared` uses the preparation only when `--head` and `--prepared`
are the latest preparation's head and `prepared_oid`, and the fetched base
has the tree of the commit B was prepared onto. A newer head, an earlier
preparation, or a base that moved by more than A's merge makes the run
behave as without `--prepared`.

- **A result with `pushed_head`:** The engine pushed. Record `pushed_head`
  with `list-ready.sh --pushed` before anything else; it is now the pinned
  head, and `old_head_oid` is the head before it. Then act on the result as
  `SKILL.md` says.
- **`OK land`:** The rebase reproduced the prepared tree, so your reads of
  it stand. Comment as for any rebase, naming a conflict you resolved.
- **`STOP rebased` with `"prepared"`:** Handle it as `rebased`. The value
  `tree-mismatch` means the rebase differs from the preparation; `ignored`
  means the head or preparation changed or the base moved past A's merge.
- **`STOP rebase-conflict` saying the prepared resolution didn't replay:**
  Handle it as `rebase-conflict`. The branch is unchanged and nothing was
  pushed.
