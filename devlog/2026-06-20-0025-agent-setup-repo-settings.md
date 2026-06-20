# Make agent-setup check the repo settings its conventions assume

agent-setup's canonical `branches`/`pull-requests` text asserts merged
branches auto-delete and merge commits are the only method, but the skill
never ensured the repo was configured that way. The gap bit this repo —
`delete_branch_on_merge` had to be enabled by hand.

## What landed

- New "Repo settings" section in agent-setup SKILL.md listing the two
  settings the conventions depend on (auto-delete head branches,
  merge-commit-only) with gated GitHub `gh` check/enable commands.
- Init step 7 and a new update step 9 both point at it and frame the work
  as offer-to-align, not silent set.

## Decisions

- **Detect → report → offer, never silent mutation.** Repo settings need
  admin the agent may not have; confirm before PATCHing, fall back to
  "here's the desired state and where to toggle it".
- **Generalized, not auto-delete-only.** The sibling setting
  (merge-commit-only) is assumed by `commits` too, so the section covers
  the set of conventions-dependent settings rather than one toggle.
- **Platform gate.** `gh api` is GitHub-only; the section is explicitly
  gated so the platform-agnostic invariant (#2) holds — other forges
  expose equivalent toggles.
- **Used typed `-F` fields** for the boolean PATCH (correct for non-string
  values), not `-f`.

## Deferred

- Branch protection / required-checks setup. The finish-line polls
  required checks, but that depends on CI existing and varies too much to
  encode as a single command. Left out of scope.
