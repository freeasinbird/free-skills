---
name: agent-setup
description: >-
  Make a project agent-ready: create or update AGENTS.md with managed canonical
  workflow sections under one of three profiles (Standard, Decision-log,
  High-assurance), scaffold the CLAUDE.md pointer, CONTRIBUTING.md, PR
  template, and (under the note-keeping profiles) the decision-note devlog,
  and audit standard files and repo settings. Use when the user asks to "set
  up this project for agents", "initialize AGENTS.md", "create AGENTS.md",
  "update AGENTS.md", "sync workflow sections", "check agent setup",
  "bootstrap devlog", "make this project agent-ready", asks to add a devlog,
  decision records, PR template, or CONTRIBUTING.md to a repo, or discusses
  managing shared development conventions across projects.
---

# Agent Setup

Ensure a project is agent-ready: AGENTS.md with canonical workflow
sections, CLAUDE.md pointer, PR template, and repo scaffolding, plus a
decision-note devlog under the note-keeping profiles (see Profiles).
Eight canonical sections encode the owner's workflow conventions and
are managed across projects; project-specific sections (build/test/run,
architecture invariants, conventions) are guided interactively during
init and left untouched during updates.

## Detecting mode

- No AGENTS.md in the project root → **Init mode**
- AGENTS.md exists with `<!-- agents-md:managed:` markers → **Update mode**
- AGENTS.md exists with no exact managed markers but with marker
  remnants → stop and report them; don't offer adoption. A remnant is
  either a lookalike of the managed or the nested `project:done-checks`
  marker (update-mode step 3's malformation rule: comment lines that
  resemble either marker in spacing, case, or indentation, or carry its
  text inside a longer line), or any nested `project:done-checks`
  markers other than exactly one correctly ordered pair: a lone opener
  or closer, a duplicate, a close before its open. Wrapping sections
  around malformed remnants leaves a partially adopted file that only
  fails later, so the user should fix or remove them first. One exact,
  correctly ordered nested pair with no managed `done` block is not a
  remnant: that is the documented opt-out (see "Managed section
  markers"), so it doesn't trigger this stop, and such a file falls to
  the adoption bullet below.
- AGENTS.md exists without markers → ask whether to adopt management or
  leave unmanaged. To adopt: match sections to canonical keys by heading,
  wrap each match's existing text as-is in markers, then gather the
  project-specific information from init step 4 without overwriting existing
  unmarked guidance. This includes coordination discovery and preserves any
  existing coordination or stage record under the update-mode rules. Then run
  the update-mode comparison so the user sees any canonical divergence as a
  diff.
  One exception to as-is: when wrapping a matched `done` section, also
  wrap its existing project checks in the nested
  `<!-- agents-md:project:done-checks -->` markers (text unchanged);
  update-mode validation requires the nested pair inside a managed
  `done` block, so a bare wrap would dead-end the adoption. Where an
  exact nested pair is already present (the opt-out routed here by the
  bullet above), keep it as it stands and wrap the managed `done` block
  around it; adding a second pair fails that same validation.

## Profiles

Three setups, differing only in whether the project keeps decision
notes. Recommend Standard unless the project has a demonstrated need
for durable decision records; a noninteractive run with no stated
preference gets Standard. A user who explicitly asks for a devlog gets
Decision-log, or High-assurance when they also name change classes
that must always carry a note.

- **Standard**: PRs, commits, issues, and current documentation carry
  the record. No `devlog/` scaffold and no managed `devlog` block. That
  absence is the profile, not drift, an opt-out, or a gap: update mode
  neither offers to insert the block nor counts it as missing content,
  and the comparator's `missing: devlog` line is the expected output.
- **Decision-log**: adds the managed `devlog` block and the
  `devlog/README.md` scaffold (selective decision notes).
- **High-assurance**: Decision-log plus a short project-specific list
  of change classes for which a note is mandatory; gather that
  concrete list from the user when this profile is chosen. A
  noninteractive run that names High-assurance without supplying the
  list falls back to Decision-log and flags the gap.

Record the choice in an unmanaged section of the project's AGENTS.md
as a line containing `Agent-setup profile:` and the profile name, with
the High-assurance mandatory-note list beside it. Update mode reads
this line; it is the profile's only record (no separate config or
metadata file).

## Init mode

1. Read the project to understand language, build system, test framework,
   and directory structure.
2. Read `references/canonical-sections.md` for exact managed-section text.
3. Choose a profile with the user (see "Profiles" above): present the
   three explicitly and recommend Standard; apply the Profiles defaults
   when the run is noninteractive or the user has already stated a
   preference.
4. Gather the project-specific sections interactively; see
   "Project-specific section guidance" below. The conventional order
   interleaves them with the managed sections, so collect this content
   (or decide on placeholders) before writing.
5. Write AGENTS.md once, following the conventional section order (see
   below): each canonical section wrapped in its markers (the `devlog`
   block only under Decision-log or High-assurance), project-specific
   content or placeholders in place, and the `Agent-setup profile:`
   line (plus the High-assurance mandatory-note list and any justified
   coordination or work-unit stage record) in an unmanaged section.

   Verify that write before moving on: init pastes the managed blocks by
   hand, and every comparison update mode makes depends on their
   byte-exactness. Where the running agent can execute shell scripts, run
   the comparator described under "Update mode". Under Decision-log or
   High-assurance, pass `--require-all` and require exit 0. Under
   Standard, drop the flag: the run must exit 0 with `missing: devlog`
   as its only missing line and every other key reporting `ok:`. Without
   shell access, make the comparator's comparison by hand: read each
   managed block's whole text back against
   `references/canonical-sections.md`, excluding the nested
   `project:done-checks` payload from both sides as step 6 does. A
   dropped or reworded sentence inside a block is exactly the drift this
   check exists to catch; the project's own checks in the nested block
   are not drift.

6. Create scaffolding files:
   - `devlog/README.md`: content in `references/scaffolding.md`
     §devlog-readme (Decision-log and High-assurance profiles only)
   - `.github/pull_request_template.md`: content in `references/scaffolding.md` §pr-template
   - `CONTRIBUTING.md`: content in `references/scaffolding.md` §contributing
   - `CLAUDE.md`: content in `references/scaffolding.md` §claude-md

   For any that already exist, don't recreate them: compare against the
   template and, on drift, show the diff and offer to refresh (the same
   rule as update-mode step 9); never overwrite silently.

7. Audit standard project files; see "Standard project files" below.
   Report which are present, which are missing, and suggest creating any
   that apply. Don't create them (content is project-specific); just flag.
   Also check for an automated-reviewer record; see "Automated reviewer
   record" below.
8. Check the settings listed under "Repo settings" below and offer to align
   them. Report any that can't be checked or set (wrong permissions,
   non-GitHub forge).
9. Summarize what was created, what the user should fill in, which
   standard files are missing, and which repo settings need attention.

## Update mode

1. Read `references/canonical-sections.md` for current canonical text.
2. Read the project's AGENTS.md.
3. Validate the markers before touching anything: every opening
   `<!-- agents-md:managed:KEY -->` has a matching close after it, no KEY
   appears twice, every KEY is a known one, no two blocks overlap (a
   block that opens inside another's range crosses a boundary even
   though both keys pair correctly), any line that merely
   resembles a managed marker or the nested `project:done-checks` marker
   (indentation, case, or spacing variants, a mistyped or unknown key,
   or a marker's text carried inside a longer line) is treated
   as a malformation, the nested `project:done-checks` markers are
   either absent or exactly one correctly ordered pair, and, when a
   managed `done` block is present, that pair sits inside it. (One exact
   pair with no managed `done` block is the documented opt-out, not a
   malformation; see "Managed section markers".) On any malformation, stop and report it; never refresh
   (a broken boundary would pull project-specific text into the managed
   region, and the refresh would delete it). Nothing below reads the file
   for meaning until its boundaries are trusted, so this precedes the
   profile discovery that can negotiate a migration with the user.
4. Discover the profile: look for the `Agent-setup profile:` line.
   - Recorded: preserve it and scope the steps below to it (see
     Profiles for what Standard's absent `devlog` block means); never
     switch a recorded profile without the user's explicit choice.
   - Absent, but a managed `devlog` block, a `devlog/` scaffold, or a
     session-bookend protocol exists: a legacy setup. Offer migration
     to Decision-log (or High-assurance when the user names mandatory
     change classes), showing the resulting managed-block and scaffold
     diffs before applying anything. On acceptance, the block and
     scaffold changes and the new profile line land through the normal
     steps below; on decline, change and record nothing (the offer
     recurs on the next update run). Never delete an existing devlog or
     switch the project to Standard without the user's explicit choice;
     the historical entries stay untouched either way. When migrating a
     queue-era devlog, walk the apparently open queue items
     (`## To promote` bullets, deferrals,
     needs-human notes without a drain record) once, in prose with the
     user: already resolved or promoted needs nothing; still
     actionable gets an existing or new tracker issue linked; only
     conditionally relevant stays as a historical observation. Never
     automate this by parsing or mutating old entries.
   - Absent with no devlog anywhere: treat as Standard and offer to
     record the line.
5. Protect the reviewer record before refreshing: if an automated-reviewer
   record appears inside a managed block, resolve its location first; see
   "Automated reviewer record".
6. For each managed block:
   - Extract the content between markers.
   - Compare against the canonical version for that KEY. For `done`,
     exclude the nested `project:done-checks` block from both sides
     (matching its exact marker lines only, per step 3) and compare only
     the text around it; never modify the nested block.
   - If different, show the diff and ask whether to update.
7. Leave all unmarked (project-specific) content untouched, except for
   owner-requested creation or modification of a coordination model or
   work-unit stage record. Within either record, create or change only the
   requested fields or stages; preserve every unrequested field or stage and
   all unrelated unmarked content verbatim. See "Work contracts and
   coordination" and "Work-unit stages (optional)".
8. If a canonical section is missing entirely, offer to insert it at its
   conventional position; under Standard, `devlog` is not such a gap
   (see Profiles).
9. Check scaffolding files (CLAUDE.md, CONTRIBUTING.md, PR template,
   and, under a note-keeping profile, devlog/README.md): offer to
   create any that are missing; for any that exist, compare against the
   templates in `references/scaffolding.md` and, on drift, show the
   diff and offer to refresh. These files carry no markers and may hold
   local customizations, so never overwrite silently; let the user
   decide per file. (Watch `devlog/README.md` especially: the managed
   `devlog` block points to it as the protocol, and a stale copy
   contradicts a freshly-synced block.)

   An existing file that holds substantive content the template doesn't
   is not drift to refresh: refreshing it would delete material the
   project relies on. Report the difference and leave such a file as it
   stands unless the user asks otherwise. `CONTRIBUTING.md` and the PR
   template are meant to be customized, so a fuller local copy is the
   project's own documentation, not drift to reduce. `CLAUDE.md` is the
   one file that gets a further offer, because its template is a
   five-line pointer to AGENTS.md as the single source, so any CLAUDE.md
   carrying real guidance diffs as a total rewrite. For that file, offer
   migrate-then-reduce: move the durable, tool-agnostic instructions
   into the matching project-specific AGENTS.md sections (never into a
   managed block), keep anything genuinely Claude-specific below the
   `@AGENTS.md` import, and only then reduce the file toward the
   template. Never delete the content, and on decline leave the file as
   it stands and report it.

10. Audit standard project files (see below) and flag any newly missing;
    also check the automated-reviewer record, any coordination model, and any
    optional work-unit stage record; see "Automated reviewer record", "Work
    contracts and coordination", and "Work-unit stages (optional)".
11. Check the settings listed under "Repo settings" and offer to align any
    that have drifted.

Where the running agent can execute shell scripts, run this skill's
`scripts/compare-managed-blocks.sh` **from the project root**, giving it
the script's path inside the skill directory and the project's AGENTS.md
path (which defaults to `AGENTS.md`):

```sh
/path/to/agent-setup/scripts/compare-managed-blocks.sh AGENTS.md
```

The script resolves the canonical sections relative to itself, so it runs
from any working directory, but the AGENTS.md argument resolves from the
caller's: run it from the skill directory and a relative project path
resolves inside the skill instead of the project. It performs steps 3 and
6's mechanical parts in one deterministic pass, validating markers and
printing a per-block diff that excludes the nested block, with one
`ok:`, `drift:`, or `missing:` line per key. A missing block is tolerated
as the documented opt-out unless `--require-all` is passed, which turns
it into a failure; that flag fits a note-keeping profile (and init's
post-write check), not a Standard project, whose absent `devlog` block
would fail it (see Profiles). Review its diffs with the user as step 6
describes. Without shell access, follow the steps manually as written.

## Conventional section order

```text
1. Header/intro                          (project-specific)
2. Decision notes                        (managed: devlog;
                                          note-keeping profiles only)
3. Default agent finish line             (managed: finish-line)
4. Context discipline                    (managed: context)
5. Writing for humans                    (managed: communication)
6. Build, test, run                      (project-specific)
7. [Other project-specific sections]     (project-specific)
8. Branches                              (managed: branches)
9. Pull requests + Handing off the PR    (managed: pull-requests)
10. Commits                              (managed: commits)
11. Definition of done for an increment  (managed: done)
```

## Managed section markers

Each canonical section is wrapped with HTML comment markers:

```markdown
<!-- agents-md:managed:KEY -->

## Section Heading

Content...

<!-- /agents-md:managed:KEY -->
```

Keys: `devlog`, `finish-line`, `context`, `communication`, `branches`,
`pull-requests`, `commits`, `done`.

The research basis for the `communication` section (reading behavior,
attention limits, warning habituation, AI over-reliance) is summarized
in `references/writing-for-humans.md`. It ships with the skill for
maintainers revising that section; it is never copied into projects.

To opt a section out of management, remove its markers. The update mode
will note it as missing and offer to re-add, but will not force it.
Opting out `done` this way leaves the nested `project:done-checks`
markers behind as plain project content; that is expected and fine. An
absent `devlog` block under Standard is that project's profile rather
than an opt-out (see Profiles).

## Project-specific section guidance

During init, guide the user through these sections interactively. If
the project is too early for these decisions (fresh repo, no code yet),
write the canonical sections and scaffolding, leave placeholders for
project-specific sections (a TODO comment noting what to fill in), and
move on. The user can re-run in update mode once the project has shape.

Keep the project-specific payload lean: AGENTS.md is loaded whole into
every agent session, so its sections should hold rules that apply to
most sessions. Reference material (a format spec, API detail, a long
gotcha catalog) belongs in `docs/` behind a one-line pointer that names
when to read it ("before editing the parser, read
`docs/format-spec.md`"), not inlined.

### Work contracts and coordination

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
  integration capacity.
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
unit.

### Work-unit stages (optional)

When a project adopts distinct stages, record them in an unmanaged,
project-specific AGENTS.md section near the `Agent-setup profile:` line. No
stage record means the default single implementation workflow, not missing
content. Planning is optional; never create a planning stage merely because
the project uses tracker issues.

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
existing record supplies all six fields and preserve it as unmanaged project
content except for owner-requested edits. Leave an absent record alone unless
the owner explicitly requests stage adoption; then create only the requested
stage definitions. Never fabricate a stage record or move it inside a managed
block.

### Header/intro

Write a one-paragraph intro: project name, pointer to the spec document
(usually README.md), and a sentence on what AGENTS.md covers. Also write
the canonical file rule into AGENTS.md (intro or CI subsection):
"CLAUDE.md is a pointer that imports AGENTS.md; edit AGENTS.md, never
the pointer."

### Build, test, run

- Detect language and build system from project files. If no code
  exists yet, leave this section as a placeholder and skip to
  scaffolding.
- Ask for: build, test, run commands.
- Ask for: targets or entry points, language/runtime version, CI file location.
- Ask about enforced constraints (e.g., "no force unwraps", "strict mode").
- **Lint and format are required, not optional.** The workflow conventions
  depend on them: definition of done expects a successful build, passing
  tests, and clean lint and formatting; commits assume CI catches unformatted
  code. Ask which tools the project uses.
  If the user has none, help them choose and configure one appropriate
  for the language (e.g., `swift-format` for Swift, `prettier` +
  `eslint` for JS/TS, `black` + `ruff` for Python, `rustfmt` +
  `clippy` for Rust). The goal is a single command that can lint and a
  single command that can format, both runnable in CI.

### Architecture invariants (optional)

- Ask: "What rules protect this codebase's structural integrity?"
- Each invariant states what it prevents and how it's enforced.
- Number them for stable cross-references.

### Conventions & gotchas (optional)

- Ask: "What non-obvious patterns or footguns should a new contributor know?"
- Framework traps, naming conventions, testing patterns, runtime quirks.

### Definition of done: project checks

The managed `done` section includes a tool-agnostic expectation that the
build succeeds, tests pass, and lint and formatting are clean, followed by
a placeholder for project-specific verification steps. During init, fill the
`<!-- agents-md:project:done-checks -->` block with the project's actual
verification commands (build command, test command, lint/format command,
visual check method, schema round-trip if applicable).

## Standard project files

Audit for these during init and update. Report presence/absence; don't
create them (content is project-specific), just flag what's missing and
note why it matters.

### Root signal files (GitHub-recognized)

| File                 | Purpose                                         | When needed       |
| -------------------- | ----------------------------------------------- | ----------------- |
| `README.md`          | Landing page: what, who, how to start           | Always            |
| `LICENSE`            | Legal terms (GitHub auto-detects)               | Always            |
| `CHANGELOG.md`       | Release history (Keep a Changelog format)       | Shipping releases |
| `CODE_OF_CONDUCT.md` | Community standards (GitHub links from sidebar) | Open-source       |
| `SECURITY.md`        | Vulnerability reporting policy (GitHub sidebar) | Has users         |

### CI configuration

The workflow conventions assume CI exists: the finish line polls
required checks, the commits section requires every commit green, and
the definition of done expects a successful build, passing tests, and clean
lint and formatting. Check for any of:
`.github/workflows/`, `.circleci/`, `Jenkinsfile`, `.gitlab-ci.yml`,
`Makefile` with a `ci` target, or equivalent. If none is found, flag it:
"Your workflow conventions depend on CI but no CI configuration was
detected." Don't create a CI config (too project-specific), just warn.

### Scaffolded by this skill (created, not just audited)

| File                               | Purpose                                                   |
| ---------------------------------- | --------------------------------------------------------- |
| `CLAUDE.md`                        | Agent entry point; `@`-imports AGENTS.md                  |
| `AGENTS.md`                        | Development conventions (single source)                   |
| `CONTRIBUTING.md`                  | Human contribution guide                                  |
| `devlog/README.md`                 | Decision-note protocol (Decision-log/High-assurance only) |
| `.github/pull_request_template.md` | PR body scaffold                                          |

### docs/ (project-specific, no canonical content)

| File                   | Purpose                                       | When needed      |
| ---------------------- | --------------------------------------------- | ---------------- |
| `docs/architecture.md` | System design, data model, module boundaries  | Non-trivial code |
| `docs/concepts.md`     | Domain glossary, mental model for the project | Domain language  |

Note: projects may have additional `docs/` files for format specs,
API references, or other concerns. These two are the baseline worth
flagging; everything else is project-specific.

## Repo settings

Several canonical conventions name or benefit from repository settings:
merged branches auto-delete, a real merge commit is the only merge method,
the merge commit message is the PR title alone, and stale PR branches are
surfaced for an explicit update. Restricted Actions workflow permissions also
keep the repository token at least privilege unless a workflow declares a
specific need. The audit keeps that setup true so the canonical text's manual
fallbacks stay rare. Treat this as
**detect → report → offer to align**, never a silent mutation. Changing repo
settings needs admin rights the agent may not have, so confirm before applying;
otherwise tell the user the desired state and where to set it.

Settings the conventions use or the audit recommends:

| Setting                                        | Why it matters                                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Auto-delete head branches on merge             | `branches`/`pull-requests` state merged branches auto-delete                                |
| Merge-commit-only (squash and rebase off)      | `commits` needs real merge commits for the `--first-parent` history                         |
| Merge commit message = PR title only           | keeps the body's review material out of history; the title carries the `--first-parent` log |
| Always suggest updating pull request branches  | surfaces a stale branch and offers an explicit refresh action                               |
| Default workflow token permissions = read      | makes workflows declare the specific write permissions they need                            |
| Actions cannot create or approve pull requests | prevents the repository workflow token from creating or approving changes by default        |

These toggles are forge-specific. On GitHub, check and (after confirming)
set them with `gh`; skip or adapt this on other forges, which expose
equivalent settings:

```sh
# Check current state
gh api repos/{owner}/{repo} \
  --jq '{delete_branch_on_merge, allow_merge_commit, allow_squash_merge,
         allow_rebase_merge, merge_commit_title, merge_commit_message,
         allow_update_branch}'

gh api repos/{owner}/{repo}/actions/permissions/workflow \
  --jq '{default_workflow_permissions, can_approve_pull_request_reviews}'

# Align (only after confirming with the user)
gh api -X PATCH repos/{owner}/{repo} \
  -F delete_branch_on_merge=true \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false \
  -F allow_update_branch=true \
  -f merge_commit_title=PR_TITLE \
  -f merge_commit_message=BLANK

gh api --method PUT repos/{owner}/{repo}/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false
```

On GitHub, `allow_update_branch` is the **Always suggest updating pull request
branches** setting under Settings → General → Pull Requests. On other forges,
look for the equivalent stale-branch/update suggestion. If the setting or its
read is unavailable because of the forge, plan, or permissions, report that
limitation clearly and point to the canonical "Handing off the PR" manual
freshness procedure; never infer that an unread setting is disabled.

Before offering to restrict Actions workflow permissions, inspect
`.github/workflows/` for jobs that rely on implicit write access or use the
repository workflow token to create pull requests. Report each affected
workflow. Prefer explicit workflow or job-level `permissions` for required
write scopes while retaining the read-only default. If creating pull requests
from Actions is intentional, surface the conflict and ask whether to keep that
repository-level exception; a workflow cannot override the repository setting
that prevents Actions from creating or approving pull requests. An owning
organization or enterprise may also lock either value. Report that policy
constraint instead of treating the setting as unsupported or disabled.

### Required checks and CI matrices

When branch protection is configured, required status checks are matched
by context name, and a skipped required check counts as satisfied. Both
failure modes bite when a single CI job becomes a matrix: renaming the
job leaves the required context never reporting, so nothing can merge;
keeping the name via a bare fan-in job (`needs:` alone) fails open,
because a failed matrix leg skips the fan-in and the skipped check
passes. Keep the required context reporting through a fan-in job with
`if: always()` and an explicit result test:

```yaml
check:
  needs: test # the matrix job
  if: always() # run even when a leg failed
  runs-on: ubuntu-latest
  steps:
    - run: test "${{ needs.test.result }}" = "success"
```

During the audit, compare the protected branch's required contexts against the
workflow job names and flag any context no job reports, and any bare fan-in
guarding a matrix. Also inspect whether required checks enforce current-base
freshness. On GitHub, `.required_status_checks.strict: true` is **Require
branches to be up to date before merging**:

```sh
gh api repos/{owner}/{repo}/branches/{branch}/protection \
  --jq '{strict: .required_status_checks.strict,
         contexts: .required_status_checks.contexts,
         checks: .required_status_checks.checks}'
```

When required checks exist and strict freshness is off, report it and offer to
enable it, preserving the existing check names and app bindings if the user
accepts. Never change protection silently. If branch protection, strict checks,
or their read is unavailable because of forge support, plan, or permissions,
report the limitation and point to the canonical manual freshness procedure.
A forge merge queue may be reported as an optional capability for a busy
repository, but it is not a canonical requirement.

## Automated reviewer record

The managed `pull-requests` section tells agents to record a noticed
automated reviewer so a review-watch can resolve who to wait on without
re-detecting (the "record a noticed automated reviewer" convention).
During init and update, check whether the project carries such a record:
typically an "Automated reviewer" entry in a project-specific (unmanaged)
AGENTS.md section naming the reviewer, its login/account identity (and the
API-specific form when it differs), its trigger, and any observed status
signals (an in-progress or clean-pass indicator, such as a reaction on the
PR description; without a recorded clean-pass signal, a review-watch can
only time out on a reviewer that posts no review when a pass is clean).

Treat this as **detect → report, never fabricate**. A reviewer is usually
configured after agent-setup first runs, so absence is expected and fine; do not
infer or invent one. If none is recorded, note that one should be added once a
reviewer is configured.

The record is durable project state; a managed-block sync must not delete or
rewrite it silently. If a record sits inside an `agents-md:managed:*` block,
flag it before any managed-block refresh and offer, in order:

1. Relocate the record verbatim to an unmanaged, project-specific section,
   then refresh the block.
2. If relocation is declined: refresh the block and re-insert the record
   verbatim at its prior position, flagged for later relocation.
3. If both are declined: skip refreshing that block and report the conflict.
