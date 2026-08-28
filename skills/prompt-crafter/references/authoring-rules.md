# Authoring Rules (Write Lens)

## Writing Rules

- **Prompts influence agent behavior, but do not guarantee it.** The model
  weighs every sentence against everything else in context. Concise, clear,
  and unambiguous instructions work better than repetition or shouting.
- **Guarantees require enforcement.** Use a real gate, such as a hook or CI
  check, when compliance is mandatory.
- **Reserve absolutes for invariants.** Use `ALWAYS`, `NEVER`, and `MUST` only
  for safety rules and true never-actions. Use decision rules ("prefer X unless
  Y") for judgment calls. Newer Claude models over-trigger on aggressive
  emphasis (see sources below), so prefer normal phrasing in every variant.
- **Give gates examples.** Abstract categories under-fire, but a ten-word
  example list helps the gate trigger at the critical moment.
- **Structure matters.** Headers group, bullets isolate rules, and
  each rule's position matters. Models drop the middle of dense blocks
  first.
- **Only include instructions the intended reader can act on.** Before writing a
  rule, name who executes it (agent or human) and don't give an instruction
  to a party who can't perform it.
- **Prompts should follow the same rules they give the agent.** A prompt
  that bans a punctuation habit must contain none of it; models mimic their
  config's prose. Any style ban in a payload creates a mechanical
  self-check (a grep) for that payload; `verification.md` runs them.
- **If you need to add something to a capped document, shorten something
  else.** In a hard-capped prompt (ChatGPT Custom Instructions), plan every
  addition as a swap: find the trim that funds it, and prefer trims of implied
  content ("recommendation/next steps" to "recommendation") over trims of
  qualifiers ("hidden assumptions" to "assumptions"), which change behavior.

## Per-Tool Tilts

Use this table to tailor the wording for each tool. Keep tool-specific tone out
of shared text. Because the table can become outdated, check it against the
primary sources below whenever a major model generation is released, then update
the last-verified date.

| Axis      | Claude Variant                                                             | GPT/Codex Variant                                                                              |
| --------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Emphasis  | Use normal, explicit phrasing; reserve strong emphasis for true invariants | State each instruction once; reserve absolutes for true invariants                             |
| Structure | Use clear sections and numbered or bulleted steps when order matters       | Lead with the outcome, constraints, and success criteria; specify the output shape when useful |
| Rationale | Briefly explain why when it helps the model generalize                     | Keep rationale brief; emphasize the required outcome and checks                                |
| Verbosity | Be concise, but include enough explanation to make the reasoning clear     | Be brief and action-oriented; omit explanation that does not affect the decision or result     |

When a rule diverges per tool, variants should differ in wording and emphasis,
not intent. Most principles are genuinely tool-neutral and belong once,
verbatim, in a shared core.

### Sources (Last Verified 2026-08-24)

- Anthropic, "Prompting best practices"
  (<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>):
  recommends clear, explicit instructions and structured steps when order
  matters. It says context or motivation helps Claude generalize, and warns
  that aggressive language can over-trigger tools in some Claude models.
- OpenAI, "Model guidance"
  (<https://developers.openai.com/api/docs/guides/latest-model>): recommends
  lean prompts that state each instruction once. It also recommends
  outcome-focused prompts with constraints, success criteria, and an output
  shape, plus explicit guidance about what concise answers must preserve.

## Structural Pattern: Shared Core + Per-Tool Tail

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
