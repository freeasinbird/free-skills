---
name: merge-cleanup
description: >-
  Run post-merge cleanup when a user reports "merged", "PR merged, please
  clean up", "PR #N is merged", "just merged it, tidy up", or "the PR landed".
  Safely tidies branches and refs, verifies issue closure, performs documented
  project reconciliation, and stops review watches. Also sweeps the
  worktrees of merged branches when the owner asks: "sweep the worktrees" or
  "remove the worktrees for merged branches". Not for merging a PR or
  cleaning up one that remains open. The bundled executor requires a
  shell-capable environment with Bash, Git, required utilities, and
  authenticated GitHub CLI for GitHub or a compatible GitHub Enterprise host.
---

# Merge Cleanup

Clean up after a merged PR: resync the base, delete and prune the merged
branch, verify that close-keyword issues closed, reconcile documented project
obligations, and stop any review watch. A bundled script handles the Git and
GitHub mechanics. This skill keeps issue-close verification, project-specific
reconciliation, watcher shutdown, and the final owner-facing judgment.

## Check Prerequisites

Use this skill on any agent platform that can run the required bundle. Before
cleanup, establish support through read-only project records and tool checks:

- **Supported forge:** GitHub or a compatible GitHub Enterprise host, accessed
  through authenticated `gh`. Resolve the host and slug as Resolve the Work
  Unit requires. Keep the actual forge host explicit, not the SSH alias or
  ambient `GH_HOST`. A custom hostname alone does not mean unsupported.
  Confirm access with a read-only `gh` lookup pinned to that host.
- **Required runtime:** A shell-capable environment with Bash, Git, `gh`,
  `env`, `sed`, `tr`, `mktemp`, `mkdir`, `rm`, `readlink`, `tail`, `grep`, and
  `find`. Check availability with `command -v`. Git must support the bundle's
  worktree, ref, and transport operations; the landing helper checks
  `git switch` when the branch name requires it. No numeric minimum versions
  are specified. Standalone `jq` and `rg` are not cleanup requirements.
- **Executable bundle:** Check that `merge-cleanup.sh` and its adjacent
  `base-landing-plan.sh` are present and executable. SSH transport also needs
  its configured SSH tooling. The executor uses `ssh -G` to validate aliases
  against the pinned forge host.
- **Stop on missing support:** Report a non-GitHub forge as unsupported, name
  unavailable mandatory tooling or an unusable bundle, and report unknown
  host identity or failed authentication/API evidence as a lookup gap. Stop
  before any fetch, switch, retarget, delete, or prune. Do not substitute
  another forge CLI or reconstruct the destructive sequence from prose.

These requirements apply to the cleanup executor. The separate reconciliation
checker and the tracker refresh command also need `awk`; their manual
fallbacks are described in Reconcile Project Obligations and do not replace
the executor.

Once prerequisites pass, follow this procedure:

1. Resolve the work unit: the repository, PR number, worktree, and remote
   roles.
2. Run the guarded cleanup script.
3. Interpret the result ledger.
4. Verify issue closure.
5. List the obligations found.
6. Reconcile project obligations.
7. Stop the review watch.
8. Summarize for the owner, one line per obligation.

## Resolve the Work Unit

Resolve the merged PR from the conversation first. Otherwise identify it with
`gh` against the explicit host, but never select an ambiguous candidate.

Establish each of these before invoking the script:

- **Base repository and PR number.** Use `host/owner/name` and the positive
  decimal PR number. Take the host and slug from the project's forge record
  when AGENTS.md carries one, an entry naming both, before inferring them from
  a remote: a remote on an SSH host alias hides both. Keep the host explicit
  even when it is `github.com`: `GH_HOST` and the CLI's default host are
  ambient state, not pinned evidence.
- **The exact worktree the cleanup may rewrite.** Prefer the worktree already
  holding the PR's base branch. Otherwise use the clean feature worktree that
  can land on the base. Pass its root, not a subdirectory.
- **The base and head remote roles.** Inspect configured remotes when
  necessary. A fork PR usually has different roles; never let a base remote
  stand in for the fork that owns the head branch.

Do not fetch, switch, retarget, delete, or prune before invoking the script.
Those operations belong to one guarded sequence, and a partial manual prelude
invalidates its initial evidence.

## Run the Guarded Cleanup

Invoke the script by its skill-directory path so its bundled helpers remain
available:

```sh
<skill-dir>/merge-cleanup.sh \
  --repo '<host/owner/name>' \
  --pr '<number>' \
  --checkout '<absolute-worktree-root>'
```

- **Required:** `--repo`, `--pr`, and `--checkout`.
- **Optional remotes:** `--base-remote '<name>'` or `--head-remote '<name>'`,
  only after inspecting the mapping and choosing the remote for that role.
  Explicit remotes help ambiguous layouts and hostless local-path fixtures;
  they do not bypass the script's identity, push-target, or lease checks.
- **Contract:** `--help` and `-h` print it.

The script runs this mechanical sequence in order:

1. **Pin the facts** from the base repository: the merged PR, head OID, base
   branch, head repository, and closing references.
2. **Preflight, then reject unsafe state.** Reject:
   - Dirty or paused worktrees, and linked head worktrees that still require
     owner removal.
   - Dangerous ref aliases and mismatched local refs.
   - Credential-bearing URLs.
   - Overlapping remote-tracking namespaces and ambiguous remote identities.
3. **Land on the base branch and resync it.**
   - Require the local base branch to exist, then land on it through
     `base-landing-plan.sh`.
   - Re-resolve branch-conditioned remotes and tracking state, guard that
     namespace, then fetch and fully fast-forward-resync the base.
   - Leave an absent base for the owner to create before rerunning cleanup:
     Git offers no branch-creation lease that also rejects a concurrently
     created dangling symbolic ref.
4. **Delete the remote head.**
   - Re-resolve the head repository and compare its exact remote branch OID
     with the merged PR head.
   - Pin its validated fetch URL, and require its single push URL to identify
     the same destination.
   - Bind each transport command through a one-use full-length URL rewrite, so
     later live rewrite config cannot redirect it.
   - Check branch consumers, then delete with an OID lease.
   - Retarget a same-repository stacked PR to the merged PR's base and verify
     it first. Stop on a cross-repository stack or a shared head anywhere in
     the repository network.
5. **Delete the local head and prune.**
   - Compare-and-delete the local head at the forge-verified OID, then prune
     the base and distinct head remotes.
   - Stop for the owner to remove a linked head worktree: Git offers no
     inventory lease for safe automatic removal. The owner can remove it with
     the sweep in Sweep Worktrees for Merged Branches.
   - Retain `branch.<name>` config deliberately: Git cannot couple its
     deletion atomically to the expected ref OID.

The base resync deliberately finishes before remote deletion. This ordering
comes from issue #105: a later destructive guard can stop while leaving the
checkout on a current base, without weakening the branch-deletion guards.

`merge-cleanup.sh` calls `base-landing-plan.sh --format nul` internally. That
helper's default format stays JSON for human inspection; `--format json`,
`--format nul`, `--help`, and `-h` are its documented interfaces. Do not parse
the human JSON to recreate the orchestrator. The linked-worktree guard is also
available as `worktree-inventory.sh '<absolute-worktree-root>'`, with `--help`
or `-h`, for diagnosis only.

### Interpret the Result Ledger

When the script emits a result ledger, its last stdout line is one of these:

- `OK cleanup <json>` at exit 0: every mechanical step completed or was
  already absent.
- `STOP <guard> <json>` at exit 2: evidence was valid enough to refuse the
  next unsafe action.
- `LOOKUP_FAILED <what> <json>` at exit 4: required evidence could not be
  established, so the next action did not run.

Exit 64 means the invocation is invalid. Exit 69 covers explicit runtime
checks, including missing Git, `gh`, or the executable landing helper, and
can occur without a JSON ledger. Other missing utilities need not return 69
or produce a ledger. For example, missing `find` causes `LOOKUP_FAILED` at
exit 4 when the landing helper inspects the refs tree. Authentication or API
evidence failures are lookup failures, not proof of an unsupported forge.

Every JSON payload carries the same fields: `repo`, `pr`, `merge`,
`head_branch`, `base_branch`, `head_repo`, `checkout`, `worktree`, `consumers`,
`remote_branch`, `base_resync`, `local_branch`, `prune`, `closing_refs`,
`incomplete_step`, and `detail`. Report completed dispositions even when a
later step stopped. In particular, do not describe a resynced base as a failed
cleanup merely because remote deletion was refused.

Three `local_branch` values are truthful boundaries, not incomplete cleanup:
`deleted_merged_config_retained`, `deleted_verified_config_retained`, and
`already_absent_config_retained`. Each means the named local ref is absent
while any same-named branch config stays untouched, to avoid racing another
Git process that recreates the ref. Do not summarize them as config removal.

A result is retryable after its stated guard is resolved. Re-run the whole
script with the same pinned PR and checkout; its already-absent dispositions
make completed deletion steps idempotent. Do not extract and run the remaining
Git command by hand. If the executable cannot run, stop and report the runtime
gap as Check Prerequisites requires.

For guard rationale or maintenance, read only the relevant section. Normal
cleanup does not require loading this reference.

- `references/hazards.md` §merged-not-ancestor
- `references/hazards.md` §tag-shadow
- `references/hazards.md` §push-refspec-ambiguity
- `references/hazards.md` §checkout-detach
- `references/hazards.md` §leading-hyphen-args
- `references/hazards.md` §worktree-refusals
- `references/hazards.md` §worktree-remove-destroys
- `references/hazards.md` §ignored-file-overwrite
- `references/hazards.md` §status-config
- `references/hazards.md` §prune-refspec-scope
- `references/hazards.md` §branch-d-upstream

## Verify Issue Closure

Merging should close issues named with close keywords, but cross-repository
references, a non-default base, and keyword mistakes can fail silently. Check
closure:

- **Start with the ledger's `closing_refs`.** Query each named issue
  separately and pin the repository from that record, since the reference may
  be cross-repository.
- **Also read the merged PR body and `closingIssuesReferences`** in one pinned
  forge lookup. If the body appears to contain a close keyword the forge did
  not recognize, resolve the apparent target and check it explicitly.
- **Treat plain `Refs #N` mentions as intentionally non-closing.**
- **Surface any still-open issue for the user to close.** Do not close it
  unless the user separately asks; whether the merged work fully resolves it
  is an owner decision.
- **If the forge lookup cannot run, state the verification gap** instead of
  silently omitting this stage.

## List the Obligations Found

Discover the project's post-merge obligations before any tracker write, and
tell the user the list before acting on it. Inspect the authoritative project
instructions that govern the repository for exactly one fixed-field
`Post-merge obligations` record whose fields each appear exactly once. Read it
and its mechanics document as `references/project-obligations.md` §discovery
requires, then list:

- **Each containing tracker**, with the unit entry and transition the
  mechanics name for it.
- **Each field to refresh** in that tracker.
- **The closing issues** whose verified state selects those trackers.
- **Any other documented post-merge duty**, including one the record asks for
  but this skill may not perform.

Write the same list as the trace's `policy` row and `plan` rows. Use `write`
for a transition or refresh to apply, `noop` for one already satisfied,
`report` for derived output such as newly unblocked units, and `unsupported`
for a duty outside this skill's authority. Then generate the trace skeleton:

```sh
<skill-dir>/reconciliation-ledger.sh --skeleton '<plan-file>' > '<trace-file>'
```

The skeleton holds the happy-path events in the checked order. Replace each
expected value with the observed one as the work runs, and replace the block
of an item that did not run with its `skip` row. With a readably absent
record, the list is empty: say so in one line, and still close the trace.
When the record or its mechanics cannot be read, list no items; the skeleton
adds the one umbrella skip, and its reason names the failed source.

## Reconcile Project Obligations

Run this after issue-close verification, and only when merge verification
passed. An earlier mechanical cleanup stop does not block safe reconciliation,
but continuing requires a freshly resolved current base tip. Report the
mechanical and project results separately.

Before acting, read these, and use `references/project-obligations.md`
§freeside-example only as calibration:

- `references/project-obligations.md` §record
- `references/project-obligations.md` §discovery
- `references/project-obligations.md` §state-machine
- `references/project-obligations.md` §authorization
- `references/project-obligations.md` §trackers
- `references/project-obligations.md` §failures

**Scope.** Reconcile only known trackers and authorized fields, observing every
limit in the reference.

- The record can authorize only documented transitions and listed refreshes
  for known containing trackers, never another external or project mutation.
- Readable absence adds no behavior or summary text, but only after its final
  base-tip check stays unchanged. An unreadable required source makes cleanup
  incomplete.

**Freshness and rereads.** Read the record and mechanics from one freshly
resolved immutable base commit, never from the checked-out feature tree or a
stale local ref.

- Recheck that base tip before every tracker write attempt and after its
  tracker verification attempt, even when the write or verification failed.
- Immediately before a tracker write, freshly reread every external object
  whose state selected the tracker or determined the computed edit, not only
  the tracker being written. Then recompute and apply only the documented
  idempotent transition.
- After the target verification, reread that full input set again.
- A changed or unverifiable input makes every otherwise verified field from
  the attempt unknown, and stops later work.
- Successful later verification proves current observed state, not that no
  concurrent edit was overwritten.

**Ledger.** Use `reconciliation-ledger.sh` for every discovery result,
including readable absence.

- Start from the skeleton generated in the previous step, which enumerates
  work per tracker and per transition or refreshed field. Record each ordered
  freshness, guard, attempt, target verification, full-input recheck, and
  disposition event as observed, never as expected.
- Name every external input used by a write, no-op, or report. After all writes
  are dispositioned, reread and recompute no-op and report items before
  recording them fresh.
- Close the trace with a final base-tip observation even when no write ran.
- A stable absence suppresses the complete ledger and stays silent; otherwise
  report the checker's ledger and owner action.
- Only `RESULT complete` supports a full project-reconciliation claim.

Run it as `<skill-dir>/reconciliation-ledger.sh '<trace-file>'`; `--help`, or
`-h`, prints the trace contract. If the executable check cannot run, apply the
referenced state machine manually and report that verification gap.

**Shared-format trackers.** Compute the refresh of a known containing tracker
on the shared tracker format with the bundled command, not by hand. Run it
immediately before the write, once for the body and once for each comment that
holds both a `flowchart` fence and a `## Units` heading:

```sh
<skill-dir>/tracker-refresh.sh --repo <host/owner/name> --issue <N> > '<body-file>'
<skill-dir>/tracker-refresh.sh --repo <host/owner/name> --issue <N> --comment <ID> > '<comment-file>'
```

- **The run is the fresh reread.** It reads the tracker and every unit and
  prerequisite it consults, so record those as the write's inputs. It never
  writes to the forge.
- **Write only a change.** When its stderr line begins `OK unchanged`, record
  a `noop`. Otherwise write stdout with `gh issue edit --body-file` or a
  `gh api -X PATCH` of the comment's `body`, then run the command again; its
  `OK unchanged` is the `verify` and `recheck fresh` evidence.
- **Make no write on a stop.** Exit 2 means the tracker is closed or not on the
  format, and exit 4 names the read, node, or Dependencies entry that failed.
  Record the item unverified and name the cause to the owner.
- **Report what it leaves.** Put its ticks, startable set, and every item it
  left in place in the owner summary. `--help` prints the full contract.
- **It applies the shared rule only.** A project's own additions to
  **Startable now** stay the agent's judgment: apply them to stdout before the
  write; to verify, apply them to the rerun's stdout and compare that with
  the text written. If the command cannot run, apply the format's refresh
  section by hand and report that gap.

## Stop the Review Watch

If a review watch for the merged PR is still running, stop it where the
platform provides a background task, automation, or delegated-watcher control.
If the platform has no such control, say it will self-terminate on activity or
at its time cap. Do not invent a cancellation mechanism.

## Summarize

Lead with the cleanup outcome. State:

- What was resynced, deleted, already absent, or blocked.
- What merge verification showed.
- Any issue needing manual closure.
- Whether a review watch stopped or remains to expire.

Then report every listed obligation on its own line as done, skipped, or
blocked, with its reason. Take each state from the ledger:

- **Done** is a `COMPLETED` row: a verified write, a confirmed no-op, or a
  recomputed report.
- **Skipped** is a `SKIPPED` row whose fresh rereads showed the item no longer
  applied, or an `unsupported` item outside this skill's authority.
- **Blocked** is an `UNKNOWN` row, or a `SKIPPED` row caused by a source,
  input, tooling, or freshness failure. Quote the ledger's owner action.

An unreadable required source is one blocked line for the whole
reconciliation. Never fold these lines into a general cleanup verdict; the
user should see each tracker by name.

## Sweep Worktrees for Merged Branches

Run the sweep only when the owner asks for it in this session, such as "sweep
the worktrees" or "remove the worktrees for merged branches". A merge-cleanup
request or a landing batch never authorizes it. Removing a worktree deletes
files: `git worktree remove` without `--force` still deletes ignored ones.

Fetch the base's remote first, with `git fetch --prune <remote>`: `origin`
by default, or the remote in the ref `--base` names. The sweep never fetches,
so a branch merged on the forge but not yet fetched looks unmerged and stays.
Then run it from the primary checkout, starting with the dry run:

```sh
<skill-dir>/worktree-sweep.sh
```

Show the owner the report. Remove only with the flags the owner names for this
run; approval of an earlier run doesn't carry over:

- `--remove` removes the clean candidates.
- `--remove --remove-dirty` also removes the dirty candidates, deleting the
  files their lines list. `--remove-dirty` alone is a usage error.
- `--base '<ref>'` names the branch merged branches land on, when
  `refs/remotes/origin/HEAD` doesn't, such as a remote not called `origin`.
- `--help` or `-h` prints the full contract.

```sh
<skill-dir>/worktree-sweep.sh --remove
<skill-dir>/worktree-sweep.sh --remove --remove-dirty
```

A candidate is a linked worktree on a branch merged into the base, or a
detached worktree that a dead `land` run left at its exact
`land-wt.XXXXXX/wt` template (six letters or digits).
Don't run a removal while a landing batch is running: the batch's live
temporary worktree is a candidate too.

Each registered worktree gets one `WORKTREE <disposition> <json>` line:

- **`removed`:** This run removed it.
- **`clean`:** A candidate whose removal deletes nothing but its checkout.
- **`dirty`:** A candidate holding untracked, modified, ignored, or
  index-flagged files, a paused operation, or a detached HEAD that no ref
  holds; its line lists each file. A
  dirty branch whose line says no landing merge was found is never removed: a
  branch with no commits of its own looks the same and may be work in
  progress.
- **Never a candidate:** `primary`, `self`, `locked`, `prunable`,
  `holds-worktree`, `holds-submodule`, `holds-repository`, `base-branch`,
  `unmerged`, `unresolved-branch`, `unreadable`, `redirected`, and
  `detached-other`. The line's reason says why. A `prunable` entry is reported, never pruned.

The last line is `OK sweep <json>` with counts, `STOP no-base`,
`STOP remove-failed` when git refused a removal and nothing after it was
attempted, or `LOOKUP_FAILED <what>` when a read failed. Report removed and
kept worktrees by path. The sweep rechecks each worktree right before removing
it, which narrows a race with another process but can't close it.

Afterwards, rerun merge-cleanup for each PR that stopped
`head-worktree-present`.
