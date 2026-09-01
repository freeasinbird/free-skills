# Splitting agent-setup SKILL.md into a one-read core and step-local references

The 2026-09-01 transcript audit found that `skills/agent-setup/SKILL.md`
(894 lines) was the longest skill prompt in the repo and that Codex
truncated its read 32 times across 57 sessions. Sync runs themselves
worked (12 of 14 recorded runs merged without correction), so the cost
was read size, not behavior. Issue #203 set the contract: a core of at
most about 250 lines, every moved section reachable from the step that
needs it by a `references/<file>.md` §slug pointer, and no rule dropped.

## Decisions

- **Core/reference boundary is "every run reads it" versus "one step
  reads it".** Core keeps the mode-detection table, the profile rules,
  the numbered init, update, and reassessment procedures, the managed
  keys, and the reviewer-record safety rule. Reference holds, verbatim,
  each block of step-local detail: the three mode-routing outcomes and
  the reassessment steps (`modes.md`), marker format and validation,
  profile discovery, the init write check, scaffold drift rules, the
  comparator invocation, and the reviewer-record audit
  (`managed-blocks.md`), the conventional section order and all
  project-specific section guidance (`project-sections.md`), and the
  standard-file and repo-settings audits (`audit.md`). The core landed at
  199 lines.
- **Four topical files, not one procedure file.** A sync run reads
  `managed-blocks.md` sections; an init reads `project-sections.md` and
  `audit.md` as well; a reassessment reads `modes.md` and the existing
  `coordination-discovery.md`. One file would put the reassessment
  procedure and the repo-settings tables in every sync read, which is the
  read-size problem again at a smaller scale. Rejected: folding the
  reassessment steps into `coordination-discovery.md` §reassess, because
  that section is the input-state validation table the steps cite, and
  a procedure that wraps its own reference reads as one long section.
- **Every pointer is an imperative, step-anchored read trigger in the
  core**, following the 2026-08-21 core-reference split. Pointers inside
  reference files satisfy the structure check on their own, so the check
  cannot prove the issue's "reachable from the step that needs it"
  criterion; the core carries a full-form pointer to each of the
  fifteen new sections, and a reference pointer is only ever a
  cross-reference beside it.
- **The mode table no longer quotes the marker opener.** The structure
  check blanks everything after an unclosed `<!--`, as its docstring
  says, and the row reading "AGENTS.md has `<!-- agents-md:managed:`
  markers" opened a comment that the pre-split text happened to close
  at the adoption step's nested-marker example. With that example moved
  out, every pointer below the table became invisible and fourteen
  sections reported as orphaned. The row now reads "has exact
  `agents-md:managed:` markers". Rejected: teaching the check that a
  backticked opener is code, since the hiding rule is deliberate and a
  table cell is the only place the prompt needs the literal.
- **Relocation is one commit with a sentence-level coverage check
  instead of a relocation-then-compression pair.** Moving the step-local
  detail alone brought the core under the line budget, so no compression
  pass was needed and the reference text is the pre-split text with only
  cross-references rewritten to name their new location. A scratch
  script split the pre-split prompt into 475 sentence-level units and
  looked each up in the new core plus references; the 30 misses were
  headings and rewritten cross-references, audited one by one, after
  three genuine drops it surfaced were restored: "let the user decide
  per file", the update-step "on drift, show the diff and offer to
  refresh" clause, and the `devlog/README.md` stale-copy warning.

## Verification findings

- The readability gate treats moved lines as touched, so one pre-split
  paragraph of 123 words in the stage rules had to be split at a
  sentence boundary; that is the only prose edit that is not a
  cross-reference.
- Dedenting two list-item bodies into reference sections left their
  original ordinal prefixes ("3.", "6."), which markdownlint flags as a
  list starting at the wrong number; they are now plain lead sentences.

Revisit when: a downstream sync skips a pointed section it needed, the
core regrows past 250 lines without a new mode or step behind it, or
issue #209 adds the forge-slug record and needs a home for its audit text.
