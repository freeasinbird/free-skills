# Request Sources

## §set-named-earlier

The request may point at a set instead of giving numbers, such as "plan and
handle those". Use the set only when the reference resolves to one list of
issue numbers already written in the thread. Keep that list's order. Never
search the forge to build the set, and never add to it or filter it.

Ask which issues are meant, and launch nothing until the owner answers, when:

- The reference could mean more than one list in the thread.
- The set is described by criteria, not numbers.

Examples:

- **Resolves.** A triage reply listed "#12, #9, #15", then the owner says
  "plan and handle those, two at a time". Run #12, #9, and #15 in that order.
- **Ambiguous.** The thread holds a triage list and a later shortlist, then
  "plan and handle those". Ask which list.
- **Criteria.** "Plan and handle the open bugs." Ask for the issue numbers.

## §tracker

The request may point at one tracker issue instead of listing issues, such as
"plan and handle the startable units on #835, three at a time". Treat an issue
as a tracker only when the request calls it one or asks for its units. The
batch is the tracker's startable units that no one is working on yet.

Resolve the set in three steps:

1. **Compute the startable units.** Where you have a shell, `gh`, `awk`, and
   `merge-cleanup` installed beside this skill, run its read-only
   `tracker-refresh.sh` with `--repo <host/owner/name>` and `--issue <N>`. Add
   `--comment <ID>` when the owner points at a tracker kept in a comment. The
   `startable now` part of its stderr `OK` line is the set, and its `left`
   part names held units. Where the script can't run, read the tracker's
   **Startable now** bullet, and say in the opening message that it may be
   stale.
2. **Drop units that can't start here.** A tracker keeps a unit startable
   until its PR merges, and the script doesn't check every condition. Leave
   out a unit that:
   - Is closed.
   - Belongs to another repository.
   - Is stacked on a PR that is neither open nor merged.
3. **Put the critical path first.** Units whose nodes a thick arrow (`==>`)
   joins in the tracker's diagram go first, then the rest. Keep the tracker's
   Units order within each group.

Every remaining unit gets a planner, including one that already has a plan.
Its planner's report still decides whether it dispatches.

Launch nothing, and say why, when:

- **The tracker isn't readable as one.** It is closed, isn't on the shared
  tracker format, or the script exits with a stop or a failed lookup. Report
  the script's error, and ask for issue numbers where the format is the
  problem.
- **Nothing remains.** Report the tracker's reason and each unit left out.
- **The source is unclear.** The request names a tracker without its number
  or link, names two trackers, or adds listed issues to one. Ask which set is
  meant.
