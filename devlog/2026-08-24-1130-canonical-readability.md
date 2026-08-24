# Rewrite the canonical workflow in plain English

Issue #160 required a shorter, clearer version of the workflow that preserves
every rule. The wording now uses short sentences, one rule per bullet, and
numbered procedures where order matters.

## Decisions

- **Kept the eight managed sections.** Changing their boundaries would break
  the stable marker interface and make downstream updates harder to review.
  The existing split also still matches the workflow's main concerns.
- **Kept step-local detail in `docs/agent-workflow.md`.** The core retains
  rules used throughout a work unit or review round. Procedures used at one
  step remain behind the nine existing read triggers.
- **Defined terms where they appear.** A separate glossary would make readers
  jump between sections. The rewrite instead explains terms such as baseline,
  claim, and fold at the point of use.
- **Used plain instructions instead of compressed shorthand.** Dense phrases
  such as "validity-sustained review" became direct statements about when to
  continue, stop, fix, defer, or decline.
- **Matched ordinary user register without weakening gates.** Ordinary prose
  uses contractions where they sound natural. Safety, compatibility, and
  exact-procedure gates stay firm. Review-watch and convergence instructions
  now name the event or action instead of relying on workflow shorthand.
- **Named actors and checks instead of process abstractions.** Handoff rules
  say what one agent leaves for the next. Review rules say who checks the
  change, what evidence they receive, and which outcome to record.
- **Left CONTRIBUTING.md and the PR template unchanged.** Both were already
  short, direct, and free of long sentences. Rewriting them would add churn
  without improving comprehension.

## Voice and heading pass (follow-up)

A later pass, folded into this PR, tightened voice and heading style after an
owner review against `writing-style.md`.

- **Contracted the remaining declarative negatives.** The first rewrite still
  left "does not", "cannot", and "is not" in ordinary statements; they now read
  "doesn't", "can't", and "isn't". Imperative gates keep their firm form:
  "Never ..." and "Do not ..." where it commands. This completes the
  contractions decision above rather than reversing it.
- **Chose title case for prose headings.** The owner strongly prefers title
  case, so managed-section and reference headings now use it (for example
  "Default Agent Finish Line"). No written heading-case convention existed to
  change; this replaces the repo's earlier sentence-case habit.
- **Kept identifier headings lowercase.** The `## Section: <slug>` markers and
  the `§slug` headings stay as anchor identifiers the pointer check resolves,
  so title case does not reach them.
- **Deferred the repo-wide sweep to #178.** Only this PR's files changed. The
  README, other skills, CONTRIBUTING.md, the PR template, and the non-managed
  AGENTS.md sections still use sentence case; #178 tracks converting them.

## Preservation record

No normative statement was deliberately dropped. The rule map in the PR body
shows where every old rule now lives.

Codex review found two accidental omissions in the first rewrite: updating the
default branch from its remote and reading the stacked-PR procedure before
creating a dependent branch. Both rules are explicit again in the canonical
text and its AGENTS.md mirror.

A later pass found two more preservation gaps. The refute-first trigger now
applies to any work on the listed risk paths, including behavior-preserving
refactors. The decision-note protocol again makes its one-note limit an
ordinary-case rule rather than an absolute limit.

A lost-info audit against the pre-rewrite text found ten more rules whose
meaning narrowed or shifted, now all restored and mirrored: the handoff
fallback again hands the PR back with the review pending rather than reporting
no review; a reviewer record again requires a recent PR; worktree isolation
again gates on platform and session and names the single-directory sandbox; a
review reply again separates a fix's SHA from a decline's reason; the
one-concern rule is again a hard split, not a usual one; the review-tooling
rule regains its firm form and the delegated-effort rule its effort-level
option; and "which assumption or condition changed" returns in the two sections
that had trimmed it. These corrections raised the managed payload to 17,740
bytes, still within the 20,000 budget. Three restored sentences were split to
stay within the rewrite's 27-word ceiling, so the PR's readability report still
holds.

Repeated rationale was shortened only when the rule itself remained explicit.
Examples include why direct commits damage first-parent history and why a
SHA-based commit map goes stale. Research detail remains in
`writing-for-humans.md`, while the managed communication section carries the
plain-language rule it supports.

The rewrite preserves the stable interfaces:

- Eight managed marker names.
- Nine `docs/agent-workflow.md` section slugs and their read triggers.
- The project-owned `project:done-checks` block.
- The managed-block limit of 20,000 bytes.

## Rejected alternatives

- **Split the eight sections differently:** rejected because the marker names
  are a public sync interface and the current concerns remain coherent.
- **Move more core rules into the reference file:** rejected because rules
  used throughout implementation or every review round must stay loaded.
- **Add a glossary:** rejected because only a few project terms need
  explanation, and defining them in place is easier to follow.
- **Keep the old wording and add summaries:** rejected because duplicated
  summaries would increase length and leave the difficult source text intact.
- **Delete detail until the density numbers looked good:** rejected because
  readability evidence cannot replace the rule-preservation contract.
- **Keep sentence-case headings:** rejected because the owner prefers title
  case and no written convention required sentence case.

## Verification findings

The tone audit found the same conversational pattern through two independent
filters. A conservative scan found 549 short messages with direct evidence of
user authorship. A stricter filter found 304 unique likely-typed messages with
a nine-word median sentence and 101 contractions. The human-audited
prompt-crafter files and the global AGENTS.md also favor ordinary contractions.

The managed payload fell from 19,991 to 17,740 bytes while preserving all nine
procedure pointers. Across the eight measured files, words fell from 11,002 to
10,107 before this note was added. Sentences over 40 words fell from 55 to 5;
the remaining five are in project-specific AGENTS.md content outside the
rewritten managed blocks.

Revisit when an agent misreads a rewritten rule, a downstream sync exposes an
unclear term, or a later workflow change requires a new managed section or
procedure slug.
