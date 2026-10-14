# Tracker Refresh Command

Chose a read-only bash command, `skills/merge-cleanup/tracker-refresh.sh`,
that computes the merge-time refresh of `tracker-format.md` §refresh from
each unit issue's state and Dependencies field. Merge cleanup runs it and
does the write. Issue #294 carries the contract; the parallel-work proposal
(#291, `docs/proposals/parallel-work-design.md` §2.5) asked for it.

## Decisions

- **Agent-run, not workflow-run.** The owner decided this on 2026-10-14
  (proposal §7, decision 4). How a unit closed and whether an edge changed
  mid-wave are judgment calls, so the session that merged runs it.
- **The command computes and never writes.** The reconciliation protocol
  already rereads every input before a tracker write and verifies after it.
  A command that also wrote would overwrite the whole body outside that
  ledger. Stdout is the body exactly, so a write of it reads back the same;
  the stderr line begins `OK unchanged` or `OK changed`. Merge cleanup uses
  that word for its `noop` and `verify` evidence, not a byte diff, because
  `gh --jq .body` adds a newline the body doesn't have.
- **Bash and `awk` over the proposal's 33-line Python prototype.** Every
  shipped tool here is bash or `.mjs`, the skill already requires `awk`, and
  the structure check's flag parity covers only those languages. The script
  stays bash 3.2 and BWK `awk` compatible for macOS.
- **The Dependencies field, not the drawn edges, gates a start.** This
  supersedes the proposal's §2.5 sentence "It trusts the edges as drawn".
  The tracker format already calls the field the authority and the chart a
  derived transitive reduction. Only `starts-after` gates a start;
  `merges-after`, `stacked-on`, and `exclusive-with` don't.
- **Closed as not planned isn't merged.** Merged means closed with state
  reason `COMPLETED`. 4 of Freeside's last 100 closed issues closed as not
  planned. `tracker-format.md` §refresh now says so in one sentence.
- **Never remove a tick or a double border.** One that issue state doesn't
  support stays, and the stderr line reports it. Removing it would hide a
  disagreement the owner should see.
- **Refuse rather than guess.** A closed tracker, a comment on another issue,
  or text missing `## Status`, `## Units`, the chart, or the
  **Startable now** bullet exits 2. So do a unit with no standalone node
  line, an off-format unit line, and an unparsable `class` line, since a
  unit drawn another way could carry a fence the command would miss. An
  ambiguous node, an open unit with no Dependencies field, or a field the
  grammar can't read exits 4 and names the unit.
- **Fail closed on the Dependencies grammar.** A refute-first review found
  that a lenient reader dropped prerequisites: `#10 or #11`, a bare second
  reference, a continuation line, a numbered list, and a `starts-after`
  after another relation each made a waiting unit startable. A wrongly
  startable unit lets two sessions collide, while a stop costs one look. So
  an entry is a relation followed by references joined only by `,` or `and`,
  and anything else stops. Prose may name `starts-after` only to say which
  issues wait on this unit. A bare `none` line that opens the field declares
  no dependency, and the notes after it may explain; an entry-shaped line
  after it stops.
- **Declined review findings, all erring safe.** A cosmetic rewrite of a
  startable line reports `changed` once. A bold lead that mixes
  `exclusive-with` prose with `starts-after` stops. A null state reason
  counts as not merged. Each costs at most one manual look and never a wrong
  start.

## Findings From the Live Trackers

A read-only run against Freeside's trackers changed four rules:

- **Dependencies sections mix entries and prose.** #2018 carries
  "Reverse: #2020 and #2024 declare `starts-after` #2018", and other units
  add `Refs` and "Not dependencies, but" lines. Scanning the section for
  relation keywords would make #2018 wait on itself. So a line that begins
  with `starts-after`, or a list item, is an entry and must parse; other
  prose is a note, and may name `starts-after` only for such a reverse
  statement.
- **A closed unit's Dependencies field is stale history.** #1421, already
  merged, still lists an `exclusive-with` entry in old prose. Only an open
  unit can be startable, so the command reads only open units' fields.

- **A note after an entry can add a prerequisite.** #1934's field reads
  `starts-after: #1938.`, then a note: "Owner revision 2026-10-10, second:
  also starts-after #1936". The first reader ended the entry at the period
  and dropped #1936, as Codex found on the PR. So a note after a colon or
  period, and a `Fence:` line, follow the same reverse-only rule as other
  prose.
- **An explicit `none` comes with explanation.** #2019's field reads `none`,
  then notes that name `starts-after` to say the unit lost its prerequisites.
  The fail-closed reader first stopped on it, which led to the `none` rule
  above.

After those changes, #2021 and #1616 came back `OK unchanged`, and #2021
matched its fresh hand refresh byte for byte. The 2026-10-10 exit-set
comment on issue #1613 stops on #1934's note, the fail-closed result, until
that field states #1936 as an entry. The older remediation comment on #1613 has no
**Startable now** bullet, so the command stops on it; the format requires
that bullet.

Revisit when Freeside's daemon reads dependency data to work out what can
start (plan §5.18, wave 11): the command's Dependencies grammar should then
follow the daemon's reader instead of its own.
