---
name: hill-climb
description: >-
  Improve an artifact against a trustworthy score in a loop: agree a goal file
  with the owner, prove and freeze the check, try one hypothesis per attempt,
  keep only gains past noise with guards green, log every attempt, check in
  when stalled, and deliver the kept changes as a PR. Use when the user says
  "hill-climb X", "hillclimb", or "keep improving X until it scores Y", or asks
  to push a measurable score toward a target over many attempts. Not for a
  one-off council scoring request, an "improve X" edit with no score, a prompt
  audit or edit with no score (prompt-crafter), a single eval run, a reflect request, or
  "Plan #N".
---

# Hill-Climb

A climb improves an artifact one measured attempt or round at a time. The owner sets
the goal, the target, and the budget and keeps the merge. The climber proves
the check can be trusted, then tries changes, keeps what beats noise, and
reverts the rest.

Follow this procedure:

1. Intake: agree the goal file and get sign-off.
2. Choose the check.
3. Prove the check, then freeze it.
4. Run attempts.
5. Check in when stalled.
6. Ratchet to a declared next stage.
7. Stop.
8. Deliver.

## Intake

Draft the goal file from `references/goal-file.md` §goal-file. Propose a
durable climb directory outside the repository, such as
`~/.hill-climb/<repo>/<slug>/`, and let the owner name another. Session
scratch space isn't enough, because the report gives a log path that must
still exist. The goal file, the frozen check, and the attempt log all live
there.

Show the goal file to the owner. Start no attempt, and change nothing in the
repository, until the owner signs off. Then record the sign-off and the goal
file's hash in the attempt log. The owner controls the goal file; never edit
it after sign-off.

Before the first attempt, create a branch in an isolated checkout as the
project's rules require. Never climb on the default branch or in a checkout
that holds the owner's uncommitted work. Commit each kept attempt there; a
revert restores the last kept commit.

## Choose the Check

Use the first tier that fits the goal:

1. **A program.** A test suite, benchmark, linter count, or size measure.
   Programs don't drift.
2. **Comparison against a reference.** A diff or similarity measure against
   a known-good output.
3. **`council` in scoring mode.** Only at rung 1 or 2, where members run in
   fresh contexts. At rung 3 council returns no scores, so this tier isn't
   available.

A check only a human can run marks the goal "not climbable". Say so and stop.

For a council-scored climb:

- **State the cost.** Put council's runs per unit in the budget before
  sign-off.
- **Screen first.** Screen each candidate with a program or with one
  fresh-context judge that hill-climb runs itself; council never seats a
  single member. Prove the screen like the check. A candidate passes the
  screen only when it beats the current best's screen score by more than the
  screen's noise. For a set goal, a candidate passes when its screen score
  meets the acceptance rule or falls short by no more than the screen's
  noise. Only passing candidates, the final candidate, and the held-out cases
  go to the full panel.
- **Queue proposed candidates.** Council's Scoring Contract doesn't ask
  judges for candidates, so this applies only when a judge's output includes
  one. Queue it, and send it through the screen and the full panel like any
  other candidate. Ignore the score a judge gave its own proposal.
- **Brief council by its Scoring Contract.** Pass a rubric, the goal file's
  reference examples, and the candidates. Keep the goal statement out of the
  brief, or pass it as the target, which council keeps from members.
- **Reduce to one score.** Council returns each member's scores and spread,
  never a pass or fail. Apply the goal file's score rule to get one number,
  then keep, revert, accept, or reject by the rules below.
- **Rescore after a failed seat.** A council report scored a different panel
  than the proven check when it has a failed member, a lower rung than the
  goal file's check tier, or a panel other than the one that proved the check.
  Don't use it to keep, revert, accept, reject, prove the check, or score the
  held-out cases; rescore. Count replacement and rescore runs against the
  budget; when it can't cover a rescore, stop as budget spent with no decision
  on that unit. If the full panel can't be restored, pause the climb and check
  in with the owner, since the proven check can't run.

## Prove the Check

These are the rules for a trustworthy check. Other skills cite this section.

1. **Measure noise.** Rescore the unchanged baseline at least three times. A
   deterministic program needs one rerun that shows an identical score. The
   spread of these scores is the noise band.
2. **Separate good from bad.** Score a known-good and a known-bad case. The
   gap must exceed the noise band; if it doesn't, the check can't guide a
   climb. Report that and propose a better check. For council, these cases
   must differ from the reference examples it sees as anchors.
3. **Freeze the check.** Copy the check, and every file it reads that a
   candidate could change, into the climb directory, and record their hash.
   From then on the check doesn't change for this stage.
4. **Score where the climber can't write.** Score every candidate from the
   frozen copy, run against the candidate outside the working checkout. Verify
   the hash before each score; a mismatch is the "check is wrong" exit. Where
   the platform offers a read-only sandbox for scoring, use it.

## Run Attempts

Before each unit, verify the goal file's hash. A change pauses the climb
until the owner confirms it.

A climb counts in the goal file's unit. An attempt scores one candidate. A
round writes one hypothesis per candidate, scores the batch in one run of the
frozen check, and keeps at most its best candidate by the keep rule below.

Each candidate tests one hypothesis. Write the hypothesis and the mechanism
that should make it work before changing anything. Then make the change,
score it from the frozen check, and run every guard. A candidate never edits
the check, its inputs, or a guard, and never skips a test.

- **Keep** the change only when it beats the current best by more than the
  noise band and every guard holds. A scored guard holds while it stays within
  its noise band of its baseline.
- **Revert** it fully otherwise, back to the last kept state. A gain within
  noise is a revert; so is any guard regression, whatever the score.

For a set goal, accept each candidate that meets the goal file's acceptance
rule with every guard holding, and commit it as a kept attempt is committed.
Reject the rest. A rejection is not a revert and undoes nothing.

A unit makes **progress** when the best score rises by more than the noise
band. For a set goal, progress is a new accepted item, or a rise past noise
in the best near-miss: the best score the full check gave a rejected
candidate. Stalls and
the plateau count units without progress, never reverted or rejected
candidates.

Log every candidate in the climb directory: its unit, number, hypothesis,
mechanism, change, score, guard results, and outcome (kept, reverted,
accepted, or rejected). After each unit, log the best score, and for a set
goal the best near-miss.

## Check In When Stalled

A run of units without progress is a stall. A round with many rejected
candidates and a higher best score is not a stall. Ask what is blocking
progress: a missing tool, a slow check, a subproblem too large for one
attempt. Turn each blocker into a proposal, either a tool to build or a
separate climb with its own goal file. Show the proposals to the owner and
build or start nothing until the owner approves it.

Check in at the latest before a plateau stop. Show the best score for each
recent unit, the cost of one more unit, and the budget left, and offer one
more unit as a choice beside stopping. If the owner says yes, log the answer
in the attempt log and run one unit. Never edit the goal file for it, and
never go past the budget.

## Ratchet

A next stage, such as "hold the score, cut the size", runs only when the goal
file declares it or the owner approves it. Each stage proves and freezes its
own check. The earlier stage's metric becomes a guard at its final score.

## Stop

Stop at the first of these:

- **Target reached.** The score meets the target, or for a set goal the
  accepted count does, and the run has made the goal file's minimum number of
  units.
- **Plateau.** The goal file's count of units in a row without progress
  (default 5 for attempts, 3 for rounds), after the run has tried at least two
  kinds of change. It never fires while a queued proposed candidate waits to
  be scored.
- **Budget spent.** This stop fires even with proposed candidates still
  queued.
- **Check is wrong.** The frozen check's hash doesn't match, the goal file
  changed without the owner's confirmation, or an attempt shows the check
  rewards something other than the goal.

Never relax the target, even when asked mid-climb; a new target is a new goal
file and a new sign-off. Before keeping a suspiciously large jump, read its
diff for gaming of the check, such as special-casing test inputs; gaming is a
revert and a "check is wrong" exit. Score the held-out cases once, at the
end, never during the climb.

## Platform Gates

- **Parallel attempts** need delegation that starts parallel workers. When
  the candidates are edits made in parallel, each also needs an isolated
  checkout, such as a worktree. Each parallel round starts from the current
  best and, like any round, keeps at most its best candidate; the next round
  starts from that. Without the capabilities a round needs, make one
  candidate at a time, save each as a patch against the current best, and
  score the round together.
- **Unattended runs** need a way to keep working without the owner present,
  such as a scheduled or background run. At a stall, an unattended run logs
  its proposals, builds and starts nothing, and keeps trying other kinds of
  change until a stop. At a plateau it stops without asking and puts the
  check-in's three facts in its report: the best score for each recent unit,
  the cost of one more unit, and the budget left. Without the capability, run
  attended and check in at each stall. Every run stops at the budget.
- **Fresh-context judges** need delegation that starts a fresh context.
  Without it, a judge-only check is unavailable; use a program or reference
  tier, or mark the goal not climbable.

## Deliver

After a "check is wrong" exit, open no PR: the kept attempts were scored by a
check that can't be trusted. Report the exit and the kept attempts for the
owner to judge.

After any other stop, shape the kept changes, or a set goal's accepted
items, into commits by the project's
rules and open a PR through the project's flow. Never merge.

The report gives:

- **Scores.** Baseline to final, with the noise band.
- **Candidates.** How many were kept and how many reverted. For a set goal,
  how many were accepted and rejected, and the best near-miss.
- **Unscored proposals.** After a budget stop, any proposed candidates left
  in the queue.
- **Plateau facts.** After an unattended plateau stop, the best score for
  each recent unit, the cost of one more unit, and the budget left.
- **Log path.** The attempt log in the climb directory.
- **Held-out results.** Scored once, at the end.
- **Stop reason.** Which stop rule ended the climb.
- **Next idea.** The next hypothesis worth trying.
