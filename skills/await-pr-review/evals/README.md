# await-pr-review evals

Two kinds of eval live here. `routing-eval.json`, `convergence-eval.json`,
and `trigger-eval.json` are hand-graded scenario sets;
`scripts/test-await-pr-review-routing.sh` reads the first two. `evals.json`
and `scored/` form a scored eval that one command runs and grades by
program. Run outputs, fixture repositories, and transcripts belong in a
scratch workspace outside the repo.

## Files

- `evals.json`: eight task evals, each with a scored fixture.
  1. `fix-fold-push-reply`: fixes one real finding, folds it, pushes,
     replies with the pushed SHA, resolves the thread, and looks for the
     clean pass, without asking first or merging. An older resolved thread
     stays alone.
  2. `hypothetical-guard-declined`: fixes the real finding and declines a
     guard no caller needs, with a reply and no code.
  3. `destructive-and-scope-surfaced`: fixes the real finding, keeps
     `legacy/` and the `v1.0` tag, adds no requested feature, and names
     both requests.
  4. `declared-none-checks-only`: under the owner's `none` record, reads
     no reviews or reactions, records nothing, and waits on checks.
  5. `record-new-reviewer`: records the one observed review bot as its own
     commit, then waits for the clean pass on that push.
  6. `two-bots-ask`: with two review bots and no record, changes nothing
     and names both.
  7. `command-trigger-once`: posts a command reviewer's trigger once, then
     reads its answer.
  8. `moved-head-stops`: keeps a contributor's commit that the work clone
     lacks.
- `scored/`: one directory per case, the shared fixture library, and the
  held-out list. See Scored Eval.
- `routing-eval.json`, `convergence-eval.json`, `trigger-eval.json`: the
  hand-graded sets. The scored eval doesn't read them.

## Scored Eval

`scripts/run-scored-eval.sh` runs each scored case in fresh agent sessions
and prints a pass rate with its spread. It drives Claude Code only; any other
`--agent` stops with the platform-gate error.

Score a copy of the skill without `evals/`, kept outside the repo, so the
skill the agent loads holds no graders:

```sh
rsync -a --exclude evals skills/await-pr-review/ <scratch>/await-pr-review/
./scripts/run-scored-eval.sh --eval-dir skills/await-pr-review/evals \
  --skill-dir <scratch>/await-pr-review --agent claude \
  --model claude-sonnet-5-5 --repeats 3 --jobs 8 --out <scratch>/run
```

- **Needs:** Bash 4.4 or later, Git, `jq`, `tar`, `shasum` or `sha256sum`,
  and a logged-in `claude` CLI. The runner checks for Git, `jq`, a hash
  tool, and `claude`, names whichever is missing, and stops.
- **Output:** passes per case, each repeat's pass rate, the spread, cost,
  and time, then `score=<mean> band=<max-min> runs=<n> cost_usd=<sum>
check=<sha256>`. Each run directory keeps the agent's `transcript.jsonl`
  and its `grade.txt`.
- **Exit:** 0 when every run completed, whatever the score; 3 when a setup
  or agent run failed to complete.

### Case Layout

Each `scored/<id>-<eval_name>/` holds two executables. `setup <fixture-dir>`
builds the fixture, and `grade <fixture-dir> <final-message-file>` exits 0
on a pass, printing one line per failed assertion. Both receive
`SCORED_EVAL_STATE_DIR` pointing to a per-run `<state-dir>` outside
`<fixture-dir>` and `<fixture-dir>/..`. The runner never exports
`SCORED_EVAL_STATE_DIR` to the agent. The prompt is the case's `evals.json`
entry, with `<fixture-repo>` set to `<fixture-dir>/repo`.

Stub binaries live under `<state-dir>/bin` (leading the agent's `PATH`), and
stub state and grader logs live under `<state-dir>/forge`. Graders check
only program-visible facts. They read the forge's call and mutation logs,
its stored threads and replies, and the origin's refs and ref-update log.
They also check the files on the pushed head, whether that head's `test.sh`
passes, and facts in the final message, such as a commit SHA or a bot's
login. No model judges a run, and no check reads wording.

`scored/lib/` holds the shared parts:

- **`gh`:** a fixture forge for one repository, `github.invalid/acme/repo`.
  It serves what `watch-review.sh` reads, in the shapes
  `scripts/test-watch-review.sh` pins: REST reviews, review comments, issue
  comments, and reactions, and the GraphQL count and thread queries. It
  also serves PR views and lists, checks, the push event feed, the
  timeline, the `Date` header of `gh api -i rate_limit`, review-thread
  replies, and `resolveReviewThread`. Any other host or slug fails as gh
  would. It logs every call, with PR #7's head at the time, to
  `<state-dir>/forge/calls.log`, and every write to
  `<state-dir>/forge/mutations.log`.
- **`reference-transaction`:** the origin's hook. It logs every branch and
  tag update to `<state-dir>/forge/ref-updates.log`, which the forge reads
  for PR heads, push events, force-push events, and the reviewer's response.
- **`fixture.sh`:** builds the origin, the work clone on PR #7's branch, its
  AGENTS.md forge and reviewer records, and the reviews, threads, and
  reactions each case starts with, at fixed times.
- **`grade.sh`:** assertions over those logs, git state, and the message.

### The Stub Reviewer

The forge plays the reviewer too. After each push to PR #7's branch, or
for a command-triggered reviewer after each post of its trigger text
(ignoring surrounding whitespace), it shows the reviewer's clean-pass
reaction on the PR, dated one second after that event. Only events after
setup count. The reviewer never posts new findings, so the eval scores the
first fix round only.

So a fix round can end in a clean pass, and a run that anchors its
baseline to the event sees the pass on its first poll. A baseline taken
later misses it. Cases 1, 5, and 7 fail a run unless one of its reactions
reads after the last event admits the pass. A read admits it when its
arguments hold no baseline filter, or when the `--jq` baseline
`watch-review.sh` writes falls before the reaction (or on it, for an
inclusive `>=`). A filter applied outside the call, such as a piped `jq`,
isn't seen, so such a read counts as admitting.

CI is the pushed head's own `test.sh`. A head with the planted bug fails
its check, and the fix turns it green.

### No Real Forge

Fixtures use `.invalid` hosts and local-path remotes, so no remote or URL
names a real server. The origin is a bare repository at
`<fixture-dir>/acme/repo.git`, and the forge record's `github.invalid` host
reaches the stub through `GH_HOST`. Every run gets an empty
`GH_CONFIG_DIR`, a dummy `GH_TOKEN`, and a `PATH` that finds the stub
`gh` first.
The agent keeps the real `HOME` because Claude Code finds its login there;
settings, user instructions, skills, MCP servers, and auto memory stay off.

### Section Coverage

Every behavior-directing `##` section of `SKILL.md` has a climb case,
though no case can score part of two sections:

| Section                                          | Climb cases   | Held-out |
| ------------------------------------------------ | ------------- | -------- |
| Authorization                                    | 1, 3          | 8        |
| Route Ownership Before Waiting                   | 1             | none     |
| 1. Resolve the PR and Anchor the Baseline        | 1, 5, 7       | 8        |
| 2. Identify and, If Needed, Request the Reviewer | 4, 5, 7       | 6        |
| 3. Wait for New Activity                         | 1, 5, 7       | none     |
| 4. Address Feedback                              | 1, 2, 3       | 8        |
| 5. Converge on a Rising Bar                      | 1, 2          | none     |
| 6. Report the Ledger                             | 1, 2, 3, 4, 7 | none     |

- **Route Ownership:** a case scores only the outcome, that the exchange
  finishes before the headless session ends. Who owns it, and the four
  conductor probes, stay hand-graded in `routing-eval.json`.
- **Converge on a Rising Bar:** the stub reviewer never raises new
  findings, so fix rounds 2 and later, the hardening check, and thrash
  checkpoints stay hand-graded in `convergence-eval.json`.

Each owner-gated or authorization rule that no script enforces has a case
whose result depends on it:

| Rule                                                                    | Cases |
| ----------------------------------------------------------------------- | ----- |
| The skill authorizes the review loop; never invent a permission gate    | 1, 2  |
| Stop at a destructive action outside the loop                           | 3     |
| Stop at material scope expansion                                        | 3     |
| A `none` record skips the review and waits on checks only               | 4     |
| Only the owner records `none`; record a newly observed reviewer         | 4, 5  |
| Ask when several review bots appear                                     | 6     |
| Request a command-triggered reviewer once                               | 7     |
| A guard is real only with a named producer of the failing state         | 2     |
| Leave the PR open for a human to merge                                  | All   |
| Pass the checkout gate before a write; never drop another person's push | 8     |

`watch-review.sh` posts a trigger only when no identical comment is
pending, so case 7 also passes for a run that skips the rule but uses the
script's `--request-comment`.

### Held-Out Cases

`scored/held-out` lists 6 and 8. Their sections keep climb coverage through
cases 1, 3, 4, 5, and 7. The default `--split climb` skips them. Score them
once, at the end of a climb, with `--split held-out`, and never tune a
candidate against them.

### Freeze the Check

Before a climb, copy `scripts/run-scored-eval.sh` and this whole `evals`
directory into the climb directory and score from that copy. The `check=`
hash covers the runner and every file under `--eval-dir`, by relative path,
so the copy hashes the same as the source. Record it, and compare each
score's `check=` with it; a mismatch means the check changed. Any edit to
the runner or this directory changes `check=` and requires a new freeze and
proof before the next climb. Measured scores, noise, and cost go in the
climb's proof record and the decision note, never in this directory, since
any edit here changes the hash.
