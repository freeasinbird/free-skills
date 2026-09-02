# Review Detection and Waiting

`watch-review.sh`, bundled beside `SKILL.md`, is the canonical executable
detector where a shell and host CLI are available. An API or repository
connector can implement the same detector contract when they can't. Read this
reference when capturing a baseline, detecting an unrecorded reviewer, invoking
the watcher, scheduling repeated wakes, or polling through a connector because
the script can't run.

The skill assumes an open PR, an automated reviewer that can be identified,
access to the host's reviews, comments, and reactions through either the
bundled script or an equivalent API or connector, and a permitted wait or
re-entry mechanism. A host CLI and shell are preferred, not mandatory. When
neither the script nor API-based detection can observe the required host data,
name that missing capability and hand control back rather than pretending to
watch.

## Contents

- [Event-anchored baselines](#event-anchored-baselines)
- [Snapshot sources and paging](#snapshot-sources-and-paging)
- [Reviewer identity and trigger](#reviewer-identity-and-trigger)
- [Signals and login forms](#signals-and-login-forms)
- [Watcher invocation](#watcher-invocation)
- [Main-owned mechanisms](#main-owned-mechanisms)
- [Connector or API polling](#connector-or-api-polling)
- [Scheduled wake contract](#scheduled-wake-contract)
- [Cadence and cap](#cadence-and-cap)

## §event-anchored-baselines

The baseline is the timestamp each poll compares activity against. Anchor it to
the event that should produce the pass, not to watcher startup:

- An open- or push-triggered wait uses the host's PR open/ready or push event
  timestamp.
- A manual no-push recheck uses the request timestamp and snapshots reviews
  already present when the request is made.
- A commit's authored or committed time is not a push time.
- A local or host clock reading taken after `git push` returns is later than the
  event and can silently bank a review that arrived in the gap.

Prefer a host event. The repository event feed carries `PushEvent` with a
timestamp and pushed head:

```sh
gh api --paginate "repos/OWNER/REPO/events?per_page=100" --jq \
  '.[] | select(.type == "PushEvent") | {created_at, ref: .payload.ref, head: .payload.head}'
```

The feed can lag, retains a bounded history, and does not show a fork's push in
the base repository. A force-push also appears on the PR timeline:

```sh
gh api --paginate "repos/OWNER/REPO/issues/PR/timeline?per_page=100"
```

Select `head_ref_force_pushed` and its `created_at`. A plain push creates no
equivalent timeline event; `committed` entries can have a null top-level
timestamp.

When no host event resolves, bound the event with two readings from the host's
clock:

1. Take the first immediately before the push. This is the watcher baseline.
2. Take the second immediately after the push. Keep it only to disambiguate
   matching activity; never pass it as the baseline.

Attribute an item by where it falls:

- An item after the second reading certainly postdates the push.
- An item between readings is ambiguous, so refetch it and keep waiting while
  attribution stays unresolved.

Early baselines are recoverable because the expected-head filter rejects much
superseded activity; late baselines silently drop the awaited pass.

If the exchange begins after the push and no host event resolves, the pre-push
reading does not exist. Do not invent a late baseline or report the round quiet,
clean, or complete. Record that this round can't be disambiguated, continue only
on activity that can independently be tied to the expected head/round, and carry
the attribution gap into the final ledger.

Use the host's `Date` response header, not the local clock:

```sh
gh api -i rate_limit 2>/dev/null | \
  awk 'tolower($1)=="date:"{sub(/^[^ ]* /,""); print}'
```

Convert the RFC 7231 date to whole-second UTC for `--baseline`. Keep the
fallback caveats in mind: replies on existing threads retain an old anchor,
reactions carry no commit, and GitHub can re-anchor a comment's `commit_id` as
the PR advances.

Whatever the baseline source, confirm which round a signal covered. This round
attribution matters because GitHub stamps a review with the head current at
submission, not necessarily the head the reviewer analyzed. A review already
running during a push can therefore land afterward and appear to cover the new
head. Clean-pass reactions are harder because they carry no head at all. This
attribution check belongs to the exchange owner and is not repeated later.

At the same boundary, record the expected PR head plus base branch and base tip
from the host. Pass the expected head to the watcher; retain the base for the
final freshness guard.

## Snapshot Sources and Paging

Capture three independent sources:

1. Top-level reviews, including state and body.
2. Review comments/threads, including replies on existing threads.
3. PR-description reactions used as progress or clean-pass signals.

An illustrative GraphQL snapshot is:

```sh
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  state isDraft closedAt mergedAt headRefName headRefOid baseRefName baseRefOid
  reviews(last:20){pageInfo{hasPreviousPage startCursor} nodes{author{login} submittedAt state body commit{oid}}}
  reviewThreads(first:50){pageInfo{hasNextPage endCursor} nodes{id isResolved comments(last:1){nodes{id author{login} createdAt body path line}}}}
  reactions(last:20){pageInfo{hasPreviousPage startCursor} nodes{content createdAt user{login}}}}}}' \
  -F o=OWNER -F r=REPO -F n=PR
```

Use time rather than enumerating and diffing IDs: a target-reviewer
`submittedAt`, comment `createdAt`, or status reaction `createdAt` after the
baseline is new. Read `comments(last:1)`, not the first comment, to detect a
reply on an existing thread.

Every single connection page is only a window. Page reviews, comments, and
reactions until the scan crosses the baseline. `watch-review.sh` does this
through REST. When hand-rolling, use the matching paged endpoints:

- `pulls/PR/reviews`
- `pulls/PR/comments`
- `issues/PR/reactions`

For terminal readiness, page the full `reviewThreads` connection to exhaustion
even when the visible page is resolved; an unresolved thread past the first page
remains blocking. Also compare both `baseRefName` and `baseRefOid` with the
recorded base; a same-tip retarget still invalidates integration evidence.

A terminal composite snapshot is valid only when all of these hold:

- The PR exists and its lifecycle state is open
- Every required query succeeded
- Every required scalar and collection is present with the expected shape
- Every required connection was exhausted

Treat any of these as incomplete evidence, not empty state:

- A missing required field
- A null where a field contract requires a value
- A malformed value
- A partial result
- An unpaged connection

Preserve documented nullability: `closedAt` and `mergedAt` are expected to be
null when `state` is `OPEN`.

Require two consecutive complete terminal composite scans with identical
canonical results. Compare across both scans:

- PR lifecycle, head, base, required checks, and pending push
- Every review, comment, and reply identity and timestamp
- The complete thread map, including every thread ID, `isResolved` state, and
  latest comment identity
- Page metadata

If any value differs, discard both mixed-time scans and restart until two
complete scans match. Individual page sequences or a partial boundary
fingerprint do not prove coherent state.

## §reviewer-identity-and-trigger

Establish identity in this order:

1. Use the project's recorded reviewer identity, API login forms, trigger, and
   progress/clean signals as a strong hint.
2. Otherwise scan recent PRs for a Bot/App account that submitted a review. CI
   bots that post checks are not reviewers.
3. If findings reviews never appear, scan PR-description reactions for a
   recurring bot signal shortly after PR events. That can identify a
   clean-pass-only reviewer.
4. A user assertion counts only if it names a reviewer/login that can be matched
   and identifies or establishes its trigger.

If more than one distinct review bot appears, ask which one to await. Past
activity reveals identity but not necessarily the trigger; establish whether it
runs on PR events, a command, or a CI job before polling. If the trigger cannot
be established, ask rather than burning the wait cap.

When a reviewer or status signal is newly observed, record its name, login
forms, trigger, and observed signals in the project's designated conventions
section. Augment an existing record that lacks newly observed signals. Never
record that no reviewer exists.

For an unrecorded reviewer scan recent PRs with `gh pr list --state all
--limit 20 --json number`, then page their reviews and reactions. An App bot's
reaction login usually supplies the REST form with `[bot]`; strip the suffix for
the GraphQL review form and record both. A machine-user reviewer keeps its plain
login.

Request a command-triggered reviewer once when no request is pending. An
acknowledgement or reaction on the trigger comment is not completion.

Treat a recorded reviewer as stale after two consecutive fully covered waits, on
events that should trigger it, produce no matching progress or completion
signal. Before another capped wait, rerun reviewer detection. Update the record
only when a replacement identity, trigger, or signal is actually observed.

## Signals and Login Forms

A round completes only on target-reviewer activity after the baseline:

- A submitted top-level review
- A new review thread
- A new comment on an existing review thread
- A configured clean-pass reaction on the PR description

An in-progress signal or acknowledgement means keep waiting; absence proves
nothing. Match reactions by `createdAt`, never bare presence, because a leftover
reaction from an earlier round can remain on the PR.

Read the latest review's state and body before declaring a pass clean. A
`CHANGES_REQUESTED`, or a `COMMENTED` review with a substantive summary, can
carry findings without an inline thread.

Author fields and login forms follow the API:

- GraphQL reviews and thread comments use `author.login`.
- GraphQL reactions use `user.login`.
- REST reviews, comments, and reactions all use `user.login`; those payloads
  have no `author` field.
- An App bot is commonly `name` for GraphQL review authorship and `name[bot]`
  for REST and reactions. A regular machine user stays plain.

`watch-review.sh` reads REST and normalizes either App-bot form. Use
`--rest-login` only for a machine-user reviewer or another form the automatic
normalization cannot derive.

## §watcher-invocation

Run the script by path from the PR checkout:

```sh
<skill-dir>/watch-review.sh --pr 46 --baseline 2026-07-02T05:07:30Z \
  --login chatgpt-codex-connector --head 9c346ab \
  --interval 75 --cap-minutes 25
```

Pass `--repo owner/name` whenever the working directory is not the PR's
checkout. Don't `cd` into a globally installed skill and rely on its repo
default.

Optional flags include `--rest-login`, `--clean-content`, `--progress-content`,
`--interval`, and `--cap-minutes`. `--reaction-login` is a deprecated alias for
`--rest-login`, retained for older callers. `--help` (or `-h`) prints the full
flag summary and exit codes to stdout and exits 0.

| Exit | Report            | Meaning                                             |
| ---- | ----------------- | --------------------------------------------------- |
| 0    | `REVIEW_ACTIVITY` | Review or review comment after the baseline         |
| 3    | `CLEAN_PASS`      | Clean-pass signal after the baseline, nothing else  |
| 2    | `CAP_EXPIRED`     | Cap reached; inspect coverage fields                |
| 64   | usage on stderr   | Invalid invocation; fix it rather than retrying     |
| 69   | note on stderr    | `gh` missing; this environment cannot run the watch |

Every report carries `unresolved_threads`: the PR's review threads whose
`isResolved` is false on the latest poll that read them, or `null` when no
poll did. The watch reports activity after the baseline, but this count
includes threads open since before it. A round is not clean while the count
is above zero, whatever the exit code; disposition each open thread before
calling it clean. A failed query prints a notice on stderr followed by the
first line of `gh`'s own error, labelled by query; a positive exit still
prints the notice for a scan that failed part-way. Read stderr for the cause
instead of guessing at the token, scope, rate limit, or repository.

For exit 2, `polls_ok:0` means no poll ever observed the PR. Otherwise the last
poll decides coverage because each poll rescans every source from the frozen
baseline: `last_poll_ok:true` proves the final window quiet; `last_poll_ok:false`
means the tail is unobserved. `in_progress_seen` is history across a multi-poll
run, but on a single final poll it means the reviewer was still active at the
deadline.

Every positive match still needs round attribution before it is accepted. If a
matched review/comment is stale, scan reactions separately because the script
exits on the positive item before reaching a clean-pass reaction. Branch on
every exit code, and report incomplete coverage as incomplete, not quiet. A
round ends only on the activity listed under Signals and Login Forms.

Keep one active watch per PR and reviewer. Start it promptly, before waiting
on required checks. After a new push, advance or replace its baseline instead
of leaving duplicate watchers alive. Checks stay a separate required wait; the
review detector does not prove them green.

## §main-owned-mechanisms

After emitting the required `Conductor skipped` line, a main-owned exchange
chooses the cheapest permitted mechanism that reliably re-enters the main
agent:

1. A background no-model `watch-review.sh` process whose completion re-enters
   the agent, when a shell and host CLI are available.
2. A read-only watcher subagent on the smallest capable model, when
   background-process re-entry is absent.
3. A cancellable scheduled API or connector poll, or script invocation, that
   uses the same frozen baseline and expected head on every wake.
4. A bounded foreground detector when the main agent can stay active through
   the wait, using the script or equivalent API or connector snapshots.
5. Hand back the baseline when none can run. Name the missing capability
   rather than pretending to watch.

The watcher-only subagent is not the conductor. It must not edit, commit, push,
trigger a review, reply, or resolve threads. It reports compact IDs,
timestamps, states, paths and lines, the top-level review body, status
reactions, and checks state.

## §connector-or-api-polling

When the exchange owner has no shell or host CLI, reproduce the watcher contract
through the available API or repository connector. Use the exact baseline and
expected head for every poll, both frozen at the event boundary: never replace
them with the current time or latest head.

Each poll pages the three snapshot sources until it crosses the baseline:
top-level reviews, review comments including the latest replies on existing
threads, and configured PR-description reactions. Normalize the review and
reaction login forms, apply the completion rules above, and confirm round
attribution before accepting a match. A progress reaction keeps the loop active;
it is not completion.

Keep the loop bounded to the same 20–30 minute overall cap and roughly 60–90
second cadence when the connector can wait without waking the model. If each
poll wakes the model, use roughly 4–5 minutes and the scheduled wake that
resumes the same conductor without releasing exchange ownership. The routing
gate must establish that blocking wait or scheduled-wake capability before the
conductor starts; instantaneous connector reads with scheduling only for the
main agent require a main-owned exchange.

At the cap, take one final complete snapshot and report the equivalent of script
coverage: polls or snapshots completed, whether the last one succeeded, whether
progress was seen, and whether the final window is covered. A failed final
snapshot is an incomplete tail, not a quiet round.

Map outcomes to the script semantics so later workflow steps do not depend on
the transport: review activity, clean pass, covered cap expiry, or broken or
incomplete observation. Connector-only access changes how the exchange owner
polls, not what counts as a completed round. Under conductor ownership, grant 2
supplies the blocking wait or scheduled same-conductor wake. Under main
ownership, the mechanism ladder can use a scheduled connector or API poll even
when scheduling cannot target a subagent.

## Scheduled Wake Contract

A scheduled wake changes re-entry, not detection. Every wake executes the same
detector contract, through the script or equivalent API/connector snapshots,
with the exact frozen baseline and expected head. Never recompute either value.

On each wake:

- Review activity or clean pass: confirm round attribution, cancel if current,
  otherwise scan reactions and re-arm when unresolved.
- Covered cap expiry or quiet snapshot: re-arm unless the overall deadline has
  arrived. Two consecutive wakes with no successful complete snapshot make the
  watch broken rather than quiet.
- Invalid, unavailable, or incomplete detection: cancel and fix the call or
  transport instead of treating the round as quiet.

For the script these states are exits 0 or 3, exit 2 with its coverage fields,
and exits 64 or 69. Size each script cap just under the wake gap; a connector
wake normally takes one complete paged snapshot. At the overall deadline, run
one final `--cap-minutes 0` script poll or complete connector snapshot so the
tail is scanned, then stop and report quiet, pending, or incomplete. The
scheduler must be cancellable and must avoid overlapping runs.

## Cadence and Cap

A no-model poll can check every 60–90 seconds. Any path that wakes a model per
check should use roughly 4–5 minutes. These are separate layers: a scheduled
5-minute model wake can run the script every 75 seconds inside a four-minute
cap.

Bound the whole wait at roughly 20–30 minutes. A clean-pass signal usually ends
earlier. See `cost-model.md` only when auditing the cache-cadence tradeoff or
re-deriving these numbers.
