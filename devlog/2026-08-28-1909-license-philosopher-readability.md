# License philosopher readability structure

Issue #169 rewrites the license-philosopher instructions and the public
licensing philosophy without changing their rules.

## Decisions

- **Keep both philosophy files byte-identical.** The skill copies its
  reference verbatim into downstream repositories. The root copy states this
  project's philosophy. Shipping both in one commit prevents either copy from
  becoming stale.
- **Keep the philosophy general.** Its work-type table names licenses and
  linking behavior, but no language or ecosystem. Operational ecosystem
  examples stay in `SKILL.md`. The three opening paragraphs keep the owner's
  public wording byte-for-byte.
- **Keep cross-license safeguards below the license table.** The table shows
  files and notices well. It doesn't state clearly that canonical license text
  stays unmodified, LGPL needs both texts, or MPL's notice is a manual source
  file step. Separate bullets keep those rules visible.

## Refute-first findings

- **Disproved, license replacement without confirmation.** The rewrite still
  requires confirmation before replacing an existing license file.
- **Disproved, continuing with an unsupported license.** The short-circuit
  still says to stop and explain the conflict when the user keeps one.
- **Allowed, existing README section replacement.** The old text already
  replaced that section after the user chose a license. Adding a separate
  confirmation would change the flow, so the rewrite doesn't add one.
- **Disproved, LGPL or MPL file drift.** LGPL still writes both license files.
  MPL still writes one and points the user to the Exhibit A source notice.
- **Confirmed, one compressed qualifier.** The first draft omitted “only”
  from the MPL override sentence. The selection table still constrained the
  choice, but restoring the word removed any alternate reading.
- **Confirmed, local application category drift.** The first rewrite shortened
  “Standalone applications and tools” to “Tools that run locally.” Automated
  review caught the lost category. Restoring “Standalone applications and
  tools” keeps the philosophy aligned with the skill's GPL mapping.

Revisit when the freeasinbird.com about page next changes or this repository
becomes its source of truth. Until then, issue #169 intentionally lets the two
presentations differ.
