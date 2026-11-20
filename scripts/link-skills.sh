#!/usr/bin/env bash
#
# link-skills.sh — symlink this repo's skills into the local Claude Code,
# Codex, and Antigravity skill directories, then prune links for skills that
# no longer exist.
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
# A target that resolves into this clone, directly or through a symlink, is
# refused in every mode; every target is checked before any changes. A real
# directory that holds this clone is never replaced, even with --adopt.
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
# REPO stays logical because the "$SRC"/* ownership match below compares it
# with readlink output; REPO_REAL is the physical path the target check uses.
# Physical paths come from the external pwd (getcwd), not the bash builtin:
# on a case-insensitive filesystem the builtin keeps a path's spelled case,
# so .../CLONE/skills wouldn't match .../clone and would pass the check.
# cd -P makes `link/..` the link target's parent, as the kernel does, not
# the textual parent.
REPO_REAL=$(cd -P "$REPO" && env pwd -P)
SRC="$REPO/skills"

[ -d "$SRC" ] || {
  echo "no skills directory at $SRC" >&2
  exit 1
}

# Target skill directories per platform.
TARGETS=(
  "$HOME/.claude/skills" # Claude Code
  "$HOME/.agents/skills" # Codex
  # Antigravity reads global skills only under ~/.gemini/config; it doesn't
  # search ~/.agents/skills outside a project.
  "$HOME/.gemini/config/skills" # Antigravity
)

# resolve_physical PATH: print PATH's physical location, even when PATH or
# some of its parents don't exist yet. A dry run on a new machine and a
# symlinked parent such as ~/.gemini both need this: cd alone fails on a
# missing path, and mkdir -p would follow the parent symlink.
# Walks up to the deepest existing directory, resolves it, then appends the
# missing names; symlinks on the way (dangling ones too) are followed by
# their text. Fails on an unreadable directory, a symlink loop, or a `.` or
# `..` under a missing directory.
resolve_physical() {
  local path=$1 rest="" hops=0 link name
  while :; do
    if [ -d "$path" ]; then
      path=$(cd -P "$path" 2>/dev/null && env pwd -P) || return 1
      [ -z "$rest" ] || path=${path%/}
      printf '%s%s\n' "$path" "$rest"
      return 0
    elif [ -L "$path" ]; then
      hops=$((hops + 1))
      [ "$hops" -le 40 ] || return 1
      link=$(readlink "$path")
      case "$link" in
      /*) path=$link ;;
      *) path="$(dirname "$path")/$link" ;;
      esac
    else
      name=$(basename "$path")
      case "$name" in
      . | .. | /) return 1 ;;
      esac
      rest="/$name$rest"
      path=$(dirname "$path")
    fi
  done
}

# check_target DEST: refuse DEST, with a message, when it resolves to this
# clone or a path inside it, or when it can't be resolved.
check_target() {
  local real
  if ! real=$(resolve_physical "$1"); then
    echo "refusing target $1: can't resolve its physical path (unreadable directory, symlink loop, or . or .. under a missing directory)" >&2
    return 1
  fi
  case "$real" in
  "$REPO_REAL" | "$REPO_REAL"/*)
    echo "refusing target $1: resolves to $real, inside this clone ($REPO_REAL)" >&2
    return 1
    ;;
  esac
}

# contains_clone PATH: true when PATH is this clone or one of its ancestors,
# so rm -rf on it would delete the clone. Also true when PATH can't be
# resolved, so an unknown path is never removed.
contains_clone() {
  local real
  real=$(resolve_physical "$1") || return 0
  case "$REPO_REAL/" in
  "${real%/}"/*) return 0 ;;
  esac
  return 1
}

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
      if contains_clone "$link"; then
        # e.g. this clone checked out as <target>/<skill-name>
        printf 'skip (holds this clone or cannot be resolved, never replaced): %s\n' "$link"
      elif [ "$ADOPT" -eq 1 ]; then
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

# Check every target before changing any. A target inside the clone, such
# as ~/.claude/skills -> <clone>/skills, would make --adopt rm -rf the
# clone's own skills and a plain run write links inside the clone.
refused=0
for dest in "${TARGETS[@]}"; do
  check_target "$dest" || refused=1
done
[ "$refused" -eq 0 ] || exit 1

for dest in "${TARGETS[@]}"; do
  # Check again: an earlier target's new link can redirect a later target
  # whose path ran through a link that dangled at the first check.
  check_target "$dest" || exit 1
  echo "==> $dest"
  reconcile "$dest"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Done (dry run — no changes made)."
else
  echo "Done."
fi
