#!/usr/bin/env bash
# worktree-inventory.sh: report state a linked worktree hides, before anyone
# removes it. Read-only by construction: it inspects one worktree and prints a
# verdict. It never removes a worktree, touches a ref, or writes to the index,
# because deciding what to do about hidden work is the skill's job (and the
# user's), while finding it is a program.
#
# `git worktree remove` refuses on "modified or untracked files", which reads
# like a fail-safe and is not one: an ignored file does not trip it, and an
# index-flagged file is invisible to every porcelain form while removal takes
# it with exit 0. Each rule below exists because that gap was reproduced; the
# evidence is in references/hazards.md §worktree-remove-destroys.
#
# Usage:
#   worktree-inventory.sh <worktree-path>
#   worktree-inventory.sh --help
#
# Output is one line. Exit codes:
#   0   OK inventory {...}       nothing hidden; removal is the caller's call
#   2   STOP <guard> {...}       hidden state, or a removal that cannot be safe
#   4   LOOKUP_FAILED <what>     a read failed; absence was never established
#   64  usage on stderr          bad arguments
#   69  note on stderr           git missing, or bash too old for NUL reads
set -u

# Byte semantics, globally rather than per function: the escaping below indexes
# strings by byte, and a `local LC_ALL=C` does not apply to expansions on its
# own declaration line, so a byte count taken there comes back as a character
# count under a UTF-8 locale and the tail of a multibyte path goes unexamined.
export LC_ALL=C

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

case "${1:---help}" in
  --help | -h) sed -n '2,/^set -u$/p' "$0" | sed '$d'; exit 0 ;;
esac
[ $# -eq 1 ] || usage
TARGET="$1"
case "$TARGET" in
  -*) usage ;;  # an option-shaped path is a mistake, not a worktree
esac

command -v git >/dev/null 2>&1 \
  || { echo "worktree-inventory.sh: git is not on PATH" >&2; exit 69; }
# `read -d` is not POSIX (dash rejects it), and the NUL-terminated reads below
# are what keep a path holding a newline intact. Refusing here beats a
# line-oriented fallback that silently mis-pairs exactly those paths.
[ -n "${BASH_VERSION:-}" ] \
  || { echo "worktree-inventory.sh: needs bash for NUL-terminated reads" >&2; exit 69; }

utf8_len() { # utf8_len <string> <byte index>: bytes in the valid UTF-8
  # sequence starting there, or 0 where no valid sequence does. The
  # second-byte ranges are RFC 3629's, so an overlong form, a surrogate, and
  # anything past U+10FFFF all count as invalid, which is what a strict JSON
  # reader does with them too.
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

json_escape() {
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
    # A whole valid sequence is copied through: JSON is UTF-8, so those bytes
    # belong in the line as they are, where \u-escaping each one separately
    # emits escapes that decode to mojibake and name a path that does not
    # exist. A path is not required to be UTF-8 at all, though, and no JSON
    # string can carry a byte that starts no valid sequence, so that byte is
    # escaped: the name it reports back is then lossy, which beats a line the
    # caller cannot parse when the verdict is a stop.
    len=$(utf8_len "$s" "$i")
    if [ "$len" -eq 0 ]; then out+=$(printf '\\u%04x' "$o"); i=$((i + 1)); continue; fi
    out+="${s:i:len}"
    i=$((i + len))
  done
  printf '%s' "$out"
}

out_exact() { # out_exact <var> <cmd...>: capture stdout byte-exactly
  # A plain $( ) strips every trailing newline, and a directory name may end
  # in one: the stripped path then names a different, existing worktree, so
  # the inventory reports on the sibling. The x sentinel keeps the bytes and
  # only git's own delimiting newline is removed.
  local __v="$1"; shift
  local __o
  __o=$("$@" 2>/dev/null && printf x) || return 1
  __o="${__o%x}"
  printf -v "$__v" '%s' "${__o%$'\n'}"
}

stop() { # stop <guard> <detail>
  echo "STOP $1 {\"detail\":\"$(json_escape "$2")\"}"
  exit 2
}
lookup_failed() { # lookup_failed <what> <detail>
  echo "LOOKUP_FAILED $1 {\"detail\":\"$(json_escape "$2")\"}"
  exit 4
}

[ -d "$TARGET" ] || stop no-worktree "$TARGET is not a directory"

# The worktree root, not whatever subdirectory was passed: every path below is
# resolved against it, and `ls-files --full-name` reports relative to it.
out_exact ROOT git -C "$TARGET" rev-parse --show-toplevel \
  || lookup_failed worktree "could not resolve a worktree at $TARGET"
[ -n "$ROOT" ] || lookup_failed worktree "$TARGET has no working tree (bare or detached from one)"

# Removing the worktree the shell stands in exits 0 and unlinks the current
# directory, so the next command in the sequence dies. Compare by inode: a
# string comparison misses a symlinked or differently spelled path.
out_exact SELF git rev-parse --show-toplevel || SELF=
if [ -n "$SELF" ] && [ "$SELF" -ef "$ROOT" ]; then
  stop self-target "$ROOT is the worktree this command is running in; inventory and remove it from outside"
fi

# -uall is load-bearing: status.showUntrackedFiles=no empties the porcelain
# forms, so a guard that inherits repository configuration can be switched off
# by the repository it protects (references/hazards.md §status-config).
# -c core.fsmonitor=false because git runs a configured fsmonitor as a hook
# during status, which would let the inspected repository's own configuration
# execute code from inside a check that exists to be safe to run.
inv=$(git -C "$ROOT" -c core.fsmonitor=false status -uall --porcelain --ignored 2>/dev/null) \
  || lookup_failed status "could not read the status of $ROOT"
[ -z "$inv" ] \
  || stop dirty "$ROOT holds modified, untracked, or ignored files; removal would delete them"

# Sparse checkout marks every excluded path skip-worktree while leaving it
# absent, which is the one absence that is not a hidden deletion. Read it from
# the target worktree: the setting is per-worktree.
# --bool because git accepts every boolean spelling (`yes`, `on`, `1`), while
# --get returns the raw string: comparing that against "true" reports an
# ordinary sparse worktree as hidden work. A read that fails is not sparse,
# which is the fail-safe direction (nothing gets exempted).
sparse=false
out_exact sparse_cfg git -C "$ROOT" config --bool --get core.sparseCheckout || sparse_cfg=false
[ "$sparse_cfg" != true ] || sparse=true

# `ls-files -v` prints every cached file (`H` for an ordinary one), so the tag
# decides; lowercase means assume-unchanged, `S` means skip-worktree. `-z`
# because the non-NUL form C-quotes a path holding a newline or tab, and
# --full-name because a path is otherwise relative to the caller's cwd.
tmp=$(mktemp) || lookup_failed mktemp "could not create a temporary file"
git -C "$ROOT" ls-files -vz --full-name > "$tmp" 2>/dev/null \
  || { rm -f "$tmp"; lookup_failed index "could not read the index of $ROOT"; }
flagged=0
first=""
while IFS= read -r -d '' rec; do
  case "$rec" in
    [a-z]\ * | S\ *) ;;
    *) continue ;;
  esac
  tag="${rec%% *}"
  path="${rec#? }"
  if [ -e "$ROOT/$path" ] || [ -L "$ROOT/$path" ]; then
    # Present: the flag means git stopped checking it, so no inventory can
    # decide whether its contents differ. Presence is the finding.
    :
  elif [ "$tag" = S ] && [ "$sparse" = true ]; then
    continue  # an ordinary sparse exclusion: nothing is there to lose
  fi
  flagged=$((flagged + 1))
  [ -n "$first" ] || first="$path"
done < "$tmp"
rm -f "$tmp"
[ "$flagged" -eq 0 ] \
  || stop flagged "$flagged file(s) in $ROOT carry assume-unchanged or skip-worktree, starting with $first; their edits and deletions are invisible to status"

echo "OK inventory {\"worktree\":\"$(json_escape "$ROOT")\",\"sparse\":$sparse}"
