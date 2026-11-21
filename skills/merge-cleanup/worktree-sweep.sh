#!/usr/bin/env bash
# worktree-sweep.sh: list the linked worktrees that are safe to remove after a
# batch of landings, report what each removal would delete, and remove only
# what the owner authorized for this run. Removal is destructive, so the
# default is a dry run and every removal is rechecked just before it happens.
# The owner runs it; a landing batch runs only --remove-landed, at its end,
# and merge-cleanup runs only --remove-head, for the PR it cleans up.
#
# Usage:
#   worktree-sweep.sh [--base <ref>] [--remove [--remove-dirty] | --remove-landed]
#     [--caller-dir <dir>]
#   worktree-sweep.sh --remove-head <branch> --head-oid <oid>
#     [--disposables-at <oid>] [--caller-dir <dir>]
#   worktree-sweep.sh --help
#
#   --base <ref>     the ref a branch must be merged into. Default: the
#                    branch refs/remotes/origin/HEAD points at. The script
#                    never fetches, so fetch first: a stale base keeps
#                    worktrees merged since, and can still allow deleting
#                    paths under a disposables entry the project has since
#                    dropped.
#   --remove         remove the clean candidates. Without it, nothing changes.
#   --remove-dirty   with --remove, also remove the dirty candidates, deleting
#                    the files the report lists. Alone, a usage error. This
#                    clears untracked leftovers no entry covers, such as
#                    scratch files: read a dry run's list first.
#   --remove-landed  remove only the clean branch candidates whose landing
#                    merge was found. Keeps every dirty candidate, every
#                    branch with no landing merge (it may be a fresh branch a
#                    session just started in), and every detached land-wt
#                    worktree (a lander may be using it). With --remove or
#                    --remove-dirty, a usage error.
#   --remove-head <branch>
#                    remove only the worktree on refs/heads/<branch>, and only
#                    when it is clean and the branch is at --head-oid. The
#                    caller vouches that <oid> is a merged PR's head, so no
#                    base or ancestry test applies; merge-cleanup passes the
#                    head it verified on the forge. Prints lines only for
#                    worktrees on that branch. With --base, --remove,
#                    --remove-dirty, or --remove-landed, a usage error.
#   --head-oid <oid> the full object name the branch must be at. Required by
#                    --remove-head, and a usage error without it.
#   --disposables-at <oid>
#                    the full object name of the commit whose disposables
#                    file --remove-head applies. The caller vouches that it
#                    is a reviewed base commit; merge-cleanup passes the base
#                    tip it just fetched. It is only read, never tested for
#                    ancestry or a landing merge. Optional with
#                    --remove-head, and a usage error without it.
#   --caller-dir <dir>
#                    a directory the caller stands in, such as a shell's
#                    working directory, that this run's own directory may not
#                    be. The worktree holding it is reported self, like the
#                    one this runs in.
#
# A candidate is a linked worktree on a branch whose tip is an ancestor of the
# base, or a detached worktree at land's <tmp>/land-wt.XXXXXX/wt template.
# Never a candidate: the primary checkout, the worktree this runs in, a locked
# worktree, one whose directory is gone (prunable), one that holds another
# registered worktree, a submodule repository, populated or not, or a nested
# repository (removal deletes them too), one on the base branch, an unmerged
# branch, or a branch that no longer resolves, one git resolves to another
# working tree, and any other detached worktree. A nested repository inside
# an ignored directory that a disposables entry matches is not one. Under
# --remove-head, a worktree on the named branch at another commit is
# reported moved instead, and a worktree on any other branch is not a
# candidate and not printed.
#
# A candidate is clean when worktree-inventory.sh reports OK inventory, no
# operation is paused in it, it holds no resolvable ref under refs/worktree/ or
# refs/bisect/, no unreferenced commit is reachable from HEAD reflog entries
# recorded after HEAD first reached its current commit (ignoring refs/worktree/*
# and refs/bisect/* as surviving refs), and, for a detached one, a ref holds its
# HEAD; anything else is dirty. The one exception is the project's disposables:
# an inventory that stops only because the worktree holds ignored files still
# counts as clean when every file this script finds is an ignored path that a
# disposables entry matches, or an ignored .DS_Store, and none of the other
# checks above found anything. A dirty branch candidate
# with no landing merge (no first-parent merge of the base whose second parent
# is its tip) is never removed: a fast-forwarded branch and a branch that has
# no commits of its own yet look the same, and the second may hold work in
# progress.
#
# Output is one line per registered worktree, in `git worktree list` order:
#   WORKTREE <disposition> {path, branch, ...}
# where <disposition> is removed, clean, dirty (a candidate left in place), or
# the reason it is not a candidate: primary, self, prunable, locked,
# holds-worktree, holds-submodule, holds-repository, base-branch, unmerged,
# unresolved-branch, unreadable, redirected, detached-other, or, under
# --remove-head, moved, or other-branch when a recheck finds it switched.
# A candidate's line carries merge (the landing merge's oid and subject, or "none found"),
# state, operation, unreferenced_head (a detached HEAD no ref holds, or null),
# the untracked, modified, ignored, flagged, and disposable paths removal
# would delete, worktree_refs (resolvable refs/worktree/* and refs/bisect/*),
# and reflog_commits (unreferenced commits reachable from post-HEAD reflog
# entries). disposable names each matched prefix once (app/.build/, not
# every file under it); ignored holds only the ignored paths no entry
# matches, and names a directory an ignore pattern matches once, with a
# trailing / (.venv/, not every file under it).
#
# Then one result line, whose counts are worktrees, candidates, clean, dirty,
# removed, and kept (candidates left in place), each worktree counted as its
# last check found it, and whose disposables field lists the file's entries
# (empty without one; the built-in .DS_Store is not listed). Exit codes:
#   0   OK sweep {...}             the run finished
#   2   STOP <guard> {...}         no-base, bad-record (before any worktree is
#                                  read), or remove-failed (nothing after it
#                                  was attempted)
#   4   LOOKUP_FAILED <what> {...} a read failed; nothing after it was removed
#   64  usage on stderr            bad arguments
#   69  note on stderr             git or the inventory missing, or not bash
#
# Disposables. The project names the ignored paths removal may delete in
# .worktree-disposables at the repository root, read at the pinned base
# commit (never from a worktree, so a branch cannot widen it before it
# lands). Each line is one entry; blank lines and lines starting with # are
# skipped:
#   # SwiftPM and Python build output
#   app/.build/
#   __pycache__/
# Each entry is literal: a name or a path relative to the worktree root, with
# an optional trailing / meaning directory only. An entry with no interior /
# matches that name at any depth; one with an interior / is anchored at the
# root. An ignored path is disposable when a leading run of its components
# matches an entry and that run is itself ignored; an untracked one never is.
# A directory, not a repository, whose own .gitignore holds only a * (and
# comments), as Hypothesis and uv write one, counts as ignored. A missing,
# empty, or comments-only file means no entries. Built in, with no entry: an
# ignored file named .DS_Store, at any depth, is disposable.
# --remove-head has no base, so it reads the file only at the
# --disposables-at commit; without that flag it reads no file and applies
# only the built-in rule.
#
# STOP bad-record refuses the file when it is not a regular file (a
# symlink's blob is its target's name), holds a NUL byte or a carriage
# return, has a line with a leading or trailing space (a comment
# included), or has an entry with a leading / or !, a \, a glob character
# (* ? [ ]), an empty component (//), a . or .. component, a .git component
# in any case, or a control character.
set -u

# Byte semantics for json_escape's string indexing; see worktree-inventory.sh.
export LC_ALL=C
# An inherited GIT_DIR or GIT_WORK_TREE would point every `git -C <worktree>`
# read at another repository's index and files, so each worktree is judged
# by what it is. GIT_OPTIONAL_LOCKS=0 stops `git status`, here and in the
# inventory, from rewriting a worktree's index during a dry run.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
export GIT_OPTIONAL_LOCKS=0

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

case "${1:-}" in
  --help | -h) [ $# -eq 1 ] || usage; sed -n '2,/^set -u$/p' "$0" | sed '$d'; exit 0 ;;
esac

BASE_OPT="" REMOVE=false REMOVE_DIRTY=false REMOVE_LANDED=false
HEAD_BRANCH="" HEAD_OID_OPT="" DISPOSABLES_AT_OPT="" CALLER_OPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --remove-head | --head-oid | --disposables-at | --caller-dir)
      [ $# -ge 2 ] || { echo "worktree-sweep.sh: $1 requires a value" >&2; usage; }
      case "$2" in
        '' | -*) echo "worktree-sweep.sh: $1 needs a value, not '$2'" >&2; usage ;;
      esac
      case "$1" in
        --remove-head) HEAD_BRANCH="$2" ;;
        --head-oid) HEAD_OID_OPT="$2" ;;
        --disposables-at) DISPOSABLES_AT_OPT="$2" ;;
        --caller-dir) CALLER_OPT="$2" ;;
      esac
      shift 2 ;;
    --base)
      [ $# -ge 2 ] || { echo "worktree-sweep.sh: --base requires a value" >&2; usage; }
      case "$2" in
        '' | -*) echo "worktree-sweep.sh: --base needs a ref, not '$2'" >&2; usage ;;
      esac
      BASE_OPT="$2"; shift 2 ;;
    --remove) REMOVE=true; shift ;;
    --remove-dirty) REMOVE_DIRTY=true; shift ;;
    --remove-landed) REMOVE_LANDED=true; shift ;;
    *) echo "worktree-sweep.sh: unknown argument: $1" >&2; usage ;;
  esac
done
# --remove-landed is a narrower rule, not a widening of --remove, so a run
# names exactly one removal rule.
if [ "$REMOVE_LANDED" = true ] && { [ "$REMOVE" = true ] || [ "$REMOVE_DIRTY" = true ]; }; then
  echo "worktree-sweep.sh: --remove-landed stands alone; drop --remove and --remove-dirty" >&2
  usage
fi
# Two flags, so deleting files the owner may still want always takes a
# separate, deliberate word on the command line.
if [ "$REMOVE_DIRTY" = true ] && [ "$REMOVE" != true ]; then
  echo "worktree-sweep.sh: --remove-dirty only widens --remove; pass both" >&2
  usage
fi
# --remove-head judges one branch against the oid its caller verified, so a
# base or a broader rule has no meaning beside it.
if [ -n "$HEAD_BRANCH" ]; then
  if [ -n "$BASE_OPT" ] || [ "$REMOVE" = true ] || [ "$REMOVE_LANDED" = true ]; then
    echo "worktree-sweep.sh: --remove-head stands alone; drop --base, --remove, --remove-dirty, and --remove-landed" >&2
    usage
  fi
  case "$HEAD_OID_OPT" in
    '') echo "worktree-sweep.sh: --remove-head requires --head-oid" >&2; usage ;;
    *[!0-9a-f]*) echo "worktree-sweep.sh: --head-oid must be a full lowercase hex object name" >&2; usage ;;
  esac
  case "${#HEAD_OID_OPT}" in
    40 | 64) ;;
    *) echo "worktree-sweep.sh: --head-oid must be a full lowercase hex object name" >&2; usage ;;
  esac
  if [ -n "$DISPOSABLES_AT_OPT" ]; then
    case "$DISPOSABLES_AT_OPT" in
      *[!0-9a-f]*) echo "worktree-sweep.sh: --disposables-at must be a full lowercase hex object name" >&2; usage ;;
    esac
    case "${#DISPOSABLES_AT_OPT}" in
      40 | 64) ;;
      *) echo "worktree-sweep.sh: --disposables-at must be a full lowercase hex object name" >&2; usage ;;
    esac
  fi
elif [ -n "$HEAD_OID_OPT" ]; then
  echo "worktree-sweep.sh: --head-oid only qualifies --remove-head" >&2
  usage
elif [ -n "$DISPOSABLES_AT_OPT" ]; then
  echo "worktree-sweep.sh: --disposables-at only qualifies --remove-head" >&2
  usage
fi

command -v git >/dev/null 2>&1 \
  || { echo "worktree-sweep.sh: git is not on PATH" >&2; exit 69; }
[ -n "${BASH_VERSION:-}" ] \
  || { echo "worktree-sweep.sh: needs bash for NUL-terminated reads" >&2; exit 69; }
INVENTORY="$(cd "$(dirname "$0")" && pwd)/worktree-inventory.sh"
[ -x "$INVENTORY" ] \
  || { echo "worktree-sweep.sh: $INVENTORY is missing or not executable" >&2; exit 69; }

utf8_len() { # utf8_len <string> <byte index>: copied from worktree-inventory.sh
  local LC_ALL=C s="$1" i="$2" n b b2 need lo hi k
  n=${#s}
  printf -v b '%d' "'${s:i:1}"
  b=$((b & 255))
  if [ "$b" -lt 128 ]; then U8_LEN=1; return; fi
  if [ "$b" -ge 194 ] && [ "$b" -le 223 ]; then need=1; lo=128; hi=191
  elif [ "$b" -eq 224 ]; then need=2; lo=160; hi=191
  elif [ "$b" -ge 225 ] && [ "$b" -le 236 ]; then need=2; lo=128; hi=191
  elif [ "$b" -eq 237 ]; then need=2; lo=128; hi=159
  elif [ "$b" -ge 238 ] && [ "$b" -le 239 ]; then need=2; lo=128; hi=191
  elif [ "$b" -eq 240 ]; then need=3; lo=144; hi=191
  elif [ "$b" -ge 241 ] && [ "$b" -le 243 ]; then need=3; lo=128; hi=191
  elif [ "$b" -eq 244 ]; then need=3; lo=128; hi=143
  else U8_LEN=0; return
  fi
  [ $((i + need)) -lt "$n" ] || { U8_LEN=0; return; }
  for ((k = 1; k <= need; k++)); do
    printf -v b2 '%d' "'${s:i+k:1}"
    b2=$((b2 & 255))
    if [ "$k" -eq 1 ]; then
      { [ "$b2" -ge "$lo" ] && [ "$b2" -le "$hi" ]; } || { U8_LEN=0; return; }
    else
      { [ "$b2" -ge 128 ] && [ "$b2" -le 191 ]; } || { U8_LEN=0; return; }
    fi
  done
  U8_LEN=$((need + 1))
}

json_escape() { # copied from worktree-inventory.sh, which explains the rules
  json_escape_to "$1"
  printf '%s' "$JSON_ESC"
}

json_escape_to() { # copied from worktree-inventory.sh
  local LC_ALL=C s="$1" out="" i=0 n c o bs='\' q='"'
  case "$s" in
    *[![:print:]]*) ;;
    *)
      s=${s//"$bs"/"$bs$bs"}
      JSON_ESC=${s//"$q"/"$bs$q"}
      return
      ;;
  esac
  n=${#s}
  while [ "$i" -lt "$n" ]; do
    c="${s:i:1}"
    case "$c" in
      \\) out+='\\'; i=$((i + 1)); continue ;;
      \") out+='\"'; i=$((i + 1)); continue ;;
      $'\n') out+='\n'; i=$((i + 1)); continue ;;
      $'\t') out+='\t'; i=$((i + 1)); continue ;;
      $'\r') out+='\r'; i=$((i + 1)); continue ;;
    esac
    printf -v o '%d' "'$c"
    o=$((o & 255))
    if [ "$o" -lt 32 ]; then printf -v c '\\u%04x' "$o"; out+="$c"; i=$((i + 1)); continue; fi
    if [ "$o" -lt 128 ]; then out+="$c"; i=$((i + 1)); continue; fi
    utf8_len "$s" "$i"
    if [ "$U8_LEN" -eq 0 ]; then printf -v c '\\u%04x' "$o"; out+="$c"; i=$((i + 1)); continue; fi
    out+="${s:i:U8_LEN}"
    i=$((i + U8_LEN))
  done
  JSON_ESC="$out"
}

out_exact() { # out_exact <var> <cmd...>: capture stdout byte-exactly
  # A plain $( ) strips every trailing newline, and a worktree path may end in
  # one; see worktree-inventory.sh.
  local __v="$1"; shift
  local __o
  __o=$("$@" 2>/dev/null && printf x) || return 1
  __o="${__o%x}"
  printf -v "$__v" '%s' "${__o%$'\n'}"
}

physical_dir() { # physical_dir <dir>: its symlink-free path; run under out_exact
  cd -P -- "$1" && pwd -P
}

N_WORKTREES=0 N_CANDIDATES=0 N_CLEAN=0 N_DIRTY=0 N_REMOVED=0 N_KEPT=0
BASE_NAME="" BASE_OID=""
# The disposables file: DISPOSABLES holds each entry as written, D_BODY the
# entry without its trailing /, D_DIR whether that / was there, and D_ANCHORED
# whether the body holds a /. N_DISPOSABLES guards every expansion, since
# bash 3.2 treats an empty array's "${a[@]}" as unbound under set -u.
DISPOSABLES=() D_BODY=() D_DIR=() D_ANCHORED=() N_DISPOSABLES=0 DISPOSABLES_JSON=""

result_json() { # result_json <detail>
  printf '{"base":"%s","base_oid":"%s","mode":"%s","disposables":[%s],"worktrees":%d,"candidates":%d,"clean":%d,"dirty":%d,"removed":%d,"kept":%d,"detail":"%s"}' \
    "$(json_escape "$BASE_NAME")" "$BASE_OID" "$MODE" "$DISPOSABLES_JSON" "$N_WORKTREES" \
    "$N_CANDIDATES" "$N_CLEAN" "$N_DIRTY" "$N_REMOVED" "$N_KEPT" "$(json_escape "$1")"
}
stop() { # stop <guard> <detail>
  echo "STOP $1 $(result_json "$2")"
  exit 2
}
lookup_failed() { # lookup_failed <what> <detail>
  echo "LOOKUP_FAILED $1 $(result_json "$2")"
  exit 4
}

MODE=dry-run
[ "$REMOVE" != true ] || MODE=remove
[ "$REMOVE_DIRTY" != true ] || MODE=remove-dirty
[ "$REMOVE_LANDED" != true ] || MODE=remove-landed
[ -z "$HEAD_BRANCH" ] || MODE=remove-head

git rev-parse --git-dir >/dev/null 2>&1 \
  || lookup_failed repository "not inside a git repository"

# Pin the base once, so every worktree in the run is judged against the same
# commit even if a fetch lands mid-run. --remove-head needs none; its
# --disposables-at commit only names where the disposables file is read, so
# BASE_NAME stays empty and no base-branch, ancestry, or landing test uses it.
if [ "$MODE" = remove-head ]; then
  if [ -n "$DISPOSABLES_AT_OPT" ]; then
    # The equality test keeps a ref named like an oid, or a tag that peels
    # to another commit, from standing in for the commit the caller named.
    BASE_OID=$(git rev-parse --verify --quiet "$DISPOSABLES_AT_OPT^{commit}" 2>/dev/null) \
      && [ "$BASE_OID" = "$DISPOSABLES_AT_OPT" ] \
      || stop no-base "--disposables-at $DISPOSABLES_AT_OPT is not a local commit; fetch the base first"
  fi
elif [ -n "$BASE_OPT" ]; then
  BASE_NAME="$BASE_OPT"
else
  out_exact BASE_NAME git symbolic-ref -q refs/remotes/origin/HEAD \
    || stop no-base "refs/remotes/origin/HEAD is not set; pass --base <ref> to name the branch that merged branches land on"
fi
if [ "$MODE" != remove-head ]; then
  BASE_OID=$(git rev-parse --verify --quiet "$BASE_NAME^{commit}" 2>/dev/null) \
    || stop no-base "$BASE_NAME does not resolve to a commit; fetch, or pass --base <ref>"
fi

# The local branch the base stands for (main for origin/main), whose worktree
# is the owner's checkout of the default branch, not a merged branch's. A
# remote's name may hold a slash, so the longest configured remote that
# prefixes the ref is the one stripped.
BASE_BRANCH=""
[ -z "$BASE_NAME" ] \
  || BASE_BRANCH=$(git rev-parse --symbolic-full-name "$BASE_NAME" 2>/dev/null) || BASE_BRANCH=""
case "$BASE_BRANCH" in
  refs/remotes/*/*)
    remotes=$(git remote) || lookup_failed remotes "could not list the remotes"
    remote=""
    while IFS= read -r r; do
      case "$BASE_BRANCH" in
        "refs/remotes/$r/"*) [ "${#r}" -le "${#remote}" ] || remote="$r" ;;
      esac
    done <<< "$remotes"
    if [ -n "$remote" ]; then
      BASE_BRANCH="refs/heads/${BASE_BRANCH#"refs/remotes/$remote/"}"
    else
      BASE_BRANCH="refs/heads/${BASE_BRANCH#refs/remotes/*/}"
    fi
    ;;
  refs/heads/*) ;;
  *) BASE_BRANCH="" ;;
esac

# bad_entry <entry>: print why the grammar refuses it, or nothing. Literal
# names only: a glob that matches more than intended deletes real work, and
# a .git component would let removal take a nested repository's history.
bad_entry() {
  local e="$1" body c rest
  case "$e" in
    '') echo "an empty entry"; return ;;
    *[[:cntrl:]]*) echo "a control character"; return ;;
    [[:space:]]* | *[[:space:]]) echo "a leading or trailing space"; return ;;
    /*) echo "a leading /; entries are relative to the worktree root"; return ;;
    !*) echo "a leading !; the file has no negation"; return ;;
    *\\*) echo "a \\"; return ;;
    *[*?]* | *[][]*) echo "a glob character; entries are literal"; return ;;
    *//*) echo "an empty component"; return ;;
  esac
  body="${e%/}" rest="$body"
  while :; do
    c="${rest%%/*}"
    case "$c" in
      . | ..) echo "a . or .. component"; return ;;
      .[gG][iI][tT]) echo "a .git component"; return ;;
    esac
    case "$rest" in */*) rest="${rest#*/}" ;; *) break ;; esac
  done
}

# Read the disposables file before any worktree, so a bad one stops the run
# with nothing judged or removed. ls-tree tells a missing file from a failed
# read, which must stop the run rather than read as no entries; --full-tree
# finds the root's file from any subdirectory. --remove-head reads it only
# at the --disposables-at commit its caller pinned, the newest base tip the
# project reviewed, and never from the merged head: the head's copy may hold
# entries the base has since dropped. Without that flag it reads none.
DECL=.worktree-disposables
DECL_AT="$BASE_NAME"
[ -n "$DECL_AT" ] || DECL_AT="$BASE_OID"
decl_refuse() { # decl_refuse <why>
  rm -f "$record_tmp"
  stop bad-record "$DECL at $DECL_AT $1"
}
record_tmp="" decl_entry=""
if [ -n "$BASE_OID" ]; then
  decl_entry=$(git ls-tree --full-tree "$BASE_OID" -- "$DECL" 2>/dev/null) \
    || lookup_failed record "could not list $DECL at $DECL_AT"
fi
if [ -n "$decl_entry" ]; then
  case "$decl_entry" in
    "100644 blob "* | "100755 blob "*) ;;
    *) decl_refuse "is not a regular file" ;;
  esac
  record_tmp=$(mktemp) || lookup_failed mktemp "could not create a temporary file"
  git cat-file blob "$BASE_OID:$DECL" > "$record_tmp" 2>/dev/null \
    || { rm -f "$record_tmp"; lookup_failed record "could not read $DECL at $DECL_AT"; }
  # read drops a NUL (bash 5) or ends the line at it (bash 3.2), changing the
  # entry. A file, not a pipe: cmp can exit at the first difference and
  # kill tr.
  nul_free_tmp=$(mktemp) \
    || { rm -f "$record_tmp"; lookup_failed mktemp "could not create a temporary file"; }
  rc=2
  tr -d '\000' < "$record_tmp" > "$nul_free_tmp" && { cmp -s "$record_tmp" "$nul_free_tmp"; rc=$?; }
  rm -f "$nul_free_tmp"
  case "$rc" in
    0) ;;
    1) decl_refuse "holds a NUL byte" ;;
    *) rm -f "$record_tmp"; lookup_failed record "could not read $DECL at $DECL_AT" ;;
  esac
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in
      *$'\r'*) decl_refuse "line $n holds a carriage return; save it with LF line endings" ;;
      [[:space:]]* | *[[:space:]]) decl_refuse "line $n has a leading or trailing space" ;;
      '' | '#'*) continue ;;
    esac
    why=$(bad_entry "$line")
    [ -z "$why" ] || decl_refuse "line $n, entry '$line': $why"
    DISPOSABLES[N_DISPOSABLES]="$line"
    D_BODY[N_DISPOSABLES]="${line%/}"
    D_DIR[N_DISPOSABLES]=false
    [ "$line" = "${line%/}" ] || D_DIR[N_DISPOSABLES]=true
    D_ANCHORED[N_DISPOSABLES]=false
    case "${line%/}" in */*) D_ANCHORED[N_DISPOSABLES]=true ;; esac
    [ -z "$DISPOSABLES_JSON" ] || DISPOSABLES_JSON+=","
    DISPOSABLES_JSON+="\"$(json_escape "$line")\""
    N_DISPOSABLES=$((N_DISPOSABLES + 1))
  done < "$record_tmp"
  rm -f "$record_tmp"
fi

# The worktree this command runs in: removing it unlinks the shell's current
# directory. Compared by inode, as worktree-inventory.sh does.
out_exact SELF git rev-parse --show-toplevel || SELF=""
# The caller's directory, physical, so each worktree's ancestry test below
# compares inodes, not spellings.
CALLER=""
if [ -n "$CALLER_OPT" ]; then
  out_exact CALLER physical_dir "$CALLER_OPT" \
    || lookup_failed caller-dir "could not enter --caller-dir $CALLER_OPT"
fi
holds_caller() { # holds_caller <path>: is the caller's directory at or under it?
  local d="$CALLER"
  [ -n "$d" ] || return 1
  while :; do
    [ "$d" -ef "$1" ] && return 0
    [ "$d" != / ] || return 1
    d="${d%/*}"
    [ -n "$d" ] || d=/
  done
}

# Parse `git worktree list --porcelain -z` NUL-aware into WT_* arrays. Each
# entry is NUL-terminated fields ended by an empty field; the first entry is
# the primary checkout. The fields stream through a temp file, since a command
# substitution would drop a trailing newline from a path.
scan_worktrees() {
  local tmp field n=-1
  WT_PATH=() WT_BRANCH=() WT_LOCKED=() WT_PRUNABLE=()
  tmp=$(mktemp) || lookup_failed worktree-list "mktemp failed"
  git worktree list --porcelain -z > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed worktree-list "git worktree list failed"; }
  while IFS= read -r -d '' field; do
    case "$field" in
      "worktree "*)
        n=$((n + 1))
        WT_PATH[n]="${field#worktree }" WT_BRANCH[n]="" WT_LOCKED[n]="" WT_PRUNABLE[n]=""
        ;;
      "branch "*) WT_BRANCH[n]="${field#branch }" ;;
      detached) WT_BRANCH[n]=detached ;;
      bare) WT_BRANCH[n]=bare ;;
      locked | "locked "*) WT_LOCKED[n]=1 ;;
      prunable | "prunable "*) WT_PRUNABLE[n]=1 ;;
    esac
  done < "$tmp"
  rm -f "$tmp"
  WT_COUNT=$((n + 1))
  [ "$WT_COUNT" -gt 0 ] || lookup_failed worktree-list "git worktree list returned no entries"
}

# Is a git operation paused in the worktree? Copied from merge-cleanup.sh's
# op_probe: removal deletes the per-worktree state that resumes it.
op_probe() { # op_probe <dir>: returns 0 and sets OP_FOUND when one is paused
  local d="$1" p gp
  OP_FOUND=""
  for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_START rebase-merge rebase-apply; do
    out_exact gp git -C "$d" rev-parse --git-path "$p" \
      || lookup_failed op-probe "could not resolve $p inside $d"
    if (cd "$d" && { [ -e "$gp" ] || [ -L "$gp" ]; }); then
      OP_FOUND="$p"; return 0
    fi
  done
  return 1
}

json_add() { # json_add <array> <path>: append <path> to <array> as a JSON string
  # An array append copies nothing built so far, where rebuilding one string
  # per path grew quadratically with a long list.
  json_escape_to "$2"
  JSON_ESC="\"$JSON_ESC\""
  eval "$1+=(\"\$JSON_ESC\")"
}

json_list() { # json_list <array>: set JSON_LIST to its items joined by commas
  # The ${a[*]+...} form keeps bash 3.2 from calling an empty array unbound.
  local IFS=,
  eval "JSON_LIST=\${$1[*]+\"\${$1[*]}\"}"
}

# Is <path> disposable? It is when a leading run of its components matches a
# disposables entry and that run is itself ignored, so declaring notes/ never
# covers notes/private/ while only the latter is ignored. git never looks
# inside an ignored directory, so all of it is ignored, nested repositories
# included. <path> is relative to the worktree root, and a trailing / marks
# it a directory, as status prints one; <ignored> is true when status
# already reported <path> ignored. On a match, sets M_PREFIX to the shortest
# such run, with a trailing / when it is a directory. M_LAST is the previous
# match: `status --ignored=matching` lists a directory a pattern matches as
# one record, but enters a directory that only its contents' pattern ignores
# (a * in its own .gitignore, as in a uv .venv) and lists each entry in it,
# together, so a path under the last directory prefix is answered without
# walking it. M_IGNORED and M_KEPT cache check-ignore answers, newline
# delimited. Callers reset all three for each worktree. Built in: an
# ignored file named .DS_Store is disposable with no entry, since Finder
# recreates it and nobody keeps work in it. The entries go first, so a
# .DS_Store under a declared directory reports that directory's prefix.
match_disposable() { # match_disposable <worktree> <path> <ignored>
  match_declared "$@" && return 0
  if [ "$3" = true ] && [ "${2##*/}" = .DS_Store ]; then
    M_PREFIX="$2"
    return 0
  fi
  return 1
}
match_declared() { # match_declared <worktree> <path> <ignored>
  local wt="$1" rest="$2" comp prefix="" is_dir j hit rc
  M_PREFIX=""
  [ "$N_DISPOSABLES" -gt 0 ] || return 1
  case "$M_LAST" in
    */) case "$2" in "$M_LAST"*) M_PREFIX="$M_LAST"; return 0 ;; esac ;;
  esac
  while [ -n "$rest" ]; do
    case "$rest" in
      */*) comp="${rest%%/*}" rest="${rest#*/}" is_dir=true ;;
      *) comp="$rest" rest="" is_dir=false ;;
    esac
    prefix+="$comp"
    # The caches are newline delimited, so a prefix holding a newline could
    # read another path's answer. No part from there down is disposable.
    case "$prefix" in *$'\n'*) return 1 ;; esac
    hit=false
    for ((j = 0; j < N_DISPOSABLES; j++)); do
      [ "${D_DIR[j]}" = false ] || [ "$is_dir" = true ] || continue
      if [ "${D_ANCHORED[j]}" = true ]; then
        [ "$prefix" = "${D_BODY[j]}" ] || continue
      else
        [ "$comp" = "${D_BODY[j]}" ] || continue
      fi
      hit=true
      break
    done
    if [ "$hit" = true ] && [ "$3" = true ] && [ -z "$rest" ]; then
      rc=0
    elif [ "$hit" = true ]; then
      case "$M_IGNORED" in
        *$'\n'"$prefix"$'\n'*) rc=0 ;;
        *)
          case "$M_KEPT" in
            *$'\n'"$prefix"$'\n'*) rc=1 ;;
            *)
              # No trailing /: with one, a pattern for the directory's
              # contents, such as cache/* or a * in its own .gitignore,
              # answers for the directory. ./ keeps a leading : from reading
              # as pathspec magic. stdin is the caller's record stream.
              git -C "$wt" -c core.fsmonitor=false check-ignore -q -- "./$prefix" \
                < /dev/null 2>/dev/null
              rc=$?
              if [ "$rc" -eq 1 ] && [ "$is_dir" = true ] && own_star_ignored "$wt" "$prefix"; then
                rc=0
              fi
              case "$rc" in
                0) M_IGNORED+="$prefix"$'\n' ;;
                1) M_KEPT+="$prefix"$'\n' ;;
                *) lookup_failed check-ignore "could not check whether $wt/$prefix is ignored" ;;
              esac
              ;;
          esac
          ;;
      esac
    else
      rc=1
    fi
    if [ "$rc" -eq 0 ]; then
      M_PREFIX="$prefix"
      [ "$is_dir" = false ] || M_PREFIX+="/"
      M_LAST="$M_PREFIX"
      return 0
    fi
    prefix+="/"
  done
  return 1
}

# Tools such as Hypothesis (.hypothesis/) and uv (.venv/) ignore their own
# directory with a * in a .gitignore inside it, so check-ignore without the
# trailing / reads the directory as not ignored, and a declared entry for it
# never matched. Such a directory counts as ignored only when git ignores
# <dir>/ by the pattern * from <dir>/.gitignore and that file holds nothing
# but *, comments, and blank lines. The * ignores every child, and git reads
# no deeper .gitignore under an ignored directory, so no line anywhere can
# re-include a path, a repository included; a ! line in this file could, so
# any other line refuses the directory. Any other pattern for its contents,
# such as cache/*, still doesn't answer for it. A repository at <dir> never
# counts: a * in its own .gitignore must not make its commits disposable.
own_star_ignored() { # own_star_ignored <worktree> <dir>
  local wt="$1" dir="$2" tmp rc src="" _="" pat="" l=""
  { [ -d "$wt/$dir" ] && [ ! -L "$wt/$dir" ]; } || return 1
  { [ ! -e "$wt/$dir/.git" ] && [ ! -L "$wt/$dir/.git" ]; } || return 1
  { [ -f "$wt/$dir/.gitignore" ] && [ ! -L "$wt/$dir/.gitignore" ]; } || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in '*' | '' | '#'*) ;; *) return 1 ;; esac
  done < "$wt/$dir/.gitignore" \
    || lookup_failed gitignore "could not read $wt/$dir/.gitignore"
  tmp=$(mktemp) || lookup_failed mktemp "could not create a temporary file"
  # -z needs --stdin; its fields arrive whole whatever the name holds.
  printf './%s/\0' "$dir" \
    | git -C "$wt" -c core.fsmonitor=false check-ignore -v -z --stdin > "$tmp" 2>/dev/null
  rc=${PIPESTATUS[1]}
  case "$rc" in
    0) ;;
    1) rm -f "$tmp"; return 1 ;;
    *) rm -f "$tmp"; lookup_failed check-ignore "could not check whether $wt/$dir/ is ignored" ;;
  esac
  { IFS= read -r -d '' src; IFS= read -r -d '' _; IFS= read -r -d '' pat; } < "$tmp" || true
  rm -f "$tmp"
  [ "$src" = "$dir/.gitignore" ] && [ "$pat" = "*" ]
}

# --ignored=matching lists an ignored directory holding nothing but empty
# directories, which the per-file listing never did, and removing it deletes
# no file. Such a record is skipped so it can't turn a clean worktree dirty;
# a failed find counts as holding something.
holds_entries() { # holds_entries <worktree> <status path>
  local hit
  case "$2" in */) ;; *) return 0 ;; esac
  hit=$(find "$1/$2" ! -type d -print -quit 2>/dev/null) || return 0
  [ -n "$hit" ]
}

# What removal would delete from a candidate. Sets C_STATE and C_DETAIL (the
# operation and file-list fields of its line). The inventory decides clean;
# the lists are read here because the inventory stops without naming files.
inspect() { # inspect <path> <unreferenced detached HEAD, or empty>
  local path="$1" tmp tmp_in rec xy p skip=false sparse=false sparse_cfg inv rc
  local untracked=() modified=() ignored=() flagged=() disposable=()
  local worktree_refs=() reflog_commits=() log_oids=()
  local last_added="" op=null unref=null refname head_oid has_reflog head_log oid earliest idx
  local found name
  M_LAST="" M_IGNORED=$'\n' M_KEPT=$'\n'
  [ -z "$2" ] || unref="\"$2\""
  if op_probe "$path"; then op="\"$OP_FOUND\""; fi
  tmp=$(mktemp) || lookup_failed mktemp "could not create a temporary file"
  # -uall and core.fsmonitor=false for the reasons worktree-inventory.sh
  # gives: an explicit untracked mode overrides status.showUntrackedFiles=no.
  # -z so a path holding a newline arrives whole and unquoted.
  # --ignored=matching lists a directory an ignore pattern matches once, as
  # dir/, rather than every file under it, so an undeclared .venv/ is one
  # record, not tens of thousands. A directory no pattern matches is still
  # entered, so each ignored file in it, such as a .DS_Store, lists alone.
  git -C "$path" -c core.fsmonitor=false status -uall --porcelain --ignored=matching -z \
    --ignore-submodules=none \
    > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed status "could not read the status of $path"; }
  while IFS= read -r -d '' rec; do
    # A rename or copy record is followed by its source path, which names
    # nothing in the worktree.
    if [ "$skip" = true ]; then skip=false; continue; fi
    xy="${rec:0:2}" p="${rec:3}"
    case "$xy" in
      '??') json_add untracked "$p" ;;
      '!!')
        if match_disposable "$path" "$p" true; then
          [ "$M_PREFIX" = "$last_added" ] || json_add disposable "$M_PREFIX"
          last_added="$M_PREFIX"
        elif holds_entries "$path" "$p"; then
          json_add ignored "$p"
        fi
        ;;
      *)
        json_add modified "$p"
        case "$xy" in R? | C? | ?R | ?C) skip=true ;; esac
        ;;
    esac
  done < "$tmp"
  # The same flag rule as worktree-inventory.sh, which explains it.
  out_exact sparse_cfg git -C "$path" config --bool --get core.sparseCheckout || sparse_cfg=false
  [ "$sparse_cfg" != true ] || sparse=true
  git -C "$path" ls-files -vz --full-name > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed index "could not read the index of $path"; }
  while IFS= read -r -d '' rec; do
    case "$rec" in
      [a-z]\ * | S\ *) ;;
      *) continue ;;
    esac
    p="${rec#? }"
    if [ ! -e "$path/$p" ] && [ ! -L "$path/$p" ] && [ "${rec%% *}" = S ] && [ "$sparse" = true ]; then
      continue
    fi
    json_add flagged "$p"
  done < "$tmp"
  # Per-worktree refs (refs/worktree/* and refs/bisect/*) live only in this
  # worktree's git directory and are deleted with it.
  git -C "$path" for-each-ref --format='%(refname)' refs/worktree/ refs/bisect/ \
    > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed refs "could not list worktree refs in $path"; }
  while IFS= read -r refname; do
    [ -n "$refname" ] || continue
    json_add worktree_refs "$refname"
  done < "$tmp"
  # Commits reachable only from HEAD reflog entries recorded after HEAD first
  # reached its current commit are lost with the worktree's logs/HEAD. Earlier
  # entries (such as pre-merge amends and rebases) are skipped so ordinary
  # merged PR worktrees stay clean.
  head_oid=$(git -C "$path" rev-parse --verify --quiet HEAD 2>/dev/null) \
    || { rm -f "$tmp"; lookup_failed head "could not read HEAD in $path"; }
  has_reflog=false
  # Under the files backend, an empty or unreadable logs/HEAD makes
  # `git rev-list -g HEAD` fall back to the branch's shared reflog, and
  # `git reflog exists HEAD` returns 1 for a symlinked logs/HEAD even though
  # `rev-list -g HEAD` still reads it. Check logs/HEAD on disk first; fall
  # back to `git reflog exists HEAD` when absent (including reftable).
  out_exact head_log git -C "$path" rev-parse --git-path logs/HEAD \
    || { rm -f "$tmp"; lookup_failed reflog "could not resolve HEAD reflog path in $path"; }
  case "$head_log" in /*) ;; *) head_log="$path/$head_log" ;; esac
  if [ -e "$head_log" ] || [ -L "$head_log" ]; then
    [ -f "$head_log" ] && [ -r "$head_log" ] \
      || { rm -f "$tmp"; lookup_failed reflog "could not read HEAD reflog $head_log"; }
    [ ! -s "$head_log" ] || has_reflog=true
  else
    git -C "$path" reflog exists HEAD >/dev/null 2>&1
    rc=$?
    case "$rc" in
      0) has_reflog=true ;;
      1) has_reflog=false ;;
      *) rm -f "$tmp"; lookup_failed reflog "could not check HEAD reflog in $path" ;;
    esac
  fi
  if [ "$has_reflog" = true ]; then
    # The `--` keeps a worktree file named HEAD from making the revision
    # ambiguous, which would fail the whole sweep.
    git -C "$path" rev-list -g HEAD -- > "$tmp" 2>/dev/null \
      || { rm -f "$tmp"; lookup_failed reflog "could not read HEAD reflog in $path"; }
    earliest=-1
    idx=0
    while IFS= read -r oid; do
      [ -n "$oid" ] || continue
      log_oids[idx]="$oid"
      [ "$oid" != "$head_oid" ] || earliest="$idx"
      idx=$((idx + 1))
    done < "$tmp"
    if [ "$earliest" -gt 0 ]; then
      tmp_in=$(mktemp) || { rm -f "$tmp"; lookup_failed mktemp "could not create a temporary file"; }
      for ((idx = 0; idx < earliest; idx++)); do
        [ "${log_oids[idx]}" = "$head_oid" ] || printf '%s\n' "${log_oids[idx]}"
      done > "$tmp_in"
      if [ -s "$tmp_in" ]; then
        git -C "$path" rev-list --stdin --not --single-worktree --exclude='refs/worktree/*' --exclude='refs/bisect/*' --all \
          < "$tmp_in" > "$tmp" 2>/dev/null \
          || { rm -f "$tmp" "$tmp_in"; lookup_failed reflog "could not check HEAD reflog reachability in $path"; }
        while IFS= read -r oid; do
          [ -n "$oid" ] || continue
          json_add reflog_commits "$oid"
        done < "$tmp"
      fi
      rm -f "$tmp_in"
    fi
  fi
  rm -f "$tmp"
  found=$((${#untracked[@]} + ${#modified[@]} + ${#ignored[@]} + ${#flagged[@]} + ${#worktree_refs[@]} + ${#reflog_commits[@]}))
  inv=$("$INVENTORY" "$path" 2>&1)
  rc=$?
  case "$rc:$inv" in
    "0:OK inventory "*) C_STATE=clean ;;
    # The inventory stops at its first finding, so STOP dirty means only that
    # status printed something; it never reaches its flag read. This
    # script's own reads above stand in for it: the stop is accepted only
    # when they found declared disposables and nothing else, the flag read
    # included. A file created between the two reads can still read as
    # clean here; the recheck right before removal narrows that window to
    # the one before `git worktree remove`, which refuses untracked files
    # but deletes ignored ones, as it did before disposables existed.
    "2:STOP dirty "*)
      if [ "${#disposable[@]}" -gt 0 ] && [ "$found" -eq 0 ]; then
        C_STATE=clean
      else
        C_STATE=dirty
      fi
      ;;
    2:*) C_STATE=dirty ;;
    *) lookup_failed inventory "worktree-inventory.sh could not inventory $path: $inv" ;;
  esac
  # Either reader finding something makes it dirty; neither overrules the
  # other toward clean, except for the declared disposables above.
  if [ "$op" != null ] || [ "$unref" != null ] || [ "$found" -gt 0 ]; then
    C_STATE=dirty
  fi
  C_DETAIL="\"operation\":$op,\"unreferenced_head\":$unref"
  for name in untracked modified ignored flagged disposable worktree_refs reflog_commits; do
    json_list "$name"
    C_DETAIL+=",\"$name\":[$JSON_LIST]"
  done
}

# The landing merge: the oldest first-parent merge of the base whose second
# parent is the tip. Sets C_MERGE and C_LANDED.
find_landing() { # find_landing <tip>
  local tip="$1" log m p1 p2 rest subject
  C_MERGE='"none found"' C_LANDED=false
  log=$(git log --first-parent --merges --reverse --format='%H %P' "$tip..$BASE_OID" 2>/dev/null) \
    || lookup_failed merge-log "could not read the merges of $BASE_NAME since $tip"
  while read -r m p1 p2 rest; do
    [ "$p2" = "$tip" ] || continue
    out_exact subject git log -1 --format=%s "$m" \
      || lookup_failed merge-log "could not read the subject of $m"
    C_MERGE="{\"oid\":\"$m\",\"subject\":\"$(json_escape "$subject")\"}"
    C_LANDED=true
    return
  done <<< "$log"
}

# Only mktemp's exact fill of land.sh's template (six alphanumerics) counts,
# so an owner's own land-wt.<name> directory never makes a candidate.
in_land_template() { # in_land_template <path>: <dir>/land-wt.XXXXXX/wt
  local parent="${1%/wt}"
  [ "$parent" != "$1" ] || return 1
  case "${parent##*/}" in
    land-wt.[[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]][[:alnum:]]) return 0 ;;
  esac
  return 1
}

holds_worktree() { # holds_worktree <i>: sets HELD to a registered path under it
  local j
  HELD=""
  for ((j = 0; j < WT_COUNT; j++)); do
    [ "$j" -ne "$1" ] || continue
    case "${WT_PATH[j]}" in
      "${WT_PATH[$1]}"/*) HELD="${WT_PATH[j]}"; return 0 ;;
    esac
  done
  return 1
}

# A submodule keeps its repository in modules/ under this worktree's own git
# directory, so --force deletes commits that may exist nowhere else. It stays
# there after `submodule deinit` or `git rm`, and `ignore = all` hides it from
# status; git's own remove refuses whenever that directory exists. A gitlink
# populated with an embedded .git is checked one by one.
holds_submodule() { # holds_submodule <path>: sets HELD to what it holds
  local path="$1" tmp rec modules
  HELD=""
  out_exact modules git -C "$path" rev-parse --git-path modules \
    || lookup_failed git-dir "could not resolve the git directory of $path"
  case "$modules" in /*) ;; *) modules="$path/$modules" ;; esac
  if [ -d "$modules" ]; then HELD="$modules"; return 0; fi
  tmp=$(mktemp) || lookup_failed mktemp "could not create a temporary file"
  git -C "$path" ls-files -z --stage > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed index "could not read the index of $path"; }
  while IFS= read -r -d '' rec; do
    case "$rec" in 160000\ *) ;; *) continue ;; esac
    rec="${rec#*$'\t'}"
    if [ -e "$path/$rec/.git" ]; then HELD="$path/$rec/.git"; break; fi
  done < "$tmp"
  rm -f "$tmp"
  [ -n "$HELD" ]
}

# Any other .git below the root is a nested repository, untracked or ignored,
# whose commits may exist nowhere else; status names only its directory, and
# under an ignored directory not even that. git never tracks a .git path.
# The one exception is a repository inside an ignored directory that a
# disposables entry matches, such as a package manager's checkout under
# .build/: the project declared it disposable. An untracked one never is.
holds_repository() { # holds_repository <path>: sets HELD to the first one
  local path="$1" tmp g dir
  HELD=""
  M_LAST="" M_IGNORED=$'\n' M_KEPT=$'\n'
  tmp=$(mktemp) || lookup_failed mktemp "could not create a temporary file"
  # -prune: a nested .git is never searched, so its unreadable objects do not
  # fail the run. Without entries the first one decides, as before.
  if [ "$N_DISPOSABLES" -gt 0 ]; then
    find "$path" -mindepth 2 -name .git -prune -print0 > "$tmp" 2>/dev/null
  else
    find "$path" -mindepth 2 -name .git -prune -print0 -quit > "$tmp" 2>/dev/null
  fi \
    || { rm -f "$tmp"; lookup_failed find "could not search $path for nested repositories"; }
  while IFS= read -r -d '' g; do
    dir="${g#"$path"/}"
    dir="${dir%.git}"
    match_disposable "$path" "$dir" false && continue
    HELD="$g"
    break
  done < "$tmp"
  rm -f "$tmp"
  [ -n "$HELD" ]
}

# Classify WT entry <i>. Sets C_CLASS (a non-candidate disposition, or
# "candidate"), C_REASON for a non-candidate, and for a candidate C_STATE,
# C_DETAIL, C_MERGE (empty for a detached one), C_LANDED (false for a
# detached one), and C_DIRTY_OK: whether --remove-dirty may remove it.
classify() { # classify <i>
  local i="$1" path="${WT_PATH[$1]}" ref="${WT_BRANCH[$1]}" tip rc top head holder unref
  C_CLASS="" C_REASON="" C_STATE="" C_DETAIL="" C_MERGE="" C_LANDED=false C_DIRTY_OK=false
  if [ "$MODE" = remove-head ] && [ "$ref" != "refs/heads/$HEAD_BRANCH" ]; then
    C_CLASS=other-branch C_REASON="it does not hold refs/heads/$HEAD_BRANCH"; return
  fi
  if [ "$i" -eq 0 ]; then
    C_CLASS=primary C_REASON="the primary checkout is never a candidate"; return
  fi
  if [ -n "$SELF" ] && [ "$path" -ef "$SELF" ]; then
    C_CLASS=self C_REASON="this command runs in it; run the sweep from another worktree to judge it"; return
  fi
  if holds_caller "$path"; then
    C_CLASS=self C_REASON="the caller's directory $CALLER is inside it; removing it would pull the caller's working directory out from under it"; return
  fi
  # A missing directory is checked as well as the field, which an older git
  # does not print.
  if [ -n "${WT_PRUNABLE[$i]}" ] || [ ! -d "$path" ]; then
    C_CLASS=prunable C_REASON="its directory is gone; git worktree prune is the owner's call"; return
  fi
  if [ -n "${WT_LOCKED[$i]}" ]; then
    C_CLASS=locked C_REASON="it is locked; unlocking it is the owner's call"; return
  fi
  if holds_worktree "$i"; then
    C_CLASS=holds-worktree C_REASON="the worktree at $HELD lies inside it, and removal would delete that one's files too"; return
  fi
  case "$ref" in
    detached)
      if ! in_land_template "$path"; then
        C_CLASS=detached-other C_REASON="a detached worktree outside land's land-wt template"; return
      fi
      # land's own scratch checkout of commits already in the object store.
      C_DIRTY_OK=true
      ;;
    refs/heads/*)
      if [ "$ref" = "$BASE_BRANCH" ]; then
        C_CLASS=base-branch C_REASON="it holds $ref, the base's own branch"; return
      fi
      if ! tip=$(git rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null); then
        C_CLASS=unresolved-branch C_REASON="$ref no longer resolves"; return
      fi
      if [ "$MODE" = remove-head ]; then
        # Commits past the merged head exist only here; the merge kept none
        # of them.
        if [ "$tip" != "$HEAD_OID_OPT" ]; then
          C_CLASS=moved C_REASON="$ref is at $tip, not the merged head $HEAD_OID_OPT"; return
        fi
      else
        git merge-base --is-ancestor "$tip" "$BASE_OID" 2>/dev/null
        rc=$?
        case "$rc" in
          0) ;;
          1) C_CLASS=unmerged C_REASON="$ref is not merged into $BASE_NAME"; return ;;
          *) lookup_failed merge-base "could not compare $ref with $BASE_NAME" ;;
        esac
        find_landing "$tip"
        C_DIRTY_OK="$C_LANDED"
      fi
      ;;
    *)
      C_CLASS=unresolved-branch C_REASON="git reports no branch for it"; return ;;
  esac
  # Every read below is relative to this worktree, so it must be its own
  # working tree root: a per-worktree core.worktree points git elsewhere.
  if ! out_exact top git -C "$path" rev-parse --show-toplevel || [ -z "$top" ]; then
    C_CLASS=unreadable C_REASON="git cannot open it as a working tree"; return
  fi
  if ! [ "$top" -ef "$path" ]; then
    C_CLASS=redirected C_REASON="git resolves its working tree to $top"; return
  fi
  if holds_submodule "$path"; then
    C_CLASS=holds-submodule C_REASON="it holds submodule repository data at $HELD, which removal would delete"; return
  fi
  if holds_repository "$path"; then
    C_CLASS=holds-repository C_REASON="it holds the nested repository $HELD, which removal would delete"; return
  fi
  # A detached HEAD that no ref holds is lost with the worktree's reflog.
  unref=""
  if [ "$ref" = detached ]; then
    head=$(git -C "$path" rev-parse --verify --quiet HEAD 2>/dev/null) \
      || lookup_failed head "could not read HEAD in $path"
    holder=$(git for-each-ref --count=1 --format=x --contains "$head" 2>/dev/null) \
      || lookup_failed refs "could not list the refs that contain $head"
    [ -n "$holder" ] || unref="$head"
  fi
  C_CLASS=candidate
  inspect "$path" "$unref"
}

branch_json() { # branch_json <ref>
  printf '"%s"' "$(json_escape "$1")"
}

emit() { # emit <disposition> <path> <ref> <reason or empty>: uses C_* for a candidate
  local line="{\"path\":\"$(json_escape "$2")\",\"branch\":$(branch_json "$3")"
  if [ "$C_CLASS" = candidate ]; then
    [ -z "$C_MERGE" ] || line+=",\"merge\":$C_MERGE"
    line+=",\"state\":\"$C_STATE\",$C_DETAIL"
  fi
  [ -z "$4" ] || line+=",\"reason\":\"$(json_escape "$4")\""
  echo "WORKTREE $1 $line}"
}

authorized() { # authorized: may this run remove the candidate in C_*?
  [ "$C_CLASS" = candidate ] || return 1
  if [ "$MODE" = remove-head ]; then
    [ "$C_STATE" = clean ]
    return
  fi
  # Only a branch has a landing merge, so a detached land-wt worktree, which
  # a lander starting after the batch's release may be using, is never one.
  if [ "$REMOVE_LANDED" = true ]; then
    [ "$C_STATE" = clean ] && [ "$C_LANDED" = true ]
    return
  fi
  [ "$REMOVE" = true ] || return 1
  [ "$C_STATE" = clean ] && return 0
  [ "$REMOVE_DIRTY" = true ] && [ "$C_DIRTY_OK" = true ]
}

# Read everything before removing anything, so a failed read stops the run
# with every worktree still in place.
scan_worktrees
N_WORKTREES=$WT_COUNT
P_PATH=() P_REF=()
for ((i = 0; i < WT_COUNT; i++)); do
  classify "$i"
  P_PATH[i]="${WT_PATH[i]}" P_REF[i]="${WT_BRANCH[i]}"
  P_CLASS[i]="$C_CLASS" P_REASON[i]="$C_REASON" P_STATE[i]="$C_STATE"
  P_DETAIL[i]="$C_DETAIL" P_MERGE[i]="$C_MERGE" P_LANDED[i]="$C_LANDED"
  P_DIRTY_OK[i]="$C_DIRTY_OK"
  if [ "$C_CLASS" = candidate ]; then
    N_CANDIDATES=$((N_CANDIDATES + 1))
    if [ "$C_STATE" = clean ]; then N_CLEAN=$((N_CLEAN + 1)); else N_DIRTY=$((N_DIRTY + 1)); fi
  fi
done

registered() { # registered <path>: is <path> still a worktree entry?
  local j
  for ((j = 0; j < WT_COUNT; j++)); do
    [ "${WT_PATH[j]}" = "$1" ] && return 0
  done
  return 1
}

HALTED=""
for ((i = 0; i < N_WORKTREES; i++)); do
  path="${P_PATH[i]}" ref="${P_REF[i]}"
  C_CLASS="${P_CLASS[i]}" C_STATE="${P_STATE[i]}" C_DETAIL="${P_DETAIL[i]}"
  C_MERGE="${P_MERGE[i]}" C_LANDED="${P_LANDED[i]}" C_DIRTY_OK="${P_DIRTY_OK[i]}"
  if [ "$C_CLASS" != candidate ]; then
    [ "$C_CLASS" = other-branch ] || emit "$C_CLASS" "$path" "$ref" "${P_REASON[i]}"
    continue
  fi
  if [ -n "$HALTED" ]; then
    N_KEPT=$((N_KEPT + 1))
    emit "$C_STATE" "$path" "$ref" "not attempted: an earlier removal failed"
    continue
  fi
  if ! authorized; then
    N_KEPT=$((N_KEPT + 1))
    if [ "$MODE" = remove-head ]; then
      emit "$C_STATE" "$path" "$ref" "not clean; --remove-head removes only a clean worktree"
    elif [ "$REMOVE_LANDED" = true ]; then
      if [ "$C_STATE" != clean ]; then
        emit "$C_STATE" "$path" "$ref" "dirty; --remove-landed removes only clean worktrees"
      elif [ "$ref" = detached ]; then
        emit "$C_STATE" "$path" "$ref" "a detached land-wt worktree, left for the owner's sweep: a lander may be using it"
      else
        emit "$C_STATE" "$path" "$ref" "clean, but no landing merge was found: a branch with no commits of its own looks the same, so a session may be starting work in it"
      fi
    elif [ "$REMOVE" != true ]; then
      emit "$C_STATE" "$path" "$ref" "dry run"
    elif [ "$REMOVE_DIRTY" != true ]; then
      emit "$C_STATE" "$path" "$ref" "dirty; --remove-dirty would delete the files listed"
    else
      emit "$C_STATE" "$path" "$ref" "dirty, and no landing merge was found: a branch with no commits of its own looks the same, so this may be work in progress"
    fi
    continue
  fi
  # Reclassify right before removing: the worktree may have changed since the
  # first pass. This narrows the race with another process; it cannot close it.
  scan_worktrees
  found=""
  for ((j = 0; j < WT_COUNT; j++)); do
    if [ "${WT_PATH[j]}" = "$path" ]; then found="$j"; break; fi
  done
  if [ -z "$found" ]; then
    N_KEPT=$((N_KEPT + 1))
    emit "$C_STATE" "$path" "$ref" "no longer registered when the removal was due"
    continue
  fi
  classify "$found"
  # Report and count what the recheck found, so each line and the result
  # agree: move this worktree out of its first-pass bucket and into its new
  # one, if it is still a candidate.
  ref="${WT_BRANCH[found]}"
  N_CANDIDATES=$((N_CANDIDATES - 1))
  if [ "${P_STATE[i]}" = clean ]; then N_CLEAN=$((N_CLEAN - 1)); else N_DIRTY=$((N_DIRTY - 1)); fi
  if [ "$C_CLASS" = candidate ]; then
    N_CANDIDATES=$((N_CANDIDATES + 1))
    if [ "$C_STATE" = clean ]; then N_CLEAN=$((N_CLEAN + 1)); else N_DIRTY=$((N_DIRTY + 1)); fi
  fi
  if ! authorized; then
    if [ "$C_CLASS" = candidate ]; then
      N_KEPT=$((N_KEPT + 1))
      emit "$C_STATE" "$path" "$ref" "changed since the first pass and no longer authorized for removal"
    else
      emit "$C_CLASS" "$path" "$ref" "changed since the first pass: $C_REASON"
    fi
    continue
  fi
  # One --force at most: git's own refusal still protects a locked worktree.
  if [ "$C_STATE" = clean ]; then
    err=$(git worktree remove -- "$path" 2>&1 >/dev/null)
  else
    err=$(git worktree remove --force -- "$path" 2>&1 >/dev/null)
  fi
  rc=$?
  scan_worktrees
  if [ "$rc" -eq 0 ] && ! registered "$path" && [ ! -e "$path" ] && [ ! -L "$path" ]; then
    N_REMOVED=$((N_REMOVED + 1))
    emit removed "$path" "$ref" ""
    continue
  fi
  N_KEPT=$((N_KEPT + 1))
  err=$(printf '%s' "$err" | tr -d '\0' | tr '\n\t' '  ' | tail -c 300)
  HALTED="git worktree remove did not remove $path (exit $rc): ${err:-the entry or directory is still there}"
  emit "$C_STATE" "$path" "$ref" "$HALTED"
done

[ -z "$HALTED" ] || stop remove-failed "$HALTED"
echo "OK sweep $(result_json "")"
