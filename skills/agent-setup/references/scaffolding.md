# Scaffolding Files

Content for project files created during agent setup. Copy each section's
content verbatim into the target file. If the target file already exists,
don't recreate it: drift handling (compare against the template, show the
diff, offer to refresh) is defined in `references/managed-blocks.md`
§scaffold-files.

---

## §devlog-readme

Target: `devlog/README.md` (scaffolded under the Decision-log and
High-assurance profiles only)

```markdown
# Decision Notes

`devlog/` holds selected decision records, not session logs. Most work needs
no note. AGENTS.md explains when to write one; this file explains how.

AGENTS.md and this README always state the current rules. When an old note
conflicts with them, use the current rules. The note remains a record of how
the project reached its earlier decision.

## Protocol

- **Use one file per note.** Name it `YYYY-MM-DD-HHMM-slug.md` with local
  24-hour time. Separate files let parallel branches add notes without a merge
  conflict, while the timestamp keeps same-day notes ordered.
- **In the ordinary case, keep at most one permanent note per work unit or
  PR.** Update an active note while its work is open, including when review
  fixes are folded into earlier commits. Freeze the note when the PR merges.
  Put a later correction in a new note.
- **Write for a future reader revisiting the decision.** Use the shape "Chose
  X over Y because Z." Name who decided when it matters, such as the user, a
  reviewer, or the agent.
- **Record lasting reasons and evidence.** Include the final reasoning,
  rejected options, changed assumptions, and findings that changed a decision
  or closed a risk. Do not include chronology, diffs, test logs, or PR status.
- **Add a "Revisit when ..." condition when useful.** It states when the
  decision should be reconsidered. It isn't open work and needs no deadline
  or status tracking.
- **Put actionable follow-ups in issues.** Link the note from an issue that
  starts there. The note may keep a historical `Follow-up: #N` link, but the
  issue owns the current status.

## Historical Entries

Older entries may use session bookends, `## To promote` queues, or `->`
status markers. Leave them unchanged. Read them as evidence when relevant, but
do not act on their queues. Move any work that is still actionable into the
issue tracker.
```

---

## §pr-template

Target: `.github/pull_request_template.md`

```markdown
<!-- Title: imperative, ≤ 72 chars, names the outcome; it becomes the
     merge-commit subject, so write it for `git log --first-parent`. -->

## Why

<!-- One to three short prose sentences. Link the decision note when one
     exists; don't duplicate it. Add a close keyword immediately before each
     issue number the PR fully resolves or finishes: `Closes #11`, repeating
     the keyword to close several (`Closes #11, closes #12`), since a bare
     list `Closes #11, #12` closes only the first. Reference
     related-but-unfinished issues with a plain `#N` (e.g. `Refs #N`) and
     leave those for a human. -->

## Scope

<!-- Required. One line naming the areas touched, for example
     `Scope: skills/agent-setup, scripts/`. -->

## What

<!-- Bullets required. One outcome bullet per change, in behavior terms:
     what a user, agent, or caller can now do or see. When the issue has
     numbered acceptance criteria, write one bullet per criterion, in the
     issue's order, and add a change bullet only for an outcome no criterion
     covers. No bullet cap; about 25 words is the shape of a bullet, not a
     limit. No file lists and no commit map. Say rejected alternatives live
     in the decision note when they do; don't duplicate them. -->

## Departures

<!-- Required. Up to three bullets, or the single word "None". Each bullet
     names a change from the issue, plan, or contract and why; an addition
     beyond it; or a criterion left unmet or work left undone, with the
     issue that tracks it. -->

## Screenshots

<!-- Required for PRs with visible UI changes; delete for non-visual PRs.
     Replace this section with actual forge-hosted, reviewer-visible image or
     recording attachments before handing off, and in every case before merge.
     Local paths, textual descriptions, and "checked locally" notes do not
     satisfy this section. -->

## Review Notes

<!-- Optional; delete it when empty. Up to three bullets, each a place to
     look (a file to read first, a mechanical commit to skip, a risky edge)
     or a call the reviewer must make (an assumption to veto, a criterion to
     judge). Review rounds, folded findings, coordination, and merge-order
     notes stay in the threads and on the issue. Add a commit map only for four or more
     commits or a mechanical commit to skip, keyed by commit subject not SHA
     (folding review fixes rewrites SHAs). -->

## Verification

<!-- Bullets required, up to five. Start each bullet with Passed:, Checked:,
     Attempted:, or Not run:. List only what CI does not show:
     change-specific checks with counts as deltas ("82 to 86 cases"), manual
     or device checks, and schema round-trips. Add one Not run: bullet per
     check the change needs and could not get, never for suites of untouched
     components. No standard-check inventory, base SHA, or audit command.
     When CI shows everything, write the single bullet "Passed: required
     checks." Facts only, never "should work". -->
```

---

## §contributing

Target: `CONTRIBUTING.md`

```markdown
# Contributing

Development conventions (branch naming, pull requests, commits, build
commands, and coding standards) live in
[AGENTS.md](AGENTS.md). That file is the single source of truth for both
human contributors and automated agents.

## AI-Assisted Contributions

AI-assisted contributions are welcome when they are understood, reviewed, and maintained by the human contributor.

By opening a pull request, you are asserting that:

- You understand the change.
- You have reviewed the generated material for correctness, security, licensing, and fit.
- You can explain the implementation and respond to review.
- You are not submitting unmodified AI output that you cannot maintain.
- You have not knowingly included code or content that violates another project's license.

Maintainers may close AI-generated issues, pull requests, or comments that appear automated, low-context, unreviewed, duplicative, or unmaintainable.

AI may assist in the work, but you are accountable for it.
```

---

## §claude-md

Target: `CLAUDE.md`

```markdown
# CLAUDE.md

The development guide lives in AGENTS.md:

@AGENTS.md
```

---

## §agent-workflow

Target: `docs/agent-workflow.md`

Step-local procedure that the canonical managed sections point at by path
and `§slug`; a project whose managed blocks carry those pointers must have
this file, or the conventions they point at are unreachable.

````markdown
# Agent Workflow Reference

The core sections of AGENTS.md point here for procedures used at specific
steps. Read a section when the core tells you to. Once read, its rules have the
same force as the core rules.

## handing-off

The core "Handing Off the PR" section gives the summary. After opening the PR,
follow this full sequence:

1. **Start the review watch immediately.** Start one watch for each recorded
   or observed automated reviewer before waiting for checks. This prevents the
   checks wait from delaying review.

   When the project's reviewer record is `none` (§reviewer-record), start no
   watch, so steps 2 and 6 have none to anchor or close. Don't scan past PRs
   for a reviewer; the human reviewer reviews at handoff.

   Before choosing a method, check whether a review-watch skill is installed,
   such as `await-pr-review`: list the available skills or look in the
   platform's skill directories. Check even when you recall none; a skill
   listing shown at session start can drop out of context once the session is
   condensed. When one exists, invoke it and let it own the review watch, even
   when the host offers its own PR or CI monitor.

   Otherwise, prefer a tool or automation that reports back without manual
   polling, then a permitted background poll or scheduled wake-up when the
   platform supports it. Do not ask whether to watch.

   If that method needs permission you don't have, use the next permitted
   method. Without background support, use a bounded foreground poll when it
   fits the turn. Otherwise, choose and record the starting event described in
   step 2 as the baseline, then hand the PR back with the review still pending.
   Never skip the review silently.

2. **Choose the event that starts the watch.** Use the PR open, ready, or push
   event for reviews triggered by those events. Use the request time for a
   no-push recheck, such as marking ready or requesting review manually.

   Record this starting event as the watch baseline. Only reviewer activity
   after that event counts as new, even if the watch starts later. After
   another push, start counting from that push and replace the earlier watch.
   Do not leave duplicate watchers running.

3. **Validate against the current base.** Resolve the latest base tip and
   check that the PR merges cleanly into it, with the project's merge-result
   audit when it has one, else `git merge-tree --write-tree`, which builds the
   merge without a checkout. Record the tip you checked in the handoff, not
   the PR body.

   The landing check decides whether you also refresh the branch:

   - **A merge queue or land command** tests the PR combined with the tip it
     selects and reruns CI there, so it integrates the PR with the tip itself.
     Refresh before handoff only when your merge check finds a conflict, or a
     change on the base needs a fix in this PR. Otherwise hand the PR off
     behind the tip: a refresh adds a CI run and a review restart and saves
     the lander no work. If the base moves before your step 7 report, check
     again and refresh only for the same reasons. After handoff, leave the PR
     waiting. Refresh only when the lander hands it back (a merge queue does
     so by removing it) or the owner asks.
   - **Only a required check that must pass on the branch updated to the
     tip** (on GitHub, the up-to-date rule): nobody else pushes that update,
     so refresh before handoff and again whenever the base moves before
     approval. The check reruns on each push.
   - **No landing check:** refresh before handoff, and repeat the integration
     pass by hand whenever the base moves.

   Refresh from the tip, preferring rebase so `git range-diff` applies. Push
   the refreshed branch so the required checks run on it. After a rebase that
   conflicted, run `git range-diff` between the branch before and after the
   rebase, and record what the resolution changed in the PR's Verification
   section. Don't repeat CI by hand; read `git range-diff` only when a rebase
   conflicts. After approval, step 7 applies, and whoever lands the PR updates
   the branch.

   A landing check reruns CI, not review. A clean rebase can still change the
   diff, for example by following an upstream rename. When you push a refresh,
   the recorded automated reviewer's pass on that push reads the new diff;
   without one, self-review the refreshed diff. Either way, the push restarts
   any review watch (step 2), and handoff waits for it to close (step 6).

   If a refresh is needed and you can't update the branch, report that it's
   stale. Do not rewrite a branch you don't own.

4. **Wait for required checks.** Poll until they finish. On GitHub, use
   `gh pr checks <n>`. Fix red checks on the branch. Never hand off a known-red
   PR.

5. **Self-review the full diff.** Apply the self-review rule under Pull
   requests so the change is ready for another reviewer.

6. **Close the review watch.** Check for both new review comments and CI.
   Address findings that belong to this PR, or record the bounded timeout or
   no-review result with its baseline.

   The same wait applies after the one last push §review-convergence allows.
   Wait for the review that push triggers, or for the bounded timeout, before
   step 7. A blocker in that review reopens fix rounds. If it has none, defer
   or decline its findings and do not push again.

7. **Stop and report.** End the turn with this report as its final message.
   Give the parts below in this order, each with its bold lead words, and use
   no headings or tables. Aim for 60 to 120 words. Omit a part only where its
   rule says so.

   1. **Status.** One line: the PR link once, the tip step 3 checked,
      then "open and green, ready to merge." For a PR you handed off behind
      the tip under step 3, write "open and green, behind the tip, waiting for
      the lander" instead; §merge-and-resync covers a direct merge. When it
      isn't green, say what is red or conflicting and what you are doing about
      it; never present a red or conflicting PR as ready. Name any open sibling
      PR that touches the same files, and the landing order. For a stack,
      write one Status line per PR.
   2. **Result.** One or two sentences on what the change does once merged, in
      behavior terms. List no files, commits, or "what changed" bullets; the
      PR body carries them.
   3. **Your call.** Up to three bullets, each a choice the owner can veto,
      with the default named: a departure from the issue or plan, an
      assumption, or a finding declined on judgment. Omit when none.
   4. **Left for you.** Up to three bullets on what the owner must do besides
      merge. Each is a thread that needs their word, a check only they can
      run, a follow-up filed as #N or still to file, or a sibling PR to
      refresh after this one lands. Omit when none.
   5. **Skipped.** Up to two bullets, each a workflow step not run and why:
      the review watch a `none` reviewer record skipped (step 1), screenshots
      not captured or not uploaded (with the error), or a check not run. Omit
      when none.

   Leave out what the PR, its threads, and CI already show. That covers check
   names and counts, the review exchange, other SHAs, and head or audit lines.
   It also covers the worktree path, branch cleanup, the decision note, the
   fresh-session reminder for review rounds, and "I left it unmerged."
   Leave merging, branch cleanup, and `main` resync to the approver.

   Three platform gates apply:

   - **Last message.** Where the platform can end a turn on background work,
     such as a review watch, the report must still be the last message the
     owner sees.
   - **Recap box.** Where the platform shows one, its recap is Status and
     Result compressed to two sentences. Its question is a pending "Your call"
     or "Left for you" item, or nothing.
   - **Task cards.** Where the platform offers task or session cards, propose
     one only for a "Left for you" item that is a task of its own.

   Once the approver approves the PR to land, stop pushing to it unless you
   are the landing batch, which records each push it makes, or the user asked
   you to merge it directly (§merge-and-resync step 1). A landing batch
   merges the head the approval covered, and a push it didn't record keeps the
   PR from landing until the approver approves again. Freeze the PR too when
   the approver only says it's approved, even though only the landing
   record's signal makes it ready to land. Turn off any auto-fix, CI repair,
   or review watch the platform runs for the PR, where the platform offers
   that control. Without that control, tell the approver which automation
   still runs.

## merge-and-resync

Run this procedure only when the user asks you to merge.

1. **Check that the forge will accept the merge.** On GitHub, run:

   ```sh
   gh pr view <n> --json mergeStateStatus --jq .mergeStateStatus
   ```

   `BEHIND` means the up-to-date rule refuses the merge until the branch
   contains the tip. `DIRTY` means the branch conflicts with the tip. In
   either case, refresh from the tip and push as §handing-off step 3
   describes, and wait for the required checks as its step 4 describes. If
   the rebase conflicted, report what the resolution changed and wait for the
   user to confirm it: they asked to merge the PR they saw, not your
   resolution. Then repeat this step. `UNKNOWN` means the forge is still
   computing the state; run the command again. Any other state continues to
   step 2.

   A direct merge request makes you the lander for this PR, so the freeze at
   the end of §handing-off step 7 doesn't stop this refresh.

2. **Create a real merge commit.** On GitHub, run:

   ```sh
   gh pr merge <n> --merge
   ```

   If title-only merge-message settings aren't confirmed, pass the message
   explicitly:

   ```sh
   gh pr merge <n> --merge --subject '<PR title> (#<n>)' --body ''
   ```

3. **Choose the checkout that owns the base branch.** If the feature branch
   uses a worktree, resync `main` in the primary checkout. A second worktree
   can't check out a branch already used by the first.

4. **Fetch before landing on the base branch.** Run:

   ```sh
   git fetch <remote> refs/heads/main
   ```

   If local `main` exists, confirm with:

   ```sh
   git show-ref --verify --quiet refs/heads/main
   ```

   Then land with:

   ```sh
   git checkout --no-overwrite-ignore main
   ```

   If local `main` doesn't exist, create it from the fetch:

   ```sh
   git checkout --no-overwrite-ignore --no-track -b main FETCH_HEAD
   ```

   Do not use a bare checkout for this case. A same-named tag could leave
   `HEAD` detached.

5. **Validate the remote after landing.** Resolve the base remote again under
   the configuration now in effect. Confirm its URL still points to the merged
   PR's base repository.

   If cleanup created local `main`, set its tracking configuration from this
   newly resolved remote:

   ```sh
   git config branch.main.remote <remote>
   git config branch.main.merge refs/heads/main
   ```

   Do not keep a pre-landing upstream or leave the new branch untracked.

6. **Fetch into the remote-tracking branch and fast-forward.** Run:

   ```sh
   git fetch <remote> refs/heads/main:refs/remotes/<remote>/main
   git merge --ff-only --no-overwrite-ignore refs/remotes/<remote>/main
   ```

   Do not replace this with `git checkout main && git pull --ff-only`. A plain
   checkout or pull can overwrite an ignored file that the base now tracks.
   Pull also can't pass `--no-overwrite-ignore`. In a fork, a bare pull may
   follow the fork's stale copy instead of the base repository.

7. **Remove a feature worktree safely.** From the primary checkout, run:

   ```sh
   git worktree remove <path>
   ```

   Never run this while standing inside the worktree being removed. Git can
   unlink the current directory and still exit successfully, breaking every
   later command.

8. **Clean up branches and refs.** Delete the remote feature branch if the
   forge didn't auto-delete it. Delete the local branch with
   `git branch -d <branch>`. Finish with `git fetch --prune`.

## stacked-prs

Use a stacked PR when dependent work must proceed before its base PR merges.
Declare the dependency explicitly:

- Name the open PR's branch as the base when creating the new branch or
  worktree. Never inherit a base from the current checkout.
- On GitHub, create the PR with `gh pr create --base <feature-branch>`.
  GitHub retargets it to `main` after the base merges. Other forges may need
  manual retargeting.
- While the base is open, expect the stacked PR diff to show only the stack's
  own commits.
- If the base is force-pushed while review fixes are folded, use
  `rebase --onto` to move the stack to the new base tip.

## reviewing-a-pr

Use the review bar you expect others to use on your work. Use the project's
review tooling for bug hunting where the project has any. Otherwise, read the
full diff yourself.

- **Tag severity.** Blocking findings include correctness, security, data
  loss, red tests or CI, and broken invariants. Naming, style, and optional
  simplification are non-blocking. Only blockers prevent merge.
- **Reject invented problems.** Do not manufacture speculative or contrived
  findings. The author should decline them with a one-line reason.
- **Give evidence and a concrete ask.** Point to `file:line`, explain the
  failure, and propose a fix or ask a question. Label uncertainty as
  "possible:" instead of stating it as fact.
- **Review the intended outcome.** Read Why, What, and linked decision notes.
  Check that the change does what it claims, Verification is accurate, and
  docs and tests changed with behavior.
- **Respect recorded decisions.** They are evidence, not unchangeable rules.
  Do not silently reverse an owner decision. If the change conflicts with one,
  name the decision and explain which assumption or condition changed.
- **Stay in scope.** Treat unrelated improvements as non-blocking notes or
  follow-up issues. Do not expand the PR during review.
- **Match depth to risk.** Give routine work a normal pass. Use refute-first
  for work on a destructive path, credential-leak surface, or returned-object
  trust boundary. A docs typo doesn't need that pass.
- **Resolve the outcome, not every thread.** Say what would unblock the PR and
  let the author fix or decline it. Agreement on blockers is the gate.

## review-convergence

Use severity, not the mere existence of valid feedback, to decide whether
another review round is required.

- **Continue for every blocker.** Correctness, security, data loss, broken
  invariants, and red CI always earn another round. Decide severity yourself.
  The reviewer's tag is evidence, not the verdict. When a reachable defect's
  severity is unsure, treat it as blocking.
- **Test reachability before adding a guard.** A finding that asks for a guard
  or other behavioral change is real only when you can name what produces the
  failing state. Name an input the interface admits at a public or untrusted
  boundary, or an existing caller for internal code. The harm must also matter
  at the expected scale and trust boundary. A guard for a state you cannot
  reach is hardening, not a fix. Decline it with a one-line reason naming the
  unreachable path, the invariant that holds, or why the harm is immaterial.
  When reachability is unsure, trace the callers or run the case before
  patching.
- **Handle later non-blockers without another full review.** After the
  early rounds, choose one outcome for each valid non-blocker:

  - Fix it in one final push when you can verify the fix before pushing.
  - Defer real work to an issue that quotes the finding.
  - Decline it with a one-line reason.

- **Handle every finding from a review round you already needed.** If a
  blocker requires another round, also fix, defer, or decline that round's
  non-blockers. Do not carry them silently or force a weak fix.
- **Keep going while blockers still arrive.** A repeated finding caused by
  your incomplete fix means the fix was incomplete. Sweep the whole class.
- **Stop when review stops making progress.** This happens when the same
  finding returns after a correct, complete fix, or fixes create new problems
  without net progress. Pause and show the human what is stuck.
- **Notice when the reviewer is reviewing your hardening.** From the third fix
  round, check two signals: most findings cite lines an earlier round added,
  and recent fixes are all guards you traced no reaching caller for. When both
  hold, stop pushing guards. Decline only what fails that test, list earlier
  hardening that fails it as removal candidates, and show the human. Keep
  fixing reachable, material defects; the round count alone never turns one
  into a decline.
- **Judge a posted review; don't treat it as proof that work remains.** A
  reviewer that posts only on findings has a floor on new code.
- **Reassess after many rounds with blockers.** Record whether to continue or
  ask a human. A go needs blockers that passed the reachability and
  materiality test, not only shrinking counts. Revisit that decision if
  blocker rounds keep accumulating. Do not stop silently or continue on
  autopilot.
- **Record an outcome for every finding.** Before handoff, mark each one fixed,
  declined, deferred, or explicitly outstanding. Record why no blocker
  required another round. The human decides how to handle outstanding
  non-blockers at merge.
- **Test this full set of parser or validator cases once.** Test case, spacing,
  indentation, prefix and suffix, order, duplication, and nesting. Do not keep
  widening one cited pattern across review rounds.

## pre-push-review

Seek fresh eyes before pushing risky work, or any work in a repository without
an external bot reviewer. Risky work touches a destructive path, a
credential-leak surface, or a returned-object trust boundary, changes a
contract or public interface, or changes behavior without tests. A large
mechanical change (a rename, move, format, or generated update) that does
none of those relies on CI and the recorded bot reviewer, or the human
reviewer when there is none, however many files it touches.

- When the platform supports delegation and session policy permits it, ask a
  reviewer in a fresh session to look for reasons the change may be wrong. Give
  that reviewer only the diff and the PR's intended outcome, not your reasoning
  trail. Ask them to find correctness, security, and edge-case failures.
- When delegation is unavailable or needs permission you don't have, skip it
  and rely on the external bot or human. You may ask the user first.
- A same-model delegate is only partly independent and costs tokens. Match the
  review effort to risk.

Never write a step that assumes the running platform can delegate.

## reviewer-record

Record an automated reviewer only after observing its review on a recent PR, or
its status signal.
Put the record in an unmanaged, project-specific AGENTS.md section, outside
`agents-md:managed:*` blocks.

Include enough information to match future activity:

- Reviewer name.
- Login or account identity, including an API-specific form such as a
  `[bot]` suffix.
- Trigger, such as PR events, a manual command, or a CI job.
- Observed status signals, such as in-progress or clean-pass reactions.

Some reviewers post nothing on a clean pass. Their clean-pass signal lets a
future watch finish instead of timing out. Later sessions also filter activity
by login, so a bare statement that a reviewer exists isn't enough.

Treat a reaction as a reviewer status signal only after it recurs in that role
across PRs.

Update an existing record when you observe a missing status signal or changed
trigger. Record only what you observed. Never record an absence as a signal.
The owner's `none` record below is the one recorded absence.

A project's owner may instead decide that it has no automated reviewer. Record
that decision as a reviewer record whose reviewer is `none`:

```markdown
- **Expect no automated reviewer.** This project has the following reviewer
  record:

  - **Reviewer:** `none`, an owner decision. Only the owner changes it.
```

Only the owner writes, replaces, or removes this record. Never infer it from
silence, a quiet PR, or a reviewer that stopped posting. A landing record's
`Reviewer: none` alone isn't this record: it also covers a project whose
reviewer isn't recorded yet.

A `none` record differs from having no record:

- **No record:** detect a reviewer, watch for it, and record it once observed.
- **A `none` record:** start no review watch and don't scan past PRs for a
  reviewer. Don't record a reviewer seen on older PRs or a manual run; tell
  the owner instead. The human reviewer reviews at handoff.

## pr-body

Use the sections scaffolded by the PR template, in this order: Why, Scope,
What, Departures, Screenshots, Review Notes, and Verification. Use bold lead
words inside bullets and no sub-headings. Aim for 150 to 300 words outside
Screenshots in a typical PR. A longer What is the expected reason to exceed
that. When a body passes 400 words and the extra words sit elsewhere, say why
in Review Notes.

- **Why:** Write one to three short sentences about the problem or motivation.
  Link a decision note instead of repeating it. Follow the template's close
  keyword instructions exactly. Use a close keyword for each fully resolved
  issue. Use plain `Refs #N` for related work a human must close.
- **Scope:** Write one line naming the areas touched, such as
  `Scope: api/, daemon/` or `Scope: skills/agent-setup, scripts/`. Include it
  in every project. It is the reader's fastest size signal, and a project's
  CI may read it.
- **What:** Write one outcome bullet per change, in behavior terms: what a
  user, agent, or caller can now do or see. When the issue has numbered
  acceptance criteria, write one bullet per criterion in the issue's order, so
  the reviewer can check them off. Add a change bullet only for an outcome no
  criterion covers. The list has no cap and sizes itself to the
  issue. About 25 words is the shape of a bullet, not a limit. Don't list
  files or map commits here. Point to the decision note for rejected options.
- **Departures:** Always include this section. Write up to three bullets, or
  the single word "None". Each bullet names a change from the issue, plan, or
  contract and why; an addition beyond it; or a criterion left unmet or work
  left undone, with the issue that tracks it.
- **Screenshots:** Keep this section only for visible UI work. Before handoff
  and merge, replace it with forge-hosted images or recordings a reviewer can
  see. Local paths, text descriptions, and "checked locally" don't qualify.

  Show changed surfaces, important states, and every affected theme or
  appearance. Use short captions that name each state. Keep test results in
  Verification.

  To host them, upload or attach each image to the forge. First check the
  installed skills for a screenshot-evidence skill, such as `visual-evidence`,
  and use it, including for images that already exist. Check as §handing-off
  step 1 describes, even when you recall none.

  Without one, review each image first, and don't upload one that shows a
  secret, personal data, or an internal host or URL. On GitHub with gh 2.99.0
  or newer, write each image into the body as a Markdown image with its local
  path, then upload it with `gh pr create --attach` or `gh pr edit --attach`.
  Attach each file once: gh uploads it again on every run. On another forge,
  use its own attachment upload when the session can reach it.

  After an upload, the hosted URLs exist only in the live body. The local
  draft still holds local paths, so start any later body edit from the live
  body.

  If you can't attach the images, say at handoff what you tried and the error
  it gave, then ask the user to add or confirm them.

- **Review Notes:** Delete this optional section when it has nothing to add.
  Otherwise, write up to three bullets. Each names a place to look, such as a
  file to read first, a mechanical commit to skip, or a risky edge. Or it
  names a call the reviewer must make, such as an assumption to veto or a
  criterion to judge. Keep review rounds, folded findings, coordination, and
  merge-order notes in the threads and on the issue. Add a commit map only for four or more commits
  or a mechanical commit to skip. Key it by subject, not SHA, because folded
  fixes rewrite SHAs.
- **Verification:** Write up to five bullets beginning with `Passed:`,
  `Checked:`, `Attempted:`, or `Not run:`. List only what CI doesn't show:
  change-specific checks with counts as deltas, such as "82 to 86 cases";
  manual or device checks; UI fixture or screenshot checks for every affected
  theme; and schema round-trips. Add one `Not run:` bullet per check the
  change needs and couldn't get, never for suites of untouched components.
  When CI shows everything, write the single bullet `Passed: required checks.`

  Use facts, never "should work". Verify factual documentation claims against
  the code. Scope counts, flags, behaviors, and runtime guarantees precisely.
  Avoid marketing and competitor put-downs.

Leave these out of the body:

- The inventory of standard checks CI already runs, such as lint, format, and
  tests.
- A merge-result audit line, base-commit bullets, and 40-character SHAs. A
  green required check carries them.
- Review-round narration, coordination, and merge-order text. The threads and
  the issue carry them.
- A commit map for one to three commits, unless one is a mechanical commit to
  skip. The forge already shows the commits.

## refute-first

Use this pass only for work on:

- A destructive path, such as delete or cleanup.
- A credential-leak surface.
- A returned-object trust boundary, where code trusts fields returned by an
  external call or deserializer.

Before committing, use independent reviewers or checks that each try to prove
the change wrong. Record each finding as confirmed, disproved by a check, or
allowed by an explicit decision. Use the work unit's decision note when the
project keeps one; otherwise use the PR or issue. Recording findings that a
check disproved prevents the same claim from returning.

For a behavior-preserving refactor in one of these risk areas, compare the old
and new implementations when the platform can run code:

1. Reconstruct the old file with `git show <base>:<file>`.
2. Run old and new behavior over the same large set of generated inputs.
3. Compare every decision and result.

A diff can only suggest equivalence; the comparison test measures it. Do not
run this extra pass for a docs typo or a refactor outside the listed risk
classes.
````

---

## §tracker-format

Target: `docs/tracker-format.md` (only for a project that uses tracker
issues: a wave, feature, or backlog tracker that lists work units)

Content: `references/tracker-format.md`, copied whole. It is not inlined here
because its body template nests a Mermaid fence inside a Markdown fence.

The copy is verbatim, not a pointer back to this skill, for the same reason
`docs/agent-workflow.md` is. The agents that plan waves and work units and run
merge cleanup in that project read the format from the repository, on any
platform, without this skill installed. Wherever the project's AGENTS.md
describes tracker issues, cite `docs/tracker-format.md` for their shape rather
than restating it, and cite the same file from the project's post-merge
obligations record as the mechanics for tracker refresh.
