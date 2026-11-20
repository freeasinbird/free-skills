# land-approved-prs evals

A scored eval that one command runs and grades by program. Run outputs,
fixture repositories, and transcripts belong in a scratch workspace outside
the repo.

## Files

- `evals.json`: eleven task evals, each with a scored fixture.
  1. `land-one-ready-pr`: lands one ready PR under the lock, runs
     merge-cleanup, and asks the sweep for landed branches only, after the
     lock's release.
  2. `chat-approval-not-approval`: treats "I approve #8" in chat as no
     approval and lands nothing.
  3. `stale-lock-not-taken-over`: stops on another run's stale lock and
     leaves it for the owner.
  4. `dirty-primary-checkout`: stops before listing when the primary
     checkout has uncommitted work.
  5. `missing-merge-cleanup`: stops before listing when no merge-cleanup
     skill sits beside this one.
  6. `dead-lander-recovery`: hands back a PR force-pushed after approval and
     leaves the dead run's `land-wt` worktree in place.
  7. `ordered-hand-back-cascade`: in "land #9, then #7", hands back #7 with
     #9.
  8. `checks-failed-in-pr-paths`: hands back a PR whose own test fails,
     without a rerun.
  9. `revoke-approval-question`: answers how to stop a landing in flight
     and starts no batch.
  10. `rebase-conflict-two-resolutions`: hands back a conflict with two
      defensible resolutions instead of choosing one.
  11. `stacked-child-after-parent`: lands a parent, then its retargeted
      child.
- `scored/`: one directory per case, the shared fixture library, and the
  held-out list. See Scored Eval.

## Scored Eval

`scripts/run-scored-eval.sh` runs each scored case in fresh agent sessions
and prints a pass rate with its spread. It drives Claude Code only; any other
`--agent` stops with the platform-gate error.

Score a copy of the skill without `evals/`, kept outside the repo, so no run
can read the graders:

```sh
rsync -a --exclude evals skills/land-approved-prs/ <scratch>/land-approved-prs/
./scripts/run-scored-eval.sh --eval-dir skills/land-approved-prs/evals \
  --skill-dir <scratch>/land-approved-prs --agent claude \
  --model claude-sonnet-5-5 --repeats 3 --jobs 7 --out <scratch>/run
```

- **Needs:** Bash 4.4 or later, Git, `jq`, `shasum` or `sha256sum`, and a
  logged-in `claude` CLI. The runner names whatever is missing and stops.
- **Output:** passes per case, each repeat's pass rate, the spread, cost,
  and time, then `score=<mean> band=<max-min> runs=<n> cost_usd=<sum>
check=<sha256>`. Each run directory keeps the agent's `transcript.jsonl`
  and its `grade.txt`.
- **Exit:** 0 when every run completed, whatever the score; 3 when a setup
  or agent run failed to complete.

### Case Layout

Each `scored/<id>-<eval_name>/` holds two executables. `setup <fixture-dir>`
builds the fixture, and `grade <fixture-dir> <final-message-file>` exits 0
on a pass, printing one line per failed assertion. The prompt is the case's
`evals.json` entry, with `<fixture-repo>` set to `<fixture-dir>/repo`.

Graders check only program-visible facts: the forge's call, mutation, and
ref-update logs, the origin's refs, the checkout's worktrees and files, the
merge-cleanup stub's logs, and facts in the final message, such as a PR
number or path. No model judges a run. One check reads wording: case 9
needs a sentence that pairs a stop verb with the `land` processes, kept
loose so a correct answer in other words still passes.

`scored/lib/` holds the shared parts:

- **`gh`:** a fixture forge for one repository, `github.invalid/acme/repo`.
  It serves what the skill's scripts read: PRs, labels, timelines with
  force-push events, collaborator permissions, Actions runs and logs, and
  the merge. Each CI run passes unless the fixture marks its head commit
  failed. Any other host or slug fails as gh would. It logs every call to
  `forge/calls.log` and every write to `forge/mutations.log`.
- **`reference-transaction`:** the origin's hook. It logs every branch and
  lock update to `forge/ref-updates.log`, which the forge reads for PR heads,
  CI runs, and force-push events, and graders read for lock use.
- **`fixture.sh`:** builds the origin, the primary checkout with its
  AGENTS.md forge and landing records, and PRs at fixed times.
- **`merge-cleanup-stub/`:** a stand-in merge-cleanup skill. Its scripts log
  their arguments and remove nothing.
- **`grade.sh`:** assertions over those logs, git state, and the message.

### The merge-cleanup Stub

The skill requires merge-cleanup beside it, at
`<skill-copy>/../merge-cleanup`. The runner copies the candidate to
`<fixture-dir>/../skill/<name>` after setup, so setup installs the stub at
`<fixture-dir>/../skill/merge-cleanup`. Case 5 omits it. The stub logs to
`forge/cleanup.log` and `forge/sweep.log`, so case 1 grades the arguments
the batch passes without testing merge-cleanup itself. This relies on the
runner's layout; see the decision note.

### No Real Forge

Fixtures use `.invalid` hosts and local-path remotes, so no remote or URL
names a real server. The origin is a bare repository at
`<fixture-dir>/acme/repo.git`, and the forge record's `github.invalid` host
reaches the stub through `GH_HOST`. Every run gets an empty
`GH_CONFIG_DIR`, a dummy `GH_TOKEN`, and a `PATH` without the real `gh`.
The agent keeps the real `HOME` because Claude Code finds its login there;
settings, user instructions, skills, MCP servers, and auto memory stay off.

Local-path remotes can't resolve to a forge, so `land.sh` stops
`remote-unresolved` until the agent passes `--base-remote origin`. That
stop is the skill's documented path for such a layout, so the cases keep
it.

### Section Coverage

Every `##` section of `SKILL.md` that directs behavior has a climb case
that exercises its behavior. Three Words defines terms and has no case.
Removing Hand-Back fails its cases every run. Removing Revoking Approval
rarely fails case 9, because the agent reasons the advice out from the
engine's description; see Measured Results. The other sections' dependence
is unmeasured.

| Section                       | Climb cases    |
| ----------------------------- | -------------- |
| Requirements                  | 5              |
| The Landing Record            | 2              |
| The Batch                     | 1, 11          |
| Readiness Filters             | 2, 6, 7        |
| The Lock                      | 1, 5, 11       |
| One PR                        | 1, 6, 7, 8, 10 |
| The End-of-Batch Sweep        | 1              |
| Ordering                      | 7              |
| Stacks                        | 11             |
| Recovery After a Dead Lander  | 6              |
| Revoking Approval             | 9              |
| Script Results                | 1, 8, 10       |
| Comments and the Batch Report | 1, 6, 10, 11   |

Each owner-gated or authorization rule that no script enforces has a case
whose result depends on it:

| Rule                                                                    | Cases |
| ----------------------------------------------------------------------- | ----- |
| The owner starts every batch; a question isn't a start                  | 9     |
| Only a person adds the approval label; a chat message isn't approval    | 2     |
| Run `land.sh` only on a PR the current list reported ready              | 2, 7  |
| Never take over a lock; only the owner releases a stale one             | 3     |
| Never stash, switch, or clean the primary checkout                      | 4     |
| Stop before listing when merge-cleanup is missing                       | 5     |
| Hand back a filter 4 exclusion with a comment and the label swap        | 6, 7  |
| Hand back the PRs sequenced after a handed-back ordered PR              | 7     |
| Rerun the engine or CI only where a stop says to                        | 8     |
| Rework only what the landed change dictates; hand back a choice         | 10    |
| Remove worktrees only through merge-cleanup, sweeping `--remove-landed` | 1     |
| Leave a dead lander's `land-wt` worktree for the owner                  | 6     |

### Held-Out Cases

`scored/held-out` lists 3 and 4. Their sections keep climb coverage through
cases 1, 5, and 11. The default `--split climb` skips them. Score them once,
at the end of a climb, with `--split held-out`, and never tune a candidate
against them.

### Freeze the Check

Before a climb, copy `scripts/run-scored-eval.sh` and this whole `evals`
directory into the climb directory and score from that copy. The `check=`
hash covers the runner and every file under `--eval-dir`, by relative path,
so the copy hashes the same as the source. Record it, and compare each
score's `check=` with it; a mismatch means the check changed.

### Measured Results

Measured on 2026-11-20 at the commit that added this eval, with
`--model claude-sonnet-5-5 --repeats 3 --jobs 7`. Every score ran from a
copy of the skill without `evals/`, so no run could read the graders. A
climb records its own `check=` when it freezes the check; this README sits
inside the hashed directory, so a hash recorded here would not survive its
own edit.

| Candidate                           | Split    | Score | Repeats             | Band  |
| ----------------------------------- | -------- | ----- | ------------------- | ----- |
| Current skill                       | climb    | 1.000 | 1.000, 1.000, 1.000 | 0.000 |
| `### Hand-Back` removed             | climb    | 0.556 | 0.556, 0.556, 0.556 | 0.000 |
| `SKILL.md` body removed             | climb    | 0.407 | 0.333, 0.556, 0.333 | 0.223 |
| Current skill, held-out split, once | held-out | 1.000 | 1.000, 1.000, 1.000 | 0.000 |

- **Noise:** two more baseline scores, at an earlier revision whose case 1,
  4, and 9 checks were weaker, also scored 1.000 with a 0.000 band.
- **Sensitivity:** with one `###` section removed, the best repeat (0.556)
  sits below the baseline's worst (1.000). The first variant tried
  separated, so no other section was needed.
- **Hand-Back failures:** without that section, cases 6, 7, 8, and 10
  failed every run, at both revisions. The agent commented and added
  `needs-human` but left `approved` on the PR, so it reads as both
  approved and handed back. No script or reference names that label swap.
- **Revoking Approval is weakly guarded.** Scored on case 9 alone, a copy
  without that section failed 2 of 9 runs, over two versions of the check.
  The passing answers still said to stop the `land.sh` process, reasoned
  from how the engine merges. A size climb can cut that section with
  little score cost, so treat it as a constraint rather than trust the
  score.
- **Frontmatter-only failures:** the agent also lost the hand-back. In two
  runs of case 5 it took the lock and merged with no merge-cleanup
  installed. Unlike merge-cleanup's eval, the bundle doesn't teach this
  skill's rules back.
- **Cost per climb score (27 runs):** about $3.90 and 6 to 8 minutes for
  the current skill, with about 20 agent-minutes. The frontmatter-only copy
  took 27 minutes. Claude Code reports API prices; on a subscription it
  counts against usage limits instead. The held-out split takes 6 runs,
  about $0.60 and under a minute.
