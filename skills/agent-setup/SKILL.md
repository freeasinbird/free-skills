---
name: agent-setup
description:
  This skill should be used when the user asks to "set up this project for
  agents", "initialize AGENTS.md", "create AGENTS.md", "update AGENTS.md", "sync
  workflow sections", "check agent setup", "bootstrap devlog", "make this project
  agent-ready", or discusses managing shared development conventions across projects.
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
- AGENTS.md exists without markers → ask whether to adopt management
  (insert markers around matching sections) or leave unmanaged

## Init mode

1. Read the project to understand language, build system, test framework,
   and directory structure.
2. Read `references/canonical-sections.md` for exact managed-section text.
3. Write AGENTS.md following the conventional section order (see below),
   with each canonical section wrapped in its markers.
4. Guide the user through project-specific sections interactively — see
   "Project-specific section guidance" below.
5. Create scaffolding files (skip any that already exist):
   - `devlog/README.md` — content in `references/scaffolding.md` §devlog-readme
   - `.github/pull_request_template.md` — content in `references/scaffolding.md` §pr-template
   - `CONTRIBUTING.md` — content in `references/scaffolding.md` §contributing
   - `CLAUDE.md` — content in `references/scaffolding.md` §claude-md
6. Audit standard project files — see "Standard project files" below.
   Report which are present, which are missing, and suggest creating any
   that apply. Don't create them (content is project-specific); just flag.
7. Check the repo settings the conventions depend on and offer to align
   them — see "Repo settings" below. Report any that can't be checked or
   set (wrong permissions, non-GitHub forge).
8. Summarize what was created, what the user should fill in, which
   standard files are missing, and which repo settings need attention.

## Update mode

1. Read `references/canonical-sections.md` for current canonical text.
2. Read the project's AGENTS.md.
3. For each `<!-- agents-md:managed:KEY -->` block:
   - Extract the content between markers.
   - Compare against the canonical version for that KEY.
   - If different, show the diff and ask whether to update.
4. Leave all unmarked (project-specific) content untouched.
5. If a canonical section is missing entirely, offer to insert it at its
   conventional position.
6. The `done` section has a nested `<!-- agents-md:project:done-checks -->`
   block — never overwrite that block during update; only compare the
   principle text outside it.
7. Check scaffolding files (devlog/README.md, CLAUDE.md, CONTRIBUTING.md,
   PR template) and offer to create any that are missing.
8. Audit standard project files (see below) and flag any newly missing.
9. Check the repo settings the conventions depend on (see "Repo settings")
   and offer to align any that have drifted.

## Conventional section order

```text
1. Header/intro                          (project-specific)
2. Devlog (session bookends)             (managed: devlog)
3. Default agent finish line             (managed: finish-line)
4. Build, test, run                      (project-specific)
5. [Other project-specific sections]     (project-specific)
6. Branches                              (managed: branches)
7. Pull requests + Landing a PR          (managed: pull-requests)
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

## Project-specific section guidance

During init, guide the user through these sections interactively. If
the project is too early for these decisions (fresh repo, no code yet),
write the canonical sections and scaffolding, leave placeholders for
project-specific sections (a TODO comment noting what to fill in), and
move on. The user can re-run in update mode once the project has shape.

### Header/intro

Write a one-paragraph intro: project name, pointer to the spec document
(usually README.md), and a sentence on what AGENTS.md covers.

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
- Note the canonical file rule: "CLAUDE.md is a pointer that imports
  AGENTS.md — edit AGENTS.md, never the pointer."

### Architecture invariants (optional)

- Ask: "What rules protect this codebase's structural integrity?"
- Each invariant states what it prevents and how it's enforced.
- Number them for stable cross-references.

### Conventions & gotchas (optional)

- Ask: "What non-obvious patterns or footguns should a new contributor know?"
- Framework traps, naming conventions, testing patterns, runtime quirks.

### Definition of done — project checks

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

The workflow conventions assume CI exists — the finish line polls
required checks, the commits section requires every commit green, and
the definition of done starts with tests and lint. Check for any of:
`.github/workflows/`, `.circleci/`, `Jenkinsfile`, `.gitlab-ci.yml`,
`Makefile` with a `ci` target, or equivalent. If none is found, flag it:
"Your workflow conventions depend on CI but no CI configuration was
detected." Don't create a CI config (too project-specific), just warn.

### Scaffolded by this skill (created, not just audited)

| File                               | Purpose                                   |
| ---------------------------------- | ----------------------------------------- |
| `CLAUDE.md`                        | Agent entry point — `@`-imports AGENTS.md |
| `AGENTS.md`                        | Development conventions (single source)   |
| `CONTRIBUTING.md`                  | Human contribution guide                  |
| `devlog/README.md`                 | Devlog protocol                           |
| `.github/pull_request_template.md` | PR body scaffold                          |

### docs/ (project-specific, no canonical content)

| File                   | Purpose                                       | When needed      |
| ---------------------- | --------------------------------------------- | ---------------- |
| `docs/architecture.md` | System design, data model, module boundaries  | Non-trivial code |
| `docs/concepts.md`     | Domain glossary, mental model for the project | Domain language  |

Note: projects may have additional `docs/` files for format specs,
API references, or other concerns. These two are the baseline worth
flagging; everything else is project-specific.

## Repo settings

Several canonical conventions assume specific repository settings. The
`branches` and `pull-requests` sections state that merged branches
auto-delete and that a real merge commit is the only merge method —
those sentences read as false if the settings are off. agent-setup
doesn't own repo configuration, but it should check these and offer to
align them.

Treat this as **detect → report → offer to enable**, never a silent
mutation. Changing repo settings needs admin rights the agent may not
have, so confirm before applying and otherwise fall back to telling the
user the desired state and where to set it.

Settings the conventions depend on:

| Setting                                   | Why it matters                                                      |
| ----------------------------------------- | ------------------------------------------------------------------- |
| Auto-delete head branches on merge        | `branches`/`pull-requests` state merged branches auto-delete        |
| Merge-commit-only (squash and rebase off) | `commits` needs real merge commits for the `--first-parent` history |

These toggles are forge-specific. On GitHub, check and (after confirming)
set them with `gh` — skip or adapt this on other forges, which expose
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

## Additional Resources

### Reference Files

- **`references/canonical-sections.md`** — exact text of all managed
  sections, ready to paste
- **`references/scaffolding.md`** — content for devlog/README.md and
  PR template
