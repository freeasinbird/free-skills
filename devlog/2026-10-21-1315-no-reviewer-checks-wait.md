# No Reviewer Still Waits on Checks

`await-pr-review` no longer stops on an owner's `none` reviewer record. It
skips the review exchange, as before, and still waits for every CI
check on the PR head, fixing a red one. The owner asked for this: a skill
that stopped outright left the CI wait to whoever invoked it, so a run in a
no-reviewer project ended without the green-checks evidence handoff needs.

This revises one decision in
`2026-10-21-0929-declared-no-reviewer.md`, "Stop before routing, not inside
the conductor." Its reason still holds; only the stop changed.

- **Wait in the main agent, not a conductor.** The cost the earlier note
  avoided was the PR-history scan and capped review wait, both of which the
  skip still prevents. A checks wait is one command whose final table is all
  it reads, so a conductor's spawn and brief would cost more than the context
  it protects.
  Rejected: routing a checks-only exchange through the four-probe gate.
- **Wait on every check, confirmed by two matching reads.** Chose all
  checks over required ones because `land.sh` already refuses a head with any
  red check, and a private repository whose plan gates branch protection has
  no required checks at all. Required-only waiting also passed too early in
  practice: on this repository's own PR, `gh pr checks --required --watch`
  exited 0 before the fan-in `markdown-required` job existed. A fan-in job
  appears only after its dependencies finish, so one green read proves
  nothing. The second read follows `land.sh`'s `ci_wait`.
- **Confirm the head before waiting.** `gh pr checks` takes a PR, not a
  commit, so right after a fix push it can report the old head's checks or
  none yet.
- **Leave the canonical handoff unchanged.** With a `none` record, handoff
  step 1 still starts no watch, and step 4 still waits for checks itself.
  The skill change matters when an agent or user invokes the skill directly.

Revisit when a project needs an optional check to stay non-blocking.
