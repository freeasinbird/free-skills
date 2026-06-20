# Make README skills ordering explicitly alphabetical

The skills table was already in alphabetical order (agent-setup,
license-philosopher, self-merge) but nothing said so, so a future skill
could be appended out of order.

## What landed

- README: HTML comment above the skills table stating the order
  (alphabetical by skill name, insert in order).
- AGENTS.md: first real `Conventions` bullet recording the same rule;
  trimmed the placeholder TODO to the items still open.

## Decisions

- **Document, don't just sort.** The table was already sorted; the value is
  making the rule explicit so it's maintained. Marker lives both at the
  point of use (README comment) and where agents look for rules (AGENTS.md
  Conventions).
- **Alphabetical by skill name**, which equals the directory name and the
  table's link text — no ambiguity about the sort key.

## Deferred

- Nothing.
