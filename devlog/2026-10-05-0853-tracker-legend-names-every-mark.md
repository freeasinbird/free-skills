# Name Every Diagram Mark in the Tracker Legend

Chose to extend the tracker format's verbatim legend so it names every mark
`## status` defines, over leaving the unnamed marks to project bullets. The
owner decided this on 2026-10-05. The legend now also lists the dotted arrow
(soft dependency) and the dashed outline (fenced).

The gap misled a reader. On a Freeside feature tracker
(freeside-ai/freeside#1616), a dotted edge ran from a fenced unit into a
startable one. The owner read the pair as a `starts-after` chain and asked why
a unit behind an unstartable one was startable. The legend named neither mark,
and the project bullet that explained the dotted edge sat below it.

Rejected options:

- **Leave the marks to project bullets.** Freeside's mechanics add an
  **Edges:** bullet "because the verbatim legend covers only `starts-after`".
  That covers the gap in one project and leaves it open in every other.
- **Edit the legend in the project's copy.** The copy is verbatim, so a local
  edit is drift that the next sync offers to overwrite.
- **List only the marks a diagram uses.** A per-tracker legend is no longer
  one verbatim line. It would also need a rewrite whenever a fence or a dotted
  edge appears or goes, and §refresh limits merge cleanup to four edits.

The legend keeps the format's own term, "soft dependency", and names no
relationship type. A project with typed relationships still says in its own
bullet which relation its dotted edges carry.

A project picks up the new line when it syncs its copy. It updates its open
trackers itself, because §refresh leaves the legend alone.

Revisit when the format gains or drops a diagram mark, since the legend must
change with it. Revisit also when a reader takes a soft dependency for a start
prerequisite; `## status` would then need to define the term.
