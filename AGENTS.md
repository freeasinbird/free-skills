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

For any request to change code, docs, assets, or project state, the
default endpoint is **an open, review-ready PR with required checks
green**, not a merged branch. Merging is a human decision; do not merge
your own PR unless the user explicitly asks, or the project has adopted
an opt-in self-merge workflow.

Before implementation, establish a lightweight work contract: objective,
testable acceptance criteria, scope, dependencies and blockers, and explicit
non-goals. Direct user-assigned work needs no issue; the prompt and PR
carry the contract. Persist it in a tracker issue when the
work must survive a session boundary, pass sequentially between agents or
sessions (even within one short session), coordinate concurrent workers, or
join a backlog; a sequential handoff puts the durable input and output in
the issue and its comments, never only in transient chat. Actionable work
deferred out of the unit's scope gets a tracker issue before handoff.

A project may declare optional work-unit stages in an unmanaged,
project-specific section. While a declared stage is active, its recorded
allowed mutations and finish line govern: an implementation stage runs
only the checklist steps they permit and stops at its recorded
transition, a non-implementation stage follows its own record instead,
and completing a stage hands off to the next without authorizing it to
begin. Work that is not a declared stage runs the checklist in full,
minus any action a separately declared stage owns.

By default, begin work only through explicit user assignment. An issue, label,
backlog entry, satisfied dependency, completed plan, or claim is not
authorization to select and start work. Agent self-selection requires an
explicit project-specific opt-in policy.

The implementation checklist:

1. Read the README and, when resuming a work unit, its issue or PR and any
   decision note they link. Resolve the default branch explicitly, update it
   from its remote, and start from that exact tip (see Branches; only a
   declared stacked PR starts elsewhere).
2. Create one correctly named branch from that tip in a dedicated worktree
   or equivalent isolated checkout (see Branches for the primary-checkout
   exception).
3. Make the scoped change, with the docs/tests/assets that keep it complete
   and, where the project keeps decision notes, a note when the work meets
   its triggers.
4. Run the relevant verification plus the standard lint/build/test checks;
   if any check cannot run, record the exact gap in the PR.
5. Commit one concern at a time with a body that says why.
6. Push, open the PR with the template, and remove sections that do not apply.
7. Hand off per "Handing off the PR" (under Pull requests); leave the PR
   open for a human to review and merge.

For changes on a **destructive path** (delete/cleanup), a
**credential-leak surface**, or a **returned-object-trust boundary**
(trusting fields of a value handed back by an external call or
deserializer), read `docs/agent-workflow.md` §refute-first before
committing and run the verification pass it describes; a docs typo or
an off-path refactor doesn't trigger it.

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

<!-- agents-md:managed:communication -->

## Writing for humans

Humans scan rather than read: a fifth of the words, weighted toward
first lines and line-starts, about four open items in mind, rapid
tune-out of repeated warnings. Write every human-facing artifact
(handoff, PR body, issue, plan, review comment, question) for that
reader; never rely on them digging.

- **Bottom line first.** Open the artifact with its conclusion,
  decision, or ask, along with any assumption or caveat it stands or
  falls on; supporting material follows in descending importance. A
  reader who stops after the opening still acts correctly.
- **Front-load every unit.** The first words of a heading, bullet, or
  paragraph carry its information.
- **Layer, don't just shrink.** The artifact is also the durable
  record: the skim layer carries the decision, while evidence,
  alternatives, and detail live below it or in the linked note or
  issue, never cut to shorten the skim layer.
- **Few asks per round, with defaults.** Surface the questions that
  gate the work, about three at a time, each with a recommended answer
  and a one-line reason. Convert questions a sensible default settles
  into visible assumptions the reader can veto; queue the remaining
  gating questions for a later round rather than assuming through
  them.
- **Ration flags, and calibrate them.** Tag severity, flag what
  changes the reader's decision or how much to trust the result, and
  make rare critical warnings visually distinct; a page of routine
  hedges buries the one that matters.
- **Surface uncertainty; don't polish past it.** State what was not
  verified and where you are unsure, so the human's attention lands
  where checking is needed; fluent prose invites rubber-stamping.

<!-- /agents-md:managed:communication -->

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

### Readability report

```sh
./scripts/check-readability.sh [file ...]
```

The report prints one row per markdown file with its word count, median and
maximum sentence length, sentences over 40 words, and maximum paragraph
length. All lengths use whitespace-separated word counts. It is report-only
and exits 0 after any successful report; no readability thresholds are
enforced.

### CI

Pull requests run `.github/workflows/commit-messages.yml`, which checks the
exact feature-branch commit range against the Mechanical Commit-Message
Checks below. Broader Markdown and script CI remains future work.

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
  communication, branches, pull-requests, commits, done) mirror the
  canonical source at
  `skills/agent-setup/references/canonical-sections.md`. When you change one of
  those conventions, edit **both** the canonical source **and** this file's
  matching managed block, keeping the managed text in sync (`diff` them).
  **Exception:** a managed block may wrap a nested
  `<!-- agents-md:project:* -->` sub-block (here, `project:done-checks` inside
  `done`); that content is project-specific by design, so keep it local and
  never overwrite it with the canonical template. The two-place rule also
  covers this repo's **scaffolded files**: `devlog/README.md` (which the
  managed devlog block points to as the authoritative protocol),
  `docs/agent-workflow.md` (the step-local reference the managed blocks
  point at by `§slug`; `./scripts/check-managed-sync.sh` diffs it against
  the template), `CONTRIBUTING.md`, the PR template, and `CLAUDE.md` are
  live copies of the templates in
  `skills/agent-setup/references/scaffolding.md`, so an edit to a
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
explicitly from that tip, never from the currently checked-out feature
branch; a non-default starting point is allowed only for an intentionally
declared stacked PR. Do the work as atomic commits (see Commits), then open
a PR; it merges with a real merge commit on a human's call. Never commit
directly to `main`, with no triviality exception: every bypass erodes the
`--first-parent` narrative.

Name branches `<type>/<short-kebab-slug>`: type from the Conventional
Commits vocabulary (`feat`, `fix`, `refactor`, `docs`, `chore`), slug
2–4 kebab-case words naming the work unit:

```text
feat/worksheet-promotion
fix/pane-focus-race
chore/swift-format-sweep
```

Exactly one slash (`feat/x` and a bare `feat` can't coexist). No ticket
numbers, dates, or owner prefixes; prepend an owner segment
(`bnw/feat/…`) only if multiple people or agents start pushing in
parallel. Merged branches auto-delete where that repo setting is on;
delete them after merge where it isn't.

**Break down concurrency before isolating it.** Keep coupled work in one work
unit, an explicit dependency chain, or an intentionally declared stack; a
worktree separates checkouts but cannot make logically dependent work safe in
parallel. Before substantive work, an assigned concurrent unit uses the
project's forge-visible claim mechanism, when one is defined. The claim
advertises active occupancy, not authorization; its form is project-specific.

**Isolate every implementation work unit** in a dedicated worktree or
equivalent isolated checkout. Where your platform and session support a
second checkout (a native worktree tool or session flag, or plain
`git worktree add <path> -b <type>/<slug> <default-branch>`), create the
branch and checkout from the freshly updated default-branch tip. Use the
primary checkout only when an explicit user or project instruction requires
it, or when the platform cannot create another checkout (no multi-checkout
support, or a sandbox pinned to one directory); then serialize all work on
one correctly based branch there and report the exception, never running
concurrent work units in one checkout. Remove a worktree once its branch
merges, standing outside the one being removed (`git worktree remove <path>`).

Work that depends on an open PR can stack on its branch instead of
waiting; see Stacked PRs under Pull requests.

<!-- /agents-md:managed:branches -->

<!-- agents-md:managed:pull-requests -->

## Pull requests

A PR is one work unit, reviewed as a whole and merged with a real merge
commit. Commits carry the atomic why (see Commits); the PR carries the
arc.

- **Title**: imperative, ≤ 72 chars, names the outcome, no type prefix
  or ticket noise ("Fix missing menu bar on unbundled launch"). In the
  intended repo setup the title (plus its number) is the _entire_ merge
  commit message; write it for `git log --first-parent` either way.
- **Body**: scaffolded by the repo's PR template
  (`.github/pull_request_template.md` on GitHub): Why, What (outcome bullets and a
  commit map keyed by subject, not SHA), Screenshots (UI changes only),
  Review Notes (optional), and Verification (bullets starting `Passed:`,
  `Checked:`, `Attempted:`, or `Not run:`; facts only). Before writing
  or updating the body, read `docs/agent-workflow.md` §pr-body and meet
  each section's bar (for UI changes, the Screenshots bar).
- **Self-review the diff in the PR files view before handing off**: the
  whole change as one artifact shows stray hunks, leftover debug code,
  scope creep, and accidental files. This is _mechanical hygiene_, not
  substantive critique.
- **Integration evidence belongs to one base commit.** CI results, a
  full-diff self-review, and a ready-for-handoff claim are valid only for
  the base commit they were checked against; a base-branch change
  invalidates all three, however clean the earlier diff looked.
- **Substantive critique needs fresh, ideally non-self eyes**, since
  same-context self-review shares the blind spots that produced the
  code: self-in-context < same-model fresh-context subagent <
  different-vendor bot / human. The bot reviewer or human is the
  load-bearing pass. For a non-trivial change, or a repo without a bot
  reviewer, read `docs/agent-workflow.md` §pre-push-review before
  pushing and run the platform-gated review it describes.
- **Record a noticed automated reviewer.** On seeing a bot-authored
  review or reviewer status signal the project hasn't recorded, read
  `docs/agent-workflow.md` §reviewer-record and add or augment the
  record before handing off.
- **Responding to automated review.** Evaluate each comment on its merits:
  fix real findings; push back, _with a one-line reason_, on contrived,
  speculative, or already-fixed ones; never reflexively comply. Reply
  inline with the disposition and the fixing commit SHA ("Fixed in
  `<sha>`" / a reasoned decline), then resolve the thread. Where fixes
  fold into their commits, fold all of a round's fixes and push once
  before any reply (the fold-then-reply gate in Commits), so every cited
  SHA is the final, pushed one. Resolving every thread is _not_ a hard
  merge gate; evaluate-on-merits is.
- **Fix the class, not just the cited line.** When a finding names one
  location, sweep the file and repo mechanically (grep for the finding's
  pattern, don't just eyeball nearby lines) and fix every instance in the
  same push; the class recurs in sibling sentences and files the citation
  never named. For validation or parsing code the sweep is the
  adversarial input-space enumeration in `docs/agent-workflow.md`
  §review-convergence; read it before widening the cited pattern.
- **Converge on a bar that rises with the rounds.** Blocking findings
  (correctness, security, data-loss, broken invariants, red CI) always
  earn another round; judge that severity yourself, the reviewer's tag
  being input, not verdict, and when unsure treat a finding as blocking.
  Once an exchange passes its early rounds or a finding recurs, read
  `docs/agent-workflow.md` §review-convergence before deciding on
  another. Hand off with every finding dispositioned (fixed, declined,
  deferred, or explicitly outstanding).
- **Keep the body current as review evolves the PR.** The body is the
  work unit's durable record on the forge: when review adds commits or
  shifts scope, update What, the
  commit map (flagging which commits resolve review findings, by
  subject), and Verification before re-handing-off. The inline reply on
  each resolved thread is the per-finding record; don't duplicate it
  into a standing "feedback" section.
- The intended repo settings enforce the Commits rules: merge commits
  only (squash and rebase disabled), title-only merge messages, and
  auto-delete of merged branches. Don't re-enable around them; where
  they aren't set, hold the same rules manually.

### Handing off the PR

Done means open, green, threads handled, self-reviewed, and no new
review activity outstanding. Once the PR is up, read
`docs/agent-workflow.md` §handing-off and follow its sequence:
review-watch per PR/reviewer first, anchored to the open or push event;
base-freshness pass with the base commit recorded; required checks
waited out, never a known-red handoff; self-review; watch closed out
with findings addressed or the bounded timeout recorded; then stop and
summarize.

If the user does ask you to merge, read `docs/agent-workflow.md`
§merge-and-resync before the merge or resync and follow it step by step;
do not merge or resync from memory.

### Reviewing a PR

When asked to review a PR, read `docs/agent-workflow.md` §reviewing-a-pr
first and hold its bar.

### Stacked PRs

Before creating a branch or PR that depends on an open PR, read
`docs/agent-workflow.md` §stacked-prs and declare the base explicitly,
never the current checkout.

<!-- /agents-md:managed:pull-requests -->

<!-- agents-md:managed:commits -->

## Commits

History serves three uses: diagnostics (blame/bisect lead to a
cause), reviewability (a PR reads commit-by-commit), and learning (the
log tells the project's evolution). Rules:

- **One concern per commit, every commit green.** If the body wants
  labeled sections (Correctness:/Performance:/…), it's more than one
  commit; split it. Each commit must build and pass tests on its own;
  never leave red intermediate states (it breaks bisect).
- **Body says why, not just what.** Write dense, specific bodies,
  wrapped ≤ 72 columns, referencing the work unit's decision note when
  one exists. State change deltas ("27 → 36 tests") if meaningful, never
  absolute status ("36 tests green"), which goes stale.
- **Never commit secrets** (credentials, tokens, keys, `.env`
  contents); reference them by name and use placeholders in examples.
- **Mechanical churn commits alone.** Reformats, renames, and moves get
  their own commit, added to `.git-blame-ignore-revs` in the same change
  (activate locally with
  `git config blame.ignoreRevsFile .git-blame-ignore-revs`).
- **Fold review fixes into the commit they belong to.** A fix that
  review or self-review turns up for an already-pushed commit folds into
  that commit, never an appended "address review" commit, keeping the
  merged PR clean and bisectable.
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
  structure above. A real merge commit keeps `git log --first-parent` as
  the work-unit narrative and the full log as the atoms; narrative
  subjects ("Walking skeleton: end-to-end flow") belong at that merge/PR
  level.

<!-- /agents-md:managed:commits -->

## Mechanical Commit-Message Checks

Pull-request CI runs
`bash scripts/check-commit-messages.sh <base-ref> <head-ref>` (locally, usually
`bash scripts/check-commit-messages.sh origin/main HEAD`). It resolves the
merge base and checks every non-merge commit in `merge-base..head`; merge
commits and mainline commits brought in by a base-freshness merge are exempt.
The check reports every offending commit and rule in one run.

Every checked commit must satisfy all of these mechanical rules:

- A subject and a body are required, with line 2 blank between them. The
  body must contain at least one non-blank line after that separator.
- The subject is at most 72 characters, does not end in a period, and does
  not begin with a lowercase ASCII letter. Acronym-, identifier-, and
  digit-led subjects remain valid.
- Case-insensitive Conventional Commit prefixes are forbidden for `build`,
  `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`,
  and `test`, including scoped and breaking forms such as `feat(api):` and
  `refactor!:`.
- Case-insensitive `fixup!` and `squash!` prefixes and standalone `WIP`
  markers are forbidden.
- Case-insensitive review-cleanup prefixes are forbidden: `Address review`,
  `Address PR review`, `Address pull request review`, `Apply review feedback`
  (with optional `PR` or `pull request` before `review`), `PR feedback`, and
  `Pull request feedback`. Fold that work into its owning commit instead.
- Body lines are at most 72 characters. A line with no whitespace is exempt
  so an unbreakable URL, object ID, or ref can remain intact.

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
- Skill structure check clean (`./scripts/check-skill-structure.sh`): valid
  `SKILL.md` frontmatter (`description` as a `>-` block scalar; see
  Conventions), no prose paragraph over 15 lines, script flags and their
  `SKILL.md` documentation in step (shell and JavaScript scripts), and every
  `references/<file>.md` §slug pointer resolving both ways
- Skill prompts reviewed for platform-agnostic language (no
  Claude-Code-only or Codex-only assumptions without explicit gates)
- Managed blocks in sync with the canonical source and
  `docs/agent-workflow.md` in sync with its scaffold template
  (`./scripts/check-managed-sync.sh`)
- Comparator regression suite green when the comparator or sync check
  changed (`./scripts/test-compare-managed-blocks.sh`)
- Sync-check validation matrix green when `check-managed-sync.sh` changed
  (`./scripts/test-check-managed-sync.sh`)
- Watcher validation matrix green when await-pr-review's `watch-review.sh`
  changed (`./scripts/test-watch-review.sh`)
- Prose-tics matrix green when the prose-tic check changed
  (`./scripts/test-check-prose-tics.sh`)
- Readability matrix green when `check-readability.sh` changed
  (`./scripts/test-check-readability.sh`)
- Commit-message validation matrix green when the commit-message check changed
  (`./scripts/test-check-commit-messages.sh`)
- Skill-structure matrix green when the structure check changed
  (`./scripts/test-check-skill-structure.sh`)
- Capture validation matrix green when visual-evidence's `capture.mjs`
  changed (`./scripts/test-capture.sh`)
- Self-merge validation matrix green when self-merge's `self-merge.sh`
  changed (`./scripts/test-self-merge.sh`)
- Inventory validation matrix green when merge-cleanup's
  `worktree-inventory.sh` changed
  (`./scripts/test-merge-cleanup-inventory.sh`)
- Landing validation matrix green when merge-cleanup's
  `base-landing-plan.sh` changed
  (`./scripts/test-merge-cleanup-landing.sh`)
- Orchestration validation matrix green when merge-cleanup's
  `merge-cleanup.sh` changed (`./scripts/test-merge-cleanup.sh`)

<!-- /agents-md:project:done-checks -->

<!-- /agents-md:managed:done -->
