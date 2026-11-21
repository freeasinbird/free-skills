# Clean Up a Unit's Temporary Checkouts at Hand-off

Hand-off step 7 checked only the PR's own worktree, so review checkouts,
superseded attempts, and abandoned session worktrees outlived every work unit.
A landing batch on 2026-11-21 found nine such checkouts (#491). Merge-cleanup
can't catch them, because their branches never become a PR head. Step 3 now
records each extra checkout and temporary branch when it's created, and step 7
removes recorded items that pass a mechanical safety check.

## Decisions

- **Act only on recorded items.** After context condensation an agent can't
  reliably recall which checkouts it made, and a checkout on disk may be a
  sibling unit's or the owner's. A record written at creation is the only
  evidence of ownership that survives. Unrecorded checkouts, including every
  one made before this convention, stay out of scope.
- **Record at step 3, not only clean up at step 7.** The superseded and
  abandoned cases never reach step 7 of the session that made them. The
  record moves to the issue when work continues in a later session, and the
  step lets an agent remove an abandoned checkout as soon as it abandons it.
  The 2026-11-19 scratch-outside-worktree note set the same pattern for
  scratch files.
- **Use the inventory script, or a stricter fallback, instead of plain
  status.** `git worktree remove` deletes ignored and index-flagged files at
  exit 0, and `status.showUntrackedFiles=no` hides untracked files from both
  status and removal (`hazards.md` §worktree-remove-destroys,
  §status-config). Where merge-cleanup is installed, `worktree-inventory.sh`
  encodes those findings. The fallback for projects without it treats any
  ignored file and any non-`H` row as a reason to keep. That over-keeps
  checkouts with `node_modules` or a sparse checkout; it reports them
  instead of guessing.
- **Require ancestry before deleting a branch.** The tip must be an
  ancestor of the freshly fetched PR head or default-branch tip. A pre-fold
  copy, like the six `t3/*claim-record*` branches behind #428, fails and is
  reported, not deleted. Rejected: letting the agent judge that a pre-fold
  copy is safe, since that judgment is exactly what condensation erodes.
  `git branch -d` isn't proof because it checks an upstream when one is set
  (§branch-d-upstream).
- **Dropped the contract's `git cherry` route.** The issue allowed a tip
  whose commits `git cherry` marks `-`. Pre-push review showed patch IDs
  ignore whitespace, so a re-indented Python line counted as contained while
  the trees differed. A content check would make the rule longer than its
  benefit; a rebased copy that only `git cherry` could clear is now reported
  instead of deleted.
- **Keep delegate cleanup parent-side.** A delegate may return before its
  checkout is safe to judge, and may not know what the parent's PR contains.
  The parent asks it to name what it created, records that, and runs the
  same checks.
- **Gate host-owned checkouts.** Hosts that create thread or session
  worktrees may track them; removing one behind the host's back can strand
  its state. Use the host's control, or raw `git` only where the host says
  it's safe, else keep and report.
- **Change the managed finish-line block.** The record must exist before step
  7, and only step 3 runs at creation time. The sentence costs 330 bytes of
  the managed budget (17,995 to 18,378 of 20,000).

## Refute-first Findings

An independent reviewer subagent tried to break the draft in scratch
repositories on git 2.54.0, checking each case against `hazards.md` and
`worktree-inventory.sh`.

Confirmed and fixed in the step 7 text:

- **Stale remote ref passed ancestry.** After another clone force-pushed the
  PR branch, `merge-base --is-ancestor` against the unfetched `origin/feat`
  returned 0 for a copy holding a dropped commit. Step 7 now fetches first
  and uses the PR head as just fetched.
- **`git cherry` skips merge commits.** A temporary branch whose merge
  commit added a file passed with only `-` lines. The draft added a
  no-merges guard; pre-push review then removed the cherry route entirely.
- **`git am` was missing from the operation list.** A stopped am session
  read clean everywhere except plain `git status`, and removal took its
  pending patches. The list is now "any operation in progress, such as".
- **A reused path or branch name could belong to another unit.** A fresh,
  clean worktree passes every check, so only the record separates it from an
  abandoned one. Step 3 now records each checkout by path and branch, and
  step 7 skips one whose branch no longer matches.

Disproved by a check: ignored files (`!!` row, inventory `STOP dirty`);
`status.showUntrackedFiles=no` (the explicit flag still lists the file);
deleted assume-unchanged and edited skip-worktree files (`h` and `S` rows,
inventory `STOP flagged`); locked worktrees (porcelain shows `locked`, and
removal refuses); detached and pre-fold HEADs (both fail containment);
deleting a branch still checked out (git refuses, and the text orders removal
first); submodules (status shows them, and removal refuses); nested
repositories (listed as untracked or ignored); empty commits (`+` in cherry);
and removal from inside the target (the text says from another checkout, and
the inventory stops with `self-target`).

Allowed by decision, not changed:

- **Stashes aren't reported.** `refs/stash` is shared and survived removal, so
  nothing is lost.
- **Host ownership isn't detected mechanically.** The host's own
  documentation decides it, and an unsure case falls to keep and report.
- **The fallback status read runs a configured fsmonitor.** Every status read
  in the workflow already does; it is not a data-loss path.
- **"A running delegate still uses" is judgment.** The parent started the
  delegate and knows whether it has returned; no git state shows it.

Pre-push review, a fresh-context reviewer with the project's fixed brief,
confirmed two more and both are fixed:

- **`git cherry` ignores whitespace.** A temporary commit that dedented a
  line the PR head indented printed only `-`, and no merge was involved.
  Step 7 now accepts ancestry alone.
- **Scratch deletion reached past the record.** "Your own in any checkout"
  let an agent delete a same-named file in the primary checkout from memory.
  It now covers the PR's worktree and the recorded checkouts only.

A second pre-push round, same brief, confirmed four more, all fixed:

- **Host-owned checkouts skipped the checks.** The host bullet read as an
  alternative path. The read-only checks now run first, and the host gate
  covers only the removal.
- **Reflog-only commits were lost.** A commit made and reset away in a
  temporary checkout lives only in its HEAD reflog, which removal deletes.
  The first refute pass had allowed this as intended. It is now kept,
  matching `worktree-sweep.sh`, which treats such commits and
  `refs/worktree/` refs as dirty. A checkout where the agent amended also
  stays; that over-keeps rather than loses work.
- **A tag could shadow the branch name.** `merge-base` on a bare name
  resolves a same-named tag first (`hazards.md` §tag-shadow), while
  `git branch -D` deletes the branch. The proof now names
  `refs/heads/<branch>`.
- **A reused path with a detached checkout passed the record match.** The
  record now holds the detached HEAD, and a mismatch means skip.

A third round found no blockers. It clarified two phrases: a record
mismatch now says keep (and so report), and the inventory test names the
script's `OK inventory` line. Two edge cases were declined:

- **Reflogs turned off.** With `core.logAllRefUpdates=false`, a reset-away
  commit lives only in `ORIG_HEAD`, which removal deletes. That needs a
  non-default setting plus a reset of the agent's own work, and the commit
  survives until gc.
- **A branch moved without HEAD.** `git branch -D` drops the branch reflog,
  so a commit only that reflog held, after `git branch -f` or a forced
  fetch into the branch, goes unchecked. Both are deliberate overwrites by
  the agent, and commits made through HEAD are caught by the checkout's
  reflog check.

A scripted walk by the implementer confirmed the happy path: a clean,
contained detached checkout passes every check, and two pre-fold copies of a
folded branch fail ancestry.
