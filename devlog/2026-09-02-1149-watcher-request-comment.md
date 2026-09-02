# Move the request and record procedures out of the conductor brief

Tracker #227. During review of #224, Codex found an omitted step in the same
two sentences of `conductor-brief.md` in five consecutive rounds: the
reviewer-record sentence three times, the command-trigger sentence twice.
Each sentence summarized a multi-step procedure, and each summary dropped a
step. The brief's own recurrence rule names that pattern and prescribes a
tested check over more prose. This note records how each procedure was
re-homed and the choices made along the way.

## Request Procedure Into the Watcher

Chose a `--request-comment <text>` flag on `watch-review.sh` over a separate
request script or a longer sentence. The pending check, the post, and the
baseline re-anchor form one event boundary that must complete before the
first poll, and the watcher already owns the baseline. The brief now names
the flag in one clause and the connector loop applies the same rule by hand.

Chose the posted comment's `created_at` as the new baseline over the
response `Date` header the issue asked for. Both are host clock readings.
`created_at` is the request timestamp itself, already whole-second ISO-8601,
and it is never later than the response `Date`, so it can only err early,
which the expected-head filter recovers from. It also avoids parsing an RFC
7231 date portably without `date -d`.

Chose an exact body match by any author over the issue's "by the caller"
wording. A pending request is pending whoever posted it, and identifying the
caller needs a `user` lookup that fails under an installation token and adds
a failure path for no gain in correctness.

Chose to carry the text into the jq filter through `$ENV` rather than
interpolating it. The text then needs no character validation beyond
non-blank, and a quote in it compares literally. gh 2.93 was checked to
expose `$ENV` in `--jq`.

Chose exit 75 (`EX_TEMPFAIL`) for a failed pending check or post, before any
poll, over falling through to a quiet cap. An unposted request never draws a
pass, and an unchecked one could double-post. A retry is safe because a
request that did post is found as pending on the next run.

Chose an inclusive request-creation second after review exposed GitHub's
whole-second timestamp limit. A response can share the request comment's
`created_at`; a strict comparison then rejects it on every re-armed watch.
Ordinary open, ready, and push boundaries stay strict. The inclusive boundary
applies only after a new request or when a pending request is exactly at the
supplied baseline.

Chose to snapshot reviewer artifact IDs before posting after review exposed
the inverse race. An earlier-round review, comment, or reaction can share the
new request's whole-second timestamp, especially during a manual re-review of
the same head. The inclusive filters now exclude only IDs observed before the
post and retain genuinely new same-second artifacts across all three sources.
The watcher reports one compact token carrying those IDs so a re-armed watch
can preserve the exclusion set. Without that token, an inclusive pending
request stops before polling rather than guess which same-second artifacts are
new. Pending reviews are not snapshotted because submission keeps the review
ID; a review submitted after the request must remain visible.

Chose an RFC 3339 `+00:01` offset for the pending-comment query after review
exposed the exact-minute boundary. The API's `since` filter is exclusive, so
flooring `08:00:00Z` to its minute still excluded a request created then.
Writing that baseline as `08:00:00+00:01` names `07:59:00Z` without
platform-specific date arithmetic. A live read-only GitHub call confirmed the
offset form.

The pending check reads one page of issue comments filtered by `since`.
Comments on one PR since one baseline do not approach a hundred, so paging
until the baseline is crossed, as the three signal sources do, buys nothing.

## Record Procedure Into a Numbered List

Chose a five-step list in `detection.md` §reviewer-identity-and-trigger, with
no script, per the issue's non-goal. The path is rare and the steps are
ordinary git and host calls the conductor already performs. The brief points
at the list and no longer restates any step. The routing matrix pins the
list's first, third, and fifth steps and the brief's pointer, so a later edit
that drops a step fails the check instead of waiting for a review round.

## Refute-First Findings

A fresh-context reviewer tried to break the watcher change before it was
committed. Its findings and their outcomes:

- **Confirmed and fixed: a re-armed wake double-posted.** The pending match
  was strictly after the baseline, but the re-anchored baseline the watcher
  prints is the posted request's own creation second. A wake that hands that
  value back with the same text posted again. The match is now at-or-after
  the baseline, and the host's exclusive `since` filter is floored to the
  minute. A matrix case pins both.
- **Confirmed and fixed: the numbered list dropped the re-request.** The old
  brief's "re-watch from that push as in step 6" carried the command-trigger
  re-request by reference. Step 5 of the list now names `--request-comment`
  itself, the omission class this change exists to end.
- **Confirmed and fixed: the `created_at` shape check had no test.** Deleting
  it left the matrix green. Three cases now feed fractional seconds, an
  offset, and `null` and expect exit 75 with nothing watched.
- **Allowed by decision: a transient failure of the pending check is fatal.**
  The mid-poll scans retry because the cap backstops them; here a retry
  could double-post, so the script stops and the caller retries once the
  cause on stderr is read.
- **Allowed by decision: the pending check reads one page.** Recorded above.
- **Disproved by a check:** `$ENV` quoting and injection, the shim's `posted`
  marker on a failed post, no-flag regressions, the temp-file trap on exit
  75, and flag ordering relative to repository resolution and the deadline.
- **Confirmed and fixed: a re-armed watch lost the artifact snapshot.** The
  first run now reports one opaque ID token, and the resumed watch requires it
  before using an inclusive pending boundary.
- **Confirmed and fixed: a pending review kept its ID on submission.** The
  pre-request snapshot now includes submitted reviews only, so a later
  submission with the same ID remains visible.
- **Disproved by the request-boundary invariant: a prior-round artifact cannot
  arrive between the snapshots and post.** A new request starts only after the
  prior target-reviewer round is quiescent. No target artifact remains in
  flight during that interval.
- **Confirmed and fixed: a lost post response stranded the snapshot token.**
  The watcher now builds and reports the token before posting. A retry reuses
  it whether the request exists or must be posted again.
- **Confirmed and fixed: the recovery report was missing from the interface
  docs.** The public help and both caller tables now name
  `REQUEST_INCOMPLETE` and tell the caller to pass its token back.

## Revisit When

- A reviewer's command trigger is something other than an issue comment,
  such as a review request or a label. The flag then needs a second mode or
  a sibling.
- Either sentence draws a recurring omission finding again, which would mean
  the pointer itself is being re-derived.
