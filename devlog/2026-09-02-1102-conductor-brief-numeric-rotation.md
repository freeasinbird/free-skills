# Give the conductor one brief file and a numeric rotation trigger

The 2026-09-01 transcript audit (tracker #210) measured 51 await-pr-review
conductors at 428M tokens. Polling was not the cost: each ran the watcher 5
to 14 times. The cost was fix, fold, verify, and reply work inside a subagent
that started at 48k to 62k tokens of inherited prompt, then read `SKILL.md`,
`conductor.md`, `detection.md`, and `review-response.md` before its first
action. The largest reached 719k tokens of context over 365 turns without
rotating. This note records the lever adopted and the one declined.

## Numeric Rotation, Revising the #148 Decision

The 2026-08-20 rotation-trigger note (#148) rejected any measured threshold
for two reasons: no host exposes a conductor's context size, and a threshold
would make rotation routine, a kill switch the design forbids. It chose a
qualitative proxy instead: expected further blocker rounds plus felt replay
strain, judged at a five-round checkpoint.

The changed assumption is that proxy's fire rate. Across 51 conductors it
fired zero times, including on conductors past 300 turns. A rule the
conductor never applies is absent, not cautious, and the handshake protocol
built around it was dead prose.

Chose the fix-round count as the stand-in for context size. It is already in
the ledger for the rising bar, it ends exactly where rotation is allowed, and
the audit's numbers put a fix round near 50k tokens while a poll-only round
adds almost nothing. Rotation arms at the end of every third fix round since
spawn, or at once on a host compaction or context-limit warning, and fires
only at a quiescent boundary where a full fix round is waiting. The stand-in
answers the first objection from #148; keeping every quiescence and ownership
gate answers the second, so the count arms rotation and never fires it alone.

The user chose three fix rounds over five. Five arms between 300k and 470k
on the audit's per-round sizes, catching only the tail while the 250k to
400k band held most of the spend. Three was preferred over two because two
doubles the handoff count for little saving. Three also lands on the boundary
where the rising bar already tightens, so no new checkpoint was added.

Rejected, at review, a per-round size estimate as a further gate once
rotation is armed: it is the same judgment proxy that never fired, and on the
calibration even a short full fix round repays the handoff. The little-work
case the cost model warns about is a final triage push or a decline-only
close, which the rule already refuses to rotate for.

Rejected proxies: tool-call count from memory (agents miscount over long
runs), wall-clock time (polling dominates it), transcript file size on disk
(host-specific, and the conductor does not know its own session id), and
findings dispositioned (a class sweep counts as one).

Declined by the user: running the conductor's own refute and explore
delegates on a cheaper model tier. The skill still says nothing about
delegate tier.

The per-round figures are back-of-envelope from the audit's aggregate
numbers, not a per-round measurement. `cost-model.md` states them as a
calibrated default so a later audit can retune the count without reopening
the design.

## Revisit When

- A later audit measures per-round context and the median conductor crosses
  200k well away from the third fix round.
- A host exposes context size to a subagent, which removes the need for a
  stand-in.
- Rotation fires in practice and the handshake costs materially more than one
  conductor startup, or fails often enough that the trigger should move
  later.
