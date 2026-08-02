---
name: await-pr-review
description: >-
  Wait for an automated PR reviewer (such as Codex) to post its review, then
  handle the feedback, without you having to tell the agent to check or poll.
  Use this after you open or push to a pull request that has an automated
  reviewer: starting the watch is the default follow-on, not something to ask
  whether to do; it watches for the bot's review (or its out-of-band
  clean-pass signal, such as a reaction on the PR description) and addresses
  it. It waits non-blockingly where platform support and session policy
  permit it (a
  delegated watcher/subagent that can notify or re-enter the main agent,
  backgrounded poll, or scheduled wake-up that re-invokes the agent when
  feedback lands), and only falls back to a bounded foreground poll when it must.
  When feedback arrives it auto-addresses the clear-cut findings and surfaces
  judgment calls for you, converging across the re-reviews that its own fixes
  trigger on a bar that rises with the rounds: blocking findings sustain the
  loop until it thrashes or a recorded checkpoint escalates, while later
  valid-but-non-blocking ones are fixed in a locally verified final push,
  deferred to a tracked follow-up issue, or declined, and the exchange hands
  off with a disposition ledger. It reuses the project's review-response
  conventions and does not replace human review. Not
  for when there is no automated reviewer, no open PR, or you only want a human
  to review.
---

# Await PR Review

Watch an open pull request for its automated reviewer (e.g. Codex), then handle
the feedback: the part you would otherwise do by repeatedly telling the agent
to "check the PR" or "poll for comments." This skill owns the **waiting and
orchestration**; the actual responses follow the project's existing review
conventions (it references them, it does not restate a weaker version).

The design goal is to **not block the main thread**: where the platform can
delegate a watcher that reliably notifies or re-enters the main agent, run a
backgrounded watcher, or re-enter the agent on a schedule (and policy permits
that mechanism), you keep working while it waits, and the agent comes back when
the review lands. Blocking is a last resort, used only where nothing else is
available.

Because the non-blocking watch does not occupy the main thread while it waits,
**starting it is the default after opening or pushing such a PR; don't stop to ask
whether to watch.** Asking "should I watch for the review?" is exactly the manual
polling this skill exists to remove; start the watch and keep working. Keep one
active watch per PR/reviewer; after a new push, advance or replace that watch's
baseline (anchoring rules: step 1) rather than leaving duplicate watchers
running. (Where the platform or
session policy can't watch non-blockingly, fall back per the ladder in step 3;
the gate is the available permitted mechanism, not whether to engage.)

## When to use it

- Right after opening a PR, or after pushing fixes to one, when an automated
  reviewer will post a review shortly: the default next step, handled without
  babysitting, not one to ask whether to do.
- Any time you would otherwise type "check the PR for comments" or "keep polling
  until the review shows up."

## When NOT to use it

- No automated reviewer is configured on the repo: there is nothing to wait for.
  Step 2 says how to tell: a recorded reviewer identity, a bot-authored review on
  recent PRs, or the user naming one.
- No open PR yet (open it first), or the change is on a branch with no PR.
- You only want a human review: this watches the bot pass, not a person.

## The loop

### 1. Resolve the PR and snapshot a baseline

Find the PR for the current branch (`gh pr view --json number,url`). Record a
**baseline** of what already exists so later you detect only _new_ activity.
**Anchor that baseline to the event that will produce the pass you're waiting
for, not the moment the watch starts.**

- **For an open/push-triggered wait**, capture the PR open/ready or actual
  push event timestamp at the event boundary (or read that event timestamp
  from the host). The reviewer often fires on PR open or push, so a pass can
  land after that event but _before_ you start the watcher; anchoring to
  watch-start would bank it as pre-existing and hand off unhandled.
- **Do not use the head commit's authored/committed time as a proxy for the
  push**: a locally created commit may predate already-handled reviews and
  only be pushed later.
- **A clock reading taken after the push is not the push time either.**
  Stamping `date -u` once `git push` returns puts the baseline later than the
  event, so a review landing in that gap is banked as pre-existing and the
  watch burns its whole cap waiting for a pass it already missed. Read the
  event from the host instead: the repository events feed carries a
  `PushEvent` with its own timestamp and the pushed head, and a force-push
  also lands a timestamped entry on the PR timeline. Both queries, and their
  caveats, are in `references/detection.md`.
- **Where no host event resolves, bound the baseline _before_ the push, not
  after.** Early is the recoverable direction: with `--head` passed (below),
  reviews of the superseded commit are filtered out, so much of the reopened
  window is inert. Late is silent, and drops the review you are waiting for.
  But the head filter is **best-effort**, and three things cross it: replies
  on existing threads are exempt by design (they keep an old anchor yet are a
  real completion signal), reactions carry no commit at all, and GitHub
  re-anchors a comment's `commit_id` as the PR advances.
- **So take two readings under this fallback, and keep their roles apart.**
  The pre-push one is the baseline you pass to the watcher. Take a second
  immediately _after_ the push and keep it only for disambiguation, never
  passing it as the baseline, which is what the clock-reading bullet above
  rejects. Then a signal later than the post-push reading provably postdates
  the push and is this round's; one falling between the two readings cannot
  be resolved, though that window is only as wide as the push took. Refetch
  the matching review, comment, or reaction to compare, and keep waiting
  while it stays unresolved. Take both readings from the **host's clock**,
  never the local one: you are comparing them against host-authored
  timestamps across a window only as wide as a push, so ordinary skew is
  enough to invert the ordering and admit a previous round's signal. Every
  API response carries the server time; `references/detection.md` has it.
  Holding neither reading, because you joined after the push, means you
  cannot disambiguate at all: say that at handoff rather than reporting the
  round quiet or incomplete as though you could.
- **Start the watch promptly**, before waiting on anything else (such as
  CI), so the window where a review can slip in unbaselined stays small.
  Reviewer activity after the captured open/push timestamp is new.
- **But when you _manually re-trigger_ a recheck with no new push** (the
  request-it-once path in step 2), the last push predates reviews you've
  already handled, so last-push anchoring would replay them and exit the
  wait instantly. Anchor that case to the **trigger/request time** instead:
  snapshot the reviews that exist _at the moment you request_ as
  already-seen, and treat only the reviewer's pass dated after that request
  as the awaited one.

**Whatever the baseline's source, confirm which head a pass actually covered
before treating it as this round's.** A correct host-event baseline is not
enough on its own: GitHub stamps a review with the head current at
_submission_, not the head it analyzed, so a review already running when you
push finishes afterwards and carries your new head, clearing both the
baseline and the `--head` gate while the push-triggered pass is still
outstanding. `watch-review.sh` documents that attribution as best-effort and
puts the confirmation on the caller. **The check is yours and nothing
downstream repeats it**: step 4 evaluates findings and step 6 reports,
neither re-validates which round arrived. The pre-push fallback only makes it
harder, since a clean-pass reaction carries no head at all and ends the wait
on an absence-based verdict with no review to read.

At the same cycle boundary, the main agent records the PR's expected head
commit plus its base branch and current base-tip commit, resolved from the host
rather than a possibly stale local ref. Pass the expected head to the watcher so
it can reject a superseded review; retain the base commit for step 6's final
reporting guard. Capturing the base does not make branch updates part of the
watcher's role.

Capture **three** things, because they are separate connections and a round
can show up in any one of them alone: top-level **reviews** (a bot can
complete a review with a summary or approval and _no_ inline findings), the
inline **review threads**, and the PR-description **reactions**, where some
reviewers signal review status out of band (see the status signals in
step 3).

Two rules govern the detection. **Prefer time, not enumeration**: treat a
round as arrived when the configured reviewer has a review `submittedAt`, a
review-comment `createdAt`, or a status-signal reaction `createdAt` (step 3)
_after_ the baseline; enumerate-and-diff of threads is edge-prone (paging,
first-vs-last comment, author filtering). And **page every source past the
baseline**: a single page is a window, not the collection, so enough newer
activity by other authors can push the item you are looking for out of it.
Reach for the full thread set only when you actually need it (e.g. to resolve
threads).

`watch-review.sh` (step 3) is the executable form of this detection, with
every source paged; prefer it over re-deriving anything. The snapshot query,
its field caveats, and the REST/GraphQL paging mechanics are specified once,
in `references/detection.md`; read it when the script cannot run.

### 2. Identify the reviewer, then ensure it's requested

You need enough **identity to match the reviewer's future reviews**: its account
login (the login you filter on in step 3, under a field name and a login form
that both depend on which API you read), not merely "some bot will
review." Establish it in this order; the **recorded identity is the primary
source, detection only a fallback**:

- **Recorded identity (primary).** If the project records its automated reviewer
  (per the "record a noticed reviewer" convention, typically an "Automated
  reviewer" entry in AGENTS.md), use it: the reviewer's name, login (mind the
  API-form caveat in step 3), trigger, and any recorded status signals (the
  in-progress and clean-pass indicators used in step 3). Treat it as a strong
  hint, not gospel: if repeated waits turn up nothing the note may be stale
  (reviewer removed), so fall through to detection.
- **Detection (fallback).** Otherwise scan recent PRs for a bot-authored
  review: a `Bot`/`App` author that submitted a _review_ is the reviewer (CI
  bots post checks/statuses, not reviews). Scan that bot's PR-description
  reactions too and record any status signals you observe: a reviewer that
  posts reviews only on findings rounds marks clean passes out of band, and
  a record missing the clean-pass signal still burns the full wait cap on
  every clean PR. A repo with no bot review on any PR can still have a
  clean-pass-only reviewer, detectable by its recurring reaction on PR
  descriptions shortly after they open (step 3); its reaction login yields
  the identity; record both login forms (login rule in step 3). Either
  way the scan yields both the gate (a reviewer exists) and the login to
  match; the full procedure (the commands, and deriving each login form) is
  in `references/detection.md`. **If the scan finds more than one distinct bot
  reviewer** (e.g. Codex _and_ CodeRabbit), don't auto-pick: "is a bot" can't
  disambiguate them, and step 3's login filter would reject the others as a
  "different bot" and stall; ask the user which to wait on (or require a record).
  Detection reveals the **login but not necessarily the trigger**: past reviews
  show who reviewed, not what starts a fresh one. Before treating the reviewer as
  ready to wait on, derive the trigger from project notes, reviewer docs, prior PR
  command comments, or host configuration; if you cannot tell it runs
  automatically, ask for the trigger instead of burning the capped poll.
- **Human-asserted, only if it identifies.** The user telling you a reviewer
  exists counts **only when it names the reviewer enough to match its reviews** (a
  login, or a name you can resolve to one); step 3 still filters by that
  login, so a bare "there is a reviewer" can't be matched. If the
  assertion lacks identity, ask for the login (and trigger) before engaging.
- **None of these → don't engage.** No record, no bot review in history, and no
  identifying assertion means there is nothing to match on; hand back (see When
  NOT to use).

**When you confirm a reviewer the project hasn't recorded, write the record**
outside managed blocks in a project-specific AGENTS.md section (per the
convention) so later sessions needn't re-detect: the reviewer's name, its
login/account identity (including the API-specific form when it differs), how
it's triggered, and any status signals you observed (an in-progress or
clean-pass indicator, step 3), so later watches can finish on them instead of
waiting out the cap. The same applies to an **existing** record that predates
signal recording: when you observe status signals it lacks, augment the
record in place rather than treating "already recorded" as done. Record only
a reviewer you observed, never its absence:
a stale record naming a removed reviewer costs at most a capped wait, while a
recorded "none" would silently skip a reviewer added later.

Any reviewer that posts through GitHub's review mechanism works here (Codex, a
Claude review action, CodeRabbit, and the like); only the bot login and the
trigger change. Reviewers differ on triggering: most run automatically on open
and on each push (Codex does both, and also accepts a manual `@codex review`);
some run only on a command comment, with reviewer-specific syntax; some run as
a CI/Action job on PR events. If yours needs a
trigger and none is pending, request it once; don't re-trigger on every poll.

### 3. Wait for new review activity, non-blocking where supported

The watch itself is mechanical: take the step-1 snapshot, compare timestamps
against the baseline, sleep, repeat. It needs no judgment until feedback
actually lands, so choose the mechanism by **cost, not capability**: the
cheapest one the platform offers that still reliably re-enters the main agent.
Two costs add up: what runs while waiting (the watcher), and how the main
agent resumes (every re-entry replays the whole main context as input tokens,
so mechanisms that wake it once beat mechanisms that wake it per check).
When a conductor owns the loop (step 4), apply this same rule from inside
its context, where the ranking inverts: a bounded foreground poll blocks
only the conductor and costs nothing while it waits, so it wins there.

Watcher side, cheapest first:

- **Backgrounded no-model poll (preferred wherever the platform can run a
  background process whose completion re-invokes the agent; backgrounding
  alone is not enough, since without the re-entry the loop finishes into a
  turn that never resumes).** Launch a background shell loop that re-checks the PR
  on an interval and exits when new reviewer activity appears past the
  baseline (in Claude Code, a `run_in_background` shell loop); the harness
  then re-invokes the agent once to handle it. This costs zero tokens while
  waiting and wakes the main agent exactly once: the loop only answers "is
  there reviewer activity after the baseline?", a timestamp comparison that
  needs no model. On GitHub, don't write the loop by hand: this skill ships
  `watch-review.sh` next to this file. Invoke it **by path, from a checkout
  of the PR's repository**, where `<skill-dir>` is the directory holding
  this file (its path differs per platform and install):

  ```sh
  <skill-dir>/watch-review.sh --pr 46 --baseline 2026-07-02T05:07:30Z \
    --login chatgpt-codex-connector --head 9c346ab \
    --interval 75 --cap-minutes 25
  ```

  Don't change directory into the skill to run it. `--repo` defaults to
  whatever repository the working directory belongs to, so from a globally
  installed skill's own directory (the usual install) that default either
  finds no repository or silently resolves the wrong one and watches _its_
  PR 46. **Pass `--repo owner/name` explicitly whenever the working
  directory is not the PR's checkout.**

  `--login` takes either login form; the watcher reads REST only, so it
  derives the one REST-form login it matches all three sources on (override
  with `--rest-login <login>` for a machine-user reviewer, which carries no
  `[bot]` suffix; `--reaction-login` is a deprecated alias for the same
  option, kept for callers written before the flag covered all three
  sources). `--head` is the expected head SHA, so a stale pass
  against a superseded head does not end the wait. Also available:
  `--clean-content` /
  `--progress-content` for a reviewer whose status reactions differ from
  👍/👀, and `--interval` / `--cap-minutes` for cadence and cap. It
  implements the step-1 detection and the matching rules below, and exits with a
  distinct code plus a compact one-line report, so the caller branches on
  the exit code without parsing prose:

  | Exit | Report          | Meaning                                             |
  | ---- | --------------- | --------------------------------------------------- |
  | 0    | REVIEW_ACTIVITY | reviewer review or review comment past the baseline |
  | 3    | CLEAN_PASS      | clean-pass signal past the baseline, nothing else   |
  | 2    | CAP_EXPIRED     | the cap ran out (see `polls_ok` below)              |
  | 64   | usage on stderr | bad or missing flags: fix the call, don't retry     |
  | 69   | note on stderr  | `gh` not on PATH: this environment cannot watch     |

  Branch on all five: treating 64 or 69 as "no review arrived" reports a
  broken call as a quiet reviewer. **Exit 2 is not by itself a quiet PR**,
  so read the payload's coverage fields before reporting one. `polls_ok:0`
  means no poll ever observed the PR (bad token, missing scope, rate limit,
  wrong repo, each logged on stderr): report "could not watch." Otherwise
  `last_poll_ok` decides, because every poll rescans each source from the
  baseline, so the final poll's scan is what covers the whole wait: `true`
  means the window really was quiet, while `false` means coverage stops at
  an earlier poll and the tail went unobserved, however many polls
  succeeded. Report an incomplete watch as incomplete; a source that never
  scanned is not a source that was quiet, and a reviewer whose clean pass
  leaves only a reaction is exactly the one such a gap hides. Where `gh`
  or a shell is missing, hand-roll the watch from the specification in
  `references/detection.md`; it is the same detection the script
  implements.

- **Delegated watcher / subagent (only where background processes are absent
  but subagents are available and permitted).** If the session policy permits
  delegation without asking, and the platform will reliably notify or
  re-enter the main agent when the watcher finishes, delegate a watcher-only
  task. The watch is mechanical, so run it on the **smallest, cheapest model
  class the platform offers** (a frontier-class watcher buys nothing), and
  have it poll inside one long-running command rather than one tool call per
  check, since each tool call replays the watcher's own growing context. Give
  it the repo, PR number, configured reviewer login and status signals,
  expected head SHA, and baseline event time. It should poll until reviewer
  activity appears on that head or the bounded wait expires, then report
  **compactly** (IDs, timestamps, state, path/line, never thread dumps; the
  report lives in the main context for the rest of the session): the matching
  review's ID, state, `submittedAt`, and body; unresolved actionable threads
  with thread/comment IDs and path/line; any status-signal reaction with its
  `createdAt`; and checks status. If the watcher cannot fetch the top-level
  review body, it must say so explicitly and tell the main agent to refetch
  it before declaring the round clean. The watcher must not edit files,
  commit, push, post trigger comments, reply to review threads, or resolve
  threads. If delegation would require explicit permission that is not
  already granted, or completion would require the main agent/user to poll
  the subagent manually, skip this mechanism and fall through to the next
  available watch path.

Main-agent side: the default resume is a **single wake on activity**; the
watcher fires once and the main agent pays one full-context read, often
cache-cold when the review takes longer to land than a short prompt-cache TTL
(though a fast reviewer plus a tight no-model poll can instead land that wake
while the cache is still warm; see the cadence note below).
Where the platform can instead re-enter the agent on a timer (a scheduled
wake-up or self-paced loop), each wake replays the main context itself, which
is normally the costliest pattern; it becomes the cheaper one only in a
narrow case (the main context is large, the platform discounts cached context
reads steeply behind a short cache TTL, and the expected wait is short), and
then only up to the break-even: at typical pricing roughly ten cache-cadence
wakes, so waits up to ~45 minutes. Otherwise the single cold wake wins. The
cache-TTL arithmetic behind these numbers is derived in
`references/cost-model.md`.

**A scheduled wake changes the re-entry mechanism, not the detector.** Each
wake invokes `watch-review.sh` with the frozen step-1 baseline and a
`--cap-minutes` sized just under the wake gap, then branches on the exit
code. Rebuilding the review, thread, and reaction queries inside every wake
pays model tokens for a timestamp comparison, drifts from the script's paging
and login-form matching, and conflates the two cadences below; hand-roll from
`references/detection.md` only where the script cannot run at all. An
example, platform-neutral, on a 5-minute wake gap:

```text
Every 5 minutes until told to stop, run exactly this command for detection.
Do not rebuild the queries it already runs.

<skill-dir>/watch-review.sh --repo owner/name --pr 46 \
  --login chatgpt-codex-connector --head 9c346ab \
  --baseline 2026-07-02T05:07:30Z --interval 75 --cap-minutes 4

--baseline is the host's push-event time for head 9c346ab. Never recompute
it: pass this exact string on every wake.

0  REVIEW_ACTIVITY -> first refetch the matching review or comment and
   confirm it covers this round (step 1), whatever the baseline's source;
   nothing later re-checks this. Covered: cancel the schedule and go to
   step 4. Stale, or you cannot tell: read the reactions yourself, because
   a review or comment match ends the script's poll before it ever scans
   them, so a genuine clean-pass reaction stays hidden behind the stale
   item for as long as it sits there. A clean pass you can tie to this
   round finishes the round: cancel and report it. Only when that scan
   finds nothing, or nothing you can place, re-arm; expect this same exit
   every wake, because the script is stateless and that item stays past
   the baseline. The deadline below is what ends that loop.
3  CLEAN_PASS      -> same confirmation first, and it is harder here,
   since a reaction carries no head at all. Covered: cancel the schedule
   and report the clean pass (step 6). Otherwise re-arm, as above.
2  CAP_EXPIRED     -> nothing yet: re-arm. polls_ok:0 means this one wake
   observed nothing (rate limit, bad token, wrong repo, on stderr): re-arm
   anyway, and cancel only if the next wake is also polls_ok:0, since a
   few polls is too short a window to call a watch broken.
64 usage error     -> cancel the schedule. The call is wrong, not the PR;
   fix the flags before arming anything again.
69 gh missing      -> cancel the schedule; nothing here can run the script.
   Watch by hand from references/detection.md, or hand back.

The deadline bounds the schedule, not any one branch. At 25 minutes past
the baseline, whichever branch has been re-arming, run one final wake with
--cap-minutes 0 so a poll lands at the deadline itself: a wake stops
polling at its own cap, so the gap before the deadline would otherwise go
unscanned. Then stop and report. Quiet if that poll's last_poll_ok is
true; incomplete if it is false, or if activity is still replaying that
you could not tie to this round. in_progress_seen needs one distinction:
inside a multi-poll wake it is history, since the script sets it once and
never resets it, but the final wake runs a single poll, so a true there
means the reviewer was mid-review at the deadline itself. Report that as
pending rather than quiet.
```

Pass the **same** baseline on every wake. Each poll rescans all three sources
from it, so consecutive wakes leave no hole between them, while recomputing
it per wake drops exactly the review that landed in the last gap. Step 5
advances the baseline once per _round_, after a fix lands, never once per
wake. The script runs a final poll _at_ its deadline, so a wake's worst case
is the cap plus one poll: leave that much headroom in the gap, and have a
wake do nothing if the previous run is somehow still live. Detection is all
the script covers; required checks stay the separate poll they already were.
Every branch above cancels, so this path needs a scheduler the agent can also
**cancel**; without one, or without a scheduler at all, take the single wake
above or the bounded foreground poll below.

Remaining fallbacks, in order:

- **Bounded foreground poll (blocking fallback).** Only where none of the
  above exists: poll in the foreground with a hard cap, accepting that it
  blocks, and that it is the costliest per check: each foreground poll is a
  full-context round whose output then stays in the context for the rest of
  the session.
- **Hand back (last resort).** Where the agent can do none of these, report the
  baseline and ask the user to re-invoke once the bot has commented.

Cadence scales with what a re-check costs. A no-model background poll can
re-check every **60–90 seconds** (an API call is the only cost, and the
tighter loop cuts latency); paths where a model wakes per check should
re-check about every **4–5 minutes** (~270s also keeps a 5-minute prompt
cache warm). Either way, cap the total wait (e.g. **20–30 minutes**) before
reporting that no review arrived; a reviewer with a clean-pass signal (below)
usually ends the wait in single-digit minutes.

Those are two layers, not two options, and a scheduled wake runs both at
once: the **model cadence** is the wake gap, one full re-entry apiece, and
belongs in the 4–5 minute band, while the script's `--interval` is the
**API cadence inside a single wake**, 60–90 seconds and no model. Size
`--cap-minutes` just under the wake gap so a wake's script has exited before
the next wake starts, and keep the overall 20–30 minute cap in the scheduler:
the script caps only its own wake and knows nothing of the wakes before it.
Layering them this way is also why the next paragraph's warning about a
coarse ~270s grid does not indict a 5-minute wake gap: the grid it faults is
one that _detects_ at 270s, and here detection still happens at 75s.

The tight no-model cadence has a second payoff beyond latency: observed Codex
reviews landed 2m54s–4m46s after each push, so a ~75s poll tends to fire the
single wake while the main context is still cache-warm, where a coarse ~270s
grid would wake it cold: at typical pricing roughly a 12x swing on that one
wake read. Treat the band as observed for one reviewer, not a guarantee; the
observed-latency data and the warm-wake arithmetic are in
`references/cost-model.md`.

Finish a round on any of four signals from the configured reviewer, dated after
the baseline: a **submitted review**, a **new review thread**, a **new
review-comment on an existing thread** (a reply leaves no new thread and no new
submitted review, so this case is easy to miss; it is why the step-1
snapshot reads each thread's newest comment, not its first), or the
reviewer's **clean-pass status signal** (next
paragraph). All four must be **authored by the configured reviewer**, and
**the field you filter on, like the login form, follows the API you read,
not the kind of item** (the canonical login rule the rest of this skill
points at):

- **Field.** In GraphQL, reviews and thread comments expose their author
  under `author.login` while reactions expose theirs under `user.login`. On
  the REST feeds `references/detection.md` prescribes for paging
  (`pulls/N/reviews`, `pulls/N/comments`, `issues/N/reactions`), **all
  three** expose it under `user.login`; those payloads carry no `author`
  field at all, so a REST review filtered on `author.login` matches nothing.
- **Form.** GitHub returns an App-based bot as `name` in GraphQL review
  authorship but `name[bot]` in REST (e.g. `chatgpt-codex-connector` via the
  GraphQL `reviewThreads` vs `chatgpt-codex-connector[bot]` via
  `gh api repos/.../pulls/N/reviews`); its _reaction_ author carries the
  REST-style `name[bot]` form even in GraphQL; and a reviewer running as a
  regular machine-user account carries its plain login everywhere, under
  both APIs.

Match the field and the form to the API you are querying, or the filter
silently matches nothing and a real review looks like "no activity." Then:

- **Only the target reviewer finishes the round.** A human review, or a
  _different_ bot, posting after the baseline is **not** the awaited pass:
  this skill is scoped to the automated reviewer, so unrelated activity must
  not finish the round (else you stop early or auto-address the wrong
  feedback while the target reviewer is still pending).
- **An acknowledgement is not completion.** Some reviewers post a
  placeholder or react before the real review (Codex, for one, acknowledges
  an `@codex review` request and posts the actual review, with any inline
  findings, _afterward_); a reaction on your trigger comment or a
  placeholder is still _pending_, so keep waiting.
- **But don't depend on an ack either**: not every reviewer posts one, so
  key off the reviewer's actual response (any of the four signals above),
  never an acknowledgement that may never come.
- **Read state and body before declaring clean.** Treat it as "reviewed,
  nothing to address" only when the latest review adds no new unresolved
  threads **and** its `state` / `body` carry no actionable feedback: a
  `CHANGES_REQUESTED`, or a `COMMENTED` review with a substantive summary
  body, can hold findings with no inline thread at all.

Some reviewers also signal status **out of band**, on the PR itself rather
than through a review, and some post no review at all when a pass finds
nothing to raise. A watch that reads only reviews and threads therefore waits
out its full cap on a clean PR, then wrongly reports "no review arrived."
Codex, for one, reacts on the PR description: eyes (👀) while a review is in
progress, thumbs-up (👍) when a pass found nothing; on a clean first pass
that thumbs-up, minutes after open, is the only artifact the reviewer leaves.
Learn your reviewer's signals, record them with its identity (step 2), and
include the PR-description reactions in the step-1 snapshot.

- A **clean-pass signal dated after the baseline** is the fourth completion
  signal: the round finished as "reviewed, nothing to address."
- An **in-progress signal** works like the acknowledgement rule above: its
  presence means keep waiting; its absence proves nothing (the reviewer may
  remove it when the review completes).
- **Match on `createdAt`, never bare presence.** Reactions are
  one-per-user-per-emoji and mutable, and this governs **both** signals: a
  leftover clean-pass reaction from an earlier round predates the baseline
  and does not count, and a leftover in-progress reaction likewise means
  nothing about this round, so reading it by presence alone stretches the
  wait for a pass that already finished. The wait cap stays as the backstop
  when the signals are ambiguous.
- **Reactions expose their author under `user.login` in both APIs**, in the
  `name[bot]` form for an App bot, per the canonical login rule above; the
  GraphQL review-author form matches no reactions.

### 4. Address the feedback: auto clear-cut, surface judgment calls

For each new finding, follow the project's review-response conventions where it
has them (e.g. an AGENTS.md "Responding to automated review" section); the
essentials, project-agnostic:

- **Evaluate on merits.** Fix real findings; decline contrived, speculative, or
  already-fixed ones with a one-line reason. Do not reflexively comply.
- **Fix the class, not just the cited line.** Sweep the file/repo for the same
  class and fix every instance in the same push, so the next re-review doesn't
  flag the siblings one at a time.
- **Reply and resolve, in fold-then-reply order.** Where the project's commit
  conventions fold review fixes into their originating commits, the order is a
  gate, not a preference: **fix, fold, push, verify, reply, resolve.** Fold
  the fix into the commit it belongs to (mechanism per the project's
  convention or your judgment: a `fixup!` commit squashed by
  `git rebase --autosquash <target>~1`, noting that plain `--autosquash`
  squashes without `-i` only on Git 2.44+, that older Git needs the
  interactive form driven by a no-op editor, as in
  `git -c sequence.editor=true rebase -i --autosquash <target>~1`, with
  `-c core.editor=true` added when the range holds a `squash!` (on
  those versions its combined-message editor still opens, which fails
  or hangs an editor-less agent), and
  that a range holding a merge (a base-branch merge after `<target>`)
  needs `--rebase-merges` added, or the rebase silently flattens the
  merge; an `--amend`; or an equivalent rebase), push the
  rewritten branch (`--force-with-lease`), and **verify against the pushed
  ref, not local state**, that the SHA you are about to cite is reachable
  from the pushed head and actually contains the fix: run
  `git branch -r --contains <sha>`, confirm the PR head's
  remote-tracking ref is listed (resolve the head's actual remote and
  branch from the host; a fork PR's head is not `origin`), then inspect
  the commit on that ref (a botched fold can silently drop the edit).
  Only then reply inline with the
  disposition and that final commit SHA, and resolve the thread. When a
  round accepts several findings, the gate binds the round, not each
  finding: fold every accepted fix, push once, verify each SHA you will
  cite against that one final head, then write all the replies and
  resolve, since a per-finding reply lets the next finding's fold
  rewrite the SHA already cited. (A _later round's_ fold still rewrites
  earlier-cited SHAs; that churn is inherent to folding and accepted:
  each reply is a point-in-time record, and the PR body's subject-keyed
  commit map is the reference that stays stable.) Never write
  the reply first: a standalone fix commit's SHA is rewritten by the later
  fold, so a pre-fold reply cites a commit that will not exist, and a
  standalone "address review" commit left on the branch is an unfinished
  round, not a done one. Where the project instead appends fix commits, cite
  the fix commit as-is; the verify-on-pushed-ref step still applies. A
  decline pushes no commit, so reply with the reasoned decline alone; per
  step 5, a round of only declines ends the exchange rather than
  manufacturing a fresh pass on unchanged code.
- **Auto-address the clear-cut; surface the judgment calls.** Apply the
  obviously-correct fixes yourself. **Pause and surface** anything ambiguous,
  contentious, or design-altering for the user to decide; do not silently make
  a debatable change.

**Where to run the rounds.** By default the main agent addresses the feedback
itself: the watcher has already woken it, its context is warm, and it holds
the diff and the session's understanding of the change.

- **Delegate only when both hold**: the round is long (many findings, a wide
  class sweep, dozens of tool calls) **and** the main context dwarfs the
  fixer's brief. Delegation adds main-agent wakes and a context rebuild
  before it saves anything (`references/cost-model.md` derives this
  break-even and the persistent-fixer amortization below), so a short round
  (a few edits) is cheaper in the already-awake main agent, overhead
  included.
- **Gate it on the platform**: delegation with write access, permitted by
  session policy without asking.
- **Run the round in a fresh, compact fixer context**, briefed with the
  repo, the PR, the reviewer's identity and status signals, the current
  baseline, and a pointer to the project's review-response conventions.
- **The fixer inherits the auto/surface split above**, relocated: it
  auto-addresses the clear-cut findings, runs the project's verification
  checks itself and reports facts, and **reports judgment calls back rather
  than deciding them**.
- **Hold its report to the watcher's compactness contract**: fixing commit
  SHAs, a one-line disposition per finding, judgment calls with just enough
  quoted context to decide, never full diffs. Only that report crosses back
  into the main context.
- **Its reported SHAs are bound by the fold-then-reply gate** above:
  post-fold, pushed, and verified against the pushed ref, never a SHA a
  later fold will rewrite.
- **The main agent spot-checks only the judgment calls**, since re-verifying
  clear-cut fixes from the main context pays for the round twice.
- **Skip delegation** when the round is short, the main context is small, or
  the round is mostly judgment calls (each escalation wakes the main agent
  anyway, so the savings evaporate).
- **Unlike the watcher, the fixer needs a capable model class**: the savings
  come from context size, not model tier.

That break-even is stated **per round**, which makes short rounds look like
they never justify delegation. But a convergence loop is many rounds, and a
**fixer kept alive across the loop** amortizes the context rebuild a fresh
fixer would re-pay every round, while keeping each round's debris (its
findings and fixes) out of the main context, since only the compact reports
cross back (the amortization arithmetic is in `references/cost-model.md`).
So a persistent fixer likely wins on any longer exchange (roughly 4+ rounds)
even when each round on its own falls below the per-round break-even above;
the per-round rule still governs a one-shot round. Two honest caveats:

- It needs a platform that can keep a subagent **resumable across the main
  agent's turns** (in Claude Code, re-messaging the same agent instead of
  spawning a new one), so gate it like the delegated-fixer path above and
  fall back to in-main rounds where that is unavailable.
- The judgment calls still wake the main agent every round regardless.

The fixer's own context grows across the loop, which is the point, not a
cost: that growth lands in the small, cheap context instead of the fat main
one.

**Where the platform can also notify or re-enter the main agent when a
subagent finishes, promote the persistent fixer to a conductor that owns
the whole exchange.** Orchestration is the remaining per-round cost: even
with every fix delegated, the watcher wakes the main agent once per round
to advance the baseline, restart the watch, and apply the convergence
policy, and each wake replays the full main context. A conductor keeps
steps 1 through 5 inside the fixer's small context instead: brief it once
with the repo, the PR, the reviewer identity and status signals, the
current baseline and expected head, and a pointer to the project's
review-response conventions, then let it watch, fix, advance the baseline,
and ratchet the bar itself. The main agent then pays two wakes per
exchange (spawn and terminal report) plus one per surfaced interruption
(judgment call or checkpoint escalation; two when user-routed, the
answer being a second turn), instead of one or more per round
(`references/cost-model.md` has the whole-exchange arithmetic).

Inside the conductor, re-pick the step-3 watch mechanism by the same cost
rule, which now lands differently: a bounded foreground `watch-review.sh`
call blocks only the conductor, costs no model tokens while it polls, and
needs no re-entry machinery, so it becomes the preferred watch there. The
conductor inherits everything this skill binds on whoever runs the loop:
the step-1 baseline and attribution rules, the fold-then-reply gate, the
step-5 ratchet, checkpoints, and thrash rule, and the compactness contract
on what crosses back. It surfaces judgment calls, checkpoint escalations,
and the terminal disposition ledger to the main agent rather than deciding
them, and the main agent (or user) answers by resuming the same conductor,
never by spawning a fresh one. The near-free wait also rescopes step 5's
no-wait handoff: the conductor waits out the re-review its own final
push triggers and issues the terminal ledger only at quiescence (step 5).

Gate the conductor on the full grant it needs: write-capable delegation,
resumable across the main agent's turns, whose completion reliably
notifies or re-enters the main agent, plus checkout isolation for the
branch it rewrites. The conductor edits, folds, and force-pushes across
the whole exchange while the main agent's thread is free, so the two
must never share a mutable checkout: an interleaved main-agent edit can
be swept into a fold, and its half-finished verification invalidated
mid-run. Give the conductor its own worktree, checkout, or clone where
the platform supports one; otherwise grant it exclusivity over the
shared checkout. Where any part of that grant is missing, fall back to
the persistent fixer with the main agent keeping the loop, then
per-round delegation, then in-main rounds, exactly as above.

Whatever form the isolation takes, align it before the first write: the
conductor verifies its checkout's HEAD equals the expected PR head
recorded in step 1, resolved from the host, before any fix or fold. A
fresh clone starts on its default branch and a worktree can be cut from
any branch, and the pinned lease below cannot catch the mismatch, since
it checks only what the remote held, not what the push would replace it
with; a rewrite built on stale history force-pushes the PR's commits
away. On a mismatch, stop and re-anchor on the fetched PR head rather
than editing. The same pre-write check covers cleanliness: a checkout
already holding tracked or untracked edits can see them swept into a
fold and force-pushed as the PR's own work, so the conductor also
requires a clean worktree and index before its first write, stopping
to surface any pre-existing changes instead of committing them.

Two further edges of that isolation bind for the conductor's whole run.
Exclusivity ends when the exchange terminates with the terminal
ledger, not when the conductor pauses: a surfaced judgment call or
checkpoint escalation resumes the same conductor afterward, so a
main-agent edit to the branch during the pause is exactly the
collision above; a change the human wants on the branch mid-exchange
goes through the conductor, or ends the exchange first. And any fetch
of the PR branch into the conductor's checkout (a worktree shares the
main checkout's refs, and a separate clone's own fetch advances its
tracking ref the same way) updates the value a bare
`git push --force-with-lease` checks against, blessing an overwrite
of whatever that fetch brought in; so the conductor pins every
rewrite's lease explicitly, whatever the checkout type.

Pin the lease to the conductor's own last pushed head
(`--force-with-lease=<branch>:<last-pushed-sha>`; on the first push,
the aligned expected head from step 1), never merely to the newest
remote head observed: a contributor can push between rounds, and a
lease advanced to a SHA the local history does not contain would
bless force-pushing that commit away. A failing lease therefore means
someone else pushed; stop and re-anchor onto the observed remote
head, incorporating it into local history, before any further
rewrite, then advance the lease to that incorporated head for the
retry: the pin always names the newest remote head local history
contains.

Where delegation with write access is unavailable or not permitted, run the
rounds in the main agent as usual; for a long review loop from an
already-huge session, starting a fresh session for the loop is the manual
equivalent.

### 5. Converge on value, with a rising bar

A round ends one of two ways. **When you pushed a fix**, the commit
re-triggers a push-triggered reviewer on its own; a command-triggered one
still needs its command re-issued (step 2). **When the round produced no push
because every finding was declined**, the exchange is over: the declines are
already recorded inline, so hand off with the ledger below rather than paying
a round for the reviewer to re-confirm code that did not change. A pure
judgment-call round pauses for the user per step 4 either way; resume the
loop when their call lands, and if it changes code, the push re-triggers as
usual.

**Advance the baseline (step 1) before each post-fix wait**: to the review you
just handled, or to the push you just made. Otherwise the already-handled
review is still "after baseline," so the next wait returns instantly and
reprocesses old feedback; only the reviewer's _fresh_ pass should finish the
next round.

The stop signal is **value weighed against round cost, on a bar that rises
with the rounds.** A round is not free: it costs on the order of 1.5–3x the
main context in token-equivalents plus ~10 minutes of latency
(`references/cost-model.md`), and a reviewer whose findings stay individually
valid will sustain an unbounded exchange if any worthwhile finding is enough
to continue. So ratchet the bar. In the first two fix rounds, address
everything worthwhile: real correctness, clarity, or safety issues, including
the round your last fix triggered. From the third fix round on, only
**blocking** findings (correctness, security, data-loss, broken invariants,
red CI) justify another full round; a pass whose findings are all valid but
non-blocking is the taper signal, not fuel. When an exchange does run long on
blockers, keep the fixer alive across rounds rather than respawning it each
time; step 4 covers why a persistent fixer amortizes better over a
multi-round loop.

**The severity call is yours.** Judge each finding against those blocking
categories yourself; the reviewer's severity tag (a P1/P2 label) is input,
not verdict, in both directions. When unsure whether a finding blocks, treat
it as blocking: uncertainty buys a round, not an exit, so the exit never
rewards a convenient downgrade. And a round the exchange pays for anyway
dispositions every finding in the pass, not just the blockers that earned
it: fix the worthwhile ones, defer or decline the rest on the triage merits
below; never silently carry a finding to a later round, and never force-fix
one that rightly earns a decline.

A **fix round** is one that pushed fixes: a decline-only round advances
neither the ratchet count nor the checkpoint below, and the final triage
push below counts as the exchange's last fix round.

**From the third fix round on, when a pass raises no blockers on your own
severity read**, triage instead of looping. Fix in one final push the
findings you can verify locally before pushing: an edit inert to behavior (a
typo, or prose that nothing executes; wording in a prompt or instruction
file is behavior, not inert), or a change covered by a check you run first
(a rename only with its references swept and verified, by grep, build, or
the project's checks). Move a valid finding that needs real or
hard-to-verify work to the project's tracker as a follow-up issue linked
from the PR, quoting the finding with enough context to act on later:
deferral preserves the work, it is not a cheaper exit. Decline the marginal
rest (style, micro-wording, contrived edge-cases) with a one-line reason.

How that final push hands off depends on who owns the loop. In a
main-agent-owned loop, hand off without waiting for the pass the push
triggers, noting that a further review may still land so the human knows
to glance at merge: waiting there costs another full-context round. A
conductor's wait is a near-free foreground poll (step 3), so a
conductor instead waits out that re-review, dispositions anything it
raises on this same rising bar, and delivers the terminal ledger at
quiescence: a clean pass, a capped timeout with no review (recorded in
the ledger with its baseline), or every finding dispositioned with no
push pending.

The triage push is also what bounds that tail. Past it, a new blocker
reopens fix rounds as usual, but further non-blocking findings take
terminal dispositions only, deferred to the tracker or declined, never
another push: a reviewer yielding one fresh nit per push would
otherwise hold the conductor, and its checkout exclusivity, alive
indefinitely. A disposition-only round pushes nothing, triggers no new
pass, and so reaches quiescence; with the capped timeout above,
exclusivity never outlives a bounded wait.

The verifiability gate is what keeps the final push from
breeding fixes-of-fixes: a fix whose correctness would itself need a reviewer
pass to confirm (a logic edit, parsing or validation changes, anything on a
destructive, credential-leak, or trust-boundary path) never rides the final
push. When such a finding is blocking, it earns the verified round or stays
explicitly outstanding for the human at handoff, never a deferred issue;
only a non-blocking one may defer to the tracker instead.

**Hand off with a disposition ledger.** At the end of the exchange every
finding carries exactly one recorded disposition: fixed (the pushed SHA),
declined (the reasoned inline reply), deferred (the follow-up issue), or
outstanding for the human. When a no-blocker call ended the exchange, the
ledger states that call itself, so the human can audit in one glance the
judgment that stopped the loop. Nothing is silently dropped: deferral
preserves the finding without another round, and the human arbitrates
outstanding non-blockers at merge. "Stop" means stop _auto-addressing and
watching_, not "guaranteed converged."

**What stops a blocker-sustained exchange is thrash, not a round count**: the
same finding recurring _after a correct, complete fix_, or each fix spawning
new problems without net progress, means the change or the loop is broken,
so pause and bring in the human with what is stuck. Short of thrash,
blockers that keep landing and staying fixed keep earning rounds: a
premature handoff saves nothing, because the human restarts the exchange,
re-pays the remaining rounds, and pays their own attention on top.

At about five blocker-sustained fix rounds, break autopilot with a
**checkpoint**:
record a one-line go/no-go, continuing only with a stated reason the
exchange is converging (rounds shrinking, fixes holding), and otherwise
escalating to the human with the ledger instead of another patch round. A go
call buys the next few rounds, never the rest of the exchange: repeat the
checkpoint on that same cadence for as long as blockers sustain the loop,
since an exchange yielding one fresh blocker per round, every fix holding,
trips neither thrash nor a one-time check. The forced assessment is the
checkpoint's value; don't rubber-stamp it.

Distinguish thrash from **your own half-fix**: a class that recurs because
you patched the cited line and didn't sweep its siblings is your miss, so
sweep it properly (grep the file) and keep going, though the sweep round
still counts toward the checkpoint. Don't rationalize a stop from a
recurrence you caused; a healthy exchange ends on the taper well before the
checkpoint fires.

**Track findings by class across the whole exchange, and escalate on a
recurrence.** Classify every finding as it arrives, from any source (a serial
reviewer's rounds, an adversarial refute pass, your own self-review), and sweep
each one's class immediately per step 4: the _first_ finding already earns an
exhaustive same-push sweep, so never hold off waiting for a second. What the
finding history adds is an **escalation** signal, tracked finding-level, not
round-level (rounds are just the serial reviewer's batching). When a class gains
a **second member** anywhere (same review, adjacent rounds, wherever) despite
that sweep, you drew the boundary too narrow, so widen it one level up and
re-enumerate the larger class (for example "thread page", then "REST comment
page", then the real class "any single-page read of any connection") instead of
patching the new instance at the old width.

Track recurrence by **rule as well as class**: when successive rounds keep
landing on the same rule or prose surface, and the findings read as "the
instructions omit a clause" rather than "the program has a bug," no
enumeration converges, because the prose is re-deriving a program. Stop
clause-patching and surface a medium escalation to the owner: the evidence
(rounds, severities, what kept recurring) plus a recommendation, usually to
move the rule into a small tested script or check, so later findings become
ordinary program bugs a test can hold closed.

That second same-class finding is also when to spend one **adversarial refute
pass**, where the platform permits **read-only** fresh-context delegation: a
few fresh-context lenses, run in parallel, each tasked to _disprove_ the change,
to surface the rest of the class in one shot before the reviewer serializes it
over more rounds.

- **It is a lighter grant than step 4's write-capable fixer**: like the
  watcher, the lenses only disprove and report evidence, never edit, commit,
  or push, so gate them on read-only delegation (as step 4's fixer is gated
  on write access), not on the fixer's gate.
- **The economics**: a review round costs on the order of 1.5–3x the main
  context in token-equivalents plus ~10 min of latency, while a three-lens
  refute pass costs about one round's tokens and one round's wall clock, so
  it pays once the odds of two or more further preemptable rounds clear
  roughly 0.3–0.5, a bar a recurring class empirically meets.
- **Guardrails**: one such pass per PR, re-armed only if a class recurs
  after it; platform-gated on read-only delegation, with plain serial
  sweeping as the fallback where even that is unavailable; and
  evidence-or-drop on whatever it raises, no speculative findings.
- **Don't fire it** on mixed-class declining-severity nits, a small change,
  or a single-surface diff, where there is no class to preempt.

### 6. Report

Before any final report calls the PR ready for handoff, the main agent resolves
the PR's current base branch and tip from the host again and compares them with
the cycle's recorded base. If either changed, report that the automated-review
round is complete but the PR's integration evidence is stale, then return
control to the project's handoff/freshness convention instead of claiming
readiness. The watcher must not rebase, merge, push, or otherwise update the
branch. After the branch owner refreshes it and pushes, start the ordinary new
head review cycle again from step 1.

Where the project folds review fixes, the report has a second blocker:
confirm the pushed branch carries no leftover autosquash subjects
(`fixup!`, `squash!`, or the `amend!` form that `--fixup=amend:` and
`--fixup=reword:` create) and no standalone review-fix commits (an
"address review" commit that never got folded into its concern). Any
found means step 4's fold gate is unfinished; complete the fold and
re-push before declaring the round done.

Summarize as the exchange's disposition ledger: what the reviewer raised,
what was fixed (with SHAs), what was declined and why, what was deferred
(with its follow-up issue), what is outstanding or surfaced for the user, and
the PR's state (threads resolved, checks green). Leave the PR open for human
review and merge unless the project has opted into self-merge.

## Platform support and fallbacks

The non-blocking mechanisms above are **platform-specific**: subagents,
backgrounded re-invocation, and scheduled wake-ups are not universal. Gate on
what the running agent actually supports and what its session policy permits,
then pick the cheapest permitted mechanism per step 3's cost model; never emit
steps the agent cannot perform or is not allowed to start without permission.

- **The grants form a ladder.** The delegated watcher needs read-only
  delegation whose completion reliably notifies or re-enters the main agent
  (that gate, and the skip rule when it fails, live in step 3's
  delegated-watcher path); step 4's delegated fixer needs delegation
  _with write access_, a larger grant (its gate lives in step 4); and
  step 4's conductor needs that write grant plus resumability across the
  main agent's turns, completion re-entry, and checkout isolation or
  exclusivity (step 4), the largest. Where a grant is
  not both supported and permitted, take the next permitted path.
- **An agent with background re-invocation or scheduled wake-ups** (e.g.
  Claude Code) runs the **non-blocking** path for that environment.
- **An agent whose turn is synchronous** and that lacks a reliable
  subagent/background re-entry path (e.g. a plain Codex CLI session)
  degrades to the **bounded foreground poll** (still hands-off within the
  turn, just blocking) or hands back.

Everything else here (resolving the PR, detecting activity via `gh`,
addressing, converging) is platform-neutral and behaves the same across
agents.

This skill assumes a reviewer bot, a PR host CLI (such as `gh`), and a shell;
where any is missing, hand control back to the user rather than pretending to
wait.
