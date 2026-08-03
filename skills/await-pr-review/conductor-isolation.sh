#!/usr/bin/env bash
# conductor-isolation.sh: establish and tear down the isolated checkout a
# review conductor owns (await-pr-review, step 4). The conductor rewrites
# and force-pushes the PR branch across a whole exchange while the main
# agent's thread stays free, so the two must not share a mutable checkout.
#
# This exists as a script rather than skill prose because the correct
# command depends on the route taken and the state found, and each wrong
# branch of that conditional fails in its own way: a fork PR's head is
# served by the base repository while its branch lives in the fork, a
# worktree cannot check out a branch another worktree holds, worktree
# removal rejects a separate clone, --ff-only is not a cleanliness guard,
# and a folded (rewritten) history is never a fast-forward. Prose kept
# re-deriving those branches one review finding at a time.
#
# Usage:
#   conductor-isolation.sh setup --path <dir> --repo owner/name --pr N
#     [--head <sha>]      # skip host resolution, use this head
#     [--branch <name>]   # skip host resolution, use this branch
#     [--head-remote <u>] # where the PR head's BRANCH lives (URL or remote
#                         # name). Required for a fork PR whenever --head
#                         # and --branch skip host resolution, which is the
#                         # only other way this is learned.
#     [--remote origin]   # BASE remote: it serves refs/pull/<n>/head even
#                         # when the PR head lives in a fork
#
#   conductor-isolation.sh teardown --path <dir>
#     [--realign]         # also move the primary checkout's local branch
#                         # to the pushed head, under the guards below
#     [--branch <name>]   # what to realign when no setup recorded it (a
#                         # clone made by hand). Without the recorded setup
#                         # head, only a fast-forward realign is served.
#     [--at-setup <sha>]  # the head the branch had before the exchange,
#                         # when no setup recorded it. Realigning a
#                         # rewritten (folded) history needs this proof
#                         # that the branch gained nothing unseen.
#     [--expect <sha>]    # the head the conductor's checkout ended on,
#                         # when neither that checkout nor a recorded
#                         # teardown is left to read it from. Realign
#                         # refuses if the remote branch holds anything
#                         # else, since someone else pushed it.
#     [--remote origin]   # where the pushed BRANCH is fetched from when
#                         # no setup record names it. On a fork PR this
#                         # must name the fork: the base repository does
#                         # not carry that branch, and a same-named base
#                         # branch there is an unrelated commit.
#
# Run both from the primary checkout, never from inside <dir>: git has no
# self-target check, so removing the worktree a session stands in unlinks
# that directory and still exits 0.
#
# Prints one report line on exit, tagged for the caller:
#   ISOLATION_READY <json>    worktree created, head verified, tree clean
#   TEARDOWN_DONE <json>      worktree removed (realign result included)
#   TEARDOWN_NOOP <json>      nothing at <dir> to remove
#   BLOCKED <json>            needs a human: the reason is in the payload
#
# Exit codes: 0 ready/done/noop, 1 blocked, 64 usage, 69 environment.
set -euo pipefail

USAGE='usage: conductor-isolation.sh setup --path <dir> --repo owner/name --pr N
                                    [--head <sha>] [--branch <name>]
                                    [--head-remote <url|name>] [--remote <name>]
       conductor-isolation.sh teardown --path <dir> [--realign]
                                    [--branch <name>] [--at-setup <sha>]
                                    [--expect <sha>] [--remote <name>]'

die_usage() { printf '%s\n%s\n' "$1" "$USAGE" >&2; exit 64; }
die_env() { printf '%s\n' "$1" >&2; exit 69; }

# JSON string escaping, enough for the paths and refs that reach a report.
# Userinfo is stripped first: a remote URL can carry a token, and reports
# go to stdout, logs, and transcripts.
# Both remote spellings carry userinfo: `scheme://user@host/path` and the
# scp-style `user@host:path`, which has no `://` for a scheme-only pattern
# to anchor on. An absolute path is untouched, since its leading `/`
# stops the scp alternative from matching a directory named `a@b`.
# Escaped to valid JSON, which is more than the backslash and the quote.
# A path is bytes, and two kinds of them break the payload: a control
# character (a newline or tab is legal in a path) makes it invalid JSON
# and breaks the one-report-line contract the header advertises, and a
# byte that is not part of a valid UTF-8 sequence makes it undecodable
# even though it parses as text here. Valid UTF-8 passes through intact,
# so a legitimately non-ASCII path stays readable; anything else becomes
# `\u00xx`, which keeps the byte value recoverable. awk rather than sed,
# since both rules are per-byte decisions no substitution list can make.
# Newline is the record separator here, so it is re-emitted between
# records rather than mapped. Both stages run under LC_ALL=C: in a UTF-8
# locale sed rejects an invalid byte outright ("RE error: illegal byte
# sequence"), which would empty the whole payload rather than escape the
# byte.
esc() {
  printf '%s' "$1" |
    LC_ALL=C sed -E 's#(://)[^/@]*@#\1#g; s#^[^/@]+@([^/]*:)#\1#' |
    LC_ALL=C awk '
      BEGIN {
        for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
        for (i = 1; i < 32; i++) map[sprintf("%c", i)] = sprintf("\\u%04x", i)
        map["\b"] = "\\b"; map["\t"] = "\\t"; map["\f"] = "\\f"; map["\r"] = "\\r"
        map["\\"] = "\\\\"; map["\""] = "\\\""
      }
      # Bytes of a valid UTF-8 sequence starting at i, else 0. The ranges
      # are the ones that exclude overlong forms, surrogates, and
      # anything past U+10FFFF, so this rejects what a decoder would.
      function seq(s, n, i,   b, want, lo, hi, k, c) {
        b = ord[substr(s, i, 1)]
        if (b >= 194 && b <= 223) { want = 2; lo = 128; hi = 191 }
        else if (b >= 224 && b <= 239) {
          want = 3; lo = (b == 224 ? 160 : 128); hi = (b == 237 ? 159 : 191)
        } else if (b >= 240 && b <= 244) {
          want = 4; lo = (b == 240 ? 144 : 128); hi = (b == 244 ? 143 : 191)
        } else return 0
        if (i + want - 1 > n) return 0
        for (k = 1; k < want; k++) {
          c = ord[substr(s, i + k, 1)]
          if (k == 1) { if (c < lo || c > hi) return 0 }
          else if (c < 128 || c > 191) return 0
        }
        return want
      }
      {
        if (NR > 1) printf "\\n"
        n = length($0); o = ""; i = 1
        while (i <= n) {
          c = substr($0, i, 1)
          if (c in map) { o = o map[c]; i++ }
          else if (ord[c] < 128) { o = o c; i++ }
          else if ((w = seq($0, n, i)) > 0) { o = o substr($0, i, w); i += w }
          else { o = o sprintf("\\u%04x", ord[c]); i++ }
        }
        printf "%s", o
      }'
}

# The userinfo a remote carries, empty when it carries none. `git` alone
# is the conventional ssh identity and not a secret; anything else in
# that position is treated as one.
userinfo_of() {
  case "$1" in
  *://*) rest=${1#*://}; case "$rest" in *@*) printf '%s' "${rest%%@*}" ;; esac ;;
  /*) ;;
  *@*:*) printf '%s' "${1%%@*}" ;;
  esac
}

# Why a remote is unacceptable, empty when it is fine. This value is
# persisted to the state file and echoed back in reports, so the rule is
# a shape a URL may have rather than a list of things a secret is called:
# `?access_token=`, `?sig=`, `#token` and whatever the next host invents
# all ride in a query or fragment, and enumerating their names is the
# losing half of that game. A URL here names a location and nothing else.
# Two deliberate exemptions: the conventional `git@` ssh identity, which
# is not a secret, and a filesystem path, which has no query or fragment
# to carry one (that is also why a directory named `a@b` is not read as
# credentials). A bare remote name is checked by neither, having no URL
# syntax at all.
remote_defect() {
  # Before the shape, the bytes: this value is written to the state file
  # as one `key=value` line and read back by splitting on that, so an
  # embedded newline silently truncates what teardown fetches from. No
  # remote spelling needs a control character.
  case "$1" in
  *[[:cntrl:]]*) printf 'control'; return ;;
  esac
  case "$1" in
  /*) return ;;
  *://* | *@*:*) ;;
  *) return ;;
  esac
  case "$(userinfo_of "$1")" in
  "" | git) ;;
  *) printf 'userinfo'; return ;;
  esac
  case "$1" in
  *\?*) printf 'query' ;;
  *\#*) printf 'fragment' ;;
  esac
}

# Worktree records, NUL-terminated. A path may contain a newline, which
# a line-oriented read splits into fragments that match neither the
# `worktree <target>` test below nor the branch-location one: teardown
# then calls its own linked worktree a foreign directory and leaves it
# registered and on disk. The fallback keeps that pre-2.36 behavior
# rather than dropping the records (and with them the "checked out
# elsewhere" guard) on a git without `-z`.
worktree_records() {
  git worktree list --porcelain -z 2>/dev/null ||
    git worktree list --porcelain | tr '\n' '\0'
}

report() { # tag, then key=value pairs
  tag=$1; shift
  out=""
  for pair in "$@"; do
    [ -n "$out" ] && out="$out,"
    out="$out\"${pair%%=*}\":\"$(esc "${pair#*=}")\""
  done
  printf '%s {%s}\n' "$tag" "$out"
}

blocked() { report BLOCKED "reason=$1" "${@:2}"; exit 1; }

command -v git >/dev/null 2>&1 || die_env "git not on PATH"

MODE=${1:-}
case "$MODE" in
setup | teardown) shift ;;
-h | --help) printf '%s\n' "$USAGE"; exit 0 ;;
*) die_usage "first argument must be setup or teardown" ;;
esac

PATH_ARG="" REPO="" PR="" HEAD="" BRANCH="" REMOTE="origin" REALIGN=0
HEADREMOTE="" HEADURL="" AT_SETUP="" EXPECT="" HOSTRESOLVED=0
while [ $# -gt 0 ]; do
  case "$1" in
  --path) PATH_ARG=${2:-}; shift 2 || die_usage "--path needs a value" ;;
  --repo) REPO=${2:-}; shift 2 || die_usage "--repo needs a value" ;;
  --pr) PR=${2:-}; shift 2 || die_usage "--pr needs a value" ;;
  --head) HEAD=${2:-}; shift 2 || die_usage "--head needs a value" ;;
  --branch) BRANCH=${2:-}; shift 2 || die_usage "--branch needs a value" ;;
  --head-remote) HEADREMOTE=${2:-}; shift 2 || die_usage "--head-remote needs a value" ;;
  --remote) REMOTE=${2:-}; shift 2 || die_usage "--remote needs a value" ;;
  --realign) REALIGN=1; shift ;;
  --at-setup) AT_SETUP=${2:-}; shift 2 || die_usage "--at-setup needs a value" ;;
  --expect) EXPECT=${2:-}; shift 2 || die_usage "--expect needs a value" ;;
  -h | --help) printf '%s\n' "$USAGE"; exit 0 ;;
  *) die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$PATH_ARG" ] || die_usage "--path is required"
[ "$MODE" = setup ] || [ -z "$REPO$PR$HEAD$HEADREMOTE" ] ||
  die_usage "--repo/--pr/--head/--head-remote are setup-only"
[ "$MODE" = teardown ] || { [ "$REALIGN" -eq 0 ] && [ -z "$AT_SETUP$EXPECT" ]; } ||
  die_usage "--realign/--at-setup/--expect are teardown-only"
[ "$MODE" = setup ] && [ -z "$PR" ] && [ -z "$HEAD" ] &&
  die_usage "setup needs --pr (or --head to skip host resolution)"
case "$HEAD" in
"" | [0-9a-fA-F]*) ;;
*) die_usage "--head must be hex" ;;
esac
# Anything a URL could smuggle a credential in would be persisted to the
# state file and echoed back on failure. Refuse it rather than storing
# it: name a configured remote, or a bare URL whose credentials come from
# a helper. The value is never echoed here, since the message would be
# the leak.
for candidate in "$HEADREMOTE" "$REMOTE"; do
  case "$(remote_defect "$candidate")" in
  "") ;;
  *) die_usage "a remote URL must carry no credentials, query string, or fragment: use a remote name, or a URL whose credentials come from a git credential helper. Scheme URLs and the scp-style user@host:path form are both checked, and only the conventional git@ ssh identity is allowed" ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  die_env "not inside a git working tree: run from the primary checkout"

# Resolve the target the way git reports it: absolute, normalized, and
# symlinks resolved. A naive "$(pwd)/$arg" yields paths like
# `/repo/primary/../w` and `/var/...` where git prints `/repo/w` and
# `/private/var/...`, so every later string comparison against
# `git worktree list` silently misses. The parent must exist; the target
# itself need not, since setup creates it.
abspath() {
  # Split with parameter expansion rather than dirname/basename: those
  # are command substitutions, which strip every trailing newline, and a
  # directory name may end in one. Trailing slashes are trimmed first,
  # since that normalization was dirname's and `--path w/` is what tab
  # completion produces.
  trimmed=$1
  while [ "$trimmed" != "/" ] && [ "${trimmed%/}" != "$trimmed" ]; do
    trimmed=${trimmed%/}
  done
  case "$trimmed" in
  */*) dir=${trimmed%/*}; base=${trimmed##*/}; [ -n "$dir" ] || dir=/ ;;
  *) dir=.; base=$trimmed ;;
  esac
  # `pwd` is a command too, so its own trailing newlines need the same
  # protection: the sentinel is what makes them survive the substitution.
  parent=$(cd "$dir" 2>/dev/null && { pwd -P && printf x; }) ||
    { printf '%s' "$1"; return; }
  parent=${parent%x}; parent=${parent%$'\n'}
  case "$base" in
  .) printf '%s' "$parent" ;;
  *) printf '%s/%s' "${parent%/}" "$base" ;;
  esac
}
# The sentinel again, because this call is itself a command substitution:
# fixing the splitting inside `abspath` buys nothing if the value loses
# its trailing newline on the way out.
TARGET=$(abspath "$PATH_ARG"; printf x); TARGET=${TARGET%x}
GITDIR=$(git rev-parse --git-common-dir)
case "$GITDIR" in /*) ;; *) GITDIR="$(pwd)/$GITDIR" ;; esac
STATEDIR="$GITDIR/conductor-isolation"
# Hashed, not transliterated: mapping both `/` and ` ` to `_` collides
# `/tmp/a/b` with `/tmp/a_b`, so one path's setup could block or realign
# using the other's record. git is already required, so its hash is the
# portable one.
# On a case-insensitive filesystem (macOS default) `wt/Foo` and `wt/foo`
# are one directory, so keying on the literal spelling gives each its own
# record: the first exchange's pending realignment is then orphaned and
# unguarded. Fold the key when a probe proves the filesystem folds.
KEYPATH=$TARGET
mkdir -p "$STATEDIR" 2>/dev/null || true
probe="$STATEDIR/.casEprobe.$$"
if : > "$probe" 2>/dev/null; then
  [ -e "$STATEDIR/.CASEPROBE.$$" ] &&
    KEYPATH=$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')
  rm -f "$probe"
fi
KEYHASH=$(printf '%s' "$KEYPATH" | git hash-object --stdin)
STATE="$STATEDIR/$KEYHASH.state"
# Where the conductor's commits are anchored while no other ref holds
# them. A hex key makes this a valid refname by construction.
SAFETY_REF="refs/conductor-isolation/$KEYHASH"

# Standing inside the target is the one arrangement git will not protect
# against: it unlinks the current directory and exits 0.
case "$(pwd -P)/" in
"$TARGET"/*) blocked "run from the primary checkout, not from inside --path" "path=$TARGET" ;;
esac

if [ "$MODE" = setup ]; then
  [ -e "$TARGET" ] && blocked "--path already exists" "path=$TARGET"
  # State outlives a removal-only teardown so its realignment can still
  # run, which makes it clobberable by the next exchange reusing the same
  # conventional path: that would strand the earlier branch at its
  # pre-review SHA with no record of the head to move it to.
  [ -f "$STATE" ] && blocked \
    "a previous exchange at this path still has realignment pending" \
    "path=$TARGET" "resolve=teardown --path $PATH_ARG --realign" "state=$STATE"

  if [ -z "$HEAD" ] || [ -z "$BRANCH" ]; then
    command -v gh >/dev/null 2>&1 ||
      die_env "gh not on PATH: pass --head and --branch to skip host resolution"
    [ -n "$PR" ] || die_usage "--pr is required when resolving from the host"
    # Resolve the repository first rather than leaning on gh's
    # {owner}/{repo} placeholders: `${REPO:-{owner}/{repo}}` is not the
    # expansion it looks like, since the `}` in `{owner}` closes it early
    # and silently builds a malformed path.
    if [ -z "$REPO" ]; then
      REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) ||
        blocked "could not resolve the repository: pass --repo owner/name"
    fi
    fields=$(gh api "repos/$REPO/pulls/$PR" \
      --jq '[.head.sha, .head.ref, (.head.repo.clone_url // "")] | @tsv' 2>/dev/null) ||
      blocked "could not resolve PR $PR from the host" "repo=$REPO"
    [ -n "$HEAD" ] || HEAD=$(printf '%s' "$fields" | cut -f1)
    [ -n "$BRANCH" ] || BRANCH=$(printf '%s' "$fields" | cut -f2)
    # Where the BRANCH lives, which is not where the pull ref lives: a fork
    # PR's branch exists only in the fork, so fetching it from the base
    # either fails or, worse, finds a same-named base branch and realigns
    # to the wrong commit. Recorded as a URL so it works with no configured
    # remote for the fork.
    HEADURL=$(printf '%s' "$fields" | cut -f3)
    # Held to the same shape as an operator-supplied one. This URL is a
    # field of a value an external call handed back, and it lands in the
    # same state file and the same reports; that the host normally
    # returns a bare clone URL is a habit, not a guarantee. Never echoed,
    # for the same reason as above.
    [ -z "$(remote_defect "$HEADURL")" ] ||
      blocked "the host returned a head repository URL carrying credentials, a query string, or a fragment" \
        "repo=$REPO" "resolve=pass --head-remote with a clean URL or a configured remote name"
    HOSTRESOLVED=1
  fi
  # An explicit --head-remote wins, and is the only way to name the fork
  # when --head/--branch skip host resolution: without it that path would
  # fall back to the base remote and realign to whatever same-named branch
  # it finds there.
  [ -n "$HEADREMOTE" ] && HEADURL=$HEADREMOTE
  # `.head.repo` is null when the fork was deleted or is inaccessible, and
  # the empty string that leaves behind is not "the base repository", it
  # is "the host does not know". Falling back to the base there resolves
  # the branch against a repository that never held it, and teardown
  # realigns the primary checkout to whatever same-named branch happens
  # to sit there. Refuse instead: this is only reachable when host
  # resolution ran, so the --head/--branch override path keeps its
  # documented base-remote fallback.
  [ "${HOSTRESOLVED:-0}" -eq 1 ] && [ -z "$HEADURL" ] &&
    blocked "the host did not name the head repository (a deleted or inaccessible fork): pass --head-remote" \
      "repo=$REPO" "pr=$PR"

  # The head is resolved from the host, so this checkout need not hold the
  # object: a fork PR, another clone, or a stale local branch all leave
  # `git worktree add` dying on `fatal: invalid reference`. refs/pull is
  # served by the BASE repository and covers the fork case a branch fetch
  # does not; a repository without that namespace still gets the branch.
  if ! git cat-file -e "$HEAD^{commit}" 2>/dev/null; then
    if [ -n "$PR" ]; then
      git fetch --quiet "$REMOTE" "refs/pull/$PR/head" 2>/dev/null || true
    fi
    if ! git cat-file -e "$HEAD^{commit}" 2>/dev/null && [ -n "$BRANCH" ]; then
      git fetch --quiet "${HEADURL:-$REMOTE}" "refs/heads/$BRANCH" 2>/dev/null || true
    fi
    git cat-file -e "$HEAD^{commit}" 2>/dev/null ||
      blocked "expected head not fetchable" "head=$HEAD" "remote=$REMOTE"
  fi

  # --detach, because the primary checkout is normally sitting on the PR
  # branch and the branch form refuses a branch another worktree holds.
  git worktree add --detach --quiet "$TARGET" "$HEAD" 2>/dev/null ||
    blocked "worktree add failed" "path=$TARGET" "head=$HEAD"

  got=$(git -C "$TARGET" rev-parse HEAD)
  want=$(git rev-parse "$HEAD^{commit}")
  [ "$got" = "$want" ] || blocked "worktree head mismatch" "got=$got" "want=$want"
  # -uall, because `status.showUntrackedFiles=no` in the repository or the
  # user's config would otherwise report a worktree clean with untracked
  # files sitting in it (a post-checkout hook's output, say), which a
  # later broad `git add` would sweep into the conductor's push. A guard
  # that configuration can switch off is not one.
  [ -z "$(git -C "$TARGET" status --porcelain --untracked-files=all)" ] ||
    blocked "new worktree is not clean" "path=$TARGET"

  # The primary branch's head at setup: teardown --realign moves the branch
  # only while it still equals this, proving it gained nothing the
  # conductor never saw.
  primary="" local_ahead=""
  if [ -n "$BRANCH" ] && git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    at=$(git rev-parse "refs/heads/$BRANCH")
    # Recorded only when it already equals the head the conductor starts
    # from. Teardown reads this as "the branch gained nothing the
    # conductor never saw", but that inference is only sound if there was
    # nothing unseen to begin with: a branch sitting on unpushed local
    # commits is unchanged at teardown while holding work the conductor
    # never had, and the rewritten realign would reset it away. Leaving
    # the record empty costs that automatic path and keeps `--at-setup`
    # as the way to say "discard them, I mean it".
    if [ "$at" = "$want" ]; then
      primary=$at
    else
      local_ahead=$at
    fi
  fi
  # 0700/0600: the host-resolved clone_url is credential-free, but this
  # file records where a private fork lives and is read back by teardown.
  mkdir -p "$STATEDIR"
  chmod 700 "$STATEDIR" 2>/dev/null || true
  (umask 077; printf 'branch=%s\nhead=%s\nprimary=%s\nheadurl=%s\n' \
    "$BRANCH" "$want" "$primary" "${HEADURL:-}" > "$STATE")

  # Surfaced at setup rather than only at the teardown refusal: this is
  # the point where the operator can still push those commits.
  if [ -n "$local_ahead" ]; then
    report ISOLATION_READY "path=$TARGET" "head=$want" "branch=$BRANCH" \
      "local_unpushed=$local_ahead" \
      "note=the local branch is not at the PR head, so a rewritten realign will refuse without --at-setup"
  else
    report ISOLATION_READY "path=$TARGET" "head=$want" "branch=$BRANCH"
  fi
  exit 0
fi

# --- teardown ---------------------------------------------------------------

STATE_BRANCH="" STATE_HEAD="" PRIMARY_AT_SETUP="" HEADURL="" STATE_FINAL=""
if [ -f "$STATE" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
    branch) STATE_BRANCH=$v ;;
    head) STATE_HEAD=$v ;;
    primary) PRIMARY_AT_SETUP=$v ;;
    headurl) HEADURL=$v ;;
    final) STATE_FINAL=$v ;;
    esac
  done < "$STATE"
fi

# Named before the removal below, since the proof it guards is read from
# the checkout being removed. The refusal when neither a flag nor a
# record supplies one stays with the realign, so a plain teardown is
# unaffected.
[ -n "$BRANCH" ] || BRANCH=$STATE_BRANCH

# Route detection: only a linked worktree is git's to remove. A separate
# clone it would reject outright (`fatal: '.' is a main working tree`),
# and deleting someone's directory is not this script's call, so that
# route's removal is the human's while realignment below still runs.
is_worktree=0
while IFS= read -r -d '' line; do
  case "$line" in
  "worktree $TARGET") is_worktree=1 ;;
  esac
done < <(worktree_records)

# What the conductor left, read while its checkout still exists. The
# realign below fetches whatever now occupies the branch, which is not
# the same thing: a contributor pushing (or force-pushing) into the
# window between the conductor's last push and this call would otherwise
# be reset into the primary checkout as a reviewed head.
FINAL_HEAD=""
if [ -e "$TARGET" ]; then
  if [ "$is_worktree" -eq 1 ]; then
    # A linked worktree shares this repository's refs, so refs/heads here
    # is the primary's own pre-review SHA. Its detached HEAD is the only
    # local record of what the conductor pushed.
    FINAL_HEAD=$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || true)
  else
    # A separate clone has its own refs, so which of them is the proof
    # depends on where its HEAD sits. Detached is the documented route
    # (it pushes HEAD:<branch>, leaving refs/heads/<branch> behind at the
    # pre-fold SHA), and on the branch the two agree; only a clone parked
    # on some *other* branch has a HEAD that is not the pushed head, and
    # there the branch ref is. Parked elsewhere with no local copy of the
    # branch, it knows nothing about it: leave the proof empty and let
    # the refusal below ask for --expect, rather than offering up an
    # unrelated commit as what the conductor pushed.
    on=$(git -C "$TARGET" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    if [ -z "$on" ] || [ "$on" = "$BRANCH" ]; then
      FINAL_HEAD=$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || true)
    else
      FINAL_HEAD=$(git -C "$TARGET" rev-parse --verify --quiet "refs/heads/$BRANCH" 2>/dev/null || true)
    fi
  fi
fi
# Persisted as soon as it is read, not only on the removal-only path:
# removal happens before every guard below, so a realign that blocks (on
# a dirty primary, say) has already consumed the checkout that knew this,
# and the documented retry after clearing the blocker needs it to
# survive. Only into a record setup already made; a hand-made clone has
# no state file, and creating one here would make the next setup refuse
# that path as having a realignment pending.
if [ -f "$STATE" ] && [ -n "$FINAL_HEAD" ]; then
  (umask 077; printf 'branch=%s\nhead=%s\nprimary=%s\nheadurl=%s\nfinal=%s\n' \
    "$STATE_BRANCH" "$STATE_HEAD" "$PRIMARY_AT_SETUP" "$HEADURL" "$FINAL_HEAD" > "$STATE")
  STATE_FINAL=$FINAL_HEAD
fi

removed=none
if [ "$is_worktree" -eq 1 ]; then
  # Anchor the conductor's head before unlinking the worktree that holds
  # it. Recording the SHA is not the same as keeping the object: a
  # detached worktree's HEAD and its reflog are the only references to
  # those commits, `git worktree remove` deletes both, and a push to a
  # URL rather than a configured remote leaves no tracking ref either. If
  # the realign below then refuses because someone else force-pushed over
  # the branch, the fixes it is protecting would already be unreachable,
  # and the next `git gc --prune=now` collects them.
  [ -n "$FINAL_HEAD" ] &&
    { git update-ref "$SAFETY_REF" "$FINAL_HEAD" 2>/dev/null ||
      blocked "could not anchor the conductor's head before removal" \
        "ref=$SAFETY_REF" "head=$FINAL_HEAD"; }
  git worktree remove "$TARGET" 2>/dev/null ||
    blocked "worktree remove refused (uncommitted changes there?)" "path=$TARGET"
  removed=worktree
elif [ -e "$TARGET" ]; then
  removed=manual
fi

if [ "$REALIGN" -eq 0 ]; then
  # The state outlives a removal-only teardown so a later --realign can
  # still find its branch, the head it started from, and the head the
  # conductor ended on.
  [ "$removed" = none ] && { report TEARDOWN_NOOP "path=$TARGET"; exit 0; }
  report TEARDOWN_DONE "path=$TARGET" "removed=$removed" "realign=skipped"
  exit 0
fi

# A clone the human made directly has no setup record, so --branch names
# what to realign. Without the recorded setup head, a rewrite cannot be
# proven safe, so only the fast-forward case is served (below).
[ -n "$BRANCH" ] ||
  blocked "no branch to realign: pass --branch, or run setup so it is recorded" "path=$TARGET"

# Where the branch is checked out decides both the mechanism and which
# guards apply. Moving a ref no working tree holds cannot disturb one, so
# an unrelated dirty checkout is no reason to refuse; moving the branch
# HEAD points at would drag the tree, and a third worktree holding it
# would be desynced with nothing to notice.
checked_out=0 elsewhere=""
[ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" = "$BRANCH" ] && checked_out=1
# The worktree root, not the cwd: `git worktree list` prints roots, so a
# run from a subdirectory of this very checkout would otherwise match no
# entry and report itself as "another worktree". Everything below that
# compares or resolves a repo-relative path is anchored here for the same
# reason.
root=$(git rev-parse --show-toplevel)
wt=""
while IFS= read -r -d '' line; do
  case "$line" in
  "worktree "*) wt=${line#worktree } ;;
  "branch refs/heads/$BRANCH")
    [ "$wt" = "$root" ] || elsewhere=$wt
    ;;
  esac
done < <(worktree_records)
[ -n "$elsewhere" ] &&
  blocked "branch is checked out in another worktree" "branch=$BRANCH" "worktree=$elsewhere"

# -uall for the same reason as the setup check: configuration must not be
# able to turn this guard off.
if [ "$checked_out" -eq 1 ] && [ -n "$(git status --porcelain --untracked-files=all)" ]; then
  blocked "primary checkout is not clean: realign would move HEAD under those edits"
fi

# From the HEAD remote, not the base one --remote names: the branch the
# conductor pushed lives wherever the PR head lives, and a fork PR's
# branch is absent from the base (or, worse, present there as an
# unrelated same-named branch this would realign to).
BRANCHFROM=${HEADURL:-$REMOTE}
# Fully qualified: a bare name lets a same-named tag win into
# FETCH_HEAD, and realign would then reset the primary branch to an
# unrelated tag commit.
git fetch --quiet "$BRANCHFROM" "refs/heads/$BRANCH" 2>/dev/null ||
  blocked "could not fetch the pushed branch" "branch=$BRANCH" "from=$BRANCHFROM"
pushed=$(git rev-parse FETCH_HEAD)

# A fetched branch tip is not proof that the conductor put it there.
# Anyone with push access can land a commit, or force-push an unrelated
# one, between the conductor's last push and this call, and every guard
# below is about what the *local* branch holds, so an unreviewed head
# would sail through them and be reset into the primary checkout. The
# expected head comes from the conductor's own checkout, from the state
# recorded when that checkout was removed, or by hand from --expect; with
# none of the three there is nothing to check against, and this is the
# destructive path, so it refuses rather than assuming.
expected=${EXPECT:-${FINAL_HEAD:-$STATE_FINAL}}
[ -n "$expected" ] ||
  blocked "no proof of what the conductor pushed: pass --expect <sha>, the head its checkout ended on" \
    "branch=$BRANCH" "pushed=$pushed"
expected=$(git rev-parse --verify --quiet "$expected^{commit}" 2>/dev/null || printf '%s' "$expected")
if [ "$pushed" != "$expected" ]; then
  # Name where the work is: by now the worktree is gone, and this ref is
  # the only thing keeping those commits alive.
  saved=""
  git rev-parse --verify --quiet "$SAFETY_REF" >/dev/null 2>&1 && saved=$SAFETY_REF
  blocked "the branch does not hold what the conductor pushed: someone else pushed to it" \
    "branch=$BRANCH" "pushed=$pushed" "expected=$expected" "saved=$saved" \
    "resolve=verify that head, then move the branch by hand or re-run with --expect $pushed"
fi

git show-ref --verify --quiet "refs/heads/$BRANCH" ||
  blocked "no local branch to realign" "branch=$BRANCH"
local_head=$(git rev-parse "refs/heads/$BRANCH")

move() { # how
  if [ "$checked_out" -eq 1 ]; then
    # `git status --porcelain` does not list ignored files, so a clean
    # tree is not proof that `reset --hard` destroys nothing: a local
    # ignored file (a cache, a .env) that the pushed commit begins
    # tracking gets silently overwritten. Refuse on any path the move
    # would materialize that exists here untracked or ignored.
    collisions=""
    # -z, because `--name-only` C-quotes any path with a non-ASCII byte or
    # a control character (`"caf\303\251.txt"`), and every test below would
    # then probe a name no filesystem has. `diff.relative` is neutralized
    # for the same reason: with it set, the paths would arrive relative to
    # the cwd instead of the root they are joined to here.
    while IFS= read -r -d '' p; do
      [ -n "$p" ] || continue
      # Walk the path and every ancestor. Testing the full path alone
      # misses the case that matters most: when an ancestor component is
      # itself a local file, `-e` on the deeper path returns false
      # (ENOTDIR), so materializing the directory would delete that file
      # with nothing having flagged it. A broken symlink needs -L too.
      probe=$p
      while [ -n "$probe" ] && [ "$probe" != "." ] && [ "$probe" != "/" ]; do
        if [ -d "$root/$probe" ] && [ ! -L "$root/$probe" ]; then
          # A real directory: `ls-files --error-unmatch` proves nothing
          # here, since the pathspec matches any indexed *descendant* and
          # so calls every directory with tracked content "tracked". The
          # reset destroys such a directory only when the pushed tree puts
          # a blob at that same path, and what is lost then is whatever
          # the index does not hold. (A pushed tree, or no entry at all,
          # leaves untracked contents in place: git removes a directory
          # only once it is empty.)
          if [ "$(git -C "$root" cat-file -t "$pushed:$probe" 2>/dev/null)" = blob ] &&
            [ -n "$(git -C "$root" ls-files --others -- "$probe" 2>/dev/null)" ]; then
            collisions="$collisions $probe"
            break
          fi
        elif [ -e "$root/$probe" ] || [ -L "$root/$probe" ]; then
          git -C "$root" ls-files --error-unmatch -- "$probe" >/dev/null 2>&1 || {
            collisions="$collisions $probe"
            break
          }
        fi
        # Not `$(dirname ...)`: command substitution strips every
        # trailing newline, and a path component may end in one, so the
        # walk would silently step to a *different* ancestor and miss
        # the file the reset is about to delete.
        case "$probe" in
        */*) parent=${probe%/*}; [ -n "$parent" ] || parent=/ ;;
        *) parent=$probe ;;
        esac
        [ "$parent" = "$probe" ] && break
        probe=$parent
      done
    done < <(git -C "$root" -c diff.relative=false diff -z --name-only \
      "$local_head" "$pushed" 2>/dev/null)
    [ -n "$collisions" ] &&
      blocked "realign would overwrite untracked or ignored files the pushed commit tracks" \
        "paths=${collisions# }"
    # Guarded by a clean tree, by that collision check, and by the branch
    # holding nothing the conductor never saw, so this discards no work.
    # Checked, because this function is reached through an `&&` list, which
    # suspends `set -e` inside it: an unchecked failure here would report
    # TEARDOWN_DONE and drop the state that a retry needs.
    git reset --hard --quiet "$pushed" ||
      blocked "reset to the pushed head failed" "branch=$BRANCH" "to=$pushed"
  else
    git update-ref "refs/heads/$BRANCH" "$pushed" "$local_head" ||
      blocked "could not move the branch ref" "branch=$BRANCH" \
        "from=$local_head" "to=$pushed"
  fi
  # Only now: a blocked realign keeps its state so the human can clear
  # whatever stopped it and re-run, instead of having to reconstruct the
  # branch and the setup head by hand.
  rm -f "$STATE"
  # The branch now holds these commits, so the anchor has nothing left to do.
  git update-ref -d "$SAFETY_REF" 2>/dev/null || true
  report TEARDOWN_DONE "path=$TARGET" "removed=$removed" "realign=$1" \
    "branch=$BRANCH" "from=$local_head" "to=$pushed"
  exit 0
}

if [ "$local_head" = "$pushed" ]; then
  rm -f "$STATE"
  # The branch now holds these commits, so the anchor has nothing left to do.
  git update-ref -d "$SAFETY_REF" 2>/dev/null || true
  report TEARDOWN_DONE "path=$TARGET" "removed=$removed" "realign=already-aligned" \
    "branch=$BRANCH" "at=$pushed"
  exit 0
fi
git merge-base --is-ancestor "$local_head" "$pushed" 2>/dev/null && move fast-forward
# Not an ancestor: the conductor folded review fixes, so the pushed head
# rewrote the commits this branch still points at. Safe to move only while
# the branch is exactly where setup found it.
# Without setup state, --at-setup is how the operator supplies the same
# proof by hand: the head the branch had before the exchange. It is
# checked, not trusted, since it only counts when the branch still
# equals it.
[ -n "$AT_SETUP" ] && [ -z "$PRIMARY_AT_SETUP" ] &&
  PRIMARY_AT_SETUP=$(git rev-parse --verify --quiet "$AT_SETUP^{commit}" || true)
[ -n "$PRIMARY_AT_SETUP" ] && [ "$local_head" = "$PRIMARY_AT_SETUP" ] && move rewritten
blocked "local branch holds commits the conductor never saw" \
  "branch=$BRANCH" "local=$local_head" "pushed=$pushed" "at_setup=$PRIMARY_AT_SETUP"
