---
name: merge-cleanup
description: >-
  Run post-merge cleanup when a user reports "merged", "PR merged, please
  clean up", "PR #N is merged", "just merged it, tidy up", or "the PR landed".
  Safely tidies branches and refs, verifies issue closure, performs documented
  project reconciliation, and stops review watches. Not for merging a PR or
  cleaning up one that remains open.
---

# Merge Cleanup

Clean up after a merged PR: resync the base, delete and prune the merged
branch, verify that close-keyword issues closed, reconcile documented project
obligations, and stop any review watch. A bundled script handles the Git and
forge mechanics. This skill keeps issue-close verification, project-specific
reconciliation, watcher shutdown, and the final owner-facing judgment.

Use it when the user reports a merge (see the description above). The
procedure:

1. Resolve the work unit: the repository, PR number, worktree, and remote
   roles.
2. Run the guarded cleanup script.
3. Interpret the result ledger.
4. Verify issue closure.
5. Reconcile project obligations.
6. Stop the review watch.
7. Summarize for the owner.

## Resolve the Work Unit

Resolve the merged PR from the conversation first. Otherwise identify it with
the forge CLI, but never select an ambiguous candidate.

Establish each of these before invoking the script:

- **Base repository and PR number.** Use `host/owner/name` and the positive
  decimal PR number. Keep the host explicit even when it is `github.com`:
  `GH_HOST` and the CLI's default host are ambient state, not pinned evidence.
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
     inventory lease for safe automatic removal.
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

The last stdout line is always one of these:

- `OK cleanup <json>` at exit 0: every mechanical step completed or was
  already absent.
- `STOP <guard> <json>` at exit 2: evidence was valid enough to refuse the
  next unsafe action.
- `LOOKUP_FAILED <what> <json>` at exit 4: required evidence could not be
  established, so the next action did not run.

Exit 64 means the invocation is invalid. Exit 69 means a required local
executable or bundled helper is unavailable.

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
Git command by hand. If exit 69 prevents the executable from running, stop and
surface the gap rather than reconstructing the destructive sequence from prose.

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

## Reconcile Project Obligations

Run this after issue-close verification, and only when merge verification
passed. An earlier mechanical cleanup stop does not block safe reconciliation,
but continuing requires a freshly resolved current base tip. Report the
mechanical and project results separately.

Inspect the authoritative project instructions that govern the repository for
exactly one fixed-field `Post-merge obligations` record whose fields each
appear exactly once.

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

- Enumerate work per tracker and per transition or refreshed field. Record
  each ordered freshness, guard, attempt, target verification, full-input
  recheck, and disposition event.
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

When project obligations exist, or their required source was unreadable, also
name what ran, what changed, what remains unresolved, and which owner must act.
