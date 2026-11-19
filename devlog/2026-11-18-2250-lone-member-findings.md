# Count a Lone Council Member's Findings in Pre-Push Review

Issue #416 closes a gap left by #409. Council's Rung 3 Contract now keeps a
lone completed member's confirmed findings, labeled a single review, not a
council. Pre-push review read a rung 3 report only as "use the fallback
reviewer it names", so it said nothing about those findings. The rule lives
in the managed `docs/agent-workflow.md`, which downstream projects inherit.

## Decisions

- **Chose to count the lone member's confirmed findings, then fall back,
  over letting the fallback reviewer start fresh.** Ignoring them lets a
  confirmed blocker go unacted on unless the fallback reviewer happens to
  find it again. Counting them as this round's confirmed findings puts them
  under the existing round rules: a blocker is fixed and re-reviewed, and a
  non-blocker is fixed, deferred, or declined per §review-convergence.
- **Chose council's confirmation as enough over asking the caller to confirm
  again.** Council's findings mode confirms each finding by reproduction or
  trace before reporting it, which is the same bar the **Count only confirmed
  findings.** bullet sets. The label "single review" marks the reduced
  independence; it doesn't lower the confirmation bar.
- **Chose to keep the fallback step over treating the lone member as the
  round's review.** One member isn't the panel the risk class asked for, so
  the fallback reviewer still runs, on the revision with the lone member's
  blockers fixed. Council's fallback is often a bot or human who reviews
  after push, so handing off first would push a known blocker. This corrects
  the expectation in `2026-11-18-2209-council-failed-seats.md` that
  `docs/agent-workflow.md` needed no edit.

Related: `2026-11-18-1926-pre-push-council.md`,
`2026-11-18-2209-council-failed-seats.md`.

Revisit when council's Rung 3 Contract changes what it reports for a lone
member.
