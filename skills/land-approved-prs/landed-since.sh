#!/usr/bin/env bash
# landed-since.sh: gather what has landed on the default branch since a PR
# diverged from it, for the land-approved-prs skill's read-what-landed step.
# It prints and runs; it decides nothing. The agent reads the output and
# judges whether the PR still holds.
#
# Usage:
#   landed-since.sh --repo owner/name --pr N [--since <40-hex-oid>]
#     [--base-remote NAME]   # override remote resolution for the repository
#
# Without --since, the range starts at the PR's original merge base: the
# merge base of its first pushed head with the default branch, which does
# not move as the default branch advances or the author rebases. The first
# pushed head is the head of the PR's earliest pull_request CI run. When no
# run exists, or a force-push precedes the earliest run, the first head is
# unknown and the script stops first-head-unknown rather than start from a
# later head, which would skip exactly the commits this read exists for.
#
# --since starts the range at an earlier read's tip instead, for the re-read
# after land stops rebased.
#
# It then prints the default branch's first-parent log with --stat over the
# range and runs each command the landing record lists under Base-advance
# checks, from the checkout's root, printing its output and exit status.
# Each command sees LAND_PR, LAND_FROM, and LAND_TIP in its environment.
#
# Last line on stdout is the machine-readable result:
#   OK landed-since <json>
#   STOP <guard> <json>
#   LOOKUP_FAILED <what> <json>
# Exit codes: 0 OK; 2 STOP; 4 LOOKUP_FAILED; 64 usage error; 69 gh
# (GitHub CLI) not found on PATH.
set -u

REPO="" PR="" SINCE="" BASE_REMOTE_OPT=""

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

die_usage() { echo "landed-since.sh: $1" >&2; usage; }

while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --repo|--pr|--since|--base-remote) ;;
    *) die_usage "unknown option: $opt" ;;
  esac
  [ $# -ge 2 ] || die_usage "$opt requires a value"
  val="$2"; shift 2
  case "$opt" in
    --repo) REPO="$val" ;;
    --pr) PR="$val" ;;
    --since) SINCE=$(printf '%s' "$val" | tr 'A-F' 'a-f') ;;
    --base-remote) BASE_REMOTE_OPT="$val" ;;
  esac
done

[ -n "$REPO" ] && [ -n "$PR" ] || usage
case "$PR" in ''|*[!0-9]*|0*) die_usage "--pr must be a positive integer without leading zeros" ;; esac
case "$REPO" in
  */*/*|*[!A-Za-z0-9._/-]*) die_usage "--repo must be owner/name" ;;
  ?*/?*) ;;
  *) die_usage "--repo must be owner/name" ;;
esac
if [ -n "$SINCE" ]; then
  case "$SINCE" in *[!0-9a-f]*) die_usage "--since must be a full 40-hex commit OID" ;; esac
  [ "${#SINCE}" -eq 40 ] || die_usage "--since must be a full 40-hex commit OID"
fi
case "$BASE_REMOTE_OPT" in -*) die_usage "remote names must not begin with a hyphen" ;; esac

command -v gh >/dev/null 2>&1 || {
  echo "landed-since.sh: gh (GitHub CLI) not found on PATH; the skill needs an authenticated forge CLI, so stop and hand the batch to the owner" >&2
  exit 69
}

json_escape() {
  local LC_ALL=C s="$1" out="" c i o
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      \\) out+='\\' ;;
      \") out+='\"' ;;
      *)
        o=$(( $(printf '%d' "'$c") & 255 ))
        if [ "$o" -lt 32 ] || [ "$o" -eq 127 ]; then out+=$(printf '\\u%04x' "$o")
        else out+="$c"; fi ;;
    esac
  done
  printf '%s' "$out"
}
stop() {
  echo "STOP $1 {\"detail\":\"$(json_escape "$2")\"}"
  exit 2
}
lookup_failed() {
  echo "LOOKUP_FAILED $1 {\"detail\":\"$(json_escape "$2")\"}"
  exit 4
}

TOP=$(git rev-parse --show-toplevel 2>/dev/null) \
  || stop not-a-repo "run from a checkout of $REPO"

# Whether a remote's fetch URL names the repository: it ends in /owner/name
# or :owner/name, ignoring case, a trailing slash, and .git.
remote_names_repo() { # remote_names_repo <remote>
  local want url
  want=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')
  url=$(git remote get-url -- "$1" 2>/dev/null) || return 1
  url=$(printf '%s' "$url" | tr 'A-Z' 'a-z')
  url="${url%/}"; url="${url%.git}"
  case "$url" in */"$want"|*:"$want") return 0 ;; esac
  return 1
}
resolve_remote() {
  local r match="" n=0
  while IFS= read -r r; do
    remote_names_repo "$r" || continue
    match="$r"; n=$((n + 1))
  done < <(git remote)
  [ "$n" -gt 0 ] || stop remote-unresolved "no remote's URL names $REPO; add one"
  [ "$n" -eq 1 ] || stop remote-ambiguous "$n remotes name $REPO; pass --base-remote"
  REMOTE="$match"
}
# The override only picks among remotes that name the repository. A fork or
# sibling remote would serve its own landing record while the forge
# calls still read $REPO.
if [ -n "$BASE_REMOTE_OPT" ]; then
  git remote get-url -- "$BASE_REMOTE_OPT" >/dev/null 2>&1 \
    || stop remote-unresolved "no remote named $BASE_REMOTE_OPT"
  remote_names_repo "$BASE_REMOTE_OPT" \
    || stop remote-repo-mismatch "remote $BASE_REMOTE_OPT's URL does not name $REPO"
  REMOTE="$BASE_REMOTE_OPT"
else
  resolve_remote
fi

DEFAULT=$(gh api "repos/$REPO" --jq .default_branch 2>/dev/null) \
  || lookup_failed repo "could not read $REPO's default branch"
[ -n "$DEFAULT" ] || lookup_failed repo "$REPO reported no default branch"
git fetch -q --no-tags -- "$REMOTE" "+refs/heads/$DEFAULT:refs/remotes/$REMOTE/$DEFAULT" 2>/dev/null \
  || lookup_failed base-fetch "could not fetch $DEFAULT from $REMOTE"
TIP=$(git rev-parse --verify --quiet "refs/remotes/$REMOTE/$DEFAULT^{commit}") \
  || lookup_failed base-fetch "the fetched $DEFAULT did not resolve to a commit"

FIRST_HEAD=""
if [ -n "$SINCE" ]; then
  FROM="$SINCE"
  git cat-file -e "$FROM^{commit}" 2>/dev/null \
    || lookup_failed since "--since $FROM is not a commit in this repository; fetch it or read from the original base"
else
  fields=$(gh pr view "$PR" --repo "$REPO" --json createdAt,headRefName \
    --jq '[.createdAt, .headRefName] | @tsv' 2>/dev/null) \
    || lookup_failed pr-view "could not read PR $PR"
  IFS=$'\t' read -r created head <<< "$fields"
  [ -n "$created" ] && [ -n "$head" ] || lookup_failed pr-view "PR $PR reported no creation time or head branch"
  # A pull_request run created before the PR existed belongs to an earlier
  # PR that reused the branch name, and one whose head lives in another
  # repository belongs to a fork's PR from a same-named branch.
  repo_lc=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')
  first_run=$(gh api -X GET --paginate "repos/$REPO/actions/runs" -f event=pull_request \
    -f branch="$head" -f per_page=100 \
    --jq ".workflow_runs[] | select((.head_repository.full_name // \"\" | ascii_downcase) == \"$repo_lc\") | [.created_at, .head_sha] | @tsv" 2>/dev/null) \
    || lookup_failed actions-runs "could not read PR $PR's CI runs"
  first_run=$(printf '%s\n' "$first_run" | awk -F'\t' -v c="$created" 'NF == 2 && $1 >= c' | sort -t $'\t' -k1,1 | head -n 1)
  first_push=$(gh api --paginate "repos/$REPO/issues/$PR/timeline?per_page=100" \
    --jq '.[] | select(.event == "head_ref_force_pushed") | .created_at' 2>/dev/null) \
    || lookup_failed timeline "could not read PR $PR's timeline"
  first_push=$(printf '%s\n' "$first_push" | sed '/^$/d' | sort | head -n 1)
  [ -n "$first_run" ] \
    || stop first-head-unknown "PR $PR has no pull_request CI run, so its first pushed head is unknown; hand it back"
  run_at="${first_run%%$'\t'*}" FIRST_HEAD="${first_run#*$'\t'}"
  if [ -n "$first_push" ] && [[ "$first_push" < "$run_at" ]]; then
    stop first-head-unknown "PR $PR was force-pushed at $first_push, before its earliest CI run at $run_at, so its first pushed head is unknown; hand it back"
  fi
  case "$FIRST_HEAD" in *[!0-9a-f]*|'') lookup_failed actions-runs "unparseable head '$FIRST_HEAD'" ;; esac
  # The forge keeps force-pushed-away commits and reports their merge base,
  # so this works even when the first head is gone from every branch.
  FROM=$(gh api "repos/$REPO/compare/$DEFAULT...$FIRST_HEAD" --jq .merge_base_commit.sha 2>/dev/null) \
    || lookup_failed compare "could not read the merge base of $FIRST_HEAD with $DEFAULT"
  case "$FROM" in *[!0-9a-f]*|'') lookup_failed compare "unparseable merge base '$FROM'" ;; esac
  git cat-file -e "$FROM^{commit}" 2>/dev/null \
    || lookup_failed merge-base "the merge base $FROM is not in the fetched $DEFAULT"
fi

COUNT=$(git rev-list --first-parent --count "$FROM..$TIP" 2>/dev/null) \
  || lookup_failed log "could not count $FROM..$TIP"
echo "landed on $DEFAULT from ${FROM:0:7} to ${TIP:0:7}: $COUNT first-parent commit(s)${FIRST_HEAD:+ (original base of first head ${FIRST_HEAD:0:7})}"
if [ "$COUNT" -gt 0 ]; then
  git --no-pager log --first-parent --stat --no-color "$FROM..$TIP" \
    || lookup_failed log "could not print $FROM..$TIP"
fi

# The record's Base-advance checks bullet: none (bare or backticked), or
# backticked commands. Every backticked span is a command. A record that
# can't be read, a missing bullet, or a value with no backticked command
# stops rather than skip the checks.
AGENTS_TEXT=$(git show "$TIP:AGENTS.md" 2>/dev/null) \
  || stop no-landing-record "AGENTS.md is missing at $DEFAULT's tip, so there is no landing record"
printf '%s\n' "$AGENTS_TEXT" | grep -q '^  - \*\*Mechanism:\*\* ' \
  || stop no-landing-record "AGENTS.md at $DEFAULT's tip has no landing record (no Mechanism bullet)"
checks=$(printf '%s\n' "$AGENTS_TEXT" | awk '
  !started && /^  - \*\*Mechanism:\*\* / { started = 1 }
  !started { next }
  /^  - \*\*Base-advance checks:\*\* / { grab = 1; line = $0; sub(/^  - \*\*Base-advance checks:\*\* /, "", line); print line; next }
  /^  - \*\*/ { grab = 0; next }
  /^    [^ ]/ && grab { line = $0; sub(/^ +/, "", line); print line; next }
  /^    [^ ]/ { next }
  { exit }
')
[ -n "$checks" ] \
  || stop bad-record "the landing record needs a Base-advance checks bullet, none when the project has no checks"
checks_json=""
case "$checks" in
  none*|'`none`'*) echo "base-advance checks: none recorded" ;;
  *)
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      echo "base-advance check: $cmd"
      rc=0
      (cd "$TOP" && LAND_PR="$PR" LAND_FROM="$FROM" LAND_TIP="$TIP" bash -c "$cmd") < /dev/null 2>&1 || rc=$?
      echo "base-advance check exit $rc: $cmd"
      checks_json+=",{\"command\":\"$(json_escape "$cmd")\",\"exit\":$rc}"
    done < <(printf '%s\n' "$checks" | grep -o '`[^`]*`' | sed 's/^`//; s/`$//')
    # A value with no backticked command is a record mistake, such as
    # make test without backticks; running nothing would turn the checks off.
    [ -n "$checks_json" ] \
      || stop bad-record "the Base-advance checks bullet names no command in backticks; write none when the project has no checks"
    ;;
esac

echo "OK landed-since {\"pr\":$PR,\"from\":\"$FROM\",\"tip\":\"$TIP\",\"first_head\":\"$FIRST_HEAD\",\"commits\":$COUNT,\"checks\":[${checks_json#,}]}"
