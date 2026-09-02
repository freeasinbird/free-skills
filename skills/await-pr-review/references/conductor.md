# Conductor Contract

Read this reference before you spawn or resume a conductor. It owns the
whole-exchange mechanics that don't belong in the routing-focused entry
point.

## Contents

- [Spawn brief](#spawn-brief)
- [Probes](#probes)
- [Turn discipline](#turn-discipline)
- [Checkout gate](#checkout-gate)
- [Pinned force-with-lease](#pinned-force-with-lease)
- [Quiescence and reporting](#quiescence-and-reporting)
- [Context rotation](#context-rotation)
- [Stranded-conductor recovery](#stranded-conductor-recovery)

## §spawn-brief

Spawn the conductor with the least inherited parent context the host exposes:

- Codex: use `fork_turns: "none"`.
- Claude Code: use an ordinary named background subagent, not a
  context-inheriting fork.
- Another host: request fresh or empty context when it is supported.

If the host can't control inheritance, say so in the brief and continue when
the four conductor grants still hold. Context control is an optimization, not a
fifth grant.

Give the conductor one compact, self-contained task with these facts:

- The current task contract at spawn: objective, acceptance criteria, scope,
  dependencies and blockers, explicit non-goals, and task-specific user
  constraints
- Repository and PR number
- Automated reviewer login in each required API form, when already recorded
- Trigger and progress/clean status signals, when already recorded
- Baseline source and exact timestamp (plus the post-push disambiguation
  reading when the baseline used the pre-push fallback), or the explicit
  attribution gap when no baseline could be anchored
- Expected PR head SHA
- Base branch and base-tip SHA
- Initial-context mode, or the unsupported-control notice
- Available host-observation surface (script, API, or connector)
- Conductor-local wait or scheduled same-conductor wake mechanism
- Checkout path and whether it is isolated or exclusively assigned
- Project review-response, commit, verification, and handoff conventions
- The path to `references/conductor-brief.md`, the conductor's one startup
  read, which carries the operating contract and points to the deeper
  references on demand

When reviewer identity or trigger facts are not recorded yet, say so in the
brief and assign the conductor the step-2 discovery before it waits. Don't make
the main agent scan history just to complete the brief. Grant checkout
isolation or exclusivity explicitly, and run the conductor on a model capable
of editing and review judgment, not the cheapest watcher tier.

In this reference, `current task contract` means that initial contract plus
every later decision and constraint amendment the user makes through a surfaced
judgment call.

The brief file carries the operating contract, so the spawn message need not
repeat it. The conductor must be able to act from the spawn message plus that
one file without parent conversation history; it opens `detection.md`,
`review-response.md`, and this reference only where the brief points to them.
It reads the referenced project conventions itself. Keep its reports compact:
finding ID, one-line disposition, final pushed SHA or issue, checks status,
and only enough context to decide a surfaced call.

## §probes

Map any agent's actual tools to the four routing grants through the probes
below. Each probe names the evidence to look for, what that evidence looks
like on Claude Code and on Codex, and the default when the evidence is absent
or the probe cannot run. The defaults favor spawning. A wrongly spawned
conductor reports a concrete gap in its first turn; a wrongly skipped one
costs the whole exchange in main context.

### Grant 1: Write-Capable Delegation

- **Probe:** the session's tool list contains a spawn tool whose subagent can
  edit files and run commands, and no rule in effect forbids using it for
  this skill.
- **Claude Code:** the `Agent` tool is listed with a general-purpose agent
  type. Spawn an ordinary named background subagent, which starts with fresh
  context, not a fork that inherits the parent conversation.
- **Codex:** `spawn_agent` is listed. Spawn with `fork_turns: "none"` so the
  conductor inherits no parent turns.
- **Other hosts:** any listed tool that starts a separate agent with the
  parent's edit and command tools.
- **Default:** a listed spawn tool grants it; a missing one fails it. A
  tool list you cannot observe grants it: attempt the spawn, and a failed
  spawn is the concrete absence. A multi-agent rule that disables proactive delegation except when the user or
  an applicable skill requests it does not fail this grant, because this
  skill is that request. To fail it on a higher-priority instruction, explain
  why the rule's exceptions exclude skill-mandated delegation. Then name the
  rule by source, or give a non-sensitive paraphrase when disclosure is
  restricted.

### Grant 2: Wait-and-Resume Continuity

- **Probe:** the subagent can delay in-turn with a bounded foreground
  command, or the host can schedule a wake that resumes the same subagent.
  The host can also message or resume that subagent after it surfaces a
  pause.
- **Claude Code:** a background subagent runs a bounded shell wait such as
  `watch-review.sh` in the foreground. `SendMessage` re-enters the same
  subagent after it pauses.
- **Codex:** the spawned agent runs the same bounded shell wait. Whichever
  listed tool continues an idle agent resumes it after a pause. Its name
  varies by version (`send_input`, `resume_agent`, and `followup_task` have
  all been reported), so match the listed tool, not a name.
- **Other hosts:** a shell or a scheduled same-agent wake, plus any follow-up
  or resume control that targets the same agent.
- **Default:** a shell in the subagent grants it. It fails only on concrete
  absence: the subagent has neither an in-turn bounded wait nor a scheduled
  same-conductor wake, or the host cannot re-enter it after a pause. A
  background process that re-enters only the main-agent layer does not satisfy
  this grant.

### Grant 3: Completion Notification

- **Probe:** the host delivers a notification to the main agent when the
  subagent ends, or exposes a blocking wait on the subagent's completion.
- **Claude Code:** a background subagent's completion arrives as a task
  notification.
- **Codex:** `wait_agent` blocks until the agent reaches a final status, and
  the host also sends a notification message carrying that status.
- **Other hosts:** any completion callback or blocking wait a listed tool
  describes.
- **Default:** a listed spawn tool grants it. It fails only when a listed
  tool's own description says completion is not surfaced.

### Grant 4: Checkout Isolation or Exclusivity

- **Probe:** `git worktree list` shows the PR branch checked out in a
  worktree the conductor can own, or the spawn call can create one.
  Otherwise the checkout is shared, and the main agent grants exclusivity by
  making no edit, commit, PR-branch fetch, rebase, or push until the terminal
  ledger.
- **Claude Code:** the spawn call accepts `isolation: "worktree"`, and a
  session already running in a dedicated worktree can hand that path to the
  conductor.
- **Codex:** subagents share the checkout. Grant exclusivity by leaving the
  PR branch untouched in the main agent until the terminal ledger.
- **Other hosts:** apply the same two options, then run the checkout gate
  below before every write. Isolation and exclusivity satisfy the grant
  equally.
- **Default:** grant exclusivity. It fails only when the main agent must keep
  changing that checkout during the exchange.

### When a Probe Cannot Run

A probe that cannot run, such as a tool list the host does not expose, is not
a failed grant. Take the grant's default, record the unobserved evidence in
the brief, and let the conductor report any concrete gap in its first turn.
Do not infer a failed grant from an unfamiliar tool name; name the concrete
missing grant when one is absent. Request fresh or empty context when the
host supports it. When it cannot control inherited context, state that limit
and continue with the compact self-contained brief; this optimization gap is
not a failed grant.

## Turn Discipline

The conductor keeps ownership for the whole exchange. It pauses or ends a turn
only for:

- A scheduled wake that targets this same conductor and preserves its exchange
  state without reporting terminal completion
- A judgment call that the main agent or user must decide
- A no-go or materially uncertain convergence escalation
- An armed context-rotation handoff or read-only reconciliation result that
  the main agent must coordinate
- The terminal disposition ledger

A scheduled wake resumes the conductor automatically. Resume the same conductor
after any ordinary surfaced call. Don't spawn a replacement or release checkout
exclusivity during an ordinary pause. Context rotation is the only replacement
path, and it hands the main agent the handoff between the conductor's quiescent
checkpoint pauses.

Prefer a bounded foreground poll inside the conductor: it is the cheapest
ownership-preserving path. Use the script where it can run. An API or connector
loop that can't delay in-turn schedules a wake of this same conductor and
preserves its exchange state across the pause.

If the conductor has neither an in-turn bounded wait nor a scheduled
same-conductor wake, grant 2 failed and the exchange belongs in the main
agent. A background
process that re-enters only the main-agent layer doesn't satisfy this contract:
it can strand the exchange and send a misleading completion notice.

## §checkout-gate

The conductor rewrites and force-pushes the PR branch, so it needs one of:

- An isolated worktree, checkout, or clone, or
- Exclusive ownership of a shared checkout, while the main agent makes no edit,
  commit, fetch of the PR branch, rebase, or push.

Isolation and exclusivity satisfy the fourth routing gate equally. Don't
silently reinterpret isolation as mandatory on a platform whose subagents share
the filesystem.

Before the first write, and before any later write after a wait or resume, the
conductor verifies these checks. Under main ownership, the main agent runs the
same gate itself:

1. The host-reported PR head equals its checkout HEAD.
2. The worktree and index are clean, including untracked files.
3. The checked-out branch is the PR branch it is expected to push.
4. The host PR object exists and its lifecycle state is open.

Handle a failed check by its cause:

- A dirty worktree or index is unrelated user state. Stop without modifying,
  moving, stashing, or cleaning it, and surface the exact paths.
- A clean checkout on the wrong branch or head may be re-anchored to the fetched
  PR head before editing.
- A failed lifecycle query, or a missing, null, malformed, closed, or merged PR,
  stops the response round as incomplete evidence.

A pinned lease protects the remote's old value. It does not prove the local
history being installed is the intended PR history.

Exclusivity lasts through surfaced pauses until the terminal ledger. A human
change requested mid-exchange goes through the conductor, or ends the exchange
first.

## Pinned Force-With-Lease

Pin the lease explicitly on every rewritten push:

```text
--force-with-lease=<branch>:<last-pushed-sha>
```

Use the expected head captured at the event boundary on the first push. Use the
conductor's own last pushed head on later pushes.

Never use a bare lease. A fetch can advance the remote-tracking ref, and a bare
lease then blesses overwriting a contributor's push. Don't advance the pin to a
newly observed remote SHA that local history does not contain, either.

A failed pinned lease means someone else pushed. Stop, fetch, incorporate the
observed remote head into local history, re-run the relevant verification, then
advance the lease to that incorporated head for the retry.

## §quiescence-and-reporting

The conductor waits out every review its own push triggers, including a final
locally verifiable triage push. It emits the terminal ledger only at quiescence:

- A clean pass tied to the current round
- A bounded timeout whose coverage and baseline are recorded
- Every finding dispositioned, with no push pending

Past the final triage push, a new blocker reopens fix rounds. New non-blockers
take terminal dispositions only (defer or decline), so a reviewer producing one
new nit per push can't hold checkout exclusivity forever.

Immediately before a terminal ledger declares the PR ready, take a fresh
live-state snapshot, including after any resume or interruption. The snapshot
must carry:

- The PR object present, its lifecycle state open, and the PR review-ready
  rather than draft
- The host-reported PR head, refreshed and equal to the last handled and
  verified head, with required checks covering that exact head
- Automated-review evidence: either a completed pass tied to that head with
  every activity dispositioned, or a fully covered bounded timeout whose final
  observation found no in-progress signal
- The current base tip and freshness, every review thread and blocker, pending
  push state, and any automated-review activity after the last handled boundary

Page every collection needed to prove those facts to exhaustion.

Treat the snapshot as valid only when every required query succeeds and every
required scalar and collection is present with the expected shape. Treat any of
these as incomplete evidence, never as an empty or clean state:

- A failed or partial query
- A missing PR
- An absent required field
- A null where the field contract requires a value
- A malformed value
- An unexhausted page

Preserve documented nullability: for an open PR, `closedAt` and `mergedAt` are
expected to be null.

Require two consecutive complete composite scans with identical canonical
results. Compare across both scans:

- PR lifecycle, head, base, checks, and pending push
- Every review, comment, and reply identity and timestamp
- The complete thread map, including each thread's `isResolved` state and latest
  comment identity

If any value or page metadata differs, discard both mixed-time scans and restart
until two complete scans match. Cached, single-scan, or partially compared state
never proves readiness. A changed PR head makes the previous evidence stale:
capture the new event boundary and reopen the exchange. Reopen on new same-head
reviewer activity too; head equality does not disposition a late review,
comment, or reply.

Don't declare the PR ready while any of these holds:

- Its lifecycle is not open, or it remains draft
- Any blocker or thread is unresolved
- A push is pending
- Reviewer activity after the handled boundary is undispositioned
- The reviewer is known to be in progress, outside the main-owned
  final-triage exception in `review-response.md`
- Review or snapshot coverage is incomplete or broken
- A required check is failed or incomplete
- The base is stale

If the current base branch or tip differs from the recorded base, report the
review exchange complete but integration evidence stale, and return to the
project's freshness workflow. Do not update the branch as part of the watcher
role. Wait for every required check and fix any known-red result before
claiming the PR ready; review completion is not CI completion. Leave the PR
open for human review and merge unless the project explicitly opts into
self-merge.

The terminal ledger records every finding disposition, the fresh checks and
thread states, the current PR head, the current base and its freshness result,
pending push or review state, and any watch coverage gap. It is the conductor's
completion, not a question to answer.

## §context-rotation

Keep the same conductor through ordinary waits and review rounds. Elapsed
time, idle time, and poll count are not reasons to replace it. Context size
is, and because no host exposes it, the conductor's fix-round count stands in
for it: on measured exchanges a fix round adds roughly 50k tokens, so three
rounds from a typical start cross about 200k. `references/cost-model.md`
records that calibration.

Rotation arms at the end of every third fix round since the conductor's
spawn, or immediately when the host reports compaction or a context limit. It
stays armed until a rotation completes; a replacement starts its own count.
Once armed, rotate only when all of these hold:

- A full fix round is waiting: the pass on the latest push is dispositioned,
  and at least one accepted finding earns another reviewer round rather than
  a final triage push or a decline-only close
- Fresh or empty replacement context is available
- The host can transfer the existing checkout path to the replacement without
  creating a second checkout of the PR branch

If any of those fails, keep the current conductor and re-check at the next
boundary. The count is a trigger, not a kill switch: the quiescence and
exactly-once ownership gates below still decide when and whether the transfer
completes.

The full-fix-round condition is the cost gate from `references/cost-model.md`.
On its calibration, a fix round of any size replays the old context often
enough to repay one replacement startup and handshake, while a final triage
push or a decline-only close does not. Do not estimate the pending round's
size beyond that test; the earlier size-and-strain judgment never fired.

Rotate only at a quiescent boundary between rounds. Require all of these before
rotating:

- The current round fully dispositioned and verified
- Its push complete
- Its baseline advanced
- Its watcher consumed or stopped
- And no pending push, active watcher, undispositioned finding, or unresolved
  decision

A failed gate aborts rotation without changing exchange or checkout ownership.

Prepare two deliberately separate rotation artifacts. The live main agent
keeps a private replacement brief containing the current task contract: the
initial brief's contract plus every post-spawn decision and constraint
amendment the user made through surfaced judgment calls. It also contains:

- Available host-observation surface and conductor-local wait or scheduled-wake
  mechanism
- The automated reviewer login in every required API form, trigger, and progress
  and clean-pass signals
- Pinned lease SHA
- Fix-round and convergence-checkpoint counts for the rising bar, prior
  checkpoint calls and evidence, and the next checkpoint cadence; the
  replacement's rotation count restarts at zero
- The current taper or rising-bar phase and whether the one permitted final-triage
  push has already been used
- Pending-push and active-watcher state
- Checkout path, its isolation or exclusivity grant, and the host mechanism
  that will transfer that exact path to the replacement
- Ownership state before rotation and the exact old-to-new transfer point
- Project review-response, commit, verification, and handoff conventions
- The path to `references/conductor-brief.md`
- Plus the current operating contract, including every post-spawn amendment made
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

1. The old conductor persists the pointer-only record in the work unit's
   tracker issue when one carries the authoritative contract, otherwise in a PR
   comment. It then surfaces that durable URL or ID to the main agent, pauses,
   and keeps exchange and checkout ownership while making no further checkout or
   host mutation. A failed or incomplete write aborts rotation. Don't use a
   decision note as the live pointer record.
2. The main agent spawns one fresh-context replacement with the current private
   brief and the pointer-record URL. The replacement reads the durable record,
   starts no watcher, and makes no checkout, host, or forge mutation before
   transfer. It then:
   - Refreshes the forge read-only, including current head, base, baseline
     attribution, checks, threads, and reviewer state
   - Reconciles every forge value with the pointer record
   - Reconciles private operating state with the main-supplied brief
   - Inspects the exact checkout path that will be transferred
   - Reports provisional acceptance or a precise mismatch to the main agent

   This read-only inspection does not require the replacement to check out the
   PR branch or claim checkout ownership while the old conductor owns it.

3. The main agent decides the transfer from the reconciliation result.

   Several conditions abort the transfer:
   - A stale head, base, baseline, finding, thread, check, or reviewer state
   - Unresolved work, a live push, or a live watcher
   - A checkout mismatch or an unavailable path transfer
   - A failed provisional acceptance

   On any of those, the main agent persists only the refreshed forge-derivable
   state and exact next action beside the pointer record, then aborts the
   transfer. It reports private mismatches only through the live agent channel.

   For a successful reconciliation, the main agent
   persists the refreshed forge state and next action there before transfer. A
   failed or incomplete result write also aborts rotation.

   In every abort, start no replacement watcher, don't terminate the old
   conductor, and keep or resume the old owner unless the existing safety or
   judgment rules require a stop.

4. Transfer ownership exactly once, on the old conductor's release. After
   reconciliation and provisional inspection succeed:
   - The already-live replacement explicitly accepts future ownership of the
     exchange and exact checkout path, contingent on the old conductor's
     release.
   - The main agent instructs the old conductor to release both forms of
     ownership and acknowledge that release before terminating.
   - Without that acknowledgement, the old conductor stays the owner and the
     transfer aborts.
   - With it, both forms transfer exactly once to the replacement before the old
     conductor terminates. Ownership and the checkout-path transfer are then
     complete and not repeatable;
     only the activation notification to the replacement remains.

   After that release acknowledgement, the main agent sends the replacement one
   activation message stating that release landed and that it now owns the
   exchange and the exact checkout path. The replacement takes no owning action
   before that message. Ownership already transferred exactly once at the
   release acknowledgement, so the activation message is idempotent: a lost or
   delayed one never re-transfers ownership.

   The replacement confirms receipt. While that confirmation is absent, whether
   the main agent was interrupted or the message was dropped, the main agent
   re-sends the same activation message. The replacement keeps waiting, taking
   no owning action, until one arrives, and re-sending never re-transfers
   ownership.

5. This step begins only after that activation message. The
   replacement retains ownership if the old conductor's termination or
   completion notification is delayed or ambiguous; here "delayed" refers to the
   old conductor's termination notice, not to the activation message.

   The replacement immediately runs the full checkout gate at the path it
   already inspected, before any mutation or watcher. A failed gate does not end
   the exchange: the replacement keeps both forms of ownership, surfaces the
   precise recovery state, and resumes after main-agent-coordinated recovery.

   Handle an interruption by when it lands:
   - Interrupted after this activation message, whether or not its checkout gate
     has completed: the main agent resumes that same owner under
     stranded-conductor recovery.
   - Interrupted during the activation gap, after ownership transferred at the
     release acknowledgement but before the activation message arrives: this is
     not stranded-conductor recovery. The replacement only keeps waiting and the
     main agent re-sends the idempotent activation message per step 4, starting
     no watcher, running no checkout gate, and doing no review work until
     activation arrives.

   Only a successful gate permits the exact next action and at most one watcher.

Never overlap watchers or active checkout ownership. A replacement's read-only
reconciliation is provisional acceptance, not permission to mutate, check out
the PR branch in a second worktree, or claim checkout ownership before the
one-time transfer.

## §stranded-conductor-recovery

Treat any conductor completion notice whose report says it is still waiting as a
stranded exchange. This holds whether it is an ordinary conductor or an
activated rotation replacement, and whether or not that replacement has
completed its checkout gate.

One exception: a rotation replacement still in the activation gap, interrupted
after ownership transferred at the release acknowledgement but before the
activation message arrives. That case is not stranded. Rotation handshake step 4
governs it instead: re-wait and idempotent activation re-send, with no watcher
and no checkout gate until activation arrives.

A stranded replacement that has not yet completed its checkout gate runs that
gate first, per step 5, before step 2 below resumes any watcher. No watcher ever
precedes the gate.

Resume the stranded conductor with these instructions:

1. Terminate or reuse the abandoned watcher so only one watch remains.
2. Resume the foreground script, or the scheduled same-conductor connector/API
   polling loop, with the frozen baseline and expected head.
3. Continue until a surfaced decision or terminal ledger.

Don't wait alongside the stranded conductor, and don't start a second conductor
for the same PR/reviewer. A stranded completion is not a quiescent rotation
boundary; only a successful context-rotation handshake permits a replacement.
