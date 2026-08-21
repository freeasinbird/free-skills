---
name: await-pr-review
description: >-
  Wait for an automated PR reviewer (such as Codex) after opening or pushing
  a pull request, then handle its feedback without making the user request
  repeated checks. Start the watch by default, detect review bodies, inline
  comments, replies, and out-of-band clean-pass signals, auto-address
  clear-cut findings, and surface judgment calls. Where write-capable
  delegation has wait-and-resume continuity plus checkout isolation or
  exclusivity,
  spawn a conductor subagent to own the whole exchange; use a main-owned
  watcher only when a named conductor gate is unavailable. Not for human-only
  review, a branch without an open PR, or a repository with no automated
  reviewer.
---

# Await PR Review

Watch an open pull request for its automated reviewer, address the feedback,
and converge without asking the user to babysit the polling loop. This skill
owns waiting and orchestration; the project's review-response conventions
still govern commits, replies, resolution, and handoff.

## Authorization

Treat invocation of this skill as authorization to perform its ordinary,
task-scoped review-loop actions without per-action or per-round confirmation:
wait, fix accepted findings, fold fixes, push with the required pinned lease
and safeguards, verify, reply, resolve, advance the baseline, and trigger or
await the next automated pass. This includes the history rewrite required by
the project's fold convention, but only on the expected PR branch under the
checkout and lease gates.

The ordinary authorization stops at a destructive exception outside that
sequence, a failed pinned lease or other unmet safety precondition, material
scope expansion, or a genuine judgment call. Apply the documented safe
recovery where one exists; surface the stop when it needs judgment or new
authority. Obey a platform-required approval prompt, but do not invent a
conversational permission gate when invocation and the workflow safeguards
already authorize the action.

## Route ownership before waiting

**Default to one conductor subagent.** First resolve only the event-boundary
facts needed for its brief. Request the least inherited parent context the
host exposes, give the conductor a self-contained compact brief, then spawn it
before reading feedback, waiting on CI, or starting any watcher. The conductor
owns steps 1 through 5 and wakes the main agent only for a judgment call, a
no-go or materially uncertain convergence escalation, a checkpoint-approved
context-rotation handshake that the main agent must coordinate, or its terminal
disposition ledger.

Apply one platform-neutral gate. A conductor owns the exchange when all four
grants hold:

1. Write-capable delegation is available and permitted.
2. The same subagent has wait-and-resume continuity: it can stay active through
   each bounded wait or receive a scheduled wake without ending exchange
   ownership, and it can resume after surfaced pauses.
3. Completion reliably notifies or re-enters the main agent.
4. The PR branch has either an isolated checkout or explicit shared-checkout
   exclusivity until the terminal ledger.

Under a multi-agent rule that otherwise disables proactive delegation except
when the user or an applicable skill requests it, this skill supplies that
request. An applicable skill that explicitly requires delegation counts as
authorization under this exception. Do not require a separate user request.

Map any agent's actual tools to those grants. The named surfaces below are
concrete examples that prevent repeated capability guesswork; they do not
replace the generic route:

- **Codex app:** spawn the conductor with `fork_turns: "none"` so it inherits
  no parent turns. Collaboration tools that expose spawn and completion
  notification satisfy grants 1 and 3. Follow-up/resume plus a conductor-local
  foreground wait or scheduled same-conductor wake satisfy grant 2. If agents
  share the checkout, grant branch exclusivity by having the main agent make no
  edit, commit, fetch of the PR branch, rebase, or push until the terminal
  ledger. If the main agent must keep changing that checkout, grant 4 does not
  hold.
- **Claude Code:** use one ordinary named background subagent, which starts
  with fresh context, rather than an experimental fork that inherits the
  parent conversation. Give it explicit worktree isolation. Its blocking
  foreground wait plus re-messaging the same agent satisfy grant 2; completion
  notification satisfies grant 3.
- **Any other agent:** inspect its delegation, conductor-local wait and resume,
  completion, and checkout controls and apply the same four-grant gate. An API
  or connector that can only return instantaneous reads does not satisfy grant
  2 unless it can schedule the same conductor to resume without ending the
  exchange. Request fresh or empty context when the host supports it. When it
  cannot control inherited context, state that limitation and continue with
  the compact self-contained brief; this optimization gap is not a failed
  conductor grant. Do not infer a failed gate from unfamiliar tool names; name
  the concrete missing grant if one is absent.

Keep the exchange in the main agent only when a grant is concretely absent or
forbidden, or when feedback is already in hand and known to require at most a
couple of trivial operations. A small main context, a background shell, or a
prediction that the review will be clean or one-shot is not an exception.

Before any main-owned watch, state the fallback in this exact shape, naming
either the failed grant or the narrow trivial-feedback exception:

```text
Conductor skipped: <specific failed grant or allowed exception>.
```

“Higher-priority instruction” is not a valid failed grant by itself. To fail
grant 1 on that basis, identify the prohibiting rule by source when disclosure
is permitted, or give a non-sensitive paraphrase of the binding constraint
otherwise, and explain why none of its exceptions apply.

The main agent captures and passes the current task contract at spawn
(objective, acceptance criteria, scope, dependencies and blockers, explicit
non-goals, and task-specific user constraints); repository and PR; any recorded
reviewer identity and status signals; the event-anchored baseline (or its
explicit attribution gap); expected PR head; base branch and base tip; the
initial-context mode or unsupported-control notice; the available
host-observation surface (script, API, or connector); the conductor-local wait
or scheduled-wake mechanism; checkout ownership; the project review-response
conventions; the relevant skill and reference paths; and the operating
contract in `references/conductor.md`. An unrecorded reviewer is not a reason
to delay the spawn; assign step-2 discovery to the conductor. Grant checkout
isolation or exclusivity explicitly. Use a model capable of editing and review
judgment, not the cheapest watcher tier. Read that reference before spawning;
it contains the ready-to-use brief, turn discipline, checkout alignment,
rotation protocol, and lease rules.

## The exchange

### 1. Resolve the PR and anchor the baseline

Resolve the current branch's PR and record the event that should produce the
next pass. For an open- or push-triggered wait, use the host's open, ready, or
push event time. For a manual no-push recheck, use the request time. Never use
the commit authored time or a local clock reading taken after the event.

Record the expected head plus the base branch and current base tip from the
host. The main agent captures these facts at the event boundary even when a
conductor will own everything afterward.

Confirm which round a returned pass actually covered before accepting it.
GitHub attributes a review to the head current at submission, not necessarily
the head the reviewer analyzed, and reactions carry no head. This attribution
check belongs to the exchange owner and is not repeated later.

Read `references/detection.md` for host-event queries, the two-reading
pre-push fallback, source paging, login forms, and attribution caveats.

### 2. Identify and, if needed, request the reviewer

Prefer the project's recorded automated-reviewer identity, trigger, and
status signals. Otherwise detect a bot that actually submits reviews or a
clean-pass-only bot with recurring PR-description reactions. If detection
finds multiple bot reviewers, ask which one to await. If the trigger cannot
be established, ask rather than burning the wait cap.

Record a newly observed reviewer, or newly observed status signals for an
existing reviewer, in the project's designated unmanaged conventions section.
Never record an absence. Request a command-triggered reviewer once when no
request is pending; do not re-trigger every poll.

### 3. Wait for new activity

**Conductor-owned exchange:** when a shell and host CLI are available, run
`watch-review.sh` as a bounded foreground command inside the conductor. When
they are not, use an equivalent bounded foreground API or connector polling
loop over the same frozen baseline, expected head, sources, and completion
signals. A connector loop that cannot delay in-turn uses the scheduled
same-conductor wake established by grant 2. Either mechanism stays under
conductor ownership; it must not emit terminal completion merely to wait. The
script blocks only the small conductor context and costs no model tokens while
polling. The connector loop may require model wakes, but it preserves conductor
ownership and the same round-attribution rules.

Keep one active watch per PR/reviewer. Start it promptly before waiting on
required checks. After a new push, advance or replace its baseline instead of
leaving duplicate watchers alive. Checks remain a separate required wait; the
review detector does not prove them green.

**Main-owned fallback only:** after emitting the required `Conductor skipped`
line, choose the cheapest permitted mechanism that reliably re-enters the
main agent:

1. A background no-model `watch-review.sh` process whose completion re-enters
   the agent, when a shell and host CLI are available.
2. A read-only watcher subagent on the smallest capable model when background
   process re-entry is absent.
3. A cancellable scheduled API or connector poll, or script invocation, that
   uses the same frozen baseline and expected head on every wake.
4. A bounded foreground detector when the main agent can remain active through
   the wait, using the script or equivalent API/connector snapshots.
5. Hand back the baseline when none can run.

The watcher-only subagent is not the conductor. It must not edit, commit,
push, trigger a review, reply, or resolve threads. Report compact IDs,
timestamps, states, paths/lines, the top-level review body, status reactions,
and checks state.

When the script is selected, run it from the PR checkout, or pass
`--repo owner/name` explicitly:

```sh
<skill-dir>/watch-review.sh --repo owner/name --pr 46 \
  --login chatgpt-codex-connector --head 9c346ab \
  --baseline 2026-07-02T05:07:30Z --interval 75 --cap-minutes 25
```

Branch on every exit: 0 review activity, 3 clean pass, 2 cap expired, 64 bad
invocation, and 69 missing `gh`. For exit 2, `polls_ok:0` means the watch never
worked; otherwise `last_poll_ok` determines whether the final window was
covered. An API or connector detector maps its outcomes to the same states as
specified in `references/detection.md`. Report incomplete coverage as
incomplete, not quiet.

Finish a round only on target-reviewer activity after the baseline: a
submitted review, a new thread, a new reply on an existing thread, or the
configured clean-pass signal. An in-progress reaction or acknowledgement is
not completion. Read the review state and body before declaring a round clean.

All detection mechanics, scheduled-wake rules, cadence, status reactions, API
field/login forms, and script exit semantics live in
`references/detection.md`.

### 4. Address feedback

Read `references/review-response.md` before changing the branch. Its gates are
part of this workflow, not optional advice.

Before changing the branch or writing host review state after any wait or
resume, refresh the PR object. Require it to exist, remain open, and still have
the expected head. A failed query or a missing, null, malformed, closed, or
merged PR stops the response round as incomplete evidence.

For every finding:

- Evaluate it on its merits. Fix real findings and decline contrived,
  speculative, or already-fixed ones with a one-line reason.
- Sweep the whole finding class, not only the cited line.
- Auto-address clear-cut fixes. Surface ambiguous, contentious, or
  design-altering calls to the user.
- Follow the project's commit convention. Where review fixes fold into their
  originating commits, the order is: fix, fold, push, verify on the pushed
  ref, reply with the final SHA, then resolve. Fold all fixes in a round and
  push once before replying to any of them.

Under conductor ownership these operations remain in the conductor. Under
main ownership, delegate a fixer only when write-capable delegation is
available and permitted, the round is long, and the main context dwarfs the
fixer's brief; otherwise address it in main.

### 5. Converge on a rising bar

After a fix push, advance the baseline and await the newly triggered pass. A
decline-only round ends the exchange because unchanged code needs no confirming
round. A command-triggered reviewer must be requested again after a push.

In the first two fix rounds, address every worthwhile finding. From the third
fix round onward, only blockers (correctness, security, data loss, broken
invariants, or red CI) earn another full round. Triage non-blockers into a
locally verifiable final push, a linked follow-up issue, or a reasoned decline.
When unsure whether a finding blocks, treat it as blocking.

Stop for human judgment on thrash: the same class recurring after a correct
complete fix, or fixes producing new problems without net progress. At about
five blocker-sustained fix rounds, make and record a go/no-go checkpoint. A go
is an internal call: record one line naming the convergence evidence, then
continue without yielding or asking permission. A no-go or materially
uncertain call surfaces the current ledger for human judgment. Repeat the
checkpoint at the same cadence while blockers continue; an earlier go does
not authorize an unbounded loop.

Keep the same conductor through ordinary waits, surfaced pauses, and review
rounds; idle lifetime alone is not a reason to replace it. Only after an
existing checkpoint records a justified go may the owner consider the context
rotation protocol in `references/conductor.md`, and only when expected
remaining work is likely to repay the full handoff and reconstruction cost in
`references/cost-model.md`. Finish and disposition the current round first,
complete any push, advance its baseline, consume or stop its watcher, and
verify that the existing checkout path can transfer safely to the already-live
replacement before rotation.

Persist the pointer-only forge record and its
forge-derived reconciliation result in the work unit before ownership moves.
That record may contain forge-derivable state and the exact next action, never
the task contract, user constraints, or other chat-only operating input. The
live main agent supplies the current private inputs to the replacement: the
initial brief plus every post-spawn decision and constraint amendment the user
made through surfaced judgment calls.
A fixed round count, elapsed time, idle time, or context size alone never forces
replacement.

Track finding classes across the whole exchange. A second member after a
class sweep requires a root-cause hypothesis for why the sweep missed it,
widens the class one level, and earns one fresh-context adversarial refute pass
where read-only delegation is available. Repeated prose-clause findings on one
rule surface should trigger an owner escalation to replace the prose program
with a tested script or check.

The full taper, final-push, checkpoint, recurrence, refute-pass, and ledger
rules live in `references/review-response.md`.

### 6. Report the ledger

Every finding ends as fixed (pushed SHA), declined (reason), deferred (linked
issue), or explicitly outstanding for the human. State any no-blocker call
that ended the exchange, whether threads are resolved, checks status, and any
bounded timeout or coverage gap.

Before calling the PR ready, take a fresh live-state snapshot, including after
any resume or interruption. Require the PR object to exist, its lifecycle state
to be open, and the PR to be review-ready rather than draft. Refresh the
host-reported PR head and require it to equal the last handled and verified
head; confirm required checks cover that exact head.
Automated-review evidence must be either a completed pass tied to that head
with every activity dispositioned, or a fully covered bounded timeout whose
final observation found no in-progress signal. The documented main-owned
final-triage handoff is the sole exception to that terminal-review evidence:
its locally verified head may be handed off with the re-review explicitly
pending. Also refresh the base branch and tip, every review thread and blocker,
pending push state, and any automated-review activity after the last handled
boundary. Page every collection needed to prove those facts to exhaustion.

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
two complete scans match. Never report readiness from cached, single-scan, or
partially compared state.

Do not call the PR ready while its lifecycle is not open or it remains draft;
any blocker or thread is unresolved; a push is pending; reviewer activity after
the handled boundary remains undispositioned; the reviewer is known to be in
progress outside that final-triage exception; review or snapshot coverage is
incomplete or broken; a required check is failed or incomplete; or the base is
stale. If the refreshed PR head differs from the last handled and verified
head, treat the earlier review and check evidence as stale, capture the new
event boundary, and reopen the exchange. Reopen on new same-head reviewer
activity too; head equality does not disposition a late review, comment, or
reply. If the current base branch or tip differs from the recorded base,
report the review exchange complete but integration evidence stale and return
to the project's freshness workflow. Do not update the branch as part of the
watcher role.

Wait for every required check and fix any known-red result before claiming the
PR ready. The ledger records the final checks state rather than treating review
completion as CI completion.

Where fixes are folded, confirm the pushed branch contains no autosquash
subjects and no standalone review-fix commits. Leave the PR open for human
review and merge unless the project explicitly opts into self-merge.

## References

- `references/conductor.md`: read before spawning or resuming a conductor.
- `references/detection.md`: read for baseline capture, reviewer detection,
  watcher execution, scheduled wakes, or hand-rolled detection.
- `references/review-response.md`: read before addressing findings and while
  applying convergence policy.
- `references/cost-model.md`: read only when re-deriving or auditing a
  borderline cost decision.

This skill assumes an open PR, an automated reviewer that can be identified,
access to the host's reviews/comments/reactions through either the bundled
script or an equivalent API/connector, and a permitted wait/re-entry
mechanism. A host CLI and shell are preferred, not mandatory. When neither
script nor API-based detection can observe the required host data, name that
missing capability and hand control back rather than pretending to watch.
