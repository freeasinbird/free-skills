# Coordination Discovery

Use this reference during agent-setup initialization or adoption to derive the
smallest coordination model supported by current project evidence. The shapes
are capabilities, not maturity levels. A project may remain simple, skip a
capability, combine supported capabilities, or later simplify when its
evidence changes.

## §evidence

Inspect the evidence available now and name conflicts or gaps rather than
filling them with assumptions:

- **Plans:** treat a current plan as evidence of intended work, not authority.
  Check its assumptions against the repository and owner statements. A
  speculative plan by itself cannot justify typed relations, named streams, or
  an integration spine.
- **Code and architecture documents:** look for actual shared contracts,
  independent components, generated surfaces, path overlap, integration
  points, and ordering constraints. Directory names alone do not establish
  ownership or stable work streams.
- **Work-unit and PR history:** look for boundaries that recur across several
  units, repeated conflicts, intentional stacks, integration delays, and the
  people or agents that realistically review and integrate the work. This is
  the required basis for named streams.
- **Owner expectations:** use stated plans for team size, review capacity,
  release ownership, and expected concurrency. Keep a stated expectation
  distinguishable from observed project behavior.

Prefer corroborated evidence over a single source. When sources conflict,
select the simpler safe shape. Put the disagreement in the reassessment trigger
when a coordination record exists or the owner requests one; otherwise report
the disagreement and an observable reassessment trigger in the setup result
without persisting a record. Never turn a tentative directory layout or roadmap
heading into a lane, ownership map, graph, or claim mechanism.

Cap recommended concurrency at the number of independent units the project can
review and integrate without building an unowned queue. Consider reviewer and
integrator availability, CI throughput, and shared-contract bottlenecks, not
only the number of workers or isolated checkouts. When capacity is unknown,
recommend serial work until the owner supplies a credible limit.

## §shapes

Begin with the serial or path-and-dependency base, then add only the later
capabilities the evidence requires. Shapes 3 through 5 may compose: typed
relations, stable named streams, and an integration spine solve different
problems. A richer primary shape retains any earlier semantics the evidence
still supports. Record the smallest combination that fully represents the
project, not the highest label it could plausibly claim.

### 1. Safe Serial Baseline

Use when the repository has neither a credible plan nor demonstrated
independent work, when its only plan is speculative and uncorroborated, or when
evidence conflicts. No coordination record is required because absence means
this baseline. Do not invent lanes, owners, graphs, claims, or parallel work.
Reassess after repeated independent work units appear or serial work creates an
observable integration delay.

### 2. Path and Dependency Units

Use when concrete work can be divided into independent units and the relevant
path overlap or dependency order is known, but recurring streams are not. Keep
boundaries and dependencies in each work contract. Add a forge-visible claim
only when the project already defines its mechanism and stale-claim handling.
Reassess when start order, integration order, branch ancestry, or mutual
exclusion repeatedly need different treatment.

### 3. Typed Relations

Use when evidence shows that one generic dependency cannot safely represent
all operational relationships. Keep these meanings distinct even if the
project uses different names:

- **Start order:** one unit must finish or merge before another begins.
- **Merge order:** units may start independently, but one integrates later.
- **Intentional stacking:** one branch deliberately bases on another open
  branch or PR.
- **Mutual exclusion:** units may not be active at the same time.

Put definitions, authority, examples, and tracker notation in a project
document. Unknown or materially ambiguous relations serialize until an owner
or designated integrator resolves them. Reassess when the relations repeatedly
cluster into stable work boundaries.

### 4. Stable Named Work Streams

Use only when work-unit or PR history shows recurring, stable boundaries that
help route work and predict overlap. A top-level directory, component name, or
one plan is insufficient. Define each stream's scope and interaction points in
project documentation, and keep work contracts authoritative for individual
units. Reassess when work routinely crosses streams or the names stop helping
review and integration.

### 5. Integration Spine or Shared-Contract Domain

Use when recurring convergence work needs a designated integration path, or a
shared contract must change serially even while component work remains
independent. Model shared-contract serialization separately from component
ownership: owning or working in a component does not grant concurrent access to
the shared contract, and an integrator can coordinate convergence without
owning every component. Reassess when the bottleneck disappears, changes
location, or a simpler per-unit dependency captures it completely.

For shapes 3 through 5, keep long mechanics outside AGENTS.md. The project
document should state relationship authority, work-unit boundaries, claim
rules when one exists, integration responsibility, and the capacity limit.
AGENTS.md carries only the compact record and a pointer to that document.

## §record

Place a coordination record in unmanaged, project-specific AGENTS.md content
near the `Agent-setup profile:` line. Never put it inside a canonical managed
block. Use this fixed field list:

```markdown
### Coordination model

- **Current shape:** <shape or combination and supported concurrency width>
- **Evidence basis:** <one line naming the supporting evidence>
- **Detailed mechanics:** <project-doc pointer, required for shapes 3–5>
- **Reassess when:** <observable evidence that would justify change>
```

Omit the record for the safe serial baseline unless the owner explicitly wants
it stated. No record means serial work, not missing content. For shape 2, the
detailed-mechanics field may point to the work-contract location instead of a
dedicated coordination document. Never create a placeholder graph, lane list,
ownership map, or claim rule merely to fill a field.

In update mode, detect the record and report whether all four fields are
present. Preserve it and all other unmanaged content verbatim unless the owner
explicitly requests a field change. Do not reassess or rewrite an established
model as a side effect of syncing canonical sections; topology reassessment is
a separate owner-assigned work unit.

## §freeside

Freeside's completed coordination change is a calibration example, not a
template. Its work history showed recurring work streams, a serialized
shared-contract chain, a designated integration role, and distinct start,
merge, stacking, and exclusion constraints. That evidence justified stable
named streams plus an integration spine and typed relations.

The portable lesson is the derivation: recurring history justified names,
shared-contract risk justified serialization, and observed integration needs
justified a spine. Do not copy Freeside's lane names, tracker vocabulary,
labels, or integration role into another project. Derive local terms only from
that project's evidence. See
[Freeside PR #801](https://github.com/freeside-ai/freeside/pull/801) for the
project-specific result.
