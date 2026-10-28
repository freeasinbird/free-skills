# Tracker Refresh Holds One Unit Instead of Stopping

Chose to hold an open unit whose Dependencies field can't be read, keeping it
out of the startable set while `tracker-refresh.sh` still prints the
refreshed tracker, over stopping the whole run with exit 4. Issue #354
carries the contract. This revises the "Fail closed on the Dependencies
grammar" decision in `2026-10-14-1502-tracker-refresh-command.md`, which
stopped the run on any field the grammar couldn't read.

## Why

On 2026-10-27, after a merge in freeside-ai/freeside, the refresh of
tracker #2346 exited 4 on #2336's `Blocker, not yet filed: …` line. That
line had no bearing on the merged unit's tick, its node, or any other unit's
start. Merge cleanup's "Make no write on a stop" then left the tracker
stale, and the earlier merge's refresh had most likely stopped on the same
line. One stale field blocked every later refresh of its tracker until the
planner rewrote it.

The 2026-10-14 decision wanted one thing: a waiting unit must never be
listed as startable, since that lets two sessions collide. A held unit is
never startable, so the hold keeps that guarantee. The run-wide stop added
only the cost of a missed tick, border, and startable update for every
other unit.

## Decisions

- **Every Dependencies failure on an open unit holds that unit.** That
  covers a line that doesn't parse, a missing field, an empty section, and
  `none` followed by an entry: exactly what exited 4 before. The stderr
  `left` list names each held unit and its reason, so the owner sees it.
- **A held unit names no prerequisite.** Its list may be incomplete, so the
  **Startable now** fallback says `held` instead of guessing what it waits
  on. A tracker with no held unit gets the same text as before.
- **A leading `Blocker` holds the unit as a stated field.** Freeside writes
  `Blocker, not yet filed: …` where a prerequisite isn't filed yet. A
  `Blocker` line that names a relation followed by a reference looks like a
  typed entry and is reported as unparseable instead; the unit is held
  either way. Other phrasings still fail to parse, which also holds.
- **Read failures still exit 4.** The tracker, any unit, and any
  prerequisite issue must be read; without a unit's state the command can't
  know what to tick, and it isn't told which unit just merged. An ambiguous
  node and a unit listed twice also still exit 4, and exit 2 is unchanged.
- **Merge cleanup writes on exit 0 and never on 2 or 4.** The hand refresh
  fallback now covers only a command that can't run at all, so it no longer
  reads as permission, or as a duty, after a stop.

## Refute-First Review

A fresh-context reviewer tried to make a waiting, unparseable, or blocked
unit startable and found no path through the hold. Its other findings:

- **Confirmed and fixed: a `Blocker` line later in a bold-lead paragraph
  was missed.** The joined paragraph was checked only at its start, so
  `**Dependencies.** starts-after #10.` followed by a `Blocker` line left
  the unit startable. Every line of the paragraph is now checked.
- **Confirmed and fixed: a held reason could forge the status line.** The
  reason quotes the issue body, so `; startable now #13` in a field read
  as a second startable set. A `;` in a reason now becomes `,`.
- **Allowed by decision: a prerequisite read before the hold can still exit 4.** In `starts-after #40 or #11`, #40 is read before the line fails to
  parse. Read failures exit 4 by the contract above.
- **Confirmed, not caused here: macOS `/bin/bash` 3.2 can't parse the
  script.** The same error is on `main`; the suite passed under a newer
  `bash` first on `PATH`. Follow-up: #355.
- **Confirmed, not caused here: only the first Dependencies heading
  counts.** A `none` section earlier in the body, even inside a code fence,
  hides a later entry. Follow-up: #356.

Revisit when Freeside's daemon reads dependency data to work out what can
start: a `Blocker` convention it defines should replace this command's
reading of the word.
