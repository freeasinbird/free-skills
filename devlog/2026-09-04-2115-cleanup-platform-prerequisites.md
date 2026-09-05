# State Cleanup Prerequisites Before Routing

Issue #241 makes the bundled cleanup executor's existing support boundary
explicit before an agent starts cleanup.

## Decisions

- Chose an early read-only prerequisite check over generic forge wording
  because the bundle calls GitHub CLI and requires a shell runtime. Agent
  platform independence does not make the executor portable to every forge.
- Kept compatible GitHub Enterprise hosts within scope without a hostname
  allowlist. Project forge records and explicit `host/owner/name` identity
  still take precedence over SSH aliases and ambient `GH_HOST`.
- Derived the required tools from the executor and landing helper. Their
  missing-tool failures differ, so the prompt does not promise exit 69 or a
  JSON ledger for every unavailable dependency.
- Preserved the [single-executor decision](2026-08-20-1451-merge-cleanup-orchestration.md).
  An unavailable executor stops cleanup; another forge CLI or a manual
  destructive sequence is not a fallback.
- Kept the reconciliation checker's separate `awk` requirement and manual
  state-machine fallback. The deliberate
  [prefilled reconciliation skeleton](2026-09-01-1443-ledger-skeleton.md)
  and requirement to record observations remain unchanged.

## Refute-First Findings

- Confirmed a misleading pointer that could blur forge identification and
  SSH alias validation. The prompt now names the actual forge host as the
  lookup destination and describes `ssh -G` as validation against that host.
- Confirmed that a uniform missing-runtime result promise would be wrong.
  The executor exits before ledger construction for missing Git, `gh`, or
  its landing helper. A missing `find` becomes a lookup failure when the
  helper inspects refs. The wording preserves those distinct outcomes.

## Revisit When

Revisit these prerequisites when the executable bundle changes dependencies,
host compatibility, or failure reporting. A portable forge adapter would need
its own implementation and evidence before expanding the stated support.
