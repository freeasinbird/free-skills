# End a Route 1 Batch Once Every Implementer Thread Has Launched

The owner asked that `plan-and-handle-batch` stop holding its session open for
the life of every route 1 implementer. Before this, the orchestrator sent its
report only when no planner or implementer was still working, so a batch on
top-level threads waited on each thread until it opened its PR. This note
revises the waiting rule in the
[2026-11-18 batch note](2026-11-18-1019-plan-and-handle-batch.md); its choice
of threads before subagents stands.

## Decisions

- **Chose ending a route 1 batch when the queue empties over waiting for every
  thread's report.** An owner decision. A top-level thread is a session the
  owner can open, read, and answer in, and it posts its own handoff or blocked
  report there. Waiting on it adds nothing the thread doesn't already show,
  and it keeps the orchestrator's session open for hours.
- **Kept waiting on route 1 threads while an issue is queued.** The thread's
  end frees the slot the queued issue needs, so the wake is still how the
  window refills. Route 1 therefore keeps its three-part requirement,
  including the wake.
- **Kept waiting on route 2 subagents until they end.** A subagent's report
  reaches the owner only through the orchestrator, so ending early would lose
  it. This also covers subagents a host refusal moved off route 1.
- **Chose a new report state, running in its own thread, over leaving those
  rows unknown.** The orchestrator launched them and knows where they are;
  unknown would read as a lost run.

## Trade-off

The final table on route 1 no longer carries PR links for threads that were
still running. The owner finds those in each thread.

Revisit when owners ask for one table with every PR in it, or when a host
ends a top-level thread together with the session that launched it.
