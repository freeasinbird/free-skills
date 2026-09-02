# await-pr-review: the watcher names its gh failure and its open threads

Issue #207, worked as one unit. Both changes sit on a returned-object
trust boundary (the script trusts fields `gh` hands back), so this note
records the decisions and the refute-first pass AGENTS.md requires there.

## The retry notice passes gh's first stderr line through

Chose "keep the first line of `gh`'s own stderr, labelled by query, and
print it under the next notice" over "keep the four-guess message" and
over "print `gh`'s whole stderr". The 2026-09-01 transcript audit found
the four-guess notice (bad token, missing scope, rate limit, wrong repo)
in 48 sessions, and neither the agent nor the audit could tell which
cause applied. `gh` says which. The first line is enough: later lines are
usage hints and request IDs that would bury the cause under noise, and
the test shim now fails with a two-line error so the matrix proves the
second line stays out. A `gh` that exits without a message still gets its
exit status named, so the notice never goes back to being silent.

The lines live in a temp file rather than a variable because the scans
run in subshells; a variable set there is lost on return.

Review (PR 218, P2) found the one path that dropped the file unread: a
scan that failed part-way while the other scan found activity exited on
the positive evidence before any notice printed, and the EXIT trap then
deleted the cause. Accepted as a gap in the PR's own contract rather than
hardening: `references/detection.md` promises the cause on every failed
query, and the caller cannot tell a complete scan from a partial one
without it. A positive exit now prints the notice too; the positive
verdict itself stands, because a review that was seen was seen.

## A failed thread page fails the poll

Chose "a thread page that fails to load fails the whole poll, as the
count query does" over "report the count read so far". `unresolved_threads`
exists so an agent cannot call a round clean over open threads; a short
count would let it do exactly that over the threads on the page it never
saw. This is the same direction as the 2026-07-25 note's `polls_ok` rule:
when the watcher cannot see the whole PR, undercounting toward "could not
watch" is the safe error, and the cap already backstops a watcher that
gives up too readily.

The field is on every report line, including `CAP_EXPIRED`, as an integer
from the latest poll that read the threads or `null` when none did. It
counts threads open since before the baseline as well as new ones; the
watch attributes activity to a round, but an open thread blocks readiness
whichever round opened it (the quiescence rule in
`references/conductor.md` already said so; the field makes it observable).

Rejected: carrying the full rule in `SKILL.md`. The routing core is bound
at 220 lines and was at 219, so `SKILL.md` states the one-line rule and
names the field, and `references/detection.md` §watcher-invocation holds
the contract.

## Refute-first pass on the returned fields

Fields trusted: `reviews.totalCount`, `reactions.totalCount`,
`reviewThreads.nodes[].isResolved`, `pageInfo.hasNextPage`, and
`pageInfo.endCursor`, all from `gh api graphql` through one jq filter.

- A missing, null, or non-numeric count fails the poll: the jq filter
  emits a non-digit token and the script's digit check rejects it.
  Disproved by the "total API failure" and "unreadable thread page" cases.
- A page whose `isResolved` values are absent counts as zero open on that
  page, which is the one field the filter does not validate. Allowed:
  GraphQL returns the field as a non-null boolean by schema, so the only
  way to lose it is a failed query, which the digit check already fails.
- `hasNextPage` true with a null `endCursor` would loop on the same page.
  Allowed for the same reason: the schema returns a cursor whenever there
  is a next page, and a failed query fails the poll before the loop.
- The fixtures cover the continuation page by cursor; no live PR with over
  100 threads was available to poll.

Revisit when a live PR with more than 100 review threads is watched, or
when a reviewer is observed resolving its own threads, which would make
the count drop without agent action and change what a rising count means.
