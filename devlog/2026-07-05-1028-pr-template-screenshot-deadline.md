# Align PR-template screenshot deadline with the handoff rule

Downstream (free-prompts) ran `/agent-setup` to fix drift; Codex there
flagged that the scaffolded PR template's screenshot deadline said only
"before merging" while the managed `pull-requests` block (canonical) says
"before handing off, and in every case before merge". Root cause is here:
the two agent-setup source files disagreed.

## Decisions

- **Fix in the skill source, not just downstream.** `scaffolding.md`
  §pr-template is the template every project's `.github/pull_request_template.md`
  is copied from; `canonical-sections.md` already carried the handoff+merge
  wording. Bring the template comment to match, so new and re-synced projects
  inherit the consistent rule. Rejected: patching only the downstream copy,
  which would leave the template source wrong for the next project.
- **Swept the dogfooded copy.** This repo's own
  `.github/pull_request_template.md` was a byte-identical copy of the old
  template, so it had the same lag; re-synced it from the fixed template in
  the same commit (fix-the-class).

## Fixed

- `skills/agent-setup/references/scaffolding.md`: §pr-template screenshot
  comment now reads "before handing off, and in every case before merge".
- `.github/pull_request_template.md`: re-synced to match.

## Verification

- Checked: `scaffolding.md` §pr-template and `canonical-sections.md`
  pull-requests screenshot rule now use the same deadline wording.
- Passed: prettier + markdownlint on both changed files.

## To promote

- Nothing outstanding. Pre-existing queue items are unrelated
  agent-setup-learnings, left as-is.
