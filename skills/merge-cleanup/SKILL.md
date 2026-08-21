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

Use the bundled orchestrator for Git and forge mechanics. Keep issue-close
verification, project-specific reconciliation, watcher shutdown, and the final
owner-facing judgment in this skill.

## Resolve the Work Unit

Resolve the merged PR from the conversation first. Otherwise use the forge CLI
to identify it, but do not select an ambiguous candidate. Establish:

- The base repository as `host/owner/name` and the positive decimal PR
  number. Keep the host explicit even when it is `github.com`; `GH_HOST` and
  the CLI's default host are ambient state, not pinned evidence.
- The exact worktree the cleanup may rewrite. Prefer the worktree already
  holding the PR's base branch. Otherwise use the clean feature worktree that
  can land on the base. Pass its root, not a subdirectory.
- The base and head remote roles. Inspect configured remotes when necessary.
  A fork PR usually has different roles; never let a base remote stand in for
  the fork that owns the head branch.

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

The required options are `--repo`, `--pr`, and `--checkout`. Use
`--base-remote '<name>'` or `--head-remote '<name>'` only after inspecting the
mapping and choosing the remote for that role. Explicit remotes are useful for
ambiguous layouts and hostless local-path fixtures; they do not bypass the
script's identity, push-target, or lease checks. `--help` and `-h` print the
contract.

The script performs the mechanical sequence in this order:

1. Pin the merged PR, head OID, base branch, head repository, and closing
   references from the base repository.
2. Reject dirty or paused worktrees, linked head worktrees that still require
   owner removal, dangerous ref aliases, mismatched local refs,
   credential-bearing URLs, overlapping remote-tracking namespaces, and
   ambiguous remote identities.
3. Require the local base branch to exist, then land on it through
   `base-landing-plan.sh`. Re-resolve branch-conditioned remotes and tracking
   state, then guard that namespace before fetching and fully
   fast-forward-resyncing the base. The owner creates an absent base before
   rerunning cleanup because Git offers no branch-creation lease that also
   rejects a concurrently created dangling symbolic ref.
4. Re-resolve the head repository, compare its exact remote branch OID with
   the merged PR head, pin its validated fetch URL, require its single push URL
   to identify the same destination, and bind each transport command through a
   one-use full-length URL rewrite so later live rewrite config cannot redirect
   it. Check branch consumers, then delete with an OID lease.
   A same-repository stacked PR is retargeted to the merged PR's base and
   verified first. A cross-repository stack or shared head anywhere in the
   repository network is a stop.
5. Compare-and-delete the local head at the forge-verified OID, then prune the
   base and distinct head remotes. A linked head worktree stops cleanup for its
   owner to remove because Git offers no inventory lease for safe automatic
   removal. The script deliberately retains `branch.<name>` config because Git
   cannot couple its deletion atomically to the expected ref OID.

The base resync deliberately finishes before remote deletion. This is the
ordering established by issue #105: a later destructive guard can stop while
leaving the checkout on a current base, without weakening the branch deletion
guards.

The orchestrator calls `base-landing-plan.sh --format nul` internally. Its
default format remains JSON for human inspection; `--format json`,
`--format nul`, `--help`, and `-h` are its documented interfaces. Do not parse
the human JSON to recreate the orchestrator. The linked-worktree guard remains
available as `worktree-inventory.sh '<absolute-worktree-root>'`, with `--help`
or `-h`, for diagnosis only.

### Interpret the Result Ledger

The last stdout line is always one of:

- `OK cleanup <json>` at exit 0: every mechanical step completed or was
  already absent.
- `STOP <guard> <json>` at exit 2: evidence was valid enough to refuse the
  next unsafe action.
- `LOOKUP_FAILED <what> <json>` at exit 4: required evidence could not be
  established, so the next action did not run.
- Exit 64: the invocation is invalid. Exit 69: a required local executable or
  bundled helper is unavailable.

Every JSON payload has the same fields: `repo`, `pr`, `merge`, `head_branch`,
`base_branch`, `head_repo`, `checkout`, `worktree`, `consumers`,
`remote_branch`, `base_resync`, `local_branch`, `prune`, `closing_refs`,
`incomplete_step`, and `detail`. Report completed dispositions even when a
later step stopped. In particular, do not describe a resynced base as a failed
cleanup merely because remote deletion was refused.

The `local_branch` values `deleted_merged_config_retained`,
`deleted_verified_config_retained`, and `already_absent_config_retained` are
truthful boundaries, not incomplete cleanup: the named local ref is absent,
while any same-named branch config remains untouched to avoid racing another
Git process that recreates the ref. Do not summarize these dispositions as
config removal.

A result is retryable after its stated guard is resolved. Re-run the whole
script with the same pinned PR and checkout; its already-absent dispositions
make completed deletion steps idempotent. Do not extract and run the remaining
Git command by hand. If exit 69 prevents the executable from running, stop and
surface the gap rather than reconstructing the destructive sequence from
prose.

For guard rationale or maintenance, read only the relevant section:
`references/hazards.md` §merged-not-ancestor,
`references/hazards.md` §tag-shadow,
`references/hazards.md` §push-refspec-ambiguity,
`references/hazards.md` §checkout-detach,
`references/hazards.md` §leading-hyphen-args,
`references/hazards.md` §worktree-refusals,
`references/hazards.md` §worktree-remove-destroys,
`references/hazards.md` §ignored-file-overwrite,
`references/hazards.md` §status-config,
`references/hazards.md` §prune-refspec-scope, or
`references/hazards.md` §branch-d-upstream. Normal cleanup does not require
loading that reference.

## Verify Issue Closure

Merging should close issues named with close keywords, but cross-repository
references, a non-default base, and keyword mistakes can fail silently.

- Start with the ledger's `closing_refs`. Query each named issue separately
  and pin the repository from that record, since the reference may be
  cross-repository.
- Also read the merged PR body and `closingIssuesReferences` in one pinned
  forge lookup. If the body appears to contain a close keyword the forge did
  not recognize, resolve the apparent target and check it explicitly.
- Treat plain `Refs #N` mentions as intentionally non-closing.
- Surface any still-open issue for the user to close. Do not close it unless
  the user separately asks; whether the merged work fully resolves it is an
  owner decision.
- If the forge lookup cannot run, state the verification gap instead of
  silently omitting this stage.

## Reconcile Project Obligations

After issue-close verification, and only when merge verification passed,
inspect the authoritative project instructions that govern the repository for
exactly one fixed-field `Post-merge obligations` record whose fields each
appear exactly once. An earlier mechanical cleanup stop does not prevent safe
reconciliation, but continuing requires a freshly resolved current base tip;
report the mechanical and project results separately.

Before acting, read `references/project-obligations.md` §record,
`references/project-obligations.md` §discovery,
`references/project-obligations.md` §state-machine,
`references/project-obligations.md` §authorization,
`references/project-obligations.md` §trackers, and
`references/project-obligations.md` §failures. Use
`references/project-obligations.md` §freeside-example only as calibration.

Readable absence adds no behavior or summary text only after its final base-tip
check stays unchanged; an unreadable required source makes cleanup incomplete.
Reconcile only known trackers and authorized fields, observing every limit in
the reference. In particular, read the record and mechanics from the same
freshly resolved immutable base commit, never from the checked-out feature tree
or a stale local ref, and recheck that base tip before every tracker write
attempt and after its tracker verification attempt, even when the write or
verification failed. The record can authorize only guarded transitions and
listed refreshes for known containing trackers, never another external or
project mutation. The mutation guard or exclusive-writer window must cover
every external object whose state selected the tracker or determined the
computed edit, not only the tracker being written.

Use `reconciliation-ledger.sh` for every discovery result, including readable
absence. Enumerate work per tracker and per transition or refreshed field,
record each ordered freshness, guard, attempt, verification, and disposition
event. Name every external input used by a write, no-op, or report; after all
writes are dispositioned, reread and recompute no-op and report items before
recording them fresh. Then close the trace with a final base-tip observation
even when no write ran. A stable absence suppresses the complete ledger and
stays silent; otherwise report the checker's ledger and owner action. Only
`RESULT complete` supports a full project-reconciliation claim. Run it as
`<skill-dir>/reconciliation-ledger.sh '<trace-file>'`; `--help`, or `-h`, prints
the trace contract. If the executable check cannot run, apply the referenced
state machine manually and report that verification gap.

## Stop the Review Watch

If a review watch for the merged PR is still running, stop it where the
platform provides a background task, automation, or delegated-watcher control.
If the platform has no such control, say it will self-terminate on activity or
at its time cap. Do not invent a cancellation mechanism.

## Summarize

Lead with the cleanup outcome. State what was resynced, deleted, already
absent, or blocked; what merge verification showed; any issue needing manual
closure; and whether a review watch stopped or remains to expire. When project
obligations exist or their required source was unreadable, also name what ran,
what changed, what remains unresolved, and which owner must act.
