# free-skills

An open-source collection of prompt-based agent skills designed to work
across platforms (Claude Code, Codex, and others). See
[README.md](README.md) for the project overview. This file covers
development conventions, contribution workflow, and project structure.

<!-- agents-md:managed:devlog -->

## Decision Notes (devlog)

`devlog/` holds selected decision records, not session logs. Most work needs
no note. In the ordinary case, keep at most one note per work unit or PR. Name
it `YYYY-MM-DD-HHMM-slug.md`. Follow the protocol in `devlog/README.md`.

- **Write a note only for a lasting decision or discovery.** A note is
  warranted when the work includes at least one of these:

  - A significant, non-obvious decision that rejects a reasonable option.
  - A finding that materially changes the model, policy, risk, or direction.
  - An owner decision that would otherwise exist only in chat.
  - Essential cross-session context that the issue or PR doesn't carry.
  - A change on the project's mandatory-note list, when it has one.

- **Skip notes for routine work.** Implementation, formatting, ordinary docs,
  dependency updates, mechanical syncs, and simple fixes need no note unless
  they reveal a lasting decision or discovery.
- **Record the final reasoning.** Include rejected options, changed
  assumptions, important verification findings, and a "Revisit when ..."
  condition where one is useful. Do not include diffs, test logs, chronology,
  or PR status.
- **Let an active note evolve.** Update it while its work unit or PR is open.
  Freeze it when the PR merges.
- **Find notes from the work first.** Read notes linked from the current issue
  or PR. Otherwise, search by path, topic, contract, or decision name. Read
  the latest note only when resuming the work unit it describes.
- **Treat old notes as evidence, not rules.** Do not silently overturn an
  explicit owner decision. When new evidence conflicts with one, name the old
  decision, explain which assumption or condition changed, and propose the
  revision.
- **Track deferred work in issues.** Link the note from an issue that starts
  there. The note may keep a historical `Follow-up: #N` link, but never a
  second status record. Put non-actionable observations in "Revisit when ...".

<!-- /agents-md:managed:devlog -->

<!-- agents-md:managed:finish-line -->

## Default Agent Finish Line

For changes to code, docs, assets, or project state, finish with an open,
review-ready PR and green required checks. Leave the PR unmerged. Merge only
when the user asks or the project has an explicit self-merge policy.

Before implementation, define a small work contract:

- Objective.
- Testable acceptance criteria.
- Scope.
- Dependencies and blockers.
- Explicit non-goals.

A direct user request needs no issue. The request and PR carry its contract.
Use a tracker issue when the work must:

- Continue in a later session.
- Pass between agents or sessions, even during one short session.
- Coordinate concurrent workers.
- Enter a backlog.

When one agent or session hands work to another, use the issue and its
comments. Put there what the next one needs and what the previous one produced,
not only chat. Before handoff, create an issue for actionable work deferred
beyond the current scope.

A project may define optional work-unit stages in a project-specific section
outside the managed blocks. An active stage controls what may change and where
to stop:

- An implementation stage runs only its allowed checklist steps and stops
  where the active stage says to stop.
- A non-implementation stage follows its own record.
- Finishing one stage hands work off. It doesn't authorize the next stage.
- Work outside a declared stage runs the full checklist, except actions owned
  by another declared stage.

Start work only from an explicit user assignment. An issue, label, backlog
entry, satisfied dependency, completed plan, or claim isn't authorization.
An agent may choose work for itself only when an explicit project policy
allows it.

The implementation checklist:

1. Read the README. When resuming work, also read its issue or PR and linked
   decision notes. Resolve the default branch and update it from its remote.
   Start from that exact tip. Only a declared stacked PR may start elsewhere;
   see Branches.
2. Create a correctly named branch in a dedicated worktree or equivalent
   isolated checkout. See Branches for the primary-checkout exception.
3. Make the scoped change. Include the docs, tests, and assets needed to keep
   it complete. Add a decision note only when its triggers apply.
4. Run relevant verification and the standard lint, build, and test checks.
   Record any check you could not run in the PR.
5. Commit one concern at a time. Explain why in each commit body.
6. Push and open the PR with the template. Remove sections that don't apply.
7. Follow "Handing Off the PR" under Pull Requests. Leave the PR open for a
   human to review and merge.

Before committing work on a destructive path, credential-leak surface, or
returned-object trust boundary, read `docs/agent-workflow.md` §refute-first and
run its verification pass. A destructive path includes delete or cleanup. A
returned-object trust boundary is where code trusts fields returned by an
external call or deserializer. This extra pass doesn't apply to a docs typo or
unrelated refactor.

<!-- /agents-md:managed:finish-line -->

<!-- agents-md:managed:context -->

## Context Discipline

Working context is limited. Content added now is sent again with later tool
calls, so early noise makes every later step more expensive. Keep durable
state in files, such as the issue, PR body, or decision note. Keep only what
the current step needs in working context.

- **Keep raw bulk out.** Prefer a relevant file section, match list, or
  filtered log tail over a whole file or unfiltered output.
- **Delegate broad reading when supported.** Use a delegate for large searches
  or mechanical sweeps only when the platform and session permit it. Ask for
  conclusions, `file:line` references, and a short summary, never raw output.
- **Use bounded reads when delegation is unavailable.** A few targeted reads
  are also better than a delegate for a small question.
- **Match the delegate to the task.** When you can choose a model or effort
  level, use the cheapest capable option for mechanical reading. Skip this when
  the platform offers neither choice.
- **Explain large parallel work first.** One delegate for exploration or
  review is normal. Before using more, state the expected scale and get the
  user's approval or stay within a budget they already set.
- **Suggest a fresh session at a natural boundary.** After a PR handoff,
  review round, or work unit, a long session adds little value. Suggest a new
  session seeded with the PR number. The PR and decision note carry the state.

<!-- /agents-md:managed:context -->

<!-- agents-md:managed:communication -->

## Writing for Humans

People scan human-facing work such as handoffs, PRs, issues, plans, reviews,
and questions. Make the important point clear without requiring them to
translate agent jargon or search for the conclusion.

- **Lead with the bottom line.** Start with the conclusion, decision, or ask.
  Include any assumption or caveat that could change it. Put support below in
  order of importance.
- **Front-load each unit.** Begin every heading, bullet, and paragraph with
  its key words.
- **Layer detail.** Keep the decision in the skim layer. Put evidence,
  options, and detail below it or in a linked issue or note. Do not remove
  needed evidence just to make the text shorter.
- **Ask about three questions per round.** Start with questions that block the
  work. Give each a recommended answer and one-line reason. Turn questions
  with a safe default into visible assumptions the reader can reject. Save
  remaining blocking questions for the next round.
- **Reserve flags for meaningful risk.** Label severity when useful. Flag
  facts that change the decision or confidence in the result. Make rare,
  critical warnings easy to notice.
- **State uncertainty plainly.** Say what was not verified and what remains
  uncertain. Clear writing must not make weak evidence look conclusive.

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

All work lands through a PR. Resolve the default branch (`main` in the
examples) and update it from its remote. Then create an ordinary work-unit
branch from that exact tip. Never start from the current feature branch. Only
a declared stacked PR may use another base.

Use atomic commits and a real merge commit. Let a human decide when to merge.
Never commit directly to `main`, even for a small change. Direct commits break
the `--first-parent` history.

Name a branch `<type>/<short-kebab-slug>`:

- Choose a Conventional Commits type: `feat`, `fix`, `refactor`, `docs`, or
  `chore`.
- Use two to four kebab-case words for the work unit.
- Use exactly one slash. A bare `feat` can't coexist with `feat/x`.
- Omit ticket numbers, dates, and owner prefixes.
- Add an owner segment, such as `bnw/feat/...`, only when several people or
  agents work in parallel.

Examples:

```text
feat/worksheet-promotion
fix/pane-focus-race
chore/swift-format-sweep
```

Merged branches may auto-delete. If the repository doesn't do that, delete
the branch after merge.

**Plan concurrency before creating worktrees.** Keep coupled work in one work
unit, an explicit dependency chain, or a declared stack. Separate worktrees do
not make dependent changes safe to run in parallel. Before substantive work,
use the project's claim visible on the code host for an assigned concurrent
unit, when one exists. A claim only tells others that someone is already
working; it isn't permission to start.

**Isolate every implementation work unit.** Use a dedicated worktree or an
equivalent separate checkout when the platform and session support one. Create
it from the freshly updated default-branch tip. For example:

```sh
git worktree add <path> -b <type>/<slug> <default-branch>
```

Use the primary checkout only when the user or project requires it, or the
platform can't create another checkout. This can happen with no multi-checkout
support or a sandbox pinned to one directory. In that case, serialize work on
one correctly based branch, report the exception, and never run concurrent work
units in that checkout.

After merge, remove the worktree while standing outside it:
`git worktree remove <path>`.

Work that depends on an open PR may stack on its branch. See Stacked PRs under
Pull Requests.

<!-- /agents-md:managed:branches -->

<!-- agents-md:managed:pull-requests -->

## Pull Requests

One PR represents one work unit. Review it as a whole and merge it with a real
merge commit. Commits explain each atomic decision; the PR explains the full
change.

- **Write an imperative title of at most 72 characters.** Name the outcome,
  without a type prefix, ticket number, or other tracking text. The title and
  PR number become the whole merge-commit message in the intended setup. Write
  it for `git log --first-parent`.
- **Use the PR template for the body.** Include Why, What, Screenshots for UI
  changes, optional Review Notes, and Verification. Key the commit map by
  subject, not SHA. Start verification bullets with `Passed:`, `Checked:`,
  `Attempted:`, or `Not run:`. Before writing or updating the body, read
  `docs/agent-workflow.md` §pr-body. For a UI change, meet its Screenshots
  requirements.
- **Self-review the full diff in the PR files view.** Look for stray changes,
  debug code, scope creep, and accidental files. This catches accidental
  changes; it doesn't check whether the solution is correct.
- **Repeat integration checks when the base moves.** CI, final diff review,
  and readiness count only for the base commit you checked. Repeat all three
  if the base changes.
- **Use fresh eyes for substantive review.** Reviewing your own work in the
  same conversation shares the author's blind spots. A review in a fresh
  conversation is more independent. A bot from another provider or a human is
  stronger. Rely on a bot or human before handoff. For non-trivial work, or
  without a bot reviewer, read `docs/agent-workflow.md` §pre-push-review before
  pushing.
- **Record an automated reviewer you observe.** If the project has no record
  for that reviewer or signal, read `docs/agent-workflow.md` §reviewer-record
  and update the project record before handoff.
- **Judge review comments on their merits.** Fix real findings. Decline
  speculative, contrived, or already-fixed findings with a one-line reason.
  Do not comply automatically.
- **Reply after the fix is final and pushed.** Reply inline with the outcome:
  the final commit SHA for a fix, or the reason for a decline. Then resolve the
  thread. Fold all fixes from one round into their owning commits and push once
  before replying. Resolving every thread isn't a merge gate; a reasoned
  outcome is.
- **Fix the whole defect class.** Search the file and repository for the same
  pattern and fix every instance in one push. For validation or parsing code,
  read `docs/agent-workflow.md` §review-convergence before widening a pattern.
- **Keep reviewing while blockers remain.** Correctness, security, data loss,
  broken invariants, and red CI always require another round. Decide severity
  yourself; the reviewer's label is only evidence. When unsure, treat the
  finding as blocking.
- **Raise the bar as rounds continue.** After the early rounds, or when a
  finding recurs, read `docs/agent-workflow.md` §review-convergence before
  deciding on another round. Before handoff, mark every finding fixed,
  declined, deferred, or explicitly outstanding.
- **Keep the PR body current.** When review adds commits or changes scope,
  update What, the subject-based commit map, and Verification. Mark commits
  that resolve review findings. Keep each finding's outcome in its inline
  reply, not a permanent feedback section.
- **Keep the intended repository rules.** Use merge commits only, disable
  squash and rebase merges, use title-only merge messages, and auto-delete
  merged branches. Do not re-enable a disabled method. Enforce these rules
  manually where repository settings don't.

### Handing Off the PR

A PR is ready to hand off when it's open, green, self-reviewed, has no
unhandled threads, and has no outstanding review activity. After opening the
PR, read `docs/agent-workflow.md` §handing-off and follow its sequence:

1. Start the review watch from the PR open or push event. Only reviewer
   activity after that event counts as new. After another push, start counting
   from that push.
2. Refresh from the current base and record the base commit.
3. Wait for required checks. Never hand off known-red work.
4. Self-review the final diff.
5. Close the watch by handling findings or recording its bounded timeout.
6. Stop and summarize for the human reviewer.

If the user asks you to merge, read
`docs/agent-workflow.md` §merge-and-resync first and follow it step by step.
Do not merge or resync from memory.

### Reviewing a PR

Before reviewing a PR, read `docs/agent-workflow.md` §reviewing-a-pr and use
its review bar.

### Stacked PRs

Before creating a branch or PR that depends on another open PR, read
`docs/agent-workflow.md` §stacked-prs. Name the base explicitly; never inherit
it from the current checkout.

<!-- /agents-md:managed:pull-requests -->

<!-- agents-md:managed:commits -->

## Commits

History supports diagnosis, review, and learning. Keep each commit useful for
all three.

- **Keep one concern in each commit, and keep every commit green.** Split a
  commit whose body needs separate labels such as Correctness and Performance.
  Each commit must build and pass tests on its own. Never leave a red
  intermediate state that breaks `git bisect`.
- **Explain why in the body.** Use specific body text wrapped at 72
  characters. Link the work unit's decision note when one exists. Report a
  meaningful change as a delta, such as "27 to 36 tests", not an absolute
  claim such as "36 tests green" that will go stale.
- **Never commit secrets.** Keep credentials, tokens, keys, and `.env` values
  out of commits. Name the secret and use a placeholder in examples.
- **Separate mechanical churn.** Put formatting, renames, and moves in their
  own commit. Add that commit to `.git-blame-ignore-revs` in the same change,
  then enable it locally with
  `git config blame.ignoreRevsFile .git-blame-ignore-revs`.
- **Fold review fixes into the commit that caused them.** This includes issues
  found by review or self-review. Do not append an "address review" commit.
- **Keep every folded commit green.** Fold only on an unmerged feature branch.
  After merge, use a new commit. Update the matching active decision note in
  the same operation when one exists.
- **Force-push safely after a fold.** Use `--force-with-lease` on the feature
  branch. Never force-push `main`. The reset, amend, or rebase mechanism is
  your choice.
- **Push before replying to review.** The inline reply must cite the final,
  pushed SHA that contains the fix. A separate review-fix commit left on the
  branch means the fold is unfinished.
- **Never squash-merge multi-commit work.** Use a real merge commit so
  `git log --first-parent` shows the work-unit story and the full log preserves
  its atomic commits. Put narrative subjects such as "Walking skeleton:
  end-to-end flow" at the merge or PR level.

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

## Definition of Done for an Increment

An increment is done only when it's running and exercised by the end of the
work session. "Code complete" or passing tests alone isn't enough.

Before calling the work done, confirm that the build succeeds, tests pass,
and lint and formatting are clean.

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
- Reconciliation validation matrix green when merge-cleanup's
  `reconciliation-ledger.sh` changed
  (`./scripts/test-merge-cleanup-reconciliation.sh`)
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
