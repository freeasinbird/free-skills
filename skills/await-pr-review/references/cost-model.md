# Cost model: the derivations

The decision rules and their headline numbers live in `SKILL.md` (steps 3–4);
an agent that never opens this file makes the same choices. This file holds
the arithmetic behind those numbers: read it when a call is genuinely
borderline, or when re-deriving the break-evens after a pricing change.

## Single wake vs cache-keepalive wakes (step 3)

The default resume is a single wake on activity: the watcher fires once and
the main agent pays one full-context read, often cache-cold when the review
takes longer to land than a short prompt-cache TTL (though a fast reviewer
plus a tight no-model poll can instead land that wake while the cache is
still warm; see the observed-latency section below). Where the platform can
instead re-enter the agent on a timer (a scheduled wake-up or self-paced
loop), each wake replays the main context itself, which is normally the
costliest pattern.

Timer re-entry becomes the cheaper pattern only in the narrow case SKILL.md
states (large main context, steep cached-read discount behind a short cache
TTL, short expected wait). Then waking at the cache-keepalive cadence costs
the cached-read fraction of a cold read per wake, and keepalive wins while
wakes times the cached-read price stay under one cold read (at typical
pricing roughly ten cache-cadence wakes, so waits up to ~45 minutes). With a
small context, a long wait, or no cached-read discount, the single cold wake
wins.

This break-even assumes current typical pricing multipliers (cached read on
the order of 0.1x a cold read); re-derive the ten-wake figure if those
multipliers shift.

## Detection inside a timer wake (step 3)

The section above prices the wake; this one prices what runs inside it. A
wake that rebuilds the detection itself pays, per wake, the tool-call round
trips for reviews, threads, and reactions plus every payload they return, and
those payloads then sit in the main context for the rest of the session, so
the cost compounds across wakes rather than resetting at each one.
`watch-review.sh` collapses those three sources to one command and one exit
code, leaving the wake's marginal cost as the context replay it was going to
pay anyway. Over a 25-minute wait on a 5-minute gap that is five hand-rolled
query rounds traded for five exit codes.

## Observed reviewer latency and the warm-wake swing (step 3)

Observed Codex reviews landed 2m54s–4m46s after each push, right around a
5-minute cache TTL, so a ~75s poll tends to detect the review and fire its
single wake while the main context is still cache-warm, whereas a coarse
~270s grid would not detect it until a later tick and would wake the agent
cold: at typical pricing a roughly 12x swing on that one wake read (the
cached-read fraction versus a full cold read). Treat the latency band as
observed for one reviewer, not a guarantee, but it is a further reason to
prefer the tight cadence on the no-model path.

## Delegated fix round: what delegation actually saves (step 4)

Delegating a round to a subagent does not save main-agent wakes; it adds
them (the spawn turn, then a completion wake to read the report), and a
fresh fixer must first rebuild working context the main agent already has
(re-reading the diff, the touched files, the conventions). What delegation
saves is everything in between: each tool call replays the calling agent's
context, so a long round replays the main context once per call while a
fixer replays only its own small one. That is why SKILL.md's break-even
requires both a long round (many findings, a wide class sweep, dozens of
tool calls) and a main context that dwarfs the fixer's brief.

## Persistent fixer amortization (step 4)

The per-round break-even makes short rounds look like they never justify
delegation. But a convergence loop is many rounds, and what changes across
them is the rebuild cost. A fresh fixer each round re-pays the context
rebuild every time (re-reading the diff, the touched files, the
conventions), so over N rounds it pays `N × R_rebuild`; a fixer kept alive
across the loop pays that rebuild once (`1 × R_rebuild`), then reuses its
warm context, and it keeps each round's debris (its findings and fixes) out
of the main context, since only the compact reports cross back. That is why
a persistent fixer likely wins on any longer exchange (roughly 4+ rounds)
even when each round on its own falls below the per-round break-even, while
the per-round rule still governs a one-shot round.

## Conductor: whole-exchange accounting (step 4)

The sections above price a single round. Over an exchange, orchestration is
itself a per-round cost: with the main agent owning the loop, each round
wakes it at least once (the watcher firing) before any fix work starts, and
each wake replays the full main context. Writing `C_main` for the main
context and `C_cond` for the conductor's, an N-round exchange with J
surfaced interruptions, counting everything the conductor surfaces short
of the terminal report (judgment calls and checkpoint escalations alike),
`J_user` of them routed on to the user, costs roughly `N × C_main` in
orchestration wakes under main ownership, against
`(2 + J + J_user) × C_main` under a conductor: the spawn, the terminal
report, one wake per surfaced interruption, and, for a user-routed one, a
second main-agent turn when the user's answer arrives before the
conductor can resume. Beyond those wakes, every watch and fix tool call
bills at `C_cond` instead of `C_main`.

Measured sessions (a 2026-08 local usage audit; the 2026-08-02 devlog note
records it) put `C_main` at 300–500k tokens in real PR sessions against a
20–60k conductor brief, a 5x to 25x per-call ratio paid at cached-read
prices on every call. On orchestration wakes alone the conductor wins
when `2 + J + J_user < N`; the per-call savings close the gap well before
that,
since a single fix round of a few dozen tool calls replays roughly
`20 × C_main` when run in-main against `20 × C_cond` under a conductor,
and at the measured 5x to 25x ratio that one round's difference already
exceeds the conductor's two fixed wakes (`2 × C_main`). The comparison
stays governed by the formula, not a blanket rule: rounds carrying real
fix work favor the conductor, while an exchange whose interruptions
rival its rounds (`J + J_user` large against N, e.g. two one-call
rounds each pausing for the user) or a one-round exchange favors the
already-awake main agent, which is the per-round rule above.

Inside the conductor the step-3 mechanism ladder inverts at the bottom: the
bounded foreground poll, costliest on the main thread, is free while
waiting there (no model tokens while the script polls, nothing user-facing
blocked), so it becomes the preferred watch mechanism under a conductor.
