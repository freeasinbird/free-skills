# Sweep Merged Branches' Worktrees on the Owner's Word

Chose a separate script, `skills/merge-cleanup/worktree-sweep.sh`, that the
owner runs after a batch of landings, over removing worktrees inside
merge-cleanup or the lander. Issue #310 carries the contract. This note
records why the rules hold, the prefix finding, the one departure from the
contract, and the refute-first findings.

## Decisions

- **Owner-run, never on a normal path.** Removing a worktree deletes files:
  `git worktree remove` without `--force` takes ignored and index-flagged
  files with exit 0, and with `--force` takes untracked and modified ones.
  Merge-cleanup and the lander keep refusing to remove any worktree; the
  skill text runs the sweep only when the owner asks in that session.
  Rejected: removal inside merge-cleanup after `head-worktree-present`, which
  would make every cleanup request a deletion request.
- **Two flags, one `--force`.** A dry run is the default. `--remove` removes
  only clean candidates, and dirty ones need `--remove-dirty` as a second,
  separate word. The dirty removal passes `--force` once, so git's own refusal
  still protects a locked worktree even on a git that doesn't print the
  `locked` field; the matrix showed a sweep with the field read removed stops
  `remove-failed` rather than deleting.
- **Clean is the inventory's verdict plus no paused operation.**
  `worktree-inventory.sh` already finds every file `git worktree remove`
  hides, but stops without naming them, so the sweep reads the file lists
  itself and either reader finding something makes a worktree dirty. The
  inventory doesn't probe for a paused merge, rebase, cherry-pick, revert, or
  bisect, whose state removal deletes, so the sweep adds merge-cleanup's
  `op_probe`.
- **`land` gains a `land-wt` template.** At `bdc7885` `land.sh` created its
  rebase worktree with a bare `mktemp -d`, so a dead lander's worktree sat at
  an anonymous `tmp.XXXXXX/wt` that nothing could tell from any other
  detached worktree. It now uses `${TMPDIR:-/tmp}/land-wt.XXXXXX/wt`, pinned
  by `test-land.sh`, and the sweep accepts only `<dir>/land-wt.XXXXXX/wt`
  with six alphanumerics, as mktemp fills it. Every other detached worktree
  is kept.
- **Never a candidate:** the primary checkout, the worktree the sweep runs
  in, a locked worktree, a `prunable` entry (reported, never pruned), a branch
  that isn't an ancestor of the base, a branch ref that no longer resolves,
  and a detached worktree outside the template. The refute-first pass and
  review added six more, listed below: a worktree holding another registered
  worktree, a submodule repository, or a nested repository, one on the base's
  own branch, one git can't open, and one git resolves to another working
  tree.
- **Read everything, then remove.** The first pass classifies every worktree,
  so a failed read stops the run with nothing removed. Each removal then
  reclassifies its worktree from a fresh `git worktree list`, and afterwards
  confirms the entry and directory are gone. The recheck narrows a race with
  another process; it doesn't close it, and the skill text says so.

## Departure From the Contract

- **A dirty branch candidate with no landing merge is never removed.** The
  contract makes every ancestor branch a candidate and lets
  `--remove --remove-dirty` remove the dirty ones. A branch just cut from the
  base tip, with uncommitted work and no commits yet, is an ancestor too, and
  looks exactly like a fast-forwarded branch. The first dry run on this
  machine listed two such worktrees, both concurrent sessions' work in
  progress, as dirty candidates. The sweep now removes a dirty branch
  candidate only when it finds the landing merge (a first-parent merge of the
  base whose second parent is the tip). A clean one is still removable,
  since nothing on disk is lost; a fast-forward project can still sweep
  clean worktrees and must remove dirty ones by hand. The owner reviewed this
  departure on 2026-10-18 and chose to keep it over the contract's wording.

## Refute-First Findings

A fresh-context reviewer tried to make the sweep delete something it
shouldn't, reproducing each claim with real git; the PR's automated review
added the last five confirmed ones. Each confirmed finding has a matrix case
that fails against a copy of the sweep without its guard.

- **Confirmed, fixed: a nested worktree died with its parent.** A worktree
  registered inside a dirty candidate was deleted by the parent's `--force`
  removal, even when locked. A worktree holding another is now
  `holds-worktree`.
- **Confirmed, fixed: a submodule's unpushed commits died unreported.** The
  submodule's repository lives in `modules/` under the worktree's git
  directory, and `ignore = all` hides it from status. It also outlives
  `submodule deinit` and `git rm`, which leave status clean. A worktree whose
  git directory holds `modules/`, or with an embedded submodule `.git`, is
  now `holds-submodule`; status also runs with `--ignore-submodules=none`.
- **Confirmed, fixed: `core.worktree` redirected every read.** A per-worktree
  `core.worktree` made the sweep and the inventory inspect a decoy, and plain
  `--remove` then deleted an ignored file. A candidate must now be its own
  `--show-toplevel`, else `redirected` or `unreadable`.
- **Confirmed, fixed: an exported `GIT_DIR` read another index.** The sweep
  unsets `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, and `GIT_COMMON_DIR`.
- **Confirmed, fixed: a detached HEAD no ref held was "clean".** Plain
  `--remove` orphaned a commit made in a `land-wt` worktree. Such a HEAD now
  makes the candidate dirty, named in `unreferenced_head`.
- **Confirmed, fixed: the base branch's worktree was a candidate.** In a bare
  layout, the owner's checkout of `main` was removable. It is now
  `base-branch`.
- **Confirmed, fixed in part: a dry run could write.** `git status` refreshes
  the index; `GIT_OPTIONAL_LOCKS=0` now stops that write here and in the
  inventory.
- **Confirmed, fixed: any `land-wt.` suffix matched the template.** The
  sweep accepted `land-wt.?*`, so an owner's own detached worktree at
  `land-wt.personal/wt` was a candidate. Only mktemp's six-alphanumeric fill
  matches now.
- **Confirmed, fixed: a slash in a remote's name hid the base branch.** With
  `--base up/stream/main`, stripping one path segment named
  `refs/heads/stream/main`, so `main`'s own worktree was a removable
  candidate. The longest configured remote name is stripped now.
- **Confirmed, fixed: the recheck didn't reach the report.** A worktree that
  turned dirty or switched branches between the first pass and its removal
  kept its first-pass branch and counts, so the result line contradicted the
  worktree lines. Both now follow the recheck.
- **Confirmed, fixed: a nested repository died under `--remove-dirty`.** An
  untracked or ignored clone inside a candidate showed only as its directory
  in the file lists, or not at all under an ignored directory, so its
  commits went with the forced removal. Any `.git` below the root now makes
  the worktree `holds-repository`.
- **Allowed: a dry run runs the repository's clean filters.** `git status`
  runs a configured `filter.<name>.clean`. Those are the owner's own
  settings in the owner's own repository, the same trust every git command
  there extends, and the inventory already runs status. Only fsmonitor stays
  disabled, as in the inventory.
- **Allowed: a branch cut at a landed tip borrows its landing merge.** A new
  branch made from a merged branch's tip, with uncommitted work, is credited
  with that merge, so `--remove-dirty` removes it. Topology can't tell the
  two apart, and the line lists every file and the merge's subject, which
  names the other branch.
- **Allowed: a refused `--force` removal can leave files half-deleted.** Git
  deletes before it fails; the run still stops `remove-failed`.
- **Disproved:** bash 3.2 (the matrix passes under macOS `/bin/bash`), rename
  and copy records in `status -z`, paths holding tabs, globs, spaces, or a
  leading dash, a `!` alias exporting `GIT_DIR`, and lock handling.

Revisit when `prunable` entries from macOS's `TMPDIR` cleanup become common,
or when a project that lands by fast-forward needs to sweep dirty worktrees.
