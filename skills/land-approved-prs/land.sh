#!/usr/bin/env bash
# land.sh: the landing engine of the land-approved-prs skill, its guarded
# merge sequence. It ends at the merge; post-merge cleanup belongs to the
# merge-cleanup skill. The skill's prose owns the judgment (which PRs are
# ready, whether one still holds, what to do when a guard
# fires); this script owns the mechanics, so no agent re-derives quoting,
# encoding, or parsing rules at runtime. Every forge- or git-sourced value
# stays in a shell variable and reaches commands through argv, behind an
# option terminator wherever the command takes a positional name; nothing
# here re-parses a value through a shell.
#
# Usage:
#   land.sh check   --pr N --repo owner/name
#   land.sh land    --pr N --repo owner/name --head <40-hex-oid>
#   land.sh merge   --pr N --repo owner/name --head <40-hex-oid>
#     [--base-remote NAME]   # override remote resolution for the base repo
#     [--head-remote NAME]   # override remote resolution for the head repo
#     [--interval 10]        # land/merge: seconds between CI and MERGED polls
#     [--cap-minutes 15]     # land/merge: total wait for MERGED
#     [--ci-cap-minutes 30]  # land phase: total wait for CI on the head
#     [--dry-run]            # land phase only: report, never rebase or merge
#
# Run each phase from the base-branch checkout, the one merge-cleanup will
# later rewrite. --repo is required, never defaulted: a bare PR number
# resolves against the CLI's default repository, which in a fork clone can
# act on a different PR entirely.
#
# check    Pre-merge guards: PR open, no head/base name collision, clean
#          workspace, no git operation in progress, no competing worktree
#          layout, no open PR sharing the head branch, and a merge queue's
#          method identified as merge-commit before anything is enqueued.
#          Prints the verified head OID the later phases pin and the open
#          PRs stacked on the head branch, which every phase reports
#          rather than refuses unless the head is cross-repository.
# land     One round of the landing procedure for a base without branch
#          protection: fetch the base. When the head is not on its tip,
#          rebase it, lease-push it against --head, and STOP rebased with
#          the new head: its range-diff needs reading before check and land
#          run again with it. On the tip, wait for CI on the exact head
#          commit, refuse if the forge's base tip moved since the fetch,
#          then run merge. A refusal is a STOP; rerunning land is the retry.
# merge    Merges pinned to --head with an explicit title-only message,
#          then polls until the forge reports the PR MERGED (a zero exit
#          from the merge command proves enqueueing, not merging).
#
# Last line on stdout is the machine-readable result:
#   OK <phase> <json>            phase completed; json carries the facts
#   STOP <guard> <json>          a guard fired: surface it, never work
#                                around it; the guard names are stable
#   LOOKUP_FAILED <what> <json>  a read failed; unknown is not absence, so
#                                nothing was decided from the empty result;
#                                a failed forge read adds "stderr", the first
#                                300 bytes of gh's error output
# Exit codes: 0 OK; 2 STOP; 4 LOOKUP_FAILED; 64 usage error; 69 gh
# (GitHub CLI) not found on PATH.
set -u

PHASE="" PR="" REPO="" HEAD_OID="" BASE_REMOTE_OPT="" HEAD_REMOTE_OPT=""
INTERVAL=10 CAP_MINUTES=15 CI_CAP_MINUTES=30 DRY_RUN=false

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

case "${1:-}" in
  check|land|merge) PHASE="$1"; shift ;;
  *) echo "land.sh: first argument must be check, land, or merge" >&2; usage ;;
esac

# Recognize the option, then require its value, before reading $2: a
# trailing bare option must die as a usage error, not a set -u crash.
while [ $# -gt 0 ]; do
  opt="$1"
  # The one boolean flag. Land-only, so a mistyped `merge --dry-run` is a
  # usage error rather than a real merge.
  if [ "$opt" = --dry-run ]; then
    [ "$PHASE" = land ] || { echo "land.sh: --dry-run applies only to land" >&2; usage; }
    DRY_RUN=true; shift; continue
  fi
  case "$opt" in
    --pr|--repo|--head|--base-remote|--head-remote|--interval|--cap-minutes|--ci-cap-minutes) ;;
    *) echo "land.sh: unknown option: $opt" >&2; usage ;;
  esac
  [ $# -ge 2 ] || { echo "land.sh: $opt requires a value" >&2; usage; }
  val="$2"; shift 2
  case "$opt" in
    --pr) PR="$val" ;;
    --repo) REPO="$val" ;;
    --head) HEAD_OID="$val" ;;
    --base-remote) BASE_REMOTE_OPT="$val" ;;
    --head-remote) HEAD_REMOTE_OPT="$val" ;;
    --interval) INTERVAL="$val" ;;
    --cap-minutes) CAP_MINUTES="$val" ;;
    --ci-cap-minutes) CI_CAP_MINUTES="$val" ;;
  esac
done

[ -n "$PR" ] && [ -n "$REPO" ] || usage
case "$PR" in ''|*[!0-9]*|0*)
  echo "land.sh: --pr must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$REPO" in
  */*/*|*[!A-Za-z0-9._/-]*) echo "land.sh: --repo must be owner/name" >&2; usage ;;
  ?*/?*) ;;
  *) echo "land.sh: --repo must be owner/name" >&2; usage ;;
esac
if [ "$PHASE" != check ]; then
  HEAD_OID=$(printf '%s' "$HEAD_OID" | tr 'A-F' 'a-f')
  case "$HEAD_OID" in *[!0-9a-f]*|'')
    echo "land.sh: --head must be the full 40-hex verified head OID" >&2; usage ;;
  esac
  [ "${#HEAD_OID}" -eq 40 ] || {
    echo "land.sh: --head must be the full 40-hex verified head OID" >&2; usage
  }
fi
case "$INTERVAL" in ''|0|0*|*[!0-9]*)
  echo "land.sh: --interval must be a positive integer without leading zeros (seconds)" >&2; usage ;;
esac
case "$CAP_MINUTES" in ''|0?*|*[!0-9]*)
  echo "land.sh: --cap-minutes must be a non-negative integer without leading zeros" >&2; usage ;;
esac
# Keep later arithmetic inside a signed 32-bit range on every supported Bash.
# These limits are far beyond a useful interactive wait while rejecting values
# that could wrap only after the irreversible merge command has run.
[ "${#INTERVAL}" -le 9 ] || {
  echo "land.sh: --interval must be at most 999999999 seconds" >&2; usage
}
[ "${#CAP_MINUTES}" -le 7 ] || {
  echo "land.sh: --cap-minutes must be at most 9999999" >&2; usage
}
case "$CI_CAP_MINUTES" in ''|0?*|*[!0-9]*)
  echo "land.sh: --ci-cap-minutes must be a non-negative integer without leading zeros" >&2; usage ;;
esac
[ "${#CI_CAP_MINUTES}" -le 7 ] || {
  echo "land.sh: --ci-cap-minutes must be at most 9999999" >&2; usage
}
# Remote-name overrides: a leading hyphen would read as an option to git
# even behind our own parsing, and every use below passes them as
# positionals, so refuse the shape outright rather than trusting quoting.
for rn in "$BASE_REMOTE_OPT" "$HEAD_REMOTE_OPT"; do
  case "$rn" in -*)
    echo "land.sh: remote names must not begin with a hyphen" >&2; usage ;;
  esac
done

command -v gh >/dev/null 2>&1 || {
  echo "land.sh: gh (GitHub CLI) not found on PATH; stop and hand off unless another authenticated PR-host CLI can perform every required forge check" >&2
  exit 69
}

# --- reporting -------------------------------------------------------------

# Byte-wise escaper for report payloads. Not awk or sed: record splitting
# cannot represent a trailing newline, and the worktree path this
# serializes is exactly the kind of value the parser upstream is hardened
# to carry faithfully. Printable ASCII passes through; every other byte,
# control and high alike, encodes as \u00XX, so the emitted line is always
# valid UTF-8 JSON and the string's code points are the value's bytes
# (recover them by mapping code points 0-255 back to bytes). Raw high
# bytes must not pass through: a path byte outside UTF-8 would make the
# report unparseable, and a parser that substitutes U+FFFD loses the path.
json_escape() {
  local LC_ALL=C s="$1" out="" c i o
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      \\) out+='\\' ;;
      \") out+='\"' ;;
      $'\n') out+='\n' ;;
      $'\t') out+='\t' ;;
      $'\r') out+='\r' ;;
      *)
        o=$(( $(printf '%d' "'$c") & 255 ))
        if [ "$o" -ge 32 ] && [ "$o" -le 126 ]; then
          out+="$c"
        else
          out+=$(printf '\\u%04x' "$o")
        fi ;;
    esac
  done
  printf '%s' "$out"
}

# Capture stdout byte-faithfully except the final terminator: a bare $( )
# strips every trailing newline, erasing the byte that distinguishes a
# newline-ending value from its newline-less sibling.
out_exact() { # out_exact <var> <cmd...>: fails when the command fails
  local __v="$1"; shift
  local __o
  __o=$("$@" 2>/dev/null && printf x) || return 1
  __o="${__o%x}"
  printf -v "$__v" '%s' "${__o%$'\n'}"
}

physical_dir() { # physical_dir <path>
  cd -P -- "$1" 2>/dev/null || return 1
  pwd -P
}

# Reject a remote whose configured URLs carry a newline: every listing of
# them is line-based, so the distinguishing byte cannot survive any
# comparison, and a stripped comparison would accept a split destination.
# The raw config is read NUL-separated, so this test itself is
# byte-faithful.
remote_urls_newline_free() { # remote_urls_newline_free <remote>
  local raw
  raw=$(git config --null --get-all "remote.$1.url" 2>/dev/null; printf x)
  raw="$raw$(git config --null --get-all "remote.$1.pushurl" 2>/dev/null; printf x)"
  case "$raw" in *$'\n'*) return 1 ;; esac
  return 0
}
stop() { # stop <guard> <detail>
  echo "STOP $1 {\"detail\":\"$(json_escape "$2")\"}"
  exit 2
}
lookup_failed() { # lookup_failed <what> <detail>
  local excerpt="" extra=""
  [ -s "${GH_ERR:-}" ] && excerpt=$(tr -d '\0' < "$GH_ERR" | head -c 300)
  [ -z "$excerpt" ] || extra=",\"stderr\":\"$(json_escape "$excerpt")\""
  echo "LOOKUP_FAILED $1 {\"detail\":\"$(json_escape "$2")\"$extra}"
  exit 4
}

# Forge reads keep gh's stderr here so lookup_failed can quote why a read
# failed. head, not tail: gh's summary line comes first, before any body.
GH_ERR=$(mktemp) || lookup_failed tmp "mktemp failed"
trap 'rm -f -- "$GH_ERR"' EXIT
# Go's http2debug trace prints the Authorization header unredacted. Drop
# that one setting and keep any other GODEBUG setting gh may rely on.
GH_GODEBUG=$(printf '%s' "${GODEBUG:-}" | sed -E 's/(^|,)http2debug=[^,]*//g; s/^,//')
# Run one forge read, keeping its stderr only when it fails, so a warning
# from a read that worked can't attach to a later failure. GH_DEBUG is set
# empty, not unset: gh falls back to the legacy DEBUG variable when
# GH_DEBUG is unset, and debug output carries headers and response bodies.
gh_read() {
  GH_DEBUG= GODEBUG="$GH_GODEBUG" gh "$@" 2>"$GH_ERR" || return
  : > "$GH_ERR"
}

# Percent-encode one URL path segment or query value. Forge-sourced branch
# names are parsed as URL syntax by the API client, so a branch legitimately
# named release#1 would otherwise query the rules for release (the #1 reads
# as a fragment), and a ? truncates the same way.
urlencode() {
  # LC_ALL=C makes the slice byte-wise, so multibyte names encode as their
  # UTF-8 bytes rather than mis-encoding a codepoint above 255.
  local LC_ALL=C s="$1" out="" c i
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [A-Za-z0-9.~_-]) out+="$c" ;;
      # Mask to one byte: bash 3.2 (the macOS system shell) sign-extends
      # high bytes through printf %X, which would corrupt every multibyte
      # name into a filter that matches nothing.
      *) out+=$(printf '%%%02X' "$(( $(printf '%d' "'$c") & 255 ))") ;;
    esac
  done
  printf '%s' "$out"
}

# --- PR facts ---------------------------------------------------------------

# Ref names cannot contain whitespace or control characters (git
# check-ref-format), so a tab-separated read is faithful for branch fields;
# the title, which can hold anything, is read separately where needed.
# The ~ sentinel keeps a null field (a deleted fork's owner or repo) from
# collapsing out of the tab-separated read and shifting every later field:
# tabs are IFS whitespace, so consecutive tabs read as one separator.
pr_fields=$(gh_read pr view "$PR" --repo="$REPO" \
  --json state,headRefName,baseRefName,headRefOid,isCrossRepository,headRepositoryOwner,headRepository,url \
  --jq '[.state,.headRefName,.baseRefName,.headRefOid,(.isCrossRepository|tostring),(.headRepositoryOwner.login // "~"),(.headRepository.name // "~"),.url] | @tsv') \
  || lookup_failed pr-view "could not read PR $PR from $REPO"
IFS=$'\t' read -r PR_STATE BRANCH BASE FORGE_HEAD_OID IS_FORK HEAD_OWNER HEAD_REPO_NAME PR_URL <<< "$pr_fields"
[ -n "$BRANCH" ] && [ -n "$BASE" ] || lookup_failed pr-view "PR $PR returned empty branch fields"
if [ "$HEAD_OWNER" != "~" ]; then
  case "$HEAD_OWNER" in *[!A-Za-z0-9-]*)
    lookup_failed pr-view "unexpected head-owner form: $HEAD_OWNER" ;;
  esac
fi
if [ "$IS_FORK" = true ]; then
  { [ "$HEAD_OWNER" != "~" ] && [ "$HEAD_REPO_NAME" != "~" ]; } \
    || lookup_failed pr-view "the fork's head repository is gone; its branch cannot be checked or cleaned from here"
  HEAD_REPO="$HEAD_OWNER/$HEAD_REPO_NAME"
else
  HEAD_REPO="$REPO"
fi
# The forge host this PR lives on, for matching configured remotes.
PR_HOST="${PR_URL#*://}"; PR_HOST="${PR_HOST%%/*}"
PR_HOST=$(printf '%s' "$PR_HOST" | tr 'A-Z' 'a-z')
[ -n "$PR_HOST" ] || lookup_failed pr-view "could not derive the forge host from $PR_URL"
# A leading-hyphen ref is valid at the ref level even though git branch
# refuses to create one, and git checkout's -- means pathspec rather than
# branch, so the bare-name switch below cannot be terminated: refuse the
# shape instead of guarding each use.
case "$BRANCH" in -*) stop bad-name "head branch begins with a hyphen: $BRANCH" ;; esac
case "$BASE" in -*) stop bad-name "base branch begins with a hyphen: $BASE" ;; esac

ENC_BRANCH=$(urlencode "$BRANCH")
ENC_BASE=$(urlencode "$BASE")

# --- shared guards ----------------------------------------------------------

probe_component_alias() { # probe_component_alias <directory> <name> <name>
  local probe left right rc=1
  probe=$(mktemp -d "$1/.self-merge-ref-alias.XXXXXX" 2>/dev/null) \
    || lookup_failed name-collision "could not create a same-filesystem ref-alias probe"
  left="$probe/$2"
  right="$probe/$3"
  if ! : > "$left" || ! : > "$right"; then
    rm -rf -- "$probe" >/dev/null 2>&1
    lookup_failed name-collision "could not write the same-filesystem ref-alias probe"
  fi
  [ "$left" -ef "$right" ] && rc=0
  rm -rf -- "$probe" >/dev/null 2>&1 \
    || lookup_failed name-collision "could not remove the same-filesystem ref-alias probe"
  return "$rc"
}

filesystem_names_alias() { # filesystem_names_alias <ref-name> <ref-name>
  # Filesystem casefolding can be directory-scoped. Walk equal or aliasing
  # path components through the real loose-ref hierarchy while it exists;
  # only use an inherited temporary directory once a packed-only prefix has
  # no directory whose effective semantics can be inspected.
  local common refs_dir current virtual_root=""
  local left_rest="$1" right_rest="$2" left_part right_part
  local left_more right_more next
  out_exact common git rev-parse --git-common-dir \
    || lookup_failed name-collision "could not locate the repository's common directory"
  refs_dir="$common/refs/heads"
  mkdir -p -- "$refs_dir" 2>/dev/null \
    || lookup_failed name-collision "could not locate the repository's loose-ref directory"
  current="$refs_dir"
  while :; do
    case "$left_rest" in
      */*) left_part="${left_rest%%/*}"; left_rest="${left_rest#*/}"; left_more=1 ;;
      *) left_part="$left_rest"; left_rest=""; left_more=0 ;;
    esac
    case "$right_rest" in
      */*) right_part="${right_rest%%/*}"; right_rest="${right_rest#*/}"; right_more=1 ;;
      *) right_part="$right_rest"; right_rest=""; right_more=0 ;;
    esac
    if [ "$left_part" != "$right_part" ] \
        && ! probe_component_alias "$current" "$left_part" "$right_part"; then
      [ -z "$virtual_root" ] || rm -rf -- "$virtual_root" >/dev/null 2>&1 \
        || lookup_failed name-collision "could not remove the inherited ref-alias probe"
      return 1
    fi
    if [ "$left_more" -eq 0 ] || [ "$right_more" -eq 0 ]; then
      [ -z "$virtual_root" ] || rm -rf -- "$virtual_root" >/dev/null 2>&1 \
        || lookup_failed name-collision "could not remove the inherited ref-alias probe"
      [ "$left_more" -eq "$right_more" ]
      return
    fi
    if [ -d "$current/$left_part" ]; then
      current="$current/$left_part"
    elif [ -d "$current/$right_part" ]; then
      current="$current/$right_part"
    else
      next=$(mktemp -d "$current/.self-merge-ref-alias.XXXXXX" 2>/dev/null) \
        || lookup_failed name-collision "could not create an inherited ref-alias probe"
      [ -n "$virtual_root" ] || virtual_root="$next"
      current="$next"
    fi
  done
}

ref_names_alias() { # ref_names_alias <ref-name> <ref-name>
  local left="$1" right="$2"
  [ "$left" = "$right" ] && return 0
  # Preserve the cheap, deterministic ASCII check even when a repository's
  # core.ignorecase setting was copied to a case-sensitive filesystem, but
  # never trust a false or missing setting to describe the actual filesystem.
  if [ "$(git config --type=bool --get core.ignorecase 2>/dev/null)" = true ] \
      && [ "$(printf '%s' "$left" | tr 'A-Z' 'a-z')" \
        = "$(printf '%s' "$right" | tr 'A-Z' 'a-z')" ]; then
    return 0
  fi
  filesystem_names_alias "$left" "$right"
}

# Facts about the base repository, loaded once per run: the default branch
# for the collision guard, the fork lineage and count for the consumer
# guards, and whether the forge auto-deletes a merged PR's head branch.
REPO_FACTS_LOADED=""
load_repo_facts() {
  [ -n "$REPO_FACTS_LOADED" ] && return 0
  local facts rn
  facts=$(gh_read api "repos/$REPO" \
    --jq '[.default_branch, (.fork|tostring), (.forks_count|tostring), (.delete_branch_on_merge|tostring), (.parent.full_name // "~"), (.source.full_name // "~"), (.clone_url // "~"), (.ssh_url // "~"), (.merge_commit_title // "~"), (.merge_commit_message // "~")] | @tsv') \
    || lookup_failed repo-facts "could not read repository facts for $REPO"
  IFS=$'\t' read -r DEFAULT_BRANCH REPO_IS_FORK FORKS_COUNT DELETE_BRANCH_ON_MERGE PARENT_REPO SOURCE_REPO REPO_CLONE_URL REPO_SSH_URL MERGE_COMMIT_TITLE_SETTING MERGE_COMMIT_MESSAGE_SETTING <<< "$facts"
  [ -n "$DEFAULT_BRANCH" ] || lookup_failed repo-facts "empty default branch for $REPO"
  case "$REPO_IS_FORK" in true|false) ;; *)
    lookup_failed repo-facts "unexpected fork flag: $REPO_IS_FORK" ;;
  esac
  case "$DELETE_BRANCH_ON_MERGE" in true|false) ;; *)
    lookup_failed repo-facts "unexpected delete_branch_on_merge flag: $DELETE_BRANCH_ON_MERGE" ;;
  esac
  case "$FORKS_COUNT" in ''|*[!0-9]*)
    lookup_failed repo-facts "unexpected forks_count: $FORKS_COUNT" ;;
  esac
  [ "$REPO_CLONE_URL" != "~" ] && [ "$REPO_SSH_URL" != "~" ] \
    || lookup_failed repo-facts "repository clone endpoints are missing"
  REPO_CLONE_ID=$(url_id "$REPO_CLONE_URL")
  REPO_SSH_ID=$(url_id "$REPO_SSH_URL")
  case "$REPO_CLONE_ID,$REPO_SSH_ID" in host\ *,host\ *) ;; *)
    lookup_failed repo-facts "repository clone endpoints are not hosted URL identities" ;;
  esac
  for rn in "$PARENT_REPO" "$SOURCE_REPO"; do
    case "$rn" in *[!A-Za-z0-9._/~-]*)
      lookup_failed repo-facts "unexpected repository name in fork lineage: $rn" ;;
    esac
  done
  REPO_FACTS_LOADED=1
}

collision_check() {
  load_repo_facts
  for ref_name in "$BRANCH" "$BASE" "$DEFAULT_BRANCH"; do
    git check-ref-format "refs/heads/$ref_name" >/dev/null 2>&1 \
      || lookup_failed name-collision "the forge returned an invalid branch name: $ref_name"
  done
  if ref_names_alias "$BRANCH" "$BASE"; then
    stop name-collision "head branch $BRANCH resolves to the same ref as base $BASE"
  fi
  if ref_names_alias "$BRANCH" "$DEFAULT_BRANCH"; then
    stop name-collision "head branch $BRANCH resolves to the same ref as default branch $DEFAULT_BRANCH"
  fi
}

# Workspace preflight, in the checkout this script runs from, which is the
# base checkout the later phases operate from. A clean tree elsewhere says
# nothing.
workspace_preflight() {
  # -uall on the command line overrides status.showUntrackedFiles=no; a
  # guard that inherits repository configuration can be switched off by the
  # repository it protects.
  local dirty
  dirty=$(git status -uall --porcelain 2>/dev/null) \
    || stop not-a-repo "not inside a git working tree"
  [ -z "$dirty" ] || stop dirty-tree "uncommitted changes present (git status -uall --porcelain)"
  if op_probe .; then
    stop op-in-progress "$OP_FOUND exists: a git operation is paused here"
  fi
}

# Is a git operation paused in the given worktree? Operation state is
# per-worktree, so this checkout's probes say nothing about another
# worktree. Probe the per-worktree paths, never the names as
# revisions: an ordinary refs/heads/MERGE_HEAD otherwise looks like a
# paused merge. out_exact preserves a trailing newline in a linked
# worktree's git-dir path; -L also catches a dangling marker symlink.
# rebase-apply covers an interrupted git am.
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

# Parse `git worktree list --porcelain -z` NUL-aware: the output is
# NUL-terminated fields, not paths, so the reader strips the leading
# "worktree " keyword and pairs each path with the branch field that
# follows it. A command substitution would strip a trailing newline from a
# path, and a line-oriented read mis-pairs on paths holding newlines, so
# the fields stream through a temp file into read -d ''.
worktree_scan() { # worktree_scan <ref>: sets WT_MATCH to the unique path
  # whose branch field is exactly <ref>, empty when none; duplicates stop
  local want="$1" tmp field cand="" count=0
  WT_MATCH=""
  tmp=$(mktemp) || lookup_failed worktree-scan "mktemp failed"
  git worktree list --porcelain -z > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed worktree-scan "git worktree list failed"; }
  while IFS= read -r -d '' field; do
    case "$field" in
      "worktree "*) cand="${field#worktree }" ;;
      branch*)
        if [ "$field" = "branch $want" ]; then
          count=$((count + 1))
          WT_MATCH="$cand"
        fi
        ;;
    esac
  done < "$tmp"
  rm -f "$tmp"
  [ "$count" -le 1 ] \
    || stop duplicate-worktree "$count worktrees check out $want; the sequence cannot choose one without leaving or moving another"
}

layout_check() {
  # The current worktree's root is compared by inode (-ef) against a
  # relative path: --show-cdup is dots and slashes and cannot end in a
  # newline, while --show-toplevel through a command substitution loses a
  # trailing newline the scanned worktree paths faithfully keep, so a
  # string comparison would misidentify the current worktree exactly when
  # the path is hostile.
  local base_wt
  CWD_CDUP=$(git rev-parse --show-cdup 2>/dev/null) \
    || stop not-a-repo "not inside a git working tree"
  CWD_CDUP="${CWD_CDUP:-.}"
  out_exact WORKTREE_ROOT physical_dir "$CWD_CDUP" \
    || stop not-a-repo "could not resolve the current worktree root"
  worktree_scan "refs/heads/$BASE"; base_wt="$WT_MATCH"
  if [ -n "$base_wt" ] && ! [ "$base_wt" -ef "$CWD_CDUP" ]; then
    stop wrong-checkout "the base branch is checked out in another worktree: run this phase from $base_wt"
  fi
  # Reject ambiguity at the layout boundary. land_rebase repeats this scan
  # immediately before moving the head worktree, retrieving the path afresh
  # and closing layout changes made during the earlier checks.
  worktree_scan "refs/heads/$BRANCH"
}

# Consumer guards, both directions. An error is unknown and unknown keeps
# the branch: a failed listing returns no rows, which would otherwise read
# as "nothing depends on this branch" moments before a delete.
consumer_checks() {
  load_repo_facts
  local shared stacked target seen="" n
  if [ "$IS_FORK" = true ]; then
    shared=$(gh_read api "repos/$REPO/pulls?state=open&head=$HEAD_OWNER:$ENC_BRANCH" \
      --jq "[.[] | select(.number != $PR) | .number] | length") \
      || lookup_failed shared-head "could not list open PRs sharing head $HEAD_OWNER:$BRANCH"
  else
    shared=$(gh_read pr list --repo="$REPO" --head="$BRANCH" --state=open --json=number \
      --jq "[.[] | select(.number != $PR) | .number] | length") \
      || lookup_failed shared-head "could not list open PRs sharing head $BRANCH"
  fi
  case "$shared" in ''|*[!0-9]*) lookup_failed shared-head "unparseable shared-head listing" ;; esac
  [ "$shared" -eq 0 ] || stop shared-head "$shared other open PR(s) use $BRANCH as their head; deleting or auto-deleting it closes them"
  # Stacked PRs are reported, not refused: nothing in these phases deletes
  # the branch. merge-cleanup owns the delete and retargets each
  # same-repository child onto the base first. A cross-repository head's
  # children live in the head's repository, where neither the forge nor
  # merge-cleanup can retarget them onto this base, so they still stop.
  stacked=$(gh_read pr list --repo="$HEAD_REPO" --base="$BRANCH" --state=open --json=number \
    --jq '[.[].number] | tojson') \
    || lookup_failed stacked-prs "could not list open PRs based on $BRANCH"
  n=${stacked#\[}; n=${n%\]}
  case "$stacked" in '['*']') ;; *) lookup_failed stacked-prs "unparseable stacked-PR listing" ;; esac
  case "$n" in *[!0-9,]*|,*|*,|*,,*) lookup_failed stacked-prs "unparseable stacked-PR listing" ;; esac
  STACKED_PRS=$stacked
  if [ -n "$n" ]; then
    [ "$IS_FORK" = false ] \
      || stop stacked-prs "open PR(s) $n in $HEAD_REPO are based on $BRANCH and cannot be retargeted onto $REPO/$BASE"
    echo "land.sh: PR $PR: open PR(s) $n are based on $BRANCH; they move onto $BASE when $BRANCH is deleted after the merge" >&2
  fi
  # A repository that is itself a fork: its branch can simultaneously head
  # a PR to the parent or root of its network, which the per-repository
  # listings above cannot see. Query the recorded lineage; no cross-repo
  # number exclusion, since another repository's PR can share this PR's
  # number without being it.
  if [ "$REPO_IS_FORK" = true ]; then
    for target in "$PARENT_REPO" "$SOURCE_REPO"; do
      [ "$target" != "~" ] || continue
      [ "$target" != "$REPO" ] || continue
      case " $seen " in *" $target "*) continue ;; esac
      seen="$seen $target"
      n=$(gh_read api "repos/$target/pulls?state=open&head=${REPO%%/*}:$ENC_BRANCH" --jq length) \
        || lookup_failed shared-head "could not list open PRs in $target sharing head $BRANCH"
      case "$n" in ''|*[!0-9]*) lookup_failed shared-head "unparseable listing from $target" ;; esac
      [ "$n" -eq 0 ] || stop shared-head "$n open PR(s) in $target use $BRANCH as their head; deleting or auto-deleting it closes them"
    done
  fi
}

# A same-repository head on a base repository that is itself a fork can
# also head PRs to sibling forks, which no repository-scoped query can
# enumerate. If this repository auto-deletes heads on merge, merge-cleanup's
# consumer guards run too late: the forge already removed the branch. Stop
# before both direct merges and queue enqueueing.
fork_auto_delete_check() {
  load_repo_facts
  if [ "$IS_FORK" != true ] && [ "$DELETE_BRANCH_ON_MERGE" = true ]; then
    if [ "$REPO_IS_FORK" = true ] || [ "$FORKS_COUNT" -gt 0 ]; then
      stop fork-auto-delete "$REPO participates in a fork network and auto-deletes merged head branches; $BRANCH may have unenumerable fork consumers, so merging could delete it before merge-cleanup can check its consumers"
    fi
  fi
}

# A queue owns the eventual commit message as well as the merge method:
# gh's enqueue operation cannot carry --subject/--body through to that
# commit. The repository settings therefore become part of the title-only
# history contract whenever a MERGE queue applies.
queue_message_check() {
  [ "${QUEUE:-absent}" = merge ] || return
  load_repo_facts
  if [ "$MERGE_COMMIT_TITLE_SETTING" != PR_TITLE ] \
     || [ "$MERGE_COMMIT_MESSAGE_SETTING" != BLANK ]; then
    stop queue-message "the merge queue on $BASE cannot honor command-line subject/body; repository merge-commit settings must be PR_TITLE and BLANK (got: $MERGE_COMMIT_TITLE_SETTING and $MERGE_COMMIT_MESSAGE_SETTING)"
  fi
}

# A merge queue picks the integration method itself, so --merge cannot
# promise first-parent history: identify the queue's method before anything
# is enqueued, from the branch-rules API (the CLI's ruleset commands have no
# JSON output and cannot report the method). Fail closed on any shape this
# read does not recognize: the payload belongs to the forge.
queue_check() {
  local methods row method="" count=0
  methods=$(gh_read api --paginate "repos/$REPO/rules/branches/$ENC_BASE" \
    --jq '.[] | select(.type == "merge_queue") | (.parameters.merge_method // "unidentified")') \
    || lookup_failed queue-rules "could not read branch rules for $BASE"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    count=$((count + 1))
    method="$row"
  done <<< "$methods"
  if [ "$count" -eq 0 ]; then
    QUEUE=absent
    return
  fi
  [ "$count" -eq 1 ] \
    || stop queue-method "multiple merge-queue rules apply to $BASE; the integration method is ambiguous"
  case "$method" in
    MERGE) QUEUE=merge ;;
    SQUASH|REBASE) stop queue-method "the merge queue on $BASE integrates by $method, not a merge commit" ;;
    *) stop queue-method "could not identify the merge queue's method on $BASE (got: $method)" ;;
  esac
  queue_message_check
}

# Normalized identity of a remote URL. Hosted forms
# (scheme://[user@]host[:port]/path, or the scp form user@host:path)
# yield "host <transport> <authority> <path>", with only the authority
# lowercased; the explicit type and transport tags cannot collide with a
# single-label hostname. The
# complete, case-preserved hosted path is load-bearing: /a/owner/name and
# /b/owner/name, /A/owner/name and /a/owner/name, or repo and repo.git can
# be different repositories behind one authority. A URL with no host is a
# local path and is identified by its full path, case preserved and with
# only a trailing slash normalized away. file:///path and
# file://localhost/path use Git's local absolute-path semantics; other
# file authorities and scheme spellings stay a distinct, fail-closed
# identity rather than being mistaken for a relative path or hosted
# transport.
url_id() {
  local raw="$1" host rest authority path after_user scheme transport="" ssh_user=""
  case "$raw" in
    file://*)
      rest="${raw#*://}"
      case "$rest" in
        /*) raw="$rest" ;;
        [Ll][Oo][Cc][Aa][Ll][Hh][Oo][Ss][Tt]/*) raw="/${rest#*/}" ;;
        *)
          printf 'file-url %s' "$rest"
          return
          ;;
      esac
      ;;
    [Ff][Ii][Ll][Ee]://*)
      printf 'file-url %s' "$raw"
      return
      ;;
  esac
  case "$raw" in
    *://*)
      # Authority = up to the first slash. Non-SSH userinfo is credentials
      # and does not change the repository endpoint; an SSH username does,
      # so preserve it. Split at the last @ first so a colon inside
      # user:pass cannot truncate the host to the username, then keep host
      # and port together: two ports are two endpoints.
      scheme="${raw%%://*}"
      rest="${raw#*://}"
      authority="${rest%%/*}"
      host="${authority##*@}"
      case "$scheme" in
        ssh|git+ssh|ssh+git)
          transport=ssh
          case "$authority" in *@*) ssh_user="${authority%"@$host"}" ;; esac
          ;;
        *) transport="$scheme" ;;
      esac
      if [ "$rest" = "$authority" ]; then path=""; else path="${rest#*/}"; fi
      ;;
    *:*)
      # Git's SCP form allows an optional user. A slash before the first
      # colon makes the value a local path instead, while userless
      # host:path and bracketed IPv6 forms are still hosted transports.
      transport=scp
      case "${raw%%:*}" in
        */*) host="" ;;
        *)
          after_user="${raw##*@}"
          case "$raw" in *@*) ssh_user="${raw%"@$after_user"}" ;; esac
          case "$after_user" in
            \[*\]:*)
              host="${after_user%%]:*}]"
              path="${after_user#*]:}"
              ;;
            *)
              host="${after_user%%:*}"
              path="${after_user#*:}"
              ;;
          esac
          ;;
      esac
      ;;
    *) host="" ;;
  esac
  if [ -z "$host" ]; then
    case "$raw" in /) ;; */) raw="${raw%/}" ;; esac
    printf 'path %s' "$raw"
    return
  fi
  host=$(printf '%s' "$host" | tr 'A-Z' 'a-z')
  [ -z "$ssh_user" ] || host="$ssh_user@$host"
  path="${path%/}"
  printf 'host %s %s %s' "$transport" "$host" "$path"
}

# Resolve a hostless URL to the filesystem destination Git will use now.
# Ask Git to expand its leading ~/ and ~user/ path syntax, root other relative
# paths at the worktree root, and follow every symlink before the identity
# crosses a checkout boundary. Keep the remaining resolution in shell so
# the script does not gain another executable dependency.
canonical_local_path() { # canonical_local_path <path>
  local path="$1" link dir base physical suffix="" hops=0
  case "$path" in
    ~*) out_exact path git -c "selfmerge.path=$path" config --path --get selfmerge.path \
      || return 1 ;;
  esac
  case "$path" in
    /*) ;;
    *)
      case "$WORKTREE_ROOT" in
        /) path="/$path" ;;
        *) path="$WORKTREE_ROOT/$path" ;;
      esac
      ;;
  esac
  while [ -L "$path" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 40 ] || return 1
    out_exact link readlink "$path" || return 1
    [ -n "$link" ] || return 1
    dir="${path%/*}"; [ -n "$dir" ] || dir=/
    case "$link" in /*) path="$link" ;; *) path="$dir/$link" ;; esac
  done
  while ! [ -d "$path" ]; do
    base="${path##*/}"
    [ -n "$base" ] || return 1
    suffix="/$base$suffix"
    dir="${path%/*}"; [ -n "$dir" ] || dir=/
    [ "$dir" != "$path" ] || return 1
    path="$dir"
  done
  cd -P -- "$path" 2>/dev/null || return 1
  out_exact physical pwd -P || return 1
  printf '%s%s' "${physical%/}" "$suffix"
}

remote_url_id() { # remote_url_id <effective-url>
  local id path resolved
  id=$(url_id "$1")
  case "$id" in
    path\ *)
      path="${id#path }"
      [ -n "$path" ] || return 1
      out_exact resolved canonical_local_path "$path" || return 1
      printf 'path %s' "$resolved"
      ;;
    *) printf '%s' "$id" ;;
  esac
}

# The forge identifies a repository by host plus owner/name even when the
# Git endpoint has a deployment-specific path prefix. Keep this derivation
# separate from url_id: it is for selecting a candidate remote, never for
# proving that its fetch and push destinations are the same repository.
url_forge_id() {
  local id transport host path forge_path parent owner name
  id=$(url_id "$1")
  case "$id" in
    host\ *) id="${id#host }" ;;
    *) return 1 ;;
  esac
  transport="${id%% *}"; id="${id#* }"
  host="${id%% *}"; path="${id#* }"
  # SSH users are endpoint-defining for fetch/push equality, but the forge
  # candidate match is deliberately only host plus owner/name.
  host="${host##*@}"
  forge_path=$(printf '%s' "$path" | tr 'A-Z' 'a-z')
  forge_path="${forge_path%.git}"
  name="${forge_path##*/}"; parent="${forge_path%/*}"
  [ "$parent" != "$forge_path" ] || return 1
  owner="${parent##*/}"
  [ -n "$owner" ] && [ -n "$name" ] || return 1
  printf '%s %s/%s' "$host" "$owner" "$name"
}

# Does a remote have exactly one push destination with the expected identity?
# --push --all is load-bearing: a remote can configure several push URLs,
# git push sends to every one of them, and the plain --push query returns
# only the first, so validating one URL blesses a broadcast. Even duplicate
# effective URLs are unsafe: the first lease delete succeeds and the second
# fails against stale lease information. The queries return
# insteadOf/pushInsteadOf-expanded URLs (verified), so config rewrites cannot
# smuggle in a different destination either.
push_ids_match() { # push_ids_match <remote> <expected-id>
  local purls pu count=0
  out_exact purls git remote get-url --push --all -- "$1" || return 1
  while IFS= read -r pu; do
    [ -n "$pu" ] || return 1
    count=$((count + 1))
    [ "$(url_id "$pu")" = "$2" ] || return 1
  done <<< "$purls"
  [ "$count" -eq 1 ]
}

# Resolve an SSH host, possibly a local ~/.ssh/config Host alias, to the
# concrete hostname, user, and port Git will actually connect to. The forge
# identity guards below compare a remote against the forge's authoritative
# clone endpoints; a local alias (HostName github.com behind the label
# bnw.github.com) names that same endpoint, so it must resolve before the
# comparison rather than read as a foreign host. `ssh -G` computes the
# effective config offline without connecting, and the user's own ssh config
# is the same trust domain as the git insteadOf rules the script already
# honors. Resolve the exact user@host target Git will reach: ~/.ssh/config can
# expand a different HostName/port per remote user (`Match user`, `%r` in
# HostName), so resolving a bare host could bless a userless endpoint while the
# delete routes through the user-qualified one. Fails closed (nonzero, empties
# left) when ssh is absent or cannot resolve. SSH_ALIAS_HOST/USER/PORT are the
# outputs.
SSH_ALIAS_HOST="" SSH_ALIAS_USER="" SSH_ALIAS_PORT=""
ssh_resolved_endpoint() { # ssh_resolved_endpoint <host> [user]
  local host="$1" user="${2:-}" target key val resolved
  SSH_ALIAS_HOST="" SSH_ALIAS_USER="" SSH_ALIAS_PORT=""
  command -v ssh >/dev/null 2>&1 || return 1
  # Git honors an ssh-command override (GIT_SSH_COMMAND, then core.sshCommand,
  # else GIT_SSH) for the fetch/ls-remote/push that deletes the branch, but this
  # guard queries the plain `ssh` on PATH. Under an override the offline `ssh -G`
  # no longer reflects the endpoint Git reaches, so fail closed rather than bless
  # a possibly-divergent host. The intersection that this stops (an alias that
  # needs resolving while an override is active) is narrow and errs safe.
  [ -n "${GIT_SSH_COMMAND:-}" ] && return 1
  [ -n "${GIT_SSH:-}" ] && return 1
  [ -n "$(git config --get core.sshCommand 2>/dev/null)" ] && return 1
  # An option-shaped host or user could be read as an ssh flag even after --, so
  # refuse it outright rather than trust a single guard.
  case "$host" in ''|-*) return 1 ;; esac
  # Query user@host when the URL names a user, matching Git's own connection; a
  # bare host otherwise, matching Git applying the config's User.
  target="$host"
  case "$user" in
    -*|*@*) return 1 ;;
    ?*) target="$user@$host" ;;
  esac
  resolved=$(ssh -G -- "$target" 2>/dev/null) || return 1
  while read -r key val; do
    case "$key" in
      hostname) [ -n "$SSH_ALIAS_HOST" ] || SSH_ALIAS_HOST="$val" ;;
      user) [ -n "$SSH_ALIAS_USER" ] || SSH_ALIAS_USER="$val" ;;
      port) [ -n "$SSH_ALIAS_PORT" ] || SSH_ALIAS_PORT="$val" ;;
    esac
  done <<< "$resolved"
  [ -n "$SSH_ALIAS_HOST" ] || return 1
  SSH_ALIAS_HOST=$(printf '%s' "$SSH_ALIAS_HOST" | tr 'A-Z' 'a-z')
}

# Rewrite an SSH remote URL whose host is a local alias into the concrete URL
# form that names the real endpoint, so the forge identity comparison sees the
# true host and user. Only ssh-family transports (scp-like host:path and the
# ssh:// schemes) carry aliases; every other URL is left to its existing
# mismatch. The rewrite substitutes the resolved hostname, fills in the
# resolved user when the URL states none (an alias commonly carries `User
# git`), and keeps the original transport form and path byte-for-byte. It
# fails, leaving the caller on its mismatch, when ssh cannot resolve, when the
# resolved port is not the default (a non-default port is a genuinely different
# endpoint than the forge's default-port ssh_url and must not be blessed), or
# when the host is unchanged (no alias in play). The rewritten URL feeds only
# the identity check; fetch and push keep the original alias URL so its ssh
# config still applies, while SSH_ALIAS_PIN_COMMAND pins the checked endpoint
# for the destructive head transports.
SSH_ALIAS_URL="" SSH_ALIAS_PIN_COMMAND=""
ssh_alias_resolve() { # ssh_alias_resolve <url>
  local raw="$1" scheme rest authority before after path="" host user="" newuser newauth
  SSH_ALIAS_URL="" SSH_ALIAS_PIN_COMMAND=""
  case "$raw" in
    *://*)
      scheme="${raw%%://*}"
      case "$scheme" in ssh|git+ssh|ssh+git) ;; *) return 1 ;; esac
      rest="${raw#*://}"
      authority="${rest%%/*}"
      case "$authority" in *@*) user="${authority%@*}"; host="${authority##*@}" ;;
        *) host="$authority" ;; esac
      [ "$rest" = "$authority" ] || path="${rest#*/}"
      ;;
    *:*)
      case "${raw%%:*}" in */*) return 1 ;; esac
      before="${raw%%:*}"; after="${raw#*:}"
      case "$before" in *@*) user="${before%@*}"; host="${before##*@}" ;;
        *) host="$before" ;; esac
      ;;
    *) return 1 ;;
  esac
  # A port or IPv6 literal in the host is not the simple alias this resolves.
  case "$host" in ''|*:*|\[*) return 1 ;; esac
  ssh_resolved_endpoint "$host" "$user" || return 1
  # GIT_SSH_COMMAND is parsed as a shell command by Git. Only literal endpoint
  # fields may enter it; quoting untrusted ssh -G output would be a weaker
  # boundary because another shell parses the value later.
  case "$SSH_ALIAS_HOST" in ''|*[!A-Za-z0-9.-]*) return 1 ;; esac
  case "$SSH_ALIAS_USER" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$SSH_ALIAS_PORT" in ''|*[!0-9]*) return 1 ;; esac
  [ "$SSH_ALIAS_PORT" = 22 ] || return 1
  [ "$SSH_ALIAS_HOST" != "$(printf '%s' "$host" | tr 'A-Z' 'a-z')" ] || return 1
  newuser="$user"; [ -n "$newuser" ] || newuser="$SSH_ALIAS_USER"
  case "$newuser" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  newauth="$SSH_ALIAS_HOST"; [ -z "$newuser" ] || newauth="$newuser@$SSH_ALIAS_HOST"
  SSH_ALIAS_PIN_COMMAND="ssh -o HostName=$SSH_ALIAS_HOST -o User=$newuser -o Port=$SSH_ALIAS_PORT -o CanonicalizeHostname=no"
  case "$raw" in
    *://*) [ -n "$path" ] && SSH_ALIAS_URL="$scheme://$newauth/$path" \
             || SSH_ALIAS_URL="$scheme://$newauth" ;;
    *) SSH_ALIAS_URL="$newauth:$after" ;;
  esac
}

# Run one Git transport with an optional command-scoped SSH endpoint pin. An
# empty pin runs plain git (the pin variable must never be exported as an empty
# GIT_SSH_COMMAND, which would break a non-alias SSH transport); a non-empty pin
# forces HostName/User/Port for this invocation only, so a Match-exec change
# after identity acceptance cannot redirect the destructive head transport.
git_with_ssh_pin() { # git_with_ssh_pin <ssh-command-or-empty> <git args...>
  local pin="$1"; shift
  if [ -n "$pin" ]; then
    GIT_SSH_COMMAND="$pin" git "$@"
  else
    git "$@"
  fi
}

# Resolve which configured remote points at a repository, matching the
# PR's forge host as well as the owner/name tail: a same-named repository
# on another host (a GitLab mirror of a GitHub repo) shares the tail, and
# deleting a branch there is the wrong remote's branch. Every push URL
# must carry the same identity as the fetch URL, because the existence
# checks read the fetch side while a push writes every configured push
# destination. A URL with no host (a local path or file://) never
# auto-resolves; pass the override flag for such a layout. Overridable
# because URL forms vary; unresolvable is a stop, not a guess.
resolve_remote() { # resolve_remote <owner/name>: sets RESOLVED_REMOTE
  local want r furl fid raw_fid forge_id resolved match=""
  want=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  RESOLVED_REMOTE=""
  while IFS= read -r r; do
    remote_urls_newline_free "$r" || continue
    out_exact furl git remote get-url -- "$r" || continue
    fid=$(url_id "$furl"); raw_fid="$fid"
    forge_id=$(url_forge_id "$furl") || forge_id=""
    # A local SSH host alias hides the true forge identity; resolve it and
    # retry the candidate match on the concrete endpoint when the raw URL
    # fails. push_ids_match still compares against the raw fetch id because
    # the configured push URLs carry the alias, not the resolved host.
    if { [ "$fid" != "$REPO_CLONE_ID" ] && [ "$fid" != "$REPO_SSH_ID" ]; } \
        || [ "$forge_id" != "$PR_HOST $want" ]; then
      ssh_alias_resolve "$furl" || continue
      resolved="$SSH_ALIAS_URL"
      fid=$(url_id "$resolved")
      forge_id=$(url_forge_id "$resolved") || continue
    fi
    case "$fid" in "$REPO_CLONE_ID"|"$REPO_SSH_ID") ;; *) continue ;; esac
    [ "$forge_id" = "$PR_HOST $want" ] || continue
    push_ids_match "$r" "$raw_fid" || continue
    if [ -z "$match" ] || [ "$r" = origin ]; then match="$r"; fi
  done < <(git remote)
  RESOLVED_REMOTE="$match"
}

# A hosted override must still identify the PR's repository. A hostless
# mapping cannot be matched to forge identity, so naming that remote
# explicitly is the separate trust decision. A hostless mapping that remains
# after checkout is pinned to that identity; a replacement hosted mapping can
# instead be validated against the forge. CHECKED_REMOTE_ID exposes the
# validated identity to that checkout boundary, and fetch/push identity is
# still checked before a destructive head push. PINNED_SSH_COMMAND carries the
# alias endpoint pin for the destructive head transports, empty otherwise.
CHECKED_REMOTE_ID="" PINNED_SSH_COMMAND=""
remote_repo_check() { # remote_repo_check <remote> <role>
  local remote="$1" role="$2" configured u have_url=false furl endpoint_id resolved_id
  PINNED_SSH_COMMAND=""
  remote_urls_newline_free "$remote" \
    || stop remote-repo-mismatch "$role remote $remote has a newline-bearing URL whose forge identity cannot be compared faithfully"
  out_exact configured git config --get-all "remote.$remote.url" \
    || lookup_failed "$role-remote" "could not read $remote's configured URLs"
  while IFS= read -r u; do
    [ -n "$u" ] && have_url=true
  done <<< "$configured"
  [ "$have_url" = true ] \
    || lookup_failed "$role-remote" "$remote has no URL configured"
  out_exact furl git remote get-url -- "$remote" \
    || lookup_failed "$role-remote" "could not read $remote's URL"
  out_exact endpoint_id remote_url_id "$furl" \
    || stop remote-repo-mismatch "$role remote $remote's effective local destination could not be resolved safely"
  CHECKED_REMOTE_ID="$endpoint_id"
  case "$endpoint_id" in
    path\ *) return 0 ;;
    "$REPO_CLONE_ID"|"$REPO_SSH_ID") return 0 ;;
  esac
  # A local SSH host alias resolves to the forge's real endpoint; compare that
  # resolved identity before refusing. CHECKED_REMOTE_ID stays the alias id so
  # the post-checkout path-change guard still sees a hosted id (not a hostless
  # path). Only a head alias earns the endpoint pin the destructive transports
  # apply; the base fetch and resync route through the alias's own ssh config.
  if ssh_alias_resolve "$furl" \
      && out_exact resolved_id remote_url_id "$SSH_ALIAS_URL"; then
    case "$resolved_id" in "$REPO_CLONE_ID"|"$REPO_SSH_ID")
      [ "$role" != head ] || PINNED_SSH_COMMAND="$SSH_ALIAS_PIN_COMMAND"
      return 0
      ;;
    esac
  fi
  stop remote-repo-mismatch "$role remote $remote does not match PR repository $REPO's authoritative clone endpoints"
}

# --- landing ----------------------------------------------------------------

# Without branch protection nothing stops a merge of a head that was never
# tested against the current base. land runs one round of the landing
# procedure itself: the head must contain the base tip it fetched, CI must
# be green on that exact head, and the forge's base tip must still be the
# fetched one when the merge starts. Each refusal is a STOP and rerunning
# land is the retry, so every refusal reaches the caller.
LAND_TIP="" LAND_TMP_WT="" LAND_WT="" NEW_HEAD="" MOVE_ERR="" MOVE_IGNORED=false

# Encode a branch for a forge path that takes it as slash-separated
# segments (git/ref/heads/<branch>): each segment percent-encoded, the
# slashes kept.
urlencode_ref_path() {
  local rest="$1" out=""
  while :; do
    case "$rest" in
      */*) out+="$(urlencode "${rest%%/*}")/"; rest="${rest#*/}" ;;
      *) out+="$(urlencode "$rest")"; break ;;
    esac
  done
  printf '%s' "$out"
}

forge_base_tip() { # sets FORGE_BASE_TIP to the forge's current tip of $BASE
  FORGE_BASE_TIP=$(gh_read api "repos/$REPO/git/ref/heads/$(urlencode_ref_path "$BASE")" \
    --jq '.object.sha') \
    || lookup_failed base-ref "could not read the tip of $BASE from $REPO"
  case "$FORGE_BASE_TIP" in *[!0-9a-f]*|'')
    lookup_failed base-ref "unexpected tip for $BASE: $FORGE_BASE_TIP" ;;
  esac
  [ "${#FORGE_BASE_TIP}" -eq 40 ] \
    || lookup_failed base-ref "unexpected tip for $BASE: $FORGE_BASE_TIP"
}

# Read CI for one commit once. Sets CI_STATE to passed, failed, pending, or
# missing, and CI_DETAIL to what is not green. Only success, neutral, and
# skipped pass; every other conclusion (cancelled, timed_out,
# action_required, stale) fails. No check run and no commit status is
# missing, never green: CI that has not reported has not passed.
ci_read() { # ci_read <oid>
  local oid="$1" runs status st concl name total=0 bad="" waiting="" s_state s_total
  runs=$(gh_read api --paginate "repos/$REPO/commits/$oid/check-runs?per_page=100" \
    --jq '.check_runs[] | [.status, (.conclusion // "none"), .name] | @tsv') \
    || lookup_failed check-runs "could not read check runs for $oid"
  while IFS=$'\t' read -r st concl name; do
    [ -n "$st" ] || continue
    total=$((total + 1))
    if [ "$st" != completed ]; then
      waiting+=", $name ($st)"
    else
      case "$concl" in
        success|neutral|skipped) ;;
        *) bad+=", $name ($concl)" ;;
      esac
    fi
  done <<< "$runs"
  status=$(gh_read api "repos/$REPO/commits/$oid/status" \
    --jq '[.state, (.total_count|tostring)] | @tsv') \
    || lookup_failed commit-status "could not read the combined status for $oid"
  IFS=$'\t' read -r s_state s_total <<< "$status"
  case "$s_total" in ''|*[!0-9]*)
    lookup_failed commit-status "unparseable status count for $oid: $s_total" ;;
  esac
  # The combined state reads pending when no status exists at all, so it
  # means something only when the count is nonzero.
  if [ "$s_total" -gt 0 ]; then
    total=$((total + s_total))
    case "$s_state" in
      success) ;;
      pending) waiting+=", commit statuses (pending)" ;;
      failure|error) bad+=", commit statuses ($s_state)" ;;
      *) lookup_failed commit-status "unexpected combined state for $oid: $s_state" ;;
    esac
  fi
  if [ -n "$bad" ]; then CI_STATE=failed; CI_DETAIL="${bad#, }"
  elif [ -n "$waiting" ]; then CI_STATE=pending; CI_DETAIL="${waiting#, }"
  elif [ "$total" -eq 0 ]; then CI_STATE=missing; CI_DETAIL="no check runs or commit statuses"
  else CI_STATE=passed; CI_DETAIL="$total check(s) green"
  fi
}

ci_wait() { # ci_wait <oid>: returns only once CI passed on <oid>
  local oid="$1" deadline remaining sleep_for seen_passing=""
  deadline=$(( SECONDS + CI_CAP_MINUTES * 60 ))
  while :; do
    ci_read "$oid"
    [ "$CI_STATE" != failed ] \
      || stop checks-failed "CI failed on $oid: $CI_DETAIL; fix the branch, then run check and land again"
    # Workflows register their checks asynchronously after a push, so one
    # green read can be a fast check finishing before a slow one exists.
    # Pass only on the second consecutive green read with the same check
    # count; a first green read at the cap is still unconfirmed.
    if [ "$CI_STATE" = passed ]; then
      [ "$seen_passing" != "$CI_DETAIL" ] || return 0
      seen_passing="$CI_DETAIL"
    else
      seen_passing=""
    fi
    remaining=$(( deadline - SECONDS ))
    if [ "$remaining" -le 0 ]; then
      [ "$CI_STATE" != passed ] \
        || stop checks-pending "CI on $oid read green only once before the $CI_CAP_MINUTES-minute cap, so a slower check may not have registered yet; rerun land to confirm it"
      [ "$CI_STATE" != pending ] \
        || stop checks-pending "CI is still running on $oid after $CI_CAP_MINUTES minute(s): $CI_DETAIL; rerun land when it finishes"
      stop checks-missing "nothing reported CI on $oid within $CI_CAP_MINUTES minute(s); an unchecked commit is not green"
    fi
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

# Remove land's temporary worktree. It holds only a detached checkout of
# commits already in the object store, plus whatever hooks wrote there or a
# rebase left paused, so --force discards nothing of value.
remove_land_worktree() { # fails only when git cannot remove it
  local rc=0
  [ -n "$LAND_TMP_WT" ] || return 0
  if git worktree remove --force -- "$LAND_TMP_WT/wt" >/dev/null 2>&1; then
    rm -rf -- "$LAND_TMP_WT"
  else
    echo "land.sh: could not remove the temporary worktree at $LAND_TMP_WT/wt; remove it with git worktree remove --force" >&2
    rc=1
  fi
  LAND_TMP_WT=""
  return "$rc"
}

# Move local $BRANCH from <from> to <to>. A worktree that holds the branch
# moves with it through checkout --no-overwrite-ignore, which changes nothing
# when an ignored file is in the way: at a path <to> tracks, inside a
# directory <to> replaces with a file, or at a file <to> replaces with a
# directory. A plain rebase or reset overwrites or deletes such a file.
# Without a worktree only the ref moves, and only if it still holds <from>.
land_move_branch() { # land_move_branch <from> <to>; sets MOVE_ERR on failure
  local cur
  MOVE_ERR="" MOVE_IGNORED=false
  if [ -z "$LAND_WT" ]; then
    git update-ref "refs/heads/$BRANCH" "$2" "$1" >/dev/null 2>&1 && return 0
    MOVE_ERR="local $BRANCH no longer holds $1"
    return 1
  fi
  cur=$(git rev-parse --verify --quiet "refs/heads/$BRANCH")
  if [ "$cur" != "$1" ]; then
    MOVE_ERR="local $BRANCH is ${cur:-unreadable}, not $1"
    return 1
  fi
  # Submodule recursion would not pass --no-overwrite-ignore down. The C
  # locale keeps git's refusal text matchable. A failing post-checkout hook
  # fails the command after the move, so the ref and a clean index decide.
  MOVE_ERR=$(LC_ALL=C git -C "$LAND_WT" checkout --quiet --no-overwrite-ignore \
    --no-recurse-submodules -B "$BRANCH" "$2" 2>&1 >/dev/null) && return 0
  case "$MOVE_ERR" in *untracked*) MOVE_IGNORED=true ;; esac
  MOVE_ERR=$(printf '%s' "$MOVE_ERR" | tr -d '\0' | tr '\n\t' '  ' | tail -c 300)
  cur=$(git rev-parse --verify --quiet "refs/heads/$BRANCH")
  [ "$cur" = "$2" ] && [ -z "$(git -C "$LAND_WT" status --porcelain -uno --ignore-submodules=all 2>/dev/null)" ]
}

# Rebase the reviewed head onto LAND_TIP in a temporary detached worktree,
# so the rebase never runs where ignored files live, then move the local
# branch to the result. Sets NEW_HEAD and LAND_WT (the worktree that holds
# the branch, or empty). Every refusal here leaves $BRANCH at HEAD_OID and
# pushes nothing.
land_rebase() {
  local wt dirty err conflicts detail cur
  worktree_scan "refs/heads/$BRANCH"; LAND_WT="$WT_MATCH"
  if [ -n "$LAND_WT" ]; then
    dirty=$(git -C "$LAND_WT" status -uall --porcelain 2>/dev/null) \
      || lookup_failed head-worktree "could not read the status of the head worktree at $LAND_WT"
    [ -z "$dirty" ] \
      || stop dirty-tree "the head worktree at $LAND_WT has uncommitted changes; land does not move it under them"
    if op_probe "$LAND_WT"; then
      stop op-in-progress "$OP_FOUND exists in the head worktree at $LAND_WT"
    fi
  fi
  LAND_TMP_WT=$(mktemp -d) || lookup_failed rebase "mktemp failed"
  wt="$LAND_TMP_WT/wt"
  if ! git worktree add --quiet --detach -- "$wt" "$HEAD_OID" >/dev/null 2>&1; then
    # A failing post-checkout hook fails the add after registering it.
    git worktree remove --force -- "$wt" >/dev/null 2>&1
    rm -rf -- "$LAND_TMP_WT"; LAND_TMP_WT=""
    lookup_failed rebase "could not add a temporary worktree at $HEAD_OID"
  fi
  # This replaces the startup EXIT trap, so it keeps removing GH_ERR too.
  trap 'remove_land_worktree; rm -f -- "$GH_ERR"' EXIT
  err=$(mktemp) || lookup_failed rebase "mktemp failed"
  # Pin the settings that would let a rebase touch more than this commit:
  # autostash stashes and reapplies work, and updateRefs moves branches.
  if ! git -C "$wt" -c rebase.autoStash=false -c rebase.updateRefs=false \
      rebase --quiet "$LAND_TIP" >/dev/null 2>"$err"; then
    detail=$(tr -d '\0' < "$err" | tail -c 300); rm -f "$err"
    conflicts=$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
    [ -n "$conflicts" ] \
      || stop rebase-failed "rebasing $HEAD_OID onto $LAND_TIP failed without conflicts; $BRANCH is unchanged: $detail"
    stop rebase-conflict "rebasing $BRANCH onto $BASE tip $LAND_TIP conflicts in: ${conflicts% }. $BRANCH is unchanged at $HEAD_OID. Rebase it by hand, read git range-diff, push, then run check and land again"
  fi
  rm -f "$err"
  NEW_HEAD=$(git -C "$wt" rev-parse --verify HEAD 2>/dev/null) \
    || lookup_failed rebase "could not read the rebased head"
  # A leaked worktree would outlive the run unnoticed; stop while nothing
  # has moved.
  remove_land_worktree \
    || stop rebase-failed "the temporary worktree at $wt could not be removed; $BRANCH is unchanged at $HEAD_OID and nothing was pushed"
  # Every commit already on the base leaves nothing to land; pushing the
  # base tip as the head would empty the PR.
  [ "$NEW_HEAD" != "$LAND_TIP" ] \
    || stop rebase-failed "every commit on $BRANCH is already on $BASE, so there is nothing to land; $BRANCH is unchanged at $HEAD_OID"
  if ! land_move_branch "$HEAD_OID" "$NEW_HEAD"; then
    cur=$(git rev-parse --verify --quiet "refs/heads/$BRANCH")
    # A refusal leaves both the ref and the index at HEAD_OID; anything else
    # is a half-finished move that needs a person.
    [ "$cur" = "$HEAD_OID" ] && [ -z "$(git -C "${LAND_WT:-.}" status --porcelain -uno --ignore-submodules=all 2>/dev/null)" ] \
      || stop rebase-failed "moving $BRANCH to the rebased $NEW_HEAD failed partway: $BRANCH is ${cur:-unreadable} and nothing was pushed; inspect it by hand: $MOVE_ERR"
    [ "$MOVE_IGNORED" = false ] \
      || stop ignored-clobber "moving the head worktree at $LAND_WT to the rebased $NEW_HEAD would overwrite or remove ignored files, so nothing moved and nothing was pushed; move them aside, then rerun land: $MOVE_ERR"
    stop rebase-failed "could not move $BRANCH to the rebased $NEW_HEAD; it is unchanged at $HEAD_OID and nothing was pushed: $MOVE_ERR"
  fi
  # The agent judges the rebase from this, as it would a manual one.
  echo "land.sh: rebased $BRANCH onto $LAND_TIP; git range-diff $LAND_TIP $HEAD_OID $NEW_HEAD:" >&2
  git range-diff --no-color "$LAND_TIP" "$HEAD_OID" "$NEW_HEAD" >&2 2>/dev/null \
    || echo "land.sh: (git range-diff failed; compare the commits by hand)" >&2
}

# Push the rebased branch with a lease on the reviewed head, so a push that
# landed after check fails instead of being overwritten. A refused push puts
# the local branch back at HEAD_OID, so check and land can run again from a
# state that agrees with the forge.
land_push() { # land_push <remote> <ssh-pin-or-empty>
  local err detail restored=yes
  err=$(mktemp) || lookup_failed push "mktemp failed"
  if ! git_with_ssh_pin "$2" push --quiet \
      --force-with-lease="refs/heads/$BRANCH:$HEAD_OID" \
      -- "$1" "refs/heads/$BRANCH:refs/heads/$BRANCH" >/dev/null 2>"$err"; then
    detail=$(tr -d '\0' < "$err" | tail -c 300); rm -f "$err"
    land_move_branch "$NEW_HEAD" "$HEAD_OID" || restored=no
    if [ "$restored" = yes ]; then
      stop lease-failed "the lease-protected push of rebased $BRANCH to $1 was refused, and local $BRANCH is back at $HEAD_OID; the remote branch may have moved since check: $detail"
    fi
    stop lease-failed "the lease-protected push of rebased $BRANCH to $1 was refused, and local $BRANCH could not be put back from $NEW_HEAD to $HEAD_OID: $detail"
  fi
  rm -f "$err"
}

# Wait for the forge's PR head to show the pushed commit; it updates
# asynchronously. Any third OID means someone else pushed.
land_await_forge_head() {
  local deadline remaining sleep_for fields state oid
  deadline=$(( SECONDS + CI_CAP_MINUTES * 60 ))
  while :; do
    fields=$(gh_read pr view "$PR" --repo="$REPO" --json state,headRefOid \
      --jq '[.state,.headRefOid] | @tsv') \
      || lookup_failed pr-view "could not reread PR $PR after the push"
    IFS=$'\t' read -r state oid <<< "$fields"
    [ "$state" = OPEN ] || stop pr-not-open "PR $PR is $state after land pushed $NEW_HEAD"
    [ "$oid" != "$NEW_HEAD" ] || return 0
    [ "$oid" = "$HEAD_OID" ] \
      || stop oid-mismatch "after land pushed $NEW_HEAD the forge reports head $oid; something else pushed to $BRANCH"
    remaining=$(( deadline - SECONDS ))
    [ "$remaining" -gt 0 ] \
      || lookup_failed pr-head "the forge still reports head $HEAD_OID after land pushed $NEW_HEAD; rerun check and land once it catches up"
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

# Read every check once and report what land would do, changing nothing
# beyond the base fetch. The STOP or OK line is what a real run would hit
# first; stderr carries all three results either way.
land_dry_run() { # land_dry_run <on-tip>
  local on_tip="$1" tip_msg ci_msg base_msg summary
  ci_read "$HEAD_OID"
  forge_base_tip
  if [ "$on_tip" = true ]; then
    tip_msg="head $HEAD_OID contains the fetched $BASE tip $LAND_TIP"
  elif [ "$IS_FORK" = true ]; then
    tip_msg="head $HEAD_OID is not on the fetched $BASE tip $LAND_TIP, and a cross-repository head must be rebased by its author"
  else
    tip_msg="head $HEAD_OID is not on the fetched $BASE tip $LAND_TIP; land would rebase it, push it with a lease on $HEAD_OID, and stop for the new head's range-diff"
  fi
  ci_msg="CI on $HEAD_OID is $CI_STATE ($CI_DETAIL)"
  if [ "$FORGE_BASE_TIP" = "$LAND_TIP" ]; then
    base_msg="the forge's $BASE tip is still the fetched $LAND_TIP"
  else
    base_msg="the forge's $BASE tip $FORGE_BASE_TIP differs from the fetched $LAND_TIP"
  fi
  printf 'land.sh: land dry run, PR %s:\n  tip:    %s\n  checks: %s\n  base:   %s\n' \
    "$PR" "$tip_msg" "$ci_msg" "$base_msg" >&2
  summary="dry run, nothing changed. tip: $tip_msg. checks: $ci_msg. base: $base_msg"
  [ "$on_tip" = true ] || stop not-on-tip "$summary"
  case "$CI_STATE" in
    failed) stop checks-failed "$summary" ;;
    pending) stop checks-pending "$summary; a real run waits up to $CI_CAP_MINUTES minute(s)" ;;
    missing) stop checks-missing "$summary; a real run waits up to $CI_CAP_MINUTES minute(s)" ;;
  esac
  [ "$FORGE_BASE_TIP" = "$LAND_TIP" ] || stop base-moved "$summary"
  echo "OK land {\"dry_run\":true,\"head_oid\":\"$HEAD_OID\",\"base_tip\":\"$LAND_TIP\",\"checks\":\"$CI_STATE\",\"would\":\"merge\"}"
  exit 0
}

# --- phases -----------------------------------------------------------------

phase_check() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  collision_check
  workspace_preflight
  layout_check
  consumer_checks
  fork_auto_delete_check
  queue_check
  # The verified head is the tip this session pushed: the local branch is
  # primary because a forge-reported head can move with a third party's
  # push, while nothing moves the local ref but this checkout. The forge
  # value is the cross-check; disagreement means the branch moved after
  # the review evidence was collected.
  local local_tip
  git show-ref --verify --quiet "refs/heads/$BRANCH" \
    || stop no-local-branch "no local $BRANCH in this repository: the verified head must be the tip this session pushed, so run the phases from the clone that pushed it (any of its worktrees sees the ref)"
  local_tip=$(git rev-parse "refs/heads/$BRANCH")
  [ "$local_tip" = "$FORGE_HEAD_OID" ] \
    || stop oid-mismatch "local $BRANCH is $local_tip but the forge reports $FORGE_HEAD_OID; the branch moved"
  echo "OK check {\"head_oid\":\"$FORGE_HEAD_OID\",\"head_branch\":\"$(json_escape "$BRANCH")\",\"base_branch\":\"$(json_escape "$BASE")\",\"fork\":$IS_FORK,\"queue\":\"$QUEUE\",\"stacked_prs\":$STACKED_PRS}"
}

phase_land() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  [ "$FORGE_HEAD_OID" = "$HEAD_OID" ] \
    || stop oid-mismatch "the forge reports head $FORGE_HEAD_OID but --head pinned $HEAD_OID; something was pushed since check"
  load_repo_facts
  layout_check
  # The local branch is what a rebase rewrites, so it must be the reviewed
  # head too, as check required.
  local local_tip rc=0 on_tip fields head_remote head_pin="" hr_furl
  git show-ref --verify --quiet "refs/heads/$BRANCH" \
    || stop no-local-branch "no local $BRANCH in this repository: run land from the clone that pushed it"
  local_tip=$(git rev-parse "refs/heads/$BRANCH")
  [ "$local_tip" = "$HEAD_OID" ] \
    || stop oid-mismatch "local $BRANCH is $local_tip, not the reviewed head $HEAD_OID"
  # merge repeats these at the end; asking first keeps a rebase push from
  # rewriting a branch that another PR heads or a cross-repository PR stacks
  # on. Same-repository children are only reported: the rebase leaves them on
  # the parent's pre-rebase commits, which their own land rebase drops.
  consumer_checks
  queue_check

  if [ -n "$BASE_REMOTE_OPT" ]; then
    BASE_REMOTE="$BASE_REMOTE_OPT"
  else
    resolve_remote "$REPO"
    [ -n "$RESOLVED_REMOTE" ] \
      || stop remote-unresolved "no configured remote's URL matches $REPO; pass --base-remote"
    BASE_REMOTE="$RESOLVED_REMOTE"
  fi
  remote_repo_check "$BASE_REMOTE" base
  # The + lets a base force-pushed to a non-descendant still update the
  # tracking ref, so the checks below judge the base as it is now.
  git fetch -- "$BASE_REMOTE" "+refs/heads/$BASE:refs/remotes/$BASE_REMOTE/$BASE" >/dev/null 2>&1 \
    || lookup_failed base-fetch "could not fetch $BASE from $BASE_REMOTE"
  LAND_TIP=$(git rev-parse --verify --quiet "refs/remotes/$BASE_REMOTE/$BASE^{commit}") \
    || lookup_failed base-fetch "the fetched $BASE did not resolve to a commit"
  git merge-base --is-ancestor "$LAND_TIP" "$HEAD_OID" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) on_tip=true ;;
    1) on_tip=false ;;
    *) lookup_failed ancestry "could not compare $HEAD_OID with $BASE tip $LAND_TIP (git merge-base exit $rc)" ;;
  esac

  [ "$DRY_RUN" = false ] || land_dry_run "$on_tip"

  if [ "$on_tip" = false ]; then
    [ "$IS_FORK" != true ] \
      || stop not-on-tip "head $HEAD_OID is not on $BASE tip $LAND_TIP, and land does not push to another repository's branch; its author must rebase and push, then run check and land again"
    # A base remote that lags the forge would cost a rebase, a push, and a
    # CI wait before the final check caught it.
    forge_base_tip
    [ "$FORGE_BASE_TIP" = "$LAND_TIP" ] \
      || stop base-moved "the forge reports $BASE at $FORGE_BASE_TIP but $BASE_REMOTE fetched $LAND_TIP; nothing was rebased, so rerun land"
    # Validate the push destination before rewriting anything, so a remote
    # that fails here leaves the branch untouched.
    head_remote="${HEAD_REMOTE_OPT:-$BASE_REMOTE}"
    remote_repo_check "$head_remote" head
    head_pin="$PINNED_SSH_COMMAND"
    out_exact hr_furl git remote get-url -- "$head_remote" \
      || lookup_failed head-remote "could not read $head_remote's URL"
    push_ids_match "$head_remote" "$(url_id "$hr_furl")" \
      || stop pushurl-mismatch "$head_remote must have exactly one effective push destination matching its fetch URL; git broadcasts to every configured push URL"
    land_rebase
    land_push "$head_remote" "$head_pin"
    land_await_forge_head
    # CI reruns on the rebased commit, but nothing reviews its diff, so the
    # agent reads the range-diff printed above before landing it.
    echo "STOP rebased {\"head_oid\":\"$NEW_HEAD\",\"old_head_oid\":\"$HEAD_OID\",\"base_tip\":\"$LAND_TIP\",\"detail\":\"$(json_escape "rebased $BRANCH onto $BASE tip $LAND_TIP and pushed $NEW_HEAD; read the range-diff on stderr, then run check and land --head $NEW_HEAD")\"}"
    exit 2
  fi

  ci_wait "$HEAD_OID"

  # The CI wait can be long; merge's own guards need the PR as it is now.
  local base_now
  fields=$(gh_read pr view "$PR" --repo="$REPO" --json state,headRefOid,baseRefName \
    --jq '[.state,.headRefOid,.baseRefName] | @tsv') \
    || lookup_failed pr-view "could not reread PR $PR before the merge"
  IFS=$'\t' read -r PR_STATE FORGE_HEAD_OID base_now <<< "$fields"
  [ "$base_now" = "$BASE" ] \
    || stop base-moved "PR $PR now targets $base_now, not $BASE, which land checked the head against; run check and land again"
  phase_merge
}

phase_merge() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  [ "$FORGE_HEAD_OID" = "$HEAD_OID" ] \
    || stop oid-mismatch "the forge reports head $FORGE_HEAD_OID but --head pinned $HEAD_OID; something was pushed since check"
  # Read the title before the last-moment destructive guards. No forge API
  # call sits between their final repository-settings refresh and merge.
  local title
  title=$(gh_read pr view "$PR" --repo="$REPO" --json title --jq .title) \
    || lookup_failed title "could not read the PR title"
  { [ -n "$title" ] && [ "$title" != null ]; } \
    || lookup_failed title "the PR title read back empty"
  # check's answers go stale in the gap where the caller verifies its own
  # guardrails: a retarget (a stacked PR's base merging) can change the
  # base branch and with it which merge queue applies, and a new PR can
  # start sharing the head branch, which the merge itself then auto-deletes.
  # Both are re-asked at the last moment before anything irreversible.
  queue_check
  consumer_checks
  # land's last refusal: the base tip it fetched and waited on must
  # still be the forge's tip. Only the auto-delete refresh, which keeps its
  # own zero-read window, sits between this read and the merge. The read and
  # the merge are still not atomic; the landing design accepts that while
  # one person starts every merge.
  if [ -n "$LAND_TIP" ]; then
    forge_base_tip
    [ "$FORGE_BASE_TIP" = "$LAND_TIP" ] \
      || stop base-moved "$BASE moved from $LAND_TIP to $FORGE_BASE_TIP after land fetched it; $HEAD_OID was not checked against the new tip, so run check and land again"
  fi
  # consumer_checks loads repository facts for its lineage queries. Reload
  # them at the final boundary so an auto-delete setting changed while the
  # other guards ran cannot pass from the stale cache.
  REPO_FACTS_LOADED=""
  fork_auto_delete_check
  queue_message_check
  local err
  err=$(mktemp) || lookup_failed merge "mktemp failed"
  if ! gh pr merge "$PR" --repo="$REPO" --merge \
      --match-head-commit="$HEAD_OID" \
      --subject="$title (#$PR)" --body="" 2>"$err"; then
    local detail; detail=$(tr -d '\0' < "$err" | tail -c 300); rm -f "$err"
    stop merge-refused "gh pr merge failed: $detail"
  fi
  rm -f "$err"
  # Zero exit proves enqueueing, not merging: on a queued base the command
  # returns once the PR is in the queue. Only the forge saying MERGED with
  # a non-null mergedAt is completion; deleting anything before that can
  # cancel the merge and take the branch's last copies with it.
  local deadline state merged_at remaining sleep_for
  deadline=$(( SECONDS + CAP_MINUTES * 60 ))
  while :; do
    if pr_fields=$(gh_read pr view "$PR" --repo="$REPO" --json state,mergedAt \
        --jq '[.state,(.mergedAt // "null")] | @tsv'); then
      IFS=$'\t' read -r state merged_at <<< "$pr_fields"
      if [ "$state" = MERGED ] && [ "$merged_at" != null ]; then
        if [ "$PHASE" = land ]; then
          echo "OK land {\"head_oid\":\"$HEAD_OID\",\"merged_at\":\"$(json_escape "$merged_at")\"}"
        else
          echo "OK merge {\"merged_at\":\"$(json_escape "$merged_at")\"}"
        fi
        return 0
      fi
      [ "$state" = OPEN ] || [ "$state" = MERGED ] \
        || stop pr-closed "PR $PR is $state after the merge command; nothing merged"
    else
      echo "land.sh: merge-state poll failed; retrying" >&2
    fi
    remaining=$(( deadline - SECONDS ))
    [ "$remaining" -gt 0 ] \
      || lookup_failed merge-pending "the forge has not reported PR $PR merged within $CAP_MINUTES minute(s); do not clean up until it does"
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

case "$PHASE" in
  check) phase_check ;;
  land) phase_land ;;
  merge) phase_merge ;;
esac
