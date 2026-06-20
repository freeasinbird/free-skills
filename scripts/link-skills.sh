#!/usr/bin/env bash
#
# link-skills.sh — symlink this repo's skills into the local Claude Code and
# Codex skill directories, then prune links for skills that no longer exist.
#
# Idempotent reconcile: run it once per machine, then again after `git pull`
# to pick up added or removed skills. Because the installed entries are
# symlinks into this clone, `git pull` alone refreshes existing skills in
# place — re-run this only to add newly-created or drop deleted ones.
#
# Safety: by default only touches symlinks that point into THIS repo. Real
# directories and foreign symlinks are left alone (skipped with a message),
# so the script can't delete unrelated installs. Pass --adopt to replace
# them — e.g. to convert an earlier copied install into a tracking symlink.
#
# Portable across macOS (BSD) and Linux (GNU). Not for Windows — use WSL,
# or directory junctions via a separate PowerShell script.
#
# Usage:
#   scripts/link-skills.sh            # apply changes
#   scripts/link-skills.sh --dry-run  # show what would change, do nothing
#   scripts/link-skills.sh --adopt    # also replace real dirs / foreign
#                                      # symlinks with tracking symlinks

set -euo pipefail

DRY_RUN=0
ADOPT=0
for arg in "$@"; do
  case "$arg" in
    --dry-run | -n) DRY_RUN=1 ;;
    --adopt) ADOPT=1 ;;
    -h | --help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

# Repo root is the parent of this script's directory, so the script works
# from any clone path and any working directory.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
SRC="$REPO/skills"

[ -d "$SRC" ] || {
  echo "no skills directory at $SRC" >&2
  exit 1
}

# Target skill directories per platform.
TARGETS=(
  "$HOME/.claude/skills" # Claude Code
  "$HOME/.agents/skills" # Codex
)

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'would: %s\n' "$*"
  else
    "$@"
  fi
}

reconcile() {
  dest=$1
  run mkdir -p "$dest"

  # Add or refresh: one symlink per skill directory in the repo.
  for d in "$SRC"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    target="${d%/}"
    link="$dest/$name"
    if [ -L "$link" ]; then
      cur=$(readlink "$link")
      case "$cur" in
      "$SRC"/*)
        # already ours — refresh only if the target drifted
        [ "$cur" = "$target" ] || run ln -sfn "$target" "$link"
        ;;
      *)
        # symlink to somewhere else
        if [ "$ADOPT" -eq 1 ]; then
          printf 'adopt (replacing foreign symlink): %s -> %s\n' "$link" "$cur"
          run rm -rf "$link"
          run ln -sfn "$target" "$link"
        else
          printf 'skip (foreign symlink — re-run with --adopt to replace): %s -> %s\n' "$link" "$cur"
        fi
        ;;
      esac
    elif [ -e "$link" ]; then
      # real file or directory, e.g. an earlier copied install
      if [ "$ADOPT" -eq 1 ]; then
        printf 'adopt (replacing real path): %s\n' "$link"
        run rm -rf "$link"
        run ln -sfn "$target" "$link"
      else
        printf 'skip (real directory — re-run with --adopt to replace): %s\n' "$link"
      fi
    else
      run ln -sfn "$target" "$link"
    fi
  done

  # Prune: symlinks we own (pointing into this repo) whose skill is gone.
  [ -d "$dest" ] || return 0
  for link in "$dest"/*; do
    [ -L "$link" ] || continue
    cur=$(readlink "$link")
    case "$cur" in
    "$SRC"/*)
      name=$(basename "$link")
      [ -d "$SRC/$name" ] || run rm "$link"
      ;;
    esac
  done
}

for dest in "${TARGETS[@]}"; do
  echo "==> $dest"
  reconcile "$dest"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Done (dry run — no changes made)."
else
  echo "Done."
fi
