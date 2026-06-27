# Front-load Quick install; move Installation below Skills

README opened with a conceptual "a skill is just a directory…" preamble plus
three install variants before a reader saw _what skills exist_. Reordered for
scannability (and to match gh-imgup's front-loaded Quick Start).

## Change

- New top-level **`## Quick install`** right after the intro: the three
  `npx skills add` commands + the update/scope-flags note. This is the
  recommended one-command path, now first.
- **`## Skills`** (the catalog) now comes before the detailed install reference.
- **`## Installation`** moved below Skills: keeps the conceptual intro (skill =
  dir + the two agent dirs), Manual install, and the `link-skills.sh` helper.
- Bidirectional cross-links: Quick install → Installation (for manual / clone
  setup); Installation → Quick install (the easiest path).

## Decisions

- **npx commands stay up top, in full** (three variants), not reduced to one —
  the "quick" path should be complete where it lives; Installation carries the
  _other_ methods, not a second copy of the npx flow. No duplication.
- **Reorder only — prose preserved.** Manual/link-skills text is unchanged
  except "Or place…" → "Place…" now that it no longer trails Quick install.

## Verification

Markdownlint + prettier --check clean. Heading order and both `#quick-install`
/ `#installation` anchors confirmed.
