# Allow grep-locked lowercase list items

Issue [#185](https://github.com/freeasinbird/free-skills/issues/185) adopts a
repository-wide convention that every Markdown list item starts with a
capitalized word. A mechanical check enforces the convention outside frozen
decision notes, session-local copies, and fenced code.

## Decisions

- **Allowlist the five forge-record fields by exact text.** The
  await-pr-review routing matrix grep-locks these lowercase field names.
  Capitalizing them would require changing a test contract without changing
  behavior. Exact matching keeps the exception narrow and visible.
- **Ignore list items that do not start with a letter.** Code spans, links,
  task items, digits, and emphasis syntax preserve their exact content. The
  check flags only an initial lowercase letter.
- **Track Markdown fence character and length.** A closing fence must use the
  opening character and contain at least as many markers. This avoids false
  findings in examples and keeps shorter fence runs inside longer blocks.
- **Keep the check lexical after Prettier normalization.** CI runs Prettier
  3.9.6 before this check. Prettier joins non-interrupting ordered markers to
  their paragraph and rewrites marker-only continuations onto the marker line.
  The checker borrows fence and container tracking from the readability check.
  Its exact-item-text allowlist is the escape hatch for occasional false
  positives at this lexical, fence-aware boundary.

## Rejected Alternative

- **Capitalize the locked field names and update their regression test:**
  rejected because it edits a behavioral contract for a presentation-only
  convention. The allowlist documents why the existing strings remain exact.

Revisit a parser-based check only when false positives need more than an
occasional exact-text allowlist entry, or when the routing matrix no longer
pins the forge-record field strings.
