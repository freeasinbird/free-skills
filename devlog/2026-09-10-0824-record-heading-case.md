# Case-Insensitive Record-Heading Matching

Made merge-cleanup's **Post-merge obligations** record and agent-setup's
**Coordination model** record recognized case-insensitively, both the
heading and the field labels. A downstream project (straylight) adopted a
title-case heading style for all its prose, which would otherwise have
turned its `### Coordination Model` and `### Post-Merge Obligations`
records invisible to the two skills that read them. Case-insensitive
matching is back-compatible: every existing lower-case project is
recognized unchanged, and the canonical template examples stay lower-case.

## Rejected Options

- **Freeze the record headings as lower-case identifiers** and keep them
  out of a project's title-case style, the way a project can freeze a
  skill-matched citation slug. Rejected: the owner wanted full title-case
  consistency in the downstream project's prose, and a record heading is
  ordinary prose a reader sees, not an opaque slug. Case-insensitive
  matching gives both the consistency and the robustness at no cost.
- **Flip the canonical template examples to title case.** Rejected: that
  churns the skills for no gain and would read as the only blessed casing,
  when the point is that either casing is recognized. The examples stay
  lower-case; the rule says case doesn't matter.

## Revisit When

A skill gains a script that parses the record by exact string match; that
script must fold case the same way, or this note's guarantee breaks.
