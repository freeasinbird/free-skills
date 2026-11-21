# Dependencies Check

## §dependencies-check

After writing or changing a Dependencies field, check the persisted field
before posting the plan. This includes a partner issue's Dependencies field
when planning changed its coordination record. Check only fields planning
wrote or changed.

Run the project's documented check for the field first. Otherwise, use
merge-cleanup's bundled `tracker-refresh.sh` when the issue or project records
name a shared-format tracker that lists the unit. Do not search the forge for
trackers beyond those records. When neither check applies, there is nothing
to run or report.

The fallback requires a shell, an authenticated `gh`, and merge-cleanup
installed beside this skill. Run `../merge-cleanup/tracker-refresh.sh` relative
to this skill's directory (the directory holding `SKILL.md`) with
`--repo <host/owner/name> --issue <tracker>`.
Add `--comment <ID>` when the tracker is in a comment. The script only reads.
Discard its stdout; never write the refreshed text to the tracker, which is
outside the planning mutation surface.

The fallback reads only unit issue bodies. It cannot verify a Dependencies
field in a separate contract record. Report that field under **Not verified**
unless a project check covers that record.

On exit 0, inspect the stderr status line for each changed unit's
`<ref> held: <reason>`. A `Blocker line in Dependencies` hold is a stated field,
not a parse failure. Any other held reason for that unit is a parse failure.
Other units' holds do not reject this unit's field. Exit 2 or 4 means the
check could not complete, not that the field passed. Treat any other nonzero
exit as an unsuccessful check too.

Fix a rejected field to the project's shape, using typed entries or a bare
`none` as applicable. Move notes and planning subsections out of the
Dependencies section. Rerun the check after the write. If it still rejects
the field, or the required shape is unclear, report planning blocked with the
check's message. Do not post the plan or report finished while a field is
known to fail its check.

When an applicable check cannot run, name the field, the check, and the
missing capability or failed lookup under **Not verified**. This includes a
missing shell, `gh`, or sibling merge-cleanup installation for the fallback.
Never report an unchecked field as passing.
