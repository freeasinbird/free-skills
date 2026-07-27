#!/usr/bin/env bash
# base-landing-plan.sh: decide how to land on the branch a merged PR went into,
# before anything destructive runs. It inspects the repository and prints a
# plan, and writes nothing itself: it never switches branches, creates a ref,
# fetches, or writes configuration, because running the landing is the skill's
# job (and the user's), while deciding it is a program.
#
# "Writes nothing itself" is the honest form: repository configuration can turn
# a read into an execution. The vectors that reach these reads are closed where
# they can be (no alias is ever expanded, and core.fsmonitor is overridden), but
# asking git whether the tree is clean runs the repository's configured
# filter.<driver>.clean, and nothing switches that off.
#
# The plan is a decision over three axes, the base name's shape, whether a local
# branch exists, and whether the branch carries a complete upstream, behind two
# guards, a dirty tree and a git without `git switch`. Every rule exists because
# the behaviour was reproduced; the evidence, and the reasoning each rule rests
# on, is in references/hazards.md §leading-hyphen-args, §tag-shadow,
# §checkout-detach, and §status-config. Comments below cite the section rather
# than restating it.
#
# Run it before the sequence deletes anything: it is free to run early, and a
# stop found here costs nothing where the same stop found after step 1 leaves
# the remote branch deleted and the workspace still on the merged branch.
#
# Usage:
#   base-landing-plan.sh <base-remote> <base-branch>
#   base-landing-plan.sh --help
#
# The arguments are in git's own order, and neither is treated as an option: an
# option-shaped base branch is the case this script exists for. `--help`, or
# `-h`, is help only as the sole argument, so with both positionals present
# `-h` is a branch name.
#
# Output is one line. Exit codes:
#   0   OK landing {...}       the plan: fetch, verb, create, tracking
#   2   STOP <guard> {...}     do not proceed; the line is what to surface
#   4   LOOKUP_FAILED <what>   a read failed, so no plan was established
#   64  usage on stderr        bad arguments
#   69  note on stderr         git missing, no work tree here, or not bash
set -u

# Byte semantics, globally: the string handling below indexes by byte, and a
# `local LC_ALL=C` does not reach expansions on its own declaration line, so a
# byte count taken there returns a character count. It also keeps grep from
# refusing an invalid byte sequence, which the ref match would read as absence.
export LC_ALL=C

usage() { # usage [reason]
  [ $# -eq 0 ] || echo "base-landing-plan.sh: $1" >&2
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

# Help only as the sole argument: two positionals are required, so a
# two-argument call is never a help request.
if [ $# -le 1 ]; then
  # ${1---help}, not ${1:---help}: the colon form substitutes its default for
  # an empty value as well as an unset one, so a lone "" would print help and
  # exit 0 on a call that named no remote at all.
  case "${1---help}" in
    --help | -h) sed -n '2,/^set -u$/p' "$0" | sed '$d'; exit 0 ;;
  esac
fi
[ $# -eq 2 ] || usage
REMOTE="$1"
BASE="$2"
[ -n "$REMOTE" ] || usage "the base remote is empty"
[ -n "$BASE" ] || usage "the base branch is empty"

command -v git >/dev/null 2>&1 \
  || { echo "base-landing-plan.sh: git is not on PATH" >&2; exit 69; }
# The JSON escaping below is bash substring expansion. Duplicated from
# worktree-inventory.sh rather than shared: each script runs standalone from the
# skill directory.
[ -n "${BASH_VERSION:-}" ] \
  || { echo "base-landing-plan.sh: needs bash for its JSON escaping" >&2; exit 69; }
[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
  || { echo "base-landing-plan.sh: not inside a git work tree" >&2; exit 69; }

# A name git cannot use as a ref names no branch at all, so the plan would
# emit refspecs git rejects. `refs/heads/-x` passes this, which is the point:
# an option-shaped name is well-formed, just unspellable for `git checkout`.
git check-ref-format "refs/heads/$BASE" 2>/dev/null \
  || usage "not a valid branch name: $BASE"

utf8_len() { # utf8_len <string> <byte index>: bytes in the valid UTF-8
  # sequence starting there, or 0 where none does. Second-byte ranges are
  # RFC 3629's, so overlongs, surrogates, and anything past U+10FFFF are
  # invalid, which is what a strict JSON reader makes of them too.
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

utf8_valid() { # utf8_valid <string>
  local LC_ALL=C s="$1" i=0 n len
  n=${#s}
  while [ "$i" -lt "$n" ]; do
    len=$(utf8_len "$s" "$i")
    [ "$len" -gt 0 ] || return 1
    i=$((i + len))
  done
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
    # Whole valid sequences pass through, because JSON is UTF-8 and escaping
    # each byte separately decodes to mojibake. A byte starting no valid
    # sequence is escaped instead, since no JSON string can carry it; the
    # arguments are validated below, so that branch matters for the shared
    # copy in worktree-inventory.sh, whose paths carry arbitrary bytes.
    len=$(utf8_len "$s" "$i")
    if [ "$len" -eq 0 ]; then out+=$(printf '\\u%04x' "$o"); i=$((i + 1)); continue; fi
    out+="${s:i:len}"
    i=$((i + len))
  done
  printf '%s' "$out"
}

# Refused rather than escaped: \u00XX round-trips to a different byte sequence,
# so the caller would fetch a refspec naming nothing. On stderr, since the JSON
# line is precisely what cannot represent the name.
utf8_valid "$REMOTE" || usage "the base remote is not valid UTF-8"
utf8_valid "$BASE" || usage "the base branch is not valid UTF-8"

stop() { # stop <guard> <detail>
  echo "STOP $1 {\"detail\":\"$(json_escape "$2")\"}"
  exit 2
}
lookup_failed() { # lookup_failed <what> <detail>
  echo "LOOKUP_FAILED $1 {\"detail\":\"$(json_escape "$2")\"}"
  exit 4
}

# Valid branch names that no landing command can attach HEAD to: git reads them
# as revision shorthand before refs/heads, so no terminator reaches the
# collision and two of the three land elsewhere at exit 0. Three literals, not a
# pattern; the enumeration behind that, and the spellings that do work, are in
# references/hazards.md §leading-hyphen-args.
case "$BASE" in
  - | @ | HEAD)
    stop unspellable "no git command can attach HEAD to a branch named $BASE: git reads that name as revision shorthand before refs/heads, so the landing would silently take you elsewhere"
    ;;
esac

# An option-shaped name is the one case `git checkout` cannot express. Keep
# checkout everywhere else: `git switch` is still documented as experimental
# (git 2.50.1), so a second switching command earns its place only where the
# first cannot name the branch.
case "$BASE" in
  -*) VERB=switch ;;
  *) VERB=checkout ;;
esac

# Listing builtins, not running `git switch -h`: where switch is not yet a
# builtin an `alias.switch` is expanded, and git runs a `!`-prefixed alias as a
# shell command with the -h appended (references/hazards.md
# §leading-hyphen-args). An alias cannot shadow a builtin, so the list is also
# the honest answer where switch exists. A failed read counts as absent, which
# is fail-safe because absent is a stop taken while nothing has been deleted,
# and --list-cmds predates switch by five releases. Reported before the dirty
# tree, because cleaning the tree cannot fix it.
if [ "$VERB" = switch ]; then
  builtins=$(git --list-cmds=builtins 2>/dev/null) || builtins=""
  case $'\n'"$builtins"$'\n' in
    *$'\n'switch$'\n'*) ;;
    *) stop switch-missing "$BASE can only be switched to with git switch (git 2.23+), which this git does not provide" ;;
  esac
fi

# -uall because status.showUntrackedFiles=no lets the repository switch half
# this guard off (references/hazards.md §status-config). No --ignored: the
# landing commands pass --no-overwrite-ignore, so git aborts by itself.
# --no-optional-locks because a plain status rewrites .git/index to refresh
# stat information, and -c core.fsmonitor=false because git runs a configured
# fsmonitor as a hook even then, both of which this script promises not to do.
st=$(git -c core.fsmonitor=false --no-optional-locks status -uall --porcelain 2>/dev/null) \
  || lookup_failed status "could not read the status of this work tree"
[ -z "$st" ] \
  || stop dirty "the work tree holds uncommitted changes; a checkout would carry them onto $BASE"

# cfg_nonempty <mode> <key>: does the key carry a usable value? The mode is the
# caller's, because git's semantics differ by key and the wrong one passes a
# broken configuration: --get is the effective value of a single-valued key (the
# last set, so origin-then-empty is empty), --get-all only for a genuinely
# multi-valued one. An empty value counts as missing either way, and exit 1 is
# git's "not set"; any other failure is a read that did not happen.
cfg_nonempty() { # cfg_nonempty <--get|--get-all> <key>
  local v rc
  v=$(git config "$1" "$2" 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] \
    || lookup_failed config "could not read $2 (git config exited $rc)"
  # Empty only, not trimmed: whitespace is legal in a Unix path, and a remote
  # URL of three spaces naming a directory that holds a repository is one git
  # fetches through quite happily (verified), so stripping it would refuse a
  # cleanup git can perform.
  [ "$rc" -eq 0 ] && [ -n "$v" ]
}

# Checked even where the landing itself never touches the remote: step 3
# fetches from it in every shape, so a name resolving to nothing strands the
# cleanup after step 1. `--` because a remote is a bare positional.
git remote get-url -- "$REMOTE" >/dev/null 2>&1 \
  || lookup_failed remote "$REMOTE names no remote in this repository"
# Existing is not usable: with the URL empty git falls back to the remote's own
# name, so get-url succeeds while step 3's fetch dies. Read the configured value
# instead. --get-all because remote.<name>.url is genuinely multi-valued and git
# fetches through the first usable entry, skipping an empty one.
cfg_nonempty --get-all "remote.$REMOTE.url" \
  || lookup_failed remote "$REMOTE has no URL configured"

ref_exists() { # ref_exists <namespace> <full-ref>
  # Exact, where `git show-ref --verify` folds case for a loose ref on a
  # case-folding filesystem and would report refs/heads/Main as the existing
  # main. A ref name cannot hold a newline, so a line-wise read is exact.
  #
  # The status is captured before the match rather than left to a pipeline,
  # which would report grep's: a failed enumeration would arrive as "no match"
  # and plan create=true for a branch that exists.
  local refs rc
  refs=$(git for-each-ref --format='%(refname)' "$1" 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] \
    || lookup_failed refs "could not enumerate $1 (git for-each-ref exited $rc)"
  printf '%s\n' "$refs" | grep -qxF -- "$2"
}

# No local branch means the landing has to create one, and creating it is where
# the two verbs diverge.
CREATE=false
ref_exists refs/heads/ "refs/heads/$BASE" || CREATE=true

# A case-folding filesystem cannot hold refs/heads/Main as a file distinct from
# refs/heads/main, so a base differing from an existing branch only in case has
# no safe landing there, and the failure takes two shapes. Against a loose ref
# `checkout -b` refuses outright ("a branch named 'Main' already exists").
# Against a packed one it exits 0 and is worse: the new loose file case-folds
# over the packed entry, so `git rev-parse release` starts reporting Release's
# tip while `for-each-ref` still shows the real one, and the user's branch is
# hijacked under a sequence that then fast-forwards and deletes against it.
# Both land after step 1, which is why the stop happens here.
#
# Two conditions, because either alone gets a case wrong. Whether the filesystem
# folds is probed by asking for $GIT_DIR/head, which resolves only where it
# does: `core.ignoreCase` describes the working tree, not the ref store, and a
# case-sensitive volume whose flag is stale or hand-set creates both refs
# cleanly, so gating on the flag refuses a landing git performs. And whether a
# variant exists has to be a fold over the enumerated refs, not
# `show-ref --verify`, which folds for a loose ref and not a packed one and so
# misses exactly the hijack above. Verified over both volume types and both ref
# storages.
if [ "$CREATE" = true ]; then
  gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) \
    || lookup_failed refs "could not resolve the git directory"
  # First, ask the filesystem. The exact ref is absent (CREATE is true), so a
  # file already sitting at that path means the filesystem aliases the name to
  # some other ref, and this catches every aliasing it does: case folding,
  # Unicode normalization (APFS aliases refs/heads/café onto an existing CAFÉ),
  # and the name being a directory of refs. One stat, no folding rules of our
  # own. It also catches a syntactically broken loose ref, which for-each-ref
  # skips; the detail is worded for the general condition rather than only for
  # case.
  if [ -e "$gitdir/refs/heads/$BASE" ]; then
    stop case-collision "the ref path for $BASE is already occupied in this repository, by a name the filesystem treats as the same one or by a directory of refs, so the landing would either be refused or silently alias that branch"
  fi
  # Then the packed case, which has no file to stat: a loose ref written now
  # would be aliased onto a packed entry at read time. That has to be a fold
  # over the enumerated names, and it is ASCII, so a non-ASCII variant of a
  # *packed* ref is the one shape here that goes undetected; the loose form of
  # the same collision is caught above.
  if [ -e "$gitdir/HEAD" ] && [ -e "$gitdir/head" ]; then
    heads=$(git for-each-ref --format='%(refname)' refs/heads/ 2>/dev/null) \
      || lookup_failed refs "could not enumerate refs/heads/ (git for-each-ref failed)"
    want=$(printf '%s' "refs/heads/$BASE" | tr '[:upper:]' '[:lower:]')
    if printf '%s\n' "$heads" | tr '[:upper:]' '[:lower:]' | grep -qxF -- "$want"; then
      stop case-collision "$BASE differs only in case from a branch this repository already holds, on a filesystem that folds case, so the landing would silently alias that branch"
    fi
  fi
fi

# Reported, not a stop: the create paths name an explicit start-point and
# `git switch` refuses a tag outright, so no landing here detaches. It is
# context for the caller's HEAD confirmation (references/hazards.md
# §tag-shadow, §checkout-detach).
TAG_SHADOW=false
if ref_exists refs/tags/ "refs/tags/$BASE"; then TAG_SHADOW=true; fi

# Both keys, not one: half a pair fast-forwards onto the wrong tip at exit 0
# exactly as none does (references/hazards.md §leading-hyphen-args). A complete
# pair is left alone even when it names something else; that is the user's
# configuration, not a gap to overwrite.
TRACKING=ok
if ! cfg_nonempty --get "branch.$BASE.remote" \
  || ! cfg_nonempty --get "branch.$BASE.merge"; then
  TRACKING='write'
fi

# Only when creating, and then enough to make the start-point exist: a clone
# that verified the merge through the forge need never have fetched the base.
# The switch path takes two refspecs because it cannot create the branch, so the
# name arrives in refs/heads directly and the tracking copy feeds step 3.
FETCH=""
if [ "$CREATE" = true ]; then
  if [ "$VERB" = switch ]; then
    FETCH="\"$(json_escape "refs/heads/$BASE:refs/heads/$BASE")\","
  fi
  FETCH="$FETCH\"$(json_escape "refs/heads/$BASE:refs/remotes/$REMOTE/$BASE")\""
fi

printf 'OK landing {"remote":"%s","base":"%s","verb":"%s","create":%s,"fetch":[%s],"tracking":"%s","tag_shadow":%s}\n' \
  "$(json_escape "$REMOTE")" "$(json_escape "$BASE")" "$VERB" "$CREATE" "$FETCH" "$TRACKING" "$TAG_SHADOW"
