# Refuse link-skills.sh Targets That Resolve Into the Clone

Chose to make `scripts/link-skills.sh` resolve every target skills directory
to a physical path and refuse the whole run when any target is the clone or
sits inside it. Issue #469 carries the contract. A target such as
`~/.claude/skills -> <clone>/skills` made `--adopt` run `rm -rf` on the
clone's own skill directories, because each `$dest/<name>` was the real
source directory.

## Decisions

- **Refuse in every mode, not only `--adopt`.** A plain run writes links
  inside the clone through the same target, and a dry run that passes where
  the real run would refuse misleads. Rejected: guarding only the `rm -rf`
  branches, which leaves the writes.
- **Check every target before changing any.** One refused target exits 1
  before the reconcile loop, so a half-applied run can't leave some targets
  linked and others not. The cost is that one bad target blocks the good
  ones until the owner fixes it, which is the safer failure.
- **Resolve missing paths through their deepest existing ancestor.** `cd`
  fails on a path that doesn't exist yet, which is every target in a dry run
  on a new machine. A symlinked parent such as `~/.gemini -> <clone>/x` must
  be caught before `mkdir -p` creates `config/skills` inside the clone. The
  resolver walks up, follows symlinks by their text (dangling ones too),
  canonicalizes the existing ancestor, and appends the missing names. It
  refuses a symlink loop or a missing `.` or `..` component rather than
  guess. Rejected: `realpath -m` or `readlink -f`, which BSD and older macOS
  lack in the needed form.
- **Canonicalize with the external `pwd -P`, not the bash builtin.** On a
  case-insensitive filesystem, the default on macOS, the builtin keeps a
  path's spelled case. A target linked through `.../CLONE/skills` then didn't
  match the clone's `.../clone`, passed the check, and `--adopt` deleted the
  skill. The external `pwd` reports `getcwd`'s on-disk name. The refute-first
  pass found this; see below.
- **Compare `== REPO_REAL` or `REPO_REAL/*` only.** A bare prefix match
  would also refuse a sibling such as `<clone>-other/`.
- **Check each target again just before reconciling it.** An earlier
  target's new link can redirect a later target whose path ran through a
  link that dangled at the first check. The up-front pass still keeps the
  common case all-or-nothing; the recheck stops the rare redirected case
  before it writes into the clone, after earlier targets already changed.
- **Never adopt a real directory that holds the clone.** With the clone
  checked out as `<target>/<skill-name>`, `--adopt` ran `rm -rf` on the
  whole clone. This predates #469 and isn't reached through a symlinked
  target, but it's the same total loss on the same path, so it's fixed here
  with a skip instead of left for a follow-up.
- **Keep `REPO` logical.** The ownership match compares `readlink` output
  with `"$SRC"/*`, and existing installs hold logical paths. Only the guard
  uses the physical `REPO_REAL`.

## Refute-First Findings

Each attempt below tried to make the script delete or write inside the
clone, or to refuse a legitimate setup. A fresh-context reviewer and the
author ran the probes on macOS (case-insensitive APFS) with scratch clones
and a throwaway HOME. `scripts/test-link-skills.sh` pins every confirmed
case and the main disproved ones.

- **Confirmed and fixed: case-variant spelling.** A target linked through
  `.../CLONE/skills`, or the script run from a `.../CLONE/scripts` spelling,
  passed the check under the builtin `pwd -P`, and `--adopt` deleted the
  skill. Fixed with the external `pwd`.
- **Confirmed and fixed: textual `..`.** A HOME spelled `<link>/..` made the
  logical `cd` stop at the textual parent while the kernel reached the
  clone, so links were written and a real directory inside the clone was
  replaced. Fixed with `cd -P`.
- **Confirmed and fixed: redirected later target.** See the recheck
  decision above. Very contrived: one target must link to an entry another
  target is about to create.
- **Confirmed and fixed: clone inside a target.** See the adopt decision
  above. Contrived: the clone's directory must share a skill's name.
- **Disproved by checks.** Relative, chained, and dangling links into the
  clone; a symlinked HOME; a symlink parent such as `~/.gemini` with or
  without its target; a symlink loop; a link to a file inside the clone; an
  NFD spelling of an NFC clone name; the `/System/Volumes/Data` firmlink
  spelling; the script invoked through a symlinked clone path; clone paths
  with spaces, glob characters, or a newline; and `$dest/alpha -> <clone>`
  under `--adopt`, which removes only the link. Each was refused or left the
  clone untouched.
- **Allowed by decision: over-refusal of unusable paths.** A `.` or `..`
  under a missing directory, or a directory the user can't enter, is refused
  as unresolvable. The kernel can't resolve those paths for `mkdir -p`
  either, so nothing usable is lost.
- **Checked: no over-refusal of legitimate setups.** A sibling such as
  `<clone>-other`, a trailing-slash or relative HOME, a symlinked HOME
  outside the clone, and a target symlinked to a dotfiles directory all
  exit 0 and link as before.

## Revisit When

- A new target is added to `TARGETS`, or `reconcile()` starts writing
  anywhere other than its target: the guard covers only the target paths.
