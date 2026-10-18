#!/usr/bin/env bash
# worktree-sweep.sh: list the linked worktrees that are safe to remove after a
# batch of landings, report what each removal would delete, and remove only
# what the owner authorized for this run. Removal is destructive, so the
# default is a dry run and every removal is rechecked just before it happens.
# The owner runs it, never merge-cleanup or a landing batch.
#
# Usage:
#   worktree-sweep.sh [--base <ref>] [--remove [--remove-dirty]]
#   worktree-sweep.sh --help
#
#   --base <ref>     the ref a branch must be merged into. Default: the
#                    branch refs/remotes/origin/HEAD points at. The script
#                    never fetches, so fetch first: a stale base only keeps
#                    more worktrees.
#   --remove         remove the clean candidates. Without it, nothing changes.
#   --remove-dirty   with --remove, also remove the dirty candidates, deleting
#                    the files the report lists. Alone, a usage error.
#
# A candidate is a linked worktree on a branch whose tip is an ancestor of the
# base, or a detached worktree at land's <tmp>/land-wt.XXXXXX/wt template.
# Never a candidate: the primary checkout, the worktree this runs in, a locked
# worktree, one whose directory is gone (prunable), one that holds another
# registered worktree, a submodule repository, populated or not, or a nested
# repository (removal deletes them too), one on the base branch, an unmerged
# branch, or a branch that no longer resolves, one git resolves to another
# working tree, and any other detached worktree.
#
# A candidate is clean when worktree-inventory.sh reports OK inventory and no
# operation is paused in it and, for a detached one, a ref holds its HEAD;
# anything else is dirty. A dirty branch candidate
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
# unresolved-branch, unreadable, redirected, or detached-other. A candidate's
# line carries merge (the landing merge's oid and subject, or "none found"),
# state, operation, unreferenced_head (a detached HEAD no ref holds, or null),
# and the untracked, modified, ignored, and flagged paths removal would delete.
#
# Then one result line, whose counts are worktrees, candidates, clean, dirty,
# removed, and kept (candidates left in place), each worktree counted as its
# last check found it. Exit codes:
#   0   OK sweep {...}             the run finished
#   2   STOP <guard> {...}         no-base, or remove-failed (nothing after it
#                                  was attempted)
#   4   LOOKUP_FAILED <what> {...} a read failed; nothing after it was removed
#   64  usage on stderr            bad arguments
#   69  note on stderr             git or the inventory missing, or not bash
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

BASE_OPT="" REMOVE=false REMOVE_DIRTY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      [ $# -ge 2 ] || { echo "worktree-sweep.sh: --base requires a value" >&2; usage; }
      case "$2" in
        '' | -*) echo "worktree-sweep.sh: --base needs a ref, not '$2'" >&2; usage ;;
      esac
      BASE_OPT="$2"; shift 2 ;;
    --remove) REMOVE=true; shift ;;
    --remove-dirty) REMOVE_DIRTY=true; shift ;;
    *) echo "worktree-sweep.sh: unknown argument: $1" >&2; usage ;;
  esac
done
# Two flags, so deleting files the owner may still want always takes a
# separate, deliberate word on the command line.
if [ "$REMOVE_DIRTY" = true ] && [ "$REMOVE" != true ]; then
  echo "worktree-sweep.sh: --remove-dirty only widens --remove; pass both" >&2
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
  b=$(($(printf '%d' "'${s:i:1}") & 255))
  if [ "$b" -lt 128 ]; then echo 1; return; fi
  if [ "$b" -ge 194 ] && [ "$b" -le 223 ]; then need=1; lo=128; hi=191
  elif [ "$b" -eq 224 ]; then need=2; lo=160; hi=191
  elif [ "$b" -ge 225 ] && [ "$b" -le 236 ]; then need=2; lo=128; hi=191
  elif [ "$b" -eq 237 ]; then need=2; lo=128; hi=159
  elif [ "$b" -ge 238 ] && [ "$b" -le 239 ]; then need=2; lo=128; hi=191
  elif [ "$b" -eq 240 ]; then need=3; lo=144; hi=191
  elif [ "$b" -ge 241 ] && [ "$b" -le 243 ]; then need=3; lo=128; hi=191
  elif [ "$b" -eq 244 ]; then need=3; lo=128; hi=143
  else echo 0; return
  fi
  [ $((i + need)) -lt "$n" ] || { echo 0; return; }
  for ((k = 1; k <= need; k++)); do
    b2=$(($(printf '%d' "'${s:i+k:1}") & 255))
    if [ "$k" -eq 1 ]; then
      { [ "$b2" -ge "$lo" ] && [ "$b2" -le "$hi" ]; } || { echo 0; return; }
    else
      { [ "$b2" -ge 128 ] && [ "$b2" -le 191 ]; } || { echo 0; return; }
    fi
  done
  echo $((need + 1))
}

json_escape() { # copied from worktree-inventory.sh, which explains the rules
  local LC_ALL=C s="$1" out="" i=0 n c o len
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
    o=$(($(printf '%d' "'$c") & 255))
    if [ "$o" -lt 32 ]; then out+=$(printf '\\u%04x' "$o"); i=$((i + 1)); continue; fi
    if [ "$o" -lt 128 ]; then out+="$c"; i=$((i + 1)); continue; fi
    len=$(utf8_len "$s" "$i")
    if [ "$len" -eq 0 ]; then out+=$(printf '\\u%04x' "$o"); i=$((i + 1)); continue; fi
    out+="${s:i:len}"
    i=$((i + len))
  done
  printf '%s' "$out"
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

N_WORKTREES=0 N_CANDIDATES=0 N_CLEAN=0 N_DIRTY=0 N_REMOVED=0 N_KEPT=0
BASE_NAME="" BASE_OID=""

result_json() { # result_json <detail>
  printf '{"base":"%s","base_oid":"%s","mode":"%s","worktrees":%d,"candidates":%d,"clean":%d,"dirty":%d,"removed":%d,"kept":%d,"detail":"%s"}' \
    "$(json_escape "$BASE_NAME")" "$BASE_OID" "$MODE" "$N_WORKTREES" \
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

git rev-parse --git-dir >/dev/null 2>&1 \
  || lookup_failed repository "not inside a git repository"

# Pin the base once, so every worktree in the run is judged against the same
# commit even if a fetch lands mid-run.
if [ -n "$BASE_OPT" ]; then
  BASE_NAME="$BASE_OPT"
else
  out_exact BASE_NAME git symbolic-ref -q refs/remotes/origin/HEAD \
    || stop no-base "refs/remotes/origin/HEAD is not set; pass --base <ref> to name the branch that merged branches land on"
fi
BASE_OID=$(git rev-parse --verify --quiet "$BASE_NAME^{commit}" 2>/dev/null) \
  || stop no-base "$BASE_NAME does not resolve to a commit; fetch, or pass --base <ref>"

# The local branch the base stands for (main for origin/main), whose worktree
# is the owner's checkout of the default branch, not a merged branch's. A
# remote's name may hold a slash, so the longest configured remote that
# prefixes the ref is the one stripped.
BASE_BRANCH=$(git rev-parse --symbolic-full-name "$BASE_NAME" 2>/dev/null) || BASE_BRANCH=""
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

# The worktree this command runs in: removing it unlinks the shell's current
# directory. Compared by inode, as worktree-inventory.sh does.
out_exact SELF git rev-parse --show-toplevel || SELF=""

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

json_add() { # json_add <var> <path>: append a JSON string to a list body
  local __cur
  eval "__cur=\${$1}"
  if [ -n "$__cur" ]; then __cur+=","; fi
  __cur+="\"$(json_escape "$2")\""
  printf -v "$1" '%s' "$__cur"
}

# What removal would delete from a candidate. Sets C_STATE and C_DETAIL (the
# operation and file-list fields of its line). The inventory decides clean;
# the lists are read here because the inventory stops without naming files.
inspect() { # inspect <path> <unreferenced detached HEAD, or empty>
  local path="$1" tmp rec xy p skip=false sparse=false sparse_cfg inv rc
  local untracked="" modified="" ignored="" flagged="" op=null unref=null
  [ -z "$2" ] || unref="\"$2\""
  if op_probe "$path"; then op="\"$OP_FOUND\""; fi
  tmp=$(mktemp) || lookup_failed mktemp "could not create a temporary file"
  # -uall and core.fsmonitor=false for the reasons worktree-inventory.sh
  # gives; -z so a path holding a newline arrives whole and unquoted.
  git -C "$path" -c core.fsmonitor=false status -uall --porcelain --ignored -z \
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
      '!!') json_add ignored "$p" ;;
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
  rm -f "$tmp"
  inv=$("$INVENTORY" "$path" 2>&1)
  rc=$?
  case "$rc:$inv" in
    "0:OK inventory "*) C_STATE=clean ;;
    2:*) C_STATE=dirty ;;
    *) lookup_failed inventory "worktree-inventory.sh could not inventory $path: $inv" ;;
  esac
  # Either reader finding something makes it dirty; neither overrules the
  # other toward clean.
  if [ "$op" != null ] || [ "$unref" != null ] || [ -n "$untracked$modified$ignored$flagged" ]; then
    C_STATE=dirty
  fi
  C_DETAIL="\"operation\":$op,\"unreferenced_head\":$unref,\"untracked\":[$untracked],\"modified\":[$modified],\"ignored\":[$ignored],\"flagged\":[$flagged]"
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
holds_repository() { # holds_repository <path>: sets HELD to the first one
  local path="$1" tmp
  HELD=""
  tmp=$(mktemp) || lookup_failed mktemp "could not create a temporary file"
  find "$path" -mindepth 2 -name .git -print0 -quit > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed find "could not search $path for nested repositories"; }
  IFS= read -r -d '' HELD < "$tmp"
  rm -f "$tmp"
  [ -n "$HELD" ]
}

# Classify WT entry <i>. Sets C_CLASS (a non-candidate disposition, or
# "candidate"), C_REASON for a non-candidate, and for a candidate C_STATE,
# C_DETAIL, C_MERGE (empty for a detached one), and C_DIRTY_OK: whether
# --remove-dirty may remove it.
classify() { # classify <i>
  local i="$1" path="${WT_PATH[$1]}" ref="${WT_BRANCH[$1]}" tip rc top head holder unref
  C_CLASS="" C_REASON="" C_STATE="" C_DETAIL="" C_MERGE="" C_DIRTY_OK=false
  if [ "$i" -eq 0 ]; then
    C_CLASS=primary C_REASON="the primary checkout is never a candidate"; return
  fi
  if [ -n "$SELF" ] && [ "$path" -ef "$SELF" ]; then
    C_CLASS=self C_REASON="this command runs in it; run the sweep from another worktree to judge it"; return
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
      git merge-base --is-ancestor "$tip" "$BASE_OID" 2>/dev/null
      rc=$?
      case "$rc" in
        0) ;;
        1) C_CLASS=unmerged C_REASON="$ref is not merged into $BASE_NAME"; return ;;
        *) lookup_failed merge-base "could not compare $ref with $BASE_NAME" ;;
      esac
      find_landing "$tip"
      C_DIRTY_OK="$C_LANDED"
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
  [ "$C_CLASS" = candidate ] && [ "$REMOVE" = true ] || return 1
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
  P_DETAIL[i]="$C_DETAIL" P_MERGE[i]="$C_MERGE" P_DIRTY_OK[i]="$C_DIRTY_OK"
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
  C_MERGE="${P_MERGE[i]}" C_DIRTY_OK="${P_DIRTY_OK[i]}"
  if [ "$C_CLASS" != candidate ]; then
    emit "$C_CLASS" "$path" "$ref" "${P_REASON[i]}"
    continue
  fi
  if [ -n "$HALTED" ]; then
    N_KEPT=$((N_KEPT + 1))
    emit "$C_STATE" "$path" "$ref" "not attempted: an earlier removal failed"
    continue
  fi
  if ! authorized; then
    N_KEPT=$((N_KEPT + 1))
    if [ "$REMOVE" != true ]; then
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
