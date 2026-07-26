# Verified Hazards

The git mechanics the guards in `SKILL.md` defend against, and how each was
verified. Every decision lives in `SKILL.md`: an agent that never opens this
file makes the same choices. Read a section when its guard looks removable,
when a review re-litigates one, or when re-checking a mechanic against a new
git version. Each section is cited from the rule it justifies as
`references/hazards.md` followed by the section marker.

---

## §merged-not-ancestor

`git branch --merged <base>` lists only branches whose tip is an ancestor of
that base. That holds for a merge-commit or fast-forward merge, but not for a
squash or rebase merge, where the just-merged branch's tip never becomes an
ancestor of the base.

Relied on by the identify section (the `--merged` fallback), the verify
section (what counts as verification in a squash- or rebase-merge repo), and
step 4 (when `-D` is the correct deletion).

---

## §tag-shadow

Two distinct bare-name resolution holes, both reachable just before a
deletion:

- A bare name tail-matches other refs in `git ls-remote`: the pattern
  `<branch>` also matches `bar/<branch>`.
- Elsewhere, revision lookup tries `refs/tags/` before both `refs/heads/` and
  `refs/remotes/`, so a stray or malicious tag named `<branch>` or
  `<base-remote>/<base-branch>` resolves ahead of the real ref.

A bare fetch or pull refspec is exposed the same way.

Relied on by the identify section (fully qualify every ref a guard resolves
or compares), step 1 (accepting the `ls-remote` result only when it is
exactly one line), and step 3 (the qualified fetch refspec).

---

## §checkout-detach

`git checkout` is the one command that cannot be fully qualified:
`git checkout refs/heads/<branch>` detaches `HEAD` instead of switching to
the branch. The bare form prefers a local branch only when one exists; with
no local branch and a same-named tag, `git checkout <base-branch>` detaches
`HEAD` at the tag.

Relied on by the identify section (the qualification exception) and step 2
(the local-branch-exists switch and the detached-`HEAD` confirmation).

---

## §worktree-refusals

With the base branch, or `<branch>` itself, checked out in another linked
worktree, three steps of the sequence refuse, all verified against git:

- `git checkout '<base-branch>'` refuses with "already used by worktree".
- A fetch or merge into the base branch refuses with "refusing to
  fetch/update into branch checked out at ...".
- `git branch -d '<branch>'` refuses while `<branch>` is still checked out in
  a worktree.

Relied on by the worktree preflight.

---

## §ignored-file-overwrite

`git status --porcelain` does not report ignored files, and both the checkout
and the fast-forward update ignored files by default. Verified in a scratch
repo, against an ignored `.env` that the base branch still tracks:

- A plain checkout replaced the ignored file with the base's copy;
  `--no-overwrite-ignore` aborts the checkout instead.
- A plain `git pull --ff-only` replaced it the same way, while
  `git merge --ff-only --no-overwrite-ignore` aborts and preserves it;
  `git pull` itself rejects `--no-overwrite-ignore`.

Relied on by step 2 (both switches) and step 3 (the resync).

---

## §status-config

A status read inherits repository configuration, so the repository a guard
protects can switch that guard off. Verified in scratch repos on git 2.50.1,
with `status.showUntrackedFiles=no` set in the repository config:

- `git status --porcelain` and `git status --porcelain --ignored` both came
  back empty on a worktree holding an untracked file and an ignored `.env`.
  `-uall` restored both listings.
- `git worktree remove` then deleted that worktree with exit 0, the
  untracked-file refusal described above having stopped firing too; under the
  default configuration the same removal refused with exit 128.

Relied on by step 2 (the dirty-tree check) and the worktree preflight (the
inventory), which pass `-uall` explicitly for this reason.

---

## §branch-d-upstream

`git branch -d` checks the branch against its _upstream_ when one is set, and
against `HEAD` only when none is. Cleanup prunes a step later, so the
not-yet-pruned `<head-remote>/<branch>` usually still contains the tip and
satisfies that check.

Relied on by step 4 (why the step runs its own merge check first).
