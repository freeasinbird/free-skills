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
- **Section shape is reassessed per file, not copied from this pilot.** The
  owner tone pass removed the pilot's separate Terms and Procedure sections.
  In the final `SKILL.md`, each remaining term is defined where it is used,
  and the workflow headings plus numbered steps already provide the
  procedure. Repeating those ideas in opening sections added navigation but
  also duplicated content. Later units should add a glossary or procedure
  summary only when the file needs one.
- **The final pilot keeps the direct section order.** `SKILL.md` runs from
  the opening to Core Model, references, the three workflows, and Guardrails.
  Reference files keep their established headings and explain each taxonomy
  symptom in prose before its Test and Fix bullets. The owner chose this
  final form whole cloth after reviewing the agent rewrite.
- **Density numbers are evidence, not a substitute for owner judgment.** The
  final four files contain three sentences over forty words and a maximum
  paragraph of 101 words. The owner preferred the final wording and direct
  workflow presentation despite those report values. Later units still run
  the density report, but choose their section shape from the text at hand.
- **The live-example mismatch remains deferred.** Classes 1 and 7 still have
  no quoted live example while `SKILL.md` and the taxonomy introduction say
  every class has one. Follow-up #174 owns the choice between supplying real
  examples and narrowing the claim; this readability unit does not decide it.

Revisit when the map proves too heavy for the agent-setup unit (#161, the
largest file): the likely relief is coarser rows (one per bullet, with the
bullet's inner sentences listed in the note) rather than a different
artifact. Reassess glossary and procedure-summary sections independently for
that file. Also revisit if #171 records a different map format after this
unit lands; the tracker comment then governs.
