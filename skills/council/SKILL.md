---
name: council
description: >-
  Convene a panel of independent reviewers drawn from as many model providers
  as the platform can reach, then report how independent the panel was. In
  findings mode it reviews a change at a fixed revision and keeps only
  confirmed findings; in scoring mode it scores blinded candidates against a
  rubric. Use when the user says "council", "council this", or "multi-model
  review", asks several models to review one change independently, or when
  another skill invokes council. An escalation that costs one
  high-effort run per member: never run it on your own initiative, and not for
  an ordinary single review, a code-review command, or one named second
  opinion.
---

# Council

Council seats independent reviewers, preferably from different model
providers, so that one model's blind spots don't decide a review. Each member
costs a high-effort run, so council is an escalation, never a default.

## When to Run

Run council only when one of these requests it:

- **The user.** They ask for council.
- **A calling skill.** Another skill invokes council.
- **A project instruction for a named class of work.** It sits in the
  project's agent instructions, such as `AGENTS.md` or a document it points
  to. For example, a pre-push review section that requests council on
  changes to a destructive path or a credential-leak surface. It is the
  owner's standing request, but only for the classes it names.

Never start council on your own initiative for work no request covers, even
risky work; suggest it instead. A standing request doesn't skip "State the
Cost First."

Risk-class work, which changes how the panel stages, means work that touches
a destructive path, a credential-leak surface, or a returned-object trust
boundary, changes a contract or public interface, or changes behavior without
tests. Use the project's own list instead when it defines one.

## Check the Platform

Before choosing a panel, find which providers the host can reach. A provider
counts as reachable through either of these:

- **A delegation tool that starts a fresh context.** For example, a host
  delegation tool with a provider or model option, or a plain subagent tool,
  which reaches the lead's own provider.
- **An installed CLI the session may run.** For example, `codex exec` or
  `claude -p`. The CLI must be on the path, authenticated, and allowed by the
  session's permissions. A denied or prompting command that the user declines
  doesn't count; never route around it.

Reachable also means the account has usage left, which shows only at launch;
don't spend a run probing it beforehand. A member can fail for quota, a rate
limit, or exhausted usage on the account, at launch or partway. Unless a
retry under When a Member Fails clears it, that provider is unreachable for
the rest of this run. Any other failure, such as a model the route doesn't
offer or a timeout, costs that seat, not the provider.

The number of reachable providers sets the rung below; each provider lost,
before or during the run, moves the panel toward a lower rung. The tools named
here are examples, never requirements.

## Choose the Rung

| Rung | Platform                                        | Panel                                                                                                       |
| ---- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 1    | Two or more providers reachable                 | One strong model per reachable provider                                                                     |
| 2    | One provider reachable through fresh contexts   | Two fresh contexts with different focuses, such as correctness and security, on different models if offered |
| 3    | No way to start a fresh context on any provider | No council                                                                                                  |

At rung 3, run no council. Say so, and fall back to the project's bot or human
reviewer; in scoring mode, return no scores. Don't play a member in your own
context, since your context holds the reasoning members must not see.

The default rung 1 panel is one member per provider. A third seat from a
provider already seated runs only when the user or calling skill asks for it.

**Named members.** When the user or calling skill names members, such as
providers or models, seat only the reachable ones. Say before launching which
named members aren't reachable and leave their seats empty. Never fill an
empty seat with a different model unless the user says to; when fewer than two
named members remain, ask whether to add one, or report that no council ran.

## When a Member Fails

A missing review must never read as a clean one. Handle a member that fails
at launch or partway this way:

- **Failed means failed.** A member refused at launch, or one that errors,
  times out, or returns no parseable report, is a failed seat. Record its
  provider, model, and error, and never count it as "no findings." In scoring
  mode, a member whose either run fails is failed.
- **Retry once at most.** Retry only a transient error, such as a rate limit
  with a stated reset or a dropped connection, and only when the wait fits the
  run. It fits within a time budget the user or caller set. With no budget,
  it fits before the other launched members return. With no budget and no
  other launched member still running when the error arrives, such as the
  first member in findings staging, the wait is at most 2 minutes. Retry
  after a stated reset no more than 2 minutes away, or at once after a
  dropped connection. Otherwise the seat is failed.
- **Re-seat a default panel only when the rung drops.** When the remaining
  planned seats still support the planned rung, report the failure and launch
  no replacement. Otherwise prefer a replacement that keeps the planned rung:
  the failed member's own provider if it is still reachable, on another model
  where one is offered, or a reachable provider not yet seated. Only when none
  exists, seat another fresh context on a remaining provider (rung 2). State
  the revised cost first. Re-seat each slot once; a failed replacement leaves
  the slot failed. With no seat left, the panel drops to the lower rung or
  rung 3.
- **Leave a named member's seat empty.** The Named members rule above
  applies: no substitute without the user's say-so.

Report the rung the panel achieved. Count completed members, plus reachable
seats that staging held back after a completed member found a confirmed
blocker; never count a failed seat. Count members, not runs: a scoring
member's two runs are one member. Two or more providers is rung 1, two or more
members on one provider is rung 2, and fewer than two is rung 3.

## State the Cost First

Before launching anyone, state the rung, the panel size, each member's
provider and model, the effort level, and the number of runs (two per member
in scoring mode). Use high effort unless the user or
caller sets another. For findings mode, also state the staging below, since
later members may not run. Re-state the cost before launching any
replacement for a failed seat.

## Brief Members

Each member starts read-only in a fresh context and receives only these:

- **The artifact at a fixed revision.** A commit SHA, a diff saved to a file,
  or a set of files at a named revision.
- **Its intended outcome, in findings mode only.** What the change should
  achieve, taken from the caller, the issue, or the PR. Scoring mode withholds
  it, since it describes the target.
- **The mode's instructions.** For findings mode, ask the member to find
  reasons the artifact is wrong and to give a reproduction or trace for each
  claim. For scoring mode, use the scoring brief below.

Leave out your reasoning, your earlier findings, and other members' output.
The one exception is a fix check, whose brief also lists the confirmed
findings being checked, each with its reproduction or trace.
Where the route can enforce read-only access, such as a CLI's read-only
sandbox, use it; otherwise state it in the brief.

Never edit a checkout a member is still reading. Give each member a separate
checkout or worktree at the fixed revision, or wait for every member reading
your checkout to return before you edit it.

## Stage the Findings Panel

Findings mode seats the panel in stages to spend runs only where they add
independence:

1. **Other provider first.** A member from a provider other than yours
   reviews first. At rung 2, a member on a model other than yours goes first
   where there is one.
2. **Expand only when it pays.** Further members join only when the first
   finds no confirmed blocker, or when the work is risk-class. A blocker is
   a confirmed finding the change can't ship with, such as a correctness,
   security, or data-loss defect.
3. **Check fixes narrowly.** After you fix confirmed findings, one member
   checks the fixes, preferably the one that found them, at the new fixed
   revision.
4. **Full panel for the final version.** The whole panel reviews again only
   the version you intend to hand off.

A failed member isn't a member that found no confirmed blocker. Its
replacement, if When a Member Fails calls for one, or else the next planned
member, takes its place in the stage.

When the caller wants a report only, with no fixes, stop after steps 1 and 2.

## Findings Mode

A claimed finding counts only after a reproduction or trace confirms it.
Confirm it yourself: run the failing case, or trace the call path with
`file:line` references. A claim you can't confirm stays in the unconfirmed
list; it isn't dropped and isn't counted.

Group claims that name the same defect. Record which members raised each one,
and where members disagree, such as one calling a path reachable and another
not, record both positions and what your confirmation showed.

Keep the scope from growing. A confirmed finding outside the artifact's
intended outcome becomes a follow-up, not new work in this change.

## Scoring Mode

Scoring mode seats the full panel at the chosen rung, since disagreement
between members, visible in each member's scores, is part of the result. Brief each member with these rules:

- **Rubric and references in view.** Give the rubric and the reference
  examples that anchor its scale.
- **Target hidden.** Leave out the target the candidates aim at, such as a
  mock-up or the caller's goal statement. Seeing it inflates scores.
- **Candidates blinded.** Shuffle the candidates and strip every label that
  hints at origin or order, such as file names, iteration numbers, or authors.
  Keep a private key that maps each blinded candidate back.
- **Two scores each.** Each member scores every candidate twice, in two fresh
  contexts with a different shuffle each time.

Report both scores and their spread for each candidate and member. Scores
never gate a review on their own: never turn them into a pass or fail. The
caller decides what a score means.

## Caller Contract

Other skills call council through these inputs and report fields. Changing
them means updating every caller. Callers treat a council with failed seats
as the rung it achieved.

### Findings Contract

**Inputs:** the artifact at a fixed revision (a diff, commit, or set of
files) and its intended outcome. Optional: named members, effort level,
whether the work is risk-class, and whether to report only.

**Report:**

- **Rung and members.** The rung the panel achieved, and each member's
  provider, model, and effort, with any named member that wasn't reachable.
- **Failed members.** Each failed member's provider, model, and reason, and
  whether its seat was re-seated.
- **Confirmed findings.** Each with the member or members that found it and
  its reproduction or trace.
- **Agreement.** Where members agreed and where they disagreed.
- **Unconfirmed claims.** Listed separately, with the member that raised each.
- **Follow-ups.** Confirmed findings outside the intended outcome.

### Scoring Contract

**Inputs:** a rubric, reference examples, and one or more candidates. The
caller may also pass the target, which council keeps from members, and named
members or an effort level.

**Report:**

- **Rung, members, and failed members.** As in findings mode.
- **Scores.** For each candidate and completed member, both scores and their
  spread.

The scoring report never includes a pass or fail.

### Rung 3 Contract

At rung 3 either mode reports the rung, the reason no council ran, and the
fallback reviewer, with no council findings or scores. A run that fell to rung
3 because members failed also lists them. In findings mode, it keeps a lone
completed member's confirmed findings, labeled a single review, not a
council.
