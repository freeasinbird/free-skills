# Tracker Refresh Holds a Body with Two Dependencies Fields

Chose to hold an open unit whose body has more than one Dependencies field,
in any mix of heading and lead line, and to skip headings and leads inside
fenced code blocks and HTML comments rather than hold on them. Issue #356
carries the contract; this extends the per-unit hold in
`2026-10-27-2157-tracker-refresh-per-unit-hold.md`.

## Why

`parse_deps` read only the first Dependencies heading, or failing that the
first lead line, and treated fenced and commented lines as ordinary text. A
`none` field above a real `starts-after #11` field, whether real, fenced, or
commented out, listed the unit startable while #11 was open. So did a
commented-out heading inside the real section, which ended it early. That is
the one failure the command must not have, since it lets two sessions
collide.

## Decisions

- **Hold on two fields, over picking one.** No rule for choosing between two
  fields is safe: either can carry the prerequisite. A hold is visible on
  stderr with the count, and the planner fixes the body.
- **Count lead lines as fields, over counting headings only.** A heading
  followed by a `**Dependencies.**` lead, or two leads, hid a prerequisite
  the same way. The cost is that a heading-form body with a stray line
  starting `Dependencies:` now holds. That is a visible hold, not a false
  startable.
- **Skip hidden headings, over holding on them.** A commented-out template
  block is common and isn't a second field. Holding on it would hold
  ordinary bodies for no gain. Hidden headings neither start a field nor end
  one; a hidden line inside the section still parses, so a fenced or
  commented `starts-after` there still blocks.
- **Follow CommonMark's block rules, over the simpler scan in the plan.**
  The plan scanned for any line starting with a fence and any trailing
  `<!--`, and claimed a mismatch with the rendered page could never add a
  startable unit. That claim was false. When the scan hides a real field
  that the page shows, a visible decoy `none` becomes the only field the
  scan reads. The scan now matches fence length, character, and indent,
  rejects a backtick in a backtick info string, and opens a comment only on
  a line that starts with `<!--`.
- **Hold when a block's end is uncertain, over modeling containers.** The
  scan doesn't track list items, so it can't tell where an indented block
  ends on the page. GitHub also hides the rest of the body after a comment
  that a `<!--` reopens on its `-->` line, and shows a fence marker inside
  raw HTML such as `<details>` as text. When such a block, or one left open
  at the end of the body, hides a heading or a Dependencies lead, the unit
  holds. The raw HTML region is read loosely, since reading too much only
  adds holds. Full container and HTML-block tracking would cost far more
  code for rare bodies.

## Refute-First Result

An independent reviewer attacked the plan's scan and confirmed six bodies
that it listed startable while GitHub showed `starts-after #11` and `main`
blocked them:

- A shorter closing fence, in backticks or tildes.
- A closing fence indented four spaces.
- An opening fence indented four spaces.
- An unclosed fence in a list item.
- A mid-line `<!--`.
- A backtick in a backtick fence's info string.

Each led to the CommonMark rules or the uncertain-block hold above, and
each is now a test case. The reviewer disproved these: a single-line
comment before the real heading, a heading with a trailing `<!--`, and
longer sections from hidden headings, which can only add entries or holds.
It also checked the new awk for POSIX-only features.

A second reviewer attacked the revised scan and confirmed one more class: a
fence marker inside a raw HTML block (`<div>`, `<details>`, `<pre>`, or a
lone tag line) that the scan opened as a fence, hiding the real field. That
led to the raw HTML rule above. It disproved a `<!--` inside a `<div>`,
`<!-->` and `<!---->`, markers nested across fences and comments, fences in
blockquotes and nested lists, tab-indented fences, whitespace-only lines,
CRLF, tilde info strings with backticks, and a decoy after the real field.

## Revisit When

- Real trackers show the lead-line count holding bodies often. Then narrow
  the count to headings plus lead lines outside any heading section.
- Real bodies hold often on an uncertain block. Then track list containers
  or HTML blocks exactly instead of holding.
