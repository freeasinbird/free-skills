---
name: prepare-hill-climb
description: >-
  Prepare the check a climb will run on before hill-climb starts: choose the
  metric and target, build or gather the instrument (a program, a reference,
  or a council rubric), state the proving cost, prove the check separates
  good from bad past noise, freeze it, map what it can't see, and leave a
  draft goal file and a proof record that hill-climb can accept. Use when the
  user says "set up scoring for X", "build a scored eval for X", "how do we
  score X", "find comps for this design", or "set a performance target", or
  asks to make a goal measurable before climbing it. Not for running the
  climb itself ("hill-climb X", hill-climb), a one-off council scoring
  request (council), a single eval run, writing ordinary unit tests, or
  "Plan #N".
---

# Prepare Hill-Climb

This skill does the work before a climb. It settles what to measure, builds
the check, proves the check can be trusted, and hands `hill-climb` a draft
goal file and a proof record. The owner keeps the goal, the budget, and the
sign-off. This skill stops before the climb starts.

Follow this procedure:

1. Confirm `hill-climb` is installed beside this skill.
2. Choose the check tier.
3. Draft the goal file in the climb directory.
4. Build the check for its tier.
5. State the proving cost and wait for the owner's go-ahead.
6. Prove and freeze the check.
7. Map the blind spots.
8. Write the proof record.
9. Report and stop.

## Use hill-climb's Rules

This skill cites `hill-climb` and doesn't copy it. The goal file's fields
live in `../hill-climb/references/goal-file.md` §goal-file. The proving
rules live in the Prove the Check section of `../hill-climb/SKILL.md`, and
the tier order in its Choose the Check section. Read both before step 2.

When `hill-climb` isn't installed beside this skill, say so and stop. The
goal file and the proof both follow rules this skill doesn't carry, so
neither can be built correctly without them.

## Choose the Tier

Use the first tier that fits the goal, in `hill-climb`'s order:

1. **A program.** A test suite, benchmark, size measure, or scored eval.
2. **A reference.** A measured comparison against known-good examples.
3. **A rubric scored by `council`.** Only at rung 1 or 2.

A check only a human can run marks the goal "not climbable". Say so, write
no files, and stop. Don't invent a proxy score to fill the gap.

## Draft the Goal File

Propose a durable climb directory outside the repository, as `hill-climb`'s
Intake does, such as `~/.hill-climb/<repo>/<slug>/`. Let the owner name
another. Session scratch space isn't enough: the climb reads these files
later.

Draft the goal file there from `../hill-climb/references/goal-file.md`
§goal-file. Fill the goal, metric, better direction, target, check, check
tier, and the known-good, known-bad, and held-out cases. For a council
check, also fill the score rule, screen, and reference examples.

- **Target.** Give its basis in the proof record: a pilot's ratio, a
  benchmark, a service level, or the owner's own number. A target with no
  basis is a guess; label it one and leave the choice to the owner.
- **Guards.** List each guard with its baseline result, and mark it cheap or
  expensive relative to one score. A lint or structure check is cheap; a
  second scored eval is expensive. `hill-climb` runs the cheap ones before
  scoring a candidate.
- **Constraints.** Quote each limit the owner stated. Add each blind spot
  that should bind candidates as a climber-added limit whose source is the
  proof record and its entry.
- **Owner fields.** Leave the unit, budget, stop rule, plateau, and ratchet
  stages blank for the owner. A blank field needs the owner's answer before
  sign-off.

## Build the Check

Build the check for the chosen tier. Keep everything the check reads in
files a candidate can't change once the check is frozen. If the check's
source files belong in the repository, deliver them through the project's
own flow. The climb must start from a revision that holds them unchanged.

### Program Tier

A program prints one number that moves in one direction as the goal
improves.

- **Metric.** Name the number, its unit, and the better direction.
- **Measurement setup.** Write one command that prints the number and runs
  outside the working checkout.
- **Environment.** Pin what moves the number without the artifact changing:
  tool and runtime versions, hardware, input data, and background load.
  Record each pin in the proof record.
- **Baseline.** Measure the artifact at a named revision, repeatedly, from
  the frozen copy.
- **Target.** Set it from its basis, and say how far it sits from the
  baseline in noise bands.

For a scored eval of an agent skill, follow
`references/scored-eval.md` §scored-eval. Two size climbs have run on such
an eval, so those steps are piloted.

**Not yet piloted: performance measurement.** No climb behind this skill
has measured time, memory, or throughput yet. Treat the program steps above
as a starting point for those metrics, say so to the owner, and record what
the first such climb learns.

### Reference Tier

**Not yet piloted.** No climb behind this skill has used a reference check.
These steps are a starting point; say so to the owner.

- **Find comps.** Take them from the owner, the project's design system, or
  prior art the owner names. Ask before adding one the owner hasn't seen.
- **Assess each comp.** Keep a comp only when it fits the artifact's
  platform and purpose and the project may use it as a reference.
- **Define "closer".** Pick a measure a program can compute, such as a
  pixel or structural diff, or a layout metric. When closeness needs
  judgment, the check belongs to the rubric tier instead.
- **Hold comps out.** Keep at least one comp out of the climb for the
  held-out score.

### Rubric Tier

**Not yet piloted.** No climb behind this skill has used a council rubric.
These steps are a starting point; say so to the owner.

- **Write the rubric.** Give each criterion a scale and say what each end
  of the scale looks like.
- **Choose anchors.** Pick reference examples for the scale's ends.
- **Keep cases apart from anchors.** The known-good and known-bad cases,
  and the held-out cases, must differ from every anchor. A judge that has
  seen a case as an anchor recognizes it.
- **Propose a screen.** Name the program or single fresh-context judge
  that will screen candidates, and prove it like the check.
- **Record the panel.** Let council pick its default panel for the first
  proving run, then name that panel on every later proving run. Record each
  member's provider, model, and effort.

## State the Cost

Before any proving run, estimate its cost in money and time. Count the
noise rescores, the known-good and known-bad scores, any variants that map
coverage, and the held-out baseline. Show the estimate to the owner and wait
for a go-ahead. Spend nothing on proving runs before it.

## Prove and Freeze

Apply steps 1 to 3 of `hill-climb`'s Prove the Check to the baseline: noise,
the good-versus-bad gap, then the freeze. Before the first proving run,
rename any proof record already in the climb directory to
`proof-record.superseded.md`, so a failed re-proof can't leave an old
record standing. Then use this order:

1. Finish every edit to every file the check reads, including any README
   inside a hashed directory.
2. Freeze: copy the check into the climb directory and record the hash.
3. Take every recorded score from the frozen copy: the noise band, the
   baseline, the known-good and known-bad scores, and the held-out baseline.

Scores taken before the last edit to a hashed file don't count. After such
an edit, freeze again and rescore.

When the gap doesn't exceed the noise band, the check can't guide a climb.
Report the scores, propose a better check, and write no proof record.

## Map the Blind Spots

List what the check can't see, each with its evidence:

- **Uncovered rules.** A rule no case fails without, as a coverage map
  finds.
- **Silent removals.** A section or behavior whose removal didn't move the
  score past noise.
- **Rebuilt behavior.** Behavior the agent or tool rebuilds from elsewhere,
  so the score holds when the artifact loses it.
- **Unmeasured qualities.** Anything the metric doesn't sample, such as a
  platform, a model, or an input the cases never use.

For each blind spot that should bind candidates, propose a Constraint in
the draft goal file, with the proof record as its source. For the rest,
say how the climb should cover them, such as an adversarial review of the
final diff.

## Write the Proof Record

Write `proof-record.md` in the climb directory from
`references/proof-record.md` §proof-record. Fill every field the check's
tier uses. `hill-climb` reads this file to decide whether it may skip
proving the check itself.

## Report and Stop

Report:

- **Paths.** The climb directory, the draft goal file, the frozen check, and
  the proof record.
- **Scores.** The baseline, the noise band, and the known-good versus
  known-bad gap.
- **Cost.** Per score, and the total spent on proving.
- **Target basis.** Where the proposed target comes from.
- **Blind spots.** Each one, and which became proposed Constraints.
- **Owner fields.** The goal file's blanks the owner must fill.

Then stop. Never sign off a goal file, start an attempt, or change the
artifact under climb. The owner starts the climb with `hill-climb`, which
reads the draft goal file and the proof record.

## Platform Gates

- **Scored-eval runs** need a shell and an agent CLI that a runner can
  start in fresh, isolated sessions. Without them, use another program
  check, or report that the scored-eval tier is unavailable.
- **Council checks and single judges** need delegation that starts a fresh
  context. Without it, the rubric tier and judge screens are unavailable;
  use a program or reference check, or mark the goal not climbable.
- **`hill-climb` installed beside this skill** supplies the goal-file
  fields and the proving rules. Without it, say so and stop.
