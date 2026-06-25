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
- **Reframed the ≤40-line cap as a density target (post-open feedback).** The
  new revisable-until-merge rule makes one entry absorb every review round, so
  a hard per-file cap fought heavy-review PRs. Rule is now density (decisions,
  never narration; transcript lives in commits + PR threads), with ≤~40 lines
  as a _per-round_ soft target that scales with distinct decisions. Landed as
  its own commit, not a fold into c1/c2 — it resolves a tension this PR
  introduced and edits pre-existing cap text, so a named commit reads better
  than rewriting pushed commits.
- **Added reviewer-side conventions (post-open feedback).** `pull-requests`
  documented only the author receiving review (§1b); the reviewer side was
  missing. Added a `### Reviewing a PR` subsection mirroring the author rules
  (severity-tag, evidence + concrete ask, review against intent, stay in
  scope, scale depth to risk, resolve explicitly). Kept methodology-neutral —
  "use the project's review tooling" rather than naming a Claude-Code-only
  skill (invariant #2). Subsection over a new `review` managed KEY: review
  doesn't separate cleanly from PR conventions.
- **Folded Codex's P2 into c2 (dogfooding fold-fix).** The managed devlog
  block still said "append-only" while the README now says revisable — valid
  finding. Dropped the word and folded into the protocol commit (c2) so every
  commit stays internally consistent, not a separate fix commit. Done via
  cherry-pick rebuild (rebase -i unavailable) with a backup branch; tree diff
  vs pre-fold = only the two-line drop.

## To promote

- (none — this change _is_ the promotion of the gh-imgup learnings.)
