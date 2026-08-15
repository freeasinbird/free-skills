# Keep work-unit stage records project-specific

Issue #121 introduces optional planning, implementation, review, and
integration handoffs that downstream projects may adopt independently.

## Decisions

- Chose an unmanaged, project-specific AGENTS.md record over a ninth managed
  section because each project's stages, mutations, inputs, outputs, finish
  lines, and transitions are owner choices. Projects with one implementation
  workflow should carry no unused stage text.
- Kept only the cross-project contract and authorization defaults in the
  canonical `finish-line` section. Downstream agents always read that section,
  so it can require them to honor a declared stage without making any stage
  mandatory.
- Required issue-backed state for sequential cross-agent handoffs, even within
  one short session, because the next agent needs durable input and output
  rather than transient chat context.
- Scoped the repository-change checklist around declared boundaries. An
  undeclared implementation phase keeps the checklist except actions assigned
  to declared stages; a declared implementation stage stops at its recorded
  transition. Non-implementation stages follow their own mutation and
  finish-line records. This supports independently adopted stages without
  crossing an explicit boundary.
- Made an explicit owner request the narrow update-mode exception for creating
  or editing a stage record. Without that request, an absent record stays
  absent and existing unmanaged content stays untouched.
- Rejected the managed `branches` section as the stage home because it owns
  concurrency and isolation, not sequential lifecycle policy. Rejected a
  separate stage configuration file because agents are not guaranteed to load
  it. Rejected a managed stage section because canonical synchronization would
  impose project-specific or empty content on every project.

Revisit when stage semantics become identical across projects, or when every
supported agent platform reliably discovers a dedicated project configuration
file alongside AGENTS.md.
