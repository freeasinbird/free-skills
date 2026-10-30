# Keep Owner-Run Units Out of the Startable Set

Chose to make a unit in class `owner` never startable, in both the tracker
format and `tracker-refresh.sh`, over leaving the exclusion to each project.
[Issue #364](https://github.com/freeasinbird/free-skills/issues/364) carries
the contract and implementation plan.

The format's template already left its owner-run unit out of **Startable
now**, but its prose gave `startable` to every open, unfenced unit with merged
prerequisites. The command followed the prose, so a merge cleanup on
freeside-ai/freeside#2386 had to filter stdout by hand before the write and
again before the verify. A project can't fix this locally: merge-cleanup leaves
project additions to agent judgment, and a cleanup that skips the filter writes
the wrong set.

- **Read the class, not the label or heading.** The command doesn't read the
  `needs-human` label or the `### Owner-run` heading, because the format
  already requires class `owner` on those units. A `### Owner-run` unit without
  the class counts as startable; that's a tracker error. A unit whose
  `needs-human` label comes off stays excluded until someone removes `owner`
  from the chart, which errs toward not listing work.
- **Keep `owner` units out of `left`.** Being owner-run is a unit's normal
  state, not something to repair. An `owner` unit with a held Dependencies
  field still appears there, because that field can be fixed. Like a fenced
  unit, it doesn't make the reason text say `held`.
- **Leave non-unit nodes alone.** The refresh already keeps a non-unit node's
  `startable` membership whatever its other classes are, because that node isn't
  this tracker's to refresh. An `owner` non-unit node gets the same treatment.
- **Build the reason from a list.** A third reason in the old nested chain
  would have doubled its branches. Every earlier reason string stays
  byte-for-byte the same, and `owner-run` sits after `held` and before
  `waits on`.

Revisit if a project needs an `owner` unit an agent may start, or if the owner
decides the rule should read the `needs-human` label.
