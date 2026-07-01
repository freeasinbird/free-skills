# Promote the fix-the-class refinement for validators

Drains the `## To promote` entry from the 2026-07-01-1519 audit entry
(frozen since #36 merged; per protocol the drain is recorded here, not
by editing it). User approved 2026-07-01.

## Decisions

- The fix-the-class bullet (canonical pull-requests section and the
  AGENTS.md managed mirror, edited in sync and verified by
  `./scripts/check-managed-sync.sh`) now states the sharper form for
  validation or parsing code: the mechanical sweep is an adversarial
  enumeration of the input space (case, spacing, indentation,
  prefix/suffix, order, duplication, nesting), run once as tests, not a
  widening of the cited pattern. Evidence retained in the sentence
  itself: pattern-widening spent eight review rounds on one class in
  PR #36/#37 before the enumeration closed it.
- Kept it to one added sentence plus the evidence clause; the bullet's
  existing sweep and convergence rules are unchanged.

## Verification

- Passed: `./scripts/check-managed-sync.sh` (managed blocks
  byte-identical after the paired edit).
- Passed: `npx markdownlint-cli2 '**/*.md'` and
  `npx prettier --check '**/*.md'`.

## To promote

- Make the comparator's failure matrix a regression test. The review
  cycle verified ~15 failure modes (lookalike variants, order, embedded
  fragments, moved nested block, SIGPIPE on large blocks, opt-out
  paths), but every verification was ad-hoc session shell; nothing in
  the repo re-runs it. A test script under `skills/agent-setup/scripts/`
  exercising the matrix against fixtures would make the newly promoted
  enumerate-once-as-tests rule literal for the very script that taught
  it, and protect the next comparator edit.
- Devlog protocol gap: a `## To promote` entry freezes when its PR
  merges, so the queue grep re-surfaces drained items forever. The
  devlog README template should state how a frozen entry is drained (a
  later entry records the drain; check subsequent entries before
  re-raising). Exercised for the first time by this very entry.
