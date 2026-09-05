#!/usr/bin/env bash
# self-merge.sh: the executable form of the self-merge skill's guarded
# merge-and-cleanup sequence. The skill's prose owns the judgment (when
# self-merge applies, the pre-merge guardrails, what to do when a guard
# fires); this script owns the mechanics, so no agent re-derives quoting,
# encoding, or parsing rules at runtime. Every forge- or git-sourced value
# stays in a shell variable and reaches commands through argv, behind an
# option terminator wherever the command takes a positional name; nothing
# here re-parses a value through a shell.
#
# Usage:
#   self-merge.sh check   --pr N --repo owner/name
#   self-merge.sh merge   --pr N --repo owner/name --head <40-hex-oid>
#   self-merge.sh cleanup --pr N --repo owner/name --head <40-hex-oid>
#     [--base-remote NAME]   # override remote resolution for the base repo
#     [--head-remote NAME]   # override remote resolution for the head repo
#     [--interval 10]        # merge phase: seconds between MERGED polls
#     [--cap-minutes 15]     # merge phase: total wait for MERGED
#
# Run each phase from the checkout the cleanup will rewrite (the one that
# holds, or will hold, the base branch). --repo is required, never
# defaulted: a bare PR number resolves against the CLI's default
# repository, which in a fork clone can act on a different PR entirely.
#
# check    Pre-merge guards: PR open, no head/base name collision, clean
#          workspace, no git operation in progress, no competing worktree
#          layout, no open PR sharing or stacked on the head branch, and a
#          merge queue's method identified as merge-commit before anything
#          is enqueued. Prints the verified head OID the later phases pin.
# merge    Merges pinned to --head with an explicit title-only message,
#          then polls until the forge reports the PR MERGED (a zero exit
#          from the merge command proves enqueueing, not merging).
# cleanup  Post-merge: land on and resync the base branch, then a
#          lease-protected remote branch delete behind re-checked remote and
#          consumer guards,
#          stop before mutating branches when a separate linked head worktree
#          remains, keep the local branch for a separate deliberate delete,
#          prune.
#
# Last line on stdout is the machine-readable result:
#   OK <phase> <json>            phase completed; json carries the facts
#   STOP <guard> <json>          a guard fired: surface it, never work
#                                around it; the guard names are stable
#   LOOKUP_FAILED <what> <json>  a read failed; unknown is not absence, so
#                                nothing was decided from the empty result
# Exit codes: 0 OK; 2 STOP; 4 LOOKUP_FAILED; 64 usage error; 69 gh
# (GitHub CLI) not found on PATH.
set -u

PHASE="" PR="" REPO="" HEAD_OID="" BASE_REMOTE_OPT="" HEAD_REMOTE_OPT=""
INTERVAL=10 CAP_MINUTES=15

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

case "${1:-}" in
  check|merge|cleanup) PHASE="$1"; shift ;;
  *) echo "self-merge.sh: first argument must be check, merge, or cleanup" >&2; usage ;;
esac

# Recognize the option, then require its value, before reading $2: a
# trailing bare option must die as a usage error, not a set -u crash.
while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --pr|--repo|--head|--base-remote|--head-remote|--interval|--cap-minutes) ;;
    *) echo "self-merge.sh: unknown option: $opt" >&2; usage ;;
  esac
  [ $# -ge 2 ] || { echo "self-merge.sh: $opt requires a value" >&2; usage; }
  val="$2"; shift 2
  case "$opt" in
    --pr) PR="$val" ;;
    --repo) REPO="$val" ;;
    --head) HEAD_OID="$val" ;;
    --base-remote) BASE_REMOTE_OPT="$val" ;;
    --head-remote) HEAD_REMOTE_OPT="$val" ;;
    --interval) INTERVAL="$val" ;;
    --cap-minutes) CAP_MINUTES="$val" ;;
  esac
done

[ -n "$PR" ] && [ -n "$REPO" ] || usage
case "$PR" in ''|*[!0-9]*|0*)
  echo "self-merge.sh: --pr must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$REPO" in
  */*/*|*[!A-Za-z0-9._/-]*) echo "self-merge.sh: --repo must be owner/name" >&2; usage ;;
  ?*/?*) ;;
  *) echo "self-merge.sh: --repo must be owner/name" >&2; usage ;;
esac
if [ "$PHASE" != check ]; then
  HEAD_OID=$(printf '%s' "$HEAD_OID" | tr 'A-F' 'a-f')
  case "$HEAD_OID" in *[!0-9a-f]*|'')
    echo "self-merge.sh: --head must be the full 40-hex verified head OID" >&2; usage ;;
  esac
  [ "${#HEAD_OID}" -eq 40 ] || {
    echo "self-merge.sh: --head must be the full 40-hex verified head OID" >&2; usage
  }
fi
case "$INTERVAL" in ''|0|0*|*[!0-9]*)
  echo "self-merge.sh: --interval must be a positive integer without leading zeros (seconds)" >&2; usage ;;
esac
case "$CAP_MINUTES" in ''|0?*|*[!0-9]*)
  echo "self-merge.sh: --cap-minutes must be a non-negative integer without leading zeros" >&2; usage ;;
esac
# Keep later arithmetic inside a signed 32-bit range on every supported Bash.
# These limits are far beyond a useful interactive wait while rejecting values
# that could wrap only after the irreversible merge command has run.
[ "${#INTERVAL}" -le 9 ] || {
  echo "self-merge.sh: --interval must be at most 999999999 seconds" >&2; usage
}
[ "${#CAP_MINUTES}" -le 7 ] || {
  echo "self-merge.sh: --cap-minutes must be at most 9999999" >&2; usage
}
# Remote-name overrides: a leading hyphen would read as an option to git
# even behind our own parsing, and every use below passes them as
# positionals, so refuse the shape outright rather than trusting quoting.
for rn in "$BASE_REMOTE_OPT" "$HEAD_REMOTE_OPT"; do
  case "$rn" in -*)
    echo "self-merge.sh: remote names must not begin with a hyphen" >&2; usage ;;
  esac
done

command -v gh >/dev/null 2>&1 || {
  echo "self-merge.sh: gh (GitHub CLI) not found on PATH; stop and hand off unless another authenticated PR-host CLI can perform every required forge check" >&2
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
  echo "LOOKUP_FAILED $1 {\"detail\":\"$(json_escape "$2")\"}"
  exit 4
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
pr_fields=$(gh pr view "$PR" --repo="$REPO" \
  --json state,headRefName,baseRefName,headRefOid,isCrossRepository,headRepositoryOwner,headRepository,url \
  --jq '[.state,.headRefName,.baseRefName,.headRefOid,(.isCrossRepository|tostring),(.headRepositoryOwner.login // "~"),(.headRepository.name // "~"),.url] | @tsv' \
  2>/dev/null) || lookup_failed pr-view "could not read PR $PR from $REPO"
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
  facts=$(gh api "repos/$REPO" \
    --jq '[.default_branch, (.fork|tostring), (.forks_count|tostring), (.delete_branch_on_merge|tostring), (.parent.full_name // "~"), (.source.full_name // "~"), (.clone_url // "~"), (.ssh_url // "~"), (.merge_commit_title // "~"), (.merge_commit_message // "~")] | @tsv' \
    2>/dev/null) \
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

# Test raw ref presence without a version-new `show-ref --exists` dependency.
# Ask symbolic-ref first, which sees even a dangling symref; then verify an
# ordinary direct ref. Return 0 for present and 1 for absent; every other Git
# result is an unknown state and stops the caller.
ref_exists() { # ref_exists <full-ref>
  local rc=0
  git symbolic-ref -q "$1" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) ;;
    *) lookup_failed local-ref "could not determine whether $1 is symbolic (git symbolic-ref exit $rc)" ;;
  esac
  rc=0
  git show-ref --verify --quiet "$1" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) ;;
    *) lookup_failed local-ref "could not determine whether $1 exists (git show-ref exit $rc)" ;;
  esac
  # A direct ref can become a dangling symref between the two reads above.
  # Repeat the symbolic probe before linearizing the result as absent.
  rc=0
  git symbolic-ref -q "$1" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) lookup_failed local-ref "could not recheck whether $1 is symbolic (git symbolic-ref exit $rc)" ;;
  esac
}

# Workspace preflight, in the checkout this script runs from, which is the
# working tree the cleanup rewrites. A clean tree elsewhere says nothing.
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
# per-worktree, so the cleanup checkout's probes say nothing about the
# worktree being removed. Probe the per-worktree paths, never the names as
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

# Diagnose state that makes even manual worktree removal unsafe. Automated
# cleanup stops afterward even when this inventory is clean.
worktree_preservation_preflight() { # worktree_preservation_preflight <dir>
  local d="$1" inv flagged
  if op_probe "$d"; then
    stop worktree-op-in-progress "$OP_FOUND exists in the linked head worktree at $d"
  fi
  inv=$(git -C "$d" status -uall --porcelain --ignored 2>/dev/null) \
    || lookup_failed worktree-inventory "could not inventory $d"
  [ -z "$inv" ] \
    || stop worktree-dirty "the worktree at $d holds untracked or ignored files; preserve it and report this stop; removal authority alone does not authorize moving, changing, or deleting its contents to clear the stop"
  # A flagged row is hidden state unless something explains its absence.
  # Sparse checkout marks every excluded path skip-worktree (`S`) and leaves
  # it absent, which is the one benign absence: an absent assume-unchanged
  # row is an uncommitted deletion, and status reports neither. So exempt an
  # absent row only when it is `S` and this worktree has sparse checkout on
  # (the setting is per-worktree, so it is read from there). Read
  # NUL-terminated (`-vz`) rather than line-wise, and stream through a temp
  # file, because a path can hold a newline and command substitution drops
  # NUL bytes outright; `--full-name` keeps each path relative to the
  # worktree root that `$d/` then anchors. The read's own failure must not
  # count as "no flagged files": a pipeline into grep -c reports grep's
  # status, and zero matches and a failed git read print the same 0.
  # --bool because git accepts every boolean spelling (`yes`, `on`, `1`) while
  # --get returns the raw string, so a raw comparison reports an ordinary
  # sparse worktree as hidden work. A failed read is not sparse, which exempts
  # nothing.
  local tmp rec tag sparse=false sparse_cfg
  flagged=0
  out_exact sparse_cfg git -C "$d" config --bool --get core.sparseCheckout || sparse_cfg=false
  [ "$sparse_cfg" != true ] || sparse=true
  tmp=$(mktemp) || lookup_failed worktree-inventory "mktemp failed"
  git -C "$d" ls-files -vz --full-name > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; lookup_failed worktree-inventory "could not read the index of $d"; }
  while IFS= read -r -d '' rec; do
    case "$rec" in
      [a-z]\ *|S\ *) ;;
      *) continue ;;
    esac
    tag="${rec%% *}"
    rec="${rec#? }"
    if ! [ -e "$d/$rec" ] && ! [ -L "$d/$rec" ] \
      && [ "$tag" = S ] && [ "$sparse" = true ]; then
      continue
    fi
    flagged=$((flagged + 1))
  done < "$tmp"
  rm -f "$tmp"
  [ "$flagged" -eq 0 ] \
    || stop worktree-flagged "$flagged tracked file(s) in $d carry assume-unchanged or skip-worktree; their edits and deletions are invisible to status"
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
    || stop duplicate-worktree "$count worktrees check out $want; cleanup cannot choose one without leaving or moving another"
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
  # Reject ambiguity at the layout boundary. Cleanup repeats this scan after
  # validating the local head ref and immediately before remote resolution,
  # retrieving the path afresh and closing layout changes during those local
  # checks.
  worktree_scan "refs/heads/$BRANCH"
}

# Consumer guards, both directions. An error is unknown and unknown keeps
# the branch: a failed listing returns no rows, which would otherwise read
# as "nothing depends on this branch" moments before a delete.
consumer_checks() {
  load_repo_facts
  local shared stacked target seen="" n
  if [ "$IS_FORK" = true ]; then
    shared=$(gh api "repos/$REPO/pulls?state=open&head=$HEAD_OWNER:$ENC_BRANCH" \
      --jq "[.[] | select(.number != $PR) | .number] | length" 2>/dev/null) \
      || lookup_failed shared-head "could not list open PRs sharing head $HEAD_OWNER:$BRANCH"
  else
    shared=$(gh pr list --repo="$REPO" --head="$BRANCH" --state=open --json=number \
      --jq "[.[] | select(.number != $PR) | .number] | length" 2>/dev/null) \
      || lookup_failed shared-head "could not list open PRs sharing head $BRANCH"
  fi
  case "$shared" in ''|*[!0-9]*) lookup_failed shared-head "unparseable shared-head listing" ;; esac
  [ "$shared" -eq 0 ] || stop shared-head "$shared other open PR(s) use $BRANCH as their head; deleting or auto-deleting it closes them"
  stacked=$(gh pr list --repo="$HEAD_REPO" --base="$BRANCH" --state=open --json=number \
    --jq length 2>/dev/null) \
    || lookup_failed stacked-prs "could not list open PRs based on $BRANCH"
  case "$stacked" in ''|*[!0-9]*) lookup_failed stacked-prs "unparseable stacked-PR listing" ;; esac
  [ "$stacked" -eq 0 ] || stop stacked-prs "$stacked open PR(s) are based on $BRANCH; confirm their retarget before it is deleted"
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
      n=$(gh api "repos/$target/pulls?state=open&head=${REPO%%/*}:$ENC_BRANCH" --jq length 2>/dev/null) \
        || lookup_failed shared-head "could not list open PRs in $target sharing head $BRANCH"
      case "$n" in ''|*[!0-9]*) lookup_failed shared-head "unparseable listing from $target" ;; esac
      [ "$n" -eq 0 ] || stop shared-head "$n open PR(s) in $target use $BRANCH as their head; deleting or auto-deleting it closes them"
    done
  fi
}

# A same-repository head on a base repository that is itself a fork can
# also head PRs to sibling forks, which no repository-scoped query can
# enumerate. If this repository auto-deletes heads on merge, cleanup's
# kept_fork_network path runs too late: the forge already removed the
# branch. Stop before both direct merges and queue enqueueing.
fork_auto_delete_check() {
  load_repo_facts
  if [ "$IS_FORK" != true ] && [ "$DELETE_BRANCH_ON_MERGE" = true ]; then
    if [ "$REPO_IS_FORK" = true ] || [ "$FORKS_COUNT" -gt 0 ]; then
      stop fork-auto-delete "$REPO participates in a fork network and auto-deletes merged head branches; $BRANCH may have unenumerable fork consumers, so merging could delete it before cleanup can keep it"
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
  methods=$(gh api --paginate "repos/$REPO/rules/branches/$ENC_BASE" \
    --jq '.[] | select(.type == "merge_queue") | (.parameters.merge_method // "unidentified")' \
    2>/dev/null) \
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
# cleanup does not gain another executable dependency.
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
  echo "OK check {\"head_oid\":\"$FORGE_HEAD_OID\",\"head_branch\":\"$(json_escape "$BRANCH")\",\"base_branch\":\"$(json_escape "$BASE")\",\"fork\":$IS_FORK,\"queue\":\"$QUEUE\"}"
}

phase_merge() {
  [ "$PR_STATE" = OPEN ] || stop pr-not-open "PR $PR is $PR_STATE, not OPEN"
  [ "$FORGE_HEAD_OID" = "$HEAD_OID" ] \
    || stop oid-mismatch "the forge reports head $FORGE_HEAD_OID but --head pinned $HEAD_OID; something was pushed since check"
  # Read the title before the last-moment destructive guards. No forge API
  # call sits between their final repository-settings refresh and merge.
  local title
  title=$(gh pr view "$PR" --repo="$REPO" --json title --jq .title 2>/dev/null) \
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
    if pr_fields=$(gh pr view "$PR" --repo="$REPO" --json state,mergedAt \
        --jq '[.state,(.mergedAt // "null")] | @tsv' 2>/dev/null); then
      IFS=$'\t' read -r state merged_at <<< "$pr_fields"
      if [ "$state" = MERGED ] && [ "$merged_at" != null ]; then
        echo "OK merge {\"merged_at\":\"$(json_escape "$merged_at")\"}"
        return 0
      fi
      [ "$state" = OPEN ] || [ "$state" = MERGED ] \
        || stop pr-closed "PR $PR is $state after the merge command; nothing merged"
    else
      echo "self-merge.sh: merge-state poll failed; retrying" >&2
    fi
    remaining=$(( deadline - SECONDS ))
    [ "$remaining" -gt 0 ] \
      || lookup_failed merge-pending "the forge has not reported PR $PR merged within $CAP_MINUTES minute(s); do not clean up until it does"
    sleep_for="$INTERVAL"
    [ "$sleep_for" -le "$remaining" ] || sleep_for="$remaining"
    sleep "$sleep_for"
  done
}

phase_cleanup() {
  local merged_at local_tip local_deleted=absent base_symbolic_rc=0
  local removed_worktree=none initial_base_id="" initial_head_id=""
  local remote_deleted=kept_fork repo_fork_network=false
  merged_at=$(gh pr view "$PR" --repo="$REPO" --json state,mergedAt \
    --jq 'if .state == "MERGED" and .mergedAt != null then .mergedAt else "no" end' 2>/dev/null) \
    || lookup_failed pr-view "could not read PR $PR's merge state"
  [ "$merged_at" != no ] || stop pr-not-merged "the forge does not report PR $PR merged; cleanup would tidy around a branch nothing merged"
  collision_check
  workspace_preflight
  layout_check

  git symbolic-ref -q "refs/heads/$BASE" >/dev/null 2>&1 \
    || base_symbolic_rc=$?
  case "$base_symbolic_rc" in
    0) stop local-base "local $BASE is a symbolic ref; preserve it rather than checking out and following its target" ;;
    1) ;;
    *) lookup_failed local-base "could not determine whether local $BASE is symbolic (git symbolic-ref exit $base_symbolic_rc)" ;;
  esac

  # A linked head worktree is a stop before any branch mutation. Git has no
  # portable operation that atomically verifies its HEAD and inventories its
  # files while removing the worktree: a concurrent reset can move a clean
  # detached HEAD after either check, and removal then drops its only ref and
  # reflog. Diagnose hidden state first, but leave even a clean worktree for a
  # separate, explicitly idle cleanup step.
  if ref_exists "refs/heads/$BRANCH"; then
    if git symbolic-ref -q "refs/heads/$BRANCH" >/dev/null 2>&1; then
      stop local-branch "local $BRANCH is a symbolic ref; preserve it rather than following it to another branch"
    fi
    local_tip=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null) \
      || lookup_failed local-branch "could not read local $BRANCH"
    [ "$local_tip" = "$HEAD_OID" ] \
      || stop local-branch "local $BRANCH is $local_tip, not the pinned merged head $HEAD_OID; preserve the repurposed checkout"
  fi
  worktree_scan "refs/heads/$BRANCH"
  if [ -n "$WT_MATCH" ] && ! [ "$WT_MATCH" -ef "$CWD_CDUP" ]; then
    worktree_preservation_preflight "$WT_MATCH"
    stop head-worktree-present "the clean head worktree at $WT_MATCH remains; report it for owner removal or separately authorized cleanup; honor existing task-specific authority, retain preservation and ownership checks, and rerun cleanup only after the stop is cleared"
  fi

  # Base remote first: the resync depends on it whatever happens to the
  # head branch.
  if [ -n "$BASE_REMOTE_OPT" ]; then
    BASE_REMOTE="$BASE_REMOTE_OPT"
  else
    resolve_remote "$REPO"
    [ -n "$RESOLVED_REMOTE" ] \
      || stop remote-unresolved "no configured remote's URL matches $REPO; pass --base-remote"
    BASE_REMOTE="$RESOLVED_REMOTE"
  fi
  remote_repo_check "$BASE_REMOTE" base
  initial_base_id="$CHECKED_REMOTE_ID"

  # An explicit hostless head remote is a trust decision made against the
  # configuration active at invocation. Pin that identity now so the checkout
  # cannot silently redirect the later delete. Hosted remotes are checked
  # against the forge's authoritative endpoints at use time instead.
  if [ "$IS_FORK" != true ] && [ "$REPO_IS_FORK" != true ] \
      && [ "$FORKS_COUNT" -eq 0 ]; then
    if [ -n "$HEAD_REMOTE_OPT" ]; then
      remote_repo_check "$HEAD_REMOTE_OPT" head
      initial_head_id="$CHECKED_REMOTE_ID"
    else
      initial_head_id="$initial_base_id"
    fi
  fi

  # Land on the base branch. The bare-name switch is only taken when the
  # local branch verifiably exists (a rev-parse existence probe is
  # satisfied by a same-named tag, and a bare checkout then detaches HEAD
  # at the tag); otherwise the branch is created from a freshly fetched
  # tracking ref, since the start-point can be absent in a fresh,
  # single-branch, or sparse clone. Both switches refuse to overwrite an
  # ignored file the base tracks; that refusal surfaces as a stop.
  base_created=false
  if git show-ref --verify --quiet "refs/heads/$BASE"; then
    git checkout --no-overwrite-ignore "$BASE" >/dev/null 2>&1 \
      || stop checkout-refused "switching to $BASE was refused (an ignored file the base tracks, or a conflicting state); nothing was overwritten"
  else
    git fetch -- "$BASE_REMOTE" "refs/heads/$BASE:refs/remotes/$BASE_REMOTE/$BASE" >/dev/null 2>&1 \
      || lookup_failed base-fetch "could not fetch $BASE from $BASE_REMOTE"
    git checkout --no-overwrite-ignore --no-track -b "$BASE" "refs/remotes/$BASE_REMOTE/$BASE" >/dev/null 2>&1 \
      || stop checkout-refused "creating local $BASE from $BASE_REMOTE was refused; nothing was overwritten"
    base_created=true
  fi
  [ "$(git symbolic-ref -q HEAD 2>/dev/null)" = "refs/heads/$BASE" ] \
    || stop detached "HEAD is not on $BASE after the switch (a same-named tag or OID shadowed the branch)"

  # Branch-conditioned includes can change every remote URL at checkout. Do
  # not carry the pre-landing remote selection into the resync: resolve and
  # validate it again under the base branch's effective configuration. Hosted
  # URLs must still identify the PR repository. A post-checkout hostless path
  # cannot be matched to the forge, so it must be the exact path explicitly
  # trusted before the checkout.
  if [ -n "$BASE_REMOTE_OPT" ]; then
    BASE_REMOTE="$BASE_REMOTE_OPT"
  else
    resolve_remote "$REPO"
    [ -n "$RESOLVED_REMOTE" ] \
      || stop remote-unresolved "no configured remote's URL matches $REPO after landing on $BASE; pass --base-remote"
    BASE_REMOTE="$RESOLVED_REMOTE"
  fi
  remote_repo_check "$BASE_REMOTE" base
  case "$CHECKED_REMOTE_ID" in path\ *)
    [ "$CHECKED_REMOTE_ID" = "$initial_base_id" ] \
      || stop remote-config-changed "base remote $BASE_REMOTE became a hostless path not trusted before checkout; preserve the remote branch and validate the new path manually" ;;
  esac
  if [ "$base_created" = true ]; then
    git config "branch.$BASE.remote" "$BASE_REMOTE" \
      && git config "branch.$BASE.merge" "refs/heads/$BASE" \
      || stop tracking-config-failed "could not configure local $BASE to track $BASE_REMOTE/$BASE; preserve the remote branch and repair the upstream manually"
  fi

  # Resync before deleting the remote feature branch: fetch, then an explicit
  # fast-forward merge. Not git pull: its
  # merge step updates ignored files by default and rejects
  # --no-overwrite-ignore, and a bare pull follows the configured
  # upstream, which in a fork clone can be the fork's stale copy.
  git fetch -- "$BASE_REMOTE" "refs/heads/$BASE:refs/remotes/$BASE_REMOTE/$BASE" >/dev/null 2>&1 \
    || lookup_failed base-fetch "could not fetch $BASE from $BASE_REMOTE"
  git merge --ff-only --no-overwrite-ignore "refs/remotes/$BASE_REMOTE/$BASE" >/dev/null 2>&1 \
    || stop resync-failed "fast-forwarding $BASE refused (divergence, or an ignored file the fetch started tracking); resolve it rather than forcing"

  # Delete the remote head only after the base resync succeeds. A fork's
  # branch may head PRs anywhere in its fork network, which per-repository
  # queries cannot enumerate, so fork-network branches are kept and reported.
  # Refresh that fact after the resync because a first fork can appear while
  # cleanup is running.
  REPO_FACTS_LOADED=""
  load_repo_facts
  if [ "$REPO_IS_FORK" = true ] || [ "$FORKS_COUNT" -gt 0 ]; then
    repo_fork_network=true
  fi
  if [ "$IS_FORK" != true ] && [ "$repo_fork_network" = true ]; then
    remote_deleted=kept_fork_network
  fi
  if [ "$IS_FORK" != true ] && [ "$repo_fork_network" != true ]; then
    if [ -n "$HEAD_REMOTE_OPT" ]; then
      HEAD_REMOTE="$HEAD_REMOTE_OPT"
    else
      HEAD_REMOTE="$BASE_REMOTE"
    fi
    remote_repo_check "$HEAD_REMOTE" head
    # Capture the alias endpoint pin (empty for a direct remote) now: the head
    # ls-remote and the lease-protected delete both route through it so a
    # Match-exec change after acceptance cannot redirect the destructive push.
    local head_ssh_pin="$PINNED_SSH_COMMAND"
    case "$CHECKED_REMOTE_ID" in path\ *)
      [ "$CHECKED_REMOTE_ID" = "$initial_head_id" ] \
        || stop remote-config-changed "head remote $HEAD_REMOTE became a hostless path not trusted before checkout; preserve the branch and validate the new path manually" ;;
    esac
    # Whatever chose the remote, override included: the repository the
    # existence and OID checks read (the fetch URL) must be the only
    # repository the delete writes. git push sends to every configured
    # push URL, so all of them are held to the fetch URL's identity; a
    # split would validate one repository and delete from another.
    local hr_furl
    out_exact hr_furl git remote get-url -- "$HEAD_REMOTE" \
      || lookup_failed head-remote "could not read $HEAD_REMOTE's URL"
    push_ids_match "$HEAD_REMOTE" "$(url_id "$hr_furl")" \
      || stop pushurl-mismatch "$HEAD_REMOTE must have exactly one effective push destination matching its fetch URL; git broadcasts to every configured push URL"
    local ls_out ls_rc remote_oid="" line_oid line_ref exact=0 decoys=0
    ls_out=$(git_with_ssh_pin "$head_ssh_pin" ls-remote --exit-code --heads \
      -- "$HEAD_REMOTE" "refs/heads/$BRANCH" 2>/dev/null)
    ls_rc=$?
    if [ "$ls_rc" -eq 2 ]; then
      remote_deleted=already # a genuine absence: --exit-code separates it
    elif [ "$ls_rc" -ne 0 ]; then
      # from a transport or auth failure, which must not read as deletion
      lookup_failed ls-remote "could not reach $HEAD_REMOTE to check refs/heads/$BRANCH (exit $ls_rc)"
    else
      # The pattern match is not exact: a remote branch literally named
      # refs/heads/<branch> matches the qualified pattern too, so accept
      # only a full-string ref-column match.
      while IFS=$'\t' read -r line_oid line_ref; do
        if [ "$line_ref" = "refs/heads/$BRANCH" ]; then
          exact=$((exact + 1)); remote_oid="$line_oid"
        elif [ -n "$line_ref" ]; then
          decoys=$((decoys + 1))
        fi
      done <<< "$ls_out"
      if [ "$exact" -eq 0 ]; then
        remote_deleted=already
      elif [ "$exact" -gt 1 ]; then
        lookup_failed ls-remote "ambiguous listing for refs/heads/$BRANCH"
      else
        # A sibling ref that suffix-matches (refs/heads/refs/heads/<branch>)
        # makes the delete refspec itself ambiguous: git suffix-matches push
        # destinations, so both --delete and the :ref form refuse with "dst
        # refspec matches more than one" (verified on git 2.50). No push
        # refspec can express the delete atomically then, and a forge-API
        # delete re-runs no lease check, so this is a stop, not a workaround.
        [ "$decoys" -eq 0 ] \
          || stop ambiguous-ref "a ref suffix-matching refs/heads/$BRANCH exists on $HEAD_REMOTE; git cannot express this delete unambiguously, delete it manually"
        [ "$remote_oid" = "$HEAD_OID" ] \
          || stop oid-mismatch "remote $BRANCH is $remote_oid but the merged head was $HEAD_OID; the branch moved or was reused after the merge"
        [ "$FORGE_HEAD_OID" = "$HEAD_OID" ] \
          || stop oid-mismatch "the forge reports head $FORGE_HEAD_OID but the merged head was $HEAD_OID"
        # Fork-network membership and consumers are re-checked at the last
        # moment the branch exists: either answer can go stale after the
        # resync and remote-identity checks.
        REPO_FACTS_LOADED=""
        load_repo_facts
        if [ "$REPO_IS_FORK" = true ] || [ "$FORKS_COUNT" -gt 0 ]; then
          remote_deleted=kept_fork_network
        else
          consumer_checks
          # The lease makes the OID guard atomic: a push landing between
          # the check above and this delete fails the delete instead of
          # losing the new work. A plain --delete or a forge-API delete
          # re-opens that race.
          git_with_ssh_pin "$head_ssh_pin" push --delete \
            --force-with-lease="refs/heads/$BRANCH:$HEAD_OID" \
            -- "$HEAD_REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1 \
            || stop lease-failed "the lease-protected delete of $BRANCH on $HEAD_REMOTE was refused; the ref may have just moved"
          remote_deleted=deleted
        fi
      fi
    fi
  fi

  # Keep the local branch. Git exposes no portable deletion that combines an
  # expected-old OID with the checked-out-worktree guard: update-ref supplies
  # the former but can dangle a worktree, while branch -d supplies the latter
  # but can delete a backward-repointed ref between verification and deletion.
  # The report makes the remaining deliberate step explicit.
  if ref_exists "refs/heads/$BRANCH"; then
    local_deleted=kept_manual
  else
    local_deleted=absent
  fi

  # Prune with the remote named: a bare --prune prunes only the default
  # remote. HEAD_REMOTE is only bound on the delete path. A failure leaves
  # cleanup incomplete, so it cannot be discarded before an OK report.
  if [ -n "${HEAD_REMOTE:-}" ]; then
    git fetch --prune -- "$HEAD_REMOTE" >/dev/null 2>&1 \
      || lookup_failed prune "cleanup completed its branch operations but could not prune $HEAD_REMOTE"
    if [ "$HEAD_REMOTE" != "$BASE_REMOTE" ]; then
      git fetch --prune -- "$BASE_REMOTE" >/dev/null 2>&1 \
        || lookup_failed prune "cleanup completed its branch operations but could not prune $BASE_REMOTE"
    fi
  else
    git fetch --prune -- "$BASE_REMOTE" >/dev/null 2>&1 \
      || lookup_failed prune "cleanup completed its branch operations but could not prune $BASE_REMOTE"
  fi

  echo "OK cleanup {\"remote_branch\":\"$remote_deleted\",\"local_branch\":\"$local_deleted\",\"worktree_removed\":\"$(json_escape "$removed_worktree")\",\"resynced\":\"$(json_escape "$BASE")\"}"
}

case "$PHASE" in
  check) phase_check ;;
  merge) phase_merge ;;
  cleanup) phase_cleanup ;;
esac
