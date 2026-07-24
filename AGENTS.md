# free-skills

An open-source collection of prompt-based agent skills designed to work
across platforms (Claude Code, Codex, and others). See
[README.md](README.md) for the project overview. This file covers
development conventions, contribution workflow, and project structure.

<!-- agents-md:managed:devlog -->

## Decision notes (devlog)

`devlog/` holds selective decision records, not session logs: at most
one note per work unit or PR in the ordinary case, named
`YYYY-MM-DD-HHMM-slug.md`. `devlog/README.md` is the protocol; most
work needs no note.

- **Write or update a note only when** the work involves at least one
  of: a consequential, non-obvious decision that rejects a plausible
  alternative; an investigation or verification result that materially
  changes the model, policy, risk, or implementation direction; a
  durable owner choice that would otherwise exist only in chat;
  cross-session context the work unit's PR or issue genuinely doesn't
  carry; or a change on the project's mandatory-note list, where it
  keeps one. Routine implementation, formatting, ordinary docs,
  dependency maintenance, mechanical syncs, and uncomplicated fixes
  need no note unless they reveal something consequential.
- **Content**: final rationale, rejected alternatives, changed
  assumptions, significant verification findings, and a "Revisit
  when ..." condition where one is useful; not commit diffs, test
  transcripts, or PR status. A note may evolve while its work unit or
  PR is active; it freezes on merge.
- **Retrieval**: read the notes linked from the issue or PR at hand;
  otherwise search by affected path, topic, contract, or decision
  name. Read the latest note only when resuming the work unit it
  describes. Prior notes are evidence, not prohibitions: do not
  silently overturn an explicit owner decision; if new evidence
  conflicts with one, identify the prior decision, state which
  assumption or condition changed, and surface the proposed revision.
- **Actionable deferred work goes to the issue tracker**, not the
  note. When an issue originates from a note, link the note from the
  issue; the note may carry a plain historical `Follow-up: #N` link,
  never a second source of status. An observation that is not yet
  actionable becomes a "Revisit when ..." statement, not open work.

<!-- /agents-md:managed:devlog -->

<!-- agents-md:managed:finish-line -->

## Default agent finish line

For any user request that asks you to change code, docs, assets, or project
state, the default endpoint is **an open, review-ready PR with required
checks green**, not a merged branch. Merging is a human decision; do not
merge your own PR unless the user explicitly asks, or the project has adopted
an opt-in self-merge workflow.

Before implementation, establish a lightweight work contract: objective,
testable acceptance criteria, scope, dependencies and blockers, and explicit
non-goals. Direct user-assigned work needs no issue; the prompt and
eventual PR may carry the contract together. Persist that same contract
in a tracker issue when the work must survive a session boundary,
coordinate concurrent workers, or join a backlog. Actionable work
deferred out of the unit's scope gets a tracker issue before handoff.

By default, begin work only through explicit user assignment. An issue, label,
backlog entry, satisfied dependency, or claim is not authorization to select
and start work. Agent self-selection requires an explicit project-specific
opt-in policy.

Use this checklist for each work session:

1. Read the README and, when resuming an existing work unit, its issue or
   PR and any decision note it links. Resolve the repository's
   default branch explicitly, update it from its remote, and start ordinary
   work from that exact tip, not from whichever branch is currently checked
   out. Only an intentionally declared stacked PR may start from another open
   PR's branch (see Stacked PRs under Pull requests).
2. Create one correctly named branch explicitly from that starting tip.
3. Make the scoped change, including the docs/tests/assets that keep it
   complete and, where the project keeps decision notes, a note when
   the work meets its triggers.
4. Run the relevant verification plus the standard lint/build/test checks
   before PR; if any check cannot run, record the exact gap in the PR.
5. Commit one concern at a time with a body that says why.
6. Push, open the PR with the template, and remove sections that do not apply.
7. Hand off per "Handing off the PR" (under Pull requests): start the
   review-watch, complete the base-freshness pass, wait out required checks,
   handle reviewer activity, self-review the PR files view, and leave the PR
   open for a human to review and merge.

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

<!-- /agents-md:managed:finish-line -->

<!-- agents-md:managed:context -->

## Context discipline

The working context is finite, and everything held in it is re-sent
with every later tool call, so transient bulk pulled in early taxes
every step after it. Durable state belongs in files (the PR body, the
issue, a decision note where the project keeps one); keep the working
context to what the current step needs.

- **Keep raw bulk out.** Prefer targeted, bounded reads and searches
  (a file region, a match list, a filtered log tail) over whole-file
  dumps and unfiltered search output; don't page a large artifact into
  context when a bounded query answers the question.
- **Delegate broad exploration.** Where your platform and session
  support delegation, offload broad exploration and mechanical sweeps
  to a delegate that returns conclusions (findings, `file:line`
  pointers, a short digest), never its raw output. Where they don't,
  fall back to the bounded reads and searches above. Scale to size
  either way: for a question a couple of targeted reads can answer,
  spawning a delegate costs more than it saves.
- **Right-size delegated work.** Where the platform exposes a model
  class or effort level for delegated work, send mechanical scanning
  and digesting to the cheapest class that handles it reliably;
  frontier capability spent on rote reading is waste. Where it
  doesn't, skip this.
- **No quiet fan-out.** One delegate for exploration or review is
  normal. Parallel multi-agent fan-outs multiply cost invisibly;
  before launching one, state the expected scale and proceed with the
  user's go-ahead or within a budget they already set.
- **Prefer a fresh session over a bloated one.** The PR body (plus a
  decision note when one exists) carries the durable state, so at a
  natural boundary (a PR handed off, a review round closed, a new work
  unit) in a long session, suggest continuing in a fresh session
  seeded with the PR number rather than pushing on; the accumulated
  context adds little to the next unit and dominates its cost.

<!-- /agents-md:managed:context -->

## Build, test, run

This is a markdown-only project: no compile or build step.

### Lint

```sh
npx markdownlint-cli2 '**/*.md'
```

Gotcha: MD038 is active, so an inline code span can't have a leading or
trailing space inside the backticks. Wrapping a colon-then-space in backticks
to show that sequence trips it; describe such whitespace-bearing sequences in
prose ("a colon-then-space") rather than quoting them in a code span.

### Format

```sh
npx prettier --check '**/*.md'
npx prettier --write '**/*.md'   # to fix
```

### CI

<!-- TODO: Add CI configuration (.github/workflows/) once the repo has
     content worth gating. The workflow conventions in this file assume CI
     exists; set it up before the first real PR. -->

CLAUDE.md is a pointer that imports AGENTS.md; edit AGENTS.md, never the
pointer.

## Project structure

```text
skills/
  <skill-name>/
    SKILL.md           # The skill prompt (required entry point)
    ...                # Additional files as needed per skill
```

Each skill lives in its own directory under `skills/`. The only required
file is `SKILL.md`: the skill prompt with YAML frontmatter (name and
description) that an agent loads to execute the skill. Additional files
(reference material, examples, sub-prompts) may live alongside it.

## Architecture invariants

1. **One directory per skill.** All skill content lives under
   `skills/<skill-name>/`. No top-level loose skill files. This prevents
   naming collisions and keeps each skill self-contained.

2. **Platform-agnostic prompts.** Skills must work across Claude Code and
   Codex (and ideally other agent platforms). Avoid platform-specific tool
   calls or assumptions in prompt text; when platform-specific behavior is
   needed, gate it explicitly and document the fallback. **This extends to the
   agent-setup canonical conventions**: they get copied into downstream
   AGENTS.md files and run by arbitrary agents, so a convention must not assume
   a capability either. **Subagents/delegation are the canonical trap:** not
   every agent or session can spawn a subagent (e.g. a Codex session, or an
   agent with no subagent concept), so any instruction to delegate must be
   gated on the platform supporting it and state the fallback (skip it, or use
   an external/human reviewer), never emitting steps the running agent can't
   perform. (Surfaced by a P2 review on the fresh-context-review convention;
   see the 2026-06-26 devlog.)

3. **`SKILL.md` is the entry point.** Every skill directory must contain a
   `SKILL.md`. This is the file an agent loads to execute the skill.
   Both Claude Code and Codex discover skills by this filename.

## Conventions

- **README skills table is alphabetical by skill name.** Insert a new
  skill's row in order, not appended at the end.

- **Write prose without em dashes**; use commas, colons, semicolons, or
  parentheses instead. This covers skill prompts and the canonical
  conventions, which downstream projects inherit verbatim. En dashes in
  numeric ranges ("2–4") are fine.

- **`SKILL.md` frontmatter must parse as YAML; write `description` as a `>-`
  block scalar.** Skill indexers read `name`/`description` as YAML, so a plain
  (unquoted) scalar silently fails to load the skill when its text contains a
  colon-then-space (e.g. `proactively: the`), a leading `#`, or other YAML
  structural characters. A `>-` folded block scalar keeps the text literal and
  parse-safe; use it for new skills. Existing plain-scalar descriptions are
  acceptable only while they stay parse-safe; converting them to `>-` is a
  welcome hardening. Verify with any YAML parser when unsure. (Surfaced by a P1
  review on the visual-evidence skill; see the 2026-06-26 devlog.)

- **Agent-setup profile: High-assurance.** Decision notes live in
  `devlog/` per the Decision notes section. A note is mandatory for:
  changes to the canonical managed workflow conventions or scaffold
  templates; changes to branch, PR, review, merge, or release policy;
  changes on destructive, credential-leak, or returned-object
  trust-boundary paths; and cross-project prompt decisions that
  downstream repositories inherit. Routine skill documentation and
  mechanical syncs are exempt unless they meet a general note trigger.

- **This repo dogfoods agent-setup; edit managed conventions in two places.**
  free-skills' own AGENTS.md is built from the agent-setup skill, so its
  `<!-- agents-md:managed:* -->` blocks (devlog, finish-line, context,
  branches, pull-requests, commits, done) mirror the canonical source at
  `skills/agent-setup/references/canonical-sections.md`. When you change one of
  those conventions, edit **both** the canonical source **and** this file's
  matching managed block, keeping the managed text in sync (`diff` them).
  **Exception:** a managed block may wrap a nested
  `<!-- agents-md:project:* -->` sub-block (here, `project:done-checks` inside
  `done`); that content is project-specific by design, so keep it local and
  never overwrite it with the canonical template. The two-place rule also
  covers this repo's **scaffolded files**: `devlog/README.md` (which the
  managed devlog block points to as the authoritative protocol),
  `CONTRIBUTING.md`, the PR template, and `CLAUDE.md` are live copies of the
  templates in `skills/agent-setup/references/scaffolding.md`, so an edit to a
  scaffold template must update the matching live file here too (`diff` them),
  or the live copy silently contradicts the freshly-synced convention.
  Sections outside the managed
  markers (Architecture invariants, Conventions, Build) are free-skills-only;
  edit those here alone.

- **Automated reviewer: Codex.** Login `chatgpt-codex-connector` (REST API form
  `chatgpt-codex-connector[bot]`, which GraphQL also uses for _reactions_);
  trigger: automatic on PR events (open / mark ready / push; re-reviews after
  each fix push were observed live on PR 46), or manual
  `@codex review`. Status signals, observed on PRs 41–44: it reacts on the PR
  description with 👀 while a review is in progress and 👍 when a pass found
  nothing (a clean pass may post no review at all); it posts a review only
  when it has findings. The `await-pr-review` skill shipped in this repo uses
  this project-specific record when resolving which reviewer to wait for and
  which signals finish a round; update it if the reviewer, its trigger, or its
  signals change.

<!-- TODO: Fill in more as patterns emerge: prompt structure guidelines,
     how to handle skill dependencies, testing/validation patterns. -->

<!-- agents-md:managed:branches -->

## Branches

All work lands through a PR. Resolve and freshly update the repository's
default branch (`main` below), then create each ordinary work-unit branch
explicitly from that tip. Never create an ordinary branch from the currently
checked-out feature branch; a non-default starting point is allowed only for
an intentionally declared stacked PR. Do the work as atomic commits (see
Commits), then open a PR; the work merges with a real merge commit, a human's
call per the finish line. Never commit directly to `main`. No triviality
exception: every bypass erodes the `--first-parent` narrative.

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

**Break down concurrency before isolating it.** Keep coupled work in one work
unit, an explicit dependency chain, or an intentionally declared stack; a
worktree separates checkouts but cannot make logically dependent work safe in
parallel. Before substantive work, an assigned concurrent unit uses the
project's forge-visible claim mechanism, when one is defined. The claim
advertises active occupancy, not authorization; its form is project-specific.

**Isolate concurrent work units.** Concurrent work units must use separate
worktrees or checkouts. Where your platform and session support a second
checkout (a native worktree tool or session flag, or plain
`git worktree add <path> -b <type>/<slug> <default-branch>`), create each
worktree explicitly from the freshly updated default-branch tip, not from
whatever branch is checked out; prefer the same isolation for a single work
unit. Remove the worktree once its branch merges
(`git worktree remove <path>`). Where isolated checkouts are unavailable
(no multi-checkout support, or a sandbox pinned to one directory), serialize
the work units and use one correctly based branch at a time in the primary
checkout. Never run concurrent work units in one checkout.

Follow-up work that depends on an open PR can stack on its branch instead
of waiting; see the Stacked PRs pattern under Pull requests.

<!-- /agents-md:managed:branches -->

<!-- agents-md:managed:pull-requests -->

## Pull requests

A PR is one work unit, reviewed as a whole and merged with a real merge
commit. Commits carry the atomic why (see Commits); the PR carries the
arc.

- **Title**: imperative, ≤ 72 chars, names the outcome, no type prefix
  or ticket noise ("Fix missing menu bar on unbundled launch"). In the
  intended repo setup the PR title (plus its number) is the _entire_
  merge commit message: merges are title-only, so the body's review
  material (screenshots, verification, review notes) never lands in
  history, and `git log --first-parent` reads as the list of PR
  titles; write the title for that log either way.
- **Body**: scaffolded by the repo's PR template (on GitHub:
  `.github/pull_request_template.md`):
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
- **Self-review the diff in the PR files view before handing off**: seeing
  the whole change as one artifact catches stray hunks, leftover debug code,
  scope creep, and accidental files the editor hid. This is a
  _mechanical-hygiene_ pass; it does **not** substitute for substantive
  critique.
- **Integration evidence belongs to one base commit.** CI results, a
  full-diff self-review, and a ready-for-handoff claim are valid only for the
  base commit they were checked against. A base-branch change invalidates all
  three, even when the earlier PR diff looked clean.
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
- **Responding to automated review.** Evaluate each comment on its merits:
  fix real findings; push back, _with a one-line reason_, on contrived,
  speculative, or already-fixed ones; never reflexively comply. Reply
  inline with the disposition and the fixing commit SHA ("Fixed in
  `<sha>`" / a reasoned decline), then resolve the thread; where review
  fixes fold into their commits, the fold and push come first (the
  fold-then-reply gate in Commits), so the cited SHA is the final,
  pushed one, and a round that accepts several findings folds them all
  and pushes once before any reply, since a later fold in the round
  rewrites an already-cited SHA. Resolving every
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
  rounds on one class before the enumeration closed it.
- **Converge deliberately, and don't under-converge.** Automated
  reviewers can surface ever-smaller nits indefinitely, so converge
  and hand off rather than chasing every round to zero (value captured
  is the bar, not threads-at-zero). But don't declare a PR "addressed"
  while the reviewer is still raising real issues, and never treat a
  finding that recurs from your _own_ incomplete fix as convergence;
  that is a miss to sweep, not a stop. Bias toward continuing while
  findings are genuinely worthwhile; the human's merge is the reliable
  convergence signal, not your own sense that you are done.
- **Keep the body current as review evolves the PR.** The body is the
  work unit's durable record on the forge (the merge commit carries only
  the title), so when review adds commits or shifts scope, update What,
  the commit map (flag which commits resolve review findings, by subject as
  above), and Verification before re-handing-off. The inline disposition +
  fixing SHA on each resolved thread (above) is the located per-finding
  record (that reply is written once, post-fold, so its SHA doesn't churn);
  don't duplicate it into a standing "feedback" section that would drift.
- The intended repo settings enforce the Commits rules: merge commits
  only (squash and rebase disabled), title-only merge messages, and
  auto-delete of merged branches. Don't re-enable around them; where
  they aren't set, hold the same rules manually (merge-commit merges
  only, the merge message kept to the PR title, delete the remote
  branch after merge).

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
- **Self-review the diff** (above) so it's ready for a reviewer.
- **Close out the watch before handoff**: poll for _both_ new review
  comments and CI, address in-scope findings on the branch, or record the
  bounded timeout / no-review result with the baseline; only then declare
  done.
- **Stop and summarize**: say the PR is open and green, and surface
  anything the reviewer should focus on. Leave merging, branch cleanup, and
  the `main` resync to whoever approves it.

If the user does ask you to merge, merge with a real merge commit (on
GitHub: `gh pr merge <n> --merge`; where the repo's title-only
merge-message settings aren't confirmed set, pass the message
explicitly instead of inheriting the forge default:
`gh pr merge <n> --merge --subject '<PR title> (#<n>)' --body ''`),
delete the remote branch if the
auto-delete setting didn't, then resync the base branch, delete the
local branch (`git branch -d <branch>`), and `git fetch --prune`. In a
single checkout the resync is `git checkout main && git pull --ff-only`;
when the work ran in a dedicated worktree (see Branches) `git checkout main`
refuses with "already used by worktree", so resync `main` in the primary
checkout and `git worktree remove <path>` the feature worktree before
deleting its branch.

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

### Stacked PRs

Dependent docs or cleanup work can proceed without waiting for its base as an
intentionally declared stacked PR. A non-default base is an explicit
dependency: name the open PR's branch when creating both the follow-up branch
or worktree and the PR, never inherit it from the current checkout. On GitHub,
use `gh pr create --base <feature-branch>`; it auto-retargets to `main` when
the base merges, while other forges may require manual retargeting. Two
gotchas: while the base is open the stacked PR's diff shows only its own
commits; and if the base is force-pushed (the fold-review-fixes rule in
Commits), `rebase --onto` the stack onto the new base tip.

<!-- /agents-md:managed:pull-requests -->

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
  wrapped ≤ 72 columns. Reference the work unit's decision note
  when one exists. State change deltas ("27 → 36 tests") if meaningful;
  never absolute status ("36 tests green"); CI asserts that, and it
  goes stale.
- **Never commit secrets** (credentials, tokens, keys, `.env`
  contents); reference them by name and use placeholders in examples.
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
  update the matching decision note, when one exists, in the same
  operation. The mechanism (reset/amend/rebase) is your judgement. The
  fold-then-reply order is a gate: fold and push before writing the
  inline reply to the review thread, so the reply cites the final
  commit SHA, verified reachable from the pushed head; a standalone
  review-fix commit still on the branch at handoff is an unfinished
  fold, not a done round.
- **Never squash-merge multi-commit work**: it destroys the atomic
  structure above. Merge with a real merge commit so
  `git log --first-parent` reads as the work-unit narrative and the full
  log holds the atoms. Narrative subjects ("Walking skeleton: end-to-end
  flow") belong at that merge/PR level.

<!-- /agents-md:managed:commits -->

<!-- agents-md:managed:done -->

## Definition of done for an increment

Each increment is something actively used by the end of the work session:
not "code complete" or "tests pass" alone, but running and exercised.
Before calling work done:

The build succeeds, tests pass, and lint and formatting are clean.

<!-- agents-md:project:done-checks -->

- Markdown lint clean (`npx markdownlint-cli2 '**/*.md'`)
- Format clean (`npx prettier --check '**/*.md'`)
- Prose-tic check clean (`./scripts/check-prose-tics.sh`): no em dashes,
  misused en dashes, or stock AI openers in markdown outside `devlog/`
- New or changed skills have a valid `SKILL.md` with parse-safe YAML
  frontmatter (`description` as a `>-` block scalar; see Conventions)
- Skill prompts reviewed for platform-agnostic language (no
  Claude-Code-only or Codex-only assumptions without explicit gates)
- Managed blocks in sync with the canonical source
  (`./scripts/check-managed-sync.sh`)
- Comparator regression suite green when the comparator or sync check
  changed (`./scripts/test-compare-managed-blocks.sh`)
- Watcher validation matrix green when await-pr-review's `watch-review.sh`
  changed (`./scripts/test-watch-review.sh`)
- Prose-tics matrix green when the prose-tic check changed
  (`./scripts/test-check-prose-tics.sh`)
- Capture validation matrix green when visual-evidence's `capture.mjs`
  changed (`./scripts/test-capture.sh`)

<!-- /agents-md:project:done-checks -->

<!-- /agents-md:managed:done -->
