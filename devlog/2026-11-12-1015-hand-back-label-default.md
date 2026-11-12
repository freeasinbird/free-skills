# Default the Hand-Back Label to needs-rework

The default hand-back label in `land-approved-prs` and `agent-setup` is now
`needs-rework`, not `needs-human`, so that `needs-human` keeps only its
maintainer-only meaning. Issue #378 carries the contract. Downstream
projects inherit this default through both skills.

## What Changed

The old defaults gave one label two meanings. `land-approved-prs` used
`needs-human` for "the lander couldn't land this PR." `agent-setup`'s
tracker format uses it for a maintainer-only unit that agents never select.
The two only conflict once something reworks handed-back PRs automatically,
but nothing in the default setup stops a project from adding that. Freeside
is adding it and splitting its labels in freeside-ai/freeside#3126.

## Decisions

- **Chose `needs-rework` over keeping `needs-human`.** Keeping it leaves an
  automatic rework pass unable to tell a hand-back from a unit reserved for
  the maintainer.
- **Chose `needs-rework` over `handed-back`.** A name for the event is always
  accurate but doesn't say what to do next. Most hand-backs (a rebase
  conflict, red CI, or an unfixable finding) do need rework. For the rest,
  such as a foreign push or an unlanded dependency, the label is slightly
  off, but the hand-back comment says why. Freeside's planned label is
  `needs-rework`, so the defaults match it.
- **No migration for existing projects.** `list-ready.sh` and the
  `agent-setup` label audit read the label from each project's own landing
  record. A record that names `needs-human` keeps working, and eval 61 now
  checks that the audit doesn't report it as drift.
- **The §Hand-Back command takes placeholders.** It names
  `<approval label>` and `<hand-back label>` instead of literals, so an
  agent can't paste a default into a project whose record names other
  labels.
- **This repository's own record is unchanged.** `AGENTS.md` still names
  `needs-human` as the hand-back label; changing it is a separate owner
  decision.

Revisit when Freeside or another downstream project renames its hand-back
label again, or when a hand-back cause that needs no rework becomes common.
