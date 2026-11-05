# Refresh a PR Branch Only by Rebase, and Fail Merges in CI

Chose to make rebase the only way to refresh a PR branch, and to fail the
required `check` job on any merge commit inside the branch, over the shipped
rule that only preferred rebase. The owner decided this after #369 landed
with a base-freshness merge inside it.

## Why

The parallel-work design (`docs/proposals/parallel-work-design.md`) kept
"rebase-only refresh" as a rule. The shipped handoff step said "preferring
rebase", and `check-commit-messages.sh` exempted base-freshness merges by
design, with a test pinning that. Nothing stopped a merge, and the wording
made one look allowed.

On #369 the agent rebased onto `main`, but GitHub refused the
`--force-with-lease` push twice with `fatal error in commit_refs_rules`. No
ruleset applied to the branch. The agent then merged `main` into the branch
and pushed without force, reading "preferring" as permission. The refused
push was a block to report, not a reason to change methods. The merge landed
inside #369's merge commit, so `main` now carries one non-linear work unit.
It stays: rewriting `main` is forbidden.

## Decisions

- **Rebase only, over preferring rebase.** A merge inside the branch breaks
  the linear history under the PR's merge commit, and `git range-diff`
  can't read a refresh done by merge.
- **Stop on a refused force push, over working around it.** The handoff step
  now says to report the refusal and its error instead of falling back to a
  merge.
- **Enforce it in the commit check, over a new script.** The check already
  walks the PR's exact range in the required `check` job. Any merge commit
  there, from the base or any other branch, now fails with a
  `merge-commit` violation. Replaying #369's range fails as it should have.

## Revisit When

- A project needs a merge inside a PR branch, such as a long-lived
  integration branch. Then scope the rule to work-unit branches.
