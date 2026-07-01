# Authoring rules (write lens)

## Writing rules

- **Prompts are weighed context, not enforced config.** Concision and
  clarity raise adherence more than volume or shouting. A hard guarantee
  needs a real gate (a hook, a CI check), never louder wording.
- **Reserve absolutes for invariants.** `ALWAYS`, `NEVER`, and `MUST` only
  for safety rules and true never-actions; decision rules ("prefer X unless
  Y") for judgment calls. Newer Claude models over-trigger on aggressive
  emphasis (see sources below); prefer normal phrasing in every variant.
- **Give gates instances.** Abstract categories under-fire; a ten-word
  example list makes the gate recognizable at the moment of action.
- **Structure is load-bearing.** Headers group, bullets isolate rules, and
  each rule's position matters: models drop the middle of dense blocks
  first.
- **Every instruction must be addressable by its reader.** Before writing a
  rule, name who executes it (agent or human) and route it to that
  audience's document.
- **Self-referential style rules apply to the payload itself.** A prompt
  that bans a punctuation habit must contain none of it; models mimic their
  config's prose. Any style ban in a payload creates a mechanical
  self-check (a grep) for that payload; `verification.md` runs them.
- **Compression needs donors.** In a hard-capped prompt (ChatGPT Custom
  Instructions), plan every addition as a swap: find the trim that funds
  it, and prefer trims of implied content ("recommendation/next steps" to
  "recommendation") over trims of qualifiers ("hidden assumptions" to
  "assumptions"), which change behavior.

## Per-tool tilts

Parameterize on this table; don't hardcode one tool's register into shared
text. Treat the table as data to re-verify against the primary sources
below, not gospel: it is the part of this skill that rots. Re-check it when
a major model generation ships, and update the last-verified date.

| Axis      | Claude variant                                   | GPT/Codex variant                                 |
| --------- | ------------------------------------------------ | ------------------------------------------------- |
| Emphasis  | Normal phrasing; caps over-trigger               | Same restraint; absolutes for invariants only     |
| Structure | Headers + bullets; scans structure like a reader | Plain hierarchical Markdown; no conflicting rules |
| Rationale | Give the why; generalizes from the explanation   | State rule and check; trim narration              |
| Verbosity | Concise but explanatory                          | Terser; biased to action                          |

When a rule diverges per tool, variants differ in wording and emphasis, not
intent. Most principles are genuinely tool-neutral and belong once,
verbatim, in a shared core.

### Sources (last verified 2026-07-01)

- Anthropic, "Prompting best practices"
  (<https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices>):
  confirms the rationale tilt ("Providing context or motivation behind your
  instructions ... can help Claude better understand your goals") and the
  emphasis tilt ("The fix is to dial back any aggressive language. Where
  you might have said 'CRITICAL: You MUST use this tool when...', you can
  use more normal prompting like 'Use this tool when...'").
- OpenAI, "GPT-5 prompting guide"
  (<https://developers.openai.com/cookbook/examples/gpt-5/gpt-5_prompting_guide>):
  confirms the contradiction cost ("contradictory or vague instructions can
  be more damaging to GPT-5 than to other models, as it expends reasoning
  tokens searching for a way to reconcile the contradictions"), the
  literalism ("follows prompt instructions with surgical precision"), and
  the structure tilt (Markdown only where semantically correct,
  hierarchical organization).

## Structural pattern: shared core + per-tool tail

For system payloads serving several tools: a byte-identical tool-agnostic
core between explicit markers, plus a per-tool tail. Consequences to
enforce:

- A core edit is one edit applied identically to every file; parity is
  verified mechanically (extract between markers, diff), never by eye.
- Anything tool-specific leaks if placed in the core, even a filename
  ("CLAUDE.md" versus "AGENTS.md"); keep the core filename-neutral and
  tool-neutral.
- Chat prompts are behaviorally aligned, not byte-identical; their
  alignment check is the behavioral diff from the taxonomy's
  cross-variant-drift class, not a text diff.
