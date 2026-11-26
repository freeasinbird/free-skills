# List-Ready Run Cache

`list-ready.sh` now keeps each PR's timeline and CI-run reads for the rest of
a landing run, checked on every list by one batched GraphQL read (#496).
Chose a per-run cache keyed on a label and force-push event count over
`updatedAt` or an all-GraphQL timeline, because the count moves on exactly the
events the cached reads depend on. A relist of unchanged PRs now costs the
same calls for one PR as for four.

## The Cache Key

- **What it covers.** The landing record's values, the PR's listing fields
  (draft, base, head branch, head OID, cross-repository flag, created time,
  labels), the batched count of `LABELED_EVENT`, `UNLABELED_EVENT`, and
  `HEAD_REF_FORCE_PUSHED_EVENT` items, and the PR's lines in the push log.
- **Why that is enough for filters 3 and 4.** Filter 3's approval time and
  actor come only from label events. Filter 4 uses force-push events after
  approval, which the count tracks, and CI runs created at or before approval,
  which already exist when the first list after approval reads them.
- **What stays fresh.** The approver's permission and the review threads are
  read on every list. A reviewer round found complete on the current head is
  reused; a missing round is reread.
- **What the cache stores.** Raw events and runs, not filter outcomes. Every
  list recomputes filters 3 and 4 from them, so the permission check runs in
  today's order and the exclusion reasons stay word for word.
- **A disagreeing timeline isn't kept.** When the REST timeline's event count
  differs from the batched count, the list uses the timeline but doesn't
  cache it, so a lag on either side rereads next time.

## Evidence

- **The count matches REST.** Planning compared `filteredCount` with the REST
  timeline's count of the same events on PRs 488, 492, 493, and 495; the
  refute-first reviewer repeated it on five more. All matched.
- **The query shape works live.** The script's exact query and `--jq` parsed
  correctly against `freeasinbird/free-skills`. A number that isn't a PR makes
  `gh` exit nonzero, so the list stops `LOOKUP_FAILED review-threads`.

## Rejected

- **`updatedAt` as the change signal.** Whether thread resolution or comment
  edits move it isn't documented.
- **Reading the timeline itself in GraphQL.** It needs nested pagination per
  PR, reports bot logins without the `[bot]` suffix the permission lookup
  needs, and CI runs have no GraphQL equivalent anyway.

## Refute-First Findings

One fresh-context reviewer tried to make a cached result admit a PR that the
old script would exclude.

- **Allowed by decision: a reused reviewer round.** If the reviewer edits its
  summary on the same head from complete back to in progress, a cached round
  still passes filter 6. The issue's contract chose this reuse; a completed
  round on that head did happen.
- **Allowed by decision: the batch gates every cheap-filter survivor.** A
  GraphQL failure now stops a list whose PRs would all fail filter 3 or 4,
  which the old script listed without GraphQL. It fails toward a stop.
- **Allowed: phase order picks the stop name when two reads fail at once.**
  A later PR's bad head or the batch can stop the list before an earlier PR's
  timeline read fails. Each stop name is still today's for its failure.
- **Allowed: a lagging CI-run read sticks for the run.** A run missing from the
  first read keeps excluding the PR at filter 4 until the run ends. It fails
  toward exclusion, and approval normally follows CI by far more than API lag.
- **Allowed: a list that stops before taking the lock leaves its cache.**
  Entries are fully keyed, so a later list under that run id can't misuse
  them; release removes them.
- **Disproved by checks.** The push-log grep anchors the number and a
  trailing space, so PR 12 never matches 123's lines. A garbage, truncated, or directory entry reads as a miss. The
  run id's validated shape keeps `rm -rf` in `release_lock` inside the
  push-log directory.

Revisit when GitHub changes which events `timelineItems` counts, or when a
filter starts depending on a forge read the key doesn't cover.
