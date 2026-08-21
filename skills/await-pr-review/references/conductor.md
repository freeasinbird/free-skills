# Conductor contract

Read this reference before spawning or resuming a conductor. It owns the
whole-exchange mechanics that do not belong in the routing-focused entry
point.

## Contents

- [Spawn brief](#spawn-brief)
- [Turn discipline](#turn-discipline)
- [Checkout gate](#checkout-gate)
- [Pinned force-with-lease](#pinned-force-with-lease)
- [Quiescence and reporting](#quiescence-and-reporting)
- [Context rotation](#context-rotation)
- [Stranded-conductor recovery](#stranded-conductor-recovery)

## Spawn brief

Start the conductor with the least inherited parent context the host exposes.
For Codex collaboration use `fork_turns: "none"`; for Claude Code use an
ordinary named background subagent, not a context-inheriting fork. On another
host, request fresh or empty context when supported. If the
host cannot control inheritance, state that limitation in the brief and
continue when the four conductor grants still hold; context control is an
optimization, not a fifth grant.

Give the conductor one compact, self-contained task with these facts:

- current task contract at spawn: objective, acceptance criteria, scope,
  dependencies and blockers, explicit non-goals, and task-specific user
  constraints
- repository and PR number
- automated reviewer login in each required API form, when already recorded
- trigger and progress/clean status signals, when already recorded
- baseline source and exact timestamp (plus the post-push disambiguation
  reading when the baseline used the pre-push fallback)
- expected PR head SHA
- base branch and base-tip SHA
- initial-context mode, or the unsupported-control notice
- available host-observation surface (script, API, or connector)
- conductor-local wait or scheduled same-conductor wake mechanism
- checkout path and whether it is isolated or exclusively assigned
- project review-response, commit, verification, and handoff conventions
- paths to `SKILL.md`, this reference, `detection.md`, and
  `review-response.md`
- the operating contract below

When reviewer identity or trigger facts are not already recorded, say so in
the brief and assign the conductor the step-2 discovery before it waits. Do
not make the main agent scan history merely to complete the brief.
In this reference, `current task contract` means that initial contract plus
every later decision and constraint amendment the user makes through a
surfaced judgment call.

Use this operating contract in the brief:

```text
Own steps 1 through 5 of the review exchange until a terminal disposition
ledger. Stay awake for the whole exchange. Run watch-review.sh as a bounded
foreground command when a shell and host CLI are available; otherwise use an
equivalent bounded API or connector polling loop, with scheduled wakes that
resume this same conductor when it cannot delay in-turn. Never release
exchange ownership or emit terminal completion merely to wait. Fix, fold,
push, verify, reply, resolve, advance the baseline, and re-watch under the
skill's rising bar. Surface only judgment calls, no-go or materially uncertain
convergence escalations, a checkpoint-approved context-rotation handoff or
read-only reconciliation result for the main agent to coordinate, or the
terminal ledger. Before any write, verify a clean checkout at the expected PR
head. Keep the force-with-lease pinned to the newest remote head already
contained in local history.
```

The conductor must be able to act from the brief plus those referenced files
without parent conversation history. It reads the referenced project
conventions itself. Its reports stay compact: finding ID, one-line
disposition, final pushed SHA or issue, checks status, and only enough context
to decide a surfaced call.

## Turn discipline

The conductor retains ownership for the exchange. It pauses or ends a turn
only for:

- a scheduled wake that targets this same conductor and preserves its exchange
  state without reporting terminal completion
- a judgment call that the main agent or user must decide
- a no-go or materially uncertain convergence escalation
- a checkpoint-approved context-rotation handoff or read-only reconciliation
  result that the main agent must coordinate
- the terminal disposition ledger

The scheduled wake resumes the conductor automatically. Resume the same
conductor after any ordinary surfaced call. Do not spawn a replacement or
release checkout exclusivity during any ordinary pause. The context-rotation
protocol is the only replacement path, and it assigns the main agent the
handoff between its quiescent checkpoint pauses.

Inside a conductor, a blocking foreground poll is the cheapest
ownership-preserving path. Use the script where it can run. An API or
connector loop that cannot delay in-turn schedules a wake of this same
conductor and preserves its exchange state across that pause. If neither a
blocking wait nor a scheduled same-conductor wake exists, the ownership gate
failed and the exchange belongs in the main agent. A background process
completion that re-enters only the main-agent layer does not satisfy this
contract; it can strand the exchange and send a misleading completion notice.

## Checkout gate

The conductor rewrites and force-pushes the PR branch, so it needs either:

- an isolated worktree, checkout, or clone, or
- exclusive ownership of a shared checkout while the main agent performs no
  edit, commit, fetch of the PR branch, rebase, or push.

Isolation and exclusivity are equal ways to satisfy the fourth routing gate.
Do not silently reinterpret isolation as mandatory on a platform whose
subagents share the filesystem.

Before the first write, and before any later write after a wait or resume, the
conductor verifies:

1. The host-reported PR head equals its checkout HEAD.
2. The worktree and index are clean, including untracked files.
3. The checked-out branch is the PR branch it is expected to push.
4. The host PR object exists and its lifecycle state is open.

Handle the checks separately:

- A dirty worktree or index is unrelated user state. Stop without modifying,
  moving, stashing, or cleaning it, and surface the exact paths.
- A clean checkout on the wrong branch or head may be re-anchored to the
  fetched PR head before editing.
- A failed lifecycle query or a missing, null, malformed, closed, or merged PR
  stops the response round as incomplete evidence.

A pinned lease protects the remote's old value; it does not prove the local
history being installed is the intended PR history.

Exclusivity lasts through surfaced pauses until the terminal ledger. A human
change requested mid-exchange goes through the conductor or ends the exchange
first.

## Pinned force-with-lease

Every rewritten push pins the lease explicitly:

```text
--force-with-lease=<branch>:<last-pushed-sha>
```

On the first push, use the expected head captured at the event boundary. On
later pushes, use the conductor's own last pushed head.

Do not use a bare lease. A fetch can advance the remote-tracking ref and cause
a bare lease to bless overwriting a contributor's push. Do not advance the
pin to a newly observed remote SHA that local history does not contain either.

A failed pinned lease means someone else pushed. Stop, fetch, incorporate the
observed remote head into local history, re-run the relevant verification,
then advance the lease to that incorporated head for the retry.

## Quiescence and reporting

The conductor waits out every review its own push triggers, including a final
locally verifiable triage push. It emits the terminal ledger only at
quiescence:

- a clean pass tied to the current round
- a bounded timeout whose coverage and baseline are recorded
- every finding dispositioned with no push pending

Past the final triage push, a new blocker reopens fix rounds. New non-blockers
take terminal dispositions only (defer or decline), so a reviewer producing
one new nit per push cannot hold checkout exclusivity indefinitely.

Immediately before a terminal ledger declares the PR ready, take a fresh
live-state snapshot, including after any resume or interruption. Require the
PR object to exist, its lifecycle state to be open, and the PR to be
review-ready rather than draft. Refresh the host-reported PR head and require
it to equal the last handled and verified head; confirm required checks cover
that exact head. Automated-review evidence must be either a completed pass tied
to that head with every activity dispositioned, or a fully covered bounded
timeout whose final observation found no in-progress signal. Also refresh the
current base tip and freshness, every review thread and blocker, pending push
state, and any automated-review activity after the last handled boundary. Page
every collection needed to prove those facts to exhaustion.

The terminal snapshot is valid only when every required query succeeds and
every required scalar and collection is present with the expected shape.
Treat a failed or partial query, missing PR, absent required field, null where
the field contract requires a value, malformed value, or unexhausted page as
incomplete evidence, never as an empty or clean state. Preserve documented
nullability: for an open PR, `closedAt` and `mergedAt` are expected to be null.

Require two consecutive complete composite scans with identical canonical
results. Compare PR lifecycle, head, base, checks, pending push, every review,
comment, and reply identity and timestamp, and the complete thread map,
including each thread's `isResolved` state and latest comment identity. If any
value or page metadata differs, discard both mixed-time scans and restart until
two complete scans match. Cached, single-scan, or partially compared state
never proves readiness. A changed PR head makes the previous evidence stale:
capture the new event boundary and reopen the exchange. Reopen on new same-head
reviewer activity too; head equality does not disposition a late review,
comment, or reply.

Do not declare the PR ready while its lifecycle is not open or it remains
draft; any blocker or thread is unresolved; a push is pending; reviewer
activity after the handled boundary remains undispositioned; the reviewer is
known to be in progress; review or snapshot coverage is incomplete or broken;
a required check is failed or incomplete; or the base is stale.

The terminal ledger includes every finding disposition, the fresh checks and
thread states, current PR head, current base and its freshness result, pending
push or review state, and any watch coverage gap. It is the conductor's
completion, not a question to answer.

## Context rotation

Preserve the same conductor through ordinary waits and review rounds. A long
idle period, elapsed time, context size, or fixed round count is not a reason
to replace it. Rotation is optional only after an existing blocker-sustained
convergence checkpoint has recorded a justified go and the cost-model
comparison says the expected remaining work is likely to repay the full
handoff and reconstruction cost. If fresh or empty replacement context is not
available, or the host cannot transfer the existing checkout path to the
replacement without creating a second checkout of the PR branch, keep the
current conductor.

Rotate only at a quiescent boundary between rounds. The current round must be
fully dispositioned and verified, its push complete, its baseline advanced,
and its watcher consumed or stopped. Require no pending push, active watcher,
undispositioned finding, or unresolved decision. A failed gate aborts rotation
without changing exchange or checkout ownership.

Prepare two deliberately separate rotation artifacts. The live main agent
keeps a private replacement brief containing the current task contract: the
initial brief's contract plus every post-spawn decision and constraint
amendment the user made through surfaced judgment calls. It also contains:

- available host-observation surface and conductor-local wait or scheduled-wake
  mechanism
- automated reviewer login in every required API form, trigger, and progress
  and clean-pass signals
- pinned lease SHA
- fix-round and convergence-checkpoint counts, prior checkpoint calls and
  evidence, and the next checkpoint cadence
- current taper or rising-bar phase and whether the one permitted final-triage
  push has already been used
- pending-push and active-watcher state
- checkout path, its isolation or exclusivity grant, and the host mechanism
  that will transfer that exact path to the replacement
- ownership state before rotation and the exact old-to-new transfer point
- project review-response, commit, verification, and handoff conventions
- paths to `SKILL.md`, this reference, `detection.md`, and
  `review-response.md`
- the current operating contract, including every post-spawn amendment made
  through surfaced judgment calls

The forge-persisted pointer record contains only:

- repository and PR number
- current PR head, base branch and tip, event baseline, and attribution state
- every finding class and disposition
- complete review-thread and required-check state
- the exact next action

These fields are forge-derivable, except that the exact next action interprets
them. Never persist the task contract, task-specific user constraints,
checkout paths, ownership mechanics, host details, operating prompt, or other
chat-only material. Do not copy and redact those private inputs: exclude the
entire field class from the forge record.

The main agent coordinates ownership with this handshake:

1. The old conductor persists the pointer-only record in the work unit's tracker
   issue when one carries the authoritative contract, otherwise in a PR
   comment. It surfaces that durable URL or ID to the
   main agent, pauses, and retains exchange and checkout ownership while
   performing no further checkout or host mutation. A failed or incomplete
   write aborts rotation. Do not use a decision note as the live pointer record.
2. The main agent spawns one fresh-context replacement with the current private
   brief and the pointer-record URL.
   The replacement reads the durable record, starts no watcher, and makes no
   checkout, host, or forge mutation before transfer. It refreshes the
   forge read-only, including current head, base,
   baseline attribution, checks, threads, and reviewer state; reconciles every
   forge value with the pointer record; reconciles private operating state with
   the main-supplied brief; inspects the exact checkout path that will be
   transferred; and reports provisional acceptance or a precise mismatch to
   the main agent. This read-only inspection does not require the replacement
   to check out the PR branch or claim checkout ownership while the old
   conductor owns it.
3. On any stale head, base, baseline, finding, thread, check, or reviewer state,
   unresolved work, live push or watcher, checkout mismatch, unavailable path
   transfer, or failed provisional acceptance, the main agent persists only
   the refreshed forge-derivable state and exact next action beside the pointer
   record, then aborts the transfer. It reports private mismatches only through
   the live agent channel. For a successful reconciliation, the main agent
   persists the refreshed forge state and next action there before transfer.
   A failed or incomplete result write also aborts rotation.
   Start no replacement watcher, do not terminate the old conductor, and keep
   or resume the old owner unless the existing safety or judgment rules require
   a stop.
4. After reconciliation and provisional inspection succeed, the already-live
   replacement explicitly accepts future ownership of the exchange and exact
   checkout path, contingent on the old conductor's release. The main agent
   then instructs the old conductor to release both forms of ownership and
   acknowledge that release before terminating. Without that acknowledgement,
   the old conductor remains the owner and the transfer aborts. With it, both
   forms transfer exactly once to the replacement before the old conductor
   terminates. Ownership and the checkout-path transfer are then complete and
   not repeatable; only the activation notification to the replacement remains.
   After that release acknowledgement the main agent sends the
   replacement one activation message stating that release landed and that it
   now owns the exchange and the exact checkout path. The replacement takes no
   owning action before that message. Ownership has already transferred
   exactly once at that release acknowledgement, so the activation message
   is idempotent: a lost or delayed one never re-transfers ownership. The
   replacement confirms receipt, and while that confirmation is absent,
   whether the main agent was interrupted or the message was simply
   dropped, the main agent re-sends the same activation message; the
   replacement keeps waiting, taking no owning action, until one arrives,
   and re-sending never re-transfers ownership.
5. This step begins only after that activation message. The
   replacement retains ownership if the old conductor's termination or
   completion notification is delayed or ambiguous; here "delayed" refers to
   the old conductor's termination notice, not to the activation message. It
   immediately runs the full checkout gate at the path it already inspected,
   before any mutation or watcher. A failed gate does not end the exchange: the replacement keeps both
   forms of ownership, surfaces the precise recovery state, and resumes after
   main-agent-coordinated recovery. If the replacement is interrupted after
   this activation message, whether or not its checkout gate has completed, the
   main agent resumes that same owner under stranded-conductor recovery. An
   interruption during the
   activation gap, after ownership transferred at the release acknowledgement
   but before the activation message arrives, is not stranded-conductor
   recovery: the replacement only keeps waiting and the main agent re-sends the
   idempotent activation message per step 4, starting no watcher, running no
   checkout gate, and doing no review work until activation arrives. Only a
   successful gate permits the exact next action and at most one watcher.

Never overlap watchers or active checkout ownership. A replacement's
read-only reconciliation is provisional acceptance, not permission to mutate,
check out the PR branch in a second worktree, or claim checkout ownership
before the one-time transfer.

## Stranded-conductor recovery

Treat any conductor completion notice whose report says it is still waiting
as a stranded exchange, whether it is an ordinary conductor or an activated
rotation replacement, and whether or not that replacement has completed its
checkout gate. The one exception is a rotation replacement still in the
activation gap, interrupted after ownership transferred at the release
acknowledgement but before the activation message arrives: it is not
stranded, and rotation handshake step 4 governs it instead (re-wait and
idempotent activation re-send, with no watcher and no checkout gate until
activation arrives). A stranded replacement that has not yet completed its
checkout gate runs that gate first, per step 5, before step 2 below resumes
any watcher, so no watcher ever precedes the gate. Resume the stranded
conductor with these instructions:

1. Terminate or reuse the abandoned watcher so only one watch remains.
2. Resume the foreground script or the scheduled same-conductor connector/API
   polling loop with the frozen baseline and expected head.
3. Continue until a surfaced decision or terminal ledger.

Do not wait alongside the stranded conductor and do not start a second
conductor for the same PR/reviewer. A stranded completion is not a quiescent
rotation boundary; only a successful context-rotation handshake permits a
replacement.
