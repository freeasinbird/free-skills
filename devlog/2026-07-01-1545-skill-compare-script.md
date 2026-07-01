# Bundle the managed-block comparator with the agent-setup skill

Implements the deferred finding from this session's skill-creator
assessment (see the 2026-07-01-1519 entry): update mode's mechanical
core (validate markers, extract blocks, diff) was rewritten by hand
three times in one session and drew three Codex P2s, which is exactly
the repeated-work signal that says bundle a script.

## Decisions

- One implementation, two consumers: the skill ships
  `scripts/compare-managed-blocks.sh` (read-only reporter; a missing
  block is the documented opt-out and tolerated by default;
  `--require-all` for strict use), and the repo's
  `scripts/check-managed-sync.sh` becomes a thin strict-mode wrapper
  over it. The review-hardened validation from PR #36 (exact-form
  markers, paired-once, nested pair inside a managed done block only)
  moved into the skill script unchanged in behavior.
- SKILL.md gates usage per invariant 2: shell-capable agents run the
  script for update-mode steps 3 and 5; agents without shell access
  follow the manual steps, which remain fully written out.
- Canonical path resolves relative to the script, so it works wherever
  the skill directory lands (verified from a simulated downstream cwd).

## Review rounds (Codex, PR #37)

- Round 1 P2: indented markers evaded the column-1 scan; already fixed
  by the base branch's round-4 fold, carried here in the rebase.
- Round 2 P2 confirmed and fixed: count-only pairing accepted a
  close-before-open pair, which would silently diff a broken boundary.
  Pairing now checks order (managed and nested pairs), and the lookalike
  scan keys on tokens rather than prefix shape, mirroring the base
  branch's round-5 fix.
- Round 3 P2 reproduced and fixed: extraction toggled the nested
  exclusion with a regex contains-match, so an indented nested pair hid
  changed managed text from the diff while validation stayed green.
  Extraction now matches exact marker lines only, and the lookalike scan
  covers the nested pair; sibling-swept to the base branch's
  check-managed-sync.sh in the same round.
- Round 4 P2 confirmed, fixed differently than suggested: a text-prefixed
  marker pair read as an opt-out. Codex proposed scanning tokens anywhere
  on the line, which round 3 already showed false-positives on
  backtick-quoted prose in the scanned files. Instead, the opt-out path
  now rejects a block whose exact marker string appears embedded
  mid-line (prose mentions use a `*` wildcard, never a real key's full
  marker text). Wrapper unaffected: strict mode already failed loud on a
  zero count.
- Round 5 declined by decision (don't re-raise): a prefixed
  case-variant no-space pair (`- <!--AGENTS-MD:MANAGED:devlog-->`)
  reading as an opt-out. Not a silent pass: the run prints
  "missing: devlog", a visible report the update flow reviews with the
  user, and step 7 offers reinsertion. Closing it needs low-precision
  matching over an unbounded mangle-space, with real false positives
  (prose lines carrying the marker prefix plus key names, and markers
  deliberately broken to disable tooling). Exact markers define
  management; the exact-fragment guard is the deliberate precision
  boundary.
- Round 6 P2 reproduced and fixed: with `done` opted out, an exact
  nested pair planted inside another managed block toggled the
  extraction exclusion and hid drift ("ok: branches"). The nested
  exclusion is now scoped to the `done` extraction only, so planted
  markers in other blocks surface as drift; the plain opt-out stays
  tolerated. Main's standalone check was never affected (it enforces
  the nested pair exactly once inside `done` unconditionally).
- Round 7 (user finding) reproduced and fixed: under pipefail,
  `raw_block | grep -qxF` falsely rejected a large done block; grep -q's
  early exit SIGPIPEs awk mid-write and the 141 reads as not-found.
  The containment grep now drains its input (no -q, stdout to
  /dev/null); a 1000-line done block passes and a relocated nested pair
  is still caught. Main's merged standalone script shares the bug, but
  this PR deletes that file in favor of the wrapper, so the fix lands
  with the merge.
- Round 8 P2 confirmed and fixed as a class, not an instance: the
  round-4 embedded-fragment guard only ran in the opt-out branch, so an
  embedded marker alongside a valid exact block passed. Replaced with an
  unconditional invariant: per key (and for the nested pair), lines
  containing the marker fragment must equal the exact marker lines; any
  excess is flagged whether the block is present, missing, or nested.
  Also swept the SIGPIPE class fully: the remaining early-exit pipe
  readers (`head -1` after grep) replaced with `grep -m1`, so no
  pipeline in the script has a reader that can exit before its writer.
- Round 9 P2 confirmed and fixed: extraction dropped the nested range
  without a placeholder, so a nested pair moved within `done` could
  compare equal and print "ok: done". Extraction now emits a sentinel
  line at the exclusion point on both sides, making the nested block
  position part of the comparison. Verified the moved-pair case exits 1;
  clean, large-block, and drift cases unchanged.

## Deferred

- Wiring the comparator into init mode's adopt-management path
  explicitly; the update-mode pointer covers the comparison it triggers.

## Verification

- Passed: full matrix on the comparator: clean sync, injected drift,
  mistyped/no-space/unpaired markers, done opt-out (tolerant exit 0,
  `--require-all` exit 1), and default-argument run from a downstream
  working directory.
- Passed: repo wrapper still exits 0 clean and 1 on drift.
