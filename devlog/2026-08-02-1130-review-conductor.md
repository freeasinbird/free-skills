# Let a persistent conductor own the review exchange

A 2026-08-02 local usage audit of Claude Code transcripts (255 sessions,
July 1 to Aug 2) measured where the token spend actually goes when a build
session runs `await-pr-review` through to completion in-main: 76% of all
recorded tokens were spent in requests whose context already exceeded 200k
tokens, and the top PR sessions replayed 300–500k tokens of (cached) context
per tool call across 400–1,600 calls. Cost-weighted at current API pricing,
cache reads alone were 71% of total spend; 2,843 foreground poll turns
(`gh pr checks`, watch loops, sleeps) accounted for a further 9.3% of raw
volume. The convergence loop was running at main-context prices.

## Decision

Where the platform supports write-capable delegation that is resumable
across the main agent's turns and can notify or re-enter the main agent on
completion, the persistent fixer from step 4 may own the **whole exchange**
(steps 1 through 5), not just individual fix rounds: it runs the watch,
advances the baseline, applies the convergence policy and checkpoints, and
wakes the main agent only for judgment calls, escalations, and the terminal
disposition ledger. The main agent pays two full-context wakes per exchange
(spawn and terminal report) plus one per surfaced interruption, judgment
call or checkpoint escalation (two when it routes on to the user, whose
answer costs a second turn), instead of at least one per round plus every
in-main fix call.

A corollary inside the conductor: the step-3 mechanism ladder was priced
for the main thread, where a blocking poll is the costliest path. Inside a
conductor's small context a bounded blocking `watch-review.sh` call costs
zero model tokens while it polls and blocks nothing the user is waiting on,
so it becomes the _preferred_ watch mechanism there.

A review pass on the PR added a third element to the gate: the conductor
force-pushes the branch across an exchange during which the main agent's
thread is free, so the two must not share a mutable checkout. The
conductor gets its own worktree, checkout, or clone where the platform
supports one, or explicit main-checkout exclusivity otherwise, with the
existing fallback ladder when neither can be assured. Two refinements
from the same review exchange: exclusivity holds through pauses until
the exchange terminates (the same conductor resumes after an
escalation, so a mid-pause branch edit collides on resume), and the
conductor pins each force-with-lease to its own last pushed head, never
the bare form or a newly observed but unincorporated remote head,
whatever the checkout type: any fetch into the pushing checkout (a
worktree's shared refs, or a clone's own fetch) silently re-blesses a
bare lease, and a lease advanced to a SHA local history lacks would
bless overwriting a contributor's push. A failing lease means stop,
re-anchor and incorporate, and only then advance the pin to the
incorporated head for the retry.

A third refinement: whatever checkout the conductor gets, it verifies
the checkout starts at the expected PR head before the first write. The
pinned lease checks only the remote's old value, not the history the
push would install, so a conductor editing from a stale or
default-branch start could force-push the PR's commits away. The same
pre-write check requires a clean worktree and index, so pre-existing
edits are surfaced, never swept into a fold.

## Second decision: the conductor reports at quiescence

The step-5 no-wait handoff exception priced waiting out the final push's
re-review at a main-context round, so handing off without waiting was
the cheaper path. Inside a conductor that assumption changed: the wait
is a near-free foreground poll, and a no-wait terminal report proved
stale within minutes on this PR's own exchange (a P2 landed three
minutes after "exchange complete"). So the no-wait exception is scoped
to a main-agent-owned loop; a conductor waits out the re-review its
final push triggers, dispositions what it raises on the same rising bar
(taper, thrash rule, and checkpoints bound the tail), and delivers the
terminal ledger at quiescence: a clean pass, or every finding
dispositioned with no push pending.

Three boundaries of that rule: the wait stays bounded by the step-3
cap, with a capped no-review timeout (recorded with its baseline)
equally terminal; past the triage push, non-blocking findings take
terminal dispositions only (defer or decline, never another push), so
a reviewer yielding one nit per push cannot hold exclusivity alive
indefinitely; and the AGENTS.md handoff exception is unchanged, the
skill text being a stricter conductor-only behavior, not a
contradiction of that convention.

## What changed since the prior decisions

The per-round break-even (`2026-07-02-0318`) assumed delegation adds
main-agent wakes (spawn plus completion read) on top of an unavoidable
per-round watcher wake, and its persistent-fixer refinement kept loop
orchestration in the main agent, noting "the judgment calls still wake the
main agent every round regardless." The audit showed the main context in
real PR sessions is 5 to 10 times the size those trade-offs were argued
around, and that the orchestration wakes themselves, not just the fix
rounds, dominate. Moving loop ownership removes the per-round wakes the
prior model treated as fixed. This extends, not overturns, the
persistent-fixer decision: gates, fallbacks, and the per-round rule for
one-shot rounds all stand.

## Rejected alternatives

- **Fresh session per review loop.** Caps the replay cost but adds a human
  touchpoint at exactly the boundary the workflow exists to automate; the
  owner rejected it for that reason.
- **Config-only fix (auto-compact plus a 200k window).** Adopted separately
  at the machine level, but it caps the multiplier, not the multiplicand:
  the loop still replays the whole build context per call, compacted or
  not, and it does nothing for platforms without that knob.
- **Status quo (per-round delegated fixer).** Keeps at least one
  main-context wake per round for watch and orchestration; over the
  measured 5-to-10-round blocker-sustained exchanges that is the dominant
  remaining cost.

## Verification

Recorded in the PR. Prompt-only change plus cost-model derivation; the
standard markdown, prose-tic, and skill-structure checks apply. The
conductor path is gated per invariant 2 (platform-agnostic, explicit
fallback to the existing in-main and per-round paths), so no platform loses
a working path.

Revisit when: a platform gains cheap sub-agent context forking (making
fresh-per-round fixers as cheap as persistent ones), or measured main
contexts drop well below ~150k (the config-level compaction change may do
this), which narrows the conductor's advantage to long exchanges only.
