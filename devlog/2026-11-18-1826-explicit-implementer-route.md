# Choose plan-and-handle-batch's Routes Before Anything Launches

A live batch on a T3 Code host started both implementers as background
subagents while the session offered the skill's first route, a top-level
thread with its own worktree. The thread tools were deferred: listed by name
but not loaded. The orchestrator used the subagent tool it already had loaded,
then cited a host rule that the skill's Authorization section already
overrides. Issue #386 carries the contract. This note keeps the
[2026-11-18 batch note](2026-11-18-1019-plan-and-handle-batch.md)'s choice of
threads before subagents.

## Decisions

- **Chose resolving the route before the opening message over resolving it at
  the first dispatch.** The opening message goes out before the planners
  start, and it is the owner's one chance to stop a wrong choice before
  anything runs. A route picked at the first dispatch couldn't appear there,
  and picking it by habit left no trace to catch.
- **Chose counting a named but unloaded tool as listed over deciding from
  loaded tools only.** Hosts that load tool definitions on demand make the
  loaded set an accident of the session's history. The orchestrator now loads
  any tool that could meet a requirement or a route before deciding, and
  never picks a tool because it's already loaded. A tool that fails to load
  isn't offered, and the failure is the recorded reason.
- **Chose a host-named delegation tool over any other tool that meets
  requirement 1.** A host that names its own mechanism for background agents,
  such as T3 Code's `delegate_task`, may forbid the others for that purpose;
  T3 Code forbids a background `Agent`. So planners and route 2 implementers
  start through the named tool, and the generic requirement applies only
  where the host names none.
- **Chose recording the route, its reason, and the planner tool in the state
  file over choosing again on resume.** A resumed session that chose again
  could split one batch across two routes. A host refusal that forces route 2
  moves the rest of the batch with it, updates the record with the refusal as
  the reason, and tells the owner.
- **Kept the order of routes**, an owner decision in #386. Whether route 1
  should stay first is a separate question.

## Open Gaps

This change sends more T3 Code batches down route 1. The two gaps in the
lessons comment on #383 still apply there: a thread's run shows `completed`
each time the thread yields, and `t3_thread_wait` can time out without waking
the orchestrator. No issue tracks either one yet.

Revisit when a T3 Code batch on route 1 loses track of a thread through one of
those gaps, or when a host offers a thread route the three-part test doesn't
describe.
