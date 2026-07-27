# Rebalance review convergence: severity ratchet, ledger, backstop cap

The owner reported hours-long "one more thing" review pits: Codex rounds
kept surfacing findings that were individually valid, so step 5's stop
signal (value tapering) never fired, each fix push triggered a re-review,
and merges stalled while agent usage burned. The prior tilt toward
continuing was itself deliberate (2026-06-26-2355, after PR #27
under-converged), so this is a rebalance of that decision, not a silent
overturn: the changed condition is the observed cost profile, a reviewer
whose findings stay individually valid sustains an unbounded exchange under
a validity-only bar.

## Decision

Owner-decided in session, applied to both `skills/await-pr-review/SKILL.md`
step 5 and the canonical "Converge deliberately" bullet (now "Converge on a
bar that rises with the rounds") in
`skills/agent-setup/references/canonical-sections.md` plus this repo's
AGENTS.md mirror:

- **Severity ratchet.** Early rounds (first two fix rounds) address
  everything worthwhile, as before. From the third fix round on, only
  blocking findings (correctness, security, data-loss, broken invariants,
  red CI) sustain the loop; a pass with only valid-but-non-blocking
  findings is the taper signal, not fuel. Severity, not validity, sustains
  the loop.
- **Triage with a verifiability gate.** No-blocker passes get triaged, not
  looped: locally verifiable cheap fixes ride one final push (the exchange
  ends without waiting for the pass that push triggers); substantive valid
  findings defer to a tracked follow-up issue; marginal ones get the
  existing reasoned decline. The gate exists because fixes breed
  fixes-of-fixes (owner's explicit concern): a fix whose correctness would
  itself need a reviewer pass to confirm never rides the final push. A
  blocking finding of that kind earns the verified round or stays
  explicitly outstanding for the human, never a deferred issue; only a
  non-blocking one may defer.
- **Disposition ledger at handoff.** Every finding ends fixed (SHA),
  declined (inline reason), deferred (issue), or explicitly outstanding;
  nothing silently dropped. This is the quality-rot guard that replaces
  "bias toward continuing": the human arbitrates outstanding non-blockers
  at merge.
- **Backstop cap.** About five fix rounds or two hours of wall clock forces
  handoff with the ledger regardless; blockers still arriving at the cap
  mean the change or loop is broken, generalizing the existing thrash rule.
  Numbers live in the skill only; the canonical bullet stays qualitative so
  downstream projects can tune.
- **All-decline rounds end the exchange.** This overturns the 2026-07-02-2340
  decision to always re-trigger after a no-push round. That decision's risk
  absorption ("the decline -> re-raise -> decline loop is absorbed by step
  5's existing value-taper stop") assumed the taper fires; against a
  reviewer whose findings stay individually valid it does not, and the
  forced pass costs a round to re-confirm unchanged code. Declines remain
  recorded inline, so nothing is lost at handoff.
- **Rule-repeat tripwire.** Alongside class escalation, step 5 now tracks
  recurrence by rule: rounds that keep saying "the instructions omit a
  clause" (prose re-deriving a program, per the PR #98 worktree-inventory
  experience) get a medium escalation surfaced to the owner instead of
  another clause patch.

## Rejected alternatives

- **Hard budget only** (round/time cap, no severity gradient): caps the
  pit but wastes early rounds' full value and still fixes nits at round 4
  while capping a blocker at round 6; severity is the right axis, the cap
  is only the pathological backstop.
- **Ratchet only, no concrete cap**: keeps the prior vague "ceiling far
  above any healthy exchange," which never bound anything in practice.
- **Batch-everything final push without the verifiability gate**: rejected
  on the owner's stated concern that fixes introduce their own necessary
  fixes; an unverifiable fix landing unreviewed trades review-pit cost for
  silent-defect risk.

Revisit when: under-convergence recurs (a quality regression traced to a
deferred or declined non-blocking finding), the reviewer's finding profile
changes (e.g. a reviewer that front-loads blockers instead of serializing
nits), or the backstop cap is hit by healthy exchanges often enough to
suggest the numbers are mis-set.
