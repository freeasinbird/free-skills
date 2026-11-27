---
name: merge-cleanup
description: >-
  Run post-merge cleanup when a user reports "merged", "PR merged, please
  clean up", "PR #N is merged", "just merged it, tidy up", or "the PR landed".
  Safely tidies branches, refs, and the merged branch's clean worktree,
  verifies issue closure, performs documented project reconciliation, and
  stops review watches. Also sweeps the
  worktrees of merged branches when the owner asks: "sweep the worktrees" or
  "remove the worktrees for merged branches". Not for merging a PR or
  cleaning up one that remains open. The bundled executor requires a
  shell-capable environment with Bash, Git, required utilities, and
  authenticated GitHub CLI for GitHub or a compatible GitHub Enterprise host.
---

# Merge Cleanup

Clean up after a merged PR: resync the base, remove the merged branch's clean
worktree, delete and prune the merged branch, verify that close-keyword issues
closed, reconcile documented project obligations, and stop any review watch.
Bundled scripts do the Git and GitHub mechanics; you keep the judgment.

## Check Prerequisites

Before cleanup, confirm support with read-only checks:

- **Forge:** GitHub or a compatible GitHub Enterprise host, through
  authenticated `gh`. Resolve the host and slug as Resolve the Work Unit
  requires, and keep the actual forge host explicit, not an SSH alias or
  ambient `GH_HOST`; a custom hostname alone doesn't mean unsupported.
  Confirm access with a read-only `gh` lookup pinned to that host.
- **Runtime:** Bash, Git, `gh`, `env`, `sed`, `tr`, `mktemp`, `mkdir`, `rm`,
  `readlink`, `tail`, `grep`, and `find`, checked with `command -v`, plus the
  configured SSH tooling for SSH transport. The reconciliation checker and
  tracker commands also need `awk`.
- **Bundle:** `merge-cleanup.sh` and its adjacent `base-landing-plan.sh`,
  present and executable.

When support is missing, stop before any fetch, switch, retarget, delete, or
prune. Report a non-GitHub forge as unsupported, name the missing tool or
unusable bundle, and report an unknown host or failed authentication as a
lookup gap. Never substitute another forge CLI or rebuild the destructive
sequence from prose.

Then follow the sections in order through Summarize.

## Resolve the Work Unit

Take the merged PR from the conversation, or find it with `gh` against the
explicit host; never pick an ambiguous candidate. Before running the script,
establish:

- **Base repository and PR number,** as `host/owner/name` and a positive
  decimal number. Take the host and slug from the project's forge record when
  AGENTS.md has one naming both, before inferring them from a remote: an SSH
  host alias hides both. Keep the host explicit even for `github.com`.
- **The worktree the cleanup may rewrite:** the one holding the PR's base
  branch, or else the clean feature worktree that can land on the base. Pass
  its root, not a subdirectory.
- **The base and head remote roles.** Inspect configured remotes when
  necessary. A fork PR's differ; never let the base remote stand in for the
  fork that owns the head branch.

Don't fetch, switch, retarget, delete, or prune before the script runs. Those
belong to its one guarded sequence, and a manual prelude invalidates its
initial evidence.

## Run the Guarded Cleanup

Run the script by its skill-directory path, so its bundled helpers stay
available, from your session's own working directory. Don't `cd` into another
checkout first: the script never removes the worktree it started from, and
this keeps it from removing the directory your shell stands in.

```sh
<skill-dir>/merge-cleanup.sh \
  --repo '<host/owner/name>' \
  --pr '<number>' \
  --checkout '<absolute-worktree-root>'
```

- **Optional remotes:** `--base-remote '<name>'` or `--head-remote '<name>'`,
  only after inspecting the mapping and choosing the remote for that role.
  Explicit remotes help ambiguous layouts and hostless local-path fixtures;
  they don't bypass the script's identity, push-target, or lease checks.
- **Keep the head worktree:** `--keep-worktree`, only when the owner says to
  keep the merged branch's worktree. The cleanup then stops for them, as for
  a dirty one.
- **Contract:** `--help` prints it.

The script pins the merged PR's facts, rejects unsafe state, lands on the base
branch and fully resyncs it, then deletes the remote head under an OID lease,
retargeting a same-repository stacked PR first. Last, it deletes the local
head and prunes. The resync finishes before branch deletion, so a later stop
still leaves a current base. It leaves an absent base branch for the owner
to create and keeps `branch.<name>` config.

Before any of that, it removes the linked worktree holding the head branch
only when that worktree is clean, at the merged head, and doesn't hold your
working directory; otherwise it stops `head-worktree-present` for the owner.
Ignored paths that `.worktree-disposables` declares at the base tip, fetched
just before that check, don't make the worktree dirty. A removal that fails
partway can delete the worktree's registration and leave its directory. The
script writes the path down before it removes anything, so that run and every
rerun stop `head-worktree-orphaned` until the directory is gone.

It calls `base-landing-plan.sh --format nul` internally; never parse that
helper's JSON to recreate the sequence. `worktree-inventory.sh
'<absolute-worktree-root>'` runs the linked-worktree guard for diagnosis only.

### Interpret the Result Ledger

The script's last stdout line is the result:

- `OK cleanup <json>` at exit 0: every step completed or was already absent.
- `STOP <guard> <json>` at exit 2: a guard refused the next unsafe step.
- `LOOKUP_FAILED <what> <json>` at exit 4: required evidence couldn't be
  read, so the next step didn't run. An authentication or API failure is a
  lookup failure, not proof of an unsupported forge. A failed git fetch adds
  `stderr`, the first 300 bytes of git's error, after the script retried a
  transient failure.

Exit 64 is a usage error, and exit 69 a missing runtime, which may print no
ledger. Every JSON payload carries every step's disposition. Report completed
ones even when a later step stopped: a resynced base isn't a failed cleanup
because remote deletion was refused. The `worktree` field reads
`removed_clean` after a removal and `owner_removal_required` after the stop.
A `local_branch` value ending in `_config_retained` means the ref is gone and
same-named branch config was left on purpose; don't report it as config
removal.

`STOP bad-record` means the base's `.worktree-disposables` breaks the file's
grammar; the worktree and remote head stay in place until the owner fixes the
file on the base branch and you rerun. `STOP head-worktree-orphaned` means a
head worktree's removal failed partway. Its directory, named in the detail, is
no longer a worktree. Report the path to the owner and never delete it
yourself: only the owner can tell whether what's left matters. Once they
delete it, rerun.

To retry, resolve the stated guard and rerun the whole script with the same
PR and checkout; completed deletions are idempotent. Never run the remaining
Git command by hand. If the script can't run, stop and report the runtime gap.

For a guard's rationale, read only its section; normal cleanup doesn't need
them: `references/hazards.md` §merged-not-ancestor,
`references/hazards.md` §tag-shadow,
`references/hazards.md` §push-refspec-ambiguity,
`references/hazards.md` §checkout-detach,
`references/hazards.md` §leading-hyphen-args,
`references/hazards.md` §worktree-refusals,
`references/hazards.md` §worktree-remove-destroys,
`references/hazards.md` §worktree-partial-remove,
`references/hazards.md` §ignored-file-overwrite,
`references/hazards.md` §status-config,
`references/hazards.md` §prune-refspec-scope, and
`references/hazards.md` §branch-d-upstream.

## Verify Issue Closure

Close keywords can fail silently across repositories, on a non-default base,
or when mistyped. Query each issue in the ledger's `closing_refs` separately,
pinned to its own repository. In one pinned lookup, also read the merged PR's
body and `closingIssuesReferences`, and check the target of any close keyword
the forge missed. Plain `Refs #N` is intentionally non-closing. Surface any
still-open issue for the owner, and don't close it unless they ask. If the lookup can't run, state the
verification gap.

## List the Obligations Found

Before any tracker write, find the project's post-merge obligations and tell
the user the list before acting on it. Read the one `Post-merge obligations`
record in the project's authoritative instructions, and its mechanics
document, as `references/project-obligations.md` §discovery requires. List
each containing tracker with its unit entry and transition, each field to
refresh, the closing issues that select those trackers, and any other
documented post-merge duty, including one this skill may not perform.

Write the same list as a plan file's `policy` and `plan` rows. Name each
shared-format tracker item `#<N>` for an issue body or `#<N>/<comment-id>`
for a tracker kept in a comment, adding `:<label>` when one tracker carries
two items, such as `#835:refresh` and `#835:startable`.

When the policy is `complete` or `absent` and every item is such a tracker in
this repository, run the reconciliation with one command. Type each flag and
value literally:

```sh
<skill-dir>/tracker-reconcile.sh --repo <host/owner/name> --base <branch> --plan '<plan-file>' --trace '<trace-file>'
```

It runs every step under Reconcile Project Obligations, writes the trace from
what it observed, and prints the ledger on stdout; report from that ledger.
Its progress and the tracker scripts' stops go to stderr. Exit codes:

- **0:** `RESULT complete`, and only that.
- **1:** any other ledger result.
- **2:** the ledger rejected the plan or the finished trace.
- **64:** a usage error, an existing `--trace` file, or a plan it doesn't
  run, with no forge call and no trace. It refuses a policy that is
  `unreadable`, `invalid`, or at an `unverifiable` tip, an `unsupported`
  item, and an item name that isn't a tracker in this form.
- **69:** `gh`, `awk`, or a sibling script is missing.

For a refused plan, a tracker in another repository, or a project's own
Startable now rule, generate the trace and fill it in by hand as
`references/project-obligations.md` §state-machine says:

```sh
<skill-dir>/reconciliation-ledger.sh --skeleton '<plan-file>' > '<trace-file>'
```

With a readably absent record, the list is empty: say so in one line, and
still close the trace.

## Reconcile Project Obligations

Run this after issue-close verification, and only when merge verification
passed. An earlier mechanical stop doesn't block reconciliation, but
continuing needs a freshly resolved base tip. Report mechanical and project
results separately.

Before acting, read these, and use `references/project-obligations.md`
§freeside-example only as calibration:

- `references/project-obligations.md` §record
- `references/project-obligations.md` §discovery
- `references/project-obligations.md` §state-machine
- `references/project-obligations.md` §authorization
- `references/project-obligations.md` §trackers
- `references/project-obligations.md` §failures

They hold the full rules; in short:

- **Scope.** Change only known containing trackers, and only by the record's
  documented transitions and listed refreshes, never another external or
  project mutation.
- **Freshness.** Read the record and mechanics from one freshly resolved base
  commit, never the checked-out tree or a stale ref. Recheck the base tip
  before and after every tracker write. Right before a write, reread every
  input that selected the tracker or shaped the edit, and reread them all
  after verifying it. A changed or unverifiable input makes the attempt's
  fields unknown and stops later work.
- **Ledger.** Record each event in the trace as observed, never as expected,
  and close it with a final base-tip observation even when no write ran.
  Check it with `<skill-dir>/reconciliation-ledger.sh '<trace-file>'`;
  `--help` prints the trace contract. Only `RESULT complete` supports a full
  reconciliation claim, and a stable absence stays silent. If the checker
  can't run, apply the state machine by hand and report that gap.

**Shared-format trackers.** These rules and the result table below are the
contract `tracker-reconcile.sh` implements, and the manual path for a plan it
refuses. Write a known containing tracker on the shared
tracker format only with `tracker-write.sh`, never with `gh issue edit` or
`gh api -X PATCH`. Plan the body, and each comment holding both a `flowchart`
fence and a `## Units` heading, with the read-only `tracker-refresh.sh`,
which takes the same `--repo`, `--issue`, and `--comment`: `OK unchanged`
plans a `noop`, and `OK changed` a `write`. Run the write only for a planned
`write`, typing each flag and value literally, never through an unquoted
variable, which zsh passes as one argument:

```sh
<skill-dir>/tracker-write.sh --repo <host/owner/name> --issue <N>
<skill-dir>/tracker-write.sh --repo <host/owner/name> --issue <N> --comment <ID>
```

Name the refresh's reads in
the guard and recheck rows. Copy its one stdout line,
`tracker-write.sh: RESULT <result> guard=<g> attempt=<a> verify=<v> recheck=<r>`,
into the trace, where `none` means the row is absent. After the `guard` row:

| Result (exit)                                  | Trace                                                |
| ---------------------------------------------- | ---------------------------------------------------- |
| `written` (0), `write-failed`/`unverified` (5) | The attempt, verify, and recheck rows as printed     |
| `noop` (0)                                     | `skip`, `already current at write time`, `remaining` |
| `changed-since-read` (3)                       | `skip`, `tracker changed since read`, `remaining`    |
| `lookup-failed` (4)                            | `skip` naming the failed read, `guard`               |
| `refused` (2)                                  | `skip` naming the stderr cause, `ambiguity`          |

- **Report what it leaves.** Put the refresh's ticks, startable set, and
  every item it left in place in the summary. Name each `held` unit with its
  reason, so the owner can fix its Dependencies field.
- **Apply a project's own Startable now rule.** Save the refresh output, copy
  it, and change only the copy's `class ... startable` line and **Startable
  now** bullet. Pass `--edited '<copy>' --base '<refresh-file>'`. When the
  rule would add or remove the class line, report that instead of writing.
- **Handle exits.** On 64, fix the arguments and rerun. Only on 69 or no
  executable, when nothing ran, apply the format's refresh section by hand and
  report the gap; record such a write as `guard unavailable`.

## Stop the Review Watch

If a review watch for the merged PR still runs, stop it with the platform's
background-task, automation, or delegated-watcher control. Without one, say it
will end on activity or at its time cap. Don't invent a cancellation
mechanism.

## Summarize

Lead with the cleanup outcome: what was resynced, deleted, already absent, or
blocked; what merge verification showed; any issue needing manual closure;
and whether a review watch stopped or remains to expire.

Then give each listed obligation its own line, by tracker name, as done,
skipped, or blocked with its reason, taken from the ledger:

- **Done:** a `COMPLETED` row, meaning a verified write, a confirmed no-op, or
  a recomputed report.
- **Skipped:** a `SKIPPED` row whose fresh rereads showed the item no longer
  applied, or an `unsupported` item.
- **Blocked:** an `UNKNOWN` row, or a `SKIPPED` row caused by a source, input,
  tooling, or freshness failure. Quote the ledger's owner action.

An unreadable required source is one blocked line for the whole
reconciliation. Never fold these lines into a general cleanup verdict.

## Sweep Worktrees for Merged Branches

Run a manual sweep only when the owner asks for it in this session, such as
"sweep the worktrees" or "remove the worktrees for merged branches". A
merge-cleanup request alone never authorizes one; the cleanup's own removal of
its head worktree is not a sweep. A landing batch runs only `--remove-landed`,
after it releases its lock, as the land-approved-prs skill says. Don't run a
manual removal while a landing batch runs: its live temporary worktree is a
candidate too. Removal deletes files, ignored ones included.

1. Fetch the base's remote with `git fetch --prune <remote>`: `origin`, or
   the remote of the ref `--base` names. The sweep never fetches.
2. From the primary checkout, run the dry run and show the owner its report:

   ```sh
   <skill-dir>/worktree-sweep.sh
   ```

3. Remove only with the flags the owner names for this run; approval of an
   earlier run doesn't carry over. `--remove` removes the clean candidates;
   `--remove --remove-dirty` also deletes the files the dirty candidates
   list.
4. Report removed and kept worktrees by path. Then rerun merge-cleanup for
   each PR that stopped `head-worktree-present`.

`--base '<ref>'` names the base when `refs/remotes/origin/HEAD` doesn't, and
`--caller-dir '<dir>'` keeps the worktree that holds `<dir>`.
`--remove-head '<branch>' --head-oid '<oid>' --disposables-at '<oid>'` is
merge-cleanup.sh's own call; never run it by hand. `--help` gives the
candidate rules, the `.worktree-disposables` file's grammar (read at the base
commit; an ignored `.DS_Store` is always disposable), each `WORKTREE`
disposition, and the result lines.
