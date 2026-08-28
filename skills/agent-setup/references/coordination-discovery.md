# Coordination Discovery

Use this reference during agent-setup init, adoption, or an explicit
coordination reassessment. It derives the smallest coordination model the
current project evidence supports.

Shapes are capabilities, not maturity levels. A project may stay simple, skip a
capability, combine capabilities it supports, or simplify later when its
evidence changes.

## §evidence

Inspect the evidence available now. Name conflicts and gaps instead of filling
them with assumptions.

- **Plans:** treat a current plan as evidence of intended work, not authority.
  Check its assumptions against the repository and owner statements. A
  speculative plan alone cannot justify typed relations, named streams, or an
  integration spine.
- **Code and architecture documents:** look for real shared contracts,
  independent components, generated surfaces, path overlap, integration points,
  and ordering constraints. Directory names alone do not establish ownership or
  a stable work stream.
- **Work-unit and PR history:** look for boundaries that recur across several
  units, repeated conflicts, intentional stacks, and integration delays. Note
  who realistically reviews and integrates the work. This history is the
  required basis for named streams.
- **Owner expectations:** use stated plans for team size, review capacity,
  release ownership, and expected concurrency. Keep a stated expectation
  separate from observed project behavior.

Weigh the evidence before choosing a shape:

- **Prefer corroborated evidence** over a single source.
- **On conflict, choose the simpler safe shape.**
- **Record the disagreement.** When a coordination record exists or the owner
  requests one, put the disagreement in its reassessment trigger. Otherwise
  report the disagreement and an observable reassessment trigger in the setup
  result, and persist no record.
- **Never turn a tentative layout into structure.** A directory layout or
  roadmap heading is not a lane, ownership map, graph, or claim mechanism.

Cap concurrency at capacity. Recommend no more independent units than the
project can review and integrate without building an unowned queue. Weigh
reviewer and integrator availability, CI throughput, and shared-contract
bottlenecks, not just the number of workers or isolated checkouts. When capacity
is unknown, recommend serial work until the owner gives a credible limit.

## §shapes

Start from the serial or path-and-dependency base. Add only the later
capabilities the evidence requires.

Shapes 3 through 5 may combine: typed relations, stable named streams, and an
integration spine solve different problems. A richer primary shape keeps any
earlier semantics the evidence still supports. Record the smallest combination
that fully represents the project, not the highest label it could claim.

### 1. Safe Serial Baseline

- **Use when:** the repository shows no credible plan and no demonstrated
  independent work, its only plan is speculative and uncorroborated, or the
  evidence conflicts.
- **Do:** run work serially. No coordination record is required, because its
  absence means this baseline. Do not invent lanes, owners, graphs, claims, or
  parallel work.
- **Reassess when:** repeated independent work units appear, or serial work
  creates an observable integration delay.

### 2. Path and Dependency Units

- **Use when:** concrete work divides into independent units and the relevant
  path overlap or dependency order is known, but recurring streams are not.
- **Do:** keep boundaries and dependencies in each work contract. Add a
  forge-visible claim only when the project already defines its mechanism and
  its stale-claim handling.
- **Reassess when:** start order, integration order, branch ancestry, or mutual
  exclusion repeatedly need different treatment.

### 3. Typed Relations

- **Use when:** evidence shows that one generic dependency cannot safely
  represent every operational relationship.
- **Do:** keep these four meanings distinct, even when the project names them
  differently:
  - **Start order:** one unit must finish or merge before another begins.
  - **Merge order:** units may start independently, but one integrates later.
  - **Intentional stacking:** one branch deliberately bases on another open
    branch or PR.
  - **Mutual exclusion:** units may not be active at the same time.
- **Document** the definitions, authority, examples, and tracker notation in a
  project document.
- **Serialize** any unknown or materially ambiguous relation until an owner or
  designated integrator resolves it.
- **Reassess when:** the relations repeatedly cluster into stable work
  boundaries.

### 4. Stable Named Work Streams

- **Use only when:** work-unit or PR history shows recurring, stable boundaries
  that help route work and predict overlap. A top-level directory, a component
  name, or one plan is not enough.
- **Do:** define each stream's scope and interaction points in project
  documentation. Keep work contracts authoritative for individual units.
- **Reassess when:** work routinely crosses streams, or the names stop helping
  review and integration.

### 5. Integration Spine or Shared-Contract Domain

- **Use when:** recurring convergence work needs a designated integration path,
  or a shared contract must change serially even while component work stays
  independent.
- **Separate the shared contract from component ownership.** Owning or working
  in a component grants no concurrent access to the shared contract. An
  integrator can coordinate convergence without owning every component.
- **Serialize the shared surface repo-wide.** Serialization here means repo-wide
  mutual exclusion among changes to the shared surface. It is not per-unit
  ordering that sequences only each unit's contract change before its own
  dependents. Per-unit ordering is the reading that fails. It lets several units
  each open "its own serialized" contract change at once. They then collide
  semantically on a surface where merge tooling does not reliably show the
  conflict.
- **Reassess when:** the bottleneck disappears, moves, or a simpler per-unit
  dependency captures it completely.

When the selected model includes shared-contract serialization (not an
integration-spine-only path with no serialized contract), the detailed-mechanics
project document must define five things:

1. **The surface:** the concrete paths and generated artifacts, including the
   downstream sites a change must move in the same change (exhaustive-match
   sites, generated consumers).
2. **The exclusivity rule:**
   - At most one active contract change at a time.
   - Check it against every other in-flight contract change before starting.
   - On collision, wait or surface the conflict; never proceed in parallel.
   - Make acquisition race-safe, because creating an ordinary issue, PR, or
     label is not an atomic check-and-register. Define a protocol that breaks a
     concurrent tie deterministically. Register first, then recheck with a fixed
     winner such as earliest entry or lowest ID, or have a designated authority
     grant the lock. So two simultaneous starts can neither both proceed nor
     both wait forever.
3. **Forge-visible enumeration** of in-flight contract changes: a marker on
   contract-bearing units, or their declared surface paths on a forge-visible
   work contract.
   - Register it before implementation begins, so a starting unit can check
     against every in-flight change.
   - A directly assigned unit whose contract would otherwise live only in the
     prompt registers a forge-visible entry first: an issue, a draft PR, or the
     project's claim mechanism.
   - Gate registration on available forge capability. Where an assigned agent
     lacks the tooling or permission to register, name a human or external
     registrar, or a stop-and-escalate, so no agent faces an impossible startup
     step.
4. **Registration lifecycle:** when an entry joins the active set, when it
   leaves it (normally on merge or close), and how a stale or abandoned entry is
   released or superseded. A registration with no defined release blocks the
   surface forever, or invites agents to bypass the lock by guessing it is dead.
5. **Ordering relief** when several planned units need the surface: an explicit
   dependency chain, or one combined leading contract change.

For shapes 3 through 5, keep long mechanics outside AGENTS.md. The project
document states relationship authority, work-unit boundaries, claim rules when
one exists, integration responsibility, and the capacity limit. AGENTS.md
carries only the compact record and a pointer to that document.

## §record

Place a coordination record in unmanaged, project-specific AGENTS.md content,
near the `Agent-setup profile:` line. Never place it inside a canonical managed
block. Use this fixed field list:

```markdown
### Coordination model

- **Current shape:** <shape or combination and supported concurrency width>
- **Evidence basis:** <one line naming the supporting evidence>
- **Detailed mechanics:** <project-doc pointer, required for shapes 3–5>
- **Reassess when:** <observable evidence that would justify change>
```

Record rules:

- **Omit the record for the safe serial baseline** unless the owner explicitly
  wants it stated. No record means serial work, not missing content.
- **For shape 2,** the **Detailed mechanics** field may point to
  repository-local work-contract documentation instead of a dedicated
  coordination document.
- **Keep an external work contract as evidence.** A tracker issue or other
  external work contract is not an editable mechanics target.
- **Never fill a field with a placeholder** graph, lane list, ownership map, or
  claim rule.

In update mode, detect the record and report whether all four fields are
present. Preserve it and all other unmanaged content verbatim, unless the owner
explicitly requests a field change. Do not reassess or rewrite an established
model as a side effect of syncing canonical sections. Topology reassessment is a
separate owner-assigned work unit, described in `SKILL.md` under "Coordination
reassessment" and detailed in §reassess.

## §reassess

Reassessment re-runs coordination discovery against current evidence. It does
not turn routine synchronization into policy analysis.

Begin with the existing record and detailed mechanics, when present, and any
stage record. If no coordination record exists, the observed starting model is
the safe serial baseline. If AGENTS.md itself is absent, analyze and report
only: init must establish the profile, canonical sections, and scaffolding
before any coordination record or project coordination document is created.

### Validate the Inputs

When AGENTS.md exists, validate its managed ranges before interpreting policy.
Then locate every apparent fixed-field coordination record, work-unit stage
record, and **Detailed mechanics** value. Apply this input-state table in order:

| Input                     | Accepted state                                                                                                               | Stop condition                                                                        |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Coordination record       | Zero, meaning the safe serial baseline, or one record.                                                                       | More than one record.                                                                 |
| Fixed coordination fields | One record: each of the four fixed fields once. Zero records: not applicable.                                                | A field in the one record is missing or repeated.                                     |
| Work-unit stage record    | Zero or one project-specific section; a section may hold several stages.                                                     | More than one stage section.                                                          |
| Stage layout              | One accepted legacy or child-heading layout (see Read the Stage Record); zero stage sections, not applicable.                | A mixed or ambiguous layout (see Read the Stage Record).                              |
| Stage fields              | In every accepted entry, the six exact fields, each once, non-empty (see Read the Stage Record).                             | In any entry, a field is missing, empty, or repeated.                                 |
| Placement                 | Every record range and mechanics line sits outside all managed ranges; with no record, the mechanics line is not applicable. | A record or mechanics line intersects a managed range.                                |
| Mechanics value           | A value that fits the recorded shape (see Classify the record below).                                                        | The value does not fit the shape, or a required local target is unsafe or unresolved. |

Read the table top to bottom. Every row through **Placement** inspects structure
and labels; none adopts a value as policy.

Classify the record:

- **No coordination record:** skip the field and mechanics rows, and use the
  safe serial baseline.
- **One record:** read **Current shape** only after the structural rows pass,
  then classify **Detailed mechanics** against the last row.
- **Shapes 3, 4, or 5 take precedence** over a composed shape 2 and require a
  safe local document.
- **A blank or explicit no-document mechanics value** is accepted only when the
  final shape is shape 1, shape 2, or both, and none of shapes 3, 4, or 5.
- **A local target** must be project-specific, not a canonical source or
  scaffold template. When it targets AGENTS.md, its whole section must also stay
  outside every managed range.

Handle an external work contract as read-only:

- **A shape-2 tracker issue or other external work contract** is read-only
  evidence, not an editable mechanics target.
- **Read it only when the source is available.** Otherwise report the
  unavailable evidence as uncertainty and continue.
- **In a composed shape it may supplement,** never replace, the local mechanics
  that shape 3, 4, or 5 requires.
- **Never include an external work-contract change** in the proposed diff.
- **Stop on every other unsafe, ambiguous, or unresolved state** before reading
  or modifying the record or target. Structurally valid markers do not make the
  content inside them project-specific.

Preflight a combined setup-and-reassessment request:

- **Run marker validation and the overwrite-risk part of Placement** before
  setup.
- **For adoption,** apply that check to both current managed ranges and the
  read-only sections adoption proposes to wrap.
- **Resolve each syntactically local mechanics target** only far enough to
  locate its range or file. Derive the ranges and files the requested setup
  proposes to rewrite.
- **A record, mechanics line, or local target** that intersects one of those
  locations stops both operations before setup can overwrite it.
- **Defer every other table row,** including mechanics-value and semantic target
  suitability, until the full reassessment after setup completes. A semantic
  policy failure outside the overwrite-risk locations stops that reassessment,
  not the requested safe setup.

### Read the Stage Record

The six exact stage labels are **Activation**, **Allowed mutations**,
**Required input**, **Durable output**, **Finish line**, and **Transition**.
Every accepted entry must carry each label once, as a bold field-label bullet
with a non-empty value.

A value is non-empty only when its rendered inline or continuation text, before
the next exact field-label bullet or heading, holds substantive policy. HTML
comments do not count. Placeholder-only text such as `TODO` or `TBD` is empty.

Three layouts are accepted:

- **Legacy stage-specific section:** require the six bullets directly in the
  section, once each, non-empty. Use its heading as the sole stage name. Treat
  descendant headings as content only when their subtrees hold no exact
  stage-field bullet. If a descendant subtree holds one, stop on the ambiguous
  mix of direct legacy fields and a possible child entry.
- **Generic container heading:** a heading such as `Stages`,
  `Work unit stages`, or `Work-unit stages` supplies no name. Accept its six
  complete direct fields as one unnamed legacy stage only when it has no
  descendant headings, and report the missing name as uncertainty. Do not invent
  one. Stop when direct field bullets appear alongside child headings, or a
  skipped-level heading appears without an immediate-child entry.
- **Immediate-child entries:** each unique heading begins one entry, and the
  prose before the first entry is shared guidance. Deeper headings within an
  entry belong to that entry.

Stop on any other ambiguous boundary, or when an immediate-child heading name
repeats.

Migrate a legacy record only with owner approval. When an owner asks to add a
sibling to a legacy direct-field record:

1. Propose the necessary structural migration and get approval first.
2. Name the existing stage with the owner's input when the section heading is
   generic. Create its immediate child heading. Move its six field bullets and
   continuation lines beneath that heading verbatim.
3. Classify every other direct line as shared pre-entry guidance or
   existing-stage content, and preserve its text and relative order verbatim
   within that scope.
4. Ask the owner to confirm each classification before adding only the requested
   sibling.

Without approval, leave the record unchanged.

### Gather the Evidence

Inspect these sources only when they are available, and identify each one in the
report:

- Architecture and recent architecture changes.
- Recent work units and PR history, including recurring boundaries and overlap.
- Issue dependencies and their stated meanings.
- Repeated path overlap or shared-surface collisions.
- Changes to shared contracts or generated surfaces.
- Intentional branch or PR stacking.
- Start-order, merge-order, and mutual-exclusion constraints.
- Documented manual scheduling friction, plus the people or agents available to
  review and integrate concurrent work.

Report unavailable sources and ambiguous meanings as uncertainty. Separate
observations from inferences, and cite the path, work unit, issue relation,
owner statement, or other available source behind every material finding. Never
infer coordination maturity from repository size, age, or directory layout
alone.

### Compare With the Evidence

Compare the current record and mechanics with the evidence. Look for stale
stream names and an obsolete integration spine or shared-contract bottleneck.
Look also for missing structure now supported by recurring evidence, and for an
over-modeled topology whose distinctions no longer guide real work. Also check
whether the record's **Reassess when** condition has become observable. A
trigger starts analysis only when the owner requests reassessment; it never
activates update mode or authorizes mutation.

Re-run §shapes and select the smallest safe shape supported now. The result may
keep the current model, add a capability, simplify it, or return to the safe
serial baseline. Use the same evidence rule for both upgrades and
simplifications. When sources conflict, prefer the simpler safe shape and report
the conflict. Apply §evidence's review and integration capacity cap to every
concurrency recommendation.

### Report and Propose

Present the effective model, evidence and uncertainty, detected drift,
recommended outcome, and next observable reassessment triggers.

- **Show an exact diff** for every proposed AGENTS.md or project-document change
  before editing, including any **Reassess when** field change.
- **Existing lane names and relationship meanings stay authoritative** until the
  owner explicitly approves a documented rename or reinterpretation.
- **Issue dependencies are read-only evidence,** never mutation proposals.
- **Remove an obsolete record or update its triggers only on owner approval** of
  that exact diff. Otherwise preserve it and all unrelated unmanaged content
  verbatim, and keep the triggers in the report.

## §freeside

Freeside's completed coordination change is a calibration example, not a
template. Its work history showed recurring work streams, a serialized
shared-contract chain, a designated integration role, and distinct start, merge,
stacking, and exclusion constraints. That evidence justified stable named
streams plus an integration spine and typed relations.

The portable lesson is the derivation: recurring history justified names,
shared-contract risk justified serialization, and observed integration needs
justified a spine. Do not copy Freeside's lane names, tracker vocabulary,
labels, or integration role into another project. Derive local terms only from
that project's evidence. See
[Freeside PR #801](https://github.com/freeside-ai/freeside/pull/801) for the
project-specific result.
