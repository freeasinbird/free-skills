# Canonical Managed Sections

Each section below is the exact text to insert into a project's AGENTS.md,
including the management markers. During init, paste verbatim, except the
`agents-md:project:done-checks` block inside `done`, which is a placeholder
to fill with the project's real checks (see SKILL.md). During update,
compare the content between markers against these blocks, leaving that
nested block alone.

Sections: [devlog](#section-devlog),
[finish-line](#section-finish-line), [branches](#section-branches),
[pull-requests](#section-pull-requests), [commits](#section-commits),
[done](#section-done).

---

## Section: devlog

<!-- agents-md:managed:devlog -->

## Devlog (session bookends)

`devlog/` holds the reasoning trail: one short entry per working
session. `devlog/README.md` is the protocol: entry naming, density
target, structure, and when an entry may be revised.

- **Before starting:** read the most recent one or two entries
  (`find devlog -maxdepth 1 -type f -name '*.md' ! -name README.md | sort | tail -2`);
  they carry decisions and deliberate deferrals that aren't in the spec.
  Don't re-litigate or "fix" what an entry marks as decided/deferred without
  the user asking. Also grep the devlog for the open `## To promote` /
  deferred / needs-human queue so promotions don't span sessions unnoticed.
- **Before finishing:** append `devlog/YYYY-MM-DD-HHMM-slug.md`: decisions
  (why, and what was rejected), deferrals, open questions. Note anything
  that should be promoted to AGENTS.md: a new invariant discovered, a
  convention that wasn't written down, a gotcha that bit you; the entry
  records it, a follow-up commit promotes it. Commits and PR threads carry
  the what-changed.

<!-- /agents-md:managed:devlog -->

---

## Section: finish-line

<!-- agents-md:managed:finish-line -->

## Default agent finish line

For any user request that asks you to change code, docs, assets, or project
state, the default endpoint is **an open, review-ready PR with required
checks green**, not a merged branch. Merging is a human decision; do not
merge your own PR unless the user explicitly asks, or the project has adopted
an opt-in self-merge workflow.

Use this checklist for each work session:

1. Read README plus the latest devlog entries, then start from `main`, or,
   for a follow-up that depends on an open PR, from that PR's branch (see
   Stacked PRs under Pull requests).
2. Create one correctly named branch for the work unit.
3. Make the scoped change, including docs/devlog/tests/assets that keep it
   complete.
4. Run the relevant verification plus the standard lint/build/test checks
   before PR; if any check cannot run, record the exact gap in the PR.
5. Commit one concern at a time with a body that says why.
6. Before opening a docs/chore PR (or at session end), grep the devlog
   for the open `## To promote` / deferred / needs-human queue and clear
   what the current scope covers, or explicitly re-defer; decided
   invariants shouldn't live only as devlog archaeology.
7. Push, open the PR with the template, and remove sections that do not apply.
8. Hand off per "Handing off the PR" (under Pull requests): start the
   review-watch, wait out required checks, handle reviewer activity,
   self-review the PR files view, and leave the PR open for a human to
   review and merge.

For changes on a **destructive path** (delete/cleanup), a
**credential-leak surface**, or a **returned-object-trust boundary**
(trusting fields of a value handed back by an external call or
deserializer), add a refute-first verification pass before committing
(independent lenses whose job is to _disprove_ the fix) and record in
the devlog which findings were confirmed, rejected-by-verification (so
they're not re-raised), and accepted-by-decision. For a
behavior-preserving refactor on one of these paths, where the platform
can execute code, have a lens reconstruct the
old implementation (`git show <base>:<file>`) and compare old against new
decision-for-decision over a fuzzed corpus; a diff-read can only assert
equivalence, a harness measures it. Scope all of this to those risk
classes; a docs typo or a refactor off these paths shouldn't trigger it.

<!-- /agents-md:managed:finish-line -->

---

## Section: branches

<!-- agents-md:managed:branches -->

## Branches

All work lands through a PR: branch from `main` (read `main` as the
repo's default branch throughout), do the work as atomic commits (see
Commits), open a PR; the work merges with a real merge commit, a
human's call per the finish line. Never commit directly to `main`. No
triviality exception: every bypass erodes the `--first-parent`
narrative.

Name branches `<type>/<short-kebab-slug>`: type from the Conventional
Commits vocabulary (`feat`, `fix`, `refactor`, `docs`, `chore`), slug
2–4 kebab-case words naming the work unit:

```text
feat/worksheet-promotion
fix/pane-focus-race
chore/swift-format-sweep
```

Exactly one slash: refs are path-like, so `feat/x` and a branch named
just `feat` can't coexist. No ticket numbers, dates, or owner prefixes;
prepend an owner segment (`bnw/feat/…`) only if multiple people or
agents start pushing in parallel. Merged branches auto-delete where
that repo setting is on (delete them after merge where it isn't); the
merge commit carries the narrative.

Follow-up work that depends on an open PR can stack on its branch instead
of waiting; see the Stacked PRs pattern under Pull requests.

<!-- /agents-md:managed:branches -->

---

## Section: pull-requests

<!-- agents-md:managed:pull-requests -->

## Pull requests

A PR is one work unit, reviewed as a whole and merged with a real merge
commit. Commits carry the atomic why (see Commits); the PR carries the
arc.

- **Title**: imperative, ≤ 72 chars, names the outcome, no type prefix
  or ticket noise ("Fix missing menu bar on unbundled launch"). In the
  intended repo setup the PR title and body become the merge commit
  message, so `git log --first-parent` reads as the list of PR titles;
  write the title for that log either way.
- **Body**: scaffolded by the repo's PR template (on GitHub:
  `.github/pull_request_template.md`):
  - **Why**: prose, one to three short sentences. State the problem or
    motivation. Link the devlog entry when one exists; don't duplicate it.
    Where the template's comment spells out issue keywords, follow it
    exactly: a close keyword per issue the PR fully resolves, a plain
    `Refs #N` for related-but-unfinished issues that are left for a
    human to close.
  - **What**: required bullets. Describe work-unit outcomes, not
    file-by-file churn. For multi-commit PRs, use a compact commit map
    (one bullet per commit or concern) and say rejected alternatives live
    in the devlog when they do.
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
- **Self-review the diff in the PR files view before handing off**: seeing
  the whole change as one artifact catches stray hunks, leftover debug code,
  scope creep, and accidental files the editor hid. This is a
  _mechanical-hygiene_ pass; it does **not** substitute for substantive
  critique.
- **Substantive critique needs fresh, ideally non-self eyes.** Same-context
  self-review shares the blind spots that produced the code. Independence
  ladder, weakest to strongest: self-in-context < same-model fresh-context
  subagent < different-vendor bot / human. An automatic bot reviewer or a
  human is the load-bearing substantive pass; the default finish line
  already stops at an open PR for one.
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
- **Record a noticed automated reviewer.** When you observe a bot-authored
  review on a recent PR and the project hasn't recorded the reviewer, add a
  one-line note to an unmanaged, project-specific section of AGENTS.md
  (outside `agents-md:managed:*` blocks, so syncs don't overwrite it) with
  enough identity to match its future reviews: the reviewer's **name**, its
  **login/account identity** (including the API-specific form when it
  differs, e.g. a `[bot]` suffix in one API but not another), and how it is
  **triggered** (automatic on PR events, a manual command, or a CI job).
  Later sessions filter review activity by that login, so the identity,
  not a bare "a reviewer exists", is the point. Record only a reviewer you
  actually observed, never its absence.
- **Responding to automated review.** Evaluate each comment on its merits:
  fix real findings; push back, _with a one-line reason_, on contrived,
  speculative, or already-fixed ones; never reflexively comply. Reply
  inline with the disposition and the fixing commit SHA ("Fixed in
  `<sha>`" / a reasoned decline), then resolve the thread. Resolving every
  thread is _not_ a hard merge gate; evaluate-on-merits is.
- **Fix the class, not just the cited line.** When a finding names one
  location, sweep the file and repo mechanically (grep for the finding's
  pattern, don't just eyeball nearby lines) and fix every instance in the
  same push: the class routinely recurs in sibling sentences or files the
  citation never named, and each miss costs another review round. For
  validation or parsing code, the mechanical sweep is an adversarial
  enumeration of the input space (case, spacing, indentation,
  prefix/suffix, order, duplication, nesting), run once as tests, not a
  widening of the cited pattern: pattern-widening spent eight review
  rounds on one class before the enumeration closed it. Expect
  diminishing returns too: automated reviewers can surface ever-smaller
  nits indefinitely, so converge and hand off rather than chasing every
  round to zero (value captured is the bar, not threads-at-zero).
- **Don't under-converge either.** Don't declare a PR "addressed" while the
  reviewer is still raising real issues, and never treat a finding that
  recurs from your _own_ incomplete fix as convergence; that is a miss to
  sweep, not a stop. Bias toward continuing while findings are genuinely
  worthwhile; the human's merge is the reliable convergence signal, not
  your own sense that you are done.
- **Keep the body current as review evolves the PR.** The body becomes the
  merge commit, so when review adds commits or shifts scope, update What,
  the commit map (flag which commits resolve review findings), and
  Verification before re-handing-off. The inline disposition + fixing SHA
  on each resolved thread (above) is the located per-finding record; don't
  duplicate it into a standing "feedback" section that would drift.
- The intended repo settings enforce the Commits rules: merge commits
  only (squash and rebase disabled) and auto-delete of merged branches.
  Don't re-enable around them; where they aren't set, hold the same
  rules manually (merge-commit merges only, delete the remote branch
  after merge).

### Handing off the PR

An open PR, not a merged one, is the agent's finish line; leave it
open for a human to review, approve, and merge, unless the user
explicitly asks you to merge or the project has adopted a self-merge
workflow. Done means open, green, threads handled, self-reviewed, and
no new review activity outstanding. Once the PR is up:

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
- **Wait for required checks**: poll them until they complete (on
  GitHub: `gh pr checks <n>`); fix any red check on the branch, never
  hand off a known-red PR.
- **Self-review the diff** (above) so it's ready for a reviewer.
- **Close out the watch before handoff**: poll for _both_ new review
  comments and CI, address in-scope findings on the branch, or record the
  bounded timeout / no-review result with the baseline; only then declare
  done.
- **Stop and summarize**: say the PR is open and green, and surface
  anything the reviewer should focus on. Leave merging, branch cleanup, and
  the `main` resync to whoever approves it.

If the user does ask you to merge, merge with a real merge commit (on
GitHub: `gh pr merge <n> --merge`), delete the remote branch if the
auto-delete setting didn't, then resync
(`git checkout main && git pull --ff-only`), delete the local branch
(`git branch -d <branch>`), and `git fetch --prune`.

### Reviewing a PR

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
  the devlog; check the change does what it claims, that Verification matches
  reality, and that docs/tests moved with behavior. Don't relitigate what the
  devlog marks decided or deferred.
- **Stay in scope.** Out-of-scope improvements are non-blocking nits or a
  follow-up issue, not merge-blockers; don't grow the PR through review.
- **Scale depth to risk.** Routine PRs get a normal pass; destructive /
  credential-leak / trust-boundary changes get the refute-first lens (see the
  finish line). A docs typo doesn't.
- **Resolve explicitly.** State what would unblock; let the author
  fix-or-decline. Resolving every thread isn't the gate; agreement on
  blockers is.

### Stacked PRs

Dependent docs or cleanup work can proceed without waiting for its base: a
follow-up PR can be based on an open PR's branch (on GitHub:
`gh pr create --base <feature-branch>`, which auto-retargets to `main`
when the base merges; on other forges retarget it manually). Two
gotchas: while the base is open the stacked PR's diff shows only its
own commits; and if the base is force-pushed (the fold-review-fixes
rule in Commits), `rebase --onto` the stack onto the new base tip.

<!-- /agents-md:managed:pull-requests -->

---

## Section: commits

<!-- agents-md:managed:commits -->

## Commits

History is optimized for three uses: diagnostics (blame/bisect lead to a
cause), reviewability (a PR reads commit-by-commit), and learning (the
log tells the project's evolution). Rules:

- **One concern per commit, every commit green.** If the body wants
  labeled sections (Correctness:/Performance:/…), it's more than one
  commit; split it. Each commit must build and pass tests on its own;
  never leave red intermediate states (it breaks bisect).
- **Body says why, not just what.** Write dense, specific bodies,
  wrapped ≤ 72 columns. Reference the session's devlog entry
  when one exists. State change deltas ("27 → 36 tests") if meaningful;
  never absolute status ("36 tests green"); CI asserts that, and it
  goes stale.
- **Mechanical churn commits alone.** Reformats, renames, and moves get
  their own commit, added to `.git-blame-ignore-revs` in the same change
  (activate locally with
  `git config blame.ignoreRevsFile .git-blame-ignore-revs`).
- **Fold review fixes into the commit they belong to.** When a review
  comment or self-review turns up a fix for code in an already-pushed
  commit, fold it into that commit rather than appending an "address
  review" commit; the merged PR keeps its clean, bisectable structure.
  Guardrails: every commit still builds and passes tests after the fold;
  `--force-with-lease`, **feature branch only, never force-push `main`**;
  only while the PR is unmerged (once merged, a fix is a new commit);
  update the matching devlog entry in the same operation. The mechanism
  (reset/amend/rebase) is your judgement.
- **Never squash-merge multi-commit work**: it destroys the atomic
  structure above. Merge with a real merge commit so
  `git log --first-parent` reads as the work-unit narrative and the full
  log holds the atoms. Narrative subjects ("Walking skeleton: end-to-end
  flow") belong at that merge/PR level.

<!-- /agents-md:managed:commits -->

---

## Section: done

<!-- agents-md:managed:done -->

## Definition of done for an increment

Each increment is something actively used by the end of the work session:
not "code complete" or "tests pass" alone, but running and exercised.
Before calling work done:

<!-- agents-md:project:done-checks -->

<!-- TODO: replace with this project's real verification commands during
     init: the test command, the lint/format command, and the checks
     specific to this project's change classes (e.g. "affected surfaces
     verified in the running application"). -->

- Tests green
- Lint/format clean

<!-- /agents-md:project:done-checks -->

<!-- /agents-md:managed:done -->
