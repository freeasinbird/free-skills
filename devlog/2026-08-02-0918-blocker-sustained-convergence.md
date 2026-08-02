# Let blockers sustain the review loop: thrash stop, round-five checkpoint

The 2026-07-27-0927 rebalance stopped the validity-sustained review pits,
but its own revisit condition fired: the backstop cap (~5 fix rounds / 2
hours, taking precedence over the blocker rule) was ending healthy
blocker-sustained exchanges, and the owner reported constantly restarting
them by hand with a dictated rule (continue while P1s keep arriving; on an
all-P2 round, judge for yourself whether anything blocks, and otherwise
defer with issues or decline). This is a rebalance of that note, not a
silent overturn: the changed condition is that healthy exchanges hit the
cap often, which that note named as the signal its numbers were mis-set.

## Decision

Owner-decided in session, applied to `skills/await-pr-review/SKILL.md`
step 5 and the canonical "Converge on a bar that rises with the rounds"
bullet in `skills/agent-setup/references/canonical-sections.md` plus this
repo's AGENTS.md mirror:

- **Blockers always earn another round; thrash is the stop.** The burn
  asymmetry decides it: a premature handoff saves nothing, because the
  human restarts the exchange, re-pays the remaining rounds, and pays
  their own attention on top, while an unnecessary extra round costs
  ~10 minutes and 1.5–3x main context. The pits the cap was guarding
  against were validity-sustained nit loops, which the severity ratchet
  now terminates; the cap was no longer load-bearing for them. Thrash
  (the same finding recurring after a correct, complete fix, or fixes
  spawning new problems without net progress) pauses the loop and brings
  in the human.
- **The round number survives as a checkpoint, not a cap.** Pure
  thrash-only has a hole: a deeply broken change can produce genuinely
  new blockers every round, so thrash never fires while rounds burn. At
  about five blocker-sustained fix rounds the agent records a one-line
  go/no-go: continue only with a stated reason the exchange is converging
  (rounds shrinking, fixes holding), otherwise escalate with the ledger.
  A go call buys the next few rounds, never the rest of the exchange:
  the checkpoint repeats on the same cadence while blockers sustain the
  loop (a Codex round-one P2 caught the one-time version leaving the
  one-fresh-blocker-per-round case unbounded past the first check).
  The forced conscious assessment, not the notification, is the value.
  The 2-hour wall-clock stop is dropped: it proxied waiting, not spend,
  and the per-wait cap already bounds waiting.
- **The severity call is the agent's own, with anti-gaming defaults.**
  The owner's stated worry is agents reclassifying P2s as deferrable or
  deniable to escape the loop. Guards: the reviewer's P1/P2 tag is input,
  not verdict, in both directions; when unsure whether a finding blocks,
  treat it as blocking (uncertainty buys a round, not an exit); deferral
  requires a real tracker issue quoting the finding, so it is never the
  cheap path; and a no-blocker call that ends the exchange is stated in
  the ledger for a one-glance audit.
- **A sustained round dispositions every finding it raised.** "Handle
  them all" means disposition, not fix (owner clarification): blockers
  get fixed, and each non-blocker in the round gets fix, defer, or
  decline on its own triage merits in that same round; the rule forbids
  silently carrying a finding forward, never forces a fix on one that
  rightly earns a decline.

Numbers stay skill-only; the canonical bullet stays qualitative so
downstream projects can tune, as before.

## Rejected alternatives

- **Pure thrash-only, no checkpoint**: simplest, but leaves the
  new-blockers-every-round deep-breakage case undetected until many
  rounds have burned; round count is a cheap detector for exactly the
  case where the change needs a redesign, not more patches.
- **Higher hard cap (~10 rounds) with the same precedence**: bounds
  worst-case burn firmly but recreates the manual-restart problem
  whenever a healthy exchange outlives the new number; the axis was
  wrong, not the value.
- **Adversarial self-check on the no-blocker exit** (a refute pass
  arguing that at least one finding blocks): a real counterweight, but
  its per-exchange cost is not justified until P2 gaming is actually
  observed; the defaults-plus-audit-trail guards ship first.

Revisit when: P2 gaming is observed (a deferred or declined finding later
proves blocking, the case for adding the adversarial exit check); the
checkpoint rubber-stamps broken exchanges (go/no-go recorded but never
escalating); or deferral issues accumulate unactioned in the tracker.
