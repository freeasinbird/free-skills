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

A climb improves an artifact one measured attempt at a time. The owner sets
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

- **State the cost.** Put council's runs per attempt in the budget before
  sign-off.
- **Screen first.** Screen each attempt with a program or with one
  fresh-context judge that hill-climb runs itself; council never seats a
  single member. Prove the screen like the check. An attempt passes the
  screen only when it beats the current best's screen score by more than the
  screen's noise. Only passing attempts, the final candidate, and the
  held-out cases go to the full panel.
- **Brief council by its Scoring Contract.** Pass a rubric, the goal file's
  reference examples, and the candidates. Keep the goal statement out of the
  brief, or pass it as the target, which council keeps from members.
- **Reduce to one score.** Council returns each member's scores and spread,
  never a pass or fail. Apply the goal file's score rule to get one number,
  then keep or revert by the rules below.

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

Before each attempt, verify the goal file's hash. A change pauses the climb
until the owner confirms it.

Each attempt tests one hypothesis. Write the hypothesis and the mechanism
that should make it work before changing anything. Then make the change,
score it from the frozen check, and run every guard. An attempt never edits
the check, its inputs, or a guard, and never skips a test.

- **Keep** the change only when it beats the current best by more than the
  noise band and every guard holds. A scored guard holds while it stays within
  its noise band of its baseline.
- **Revert** it fully otherwise, back to the last kept state. A gain within
  noise is a revert; so is any guard regression, whatever the score.

Log every attempt in the climb directory: its number, hypothesis, mechanism,
change, score, guard results, and whether it was kept or reverted.

## Check In When Stalled

A run of reverted attempts is a stall. Ask what is blocking progress: a
missing tool, a slow check, a subproblem too large for one attempt. Turn
each blocker into a proposal, either a tool to build or a separate climb with
its own goal file. Show the proposals to the owner and build or start nothing
until the owner approves it. Check in at the latest before a plateau stop.

## Ratchet

A next stage, such as "hold the score, cut the size", runs only when the goal
file declares it or the owner approves it. Each stage proves and freezes its
own check. The earlier stage's metric becomes a guard at its final score.

## Stop

Stop at the first of these:

- **Target reached.** The score meets the target, and the run has made the
  goal file's minimum number of attempts.
- **Plateau.** The goal file's count of reverted attempts in a row (default
  five), after the run has tried at least two kinds of change.
- **Budget spent.**
- **Check is wrong.** The frozen check's hash doesn't match, the goal file
  changed without the owner's confirmation, or an attempt shows the check
  rewards something other than the goal.

Never relax the target, even when asked mid-climb; a new target is a new goal
file and a new sign-off. Before keeping a suspiciously large jump, read its
diff for gaming of the check, such as special-casing test inputs; gaming is a
revert and a "check is wrong" exit. Score the held-out cases once, at the
end, never during the climb.

## Platform Gates

- **Parallel attempts** need two capabilities: delegation that starts
  parallel workers, and an isolated checkout per attempt, such as a worktree.
  Each parallel round starts from the current best, keeps at most its best
  attempt, and the next round starts from that. Without both capabilities,
  run one attempt at a time.
- **Unattended runs** need a way to keep working without the owner present,
  such as a scheduled or background run. At a stall, an unattended run logs
  its proposals, builds and starts nothing, and keeps trying other kinds of
  change until a stop. Without the capability, run attended and check in at
  each stall. Every run stops at the budget.
- **Fresh-context judges** need delegation that starts a fresh context.
  Without it, a judge-only check is unavailable; use a program or reference
  tier, or mark the goal not climbable.

## Deliver

After a "check is wrong" exit, open no PR: the kept attempts were scored by a
check that can't be trusted. Report the exit and the kept attempts for the
owner to judge.

After any other stop, shape the kept changes into commits by the project's
rules and open a PR through the project's flow. Never merge.

The report gives:

- **Scores.** Baseline to final, with the noise band.
- **Attempts.** How many were kept and how many reverted.
- **Log path.** The attempt log in the climb directory.
- **Held-out results.** Scored once, at the end.
- **Stop reason.** Which stop rule ended the climb.
- **Next idea.** The next hypothesis worth trying.
