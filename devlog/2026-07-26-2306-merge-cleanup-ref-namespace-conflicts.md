# Ref-namespace conflicts in the base-landing plan

A correction to `devlog/2026-07-26-1725-merge-cleanup-landing-script.md`, which
froze when PR #104 merged. The finding arrived as round 14 of that PR's review,
after the merge, so it lands as its own work unit rather than as an edit to a
frozen note.

## Decisions

- **The guard compares enumerated ref names in both directions, rather than
  stating more ref paths.** One name cannot be both a ref and a directory of
  refs, so a create fails when an existing ref is a path prefix of the
  destination (`release` blocking `release/next`) and equally when existing refs
  live beneath it (`release/next` blocking `release`). Verified on git 2.50.1,
  all four combinations exiting 128, with the existing ref both loose and
  packed. The ref-path stat that #104 shipped catches exactly one of the four,
  the loose parent-directory case, and only incidentally, because a directory
  happens to be there to stat. A packed parent leaves nothing behind to stat,
  which is why this is a name comparison.
- **The remote-tracking destination is checked too**, since the plan's fetch
  writes `refs/remotes/<remote>/<base>` and fails the same way.
- **Swept the shape rather than the citation.** The review reported one of the
  four combinations. Taking that literally would have shipped a guard that fixed
  a quarter of the class, which is the failure mode #104's own ledger records
  three times over.

## Verification findings

- Four shapes by two storages, checked by executing the create rather than
  reading the plan: every combination where `checkout -b` exits 128 is now
  stopped, and an unrelated branch with a slashed base still plans normally.
- The matrix case fails against a copy without the guard on three of its four
  members. The fourth passes there because #104's ref-path stat already covers
  it; it is kept because the packed form of that same shape is not covered, and
  the case comment says so rather than implying the whole set discriminates.

## Review findings

- **The enumeration was rooted too narrowly** (round 1 on the follow-up PR). A
  scan of each destination's own namespace cannot see an ancestor sitting at or
  above the namespace boundary: `refs/remotes/origin` existing as a ref blocks
  the fetch's `refs/remotes/origin/<base>`, and the reviewer reported that one.
  Checking whether the same shape existed one level up found that it does, with
  `refs/heads` as a ref blocking `refs/heads/<base>`. Both verified, both
  failing with git's "cannot create" lock error. One enumeration of `refs/` now
  serves both destinations, which catches ancestors at every level; tags come
  along harmlessly, since no `refs/tags` name can be a path prefix of a branch
  or remote-tracking ref.

- **An enumeration cannot see an unresolvable ref** (round 2). `for-each-ref`
  omits a dangling symbolic ref while still exiting 0, so an ancestor in that
  state is invisible to the name comparison, though the file is there and the
  ref store still refuses to create beneath it: verified with
  `refs/heads/release` pointing at a deleted branch, where the enumeration
  listed only `main` and `checkout -b release/next` failed on the lock. The
  ancestor paths are now stated directly, which is exact for any loose occupant
  whatever its state, with the name comparison kept for packed ancestors that
  leave no file. Tested with `-f` rather than `-e`, since a namespace like
  `refs/heads` is an ordinary directory in every repository.

- **Two more shapes of the same blindness** (round 3), both in the fix above.
  Refs living _beneath_ the destination block it exactly as an ancestor does,
  and a dangling one is again omitted by the enumeration; a directory at the
  destination path is the exact signal, and the remote-tracking side is where it
  bites, because the plan creates a ref the caller never names. And the stats
  were rooted at `--absolute-git-dir`, which in a linked worktree is
  `.git/worktrees/<id>`, holding only per-worktree refs while branches and
  remote-tracking refs live in the common directory. That one is not a corner
  case: the skill's relocate rule runs step 2 inside a linked worktree whenever
  the base branch is checked out there, so the guard was blind in precisely the
  layout the skill documents.
- **The lesson across rounds 1 to 3 is one shape, widening each time:** every
  way of asking "is this ref path free" has a blind spot, and each fix inherited
  the previous one's. Enumeration misses what it cannot resolve, ancestor stats
  miss descendants, and both miss everything when rooted at the wrong git
  directory. What the guard now does is ask three different ways and take any
  positive: stat the ancestors, stat the destination, and compare enumerated
  names for the packed refs that leave no file at all.

- **The guard was in the wrong scope** (round 4), which no amount of refining
  its logic would have found. All of it sat inside the create branch, but step 3
  fetches into `refs/remotes/<remote>/<base>` on every cleanup, not only when
  the local branch had to be created, so a repository with an occupied
  `refs/remotes/origin` passed the plan and failed the resync. The
  remote-tracking check is now unconditional; the branch-side checks stay inside
  create, where they are the only place they can matter. Verified with a local
  base present, so nothing was created and the fetch still failed on the lock.

- **The descendant test over-stopped** (round 5), the mirror of the earlier
  under-stopping. A directory at the destination is not a collision by itself:
  git replaces an empty one, and an empty subtree with it, both verified by
  running the fetch. Only a loose ref beneath, at any depth, blocks the create.
  So the test is now "does any regular file live under this path", not "is this
  path a directory", which keeps the dangling-descendant case while releasing
  two landings git performs.
- **A verification of mine was invalid and said so only on a re-run.** The first
  check of this fix reported the empty-directory cases planning correctly, but
  the edit had not applied (the hoist in round 4 changed the indentation the
  anchor matched on) and the fixtures had been mutated by the fetch my own
  earlier check ran. Two wrongs reading as a right. The re-run used fresh
  fixtures per state and asserted the plan against the fetch rather than against
  an expectation, which is the same oracle the rest of this work uses and would
  have caught it the first time.

- **The occupancy predicate reached its general form on the third try**
  (round 6). Scanning for regular files missed a dangling symlink, which blocks
  the create exactly as a loose ref does. What git enforces, and says in its own
  error, is "there is a non-empty directory blocking reference", where empty
  means holding no entry that is not itself a directory. So the predicate is
  `! -type d` rather than `-type f`, verified across four states (regular file,
  dangling symlink, empty directory, nested empty tree) against what the fetch
  actually does. Three rounds refined this one test, each time because it was
  written to the example in hand rather than to the rule git applies.
- **The matrix header had drifted from what was verified.** Several appends to
  its degraded-copy list had silently done nothing, because they used a string
  replacement without asserting the anchor matched, so the list named none of
  the ref-path degradations this work unit actually ran. Rewritten from the set
  that was run, and the lesson is the same one the ledger keeps recording: an
  unchecked edit to a claim is how a claim stops being true.

- **A fresh refute pass found the backend boundary, not another predicate
  tweak.** Reftable puts a marker file at `.git/refs/heads`, so the files-backend
  ancestor walk false-stopped every missing local branch there. It also has no
  loose tree from which to recover dangling symbolic refs omitted by
  `for-each-ref`. A prepared-and-aborted ref transaction initially looked like
  the backend-native oracle, but the second refute pass disproved its read-only
  premise: `prepare` creates `tables.list.lock`, and killing the process before
  `abort` strands the lock and blocks later ref updates. The plan now names the
  limitation honestly as `STOP ref-storage`. Reftable remains unsupported until
  Git exposes a non-mutating availability query.
- **Backend detection follows extension activation and scope.** Git 2.43
  exposes but ignores `extensions.refStorage` when the repository format is 0;
  newer Git rejects that malformed combination before the planner runs.
  Repository extensions are local rather than inherited from global config.
  Reading the key without either condition false-stopped a files repository as
  reftable. The plan now defaults format 0 to files and reads the
  repository-local ref-storage extension only under format 1. The format is
  read through Git's integer parser so accepted spellings such as `01`, `+1`,
  and `0x0` dispatch as 1, 1, and 0 rather than as unsupported strings.
- **The files-backend sweep had two more asymmetric edges.** A symlink on an
  ancestor was missed when dangling and followed when it named a directory; the
  second form let fetch write the remote-tracking ref outside `.git`. All
  ancestor symlinks now stop. At the exact destination, git safely replaces a
  dangling filesystem symlink, but a broken symbolic ref made checkout exit 0
  while attaching `HEAD` to the symbolic target. The destination check now
  distinguishes those states, and its tests judge the resulting `HEAD`.
  Separately, `find` errors were discarded by a pipeline and read as an empty
  tree; its status is now captured and a failed scan is `LOOKUP_FAILED`.
- **Path classification must precede symbolic-ref reads.** An exact FIFO, or a
  symlink resolving to one, makes `git symbolic-ref` wait indefinitely for a
  writer. Moving the exact-path check first was still incomplete on Git 2.43,
  where the earlier broad `for-each-ref` opened the same entry. A special-node
  scan of the whole loose ref tree now runs before every enumeration, not only
  before symbolic-ref reads. Breaker-backed cases prove the planner returns
  without opening direct or symlinked FIFOs at either destination or a FIFO in
  an unrelated namespace. The breaker records a failure only after its FIFO
  write connects, not merely after its one-second delay, so slow hosts do not
  turn elapsed time into false evidence of a reader. The broad scan filters
  candidates through `git check-ref-format`; Git ignores special entries under
  invalid ref paths without opening them, so direct and symlinked FIFOs in that
  unreachable shape do not false-stop cleanup.
- **Resolvable symbolic refs redirected successful commands.** A symbolic
  `refs/heads/release` made checkout report success while attaching `HEAD` to
  its `victim` target, and a symbolic `refs/remotes/origin/main` made fetch
  advance that target branch instead of an ordinary tracking ref. The first was
  classified as an existing branch and skipped the create-only guard; the
  second was enumerated exactly and treated as safe to update. Both exact
  destinations are now rejected before the command can follow them.
- **An exact filesystem symlink is not blocked merely because its target
  exists.** A fetch that advances an enumerated direct ref through a symlink to
  a regular file replaces the symlink with the new loose ref and leaves the
  target file unchanged. A symlink to a directory still fails as a blocking
  non-empty directory. The occupancy check now distinguishes those outcomes
  and the matrix forces a real update before asserting the replacement.
- **Packed case aliases affect the tracking destination too.** The branch
  create had an ASCII-fold fallback because a packed ref leaves no loose path
  for the filesystem to alias. The unconditional remote-tracking fetch had no
  equivalent, so a differently cased packed tracking ref could be silently
  overlaid by the new loose ref. One shared folded-name predicate now checks
  both destinations and excludes the exact name, which remains a normal update.
- **Two inputs bypassed the intended preflight.** An older git echoes an unknown
  `--path-format=absolute` while exiting 0, so the fallback never ran and the
  filesystem checks used a bogus multiline path. The plan now resolves the
  universally available relative `--git-common-dir` answer itself. And a remote
  created directly in config can resolve through `git remote get-url` while its
  name makes `refs/remotes/<remote>/<base>` invalid; the complete destination is
  now validated before any plan.
- **The refute pass also exposed the concurrency boundary.** The plan cannot
  retain a ref lock across the later fetch and checkout without ceasing to be a
  read-only, separately executed preflight. A concurrent ref writer can
  invalidate any `OK` after it is printed. This is accepted as an explicit
  operating precondition rather than hidden as a guarantee: step 2 now requires
  one continuous interval of exclusive control over ref-mutating operations
  from its first plan through step 3's final fetch and fast-forward, including
  the switch and the second plan, and stops when that cannot be established.

## Revisit when

- merge-cleanup's plan grows a third ref namespace, or the landing starts
  writing a ref this check does not enumerate. The check is per-namespace by
  construction, so a new destination needs its own call rather than inheriting
  coverage.
