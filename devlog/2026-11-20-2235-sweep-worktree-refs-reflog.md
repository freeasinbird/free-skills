# Worktree Sweep Counts Per-Worktree Refs and Post-HEAD Reflog Commits as Dirty

Chose to count resolvable per-worktree refs (`refs/worktree/*` and
`refs/bisect/*`) and unreferenced commits from post-HEAD `HEAD` reflog entries
as dirty inside `skills/merge-cleanup/worktree-sweep.sh`, over leaving both as
accepted risks or scanning the entire `HEAD` reflog. Issue #432 carries the
contract.

This supersedes two accepted-risk entries without editing those frozen notes:

- **`2026-11-18-2346-cleanup-removes-clean-head-worktree.md`** accepted that a
  commit held only by `refs/worktree/*`, `refs/bisect/*`, or the worktree's
  `HEAD` reflog was lost when `merge-cleanup.sh` removed a clean head worktree.
- **`2026-11-18-1944-default-landed-sweep.md`** allowed the `HEAD` reflog case
  under `--remove-landed`.

## Decisions

- **Keep `refs/worktree/*` and `refs/bisect/*` always dirty.** The owner
  decided this on 2026-11-20. Any resolvable ref in either per-worktree
  namespace marks the candidate dirty and lists it in `"worktree_refs"`.
  `git -C "$path" for-each-ref --format='%(refname)' refs/worktree/ refs/bisect/`
  isolates each worktree from siblings and the primary checkout. It also works
  on both `files` and `reftable` backends and on Git versions older than 2.45
  (which lack `git refs list`).
- **Scope the `HEAD` reflog check to entries after `HEAD` first reached its
  current commit.** The owner chose this on 2026-11-20 over scanning the full
  `HEAD` reflog. Ordinary pre-merge `git commit --amend` and `git rebase`
  operations leave unreferenced commits earlier in `logs/HEAD`, so a full
  reflog scan would mark almost every merged PR worktree dirty.
- **Exclude doomed per-worktree refs and sibling `HEAD`s from reachability.**
  Post-`HEAD` reflog OIDs are checked with
  `git -C "$path" rev-list --stdin --not --single-worktree --exclude='refs/worktree/*' --exclude='refs/bisect/*' --all`.
  Excluding both namespaces prevents `$path`'s doomed refs from hiding an
  unreferenced reflog commit. Passing `--single-worktree` prevents a sibling
  worktree's detached or prunable `HEAD` from counting as a surviving ref.
  Skipping `$head_oid` avoids duplicating a detached unreferenced `HEAD`
  already reported in `"unreferenced_head"`.
- **Guard absent, empty, symlinked, and unreadable `HEAD` reflogs.** Under the
  `files` backend, an empty or unreadable `logs/HEAD` causes
  `git rev-list -g HEAD` to fall back to the branch's shared reflog, while
  `git reflog exists HEAD` returns 1 on a symlinked `logs/HEAD` even though
  `rev-list -g HEAD` reads it. Checking `logs/HEAD` on disk first and falling
  back to `git reflog exists HEAD` when absent handles `files`, symlinks, and
  `reftable`, keeps absent reflogs clean, and fails loud on unreadable files.
- **Implement once in `inspect()`.** Every sweep mode (`dry-run`, `--remove`,
  `--remove --remove-dirty`, `--remove-landed`, and `--remove-head`, including
  `merge-cleanup.sh` and `land-approved-prs`) and every pre-removal recheck
  inherits both guards. Adding both array counts to `found` prevents
  `.DS_Store` or `.worktree-disposables` entries from overriding them toward
  clean.

## Accepted Risks

- **Unreferenced commits discarded before `HEAD` first reached its current
  commit remain allowed.** In `logs/HEAD`, a commit discarded before the merged
  tip looks identical to a pre-merge `git commit --amend` or `git rebase`. The
  owner accepted this on 2026-11-20.
- **Broken symbolic refs under `refs/worktree/` or `refs/bisect/` are
  skipped.** `git for-each-ref` ignores a symref whose target does not exist; a
  broken symref holds no commit.
- **A commit held only by another linked worktree's `refs/worktree/*` reads
  dirty.** `git -C "$path" rev-list --all` cannot see a sibling worktree's
  private refs, so `$path` conservatively stays dirty rather than deleting a
  commit it cannot verify is safe.
- **Leftover `refs/rewritten/*` after a crash or deleted `rebase-merge` is out
  of scope.** Normal `git rebase` operations (`--continue`, `--abort`,
  `--quit`) delete `refs/rewritten/*`, and `op_probe` already flags an active
  rebase. Issue #432 scopes `worktree_refs` to `refs/worktree/*` and
  `refs/bisect/*`.

## Refute-First Findings

An independent pre-push reviewer (Claude Opus 5.5, High effort) tested the
change against real Git repositories and reported no blocking findings.

- **Confirmed and fixed: symlinked `logs/HEAD` read as absent.** Checking
  `git reflog exists HEAD` before the file test returned 1 on a symlinked
  `logs/HEAD` under `files`, letting a post-`HEAD` commit pass as clean and
  leaving the symlink check unreachable. Fixed by checking `logs/HEAD` on disk
  first and falling back to `git reflog exists HEAD` only when absent, plus
  adding symlinked and unreadable `logs/HEAD` test cases.
- **Confirmed and fixed: sibling prunable `HEAD` counted as surviving.**
  Without `--single-worktree`, `git rev-list --all` included a prunable
  detached sibling worktree's `HEAD`, hiding a post-`HEAD` commit that
  `git worktree prune` would later drop. Fixed by passing `--single-worktree`
  and adding a prunable-sibling test case.
- **Confirmed and fixed: missing `reftable` test case and narrow comment.**
  Added a `reftable` scenario covering `refs/worktree/*`, `refs/bisect/*`,
  isolation, and post-`HEAD` reflog commits, and clarified the `logs/HEAD`
  guard comment.
- **Allowed by decision: `refs/rewritten/*` outside an active rebase.**
  Reaching a stray `refs/rewritten/*` without `rebase-merge` requires a crash
  or manual deletion; kept outside #432's contract and noted under Accepted
  Risks.
- **Allowed by decision: earlier abandoned work and undone pre-merge rebases.**
  Commits discarded before `HEAD` first reached its merged tip stay clean, and
  an undone rebase (`git rebase` followed by `git reset --hard ORIG_HEAD`)
  conservatively reads dirty. Both follow directly from the owner's 2026-11-20
  boundary.
- **Disproved by checks: isolation, nesting, odd refs, missing objects, JSON,
  temp cleanup, modes, and disposables.** Sibling and primary `refs/worktree/*`
  never taint candidates; nested names exclude cleanly under both `files` and
  `reftable`; blob/tree refs, dangling symrefs, and pruned reflog objects do
  not break `inspect()`; JSON escaping and `"reason"` field order hold for
  `merge-cleanup.sh`; temp files clean up on every error path; disposables
  never override either guard; and all sweep modes plus pre-removal rechecks
  inherit both guards under bash 5.3 and `/bin/bash` (3.2).

Revisit when Git exposes a native worktree-reflog-only query without branch
reflog fallback, or if `refs/rewritten/*` needs standalone tracking outside
active rebases.
