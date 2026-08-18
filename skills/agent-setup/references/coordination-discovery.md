# Coordination Discovery

Use this reference during agent-setup initialization, adoption, or explicit
coordination reassessment to derive the smallest coordination model supported
by current project evidence. The shapes are capabilities, not maturity levels.
A project may remain simple, skip a capability, combine supported capabilities,
or later simplify when its evidence changes.

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
owning every component. Serialization here means repo-wide mutual exclusion
among changes to the shared surface, not per-unit ordering that only sequences
each unit's contract change before its own dependents. Per-unit ordering is the
reading that fails: it permits several units to each open "its own serialized"
contract change concurrently, colliding semantically on the surface where merge
tooling does not reliably surface the conflict.

When the selected model includes shared-contract serialization (not an
integration-spine-only path with no serialized contract), the
detailed-mechanics project document must define five things:

- **The surface** as concrete paths and generated artifacts, including
  downstream sites a change must move in the same change (exhaustive-match
  sites, generated consumers).
- **The exclusivity rule:** at most one active contract change at a time,
  checked against every other in-flight contract change before starting;
  collision means wait or surface, never proceed in parallel. Make
  acquisition race-safe, since ordinary issue, PR, or label creation is not an
  atomic check-and-register: define a protocol that breaks a concurrent tie
  deterministically, such as registering first and then rechecking with a
  fixed winner (earliest entry, lowest ID), or a designated authority that
  grants the lock, so two simultaneous starts can neither both proceed nor
  both wait forever.
- **Forge-visible enumeration** of in-flight contract changes (a marker on
  contract-bearing units, or their declared surface paths on a forge-visible
  work contract), registered before implementation begins so a starting unit
  can check against every in-flight change. A directly assigned unit whose
  contract would otherwise live only in the prompt registers a forge-visible
  entry (issue, draft PR, or the project's claim mechanism) first. Gate this
  registration on available forge capability: where an assigned agent lacks
  the tooling or permission to register, the mechanics name a human or
  external registrar, or a stop-and-escalate, so no agent faces an impossible
  startup step.
- **Registration lifecycle:** when an entry joins the active set, when it
  leaves it (normally on merge or close), and how a stale or abandoned entry
  is released or superseded. A registration with no defined release blocks the
  surface indefinitely or invites agents to bypass the lock by guessing it is
  dead.
- **Ordering relief** when several planned units need the surface: an explicit
  dependency chain, or one combined leading contract change.

Reassess when the bottleneck disappears, changes
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
detailed-mechanics field may point to repository-local work-contract
documentation instead of a dedicated coordination document. A tracker issue
or other external work contract remains evidence, not an editable mechanics
target. Never create a placeholder graph, lane list, ownership map, or claim
rule merely to fill a field.

In update mode, detect the record and report whether all four fields are
present. Preserve it and all other unmanaged content verbatim unless the owner
explicitly requests a field change. Do not reassess or rewrite an established
model as a side effect of syncing canonical sections; topology reassessment is
a separate owner-assigned work unit described in `SKILL.md` under
"Coordination reassessment" and detailed in §reassess.

## §reassess

Reassessment re-runs coordination discovery against current evidence without
turning routine synchronization into policy analysis. Begin with the existing
record and detailed mechanics, when present, and any stage record. If no
coordination record exists, the observed starting model is the safe serial
baseline. If AGENTS.md itself is absent, analyze and report only; init must
establish the profile, canonical sections, and scaffolding before any
coordination record or project coordination document is created.

When AGENTS.md exists, validate its managed ranges before interpreting policy,
then locate every apparent fixed-field coordination record, work-unit stage
record, and **Detailed mechanics** value. Apply this input-state table in order:

| Input                     | Accepted state                                                                                                                                                                                                                                                                                                                                                                                                                 | Stop condition                                                                                                                                                                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Coordination record       | Zero, meaning the safe serial baseline, or one record                                                                                                                                                                                                                                                                                                                                                                          | More than one record                                                                                                                                                                                                                                    |
| Fixed coordination fields | With one record, each of **Current shape**, **Evidence basis**, **Detailed mechanics**, and **Reassess when** appears exactly once; with zero records, not applicable                                                                                                                                                                                                                                                          | Any field in the one record is missing or repeated                                                                                                                                                                                                      |
| Work-unit stage record    | Zero or one project-specific section; one section may contain several stage definitions under immediate child headings                                                                                                                                                                                                                                                                                                         | More than one stage section                                                                                                                                                                                                                             |
| Stage layout              | In one stage section, either one legacy entry with all six fields directly in a stage-specific section (whose descendant subtrees contain no stage-field bullet), one unnamed legacy entry with all six fields directly in a generic container that has no descendants, or immediate child entries where each unique heading begins one entry and preceding prose is shared guidance; with zero stage sections, not applicable | Direct legacy fields mix with a descendant stage-field bullet, a generic container mixes direct fields with descendants, a skipped-level heading there has no immediate-child entry, other boundaries are ambiguous, or an immediate-child name repeats |
| Stage fields              | Within every accepted entry, each of the six exact fields appears once with a non-empty value                                                                                                                                                                                                                                                                                                                                  | Any entry field is missing, empty, or repeated                                                                                                                                                                                                          |
| Placement                 | Every present record range and mechanics line is outside all managed ranges; with zero coordination records, its mechanics line is not applicable                                                                                                                                                                                                                                                                              | Any present record or mechanics line intersects a managed range                                                                                                                                                                                         |
| Mechanics value           | With one record whose final shape contains only shape 1, shape 2, or both, a legacy blank value or explicit no-document value; shape 2 may instead use a local or external work contract. Whenever shape 3, 4, or 5 appears, a repository-local project document                                                                                                                                                               | The value does not fit the recorded shape, or a required local target is unsafe or unresolved                                                                                                                                                           |

The six exact stage labels are **Activation**, **Allowed mutations**,
**Required input**, **Durable output**, **Finish line**, and **Transition**.
Each must appear as a bold field-label bullet once within its immediate-child
heading entry with a non-empty value. A value is non-empty only when its
rendered inline or continuation text before the next exact field-label bullet
or heading contains substantive policy. HTML comments do not count, and
placeholder-only text such as `TODO` or `TBD` is empty.

For a legacy stage-specific section, require those six bullets directly in the
section exactly once with non-empty values, use its heading as the sole stage
name, and treat descendant headings as content only when their subtrees contain
no exact stage-field bullet. If a descendant subtree does contain one, stop on
an ambiguous mix of direct legacy fields and a possible child entry. A generic
container heading, such as `Stages`, `Work unit stages`, or `Work-unit stages`,
does not supply a name; accept its six complete direct fields as one unnamed
legacy stage only when it has no descendant headings, and report the missing
name as uncertainty. Do not invent one. Under a generic container, stop when
direct field bullets appear alongside child headings or a skipped-level heading
appears without an immediate-child entry. Deeper headings within an
immediate-child entry belong to that entry.

When an owner asks to add a sibling to a legacy direct-field record, first
propose and obtain approval for the necessary structural migration. Name the
existing stage with the owner's input when the section heading is generic,
create its immediate child heading, and move its six field bullets and
continuation lines beneath that heading verbatim. Classify every other direct
line in the proposal as shared pre-entry guidance or existing-stage content,
preserve its text and relative order verbatim within that scope, and ask the
owner to confirm each classification before adding only the requested sibling.
Without approval, leave the record unchanged.

Every row through **Placement** inspects structure and labels without adopting
their values as policy. When the first row finds no coordination record, skip
its field and mechanics rows and use the safe serial baseline. With one record,
read **Current shape** only after those structural rows pass, then classify
**Detailed mechanics** against the final row. Any shape containing shape 3, 4,
or 5 takes precedence over a composed shape 2 and requires a safe local
document. A blank legacy value is accepted only when the final shape contains
shape 1, shape 2, or both and none of shapes 3–5. A local target must be
project-specific, not a canonical source or scaffold template; when it targets
AGENTS.md, its whole section must also remain outside every managed range.

For any combined setup-and-reassessment request, run marker validation and the
overwrite-risk portion of **Placement** before setup. For adoption, apply it to
both current managed ranges and the read-only set of sections adoption proposes
to wrap. Resolve every syntactically local mechanics target only far enough to
locate its range or file, and derive the ranges and files the requested setup
proposes to rewrite. A record, mechanics line, or local target that intersects
one of those locations stops both operations before setup can overwrite it.
Defer every other table row, including mechanics-value and semantic target
suitability, until the full reassessment after setup completes; a semantic
policy failure outside overwrite-risk locations stops that reassessment, not
the requested safe setup.

A shape-2 tracker issue or other external work contract is read-only evidence,
not an editable mechanics target. Resolve and read it only when the source is
available; otherwise report the unavailable evidence as uncertainty and
continue. In a composed shape it may supplement, but never replace, the local
mechanics that shape 3, 4, or 5 requires. Never include an external
work-contract change in the proposed diff. Stop on every other unsafe,
ambiguous, or unresolved state before reading or modifying the record or
target; structurally valid markers do not make content inside them
project-specific.

Inspect these sources only when they are available, and identify each one in
the report:

- architecture and recent architecture changes;
- recent work units and PR history, including recurring boundaries and
  overlap;
- issue dependencies and their stated meanings;
- repeated path overlap or shared-surface collisions;
- changes to shared contracts or generated surfaces;
- intentional branch or PR stacking;
- start-order, merge-order, and mutual-exclusion constraints; and
- documented manual scheduling friction, plus the people or agents available
  to review and integrate concurrent work.

Report unavailable sources and ambiguous meanings as uncertainty. Separate
observations from inferences, and cite the path, work unit, issue relation,
owner statement, or other available source behind every material finding.
Never infer coordination maturity from repository size, age, or directory
layout alone.

Compare the current record and mechanics with the evidence. Look specifically
for stale stream names, an obsolete integration spine or shared-contract
bottleneck, missing structure now supported by recurring evidence, and an
over-modeled topology whose distinctions no longer guide real work. Also check
whether the record's **Reassess when** condition has become observable. A
trigger starts analysis only when the owner requests reassessment; it never
activates update mode or authorizes mutation.

Re-run §shapes and select the smallest safe shape supported now. The result
may keep the current model, add a capability, simplify it, or return to the
safe serial baseline. Use the same evidence rule for both upgrades and
simplifications. When sources conflict, prefer the simpler safe shape and
report the conflict. Apply §evidence's review and integration capacity cap to
every concurrency recommendation.

Present the effective model, evidence and uncertainty, detected drift,
recommended outcome, and next observable reassessment triggers. Show an exact
diff for every proposed AGENTS.md or project-document change before editing,
including any **Reassess when** field change. Existing lane names and
relationship meanings remain authoritative until the owner explicitly
approves a documented rename or reinterpretation. Issue dependencies are
read-only evidence and are never mutation proposals. Remove an obsolete
coordination record or update its reassessment triggers only when the owner
approves that exact diff; otherwise preserve it and all unrelated unmanaged
content verbatim and keep the triggers in the report.

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
