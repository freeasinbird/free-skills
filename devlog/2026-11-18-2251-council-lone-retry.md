# Set Council's Retry Window for a Member Running Alone

Issue #415 closes a gap in the one-retry rule from #409
(`2026-11-18-2209-council-failed-seats.md`). That rule let a member wait out a
transient error only within a time budget or before the other launched members
returned. Findings staging launches the other provider's member alone first,
and the common pre-push call sets no time budget, so that member had no window
at all. A 30-second rate limit failed its seat and, for a usage-class error,
dropped the provider for the run.

## Decisions

- **The owner chose a fixed 2-minute cap over no retry.** A lone member with
  no time budget retries once after a stated reset at most 2 minutes away, or
  at once after a dropped connection. Otherwise its seat fails. No retry, the
  wording before this change, cost a provider on a short rate limit.
- **Chose a fixed cap over a wait shorter than a typical member run.** The lead
  can't know how long a run takes until it ends, so neither an agent nor an
  eval could apply that limit the same way twice.
- **Chose "running alone" to mean no other launched member is still running
  when the error arrives.** That covers the first staging member, a fix check,
  and a straggler whose peers have already returned. Each has the same
  problem: no other run sets the window. Judging at the error keeps a member
  whose peers return mid-wait from switching to the longer lone window.

The budget rule and the wait for other launched members are unchanged, and so
is the Caller Contract, so no caller needed an edit.

Revisit when a provider exposes reset times before launch, or when a caller
sets a time budget for pre-push review.
