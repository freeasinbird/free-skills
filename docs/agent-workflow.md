# Agent workflow reference

Step-local procedure that the core sections of AGENTS.md point at. Read
each section when its step arrives (the core names the step and the
section), not on every turn; once read, it binds exactly as the core
sections do.

## handing-off

The full handoff sequence; AGENTS.md's "Handing off the PR" section
summarizes it. Once the PR is up:

- **Start one review-watch per PR/reviewer as soon as the PR is open**,
  where the project records an automated reviewer or you have observed
  one, before waiting on checks, so the checks wait can't defer it.
  Prefer a dedicated review-watch skill, tool, or automation that can
  report back without manual polling; otherwise, if
  your platform can watch non-blockingly (a backgrounded poll or scheduled
  wake-up) and policy permits that mechanism, use it; don't pause to ask
  whether to watch. If a non-blocking mechanism would need permission not
  already granted, take the next permitted path. Where non-blocking support
  is absent, use a bounded foreground poll when it fits the current turn;
  otherwise hand back with the baseline and don't silently skip the review.
- **Anchor the watch baseline to the event that should produce the next
  reviewer pass**, not the moment the watch starts: the PR open/ready or
  actual push event for open/push-triggered reviews; the request time for a
  no-push recheck (marking ready, manually requesting review). Reviewer
  activity after that event is in-scope and must be handled, never absorbed
  into the baseline as already-seen. On a new push, advance or replace the
  baseline rather than leaving duplicate watchers running.
- **Validate against the current base before final handoff.** Resolve the
  current base tip, update the PR branch using the project's merge or rebase
  convention, rerun the relevant verification, and self-review the complete
  refreshed diff. Record the base commit used for that final validation in
  the PR's Verification section or the handoff. If the base advances again
  after handoff but before merge, the PR is stale and needs another
  integration pass. If you do not own the branch or lack permission to
  update it, report the stale state instead of silently rewriting it.
- **Wait for required checks**: poll them until they complete (on
  GitHub: `gh pr checks <n>`); fix any red check on the branch, never
  hand off a known-red PR.
- **Self-review the diff** (the self-review bullet under Pull requests)
  so it's ready for a reviewer.
- **Close out the watch before handoff**: poll for _both_ new review
  comments and CI, address in-scope findings on the branch, or record the
  bounded timeout / no-review result with the baseline; only then declare
  done. One exception: when the §review-convergence rule ends the exchange
  with a final triage push, don't wait out the re-review that push
  triggers; record with the baseline that it is intentionally left for
  the human to glance at during merge, and that satisfies this closeout.
- **Stop and summarize**: say the PR is open and green, and surface
  anything the reviewer should focus on. Leave merging, branch cleanup, and
  the `main` resync to whoever approves it.

## merge-and-resync

If the user does ask you to merge, merge with a real merge commit (on
GitHub: `gh pr merge <n> --merge`; where the repo's title-only
merge-message settings aren't confirmed set, pass the message
explicitly instead of inheriting the forge default:
`gh pr merge <n> --merge --subject '<PR title> (#<n>)' --body ''`),
resync the base branch as described below, re-resolve and validate the head
remote under the base branch's effective configuration, delete the remote
branch if the auto-delete setting didn't, delete the local branch
(`git branch -d <branch>`), and `git fetch --prune`.

In a single checkout, fetch the base first
(`git fetch <remote> refs/heads/main`), then land on the branch: with a
local `main` present (`git show-ref --verify --quiet refs/heads/main`)
that is `git checkout --no-overwrite-ignore main`, and without one
`git checkout --no-overwrite-ignore --no-track -b main FETCH_HEAD`, because a
bare checkout detaches `HEAD` at a same-named tag. After landing, re-resolve
the base remote under the configuration now in force and confirm its effective
URL still identifies the merged PR's base repository. For a branch created by
cleanup, then set `branch.main.remote` to that post-landing remote and
`branch.main.merge` to `refs/heads/main`; do not retain a pre-landing upstream
or leave the new branch untracked.

Fetch that base again into
its remote-tracking ref
(`git fetch <remote> refs/heads/main:refs/remotes/<remote>/main`), then
fast-forward with
`git merge --ff-only --no-overwrite-ignore refs/remotes/<remote>/main`. Not
`git checkout main && git pull --ff-only`: a plain checkout and pull's
merge step both overwrite an ignored file the base has started tracking
rather than aborting (`git pull` rejects `--no-overwrite-ignore`), and a
bare pull follows the configured upstream, which in a fork clone can be
the fork's stale copy.

When the work ran in a dedicated worktree (see Branches)
`git checkout main` refuses with "already used by worktree", so resync
`main` in the primary checkout and `git worktree remove <path>` the
feature worktree before deleting its branch. Run that removal from the
primary checkout too, never from inside the worktree being removed: git
has no self-target check, so a removal that would otherwise succeed
unlinks the directory the session is standing in and exits 0, leaving
every later command on a path that no longer exists.

## stacked-prs

Dependent docs or cleanup work can proceed without waiting for its base as an
intentionally declared stacked PR. A non-default base is an explicit
dependency: name the open PR's branch when creating both the follow-up branch
or worktree and the PR, never inherit it from the current checkout. On GitHub,
use `gh pr create --base <feature-branch>`; it auto-retargets to `main` when
the base merges, while other forges may require manual retargeting. Two
gotchas: while the base is open the stacked PR's diff shows only its own
commits; and if the base is force-pushed (the fold-review-fixes rule in
Commits), `rebase --onto` the stack onto the new base tip.

## reviewing-a-pr

The mirror of "Responding to automated review": hold the bar you'd want
held for you. Use the project's review tooling for the bug-hunting
pass where it has any, otherwise read the full diff yourself; these
are the conventions for the comments the pass produces.

- **Calibrate to severity, and tag it.** Separate blocking findings
  (correctness, security, data-loss, red tests/CI, broken invariants) from
  non-blocking ones (naming, style, optional simplification). Only blockers
  gate the merge. Don't manufacture speculative or contrived findings; the
  author convention is to decline those with a one-line reason.
- **Every comment carries evidence and a concrete ask.** Point at
  `file:line`, name the failure it causes, and propose a fix or ask a
  question. Mark uncertainty as uncertainty ("possible:"), never assert it;
  the Verification facts-only discipline applies to review too.
- **Review against intent, not just the diff.** Read the PR's Why/What and
  any linked decision note; check the change does what it claims, that
  Verification matches reality, and that docs/tests moved with behavior.
  Recorded decisions are evidence, not prohibitions: don't silently
  overturn an explicit owner decision; if the diff conflicts with one,
  name the decision and which assumption or condition changed.
- **Stay in scope.** Out-of-scope improvements are non-blocking nits or a
  follow-up issue, not merge-blockers; don't grow the PR through review.
- **Scale depth to risk.** Routine PRs get a normal pass; destructive /
  credential-leak / trust-boundary changes get the refute-first lens (see the
  finish line). A docs typo doesn't.
- **Resolve explicitly.** State what would unblock; let the author
  fix-or-decline. Resolving every thread isn't the gate; agreement on
  blockers is.

## review-convergence

- **Converge on a bar that rises with the rounds.** A reviewer whose
  findings stay individually valid can sustain an unbounded exchange,
  so severity, not validity, sustains the loop: blocking findings
  (correctness, security, data-loss, broken invariants, red CI) always
  earn another round. Judge that severity yourself against those
  categories, treating the reviewer's own tag as input, not verdict,
  and when unsure whether a finding blocks, treat it as blocking:
  uncertainty buys a round, not an exit. Past the early rounds a valid
  but non-blocking finding gets a disposition instead of a round:
  fixed in a final push when the fix is verifiable locally before
  pushing, deferred to a tracked follow-up issue that quotes the
  finding when it needs real work, or declined with a one-line reason;
  a round the loop pays for anyway dispositions every finding it
  raised on those same merits, never silently carrying one forward and
  never force-fixing one that rightly earns a decline. Don't
  under-converge: never declare a PR "addressed" while blockers are
  still arriving, and a finding that recurs from your _own_ incomplete
  fix is a miss to sweep, not a stop. What ends a blocker-sustained
  exchange is thrash, not a round count: the same finding recurring
  after a correct, complete fix, or fixes spawning new problems
  without net progress, means the change or the loop is broken, so
  pause and bring in the human with what is stuck; a long run of
  blocker-sustained rounds earns explicit, recorded
  continue-or-escalate calls, renewed as the run stretches, rather
  than a silent stop or autopilot continuation. Hand off with every
  finding dispositioned (fixed,
  declined, deferred, or explicitly outstanding) and any no-blocker
  call that ended the exchange stated for audit; the human arbitrates
  outstanding non-blockers at merge.
- For validation or parsing code, the mechanical sweep is an adversarial
  enumeration of the input space (case, spacing, indentation,
  prefix/suffix, order, duplication, nesting), run once as tests, not a
  widening of the cited pattern: pattern-widening spent eight review
  rounds on one class before the enumeration closed it.

## pre-push-review

- **Optional, risk-gated: a fresh-context pre-push review.** For non-trivial
  changes, or any repo without an external bot reviewer, get fresh eyes
  before pushing. **Where your platform and tools support delegation** (and
  it is allowed without asking), spawn a fresh-context reviewer: prompt it
  to _refute_, give it only the diff plus the PR's stated intent (not your
  reasoning trail), and let it hunt correctness, security, and edge-case
  failures. **Where they don't** (no subagent concept, or delegation needs
  explicit permission), skip it and lean on the external bot / human review,
  or ask the user first; never emit steps the running agent can't perform.
  A same-model subagent is only _partially_ independent and costs tokens;
  scale to risk, skip trivial or mechanical work.

## reviewer-record

- **Record a noticed automated reviewer.** When you observe a bot-authored
  review on a recent PR, or a reviewer status signal (a bot reacting on PR
  descriptions shortly after they open, recurring across PRs: a reviewer
  whose passes have all been clean may never post a review), and the project
  hasn't recorded the reviewer, add a compact
  record (an "Automated reviewer" entry; the required fields below usually
  take a short paragraph) to an unmanaged, project-specific section of
  AGENTS.md
  (outside `agents-md:managed:*` blocks, so syncs don't overwrite it) with
  enough identity to match its future reviews: the reviewer's **name**, its
  **login/account identity** (including the API-specific form when it
  differs, e.g. a `[bot]` suffix in one API but not another), how it is
  **triggered** (automatic on PR events, a manual command, or a CI job), and
  any **status signals** it posts out of band (an in-progress or clean-pass
  indicator, e.g. a reaction on the PR description; some reviewers post no
  review at all on a clean pass, so the recorded clean-pass signal is what
  lets a later watch finish instead of timing out). Later sessions filter
  review activity by that login, so the identity, not a bare "a reviewer
  exists", is the point. An existing record is not a reason to skip: when
  you observe status signals (or a changed trigger) the record lacks,
  augment it in place, since a name/login/trigger-only record still forces
  the full wait cap on clean passes. Record only a reviewer and signals you
  actually observed, never an absence.

## pr-body

The PR body sections, as the repo's PR template scaffolds them:

- **Why**: prose, one to three short sentences. State the problem or
  motivation. Link the decision note when one exists; don't duplicate it.
  Where the template's comment spells out issue keywords, follow it
  exactly: a close keyword per issue the PR fully resolves, a plain
  `Refs #N` for related-but-unfinished issues that are left for a
  human to close.
- **What**: required bullets. Describe work-unit outcomes, not
  file-by-file churn. For multi-commit PRs, use a compact commit map
  (one bullet per commit or concern), referencing each commit by its
  subject, not its SHA: folding a review fix into its commit (see
  Commits) rewrites every downstream SHA, so a SHA-keyed map forces a
  body rewrite each round, while subjects don't go stale. Say rejected
  alternatives live in the decision note when they do.
- **Screenshots**: required for PRs with visible UI changes; delete it
  for non-visual work. Replace the section with actual forge-hosted,
  reviewer-visible image or recording attachments before handing off,
  and in every case before merge; local paths, textual descriptions,
  and "checked locally" notes do not satisfy it. If you cannot attach
  the artifacts yourself, say so at handoff and ask the user to add
  or confirm them before merge. Show the changed surfaces,
  important states, and every theme or appearance mode the change
  affects. Keep captions short and name the state shown. Verification
  still belongs in Verification.
- **Review Notes**: optional bullets; delete the section when it adds
  no routing value. Use it to point reviewers at important files, review
  order, mechanical commits, or risky edges.
- **Verification**: required bullets. Start each with `Passed:`,
  `Checked:`, `Attempted:`, or `Not run:`. Say what was actually run and
  observed: tests, lint, fixture/screenshot checks (every affected theme
  for UI), round-trips for schema changes. Facts only, never
  "should work"; verification gaps are explicit `Not run:` bullets.
  Factual doc claims ship under the same discipline: counts, flags,
  behaviors, and runtime guarantees are checked against the code and
  scoped to the surface they describe, stated without marketing or
  competitor put-downs.

## refute-first

For changes on a **destructive path** (delete/cleanup), a
**credential-leak surface**, or a **returned-object-trust boundary**
(trusting fields of a value handed back by an external call or
deserializer), add a refute-first verification pass before committing
(independent lenses whose job is to _disprove_ the fix) and record
which findings were confirmed, rejected-by-verification (so they're
not re-raised), and accepted-by-decision: in the work unit's decision
note where the project keeps one, otherwise in the PR or issue. For a
behavior-preserving refactor on one of these paths, where the platform
can execute code, have a lens reconstruct the
old implementation (`git show <base>:<file>`) and compare old against new
decision-for-decision over a fuzzed corpus; a diff-read can only assert
equivalence, a harness measures it. Scope all of this to those risk
classes; a docs typo or a refactor off these paths shouldn't trigger it.
