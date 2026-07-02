# Defect taxonomy (review lens)

The classes a real audit of a multi-tool prompt family surfaced, ordered
roughly by severity. Every review pass hunts all of them. Each entry gives
the test that detects the class, a live example from that audit
(self-contained; wording quoted, not referenced), and the fix pattern.

## 1. Inert instructions

Rules the agent cannot act on because they name user-side controls: slash
commands the user invokes (conversation-clearing or compaction commands),
configuration the user owns (reasoning effort, model choice), decisions the
user makes (opening a new thread). These are advice to the human wearing an
instruction's clothing; the agent reads them, can do nothing, and at worst
wastes a turn apologizing.

- **Test:** can the agent, mid-session, execute this with its own tools?
- **Fix:** delete, reword to the behavior the agent does control ("suggest
  the user clear the conversation" instead of naming the command as if the
  agent could run it), or move to human-facing docs.
- **Caution:** verify the capability claim against current vendor docs
  before cutting; capabilities shift between CLI versions.

## 2. Internal contradictions

The top failure mode both vendors name: Claude may pick one instruction
arbitrarily; GPT/Codex oscillates and spends reasoning tokens trying to
reconcile the conflict (see the sources in `authoring-rules.md`). Includes
the subtle form found in practice: a shared section that points at a
tool-specific section for resolution ("see below for how this surfaces")
where the target section contradicts the pointer instead of answering it.

- **Test:** audit pointers as promises; every "see X" must be paid off by X
  without contradiction. Then check each rule against every other rule that
  could fire in the same situation.
- **Fix:** resolve the conflict at the source; one of the two rules is
  wrong, incomplete, or belongs to a different reader.

## 3. Ambiguous gate wording

Safety-critical sentences with two readings. Found live: "do not take
unclear destructive actions" parses as both "actions whose destructiveness
is unclear" and "destructive actions not clearly requested"; a safety gate
cannot afford either reading being the wrong one.

- **Test:** paraphrase each gate both ways; if two paraphrases diverge, the
  gate is ambiguous.
- **Fix:** gates must be unambiguous, and models act on instances better
  than categories: name the concrete cases the gate covers in a short
  parenthetical (`git reset --hard`, force-push, bulk deletes).

## 4. Adherence-hurting structure

A multi-sentence paragraph packing several independent rules gets its buried
rules dropped first. Found live: the two most user-visible rules in the
audited payload sat sixth and seventh of nine sentences in one paragraph.

- **Test:** count independent rules per paragraph; more than one is a
  finding unless the sentences form one sequential thought.
- **Fix:** one rule per bullet. Also catch the mechanical form: a missing
  blank line that fuses two separate rules into one rendered paragraph.

## 5. Cross-variant drift

When one variant is compressed (a chat budget) or re-registered (a terser
tool tilt), qualifiers get lost and guards get half-ported. Found live:
"hidden assumptions" compressed to "assumptions", which licenses the
contrarianism the same sentence forbids; and an anti-coaching guard ported
as a length rule, losing the register rule it existed for.

- **Test:** diff variants behaviorally, not textually. For each rule in the
  fuller variant, ask what behavior changes if the compressed variant's
  version fires instead.
- **Fix:** restore the qualifier or guard within budget, funded by a
  compression donor (see `authoring-rules.md`).

## 6. Coverage gaps that earn their tokens

Absence is only a defect when the missing rule is (a) tool-neutral, (b) one
or two lines, and (c) a genuine gate or high-frequency failure mode, not
process. The two that survived this bar in practice: secrets and credential
hygiene, and new-dependency-addition as a surfaced decision.

- **Test:** apply all three criteria; reject gap proposals that smuggle in
  repo-specific process.
- **Fix:** add the rule at the smallest wording that closes the gap, in the
  shared core if tool-neutral.

## 7. Stale or unverifiable claims

Assertions in the style of "current models are tuned against X" go stale
silently, and the payload has no mechanism to notice.

- **Test:** for each claim about model or tool behavior, ask whether it can
  be checked against a primary source today, and whether it will still be
  true after the next model generation.
- **Fix:** prefer wording that stays true regardless of vintage; where a
  vintage-bound claim is genuinely load-bearing, verify it against primary
  docs at review time.
