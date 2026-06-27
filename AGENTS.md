# free-skills

An open-source collection of prompt-based agent skills designed to work
across platforms (Claude Code, Codex, and others). See
[README.md](README.md) for the project overview. This file covers
development conventions, contribution workflow, and project structure.

<!-- agents-md:managed:devlog -->

## Devlog (session bookends)

`devlog/` holds the reasoning trail — one short entry per working
session (see `devlog/README.md` for the protocol).

- **Before starting:** read the most recent one or two entries
  (`find devlog -maxdepth 1 -type f -name '*.md' ! -name README.md | sort | tail -2`)
  — they carry decisions and deliberate deferrals that aren't in the spec.
  Don't re-litigate or "fix" what an entry marks as decided/deferred without
  the user asking. Also `grep` the devlog for the open `To promote` /
  deferred / needs-human queue so promotions don't span sessions unnoticed.
- **Before finishing:** append `devlog/YYYY-MM-DD-HHMM-slug.md` — decisions
  (why, and what was rejected), deferrals, open questions. Note anything
  that should be promoted to AGENTS.md — a new invariant discovered, a
  convention that wasn't written down, a gotcha that bit you. The devlog
  entry records it; a follow-up commit promotes it. Use local 24-hour
  time so same-day entries sort in session order. Keep it dense — decisions,
  not narration; target ≤ ~40 lines per session-round, scaling when one entry
  consolidates many review rounds. Commits and PR threads carry the
  what-changed.

<!-- /agents-md:managed:devlog -->

<!-- agents-md:managed:finish-line -->

## Default agent finish line

For any user request that asks you to change code, docs, assets, or project
state, the default endpoint is **an open, review-ready PR with required
checks green** — not a merged branch. Merging is a human decision; do not
merge your own PR unless the user explicitly asks, or the project has adopted
an opt-in self-merge workflow.

Use this checklist at the start of each work session:

1. Read README plus the latest devlog entries, then start from `main` — or,
   for a follow-up that depends on an open PR, from that PR's branch (see
   Stacked PRs under Pull requests).
2. Create one correctly named branch for the work unit.
3. Make the scoped change, including docs/devlog/tests/assets that keep it
   complete.
4. Run the relevant verification plus the standard lint/build/test checks
   before PR; if any check cannot run, record the exact gap in the PR.
5. Commit one concern at a time with a body that says why.
6. Before opening a docs/chore PR (or at session end), `grep` the devlog
   for the open promote / deferred / needs-human queue and clear what the
   current scope covers, or explicitly re-defer — decided invariants
   shouldn't live only as devlog archaeology.
7. Push, open the PR with the template, and remove sections that do not apply.
8. Poll required checks until they finish; fix failures on the branch.
9. Self-review the PR files view, then hand off — leave the PR open for a
   human to review and merge.

For changes on a **destructive path** (delete/cleanup), a
**credential-leak surface**, or a **returned-object-trust boundary**, add a
refute-first verification pass before committing — independent lenses whose
job is to _disprove_ the fix — and record in the devlog which findings were
confirmed, rejected-by-verification (so they're not re-raised), and
accepted-by-decision. Scope this to those risk classes; a docs typo or
pure refactor shouldn't trigger it.

Stop once the PR is open, green, and self-reviewed. Say what remains (review
and merge) and point the reviewer at anything that needs attention. Don't
merge, delete the branch, or resync `main` yourself unless the user asks for
that, or the project has adopted a self-merge workflow.

<!-- /agents-md:managed:finish-line -->

## Build, test, run

This is a markdown-only project — no compile or build step.

### Lint

```sh
npx markdownlint-cli2 '**/*.md'
```

### Format

```sh
npx prettier --check '**/*.md'
npx prettier --write '**/*.md'   # to fix
```

### CI

<!-- TODO: Add CI configuration (.github/workflows/) once the repo has
     content worth gating. The workflow conventions in this file assume CI
     exists — set it up before the first real PR. -->

CLAUDE.md is a pointer that imports AGENTS.md — edit AGENTS.md, never the
pointer.

## Project structure

```text
skills/
  <skill-name>/
    SKILL.md           # The skill prompt (required entry point)
    ...                # Additional files as needed per skill
```

Each skill lives in its own directory under `skills/`. The only required
file is `SKILL.md` — the skill prompt with YAML frontmatter (name and
description) that an agent loads to execute the skill. Additional files
(reference material, examples, sub-prompts) may live alongside it.

## Architecture invariants

1. **One directory per skill.** All skill content lives under
   `skills/<skill-name>/`. No top-level loose skill files. This prevents
   naming collisions and keeps each skill self-contained.

2. **Platform-agnostic prompts.** Skills must work across Claude Code and
   Codex (and ideally other agent platforms). Avoid platform-specific tool
   calls or assumptions in prompt text; when platform-specific behavior is
   needed, gate it explicitly and document the fallback.

3. **`SKILL.md` is the entry point.** Every skill directory must contain a
   `SKILL.md`. This is the file an agent loads to execute the skill.
   Both Claude Code and Codex discover skills by this filename.

## Conventions

- **README skills table is alphabetical by skill name.** Insert a new
  skill's row in order, not appended at the end.

- **`SKILL.md` frontmatter must parse as YAML; write `description` as a `>-`
  block scalar.** Skill indexers read `name`/`description` as YAML, so a plain
  (unquoted) scalar silently fails to load the skill when its text contains a
  colon-then-space (e.g. `proactively: the`), a leading `#`, or other YAML
  structural characters. A `>-` folded block scalar keeps the text literal and
  parse-safe — use it for new skills. Existing plain-scalar descriptions are
  acceptable only while they stay parse-safe; converting them to `>-` is a
  welcome hardening. Verify with any YAML parser when unsure. (Surfaced by a P1
  review on the visual-evidence skill; see the 2026-06-26 devlog.)

<!-- TODO: Fill in more as patterns emerge — prompt structure guidelines,
     how to handle skill dependencies, testing/validation patterns. -->

<!-- agents-md:managed:branches -->

## Branches

All work lands through a PR: branch from `main`, do the work as atomic
commits (see Commits), open a PR, merge with a real merge commit —
never commit directly to `main`. No triviality exception; exceptions
are where the `--first-parent` narrative erodes.

Name branches `<type>/<short-kebab-slug>` — type from the Conventional
Commits vocabulary (`feat`, `fix`, `refactor`, `docs`, `chore`), slug
2–4 kebab-case words naming the work unit:

```text
feat/worksheet-promotion
fix/pane-focus-race
chore/swift-format-sweep
```

Exactly one slash — refs are path-like, so `feat/x` and a branch named
just `feat` can't coexist. No ticket numbers, dates, or owner prefixes;
prepend an owner segment (`bnw/feat/…`) only if multiple people or
agents start pushing in parallel. Merged branches auto-delete (repo
setting) — the merge commit carries the narrative.

Follow-up work that depends on an open PR can stack on its branch instead
of waiting — see the Stacked PRs pattern under Pull requests.

<!-- /agents-md:managed:branches -->

<!-- agents-md:managed:pull-requests -->

## Pull requests

A PR is one work unit, reviewed as a whole and merged with a real merge
commit. Commits carry the atomic why (see Commits); the PR carries the
arc.

- **Title** — imperative, ≤ 72 chars, names the outcome, no type prefix
  or ticket noise ("Fix missing menu bar on unbundled launch"). Repo
  settings put the PR title and body into the merge commit, so
  `git log --first-parent` reads as the list of PR titles — write the
  title for that log.
- **Body** — scaffolded by `.github/pull_request_template.md`:
  - **Why** — prose, one to three short sentences. State the problem or
    motivation. Link the devlog entry when one exists; don't duplicate it.
    Add a close keyword immediately before each issue number the PR fully
    resolves or finishes (`Closes #11`; repeat the keyword to close several
    — `Closes #11, closes #12` — since a bare list like `Closes #11, #12`
    closes only the first). Reference related-but-unfinished issues with a
    plain `#N` (e.g. `Refs #N`), which links without closing, and leave
    those for a human.
  - **What** — required bullets. Describe work-unit outcomes, not
    file-by-file churn. For multi-commit PRs, use a compact commit map
    (one bullet per commit or concern) and say rejected alternatives live
    in the devlog when they do.
  - **Screenshots** — required for PRs with visible UI changes; delete it
    for non-visual work. Replace the section with actual GitHub-hosted,
    reviewer-visible image or recording attachments before merging; local
    paths, textual descriptions, and "checked locally" notes do not satisfy
    it. If you cannot attach the artifacts yourself, stop before merge and
    ask the user to add or confirm them. Show the changed surfaces,
    important states, and both paper/ink palettes when the change affects
    appearance. Keep captions short and name the state shown. Verification
    still belongs in Verification.
  - **Review Notes** — optional bullets; delete the section when it adds
    no routing value. Use it to point reviewers at important files, review
    order, mechanical commits, or risky edges.
  - **Verification** — required bullets. Start each with `Passed:`,
    `Checked:`, `Attempted:`, or `Not run:`. Say what was actually run and
    observed: tests, lint, fixture/screenshot checks (both palettes for
    UI), export/import round-trip for schema changes. Facts only — never
    "should work"; verification gaps are explicit `Not run:` bullets.
    Factual doc claims ship under the same discipline: counts, flags,
    behaviors, and subprocess/network guarantees are checked against the
    code and scoped to the surface they describe (a compiled CLI and a
    wrapper script differ), stated without marketing or competitor
    put-downs.
- **Self-review the diff in the PR files view before handing off** — it
  catches stray hunks and leftovers the editor view didn't.
- **Responding to automated review.** Bot reviewers (inline P1/P2
  comments) draw a lot of feedback; evaluate each comment on its merits.
  Fix real findings; push back — _with a one-line reason_ — on contrived,
  speculative, or already-fixed ones. Do not reflexively comply. Reply
  inline with the disposition and the fixing commit SHA ("Fixed in
  `<sha>`" / a reasoned decline), then resolve the thread. Resolving every
  thread is _not_ a hard merge gate — evaluate-on-merits is.
- **Fix the class, not just the cited line.** When a finding names one
  location, sweep the file/repo for the same class and fix every instance in
  the same push — otherwise the bot re-reviews on the next push and flags the
  siblings one at a time, so sweeping converges in far fewer cycles. Expect
  that re-review loop, and expect diminishing returns: automated reviewers can
  surface ever-smaller nits indefinitely, so converge and hand off rather than
  chasing every round to zero (value captured is the bar, not threads-at-zero).
- **Keep the body current as review evolves the PR.** The body becomes the
  merge commit, so when review adds commits or shifts scope, update What, the
  commit map (flag which commits resolve review findings), and Verification
  before re-handing-off. The inline disposition + fixing SHA on each resolved
  thread (above) is the located per-finding record — don't duplicate it into
  a standing "feedback" section that would drift.
- Merge-commit merges are the only enabled method (squash and rebase
  are disabled in repo settings) and merged branches auto-delete — the
  settings enforce the Commits rules; don't re-enable around them.

### Handing off the PR

Opening the PR is the agent's finish line — leave it open for a human to
review, approve, and merge, unless the user explicitly asks you to merge or
the project has adopted a self-merge workflow. Once the PR is up:

- **Wait for required checks** — poll `gh pr checks <n>` until they
  complete; fix any red check on the branch, never hand off a known-red PR.
- **Self-review the diff** (above) so it's ready for a reviewer.
- **Watch for new review activity between turns** — the finish line means
  open, green, threads handled, self-reviewed, _and no new review activity
  outstanding_. Poll open PRs for _both_ new review comments and CI,
  address findings on the branch, and only then declare done. This is
  guidance, not mandated automation.
- **Stop and summarize** — say the PR is open and green, and surface
  anything the reviewer should focus on. Leave merging, branch cleanup, and
  the `main` resync to whoever approves it.

If the user does ask you to merge, use `gh pr merge <n> --merge` (the only
enabled method; the remote branch auto-deletes), then resync
(`git checkout main && git pull --ff-only`), delete the local branch
(`git branch -d <branch>`), and `git fetch --prune`.

### Reviewing a PR

The mirror of "Responding to automated review" — hold the bar you'd want
held for you. Use the project's review tooling for the bug-hunting pass;
these are the conventions for the comments it produces.

- **Calibrate to severity, and tag it.** Separate blocking findings
  (correctness, security, data-loss, red tests/CI, broken invariants) from
  non-blocking ones (naming, style, optional simplification). Only blockers
  gate the merge. Don't manufacture speculative or contrived findings — the
  author convention is to decline those with a one-line reason.
- **Every comment carries evidence and a concrete ask.** Point at
  `file:line`, name the failure it causes, and propose a fix or ask a
  question. Mark uncertainty as uncertainty ("possible:"), never assert it —
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
  fix-or-decline. Resolving every thread isn't the gate — agreement on
  blockers is.

### Stacked PRs

Dependent docs or cleanup work can proceed without waiting for its base: a
follow-up PR can be based on an open PR's branch (`gh pr create --base
<feature-branch>`) and auto-retargets to `main` when the base merges. Two
gotchas: while the base is open the stacked PR's diff shows only its own
commits; and if the base is force-pushed (fold-fix above), `rebase --onto`
the stack onto the new base tip.

<!-- /agents-md:managed:pull-requests -->

<!-- agents-md:managed:commits -->

## Commits

History is optimized for three uses: diagnostics (blame/bisect lead to a
cause), reviewability (a PR reads commit-by-commit), and learning (the
log tells the project's evolution). Rules:

- **One concern per commit, every commit green.** If the body wants
  labeled sections (Correctness:/Performance:/…), it's more than one
  commit — split it. Each commit must build and pass tests on its own;
  never leave red intermediate states (it breaks bisect).
- **Body says why, not just what.** Keep the current style: dense,
  specific, wrapped ≤ 72 columns. Reference the session's devlog entry
  when one exists. State change deltas ("27 → 36 tests") if meaningful;
  never absolute status ("36 tests green") — CI asserts that, and it
  goes stale.
- **Mechanical churn commits alone.** Reformats, renames, and moves get
  their own commit, added to `.git-blame-ignore-revs` in the same change
  (activate locally with
  `git config blame.ignoreRevsFile .git-blame-ignore-revs`).
- **Fold review fixes into the commit they belong to.** When a review
  comment or self-review turns up a fix for code in an already-pushed
  commit, fold it into that commit rather than appending an "address
  review" commit — the merged PR keeps its clean, bisectable structure.
  Guardrails: every commit still builds and passes tests after the fold;
  `--force-with-lease`, **feature branch only — never force-push `main`**;
  only while the PR is unmerged (once merged, a fix is a new commit);
  update the matching devlog entry in the same operation. The mechanism
  (reset/amend/rebase) is your judgement.
- **Never squash-merge multi-commit work** — it destroys the atomic
  structure above. Merge with a real merge commit so
  `git log --first-parent` reads as the work-unit narrative and the full
  log holds the atoms. Narrative subjects ("M2+M3: walking skeleton…")
  belong at that merge/PR level.

<!-- /agents-md:managed:commits -->

<!-- agents-md:managed:done -->

## Definition of done for an increment

Each increment is something actively used by the end of the work session —
not "code complete" or "tests pass" alone, but running and exercised.
Before calling work done:

<!-- agents-md:project:done-checks -->

- Markdown lint clean (`npx markdownlint-cli2 '**/*.md'`)
- Format clean (`npx prettier --check '**/*.md'`)
- New or changed skills have a valid `SKILL.md` with parse-safe YAML
  frontmatter (`description` as a `>-` block scalar — see Conventions)
- Skill prompts reviewed for platform-agnostic language (no
Claude-Code-only or Codex-only assumptions without explicit gates)
<!-- /agents-md:project:done-checks -->

<!-- /agents-md:managed:done -->
