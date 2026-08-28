# Add the write-plainly skill

The owner keeps a personal writing-style guide, extracted from their own
chat history, that agents use to write in their voice. Most of that guide
isn't personal at all: it describes plain, active, bottom-line-first prose.
This work unit generalizes it into a reusable skill with no reference to any
person.

## Decisions

- **Named the skill `write-plainly`, not `plain-writing` or
  `plain-language`.** The imperative matches how users ask for it and
  reads as the instruction it is. `plain-language` was rejected because it
  names the regulated-documents discipline, which implies a public audience
  and says nothing about candor.
- **Chose a general write-plainly skill over a "write like the owner"
  skill.** The owner asked for the general form. Person-specific framing was
  removed: the "specific signals" section became ordinary rules about
  corrections, requests, follow-ups, and assumed reader competence; the
  evidence section describing the owner's chat sample was dropped because
  it's provenance, not instruction, and it names the owner.
- **Split examples into `references/examples.md`.** The skill triggers on
  most human-facing writing, so `SKILL.md` loads often. Rules stay in
  `SKILL.md` (about 1,000 words); the rewrite table and situation examples
  load on demand for longer drafts and for rewriting or reviewing text.
- **Added a "what wins when rules conflict" section and a rewriting
  section.** The source guide stated correctness-over-brevity and
  keep-exact-terms in passing. The canonical-readability rewrite (see the
  2026-08-24 note) showed that dropped rules are the main risk of any
  plainness pass, so the skill now says outright: preserve every
  requirement, and name anything you cut. Project style guides win over the
  skill, since it's installed into arbitrary repositories.
- **Described the stock openers instead of quoting them.** The repo's
  prose-tic check bans three literal openers in all non-devlog markdown, so
  the skill and its rewrite table name the class (praise the question, agree
  reflexively, announce eagerness) rather than the phrases. A reader still
  recognizes them, and the skill stays clean under its own ban.
- **Kept the overlap with the managed "Writing for Humans" section.** That
  managed block is a short set of rules for handoffs and PRs and is copied
  into downstream AGENTS.md files. The skill is the fuller craft: voice,
  sentence-level choices, tone, failure modes, and examples. They agree;
  neither points at the other, because the managed section must not assume
  a skill is installed.

## Rejected Alternatives

- **Inline all examples in `SKILL.md`:** rejected because the skill loads on
  ordinary replies, where 700 words of examples cost context on every turn.
- **Keep a short provenance note in the skill:** rejected because it would
  either name the owner or make an unverifiable "derived from real writing"
  claim the skill has no way to keep current.

Revisit when an agent using the skill drops a requirement while rewriting,
when the managed communication section and the skill diverge on a rule, or
when trigger evals show the description firing on code-only tasks.
