# Detect Codex's review-summary comment as a fourth watcher signal

Tracker #220. `watch-review.sh` read reviews, review comments, and
PR-description reactions, so a clean round whose only evidence was Codex's
issue-comment review summary ran to the cap. This adds a fourth source and
records the choices its trust boundary forced.

## Match the Completed Row, Not the Comment

Chose to gate on the summary table's `Completed` row (its own `datetime` and
backticked short commit) over the comment's `created_at` or `updated_at`.
Codex posts one summary comment per PR and edits it in place every round, so
`created_at` predates every round after the first and `updated_at` moves for
reasons unrelated to a given head. The row carries the per-round completion
time and commit; nothing else does.

Chose to truncate the row `datetime` to whole seconds before the baseline
compare. GitHub stamps the baseline to a whole second, but the row carries
fractional digits. `"…:27.822096Z"` sorts before `"…:27Z"` because `.` is
below `Z`, so an inclusive request baseline at the same second would drop the
match without the `.[0:19] + "Z"` floor.

Chose to anchor the row regex on the marker, `**Completed**`, `datetime="`,
and a backticked run of 7 to 40 hex characters, and to pin the real row in the
test fixture, over a stricter parser. The reviewer owns the format; a change to
it should fail the matrix first rather than silently stop matching.

## Read the Summary First

Chose to read the summary source before the review and comment scans each
poll. Within a round the findings review lands a few seconds before Codex
edits the row, so reading the row first guarantees the later review scan sees
that review: a findings round then reports `REVIEW_ACTIVITY` and wins over the
row, instead of a race that reports the row while the review is still unread.

Chose to fail the poll on a failed summary read, exactly as a failed reactions
read fails it. Ending a round on the row is an absence-plus-presence verdict
that needs every source observed; the cap backstops persistent failure.

Chose to size the reviews and reactions backward walk one page above the last
full page (`total/100 + 1`), not the bare ceiling. The GraphQL count is read
once per poll; a review that lands after it and crosses an exact page boundary
sits on a page the ceiling skips, so the walk missed it. That was harmless
before, because the next poll's refreshed count caught it, but the summary
source can end the round on a Completed row in that same poll, before any next
poll. Probing the extra page catches the review in this poll, so
`REVIEW_ACTIVITY` still wins over the row. The empty extra page is the existing
over-count case and just decrements. A third review flagged this class (PR 231,
P2). A count stale by more than one page cannot happen at the sub-second poll
gap.

## Page Forward by since

Chose to page the issue comments forward from a `since` filter (floored one
minute early, the same offset the pending-request check uses) until a short
page, over paging until a baseline edge as the other three sources do. The
host filter is exclusive and compares `updated_at`, and returns the whole
window; the row filter enforces the precise boundary, so there is no edge to
cross.

## Exclude a Prior Round's Row on an Inclusive Request

Chose to snapshot the summary Completed row into the `request_artifacts` token
and exclude it, like the reviewer's review, comment, and reaction IDs. A
command-triggered re-review re-anchors the baseline to the request's whole
second inclusively, and the truncation above lets a row in that second match.
Without an exclusion, a prior round's row sharing that second ends the new
round before the reviewer runs, a false `CLEAN_PASS`. A first review flagged
this (PR 231, P2).

Chose to key the summary exclusion on the row's floored datetime, not a comment
ID, because Codex edits one summary comment in place: the stale row and the
round's future row share the comment's ID, so only the datetime distinguishes
them. The round's row is stamped later, so it is not in the snapshot and still
matches. The token's `s=` field is optional, so an earlier-format token still
parses; the producer always emits it.

The connector/API fallback prose in `detection.md` §connector-or-api-polling
carries the same snapshot-and-exclude instruction, so a shell-less
implementation matches the script. A second review of the same class flagged
that layer (PR 231, P2).

## Default Cap Under the Host Command Limit

Chose a default `--cap-minutes` of 9 over 25. Claude Code kills one foreground
shell command at 10 minutes, so a default run inside a conductor was killed
mid-wait. Each documented example passes the cap explicitly, and the docs now
say one wait is several bounded runs re-armed on the same baseline and head.

## Refute-First Findings

A fresh-context pass probed the fields the filter trusts from `gh`
(`user.login`, `.body`, and the row's `datetime` and commit) before commit.

- **Disproved by checks: no crash or false match on malformed input.** A null
  body from a non-reviewer comment does not error, because the `user.login`
  check short-circuits `and` before `contains(.body)`. A `**Completed**` line
  missing the `datetime` attribute or the backticked commit does not match, and
  an empty reviewer body does not match. Ran against `jq` directly.
- **Confirmed: the matrix detects the regression.** The new cases and the
  updated `CLEAN_PASS` format fail 11 assertions against the pre-change script
  and pass against the new one.
- **Allowed by decision: a non-ISO row `datetime` false-matches.** A garbage
  timestamp floors to a string that sorts after the baseline. Reachable only if
  the trusted reviewer bot malforms its own row, a format change the pinned
  fixture catches; it is not an untrusted or public input. The row shape is the
  documented trust boundary.
- **Allowed by decision: the part-way notice on a positive exit names comments
  and reviews only.** A `REVIEW_ACTIVITY` verdict rests on those scans; the
  summary status is immaterial there, and a summary `gh` error still surfaces on
  any non-terminal poll through the completion gate's retry.

## Revisit When

- Codex changes the summary row shape (renames `Completed`, drops
  `<relative-time>`, or lengthens the short commit). The regex and the fixture
  move together.
- A host raises or removes its foreground command limit. The default cap can
  then rise back toward the exchange cap.
