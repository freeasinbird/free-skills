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

   Prefer a review-watch skill, tool, or automation that reports back without
   manual polling. Otherwise, use a permitted background poll or scheduled
   wake-up when the platform supports it. Do not ask whether to watch.

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

3. **Validate against the current base.** Resolve the latest base tip. Update
   the PR branch with the project's merge or rebase method. Rerun relevant
   checks and self-review the refreshed full diff.

   Record the base commit in the PR's Verification section or in the handoff.
   If the base moves again before merge, the PR needs another integration
   pass. If you can't update the branch, report that it's stale. Do not
   rewrite a branch you don't own.

4. **Wait for required checks.** Poll until they finish. On GitHub, use
   `gh pr checks <n>`. Fix red checks on the branch. Never hand off a known-red
   PR.

5. **Self-review the full diff.** Apply the self-review rule under Pull
   requests so the change is ready for another reviewer.

6. **Close the review watch.** Check for both new review comments and CI.
   Address findings that belong to this PR, or record the bounded timeout or
   no-review result with its baseline.

   One exception applies when §review-convergence allows one last push for
   locally verified non-blockers. Do not wait for the re-review that push
   triggers. Record that push as the new baseline and say the human should
   check the final pass before merge.

7. **Stop and summarize.** State that the PR is open and green. Name anything
   the reviewer should inspect closely. Leave merging, branch cleanup, and
   `main` resync to the approver.

## merge-and-resync

Run this procedure only when the user asks you to merge.

1. **Create a real merge commit.** On GitHub, run:

   ```sh
   gh pr merge <n> --merge
   ```

   If title-only merge-message settings aren't confirmed, pass the message
   explicitly:

   ```sh
   gh pr merge <n> --merge --subject '<PR title> (#<n>)' --body ''
   ```

2. **Choose the checkout that owns the base branch.** If the feature branch
   uses a worktree, resync `main` in the primary checkout. A second worktree
   can't check out a branch already used by the first.

3. **Fetch before landing on the base branch.** Run:

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

4. **Validate the remote after landing.** Resolve the base remote again under
   the configuration now in effect. Confirm its URL still points to the merged
   PR's base repository.

   If cleanup created local `main`, set its tracking configuration from this
   newly resolved remote:

   ```sh
   git config branch.main.remote <remote>
   git config branch.main.merge refs/heads/main
   ```

   Do not keep a pre-landing upstream or leave the new branch untracked.

5. **Fetch into the remote-tracking branch and fast-forward.** Run:

   ```sh
   git fetch <remote> refs/heads/main:refs/remotes/<remote>/main
   git merge --ff-only --no-overwrite-ignore refs/remotes/<remote>/main
   ```

   Do not replace this with `git checkout main && git pull --ff-only`. A plain
   checkout or pull can overwrite an ignored file that the base now tracks.
   Pull also can't pass `--no-overwrite-ignore`. In a fork, a bare pull may
   follow the fork's stale copy instead of the base repository.

6. **Remove a feature worktree safely.** From the primary checkout, run:

   ```sh
   git worktree remove <path>
   ```

   Never run this while standing inside the worktree being removed. Git can
   unlink the current directory and still exit successfully, breaking every
   later command.

7. **Clean up branches and refs.** Delete the remote feature branch if the
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
  The reviewer's tag is evidence, not the verdict. When unsure, treat the
  finding as blocking.
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
- **Reassess after many rounds with blockers.** Record whether to continue or
  ask a human. Revisit that decision if blocker rounds keep accumulating. Do
  not stop silently or continue on autopilot.
- **Record an outcome for every finding.** Before handoff, mark each one fixed,
  declined, deferred, or explicitly outstanding. Record why no blocker
  required another round. The human decides how to handle outstanding
  non-blockers at merge.
- **Test this full set of parser or validator cases once.** Test case, spacing,
  indentation, prefix and suffix, order, duplication, and nesting. Do not keep
  widening one cited pattern across review rounds.

## pre-push-review

For non-trivial work, or any repository without an external bot reviewer, seek
fresh eyes before pushing.

- When the platform supports delegation and session policy permits it, ask a
  reviewer in a fresh session to look for reasons the change may be wrong. Give
  that reviewer only the diff and the PR's intended outcome, not your reasoning
  trail. Ask them to find correctness, security, and edge-case failures.
- When delegation is unavailable or needs permission you don't have, skip it
  and rely on the external bot or human. You may ask the user first.
- A same-model delegate is only partly independent and costs tokens. Match the
  review effort to risk, and skip this step for trivial or mechanical work.

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

## pr-body

Use the sections scaffolded by the PR template:

- **Why:** Write one to three short sentences about the problem or motivation.
  Link a decision note instead of repeating it. Follow the template's close
  keyword instructions exactly. Use a close keyword for each fully resolved
  issue. Use plain `Refs #N` for related work a human must close.
- **What:** Use outcome bullets, not a file list. For a multi-commit PR, add a
  compact map with one bullet per commit or concern. Refer to commits by
  subject, not SHA, because folded fixes rewrite SHAs. Point to the decision
  note for rejected options.
- **Screenshots:** Keep this section only for visible UI work. Before handoff
  and merge, replace it with forge-hosted images or recordings a reviewer can
  see. Local paths, text descriptions, and "checked locally" don't qualify.

  If you can't attach them, say so at handoff and ask the user to add or
  confirm them. Show changed surfaces, important states, and every affected
  theme or appearance. Use short captions that name each state. Keep test
  results in Verification.

- **Review Notes:** Delete this optional section when it adds no routing value.
  Otherwise, point to important files, review order, mechanical commits, or
  risky edges.
- **Verification:** Use required bullets beginning with `Passed:`, `Checked:`,
  `Attempted:`, or `Not run:`. State what ran and what happened. Include
  tests, lint, UI fixture or screenshot checks for every affected theme, and
  schema round-trips when relevant.

  Use facts, never "should work". Mark every gap as `Not run:`. Verify factual
  documentation claims against the code. Scope counts, flags, behaviors, and
  runtime guarantees precisely. Avoid marketing and competitor put-downs.

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
