# Prepare a Climb's Check in Its Own Skill

Issue #456 adds `prepare-hill-climb`, which builds and proves a climb's
check and leaves a draft goal file and a proof record in the climb
directory. `hill-climb` accepts the record in place of proving the check
itself when five conditions hold. Four "build a scored eval" issues
(#392, #439, #441, and #443) had each planned this work from scratch, and
the #440 climb's eval passed 27 of 27 runs after two rules were deleted
(#454).

## Decisions

- **Chose a separate skill over folding preparation into `hill-climb`.**
  The owner rejected folding in #456. The agent's reading of why: building
  a check is its own work unit with its own PR, often in a different
  session than the climb, and `hill-climb` is already long. A separate
  skill also triggers on "how do we score X" without loading the climb
  loop.
- **Kept the name `hill-climb` over renaming it `climb`.** The owner
  rejected the rename in #456. The agent's reading: the name is cited by
  other skills, issues, and decision notes, and a rename would churn all of
  them for no change in behavior.
- **Chose a proof record beside the goal file over new goal-file fields.**
  The goal file is the owner's signed-off statement, and its fields are an
  interface other skills use. The noise band, hash, cost, and blind spots
  are measured facts, not owner choices, and `hill-climb` already keeps them
  in the attempt log. A separate record carries them without changing the
  template.
- **Accept a proof record only when five conditions hold.** The frozen
  copy hashes to the recorded value. The check's source at the climb's
  starting commit hashes the same. Every path the score reads is unchanged
  since the baseline revision. The goal file runs the record's command
  with its settings, and its environment pins hold. For council, the first
  call names the recorded panel with no member unreachable. Each one closes
  a way a stale proof could pass: a tampered copy, a source edited after
  proving, a baseline that no longer describes the artifact, a different
  model or environment, or a different panel.
- **Added the settings condition beyond the issue's four.** The pre-push
  review found that the runner's hash covers no run setting, so a record
  proved on one model would pass every hash condition on another. The
  agent added the condition; it only makes acceptance stricter. On any miss,
  `hill-climb` names the condition and proves the check itself. Step 4,
  scoring from the frozen copy with the hash checked, applies either way.
- **Chose not to ship the runner.** `scripts/run-scored-eval.sh` drives
  Claude Code only and depends on this repository's layout. Bundling it
  would make a platform-specific tool look portable, against the
  platform-agnostic invariant. The skill states the method a runner must
  meet, names this one as fitting, and tells a project without one to port
  a runner, pick another program check, or report the tier unavailable.
- **Chose to keep proving results out of hashed files.** The runner's hash
  covers the eval's README. Writing results there after proving would make
  every proof fail the source condition. Results go in the proof record; a
  README edit comes before the freeze, and the recorded scores are then
  retaken from the frozen copy.
- **Marked unpiloted steps as such.** Performance measurement, the
  reference tier, and the rubric tier have no climb behind them, so the
  skill says so where each appears. Only the scored-eval steps rest on real
  climbs (#392, #393, #439, #440).

Revisit when the first performance, reference, or rubric climb runs, when
`run-scored-eval.sh` changes its hash coverage, or when the goal-file
template gains fields that overlap the proof record.
