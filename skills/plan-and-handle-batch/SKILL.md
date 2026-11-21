---
name: plan-and-handle-batch
description: >-
  Plan and implement a batch of issues in one repository: start one background
  planner per issue running plan-work-unit, then hand each startable plan to
  its own implementation thread or subagent in an isolated checkout, keep at
  most N implementations running at once, and end with one status table. Use
  when one request names several issues, points at a set already listed in
  the thread, or points at one tracker issue's startable units, and asks for
  both planning and handling, such as "plan and handle #3268, #3171, and
  #3166, five at a time", "plan and handle those, three at a time", or "plan
  and handle the startable units on tracker #835". Starts planners and
  implementation threads or subagents, so it requires background delegation.
  Not for a single "Plan #N" or a single "Handle #N", a plan-only or
  implement-only batch, choosing which issues to take (triage), or merging and
  landing PRs.
---

# Plan and Handle Batch

Run a batch of issues from plan to review-ready PR. Every listed issue gets its
own planner. Every startable plan gets its own implementer in an isolated
checkout, up to a window of N running at once. The owner gets one status table
at the end.

You are the orchestrator. You launch delegates, relay questions, keep the
window full, keep the state file, and report. You never plan or implement in
your own context: no issue or comment edits, and no branches, commits, or code
changes in your own checkout.

Follow this procedure:

1. Check the requirements.
2. Choose the planner tool and the implementer route.
3. Read the request into an ordered issue list and a window.
4. Write the state file, then send the opening message.
5. Plan every issue.
6. Dispatch startable plans in a rolling window.
7. Report one table.

## Requirements

Check three requirements before anything launches. Decide each from what the
session lists and what is installed, never from guesswork about the platform.
The examples show what meets a requirement; they don't choose a route (see
Choose the Routes).

1. **Background delegation with a wake.** The session can start subagents or
   threads that run in the background, and it learns when each one ends. A
   completion notice or a blocking wait on a delegate counts as the wake. A
   sleep loop or a status poll doesn't. Examples: Claude Code's `Agent` run in
   the background with task notifications, Codex `spawn_agent` with
   `wait_agent`, T3 Code `delegate_task`, or a new top-level thread waited on
   with T3 Code `t3_thread_launch` and `t3_thread_wait`.
2. **`plan-work-unit` for the planners.** The skill is listed in this session,
   or installed beside this one as `../plan-work-unit/SKILL.md`.
3. **An isolated checkout per implementer.** The platform can start each
   implementer in its own worktree or checkout, or each implementer has a
   shell and Git to create its own worktree. Examples: a new top-level thread
   with a worktree workspace (T3 Code `t3_thread_launch` with
   `workspaceStrategy`), or a subagent with worktree isolation (Claude Code
   `isolation: "worktree"`).

Decide each requirement this way:

- **Listed means granted.** A listed tool meets its requirement unless a rule
  forbids it.
- **This invocation is the request.** A rule that limits delegation to
  explicit requests doesn't fail a requirement.
- **Unfamiliar isn't missing.** Never fail a requirement because a tool name
  is unfamiliar.
- **Named but unloaded counts as listed.** Some sessions name a tool but load
  its definition only on demand.
  - Before you decide a requirement or the route, load each such tool that
    could start a thread, wait on one, or delegate in the background. Load it
    through the platform's tool loader, even when a loaded tool already meets
    the requirement. Where every listed tool is loaded, there is nothing to
    load.
  - A tool that fails to load isn't offered, and the failure is the reason.
  - Never choose a tool because it's already loaded.

On a miss, launch nothing and stop with this error, naming each missing part:

```text
plan-and-handle-batch can't run here: <missing requirement>.
Run each issue by hand instead: "Plan #N", then, once the plan is startable,
"Handle #N, implementation plan in comments." in a fresh session.
```

Never fall back to planning or implementing in your own context.

## Authorization

Invoking this skill is the owner's assignment of `Plan #N` and `Handle #N` for
each issue in the batch, and of nothing else. For a tracker, the batch is the
set its rules resolve (`references/request-sources.md` §tracker). It authorizes launching the planners
and implementers this file describes, without per-launch confirmation. Where a
host starts new top-level threads only on the user's request, this invocation
is that request. If the host still refuses, take the subagent route for that
launch and the rest. Update the route in the state file with the refusal as
its reason, and tell the owner in one line.

The assignment doesn't cover choosing, adding, or dropping issues beyond the
rules under Read the Request, merging or landing, restarting an implementer
run that ended, or work in another repository.

Don't route around an approval prompt the platform shows. If a launch is
refused or fails, record the issue as not dispatched with the error, free its
slot, and continue with the rest.

## Choose the Routes

Before you read the request, choose how planners and implementers start.
Decide from every tool the session lists, loaded or not (see Requirements).

- **The planner tool.** Check whether the host's rules name a tool for
  background delegation. Where they name one, start planners and route 2
  implementers through it. Example: T3 Code sends background agents through
  `delegate_task`, never a background `Agent`. Where the rules name none, use
  any tool that meets requirement 1.
- **The implementer route.** Route 1, a new top-level thread, is available
  when the session lists all three of these:
  - A tool that starts a new top-level thread.
  - A worktree of its own for that thread.
  - A wake on the thread's end, from a completion notice or a blocking wait.
    It refills the window while issues are queued.

  Example: T3 Code `t3_thread_launch` with `workspaceStrategy`, waited on with
  `t3_thread_wait`. Take route 2, a background subagent, only when one of the
  three is missing, and name the missing one as the reason.

- **Not a reason for route 2.** A host rule that starts top-level threads only
  on the user's request doesn't rule out route 1. This invocation is that
  request (see Authorization). A host-named delegation tool doesn't rule it
  out either; it governs background delegates, not top-level threads.
- **Record both.** Write the route, the tool that starts implementers, the
  route's reason, and the planner tool to the state file. Name them in the
  opening message.

## Read the Request

Read four things from the request's plain words:

- **Issues.** An ordered list of issue numbers, or one tracker issue whose
  units become the list (`references/request-sources.md` §tracker). The order
  is the dispatch priority. Drop exact duplicates and keep the first position.
- **Window.** The most implementations from this batch running at once. Read
  it from words like "five at a time", "3 in parallel", "window of 4", or "one
  at a time". With no number, use 3 and mark it as the default. If the window
  words give two sizes, or a size that isn't a positive whole number, ask
  before anything launches.
- **Model and effort.** Optional, separately for planners and implementers.
  Default: inherit the session's. Where the platform can't set one, say so in
  the opening message.
- **Repository.** One per batch: the session's project. If the request names
  another repository's issues, say so and launch nothing.

When the request names no issue numbers directly (for example, pointing at a
set named earlier in the thread or describing issues by criteria), read
`references/request-sources.md` §set-named-earlier before resolving it. When it
points at a tracker issue or asks for its units, read
`references/request-sources.md` §tracker before resolving it.

### Occupied Issues

Before anything launches, check every issue in the set for occupancy under
the project's claim rules. Find those rules in its agent instructions, such as
a Claiming section in AGENTS.md or the coordination document it points to.
Read them before you check, and apply their lease expiry, release markers,
and planning reservations as written.

Leave out an occupied issue: one with an active claim, an active planning
reservation, or an open PR that links it. Where the project defines no claim
rules, an open PR that links the issue is the only sign. Planning an occupied
issue would replace the plan its holder is working from.

A left-out listed issue stays in the report as not dispatched: occupied, with
the evidence. If nothing remains, launch nothing and say why.

## Opening Message

Write the state file first (`references/state-file.md` §state-file). Then read
`references/templates.md` §opening-message, send the opening message, and start
without waiting for a reply.

## Plan Every Issue

Start one background planner per issue, all at once, through the planner tool
you recorded. Planners don't count against the window. If the platform caps
how many delegates run at once, start the rest as earlier planners finish. Read
`references/templates.md` §planner-brief for the exact planner brief and
fill-in rules. Record each report in the state file as it arrives. A planner
that ends with neither a report nor a question is recorded as ended without a
report and isn't dispatched.

### Relay Planner Questions

`plan-work-unit` asks a mid-planning question before any planning write, then
stops. Ask the owner as soon as a question arrives. Group questions that arrive
together, at most three per message. Lead each with the issue number and the
planner's recommendation.

Send the answer back to the same planner where the platform can re-enter a
stopped delegate. Otherwise, start a fresh planner for that issue with the same
brief and the owner's answer added. Don't answer for the owner.

## Dispatch in a Rolling Window

### Queue Only Startable Plans

An issue joins the dispatch queue only when its report's status line reads
`#N planned, startable now`. Ignore the bold `Status.` lead word, a link on
`#N`, and trailing punctuation when you match. Queue order
follows the issue list, not finish order. Every other outcome stays out of the
queue and goes in the report as not dispatched, with its reason:

- `#N planned, blocked on #M until <event>`: blocked on #M, with the event.
- `#N planned, startable but I'd hold: <reason>`: held, with the reason.
- `#N planning blocked: <blocker>`: planning blocked, with the blocker.

If the blocking issue #M is in this batch, the dependent issue still waits. #M
needs a human merge first, so this run doesn't dispatch the dependent.

If a startable report has no branch line, name the branch yourself from the
project's branch-naming rule and the issue title. Naming a branch isn't
planning.

### Start Each Implementer

Each implementer works in its own checkout on the plan's branch. That branch
starts from the freshly fetched default-branch tip. A unit whose Dependencies
field stacks it on a PR that is still open starts from that PR's branch
instead. Use the route you recorded under Choose the Routes:

1. **A new top-level thread** with its own worktree on the plan's branch, when
   you can also wait on that thread's end. Send the kickoff sentence alone,
   unless the checkout needs the branch setup. A stacked unit needs it when
   the thread's worktree starts from the default branch.
2. **A background subagent,** through the planner tool where the host names
   one, with worktree isolation where the platform offers it. Send the
   kickoff sentence and the brief in `references/templates.md`
   §implementer-brief.

Some platforms start a delegate's checkout from your commit or pick its branch
name. There, the brief's branch setup is required, or the PR starts from a
stale base. Where the platform gives a subagent no checkout of its own, the
branch setup creates one as a new worktree.

The kickoff's first line is always the sentence `plan-work-unit` hands off:

```text
Handle #N, implementation plan in comments.
```

On the subagent route, and on a thread that needs the branch setup, read
`references/templates.md` §implementer-brief and append its block after that
line.

Pass the implementer model and effort where the platform takes them. Record
the thread or agent link in the state file at launch.

### Keep the Window Full

Count a unit against the window from launch until its run ends. A run ends
with one of these:

- **Handoff report:** the PR is open and its checks are green. Ready for
  review.
- **Blocked report:** the implementer names its blocker.
- **No report:** the run stopped without a report or a question. Record it as
  ended without a report, and never restart it. A second run could duplicate
  its branch or PR.

Read a thread's or subagent's final message as its report.

An implementer that stops on an owner question keeps its slot:

- **Relay it.** Ask the owner as you do for planner questions, and return the
  answer to that unit.
- **No re-entry.** Where the platform can't re-enter that unit, its run has
  ended. Free the slot, record it as waiting on owner, and give the owner the
  question and the unit's link to resume it by hand.

Fill the window by these rules:

- **Start on a free slot.** Whenever a slot frees and the queue isn't empty,
  start the next queued issue.
- **Never exceed the window.** Count only this batch's implementers. Other
  threads, other batches, and the planners don't count.
- **Apply a new window going forward.** If the owner changes the window
  mid-run, apply it to later launches. Never stop a running unit to meet it.

### Wait Without Polling

- **Wake on completion.** Wait on completion notices or a blocking wait on a
  delegate. Re-enter on any notice and act on that delegate's result.
- **One delegate at a time.** Where the platform offers only a blocking wait
  on one delegate at a time, use bounded waits on each running delegate in
  turn.
- **No polling.** Never use a sleep loop or a status poll.
- **End a turn only where a notice wakes you.** Where yielding the turn would
  end the session, block on a wait instead. Don't stop the batch to summarize
  progress or to ask whether to continue.

### End the Batch

The batch ends when nothing it waits on is still working. Then send the
report. What the batch waits on:

- **Planners.** Every planner still working.
- **Free slots.** Every running implementer while an issue is queued behind
  it. Once the queue is empty, no launch is left to make.
- **Subagents.** Every route 2 implementer still working, including one a
  host refusal moved off route 1. Its report reaches the owner only through
  you, so wait for its run to end.

Once the queue is empty, stop waiting on route 1 threads. A top-level thread
is a session the owner can open, read, and answer in, and it posts its own
handoff or blocked report there. Report each one still working as running,
with its thread link.

- **Questions don't hold the report.** A delegate stopped on an owner question
  isn't working. The report lists open questions and any issue still queued
  behind a held slot.
- **A later answer resumes the run.** It resumes its unit and the window as
  before, followed by an updated report.

## Keep a State File

Keep one state file in the session's temporary workspace, never in the project
tree. Read `references/state-file.md` §state-file for when to write it and what
batch and per-issue fields to record. On a resumed or condensed session, read
`references/state-file.md` §resumed-session before taking any action.

## Report

Read `references/templates.md` §report and end with its one status table,
states, and post-table notes.
