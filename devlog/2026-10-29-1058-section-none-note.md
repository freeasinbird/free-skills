# Accept Notes on Section None Lines

Chose `names_entry` over `reverse_only` for notes on a section's opening
`none` or `_No response_` line. A relation followed by a reference holds
the unit. Bare relation names remain explanatory text, so
`none (starts-after, merges-after, stacked-on empty)` declares no dependency.
`reverse_only` rejects that shape because it requires a reference after
every `starts-after` mention.

[Issue #359](https://github.com/freeasinbird/free-skills/issues/359) carries
the contract and implementation plan. The lead-word boundary follows
paragraph mode. Paragraph parsing and later-line entry and note rules remain
unchanged outside the expanded none check. The section check holds notes naming any
typed relation and reference, even when that relation does not gate starts.

The contract accepts a note such as `none; starts-after the auth unit lands`
without a reference. Notes on later lines already permit that shape. A
reverse-dependency note such as `none. #20 starts-after #13` instead holds
the unit because it contains a typed relation and reference.

## Refute-First Findings

Independent parser checks resolved these claims:

- **Disproved by checks:** A note can hide a typed prerequisite. All four
  relations hold with local or cross-repository references, mixed case,
  emphasis, colon separators, tabs, and indented continuations.
- **Disproved by checks:** A longer word beginning with `none` can declare
  no dependency. `nonetheless`, `none_other`, and `none2` still hold.
- **Disproved by checks:** An accepted note can erase an earlier prerequisite
  or bypass a later entry or Blocker line. The prerequisite remains, and
  later contradictions or blockers still hold the unit.
- **Disproved by comparison:** Paragraph mode changed. The old and new
  parsers give identical results for the two accepted examples and notes
  naming `starts-after` or `merges-after` with a reference.
- **Allowed by the issue contract:** A reference-free prerequisite note is
  accepted, while a reverse-dependency note containing a typed relation and
  reference holds the unit.
- **Declined after fresh-context review:** Restricting notes to the first
  line would make them behave differently from bare `none`. The plan keeps
  the existing `seen` rule: a later none line cannot erase an earlier
  prerequisite. A direct parser check confirmed that prerequisite survives.

Revisit if the owner wants reference-free prerequisite prose to hold a unit,
or wants section notes to distinguish reverse dependencies from prerequisites.
