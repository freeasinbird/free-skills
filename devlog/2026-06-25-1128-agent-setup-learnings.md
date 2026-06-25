# Fold gh-imgup usage learnings into the agent-setup template

The user's `gh-imgup` build (PRs #3–#11, heavy bot review, security/data-loss
fixes) surfaced durable conventions that were never written down and had to be
re-derived each round. They belong in the skill's managed sections, not one
repo's AGENTS.md (which a re-sync would overwrite).

## What landed

- **canonical-sections.md** (re-synced into this repo's AGENTS.md):
  `commits` fold-fix bullet; `pull-requests` automated-review handling,
  docs-honesty Verification clause, inter-turn cadence, and a new Stacked PRs
  subsection; `finish-line` scoped refute-first pass + promotion-drain step;
  `devlog` start-of-session queue grep; `branches` stacked-PR pointer.
- **scaffolding.md §devlog-readme** (re-synced into devlog/README.md): canonical
  `## To promote` header + optional recommended section set; append-only
  replaced by revisable-until-merge-then-frozen; needs-human → file an issue.

## Decisions

- **Two judgment calls put to the user.** §5 tooling gotchas (regex/JSON
  control-char gremlin, backtick-in-backtick) → excluded: code-authoring
  footguns, not workflow conventions. §1c adversarial verification → included
  but scoped to destructive/leak/trust-boundary paths, explicitly not routine.
- **Honored §4's non-suggestions:** no per-PR adversarial mandate, no
  "resolve all threads" gate, no promotion tracker file, no rigid devlog
  template, no DOCS-STYLE.md. Additions kept to intent + guardrail, no runbooks.
- **Dogfooding parity enforced.** This repo carries the managed markers, so each
  canonical edit was mirrored into AGENTS.md and verified block-for-block
  identical (awk-extract + diff); the nested project:done-checks block is the
  one intended divergence.
- **Prettier normalized `*em*` → `_em_`** in both managed files identically;
  parity preserved.

## To promote

- (none — this change _is_ the promotion of the gh-imgup learnings.)
