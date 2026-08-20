# Start review conductors fresh and rotate only by handshake

Issue #140 refines the persistent-conductor decisions recorded in
`2026-08-02-1130-review-conductor.md` and
`2026-08-02-1914-conductor-turn-discipline.md`. Those decisions preserve one
small owner across the exchange, but they did not control how much parent
conversation the initial conductor inherited or provide a safe reset for an
unusually long exchange.

## Decision

Request the least inherited parent context the host supports and seed the
initial conductor with a compact, self-contained brief. That brief preserves
the durable task contract, including task-specific user constraints, because
fresh context cannot recover requirements that live only in parent history.
Codex collaboration uses `fork_turns: "none"`; Claude Code uses an ordinary
named subagent, whose context starts fresh, rather than an experimental
context-inheriting fork. Other hosts request fresh or empty context when
possible. An inability to control inheritance is an optimization gap, not a
fifth conductor grant, so a host that still satisfies the four ownership
grants continues with a truthful notice and the compact brief.

Keep the same conductor through ordinary waits, pauses, and review rounds.
After an existing blocker-sustained convergence checkpoint records a justified
go, rotation is optional only when expected remaining calls are likely to
repay the old-owner handoff, main-agent replacement spawn, replacement forge
refresh and reconstruction, and the remaining calls at the reset context
size. Too little expected work, or material uncertainty in that comparison,
keeps the old conductor.

Rotation uses a quiescent, exactly-once ownership handshake coordinated by the
main agent. The old conductor finishes and dispositions the round, completes
any push and baseline advance, and consumes or stops its watcher. It freezes a
private replacement brief, but persists only a pointer record containing
forge-derivable head, base, baseline/attribution, finding dispositions, thread
and check state, and the exact next action in the authoritative tracker issue
or a PR comment. The task contract, user constraints, checkout details, and
other chat-only operating inputs never enter that record. The live main agent
supplies the replacement with the current task contract, meaning the initial
brief plus every post-spawn decision and constraint amendment from surfaced
judgment calls. The replacement reads the pointer record, refreshes forge state
read-only, reconciles both sources, and inspects the exact checkout path that
will be transferred. The main agent persists only the refreshed forge state
and next action before ownership can move. After provisional acceptance, the
already-live replacement accepts future ownership contingent on the old
conductor's release. The release acknowledgement transfers exchange and
checkout ownership exactly once from old to new before the old conductor
terminates. No path transfer or replacement activation remains afterward.
Delayed old-owner completion, a failed final checkout gate, or replacement
interruption leaves the same replacement as owner for recovery, without dual
watchers, dual checkout owners, lost handoff state, or a stranded exchange.

This refines persistent ownership without changing reviewer detection,
terminal readiness, the rising convergence bar, or its escalation cadence.

## Rejected alternatives

- **Fixed conductor lifetime.** A round, elapsed-time, idle-time, or context
  threshold ignores whether meaningful work remains. It can force an expensive
  reconstruction immediately before the exchange would have ended.
- **Replace immediately at a checkpoint.** A go call justifies continued
  review, not overlapping watchers or branch owners. Transfer still requires a
  quiescent boundary and live-state reconciliation.
- **Terminate before provisional acceptance.** This removes continuity before
  proving the handoff current or establishing the already-live replacement as
  the recovery owner.
- **Stop the replacement on a failed final gate.** The old owner has already
  released, so stopping creates a zero-owner gap. The replacement retains
  ownership and reconciles the failure instead.
- **Keep the handoff only in agent messages.** A session boundary or
  interruption can erase the forge-state checkpoint. Persist the pointer-only
  record and refreshed forge result before ownership moves, while keeping
  chat-only operating inputs on the live agent channel.
- **Check out the branch in a replacement worktree before release.** Git
  rejects a branch already checked out by the old isolated worktree unless
  forced. Transfer the existing checkout path and run the final gate after the
  old owner releases it instead of overriding Git's isolation guard.
- **Treat inherited-context control as a conductor gate.** That would disable a
  safe working owner on hosts missing only a cost optimization.

## Credential-boundary refutation

The review correctly identified that the prior persistence field list crossed
a credential-leak boundary: it included the task contract and task-specific
user constraints, which can carry secrets, customer data, or internal details.
A field-class sweep found the same exposure in the protocol, success fixture,
structural assertions, and decision record. The accepted fix excludes all
chat-only fields from forge persistence and has the live main agent provide
their current values privately, including post-spawn amendments.

Adversarial fixtures reject a forge record containing the task contract, user
constraints, checkout paths, host details, or operating prompt, and separately
reject a replacement prompt that omits the private task contract. This rejects
the hypothesis that redaction is needed after copying: verification showed the
safer boundary is to never copy those fields to the forge record. The owner
declined a mandatory new tracker issue for every rotation as scope beyond
issue #140; within one live main-agent session, the pointer-only PR record is the
durable forge checkpoint.

Revisit when: hosts can migrate live agent state without replay or parallel
ownership, expose measured context size and remaining-call estimates that make
the advisory comparison executable, or change whether ordinary Claude Code
subagents and Codex `fork_turns: "none"` start without parent history.
