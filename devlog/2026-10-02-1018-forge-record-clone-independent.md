# Keeping the forge record clone-independent

Issue #282 removes the **Remote** field from the forge record. The record now
holds the forge host and the `owner/name` slug only. This revises one decision
in `devlog/2026-09-02-0751-forge-record.md`, which wrote the remote's name,
URL, and SSH alias into the record.

## Decisions

- **Chose a record of host and slug only over one that also describes the
  remote.** The 2026-09-02 note assumed the record's reader shares the
  writer's checkout. That assumption is wrong: AGENTS.md is committed, so
  every clone reads it, while the remote name, URL, and SSH alias live in one
  contributor's `.git/config` and `~/.ssh/config`. The owner set this
  contract in #282.
- **The local remote is input, never content.** The audit still reads it to
  derive and validate the record. Validation compares only host and slug, so
  a different remote name, protocol, or alias isn't a disagreement, and two
  contributors get the same result.
- **The `--repo` guidance moved onto the Slug line.** The instruction to pass
  `--repo owner/name` and never derive the owner from a sibling project is
  the rule that stops the wrong-owner guessing #209 was filed for. It applies
  in every clone, so it no longer sits inside a per-clone field.
- **A fork layout records only the base repository's host and slug.** The
  earlier text recorded other remotes by role. A contributor's fork remote is
  local state too.
- **Update mode offers to remove a per-clone line; it never removes one
  silently.** This follows the section's detect, report, offer-to-write rule.
  Downstream records keep the field until their next update run, which is
  harmless because no consumer reads it.

## Rejected

- **Keeping the Remote line as documentation.** It is false in every other
  clone, and it can make one contributor's audit "correct" another's record.
- **Offering a record for every project.** A canonical remote URL already
  states the host and slug, so the trigger stays an aliased base remote.

## Refute-First Findings

A fresh-context reviewer tried to disprove each claim against the diff.

- **Disproved: a rule lets a remote URL or its credential reach the record or
  the transcript.** Every `git remote` read, push URLs included, still passes
  through the unchanged redaction rule, and the section now forbids
  recording the URL at all.
- **Allowed: the removal offer can quote an existing record line that holds a
  URL.** That text is already committed, and the audit only ever wrote
  redacted URLs. The general rule against printing a credential still
  applies, so the section adds no second redaction rule.
- **Disproved: a consumer reads the removed field.** merge-cleanup,
  self-merge, and await-pr-review take only the host and slug, and no script
  or eval pins the Remote line.
- **Disproved: clones with an aliased SSH remote and a canonical HTTPS remote
  disagree.** Both derive the same host and slug.
- **Confirmed and fixed: a clone whose alias `gh` cannot resolve asked the
  user about the host on every update run.** With a record present, the
  audit now compares the slug alone and keeps the recorded host. It reports
  that host as unverified in this clone and asks nothing, because a
  repository that changed hosts under the same slug would otherwise pass as
  validated.
- **Confirmed and deferred: a fork-only clone has no base remote.** The audit
  derives the fork's slug and can offer to rewrite the record to it. This
  predates the change and sits outside #282's contract.
  Follow-up: #283.

Revisit when a consumer needs a per-clone remote fact. That fact belongs in
local, untracked config, not in the record.
