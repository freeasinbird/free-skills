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
# Without --since, the range starts at the PR's original fork point: the
# common ancestor of the default-branch parents of every commit the PR has
# ever had, which on one line is the oldest of those parents and which does
# not move as the default branch advances or the author merges it in or
# rebases. The commits come from the PR's current commit list and from the
# compare of the default branch with each force push's before-commit. A
# candidate off the default branch's first-parent line, such as a head or
# prefix another PR landed, is replaced by the parents of the commits it
# brought onto that line, read from the checkout, since a merge-in can make
# its own fork point older. A force push whose before-commit the forge no
# longer has stops original-base-unknown, and a truncated commit list is a
# lookup failure, rather than start from a later base, which would skip
# exactly the commits this read exists for.
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
#   LOOKUP_FAILED <what> <json>   a failed forge read adds "stderr", the
#                                 first 300 bytes of gh's error output
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
  local excerpt="" extra=""
  [ -s "${GH_ERR:-}" ] && excerpt=$(tr -d '\0' < "$GH_ERR" | head -c 300)
  [ -z "$excerpt" ] || extra=",\"stderr\":\"$(json_escape "$excerpt")\""
  echo "LOOKUP_FAILED $1 {\"detail\":\"$(json_escape "$2")\"$extra}"
  exit 4
}

# Forge reads keep gh's stderr here so lookup_failed can quote why a read
# failed. head, not tail: gh's summary line comes first, before any body.
# GH_OUT holds one attempt's output, so a retry never follows a failed
# attempt's partial output (a page of a paginated read, an error body).
GH_ERR=$(mktemp) || lookup_failed tmp "mktemp failed"
GH_OUT=$(mktemp) || { rm -f -- "$GH_ERR"; lookup_failed tmp "mktemp failed"; }
trap 'rm -f -- "$GH_ERR" "$GH_OUT"' EXIT
# Go's http2debug trace prints the Authorization header unredacted. Drop
# that one setting and keep any other GODEBUG setting gh may rely on.
GH_GODEBUG=$(printf '%s' "${GODEBUG:-}" | sed -E 's/(^|,)http2debug=[^,]*//g; s/^,//')
# Is the failure in GH_ERR an answer rather than a blip? gh exits 1 for
# every failure and names the HTTP status only in its stderr: gh api as
# "gh: Not Found (HTTP 404)", gh pr as "HTTP 401: Bad credentials (url)",
# and a GraphQL lookup of something absent as "GraphQL: Could not resolve
# to ...". GitHub answers a rate limit with a 403 that names it, so that
# 403 is transient.
gh_err_permanent() {
  grep -qi 'rate limit' "$GH_ERR" && return 1
  grep -qE '\(HTTP (401|403|404|422)\)|^HTTP (401|403|404|422):|^GraphQL: Could not resolve to ' "$GH_ERR"
}
# Run one forge read, keeping its stderr only when it fails, so a warning
# from a read that worked can't attach to a later failure. GH_DEBUG is set
# empty, not unset: gh falls back to the legacy DEBUG variable when
# GH_DEBUG is unset, and debug output carries headers and response bodies.
# A transient failure (a timeout, a dropped connection, truncated JSON, a
# 5xx, a rate limit) is retried after 1 s and then 2 s, so one blip
# doesn't end a batch; a permanent one fails at once. Each attempt
# overwrites GH_ERR, so lookup_failed quotes the last. A caller that
# already polls sets GH_READ_ATTEMPTS=1. Writes never come through here.
GH_READ_ATTEMPTS=3
gh_read() {
  local attempt=1 rc line
  while :; do
    GH_DEBUG= GODEBUG="$GH_GODEBUG" gh "$@" >"$GH_OUT" 2>"$GH_ERR" \
      && { : > "$GH_ERR"; cat -- "$GH_OUT"; return; }
    rc=$?
    { [ "$attempt" -lt "$GH_READ_ATTEMPTS" ] && ! gh_err_permanent; } || return "$rc"
    line=$(tr -d '\0' < "$GH_ERR" | head -n 1 | head -c 300)
    echo "${0##*/}: forge read failed (attempt $attempt of $GH_READ_ATTEMPTS): ${line:-gh exited $rc}; retrying in ${attempt}s" >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
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

DEFAULT=$(gh_read api "repos/$REPO" --jq .default_branch) \
  || lookup_failed repo "could not read $REPO's default branch"
[ -n "$DEFAULT" ] || lookup_failed repo "$REPO reported no default branch"
git fetch -q --no-tags -- "$REMOTE" "+refs/heads/$DEFAULT:refs/remotes/$REMOTE/$DEFAULT" 2>/dev/null \
  || lookup_failed base-fetch "could not fetch $DEFAULT from $REMOTE"
TIP=$(git rev-parse --verify --quiet "refs/remotes/$REMOTE/$DEFAULT^{commit}") \
  || lookup_failed base-fetch "the fetched $DEFAULT did not resolve to a commit"

# lineage_points <want> <head>: read one head's lineage as lines "C <sha>" (a
# commit off the default branch), "P <sha>" (one of its parents), "T <n>"
# (the forge's commit total), and "M <sha>" (its merge base), and print its
# fork-point candidates: the parents that are not themselves in the lineage,
# or the merge base when the lineage is empty because the head is already on
# the default branch. <want> is the commit count to expect, or empty to use
# T. A list shorter than that count is truncated, and one without <head> (or
# an empty one whose merge base isn't <head>) belongs to another head, as
# when a push lands between reads. Printing its candidates could miss the
# oldest one, so this prints "ERR <reason>" and fails instead.
lineage_points() {
  awk -v want="$1" -v head="$2" '
    function is_oid(s) { return length(s) == 40 && s !~ /[^0-9a-f]/ }
    err != "" { next }
    $1 == "T" { if (total == "") total = $2; next }
    !is_oid($2) { err = "unparseable oid \"" $2 "\""; next }
    $1 == "C" { if (!($2 in c)) { c[$2] = 1; n++ }; next }
    $1 == "P" { p[$2] = 1; next }
    $1 == "M" { if (base == "") base = $2; next }
    { err = "unexpected line \"" $1 "\"" }
    END {
      if (err != "") { print "ERR " err; exit 1 }
      if (want == "") want = total
      if (want !~ /^[0-9]+$/) { print "ERR unparseable commit count \"" want "\""; exit 1 }
      if (n + 0 < want + 0) { print "ERR the commit list is truncated: " n + 0 " of " want; exit 1 }
      if (n + 0 > want + 0) { print "ERR the commit list has " n " commits, more than the " want " reported"; exit 1 }
      if (n + 0 == 0) {
        if (base != head) { print "ERR the merge base \"" base "\" is not the head " head; exit 1 }
        print base; exit
      }
      if (!(head in c)) { print "ERR the commit list does not contain the head " head; exit 1 }
      for (s in p) if (!(s in c)) print s
    }'
}

# landing_lineage <commit>: for a commit off the fetched tip's first-parent
# line, print in lineage_points' line format the commits it brought onto
# that line: those reachable from it but not from the first parent of the
# oldest first-parent commit that contains it. A candidate that entered
# through a merge may have merged the default branch in itself, so its own
# fork point can be older than it.
landing_lineage() {
  local c="$1" entered lin
  # A hash lookup, not grep -f: BSD grep's cost is patterns times lines.
  entered=$(printf '%s\n' "$CHAIN" \
    | awk 'NR == FNR { d[$1]; next } $1 in d' <(git rev-list --ancestry-path "$c..$TIP") - \
    | tail -n 1)
  [ -n "$entered" ] || return 1
  lin=$(git rev-list --parents "$c" "^$entered^1") || return 1
  printf 'T %s\n' "$(printf '%s\n' "$lin" | grep -c .)"
  printf '%s\n' "$lin" | awk '{ print "C " $1; for (i = 2; i <= NF; i++) print "P " $i }'
}

HEADS=0
if [ -n "$SINCE" ]; then
  FROM="$SINCE"
  git cat-file -e "$FROM^{commit}" 2>/dev/null \
    || lookup_failed since "--since $FROM is not a commit in this repository; fetch it or read from the original base"
else
  fields=$(gh_read api "repos/$REPO/pulls/$PR" --jq '[.head.sha, .commits] | @tsv') \
    || lookup_failed pr-view "could not read PR $PR"
  IFS=$'\t' read -r head_oid head_count <<< "$fields"
  case "$head_oid" in *[!0-9a-f]*|'') lookup_failed pr-view "unparseable head '$head_oid'" ;; esac
  [ "${#head_oid}" -eq 40 ] || lookup_failed pr-view "unparseable head '$head_oid'"
  case "$head_count" in *[!0-9]*|'') lookup_failed pr-view "unparseable commit count '$head_count'" ;; esac
  [ "$head_count" -le 250 ] \
    || lookup_failed pr-commits "PR $PR has $head_count commits, and the forge lists at most 250 of them"
  # The REST timeline's force-push commit_id is the after-commit, so the
  # before-commits come from GraphQL. Page on pageInfo, never totalCount:
  # with the type filter, totalCount can count events the filter drops.
  before=$(gh_read api graphql --paginate -f owner="${REPO%%/*}" -f name="${REPO#*/}" -F number="$PR" -f query='
    query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          timelineItems(first: 100, after: $endCursor, itemTypes: [HEAD_REF_FORCE_PUSHED_EVENT]) {
            pageInfo { hasNextPage endCursor }
            nodes { ... on HeadRefForcePushedEvent { beforeCommit { oid } } }
          }
        }
      }
    }' --jq '.data.repository.pullRequest.timelineItems.nodes[] | select(has("beforeCommit")) | .beforeCommit.oid // "-"') \
    || lookup_failed force-pushes "could not read PR $PR's force pushes"
  before=$(printf '%s\n' "$before" | sed '/^$/d')
  pushes=0 heads=""
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    [ "$b" != "-" ] \
      || stop original-base-unknown "PR $PR was force-pushed from a commit the forge no longer has, so its original base is unknown; hand it back"
    case "$b" in *[!0-9a-f]*) lookup_failed force-pushes "unparseable before-commit '$b'" ;; esac
    [ "${#b}" -eq 40 ] || lookup_failed force-pushes "unparseable before-commit '$b'"
    pushes=$((pushes + 1)) heads+="$b"$'\n'
  done <<< "$before"
  HEADS=$((pushes + 1))

  points=""
  if [ "$head_count" -gt 0 ]; then
    got=$(gh_read api --paginate "repos/$REPO/pulls/$PR/commits?per_page=100" \
      --jq '.[] | "C \(.sha)", "P \(.parents[].sha)"') \
      || lookup_failed pr-commits "could not read PR $PR's commits"
    got=$(printf '%s\n' "$got" | lineage_points "$head_count" "$head_oid") \
      || lookup_failed pr-commits "PR $PR's commits: ${got#ERR }"
    points+="$got"$'\n'
  else
    # No commits off the default branch: the head itself is on it, and the
    # compare reports the head as its own merge base.
    heads+="$head_oid"$'\n'
  fi
  # Compare against the fetched tip, not the branch name, so every
  # candidate is reachable from the tip this run reads up to.
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    got=$(gh_read api --paginate "repos/$REPO/compare/$TIP...$h?per_page=250" \
      --jq '"T \(.total_commits)", "M \(.merge_base_commit.sha)", (.commits[] | "C \(.sha)", "P \(.parents[].sha)")') \
      || lookup_failed compare "could not read the compare of $DEFAULT with $h"
    got=$(printf '%s\n' "$got" | lineage_points "" "$h") \
      || lookup_failed compare "the compare of $DEFAULT with $h: ${got#ERR }"
    points+="$got"$'\n'
  done < <(printf '%s' "$heads" | sort -u)

  # A candidate off the fetched tip's first-parent line entered the default
  # branch through a merge, as when another PR landed a head or a prefix of
  # one, and may have merged the default branch in first. Replace it with
  # the candidates of the commits it brought onto that line until every
  # candidate is on the line. Each replacement is an ancestor, so this only
  # widens the range, and the merge base of candidates on one line is the
  # oldest of them. A parent the forge reports that isn't on the fetched
  # default branch would start the range somewhere this read can't follow.
  CHAIN=$(git rev-list --first-parent "$TIP") \
    || lookup_failed merge-base "could not list $DEFAULT's first-parent line"
  candidates=() seen="" pending=$(printf '%s' "$points" | sort -u)
  while [ -n "$pending" ]; do
    next=""
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$seen" in *"$c"*) continue ;; esac
      seen+="$c"$'\n'
      git merge-base --is-ancestor "$c" "$TIP" 2>/dev/null \
        || lookup_failed merge-base "the fork point $c is not in the fetched $DEFAULT"
      if printf '%s\n' "$CHAIN" | grep -qFx "$c"; then candidates+=("$c"); continue; fi
      got=$(landing_lineage "$c") \
        || lookup_failed merge-base "could not read where $c landed on the fetched $DEFAULT"
      got=$(printf '%s\n' "$got" | lineage_points "" "$c") \
        || lookup_failed merge-base "the landing of $c: ${got#ERR }"
      [ -n "$got" ] \
        || lookup_failed merge-base "the fork point $c has no ancestor on $DEFAULT's first-parent line"
      next+="$got"$'\n'
    done <<< "$pending"
    pending=$(printf '%s' "$next" | sed '/^$/d' | sort -u)
  done
  [ "${#candidates[@]}" -gt 0 ] \
    || stop original-base-unknown "no commit PR $PR has had has a parent on $DEFAULT, so its original base is unknown; hand it back"
  FROM=$(git merge-base --octopus "${candidates[@]}" 2>/dev/null) \
    || lookup_failed merge-base "the fork points of PR $PR have no common ancestor on $DEFAULT"
fi

COUNT=$(git rev-list --first-parent --count "$FROM..$TIP" 2>/dev/null) \
  || lookup_failed log "could not count $FROM..$TIP"
echo "landed on $DEFAULT from ${FROM:0:7} to ${TIP:0:7}: $COUNT first-parent commit(s)$([ "$HEADS" -eq 0 ] || echo " (original fork point of $HEADS head(s))")"
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

echo "OK landed-since {\"pr\":$PR,\"from\":\"$FROM\",\"tip\":\"$TIP\",\"heads\":$HEADS,\"commits\":$COUNT,\"checks\":[${checks_json#,}]}"
