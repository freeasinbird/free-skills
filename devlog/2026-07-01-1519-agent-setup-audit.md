# Agent-setup audit: procedures, canonical text, style sweep

Three-lens audit of the agent-setup skill (own read, fresh-context
reviewer, devlog sweep of prior decisions), then a five-commit revision.

## Decisions

- **SKILL.md procedures fixed**: init interviews before writing (order
  was inverted); the done-block exception folded into the compare step
  (it arrived three steps after "refresh every block"); marker
  validation added before any refresh (an unclosed marker would swallow
  project text); adopt-management specified (heading match, wrap as-is,
  then diff); reviewer-record decline got a middle path (refresh with
  record re-inserted verbatim, flagged) instead of permanently blocking
  the pull-requests block.
- **Canonical text genericized**: "paper/ink palettes", the compiled-CLI
  vs wrapper example, milestone-numbered commit example, and ungated
  `gh` commands violated invariant 2's extension to canonical
  conventions; now forge-neutral with gated "on GitHub:" examples.
- **One home per protocol**: finish-line steps 8-11 collapsed into a
  pointer at "Handing off the PR", which carries the watch machinery as
  two bullets (mechanism; baseline anchoring). Devlog entry-format
  mechanics live only in devlog/README.md; the canonical devlog section
  keeps the bookends and points there. `## To promote` is the literal at
  every grep site (finish-line step 6 had dropped it).
- **done placeholder**: the nested project:done-checks block shipped
  another project's checks verbatim against SKILL.md's fill-it-in
  instruction; now an explicit TODO placeholder, and "paste verbatim" is
  scoped to exclude it.
- **Style**: all em dashes replaced (judged per sentence) across the
  skill, mirrored managed blocks, scaffolded files, and unmanaged
  AGENTS.md sections; rule recorded as a Conventions bullet. Frontmatter
  converted to `>-` (sanctioned hardening).
- **New check**: `scripts/check-managed-sync.sh` makes managed-block
  drift a failing check instead of manual diff discipline; named in
  done-checks.

## Review rounds (Codex, PR #36)

- Round 1 P2 confirmed and fixed (folded into the script commit):
  exclusion-based extraction reported `ok: done` even when AGENTS.md lost
  its whole nested done-checks block. The script now validates every
  managed marker pair and the nested pair (exactly once, nested inside
  the done block) before diffing; the sweep also caught that a missing
  closing managed marker previously passed the presence check.
- Round 2, two P2s confirmed and fixed (folded into their commits): the
  script ignored unknown managed keys (a `managed:typo` block passed), so
  it now fails on any key outside the allowed set; and update-mode
  step 3's nested-marker validation contradicted the documented `done`
  opt-out (removing only the managed markers orphans the nested pair), so
  the check is scoped to when a managed `done` block exists and the
  opt-out text names the leftover markers as expected.
- Round 3 P2 confirmed and fixed (a recurrence of my round-2 half-fix,
  swept properly this time): the key scan assumed a `[a-z-]` alphabet, so
  `managed:typo_key` passed. Now any line that looks like a managed
  marker must exactly equal a canonical marker string, which also catches
  nonstandard spellings like a no-space `<!--agents-md:managed:done-->`.
  Verified against five malformed variants plus the clean state.
- Round 4 P2 confirmed and fixed, same class a third time: the marker
  scan anchored at column 1, so an indented marker passed. The scan now
  tolerates leading whitespace and case variants when hunting lookalikes
  (the exact-form equality still decides validity), and SKILL.md step 3
  states the contract generally: anything that merely resembles a
  managed marker is a malformation. Verified indented, tab-indented,
  uppercase, and indented-no-space variants all fail.
- Round 5 (PR #36) and PR #37 round 2, both confirmed and fixed: a
  spacing typo inside the tokens (`managed :done`) evaded the
  prefix-shaped scan, and count-only pairing accepted a close-before-open
  pair. The scan now keys on tokens, not prefix shape (any comment line
  mentioning agents + managed must be an exact canonical marker), and
  pairing checks order (open precedes close, managed and nested pairs).
  This is the categorical version of the fix the last three rounds
  approached variant by variant; SKILL.md step 3 says "matching close
  after it" to make order part of the contract.
- Round 6 P2 confirmed and fixed, a new finding (not the marker class):
  adopting an existing done section by wrapping it as-is creates a
  managed `done` block without the nested markers that step 3 then
  requires, dead-ending adoption. The adopt path now carries a stated
  exception: wrap the section's existing checks in the nested
  `project:done-checks` markers, text unchanged.
- PR #37 round 3, reproduced and fixed in both scripts (sibling-swept to
  check-managed-sync.sh though only the comparator was cited): the
  extraction awk toggled the nested exclusion with a regex
  contains-match, so an indented nested pair inside `done` hid changed
  managed text from the diff while exact-form validation stayed green.
  Extraction now honors exact marker lines only, and the token-based
  lookalike scan covers the nested pair as well.
- Round 7 P2 confirmed and fixed: mode detection classified a file whose
  only marker-like lines are malformed as "without markers" and offered
  adoption, deferring the step-3 malformation stop until after sections
  were wrapped. Detecting mode now runs the lookalike rule first and
  stops instead of adopting.
- Round 8 P2 confirmed and fixed: the scripts reject nested-marker
  lookalikes but SKILL.md step 3 scoped the lookalike rule to managed
  markers, leaving the manual path open to the same indented-nested-pair
  drift-hiding the scripts close. Step 3 now covers nested lookalikes
  and step 5's exclusion is pinned to exact marker lines.
- Round 9 P2 confirmed and fixed: the cross-product cell rounds 7 and 8
  left open; the pre-adoption stop covered managed lookalikes only, so a
  file whose sole remnant is a malformed nested marker fell through to
  adoption. Mode detection now names both marker families; a grep of
  every lookalike site in SKILL.md confirms all are aligned.
- Round 10 P2 confirmed and fixed, a genuine false positive from the
  round-5 broadening: an innocent comment containing the plain words
  "agents" and "managed" failed the required check. Both lookalike scans
  (managed and nested, both scripts) now key on the `agents-md`
  marker-family token, which every caught variant contains and prose
  doesn't; the nine-variant catch matrix re-verified intact.
- Post-review additions from a skill-creator assessment pass (user
  approved): a contents line in canonical-sections.md (it crossed the
  300-line reference threshold) and indirect-trigger phrases in the
  frontmatter description ("add a devlog / PR template / CONTRIBUTING").
  The assessment's bigger finding, a bundled compare script shipped with
  the skill so update mode's mechanical diff is deterministic, is a
  separate stacked PR.

## Rejected by decision (don't re-raise)

- Version stamps / pin mechanism on managed markers: premature; marker
  removal is the existing opt-out and no downstream deviation exists yet.
- Making the canonical devlog section a bare pointer to the README:
  bookends stay inline because they run every session; only entry-format
  mechanics moved.

## Deferred (still)

- CI workflow (open since 2026-06-16); the sync script lands without it
  and becomes a ready-made CI step later.

## Verification

- Every devlog-decided rule checked present after condensation
  (fold-fix, fix-the-class + mechanical sweep, don't-under-converge,
  reviewer-record identity, independence ladder + platform gate,
  PR-body-sync, docs-honesty, refute-first risk classes).
- canonical-sections.md 395 → 375 lines with the done placeholder and
  clearer watch bullets added in; net prose cut is larger than the line
  delta suggests.

## To promote

- Fix-the-class has a sharper form for validation/parsing code: the
  mechanical sweep is an adversarial enumeration of the input space
  (case, spacing, indentation, prefix/suffix, order, duplication,
  nesting), run once as tests, not a widening of the cited pattern.
  This review took eight one-variant rounds on the marker-validation
  class before the round-5 categorical fix; two later members
  (extraction regex, opt-out guard) still surfaced separately.
  Approved by the user 2026-07-01: promote as a refinement to the
  fix-the-class convention (canonical pull-requests section plus the
  AGENTS.md managed mirror, edited in sync) in a follow-up PR once
  #36 and #37 merge.
