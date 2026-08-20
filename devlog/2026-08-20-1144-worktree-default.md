# Dedicated Worktrees by Default

The managed workflow now makes a dedicated worktree or equivalent isolated
checkout the default for every implementation work unit. This revises the
preference recorded in `2026-07-02-2236-worktree-convention.md`: downstream
managed copies showed that preference wording did not reliably keep single
work units out of the primary checkout.

## Decisions

- **Isolation is the implementation default.** The finish-line checklist puts
  branch creation and isolated checkout selection in the same action, while
  the Branches policy applies the rule to every implementation work unit. This
  leaves planning-only and other declared non-implementation stages under
  their own recorded mutation rules.
- **The primary checkout has two exceptions.** It may be used when an explicit
  user or project instruction requires it, or when the platform cannot create
  another checkout. Either exception requires serialized work on one correctly
  based branch and a report that the default was not followed. It never permits
  concurrent units to share one checkout.
- **The policy stays platform-neutral and capability-gated.** A native
  isolated-checkout feature and plain `git worktree` both satisfy the rule.
  Instruction text remains the available cross-platform enforcement boundary;
  the policy adds no launcher or hook.

The earlier rules remain intact: ordinary branches start from the freshly
updated default-branch tip, intentional stacks declare their non-default base,
concurrent units use any defined forge-visible claim, and worktrees are removed
from outside the checkout after merge.

## Rejected

- **Keep isolation as a preference for single work.** Managed-copy evidence
  showed that this did not establish the intended behavior.
- **Add hard enforcement.** Launchers and hooks are platform-specific and
  outside the repository workflow contract in issue #143.

Revisit when the supported platforms expose one portable isolation mechanism
or when explicit exception reports show that the capability fallback is too
broad or too narrow.
