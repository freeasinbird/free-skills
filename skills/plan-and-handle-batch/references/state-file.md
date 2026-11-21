# Batch State File

## §state-file

Keep one file in the session's temporary workspace, never in the project tree.
Write the ordered issue list and the window before anything launches, so a
later turn doesn't depend on the message that defined the set. Then update it
at every launch, every report, and every relayed question.

Record for the batch:

- The repository, the ordered issue list, the window, and model choices.
- The issues left out, with their reasons, and for a tracker its number.
- The implementer route, the tool that starts implementers, the route's
  reason, and the planner tool. On route 2, the reason names what route 1
  lacked.

Record for each issue:

- The planner's thread or agent link, and its status line.
- The branch from the planner's report.
- The implementer's thread or agent link, and its PR.
- Its state: planning, queued, running, waiting on owner, ready for review,
  blocked, not dispatched, ended without a report, or unknown.

## §resumed-session

On a resumed or condensed session, read the state file before anything else.
Then follow these rules:

- **No second implementer.** Never relaunch an implementer the file records
  as launched.
- **A planner only for an answer.** Relaunch a recorded planner only to carry
  the owner's answer to its question.
- **The recorded set stands.** Never resolve a tracker again. A unit that
  became startable since then waits for a later batch.
- **The recorded route stands.** Launch the remaining implementers on the
  recorded route, and start any planner through the recorded tool. Don't
  choose either again.
- **Unknown stays unknown.** If the platform can't tell you whether a
  recorded run is still going, report it as unknown rather than starting
  another.
