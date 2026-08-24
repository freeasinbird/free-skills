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
