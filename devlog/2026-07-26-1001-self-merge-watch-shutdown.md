# Shutting down a stale review watch in self-merge

`merge-cleanup` ends by stopping a review watch still running for the merged
PR; `self-merge` did not, though it is the likelier place for a watch to
outlive its PR: the project starts one when the PR opens and self-merge
merges that same PR minutes later (#85, split out of #83's review).

## Decisions

- **Chose to adapt `merge-cleanup`'s wording into `self-merge` over
  cross-referencing it.** The two skills are self-contained today and
  neither loads the other, so a pointer would make the rule reachable only
  by an agent that happened to have both loaded. The cost is a second copy
  of one paragraph to keep in step.
- **Chose the merge, not a completed cleanup, as the trigger.** The watch is
  stale the moment the PR merges, so a `STOP` guard that halts the cleanup
  sequence partway (dirty tree, lingering worktree) must not also swallow
  the shutdown step.
- **Chose prose in `SKILL.md` over anything in `self-merge.sh`.** A shell
  script cannot see or stop a platform's background tasks or scheduled
  wake-ups; the gate is a judgment step the agent performs, like the
  guardrails the script already declines to judge.
- **Rejected building a stop mechanism in `await-pr-review`** (the non-goal
  in #85, and the deferred item in the 2026-07-02 merge-cleanup note). It
  has no watch handle to stop, and inventing one would fail architecture
  invariant 2; the platform gate says so explicitly rather than implying a
  mechanism exists.
- **Chose to classify this change as merge policy, not exempt routine skill
  documentation** (decider: review finding). The high-assurance profile
  makes a note mandatory for merge-policy changes, and the 2026-07-25
  merge-cleanup note is the precedent: a change to how a skill directs merge
  and cleanup behavior is policy even when the diff is prose in a
  `SKILL.md`.

## Refute-first pass (destructive path)

The change lands in `self-merge`'s cleanup section, so it takes the finish
line's refute-first pass even though it adds no command and no destructive
step. The lenses were run in-context by the authoring agent rather than
delegated to independent fresh-context ones, since this session's policy
prohibits spawning delegates unasked; the pass is that much weaker than the
independence ladder's fresh-eyes rung.

Rejected by verification:

- **"stop the watch" read as license to stop every background task.** The
  antecedent is scoped two sentences earlier ("a review watch still running
  for it") inside a five-sentence section, and tightening it would diverge
  from `merge-cleanup`'s wording, whose parity is the reason the text was
  adapted rather than pointed at.
- **"the step still applies when a guard stopped the cleanup partway" read
  as license to proceed past a `STOP`.** The sentence governs the shutdown
  step alone, and the `STOP` paragraph above it is unchanged and explicit
  that a phase is never re-run with the state forced past a guard.

Accepted by decision:

- **"such watchers self-terminate ... when their time cap expires" holds for
  the watchers this ecosystem ships** (`await-pr-review`'s watcher takes a
  `--cap-minutes`), not for every conceivable scheduled loop. Kept verbatim
  from `merge-cleanup` rather than qualified: the branch applies only where
  the platform cannot list or stop tasks at all, and parity between the two
  skills' wording is worth more than the edge case.

Confirmed: none; nothing in the pass changed the shipped text.

Revisit when `await-pr-review` gains a real watch handle: the "note that it
self-terminates" branch would then be a fallback for platforms without one,
not the answer for every platform that cannot list background tasks.
