# Canonical Managed Sections

Each section below is the exact text to insert into a project's AGENTS.md,
including the management markers. During init, paste verbatim, except the
`agents-md:project:done-checks` block inside `done`, which is a placeholder
to fill with the project's real checks (see SKILL.md). During update,
compare the content between markers against these blocks, leaving that
nested block alone. Several blocks point at step-local procedure in the
scaffolded `docs/agent-workflow.md` (`scaffolding.md` §agent-workflow);
a project whose blocks carry those pointers must have that file.

Sections: [devlog](#section-devlog),
[finish-line](#section-finish-line), [context](#section-context),
[communication](#section-communication),
[branches](#section-branches),
[pull-requests](#section-pull-requests), [commits](#section-commits),
[done](#section-done).

---

## Section: devlog

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

---

## Section: finish-line

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
in a tracker issue when the work must survive a session boundary, pass
sequentially between agents or sessions (even within one short session),
coordinate concurrent workers, or join a backlog. For a sequential handoff,
put the durable input and output in the issue and its comments, never only in
transient chat context. Actionable work deferred out of the unit's scope gets
a tracker issue before handoff.

A project may declare optional work-unit stages in an unmanaged,
project-specific section. While a declared stage is active, its recorded
allowed mutations and finish line govern. Completing one stage creates a
handoff to the next; it does not authorize that next stage to begin.

By default, begin work only through explicit user assignment. An issue, label,
backlog entry, satisfied dependency, completed plan, or claim is not
authorization to select and start work. Agent self-selection requires an
explicit project-specific opt-in policy.

For implementation work that is not itself a declared stage, use this
checklist except actions assigned to any separately declared stage. With no
stage record, that means the entire checklist. While a declared implementation
stage is active, use only the steps compatible with its allowed mutations and
recorded finish line, then stop at its recorded transition. A declared
non-implementation stage skips this checklist and follows its recorded allowed
mutations and finish line instead:

1. Read the README and, when resuming an existing work unit, its issue or
   PR and any decision note it links. Resolve the repository's
   default branch explicitly, update it from its remote, and start ordinary
   work from that exact tip, not from whichever branch is currently checked
   out. Only an intentionally declared stacked PR may start from another open
   PR's branch (see Stacked PRs under Pull requests).
2. Create one correctly named branch from that starting tip in a dedicated
   worktree or equivalent isolated checkout. Use the primary checkout only
   when an explicit user or project instruction requires it, or when the
   platform cannot create another checkout; serialize the work there and
   report the exception.
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
deserializer), read `docs/agent-workflow.md` §refute-first before
committing and run the refute-first verification pass it describes; a
docs typo or a refactor off these paths doesn't trigger it.

<!-- /agents-md:managed:finish-line -->

---

## Section: context

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

---

## Section: communication

<!-- agents-md:managed:communication -->

## Writing for humans

Agent-produced text works only if a human absorbs its load-bearing
part, and humans scan rather than read: roughly a fifth of the words
on a screen, weighted toward first lines and line-starts, with about
four open items held in mind and rapid tune-out of repeated warnings.
Write every human-facing artifact (a handoff, a PR body, an issue, a
plan, a review comment, a question) for that reader; never rely on
them digging.

- **Bottom line first.** Open the artifact with its conclusion,
  decision, or ask, along with any assumption or caveat it stands or
  falls on; supporting material follows in descending importance. A
  reader who stops after the opening still acts correctly.
- **Front-load every unit.** The first words of a heading, bullet, or
  paragraph carry its information; a key point buried mid-paragraph is
  effectively unwritten.
- **Layer, don't just shrink.** The artifact is also the durable
  record: the skim layer carries the decision, while evidence,
  alternatives, and detail live below it or in the linked note or
  issue. Cutting the record to shorten the skim layer loses what later
  diagnosis needs.
- **Few asks per round, with defaults.** Surface the questions that
  gate the work, about three at a time, each with a recommended answer
  and a one-line reason. Convert questions a sensible default settles
  into visible assumptions the reader can veto; queue the remaining
  gating questions for a later round rather than assuming through
  them. A human handed ten questions silently drops most of them.
- **Ration flags, and calibrate them.** Tag severity, flag what
  changes the reader's decision or how much to trust the result, and
  make rare critical warnings visually distinct; humans habituate to
  repeated warnings within a few exposures, and a page of routine
  hedges buries the one that matters.
- **Surface uncertainty; don't polish past it.** Fluent, confident
  prose invites rubber-stamping. State what was not verified and where
  you are unsure, so the human's attention lands where checking is
  needed.

<!-- /agents-md:managed:communication -->

---

## Section: branches

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

**Isolate every implementation work unit.** Each implementation work unit uses
a dedicated worktree or equivalent isolated checkout by default. Where your
platform and session support a second checkout (a native worktree tool or
session flag, or plain
`git worktree add <path> -b <type>/<slug> <default-branch>`), create the branch
and checkout from the freshly updated default-branch tip, not from whatever
branch is checked out. Use the primary checkout only when an explicit user or
project instruction requires it, or when the platform cannot create another
checkout (no multi-checkout support, or a sandbox pinned to one directory). In
either case, serialize all work on one correctly based branch in the primary
checkout and report the exception; never run concurrent work units in one
checkout. Remove a worktree once its branch merges, standing outside the one
being removed (`git worktree remove <path>`): git does not stop a session from
unlinking its own working directory.

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
  intended repo setup the PR title (plus its number) is the _entire_
  merge commit message: merges are title-only, so the body's review
  material (screenshots, verification, review notes) never lands in
  history, and `git log --first-parent` reads as the list of PR
  titles; write the title for that log either way.
- **Body**: scaffolded by the repo's PR template (on GitHub:
  `.github/pull_request_template.md`):
  Why, What (outcome bullets and a commit map keyed by subject, not
  SHA), Screenshots (UI changes only), Review Notes (optional), and
  Verification (bullets starting `Passed:`, `Checked:`, `Attempted:`, or
  `Not run:`; facts only). Before writing or updating the body, read
  `docs/agent-workflow.md` §pr-body and meet each section's bar (for UI
  changes, the Screenshots attachment bar).
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
  already stops at an open PR for one. For a non-trivial change, or a
  repo without a bot reviewer, read `docs/agent-workflow.md`
  §pre-push-review before pushing and run the platform-gated review it
  describes.
- **Record a noticed automated reviewer.** When you observe a bot-authored
  review on a recent PR, or a reviewer status signal, that the project
  hasn't recorded (or has recorded without that signal), read
  `docs/agent-workflow.md` §reviewer-record and add or augment the record
  before handing off: a later watch filters by the recorded login and
  finishes on the recorded clean-pass signal, so an absent or partial
  record costs the full wait cap.
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
  validation or parsing code the sweep is the adversarial input-space
  enumeration in `docs/agent-workflow.md` §review-convergence; read it
  before widening the cited pattern.
- **Converge on a bar that rises with the rounds.** Blocking findings
  (correctness, security, data-loss, broken invariants, red CI) always
  earn another round. When a review exchange passes its early rounds, a
  finding recurs, or you are deciding whether to take another round,
  read `docs/agent-workflow.md` §review-convergence and apply it before
  deciding; hand off with every finding dispositioned (fixed, declined,
  deferred, or explicitly outstanding).
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
no new review activity outstanding. Once the PR is up, read
`docs/agent-workflow.md` §handing-off and follow it; in short:

- **Start one review-watch per PR/reviewer as soon as the PR is open**,
  before waiting on checks, anchored to the open or push event that
  should produce the next reviewer pass (mechanics and baseline rules
  in §handing-off).
- **Validate against the current base before final handoff**: update
  the PR branch from the base tip, rerun verification, self-review the
  refreshed diff, and record the base commit used (§handing-off).
- **Wait for required checks** and fix any red check on the branch;
  never hand off a known-red PR.
- **Self-review the diff** (above) so it's ready for a reviewer.
- **Close out the watch before handoff**: address in-scope findings on
  the branch, or record the bounded timeout / no-review result with the
  baseline (§handing-off).
- **Stop and summarize**: say the PR is open and green, surface what
  the reviewer should focus on, and leave merging, branch cleanup, and
  the `main` resync to whoever approves it.

If the user does ask you to merge, read `docs/agent-workflow.md`
§merge-and-resync before the merge or resync and follow it step by
step; do not merge or resync from memory.

### Reviewing a PR

When asked to review a PR, read `docs/agent-workflow.md` §reviewing-a-pr
first and hold its bar: severity-tagged findings with evidence and a
concrete ask, and only blockers gate the merge.

### Stacked PRs

Before creating a branch or PR that depends on an open PR, read
`docs/agent-workflow.md` §stacked-prs and declare the base explicitly;
never inherit it from the current checkout.

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

---

## Section: done

<!-- agents-md:managed:done -->

## Definition of done for an increment

Each increment is something actively used by the end of the work session:
not "code complete" or "tests pass" alone, but running and exercised.
Before calling work done:

The build succeeds, tests pass, and lint and formatting are clean.

<!-- agents-md:project:done-checks -->

<!-- TODO: replace with this project's real verification commands during
     init: the test command, the lint/format command, and the checks
     specific to this project's change classes (e.g. "affected surfaces
     verified in the running application"). -->

- Tests green
- Lint/format clean

<!-- /agents-md:project:done-checks -->

<!-- /agents-md:managed:done -->
