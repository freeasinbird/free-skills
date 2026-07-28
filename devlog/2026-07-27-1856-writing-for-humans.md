# Writing for humans: new canonical communication section

## Decision

Add a canonical managed section `communication` ("Writing for
humans") to agent-setup, placed after Context discipline in the
conventional order, plus a maintainer-facing research reference
(`references/writing-for-humans.md`) that stays in the skill and is
never copied downstream.

Origin: the owner's Freeside observation that agent-produced words
must be optimized for humans or they get disregarded. A research
pass (2026-07-27) substantiated it: humans read ~20–28% of on-screen
words and scan (NN/g); working memory holds ~4 chunks (Cowan 2001);
neural response to repeated warnings drops by the second exposure
and clinical alert override rates run high (46.2–96.2% across a
systematic review's studies); humans over-rely on AI output, and
engagement-forcing interventions reduce that where explanations and
a displayed confidence prompt did not (Buçinca et al. 2021, per its
§3.2 conditions and Table 1, checked against the paper after a
Codex round flagged the misattribution). Sources and evidence
grades live in the reference doc.

## Rejected alternatives

- **Smearing the guidance across existing sections** (pull-requests,
  finish-line): rejected; cross-cutting behavior gets one home, and
  the artifact formats already defined elsewhere stay untouched.
- **A standalone skill**: rejected; communication style is always-on
  behavior, not a task an agent loads a skill for.
- **A hard cap on questions total.** The owner flagged that real
  work often surfaces more than three questions. Resolved as a
  per-round cap: about three open asks at a time. Overflow splits by
  kind (tightened by a Codex review of the parallel free-prompts PR,
  swept here as the same class): questions a sensible default
  settles become vetoable visible assumptions, while gating
  questions queue for a later round, never silently assumed through.
  The same review bounded flag-rationing: uncertainty that changes
  how much to trust a result stays surfaced, per the over-reliance
  evidence. A second round moved load-bearing assumptions and
  caveats into the opening bottom line itself, so a scanner never
  acts on an unconditional headline.
- **Citing the research doc from the managed block**: rejected;
  managed blocks are copied into downstream repos where the skill's
  `references/` does not exist, so the evidence is compressed into
  the block's intro sentence instead.

## Split with free-prompts

The owner's personal system prompts (free-prompts, shared core) get
the same principles as conversational-output rules in a parallel PR;
the canonical section here governs durable project artifacts and
reaches agents that never run under those system prompts. The two
share the principle, deliberately not the text, so there is no sync
relationship. free-prompts' `chat/` payloads are deferred to a
tracker issue there.

Revisit when: new evidence contradicts a graded finding in
`references/writing-for-humans.md`, or observed agent behavior shows
a rule misfiring (e.g. the per-round ask cap suppressing questions
that should have been asked).
