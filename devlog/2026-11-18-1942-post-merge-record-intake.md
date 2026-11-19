# Gather the Post-Merge Record in agent-setup Intake

agent-setup now writes the `### Post-merge obligations` record that the
merge-cleanup skill needs before it refreshes a tracker. The template lives in
`skills/agent-setup/references/project-sections.md` §post-merge-record.
Issue #271 carries the contract. This follows
`devlog/2026-09-25-0956-tracker-format-scaffold.md`, which scaffolded
`docs/tracker-format.md` but left the record that cites it unwritten.

## Decisions

- **Chose to write the record in init over only reporting its absence.**
  Without a record, merge-cleanup treats absence as its safe default and
  refreshes no tracker. A setup that scaffolds the format but not the record
  leaves every tracker stale after each merge. free-skills showed this: after
  #398 and #399, tracker #394 kept #388 and #389 under **Startable now**.
- **Chose to offer the record in update mode, not write it.** Update mode
  leaves unmarked content alone unless the owner asks. The record goes in the
  same decision as `docs/tracker-format.md` and its tracker-text citation,
  since all three only work together.
- **Chose one default containing-tracker rule.** Every open tracker that lists
  the merged unit's verified closing issue under `## Units` contains it. This
  matches the shared format, which lists units by issue. A project with its
  own **Startable now** rule or merge-order field keeps it: intake names that
  document in **Refresh** and **Detailed mechanics**.
- **Pointed free-skills at the in-repo format over a `docs/` copy.**
  free-skills' **Detailed mechanics** names
  `skills/agent-setup/references/tracker-format.md`. A copy would be a second
  file to keep in sync with its source, in the same repository, for no reader
  that can't already reach the source.

## Assumptions

- **Cleanup can find containing trackers from the closing issue.** The default
  rule asks cleanup to find the open trackers that list a closing issue, for
  example through the forge's cross-references on that issue. Freeside's
  working record relies on the same lookup.

Revisit when cleanup misses a containing tracker under the default rule, or
when merge-cleanup's record format changes.
