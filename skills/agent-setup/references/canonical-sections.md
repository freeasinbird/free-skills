# Canonical Managed Sections

Each section below is the exact text to insert into a project's AGENTS.md,
including the management markers. During init, paste verbatim. During
update, compare the content between markers against these blocks.

---

## Section: devlog

<!-- agents-md:managed:devlog -->

## Devlog (session bookends)

`devlog/` holds the reasoning trail — one short append-only entry per
working session (see `devlog/README.md` for the protocol).

- **Before starting:** read the most recent one or two entries
  (`find devlog -maxdepth 1 -type f -name '*.md' ! -name README.md | sort | tail -2`)
  — they carry decisions and deliberate deferrals that aren't in the spec.
  Don't re-litigate or "fix" what an entry marks as decided/deferred without
  the user asking.
- **Before finishing:** append `devlog/YYYY-MM-DD-HHMM-slug.md` — decisions
  (why, and what was rejected), deferrals, open questions. Note anything
  that should be promoted to AGENTS.md — a new invariant discovered, a
  convention that wasn't written down, a gotcha that bit you. The devlog
  entry records it; a follow-up commit promotes it. Use local 24-hour
  time so same-day entries sort in session order. ≤ 40 lines; commits carry
  the what-changed.

<!-- /agents-md:managed:devlog -->

---

## Section: finish-line

<!-- agents-md:managed:finish-line -->

## Default agent finish line

For any user request that asks you to change code, docs, assets, or project
state, the default endpoint is **an open, review-ready PR with required
checks green** — not a merged branch. Merging is a human decision; do not
merge your own PR unless the user explicitly asks, or the project has adopted
an opt-in self-merge workflow.

Use this checklist at the start of each work session:

1. Read README plus the latest devlog entries, then start from `main`.
2. Create one correctly named branch for the work unit.
3. Make the scoped change, including docs/devlog/tests/assets that keep it
   complete.
4. Run the relevant verification plus the standard lint/build/test checks
   before PR; if any check cannot run, record the exact gap in the PR.
5. Commit one concern at a time with a body that says why.
6. Push, open the PR with the template, and remove sections that do not apply.
7. Poll required checks until they finish; fix failures on the branch.
8. Self-review the PR files view, then hand off — leave the PR open for a
   human to review and merge.

Stop once the PR is open, green, and self-reviewed. Say what remains (review
and merge) and point the reviewer at anything that needs attention. Don't
merge, delete the branch, or resync `main` yourself unless the user asks for
that, or the project has adopted a self-merge workflow.

<!-- /agents-md:managed:finish-line -->

---

## Section: branches

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

<!-- /agents-md:managed:branches -->

---

## Section: pull-requests

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
- **Self-review the diff in the PR files view before handing off** — it
  catches stray hunks and leftovers the editor view didn't.
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
- **Stop and summarize** — say the PR is open and green, and surface
  anything the reviewer should focus on. Leave merging, branch cleanup, and
  the `main` resync to whoever approves it.

If the user does ask you to merge, use `gh pr merge <n> --merge` (the only
enabled method; the remote branch auto-deletes), then resync
(`git checkout main && git pull --ff-only`), delete the local branch
(`git branch -d <branch>`), and `git fetch --prune`. A stacked follow-up PR
retargets to `main` on its own once its base merges.

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
- **Never squash-merge multi-commit work** — it destroys the atomic
  structure above. Merge with a real merge commit so
  `git log --first-parent` reads as the work-unit narrative and the full
  log holds the atoms. Narrative subjects ("M2+M3: walking skeleton…")
  belong at that merge/PR level.

<!-- /agents-md:managed:commits -->

---

## Section: done

<!-- agents-md:managed:done -->

## Definition of done for an increment

Each increment is something actively used by the end of the work session —
not "code complete" or "tests pass" alone, but running and exercised.
Before calling work done:

<!-- agents-md:project:done-checks -->

- Tests green
- Lint/format clean
- Affected surfaces verified in the running application
- Schema/data-model changes round-trip through the serialization boundary
<!-- /agents-md:project:done-checks -->

<!-- /agents-md:managed:done -->
