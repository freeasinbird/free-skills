# Handoff Report Contract

The PR handoff now ends with a fixed five-part chat report: Status, Result,
Your call, Left for you, and Skipped, in 60 to 120 words with no headings or
tables. Chose a fixed, outcome-led report over the old step 7 rule ("State
that the PR is open and green. Name anything the reviewer should inspect
closely.") because that rule bounded nothing and never asked for the outcome,
the owner's calls, what was left for them, or what was skipped. Each session
improvised those and padded the rest with process. The owner specified the
shape in #344.

## Evidence

An analysis of 266 handoff reports in local session transcripts across seven
projects (2026-08-21 to 2026-10-22), with the owner's first reply after 246 of
them, found:

- **Reports were long and growing.** Median 318 words, p90 491; the monthly
  median rose from 227 to 331. The agent sent a median of three messages
  (462 words) between opening the PR and the owner's reply.
- **Shape varied widely.** There were 148 distinct four-word openers and 1,025
  distinct section labels; 37% used headings and 9% used tables.
- **Process narration filled them.** A median 54% of lines covered CI, the
  reviewer, the base, SHAs, the watch, the worktree, or lint. The commonest
  labels re-rendered the PR body's own sections.
- **What the owner acts on was often missing.** Only 35% said what the change
  does, 22% named decisions for the owner, and 67% stated the owner's next
  step plainly.
- **Length did not buy clarity.** Reports that drew a question had a median
  of 279 words against 317 for reports merged without one.
- **Replies named the gaps.** Owners asked what was left for them, what the
  change does, and how to proceed. Eleven replies found a PR reported green
  to be red or conflicting, most after a sibling PR landed first. Nine asked
  why a workflow step was skipped.

## Settled Points

- **The report lives in §handing-off step 7, not the managed block.** The
  pull-requests block gains a one-sentence pointer, so the payload loaded in
  every session barely grows. Rejected: writing the five parts into the
  managed block.
- **No project-specific slot.** A project that needs one more part declares
  it outside the managed block. Rejected: a placeholder part in the canonical
  report. None is known to be needed; freeside's merge-result audit line is
  covered by its CI since freeside #2084.
- **Skipped absorbs the step 1 sentence.** Step 1's "Say in the handoff
  summary that the record skipped the watch" arrived with the `none` reviewer
  record (`2026-10-21-0929-declared-no-reviewer.md`), and
  `2026-10-21-1315-no-reviewer-checks-wait.md` left that handoff text
  unchanged. A skipped watch is now one case of the Skipped part.
- **Status names sibling conflicts.** A report that says green but omits an
  open sibling PR on the same files led to most of the "not mergeable"
  replies, so Status names the sibling and the landing order.
- **Status keeps the base commit.** #344 dropped base lines because the PR's
  Verification carried them, but the PR-body contract (#345,
  `2026-10-21-2254-pr-body-contract.md`) landed first and moved the base
  commit out of the body and into the handoff. Status now names it, and the
  report drops only other SHAs. Rejected: dropping step 3's base-recording
  sentence, which changes a step this unit kept out of scope and reverses
  #345.
- **No new eval.** Forward sessions show drift soon enough.

Revisit when forward sessions show reports drifting from the shape, or the
owner asks for a dropped item back.
