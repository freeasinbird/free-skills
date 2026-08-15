# Separate Coordination Reassessment from Routine Sync

Issue #123 adds an owner-requested coordination reassessment lifecycle to
agent-setup and closes the revisit condition in
`devlog/2026-08-15-1217-progressive-coordination-discovery.md`.

## Decisions

- Chose an explicit reassessment mode over detecting topology drift during
  ordinary update because byte-for-byte preservation of unmanaged content is
  the trust boundary that makes managed-section sync safe to run routinely.
  A satisfied **Reassess when** condition remains evidence for a requested
  analysis, not an automatic trigger or mutation authority.
- Reused update mode's complete marker validation before reassessment reads
  AGENTS.md for meaning. An explicit analysis request does not make malformed
  managed boundaries trustworthy, and stopping first prevents project-specific
  policy from being interpreted or edited inside an unsafe region.
- A fresh-context refute pass confirmed three gaps beyond marker syntax:
  coordination records, stage records, and resolved mechanics targets could
  still be managed or non-project-specific. All three findings were accepted;
  none were rejected by verification. Each input must now be repository-local,
  project-specific, and wholly unmanaged before reassessment trusts it.
- A re-review exposed a cardinality gap in the same policy-input trust class:
  individually valid records can still contradict one another. Reassessment
  now stops on multiple coordination records, multiple stage records, or a
  repeated fixed coordination field instead of choosing or merging policy. A
  stage record is the project-specific section grouping stage definitions, so
  valid multi-stage policy is not mistaken for duplicate records.
- Replaced the recurring input-validation clauses with one explicit state
  table. An existing record is trusted only when all four fixed fields appear
  exactly once. Shape-2 external work contracts remain read-only evidence,
  while shapes that require detailed mechanics still need a safe local target.
  The zero-record baseline skips field and mechanics validation, and any
  composed shape containing shape 3, 4, or 5 keeps the local-target requirement.
  Legacy shape-1 and shape-2 records may retain a blank mechanics value because
  the prior contract required a document only for shapes 3–5; richer composed
  shapes never inherit that exception.
  No validator script was added because the platform-agnostic, no-shell path
  has no established executable boundary; that remains a separate owner
  decision rather than follow-up work from this change.
- A combined setup-and-reassessment request now preflights markers and policy
  placement before setup touches an existing AGENTS.md, then runs the complete
  input validation on the resulting setup before analysis. This closes the
  deletion path for policy misplaced inside a managed block, including a local
  mechanics target that a pointer outside the block could otherwise hide,
  without letting an unrelated semantic defect in unmanaged policy cancel a
  safe requested setup. The state table still requires every stage entry's six
  fields exactly once before the stage section can inform coordination.
- Adoption preflight treats planned managed ranges as managed before adding
  markers, closing the equivalent deletion path in an unmarked AGENTS.md. Stage
  entries now have an exact boundary: unique immediate child headings under the
  record section, with shared record prose only before the first child heading
  and all six exact field bullets inside each entry.
- Preserved backward compatibility for an unambiguous legacy single-stage
  section whose six fields sit directly under its heading. New and revised
  policy uses child headings, but reassessment accepts the direct-field form as
  one stage and rejects only a mixed direct-plus-child layout.
- Tightened that compatibility boundary after refutation: all six values must
  be non-empty, and a generic container heading cannot invent a stage name or
  hide a skipped-level entry. A stage-specific legacy section may keep nested
  content headings because its own heading fixes the stage boundary, but a
  stage-field bullet under one makes the layout an ambiguous possible child
  entry. Adding a sibling to the legacy form requires an owner-approved
  structural migration that relocates the old field lines verbatim and
  confirms the scope of every other direct line before adding the requested
  stage. Render-empty comments and placeholders do not satisfy a required
  field.
- Kept missing-file reassessment report-only and placed every **Reassess when**
  write inside the exact approval-gated diff. A reassessment request does not
  authorize creating a partial agent setup, and a rejected model change does
  not authorize a trigger-only policy edit.
- Sequenced combined setup-and-reassessment requests instead of giving
  reassessment unconditional precedence. Init, adoption, or update completes
  first, so an explicit setup request cannot be discarded and reassessment
  reads the resulting safe, complete setup rather than creating a partial one.
- Chose analysis, an evidence-cited recommendation, and an approval-gated diff
  over direct record editing. Coordination names and relationship meanings are
  owner-authored project policy; evidence can show that they are stale without
  silently redefining them.
- Reused the existing evidence and shape derivation for upgrades and
  simplifications instead of creating separate maturity paths. The smallest
  currently supported shape can add structure, retain it, simplify it, or
  remove an obsolete record.
- Kept issue-dependency inspection read-only and project-document proposals
  local to the repository. Reassessment informs coordination policy but does
  not maintain tracker state, active claims, or a critical path.
- Kept canonical managed blocks unchanged. The lifecycle governs
  project-specific records and documents, while the existing canonical gates
  already protect concurrency and integration.

Revisit when projects need update mode to report a tripped reassessment
condition without analyzing it, or when recurring reassessment outputs reveal
a universal managed gate rather than project-specific policy.
