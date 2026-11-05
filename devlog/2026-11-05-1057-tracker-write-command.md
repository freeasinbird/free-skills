# Tracker Write Command

Chose a bundled writer, `skills/merge-cleanup/tracker-write.sh`, over an
agent-composed `gh issue edit` for the shared-format tracker write. This
revises "The command computes and never writes" in
`2026-10-14-1502-tracker-refresh-command.md`: the refresh still never writes,
but the write is no longer the agent's to compose. Issue #370 carries the
contract.

## What Changed

That decision assumed the reconciliation protocol would guard the write. In
practice the agent composed it. On 2026-11-05 it ran the refresh through an
unquoted zsh variable, got exit 64 and an empty file, and an `&&` chain wrote
that file over freeside-ai/freeside#2586. The body was restored from its edit
history. Prose saying "act on the exit code" did not stop a write that one
unchecked shell line could make.

## Decisions

- **A separate writer, not `tracker-refresh.sh --write`.** The read-only
  command keeps its contract, so an agent running it as a check, as
  plan-work-unit does, can't write by accident.
- **Compare body bytes, not `updatedAt`.** An issue's `updatedAt` moves on
  any comment or label change, which would block writes for edits that don't
  touch the tracker text. A same-bytes edit-and-revert goes unnoticed, which
  costs nothing because the text is the same.
- **Project additions go through `--edited` with `--base`.** Freeside's
  **Startable now** rule adds `stacked-on` conditions, so the agent still
  edits the startable set. The command takes only the two startable lines
  from the file and writes the rest from its own refresh. `--base` names the
  unedited refresh the file came from; the contract had only `--edited`, and
  review showed why that was not enough (below).
- **An unguarded write prints as `UNKNOWN` with the `guard` action.**
  `reconciliation-ledger.sh` now accepts an `attempt` after
  `guard unavailable`, never after a failed `pre`. Recording it as
  `COMPLETED`, or under `partial`'s "preserve every verified write", would
  tell the owner to keep a write that might be a wipe.
- **The race is narrowed, not closed.** GitHub updates are unconditional
  (`2026-08-24-0900-optimistic-tracker-writes.md`), so an edit between the
  final reread and the write is overwritten. Edit history is the recovery
  path.

## Refute-First Findings

An independent reviewer tried to make the command write empty, stale, or
wrong text. Confirmed and fixed:

- **An empty flag value dropped the flag.** `--edited "$F"` with `F` unset
  wrote the plain refresh, losing the project rule, and `--comment ""`
  targeted the issue body. Every flag now requires a non-empty value.
- **A stale `--edited` file was written.** A file made before a unit gained
  a `Blocker` line kept that unit startable, and the rerun matched. The
  command now requires `--base` and reports `changed-since-read` when its
  own refresh differs from it.
- **SKILL.md ran the writer for planned no-ops.** That gave a write with no
  valid trace. Only a planned `write` runs the writer now, and the ledger
  matrix pins each documented result-to-trace mapping.
- **A refresh exit 69 passed through.** SKILL.md sends exit 69 to the
  by-hand fallback, the very write this fix removes. Every refresh exit other
  than 0 and 4 is now `refused` with exit 2; exit 69 means only that the
  writer itself could not run.
- **An unguarded write with a moved tip read as `restart`.** That claims
  nothing was written. It is now `incomplete` with the freshness action.

Checked and disproved: an attempt after a failed `pre`, a second write after
an unguarded one, and an unguarded trace reaching `RESULT complete` are all
invalid or impossible. The splice finds the same lines as the refresh, final
newlines are handled, and a CRLF body fails closed. All three reads return
the same bytes. An edit before the refresh's own read is caught, and a single
zsh argument exits 64.

Revisit when GitHub offers a conditional issue or comment update: the guard
reread can then become a compare-and-set.
