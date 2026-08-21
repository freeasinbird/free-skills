# Guarding post-merge cleanup in one executable sequence

Issue #141 replaces the mechanical program in `merge-cleanup` prose with one
orchestrator. Work started from `af4ce6a`, the merge of PR #145 that resolved
the #105 ordering prerequisite.

## Decisions

- **Put mechanical cleanup in `merge-cleanup.sh`.** The script requires a
  host-qualified base repository, positive PR number, and exact worktree root.
  It propagates that explicit host to every forge call and owns merged-state
  and returned-field validation, worktree layout, remote roles, landing,
  resync, consumer checks, leased deletion, local cleanup, pruning, and one
  uniform disposition ledger. Unknown evidence stops with the same ledger
  shape rather than becoming absence.
- **Resync before remote deletion.** The script implements #105's final order:
  plan and land, re-resolve the base remote, fully fast-forward and verify the
  base, then re-resolve the head destination and run its OID, consumer, push,
  and lease guards immediately before deletion. A late destructive stop leaves
  a current base checkout.
- **Reuse the existing landing decision program.** The orchestrator calls
  `base-landing-plan.sh`; linked head worktrees now stop for owner removal, so
  `worktree-inventory.sh` remains the standalone owner-facing inventory rather
  than an automatic removal precheck. The landing planner adds a NUL result
  format for byte-safe execution while preserving every existing two-position
  invocation, including a remote literally named `--format`.
- **Pin operation destinations, not remote names.** Hosted endpoints returned
  by the forge must identify the requested repository and host. Hostless
  remotes execute against their canonical filesystem destination. Head reads
  and deletion use the one validated effective push URL, so branch-conditioned
  config or a symlink cannot redirect the operation after validation.
- **Constrain prune independently.** Generic `git fetch --prune <remote>` was
  rejected because configured fetch refspecs can target and delete local
  branches. Cleanup uses a canonical URL, an explicit heads-to-tracking
  refspec, prune-tags disabled, and a checked remote namespace. Component
  prefixes and filesystem aliases between remote names stop rather than let
  one remote prune another's refs.
- **Keep policy in the skill.** Issue-close interpretation, project-obligation
  authorization and freshness, review-watch shutdown, retry judgment, and the
  owner-facing summary remain prose. The script reports closing references but
  never closes issues or mutates external trackers.
- **Keep `self-merge` separate.** It shares hardened low-level mechanics but
  has a merge/check phase, pre-merge queue and fork-network policy, different
  stacked-consumer timing, and an intentional `kept_manual` local-branch
  disposition. A shared policy-flag executor would couple distinct contracts
  and make the safer path harder to review. This unit therefore adds only the
  landing planner's result-format compatibility surface.

## Refute-first findings

The independent destructive-path review confirmed and the implementation
fixed these classes:

- A suffix-only `ls-remote` decoy produced exit 0 with no exact row and could
  be mistaken for an absent head. Any non-exact row now stops, including the
  absence path.
- The first fixture harness could continue after setup failures. It now fails
  fast everywhere except the SUT exits each scenario captures deliberately.
- A remote name could change between identity validation and push. The script
  pins the validated literal hosted URL or canonical local destination for
  both the read and leased delete.
- Forge-provided clone endpoints were initially treated as authoritative
  without binding them back to the PR host and requested repository. Both base
  and head endpoint pairs now have that binding, and a fork head equal to its
  own default branch is also rejected.
- A generic prune could obey a destructive configured refspec, while an
  explicit tracking wildcard could still cross nested or case-folding remote
  namespaces. The final scoped-prune guard closes both paths. The reviewer
  reproduced the case-folding overwrite on the host and then verified the
  corrected guard stopped it before fetch.
- A planner option parser shadowed a valid two-position remote named
  `--format`. Format parsing now activates only in the unambiguous four-argument
  form.
- A successful fast-forward command did not prove a post-merge hook left the
  requested base attached and exact. The script rechecks both the symbolic
  branch and OID before any remote deletion.
- A hostless repository argument let ambient CLI host selection query a
  different forge with the same repository and PR number. The public contract
  now requires `host/owner/name`, and every API call receives that host.
- Local branch deletion compared the expected OID before calling `git branch`,
  leaving a race in which another process could advance the ref before a
  force-delete. Cleanup now deletes with `git update-ref` and the expected old
  OID. An independent refute pass showed that separately deleting branch config
  could race a same-name ref recreation, so the script retains that config and
  reports the retention in its local-branch disposition.
- Effective hosted remotes could carry inline credentials that later entered
  fetch, push, or prune argv. Cleanup now disables inherited shell tracing
  before reading remotes and rejects credential-bearing fetch or push URLs,
  including colon-bearing userinfo in hosted SCP syntax.
- The first shared-head query saw only PRs targeting the base repository.
  Cleanup now pages the head commit's associated PRs across the repository
  network and filters them to the exact open head repository, ref, and OID.
  The refute pass also rejected treating repository-scoped PR numbers as
  globally unique, so the current PR exclusion uses base repository plus
  number and the regression gives another target repository the same number.
- Overlapping remote names could direct a base fetch into another remote's
  tracking namespace before the prune-time guard ran. A pre-landing guard was
  still insufficient because `includeIf.onbranch` can reveal another remote
  only after checkout. Cleanup now requires the local base to exist; after
  landing activates branch-conditioned config, the namespace guard runs before
  every remote-tracking fetch and prune. An attempted expected-absent ref update
  still replaced a raced dangling symbolic ref in verification, so absent-base
  creation is left to the owner before cleanup is rerun.
- A second clean inventory could not lease a linked worktree against an ignored
  file created before `git worktree remove`. Cleanup now stops before mutation
  whenever the head remains checked out elsewhere and records that owner
  removal is required.
- Re-reading a head remote after validation let a concurrent config change
  replace the fetch and push destination together. Cleanup now retains the
  validated fetch identity and literal URL, then requires the single push URL
  to identify that same destination. Supporting different authoritative fetch
  and push transports was removed as nonblocking compatibility outside the
  cleanup contract.
- A validated literal command-line URL was still subject to later `insteadOf`
  and `pushInsteadOf` config. Each transport operation now uses a unique
  synthetic URL with a full-length command-scoped rewrite to the validated
  literal. Git's one-pass, longest-match rewriting then prevents broader live
  rules from redirecting the resolved destination.
- The synthetic URL token initially used `BASHPID`, which is unavailable in
  stock macOS Bash 3.2. It now falls back to `$$`; a regression explicitly
  unsets `BASHPID` before exercising the full pinned-transport sequence.
- Scenario directories initially derived their names from passed and failed
  assertion counts, so a skipped case-folding fixture reused its directory in
  the next scenario. A monotonic scenario counter now stays unique across
  skips, with a forced-skip run covering the case on any filesystem.

Suspected regressions from branch-conditioned remote replacement, local
symlink remotes, case-folding namespaces, malformed endpoint facts, and the
new planner format were rejected by discriminating fixtures after the fixes.
The final matrix also advances the remote head in a pre-push hook to prove the
lease refuses the race, and reruns after a post-delete prune stop to prove
partial cleanup is safely retryable.

The later occurrence audit found no ordinary workflow mechanism that changes
remote rewrite config, creates a dangling symbolic base ref, or recreates a
same-named branch between each checked operation. Those cases require another
same-user actor with direct checkout mutation capability. The split-transport
addition was therefore pruned. Endpoint pinning, absent-base refusal, and
branch-config retention remain fail-closed because the destructive-path edit
gate rejected removing their non-atomic guards even under that narrowed threat
model.

The owner accepts that forge consumer state cannot be leased atomically with a
Git ref deletion. In ordinary single-operator cleanup, a new PR opening or
repointing during that interval is low probability, and the forge-pinned head
OID remains available to recreate the branch if it occurs. This is a stated
recoverability path, not a guarantee that consumers cannot race deletion; no
recheck loop or additional deletion machinery was added.

## Verification

- `test-merge-cleanup.sh`: 142 passed, 0 failed, 0 skipped.
- `test-merge-cleanup-landing.sh`: 280 passed, 0 failed.
- `test-merge-cleanup-inventory.sh`: 45 passed, 0 failed.
- `test-self-merge.sh`: 387 passed, 0 failed.
- The independent refute-first review reports no remaining blocking safety
  finding after verifying the corrected code paths.

## Revisit when

Revisit the separate executables only if `self-merge` and post-merge cleanup
adopt identical merge timing, fork-network, stacked-consumer, worktree, and
local-branch policies. Revisit filesystem pinning if Git exposes an operation
that atomically couples destination identity validation with fetch or push;
until then, replacement of the canonical destination itself remains the
namespace race already accepted by the #105 decision.
Revisit local branch-config cleanup when Git exposes a primitive that couples
ref deletion at an expected OID with deletion of its same-named config; until
then, retaining stale config is safer than deleting settings for a concurrently
recreated branch.
Revisit automatic linked-worktree removal when Git exposes an operation that
couples an expected clean inventory with removal, or another enforceable
exclusive-ownership primitive; until then, the worktree owner removes it.
Revisit automatic local-base creation when Git exposes an absence lease that
also treats a dangling symbolic ref at the branch name as existing; until then,
the base owner creates it before cleanup.
