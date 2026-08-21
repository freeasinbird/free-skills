# Rule-map format for the readability rewrites

Issue #159 piloted the readability bar (#171) on `skills/prompt-crafter/`
and had to settle the audit artifact every later unit carries: the rule
map that proves a rewrite dropped nothing normative. This note records
the format chosen and the alternatives rejected, so #160 and the skill
units can reuse it without re-deciding.

## Decisions

- **Rule map is a five-column table, one row per normative statement of
  the old text, built before rewriting.** Columns: `#` (a per-file
  prefix plus a running number, `S12`, `A9`, `T3t`), `Old location`
  (file and section, plus step or bullet), `Old statement (short)`
  (a paraphrase under about twenty words), `New location` (file and
  heading, plus step or bullet), `Note` (one of `kept`, `reworded`,
  `split`, `moved`, `merged into #N`, or `dropped: <reason>`). A
  statement counts as normative when it tells the agent to do, avoid,
  check, or treat something a certain way; definitions and rationale
  that a rule depends on are rows too. Building the map from the old
  text first is the mechanism against silent meaning drift: every
  `dropped` or `reworded` row is a claim the owner can reject.
- **Rejected: a per-file diff narrative.** Prose like "step 4 was split
  into a lead plus two bullets" reads well but cannot be audited row by
  row; a reader has to rediscover which statements the narrative
  skipped. The table makes omission visible as a missing row.
- **Rejected: a checklist without locations.** A tick per old statement
  proves the author looked, not where the statement went; the owner
  cannot spot-check a tick. `New location` is the column that makes a
  row verifiable in under a minute.
- **Rejected: a mechanical text diff as the audit.** Reordering and
  splitting produce diffs that are all churn, which is exactly what
  hides a dropped qualifier. A crude survival check (the share of each
  old sentence's long words that reappear in the new file) is a useful
  miss-detector during the rewrite, and it flagged one reworded row
  here, but it is a supplement to the map, not a substitute: it cannot
  tell a dropped qualifier from a synonym.
- **Pilot shape decisions, reusable by later units.** `SKILL.md` order:
  opening (what, when, out of scope), Terms, Procedure (one numbered
  list per workflow, one line per step), Core model, References,
  workflows, Guardrails. The glossary sits second, before Procedure, so
  a term is defined before its first bare use; the plan had allowed
  either placement. Workflow steps keep a bold lead under thirty words
  with detail as sub-bullets, which is what took the file from two
  sentences over forty words to none. Reference files keep their
  headings and get a fixed per-entry core shape (the taxonomy: Symptom,
  Test, Fix, with Found live and Caution bullets only where the old text
  carried an example or a caution) rather than a restructure. This
  narrows the 2026-07-01 note's "every class carries a live example":
  classes 1 and 7 never had a quoted example, so the intro now states
  what the text holds, and `SKILL.md` still advertises an example per
  class. Follow-up: #174.
- **Word count may grow.** The bar measures form, not length; the
  Procedure and Terms sections added about two hundred words to
  `SKILL.md`. Density improved (median sentence 18 to 10, max paragraph
  101 to 58) while total words rose. Later units should expect the same
  and not trade a dropped rule for a shorter file.

Revisit when the map proves too heavy for the agent-setup unit (#161,
the largest file): the likely relief is coarser rows (one per bullet,
with the bullet's inner sentences listed in the note) rather than a
different artifact. Also revisit if #171 records a different format
after this unit lands; the tracker comment then governs.
