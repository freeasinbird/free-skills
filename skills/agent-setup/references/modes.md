# Mode Routing Detail

Use this reference from SKILL.md's Detecting Mode table. Each section holds
the procedure for one routing outcome that the table names.

## §combined

One request asks for both setup (init, adoption, or update) and coordination
reassessment. Protect any existing AGENTS.md before setup mutates it: run
reassessment step 1, then only step 2's read-only location preflight.

The preflight does only this:

- Locate every apparent coordination record, stage record, and mechanics line,
  then apply **Placement** against the current managed ranges.
- If adoption is requested, derive its planned ranges without editing and treat
  them as managed for this check.
- Resolve every syntactically local mechanics target only far enough to check
  its location. Also derive the ranges and files setup proposes to rewrite.

A marker or location failure that would expose a record, pointer line, or local
target to overwrite stops both operations.

Don't run the deeper checks yet: record cardinality, field, stage-layout,
stage-field, mechanics-value, and semantic target-suitability validation. Those
semantic failures don't make managed setup unsafe.

Then complete the requested setup using the file-state routing in SKILL.md's Detecting Mode table, and run
the full reassessment (all of steps 1-2) against the resulting setup. If setup
stops on an unsafe state or an unresolved owner choice, don't continue to
reassessment. Never discard the setup half of a combined request merely because
later reassessment validation must stop.

## §remnants

AGENTS.md has no exact managed markers but carries marker remnants. Stop and
report them; don't offer adoption. A remnant is either of these:

- A lookalike of the managed marker or the nested `project:done-checks` marker.
  This is the malformation rule in
  `references/managed-blocks.md` §marker-validation: comment lines that resemble
  either marker in spacing, case, or indentation, or carry its text inside a
  longer line.
- Any nested `project:done-checks` markers other than exactly one correctly
  ordered pair: a lone opener or closer, a duplicate, or a close before its
  open.

Wrapping sections around malformed remnants leaves a partially adopted file
that only fails later, so the user should fix or remove them first.

One exact, correctly ordered nested pair with no managed `done` block is not a
remnant. That's the documented opt-out (see `references/managed-blocks.md` §markers), so it
doesn't trigger this stop; such a file falls to §adopt below.

## §adopt

AGENTS.md exists without markers. Ask whether to adopt management or leave the
file unmanaged. To adopt:

1. Match sections to canonical keys by heading.
2. Wrap each match's existing text as-is in markers.
3. Gather the project-specific information from init step 4 without overwriting
   existing unmarked guidance. This includes coordination discovery, and it
   preserves any existing coordination or stage record under the update-mode
   rules.
4. Run the update-mode comparison so the user sees any canonical divergence as
   a diff.

One exception to as-is: when wrapping a matched `done` section, also wrap its
existing project checks in the nested `<!-- agents-md:project:done-checks -->`
markers, text unchanged. Update-mode validation requires the nested pair inside
a managed `done` block, so a bare wrap would dead-end the adoption. Where an
exact nested pair is already present (the opt-out routed here from
§remnants above), keep it as it stands and wrap the managed `done`
block around it; adding a second pair fails that same validation.

## §reassessment

Run this mode only for the explicit owner request described under "Detecting
Mode". It analyzes the effective project-specific coordination model and may
propose a change, but it never edits the model as part of ordinary init,
adoption, or managed-section update.

1. Establish the AGENTS.md boundary before reading it for meaning.
   - When the file exists, run the complete marker validation in
     `references/managed-blocks.md` §marker-validation.
     On any malformation, stop and report it. Do not analyze coordination
     content, propose a documentation diff, or edit AGENTS.md or a project
     coordination document.
   - When the file is absent, continue with the safe serial baseline, but keep
     reassessment report-only: do not create AGENTS.md or a project
     coordination document.

   Applying a recommendation first requires a separately requested init
   operation, with its normal profile, canonical sections, and scaffolding
   workflow.

2. Before reading project-specific policy for meaning, locate every apparent
   fixed-field coordination record, work-unit stage record, and **Detailed
   mechanics** value in AGENTS.md. Apply the complete input-state table in
   `references/coordination-discovery.md` §reassess before interpreting any
   value.

   Validate the **coordination record**:
   - A present record must contain each of its four fixed fields exactly once. A
     missing or repeated field is ambiguous owner policy, not evidence to infer.
   - With no record, the field and mechanics validations don't apply, and the
     effective model is the safe serial baseline.

   Validate the **stage record**:
   - Count the project-specific section grouping stage definitions as one stage
     record, not each definition inside it.
   - A stage entry begins at an immediate child heading of that section and ends
     at the next child heading or the section's end; the unique child-heading
     text is its name.
   - Within every entry, require each of the six exact field-label bullets once
     with a non-empty value before the record can inform coordination.
   - Prose before the first child heading is shared record guidance, not another
     stage.
   - Also accept one legacy single-stage record when all six fields appear
     directly in a stage-specific section exactly once with non-empty values.
     Use that section heading as its name, and treat descendant headings whose
     subtrees contain no exact stage-field bullet as content of the stage.
   - A stage-field bullet below any descendant heading makes the
     direct-plus-descendant layout ambiguous.
   - A generic container with all six direct fields is legacy only when it has
     no descendant heading. Its sole stage's name was not recorded and must be
     reported as uncertainty, not invented.
   - Direct fields mixed with child stage entries under a generic container, or
     a skipped-level heading there without an immediate child entry, are also
     ambiguous and stop validation.

   Stop on any cardinality, completeness, placement, or target failure and ask
   the owner to repair the policy; never choose, merge, or edit one version
   while leaving another. After validation, read the single record, any valid
   mechanics source, and the single stage record.

   Validate the **mechanics targets**:
   - A shape-2 external work contract is read-only evidence, not an editable
     mechanics target. When it's unavailable, report uncertainty rather than
     rejecting an otherwise valid record.
   - A legacy blank **Detailed mechanics** value is also valid when the final
     shape contains only shape 1, shape 2, or both.
   - Any shape containing shape 3, 4, or 5 requires a safe repository-local,
     project-specific mechanics document, even when shape 2 or an external work
     contract is also present.
   - Every mechanics target that a reassessment may edit must be such a local
     document outside managed ranges.

3. Follow `references/coordination-discovery.md` §reassess. Examine each
   available evidence source, name unavailable sources as uncertainty, and
   distinguish observed facts from inferences. Cite the repository path, work
   unit, issue relation, owner statement, or other source that supports each
   material finding.
4. Report the effective model, any drift between its record and current
   evidence, and the smallest shape current evidence supports. The outcome may
   be no change, an upgrade, a simplification, or removal of obsolete topology.
   Cap any proposed concurrency at demonstrated review and integration capacity.
5. Before changing AGENTS.md or a project coordination document, show the exact
   proposed diff, including any **Reassess when** field change, and ask for
   approval. Never silently rename a lane, reinterpret a relationship, or alter
   an issue dependency; a rename is an explicit documentation proposal, and
   issue-dependency inspection is read-only evidence.
6. On approval, apply only the shown project-specific changes and preserve all
   unrelated unmanaged content verbatim. Without approval, leave the project
   unchanged.
7. State observable triggers for the next reassessment in the report. Put them
   in the record's **Reassess when** field only when the owner approved that
   field change in step 5's exact diff and step 6 applied it; otherwise leave
   the record unchanged and keep the triggers in the report.
