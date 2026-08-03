# Conductor turn discipline: never stop to wait on background re-entry

Observed live on PR #112's own review exchange, the first conductor-owned
exchange run under the `2026-08-02-1855-conductor-upfront-routing.md`
policy: the conductor launched `watch-review.sh` as a backgrounded task
and ended its turn "waiting on it", which fired its completion
notification to the main agent with the exchange incomplete. The
backgrounded watcher could not re-enter the stopped subagent; the
exchange would have stranded had the main agent not recognized the
wait-shaped report and resumed the conductor with a foreground-poll
instruction. The exchange then completed normally.

## Decision

Two additions to the skill, extending the frozen conductor decisions
without overturning them:

- **Conductor side.** The conductor stays awake for the whole exchange:
  it ends a turn only to surface a judgment call, a checkpoint
  escalation, or the terminal ledger, and never to wait on its own
  backgrounded process. For a conductor the background poll is off the
  step-3 ladder entirely, not merely dispreferred: the re-entry that
  makes backgrounding non-blocking runs at the main agent's layer, and
  a stopped subagent has completed as far as its platform is concerned.
- **Main-agent side.** A conductor completion notice whose report is a
  wait rather than a ledger or a surfaced question is a stranded
  exchange; the main agent resumes the conductor with the
  foreground-poll instruction instead of waiting alongside it, having
  it first terminate or reuse the watcher it abandoned, so one active
  watch per PR/reviewer still holds.

## Rejected alternative

Relying on the spawn brief to specify the foreground poll (the PR #112
brief already did, and the conductor backgrounded the watch anyway,
pattern-matching on the skill's main-thread preference for backgrounded
watchers). The rule belongs in the skill text both agents read, with the
main-agent-side detection as the backstop for when instruction still
loses to habit.

Revisit when: a platform gives subagents their own reliable background
re-entry (a backgrounded process completion that resumes the stopped
subagent), which would put the background poll back on the conductor's
ladder and reduce this to the ordinary step-3 cost ranking.
