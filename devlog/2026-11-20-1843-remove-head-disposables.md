# Apply Declared Disposables When merge-cleanup Removes the Head Worktree

`merge-cleanup.sh` now removes a merged head's linked worktree whose only
leftovers are ignored paths `.worktree-disposables` declares. Right before
the sweep judges the worktree, the cleanup fetches the base from its verified
remote and passes that tip to `worktree-sweep.sh --remove-head` as
`--disposables-at`. Issue #476 carries the contract; the owner asked for it.

## Revises

`devlog/2026-11-18-2223-worktree-disposables.md` chose to have
`--remove-head` read no file, because it had no base, and reading the merged
head's copy could restore an entry the base had since dropped. The changed
assumption: the cleanup can pin the newest reviewed base tip itself, from the
base remote it already verified. The dropped-entry risk applies only to the
merged head's copy, which stays unread. Without the flag, `--remove-head`
still reads no file.

## Evidence

In freeasinbird/teloleo#238, teloleo committed `.venv/` and other caches to
`.worktree-disposables` on `origin/main`. The owner's dry run reported the
head worktree clean; `merge-cleanup.sh --pr 239` kept it as dirty, since
`--remove-head` counted every ignored path as undeclared.

## Decisions

- **Chose the freshly fetched base tip over the PR's merge commit.** The tip
  is the newest list the project reviewed onto its base. An entry dropped
  after the merge is gone from it, and one added after the merge landed
  through review too, so the tip's copy wins without special handling. The
  merge commit's copy could still hold an entry the project has since
  dropped.
- **Chose a fetch before the sweep over the local tracking ref.** The cleanup
  resolved no base commit before removal; its base fetch ran later, in the
  resync. A stale tracking ref can miss an entry the base added, or keep one
  it dropped. The resync still fetches again, which is harmless.
- **Chose `STOP bad-record` over `LOOKUP_FAILED head-worktree` for a bad file
  on the base.** A retry can't pass until the owner fixes the file on the
  base branch. This is a new way for a cleanup to stop: before, a clean head
  worktree was removed even when the base's file was malformed.
- **Chose to give the oid no ancestry or landing test.** The caller vouches
  for it, as it does for `--head-oid`. The flag only names where the file is
  read.

Revisit when the cleanup gains a trusted base commit earlier in the run,
which would make the extra fetch redundant.

## Refute-First Review

One fresh-context reviewer tried to break the change before commit.

- **Confirmed and fixed:** a 64-hex `--disposables-at` resolved as a branch
  of that name in a SHA-1 repository, and a tag oid peeled to another
  commit. merge-cleanup never passes either, but the sweep now requires the
  resolved commit to equal the oid it was given.
- **Confirmed and fixed:** land-approved-prs handled only merge-cleanup's
  `head-worktree-present` stop, and its own `bad-record` guard means a broken
  landing record. It now says merge-cleanup's `bad-record` is the base's
  disposables file.
- **Allowed by decision:** a failed read of the file at the pinned commit is
  `LOOKUP_FAILED`, not `STOP bad-record`, as in the owner's sweep, because a
  retry can pass. merge-cleanup reports it as `LOOKUP_FAILED head-worktree`.
- **Disproved by a check:** setting the sweep's base oid under
  `--remove-head` adds no base-branch, ancestry, or landing test; those read
  `BASE_NAME` or run only outside that mode, and the matrices stay green.
