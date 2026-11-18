# Take a Batch From a Tracker's Startable Units

`plan-and-handle-batch` now accepts one tracker issue as its batch source. The
owner asked to point the skill at a tracker and have it work on the startable
units. This revises one rule in the
[2026-11-18 batch note](2026-11-18-1019-plan-and-handle-batch.md): the skill
reads the forge to build the set, but only from a tracker the owner names. A
set named earlier in the thread still comes only from numbers already written
there.

## Decisions

- **Chose the shared format's startable rule over a new one.** The set is
  what `merge-cleanup`'s read-only `tracker-refresh.sh` computes from each
  unit's Dependencies field, the authority the shared tracker format names.
  Its **Startable now** bullet is the fallback where the script can't run,
  with a stated staleness caveat, because merge cleanup may not have
  refreshed it.
- **Chose filtering that set before planning.** The tracker keeps a unit
  startable until its PR merges, so the set includes work already under way.
  The script also doesn't apply Freeside's `stacked-on` condition, and it
  accepts units from other repositories. The skill leaves out closed units,
  units with an open PR or a live claim, units in another repository, and
  units stacked on a PR that is neither open nor merged.
- **Chose replanning every unit, an owner decision, over dispatching existing
  plans directly.** Every plan is then grounded on the current default branch.
  The cost is one planner run per unit and a replaced plan where one existed.
- **Chose critical path first, an owner decision, over the Units order
  alone.** Units order groups by lane, which isn't a priority. Critical-path
  units gate the most later work, so they reach review first when the window
  is smaller than the set.
- **Chose starting without confirmation over asking the owner to approve the
  resolved set.** The owner asked for the batch to "just work". The opening
  message lists the units and those left out, so a wrong set can still be
  stopped at once.
- **Chose not serializing overlapping units in the same batch.** Freeside's
  coordination policy retired `exclusive-with`: a pair that must be ordered
  gets a `starts-after`, and textual conflicts resolve at landing. An
  earlier chat suggestion to brief planners about batch siblings was
  withdrawn for that reason.
- **Chose not guarding against a second batch on the same tracker.** A
  running implementer that hasn't opened its PR leaves nothing another
  session can see, unless the project records claims. The claim record is the
  project's guard here, as it is for a hand-started `Handle #N`.

## Stacked Units

The same change has implementers branch a `stacked-on` unit from its open base
PR's branch and target its PR there. A tracker can count such a unit
startable, and the brief's old default-branch base would have dropped the code
it builds on.

Revisit when a live tracker batch shows replanning every unit costing more
than it saves, or when the shared tracker format changes its startable rule.
