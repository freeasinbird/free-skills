# Add link-skills.sh maintainer install helper

A maintainer running these skills on several mac/Linux machines needs a
low-friction way to install for both Claude Code and Codex and keep them
current as the skills evolve. Symlinks into a single clone give that:
`git pull` refreshes every installed skill in place for both platforms.

## What landed

- `scripts/link-skills.sh` — idempotent reconcile that symlinks each
  `skills/<name>/` into `~/.claude/skills` and `~/.agents/skills`, then
  prunes links for removed skills. `--dry-run` previews, `--adopt` replaces
  copies.
- README: new top-level `## Installation` section — basic copy/symlink of a
  skill dir as the primary instruction, the link helper presented as a
  convenience for all-skills/both-platforms/stay-current. Platform list
  folded into the intro; `Compatibility` and the redundant `Using a skill`
  sections dropped. Closes #10.

## Decisions

- **Reconcile, not a copy loop.** Copies don't track `git pull`; a plain
  add-loop never removes deleted skills. The script adds/refreshes and
  prunes so the installed set mirrors the repo.
- **Scoped, non-destructive prune.** Only removes symlinks pointing into
  this repo whose skill is gone; never deletes real dirs or foreign
  symlinks. Confirmed by dry-run: two pre-existing real dirs in
  `~/.claude/skills` were skipped, not clobbered.
- **Safe default + explicit `--adopt`.** Real dirs / foreign symlinks are
  skipped with an actionable message by default, so the script can't nuke
  unrelated installs. `--adopt` replaces them (e.g. converting an earlier
  copied install into a tracking symlink) — destructive, so it's opt-in,
  the flag being the confirmation. The author's two copied installs are the
  motivating case.
- **mac/Linux only.** User confirmed no Windows. Git Bash `ln -s` silently
  copies and native symlinks need Developer Mode; junctions via a separate
  PowerShell script would be the Windows path if ever needed. Documented in
  the header, not built.
- **This is #10, the non-marketplace version.** Reframed mid-session: the
  symlink/clone install _is_ the installation guidelines #10 asked for, so
  the PR closes it. Native marketplace install (Claude + Codex both have one
  now) becomes a separate future issue — not preannounced in the README
  ("marketplace coming" language deliberately avoided; document only what
  exists).
- **Dropped Compatibility.** It restated the intro and duplicated the
  platform list the Installation section now carries; folded the named
  platforms + links into the intro instead.

## Deferred / not verified

- `shellcheck` not run (not installed locally); `bash -n` + `--dry-run`
  exercised instead.
