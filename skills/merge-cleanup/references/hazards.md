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
or compares), step 1 (why the `ls-remote` pattern is qualified at all), and
step 3 (the qualified fetch refspec).

---

## §push-refspec-ambiguity

Git suffix-matches a push destination against the remote's refs, so a sibling
ref that ends in the same components makes the delete inexpressible rather
than merely noisy. Verified in scratch repos on git 2.50.1, against a bare
remote holding both `refs/heads/feat` and a decoy literally named
`refs/heads/refs/heads/feat`:

- `git ls-remote --heads <remote> 'refs/heads/feat'` returned both refs, so
  the qualified pattern is not an exact match and the ref column has to be
  compared as a whole string.
- `git push <remote> --delete --force-with-lease=... 'refs/heads/feat'` and
  `git push <remote> :refs/heads/feat` both failed with "error: dst refspec
  refs/heads/feat matches more than one", exit 1, leaving every remote ref in
  place. Removing the decoy made the identical delete succeed.

No push refspec expresses the delete while the decoy exists, and a forge-API
ref delete would run neither the OID comparison nor the lease, so this is a
stop rather than a workaround.

Relied on by step 1 (the whole-string ref-column comparison and the
suffix-match stop).

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

## §leading-hyphen-args

Quoting a name protects it from the shell, not from git: a value beginning
with a hyphen reaches git's own option parser and is read as an option there.
Verified in scratch repos on git 2.50.1 (Apple Git-155), against a ref named
`-x` and a remote named `-x`:

- The shape is reachable. `git branch -- -x` refuses ("is not a valid branch
  name", exit 128), but `git check-ref-format refs/heads/-x` accepts it
  (exit 0) and `git update-ref refs/heads/-x <oid>` creates it, after which
  `git branch --list` shows it like any other branch. A forge creating refs
  through its API is under no stricter constraint than `update-ref`.
- `git checkout` has no safe spelling for such a name. The bare form fails
  with an "unknown switch" error (exit 129); `git checkout -- -x` reads the
  name as a pathspec ("did not match any file(s) known to git", exit 1); the
  qualified form succeeds and detaches `HEAD` (§checkout-detach). `HEAD`
  stayed on `main` through both failures, so what checkout produces is a base
  branch it cannot switch to, not a silent wrong switch. The creating form
  refuses too: `checkout -b -x main` consumes `-x` as the argument of `-b` and
  then rejects the name (exit 128).
- `git switch` does have one, and keeps the guards checkout's form carries.
  `git switch --no-overwrite-ignore -- -x` attached `HEAD` to the branch
  (exit 0, `symbolic-ref` reporting `refs/heads/-x`): `--` is end-of-options
  there, not a pathspec marker, and the flag is accepted. Against a branch
  that started tracking a path the worktree held as an ignored file, plain
  `git switch` overwrote it while the `--no-overwrite-ignore` form aborted
  (exit 1) with the file and `HEAD` intact, matching `git checkout`
  identically (§ignored-file-overwrite). It also refuses a same-named tag
  ("a branch is expected, got tag", exit 128) instead of detaching, and
  refuses a branch held by another worktree (exit 128). `switch -c` still
  rejects the name at creation (exit 128), so the local branch has to arrive
  by fetching `refs/heads/-x` straight into itself, which succeeded and left
  the branch switchable.
- That fetched-into-place branch starts with no upstream, where the `-b` form's
  has one. In an ordinary clone
  `checkout -b feat2 refs/remotes/origin/feat2` set `branch.feat2.remote` and
  `.merge` by itself, while fetch-then-switch left both unset and
  `git pull --ff-only` then failed with "There is no tracking information for
  the current branch" (exit 1).
- An untracked base branch is worse than unconfigured, which is why the
  tracking is set rather than left to the clone. In a clone made
  `--single-branch --branch main`, whose fetch refspec covers only `main`, a
  local `-x` fetched into place carried no upstream, and
  `git branch --set-upstream-to` refused to give it one ("not a branch",
  exit 128) because the branch falls outside that refspec.
  `git pull --ff-only` on
  that branch then fetched what the configured refspec names, `main`, rather
  than the branch: with the two diverged it aborted ("Not possible to
  fast-forward", exit 128), and with the branch an ancestor of `main` it
  **fast-forwarded the local `-x` onto main's tip at exit 0**, leaving remote
  `-x` where it was. `checkout -b` leaves the branch equally untracked in that
  clone shape, so this is not specific to the hyphen path. Writing
  `branch.<name>.remote` and `branch.<name>.merge` directly works in every
  clone shape (the pull then reported fetching `-x` and was correct), and is
  what `--set-upstream-to` writes where it succeeds.
- Half a tracking pair behaves exactly like none, which is why the check reads
  both keys. In the same clone, with `branch.-x.remote` set and
  `branch.-x.merge` absent, `git pull --ff-only` still fast-forwarded local
  `-x` onto main's tip at exit 0 while remote `-x` stayed put; the reverse half
  (`merge` set, `remote` absent) did the same. A check reading one key returns
  success on both of those states, including the one an interruption between
  the two writes leaves behind.
- `git switch` is the one command the sequence needs that a still-supported git
  may lack (it arrived in 2.23), and step 1 deletes the remote branch before
  step 2 would reach it. The probe is unambiguous: `git switch -h` prints the
  usage and exits 129 where the command exists, while an absent subcommand
  reports "is not a git command" and exits 1 (checked against a deliberately
  bogus `git switchx -h`).
- Every other site is terminable. `git branch -d -- -x` and its forced form
  `git branch -D -- -x` both deleted the ref (exit 0), where each without the
  terminator is an "unknown switch"; with a remote named `-x`,
  `git ls-remote --heads -x`,
  `git fetch -x <refspec>`, and `git fetch --prune -x` each failed with an
  "unknown switch" error (exit 129) while the `--` form of all three
  succeeded. `git worktree remove -- -wt` removed a hyphen-named worktree.
- The terminator changes nothing for ordinary names: `ls-remote`, both fetch
  forms, and
  `git push --delete --force-with-lease=<ref>:<oid> -- <remote> <ref>`
  behaved as they did without it, and that push still refused a stale lease
  with "stale info" (exit 1), leaving the remote ref in place.

So no name shape is a stop: qualification carries the ref sites, `--` carries
the positional remotes and bare refs, and `git switch` carries the one switch
`git checkout` cannot spell. The skill still uses `git checkout` everywhere
else, since `git switch` is documented as experimental (git 2.50.1) and a
second switching command earns its place only where the first cannot express
the name.

Relied on by the identify section (the pass-`--` rule and the checkout
exception), the pre-step-1 `git switch` availability check, step 2 (the
`git switch` path for a hyphen-leading base, its two-refspec fetch, and the
upstream check that follows either landing path), the worktree preflight (the
terminated removal), and the terminators in steps 1, 3, 4, and 5.

---

## §worktree-refusals

With the base branch, or `<branch>` itself, checked out in another linked
worktree, three steps of the sequence refuse, all verified against git:

- `git checkout '<base-branch>'` refuses with "already used by worktree".
- A fetch or merge into the base branch refuses with "refusing to
  fetch/update into branch checked out at ...".
- `git branch -d -- '<branch>'` refuses while `<branch>` is still checked out
  in a worktree (re-verified in the terminated form the identify section now
  requires).

Relied on by the worktree preflight.

---

## §worktree-remove-destroys

`git worktree remove` refuses on a worktree that "contains modified or
untracked files", which reads like a fail-safe and is not one. Verified in
scratch repos on git 2.50.1:

- An ignored file does not trip the refusal at all, so a worktree holding
  only a gitignored `.env` reads as clean and is deleted with the directory.
- A tracked file carrying `assume-unchanged` or `skip-worktree`, then edited,
  is reported by neither `git status -uall --porcelain` nor its `--ignored`
  form nor `git diff`, while `git ls-files -v` marks it (`h` and `S`
  respectively). Removal destroyed both files with exit 0.
- Running the removal from inside the worktree being removed also exits 0:
  git unlinks the directory and the shell is left on a path that no longer
  exists.
- The flag alone is not the hazard, the flag on a path that is still there
  is: a sparse checkout marks every excluded path `S` while leaving it absent
  from disk. A sparse worktree reported `S` for its excluded file with the
  path gone, a clean `status -uall --porcelain --ignored`, and removal
  completing at exit 0, so an unconditional stop on `S` would refuse every
  sparse worktree. `git ls-files -v` also prints every ordinary cached file
  as `H`, so both halves of the filter are load-bearing.
- The rows are relative to the worktree they describe, not to the caller.
  Inventorying a sibling worktree from the base checkout, an
  assume-unchanged edit to a file that exists only on the feature branch gave
  the row `h only-on-feat.txt`; testing that spelling from the base checkout
  reported absent while the same test prefixed with the worktree path
  reported present, and `status -uall --porcelain --ignored` was empty
  throughout. `--full-name` keeps the rows root-relative even when the `-C`
  target is a subdirectory (`f.txt` becomes `sub/f.txt`), so prefixing with
  the worktree root is then the complete anchor.
- Reading that listing without `-z` reopens the hole it was meant to close.
  `git ls-files -v` C-quotes a path holding a newline or tab (observed as
  `"odd\nname"` and `"odd\ttab"`), so an existence test against the printed
  spelling fails and drops the row; `-vz` printed both paths raw. A dangling
  symlink fails `[ -e ]` while remaining a directory entry that removal
  takes, so the presence test also asks `[ -L ]`. In the same repository, an
  assume-unchanged edit to each of those three paths left
  `status -uall --porcelain` empty, so nothing else would have caught them.
- The tag space was enumerated once rather than narrowed finding by finding:
  in a default `-v` listing, `H` is an ordinary cached file, any lowercase
  tag (`h`, `s`) means assume-unchanged, `S` means skip-worktree, and `M`
  marks an unmerged path, which the status read reports independently
  (`UU`). The flagged set is therefore exactly the lowercase rows plus `S`.
- Absence is not innocence either, which is the correction to the bullet
  above: an `assume-unchanged` file that was **deleted** still reports `h`,
  and both status forms stay empty, so exempting every absent row discards an
  uncommitted deletion. Reproduced for both flags. Sparse checkout is the one
  benign absence, so an absent row is exempt only when it is `S` **and** that
  worktree reports `core.sparseCheckout=true` (a per-worktree setting: it read
  `true` in a sparse worktree and unset in a plain one). Residual and
  deliberate: a skip-worktree deletion _inside_ a sparse worktree reads as an
  ordinary exclusion.

Two more surfaced once the check was a script, both verified:

- Resolving the root through a plain command substitution loses the same byte
  at a different layer: `$(git rev-parse --show-toplevel)` strips the trailing
  newline of a directory named with one, and the stripped spelling named an
  existing sibling worktree, so a dirty target reported `OK inventory` for its
  clean neighbour. Capture that output byte-exactly.
- `core.sparseCheckout` takes any boolean spelling. With `yes` written to the
  worktree config, `git config --get` returned `yes` while sparse checkout was
  in force, so comparing the raw string against `true` reports an ordinary
  sparse worktree as hidden work; `git config --bool --get` returned `true`.

Because the flag's purpose is that git stops checking the file, no inventory
can decide whether its contents differ, which is why a flagged row is itself
the finding rather than its diff. These rules are what
`worktree-inventory.sh` implements, and `scripts/test-merge-cleanup-inventory.sh`
holds one case per bullet above, so a later change either keeps them or turns
the matrix red.

Relied on by the worktree preflight (which runs that script and stops on any
non-zero exit).

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

Relied on by step 2 (the dirty-tree check) and by `worktree-inventory.sh`,
which pass `-uall` explicitly for this reason.

---

## §branch-d-upstream

`git branch -d` checks the branch against its _upstream_ when one is set, and
against `HEAD` only when none is. Cleanup prunes a step later, so the
not-yet-pruned `<head-remote>/<branch>` usually still contains the tip and
satisfies that check.

Relied on by step 4 (why the step runs its own merge check first).
