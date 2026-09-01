---
name: agent-setup
description: >-
  Make a project agent-ready: create or update AGENTS.md with managed canonical
  workflow sections under one of three profiles (Standard, Decision-log,
  High-assurance), scaffold the CLAUDE.md pointer, CONTRIBUTING.md, PR
  template, the docs/agent-workflow.md reference the managed sections point
  at, and (under the note-keeping profiles) the decision-note devlog, and
  audit standard files and repo settings. Use when the user asks to "set
  up this project for agents", "initialize AGENTS.md", "create AGENTS.md",
  "update AGENTS.md", "sync workflow sections", "check agent setup",
  "bootstrap devlog", "make this project agent-ready", asks to add a devlog,
  decision records, PR template, or CONTRIBUTING.md to a repo, or discusses
  managing shared development conventions across projects. Also use when the
  user asks to reassess coordination, check the parallel-work setup, or
  simplify obsolete lanes.
---

# Agent Setup

Make a project agent-ready. Set up AGENTS.md with the canonical workflow
sections, a CLAUDE.md pointer, a PR template, the `docs/agent-workflow.md`
reference those sections point at, and repo scaffolding. Under the note-keeping
profiles, also set up a decision-note devlog (see Profiles).

Eight canonical sections encode the owner's workflow conventions and are
managed across projects. Project-specific sections (build/test/run,
architecture invariants, conventions) are guided interactively during init and
left untouched during updates.

## Detecting Mode

Check the request before the file state, then pick a mode from this table:

| Situation (check top to bottom)                            | Mode                             |
| ---------------------------------------------------------- | -------------------------------- |
| Request asks only to reassess coordination, not to set up  | Reassessment                     |
| Request asks for both setup and reassessment               | Combined (see below)             |
| No AGENTS.md in the project root                           | Init                             |
| AGENTS.md has exact `agents-md:managed:` markers           | Update                           |
| AGENTS.md has marker remnants but no exact managed markers | Stop and report (see below)      |
| AGENTS.md has no markers and no remnants                   | Adopt or leave unmanaged (below) |

An explicit owner request drives Reassessment, regardless of the AGENTS.md file
state: reassess whether the coordination model still fits, check the
parallel-work setup, or simplify obsolete lanes. Enter Reassessment only from
that request, never because a recorded reassessment trigger appears satisfied or
an ordinary init, adoption, or update discovers new evidence.

For a request that asks for both setup and reassessment, read
`references/modes.md` §combined and follow it before setup mutates anything.
When AGENTS.md carries marker remnants but no exact managed markers, read
`references/modes.md` §remnants: stop and report them; don't offer adoption.
When AGENTS.md exists without markers, ask whether to adopt management or
leave the file unmanaged. To adopt, read `references/modes.md` §adopt and
follow it.

## Profiles

Three setups differ only in whether the project keeps decision notes. Recommend
Standard unless the project has a demonstrated need for durable decision
records. A noninteractive run with no stated preference gets Standard. A user
who explicitly asks for a devlog gets Decision-log, or High-assurance when they
also name change classes that must always carry a note.

- **Standard.** PRs, commits, issues, and current documentation carry the
  record. No `devlog/` scaffold and no managed `devlog` block. That absence is
  the profile, not drift, an opt-out, or a gap: update mode neither offers to
  insert the block nor counts it as missing content, and the comparator's
  `missing: devlog` line is the expected output.
- **Decision-log.** Adds the managed `devlog` block and the `devlog/README.md`
  scaffold (selective decision notes).
- **High-assurance.** Decision-log plus a short project-specific list of change
  classes for which a note is mandatory. Gather that concrete list from the
  user when this profile is chosen. A noninteractive run that names
  High-assurance without supplying the list falls back to Decision-log and
  flags the gap.

Record the choice in an unmanaged section of the project's AGENTS.md, as a line
containing `Agent-setup profile:` and the profile name, with the High-assurance
mandatory-note list beside it. Update mode reads this line. It's the profile's
only record (no separate config or metadata file).

## Init Mode

1. Read the project to understand language, build system, test framework, and
   directory structure.
2. Read `references/canonical-sections.md` for the exact managed-section text.
3. Choose a profile with the user (see "Profiles"). Present the three
   explicitly and recommend Standard. Apply the Profiles defaults when the run
   is noninteractive or the user has already stated a preference.
4. Gather the project-specific sections interactively. Read
   `references/project-sections.md` §guidance for the per-section questions,
   `references/project-sections.md` §work-contracts for coordination
   discovery, and `references/project-sections.md` §stages for optional
   work-unit stages, and follow them. The conventional order in
   `references/project-sections.md` §section-order interleaves these sections
   with the managed ones, so collect this content, or decide on placeholders,
   before writing.
5. Settle `docs/agent-workflow.md`, then write AGENTS.md once and verify the
   write. Read `references/managed-blocks.md` §init-write and follow it.
6. Create the scaffolding files listed in `references/managed-blocks.md`
   §scaffold-files. For any that already exist, apply that section's drift
   rules; never overwrite silently.
7. Audit standard project files: read `references/audit.md` §standard-files,
   then report which are present, which are missing, and suggest creating any
   that apply. Don't create them (content is project-specific); just flag.
   Also check for an automated-reviewer record (see "Automated Reviewer
   Record" below).
8. Check the settings in `references/audit.md` §repo-settings and
   `references/audit.md` §required-checks, and offer to align them. Report
   any that can't be checked or set (wrong permissions, non-GitHub forge).
9. Summarize what was created, what the user should fill in, which standard
   files are missing, and which repo settings need attention.

## Update Mode

1. Read `references/canonical-sections.md` for the current canonical text.
2. Read the project's AGENTS.md.
3. Validate the markers before touching anything. Read
   `references/managed-blocks.md` §marker-validation and check every rule
   there. On any malformation, stop and report it; never refresh. Nothing
   below reads the file for meaning until its boundaries are trusted.
4. Discover the profile: look for the `Agent-setup profile:` line, then read
   `references/managed-blocks.md` §profile-discovery and follow it. Never
   switch a recorded profile without the user's explicit choice.
5. Protect the reviewer record before refreshing. If an automated-reviewer
   record appears inside a managed block, resolve its location first (see
   "Automated Reviewer Record").
6. For each managed block:
   - Extract the content between markers.
   - Compare against the canonical version for that KEY. For `done`, exclude the
     nested `project:done-checks` block from both sides (matching its exact
     marker lines only, per step 3) and compare only the text around it; never
     modify the nested block.
   - If different, show the diff and ask whether to update. Blocks that carry
     `docs/agent-workflow.md` `§slug` pointers depend on that file existing and
     matching, so settle it in the same decision (see step 9).
7. Leave all unmarked (project-specific) content untouched, except for
   owner-requested creation or modification of a coordination model or work-unit
   stage record. Within either record, create or change only the requested
   fields or stages; preserve every unrequested field or stage and all unrelated
   unmarked content verbatim. The only structural exception is an owner-approved
   legacy-stage migration described in `references/project-sections.md`
   §stages; it may relocate an unrequested stage's existing lines without
   altering them. See `references/project-sections.md` §work-contracts for the
   coordination record.
8. If a canonical section is missing entirely, offer to insert it at its
   conventional position. A section carrying `docs/agent-workflow.md` `§slug`
   pointers settles that file in the same decision (see step 9). Under Standard,
   `devlog` is not such a gap (see Profiles).
9. Check scaffolding files: CLAUDE.md, CONTRIBUTING.md, PR template,
   docs/agent-workflow.md, and, under a note-keeping profile, devlog/README.md.
   Offer to create any that are missing. For any that exist, compare against
   the templates in `references/scaffolding.md` and, on drift, show the diff
   and offer to refresh. Before offering, read
   `references/managed-blocks.md` §scaffold-files and apply its drift rules,
   including the `docs/agent-workflow.md` exception. These files carry no
   markers and may hold local customizations, so never overwrite silently;
   let the user decide per file.
10. Audit standard project files (`references/audit.md` §standard-files) and
    flag any newly missing. Also check the automated-reviewer record, any
    coordination model, and any optional work-unit stage record (see
    "Automated Reviewer Record", `references/project-sections.md`
    §work-contracts, and `references/project-sections.md` §stages).
11. Check the settings in `references/audit.md` §repo-settings and
    `references/audit.md` §required-checks, and offer to align any that have
    drifted.

Where the running agent can execute shell scripts, run this skill's
`scripts/compare-managed-blocks.sh` for the mechanical parts of steps 3 and 6.
Read `references/managed-blocks.md` §comparator for the invocation, its
working-directory rule, and when to pass `--require-all`. Without shell
access, follow the steps manually as written.

## Coordination Reassessment

Run this mode only for the explicit owner request described under "Detecting
Mode". It analyzes the effective project-specific coordination model and may
propose a change, but it never edits the model as part of ordinary init,
adoption, or managed-section update. Read `references/modes.md` §reassessment
and follow its steps in order.

## Managed Section Markers

Each canonical section is wrapped in HTML comment markers. Keys: `devlog`,
`finish-line`, `context`, `communication`, `branches`, `pull-requests`,
`commits`, `done`. Before writing or wrapping a block, read
`references/managed-blocks.md` §markers for the marker format, the opt-out
rule, and the `communication` section's research basis.

## Automated Reviewer Record

The managed `pull-requests` section tells agents to record a noticed
automated reviewer so a review-watch can resolve who to wait on without
re-detecting. During init and update, check whether the project carries such
a record: read `references/managed-blocks.md` §reviewer-record-audit and
follow it. Treat this as **detect → report, never fabricate**. A managed-block
sync must not delete or rewrite the record silently.
