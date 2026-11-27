# Message, Brief, and Report Templates

## §opening-message

Write the state file first (`references/state-file.md` §state-file). Then send
one short message and start without waiting for a reply:

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

## §planner-brief

Brief each planner with this text. Fill in `N`, the project's branch-naming
rule, and the owner's request. Write a set named earlier, or a tracker's
resolved units, out as its issue numbers:

```text
Plan #N

The owner assigned this in their request: "<the owner's request>".

Use the plan-work-unit skill. If it isn't available to you, read
<path to plan-work-unit's SKILL.md> and follow it, together with each file
it points to in the references/ directory beside it. Read the repository by
revision, such as git show <sha>:<path>; never check out, switch, or edit
the shared working tree. If you need an owner decision, stop before any
planning write and return the question with your recommendation.

When planning finishes or blocks, return the plan-work-unit report
unchanged. After a finished report, end the same final message with one
more line:
Branch: <branch name for the implementation, following <branch rule>>
```

Leave out the path sentence when you don't know the path.

## §implementer-brief

Append this block after `Handle #N, implementation plan in comments.` on the
subagent route, and on a thread that needs the branch setup:

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

## §report

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
