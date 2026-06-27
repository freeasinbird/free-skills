---
name: await-pr-review
description: >-
  Wait for an automated PR reviewer (such as Codex) to post its review, then
  handle the feedback — without you having to tell the agent to check or poll.
  Use this after you open or push to a pull request and want the agent to watch
  for the bot's review and address it. It waits non-blockingly where the
  platform supports it (a backgrounded poll or a scheduled wake-up that
  re-invokes the agent when feedback lands), and only falls back to a bounded
  foreground poll when it must. When feedback arrives it auto-addresses the
  clear-cut findings and surfaces judgment calls for you, converging across the
  re-reviews that its own fixes trigger but stopping once findings dwindle to
  marginal nits. It reuses the project's review-response conventions and does
  not replace human review. Not for when there is no automated reviewer, no open
  PR, or you only want a human to review.
---

# Await PR Review

Watch an open pull request for its automated reviewer (e.g. Codex), then handle
the feedback — the part you would otherwise do by repeatedly telling the agent
to "check the PR" or "poll for comments." This skill owns the **waiting and
orchestration**; the actual responses follow the project's existing review
conventions (it references them, it does not restate a weaker version).

The design goal is to **not block the main thread**: where the platform can
re-enter the agent on its own (a backgrounded watcher or a scheduled wake-up),
you keep working while it waits, and the agent comes back when the review lands.
Blocking is a last resort, used only where nothing else is available.

## When to use it

- Right after opening a PR, or after pushing fixes to one, when an automated
  reviewer will post a review shortly and you want it handled without babysitting.
- Any time you would otherwise type "check the PR for comments" or "keep polling
  until the review shows up."

## When NOT to use it

- No automated reviewer is configured on the repo — there is nothing to wait for.
- No open PR yet (open it first), or the change is on a branch with no PR.
- You only want a human review — this watches the bot pass, not a person.

## The loop

### 1. Resolve the PR and snapshot a baseline

Find the PR for the current branch (`gh pr view --json number,url`). Record a
**baseline** of what already exists so later you detect only _new_ activity.
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

### 2. Ensure the review is requested

First know **which reviewer** you are waiting on — its bot account (the
`author.login` you match in step 3) and how it is invoked. Any reviewer that
posts through GitHub's review mechanism works here (Codex, a Claude review
action, CodeRabbit, and the like); only the bot login and the trigger change.
Reviewers differ on triggering: most run automatically on open and on each push;
some need a command comment (Codex uses `@codex review`; others use their own);
some run as a CI/Action job on PR events. If yours needs a trigger and none is
pending, request it once — don't re-trigger on every poll.

### 3. Wait for new review activity — non-blocking where supported

Use the strongest mechanism the platform offers, in this order:

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
match `author.login`
against the target bot. A human review, or a _different_ bot, posting after the
baseline is **not** the awaited pass: this skill is scoped to the automated
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

The non-blocking mechanisms above are **platform-specific** — backgrounded
re-invocation and scheduled wake-ups are not universal. Gate on what the running
agent actually supports and degrade in the order given; never emit steps the
agent cannot perform. Concretely: an agent with background re-invocation or
scheduled wake-ups (e.g. Claude Code) runs the **non-blocking** path; an agent
whose turn is synchronous (e.g. a Codex CLI session) degrades to the **bounded
foreground poll** — still hands-off within the turn, just blocking — or hands
back. Everything else here (resolving the PR, detecting activity via `gh`,
addressing, converging) is platform-neutral and behaves the same across agents.

This skill assumes a reviewer bot, a PR host CLI (such as `gh`), and a shell;
where any is missing, hand control back to the user rather than pretending to
wait.
