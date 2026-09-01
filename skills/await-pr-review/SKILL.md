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
owns the waiting and orchestration. The project's review-response conventions
still govern commits, replies, resolution, and handoff.

Use it after you open or push a PR that an automated reviewer will judge. Do
not use it for human-only review, a branch with no open PR, or a repository
with no automated reviewer.

The exchange runs in six steps:

1. Resolve the PR and anchor the baseline.
2. Identify the reviewer, and request it if the trigger is manual.
3. Wait for new reviewer activity.
4. Address the feedback.
5. Converge on a bar that rises each round.
6. Report the ledger.

Run one conductor subagent through steps 1 to 5 wherever the platform supports
it. The next section decides who owns the exchange.

## Authorization

Invoking this skill authorizes its ordinary, task-scoped review-loop actions
without per-action or per-round confirmation:

- Wait for the reviewer.
- Fix accepted findings and fold them into their commits.
- Push with the required pinned lease and safeguards.
- Verify, reply, and resolve threads.
- Advance the baseline, then trigger or await the next automated pass.

Folding rewrites history, so this authorization covers that rewrite, but only
on the expected PR branch under the checkout and lease gates.

The authorization stops at any of these, which need judgment or new authority:

- A destructive action outside that authorized sequence;
- A failed pinned lease, or any other unmet safety precondition;
- Material scope expansion; or
- A genuine judgment call.

At a stop, apply the documented safe recovery where one exists, and surface
the stop when it needs judgment or new authority. Obey a platform-required
approval prompt, but do not invent a conversational permission gate when
invocation and the workflow safeguards already authorize the action.

## Route Ownership Before Waiting

Decide who owns the exchange before you read feedback, wait on CI, or start any
watcher:

| Route                       | Choose it when                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------ |
| Conductor subagent, default | All four grants below hold, and the feedback is not already in hand and trivial.           |
| Main agent                  | A grant is concretely absent or forbidden, or the feedback is already in hand and trivial. |

Under main ownership, run a watcher while a reviewer wait remains, and address
feedback already in hand without a watcher (step 3).

**Default to one conductor subagent.** First resolve only the event-boundary
facts its brief needs. Request the least inherited parent context the host
exposes, give the conductor a self-contained compact brief, then spawn it
before reading feedback, waiting on CI, or starting any watcher.

The conductor owns steps 1 through 5. It wakes the main agent only for:

- A judgment call;
- A no-go or materially uncertain convergence escalation;
- A checkpoint-approved context-rotation handshake that the main agent must
  coordinate; or
- Its terminal disposition ledger.

**Apply one platform-neutral gate.** A conductor owns the exchange when all
four grants hold:

1. Write-capable delegation is available and permitted.
2. The same subagent has wait-and-resume continuity: it can stay active
   through each bounded wait or receive a scheduled wake without ending
   exchange ownership, and it can resume after surfaced pauses.
3. Completion reliably notifies or re-enters the main agent.
4. The PR branch has either an isolated checkout or explicit shared-checkout
   exclusivity until the terminal ledger.

A multi-agent rule may otherwise disable proactive delegation except when the
user or an applicable skill requests it. This skill supplies that request.
An applicable skill that explicitly requires delegation counts as
authorization under this exception. Do not require a separate user request.

Map any agent's actual tools to those grants. The named surfaces below are
concrete examples that prevent repeated capability guesswork; they do not
replace the generic route.

- **Codex app:** spawn the conductor with `fork_turns: "none"` so it inherits
  no parent turns. Collaboration tools that expose spawn and completion
  notification satisfy grants 1 and 3. Follow-up or resume, plus a
  conductor-local foreground wait or scheduled same-conductor wake, satisfy
  grant 2. If agents share the checkout, grant branch exclusivity by having
  the main agent make no edit, commit, PR-branch fetch, rebase, or push until
  the terminal ledger. If the main agent must keep changing that checkout,
  grant 4 does not hold.
- **Claude Code:** use one ordinary named background subagent, which starts
  with fresh context, rather than a fork that inherits the parent
  conversation. Give it explicit worktree isolation. Its blocking foreground
  wait plus re-messaging the same agent satisfy grant 2; completion
  notification satisfies grant 3.
- **Any other agent:** inspect its delegation, conductor-local wait and
  resume, completion, and checkout controls, then apply the same four-grant
  gate. An API or connector that can only return instantaneous reads does not
  satisfy grant 2 unless it can schedule the same conductor to resume without
  ending the exchange. Request fresh or empty context when the host supports
  it. When it cannot control inherited context, state that limit and continue
  with the compact self-contained brief; this optimization gap is not a failed
  conductor grant. Do not infer a failed gate from unfamiliar tool names; name
  the concrete missing grant if one is absent.

Keep the exchange in the main agent only when a grant is concretely absent or
forbidden, or when feedback is already in hand and known to need at most a
couple of trivial operations. A small main context, a background shell, or a
prediction that the review will be clean or one-shot is not an exception.

Before any main-owned watch, state the fallback in this exact shape, naming
either the failed grant or the narrow trivial-feedback exception:

```text
Conductor skipped: <specific failed grant or allowed exception>.
```

“Higher-priority instruction” is not a valid failed grant by itself. To fail
grant 1 on that basis, explain why none of the constraint's exceptions apply,
then either identify the prohibiting rule by source when disclosure is
permitted, or give a non-sensitive paraphrase of the binding constraint
otherwise.

At spawn, the main agent captures and passes these facts:

- The current task contract at spawn: objective, acceptance criteria, scope,
  dependencies and blockers, explicit non-goals, and
  task-specific user constraints;
- The repository and PR;
- Any recorded reviewer identity and status signals;
- The event-anchored baseline, or its explicit attribution gap;
- The expected PR head;
- The base branch and base tip;
- The initial-context mode, or an unsupported-control notice;
- The available host-observation surface (script, API, or connector);
- The conductor-local wait or scheduled-wake mechanism;
- Checkout ownership;
- The project review-response conventions;
- The relevant skill and reference paths; and
- The operating contract in `references/conductor.md`.

Also at spawn:

- An unrecorded reviewer is not a reason to delay the spawn; assign step-2
  discovery to the conductor.
- Grant checkout isolation or exclusivity explicitly.
- Use a model capable of editing and review judgment, not the cheapest watcher
  tier.
- Read `references/conductor.md` before spawning. It holds the ready-to-use
  brief, turn discipline, checkout alignment, rotation protocol, and lease
  rules.

## The Exchange

### 1. Resolve the PR and Anchor the Baseline

Resolve the current branch's PR and record the event that should produce the
next pass. Pick the baseline time by trigger:

- Open-, ready-, or push-triggered wait: the host's event time.
- Manual no-push recheck: the request time.

Never use the commit authored time, or a local clock reading taken after the
event.

Record the expected head, plus the base branch and current base tip, from the
host. The main agent captures these facts at the event boundary even when a
conductor will own everything afterward.

Confirm which round a returned pass actually covered before accepting it.
GitHub attributes a review to the head current at submission, not necessarily
the head the reviewer analyzed, and reactions carry no head. This attribution
check belongs to the exchange owner and is not repeated later.

Read `references/detection.md` for host-event queries, the two-reading
pre-push fallback, source paging, login forms, and attribution caveats.

### 2. Identify and, If Needed, Request the Reviewer

Prefer the project's recorded automated-reviewer identity, trigger, and status
signals. Otherwise, detect either a bot that actually submits reviews or a
clean-pass-only bot with recurring PR-description reactions.

- If detection finds multiple bot reviewers, ask which one to await.
- If the trigger cannot be established, ask rather than burning the wait cap.

Record a newly observed reviewer, or new status signals for an existing
reviewer, in the project's designated unmanaged conventions section. Never
record an absence. Request a command-triggered reviewer once when no request
is pending; do not re-trigger every poll.

### 3. Wait for New Activity

**Conductor-owned exchange.** When a shell and host CLI are available, run
`watch-review.sh` as a bounded foreground command inside the conductor. When
they are not, use an equivalent bounded foreground API or connector polling
loop over the same frozen baseline, expected head, sources, and completion
signals. A connector loop that cannot delay in-turn uses the scheduled
same-conductor wake from grant 2.

Either mechanism stays under conductor ownership and must not emit terminal
completion merely to wait. The script blocks only the small conductor context
and costs no model tokens while polling. The connector loop may need model
wakes, but it preserves conductor ownership and the same round-attribution
rules.

Keep one active watch per PR and reviewer. Start it promptly, before waiting
on required checks. After a new push, advance or replace its baseline instead
of leaving duplicate watchers alive. Checks stay a separate required wait; the
review detector does not prove them green.

**Main-owned fallback only:** after emitting the required `Conductor skipped`
line, choose the cheapest permitted mechanism that reliably re-enters the main
agent:

1. A background no-model `watch-review.sh` process whose completion re-enters
   the agent, when a shell and host CLI are available.
2. A read-only watcher subagent on the smallest capable model, when
   background-process re-entry is absent.
3. A cancellable scheduled API or connector poll, or script invocation, that
   uses the same frozen baseline and expected head on every wake.
4. A bounded foreground detector when the main agent can stay active through
   the wait, using the script or equivalent API or connector snapshots.
5. Hand back the baseline when none can run.

The watcher-only subagent is not the conductor. It must not edit, commit, push,
trigger a review, reply, or resolve threads. It reports compact IDs,
timestamps, states, paths and lines, the top-level review body, status
reactions, and checks state.

When you select the script, run it from the PR checkout, or pass
`--repo owner/name` explicitly:

```sh
<skill-dir>/watch-review.sh --repo owner/name --pr 46 \
  --login chatgpt-codex-connector --head 9c346ab \
  --baseline 2026-07-02T05:07:30Z --interval 75 --cap-minutes 25
```

Branch on every exit code:

| Exit | Meaning         |
| ---: | --------------- |
|    0 | Review activity |
|    3 | Clean pass      |
|    2 | Cap expired     |
|   64 | Bad invocation  |
|   69 | Missing `gh`    |

For exit 2, `polls_ok:0` means the watch never worked; otherwise
`last_poll_ok` says whether the final window was covered. An API or connector
detector maps its outcomes to the same states, per `references/detection.md`.
Report incomplete coverage as incomplete, not quiet.

Finish a round only on target-reviewer activity after the baseline: a submitted
review, a new thread, a new reply on an existing thread, or the configured
clean-pass signal. An in-progress reaction or acknowledgement is not
completion. Read the review state and body before declaring a round clean.

All detection mechanics, scheduled-wake rules, cadence, status reactions, API
field and login forms, and script exit semantics live in
`references/detection.md`.

### 4. Address Feedback

Read `references/review-response.md` before changing the branch. Its gates are
part of this workflow, not optional advice.

After any wait or resume, refresh the PR object before you change the branch or
write host review state. Require it to exist, stay open, and still have the
expected head. A failed query, or a missing, null, malformed, closed, or merged
PR, stops the response round as incomplete evidence.

Handle every finding:

- Evaluate it on its merits. A finding that asks for a guard or other
  behavioral change is real only when you can name what produces the failing
  state. Name an input the interface admits at a public or untrusted boundary,
  or an existing caller for internal code. The harm must also be material at
  the expected scale. Fix real findings; decline the rest with a one-line
  reason naming the unreachable path, the holding invariant, or why the harm
  is immaterial. Judge a clarity, documentation, naming, or maintainability
  finding on its merits and severity as before.
- Sweep the whole finding class, not only the cited line.
- Auto-address clear-cut fixes. Surface ambiguous, contentious, or
  design-altering calls to the user.
- Follow the project's commit convention. Where review fixes fold into their
  originating commits, the order is: fix, fold, push, verify on the pushed ref,
  reply with the final SHA, then resolve. Fold every fix in a round and push
  once before replying to any of them.

Under conductor ownership, these operations stay in the conductor. Under main
ownership, delegate a fixer only when write-capable delegation is available and
permitted, the round is long, and the main context dwarfs the fixer's brief;
otherwise address it in main.

### 5. Converge on a Rising Bar

After a fix push, advance the baseline and await the newly triggered pass. A
decline-only round ends the exchange, because unchanged code needs no
confirming round. A command-triggered reviewer must be requested again after a
push.

Raise the severity bar as rounds continue:

- Fix rounds 1 and 2: address every worthwhile finding.
- Fix round 3 onward: only blockers earn another full round. Blockers are
  correctness, security, data loss, broken invariants, or red CI.
- Triage each non-blocker into a locally verifiable final push, a linked
  follow-up issue, or a reasoned decline.
- When unsure whether a reachable defect blocks, treat it as blocking. When
  unsure whether its state is reachable, trace the callers or run the case
  before patching.

Stop for human judgment on thrash: the same class recurring after a correct,
complete fix, or fixes producing new problems without net progress.

From fix round 3, run the hardening check in `references/review-response.md`
before each fix round and at every checkpoint. Its signals are observable: most
findings citing lines an earlier round added, recent fixes that are all
hardening you traced no caller for, a diff that grows without delivering the
PR's What, and a flat finding count. Two signals mean the reviewer is reviewing
your hardening.

Fix what still passes both disposition questions and clears the bar; a round
count alone never turns a reachable defect into a decline. List earlier
hardening that fails either question as removal candidates, and surface the
ledger. A reviewer that posts only on findings has a floor on new code; a
posted review is not evidence that work remains.

At about five blocker-sustained fix rounds, make and record a go/no-go
checkpoint. A go is an internal call: record one line naming the convergence
evidence and blockers that passed the two disposition questions, then continue
without yielding or asking
permission. A no-go, or a materially uncertain call, surfaces the current
ledger for human judgment. Repeat the checkpoint at the same cadence while
blockers continue; an earlier go does not authorize an unbounded loop.

Keep the same conductor through ordinary waits, surfaced pauses, and review
rounds; idle lifetime alone is not a reason to replace it. Consider the
context-rotation protocol in `references/conductor.md` only after an existing
checkpoint records a justified go, and only when the expected
remaining work is likely to repay the full handoff and reconstruction cost in
`references/cost-model.md`. First finish and disposition the current round,
complete any push, advance its baseline, consume or stop its watcher, and
confirm the existing checkout path can transfer safely to the already-live
replacement before rotating.

Before ownership moves, persist the pointer-only forge record and its
forge-derived reconciliation result in the work unit. That record may hold
forge-derivable state and the exact next action, never the task contract, user
constraints, or other chat-only operating input. The live main agent supplies
the current private inputs to the replacement: the initial brief, plus every
post-spawn decision and constraint amendment the user made through surfaced
judgment calls.

A fixed round count, elapsed time, idle time, or context size alone never
forces replacement.

Track finding classes across the whole exchange. Widening applies to a real
second member, one that passes both disposition questions. Such a member
requires a root-cause hypothesis for why the sweep missed it, widens the class
one level, and earns one fresh-context adversarial refute pass where read-only
delegation is available. A second member that fails either question is a
hardening-check signal, not a class to widen. Repeated prose-clause findings
surface should trigger an owner escalation to replace the prose program with a
tested script or check.

The full taper, final-push, hardening-check, checkpoint, recurrence,
refute-pass, and ledger rules live in `references/review-response.md`.

### 6. Report the Ledger

End every finding in exactly one state: fixed (with the pushed SHA), declined
(with the reason), deferred (with a linked issue), or explicitly outstanding
for the human. Also state any no-blocker call that ended the exchange, whether
threads are resolved, the checks status, and any bounded timeout or coverage
gap.

Before you call the PR ready, take a fresh live-state snapshot, including after
any resume or interruption. Page every collection needed to prove those facts
to exhaustion.

The snapshot must carry:

- The PR object present, its lifecycle open, and the PR review-ready, not
  draft;
- The host-reported PR head, equal to the last handled and verified head, with
  required checks covering that exact head;
- Automated-review evidence that is either a completed pass tied to that head
  with every activity dispositioned, or a fully covered bounded timeout whose
  final observation found no in-progress signal;
- The base branch and tip; and
- Every review thread and blocker, pending push state, and any automated-review
  activity after the last handled boundary.

The documented main-owned final-triage handoff is the sole exception to that
terminal-review evidence: its locally verified head may be handed off with the
re-review explicitly pending.

Treat any of these as incomplete evidence, never as an empty or clean state:

- A failed or partial query;
- A missing PR, or an absent required field;
- A null where the field contract requires a value;
- A malformed value; or
- An unexhausted page.

The snapshot is valid only when every required query succeeds and every
required scalar and collection is present with the expected shape. Preserve
documented nullability: for an open PR, `closedAt` and `mergedAt` are expected
to be null.

Require two consecutive complete composite scans with identical canonical
results. Compare PR lifecycle, head, base, checks, pending push, every review,
comment, and reply identity and timestamp, and the complete thread map,
including each thread's `isResolved` state and latest comment identity. If any
value or page metadata differs, discard both mixed-time scans and restart until
two complete scans match. Never report readiness from cached, single-scan, or
partially compared state.

Do not call the PR ready while any of these holds:

- Its lifecycle is not open, or it remains draft;
- Any blocker or thread is unresolved;
- A push is pending;
- Reviewer activity after the handled boundary is undispositioned;
- The reviewer is known to be in progress, outside that final-triage exception;
- Review or snapshot coverage is incomplete or broken;
- A required check is failed or incomplete; or
- The base is stale.

If the refreshed PR head differs from the last handled and verified head, treat
the earlier review and check evidence as stale, capture the new event boundary,
and reopen the exchange. Reopen on new same-head reviewer activity too; head
equality does not disposition a late review, comment, or reply. If the current
base branch or tip differs from the recorded base, report the review exchange
complete but integration evidence stale, and return to the project's freshness
workflow. Do not update the branch as part of the watcher role.

Wait for every required check and fix any known-red result before claiming the
PR ready. The ledger records the final checks state; review completion is not
CI completion.

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
access to the host's reviews, comments, and reactions through either the
bundled script or an equivalent API or connector, and a permitted wait or
re-entry mechanism. A host CLI and shell are preferred, not mandatory. When
neither the script nor API-based detection can observe the required host data,
name that missing capability and hand control back rather than pretending to
watch.
