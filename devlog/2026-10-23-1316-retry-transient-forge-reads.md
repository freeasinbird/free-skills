# Retry Transient Forge Reads in the Landing Scripts

Chose to retry a transient forge read inside the three land-approved-prs
scripts, so only a failure that persists or isn't transient reaches
`LOOKUP_FAILED`. Issue #352 carries the contract. A freeside batch on
2026-10-23 got five transient `LOOKUP_FAILED` results in an hour, all in
`land`'s CI wait, and one PR's run and its rerun both hit one, ending the
batch after a push.

## Decisions

- **Three attempts in `gh_read`, after 1 s and then 2 s.** Every failure in
  the incident cleared within seconds. A longer bound would mostly delay a
  real outage, which the SKILL's one rerun and the agent's reachability check
  still cover.
- **Classify by gh's stderr text, and default to transient.** gh exits 1 for
  every failure and prints the status only in its message. 401, 403, 404,
  and 422 are permanent, and so is a GraphQL lookup of something absent;
  everything else, including failures with no status such as
  `unexpected end of JSON input`, is transient. Rejected: matching a
  list of transient messages, since gh and Go word them many ways and a miss
  would end the batch. Misreading a new permanent message costs two retries.
- **A 403 that names a rate limit is transient.** GitHub answers its primary
  and secondary rate limits with 403s whose message names the limit.
- **The CI wait's poll loop is its retry.** Each poll reads once, a failed
  poll resets the consecutive-green count, and three failed polls in a row,
  a permanent failure, or a failed poll at the cap end the wait with
  `LOOKUP_FAILED`. Rejected: retrying inside each poll, which would stack
  three attempts per tick and wait longer for no gain.
- **The merge-state poll keeps one attempt per poll.** It already retried,
  and its deadline excerpt quotes the last failed poll on purpose (see the
  2026-10-18 note).
- **Buffer each attempt's stdout.** gh `--paginate` streams page 1 before a
  later page fails, and a failed read prints its error body to stdout. Without
  the buffer, a retry would append to that output; two copies of one merge
  queue rule read as ambiguous. test-land.sh covers it.
- **The SKILL keeps one agent rerun for a transient or unexplained failure.**
  The scripts' retry spans seconds; the rerun follows a reachability check and
  covers a longer outage and git's reads, which the scripts don't retry. A
  permanent failure still ends the batch.

## Refute-First Findings

The retry line is new stderr output built from gh's stderr, on the
surface that #313 hardened, so each attempt below tried to put a secret in
it.

- **`GH_DEBUG=api`, legacy `DEBUG=api`, `GODEBUG=http2debug=2`: disproved by
  a check.** The retry line reads the same debug-off capture as the excerpt.
  test-land.sh runs a retried read under each setting, and its fake gh's
  header line never reaches the script's stderr.
- **A spaced or nested `http2debug` in `GODEBUG`: confirmed, then fixed.** A
  fresh-context reviewer found Go turns the trace on whenever `GODEBUG`
  contains `http2debug=1` or `=2`, so `a=1, http2debug=2` and
  `x=http2debug=1` passed #313's filter. The gap predates this change, but
  the retry line is one more place gh's stderr appears. The filter now drops
  every element that mentions `http2debug`, and test-land.sh runs both forms.
- **The plan-gated 403 retried or misread: disproved by a check.** It's
  permanent, so `queue_check` sees one call and the same capture; the retry
  line goes to the script's stderr, never into `GH_ERR`.

## Review Findings

- **gh pr and GraphQL word permanent failures differently: confirmed, then
  fixed.** A fresh-context reviewer found only `gh api` writes
  `(HTTP 404)`. A live check with gh 2.99.0 showed `gh pr view` writes
  `HTTP 401: Bad credentials (url)`, and a GraphQL lookup of a missing PR or
  repository writes `GraphQL: Could not resolve to ...`. Both now classify
  as permanent.
- **A secondary rate limit retried after 1 s and 2 s: allowed.** GitHub
  advises waiting before retrying, but #352's contract names every rate
  limit transient. The cost is at most two extra reads per failed read.
- **`open_threads` no longer parses a failed GraphQL read: allowed.** gh
  prints partial data with GraphQL errors and exits 1; the old capture read
  that data as a thread count. Now the read fails closed with
  `LOOKUP_FAILED review-threads`.

## Revisit When

gh changes how it words a failed read, GitHub changes how it reports a rate
limit, a secondary rate limit outlasts a batch's retries, or a batch reports
a `LOOKUP_FAILED` after retries that a slower backoff would have cleared.
