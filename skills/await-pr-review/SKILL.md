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
  main-owned watcher only when a named conductor gate is unavailable. With an
  owner's `none` reviewer record, wait on CI checks only. Not for
  human-only review or a branch without an open PR.
---

# Await PR Review

Watch an open pull request for its automated reviewer, address the feedback,
and converge without the user babysitting the polling. The project's
review-response conventions still govern commits, replies, resolution, and
handoff. A `none` reviewer
record skips routing and review and waits on CI checks only
(`references/detection.md` §declared-no-reviewer).

## Authorization

Invoking this skill authorizes its task-scoped review-loop actions without
per-action or per-round confirmation. They are waiting for the reviewer;
fixing accepted findings and folding them into their commits; pushing with
the pinned lease and safeguards; verifying, replying, and resolving threads;
and advancing the baseline to trigger or await the next pass. Folding
rewrites history, which is covered only on the expected PR branch under the
checkout and lease gates.

The authorization stops at a destructive action outside that sequence, a
failed pinned lease or other unmet safety precondition, material scope
expansion, or a genuine judgment call. There, apply the documented safe
recovery where one exists, and surface what needs judgment or new authority.
Obey a platform-required approval prompt, but never invent a conversational
permission gate these safeguards already cover.

## Route Ownership Before Waiting

Decide who owns the exchange before you read feedback, wait on CI, or start
any watcher. **Default to one conductor subagent.** It owns steps 1 to 5 and
wakes the main agent only for a judgment call, a convergence escalation, an
armed rotation handoff, or its terminal ledger. Spawn it with the least
inherited context the host allows and the brief in `references/conductor.md`
§spawn-brief: the current task contract at spawn, with task-specific user
constraints. Its one startup read is `references/conductor-brief.md`.

**Apply one platform-neutral gate through four probes.** A conductor owns the
exchange when all four grants hold on observable evidence, per
`references/conductor.md` §probes.

1. **Write-capable delegation.** Evidence: a spawn tool is listed in this
   session (Claude Code `Agent` as an ordinary named background subagent; Codex
   `spawn_agent` with `fork_turns: "none"`) and no rule forbids it. Default:
   listed means granted. A rule disabling proactive delegation except on
   request does not fail it; this skill supplies that request. "Higher-priority instruction" alone never
   fails it. To fail it on a rule, explain why the rule's exceptions exclude
   skill-mandated delegation. Then name the rule by source, or give a
   non-sensitive paraphrase when disclosure is restricted.
2. **Wait-and-resume continuity.** Evidence: the subagent has a bounded
   foreground shell wait or a scheduled wake, and the host can re-enter it
   after a pause. Default: a shell in the subagent grants it.
3. **Completion notification.** Evidence: the host notifies the main agent when
   a background subagent ends, or offers a blocking wait on it. Default: a
   listed spawn tool grants it. After the spawn, end your turn only where that
   signal re-enters you; a headless run blocks on the conductor, since
   yielding ends the session.
4. **Checkout isolation or exclusivity.** Evidence: `git worktree list` shows
   the PR branch in a worktree only the conductor will touch, or the spawn call
   can create one. Default: grant exclusivity: the main agent makes no edit,
   commit, PR-branch fetch, rebase, or push until the terminal ledger.

A probe you cannot run is not a failed grant: take the default and note the
gap in the brief. Never infer a failed grant from an unfamiliar tool name.
Uncontrolled inherited context is an optimization gap, not a failed grant.

Keep the exchange in the main agent only when a probe shows a grant concretely
absent or forbidden, or when feedback in hand needs at most a couple of
trivial operations. A typo fix, a reply, or a thread resolution qualifies. A
small main context, a background shell, or a predicted clean or one-shot
review is not an exception. Under main ownership, watch only while a reviewer wait remains.
Before any main-owned watch, state the fallback exactly so:

```text
Conductor skipped: <specific failed grant or allowed exception>.
```

## 1. Resolve the PR and Anchor the Baseline

Anchor the baseline to the host event that should produce the next pass (the
open, ready, or push event, or a manual recheck's request time), never a
commit time or a later clock read. Record the expected head, base branch, and
base tip from the host; take `--repo` from the project's forge record, not a
remote. Mechanics: `references/detection.md` §event-anchored-baselines.

## 2. Identify and, If Needed, Request the Reviewer

Prefer the project's recorded reviewer identity, trigger, and status signals;
otherwise detect per `references/detection.md` §reviewer-identity-and-trigger.
If several bot reviewers appear, or the trigger is unclear, ask rather than
burning the wait cap. Record a newly observed reviewer or signal in the
project's designated conventions section; only the owner records none.
Request a command-triggered reviewer once, via `--request-comment`, never per
poll. An unrecorded reviewer never delays the spawn.

## 3. Wait for New Activity

**Conductor-owned exchange.** Run `watch-review.sh` as a bounded foreground
command inside the conductor, with caps and waits from
[Cadence and Cap](references/detection.md#cadence-and-cap). Without a shell
and host CLI, run an equivalent bounded foreground API or connector polling
loop (`references/detection.md` §connector-or-api-polling), or use the
scheduled same-conductor wake from grant 2. Never emit terminal completion
merely to wait (`references/conductor.md` §stranded-conductor-recovery).

**Main-owned fallback only:** after the `Conductor skipped` line, pick the
cheapest mechanism in `references/detection.md` §main-owned-mechanisms that
re-enters the main agent, such as a background script run or a scheduled API
or connector poll.

Under either owner, keep one active watch per PR and reviewer per
`references/detection.md` §watcher-invocation. An in-progress reaction is not
completion, incomplete coverage is not quiet, and `unresolved_threads` above
zero means the round is not clean.

## 4. Address Feedback

Read `references/review-response.md` §disposition-rules first; its gates
bind. After any wait or resume, pass `references/conductor.md` §checkout-gate
before any write. Then handle every finding:

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

These stay in the conductor. Under main ownership, delegate a fixer only
under `references/review-response.md` §main-owned-fixer-choices.

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
each fix round and at every checkpoint. Two of its signals, such as recent
fixes that are all hardening you traced no caller for, mean the reviewer is
reviewing your hardening. A round count alone never turns a reachable defect
into a decline. List earlier hardening that fails either question as removal
candidates and surface the ledger. A posted review is not evidence that work
remains.

At about five blocker-sustained fix rounds, and at that cadence while
blockers continue, record a go/no-go checkpoint per
`references/review-response.md` §thrash-and-checkpoints. A go names the
convergence evidence and blockers that passed the two disposition questions,
then continues without asking; surface a no-go or materially uncertain call.

Track finding classes per `references/review-response.md`'s Finding-Class
Recurrence. A second member that fails either question is a hardening-check
signal, not a class to widen. Repeated prose-clause findings earn an owner
escalation toward a tested check.

Keep the same conductor through waits, pauses, and rounds; elapsed
time, idle time, or poll count alone never forces replacement. Rotation arms
after every third fix round and fires at the next quiescent boundary where a
full fix round waits, per `references/conductor.md` §context-rotation.

## 6. Report the Ledger

End every finding in exactly one state: fixed (pushed SHA), declined (reason),
deferred (linked issue), or explicitly outstanding for the human, per
`references/review-response.md` §disposition-ledger. Before calling the PR
ready, the exchange owner clears the readiness bars on a fresh live-state
snapshot, per `references/conductor.md` §quiescence-and-reporting, under
either ownership. Review completion is not CI completion: wait for every
required check, fix any known-red result, then leave the PR open for human
merge unless the project explicitly opts into self-merge.
