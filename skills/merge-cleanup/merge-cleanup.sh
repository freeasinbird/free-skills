#!/usr/bin/env bash
# merge-cleanup.sh: execute the mechanical post-merge cleanup sequence once,
# with every repository, PR, and checkout pinned by the caller. The skill owns
# judgment and project-specific reconciliation; this script owns the guarded
# git and forge mechanics and always returns a compact disposition ledger.
#
# Usage:
#   merge-cleanup.sh --repo host/owner/name --pr N --checkout PATH
#     [--base-remote NAME]   # explicit base-repository remote
#     [--head-remote NAME]   # explicit head-repository remote
#   merge-cleanup.sh --help
#
# The checkout must be the worktree the cleanup may rewrite. The script lands
# on and fully resyncs the PR base before it reads or deletes the remote head.
# It stops before mutation when a linked worktree still checks out the head
# branch, requiring its owner to remove that worktree first. It never closes
# issues or interprets project post-merge policy.
#
# Last line on stdout is the machine-readable result. Every result payload has
# the same fields, including dispositions for steps that did not start:
#   OK cleanup <json>            cleanup completed
#   STOP <guard> <json>          a safety guard refused the next step
#   LOOKUP_FAILED <what> <json>  required evidence could not be read
# Exit codes: 0 OK; 2 STOP; 4 LOOKUP_FAILED; 64 usage; 69 missing runtime.
set -u
# A caller may invoke `bash -x`; disable inherited tracing before any remote
# URL is read so credentials rejected below cannot leak through trace output.
set +x

PR="" REPO_SPEC="" REPO="" FORGE_HOST="" CHECKOUT_INPUT=""
BASE_REMOTE_OPT="" HEAD_REMOTE_OPT=""
HEAD_OID="" BRANCH="" BASE="" HEAD_REPO="" PR_URL="" CLOSING_REFS_JSON='[]'
MERGE_DISPOSITION=not_checked WORKTREE_DISPOSITION=not_checked
REMOTE_DISPOSITION=not_started BASE_DISPOSITION=not_started
LOCAL_DISPOSITION=not_started PRUNE_DISPOSITION=not_started
CONSUMER_DISPOSITION=not_checked RETARGETED_COUNT=0
INCOMPLETE_STEP=preflight
PIN_SERIAL=0

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

case "${1:-}" in
  --help|-h) [ $# -eq 1 ] || usage; sed -n '2,/^set -u$/p' "$0" | sed '$d'; exit 0 ;;
esac

# Recognize the option, then require its value, before reading $2: a
# trailing bare option must die as a usage error, not a set -u crash.
while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --pr|--repo|--checkout|--base-remote|--head-remote) ;;
    *) echo "merge-cleanup.sh: unknown option: $opt" >&2; usage ;;
  esac
  [ $# -ge 2 ] || { echo "merge-cleanup.sh: $opt requires a value" >&2; usage; }
  val="$2"; shift 2
  case "$opt" in
    --pr) PR="$val" ;;
    --repo) REPO_SPEC="$val" ;;
    --checkout) CHECKOUT_INPUT="$val" ;;
    --base-remote) BASE_REMOTE_OPT="$val" ;;
    --head-remote) HEAD_REMOTE_OPT="$val" ;;
  esac
done

[ -n "$PR" ] && [ -n "$REPO_SPEC" ] && [ -n "$CHECKOUT_INPUT" ] || usage
case "$PR" in ''|*[!0-9]*|0*)
  echo "merge-cleanup.sh: --pr must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$REPO_SPEC" in
  */*/*/*|*[!A-Za-z0-9._/-]*)
    echo "merge-cleanup.sh: --repo must be host/owner/name" >&2; usage ;;
  ?*/?*/?*) ;;
  *) echo "merge-cleanup.sh: --repo must be host/owner/name" >&2; usage ;;
esac
FORGE_HOST="${REPO_SPEC%%/*}"
REPO="${REPO_SPEC#*/}"
case "$FORGE_HOST" in
  ''|*[!A-Za-z0-9.-]*|.*|-*|*..*|*.-*|*-.|*.)
    echo "merge-cleanup.sh: --repo has an invalid host" >&2; usage ;;
esac
# Remote-name overrides: a leading hyphen would read as an option to git
# even behind our own parsing, and every use below passes them as
# positionals, so refuse the shape outright rather than trusting quoting.
for rn in "$BASE_REMOTE_OPT" "$HEAD_REMOTE_OPT"; do
  case "$rn" in -*)
    echo "merge-cleanup.sh: remote names must not begin with a hyphen" >&2; usage ;;
  esac
done

command -v git >/dev/null 2>&1 || {
  echo "merge-cleanup.sh: git not found on PATH" >&2
  exit 69
}
command -v gh >/dev/null 2>&1 || {
  echo "merge-cleanup.sh: gh (GitHub CLI) not found on PATH" >&2
  exit 69
}

# Resolve bundled helpers before entering the caller's checkout. The skill
# can live outside that repository, so a relative invocation must not start
# resolving helper paths against --checkout after the directory change.
SCRIPT_PATH="${BASH_SOURCE[0]}"
case "$SCRIPT_PATH" in
  */*) ;;
  *) SCRIPT_PATH=$(command -v "$SCRIPT_PATH") || {
    echo "merge-cleanup.sh: could not resolve its own path" >&2
    exit 69
  } ;;
esac
SCRIPT_PARENT="${SCRIPT_PATH%/*}"
[ "$SCRIPT_PARENT" != "$SCRIPT_PATH" ] || SCRIPT_PARENT=.
SCRIPT_DIR=$(cd -P -- "$SCRIPT_PARENT" 2>/dev/null && pwd -P) || {
  echo "merge-cleanup.sh: could not resolve its skill directory" >&2
  exit 69
}
LANDING_PLAN="$SCRIPT_DIR/base-landing-plan.sh"
[ -x "$LANDING_PLAN" ] \
  || { echo "merge-cleanup.sh: bundled landing guard is not executable" >&2; exit 69; }

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
  # Bash variables cannot hold NUL. Translate only that separator before the
  # command substitution, then append a sentinel so a URL's trailing newline
  # is not stripped along with the substitution's terminator.
  raw=$({
    git config --null --get-all "remote.$1.url" 2>/dev/null || :
    git config --null --get-all "remote.$1.pushurl" 2>/dev/null || :
  } | LC_ALL=C tr '\000' x; printf x)
  raw="${raw%x}"
  case "$raw" in *$'\n'*) return 1 ;; esac
  return 0
}
emit_result() { # emit_result <kind> <label> <detail>
  local kind="$1" label="$2" detail="$3"
  printf '%s %s {"repo":"%s","pr":%s,"merge":"%s","head_branch":"%s","base_branch":"%s","head_repo":"%s","checkout":"%s","worktree":"%s","consumers":"%s","remote_branch":"%s","base_resync":"%s","local_branch":"%s","prune":"%s","closing_refs":%s,"incomplete_step":"%s","detail":"%s"}\n' \
    "$kind" "$label" "$(json_escape "$REPO_SPEC")" "$PR" \
    "$(json_escape "$MERGE_DISPOSITION")" "$(json_escape "$BRANCH")" \
    "$(json_escape "$BASE")" "$(json_escape "$HEAD_REPO")" \
    "$(json_escape "${WORKTREE_ROOT:-$CHECKOUT_INPUT}")" \
    "$(json_escape "$WORKTREE_DISPOSITION")" \
    "$(json_escape "$CONSUMER_DISPOSITION")" \
    "$(json_escape "$REMOTE_DISPOSITION")" \
    "$(json_escape "$BASE_DISPOSITION")" \
    "$(json_escape "$LOCAL_DISPOSITION")" \
    "$(json_escape "$PRUNE_DISPOSITION")" "$CLOSING_REFS_JSON" \
    "$(json_escape "$INCOMPLETE_STEP")" "$(json_escape "$detail")"
}
stop() { # stop <guard> <detail>
  emit_result STOP "$1" "$2"
  exit 2
}
lookup_failed() { # lookup_failed <what> <detail>
  emit_result LOOKUP_FAILED "$1" "$2"
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

# --- pinned checkout and PR facts ------------------------------------------

checkout_top=""
out_exact CHECKOUT_PHYSICAL physical_dir "$CHECKOUT_INPUT" \
  || { echo "merge-cleanup.sh: --checkout is not an accessible directory" >&2; exit 64; }
cd -- "$CHECKOUT_PHYSICAL" \
  || { echo "merge-cleanup.sh: could not enter --checkout" >&2; exit 64; }
out_exact checkout_top git rev-parse --show-toplevel \
  || stop not-a-repo "--checkout is not inside a git worktree"
out_exact WORKTREE_ROOT physical_dir "$checkout_top" \
  || stop not-a-repo "could not resolve the checkout worktree root"
[ "$CHECKOUT_PHYSICAL" -ef "$WORKTREE_ROOT" ] \
  || { echo "merge-cleanup.sh: --checkout must name the worktree root" >&2; exit 64; }
cd -- "$WORKTREE_ROOT" || stop not-a-repo "could not enter the worktree root"

# Ref names cannot contain whitespace or control characters (git
# check-ref-format), so a tab-separated read is faithful for branch fields;
# the title, which can hold anything, is read separately where needed.
# The ~ sentinel keeps a null field (a deleted fork's owner or repo) from
# collapsing out of the tab-separated read and shifting every later field:
# tabs are IFS whitespace, so consecutive tabs read as one separator.
pr_payload=$(gh pr view "$PR" --repo="$REPO_SPEC" \
  --json state,mergedAt,headRefName,baseRefName,headRefOid,isCrossRepository,headRepositoryOwner,headRepository,url,closingIssuesReferences \
  --jq '([.state,(.mergedAt // "~"),.headRefName,.baseRefName,.headRefOid,(.isCrossRepository|tostring),(.headRepositoryOwner.login // "~"),(.headRepository.name // "~"),.url] | @tsv), ([.closingIssuesReferences[] | {number,repository:(.repository.nameWithOwner // "~"),url}] | tojson)' \
  2>/dev/null) || lookup_failed pr-view "could not read PR $PR from $REPO_SPEC"
case "$pr_payload" in *$'\n'*) ;; *) lookup_failed pr-view "PR $PR returned an incomplete record" ;; esac
pr_fields="${pr_payload%%$'\n'*}"
CLOSING_REFS_JSON="${pr_payload#*$'\n'}"
case "$CLOSING_REFS_JSON" in \[*\]) ;; *) lookup_failed pr-view "PR $PR returned malformed closing references" ;; esac
IFS=$'\t' read -r PR_STATE MERGED_AT BRANCH BASE FORGE_HEAD_OID IS_FORK HEAD_OWNER HEAD_REPO_NAME PR_URL <<< "$pr_fields"
[ -n "$BRANCH" ] && [ -n "$BASE" ] || lookup_failed pr-view "PR $PR returned empty branch fields"
case "$IS_FORK" in true|false) ;; *)
  lookup_failed pr-view "PR $PR returned an invalid cross-repository flag" ;;
esac
if [ "$HEAD_OWNER" != "~" ]; then
  case "$HEAD_OWNER" in *[!A-Za-z0-9-]*)
    lookup_failed pr-view "unexpected head-owner form: $HEAD_OWNER" ;;
  esac
fi
if [ "$IS_FORK" = true ]; then
  { [ "$HEAD_OWNER" != "~" ] && [ "$HEAD_REPO_NAME" != "~" ]; } \
    || lookup_failed pr-view "the fork's head repository is gone; its branch cannot be checked or cleaned from here"
  case "$HEAD_REPO_NAME" in ''|*[!A-Za-z0-9._-]*)
    lookup_failed pr-view "unexpected head-repository form: $HEAD_REPO_NAME" ;;
  esac
  HEAD_REPO="$HEAD_OWNER/$HEAD_REPO_NAME"
else
  HEAD_REPO="$REPO"
fi
HEAD_OID=$(printf '%s' "$FORGE_HEAD_OID" | tr 'A-F' 'a-f')
case "$HEAD_OID" in *[!0-9a-f]*|'') lookup_failed pr-view "PR $PR returned an invalid head OID" ;; esac
[ "${#HEAD_OID}" -eq 40 ] || lookup_failed pr-view "PR $PR returned a non-full head OID"
[ "$PR_STATE" = MERGED ] && [ -n "$MERGED_AT" ] && [ "$MERGED_AT" != "~" ] \
  || stop pr-not-merged "the forge does not report PR $PR merged with a non-null mergedAt"
MERGE_DISPOSITION=verified
# The forge host this PR lives on, for matching configured remotes.
PR_HOST="${PR_URL#*://}"; PR_HOST="${PR_HOST%%/*}"
PR_HOST=$(printf '%s' "$PR_HOST" | tr 'A-Z' 'a-z')
[ -n "$PR_HOST" ] || lookup_failed pr-view "could not derive the forge host from $PR_URL"
[ "$PR_HOST" = "$(printf '%s' "$FORGE_HOST" | tr 'A-Z' 'a-z')" ] \
  || lookup_failed pr-view "PR URL host $PR_HOST does not match pinned host $FORGE_HOST"
ENC_BRANCH=$(urlencode "$BRANCH")

# --- shared guards ----------------------------------------------------------

probe_component_alias() { # probe_component_alias <directory> <name> <name>
  local probe left right rc=1
  probe=$(mktemp -d "$1/.merge-cleanup-ref-alias.XXXXXX" 2>/dev/null) \
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

filesystem_names_alias_at() { # filesystem_names_alias_at <namespace> <name> <name> <prefix-ok>
  # Filesystem casefolding can be directory-scoped. Walk equal or aliasing
  # path components through the real loose-ref hierarchy while it exists;
  # only use an inherited temporary directory once a packed-only prefix has
  # no directory whose effective semantics can be inspected.
  local namespace="$1" left_rest="$2" right_rest="$3" prefix_ok="$4"
  local common refs_dir current virtual_root="" left_part right_part
  local left_more right_more next
  out_exact common git rev-parse --git-common-dir \
    || lookup_failed name-collision "could not locate the repository's common directory"
  refs_dir="$common/refs/$namespace"
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
      [ "$prefix_ok" = true ] || [ "$left_more" -eq "$right_more" ]
      return
    fi
    if [ -d "$current/$left_part" ]; then
      current="$current/$left_part"
    elif [ -d "$current/$right_part" ]; then
      current="$current/$right_part"
    else
      next=$(mktemp -d "$current/.merge-cleanup-ref-alias.XXXXXX" 2>/dev/null) \
        || lookup_failed name-collision "could not create an inherited ref-alias probe"
      [ -n "$virtual_root" ] || virtual_root="$next"
      current="$next"
    fi
  done
}

filesystem_names_alias() { # filesystem_names_alias <ref-name> <ref-name>
  filesystem_names_alias_at heads "$1" "$2" false
}

tracking_namespaces_overlap() { # tracking_namespaces_overlap <remote> <remote>
  filesystem_names_alias_at remotes "$1" "$2" true
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
# for the collision guard and its authoritative clone endpoints for remote
# identity checks.
REPO_FACTS_LOADED=""
load_repo_facts() {
  [ -n "$REPO_FACTS_LOADED" ] && return 0
  local facts want clone_forge ssh_forge
  facts=$(gh api --hostname "$FORGE_HOST" "repos/$REPO" \
    --jq '[.default_branch, (.clone_url // "~"), (.ssh_url // "~")] | @tsv' \
    2>/dev/null) \
    || lookup_failed repo-facts "could not read repository facts for $REPO"
  IFS=$'\t' read -r DEFAULT_BRANCH REPO_CLONE_URL REPO_SSH_URL <<< "$facts"
  [ -n "$DEFAULT_BRANCH" ] || lookup_failed repo-facts "empty default branch for $REPO"
  [ "$REPO_CLONE_URL" != "~" ] && [ "$REPO_SSH_URL" != "~" ] \
    || lookup_failed repo-facts "repository clone endpoints are missing"
  if url_has_inline_credentials "$REPO_CLONE_URL" \
      || url_has_inline_credentials "$REPO_SSH_URL"; then
    lookup_failed repo-facts "repository clone endpoints contain inline credentials"
  fi
  REPO_CLONE_ID=$(url_id "$REPO_CLONE_URL")
  REPO_SSH_ID=$(url_id "$REPO_SSH_URL")
  case "$REPO_CLONE_ID,$REPO_SSH_ID" in host\ *,host\ *) ;; *)
    lookup_failed repo-facts "repository clone endpoints are not hosted URL identities" ;;
  esac
  want=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')
  clone_forge=$(url_forge_id "$REPO_CLONE_URL") \
    || lookup_failed repo-facts "repository clone URL has no forge identity"
  ssh_forge=$(url_forge_id "$REPO_SSH_URL") \
    || lookup_failed repo-facts "repository SSH URL has no forge identity"
  [ "$clone_forge" = "$PR_HOST $want" ] && [ "$ssh_forge" = "$PR_HOST $want" ] \
    || lookup_failed repo-facts "repository clone endpoints do not identify $REPO on $PR_HOST"
  REPO_FACTS_LOADED=1
}

HEAD_FACTS_LOADED=""
load_head_facts() {
  [ -n "$HEAD_FACTS_LOADED" ] && return 0
  local facts want clone_forge ssh_forge
  facts=$(gh api --hostname "$FORGE_HOST" "repos/$HEAD_REPO" \
    --jq '[.default_branch,(.clone_url // "~"),(.ssh_url // "~")] | @tsv' 2>/dev/null) \
    || lookup_failed head-repo-facts "could not read repository facts for $HEAD_REPO"
  IFS=$'\t' read -r HEAD_DEFAULT_BRANCH HEAD_CLONE_URL HEAD_SSH_URL <<< "$facts"
  [ -n "$HEAD_DEFAULT_BRANCH" ] \
    || lookup_failed head-repo-facts "empty default branch for $HEAD_REPO"
  [ "$HEAD_CLONE_URL" != "~" ] && [ "$HEAD_SSH_URL" != "~" ] \
    || lookup_failed head-repo-facts "head repository clone endpoints are missing"
  if url_has_inline_credentials "$HEAD_CLONE_URL" \
      || url_has_inline_credentials "$HEAD_SSH_URL"; then
    lookup_failed head-repo-facts "head repository clone endpoints contain inline credentials"
  fi
  HEAD_CLONE_ID=$(url_id "$HEAD_CLONE_URL")
  HEAD_SSH_ID=$(url_id "$HEAD_SSH_URL")
  case "$HEAD_CLONE_ID,$HEAD_SSH_ID" in host\ *,host\ *) ;; *)
    lookup_failed head-repo-facts "head repository clone endpoints are not hosted URL identities" ;;
  esac
  want=$(printf '%s' "$HEAD_REPO" | tr 'A-Z' 'a-z')
  clone_forge=$(url_forge_id "$HEAD_CLONE_URL") \
    || lookup_failed head-repo-facts "head clone URL has no forge identity"
  ssh_forge=$(url_forge_id "$HEAD_SSH_URL") \
    || lookup_failed head-repo-facts "head SSH URL has no forge identity"
  [ "$clone_forge" = "$PR_HOST $want" ] && [ "$ssh_forge" = "$PR_HOST $want" ] \
    || lookup_failed head-repo-facts "head clone endpoints do not identify $HEAD_REPO on $PR_HOST"
  HEAD_FACTS_LOADED=1
}

collision_check() {
  load_repo_facts
  for ref_name in "$BRANCH" "$BASE" "$DEFAULT_BRANCH" "$HEAD_DEFAULT_BRANCH"; do
    git check-ref-format "refs/heads/$ref_name" >/dev/null 2>&1 \
      || lookup_failed name-collision "the forge returned an invalid branch name: $ref_name"
  done
  if ref_names_alias "$BRANCH" "$BASE"; then
    stop name-collision "head branch $BRANCH resolves to the same ref as base $BASE"
  fi
  if ref_names_alias "$BRANCH" "$DEFAULT_BRANCH"; then
    stop name-collision "head branch $BRANCH resolves to the same ref as default branch $DEFAULT_BRANCH"
  fi
  if ref_names_alias "$BRANCH" "$HEAD_DEFAULT_BRANCH"; then
    stop name-collision "head branch $BRANCH resolves to the same ref as head-repository default $HEAD_DEFAULT_BRANCH"
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

# Hosted HTTP-like userinfo is credential-bearing even when it contains only
# a username. SSH permits a username, but a colon introduces an inline secret,
# including in hosted SCP syntax. Hostless paths are not URL-authority
# credentials.
url_has_inline_credentials() {
  local raw="$1" scheme rest authority userinfo after_user
  case "$raw" in
    *://*) ;;
    *:*)
      case "${raw%%:*}" in */*) return 1 ;; esac
      after_user="${raw##*@}"
      case "$raw" in *@*) userinfo="${raw%"@$after_user"}" ;; *) return 1 ;; esac
      case "$userinfo" in *:*) return 0 ;; *) return 1 ;; esac
      ;;
    *) return 1 ;;
  esac
  scheme="${raw%%://*}"
  rest="${raw#*://}"
  authority="${rest%%/*}"
  case "$authority" in *@*) userinfo="${authority%@*}" ;; *) return 1 ;; esac
  case "$scheme" in
    ssh|git+ssh|ssh+git) case "$userinfo" in *:*) return 0 ;; *) return 1 ;; esac ;;
    *) return 0 ;;
  esac
}

# Resolve a hostless URL to the filesystem destination Git will use now.
# Ask Git to expand its leading ~/ and ~user/ path syntax, root other relative
# paths at the worktree root, and follow every symlink before the identity
# crosses a checkout boundary. Keep the remaining resolution in shell so
# cleanup does not gain another executable dependency.
canonical_local_path() { # canonical_local_path <path>
  local path="$1" link dir base physical suffix="" hops=0
  case "$path" in
    ~*) out_exact path git -c "mergecleanup.path=$path" config --path --get mergecleanup.path \
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
  local host="$1" user="${2:-}" target key val
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
  while read -r key val; do
    case "$key" in
      hostname) [ -n "$SSH_ALIAS_HOST" ] || SSH_ALIAS_HOST="$val" ;;
      user) [ -n "$SSH_ALIAS_USER" ] || SSH_ALIAS_USER="$val" ;;
      port) [ -n "$SSH_ALIAS_PORT" ] || SSH_ALIAS_PORT="$val" ;;
    esac
  done < <(ssh -G -- "$target" 2>/dev/null)
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
# the identity check; fetch and push keep the original alias URL so the user's
# ssh routing and key selection still apply.
ssh_alias_resolve() { # ssh_alias_resolve <url>
  local raw="$1" scheme rest authority before after path="" host user="" newuser newauth
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
  [ "$SSH_ALIAS_PORT" = 22 ] || return 1
  [ "$SSH_ALIAS_HOST" != "$(printf '%s' "$host" | tr 'A-Z' 'a-z')" ] || return 1
  newuser="$user"; [ -n "$newuser" ] || newuser="$SSH_ALIAS_USER"
  newauth="$SSH_ALIAS_HOST"; [ -z "$newuser" ] || newauth="$newuser@$SSH_ALIAS_HOST"
  case "$raw" in
    *://*) [ -n "$path" ] && printf '%s://%s/%s' "$scheme" "$newauth" "$path" \
             || printf '%s://%s' "$scheme" "$newauth" ;;
    *) printf '%s:%s' "$newauth" "$after" ;;
  esac
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
  local purls pu push_id count=0
  VALIDATED_PUSH_URL=""
  out_exact purls git remote get-url --push --all -- "$1" || return 1
  while IFS= read -r pu; do
    [ -n "$pu" ] || return 1
    url_has_inline_credentials "$pu" && return 2
    count=$((count + 1))
    out_exact push_id remote_url_id "$pu" || return 1
    [ "$push_id" = "$2" ] || return 1
    case "$push_id" in path\ *) VALIDATED_PUSH_URL="${push_id#path }" ;; *)
      VALIDATED_PUSH_URL="$pu" ;;
    esac
  done <<< "$purls"
  [ "$count" -eq 1 ]
}

# Execute one Git transport operation through a one-use synthetic URL whose
# full-length command-scoped rewrite wins over any broader live insteadOf or
# pushInsteadOf rule. Git applies URL rewrites once, so the pinned literal is
# not fed back through repository config after the synthetic name resolves.
git_pinned_url() { # git_pinned_url <literal-url> <git args with @PINNED_URL@>
  local target="$1" count="${GIT_CONFIG_COUNT:-0}" next pin arg seen=0
  local -a args=()
  shift
  case "$count" in ''|*[!0-9]*) lookup_failed url-pin "GIT_CONFIG_COUNT is invalid" ;; esac
  PIN_SERIAL=$((PIN_SERIAL + 1))
  pin="${target}#merge-cleanup-pin-${BASHPID:-$$}-${PIN_SERIAL}-${RANDOM}-${RANDOM}"
  for arg in "$@"; do
    if [ "$arg" = @PINNED_URL@ ]; then
      args+=("$pin"); seen=$((seen + 1))
    else
      args+=("$arg")
    fi
  done
  [ "$seen" -eq 1 ] || lookup_failed url-pin "pinned Git command did not contain exactly one URL placeholder"
  next=$((count + 1))
  env "GIT_CONFIG_COUNT=$((count + 2))" \
    "GIT_CONFIG_KEY_${count}=url.$target.insteadOf" \
    "GIT_CONFIG_VALUE_${count}=$pin" \
    "GIT_CONFIG_KEY_${next}=url.$target.pushInsteadOf" \
    "GIT_CONFIG_VALUE_${next}=$pin" \
    git "${args[@]}"
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
resolve_remote() { # resolve_remote <owner/name> <clone-id> <ssh-id>
  local want r furl fid forge_id resolved match="" count=0
  want=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  RESOLVED_REMOTE=""
  while IFS= read -r r; do
    remote_urls_newline_free "$r" || continue
    out_exact furl git remote get-url -- "$r" || continue
    fid=$(url_id "$furl")
    forge_id=$(url_forge_id "$furl") || forge_id=""
    # A local SSH host alias hides the true forge identity; resolve it and
    # retry the candidate match on the concrete endpoint when the raw URL fails.
    if { [ "$fid" != "$2" ] && [ "$fid" != "$3" ]; } \
        || [ "$forge_id" != "$PR_HOST $want" ]; then
      resolved=$(ssh_alias_resolve "$furl") && [ -n "$resolved" ] || continue
      fid=$(url_id "$resolved")
      forge_id=$(url_forge_id "$resolved") || continue
    fi
    case "$fid" in "$2"|"$3") ;; *) continue ;; esac
    [ "$forge_id" = "$PR_HOST $want" ] || continue
    count=$((count + 1))
    match="$r"
  done < <(git remote)
  [ "$count" -le 1 ] \
    || stop remote-ambiguous "$count configured remotes identify $1; pass the intended remote explicitly"
  RESOLVED_REMOTE="$match"
}

# A hosted override must still identify the PR's repository. A hostless
# mapping cannot be matched to forge identity, so naming that remote
# explicitly is the separate trust decision. A hostless mapping that remains
# after checkout is pinned to that identity; a replacement hosted mapping can
# instead be validated against the forge. CHECKED_REMOTE_ID exposes the
# validated identity to that checkout boundary, and fetch/push identity is
# still checked before a destructive head push.
CHECKED_REMOTE_ID="" CHECKED_REMOTE_URL=""
remote_repo_check() { # remote_repo_check <remote> <role> <repo> <clone-id> <ssh-id>
  local remote="$1" role="$2" expected_repo="$3" configured u have_url=false furl endpoint_id
  local resolved_url resolved_id
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
  url_has_inline_credentials "$furl" \
    && stop credential-url "$role remote $remote contains inline credentials"
  out_exact endpoint_id remote_url_id "$furl" \
    || stop remote-repo-mismatch "$role remote $remote's effective local destination could not be resolved safely"
  CHECKED_REMOTE_ID="$endpoint_id"
  case "$endpoint_id" in path\ *) CHECKED_REMOTE_URL="${endpoint_id#path }" ;; *)
    CHECKED_REMOTE_URL="$furl" ;;
  esac
  case "$endpoint_id" in
    path\ *) return 0 ;;
    "$4"|"$5") return 0 ;;
  esac
  # A local SSH host alias resolves to the forge's real endpoint; compare that
  # resolved identity before refusing. CHECKED_REMOTE_URL stays the alias URL
  # so fetch and push still route through the user's ssh config.
  if resolved_url=$(ssh_alias_resolve "$furl") && [ -n "$resolved_url" ] \
      && resolved_id=$(remote_url_id "$resolved_url"); then
    case "$resolved_id" in "$4"|"$5") return 0 ;; esac
  fi
  stop remote-repo-mismatch "$role remote $remote does not match $expected_repo's authoritative clone endpoints"
}

# --- cleanup orchestration --------------------------------------------------

read_plan_field() { # read_plan_field <variable> <fd>
  IFS= read -r -d '' "$1" <&"$2" \
    || lookup_failed landing-plan "landing plan returned a truncated NUL record"
}

load_landing_plan() { # load_landing_plan <remote>
  local remote="$1" tmp rc marker count i detail expected
  tmp=$(mktemp) || lookup_failed landing-plan "mktemp failed"
  "$LANDING_PLAN" --format nul "$remote" "$BASE" >"$tmp" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    detail=$(LC_ALL=C tr -d '\0' <"$tmp" | tail -c 500)
    rm -f "$tmp"
    case "$rc" in
      2) stop landing-plan "$detail" ;;
      4) lookup_failed landing-plan "$detail" ;;
      64|69) lookup_failed landing-plan "$detail" ;;
      *) lookup_failed landing-plan "planner exited $rc: $detail" ;;
    esac
  fi
  exec 3<"$tmp"
  read_plan_field marker 3
  [ "$marker" = "OK landing" ] \
    || { exec 3<&-; rm -f "$tmp"; lookup_failed landing-plan "unexpected plan marker: $marker"; }
  read_plan_field PLAN_REMOTE 3
  read_plan_field PLAN_BASE 3
  read_plan_field PLAN_VERB 3
  read_plan_field PLAN_CREATE 3
  read_plan_field PLAN_TRACKING 3
  read_plan_field PLAN_TAG_SHADOW 3
  read_plan_field count 3
  [ "$PLAN_REMOTE" = "$remote" ] && [ "$PLAN_BASE" = "$BASE" ] \
    || { exec 3<&-; rm -f "$tmp"; lookup_failed landing-plan "plan target does not match its invocation"; }
  case "$PLAN_VERB,$PLAN_CREATE,$PLAN_TRACKING,$count" in
    checkout,false,ok,0|checkout,false,write,0) ;;
    checkout,true,ok,1|checkout,true,write,1) ;;
    switch,false,ok,0|switch,false,write,0) ;;
    switch,true,ok,1|switch,true,write,1) ;;
    *) exec 3<&-; rm -f "$tmp"; lookup_failed landing-plan "plan fields are inconsistent" ;;
  esac
  case "$PLAN_TAG_SHADOW" in true|false) ;; *)
    exec 3<&-; rm -f "$tmp"; lookup_failed landing-plan "plan tag-shadow field is invalid" ;;
  esac
  PLAN_FETCH=()
  i=0
  while [ "$i" -lt "$count" ]; do
    read_plan_field detail 3
    PLAN_FETCH+=("$detail")
    i=$((i + 1))
  done
  if [ "$PLAN_CREATE" = true ]; then
    expected="refs/heads/$BASE"
    [ "${PLAN_FETCH[0]}" = "$expected" ] \
      || { exec 3<&-; rm -f "$tmp"; lookup_failed landing-plan "plan returned an unexpected FETCH_HEAD refspec"; }
  fi
  if IFS= read -r -d '' detail <&3; then
    exec 3<&-; rm -f "$tmp"; lookup_failed landing-plan "plan returned unexpected trailing fields"
  fi
  exec 3<&-
  rm -f "$tmp"
}

resolve_base_remote() {
  if [ -n "$BASE_REMOTE_OPT" ]; then
    BASE_REMOTE="$BASE_REMOTE_OPT"
  else
    resolve_remote "$REPO" "$REPO_CLONE_ID" "$REPO_SSH_ID"
    [ -n "$RESOLVED_REMOTE" ] \
      || stop remote-unresolved "no configured remote identifies base repository $REPO; pass --base-remote"
    BASE_REMOTE="$RESOLVED_REMOTE"
  fi
  remote_repo_check "$BASE_REMOTE" base "$REPO" "$REPO_CLONE_ID" "$REPO_SSH_ID"
}

remote_namespace_check() { # remote_namespace_check <remote-name>
  local remote="$1" destination="refs/remotes/$1/probe" other remotes
  git check-ref-format "$destination" >/dev/null 2>&1 \
    || stop remote-namespace "remote name $remote cannot form a safe remote-tracking namespace"
  out_exact remotes git remote \
    || lookup_failed remote-namespaces "could not enumerate remotes before writing $remote tracking refs"
  while IFS= read -r other; do
    [ "$other" != "$remote" ] || continue
    tracking_namespaces_overlap "$remote" "$other" \
      && stop remote-namespace "remote names $remote and $other have overlapping tracking namespaces"
  done <<<"$remotes"
}

safe_prune() { # safe_prune <validated-url> <remote-name>
  local url="$1" remote="$2"
  remote_namespace_check "$remote"
  git_pinned_url "$url" -c fetch.pruneTags=false fetch --prune -- @PINNED_URL@ \
    "+refs/heads/*:refs/remotes/$remote/*" >/dev/null 2>&1
}

check_consumers() {
  local shared_rows shared=0 shared_number shared_state shared_branch shared_oid shared_repo shared_base
  local numbers n observed
  local head_owner="${HEAD_REPO%%/*}" head_name="${HEAD_REPO#*/}"
  shared_rows=$(gh api graphql --hostname "$FORGE_HOST" --paginate \
    -f query='query($owner:String!,$name:String!,$oid:GitObjectID!,$endCursor:String){repository(owner:$owner,name:$name){object(oid:$oid){... on Commit{associatedPullRequests(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{number state headRefName headRefOid baseRepository{nameWithOwner} headRepository{nameWithOwner}}}}}}}' \
    -F owner="$head_owner" -F name="$head_name" -F oid="$HEAD_OID" \
    --jq '.data.repository.object.associatedPullRequests.nodes[] |
      [.number,.state,(.headRefName // "~"),(.headRefOid // "~"),
        (.headRepository.nameWithOwner // "~"),
        (.baseRepository.nameWithOwner // "~")] | @tsv' \
    2>/dev/null) \
    || lookup_failed shared-head "could not list open PRs across the network sharing $HEAD_REPO:$BRANCH at $HEAD_OID"
  while IFS=$'\t' read -r shared_number shared_state shared_branch shared_oid shared_repo shared_base; do
    [ -n "$shared_number" ] || continue
    case "$shared_number" in *[!0-9]*|0*)
      lookup_failed shared-head "network-wide shared-head listing returned an invalid PR number" ;;
    esac
    case "$shared_state" in OPEN|CLOSED|MERGED) ;; *)
      lookup_failed shared-head "network-wide shared-head listing returned an invalid PR state" ;;
    esac
    [ "$shared_state" = OPEN ] || continue
    case "$shared_oid" in *[!0-9A-Fa-f]*|'')
      lookup_failed shared-head "network-wide shared-head listing returned an invalid head OID" ;;
    esac
    [ "${#shared_oid}" -eq 40 ] \
      || lookup_failed shared-head "network-wide shared-head listing returned a non-full head OID"
    case "$shared_repo,$shared_base" in ?*/?*,?*/?*) ;; *)
      lookup_failed shared-head "network-wide shared-head listing returned an invalid repository identity" ;;
    esac
    [ "$shared_branch" != "~" ] \
      || lookup_failed shared-head "network-wide shared-head listing returned an empty head branch"
    if [ "$shared_number" -eq "$PR" ] \
        && [ "$(printf '%s' "$shared_base" | tr 'A-Z' 'a-z')" \
          = "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" ]; then
      continue
    fi
    if [ "$(printf '%s' "$shared_repo" | tr 'A-Z' 'a-z')" \
        = "$(printf '%s' "$HEAD_REPO" | tr 'A-Z' 'a-z')" ] \
        && [ "$shared_branch" = "$BRANCH" ] \
        && [ "$(printf '%s' "$shared_oid" | tr 'A-F' 'a-f')" = "$HEAD_OID" ]; then
      shared=$((shared + 1))
    fi
  done <<<"$shared_rows"
  [ "$shared" -eq 0 ] \
    || stop shared-head "$shared other open PR(s) across the network use $HEAD_REPO:$BRANCH as their head"

  numbers=$(gh api --hostname "$FORGE_HOST" --paginate \
    "repos/$HEAD_REPO/pulls?state=open&per_page=100&base=$ENC_BRANCH" \
    --jq '.[] | .number' 2>/dev/null) \
    || lookup_failed stacked-prs "could not list open PRs based on $BRANCH"
  if [ -z "$numbers" ]; then CONSUMER_DISPOSITION=clear; return 0; fi
  [ "$HEAD_REPO" = "$REPO" ] \
    || stop stacked-cross-repo "open PRs in $HEAD_REPO are based on $BRANCH and cannot be retargeted to $REPO/$BASE"
  while IFS= read -r n; do
    case "$n" in ''|*[!0-9]*) lookup_failed stacked-prs "unparseable stacked PR number" ;; esac
    gh pr edit "$n" --repo="$FORGE_HOST/$HEAD_REPO" --base="$BASE" >/dev/null 2>&1 \
      || stop stacked-retarget "could not retarget stacked PR $n to $BASE"
    observed=$(gh pr view "$n" --repo="$FORGE_HOST/$HEAD_REPO" --json=baseRefName --jq=.baseRefName 2>/dev/null) \
      || lookup_failed stacked-retarget "could not verify stacked PR $n after retarget"
    [ "$observed" = "$BASE" ] \
      || stop stacked-retarget "stacked PR $n still targets $observed after retarget"
    RETARGETED_COUNT=$((RETARGETED_COUNT + 1))
    CONSUMER_DISPOSITION="retargeted:$RETARGETED_COUNT"
  done <<<"$numbers"
}

phase_cleanup() {
  local local_tip base_symbolic_rc=0 initial_base_id="" initial_head_id=""
  local head_worktree="" base_wt="" head_target="" head_label="" head_is_remote=false
  local hr_fid ls_out ls_rc remote_oid="" line_oid line_ref exact=0 decoys=0
  local base_fetch_url="" head_fetch_url=""
  local local_disposition="" push_match_rc

  INCOMPLETE_STEP=preflight
  load_repo_facts
  load_head_facts
  collision_check
  workspace_preflight

  git symbolic-ref -q "refs/heads/$BASE" >/dev/null 2>&1 || base_symbolic_rc=$?
  case "$base_symbolic_rc" in
    0) stop local-base "local $BASE is a symbolic ref" ;;
    1) ;;
    *) lookup_failed local-base "could not determine whether local $BASE is symbolic" ;;
  esac

  if ref_exists "refs/heads/$BRANCH"; then
    if git symbolic-ref -q "refs/heads/$BRANCH" >/dev/null 2>&1; then
      stop local-branch "local $BRANCH is a symbolic ref"
    fi
    local_tip=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null) \
      || lookup_failed local-branch "could not read local $BRANCH"
    [ "$local_tip" = "$HEAD_OID" ] \
      || stop local-branch "local $BRANCH is $local_tip, not merged head $HEAD_OID"
  fi

  worktree_scan "refs/heads/$BASE"; base_wt="$WT_MATCH"
  if [ -n "$base_wt" ] && ! [ "$base_wt" -ef "$WORKTREE_ROOT" ]; then
    stop wrong-checkout "base $BASE is checked out in $base_wt; use that path as --checkout"
  fi
  worktree_scan "refs/heads/$BRANCH"; head_worktree="$WT_MATCH"
  if [ -n "$head_worktree" ] && ! [ "$head_worktree" -ef "$WORKTREE_ROOT" ]; then
    WORKTREE_DISPOSITION=owner_removal_required
    stop head-worktree-present "linked head worktree $head_worktree must be removed by its owner before cleanup"
  elif [ -n "$head_worktree" ]; then
    WORKTREE_DISPOSITION=current
  else
    WORKTREE_DISPOSITION=absent
  fi

  resolve_base_remote
  initial_base_id="$CHECKED_REMOTE_ID"
  if [ -n "$HEAD_REMOTE_OPT" ]; then
    remote_repo_check "$HEAD_REMOTE_OPT" head "$HEAD_REPO" "$HEAD_CLONE_ID" "$HEAD_SSH_ID"
    initial_head_id="$CHECKED_REMOTE_ID"
  elif [ "$HEAD_REPO" = "$REPO" ]; then
    initial_head_id="$initial_base_id"
  fi

  INCOMPLETE_STEP=base_landing
  load_landing_plan "$BASE_REMOTE"
  [ "$PLAN_CREATE" != true ] \
    || stop base-create-required "local base $BASE is absent; its owner must create it before cleanup"
  case "$PLAN_VERB,$PLAN_CREATE" in
    checkout,false)
      git checkout --no-overwrite-ignore "$BASE" >/dev/null 2>&1 \
        || stop checkout-refused "switching to $BASE was refused; nothing was overwritten" ;;
    switch,false)
      git switch --no-overwrite-ignore -- "$BASE" >/dev/null 2>&1 \
        || stop checkout-refused "switching to $BASE was refused; nothing was overwritten"
      ;;
    *) lookup_failed landing-plan "plan requested an unsupported base-creation path" ;;
  esac
  [ "$(git symbolic-ref -q HEAD 2>/dev/null)" = "refs/heads/$BASE" ] \
    || stop detached "HEAD is not attached to refs/heads/$BASE"
  BASE_DISPOSITION=landed

  resolve_base_remote
  case "$CHECKED_REMOTE_ID" in path\ *)
    [ "$CHECKED_REMOTE_ID" = "$initial_base_id" ] \
      || stop remote-config-changed "base remote became a hostless path not trusted before checkout" ;;
  esac
  base_fetch_url="$CHECKED_REMOTE_URL"
  load_landing_plan "$BASE_REMOTE"
  if [ "$PLAN_TRACKING" = write ]; then
    if ! git config "branch.$BASE.remote" "$BASE_REMOTE" \
        || ! git config "branch.$BASE.merge" "refs/heads/$BASE"; then
      stop tracking-config-failed "could not configure both tracking keys for $BASE"
    fi
    BASE_DISPOSITION=tracking_written
  fi

  INCOMPLETE_STEP=base_resync
  remote_namespace_check "$BASE_REMOTE"
  git_pinned_url "$base_fetch_url" fetch -- @PINNED_URL@ \
    "refs/heads/$BASE:refs/remotes/$BASE_REMOTE/$BASE" >/dev/null 2>&1 \
    || lookup_failed base-fetch "could not fetch $BASE from $BASE_REMOTE"
  git merge --ff-only --no-overwrite-ignore \
    "refs/remotes/$BASE_REMOTE/$BASE" >/dev/null 2>&1 \
    || stop resync-failed "fast-forwarding $BASE refused; resolve divergence or ignored-file conflict without forcing"
  [ "$(git symbolic-ref -q HEAD 2>/dev/null)" = "refs/heads/$BASE" ] \
    || stop resync-changed "HEAD moved away from refs/heads/$BASE during the fast-forward"
  local_tip=$(git rev-parse "refs/heads/$BASE" 2>/dev/null) \
    || lookup_failed base-resync "could not read local $BASE after the fast-forward"
  remote_oid=$(git rev-parse "refs/remotes/$BASE_REMOTE/$BASE" 2>/dev/null) \
    || lookup_failed base-resync "could not read fetched $BASE after the fast-forward"
  [ "$local_tip" = "$remote_oid" ] \
    || stop resync-changed "local $BASE is $local_tip after the fast-forward, not fetched base $remote_oid"
  BASE_DISPOSITION=resynced

  INCOMPLETE_STEP=remote_branch
  if [ -n "$HEAD_REMOTE_OPT" ]; then
    HEAD_REMOTE="$HEAD_REMOTE_OPT"
    remote_repo_check "$HEAD_REMOTE" head "$HEAD_REPO" "$HEAD_CLONE_ID" "$HEAD_SSH_ID"
    case "$CHECKED_REMOTE_ID" in path\ *)
      [ "$CHECKED_REMOTE_ID" = "$initial_head_id" ] \
        || stop remote-config-changed "head remote became a hostless path not trusted before checkout" ;;
    esac
    hr_fid="$CHECKED_REMOTE_ID"; head_fetch_url="$CHECKED_REMOTE_URL"
    head_target="$HEAD_REMOTE"; head_label="$HEAD_REMOTE"; head_is_remote=true
  else
    resolve_remote "$HEAD_REPO" "$HEAD_CLONE_ID" "$HEAD_SSH_ID"
    if [ -n "$RESOLVED_REMOTE" ]; then
      HEAD_REMOTE="$RESOLVED_REMOTE"
      remote_repo_check "$HEAD_REMOTE" head "$HEAD_REPO" "$HEAD_CLONE_ID" "$HEAD_SSH_ID"
      hr_fid="$CHECKED_REMOTE_ID"; head_fetch_url="$CHECKED_REMOTE_URL"
      head_target="$HEAD_REMOTE"; head_label="$HEAD_REMOTE"; head_is_remote=true
    elif [ "$IS_FORK" = true ]; then
      head_target="$HEAD_SSH_URL"; head_label="direct:$HEAD_REPO"
    else
      stop remote-unresolved "no configured remote identifies head repository $HEAD_REPO; pass --head-remote"
    fi
  fi

  if [ "$head_is_remote" = true ]; then
    push_ids_match "$HEAD_REMOTE" "$hr_fid"; push_match_rc=$?
    case "$push_match_rc" in
      0) ;;
      2) stop credential-url "head remote $HEAD_REMOTE has a push URL containing inline credentials" ;;
      *) stop pushurl-mismatch "$HEAD_REMOTE must have exactly one push destination matching its fetch URL" ;;
    esac
    head_target="$VALIDATED_PUSH_URL"
  fi

  ls_out=$(git_pinned_url "$head_target" ls-remote --exit-code --heads -- @PINNED_URL@ \
    "refs/heads/$BRANCH" 2>/dev/null); ls_rc=$?
  if [ "$ls_rc" -eq 2 ]; then
    check_consumers
    REMOTE_DISPOSITION=already_absent
  elif [ "$ls_rc" -ne 0 ]; then
    lookup_failed ls-remote "could not read refs/heads/$BRANCH from $head_label"
  else
    while IFS=$'\t' read -r line_oid line_ref; do
      if [ "$line_ref" = "refs/heads/$BRANCH" ]; then
        exact=$((exact + 1)); remote_oid="$line_oid"
      elif [ -n "$line_ref" ]; then
        decoys=$((decoys + 1))
      fi
    done <<<"$ls_out"
    [ "$exact" -le 1 ] || lookup_failed ls-remote "duplicate exact rows for refs/heads/$BRANCH"
    [ "$decoys" -eq 0 ] \
      || stop ambiguous-ref "a suffix-matching remote ref makes the delete ambiguous"
    if [ "$exact" -eq 0 ]; then
      check_consumers
      REMOTE_DISPOSITION=already_absent
    else
      [ "$remote_oid" = "$HEAD_OID" ] \
        || stop oid-mismatch "remote $BRANCH is $remote_oid, not merged head $HEAD_OID"
      check_consumers
      git_pinned_url "$head_target" push --delete \
        --force-with-lease="refs/heads/$BRANCH:$HEAD_OID" \
        -- @PINNED_URL@ "refs/heads/$BRANCH" >/dev/null 2>&1 \
        || stop lease-failed "lease-protected deletion of $BRANCH from $head_label was refused"
      REMOTE_DISPOSITION=deleted
    fi
  fi

  INCOMPLETE_STEP=local_branch
  if ref_exists "refs/heads/$BRANCH"; then
    worktree_scan "refs/heads/$BRANCH"
    [ -z "$WT_MATCH" ] \
      || stop head-worktree-present "a worktree still checks out $BRANCH at $WT_MATCH"
    if git symbolic-ref -q "refs/heads/$BRANCH" >/dev/null 2>&1; then
      stop local-branch "local $BRANCH became symbolic"
    fi
    local_tip=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null) \
      || lookup_failed local-branch "could not re-read local $BRANCH"
    [ "$local_tip" = "$HEAD_OID" ] \
      || stop local-branch "local $BRANCH moved to $local_tip after merge verification"
    if git merge-base --is-ancestor "refs/heads/$BRANCH" HEAD; then
      local_disposition=deleted_merged_config_retained
    else
      local_disposition=deleted_verified_config_retained
    fi
    git update-ref -d "refs/heads/$BRANCH" "$HEAD_OID" >/dev/null 2>&1 \
      || stop local-delete "local $BRANCH changed before its compare-and-delete"
    LOCAL_DISPOSITION="$local_disposition"
  else
    LOCAL_DISPOSITION=already_absent_config_retained
  fi
  # update-ref supplies the expected-old-OID lease that git branch lacks.
  # Leave branch.<name> config untouched: Git has no atomic primitive that
  # couples config removal to the expected ref OID, so deleting it here could
  # race a same-name branch recreation and discard the new branch's settings.

  INCOMPLETE_STEP=prune
  safe_prune "$base_fetch_url" "$BASE_REMOTE" \
    || lookup_failed prune "could not prune base remote $BASE_REMOTE"
  PRUNE_DISPOSITION=base_complete
  if [ "$head_is_remote" = true ] && [ "$HEAD_REMOTE" != "$BASE_REMOTE" ]; then
    safe_prune "$head_fetch_url" "$HEAD_REMOTE" \
      || lookup_failed prune "could not prune head remote $HEAD_REMOTE"
  fi
  PRUNE_DISPOSITION=complete
  INCOMPLETE_STEP=none
  emit_result OK cleanup ""
}

phase_cleanup
