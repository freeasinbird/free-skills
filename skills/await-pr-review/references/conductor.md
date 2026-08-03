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
- [Stranded-conductor recovery](#stranded-conductor-recovery)

## Spawn brief

Give the conductor one compact task with these facts:

- repository and PR number
- automated reviewer login in each required API form, when already recorded
- trigger and progress/clean status signals, when already recorded
- baseline source and exact timestamp (plus the post-push disambiguation
  reading when the baseline used the pre-push fallback)
- expected PR head SHA
- base branch and base-tip SHA
- available host-observation surface (script, API, or connector)
- conductor-local wait or scheduled same-conductor wake mechanism
- checkout path and whether it is isolated or exclusively assigned
- project review-response, commit, verification, and handoff conventions
- the path to `SKILL.md` and this reference

When reviewer identity or trigger facts are not already recorded, say so in
the brief and assign the conductor the step-2 discovery before it waits. Do
not make the main agent scan history merely to complete the brief.

Use this operating contract in the brief:

```text
Own steps 1 through 5 of the review exchange until a terminal disposition
ledger. Stay awake for the whole exchange. Run watch-review.sh as a bounded
foreground command when a shell and host CLI are available; otherwise use an
equivalent bounded API or connector polling loop, with scheduled wakes that
resume this same conductor when it cannot delay in-turn. Never release
exchange ownership or emit terminal completion merely to wait. Fix, fold,
push, verify, reply, resolve, advance the baseline, and re-watch under the
skill's rising bar. Surface only judgment calls, checkpoint escalations, or
the terminal ledger. Before any write, verify a clean checkout at the expected
PR head. Keep the force-with-lease pinned to the newest remote head already
contained in local history.
```

The conductor reads the referenced project conventions itself. Its reports
stay compact: finding ID, one-line disposition, final pushed SHA or issue,
checks status, and only enough context to decide a surfaced call.

## Turn discipline

The conductor retains ownership for the exchange. It pauses or ends a turn
only for:

- a scheduled wake that targets this same conductor and preserves its exchange
  state without reporting terminal completion
- a judgment call that the main agent or user must decide
- a convergence checkpoint escalation
- the terminal disposition ledger

The scheduled wake resumes the conductor automatically. Resume the same
conductor after either surfaced call. Do not spawn a replacement and do not
release checkout exclusivity during any pause.

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

Before the first write, the conductor verifies:

1. The host-reported PR head equals its checkout HEAD.
2. The worktree and index are clean, including untracked files.
3. The checked-out branch is the PR branch it is expected to push.

Handle the checks separately:

- A dirty worktree or index is unrelated user state. Stop without modifying,
  moving, stashing, or cleaning it, and surface the exact paths.
- A clean checkout on the wrong branch or head may be re-anchored to the
  fetched PR head before editing.

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

The terminal ledger includes every finding disposition, checks state, thread
state, current PR head, recorded base and its freshness result, and any watch
coverage gap. It is the conductor's completion, not a question to answer.

## Stranded-conductor recovery

Treat any conductor completion notice whose report says it is still waiting
as a stranded exchange. Resume that same conductor with these instructions:

1. Terminate or reuse the abandoned watcher so only one watch remains.
2. Resume the foreground script or the scheduled same-conductor connector/API
   polling loop with the frozen baseline and expected head.
3. Continue until a surfaced decision or terminal ledger.

Do not wait alongside the stranded conductor and do not start a second
conductor for the same PR/reviewer.
