---
name: await-pr-review
description: >-
  Wait for an automated PR reviewer (such as Codex) to post its review, then
  handle the feedback — without you having to tell the agent to check or poll.
  Use this after you open or push to a pull request that has an automated
  reviewer — starting the watch is the default follow-on, not something to ask
  whether to do; it watches for the bot's review and addresses it. It waits
  non-blockingly where platform support and session policy permit it (a
  delegated watcher/subagent that can notify or re-enter the main agent,
  backgrounded poll, or scheduled wake-up that re-invokes the agent when
  feedback lands), and only falls back to a bounded foreground poll when it must.
  When feedback arrives it auto-addresses the clear-cut findings and surfaces
  judgment calls for you, converging across the re-reviews that its own fixes
  trigger but stopping once findings dwindle to marginal nits. It reuses the
  project's review-response conventions and does not replace human review. Not
  for when there is no automated reviewer, no open PR, or you only want a human
  to review.
---

# Await PR Review

Watch an open pull request for its automated reviewer (e.g. Codex), then handle
the feedback — the part you would otherwise do by repeatedly telling the agent
to "check the PR" or "poll for comments." This skill owns the **waiting and
orchestration**; the actual responses follow the project's existing review
conventions (it references them, it does not restate a weaker version).

The design goal is to **not block the main thread**: where the platform can
delegate a watcher that reliably notifies or re-enters the main agent, run a
backgrounded watcher, or re-enter the agent on a schedule — and policy permits
that mechanism — you keep working while it waits, and the agent comes back when
the review lands. Blocking is a last resort, used only where nothing else is
available.

Because the non-blocking watch does not occupy the main thread while it waits,
**starting it is the default after opening or pushing such a PR — don't stop to ask
whether to watch.** Asking "should I watch for the review?" is exactly the manual
polling this skill exists to remove; start the watch and keep working. Keep one
active watch per PR/reviewer; after a new push, advance or replace that watch's
baseline rather than leaving duplicate watchers running. (Where the platform or
session policy can't watch non-blockingly, fall back per the ladder in step 3 —
the gate is the available permitted mechanism, not whether to engage.)

## When to use it

- Right after opening a PR, or after pushing fixes to one, when an automated
  reviewer will post a review shortly — the default next step, handled without
  babysitting, not one to ask whether to do.
- Any time you would otherwise type "check the PR for comments" or "keep polling
  until the review shows up."

## When NOT to use it

- No automated reviewer is configured on the repo — there is nothing to wait for.
  Step 2 says how to tell: a recorded reviewer identity, a bot-authored review on
  recent PRs, or the user naming one.
- No open PR yet (open it first), or the change is on a branch with no PR.
- You only want a human review — this watches the bot pass, not a person.

## The loop

### 1. Resolve the PR and snapshot a baseline

Find the PR for the current branch (`gh pr view --json number,url`). Record a
**baseline** of what already exists so later you detect only _new_ activity.
**Anchor that baseline to the event that will produce the pass you're waiting
for, not the moment the watch starts.** For an open/push-triggered wait, capture
the PR open/ready or actual push event timestamp at the event boundary (or read
that event timestamp from the host). The reviewer often fires on PR open or push,
so a pass can land after that event but _before_ you start the watcher; anchoring
to watch-start would bank it as pre-existing and hand off unhandled. Do **not**
use the head commit's authored/committed time as a proxy for the push: a locally
created commit may predate already-handled reviews and only be pushed later.
Treat reviewer activity after the captured open/push timestamp as new, and start
the watch promptly — before waiting on anything else (e.g. CI) — so the window
where a review can slip in unbaselined stays small. **But when you _manually
re-trigger_ a recheck with no new push** (the request-it-once path in step 2),
the last push predates reviews you've already handled, so last-push anchoring
would replay them and exit the wait instantly. Anchor that case to the
**trigger/request time** instead: snapshot the reviews that exist _at the moment
you request_ as already-seen, and treat only the reviewer's pass dated after that
request as the awaited one.
Capture **two** things, because they are separate connections: top-level
**reviews** (a bot can complete a review with a summary/approval and _no_ inline
findings — that round shows up only here, not under threads) and the inline
**review threads**. Snapshot the latest reviewer review time and the current
thread IDs:

```sh
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  reviews(last:20){nodes{author{login} submittedAt state}}
  reviewThreads(first:50){nodes{id isResolved comments(last:1){nodes{author{login} createdAt}}}}}}}' \
  -F o=OWNER -F r=REPO -F n=PR
```

Note `comments(last:1)` — the **newest** comment per thread, not the first; a
reviewer reply on an _existing_ thread is the latest comment, and using the
oldest would miss it.

This enumerate-and-diff snippet is illustrative but edge-prone (paging,
first-vs-last comment, author filtering), so **prefer time, not enumeration**:
treat a round as arrived when the configured reviewer has a `submittedAt` (from
`reviews` above) or any review-comment `createdAt` _after_ the baseline. That
single timestamp comparison sidesteps every snippet edge. Reach for the full
thread set only when you actually need it (e.g. to resolve threads), and then
page with `pageInfo{hasNextPage endCursor}` / `after:` since `first:50` is one
page.

### 2. Identify the reviewer, then ensure it's requested

You need enough **identity to match the reviewer's future reviews** — its account
login (the `author.login` you filter on in step 3), not merely "some bot will
review." Establish it in this order; the **recorded identity is the primary
source, detection only a fallback**:

- **Recorded identity (primary).** If the project records its automated reviewer
  (per the "record a noticed reviewer" convention — typically an "Automated
  reviewer" line in AGENTS.md), use it: the reviewer's name, login (mind the
  API-form caveat in step 3), and trigger. Treat it as a strong hint, not gospel
  — if repeated waits turn up nothing the note may be stale (reviewer removed),
  so fall through to detection.
- **Detection (fallback).** Otherwise scan recent PRs for a bot-authored review
  (`gh pr list --state all --limit 20 --json number`, then each PR's reviews) — a
  `Bot`/`App` author that submitted a _review_ is the reviewer (CI bots post
  checks/statuses, not reviews). This yields both the gate (a reviewer exists)
  and the login to match. **If the scan finds more than one distinct bot
  reviewer** (e.g. Codex _and_ CodeRabbit), don't auto-pick — "is a bot" can't
  disambiguate them, and step 3's login filter would reject the others as a
  "different bot" and stall; ask the user which to wait on (or require a record).
  Detection reveals the **login but not necessarily the trigger** — past reviews
  show who reviewed, not what starts a fresh one. Before treating the reviewer as
  ready to wait on, derive the trigger from project notes, reviewer docs, prior PR
  command comments, or host configuration; if you cannot tell it runs
  automatically, ask for the trigger instead of burning the capped poll.
- **Human-asserted — only if it identifies.** The user telling you a reviewer
  exists counts **only when it names the reviewer enough to match its reviews** (a
  login, or a name you can resolve to one) — step 3 still filters by
  `author.login`, so a bare "there is a reviewer" can't be matched. If the
  assertion lacks identity, ask for the login (and trigger) before engaging.
- **None of these → don't engage.** No record, no bot review in history, and no
  identifying assertion means there is nothing to match on; hand back (see When
  NOT to use).

**When you confirm a reviewer the project hasn't recorded, write the record**
outside managed blocks in a project-specific AGENTS.md section (per the
convention) so later sessions needn't re-detect: the reviewer's name, its
login/account identity (including the API-specific form when it differs), and how
it's triggered. Record only a reviewer you observed, never its absence — a stale
record naming a removed reviewer costs at most a capped wait, while a recorded
"none" would silently skip a reviewer added later.

Any reviewer that posts through GitHub's review mechanism works here (Codex, a
Claude review action, CodeRabbit, and the like); only the bot login and the
trigger change. Reviewers differ on triggering: most run automatically on open
and on each push; some need a command comment (Codex uses `@codex review`; others
use their own); some run as a CI/Action job on PR events. If yours needs a
trigger and none is pending, request it once — don't re-trigger on every poll.

### 3. Wait for new review activity — non-blocking where supported

Use the strongest mechanism the platform offers, in this order:

- **Delegated watcher / subagent (preferred where available and permitted).** If
  the environment can spawn a subagent while the main thread continues, the
  session policy permits delegation without asking, and the platform will
  reliably notify or re-enter the main agent when the watcher finishes, delegate
  a watcher-only task. Give it the repo, PR number, configured reviewer login,
  expected head SHA, and baseline event time. It should poll until reviewer
  activity appears on that head or the bounded wait expires, then report the
  matching review's ID, state, `submittedAt`, and body; unresolved actionable
  threads with thread/comment IDs and path/line; and checks status. If the
  watcher cannot fetch the top-level review body, it must say so explicitly and
  tell the main agent to refetch it before declaring the round clean. The watcher
  must not edit files, commit, push, post trigger comments, reply to review
  threads, or resolve threads. If delegation would require explicit permission
  that is not already granted, or completion would require the main agent/user to
  poll the subagent manually, skip this mechanism and fall through to the next
  available watch path.
- **Backgrounded poll (preferred, non-blocking).** Launch a background watcher
  that re-checks the PR on an interval and exits when new reviewer activity
  appears past the baseline; the harness then re-invokes the agent to handle it.
  In Claude Code this is a `run_in_background` shell loop. The main thread stays
  free while it waits.
- **Scheduled wake-up (non-blocking).** Where the platform can re-enter the
  agent on a timer instead of holding a process (e.g. a self-paced loop /
  scheduled wake-up), schedule the next re-check rather than running a watcher.
- **Bounded foreground poll (blocking fallback).** Only where neither of the
  above exists: poll in the foreground with a hard cap, accepting that it blocks.
- **Hand back (last resort).** Where the agent can do none of these, report the
  baseline and ask the user to re-invoke once the bot has commented.

Cadence: automated reviews usually land a few minutes after a push, so re-check
about every **4–5 minutes** (~270s also keeps the prompt cache warm) and cap the
total wait (e.g. **20–30 minutes**) before reporting that no review arrived.

Finish a round on any of three signals from the configured reviewer, dated after
the baseline: a **submitted review**, a **new review thread**, or a **new
review-comment on an existing thread** (a reply leaves no new thread and no new
submitted review, so this third case is easy to miss — it is why step 1 reads
`comments(last:1)`). All three must be **authored by the configured reviewer** —
match `author.login` against the target bot. **Mind the login form: GitHub
returns a bot as `name` in GraphQL but `name[bot]` in REST** (e.g.
`chatgpt-codex-connector` via the GraphQL `reviewThreads` vs
`chatgpt-codex-connector[bot]` via `gh api repos/.../pulls/N/reviews`) — match
the right form per API, or the filter silently matches nothing and a real review
looks like "no activity." A human review, or a _different_ bot, posting after
the baseline is **not** the awaited pass: this skill is scoped to the automated
reviewer, so unrelated activity must not finish the round (else you stop early
or auto-address the wrong feedback while the target reviewer is still pending).
Do **not** treat an **acknowledgement** as completion either — some reviewers
post a placeholder or react before the real review (Codex, for one, acknowledges
an `@codex review` request and posts the actual review, with any inline
findings, _afterward_); a thumbs-up or placeholder is still _pending_, so keep
waiting. But don't depend on an ack either — not every reviewer posts one, so
key off the reviewer's actual response (any of the three signals above — a
submitted review, a new thread, or a reply on an existing thread), never an
acknowledgement that may never come. Treat it as "reviewed, nothing to address"
only when the latest review adds no new unresolved threads **and** its `state` /
`body` carry no actionable feedback — a `CHANGES_REQUESTED`, or a `COMMENTED`
review with a substantive summary body, can hold findings with no inline thread
at all, so read the review's state and body before declaring clean.

### 4. Address the feedback — auto clear-cut, surface judgment calls

For each new finding, follow the project's review-response conventions where it
has them (e.g. an AGENTS.md "Responding to automated review" section); the
essentials, project-agnostic:

- **Evaluate on merits.** Fix real findings; decline contrived, speculative, or
  already-fixed ones with a one-line reason. Do not reflexively comply.
- **Fix the class, not just the cited line.** Sweep the file/repo for the same
  class and fix every instance in the same push, so the next re-review doesn't
  flag the siblings one at a time.
- **Reply and resolve.** Reply inline with the disposition and the fixing commit
  SHA (or the reasoned decline), then resolve the thread.
- **Auto-address the clear-cut; surface the judgment calls.** Apply the
  obviously-correct fixes yourself. **Pause and surface** anything ambiguous,
  contentious, or design-altering for the user to decide — do not silently make
  a debatable change.

### 5. Converge on value, don't cap a productive exchange

Addressing pushes commits, which re-triggers the reviewer. **Advance the
baseline (step 1) before each post-fix wait** — to the review you just handled,
or to the push you just made. Otherwise the already-handled review is still
"after baseline," so the next wait returns instantly and reprocesses old
feedback; only the reviewer's _fresh_ pass should finish the next round.

The stop signal is **value tapering, not round count.** Keep going for as long
as rounds keep
surfacing **worthwhile** findings — real correctness, clarity, or safety issues,
including the round your last fix triggered. **Never stop on a worthwhile
round**, and **don't cap a still-valuable back-and-forth**: if each round is
still delivering, ten useful rounds beat stopping at three. A good finding is
the signal to continue — after each fix, wait for the next review and only then
judge it.

**Stop when the value actually tapers** — a round comes back clean, or only
marginal nits (style, micro-wording, contrived edge-cases). Decline any
remaining nits with a one-line reason and hand off. Value captured is the bar,
not threads-at-zero. "Stop" means stop _auto-addressing and watching_, not
"guaranteed converged" — note that a further review may still land so the human
knows to glance.

The only reason to interrupt a loop that is **still finding real issues** is
**non-convergence, not a quota**: if you are thrashing — the same finding
recurring _after a correct, complete fix_, or each fix spawning new problems
without net progress — the change or the loop is broken, so pause and bring in
the human with what is stuck. But distinguish true thrash from **your own
half-fix**: a class that recurs because you patched the cited line and didn't
sweep its siblings is not non-convergence — that is your miss, so sweep it
properly (grep the file) and keep going. Don't rationalize a stop from a recurrence
you caused. Any round-count ceiling is purely a guard against a pathological
infinite loop, set far above any healthy exchange — never a target to stop at.

### 6. Report

Summarize: what the reviewer raised, what was fixed (with SHAs), what was
declined and why, what was surfaced for the user, and the PR's state (threads
resolved, checks green). Leave the PR open for human review and merge unless the
project has opted into self-merge.

## Platform support and fallbacks

The non-blocking mechanisms above are **platform-specific** — subagents,
backgrounded re-invocation, and scheduled wake-ups are not universal. Gate on
what the running agent actually supports and what its session policy permits,
then degrade in the order given; never emit steps the agent cannot perform or is
not allowed to start without permission. A delegated watcher counts as
non-blocking only when its completion reliably notifies or re-enters the main
agent; merely spawning a subagent is not enough if the main agent or user must
poll that subagent to learn it finished. If subagents exist but delegation
requires explicit permission, or completion does not wake the main agent, skip
that path and use backgrounded polling, scheduled wake-up, bounded foreground
polling, or hand-back instead. An agent with background re-invocation or
scheduled wake-ups (e.g. Claude Code) runs the **non-blocking** path for that
environment; an agent whose turn is synchronous and lacks a reliable
subagent/background re-entry path (e.g. a plain Codex CLI session) degrades to
the **bounded foreground poll** — still hands-off within the turn, just blocking
— or hands back. Everything else here (resolving the PR, detecting activity via
`gh`, addressing, converging) is platform-neutral and behaves the same across
agents.

This skill assumes a reviewer bot, a PR host CLI (such as `gh`), and a shell;
where any is missing, hand control back to the user rather than pretending to
wait.
