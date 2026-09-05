# Project-Specific Sections

Use this reference while gathering the project-specific AGENTS.md content
during init or adoption, and in update mode when checking an existing
coordination or work-unit stage record.

## §section-order

```text
1. Header/Intro                          (project-specific)
2. Decision Notes                        (managed: devlog;
                                          note-keeping profiles only)
3. Default Agent Finish Line             (managed: finish-line)
4. Context Discipline                    (managed: context)
5. Writing for Humans                    (managed: communication)
6. Build, Test, Run                      (project-specific)
7. [Other project-specific sections]     (project-specific)
8. Branches                              (managed: branches)
9. Pull Requests + Handing Off the PR    (managed: pull-requests)
10. Commits                              (managed: commits)
11. Definition of Done for an Increment  (managed: done)
```

## §guidance

During init or approved adoption, inspect project evidence before asking for
facts. Use supported facts in the proposed guidance without asking the owner
to repeat them. Ask the owner about missing facts and conflicting sources
before writing; name the sources when asking about a conflict. Profile and
policy choices still belong to the owner. Ordinary updates
preserve existing project-specific guidance.

If the project is too early for these decisions (fresh repo, no code yet),
write the canonical sections and scaffolding, leave placeholders for
project-specific sections (a TODO comment noting what to fill in), and move on.
The user can re-run in update mode once the project has shape.

Keep the project-specific payload lean: AGENTS.md is loaded whole into every
agent session, so its sections should hold rules that apply to most sessions.
Reference material (a format spec, API detail, a long gotcha catalog) belongs in
`docs/` behind a one-line pointer that names when to read it ("before editing
the parser, read `docs/format-spec.md`"), not inlined.

### Header/Intro

Write a one-paragraph intro: project name, pointer to the spec document
(usually README.md), and a sentence on what AGENTS.md covers. Also write
the canonical file rule into AGENTS.md (intro or CI subsection):
"CLAUDE.md is a pointer that imports AGENTS.md; edit AGENTS.md, never
the pointer."

### Build, Test, Run

- Detect language and build system from project files. If no code
  exists yet, leave this section as a placeholder and skip to
  scaffolding.
- Inspect manifests, local scripts or build targets, runtime pins, CI
  definitions, and project docs for build, test, run, lint, and format
  commands. Also gather targets, entry points, runtime versions, CI paths,
  and enforced constraints (e.g., "no force unwraps", "strict mode").
- Verify that command definitions and referenced paths exist and that the
  sources agree. Use file inspection and known non-mutating queries; a version
  or target-listing command qualifies only when its behavior is known to be
  non-mutating. Don't run full builds or tests merely to gather these facts.
- Distinguish facts verified from source from commands successfully executed.
  Report execution gaps without treating source-verified command definitions
  as missing facts.
- **Lint and format are required, not optional.** The workflow conventions
  depend on them: definition of done expects a successful build, passing
  tests, and clean lint and formatting; commits assume CI catches unformatted
  code. Use the tools found above. If none are established, help the user
  choose and configure one appropriate for the language (e.g., `swift-format`
  for Swift, `prettier` + `eslint` for JS/TS, `black` + `ruff` for Python,
  `rustfmt` + `clippy` for Rust). The goal is a single command that can lint
  and a single command that can format, both runnable in CI.

### Architecture Invariants (Optional)

- Ask: "What rules protect this codebase's structural integrity?"
- Each invariant states what it prevents and how it's enforced.
- Number them for stable cross-references.

### Conventions & Gotchas (Optional)

- Ask: "What non-obvious patterns or footguns should a new contributor know?"
- Framework traps, naming conventions, testing patterns, runtime quirks.

### Definition of Done: Project Checks

The managed `done` section includes a tool-agnostic expectation that the
build succeeds, tests pass, and lint and formatting are clean, followed by
a placeholder for project-specific verification steps. During init, fill the
`<!-- agents-md:project:done-checks -->` block with the project's actual
verification commands (build command, test command, lint/format command,
visual check method, schema round-trip if applicable).

## §work-contracts

Use these defaults: direct user-assigned work needs no issue; concurrent,
backlog, or cross-session work uses a tracker issue; agents do not self-select;
and neither an issue nor a claim authorizes work.

During init or adoption:

- Ask where persistent work contracts live on the project's forge.
- Ask whether the project separates planning, implementation, review, or
  integration into distinct stages with handoffs. Default to the single
  implementation workflow; record stages only when those handoffs are
  demonstrated or explicitly requested.
- Gather the available coordination evidence: plans, existing code,
  architecture documents, work-unit and PR history, and owner expectations.
  Treat a plan as evidence, never authority. Use
  `references/coordination-discovery.md` §evidence to grade the sources and
  `references/coordination-discovery.md` §shapes to choose the smallest model
  the evidence supports.
- With neither a credible plan nor a demonstrated coordination need, keep the
  safe serial baseline. Treat a speculative, uncorroborated plan the same way.
  Omit the coordination record unless the owner explicitly requests the
  fixed-field record from `references/coordination-discovery.md` §record; when
  requested, record the safe serial shape. No record means serial work, not
  missing content. Do not invent a lane, ownership map, graph, claim mechanism,
  or placeholder.
- When evidence supports a richer model, write the fixed-field record from
  `references/coordination-discovery.md` §record in unmanaged content near the
  `Agent-setup profile:` line. For typed relations, stable named streams, or an
  integration spine, keep the long mechanics in project documentation and
  point to it from the record.
- Keep shared-contract serialization separate from component ownership. When
  needed, distinguish start order, merge order, intentional stacking, and
  mutual exclusion, and cap recommended concurrency at realistic review and
  integration capacity. Shared-contract serialization means repo-wide mutual
  exclusion on the surface, not per-unit ordering; define the mechanics per
  shape 5 in `references/coordination-discovery.md` §shapes.
- If concurrency is expected and the project already defines a forge-visible
  claim mechanism, record how abandoned or stale claims are released or
  superseded. Never invent one silently; a claim advertises occupancy only.
- Use `references/coordination-discovery.md` §freeside only to calibrate the
  evidence required for named streams and an integration spine. Never copy its
  lane names or project vocabulary as defaults.
- Ask whether an explicit project-specific policy permits agent
  self-selection. Without one, self-selection stays disabled.

In update mode, detect and report whether an existing coordination record has
all four fields. Preserve it as unmanaged content unless the owner explicitly
requests a field change. Do not reassess an established model while syncing
canonical sections; topology reassessment is a separate owner-assigned work
unit under "Coordination Reassessment".

## §stages

When a project adopts distinct stages, record them in an unmanaged,
project-specific AGENTS.md section near the `Agent-setup profile:` line. That
section is one work-unit stage record and may contain several stage definitions
with the fields below; the individual stage entries are not separate records.
No stage record means the default single implementation workflow, not missing
content. Planning is optional; never create a planning stage merely because the
project uses tracker issues.

For new or revised policy:

- Give every stage definition one immediate child heading under the
  stage-record section. The unique child-heading text is the stage name, and
  its entry ends at the next immediate child heading or the stage-record
  section's end.
- Put shared record guidance before the first child heading so it cannot be
  mistaken for a stage.
- Under each stage heading, use each exact bold field-label bullet below once
  with a non-empty value. A value is non-empty only when its rendered inline or
  continuation text before the next exact field-label bullet or heading contains
  substantive policy. HTML comments do not count, and placeholder-only text such
  as `TODO` or `TBD` is empty.

Preserve a legacy single-stage record when each of the six fields appears
directly in a stage-specific section exactly once with a non-empty value. That
section heading is the sole stage's name, and all descendant headings are
content within that stage only when their subtrees contain no exact stage-field
bullet. If a descendant subtree does contain one, stop on an ambiguous mix of
direct legacy fields and a possible child entry.

A generic container heading,
such as `Stages`, `Work unit stages`, or `Work-unit stages`, does not supply a
name. Accept its six complete direct fields as one unnamed legacy stage only
when it has no descendant headings, and report the missing name as uncertainty.
Do not require an unrelated migration before update or reassessment.

Under a generic container, direct field bullets mixed with child headings have
ambiguous boundaries and need owner repair, as does a skipped-level heading
without an immediate child entry. A missing, empty, repeated, or duplicate-name
entry also needs repair. Deeper headings inside an immediate-child entry belong
to that entry. Never combine fields across entries to make one look complete.

For each adopted stage, record:

- **Activation:** the explicit assignment or event that begins the stage.
- **Allowed mutations:** the state the stage may change.
- **Required input:** the durable state that must exist before work begins.
- **Durable output:** the artifact that carries the result beyond the current
  chat or session.
- **Finish line:** the condition that completes the stage.
- **Transition:** how the finished output is handed to the next stage.

Use a tracker issue for a sequential handoff between agents or sessions, even
when it occurs within one short session. Keep its input and output in the issue
and its comments, never only in transient chat context. A completed plan,
issue, claim, or satisfied dependency does not authorize the next stage;
explicit assignment still does unless the project records a narrower
activation rule.

Adopt stages incrementally. A later update may add review or integration to an
existing planning and implementation record without changing the stages the
owner did not ask to revise. In update mode, detect and report whether an
existing record is either one complete legacy direct-field entry or gives every
uniquely named child-heading entry each of the six fields exactly once with a
non-empty value. Preserve it as unmanaged project content except for
owner-requested edits.

Adding a sibling stage to a legacy direct-field record requires a structural
migration:

- Propose an exact diff, ask the owner to name the existing stage when its
  container heading is generic, and obtain approval before creating that child
  heading and moving the existing six field bullets and their continuation lines
  beneath it verbatim.
- Classify every other direct line in the proposal as either shared pre-entry
  guidance or existing-stage content, preserve its text and relative order
  verbatim in that scope, and ask the owner to confirm each classification. Then
  add only the requested sibling.
- Without that approval, leave the record unchanged. Leave an absent record
  alone unless the owner explicitly requests stage adoption; then create only
  the requested stage definitions. Never fabricate a stage record or move it
  inside a managed block.
