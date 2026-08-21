---
name: prompt-crafter
description: >-
  Write, edit, and review reusable agent prompts: system configuration
  payloads (CLAUDE.md / AGENTS.md style files, custom instructions) and
  pasteable chat instructions, for Claude, ChatGPT/Codex, and similar tools.
  Use when the user asks to author a new prompt payload, make a cross-cutting
  edit to shared prompt principles, review or audit existing prompts for
  adherence problems, align prompt variants across tools, or asks how well
  their agent config files actually work. Also use when the user mentions
  "prompt payload", "shared core", or "per-tool tail". Not for scaffolding
  AGENTS.md files or syncing managed workflow sections (the agent-setup
  skill's job), not for one-off conversational prompts, and not for API-level
  prompt engineering (tool schemas, application system prompts).
---

# Prompt Crafter

Prompt Crafter owns the craft of reusable prompt payloads: how to word,
structure, split, and verify instructions so the target model follows them.
Use it to review an existing payload set for the defects that erode
adherence, to make a cross-cutting edit across per-tool variants without
breaking their alignment, or to author a new payload.

Out of scope:

- Repo process (branches, PRs, decision logs): the host project's own
  conventions govern it.
- API-level prompt engineering (tool schemas, system prompts inside
  applications): a different craft with different constraints.

## Terms

- **Payload**: a prompt that ships and persists. A system configuration
  file (CLAUDE.md, AGENTS.md, and equivalents), a pasteable chat instruction
  block (ChatGPT Custom Instructions, Claude personal preferences), or a
  family of such variants kept aligned across tools.
- **Shared core**: the tool-agnostic block kept byte-identical between
  explicit markers in every system payload of a family; chat variants align
  behaviorally, not textually.
- **Per-tool tail**: the part of a family member outside the shared core,
  worded per that tool's tilt.
- **Tilt**: a tool's register (emphasis, structure, rationale, verbosity),
  tabulated in `references/authoring-rules.md`.
- **Compression donor**: the trim that funds an addition to a prompt at its
  character budget.
- **Prior-decision list**: the recorded owner decisions about the payloads
  at hand, what was decided and why.

## Procedure

Pick the workflow that matches the request; each has its own section below.

Review or audit an existing prompt set:

1. Load the prior decisions relevant to the payloads.
2. Read every payload in full, plus its mechanical facts.
3. Run the defect taxonomy yourself and file findings.
4. Get an independent fresh-context critique where your platform supports
   delegation.
5. Filter the findings on merits.
6. Surface the judgment calls to the user.
7. Apply, verify, and ship per the host project's process.

Cross-cutting edit:

1. State the principle once, tool-neutral.
2. Decide its home: shared core or per-tool tails.
3. Port it to any chat variant within its budget, funded by a compression
   donor, then check for qualifier loss.
4. Read each edited payload end-to-end, then verify.

Author a new payload:

1. Establish the target tool, surface, budget, and sync mechanism.
2. Write against the taxonomy inverted as a checklist.
3. Inherit the shared core verbatim if the payload joins an existing
   family.
4. Self-check the payload against its own style rules, then verify.

## Core model

Two ideas drive every workflow; the references expand them.

- **Prompts are weighed context, not enforced config.** The model weighs
  every sentence against everything else in context. Concision, clear
  structure, and unambiguous wording raise adherence more than volume or
  shouting. A hard guarantee needs a real gate (a hook, a CI check), never
  louder wording.
- **Shared core plus per-tool tail.** When one principle set serves several
  tools, keep a byte-identical tool-agnostic core plus a per-tool tail. A
  core edit is one edit applied identically to every file, verified
  mechanically by extracting and diffing the core blocks. Chat variants are behaviorally
  aligned, not byte-identical; their alignment check is a behavioral diff,
  not a text diff.

## References

The working knowledge lives in three references, loaded on demand:

- `references/defect-taxonomy.md`: the seven defect classes a review hunts,
  each with a live example and its fix pattern.
- `references/authoring-rules.md`: the writing rules, the per-tool tilt
  table with sources, and the shared-core pattern's consequences.
- `references/verification.md`: the mechanical check battery as
  copy-pasteable commands.

## Workflow: review or audit an existing prompt set

1. **Load the prior decisions relevant to the payloads under review.**
   - Read the host project's authoring conventions.
   - Read the decision notes the current issue or PR links, and any that
     name the payloads. Search the project's decision log, where it keeps
     one, by affected path, topic, or decision name, not by chronology.
   - Build an explicit prior-decision list and carry it into every later
     step, including any prompts you delegate.
2. **Read every payload in full**, plus the mechanical facts.
   - Character counts against any platform budget.
   - Greps for the styles the payload bans in itself.
   - The core-parity diff for a shared-core family.
3. **Run the defect taxonomy yourself** (`references/defect-taxonomy.md`).
   - File each finding with severity, file, section, the concrete problem,
     and draft fix wording.
4. **Get an independent fresh-context critique where your platform supports
   delegation.** Same-context self-review shares the blind spots that wrote
   the prompt; in practice this step has found the highest-severity defects.
   - If you can spawn a subagent (and session policy permits it), give it
     only the payloads, the authoring constraints, the prior-decision list,
     and the taxonomy as evaluation prompts. Instruct it to critique
     adversarially and propose draft wording.
   - Where delegation is unavailable or needs permission you don't have,
     skip it and lean on an external reviewer (a bot or a human), or ask the
     user. Never emit steps the running agent can't perform.
5. **Synthesize and filter on merits.** Not every finding ships.
   - Check each against the prior-decision list (see the recorded-decisions
     guardrail), the concision bar, and whether the fix's tokens earn their
     adherence.
   - Fact-check any capability claim ("the agent can't do X", "this is a
     user-side control") against current vendor docs before acting on it.
6. **Surface the genuine judgment calls** to the user as options with a
   recommendation. Do not silently make debatable changes.
   - Found in practice: delete inert rules versus keep them as
     notes-to-self versus move them to human-facing docs; which optional
     coverage additions earn inclusion.
7. **Apply, run the verification battery** (`references/verification.md`),
   and ship per the host project's process.

## Workflow: cross-cutting edit

1. **State the principle once, tool-neutral**: what, and why.
2. **Decide its home.**
   - Reads identically for every tool: the shared core, placed
     byte-identically in every file.
   - Genuinely diverges: each tail, worded per that tool's tilt
     (`references/authoring-rules.md`), never conflicting with the core.
3. **Port it to any chat variant within its budget**, using a compression
   donor.
   - Afterwards run the qualifier-loss check from the taxonomy's
     cross-variant-drift class.
4. **Read each edited payload end-to-end as its own agent would**, then run
   the verification battery.

## Workflow: author a new payload

1. **Establish the target**: which tool, which surface (synced config file
   versus pasted chat box), what character budget, and what sync mechanism.
   - A payload ships verbatim: markers and comments included.
2. **Write against the taxonomy inverted as a checklist.**
   - Only agent-addressable rules.
   - Gates unambiguous and instanced.
   - Absolutes rare.
   - One rule per bullet.
   - Rationale per the tool's tilt.
   - No rule without a reader who can act on it.
3. **Inherit the shared core verbatim** if the payload joins an existing
   family, and write only the tail.
4. **Self-check the payload against every style rule it declares for
   itself**, then run the verification battery.

## Guardrails

- **Respect recorded decisions.** A recorded owner decision is evidence,
  not a prohibition: never silently overturn one. If a finding conflicts
  with it, identify the prior decision, state which assumption or condition
  changed, and surface the proposed revision to the user instead of
  shipping it. The wording or formatting of a decided rule may be improved
  freely.
- **Don't confuse repo config with payload.** The conventions governing
  work on the prompt repo are not part of any payload, and payload rules
  don't govern the repo.
- **Don't fix adherence with volume.** If a rule keeps being ignored, the
  answers are structure, placement, instancing, or a real gate; never
  repetition or shouting.
- **Don't delete on memory.** Any "the agent can't do X" or "the CLI no
  longer has Y" claim gets verified against current primary docs in the
  same session; CLI capabilities drift fast.
- **Don't grow capped prompts.** At-budget files change by swap only: every
  addition names the trim that funds it.
- **Don't ship a half-sweep.** A defect class found once is grepped for
  everywhere (all payloads, all variants) and fixed as a class.
- **Read conventions from the host project, never embed them.** The
  prior-decision list, reviewer records, and shipping process differ per
  repo; this skill carries the craft, the host project carries its own
  decisions.
