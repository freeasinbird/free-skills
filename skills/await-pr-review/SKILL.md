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
  trigger but stopping once findings dwindle to marginal nits. It reuses the
  project's review-response conventions and does not replace human review. Not
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
for, not the moment the watch starts.** For an open/push-triggered wait, capture
the PR open/ready or actual push event timestamp at the event boundary (or read
that event timestamp from the host). The reviewer often fires on PR open or push,
so a pass can land after that event but _before_ you start the watcher; anchoring
to watch-start would bank it as pre-existing and hand off unhandled. Do **not**
use the head commit's authored/committed time as a proxy for the push: a locally
created commit may predate already-handled reviews and only be pushed later.
Treat reviewer activity after the captured open/push timestamp as new, and start
the watch promptly, before waiting on anything else (such as CI), so the window
where a review can slip in unbaselined stays small. **But when you _manually
re-trigger_ a recheck with no new push** (the request-it-once path in step 2),
the last push predates reviews you've already handled, so last-push anchoring
would replay them and exit the wait instantly. Anchor that case to the
**trigger/request time** instead: snapshot the reviews that exist _at the moment
you request_ as already-seen, and treat only the reviewer's pass dated after that
request as the awaited one.
Capture **three** things, because they are separate connections: top-level
**reviews** (a bot can complete a review with a summary/approval and _no_ inline
findings: that round shows up only here, not under threads), the inline
**review threads**, and the PR-description **reactions**, where some reviewers
signal review status out of band (see the status signals in step 3). Snapshot
the latest reviewer review time, the current thread IDs, and the reviewer's
reactions. The exact snapshot query and its field caveats (such as reading each
thread's **newest** comment, not its first: a reviewer reply on an _existing_
thread lands as the latest comment, and reading the oldest would miss it) are
specified in `references/detection.md`; `watch-review.sh` (step 3) implements
the same detection.

Two rules govern the detection. **Prefer time, not enumeration**: treat a
round as arrived when the configured reviewer has a review `submittedAt`, a
review-comment `createdAt`, or a status-signal reaction `createdAt` (step 3)
_after_ the baseline; enumerate-and-diff of threads is edge-prone (paging,
first-vs-last comment, author filtering). And **page every source past the
baseline**: a single page is a window, not the collection, so enough newer
activity by other authors can push the item you are looking for out of it.
Reach for the full thread set only when you actually need it (e.g. to resolve
threads). The bundled `watch-review.sh` (step 3) is the executable form of
this detection, with every source paged; prefer it over re-deriving it. The
full prose specification (the snapshot query, the windowed-connection
derivation, and the REST/GraphQL paging mechanics) is in
`references/detection.md`.

### 2. Identify the reviewer, then ensure it's requested

You need enough **identity to match the reviewer's future reviews**: its account
login (the login you filter on in step 3, via `author.login` for reviews and
`user.login` for reactions), not merely "some bot will
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
  the identity; record both login forms (login-form rule in step 3). Either
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
  `watch-review.sh` alongside this file, parameterized on the PR, baseline,
  reviewer login (both API forms), expected head SHA (so a stale pass
  against a superseded head does not end the wait), signal contents,
  cadence, and cap. It
  implements the step-1 detection and the matching rules below, and exits with a
  distinct code plus a compact one-line report for review activity (0),
  clean pass (3), or cap expiry (2), so the caller branches on the exit code
  without parsing prose. Where `gh` or a shell is missing, hand-roll the
  watch from the specification in `references/detection.md`; it is the same
  detection the script implements.
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
paragraph). All four must be **authored by the configured reviewer**: match
the target bot against `author.login` for reviews and thread comments, but
against `user.login` for reactions (the field GraphQL exposes a reaction's
author under). **Mind the login form** (the canonical login-form rule the
rest of this skill points at): GitHub returns a bot as `name` in GraphQL but
`name[bot]` in REST (e.g. `chatgpt-codex-connector` via the GraphQL
`reviewThreads` vs `chatgpt-codex-connector[bot]` via
`gh api repos/.../pulls/N/reviews`); a _reaction_ author carries the
REST-style `name[bot]` form for an App-based bot even in GraphQL; and a
reviewer running as a regular machine-user account carries its plain login
everywhere. Match the right form per API and per field, or the filter
silently matches nothing and a real review
looks like "no activity." A human review, or a _different_ bot, posting after
the baseline is **not** the awaited pass: this skill is scoped to the automated
reviewer, so unrelated activity must not finish the round (else you stop early
or auto-address the wrong feedback while the target reviewer is still pending).
Do **not** treat an **acknowledgement** as completion either: some reviewers
post a placeholder or react before the real review (Codex, for one, acknowledges
an `@codex review` request and posts the actual review, with any inline
findings, _afterward_); a reaction on your trigger comment or a placeholder is
still _pending_, so keep waiting. But don't depend on an ack either: not
every reviewer posts one, so key off the reviewer's actual response (any of
the four signals above), never an acknowledgement that may never come. Treat
it as "reviewed, nothing to address" only when the latest review adds no new
unresolved threads **and** its `state` / `body` carry no actionable feedback:
a `CHANGES_REQUESTED`, or a `COMMENTED` review with a substantive summary
body, can hold findings with no inline thread at all, so read the review's
state and body before declaring clean.

Some reviewers also signal status **out of band**, on the PR itself rather
than through a review, and some post no review at all when a pass finds
nothing to raise. A watch that reads only reviews and threads therefore waits
out its full cap on a clean PR, then wrongly reports "no review arrived."
Codex, for one, reacts on the PR description: eyes (👀) while a review is in
progress, thumbs-up (👍) when a pass found nothing; on a clean first pass
that thumbs-up, minutes after open, is the only artifact the reviewer leaves.
Learn your reviewer's signals, record them with its identity (step 2), and
include the PR-description reactions in the step-1 snapshot. A **clean-pass
signal dated after the baseline** is the fourth completion signal: the round
finished as "reviewed, nothing to address." An **in-progress signal** works
like the acknowledgement rule above: its presence means keep waiting; its
absence proves nothing (the reviewer may remove it when the review
completes). Two caveats. Reactions are one-per-user-per-emoji and mutable, so
match on the signal's `createdAt` being after the baseline, never on bare
presence: a leftover clean-pass reaction from an earlier round predates the
baseline and does not count, and the wait cap stays as the backstop when the
signals are ambiguous. And reaction authors carry the reaction form of the
canonical login-form rule above, not the review-author form.

### 4. Address the feedback: auto clear-cut, surface judgment calls

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
  contentious, or design-altering for the user to decide; do not silently make
  a debatable change.

**Where to run the rounds.** By default the main agent addresses the feedback
itself: the watcher has already woken it, its context is warm, and it holds
the diff and the session's understanding of the change. Delegation adds
main-agent wakes and a context rebuild before it saves anything
(`references/cost-model.md` derives this break-even and the persistent-fixer
amortization below), so the trade pays off only when both hold: the round is
long (many findings, a wide class sweep, dozens of tool calls) **and** the
main context dwarfs the fixer's brief. A short round (a few edits) is cheaper
in the already-awake main agent, overhead included. When both do hold, and the platform supports
delegation with write access (and session policy permits it without asking),
run the fix round in a fresh, compact fixer context: brief it with the repo,
the PR, the reviewer's identity and status signals, the current baseline, and
a pointer to the project's review-response conventions. The fixer
auto-addresses the clear-cut findings, runs the project's verification checks
itself and reports facts, and **reports judgment calls back rather than
deciding them**: the same auto/surface split as above, relocated. Only the
fixer's final report crosses back into the main context, so hold it to the
watcher's compactness contract (fixing commit SHAs, a one-line disposition
per finding, judgment calls with just enough quoted context to decide, never
full diffs); the main agent acts on that report and spot-checks only the
judgment calls, since re-verifying clear-cut fixes from the main context pays
for the round twice. Skip delegation when the round is short, the main
context is small, or the round is mostly judgment calls (each escalation
wakes the main agent anyway, so the savings evaporate), and note that unlike
the watcher, the fixer needs a capable model class: the savings come from
context size, not model tier.

That break-even is stated **per round**, which makes short rounds look like
they never justify delegation. But a convergence loop is many rounds, and a
**fixer kept alive across the loop** amortizes the context rebuild a fresh
fixer would re-pay every round, while keeping each round's debris (its
findings and fixes) out of the main context, since only the compact reports
cross back (the amortization arithmetic is in `references/cost-model.md`).
So a persistent fixer likely wins on any longer exchange (roughly 4+ rounds)
even when each round on its own falls below the per-round break-even above;
the per-round rule still governs a one-shot round. Two honest caveats. It needs a platform that
can keep a subagent **resumable across the main agent's turns** (in Claude
Code, re-messaging the same agent instead of spawning a new one), so gate it
like the delegated-fixer path above and fall back to in-main rounds where that
is unavailable. And the judgment calls still wake the main agent every round
regardless. The fixer's own context grows across the loop, which is the point,
not a cost: that growth lands in the small, cheap context instead of the fat
main one.

Where delegation with write access is unavailable or not permitted, run the
rounds in the main agent as usual; for a long review loop from an
already-huge session, starting a fresh session for the loop is the manual
equivalent.

### 5. Converge on value, don't cap a productive exchange

Addressing pushes commits, which re-triggers a push-triggered reviewer; for a
command-triggered one, re-issue its trigger (step 2) after the fix push or the
wait has nothing coming. **Advance the
baseline (step 1) before each post-fix wait**: to the review you just handled,
or to the push you just made. Otherwise the already-handled review is still
"after baseline," so the next wait returns instantly and reprocesses old
feedback; only the reviewer's _fresh_ pass should finish the next round.

The stop signal is **value tapering, not round count.** Keep going for as long
as rounds keep
surfacing **worthwhile** findings: real correctness, clarity, or safety issues,
including the round your last fix triggered. **Never stop on a worthwhile
round**, and **don't cap a still-valuable back-and-forth**: if each round is
still delivering, ten useful rounds beat stopping at three. A good finding is
the signal to continue: after each fix, wait for the next review and only then
judge it. When the exchange runs long, keep the fixer alive across rounds
rather than respawning it each time; step 4 covers why a persistent fixer
amortizes its context rebuild better over a multi-round loop.

**Stop when the value actually tapers**: a round comes back clean, or only
marginal nits (style, micro-wording, contrived edge-cases). Decline any
remaining nits with a one-line reason and hand off. Value captured is the bar,
not threads-at-zero. "Stop" means stop _auto-addressing and watching_, not
"guaranteed converged"; note that a further review may still land so the human
knows to glance.

The only reason to interrupt a loop that is **still finding real issues** is
**non-convergence, not a quota**: if you are thrashing (the same finding
recurring _after a correct, complete fix_, or each fix spawning new problems
without net progress), the change or the loop is broken, so pause and bring in
the human with what is stuck. But distinguish true thrash from **your own
half-fix**: a class that recurs because you patched the cited line and didn't
sweep its siblings is not non-convergence; that is your miss, so sweep it
properly (grep the file) and keep going. Don't rationalize a stop from a recurrence
you caused. Any round-count ceiling is purely a guard against a pathological
infinite loop, set far above any healthy exchange, never a target to stop at.

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

That second same-class finding is also when to spend one **adversarial refute
pass**, where the platform permits **read-only** fresh-context delegation: a
few fresh-context lenses, run in parallel, each tasked to _disprove_ the change,
to surface the rest of the class in one shot before the reviewer serializes it
over more rounds. This is a lighter grant than step 4's write-capable fixer:
like the watcher, the lenses only disprove and report evidence, never edit,
commit, or push, so gate them on read-only delegation (as step 4's fixer is
gated on write access), not on the fixer's gate. The economics: a review round
costs on the order of 1.5–3x the main context in token-equivalents plus ~10 min
of latency, while a three-lens refute pass costs about one round's tokens and one
round's wall clock, so it pays once the odds of two or more further preemptable
rounds clear roughly 0.3–0.5, a bar a recurring class empirically meets.
Guardrails: one such pass per PR, re-armed only if a class recurs after it;
platform-gated on read-only delegation, with plain serial sweeping as the
fallback where even that is unavailable; and evidence-or-drop on whatever it
raises, no speculative findings. Don't fire it on
mixed-class declining-severity nits, a small change, or a single-surface diff,
where there is no class to preempt.

### 6. Report

Summarize: what the reviewer raised, what was fixed (with SHAs), what was
declined and why, what was surfaced for the user, and the PR's state (threads
resolved, checks green). Leave the PR open for human review and merge unless the
project has opted into self-merge.

## Platform support and fallbacks

The non-blocking mechanisms above are **platform-specific**: subagents,
backgrounded re-invocation, and scheduled wake-ups are not universal. Gate on
what the running agent actually supports and what its session policy permits,
then pick the cheapest permitted mechanism per step 3's cost model; never emit
steps the agent cannot perform or is
not allowed to start without permission. The grants form a ladder: the
delegated watcher needs read-only delegation whose completion reliably
notifies or re-enters the main agent (that gate, and the skip rule when it
fails, live in step 3's delegated-watcher path), while step 4's delegated
fixer needs delegation _with write access_, a larger grant (its gate lives
in step 4); where a grant is not both supported and permitted, take the next
permitted path. An agent with background re-invocation or
scheduled wake-ups (e.g. Claude Code) runs the **non-blocking** path for that
environment; an agent whose turn is synchronous and lacks a reliable
subagent/background re-entry path (e.g. a plain Codex CLI session) degrades to
the **bounded foreground poll** (still hands-off within the turn, just
blocking) or hands back. Everything else here (resolving the PR, detecting activity via
`gh`, addressing, converging) is platform-neutral and behaves the same across
agents.

This skill assumes a reviewer bot, a PR host CLI (such as `gh`), and a shell;
where any is missing, hand control back to the user rather than pretending to
wait.
