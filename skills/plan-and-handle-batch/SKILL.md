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

Run a batch of issues from plan to review-ready PR: one planner per issue, one
implementer per startable plan in an isolated checkout (up to N running at
once), and one status table at the end.

As orchestrator, you launch delegates, relay questions, keep the window full,
keep the state file, and report. Never plan or implement yourself: no issue or
comment edits, and no branches, commits, or code changes in your checkout.

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
Examples show what qualifies; they don't choose a route (see Choose the
Routes).

1. **Background delegation with a wake.** The session can run background
   subagents or threads and learn when each ends via a completion notice or
   blocking wait (never a sleep loop or status poll). Examples: Claude Code
   background `Agent` with notifications, Codex `spawn_agent` with
   `wait_agent`, T3 Code `delegate_task`, or a new top-level thread waited on
   with T3 Code `t3_thread_launch` and `t3_thread_wait`.
2. **`plan-work-unit` for planners.** Listed in this session, or installed
   beside this skill as `../plan-work-unit/SKILL.md`.
3. **An isolated checkout per implementer.** The platform gives each
   implementer its own worktree or checkout (for example, T3 Code
   `t3_thread_launch` with `workspaceStrategy`, or a Claude Code subagent with
   `isolation: "worktree"`), or each implementer has a shell and Git to create
   one.

Decide each requirement this way:

- **Listed means granted.** A listed tool qualifies unless a rule forbids it.
- **This invocation is the request.** A rule limiting delegation to explicit
  requests doesn't fail a requirement.
- **Unfamiliar isn't missing.** Never fail a requirement because a tool name
  is unfamiliar.
- **Named but unloaded counts as listed.** Before deciding a requirement or
  route, load every named-but-unloaded tool that can start or wait on a thread
  or delegate in the background. Use the platform's tool loader even when a
  loaded tool already qualifies; if every listed tool is loaded, skip loading.
  A tool that fails to load isn't offered, with the failure as the reason.
  Never choose a tool just because it's already loaded.

On a miss, launch nothing and stop with this error, naming each missing part:

```text
plan-and-handle-batch can't run here: <missing requirement>.
Run each issue by hand instead: "Plan #N", then, once the plan is startable,
"Handle #N, implementation plan in comments." in a fresh session.
```

Never fall back to planning or implementing in your own context.

## Authorization

Invoking this skill assigns `Plan #N` and `Handle #N` for each issue in the
batch (for a tracker, the set resolved by `references/request-sources.md`
§tracker), and nothing else. It authorizes launching planners and implementers
without per-launch confirmation, and counts as the user's request where a host
requires one for new top-level threads. If the host still refuses top-level
threads, switch to route 2 for that launch and the rest, update the state file
with the refusal as the reason, and tell the owner in one line.

This assignment doesn't authorize choosing, adding, or dropping issues beyond
Read the Request, merging or landing, restarting an ended implementer run, or
working in another repository.

Never route around a platform approval prompt. On a refused or failed launch,
record the issue as not dispatched with the error, free its slot, and continue.

## Choose the Routes

Before reading the request, choose how planners and implementers start from
every tool the session lists, loaded or not (see Requirements).

- **Planner tool.** If host rules name a tool for background delegation (such
  as T3 Code `delegate_task`, never background `Agent`), start planners and
  route 2 implementers through it. Otherwise use any tool meeting requirement 1.
- **Implementer route.** Prefer **route 1** (a new top-level thread) when the
  session lists all three: a tool that starts a top-level thread, a dedicated
  worktree for it, and a wake on thread end. The wake (a completion notice or
  blocking wait) refills the window while issues are queued. Take **route 2**
  (a background subagent, with worktree isolation where offered) only when one
  of the three is missing, naming the missing piece as the reason.
- **Not a reason for route 2.** A host rule requiring a user request for
  top-level threads doesn't rule out route 1 (see Authorization). Neither does
  a host-named delegation tool, which governs background delegates, not
  top-level threads.
- **Record both.** Write the route, implementer tool, route reason, and planner
  tool to the state file, and name them in the opening message.

## Read the Request

Read four things from the request's plain words:

- **Issues.** An ordered list of issue numbers, or one tracker's units
  (`references/request-sources.md` §tracker). Order sets dispatch priority;
  drop exact duplicates, keeping the first position.
- **Window.** Max batch implementations running at once, from plain words
  ("five at a time", "3 in parallel", "window of 4", "one at a time"). Default
  to 3 and mark it as the default. If the words give two sizes, or a size that
  isn't a positive whole number, ask before launching anything.
- **Model and effort.** Optional, separately for planners and implementers
  (default: inherit the session's). Say in the opening message if the platform
  can't set one.
- **Repository.** The session's project only. If the request names another
  repository's issues, say so and launch nothing.

For a request without direct issue numbers (an earlier list in the thread or
criteria), read `references/request-sources.md` §set-named-earlier first. For a
tracker issue or its units, read `references/request-sources.md` §tracker
first.

### Occupied Issues

Before launching anything, read the project's claim rules (for example,
AGENTS.md's Claiming section or the coordination doc it links) and check every
issue using their lease expiry, release markers, and planning reservations as
written.

Leave out any issue with an active claim, active planning reservation, or
linked open PR (planning it would overwrite its holder's plan). Without project
claim rules, only a linked open PR marks occupancy. Report each left-out listed
issue as not dispatched: occupied, with evidence; if none remain, launch
nothing and say why.

## Opening Message

Write the state file first (`references/state-file.md` §state-file). Then read
`references/templates.md` §opening-message, send the opening message, and start
without waiting for a reply.

## Plan Every Issue

Start one background planner per issue, all at once, through the recorded
planner tool; planners don't count against the window. If the platform caps
concurrent delegates, start the rest as earlier planners finish. Read
`references/templates.md` §planner-brief for the brief and fill-in rules.
Record each report in the state file as it arrives; record a planner ending
with neither report nor question as ended without a report, and don't dispatch
it.

### Relay Planner Questions

`plan-work-unit` asks mid-planning questions before any planning write, then
stops. Relay each question to the owner immediately, grouping concurrent
questions up to three per message and leading each with the issue number and
the planner's recommendation.

Return the owner's answer to the same planner where the platform can re-enter a
stopped delegate; otherwise start a fresh planner with the same brief plus the
answer. Never answer for the owner.

## Dispatch in a Rolling Window

### Queue Only Startable Plans

Queue an issue only when its report's status line reads
`#N planned, startable now` (ignoring a bold `Status.` lead, a link on `#N`,
and trailing punctuation). Follow the issue list's order, not finish order.
Keep every other outcome out of the queue and report it as not dispatched with
its reason:

- `#N planned, blocked on #M until <event>`: blocked on #M, with the event.
- `#N planned, startable but I'd hold: <reason>`: held, with the reason.
- `#N planning blocked: <blocker>`: planning blocked, with the blocker.

Even if blocking issue #M is in this batch, don't dispatch its dependent (#M
needs a human merge first). If a startable report omits the branch line, name
the branch from the project's branch-naming rule and issue title; naming a
branch isn't planning.

### Start Each Implementer

Each implementer works in its own checkout on the plan's branch, started from
the freshly fetched default-branch tip (or from the base PR's branch when
Dependencies stacks it on a still-open PR). Launch on the recorded route,
passing implementer model and effort where supported, and record the thread or
agent link in the state file at launch.

The kickoff's first line is always `plan-work-unit`'s handoff sentence:

```text
Handle #N, implementation plan in comments.
```

- **Route 1 (top-level thread):** Start its worktree on the plan's branch and
  send that line alone, unless the checkout needs branch setup. Branch setup is
  required when the platform starts it from your commit, picks its branch name,
  or starts a stacked unit from the default branch.
- **Route 2 (background subagent), or any thread needing branch setup:** Read
  `references/templates.md` §implementer-brief and append its block after that
  line. Branch setup is required there so the PR doesn't start from a stale
  base, and it creates a worktree where a subagent gets no checkout of its own.

### Keep the Window Full

Count a unit against the window from launch until its run ends, reading its
final message as its report:

- **Handoff report:** PR is open with green checks (ready for review).
- **Blocked report:** Implementer names its blocker.
- **No report:** Stopped without report or question. Record as ended without a
  report and never restart it (a second run could duplicate its branch or PR).

An implementer stopping on an owner question keeps its slot: relay the question
as for planners and return the answer. Where the platform can't re-enter it,
the run has ended: free the slot, record it as waiting on owner, and give the
owner the question and unit link to resume by hand.

- **Start on a free slot.** When a slot frees and the queue isn't empty, start
  the next queued issue.
- **Never exceed the window.** Count only this batch's implementers, not
  planners, other batches, or other threads.
- **Apply a new window going forward.** Apply mid-run window changes to later
  launches only; never stop a running unit.

### Wait Without Polling

- **Wake on completion.** Wait on completion notices or a blocking delegate
  wait; re-enter on any notice and act on its result.
- **One delegate at a time.** Where the platform offers only a blocking wait on
  one delegate at a time, rotate bounded waits across running delegates.
- **No polling.** Never use a sleep loop or status poll.
- **End a turn only where a notice wakes you.** Block on a wait if yielding
  would end the session. Never pause the batch to summarize progress or ask
  whether to continue.

### End the Batch

End the batch and send the report once nothing you wait on is still working:

- **Planners:** Every planner still working.
- **Free slots:** Every running implementer while an issue is queued behind it.
- **Subagents:** Every running route 2 implementer (including any moved off
  route 1 by host refusal), since its report reaches the owner only through
  you.

Once the queue is empty, stop waiting on route 1 threads. The owner can open,
read, and answer each top-level thread directly, where it posts its own handoff
or blocked report; report each still-working thread as running with its link.

- **Questions don't hold the report.** A delegate stopped on an owner question
  isn't working; list open questions and any issue queued behind a held slot.
- **A later answer resumes the run.** Resume that unit and the window as
  before, then send an updated report.

## Keep a State File

Keep one state file in the session's temporary workspace, never in the project
tree. Read `references/state-file.md` §state-file for cadence and required
fields. On a resumed or condensed session, read `references/state-file.md`
§resumed-session before taking any action.

## Report

Read `references/templates.md` §report and end with its one status table,
states, and post-table notes.
