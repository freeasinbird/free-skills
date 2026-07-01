---
name: agent-setup
description: >-
  Make a project agent-ready: create or update AGENTS.md with managed canonical
  workflow sections, scaffold the devlog, CLAUDE.md pointer, CONTRIBUTING.md,
  and PR template, and audit standard files and repo settings. Use when the
  user asks to "set up this project for agents", "initialize AGENTS.md",
  "create AGENTS.md", "update AGENTS.md", "sync workflow sections", "check
  agent setup", "bootstrap devlog", "make this project agent-ready", or
  discusses managing shared development conventions across projects.
---

# Agent Setup

Ensure a project is agent-ready: AGENTS.md with canonical workflow
sections, devlog directory, CLAUDE.md pointer, PR template, and repo
scaffolding. Six canonical sections encode the owner's workflow
conventions and are managed across projects; project-specific sections
(build/test/run, architecture invariants, conventions) are guided
interactively during init and left untouched during updates.

## Detecting mode

- No AGENTS.md in the project root → **Init mode**
- AGENTS.md exists with `<!-- agents-md:managed:` markers → **Update mode**
- AGENTS.md exists with no exact markers but with marker lookalikes,
  managed or nested `project:done-checks` (update-mode step 3's
  malformation rule: comment lines that resemble either marker in
  spacing, case, or indentation) → stop and report them; don't offer
  adoption. Wrapping sections around malformed remnants
  leaves a partially adopted file that only fails later, so the user
  should fix or remove the lookalikes first.
- AGENTS.md exists without markers → ask whether to adopt management or
  leave unmanaged. To adopt: match sections to canonical keys by heading,
  wrap each match's existing text as-is in markers, then immediately run
  the update-mode comparison so the user sees any divergence as a diff.
  One exception to as-is: when wrapping a matched `done` section, also
  wrap its existing project checks in the nested
  `<!-- agents-md:project:done-checks -->` markers (text unchanged);
  update-mode validation requires the nested pair inside a managed
  `done` block, so a bare wrap would dead-end the adoption.

## Init mode

1. Read the project to understand language, build system, test framework,
   and directory structure.
2. Read `references/canonical-sections.md` for exact managed-section text.
3. Gather the project-specific sections interactively; see
   "Project-specific section guidance" below. The conventional order
   interleaves them with the managed sections, so collect this content
   (or decide on placeholders) before writing.
4. Write AGENTS.md once, following the conventional section order (see
   below): each canonical section wrapped in its markers, project-specific
   content or placeholders in place.
5. Create scaffolding files:
   - `devlog/README.md`: content in `references/scaffolding.md` §devlog-readme
   - `.github/pull_request_template.md`: content in `references/scaffolding.md` §pr-template
   - `CONTRIBUTING.md`: content in `references/scaffolding.md` §contributing
   - `CLAUDE.md`: content in `references/scaffolding.md` §claude-md

   For any that already exist, don't recreate them: compare against the
   template and, on drift, show the diff and offer to refresh (the same
   rule as update-mode step 8); never overwrite silently.

6. Audit standard project files; see "Standard project files" below.
   Report which are present, which are missing, and suggest creating any
   that apply. Don't create them (content is project-specific); just flag.
   Also check for an automated-reviewer record; see "Automated reviewer
   record" below.
7. Check the repo settings the conventions depend on and offer to align
   them; see "Repo settings" below. Report any that can't be checked or
   set (wrong permissions, non-GitHub forge).
8. Summarize what was created, what the user should fill in, which
   standard files are missing, and which repo settings need attention.

## Update mode

1. Read `references/canonical-sections.md` for current canonical text.
2. Read the project's AGENTS.md.
3. Validate the markers before touching anything: every opening
   `<!-- agents-md:managed:KEY -->` has a matching close after it, no KEY
   appears twice, every KEY is a known one, any line that merely
   resembles a managed marker or the nested `project:done-checks` marker
   (indentation, case, or spacing variants, a mistyped key) is treated
   as a malformation, and, when a managed `done` block is present, the
   nested `<!-- agents-md:project:done-checks -->` block sits inside it,
   once, exact. (Nested markers with no managed `done` block are the
   documented opt-out, not a malformation; see "Managed section
   markers".) On any malformation, stop and report it; never refresh
   (a broken boundary would pull project-specific text into the managed
   region, and the refresh would delete it).
4. Protect the reviewer record before refreshing: if an automated-reviewer
   record appears inside a managed block, resolve its location first; see
   "Automated reviewer record".
5. For each managed block:
   - Extract the content between markers.
   - Compare against the canonical version for that KEY. For `done`,
     exclude the nested `project:done-checks` block from both sides
     (matching its exact marker lines only, per step 3) and compare only
     the text around it; never modify the nested block.
   - If different, show the diff and ask whether to update.
6. Leave all unmarked (project-specific) content untouched.
7. If a canonical section is missing entirely, offer to insert it at its
   conventional position.
8. Check scaffolding files (devlog/README.md, CLAUDE.md, CONTRIBUTING.md,
   PR template): offer to create any that are missing; for any that exist,
   compare against the templates in `references/scaffolding.md` and, on
   drift, show the diff and offer to refresh. These files carry no markers
   and may hold local customizations, so never overwrite silently; let the
   user decide per file. (Watch `devlog/README.md` especially: the managed
   `devlog` and `commits` blocks rely on its protocol, and a stale copy
   contradicts freshly-synced blocks.)
9. Audit standard project files (see below) and flag any newly missing;
   also check that an automated-reviewer record is present; see
   "Automated reviewer record".
10. Check the repo settings the conventions depend on (see "Repo settings")
    and offer to align any that have drifted.

## Conventional section order

```text
1. Header/intro                          (project-specific)
2. Devlog (session bookends)             (managed: devlog)
3. Default agent finish line             (managed: finish-line)
4. Build, test, run                      (project-specific)
5. [Other project-specific sections]     (project-specific)
6. Branches                              (managed: branches)
7. Pull requests + Handing off the PR    (managed: pull-requests)
8. Commits                               (managed: commits)
9. Definition of done for an increment   (managed: done)
```

## Managed section markers

Each canonical section is wrapped with HTML comment markers:

```markdown
<!-- agents-md:managed:KEY -->

## Section Heading

Content...

<!-- /agents-md:managed:KEY -->
```

Keys: `devlog`, `finish-line`, `branches`, `pull-requests`, `commits`, `done`.

To opt a section out of management, remove its markers. The update mode
will note it as missing and offer to re-add, but will not force it.
Opting out `done` this way leaves the nested `project:done-checks`
markers behind as plain project content; that is expected and fine.

## Project-specific section guidance

During init, guide the user through these sections interactively. If
the project is too early for these decisions (fresh repo, no code yet),
write the canonical sections and scaffolding, leave placeholders for
project-specific sections (a TODO comment noting what to fill in), and
move on. The user can re-run in update mode once the project has shape.

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
  depend on them: definition of done says "lint/format clean," commits
  assume CI catches unformatted code. Ask which tools the project uses.
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

The managed `done` section includes a principle block and a placeholder
for project-specific verification steps. During init, fill the
`<!-- agents-md:project:done-checks -->` block with the project's actual
verification commands (test command, lint command, visual check method,
schema round-trip if applicable).

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
the definition of done starts with tests and lint. Check for any of:
`.github/workflows/`, `.circleci/`, `Jenkinsfile`, `.gitlab-ci.yml`,
`Makefile` with a `ci` target, or equivalent. If none is found, flag it:
"Your workflow conventions depend on CI but no CI configuration was
detected." Don't create a CI config (too project-specific), just warn.

### Scaffolded by this skill (created, not just audited)

| File                               | Purpose                                  |
| ---------------------------------- | ---------------------------------------- |
| `CLAUDE.md`                        | Agent entry point; `@`-imports AGENTS.md |
| `AGENTS.md`                        | Development conventions (single source)  |
| `CONTRIBUTING.md`                  | Human contribution guide                 |
| `devlog/README.md`                 | Devlog protocol                          |
| `.github/pull_request_template.md` | PR body scaffold                         |

### docs/ (project-specific, no canonical content)

| File                   | Purpose                                       | When needed      |
| ---------------------- | --------------------------------------------- | ---------------- |
| `docs/architecture.md` | System design, data model, module boundaries  | Non-trivial code |
| `docs/concepts.md`     | Domain glossary, mental model for the project | Domain language  |

Note: projects may have additional `docs/` files for format specs,
API references, or other concerns. These two are the baseline worth
flagging; everything else is project-specific.

## Repo settings

Several canonical conventions assume repository settings: `branches` and
`pull-requests` state that merged branches auto-delete and that a real
merge commit is the only merge method, which read as false if the
settings are off. Treat this as **detect → report → offer to enable**,
never a silent mutation. Changing repo settings needs admin rights the
agent may not have, so confirm before applying; otherwise tell the user
the desired state and where to set it.

Settings the conventions depend on:

| Setting                                   | Why it matters                                                      |
| ----------------------------------------- | ------------------------------------------------------------------- |
| Auto-delete head branches on merge        | `branches`/`pull-requests` state merged branches auto-delete        |
| Merge-commit-only (squash and rebase off) | `commits` needs real merge commits for the `--first-parent` history |

These toggles are forge-specific. On GitHub, check and (after confirming)
set them with `gh`; skip or adapt this on other forges, which expose
equivalent settings:

```sh
# Check current state
gh api repos/{owner}/{repo} \
  --jq '{delete_branch_on_merge, allow_merge_commit, allow_squash_merge, allow_rebase_merge}'

# Align (only after confirming with the user)
gh api -X PATCH repos/{owner}/{repo} \
  -F delete_branch_on_merge=true \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false
```

If the agent lacks permission or the forge isn't GitHub, report the
desired state and point the user at the setting (on GitHub: Settings →
General → Pull Requests).

## Automated reviewer record

The managed `pull-requests` section tells agents to record a noticed
automated reviewer so a review-watch can resolve who to wait on without
re-detecting (the "record a noticed automated reviewer" convention).
During init and update, check whether the project carries such a record:
typically an "Automated reviewer" line in a project-specific (unmanaged)
AGENTS.md section naming the reviewer, its login/account identity (and the
API-specific form when it differs), and its trigger.

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

## Additional Resources

### Reference Files

- **`references/canonical-sections.md`**: exact text of all managed
  sections, ready to paste
- **`references/scaffolding.md`**: content for all scaffolded files
  (devlog README, PR template, CONTRIBUTING.md, CLAUDE.md pointer)
