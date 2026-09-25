# Tracker Issue Format

Every tracker issue takes this shape: a wave tracker, a feature tracker, or a
backlog tracker. The sections run in the order the owner reads them: the
dependency diagram most often, then what is startable now, the unit list, the
exit gate, the description, and the planning notes least. Only two parts are
wave-specific: the wave title rule and the **Gate** bullet. Everything else
applies to every tracker. Wave planning, work-unit planning, and merge cleanup
read this file; the project's AGENTS.md cites it wherever it describes
trackers instead of restating the shape.

## title

- Title a wave tracker `Wave N: <Name>`, such as `Wave 3: Sync Rebuild`.
  Tooling finds a wave tracker by its milestone and the `tracker` label, never
  by title text.
- Title a feature or backlog tracker by its subject.

## intro

Open with one bold sentence that names the tracker and its scope. Then add
labeled bullets, one line each. The project chooses which of these to carry:

- **Goal:** the goal issue.
- **Gate:** the milestone or exit gate, linked into the plan document (wave
  trackers only).
- **Plan:** the plan section, linked.
- **Safety:** what stays untouched until the gate holds.

Keep the sentence about the page being derived out of the intro; it belongs in
Notes.

## status

`## Status` opens with a Mermaid `flowchart LR`:

- Draw the transitive reduction of the `starts-after` edges. Leave out an edge
  that another path already implies.
- Draw `-.->` for a soft dependency.
- Draw `==>` thick arrows along the critical path.
- Draw `[[ ]]` double-bordered nodes for merged units.
- Give class `startable` (green outline) to an open unit whose prerequisites
  have all merged and that no fence holds. A claim or an open PR doesn't
  remove the class; only the unit's merge does.
- Give class `contract` (orange fill) to a contract unit.
- Give class `owner` (grey dashed) to an owner-run or needs-human unit.
- Give class `fenced` (dashed outline) to an externally fenced unit. A fenced
  unit is not startable until the fence lifts, whatever its prerequisites.
- Label each node `#N` plus three to five words.

Under the diagram, put this one caption line, verbatim:

`**Legend:** thick arrow critical path · arrow starts-after · double border merged · green outline startable now · orange contract · grey dashed owner-run.`

Then add labeled bullets:

- **Startable now:** always present, as `#N (lane, contract), #M (lane)`.
  The parenthetical carries only the qualifiers that apply: the unit's
  primary lane when the project has lanes, and `contract` for a contract
  unit. A project without lanes writes `#N (contract)` or a bare `#N`. A
  unit stays listed until its PR merges. When no unit is startable, keep the
  bullet and state why in a few words, such as `all units merged` or
  `every open unit waits on #N`. This is the one bullet that carries an empty
  value.
- **Owner:** only when the owner holds something.
- **Fenced:** or **Blocked:** only when non-empty.

Write no "none" line. A project may add its own labeled bullet here; the shared
format defines only these.

## units

`## Units` holds bare task-list lines, `- [ ] #N`, with nothing after the
number. When the project has lanes, group them under `### lane:<name>`
subheads by the unit's primary lane, its first lane label, and put owner-run
units under `### Owner-run`. A project without lanes uses one flat list, or
groups by whatever its coordination document names. GitHub renders the issue
title and the open or closed icon from a bare reference, so a closed issue
beside an unticked box shows that merge cleanup hasn't run. Put no title and
no dependency text on the line.

## exit

`## Exit` holds the tracker-level gate only: three to six checklist bullets the
owner ticks at close, each ending with `Evidence: #N`, the unit whose merge
supplies the proof, or `Evidence: #N, then #M` when the proof lands in steps.
Per-unit exit criteria stay off the tracker; each unit
issue's acceptance section owns them.

## notes

`## Notes` holds the planning notes inside a collapsed `<details>` block whose
`<summary>` carries the planning date. The first note states that the page is
derived. It says that each unit issue's Dependencies field is the authority,
and that the diagram is a transitive reduction, so an issue may list a
prerequisite the diagram implies through another path. It also says that merge
cleanup repairs the page in the same operation as any dependency change.

## refresh

At merge, cleanup does this and nothing more:

1. Tick the unit's line under Units.
2. Give its node the double border and remove it from the `startable` class.
3. Add `startable` to every open, unfenced unit whose prerequisites have now
   all merged.
4. Rewrite the **Startable now** bullet.

The diagram's edges never change at merge. Never edit a closed tracker.

## style

- Keep bold lead-ins on bullets in sentence case; only real headings are
  title case.
- Leave out what the old shape carried: per-unit exit criteria and prose
  implementation order (serial chains, critical-path narrative, "when #N
  merges" text). Also gone: a dash followed by `deps:` on a unit line, a
  "Prerequisites (needs human)" section, any "none" line, and a "Mergeable
  next" bullet. The tracker carries start order only.

## template

Replace the angle-bracket text. Delete an optional bullet rather than writing
"none". For a wave tracker the bold name is `Wave <N>: <Name>`; a feature or
backlog tracker names its subject and drops the **Gate** bullet. A project
without lanes drops the `### lane:<name>` subhead and the `<lane>` qualifier.

````markdown
**<Tracker name>.** <One sentence naming the scope.>

- **Goal:** #<G>, <what it delivers>.
- **Gate:** [<milestone or gate>](<plan link>), <why it matters>.
- **Plan:** [<plan section>](<plan link>).
- **Safety:** <what stays untouched until the gate holds>.

## Status

```mermaid
flowchart LR
    i<A>[["#<A> <three to five words>"]]
    i<B>["#<B> <three to five words>"]
    i<C>["#<C> <three to five words>"]
    i<A> ==> i<B>
    i<B> ==> i<C>
    classDef contract fill:#fde2c8,stroke:#c2410c,color:#000
    classDef owner fill:#e5e7eb,stroke:#6b7280,stroke-dasharray:5 5,color:#000
    classDef fenced stroke-dasharray:5 5
    classDef startable stroke:#15803d,stroke-width:3px
    class i<B> contract
    class i<C> owner
    class i<B> startable
```

**Legend:** thick arrow critical path · arrow starts-after · double border merged · green outline startable now · orange contract · grey dashed owner-run.

- **Startable now:** #<B> (<lane>, contract).
- **Owner:** #<C> is owner-run.

## Units

### lane:<name>

- [x] #<A>
- [ ] #<B>

### Owner-run

- [ ] #<C>

## Exit

<Tracker name> closes when every unit above is merged and the owner ticks
these:

- [ ] <Observable outcome.> Evidence: #<C>.
- [ ] <Observable outcome.> Evidence: #<B>.
- [ ] <Observable outcome.> Evidence: #<A>, then #<C>.

## Notes

<details>
<summary>Planning notes (<YYYY-MM-DD>)</summary>

- **This page is derived.** Each unit issue's Dependencies field is the
  authority; the diagram draws the transitive reduction of its `starts-after`
  edges, so an issue may list a prerequisite the diagram implies through
  another path. Merge cleanup repairs this page in the same operation as any
  dependency change.
- **<Decision the plan made.>** <Why, in one or two sentences.>

</details>
````
