# Parallel Work Design: Start Freely, Validate at Landing

Design proposal, revision 10, 2026-10-14. No rule changes until the owner
adopts this proposal. Review capacity is out of scope, as requested.
Revisions 4 to 9 are saved beside this file, each with notes on its
changes. Revision 4 holds the full measurements and the comparison with
large-team practice.

## Overview

**Let units start without checking on each other, and check every merge
when it lands.** A unit is one assigned task, done by one agent session,
that ends in one PR.

Today, units check for conflicts before starting. Those that change a
shared contract run at most two at a time, and only after each pair has
been assessed. Other units compare their scope with open work and declare
which pairs must not overlap. Safe work waits, yet these checks can't
catch every problem that arises when changes are combined: `main` has
accepted merges that were never tested together, and one broke the build
for 35 minutes.

The proposal replaces those restrictions with three rules (§1), enforced
by one named check on Freeside and one command on Teloleo and Straylight
(§3). Adoption means naming the check, adding one migration test, removing
the rules that serialize work, and changing agent-setup's defaults so
future projects don't inherit those restrictions (§4). Section 2 explains
how the rules apply; §5 gives the evidence, and §7 lists the owner
decisions, all made.

**The cost is retries.** Conflicts that today's rules flag before work
starts will instead appear at landing. Reading the rebase prevents a
conflict resolution from quietly undoing another unit's work (§2.4). If
retries concentrate in a few files, restructuring those files makes
them rarer (§5.2).

Two unknowns could change the recommendation: how often units overlap
when ten run at once, and how one machine handles ten agents running
tests. Both need measurement at that scale.

## Terms

- **Unit.** One assigned task, done by one agent session, that ends in
  one PR. A unit is open from its claim until its PR merges. A _contract
  unit_ changes a shared contract: the domain types, the migrations, the
  driver interfaces, or the API schema.
- **Claim.** The comment a session posts on a unit's issue to say it is
  working on it. An open PR counts as one too.
- **Tracker.** A GitHub issue that lists the units of a wave, a feature,
  or a backlog and charts their dependencies. Some trackers live in a
  comment on another tracker, such as a wave's exit set.
- **Relations.** Entries in a unit's Dependencies field: `starts-after`
  (wait for it to merge before starting), `merges-after` (start freely,
  merge after it), and `stacked-on` (branch from its open PR). This plan
  removes a fourth, `exclusive-with` (never open at the same time).
- **Planner.** Whoever plans a wave and writes its tracker: the owner, or
  a session the owner runs for it. Today this is part of the spine role
  (§6).

## 1. The Rule

1. A unit starts when it is authorized, nobody holds its claim, and every
   unit it lists as `starts-after` has merged.
2. A PR merges only after the required checks pass on its content
   combined with the tip it lands on.
3. A unit that must be written against another unit's result lists it
   as `starts-after`. Everything else, including a conflict in text, is
   resolved at landing, and after a rebase that conflicted, the author
   reads what the resolution changed.

Rule 2 proves what the required checks test and nothing else. A project
catches at landing what its checks can see; §2.6 lists what they can't.

## 2. What Follows

### 2.1 Starting

Before starting, a session checks only the three conditions in rule 1.
The two authorization doors, scheduling and `Handle #N`, stay unchanged.
A planning reservation holds its own issue but no longer blocks other
units. Sessions stop comparing their scope with open work, and contract
units no longer wait for an assessment or a free slot.

Existing `exclusive-with` pairs are removed, not converted. The planner
records a `starts-after` only when one unit must be written against the
other's result. Working on the same subject, such as retry timing and
retry limits, doesn't require an order. Neither does a textual conflict:
two PRs adding a line to one switch resolve it by rebasing at landing.

### 2.2 Contracts

Contract units need no additional coordination rule because of how
contract changes are made.

- **A breaking change fixes every user in the same PR.** The daemon,
  app, and generated client are all in this repository, and contract PRs
  already have to include their generated consumers. Another unit that
  still uses the old shape fails to compile or fails a test at landing.
- **A change of meaning is a rename in the same PR.** If a field keeps
  its shape but means something new, the compiler can't detect the
  change. Renaming makes every open PR that uses the old name fail to
  compile at landing, forcing its author to look. Review checks how the
  author adapts the code; the rename doesn't.
- **Stored data is the exception.** Rows and stored documents already
  exist under the old shape, so a change to them is added first and
  migrated.
- **Contract PRs still meet in generated files,** and on the digest
  line while it remains a checked-in constant (§5.2). The second to land
  rebases and regenerates, as the project already requires when another
  contract unit lands first.

### 2.3 Migrations

Migrations keep their numbering. `daemon/migrations/migrations.go`
numbers them contiguously and pins each applied migration by name and
digest. Every database therefore has the same history, and a renamed or
rewritten file is refused. The protocol is:

1. Take the next number.
2. If another migration lands first, rename yours behind it with
   `git mv`, grep for the old name across `daemon/`, then retest. The
   rename is safe because no database that persists has run the branch
   build. If a `dev` tier has run it, wipe and reinstall that tier.
3. From 0099 on, declare every table, column, index, trigger, or view the
   migration removes in its file, one `-- drop:` line each.

One test enforces the third rule. Eleven of the 98 migrations rebuild a
table from a column list fixed when they were written. Such a rebuild
silently drops a column, index, or trigger that another migration added
in between. A dropped column named by store code already causes a
failure: the tables are `STRICT`, and the first query naming it errors.
An index or trigger can vanish without a test failing.

The new test applies migrations in order to a fresh database and lists
the names of tables, columns, indexes, triggers, and views after each
one. Any name present before a migration and absent afterward must be
declared in that file. A declared drop that didn't happen also fails,
keeping the declarations accurate. The test starts at 0099, the next
number on `main` as of 2026-10-14, because earlier files are pinned by
digest and can't gain a comment.

The test doesn't cover a constraint change lost in a rebuild.
Constraints have no names, and changing one requires a rebuild, so this
case involves two rebuilds of one table open at once. Nor does it cover
two migrations rewriting the same rows. In both cases, the second must
be written against the first's result. Rule 3 orders them with
`starts-after` when the planner sees them.

Timestamp-named migrations applied in any order, as Ecto and Rails do,
were considered on 2026-10-14 and rejected. They remove the rename by
allowing a deployed database to run migrations in a different order from
a fresh one, which no landing check can test. The only persistent
database running branch builds is the `dev` tier, and the owner confirmed
that day that its state is disposable. Renaming therefore costs a
`git mv` and one CI run. Section 5.5 describes the current runner and
the check requested in freeside-ai/freeside#1712.

### 2.4 Reading a Rebase

Tests can't detect everything that lands. PR 47 removed a workflow fix,
a README line, and a decision note, and nothing failed. Two units can
also change one function in ways that compile but have never been read
together.

When a rebase conflicts, the author decides by hand how the changes
combine. That decision is folded into the branch's own commits, where no
diff shows it separately. The rule is: **after a rebase that conflicted,
the author runs `git range-diff` between the branch before and after the
rebase and records what the resolution changed in the PR's Verification
section.**

A clean rebase can also change the branch's diff. Git follows an upstream
rename, so a branch editing `app/item.txt` can emerge from a clean rebase
editing `daemon/item.txt`. The author pushes that rebase; Codex reviews
the push, the scope check runs on the result (§6), and tests run on it
at landing. This needs no new tool:
`scripts/merge-result-audit.sh`, which exists because of PR 47, keeps
its scope check.

A test remains the first defense. When a unit lands a test for its
intended behavior, a later unit that drops that behavior fails at landing
without anyone having to read it.

### 2.5 Trackers

At each merge, tracker upkeep consists of the four refresh steps in
`docs/tracker-format.md`. That file says chart edges never change at
merge, so planning, storage, and relations can stay as they are. Only the
refresh needs automation.

The command takes a tracker issue and reads the charts in its body and
comments. It asks GitHub which units have merged, then updates the double
borders, green outlines, ticks, and **Startable now** line. It trusts the
edges as drawn. If a Dependencies field changes mid-wave, someone redraws
the edge, as today. A session still rereads the field before claiming,
so a wrong green outline can't start work. The command must treat a
unit closed as not planned as unmerged (§5.6).

The command runs as a merge-cleanup step, by the session that merged.
The owner decided on 2026-10-14 that it stays agent-run rather than
running from a workflow, because the refresh involves judgment: how a
unit closed, and whether an edge changed mid-wave. It belongs with the
shared tracker format so Teloleo and Straylight get it too. Freeside's
daemon will need dependency data it can read to work out what can
start (plan §5.18, wave 11); that work is outside this plan.

### 2.6 What the Rule Gives Up

- **Early warning.** Conflicts are found at landing, after the work is
  done, and cost a retry.
- **Protection against unrecorded dependencies.** A missing `starts-after`
  wastes the later unit's work. Nothing catches a missing edge before
  work starts, today or under this plan.
- **A mechanical check for two units that change one function in ways
  that compile.**
  The rebase rule in §2.4 covers conflict resolution, not edits that merge
  cleanly. Tests at landing and Codex's review of every push remain.
- **A mechanical check for interaction at a distance.** One unit can
  change a behavior while another adds a caller elsewhere, without
  touching the same place. Only tests at landing can catch that.
- **A defense against two migrations rewriting the same rows or two
  rebuilds of one table open at once,** beyond the ordering a planner
  records.
- **Enforcement on private repositories.** The land command is a
  convention. Its last read of `main` and the merge are separate steps,
  so it relies on one landing at a time, agent-run or not. A
  repository-wide lock would close that window; add one if measurement
  (§4) shows landings crowding each other.

## 3. Enforcement

Rule 2 uses the same procedure in every repository:

1. Fetch `main`. If the PR branch isn't on top of its tip, rebase and
   push.
2. Wait for CI on that exact commit.
3. Merge only if `main` hasn't moved since step 1. Otherwise repeat.

All three projects already call this "Repeat integration checks when
the base moves". The difference is who enforces it.

### 3.1 Freeside

**A required check enforces the procedure.** With a required status check
and the up-to-date rule, GitHub allows a merge only when the branch
contains the tip and the check has passed on that commit. Freeside has
the up-to-date rule enabled but names no check. GitHub's documentation
says the rule has no effect until a check is named.

That check must always report. Each component workflow has a path filter
that skips it outside its paths. A skipped workflow never reports, so
requiring one would block every PR outside those paths. Instead, one job
without a path filter runs on every PR, selects component checks from
the changed paths, and reports one result. Today's checks are reliable
enough to require (§5.3). Once the check is required, it replaces the
author's recheck when `main` moves (§6).

**The merge queue can speed this up later.** With only the required
check, each merge makes every other ready PR out of date. Each must then
rebase and rerun CI in turn. GitHub's merge queue tests each queued PR
on the current tip plus the PRs ahead of it. It merges those that pass
and returns a failing PR to its author with `main` unchanged. This public,
organization-owned repository qualifies for the queue on the free plan.

The queue can't add a commit, so renaming and regeneration happen in
the PR; the queue only verifies the result. The commit-message check
runs on `pull_request` only and skips `merge_group`, because the queue's
own merge commit has a shape that check rejects. The scope check (§6)
must learn the `merge_group` event before the queue is required. That
event carries no pull request, and a group can hold several, so the job
resolves each PR in the group from its merge commits and checks every
Scope line. Enable the queue once measurements show ready PRs waiting
on each other's rebases often enough to matter (§4, step 9).

**Delete the race tests.** Three jobs ran the daemon's tests under the
race detector, only after merge, with an observer that filed a
`ci-race` issue on failure. Freeside chose that over a PR-gated race
run on 2026-08-08 (`devlog/2026-08-08-1103-main-race-incident-policy.md`)
on the assumption that a post-merge run would catch regressions worth
its cost. In two months the detector reported no data race: the eight
`ci-race` issues record suite timeouts, intermittent tests, the
observer's own API failure, and one test's nil-pointer panic (§5.4).
That test read a map entry its goroutine had already deleted, an
ordering bug in the test that the detector's scheduling exposed; its
fix changed no product code (freeside-ai/freeside#632).

The jobs run the same suites as the required job, instrumented, so they
add no test. They are CI's only run under the race detector, so
deleting them leaves data races to `go test -race` as a local command.
They cost three runners 17 to 26 minutes on every push to `main`. The
owner decided on 2026-10-14 to delete the jobs and the observer rather
than make them reliable and require them (decision 7;
freeside-ai/freeside#2019). With no post-merge run left, no test runs
only after merge.

### 3.2 Teloleo and Straylight

**A command runs the procedure.** Both repositories are private and on a
free organization plan, which provides neither the queue nor branch
protection. The command performs the same procedure as the required
check. It is enough here because merges rarely crowd each other (§5.3)
and one person starts every merge, one landing at a time, though GitHub
enforces none of it (§2.6). When an agent merges, this command becomes
the self-merge skill's merge step, and that person starts one such
landing at a time too.

## 4. Order of Work

Steps 1, 2, and 4 are independent and change no coordination rule.

1. **Name the required check for Freeside** (§3.1). Require the
   always-reporting job over today's PR checks in branch protection.
   Naming it also activates the up-to-date rule, which has no effect
   without a named check. This alone gives the guarantee.
2. **Add the declared-drop test** (§2.3) and make the Go data-migration
   hook match on filename alone (§5.5). Renumber a migration by renaming
   it and updating its references; the grep in §2.3 finds them.
3. **Switch the rules** (§6). Delete contract serialization,
   `exclusive-with`, the scope comparison before starting, the recheck
   when `main` moves, and lanes, and rename the spine the planner
   (decision 6). This requires steps 1 and 2.
4. **Change agent-setup's defaults** (§6) so Teloleo, Straylight, and
   future projects start from rule 1 rather than serial work. A project
   without a required check adopts these defaults only after step 5
   gives it rule 2; until then it keeps its serial rules.
5. **Write the land command** for Teloleo and Straylight and make it the
   self-merge skill's merge step (§3.2).
6. **Delete the race tests and their incident observer** (§3.1).
7. **Raise the number of open units** a step at a time, and measure.
8. **Fix the hot files the measurements identify** (§5.2), one unit per
   row, when rebases conflict in them often enough to matter. The
   migration count row needs no measurement: every migration PR rewrites
   it, so any two open migration PRs conflict there.
9. **Turn on Freeside's merge queue** when ready PRs wait on each other's
   rebases often enough to matter. Add the `merge_group` trigger and
   require the queue (§3.1).

The tracker refresh command (§2.5) blocks none of this work and can be
written at any point.

Measure four things: how often a PR fails at landing and why; how often
a rebase conflicts and in which files; how long a PR waits to land; and
how much work is discarded because a dependency was missed.

## 5. Evidence

### 5.1 What Limits Parallel Work Today

- **Contract work waits by rule.** Two contract units can run together
  only after the spine compares them and records their independence.
  At most two run at once. Wave 8 ran seven contract units in series
  although the links between them recorded no code dependence.
- **Units check each other before starting.** Sessions compare their
  scope with claims and open PRs. Of the last 370 closed units, about 64
  declared an `exclusive-with` pair, and 45 of those were not contract
  units. The count is a rough text match.
- **A few files appear in most merges.** Five files account for 155 of
  the last 266 merges (§5.2).
- **`main` accepts untested combinations.** Of 200 merges measured for
  revision 4, 96 landed on a base newer than the one tested. Branch
  protection enables the up-to-date rule but names no required check,
  so the rule has no effect (§3.1). PRs 1562 and 1565 each added an
  `Environment` field to one struct. They merged 78 seconds apart, and
  `main` failed to compile for 35 minutes. PR 47 removed files PR 48 had
  just landed, and CI stayed green.
- **Open units change the same declarations.** Of 117 Go merges measured
  for revision 4, 14 changed a declaration another unit had rewritten
  while both were open. Seven were in wiring functions such as `run()`,
  which §5.2 removes, and none is recorded as a bug.
- **Authors recheck by hand when `main` moves.** Each merge makes every
  open PR's evidence stale. Authors repeat CI, diff review, and the
  merge-result audit before handoff and again before merging.
- **Trackers need manual upkeep.** Wave 8's tracker body has been edited
  66 times. Ten comments containing charts, on six of sixteen trackers,
  have 74 edits between them. Wave 8's body says all remaining units have
  merged, while its exit-set comment lists two that can start.

The plan keeps what works: a worktree per unit, one PR per unit with a
real merge commit, rebase-only refresh, claims, declared scope, one check
entry point (`scripts/check.sh`), the merge-result audit, and GitHub as
the only store of work state.

### 5.2 The Hot Files

Some files appear in so many PRs that two units are likely to meet in
them. They meet because of how the file is built, in one of the three
patterns below, rather than because their work is related.

These counts show PRs that touched a file, not rebases that conflicted
in it. To measure conflicts, run `git merge-tree` over pairs of PRs that
were open at the same time. The prototypes don't yet do this; step 8
in §4 waits for that count.

| Pattern                              | Where                                                                                              | PRs in 30 days  | Candidate fix                                                                                                                 |
| ------------------------------------ | -------------------------------------------------------------------------------------------------- | --------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Many independent records in one file | `ScreenshotDigests.json`, 3,030 entries                                                            | 71              | One digest file per surface                                                                                                   |
|                                      | `ScreenshotRegressionTests.swift`, 4,051 lines                                                     | 54              | One test file per group of surfaces                                                                                           |
|                                      | `app/SURFACES.md`, one table                                                                       | 60              | One file per surface; the table is rendered on demand                                                                         |
| Wiring in one function               | `run()` and `main()` in `daemon/cmd/freesided/main.go`                                             | 37              | Each subcommand's and subsystem's wiring in its own file, with the explicit list kept in `run()`, whose cleanup order matters |
| A value every change rewrites        | Later migrations listed by name in five test files, up to 70 names each                            | 27 to 29        | Use the existing `migrationsBeforeVersion` helper, which takes a number                                                       |
|                                      | `const want = 98` in `migrate_internal_test.go`                                                    | Every migration | Derive the count from the migration files                                                                                     |
|                                      | Contract digest constant, in one Go file and one Swift file                                        | 26              | Candidate: compute it from the spec at build time                                                                             |
|                                      | `revision:` line and revision log in `docs/plan.md`; the last lines of `docs/history/decisions.md` | 27; 28          | Owner's call (§7, decision 3)                                                                                                 |

- **Measure the first two patterns first.** PRs touching the three app
  files were open at the same time 37, 33, and 26 times in 30 days, and
  17 times for `main.go`. Whether they conflicted is unknown. The digest
  file is also where an agent is most likely to resolve a conflict by
  regenerating it, the failure that ruled out a schema dump (§7,
  decision 5). If measurements identify it as a source of conflicts,
  fix it first.
- **The third pattern prevents contract work from overlapping today.**
  When every change rewrites the same line, any two changes collide,
  whatever their purpose. Contract PRs show no overlap in the history
  only because they were serialized.
- **Migration numbering is deliberate.** Every migration rewrites the
  number on purpose (§2.3). The test lines and count that must also
  change are accidental costs.

Each row would be a separate small unit. None changes behavior or is a
prerequisite for switching the rules.

### 5.3 Merge Rates and Check Times

| Last 30 days | Merges | Within 30 minutes of the previous merge | CI time    |
| ------------ | ------ | --------------------------------------- | ---------- |
| Teloleo      | 13     | 4                                       | 3 minutes  |
| Straylight   | 72     | 26                                      | 6 minutes  |
| Freeside     | 266    | 107                                     | 10 minutes |

On Freeside, 4 of 123 PR commits needed a re-run. Checks finish in 10
minutes at the median and 19 at the 90th percentile, reliable enough to
require. With only the required check, each merge sends every other
ready PR through another rebase and CI run, costing 10 minutes at the
median. With five PRs tested at once, the queue clears 15 or more an hour,
against a peak of 21 merges in a day.

### 5.4 The Race Tests

Of 65 recent runs, 21 were green, 19 failed, and 25 were cancelled by the
next push. Of 25 failures examined, one was a real collision, ten were
intermittent failures in four tests, and 14 were suite timeouts. The
incident threads from 2026-08-09 to 2026-10-07 record no data-race
report. The owner decided on 2026-10-14 to delete the jobs (§3.1,
decision 7).

### 5.5 The Migration Runner

`daemon/internal/store/migrate.go` applies the 98 files in
`daemon/migrations/` by position. It refuses duplicate numbers, gaps,
and changes to an applied file's name or digest. The collision and gap
check requested in freeside-ai/freeside#1712 therefore already exists:
the runner checks the commit that lands. No new check is needed. The
issue's other items,
the protocol in §2.3 and one pilot pair, remain. When the rules switch,
the comment calling numbering "deliberately hostile to parallel
authorship" changes to "silent parallel authorship".

The Go data-migration hook in `migration_attention_pr_reference.go`
matches ten migrations on both version and filename and silently does
nothing otherwise. A rename that misses a Go constant therefore skips
a backfill. The names are constants spread over nine Go files, so
renaming requires updating references wherever they occur; the grep in
§2.3 finds them. The hook should match on name alone, with a test that
every migration name in a Go file exists in the migrations directory.

There is no checked-in schema file, so two migration PRs have nothing to
conflict on but the number. Revision 5's proposed schema dump would also
catch a silent drop, but every migration PR would rewrite it, creating
a conflict an agent could resolve wrongly (§7, decision 5). By a keyword
count, 57 of the 98 migrations only create new tables and can't meet
anything.

### 5.6 The Tracker Refresh Prototype

A 33-line scratch version, `refresh_proto.py`, reproduced the hand-kept
result on all four live charts: wave 8's body, both of its comment
trackers, and freeside-ai/freeside#1616's body. It treats every closed
issue as merged. Four of the last 100 closed issues closed as not
planned, so the real
command must check how an issue closed.

### 5.7 Not Verified

- **None of the proposed changes is built.** Revision 4's prototypes
  measured which declarations survived a concurrent merge and how often
  declared scopes overlapped (`sibling_survival.py`, `decl_overlap.py`).
  Tracker refresh has a scratch version (`refresh_proto.py`); the land
  command and declared-drop test have none.
- **Why 96 of 200 merges landed on an untested base** despite the
  up-to-date rule. GitHub's documentation ties that rule to required
  checks and says a branch with none can merge at any time, which fits
  the measurement. I didn't test the setting itself. Naming a check
  settles it either way.
- **The always-reporting required check** has not been tried here, nor
  has running the audit's scope check in it from the PR body's Scope line.
- **Whether `git range-diff` after a rebase is enough.** The reasoning
  follows from how rebase works; it was not checked against the history.
- **The cause of the race-test timeouts** was never found. A merge that
  slowed the suite would look the same. The deletion (§3.1) makes it
  moot.
- **Hot-file conflicts and fixes.** The counts measure touches, not
  conflicts, and the fixes are not prototyped. For example, I didn't
  check whether screenshot tests can read one digest file per surface.
- **Migration categories.** Counts of migrations that rebuild a table
  or only create tables come from statement keywords, not a reading of
  every file.
- **Whether a dropped column fails an existing test.** This follows
  from the `STRICT` tables and the driver's "no such column" error, but
  I didn't run the case.
- **Whether any test asserts that the Go data-migration cases fire.**
  I found none that names them.
- **Whether the contract digest and plan revision line are deliberate,**
  as the migration number is.
- **A promise of compatibility between app and daemon versions.** I found
  none by search. If one exists, the first bullet in §2.2 needs an
  add-first step.
- **Swift.** The measure of overlapping declarations covered Go only.
- **Teloleo and Straylight:** their Actions usage, which each retest
  spends, and their hot files.
- **Overlap at ten units** is extrapolated from today's rate. The load
  of ten agents testing on one machine is unmeasured.

## 6. What Changes in the Rules

| Stays                                                         | Changes                                                                                                                      | Goes                                                              |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| A worktree per unit, one PR per unit, real merge commits      | After a rebase that conflicted, the author reads `git range-diff` and records the resolution                                 | Pairwise contract assessment                                      |
| The two doors, scheduling and `Handle #N`                     | Rechecking when `main` moves is done by the required check, the queue, or the land command                                   | The cap of two contract units                                     |
| Claims, and a planning reservation as a hold on its own issue | Migrations rely on the number collision, the declared-drop test, and ordinary `starts-after`                                 | `exclusive-with`, and a reservation's reach to other units        |
| `starts-after`, `merges-after`, `stacked-on`                  | The audit's scope check runs on the commit that merges, in the required check once it can                                    | Comparing scope with open work before starting                    |
| Rebase-only refresh and the fold rule                         |                                                                                                                              | The shared-package surface rule                                   |
| Tracker format, wave planning, exit runs, comment trackers    | The spine becomes the planner and keeps only planning: milestones and listings, `starts-after` edges, and the deferral sweep | The author's repeated CI and readiness check after a base advance |
| `kind:contract` as the label that invokes contract review     | The tracker refresh is a command                                                                                             | Runs that happen only after merge                                 |
|                                                               | The agent-setup skill starts a project from rule 1                                                                           | The hand refresh                                                  |
|                                                               |                                                                                                                              | Lanes                                                             |
|                                                               |                                                                                                                              | The race tests and the `ci-race` observer                         |

**Automation replaces the repeated manual recheck.** Today, when the
base moves, the author repeats CI, diff review, and readiness checks.
The merge-result audit runs before handoff and again after any base
advance (AGENTS.md, Integration Ordering; step 3 of the handoff procedure
in `docs/agent-workflow.md`).

With the up-to-date rule and rebase-only refresh, the branch contains
the tip, so the merge result is the branch itself. Reading the branch
means reading the change set the audit prints. The required check reruns
CI on every push, and await-pr-review waits for the reviewer's pass on
each push, a rebase push included, before handoff. Together they replace
the author's repeated CI and readiness check. The review is not part of
the landing procedure in §3: the merge stays with a human by default,
and self-merge already states that no second party reviews before it
merges. After a conflicted rebase, the author still reads the
resolution (§2.4).

The audit's scope check still runs on the commit that merges. An earlier
verdict can't carry forward because a clean rebase can follow an
upstream rename and change the paths touched (§2.4). The scope check
belongs in the required check, which already runs on that commit and
can read the PR body's Scope line. Until it runs there, the author
reruns the audit after each rebase and acts on the verdict. On Teloleo
and Straylight, the land command's CI run performs the recheck.

**The spine becomes the planner.** Today the spine owns contract
assessments, final integration ordering, the cap, trackers, and wave
planning. This plan removes the assessments, ordering, and cap, and
automates tracker refresh. The remaining work is planning: assigning
milestones and listings, writing `starts-after` edges, and sweeping
deferrals. The owner decided on 2026-10-14 to rename the role the
planner in the same change that retires lanes, because "spine" still
implies the integration work that goes, and the lane table, where the
spine is defined, is rewritten anyway.

The rule changes belong in these places:

- **`AGENTS.md`:** Coordination Gates, Contract Changes, the coordination
  model paragraph (its shape, width, cap, and lane-crossing trigger),
  Lane Names, Integration Ordering, the Planning stage's reservation
  reach, and Merge Cleanup.
- **`docs/agent-workflow.md`:** step 3 of the handoff procedure, the
  integration pass when the base moves. Change the agent-setup scaffold
  as well as this file.
- **`docs/coordination.md`:** Lane Glossary, Relationship Types,
  Claiming, Shared-Path Coordination, the routing bullet under Deferral
  Escalation, and the lane bullets under Tracking Issues.
- **`docs/plan.md`:** §5.18 lists contract serialization as an input to
  the daemon's frontier; §15 defines lanes and the spine under
  Coordination Names. Changing either is a material plan change. The
  rule-switch PR carries it and names it as the PR's direct subject,
  which AGENTS.md's Document Gating allows.
- **`docs/tracker-format.md`:** shared across projects and already usable
  without lanes. Edit it where it is maintained, not in this repository.
- **Agent-setup's `references/coordination-discovery.md`:** replace the
  serial default, the rule serializing unknown or ambiguous relations,
  and shape 5's repo-wide serialization of the shared surface with one
  principle. Authorized units in isolated checkouts proceed unless a
  recorded dependency says otherwise, and the landing check is the
  baseline. Freeside's migration mechanics stay in Freeside.

## 7. Decisions for the Owner

1. **Name the required check for Freeside now?** Decided yes,
   2026-10-14. It
   changes no coordination rule and ends untested combinations on
   `main`. Enable the merge queue once measurements show ready PRs
   waiting on each other's rebases (§4, step 9).
2. **Drop `exclusive-with` for every unit, not only contract units?**
   Decided yes, 2026-10-14, without converting existing pairs. A unit that must
   be written against another's result gets a `starts-after`; textual
   conflicts are resolved by rebasing at landing.
3. **Leave the plan's revision line and decision log as they are?**
   Decided yes for now, 2026-10-14. Any two plan changes collide on them, but
   plan changes are gated on purpose. In 30 days, PRs touching the plan
   were open together 11 times and PRs touching the decision log twice.
   Say so if those collisions are a nuisance rather than a safeguard.
4. **Run tracker refresh from a workflow once it has matched the hand
   result for a wave?** Decided no, 2026-10-14. The refresh stays a step
   in merge cleanup, run by the session that merged, because the process
   has enough judgment calls, such as how a unit closed and whether an
   edge changed mid-wave, that an agent should run it.
5. **Catch silent drops with the declared-drop test rather than a
   checked-in schema dump?** Decided yes, 2026-10-14. The test is mechanical and
   adds no file. The dump needs a resolution rule that an agent resolving
   a conflict by regenerating the file would break.
6. **Retire lanes?** Decided yes, 2026-10-14, and the spine is renamed
   the planner in the same change (§6). A lane is a named territory with
   owned paths. Its purpose was to let units in different lanes skip
   scope comparisons before starting. Rule 1 removes those comparisons,
   so the territory no longer has a purpose.

   Lanes also label issues,
   group tracker units under `### lane:<name>` subheads, and determine
   which label a deferred issue gets. The tracker format already works
   without them, and the labels distinguish little: of 330 open issues
   on 2026-10-14, 190 carry `lane:spine`, 18 carry no lane, and 2 carry
   more than one. Declared paths already show where a unit works and
   provide a better search key.

   Subsystem names (signet, gauntlet,
   publish, ward) stay as they are in the plan. Remove only the lane
   layer: the glossary and owned-paths column, `lane:*` labels, tracker
   subheads and `(lane)` qualifier, and the deferral routing bullet.
   A plain topic label would be harmless if the issue list needs one.
   With no glossary, owned paths, or rule, it would not be a lane.

7. **Delete the race tests rather than make them reliable and require
   them?** Decided yes, 2026-10-14. In two months after merge they
   reported no data race and filed eight incidents: suite timeouts,
   intermittent tests, observer faults, and one test's nil-pointer
   panic (§3.1, §5.4). This reverses Freeside's decision of 2026-08-08
   to run them after merge; the assumption that changed is that the run
   would catch regressions worth its cost. Revisit if a data race turns
   up by hand or the daemon gains concurrency the standard suite doesn't
   exercise.

## Revision Notes

Each saved revision carries its own notes. Two rejected alternatives are
recorded only here:

- A script that listed every place another unit had changed and blocked
  merging until each had a Verification line (revision 5).
  `git range-diff` already shows a conflict resolution under rebase-only
  refresh, and nothing the script alone would have caught has happened.
- Moving tracker storage to GitHub's sub-issue and blocked-by links.
  This changed where every tracker's data lives to draw a chart that a
  short command can already keep current.

## Sources

- GitHub, [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue): availability, the `merge_group` trigger, removal on failure.
- GitHub, [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches): availability on private repositories, and the up-to-date rule.
- Winters, Manshreck, and Wright, [Software Engineering at Google](https://abseil.io/resources/swe-book/html/toc.html): a behavior that matters has a test that fails when it is dropped.
- Rails, [Active Record Migrations](https://guides.rubyonrails.org/active_record_migrations.html): a tracked schema file that two migrations on one table both change.
- Revision 4 of this document, kept with the owner's working copies
  outside the repository, for the full measurements (§2), the comparison
  with large-team practice (§3), and its sources.
- Freeside, as read on 2026-10-13 and 2026-10-14:
  - Issues freeside-ai/freeside#1712, freeside-ai/freeside#1829,
    freeside-ai/freeside#1877, freeside-ai/freeside#1152, the eight
    issues labeled `ci-race`, and pull request freeside-ai/freeside#632.
  - The sixteen trackers, freeside-ai/freeside#1613 and
    freeside-ai/freeside#1616 in particular.
  - Branch protection, `.github/workflows/`, pull request history, git
    history, and the labels on all open issues.
  - `daemon/migrations/`, `daemon/internal/store/migrate.go`,
    `migration_attention_pr_reference.go`,
    `encrypted_checkpoint_schema_internal_test.go`, and
    `daemon/cmd/freesided/main.go`.
  - `scripts/merge-result-audit.sh`, `scripts/dev-instance.sh`,
    `scripts/run-real-work.sh`, and `app/scripts/install-mac-app.sh`.
  - `docs/tracker-format.md`, `docs/coordination.md`,
    `docs/agent-workflow.md`, and `docs/plan.md` (§5.18, §15,
    Environments).
  - The `exit-run` and `review-wave` skills, and the agent-setup skill's
    `references/coordination-discovery.md`.
- Two independent reviews, of revisions 7 and 8, and a scratch-repository
  reproduction of a clean rebase that follows an upstream rename,
  2026-10-14.
- Teloleo and Straylight: repository settings and pull request history as
  read on 2026-10-13.
- Measurement scripts, kept with the owner's working copies in
  `parallel-work-prototypes/`: `hot.py` and `where.py` (hot files),
  `prstats.py` (merge rates), `refresh_proto.py` (tracker refresh), and
  revision 4's `sibling_survival.py`, `decl_overlap.py`, and
  `ci_stats.py`.
