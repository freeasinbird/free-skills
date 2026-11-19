# Run merge-cleanup.sh Under macOS Bash 3.2

Chose to guard the one empty array expansion in `git_pinned_url` over
requiring Bash 4.4 or later. Issue #406 carries the contract. This note
exists because the change sits on the cleanup path, which the project's
mandatory-note list names.

## Decisions

- **Support 3.2 instead of exiting 69.** The contract allowed either route.
  One guarded expansion makes the whole orchestration suite pass under
  `/bin/bash` 3.2, so a version floor would turn away stock Macs for no gain.
- **Use the `${a[@]+"${a[@]}"}` idiom.** `land-approved-prs/list-ready.sh`
  and `agent-setup/scripts/compare-managed-blocks.sh` already use it. It
  expands to nothing when the array is empty and to the quoted elements
  otherwise, so Bash 4.4 and later see the same argument list as before.
- **Document the 3.2 run instead of adding a CI leg.** CI runs Linux Bash 5.
  The suite header now says how to run it under 3.2, as
  `test-merge-cleanup-refresh.sh` already did.

## Why It Failed Silently

Bash before 4.4 treats an empty `"${a[@]}"` as unbound under `set -u` and
exits. Both callers that pass an empty SSH command, `safe_prune` and the
base-resync fetch, send stderr to `/dev/null`, so the run ended with exit 1,
no message, and no ledger.

## Refute-First Findings

A fresh-context reviewer tried to refute the change, checked under Bash
3.2.57 and 5.3.12:

- **Splitting or globbing: disproved.** An SSH command holding spaces,
  quotes, and `*` stayed one intact argument under both versions, with a
  matching file present and with an empty `IFS`. An empty array added no
  empty argument.
- **Another empty expansion on the path: disproved.** The only other array
  expansion in `merge-cleanup.sh` is `git_pinned_url`'s `args`, which the
  one-placeholder check keeps non-empty. `PLAN_FETCH[0]` is read only when the
  plan forces one entry.
- **Suite catches the regression only under 3.2: confirmed, accepted.** The
  unfixed script passes 179 of 179 under Bash 5 and fails 72 under 3.2. The
  header's run instructions are the mitigation; a 3.2 CI leg is a non-goal.

Revisit when a later edit adds an array expansion that can be empty, or when
CI gains a macOS Bash 3.2 leg.
