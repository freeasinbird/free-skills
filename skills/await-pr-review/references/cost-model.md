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
