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
set its rules resolve (see A Tracker). It authorizes launching the planners
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
  units become the list (see A Tracker). The order is the dispatch priority.
  Drop exact duplicates and keep the first position.
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

### A Set Named Earlier

The request may point at a set instead of giving numbers, such as "plan and
handle those". Use the set only when the reference resolves to one list of
issue numbers already written in the thread. Keep that list's order. Never
search the forge to build the set, and never add to it or filter it.

Ask which issues are meant, and launch nothing until the owner answers, when:

- The reference could mean more than one list in the thread.
- The set is described by criteria, not numbers.

Examples:

- **Resolves.** A triage reply listed "#12, #9, #15", then the owner says
  "plan and handle those, two at a time". Run #12, #9, and #15 in that order.
- **Ambiguous.** The thread holds a triage list and a later shortlist, then
  "plan and handle those". Ask which list.
- **Criteria.** "Plan and handle the open bugs." Ask for the issue numbers.

### A Tracker

The request may point at one tracker issue instead of listing issues, such as
"plan and handle the startable units on #835, three at a time". Treat an issue
as a tracker only when the request calls it one or asks for its units. The
batch is the tracker's startable units that no one is working on yet.

Resolve the set in three steps:

1. **Compute the startable units.** Where you have a shell, `gh`, `awk`, and
   `merge-cleanup` installed beside this skill, run its read-only
   `tracker-refresh.sh` with `--repo <host/owner/name>` and `--issue <N>`. Add
   `--comment <ID>` when the owner points at a tracker kept in a comment. The
   `startable now` part of its stderr `OK` line is the set, and its `left`
   part names held units. Where the script can't run, read the tracker's
   **Startable now** bullet, and say in the opening message that it may be
   stale.
2. **Drop units that can't start here.** A tracker keeps a unit startable
   until its PR merges, and the script doesn't check every condition. Leave
   out a unit that:
   - Is closed.
   - Belongs to another repository.
   - Is stacked on a PR that is neither open nor merged.
3. **Put the critical path first.** Units whose nodes a thick arrow (`==>`)
   joins in the tracker's diagram go first, then the rest. Keep the tracker's
   Units order within each group.

Every remaining unit gets a planner, including one that already has a plan.
Its planner's report still decides whether it dispatches.

Launch nothing, and say why, when:

- **The tracker isn't readable as one.** It is closed, isn't on the shared
  tracker format, or the script exits with a stop or a failed lookup. Report
  the script's error, and ask for issue numbers where the format is the
  problem.
- **Nothing remains.** Report the tracker's reason and each unit left out.
- **The source is unclear.** The request names a tracker without its number
  or link, names two trackers, or adds listed issues to one. Ask which set is
  meant.

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

Write the state file first (see Keep a State File). Then send one short
message and start without waiting for a reply:

```text
Plan and handle batch: #3268, #3171, #3166 (3 issues, in dispatch order).
Window: 3 implementations at a time (default; tell me a number to change it).
Model: session model for planners and implementers.
Planners: background delegates through <planner tool>.
Implementers: new top-level threads with worktrees (route 1).
State: <state file path>
Starting 3 planners now.
```

On route 2, the implementer line names what route 1 lacked:

```text
Implementers: background subagents through <tool> (route 2: no tool waits
on a thread's end).
```

List the issue numbers in dispatch order, even when the request already gave
them, so the owner can stop a wrong set at once. Mark a default as a default.
This holds for a set named earlier, once it resolves to one list. The route
lines let the owner stop a wrong route before any implementer runs.

When the check leaves issues out, add a line for them, each with its reason.
For a tracker, also name it in the first line:

```text
Plan and handle batch: tracker #835, #897, #901, #910 (3 startable units,
critical path first, in dispatch order).
Left out: #899 (open PR #930), #905 (held: Blocker line in Dependencies).
```

## Plan Every Issue

Start one background planner per issue, all at once, through the planner tool
you recorded. Planners don't count against the window. If the platform caps
how many delegates run at once, start the rest as earlier planners finish.
Brief each planner with this text. Fill in `N`, the project's branch-naming
rule, and the owner's request. Write a set named earlier, or a tracker's
resolved units, out as its issue numbers:

```text
Plan #N

The owner assigned this in their request: "<the owner's request>".

Use the plan-work-unit skill. If it isn't available to you, read
<path to plan-work-unit's SKILL.md> and follow it. Read the repository by
revision, such as git show <sha>:<path>; never check out, switch, or edit
the shared working tree. If you need an owner decision, stop before any
planning write and return the question with your recommendation.

When planning finishes or blocks, return the plan-work-unit report
unchanged. After a finished report, end the same final message with one
more line:
Branch: <branch name for the implementation, following <branch rule>>
```

Leave out the path sentence when you don't know the path. Record each report
in the state file as it arrives. A planner that ends with neither a report nor
a question is recorded as ended without a report and isn't dispatched.

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
   kickoff sentence and the brief below.

Some platforms start a delegate's checkout from your commit or pick its branch
name. There, the brief's branch setup is required, or the PR starts from a
stale base. Where the platform gives a subagent no checkout of its own, the
branch setup creates one as a new worktree.

The kickoff's first line is always the sentence `plan-work-unit` hands off:

```text
Handle #N, implementation plan in comments.
```

On the subagent route, and on a thread that needs the branch setup, add:

```text
The owner assigned this in their request: "<the owner's request>".

Before you edit anything, claim the issue as the project's claim rules
require, if it has any. If another claim wins, stop and return a blocked
report. Then fetch the default branch from its remote and create
branch <branch> from that exact tip, in your own checkout. If the issue's
Dependencies field stacks it on a PR that is still open, start <branch> from
that PR's branch instead, and open your PR against that branch. Where
<branch> already exists with no commits of its own, reset it there. If you
have no checkout of your own, create one with git worktree add on that
branch. Work only in that checkout.

If you need an owner decision, stop and return the question with your
recommendation. When you finish, return the PR link and your handoff report,
or your blocked report.
```

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

Keep one file in the session's temporary workspace, never in the project tree.
Write the ordered issue list and the window before anything launches, so a
later turn doesn't depend on the message that defined the set. Then update it
at every launch, every report, and every relayed question.

Record for the batch:

- The repository, the ordered issue list, the window, and model choices.
- The issues left out, with their reasons, and for a tracker its number.
- The implementer route, the tool that starts implementers, the route's
  reason, and the planner tool. On route 2, the reason names what route 1
  lacked.

Record for each issue:

- The planner's thread or agent link, and its status line.
- The branch from the planner's report.
- The implementer's thread or agent link, and its PR.
- Its state: planning, queued, running, waiting on owner, ready for review,
  blocked, not dispatched, ended without a report, or unknown.

On a resumed or condensed session, read the state file before anything else.
Then follow these rules:

- **No second implementer.** Never relaunch an implementer the file records
  as launched.
- **A planner only for an answer.** Relaunch a recorded planner only to carry
  the owner's answer to its question.
- **The recorded set stands.** Never resolve a tracker again. A unit that
  became startable since then waits for a later batch.
- **The recorded route stands.** Launch the remaining implementers on the
  recorded route, and start any planner through the recorded tool. Don't
  choose either again.
- **Unknown stays unknown.** If the platform can't tell you whether a
  recorded run is still going, report it as unknown rather than starting
  another.

## Report

End with one table, one row per listed issue, in dispatch order:

```text
| Issue | Plan        | Implementation | PR    | State                        |
| ----- | ----------- | -------------- | ----- | ---------------------------- |
| #3268 | startable   | <thread link>  | #3301 | Ready for review             |
| #3171 | held        | n/a            | n/a   | Not dispatched: <reason>     |
| #3166 | startable   | <agent link>   | n/a   | Blocked: <blocker>           |
| #3170 | startable   | <thread link>  | n/a   | Running in its own thread    |
```

Use these states: ready for review, running in its own thread (route 1
only), blocked (with the blocker), waiting on owner (with the question),
queued (behind a held slot), not dispatched (with the reason), ended without a
report, and unknown. Below the table, list any question still waiting on the
owner. When a thread is still running, say that each thread reports in its
own session and the batch doesn't track it further. For a tracker, repeat the
line of units left out.
