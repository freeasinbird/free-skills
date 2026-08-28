# Apply title case to headings repo-wide

Issue #178. PR #177 title-cased the eight managed sections and their
references and deferred the rest of the repo here. This unit applies the same
decision to every remaining sentence-case prose heading: the README, each
skill's SKILL.md and reference files, CONTRIBUTING.md, the non-managed
AGENTS.md sections, and the two root policy files. It changes heading case
only and rewrites, reorders, or rewords nothing else.

## Decisions

- **Applied #177's title-case preference, not a new convention.** The owner
  prefers title case and no written sentence-case convention existed to
  change. This completes the sweep #177 deferred.
- **Kept the two inherited template pairs in sync, rejecting divergence.**
  `CONTRIBUTING.md` and its scaffold source (`scaffolding.md` `§contributing`)
  both became "AI-Assisted Contributions"; the root and skill copies of
  `LICENSING-PHILOSOPHY.md` both became "How We Choose Licenses". Under the
  two-place rule a live copy cannot diverge from its downstream template, so
  converting one side alone was not an option. Title case now propagates to
  every project these scaffold.
- **Preserved two fenced record-format template headings the plan listed for
  conversion.** `### Post-merge obligations` (project-obligations.md) and
  `### Coordination model` (coordination-discovery.md) sit inside fenced
  `markdown` record templates. "Post-merge obligations" is a matched record
  identifier: merge-cleanup SKILL.md names it in backticks and roughly fifteen
  eval prompts and assertions detect the record by that exact text. Retitling
  it would desync the contract and risk breaking detection. The acceptance
  criteria also exempt only the "Conventional section order" list from the
  fenced-heading rule, so both headings stay as written. The plan (an
  implementation aid) was overridden by the contract and this evidence.
- **Corrected interior articles the plan judged already fine.** The ruleset
  lowercases interior articles, so prompt-crafter's "Author A New Payload" and
  "Audit An Existing Prompt Set" became "a"/"an". #177's own output lowercases
  "an" ("Definition of Done for an Increment"), so this is consistency, not a
  new rule.
- **Aligned only the references a retitle makes stale.** A quoted
  cross-reference names a heading, so when its target's case changed the quote
  was updated (for example `see "Update Mode"`, `"Handing Off the PR"`), and
  the agent-setup "Conventional section order" list was aligned to the
  retitled canonical names. Reference-file `## Contents` link labels were left
  as they were: their anchors are case-insensitive and still resolve, and they
  are navigation chrome rather than prose that claims a heading's name.
- **Preserved emphasis terms and identifiers inside headings.** `_before_` and
  `_after_` stay lowercase as the visual-evidence skill's terms of art;
  `macOS`, `CI`, `PR`, `AI`, `NOT`, `CSS`, `SKILL.md`, and slugs keep their
  exact case. The `## Section: <slug>` markers, `§slug` anchors, the
  byte-locked `docs/agent-workflow.md` slugs, the eight managed AGENTS.md
  blocks, the H1 identity titles (`# free-skills`, `# CLAUDE.md`,
  `# <skill> evals`), and the frozen devlog notes were all left untouched.

## Ruleset

Capitalize the first word, the last word, and the first word after a colon.
Otherwise lowercase articles (a, an, the), coordinating conjunctions (and,
but, or, nor, for, so, yet), and prepositions of three letters or fewer (of,
to, in, on, at, by, up, vs). Capitalize longer prepositions (From, With, Into,
Over) and phrasal-verb particles (Handing Off). Each significant part of a
hyphenated compound capitalizes (Merge-and-Cleanup, Force-With-Lease), while a
coined compound that was already capitalized keeps its form (Read-As-The-Agent
in an untouched file). "vs" (versus) is treated as a short preposition and
lowercased, which also matches its own table-of-contents label.

## Rejected alternatives

- **Leave the downstream templates in sentence case:** rejected because the
  live copies could then not match them under the two-place sync rule.
- **Convert the two record-format template headings:** rejected because
  "Post-merge obligations" is an identifier the skill and its evals match by
  text, and the acceptance criteria preserve fenced headings.
- **Title-case the reference-file Contents labels too:** rejected as outside
  the heading scope; the anchors still resolve, so nothing is broken.

## Verification

markdownlint, prettier, prose-tics, skill-structure, and managed-sync all
pass, confirming no anchor, managed block, or byte-locked slug moved. A
fence-aware extractor confirms every remaining in-scope prose heading is title
case, and both synced pairs match on the changed heading.

Revisit when a downstream project wants sentence-case scaffolded files (the
two templates would need a divergence mechanism), or when a new skill,
reference file, or managed section adds headings this sweep did not cover.
