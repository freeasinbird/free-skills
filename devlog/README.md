# Decision notes

`devlog/` holds selective decision records, not session logs. Most
work leaves no note; AGENTS.md's Decision notes section defines when
one is warranted, this README defines the mechanics. The README and
AGENTS.md always hold current truth: if a note contradicts them, they
win; notes are the trail of how it got that way.

## Protocol

- **One file per note**, named `YYYY-MM-DD-HHMM-slug.md` using local
  24-hour time. Directory-of-notes (not a single file) so parallel
  branches and agent sessions add notes without merge conflicts, while
  same-day notes still sort in order.
- **At most one permanent note per work unit or PR** in the ordinary
  case. A note may evolve while its work unit or PR is active (in
  lockstep with branch rewrites; see fold-fix in AGENTS.md) and
  freezes when the PR merges; later corrections go in a new note,
  never edits to a frozen one.
- **Write for the future re-litigator**, not for someone following
  along. The decision sentence shape is "Chose X over Y because Z";
  name the decider when it isn't obvious (user choice, review finding,
  agent judgment). Record final rationale, rejected alternatives,
  changed assumptions, and verification findings that changed a
  decision or closed a risk; no chronology ("first tried..."), no
  commit diffs, no test transcripts, no PR status.
- **Add a "Revisit when ..." line** where a concrete condition would
  reopen the decision. It marks the decision's boundary, not open
  work: it needs no clock and no follow-up bookkeeping.
- **Actionable follow-ups live in the issue tracker.** When an issue
  originates from a note, link the note from the issue; the note may
  carry a plain `Follow-up: #N` historical link, but the issue, not
  the note, carries the status.

## Historical entries

Entries written under an earlier protocol (session bookends,
`## To promote` queues, `->` state markers) are frozen history: read
them as evidence when relevant, never mutate or reformat them, and
take no queue action from them; anything in one that is still
actionable belongs in the issue tracker.
