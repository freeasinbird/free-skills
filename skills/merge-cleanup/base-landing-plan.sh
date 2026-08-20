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
# Run it immediately before landing. A stop leaves both branches intact, and a
# second run after checkout reads the tracking and remote configuration active
# under the base branch.
#
# Usage:
#   base-landing-plan.sh <base-remote> <base-branch>
#   base-landing-plan.sh --format nul <base-remote> <base-branch>
#   base-landing-plan.sh --help
#
# The arguments are in git's own order, and neither is treated as an option: an
# option-shaped base branch is the case this script exists for. `--help`, or
# `-h`, is help only as the sole argument, so with both positionals present
# `-h` is a branch name.
#
# Default output is one line. `--format nul` emits the successful plan as
# NUL-delimited fields for an executable caller; stop and failure output stays
# human-readable. Exit codes:
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
FORMAT=json
if [ $# -eq 4 ] && [ "$1" = --format ]; then
  FORMAT="$2"; shift 2
  case "$FORMAT" in json|nul) ;; *) usage "--format must be json or nul" ;; esac
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
git check-ref-format "refs/remotes/$REMOTE/$BASE" 2>/dev/null \
  || usage "the base remote and branch do not form a valid remote-tracking ref: refs/remotes/$REMOTE/$BASE"

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

# Checked even where the landing itself never touches the remote: step 2
# fetches from it in every shape. `--` because a remote is a bare positional.
git remote get-url -- "$REMOTE" >/dev/null 2>&1 \
  || lookup_failed remote "$REMOTE names no remote in this repository"
# Existing is not usable: with the URL empty git falls back to the remote's own
# name, so get-url succeeds while step 2's fetch dies. Read the configured value
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

# A case-folding filesystem cannot hold refs/heads/Main as a file distinct from
# refs/heads/main, so a base differing from an existing branch only in case has
# no safe landing there, and the failure takes two shapes. Against a loose ref
# `checkout -b` refuses outright ("a branch named 'Main' already exists").
# Against a packed one it exits 0 and is worse: the new loose file case-folds
# over the packed entry, so `git rev-parse release` starts reporting Release's
# tip while `for-each-ref` still shows the real one, and the user's branch is
# hijacked under a sequence that then fast-forwards and deletes against it.
# Stop before either create reaches the ref store.
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
# The *common* git directory, not this worktree's. In a linked worktree
# --absolute-git-dir points at .git/worktrees/<id>, which holds the
# per-worktree refs (HEAD, refs/bisect) while branches and remote-tracking
# refs live in the common directory, so stats rooted at the private one see
# none of the refs this guard is about. That matters here rather than in
# theory: the skill's own relocate rule runs step 1 inside a linked worktree.
# --git-common-dir predates --path-format=absolute and returns a path relative
# to the current directory, so resolve that answer ourselves instead of probing
# an option that older git echoes as data while exiting 0.
gitdir=$(git rev-parse --git-common-dir 2>/dev/null) \
  || lookup_failed refs "could not resolve the common git directory"
case "$gitdir" in /*) ;; *) gitdir="$PWD/$gitdir" ;; esac

# Files repositories expose loose refs beneath the common directory. Reftable
# repositories instead put a backend marker at .git/refs/heads and expose no
# read-only API that lists dangling symbolic refs. Extensions are active only
# for repository format 1, and only from the repository config: an inherited
# key, or a local key under format 0, does not select a backend for Git itself.
repo_format=$(git config --local --type=int --get core.repositoryFormatVersion 2>/dev/null)
rc=$?
if [ "$rc" -eq 1 ]; then repo_format=0
elif [ "$rc" -ne 0 ]; then
  lookup_failed refs "could not determine the repository format (git config exited $rc)"
fi
case "$repo_format" in
  0) ref_storage=files ;;
  1)
    ref_storage=$(git config --local --get extensions.refStorage 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 1 ]; then ref_storage=files
    elif [ "$rc" -ne 0 ]; then
      lookup_failed refs "could not determine the repository's ref storage (git config exited $rc)"
    fi
    ;;
  *) lookup_failed refs "unsupported repository format version: $repo_format" ;;
esac
# A prepared-and-aborted update-ref transaction can query reftable, but it
# writes a lock that an interruption can strand. Stop explicitly rather than
# either misreading the backend marker as a ref conflict or violating this
# plan's no-write contract.
case "$ref_storage" in
  files) ;;
  reftable)
    stop ref-storage "reftable cannot be checked for unresolvable namespace conflicts without preparing a ref transaction, which would write a lock inside this read-only plan"
    ;;
  *) lookup_failed refs "unsupported ref storage: $ref_storage" ;;
esac

# Git 2.43 can open special loose entries while enumerating refs. Inspect the
# whole loose tree before the first for-each-ref, not only the two destinations:
# an unrelated FIFO is still reachable from the broad refs/ scan below. Direct
# special nodes and symlinks to anything other than a regular file block; a
# dangling symlink fails fast in Git and remains safe for the destination rules
# below to classify. Capture find's status so an unreadable tree is not treated
# as clean.
loose_refs_special() {
  local root="$gitdir/refs" hit links link ref rc
  [ ! -L "$root" ] || return 0
  if [ -d "$root" ]; then :
  elif [ -e "$root" ]; then return 0
  else return 1
  fi
  hit=$(find "$root" ! -type d ! -type f ! -type l -print 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] \
    || lookup_failed refs "could not inspect special entries beneath $root (find exited $rc)"
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    ref="${link#"$gitdir/"}"
    git check-ref-format "$ref" >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 1 ] \
      || lookup_failed refs "could not validate loose ref path $ref (git check-ref-format exited $rc)"
  done <<SPECIAL_EOF
$hit
SPECIAL_EOF
  links=$(find "$root" -type l -print 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] \
    || lookup_failed refs "could not inspect symlinks beneath $root (find exited $rc)"
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    if [ -e "$link" ] && [ ! -f "$link" ]; then
      ref="${link#"$gitdir/"}"
      git check-ref-format "$ref" >/dev/null 2>&1
      rc=$?
      [ "$rc" -eq 0 ] && return 0
      [ "$rc" -eq 1 ] \
        || lookup_failed refs "could not validate loose ref path $ref (git check-ref-format exited $rc)"
    fi
  done <<LINKS_EOF
$links
LINKS_EOF
  return 1
}
if loose_refs_special; then
  stop ref-conflict "the loose ref tree contains a special entry that Git ref enumeration could block on or follow outside the ref store"
fi

# No local branch means the landing has to create one, and creating it is where
# the two verbs diverge. This enumeration runs only after the loose tree is
# known not to contain an entry that Git could block on while reading.
CREATE=false
ref_exists refs/heads/ "refs/heads/$BASE" || CREATE=true

# A ref cannot also be a directory of refs, so the create fails both when an
# existing ref is a path prefix of the destination (release blocking
# release/next) and when existing refs live beneath it (release/next blocking
# release). The ref store enforces that for packed refs too, where there is no
# directory to stat, so this is a comparison over enumerated names rather than
# more stats. Ref names cannot hold glob metacharacters (check-ref-format
# rejects them), so they are safe as `case` patterns.
#
# Enumerated from refs/ rather than from each destination's own namespace,
# because an ancestor can sit at or above the namespace boundary and a
# narrower scan cannot see it: refs/remotes/origin existing as a ref blocks
# the fetch's refs/remotes/origin/release, and refs/heads existing as a ref
# blocks refs/heads/release, both verified. Tags come along harmlessly, since
# no refs/tags name can be a path prefix of a branch or remote-tracking ref.
all_refs=$(git for-each-ref --format='%(refname)' refs/ 2>/dev/null) \
  || lookup_failed refs "could not enumerate refs/ (git for-each-ref failed)"
ref_listed() { # ref_listed <full-ref>
  printf '%s\n' "$all_refs" | grep -qxF -- "$1"
}
ref_symbolic() { # ref_symbolic <full-ref>
  local rc
  git symbolic-ref -q "$1" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  [ "$rc" -eq 1 ] && return 1
  lookup_failed refs "could not inspect whether $1 is symbolic"
}
df_conflict() { # df_conflict <full-ref>
  local r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$1" in "$r"/*) return 0 ;; esac
    case "$r" in "$1"/*) return 0 ;; esac
  done <<DF_EOF
$all_refs
DF_EOF
  return 1
}
# A loose alias is visible by stating the destination path, but a packed ref
# leaves no path for the filesystem to answer with. On a folding filesystem,
# compare the enumerated names after an ASCII fold and exclude the exact name,
# which is an ordinary ref the fetch may update. The fold is deliberately only
# the packed fallback; non-ASCII loose aliases are caught by path_occupied.
case_alias() { # case_alias <full-ref>
  local want r folded
  [ -e "$gitdir/HEAD" ] && [ -e "$gitdir/head" ] || return 1
  want=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    [ "$r" = "$1" ] && continue
    folded=$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')
    [ "$folded" = "$want" ] && return 0
  done <<CASE_EOF
$all_refs
CASE_EOF
  return 1
}
# Every proper ancestor path, stated directly in a files repository, because an
# enumeration cannot see a ref it fails to resolve: `git for-each-ref` omits a
# dangling symbolic ref (or a broken one) while still exiting 0, yet the entry
# is there and the ref store still refuses to create anything beneath it. Walk
# top-down so a failed traversal is a lookup failure rather than a false
# absence. Any non-directory entry blocks; a symlink is stopped even where it
# resolves to a directory, because otherwise git follows it and writes the new
# ref outside the common git directory.
ancestor_occupied() { # ancestor_occupied <full-ref>
  local rest="$1" cursor="$gitdir" component next
  while :; do
    case "$rest" in */*) ;; *) return 1 ;; esac
    component="${rest%%/*}"
    rest="${rest#*/}"
    [ -d "$cursor" ] && [ -x "$cursor" ] \
      || lookup_failed refs "could not inspect ref paths beneath $cursor"
    next="$cursor/$component"
    [ ! -L "$next" ] || return 0
    if [ -d "$next" ]; then cursor="$next"
    elif [ -e "$next" ]; then return 0
    else return 1
    fi
  done
}

# The destination itself has three safe shapes in a files repository: absent,
# an existing direct ref that the fetch may update, or a tree containing only
# empty directories that git can prune. An unresolvable loose entry or any
# non-directory descendant blocks. Capture find's own status rather than a
# pipeline's, so an unreadable tree fails closed.
path_occupied() { # path_occupied <full-ref>
  local path="$gitdir/$1" hit rc
  # At the exact destination, git replaces either a dangling symlink or one
  # that resolves to an enumerated direct ref; it does not write through to the
  # target file. A symlink to a directory instead blocks the update as a
  # non-empty directory, and an unenumerated target is not known to be a ref.
  if [ -L "$path" ]; then
    [ ! -e "$path" ] && return 1
    if [ -f "$path" ] && ref_listed "$1"; then return 1; fi
    return 0
  fi
  if [ -d "$path" ]; then
    hit=$(find "$path" ! -type d -print 2>/dev/null)
    rc=$?
    [ "$rc" -eq 0 ] \
      || lookup_failed refs "could not inspect entries beneath $path (find exited $rc)"
    [ -n "$hit" ]
    return
  fi
  [ -e "$path" ] || return 1
  ref_listed "$1" && return 1
  return 0
}

# The remote-tracking destination is checked whatever the landing does, because
# step 2 fetches into refs/remotes/<remote>/<base> on every cleanup, not only
# when the local branch had to be created. Verified: with a local main present
# (so nothing is created) and refs/remotes/origin occupied as a ref, the plan
# passed and step 2's fetch failed on the lock.
remote_ref="refs/remotes/$REMOTE/$BASE"
if ancestor_occupied "$remote_ref" || path_occupied "$remote_ref" \
  || df_conflict "$remote_ref"; then
  stop ref-conflict "the remote-tracking ref the resync fetches into, refs/remotes/$REMOTE/$BASE, collides with an existing ref that is a path prefix of it or lives beneath it"
fi
if ref_symbolic "$remote_ref"; then
  stop ref-conflict "the remote-tracking destination, $remote_ref, is symbolic and the resync fetch would update its target instead of an ordinary tracking ref"
fi
if case_alias "$remote_ref"; then
  stop case-collision "$remote_ref differs only in case from a tracking ref this repository already holds, on a filesystem that folds case, so the resync fetch would silently alias that ref"
fi

branch_ref="refs/heads/$BASE"
if path_occupied "$branch_ref"; then
  stop ref-conflict "$BASE cannot be used as a branch here: its exact loose-ref path contains an entry that is not a direct ref Git can safely update"
fi
if ref_symbolic "$branch_ref"; then
  stop ref-conflict "$BASE is a symbolic branch ref, so landing on it would attach HEAD to its target rather than refs/heads/$BASE"
fi
if [ "$CREATE" = true ]; then
  if ancestor_occupied "$branch_ref" || df_conflict "$branch_ref"; then
    stop ref-conflict "$BASE cannot be created as a branch here: an existing ref is either a path prefix of refs/heads/$BASE or lives beneath it, and one ref name cannot also be a directory of refs"
  fi
  # Then the packed case, which has no file to stat. A loose ref written now
  # would be aliased onto the packed entry at read time.
  if case_alias "$branch_ref"; then
    stop case-collision "$BASE differs only in case from a branch this repository already holds, on a filesystem that folds case, so the landing would silently alias that branch"
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
# Do not write a branch or remote-tracking ref before checkout activates
# onbranch config. The caller creates either branch from FETCH_HEAD with an
# absence check, then guards the effective remote namespace and writes its
# tracking ref during resync.
FETCH=""
if [ "$CREATE" = true ]; then
  FETCH="\"$(json_escape "refs/heads/$BASE")\""
fi

if [ "$FORMAT" = nul ]; then
  fetch_count=0
  [ "$CREATE" != true ] || fetch_count=1
  printf 'OK landing\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0' \
    "$REMOTE" "$BASE" "$VERB" "$CREATE" "$TRACKING" "$TAG_SHADOW" "$fetch_count"
  if [ "$CREATE" = true ]; then
    printf '%s\0' "refs/heads/$BASE"
  fi
else
  printf 'OK landing {"remote":"%s","base":"%s","verb":"%s","create":%s,"fetch":[%s],"tracking":"%s","tag_shadow":%s}\n' \
    "$(json_escape "$REMOTE")" "$(json_escape "$BASE")" "$VERB" "$CREATE" "$FETCH" "$TRACKING" "$TAG_SHADOW"
fi
