# Review convergence layers: pin exact phrases

Issue #199 turns the recurrence found in PR #198 into a mechanical check. It
follows the decision in
[`2026-09-01-1007-over-hardening-exit.md`](2026-09-01-1007-over-hardening-exit.md),
whose revisit condition called for a script if the same prose-rule defect
appeared again.

## Decision

Pin one exact phrase for each rule and layer. Treat
`skills/await-pr-review/references/review-response.md` as a pinned layer too.
Normalize whitespace and Markdown emphasis markers before matching, but keep
the match case-sensitive. A rewording in any pinned layer then forces the
author to review the corresponding rows for every other layer.

Keep the table under `scripts/` beside its checker. The table is part of the
repository-wide CI contract, not a new runtime resource of await-pr-review.
The provenance fallback stays reference-only because PR #198 explicitly
declined carrying it into the managed convention.

## Rejected Options

- **One shared phrase per rule.** The layers deliberately compress and
  paraphrase the reference, so one phrase would either fail current text or
  force reference wording into shorter conventions.
- **Per-layer alternates.** Alternates would let wording drift without forcing
  the cross-layer review this check exists to require.
- **Regex, synonyms, or paraphrase matching.** They add complexity and weaken
  the clear failure condition. Exact normalized substrings are enough.
- **A table inside the skill directory.** The checker is a project CI tool,
  and keeping its data beside it makes that ownership clear.

Revisit when routine prose edits cause enough table churn to obscure real
drift, or when a qualifier changes without changing any pinned phrase. Either
case means phrase pins no longer match the defect class this check should
catch.
