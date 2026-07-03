# merge-cleanup skill

New skill from reflection-notes candidate 1: "PR merged, please clean up"
recurred in 27 sessions across five repos, and the sequence lived in
AGENTS.md with no trigger. The skill adds the trigger plus two asks that
never landed: verifying close-keyword issues actually closed (surface,
never auto-close; consistent with the 2026-06-20 decision that rejected a
post-merge comment step, this only verifies and only when cleanup was
requested) and shutting down a stale review watch (gated; await-pr-review's
watcher has no stop mechanism and self-terminates, so the no-capability
fallback wording states that).

## Decisions

- Draft-only scope, user's call: no trigger evals, description
  optimization, or behavioral evals this session.
- self-merge left untouched; its "Merging and cleanup" section duplicates
  the resync steps. Both skills stay self-contained (installed separately).

## Refute-first pass (destructive path)

One fresh-context lens prompted to disprove safety. Confirmed and fixed:
the no-tool fallback validated branch identity instead of merge status (the
data-loss hole; now: no remote delete without merge confirmation, hand the
user the command); no default-branch tripwire (`git branch --merged` output
could resolve `<branch>` to `main`; now a hard abort); stacked-PR check was
an unmandated conditional (now an explicit `gh pr list --base` step with a
no-CLI ask-the-user fallback); squash/rebase repos dead-ended verification
and `-d` (now: forge `MERGED` is the verification there, `-D` permitted
only with `headRefOid` match); dirty-tree guard sat after a checkout that
can succeed over changes (now a `git status --porcelain` pre-check);
non-default-base PRs verified/resynced the wrong branch (now `baseRefName`
aware). Rejected by verification, don't re-raise: -d-to--D escalation
wording, force/reset on diverged default, auto-closing issues, silent
stash, deleting the checked-out branch, wrong-but-merged PR number (binds
deletion to the verified PR's own head, so annoying, not destructive).

## Review round (PR 52)

Codex round 1: two P2s, both the non-default-base class that the refute
pass's finding six patched too narrowly (step 1 retargeted stacked PRs to
the default branch instead of the merged PR's base; step 2 still checked
out the default branch, so pull and `-d` validated against a branch that
hadn't moved). Second member of a class already swept once, so the
boundary was widened: the sequence, intro, and description are now
base-branch-aware throughout, with the default branch mentioned only as
the usual case. Folded into the skill commit.

Codex round 2: one P1, remote deletion deleted whatever the ref currently
pointed at after verifying only that the old PR merged, so a branch reused
or advanced post-merge could lose unmerged work. Step 1 now requires the
`git ls-remote` OID to match the PR's `headRefOid` before the remote
delete, or stops. This partially disproves the round-zero rejected-finding
rationale "binds deletion to the verified PR's own head": that held for
the local `-d`/`-D` path, not the remote one; the rejected list stands
otherwise. Folded into the skill commit.

Codex round 3: one P2 against round 1's own fork-remote sentence, which
made `origin` stand for the head remote and so pointed merge verification
and resync at a fork's stale base branch. The identify section now splits
the roles: head remote for existence check and deletion, base remote for
verification and resync. Folded into the skill commit.

Codex round 4: one P2, a bare `git pull --ff-only` could pull the fork's
stale copy via the branch's configured upstream. Second member of the
remote-explicitness class (round 3 was the first), so the class was
widened and every git command in the file enumerated under fork-clone
semantics: the pull now names `<base-remote> <base-branch>`, both "after
a fetch" phrases name the base remote, and the prune names both remotes
when they differ; ls-remote/push --delete already named the head remote,
and status/checkout/branch -d/merge-base are local by design. Folded
into the skill commit.

Codex round 5: one P2, the identify example's `--json` field list lacked
the `headRefOid` that steps 1 and 4 compare against, forcing an unstated
second lookup at deletion time; the field is now collected up front.
Severity across rounds narrowed steadily (core guards, then base-branch
awareness, then remote-delete OID, then fork remote roles, then a field
list), so convergence is close.

Codex round 6: one P2, the stacked-PR check ran `gh pr list --base` in
the current/base repository, but stacked PRs live where their base branch
does, so a fork-hosted head made the check falsely empty right before
deletion. The check now runs against the repository that owns the branch
(`--repo` the fork when the head lives there). This was the forge-command
member of the remote/repo-role class the round-4 git-command enumeration
missed; the other `gh` commands address the PR itself, which lives in the
base repository, so they were already correct.

Codex round 7: one P2, the identify example's `--json` field list still
lacked the head-repository fields (`headRepository`,
`headRepositoryOwner`, `isCrossRepository`) that the round-3 remote-role
split and the round-6 stacked-PR `--repo` check both consume, so a
cleanup starting cold on a fork-based PR had no instructed way to learn
which repository owns the head. The fields are now collected up front and
both consumers reference them. This joins round 5's class (the initial
lookup must collect what later steps consume) with the fork-role class;
as the second recurrence after two sweeps, the PR's one adversarial
refute pass was spent here: a read-only lens tasked to disprove the
file's fork-clone correctness end to end, so remaining members surface in
one shot instead of over more rounds. The lens confirmed two more
members, fixed in the same fold: the identification fallback's
`git branch --merged` hardcoded `origin` for the base-branch ref (fork
origin means a stale default branch, defeating the fetch the same
sentence mandates), and the single-remote sentence wrongly equated the
remote roles when the sole remote is the base repository and the fork
head was checked out ad hoc (head-remote steps now go to the fork
directly, by URL or forge CLI, never the base remote standing in; the
destructive variant was already blocked by the `headRefOid` guard, the
silent skip was not). Nothing else in the file survived the lens's
enumeration. Folded into the skill commit.

Codex round 8: one P2, a new class (ref-name ambiguity, not fork roles):
`ls-remote` patterns match ref tails, so the bare `<branch>` in the
remote OID guard also matches `bar/<branch>`, and a stale suffix-mate
still at `headRefOid` could green-light deleting the moved real branch.
Swept as a class: every git command that resolves or compares `<branch>`
on a deletion path now spells `refs/heads/<branch>` (the ls-remote guard,
which also now requires exactly one returned line; the remote delete; the
merge-base ancestry check, where dwim resolution lets a same-named tag
shadow the branch; and the `-D` tip confirmation, now an explicit
`git rev-parse refs/heads/<branch>`), with the rule stated once beside
the hard rules on the resolved name. `branch -d`/`-D` and `checkout`
stay bare: they operate on or prefer local branches by construction.
Folded into the skill commit.

Codex round 9: one P2, `git branch -d` was described as refusing when
the branch isn't merged into HEAD, but git checks against the branch's
upstream when one is set, and pruning happens a step later, so the
still-present `origin/<branch>` makes `-d` delete with a mere warning
regardless of the resynced base. Step 4 now runs the check itself
(`merge-base --is-ancestor` against HEAD, else the
`-D`-with-matching-`headRefOid` path, else stop). Second member of the
implicit-guard-trust class (the round-zero refute pass's
checkout-over-dirty-tree was the first), so the class was enumerated:
`pull --ff-only`'s refusal is unconditional and stays trusted; every
other destructive step already carries an explicit guard. Folded into
the skill commit.

Codex round 10: one P2, the base side of the merge verification
(`origin/<base-branch>`) has the same dwim hole round 8 fixed on the
branch side: revision lookup tries `refs/tags/` before `refs/remotes/`,
so a stray tag named `origin/main` could green-light the remote delete.
Second member of the ref-ambiguity class after its sweep, so the
boundary widened from "the branch name" to "every ref a deletion-path
guard resolves": the rule sentence now covers remote-tracking base refs,
and the merge-base base side plus the `git branch --merged` fallback are
fully qualified. Deliberately left bare: `checkout <base-branch>`
(prefers the local branch; the qualified form detaches HEAD) and the
`pull <base-remote> <base-branch>` refspec (remote-side resolution
checks `refs/heads/` before `refs/tags/`, so tag shadowing cannot occur
there, and `--ff-only` fails loud regardless). Folded into the skill
commit.

Codex round 11: one P2, the `ls-remote` OID guard and the remote delete
were check-then-act, so a push landing between them still lost new work.
The delete now carries
`--force-with-lease=refs/heads/<branch>:<headRefOid>`, making the guard
a compare-and-swap; verified in a scratch bare repo that a lease
mismatch rejects the deletion ("stale info") and a match deletes. The
round-9 enumeration had seen this race and skipped it as unlikely; that
was a miss, since the fix is one flag. Other check-then-act pairs
enumerated: the stacked-PR check → delete window is not data loss (an
orphaned just-opened PR is retargetable, and no CAS can cover it) and
the local checks are single-user, so the lease is the only member that
needed closing. Folded into the skill commit.

Codex round 12: one P1 and one P2. The P1: `<branch>` is PR-supplied and
a valid ref name can contain `$`, `;`, or parentheses, so raw
substitution into a shell command executes before git sees it. New hard
rule (PR-supplied names are untrusted shell input, substitute
single-quoted, stop on a name containing a single quote, which quoting
cannot carry), and every command example now shows the quotes; swept as
the full set of substitution sites, not just the cited delete. The P2:
the `git branch --merged` fallback told the agent to ignore the current
branch, but the workspace often still sits on the just-merged branch, so
discarding it could crown an older stale merged branch the only
candidate. The ignore list is now the default/base branches only; step 2
switches away before deletion and the ambiguity rule still forces asking
when several candidates remain. Folded into the skill commit.

Codex round 13: one P2, a recurrence of the repo-role class after the
round-7 refute pass. Round 6 asserted the `gh pr view` PR-record calls
were "already correct" because the PR lives in the base repository, but
that conflated where the PR lives with how `gh` resolves a bare number:
in a fork clone `gh pr view <n>` targets the CLI's default repository
(the fork, or unset), handing a different PR's `headRefName`/`headRefOid`
to the deletion guards. This is a `gh`-resolution axis the round-7 lens
(git remote roles) never examined. Swept the `gh` PR-record class: the
identify `gh pr view` and the issue-close `gh pr view` now both pin
`--repo '<base-repo>'` (resolved from the PR URL/context); the stacked-PR
`gh pr list --base` was already pinned to the head/fork repo (round 6)
and stays, since stacked PRs live where their base branch does. All three
`gh` calls in the file are now repo-pinned. Folded into the skill commit.

Codex round 14: one P2, a recurrence of the base-branch-awareness class
(round 1's), surviving both round 1's sweep and round 10's ref
qualification of the same command. The identify fallback still ran
`git branch --merged` against `<default-branch>`; for a PR merged into a
non-default base the just-merged feature branch need not be merged into
the default, so the fallback could omit it and surface an older branch
merged to the default as the only candidate, aiming cleanup at the wrong
branch. Now queries `refs/remotes/<base-remote>/<base-branch>`, with an
ask-the-user fallback when the base can't be determined without the CLI.
Swept the class: lines 20, 54, 138, 173 use "default branch" correctly
(descriptive of the usual case, or the deletion guard that aborts on both
default and base), so line 44 was the only functional instance. Folded
into the skill commit. Same round: rebased the branch onto `main`
(`b3b0dd7` -> `487830e`) to clear a README skills-table conflict from
merged sibling PRs; the resolution keeps both new rows in alphabetical
order.

Codex round 15: two P2s, both recurrences of classes prior work treated
as closed. (a) The `git branch --merged` fallback: round 14's default ->
base fix was necessary but insufficient, since `--merged <base>` lists
only branches whose tip is an ancestor of the base, which a squash or
rebase merge never makes the just-merged branch, so it is omitted
entirely and filtering can leave a stale older branch as the only
candidate. The fallback now treats `--merged` output as candidates to
confirm, not the answer, and asks the user when the merge was
squash/rebase, the branch isn't known from context/forge metadata, or the
output is ambiguous. (b) The step-3 resync refspec: round 10 deliberately
left `git pull <base-remote> <base-branch>` bare, reasoning remote-side
resolution checks `refs/heads/` before `refs/tags/` so tag shadowing
can't occur. That rationale was empirically false: a scratch repo with
both `refs/heads/release` and `refs/tags/release` had
`git pull origin release` write the tag to `FETCH_HEAD` (verified: bare
fetched the tag OID, `refs/heads/release` fetched the branch OID), leaving
the base unmoved before step 4 deletes against it. The refspec is now
`refs/heads/<base-branch>`, and the ref-ambiguity rule notes bare
fetch/pull refspecs share the hazard. Self-swept both classes rather than
spending a fan-out (offered to the user, who was away): every ref-taking
git command was enumerated; line-150 pull was the only remaining bare
remote-side ref and the identify fallback the only unhandled squash/rebase
inference (verify and step-4 delete already handle it). Folded into the
skill commit.

Codex round 16: one P2, the third consecutive ref-ambiguity recurrence,
this time on the one command round 15's sweep had cleared as "bare by
design": `git checkout '<base-branch>'`. Verified in a scratch repo that
with no local base branch and a same-named tag, bare `git checkout release`
detaches `HEAD` at the tag (tag OID, not the branch OID), after which
step 3 would fast-forward a detached `HEAD` and step 4 validate/delete
against it while the real base stays stale. Step 2 now switches by bare
name only when a local base branch exists, else creates it explicitly with
`git checkout -b '<base-branch>' 'refs/remotes/<base-remote>/<base-branch>'`;
the checkout exception note was corrected (it cannot be qualified, and a
bare name is safe only when the local branch exists).

Because three straight rounds each surfaced one more member of the
ref/repo-role class that prior single-context sweeps had declared closed,
spent one independent read-only fresh-context reviewer (a single review
subagent, not the multi-lens fan-out, which the user was away to approve)
to refute the whole file's git/gh correctness with scratch-repo repros
before pushing. It confirmed the destructive core sound under test
(lease-on-delete CAS, ls-remote single-line, checkout guard, qualified
rev-parse/merge-base/pull) and found two example-vs-prose gaps folded into
this same push: (1) the `gh pr list --base` example omitted the inline
`--repo` that every other `gh` example carries, so a bare call resolves
against the CLI default repo and the stacked-PR check comes back falsely
empty right before the delete, orphaning stacked PRs, a real round-13
repo-role recurrence that round 13's own sweep missed (it was pinned in
prose, never in the example); the example now pins `--repo '<head-repo>'`.
(2) `git fetch --prune` named no remote though the prose said to prune the
head and base remotes; now `git fetch --prune '<head-remote>'`. Declined
its soft finding 3 (git-only merge verification keys off local
`refs/heads/<branch>` rather than `headRefOid`): that ancestry check is the
no-CLI fallback, where the forge's `headRefOid` isn't available (with the
CLI you use `MERGED` state, not this check), and remote deletion is
separately gated by the ls-remote OID match plus lease, so a stale-local
false-positive can't by itself delete a remote branch.

Gotcha (watch tooling, not the skill): two review watches were launched
with full head SHAs expanded by guess from short prefixes; the fabricated
tails matched nothing, one watch burned its full cap on an already-landed
review, and the round-4/5 reviews were picked up manually. Full SHAs must
come from `git rev-parse`, never from completing a short prefix.

Codex round 17: one P2, a new class (tracking-ref availability, distinct
from the ref-name ambiguity of rounds 8/10/16): round 16's step-2 fallback
`git checkout -b '<base-branch>' 'refs/remotes/<base-remote>/<base-branch>'`
reads the base remote-tracking ref, but a fresh, single-branch, or sparse
clone that verified the merge through the forge `MERGED` state need never
have fetched the base, so that ref can be absent and `checkout -b` aborts
on the missing start-point after step 1 already deleted the remote branch,
leaving cleanup half-done. Step 2 now fetches the qualified base ref into
its tracking ref (`git fetch '<base-remote>'
'refs/heads/<base-branch>:refs/remotes/<base-remote>/<base-branch>'`) before
the fallback checkout. Swept the class (every command that reads the base
tracking ref): the identify `git branch --merged` (line 44) and the
merge-verify `merge-base --is-ancestor` (line 109) already state "after
fetching the base remote", so step 2's checkout, added only last round, was
the sole unguarded read. Folded into the skill commit.

Codex round 18: one P2, a recurrence of the field-completeness class
(round 5's `headRefOid`, round 7's head-repo fields: the initial lookup
must collect what later steps consume). The issue-close example fetched
`--json closingIssuesReferences` but the prose then scans the merged PR
body for close keywords the forge missed, and the body is exactly the
fallback data when `closingIssuesReferences` is empty (cross-repo,
non-default base, keyword typo), so an agent following the example had no
body to scan. Swept every `--json` call against its consumers rather than
patching the cited line: the identify lookup (line 40) already carries all
eight fields its guards read; the issue-close call was the only incomplete
one. The sweep also found a sibling the citation missed and empirically
confirmed (`gh pr view --json closingIssuesReferences` returns id, number,
repository, url but **not** state): the prose says "check each referenced
issue's state", but that state isn't in the payload, so a per-issue
`gh issue view '<n>' --repo '<issue-repo>' --json state` is now specified,
pinned to the repository the reference names (cross-repo issues live
outside the base repo). Both folded into the skill commit. User away, so
self-swept the class by hand (per the round-15 precedent) rather than
spending the round-7/16 refute pass again.

Codex round 19: one P2, another fork-role-class recurrence (rounds
3/4/6/7/13), a new member: round 6 fixed where the stacked-PR check looks
(`--repo` the fork); this is the retarget action itself. A PR stacked on
`<branch>` in a fork has the fork as its base repository, and neither
GitHub's auto-retarget nor `gh pr edit --base` can move a PR across
repositories (the new base must be a branch in the PR's own repo), so
retargeting only renames its base to the fork's copy of the merged base
branch, not the upstream base that received the merge, silently aiming
follow-up at the wrong repo/diff before the fork branch is deleted. Step 1
now says: verify the retarget landed (not just assume it), and where it
can't cross to the merged PR's base repository, surface the stacked PRs for
the user to recreate against the correct base and delete only then. Swept
the cross-repo-action dimension: the remote delete (head remote), verify
and resync (base remote), and the new issue-state read (`gh issue view
--repo`) are already role-correct; the stacked-PR retarget was the only
cross-repo write assuming same-repo semantics. Folded into the skill
commit.

Note on convergence: this is the fork-role class recurring a third time
after two adversarial passes claimed to have swept it end to end (round 7's
refute lens, round 16's independent reviewer, which said "nothing else
survived"). Each recurrence is a genuine distinct member, not thrash, so
each was worth fixing, but the pattern says the class is deeper than a
single-context sweep closes. Flag for the human at handoff: either accept
the current convergence or authorize a fresh multi-lens fan-out (which the
away user hasn't approved, and "no quiet fan-out" forbids launching
unilaterally).

Codex round 20: one P2, a new class (ignored-file overwrite, not fork-role
or field-completeness): the step-2 dirty-tree guard reads
`git status --porcelain`, which does not report ignored files, so an
ignored file the base branch still tracks (a local `.env` gitignored and
untracked on the current branch, but tracked on the base) passes the guard
and the subsequent checkout silently overwrites it, destroying local
secrets. Verified both halves in a scratch repo: default `git checkout`
clobbered the ignored `.env` with an empty `--porcelain`; adding
`--no-overwrite-ignore` aborted the checkout (exit 1) and preserved the
file, on both the plain and the `-b` path. Both step-2 checkouts now carry
`--no-overwrite-ignore`, and the guard prose notes `--porcelain` misses
ignored files and that the abort is surfaced like a dirty tree. This is a
genuinely distinct class from rounds 17-19 (data loss via working-tree
overwrite, not ref/repo resolution), so convergence isn't stalling on one
class; the reviewer is covering a broad, high-stakes surface, and each
round's finding has been real. Folded into the skill commit.

Codex round 21: one P2, the second member of round 20's ignored-file
overwrite class, surfaced by my own too-narrow round-20 sweep: I guarded
the two checkouts but not step 3's `git pull --ff-only`, whose merge step
also updates ignored files by default, so a fast-forward whose base starts
tracking a path the workspace holds as an ignored file clobbers it (a miss
to sweep, not convergence). Per the escalation rule, widened the class from
"checkout" to "every working-tree-updating command" and enumerated it:
checkout x2 (guarded round 20), pull/merge (this round); fetch, branch
-d/-D, push, and the read-only queries never touch the working tree, so the
class is now complete. Step 3 is now `git fetch` (qualified source ref)
then `git merge --ff-only --no-overwrite-ignore` on the tracking ref,
preserving the fork-upstream and tag-shadowing protections (named remote,
qualified ref) and the ff-only no-diverged-fix rule. Verified in a scratch
repo: plain `git pull --ff-only` clobbered an ignored `.env` (porcelain
empty); `git pull --no-overwrite-ignore` is rejected as an unknown option
(pull does not forward it); `git merge --ff-only --no-overwrite-ignore`
aborts (exit 1) and preserves the file. Self-swept the full working-tree
class by hand with scratch repros rather than the escalation's refute
fan-out (user away, "no quiet fan-out"); the enumeration is small and
mechanical enough to close by inspection. Folded into the skill commit.

Separate review (relayed by the user, non-Codex), two P2s + a stale-body
P3:

- P2, git-only path vs `headRefOid`: the verify section offers a git-only
  merge check (`merge-base --is-ancestor`), but step 1's OID match and lease
  both key off `headRefOid`, which only the CLI supplies, so a no-CLI run
  dead-ended or would invent the OID. Fixed by defining a **verified head
  OID** in the verify section: `headRefOid` with the CLI, else the local
  branch tip (`git rev-parse 'refs/heads/<branch>'`), valid because the
  git-only path only verifies merge-commit/ff merges, where the local tip is
  the merged head; the squash/rebase path has no git-only verification and
  so always carries the CLI. Step 1 now matches and leases against that
  verified OID. This retires the round-16 decline's assumption that "remote
  deletion is separately gated by the ls-remote OID match plus lease" held
  without a CLI: those gates themselves needed `headRefOid`, so the no-CLI
  path had no expected OID at all until now.
- P2, literal `origin` in destructive commands: despite the fork-role split,
  the step-1 `ls-remote` and `push --delete` examples used a bare `origin`,
  which in a fork is the base repo or absent as the head remote, relying on
  prose to redefine `origin`. This is the fork-role class again, from a third
  source now (Codex 3/4/6/7/13, then this review). Swept every literal
  `origin` rather than the two cited lines: the two destructive commands now
  name `<head-remote>`; the identify-section stand-in sentence now says the
  commands name `<head-remote>`/`<base-remote>` explicitly (no bare
  `origin`); the tag-shadow example (`origin/<base-branch>`) and the step-4
  tracking-ref mechanic (`origin/<branch>`) now use the role placeholders.
  The only `origin` left is the one telling the reader not to use a bare
  `origin`.
- P3, stale PR body: already refreshed at the prior hand-off (What now spans
  the full review arc, not just round 1); re-refreshed here for the two
  fixes above. Verified the current body no longer matches the "round 1
  only" description the review saw.

Codex round 22 (after the relayed-review push): one P2, a new class
(linked-worktree awareness). The sequence assumed one working tree, but
this project's own dedicated-worktree convention means the base branch is
usually already checked out in the primary worktree while cleanup runs in
the feature branch's worktree. Verified in a scratch repo that this breaks
three steps, not just the cited checkout: `git checkout '<base-branch>'`
fatals with "already used by worktree" (exit 128); a fetch/merge into the
base branch fatals with "refusing to fetch into branch checked out at ..."
(so step 3 can't resync it either); and `git branch -d '<branch>'` refuses
while `<branch>` is checked out in a worktree. So the linear sequence stalls
after step 1 already deleted the remote branch. Added a worktree preflight
before step 1: detect with `git worktree list`, and when the base branch or
`<branch>` is held by another worktree, resync in the worktree that owns the
base and `git worktree remove` the feature worktree before its `-d`, or stop
and surface rather than deleting the remote into a stalling sequence. Chose
detect-and-guide (+ stop-and-surface), not full cross-worktree automation:
removing a user's worktree and operating across worktrees are design calls,
so those are flagged for the human rather than silently automated. This is
an additive guard in the same detect-hazard-or-stop shape as the dirty-tree,
stacked-PR, and fork-remote guards, so it doesn't restructure existing
steps.

## Deferred

- Trigger-eval set + description optimization; when run, use a scratch
  `CLAUDE_CONFIG_DIR` so probes don't flood `~/.claude/projects`.
- Behavioral sandbox evals (fixture git repo) for the cleanup sequence.
- await-pr-review has no watch-stop mechanism; possible follow-up there.
