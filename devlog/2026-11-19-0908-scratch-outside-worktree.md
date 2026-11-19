# Keep Scratch Files Out of the Worktree

Agents leave throwaway scripts and temporary output in a PR's worktree, and
the merge-cleanup sweep then keeps that worktree as dirty. The owner reported
these leftovers as the main reason worktrees pile up. Their names can't be
known in advance, so no declaration of removable paths covers them. This
change prevents them instead: the finish line now says where scratch goes,
and §handing-off step 7 checks for a clean worktree before the report.

## Decisions

- **Chose prevention over cleanup for untracked leftovers.** The owner and a
  two-member council (Fable and Sol 6.1) agreed that an untracked file is
  never safe to delete automatically, since it may be real work. The sweep
  keeps treating it as dirty. A dry run followed by
  `--remove --remove-dirty` already clears leftovers in existing worktrees
  once the owner has read the list.
- **Chose a rule at step 3 over relying on the step 7 check alone.** The
  canonical text said nothing about scratch files before handoff, so agents
  in downstream projects first heard of it after the files existed. A
  session that ends before step 7 never runs the check. The rule names a
  session workspace or a temporary directory, since not every platform has
  a session workspace.
- **Kept "your own" in the step 7 cleanup.** An agent can't always tell its
  scratch from a file the owner created in the worktree. It deletes only
  what it created and reports the rest under **Left for you**.
- **Deferred the optional pre-push hook to #434.** It refuses every
  push from a worktree with uncommitted changes, including legitimate
  mid-work pushes, and its install rules took three review rounds. The step 3
  rule and the step 7 check cover the problem without it.

The check skips ignored files, so scratch written into an ignored directory
passes it and still keeps the worktree later. Checking with `--ignored` would
also flag every build directory, so the step 3 rule carries that case.

This splits #405: its handoff half lands here, and the sweep half, which
lets declared build output be removed, follows in its own PR.

Revisit when worktrees still pile up from untracked leftovers after agents
follow both steps.
