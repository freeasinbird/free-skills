# Count Hill-Climb Plateaus by Units Without Progress

Issue #411 carries the contract. This revises the plateau rule from the
first hill-climb note (`devlog/2026-11-18-1928-hill-climb.md`).

## Decisions

- **Chose units without progress over reverted attempts in a row.** A
  batched, council-scored idea climb hit its plateau while its best mean rose
  from 7.75 to 8.25 with a noise band of 0. Counting reverts treats a round of
  many misses as a stall, even when the best score is still rising. A plateau
  now means the best score, or a set goal's best near-miss, hasn't risen past
  noise for N units in a row.
- **Chose a named unit, attempt or round, over adapting the attempt rules ad
  hoc.** Without a unit for a batch scored in one check run, the climber had
  to translate the budget, minimum, and plateau into rounds, and it
  translated them too tightly. The goal file now names the unit, and every
  count uses it. The plateau defaults to 5 for attempts and 3 for rounds,
  since a round already scores many candidates.
- **Chose the budget as the cost guard over a tight plateau.** The check-in
  before a plateau stop offers one more unit with its cost and the budget
  left, instead of implying a stop. The budget stop always fires, even with
  judge-proposed candidates queued, so the proposal carve-out can't hold a
  climb open forever.
- **Chose accept and reject over keep and revert for set goals.** A goal that
  collects items, such as ideas that each meet a score rule, doesn't improve
  one artifact. A rejected item undoes nothing and isn't evidence of a stall.
- **Chose to handle judge-proposed candidates in hill-climb over changing
  council.** Council's Scoring Contract returns scores only, but judges
  proposed ideas anyway. Hill-climb queues them and scores them like any other
  candidate, ignoring a judge's score for its own proposal. Asking council
  for candidates would be a separate contract change.

Revisit when council's Scoring Contract starts returning candidates, or when a
climb shows the round default of 3 stopping too early or too late.
