# Harden self-merge's cleanup against merge-cleanup's verified hazards

self-merge told the agent to resync with `git checkout main && git pull
--ff-only`, the exact command merge-cleanup documents as unsafe on reproduced
evidence, so two skills the same repo ships contradicted each other on a
destructive path (#74). The sequence now ships as a guarded executable
(`self-merge.sh`, phases check / merge / cleanup) with a prose specification
as the no-shell fallback only where an equivalent authenticated PR-host CLI
can perform every forge guard, plus a regression matrix
(`scripts/test-self-merge.sh`) that executes every guard against scratch
repositories.

## Decisions

- Chose shipping the sequence as an executable with a prose fallback
  specification, over continuing to state the mechanics as prompt prose.
  Eighteen review rounds in one day produced 25 findings with no severity
  taper; four hazard classes (merge-queue method, worktree inventory,
  quoting/injection, branch consumers) recurred four to seven times each
  despite escalated class sweeps and two read-only enumeration lenses, and
  the later rounds' findings targeted remediation text earlier rounds had
  added, the fix-begets-finding regress. The root cause was the medium:
  prose instructions re-derived by an arbitrary agent in an arbitrary shell
  re-open the input space every run, so no enumeration closes it, while a
  script closes the quoting and parsing classes structurally (values live
  in argv, nothing is re-pasted through a shell) and pins the rest as
  regression tests. Precedent: `watch-review.sh` and `capture.mjs`, both
  moved out of prose for the same reason, with the same
  script-primary/prose-fallback split and a matrix registered as a
  conditional done-check.
- Chose hardening self-merge's own copy over pointing it at the merge-cleanup
  skill, keeping the 2026-07-02 decision that both skills stay self-contained
  because they install separately. What changed since that note: merge-cleanup's
  resync has been hardened against three verified hazards (ignored-file
  overwrite on both checkout and fast-forward, tag shadowing a bare checkout, a
  bare pull following a fork's stale upstream), so the duplicate was
  known-hazardous rather than merely redundant.
- Chose the branch tip the session itself pushed and merged
  (`git rev-parse 'refs/heads/<branch>'`) as the expected OID for the remote
  delete, with the forge's `headRefOid` demoted to a cross-check, over trusting
  `headRefOid` alone. A forge field that reports the branch's live head moves
  with a post-merge push, so an equality check against it can pass on a branch
  that has since gained unmerged commits; the local tip cannot be moved by a
  third party's push. This makes the guard independent of a question nobody
  here could settle (see Revisit when).
- Chose to keep the remote delete before the base fetch over reordering it
  after the resync to gain a CLI-free containment check against the resynced
  base (`merge-base --is-ancestor`, which merge-cleanup uses): the
  local-tip OID plus `--force-with-lease` closes the same hole without
  reordering, and a containment check there would reach into the merge
  verification #74 declared a non-goal.
- Chose to gate the cleanup on the forge reporting the PR merged (state
  `MERGED`, non-null `mergedAt`), not on the merge command's exit status. Where
  the base branch uses a merge queue, a zero exit means enqueued, so the
  cleanup would delete the remote branch and then the local one while the merge
  was still pending, cancelling it and taking the branch's last copies.
  Deliberately fixed here despite #74's "no merge verification" non-goal,
  because the defect was in a claim this change itself introduced about its own
  command, and the gate is two sentences rather than an import of
  merge-cleanup's verify section. The non-goal otherwise stands.
- Chose to bind the merge itself to the reviewed head with
  `gh pr merge --match-head-commit "$VERIFIED_HEAD_OID"`, captured before the
  merge and reused by step 3's guards rather than re-read afterwards. Without
  it the command merges whatever the head is when it runs, so a push landing
  after the checks and the diff self-review merges unreviewed content, and the
  post-hoc OID comparison cannot undo an irreversible merge. Capturing once
  also survives the local branch moving between the merge and the delete.
- Chose to make the fork-head case a stop rather than a preference. The
  shared-head lookups are per repository, so they settle a same-repository head
  and cannot settle a fork one, whose branch may head PRs anywhere in a fork
  network nothing here can enumerate. Deleting on two repository-scoped queries
  would infer absence from an unenumerated set, with another PR's source branch
  as the cost, so a fork branch is kept and surfaced unless the user explicitly
  asked for its deletion.
- Chose the branch-rules API over the forge CLI's ruleset commands for reading
  a merge queue's method: `gh ruleset check` and `gh ruleset view` have no
  `--json` flag, so they can report that a queue applies without reporting
  which method it will use, which is the only fact the guard needs. The guard
  reads the `merge_queue` rule's parameters from
  `gh api --paginate "repos/<repo>/rules/branches/<branch>"` instead,
  aggregates the queue rows from every page, and treats multiple rows or a
  payload it cannot identify as unknown-and-stop rather than guessing a field
  name, since the shape and pagination belong to the forge.
- Chose to stop rather than enqueue where a merge queue's configured method is
  not a merge commit. A queue takes both halves of step 1's promise away: gh's
  manual states no merge strategy is required when the target branch requires a
  queue, because the queue's own integration method decides the shape, so
  `--merge` cannot deliver the first-parent narrative the step claims and a
  squash-configured queue flattens it irreversibly. Reading the method first
  and putting the choice to the user is the only honest option, since neither
  proceeding nor silently degrading the history is this skill's call to make.
- Chose to make the title-only contract a repository-settings guard for merge
  queues. Enqueueing exposes no subject or body input, so the explicit flags on
  `gh pr merge` cannot control the eventual queued commit. A `MERGE` queue
  proceeds only when the repository reports `merge_commit_title=PR_TITLE` and
  `merge_commit_message=BLANK`, refreshed immediately before enqueueing.
- Chose to check for a paused merge, rebase, cherry-pick, or revert in the
  preflight, because `git status --porcelain` reports none of them. Probe
  their per-worktree paths, not their names as revisions: an ordinary branch
  named `MERGE_HEAD` resolves through `refs/heads/` and is not an operation.
  Treating clean porcelain as workspace safety was the assumption behind the
  original dirty-tree guard; two verified cases break it (below).
- Chose to pin every `gh` call with `--repo` as well as gating them on a CLI
  existing (owner's call). An unpinned `gh pr merge <n>` in a fork clone
  resolves the number against the CLI's default repository, so it can merge a
  different PR entirely, which is worse than a bad resync.
- Chose to split the untrusted-value rule by what the value is, rather than
  applying one stop rule to everything. A contained quote is dangerous when a
  value is pasted into single-quoted shell source, not when it remains in a
  variable and reaches the command through double-quoted argv. Branch and
  remote names can legitimately contain an apostrophe, so the executable
  accepts and binds them; shape restrictions remain only where a command
  cannot terminate the positional safely. `<n>` is a stated pass-as-is
  exception.
- Two divergences from merge-cleanup are deliberate, not drift. Its stacked-PR
  step retargets and then deletes, while this one surfaces the PRs and leaves
  the branch, because self-merge should not grow retargeting machinery,
  especially where a retarget cannot cross repositories. And its dirty-tree
  gate sits after the remote delete, while this one preflights before it, which
  is the safer order.

## Changed assumptions

- **A `git branch -d` refusal is not a guard, so the ancestry check is
  required, but ancestry alone is not enough.** This note originally accepted
  the check out, reasoning that self-merge merges the branch itself moments
  earlier so a refusal suffices. The refusal never arrives on the auto-delete
  path: git compares the branch against its _upstream_ when one is set, the
  not-yet-pruned tracking ref still holds the tip, so `-d` deletes with a
  warning even when `HEAD` lacks the commits, and the prune that follows drops
  the last ref to them. Reproduced end to end, with zero refs left holding the
  work. A later refute pass found the opposite movement: repointing the branch
  backward to any commit already contained in the refreshed base passes
  ancestry, then lets cleanup remove the repurposed worktree and branch. The
  attempted exact-tip and detachment fix still left two data-loss races: a
  concurrent reset could move detached `HEAD` before removal, and a different
  worktree could attach the branch before `update-ref -d`. Git has no portable
  primitive combining the required worktree and ref assertions atomically.
  The final rule therefore stops on a separate linked head worktree before
  branch mutation (the current clean head checkout can switch to base
  in-place), rejects symbolic head refs, requires exact pinned-tip equality
  at the initial boundary, and never deletes the local branch automatically.
  The successful cleanup report says `kept_manual`, leaving worktree and tip
  verification adjacent to the later deliberate delete instead of pretending
  two non-atomic Git guarantees compose. Raw ref presence is checked without
  dereferencing so a dangling symbolic head cannot read as absent, and that
  presence is recomputed for the final report so a branch created during
  cleanup is also kept and reported. The raw probe uses the long-supported
  `symbolic-ref -q` followed by `show-ref --verify --quiet`, not
  `show-ref --exists`, which would silently impose Git 2.42 on the otherwise
  unversioned prerequisite.
  The symbolic probe repeats before returning absent: a direct ref can be
  atomically replaced by a dangling symref between the first symbolic read and
  direct-ref verification, so two reads without that closing probe are not a
  stable absence observation.
- **A polling cap must bound sleeps, not only loop admission.** Checking the
  deadline before an unconditional interval sleep can exceed the advertised
  cap by nearly the full interval. The merge-state loop now sleeps for the
  lesser of the configured interval and the remaining time. Decimal-looking
  inputs with leading zeros can also become octal in Bash arithmetic, and
  oversized values can wrap. Both wait inputs now reject leading zeros and
  have practical bounds validated before the merge command.
- **`git worktree remove` destroys ignored files.** This note also cited that
  command's refusal on modified or untracked files as an extra fail-safe. It
  has a hole exactly on the class this PR is about: an untracked file aborts the
  removal, an ignored one does not, so a worktree holding only a gitignored
  `.env` reads as clean and is deleted with the directory. Step 6 now
  inventories ignored files only to diagnose hidden state, then stops even
  when the linked worktree is clean. Its removal remains a separate deliberate
  step after concurrent users are stopped.
- **Matching push identities do not make a broadcast safe.** The original
  split-remote guard accepted every configured push URL when each normalized
  to the fetch identity. Two identical effective destinations still make Git
  issue the lease-protected delete twice: the first succeeds, the second fails
  against stale lease information, and cleanup stops after mutation. The
  destructive path now requires exactly one effective push destination, and a
  duplicate-identical fixture proves the remote branch survives the stop. A
  later Git 2.43 reproduction found the line-oriented counting gap: a valid
  destination followed by a blank `pushurl` lost the trailing empty record in
  command substitution, then deleted at the valid destination before failing.
  The full listing is now captured byte-exactly and any blank record stops
  before the push; the matrix pins the mutation ordering.
- **Prose cannot close an execution space; only an executable and its tests
  can.** The original plan treated the skill prompt as the artifact and
  hardened its wording round after round. Each hardening added surface for
  the next finding, because every instruction had to anticipate any shell,
  any platform, and any adversarial input an agent might substitute at
  runtime. The executable inverts that: the input-handling classes vanish
  (nothing is substituted into source), and each remaining hazard is a test
  that either passes or fails.
- **This copy had silently diverged from merge-cleanup in more than the resync
  command.** Three separate rules stated there were missing here (the
  untrusted-name stop, the branch-name tripwire, and the no-head-remote fork
  fallback), each surfaced only after a sweep that had claimed the class
  closed. Enumerating merge-cleanup's rule set wholesale, rather than patching
  cited lines, is what closed it.

- **Input handling needed three defences at three layers, not one rule.**
  Quoting handles shell metacharacters; it cannot carry a value containing a
  single quote (so those values are bound into variables instead); and it does
  nothing about git's own argument parsing, where a value beginning with a
  hyphen becomes an option. An option terminator covers the commands that take
  a positional remote, path, or bare ref, but not `git checkout`, where `--`
  means pathspec, so that one rejects instead. Ref qualification, added for
  tag shadowing, closes the hyphen hole for qualified refs as a side effect,
  which is why the terminators are listed per command rather than assumed.
- **Name-based guards are not ref-based guards.** On a case-insensitive
  filesystem `refs/heads/Main` and `refs/heads/main` are one ref file, so a
  head branch named `Main` onto base `main` passed the collision check, passed
  the existence and ancestry checks (which read the base's own OID back), and
  `git branch -d 'Main'` then deleted the base branch and broke `HEAD`, in a
  repository where git refuses the same delete spelled `main`. The collision
  check now resolves refs and folds case. A later review found that the ASCII
  fold still misses Unicode case and normalization aliases on default macOS
  volumes. The guard now probes candidate paths in a temporary invalid-ref
  child of each corresponding existing loose-head prefix directory,
  inheriting the directory-scoped filesystem semantics that store the next
  path component, and keeps the ASCII check only as a deterministic fast path.
  Packed-only prefixes use an inherited temporary chain. A later review found
  that mutable `core.ignorecase=false` still bypassed the probe; the filesystem
  check is now unconditional, while a true setting only enables the ASCII fast
  path. The common-directory path is read byte-exactly, including a trailing
  newline. This is the sharpest instance of a general lesson here: a guard that
  compares strings is not guarding the thing the command will act on.
- **A fallback must preserve the executable's manual-cleanup boundary.** The
  executable stops before removing a separate linked head worktree and always
  reports the local branch as `kept_manual`, but stale summary and section
  text still described automatic removal. The fallback now frames worktree
  inspection as diagnostic handoff and local deletion as a separate,
  deliberately verified step. Its worktree inventory and stop now precede
  remote deletion, base checkout, and resync, matching the executable's
  pre-mutation boundary. The scan accepts zero or one match, requires any base
  match to be the current checkout, and inventories or stops only for a unique
  head match in a separate worktree. After local head-ref validation, a second
  head scan immediately before remote resolution closes layout changes during
  those local checks.
- **An empty result is not a negative result.** `git ls-remote` prints nothing
  both for a branch that is gone and for a remote it could not reach, so the
  auto-delete early exit read a transport failure as success and skipped the
  two guards behind it; the check now reads `--exit-code` (2 for absent, 128
  for failure). The same shape applies to a failed `gh pr list`, which returns
  no rows and so reads as "nothing stacks on this branch".

## Verification findings

Reproduced in scratch repos; each one changed an instruction rather than just
confirming one. These now live twice: as the guards in `self-merge.sh` and as
executable cases in `scripts/test-self-merge.sh`, so they re-verify on every
matrix run instead of resting on this note's word.

- Found by the matrix itself, not by review: with a sibling ref named
  `refs/heads/refs/heads/<branch>` present alongside the real branch, the
  delete is inexpressible: git suffix-matches push destinations, so both
  `git push --delete` and the `:refs/heads/<branch>` form refuse with "dst
  refspec matches more than one" (verified on git 2.50). The script stops
  and surfaces it (`ambiguous-ref`), since a forge-API delete would re-run
  no lease check.

- Plain `git checkout` and `git pull --ff-only` replace an ignored file the
  base branch tracks while `git status --porcelain` stays empty;
  `--no-overwrite-ignore` aborts both instead, and `git pull` rejects that flag
  outright, which is why the resync is a fetch plus an explicit merge.
- With no local base branch and a same-named tag, a bare
  `git checkout '<base-branch>'` detaches `HEAD` at the tag; the fetch-then-`-b`
  form lands on the branch, and without that fetch `-b` aborts on a missing
  start-point.
- `git rev-parse --verify '<base-branch>'` succeeds on a same-named tag, so the
  existence probe has to be a qualified
  `git show-ref --verify --quiet 'refs/heads/<base-branch>'`
  or it re-enables the detach it guards against. A symbolic local base is a
  separate hazard: checkout follows its terminal target, so cleanup now
  rejects the symref before remote resolution or deletion rather than
  discovering the changed `HEAD` after mutation.
- A value bound from command output and referenced double-quoted passes quotes,
  `$`, and `;` through literally, and a contained `$(...)` is not re-expanded,
  while the same text pasted between single quotes executes.
- A worktree holding the base branch blocks the checkout ("already used by
  worktree") and `git branch -d` of a branch checked out in one; a fetch into a
  remote-tracking ref does not block, so that hazard is not claimed.
- `git status --porcelain` stays empty both for a paused merge that introduces
  no tree delta (where a following checkout then discards `MERGE_HEAD`
  silently) and for an interactive rebase stopped at a break (where `HEAD` is
  detached and the checkout leaves the rebase dangling), which is why the
  preflight tests the sequencer state directly.
- An untracked file aborts `git worktree remove`, an ignored file does not, so
  the removal needs its own ignored-file inventory rather than relying on that
  refusal.
- A remote whose name begins with `--upload-pack=<prog>` makes `ls-remote`,
  `fetch`, and `push` execute that program; `--` before the positional remote
  closes it on each, without disturbing normal nickname resolution.
- Qualifying an `ls-remote` pattern does not make its match exact: a remote
  branch literally named `refs/heads/<branch>` returns a second line for the
  qualified pattern, so the guard's "exactly one line" rule has to be a
  full-string comparison of the ref column.
- Reading `git worktree list --porcelain` line-wise mis-targets the removal
  when a path holds a space or newline; the intended worktree survived and a
  sibling was deleted with its ignored files, exit 0. `-z` exists for this.
- Values that fail closed and needed no instruction: an empty remote, worktree
  path, or branch name each abort their command, and an empty
  `--force-with-lease` OID means "must not exist", which rejects the delete.
- An active bisect leaves `--porcelain` empty and is invisible to every
  merge-, rebase-, and cherry-pick-specific probe; the checkout succeeds, the
  bisect stays running, and the next `git bisect good` marks the base commit
  instead of the candidate. `git am` state, by contrast, lands in
  `rebase-apply`, so the existing probe already covered it.
- A directory name can end in a newline, and `$( )` strips it, so a command
  substitution cannot carry such a worktree path (69 of 70 characters
  survived) while `IFS= read -r -d ''` preserves it exactly. Prescribing `-z`
  while showing a command substitution was self-contradictory.
- `git rev-parse --verify -q BISECT_START` exits 1 during an active bisect,
  because that file holds a branch name rather than an object name. The
  earlier correction split it from object-name checks, but review later
  disproved the object-name half too: `rev-parse MERGE_HEAD` can resolve an
  ordinary `refs/heads/MERGE_HEAD`. Every operation marker now uses a
  byte-faithful `--git-path` read followed by a path-or-symlink existence
  check.
- The branch-consumer questions have to be asked before the merge, not during
  cleanup. Where a repository deletes head branches on merge, the merge removes
  the branch, cleanup takes its clean-absence exit, and another PR sharing that
  head has already lost its source and closed before any guard looks. Only the
  pre-merge moment can protect it, and only by surfacing the situation for the
  user, since the merge is what does the damage.
- The title lookup originally followed the last repository-settings guard,
  leaving a forge call in the window where `delete_branch_on_merge` could
  change. Title preparation now precedes the final queue and consumer guards;
  repository facts are then refreshed after those queries, immediately before
  the merge command. The setting cannot be read and mutated atomically with the
  merge, but no avoidable forge read remains between them.
- A guard that reads `git status` inherits repository configuration, so it can
  be switched off by the repository it is protecting. Under
  `status.showUntrackedFiles=no`, the plain and `--ignored` porcelain forms both
  came back empty, and `git worktree remove` then deleted an ignored `.env`
  _and_ an untracked file with exit 0, its own untracked-file refusal having
  stopped firing as well. So every status read in the sequence passes `-uall`
  explicitly: the inventory is the last protection the directory has, and it
  must not be configurable away by the thing it guards.
- The `assume-unchanged` and `skip-worktree` index flags hide an edited tracked
  file from both `git status --porcelain` and `--porcelain --ignored`, and
  `git worktree remove` then destroys it with exit 0 (verified). Since the
  flag's whole purpose is that git stops checking the file, the guard cannot
  decide whether contents differ, so the presence of a flagged file is itself
  the stop. The resync path is not destructive here, which is worth
  distinguishing rather than lumping in: a fast-forward over such a file
  reports success and leaves the local content, so the file diverges quietly
  instead of being lost.
- The worktree parser is bash/zsh-only, because `read -d` is not POSIX (dash
  rejects it), which the skill has to gate rather than assume away: its stated
  prerequisite is "a shell". A NUL-capable tool is the fallback (python3 works),
  and `awk` is not, since the macOS awk silently returns nothing for a NUL
  record separator, which an agent would read as "no worktree matched" rather
  than as a failure. All three checked.
- A consistency check is not a correctness check when both sides derive from
  the same value. The worktree guard compares a worktree's branch against
  `$BRANCH`, so binding `BRANCH` from `HEAD` (which is the _base_ branch, since
  cleanup runs from the base checkout) made the guard pass on the primary
  checkout and would have removed the worktree running the cleanup. Verified.
  `BRANCH` is now bound to the PR's head branch from the forge.
- A runnable snippet with a placeholder in its source is itself an injection
  site, which the file's own bind-don't-paste rule had not been applied to.
  `x$(touch${IFS}/tmp/probe)` is a ref name git creates and will hold a
  worktree on; instantiating the worktree-parsing loop by substituting it into
  the text ran the command and matched nothing, while the same value bound to
  `$BRANCH` matched correctly and executed nothing.
- One branch can be the head of several open PRs against different bases, and
  deleting it closes them, so the pre-delete checks have to look in both
  directions: PRs whose _base_ is the branch (stacked on it) and PRs whose
  _head_ is the branch (sharing it). `gh pr list --head` cannot express a fork
  head, documenting that it rejects the `<owner>:<branch>` form, so that case
  needs the API's `head=<owner>:<branch>` filter (both verified).
- A value interpolated into a `gh api` path is parsed as a URL, not a string:
  a branch legitimately named `release#1` requests the rules for `release`
  (the `#1` reads as a fragment) and a `?` truncates likewise, while the
  percent-encoded form addresses the literal name. That is the only URL-path
  interpolation in the file; the other forge calls pass branches as option
  values, which the CLI encodes itself.
- `git worktree list --porcelain -z` emits NUL-terminated _fields_, so the
  first one is `worktree <path>`, not a path: extraction has to strip that
  keyword and pair the path with the `branch` field that follows. The loop now
  in the skill was executed against a spaced path, a newline-bearing path, and
  a sibling worktree, in both bash and zsh, before being written down. A
  forced layout can emit the same branch field for several records, so the
  preflight counts matches and stops unless the branch-to-worktree mapping is
  unique.

## Refute-first dispositions (destructive path)

Confirmed and fixed: worktree removal instructed from inside the worktree being
removed (git exits 0 and unlinks the cwd, so the next command dies); the
unnamed existence probe that a tag satisfies; the delete guard's dependence on
a forge-reported field; a head-branch delete with no stacked-PR check; a
dirty-tree gate that did not say which working tree it governs; no gate on the
merge having succeeded; undefined placeholders.

Rejected by verification, not to be re-raised: that `--no-overwrite-ignore`
might not exist or might not abort on some path (it aborts on all three forms
used here); that an explicit `refs/heads/X:refs/remotes/R/X` refspec could
leave a stale tracking ref and fake a successful resync; that the qualified
`ls-remote` pattern plus the exactly-one-line rule could admit a wrong ref (a
contrived match adds a line and so fails safe).

Accepted by decision: no issue-close verification and no forge-state merge
verification beyond the `MERGED` gate above (#74's non-goals, merge-cleanup's
territory); the stacked-PR and dirty-tree divergences named under Decisions.

Confirmed and fixed in the executable form: two vacuous matrix assertions
(a stray `--` argument made `want_call` grep for the literal string `--`,
which matches every logged gh call; proven by deleting the merge's head
pin while the matrix stayed green, and the pin now has biting coverage);
sign-extension of high bytes in the percent-encoder under bash 3.2, the
macOS system shell, which corrupted every multibyte name and fail-opened
the fork shared-head filter (masked to one byte, pinned by a multibyte
case); a failed `ls-files -v` read counting as "no flagged files"
immediately before the worktree removal; a deleted fork's null owner
collapsing the tab-separated field read (sentinel added, fails loud);
check silently degrading to the forge's head OID when no local branch
exists, against this note's own local-tip-primary decision (now a stop);
pre-merge answers going stale while the caller verifies its guardrails
(the merge phase re-asks the queue and consumer questions, since a stacked
PR's retarget can change the base and its queue, and a new PR can start
sharing the head); remote auto-resolution matching only the owner/name
tail (it now also requires the PR's forge host, a same-named mirror on
another host no longer resolves, and a URL with no host never
auto-resolves); a remote whose fetch and push destinations identify
different repositories (the existence checks read the fetch side while a
push writes **every** configured push URL, of which a plain push-URL query
returns only the first, so exactly one effective destination is required and
held to the fetch URL's identity, override flags included; SSH/SCP usernames
remain part of that
identity because a relative repository path can resolve differently for
two remote users, while HTTP(S) credential userinfo does not; transport is
also load-bearing, so HTTP(S), git, SSH URL, and SCP endpoints do not collide
on one host/path; auto-resolution filters to the authoritative clone
identities before preferring `origin`; the queries return
`insteadOf`/`pushInsteadOf`-expanded URLs, verified, so config rewrites are
covered by the same comparison, and both hosted and host-less URLs are
identified by their full paths, never a truncated tail, since
`/a/owner/name` and `/b/owner/name` are different repositories even behind
one hosted authority, while hosted path case and a terminal `.git` also
remain distinct because their equivalence is server-specific rather than a
Git URL guarantee, hosted authorities keep their port since two ports are
two endpoints, non-SSH userinfo strips at its last `@` so a `user:pass`
colon cannot truncate the host to the username, bracketed IPv6 SCP hosts
parse through their closing bracket, and the forge's lowercased
`owner/name` tail with its
`.git` suffix stripped is derived separately only for remote
auto-resolution; hosted and local identities carry explicit type tags so a
single-label host named `path` cannot collide with the local-path
discriminator, `file:///path` and `file://localhost/path` normalize to
Git's local absolute-path semantics, and other file authorities remain a
distinct identity instead of colliding with a relative path after blind
scheme removal; only the lowercase `file` scheme normalizes because live
Git verification showed an uppercase scheme invokes a missing remote
helper rather than the file transport, while `localhost` authority casing
does not change the target); the skill text steering
check toward the head worktree while the layout guard requires the base
checkout (worktrees share refs, so the base checkout of the pushing clone
sees the head tip; the text now says exactly that); the report serializer
dropping a path's trailing
newline (record-splitting escapers cannot represent it, the same byte the
worktree parser is hardened to preserve, so the escaper is now a byte-wise
shell loop); the current-worktree comparisons losing that byte the same
way (`--show-toplevel` through a command substitution strips it, so the
wrong-checkout and inside-target guards now compare inodes against the
relative `--show-cdup`, which is dots and slashes and cannot end in a
newline); the removal inventory being blind to the head worktree's own
paused operation state (operation state is per-worktree, so a merge paused
there with no tree delta left every file inventory empty while
`git worktree remove` deleted the worktree and its paused state with exit
0; the preflight's probes now also run against the worktree being
removed); a base repository that is itself a fork taking the deletion path
(its branch can simultaneously head a PR to its parent or root, so the
consumer guards now query the recorded lineage before the merge, and the
cleanup keeps the branch on the same grounds as a cross-repository head:
the network is unenumerable; if forge auto-delete is enabled, the merge now
stops before the forge can remove that branch ahead of cleanup); operation
pseudoref probes resolving same-named ordinary branches (all operation
markers now use their byte-faithful per-worktree paths); the no-CLI fallback
contradiction in the skill text (the skill table, exit-69 message, and
specification introduction now all require an equivalent authenticated host
CLI, so without one the only fallback is stopping at the open PR); control
bytes beyond the named escapes now encode as `\u00XX` instead of being
dropped from reports; remote-URL comparisons losing a trailing newline to
command substitution exactly as the worktree paths once did (single URLs
are now captured with a sentinel, and a remote whose raw configured URLs
carry a newline is a stop, since no line-based listing can compare it
faithfully); the local-branch containment check running after the worktree
removal it should gate (a branch repurposed with a clean commit after the
merge now stops the cleanup while its checkout still exists); containment
still accepting a branch repointed backward to an older base commit (cleanup
now requires the exact pinned tip, rejects symbolic head refs, and stops on a
separate linked head worktree before branch mutation because Git cannot lock
its HEAD, inventory, removal, and branch deletion as one operation; local
branch deletion is likewise left manual because neither `branch -d` nor
`update-ref -d` combines both required guards); report
strings now passing only printable ASCII through, with every other byte
encoded as a `\u00XX` code point equal to the byte, so the line stays
valid UTF-8 JSON even for a path byte outside UTF-8; and `core.ignorecase`
spellings other than `true` escaping the case fold (read with
`--type=bool`); a later page of branch rules hiding a merge queue (the
branch-rules read now paginates and aggregates before deciding no queue,
while a later-page failure or multiple queue rows stops); explicit remote
overrides bypassing forge identity (hosted overrides now match the
repository API's full authoritative HTTPS or SSH clone identity, while a
hostless path remains an explicit trust decision); and a root repository
with forks taking the deletion path (the validated `forks_count` now makes
the fork-network keep rule cover both fork members and their root, and
auto-delete stops a same-repository merge anywhere in that network);
userless SCP remotes falling through as trusted local paths (Git treats
`host:path` as SSH even without `user@`, so that form now carries hosted
identity); and the first fork appearing after cleanup cached repository
facts (fork-network membership is refreshed immediately before a
lease-protected delete, and a newly networked branch is kept).
The final prune also fails loud: discarding its exit status could report
cleanup complete while stale tracking refs remained after a ref conflict or
late network failure.

## Deferred

- The same hazardous command in the canonical merge recipe
  (`skills/agent-setup/references/canonical-sections.md`, mirrored in this
  repo's `AGENTS.md` pull-requests block). `devlog/2026-07-05-1041-worktree-merge-cleanup.md`
  kept it there as the single-checkout default with ignored-file safety
  explicitly out of scope as a "richer refinement"; that decision was made
  before the hazard was reproduced. The owner chose to leave it standing and
  track the canonical instance separately, since editing a managed block
  propagates to every downstream project that syncs it. Follow-up: #82.
- self-merge does not shut down a review watch still running for the PR it just
  merged, though it is the skill most likely to strand one (the project starts
  a watch at PR open and self-merge merges minutes later). That adds a
  capability rather than hardening the cleanup commands. Follow-up: #85.

## Revisit when

- A self-merge run reports a guard firing that this sequence has no
  instruction for.
- The canonical recipe in #82 is hardened, at which point the two texts should
  be compared for drift, not merged.
- Anyone establishes whether a forge reports a merged PR's `headRefOid` live or
  frozen at merge. If it is live, merge-cleanup's remote-delete guard, which
  prefers `headRefOid` where a CLI is present, is the weaker of the two files'
  versions and should adopt this one's local-tip primary. Not filed as work
  because the premise is unproven.
