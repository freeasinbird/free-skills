# Class-sweep auto-trigger from finding history (await-pr-review step 5)

Last of the in-scope leverage-ordered follow-ups from the frozen
`2026-07-02-0003-await-review-cost-signals.md` retrospective (#5). A step-5
policy addition to `await-pr-review/SKILL.md`; it reduces the number of review
rounds rather than per-round cost.

## Fixed

- Added two bold-led paragraphs at the end of step 5, in the thrash/half-fix
  region they extend:
  - **Finding-level class accounting + escalation.** Classify every finding as
    it arrives (any source) and sweep its class immediately per step 4 (the
    _first_ finding earns the sweep, not a second). The finding history adds an
    escalation signal: a class's **second member** despite that sweep means the
    boundary was too narrow, so widen it one level up and re-enumerate.
  - **Adversarial refute pass, auto-triggered on that second member.** A few
    parallel fresh-context lenses tasked to disprove the change, with the
    economics stated (round ≈ 1.5–3x main context + ~10 min; a 3-lens pass ≈
    one round's tokens and wall clock; pays once P(≥2 more preemptable rounds)
    ≳ 0.3–0.5, which a second same-class finding meets) and guardrails (one
    pass per PR, re-arm on post-pass recurrence, platform-gated with serial
    fallback, evidence-or-drop, don't fire on mixed-class nits/small/
    single-surface diffs).

## Decisions

- Scoped to the skill's step 5, not the canonical "Fix the class" convention.
  Promoting the general finding-level trigger into that broadly-inherited
  convention is a possible follow-up, deliberately left out to avoid growing a
  downstream-inherited convention in the same PR.
- Placed in step 5 (convergence) not step 4 (addressing), because the value is
  preempting future rounds; dovetails with the existing "sweep its siblings"
  half-fix text rather than duplicating it.
- Codex P2 on PR 49: the first draft read as gating the _initial_ class sweep
  on a second finding, which regresses step 4's fix-the-class rule (sweep on
  first sight). Reworded so the first finding still sweeps immediately and the
  second member is only the escalation/refute-pass trigger; folded into the
  content commit.
- Codex P2 (round 2): the refute pass was gated on "the same gate as step 4",
  but step 4's gate is delegation _with write access_; the lenses are read-only
  (disprove and report, never edit). Re-gated on read-only delegation (like the
  watcher), so a platform that allows read-only but not write delegation can
  still run the pass; folded into the content commit.
- Kept platform-agnostic (invariant 2): the refute pass is gated on delegation
  with plain serial sweeping as the fallback, no unconditional subagent step.
- Branched from `main` after PR 47 (#1) merged and rebased onto it, so this
  edit sits on top of PR 1's step-5 cross-reference without conflict.

## Deferred queue drain

Drains #5, the last in-scope item, from the frozen `2026-07-02-0003`
retrospective queue. With #1, #3, #4 already drained this session, the queue's
remaining items are: the round close-out script (#2, deferred by user
decision) and the two observation-only notes (keepalive re-derivation on a
pricing shift; Codex 👍 `createdAt` refresh on a later clean round).

## Follow-up (out of scope)

- Promote the finding-level class-sweep trigger into the canonical "Fix the
  class" convention if it proves general beyond automated-PR-review.

## Verification

- Passed: `npx markdownlint-cli2` and `npx prettier --check` on SKILL.md.
- Checked: no em dashes in the added block; frontmatter untouched and still a
  valid `>-` block scalar; the refute pass is delegation-gated with a serial
  fallback.
