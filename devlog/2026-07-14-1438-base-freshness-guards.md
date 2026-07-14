# Prevent stale-base cross-branch reversions

The reusable workflow now treats branch ancestry and integration evidence as
explicit state. This closes the class where an ordinary branch accidentally
inherits an open sibling, then appears clean only because inverse changes cancel
against an obsolete base.

## Decisions

- **Ordinary work starts from a resolved, refreshed default branch.** A
  non-default starting point is allowed only for a declared stacked PR;
  current-checkout state never selects the base implicitly.
- **Concurrency requires checkout isolation.** Separate worktrees or checkouts
  are mandatory for concurrent work units. Platforms without isolated
  checkouts serialize work, preserving the existing capability fallback without
  permitting shared-checkout concurrency.
- **Integration evidence is base-specific.** A base advance invalidates CI,
  full-diff self-review, and readiness. Final handoff records the validated base
  commit and repeats after later base movement; agents surface stale branches
  they do not own instead of rewriting them.
- **Forge enforcement stays optional and consented.** agent-setup detects and
  offers GitHub's stale-branch suggestion and strict required-check freshness,
  but never changes settings silently. Unavailable controls route to the
  canonical manual procedure; merge queues remain optional.
- **await-pr-review guards only its reporting boundary.** The main agent records
  the review cycle's base commit and rechecks it before claiming readiness. A
  changed base returns control to the project's handoff convention; the watcher
  never updates branches, so `watch-review.sh` remains unchanged.

## Rejected

- No path-scope parser or generic component ownership policy, merge-tree
  implementation, mandatory merge queue, incident-specific terminology, or
  merge-cleanup change. Those either solve a different problem or belong to a
  different workflow owner.

## Verification findings

- The read-as-the-agent pass caught an ordering conflict in the first draft:
  it put the final base-freshness pass before the review-watch even though the
  settled watch policy starts immediately on PR open. The final sequence starts
  the watch, anchors it, then refreshes the base; any resulting push advances
  the ordinary watch cycle.
- GitHub's current official API fields match the audit text:
  `allow_update_branch` controls the stale-branch update suggestion and
  `required_status_checks.strict` controls strict base freshness.
- skill-creator validation accepts agent-setup. await-pr-review remains over
  that validator's 1,024-character description limit (1,138 parsed
  characters), a pre-existing condition. The 2026-07-02 trigger evaluation
  explicitly kept that description byte-identical, and this work does not
  change triggering, so the user-requested no-metadata rule wins; both
  frontmatters still parse as YAML.

## Review

- Codex P2 confirmed: the strictness audit promised to preserve app-bound
  required checks but displayed only legacy `contexts`, not
  `checks[].app_id`. The snapshot now includes the full `checks` array. The
  class sweep found no sibling: this is the only required-status-check snapshot
  in agent-setup.
