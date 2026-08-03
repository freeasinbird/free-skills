# Make conductor ownership an upfront routing decision

Revises the routing recorded in the frozen
`2026-08-02-1130-review-conductor.md` decision, at the owner's direction:
discretionary conductor ownership ("may own") becomes the mandatory default
wherever the gate holds, and the one-shot carve-out narrows to
known-trivial-feedback only. The conductor's operating mechanics stand.
That note let the conductor "own the whole exchange" where the gates hold;
the skill text rendered this as "promote the persistent fixer to a
conductor" late in step 4, and observed behavior (a Codex-session review of
PR #110's effect, confirmed to apply at least as strongly to Claude Code)
showed the structure under-routes: sessions pick a main-owned watch at
step 3 and never reach the conductor text.

## What changed since the prior decision

Four structural defects, not a changed cost model:

- **Ordering.** The step-3 watch ladder appears ~400 lines before the
  conductor and names Claude Code as the home of the preferred in-main
  mechanism, so the only early platform-specific instruction routed agents
  into main ownership before the conductor was ever presented.
- **Escalation reading.** "Promote the persistent fixer" plus the
  "roughly 4+ rounds" amortization read as a status earned mid-exchange,
  though the whole-exchange arithmetic repays the conductor from the first
  substantive round.
- **Discretion gap.** The devlog said "may own", the skill said "promote";
  neither made ownership a decision taken at invocation.
- **Unroutable criterion.** "A one-round exchange favors the main agent"
  asked for a prediction only available after the review arrives, handing
  sessions a speculative reason to stay in-main. It also sat one sentence
  after the arithmetic showing a single substantive round repays the
  conductor's fixed wakes.

## Decision

Ownership is chosen before step 1: where the full conductor gate holds
(write-capable delegation without asking, resumability, completion
re-entry, checkout isolation or exclusivity), the conductor owns the
exchange by default. Falling back requires naming the unmet gate. The only
in-main carve-outs are an unmet gate and feedback already in hand that is
known trivial; "likely one-shot" is removed as a routing criterion. The
cost-model reference now states explicitly that its N and J are hindsight
quantities, and that a clean pass under a conductor wastes at most one
main-context wake while a wrongly in-main substantive exchange pays the
5x to 25x per-call ratio every round. The conductor gate also gains an
explicit capability mapping example (Claude Code satisfies every part
natively), replacing inference with a checkable list.

## Rejected alternatives

- **Keep "likely one-shot" as an upfront exception.** Rejected: the
  quantity is unknowable at routing time and the miss costs are asymmetric
  (one wake wasted versus per-call context replay all exchange).
- **Renumber the loop with a step 0.** Rejected: every cross-reference in
  the skill and its references names steps 1–6; an unnumbered owner
  decision at the head of The loop changes no anchors.
- **Move the conductor mechanics above step 1.** Rejected: the operating
  contract (isolation, lease pinning, quiescence) is round-time material;
  only the routing decision needed to move.

## Verification

Recorded in the PR. Prompt-only change; standard markdown, prose-tic, and
skill-structure checks apply, plus a fresh-context refute pass on the diff.

Revisit when: a platform's spawn cost stops being a full-context wake (the
Claude Code spawn already happens inside the live handoff turn, making the
conductor near cost-neutral even on clean passes; if the cost model adopts
that, the remaining carve-out narrows further), or session contexts shrink
enough that the 5x to 25x ratio collapses.
