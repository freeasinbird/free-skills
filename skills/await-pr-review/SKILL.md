---
name: await-pr-review
description: >-
  Wait for an automated PR reviewer (such as Codex) after opening or pushing
  a pull request, then handle its feedback without making the user request
  repeated checks. Start the watch by default, detect review bodies, inline
  comments, replies, and out-of-band clean-pass signals, auto-address
  clear-cut findings, and surface judgment calls. Where write-capable
  delegation has wait-and-resume continuity plus checkout isolation or
  exclusivity, spawn a conductor subagent to own the whole exchange; use a
  main-owned watcher only when a named conductor gate is unavailable. Not for
  human-only review, a branch without an open PR, or a repository with no
  automated reviewer.
---

# Await PR Review

Watch an open pull request for its automated reviewer, address the feedback,
and converge without asking the user to babysit the polling loop. This skill
owns the waiting and orchestration; the project's review-response conventions
still govern commits, replies, resolution, and handoff.

## Authorization

Invoking this skill authorizes its ordinary, task-scoped review-loop actions
without per-action or per-round confirmation. Those actions are waiting for
the reviewer; fixing accepted findings and folding them into their commits;
pushing with the required pinned lease and safeguards; verifying, replying,
and resolving threads; and advancing the baseline, then triggering or
awaiting the next pass. Folding rewrites history; that rewrite is covered
only on the expected PR branch under the checkout and lease gates.

The authorization stops at a destructive action outside that sequence, a
failed pinned lease or other unmet safety precondition, material scope
expansion, or a genuine judgment call. At a stop, apply the documented safe
recovery where one exists, and surface what needs judgment or new authority.
Obey a platform-required approval prompt, but never invent a conversational
permission gate that these safeguards already cover.

## Route Ownership Before Waiting

Decide who owns the exchange before you read feedback, wait on CI, or start
any watcher. **Default to one conductor subagent.** It owns steps 1 to 5 and
wakes the main agent only for a judgment call, a no-go or uncertain
convergence escalation, an approved rotation handshake, or its terminal
ledger. Resolve only the event-boundary facts its brief needs, then spawn it
with the least inherited context the host exposes and the brief in
`references/conductor.md` §spawn-brief. The brief opens with the
current task contract at spawn: objective, acceptance criteria, scope,
dependencies and blockers, non-goals, and task-specific user constraints.

**Apply one platform-neutral gate.** A conductor owns the exchange when all
four grants hold:

1. Write-capable delegation is available and permitted.
2. The same subagent has wait-and-resume continuity: it stays active through
   each bounded wait, or receives a scheduled wake, without ending exchange
   ownership, and it resumes after surfaced pauses.
3. Completion reliably notifies or re-enters the main agent.
4. The PR branch has an isolated checkout or explicit shared-checkout
   exclusivity until the terminal ledger.

A multi-agent rule may otherwise disable proactive delegation except when the
user or an applicable skill requests it. This skill supplies that request.
An applicable skill that explicitly requires delegation counts as
authorization under this exception. Do not require a separate user request.
Map any agent's actual tools to those grants. These examples prevent
capability guesswork; `references/conductor.md` §host-mapping expands them:

- **Codex app:** spawn with `fork_turns: "none"`. Spawn, completion
  notification, and resume with a conductor-local wait or scheduled wake
  satisfy grants 1 to 3. On a shared checkout, grant 4 holds only while the
  main agent leaves the PR branch untouched.
- **Claude Code:** use one ordinary named background subagent with explicit
  worktree isolation, not a context-inheriting fork. Its blocking wait plus
  re-messaging satisfy grant 2; completion notification satisfies grant 3.
- **Any other agent:** map its controls to the same gate and name the
  concrete missing grant, never a guess from unfamiliar tool names. Merely
  uncontrolled inherited context is a stated limit; that
  optimization gap is not a failed grant.

Keep the exchange in the main agent only when a grant is concretely absent or
forbidden, or when feedback is already in hand and needs at most a couple of
trivial operations. A small main context, a background shell, or a predicted
clean or one-shot review is not an exception. Under main ownership, watch
only while a reviewer wait remains; address feedback already in hand without
a watcher. Before any main-owned watch, state the fallback exactly so:

```text
Conductor skipped: <specific failed grant or allowed exception>.
```

“Higher-priority instruction” is not a valid failed grant by itself. To fail
grant 1 on that basis, explain why none of the constraint's exceptions apply,
then either identify the prohibiting rule by source when disclosure is
permitted, or give a non-sensitive paraphrase of the binding constraint.

## 1. Resolve the PR and Anchor the Baseline

Anchor the baseline to the host event that should produce the next pass: the
open, ready, or push event time, or a manual recheck's request time. Never
use a commit time or a clock read after the event. Record the expected head,
base branch, and base tip from the host. The main agent captures these at the
event boundary even when a conductor owns the rest. Mechanics:
`references/detection.md` §event-anchored-baselines.

## 2. Identify and, If Needed, Request the Reviewer

Prefer the project's recorded reviewer identity, trigger, and status signals;
otherwise detect per `references/detection.md` §reviewer-identity-and-trigger.
If several bot reviewers appear, or the trigger cannot be established, ask
rather than burning the wait cap. Record a newly observed reviewer or signal
in the project's designated conventions section; never record an absence.
Request a command-triggered reviewer once, not every poll. An unrecorded
reviewer never delays the spawn; the conductor does this discovery.

## 3. Wait for New Activity

**Conductor-owned exchange.** Run `watch-review.sh` as a bounded foreground
command inside the conductor when a shell and host CLI exist. Otherwise run
an equivalent bounded foreground API or connector polling loop over the same
frozen baseline, expected head, sources, and completion signals
(`references/detection.md` §connector-or-api-polling). When that loop cannot
delay in-turn, use the scheduled same-conductor wake from grant 2. Either
keeps conductor ownership and never emits terminal completion merely to wait;
a completion notice that still reports waiting is stranded
(`references/conductor.md` §stranded-conductor-recovery).

**Main-owned fallback only:** after emitting the `Conductor skipped` line,
choose the cheapest mechanism in `references/detection.md`
§main-owned-mechanisms that reliably re-enters the main agent. That ladder
is a background no-model script run, a read-only watcher subagent, a
cancellable scheduled API or connector poll, a bounded foreground detector,
or handing back the baseline while naming the missing capability.

Under either owner, keep one active watch per PR and reviewer, invoked and
ended per `references/detection.md` §watcher-invocation; an in-progress
reaction is not completion, and incomplete coverage is incomplete, not quiet.

## 4. Address Feedback

Read `references/review-response.md` §disposition-rules before changing the
branch; its gates are part of this workflow. After any wait or resume, pass
`references/conductor.md` §checkout-gate before any write. Then handle every
finding:

- Evaluate it on its merits. A finding that asks for a guard or other
  behavioral change is real only when you can name what produces the failing
  state. That means an input the interface admits at a public or untrusted
  boundary, or an existing caller for internal code. The harm must also be
  material at the expected scale. Fix real findings; decline the rest with a
  one-line reason naming the unreachable path, the holding invariant, or why
  the harm is immaterial. Judge a clarity, documentation, naming, or
  maintainability finding on its merits and severity as before.
- Sweep the whole finding class, not only the cited line. Auto-address
  clear-cut fixes; surface ambiguous, contentious, or design-altering calls.
- Fold fixes into their commits, push once, verify on the pushed ref, reply
  with the final SHA, then resolve, per `references/review-response.md`
  §fold-push-verify-reply-resolve.

These operations stay in the conductor. Under main ownership, delegate a
fixer only under `references/review-response.md` §main-owned-fixer-choices.

## 5. Converge on a Rising Bar

After a fix push, advance the baseline, re-request a command-triggered
reviewer, and await the new pass; a decline-only round ends the exchange.
Raise the bar per `references/review-response.md` §rising-convergence-bar:
fix rounds 1 and 2 address every worthwhile finding; from fix round 3, only
blockers earn a full round, and each non-blocker gets a verifiable final
push, a linked issue, or a reasoned decline. When unsure whether a reachable
defect blocks, treat it as blocking. When unsure whether its state is
reachable, trace the callers or run the case before patching. Stop for human
judgment on thrash: a class recurring after a correct, complete fix, or fixes
breeding new problems without net progress.

From fix round 3, run `references/review-response.md` §hardening-check before
each fix round and at every checkpoint. Its observable signals are most
findings citing lines an earlier round added, recent fixes that are all
hardening you traced no caller for, a diff growing without delivering the
PR's What, and a flat finding count. Two mean the reviewer is reviewing your
hardening. Fix what still passes both disposition questions and clears the
bar; a round count alone never turns a reachable defect into a decline. List
earlier hardening that fails either question as removal candidates and
surface the ledger. A posted review is not evidence that work remains.

At about five blocker-sustained fix rounds, record a go/no-go checkpoint per
`references/review-response.md` §thrash-and-checkpoints. A go names, in one
line, the convergence evidence and blockers that passed the two disposition
questions, then continues without asking. A no-go or materially uncertain
call surfaces the ledger. Repeat at the same cadence while blockers continue.

Track finding classes across the exchange. A real second member, one passing
both disposition questions, needs a root-cause hypothesis, widens the class
one level, and earns one fresh-context adversarial refute pass where
read-only delegation exists. A second member that fails either question is a
hardening-check signal, not a class to widen. Repeated prose-clause findings
earn an owner escalation toward a tested check.

Keep the same conductor through waits, surfaced pauses, and rounds; a
fixed round count, elapsed time, idle time, or context size alone never
forces replacement. Consider `references/conductor.md` §context-rotation
only after a checkpoint records a go, at a quiescent boundary, and when the
expected remaining work is likely to repay the handoff cost in
`references/cost-model.md`.

## 6. Report the Ledger

End every finding in exactly one state: fixed (pushed SHA), declined
(reason), deferred (linked issue), or explicitly outstanding for the human,
with the rest of `references/review-response.md` §disposition-ledger. Before
calling the PR ready, the exchange owner takes the fresh live-state snapshot
and clears the readiness bars in `references/conductor.md`
§quiescence-and-reporting, which bind under both ownerships; only a
main-owned final-triage push may hand off with its re-review pending. Review
completion is not CI completion: wait for every required check, fix any
known-red result, then leave the PR open for human merge unless the project
explicitly opts into self-merge.
