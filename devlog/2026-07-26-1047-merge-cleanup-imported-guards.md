# Importing #83's verified guards into merge-cleanup

PR #83 rebuilt self-merge's merge-and-cleanup as a tested executable and, in
doing so, reproduced three hazards that `merge-cleanup/SKILL.md` did not guard:
status reads that repository configuration can empty, worktree removal that
destroys files no porcelain form reports, and a remote-delete refspec that a
suffix-matching sibling ref makes inexpressible. #88 asked for the call first:
import them as prose, or follow self-merge out of prose into an executable.

## Decisions

- **Chose the prose import over shipping a `merge-cleanup.sh`** (owner's call,
  offered as an explicit option alongside the executable and a
  prose-now-file-the-executable split). #83's "prose cannot close an execution
  space" finding was about the quoting, substitution, and parsing classes,
  where an arbitrary agent re-derives the command in an arbitrary shell every
  run, so no enumeration converges. These three are not that shape: each is a
  stop on a single observable (pass `-uall`, run an inventory before a
  destructive command, compare a ref column as a whole string), stated once and
  checkable by reading. The cost side is not symmetric either. `self-merge.sh`
  refuses fork heads outright, requires an authenticated PR-host CLI, and has
  no git-only path, no squash/rebase branch-delete path, and no stacked-PR
  retargeting, all of which merge-cleanup must support; a merge-cleanup
  executable would therefore be a second large script and matrix that inherits
  little, and two large near-siblings drift.
- **Reversed mid-PR: the worktree inventory ships as an executable
  (`skills/merge-cleanup/worktree-inventory.sh` plus
  `scripts/test-merge-cleanup-inventory.sh`), not as prose** (owner's call,
  taken on #98 after five review rounds). The prose-import decision below
  stands for the other two guards, which drew no findings at all; this one
  rule drew all five, three of them P1, and each fix opened the next hole.
  The evidence that settled it: three of the five findings were prose lagging
  an implementation that was already correct in `self-merge.sh`, and the
  fifth (an absent `assume-unchanged` row is an uncommitted deletion, not a
  sparse exclusion) was a live defect in that executable too, introduced by
  this PR. So the logic had to be written as code regardless, and leaving a
  prose re-derivation of it next door is the failure mode #83 named. The
  script is deliberately narrow where #83's was broad: read-only, one
  positional argument, no forge calls and no mutation, so the destructive
  steps stay in prose where a human decides. The five findings are now five
  matrix cases, and the discriminating ones were run against degraded copies
  of the script (flag-only, presence-only, line-wise unanchored) and fail
  there.
- **Chose to gate the worktree removal on an inventory rather than adopt
  self-merge's always-stop stance** (owner's call). self-merge stops before
  removing a separate linked head worktree even when the inventory is clean,
  and reports the local branch as `kept_manual`, because git exposes no
  operation that atomically verifies a worktree's `HEAD`, inventories it, and
  removes it. That race is real here too, but converting merge-cleanup's
  relocate-and-remove instruction into a hand-back, and its step 4 local delete
  into a manual step, is a behavior change #88 does not ask for and would make
  the skill stop on the layout this project's own convention produces on every
  work unit. The narrow adoption takes the evidence (inventory, stop on
  hidden state that is actually there) without the stance.
- **Chose to keep the suffix-decoy case a stop, matching self-merge, rather
  than falling back to a forge-API ref delete.** The API delete would succeed
  where the push cannot, but it re-runs neither the OID comparison nor the
  lease, so it trades an expressible delete for an unguarded one on the single
  path this skill says it must never risk.

## Verification findings

Reproduced in scratch repos on git 2.50.1 (Apple Git-155) before the prose was
written, in merge-cleanup's command forms rather than the script's, since this
skill inventories another worktree with `git -C` and writes its delete as a
literal command. Each refined the wording rather than only confirming it.

- Under `status.showUntrackedFiles=no`, both `git status --porcelain` and
  `git status --porcelain --ignored` came back empty on a worktree holding an
  untracked file and an ignored `.env`, so the `--ignored` form is not a way
  around the hole; `-uall` restored both listings. `git worktree remove` then
  took the directory with exit 0, its own untracked-file refusal having stopped
  firing, where the default configuration refused with exit 128.
- A tracked file flagged `assume-unchanged` (`h` in `git ls-files -v`) or
  `skip-worktree` (`S`), then edited, was reported by neither
  `status -uall --porcelain`, nor its `--ignored` form, nor `git diff --stat`.
  Removal destroyed both files with exit 0. Since the flag's purpose is that
  git stops checking the file, no inventory can decide whether its contents
  differ, which is why presence is the stop.
- With a decoy ref literally named `refs/heads/refs/heads/feat` beside the real
  branch, the qualified `ls-remote` pattern returned both lines, and both
  `git push --delete --force-with-lease=...` and `git push origin :refs/heads/feat`
  failed with "error: dst refspec refs/heads/feat matches more than one",
  exit 1, leaving every remote ref in place. The identical delete succeeded
  once the decoy was removed, so the refusal is the decoy's doing and not the
  lease's.
- Running `git worktree remove` from inside the worktree being removed exits 0
  and unlinks the directory, leaving the shell on a path that no longer exists.
  Cheap to state in the same bullet as the inventory, so it went in.
- Review on #98 caught the inventory's stop condition reading `ls-files -v`
  unfiltered: the command prints every cached file, `H` for an ordinary one, so
  "stop on whatever either command reports" would have stopped on every
  worktree holding tracked files. The stop is now scoped to rows whose first
  column is a lowercase letter or `S`. The class sweep found one weaker
  instance, self-merge's fallback prose, and scoped it the same way.
- The next round found the other half of the same class, and it was right:
  a sparse checkout marks every excluded path `S` while leaving it absent, so
  a flag-only filter refuses every sparse worktree. Reproduced independently
  (`sparse-checkout set --no-cone /base.txt` left `S feat.txt` with the file
  gone, a clean `status -uall --porcelain --ignored`, and removal at exit 0),
  along with the two controls that keep the guard honest: a present
  skip-worktree file with edits is still caught, and a materialized
  out-of-cone path is caught by the status read, since git clears the flag
  when the file appears. The filter now requires the row's path to exist.
- **The class lesson, stated once**: a row in `git ls-files -v` is evidence of
  an index flag, not of destroyable state. Both misreadings (`H` counts as
  hidden state; `S` counts even when the path is absent) came from treating
  the command's output as the inventory instead of as one input to it. Two
  rounds on one class is the pattern #83's note warns about, so the tag space
  was then enumerated in one pass instead of narrowed again: in a default `-v`
  listing, `H` is ordinary, lowercase (`h`, `s`) is assume-unchanged, `S` is
  skip-worktree, and `M` is an unmerged path the status read reports as `UU`.
  Verified: an assume-unchanged edit appears in neither the `-uall` porcelain
  status nor `git diff`, while the merge conflict and the staged deletion do. Nothing outside "lowercase or `S`, and present" is hidden
  state, which is the completeness claim the two fixes were converging on
  one instance at a time.
- The enumeration above covered the tag space but not the transport: a third
  round (P1) found the prose still prescribing the non-`z` listing, which
  C-quotes a path holding a newline or tab, so the existence test fails on the
  printed spelling and drops the row, and a dangling symlink fails `-e` while
  removal still takes it. Both reproduced, with `status -uall --porcelain`
  empty for all three paths, so nothing else would have caught them. The
  irony is self-inflicted: the executable written in the previous round
  already used `-vz` and `[ -e ] || [ -L ]`, and the prose was not brought
  along with it. The class is really "a path from git output is not a path
  until it comes from a NUL-terminated listing", so the rule now also pins
  where the worktree path itself comes from.
- A fourth round (P1) found the same shape once more: the prose wrote the
  presence test against the bare row path, which resolves against the
  caller's directory, while the rows are relative to the worktree being
  inventoried. Reproduced from a base checkout against a sibling worktree
  whose flagged file exists only on the feature branch: bare test absent,
  prefixed test present, status empty throughout. The test is now anchored
  with the worktree path and the listing takes `--full-name`, which keeps
  rows root-relative even when the `-C` target is a subdirectory. Three of
  the four rounds landed on prose that the executable already had right
  (`-vz`, the lstat pair, the `$d/` prefix), which is the honest verdict on
  this import: the prose is a re-derivation of a program, and re-derivations
  drift from the program until every clause is pinned.
- `self-merge.sh` had the second half of the class in executable form
  (`worktree_preservation_preflight` counted every flagged row). Its caller
  stops unconditionally either way, so the defect was a wrong diagnosis
  rather than a false block, but the fallback prose and the executable have
  to agree, so it was fixed here with a matrix case that fails against the
  old implementation (which stopped with `worktree-flagged` where
  `head-worktree-present` is correct) and a second case pinning that a
  present flagged file still stops. The rewritten read is NUL-terminated
  (`ls-files -vz` through a temp file), because a path can hold a newline and
  command substitution drops NUL bytes.

- The first round against the script found two defects the prose rounds could
  not have: a plain `$(git rev-parse --show-toplevel)` strips the trailing
  newline of a worktree directory named with one, so a dirty target reported
  `OK inventory` for its clean sibling (P1, verified), and `core.sparseCheckout`
  accepts every boolean spelling, so comparing `git config --get` against
  `true` flagged an ordinary `yes`-spelled sparse worktree (P2, verified).
  Both are now matrix cases that fail against the previous implementation.
  This is the medium working as intended rather than the regress continuing:
  the findings moved from "the instructions omit a clause" to "the program has
  a bug", which a test can hold closed.

## Knowingly not guarded

- A file flagged `assume-unchanged` or `skip-worktree` is equally invisible to
  step 3's resync, but that path is not destructive: the fast-forward reports
  success and leaves the local content, so the file diverges quietly rather
  than being lost. Guarding it would mean an index inventory before every
  resync, which is a cost out of proportion to a divergence the next real
  status read surfaces.

## Divergences from self-merge that remain deliberate

Beyond the worktree stance above, the two already-recorded ones stand (#83's
note): merge-cleanup retargets stacked PRs and then deletes, while self-merge
surfaces them and keeps the branch; and merge-cleanup's dirty-tree gate sits
after the remote delete, while self-merge preflights before it. Neither is
drift, and neither is what #88 asked about.

## Revisit when

- merge-cleanup's own review rounds start showing #83's fix-begets-finding
  regress (later findings targeting text earlier findings added, with no
  severity taper). That is the signal that its prose has met an execution space
  after all, and the executable question reopens. **This fired during #98 and
  was acted on**, for the worktree-inventory rule alone: five rounds, each
  finding created by the previous fix, three of them P1, while the other two
  guards drew nothing. That rule is now the script above. What remains to
  revisit is whether the same happens to a guard still written as prose; two
  clean rounds on the other two is not yet evidence that it will not.
- The atomicity race self-merge stops on (a concurrent reset moving a clean
  worktree's `HEAD` between inventory and removal) is observed rather than
  reasoned about, at which point the narrow worktree stance above should be
  reconsidered against self-merge's.
- #82 landed on 2026-07-26 (`2026-07-26-0937-canonical-resync-guards.md`), so
  the canonical recipe, self-merge, and merge-cleanup now all carry guarded
  resyncs from the same evidence. A fourth copy of these guards appearing
  anywhere is the point to ask whether they should be one text rather than
  three deliberately separate ones.
