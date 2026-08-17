# Enforce Commit-Message Quality Mechanically

## Decision

Chose a pull-request CI check over prompt-only commit guidance because recent
agent commits showed that prose conventions alone do not reliably preserve
reviewable history. Adapt the dependency-free checker and fixture suite from
`freeside-ai/freeside`, whose policy matches this repository's existing commit
and review-fix conventions.

The check covers every non-merge feature commit after the merge base. It
exempts merge commits and mainline history incorporated by a base-freshness
merge, so updating a branch cannot make it responsible for pre-existing
messages on `main`.

Rejected a local commit hook as the enforcement boundary because hooks are
optional and agent environments vary. Rejected a Conventional Commits tool
because this repository explicitly uses imperative narrative subjects without
type prefixes, and the small Bash check expresses that policy directly.

Issue: [#133](https://github.com/freeasinbird/free-skills/issues/133)

Revisit when the repository adopts a different history style, or when the
policy grows beyond what a small dependency-free checker can express clearly.
