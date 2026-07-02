#!/usr/bin/env bash
# watch-review.sh: poll a GitHub PR for automated-reviewer activity past a
# baseline, at zero model cost. The backgrounded no-model watcher from the
# await-pr-review skill (step 3). All three signal sources — submitted
# reviews, review comments (replies included, regardless of thread age),
# and PR-description reactions — are paged **until the baseline is
# crossed**, never to a fixed page ceiling: review comments walk a
# newest-first feed forward, and the ascending reviews/reactions endpoints
# walk backward from their last page (located via the connections'
# totalCounts). Authors match the reviewer's REST-style name[bot] login
# form, and every signal counts only when dated after the baseline.
#
# Usage:
#   watch-review.sh --pr N --baseline 2026-07-02T05:07:30Z \
#     --login chatgpt-codex-connector \   # plain or name[bot]; normalized
#     [--repo owner/name]                 # default: current repo
#     [--reaction-login 'name[bot]']      # default: '<plain login>[bot]';
#                                         # set for a machine-user reviewer
#     [--clean-content THUMBS_UP]         # clean-pass reaction constant
#     [--progress-content EYES]           # in-progress reaction constant
#     [--interval 75]                     # seconds between checks
#     [--cap-minutes 25]                  # total wait before giving up
#     [--head <sha>]                      # expected head (7-40 hex): only
#                                         # count reviews of this commit and
#                                         # comments anchored to it (replies
#                                         # to existing threads always
#                                         # count); omits stale passes
#                                         # against a superseded head.
#                                         # Reactions carry no commit, so
#                                         # clean-pass stays time-only.
#                                         # Best-effort: GitHub stamps a
#                                         # review with the head current at
#                                         # submission (not the head it
#                                         # analyzed) and re-anchors comment
#                                         # commit_ids as the PR advances,
#                                         # so activity racing a push can't
#                                         # be attributed reliably; the
#                                         # caller confirms which head a
#                                         # pass covered before treating it
#                                         # as the post-push round.
#
# Prints one report line on exit, tagged for the caller:
#   REVIEW_ACTIVITY <json>  reviewer review or review comment past baseline
#   CLEAN_PASS <json>       clean-pass reaction past baseline, nothing else
#   CAP_EXPIRED <json>      no reviewer activity within the cap
# The report is compact by design (the caller's context holds it for the
# rest of the session); the main agent refetches bodies and threads itself.
# Persistent API failure surfaces as CAP_EXPIRED: the cap is the backstop.
#
# Exit codes: 0 review activity; 3 clean pass; 2 cap expired; 64 usage
# error; 69 gh (GitHub CLI) not found on PATH.
set -u

PR="" BASELINE="" LOGIN="" REPO="" REACTION_LOGIN="" HEAD=""
CLEAN_CONTENT="THUMBS_UP" PROGRESS_CONTENT="EYES"
INTERVAL=75 CAP_MINUTES=25

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

# Recognize the option, then require its value, before reading $2: a
# trailing bare option must die as a usage error, not a set -u crash.
while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --pr|--baseline|--login|--repo|--reaction-login|--clean-content|--progress-content|--interval|--cap-minutes|--head) ;;
    *) echo "watch-review.sh: unknown option: $opt" >&2; usage ;;
  esac
  [ $# -ge 2 ] || { echo "watch-review.sh: $opt requires a value" >&2; usage; }
  val="$2"; shift 2
  case "$opt" in
    --pr) PR="$val" ;;
    --baseline) BASELINE="$val" ;;
    --login) LOGIN="$val" ;;
    --repo) REPO="$val" ;;
    --reaction-login) REACTION_LOGIN="$val" ;;
    --clean-content) CLEAN_CONTENT="$val" ;;
    --progress-content) PROGRESS_CONTENT="$val" ;;
    --interval) INTERVAL="$val" ;;
    --cap-minutes) CAP_MINUTES="$val" ;;
    --head) HEAD="$val" ;;
  esac
done

[ -n "$PR" ] && [ -n "$BASELINE" ] && [ -n "$LOGIN" ] || usage
# Validate every caller value that reaches a jq filter or a URL before
# interpolating it anywhere: bad values must die as usage errors, not as jq
# compile errors (silently swallowed into CAP_EXPIRED) or bash crashes.
case "$PR" in ''|*[!0-9]*|0*)
  echo "watch-review.sh: --pr must be a positive integer without leading zeros" >&2; usage ;;
esac
case "$INTERVAL" in ''|0|*[!0-9]*)
  echo "watch-review.sh: --interval must be a positive integer (seconds)" >&2; usage ;;
esac
case "$CAP_MINUTES" in ''|*[!0-9]*)
  echo "watch-review.sh: --cap-minutes must be a non-negative integer" >&2; usage ;;
esac
# Full-shape baseline check (date and time both required): a charset-only
# check would accept fragments like T00:00:00Z.
case "$BASELINE" in
  ????-??-??T??:??:??Z)
    case "$BASELINE" in *[!0-9TZ:-]*)
      echo "watch-review.sh: --baseline must be a whole-second ISO-8601 UTC timestamp (e.g. 2026-07-02T05:07:30Z)" >&2; usage ;;
    esac ;;
  *) echo "watch-review.sh: --baseline must be a whole-second ISO-8601 UTC timestamp (e.g. 2026-07-02T05:07:30Z)" >&2; usage ;;
esac
# Logins are a plain GitHub login with an optional literal [bot] suffix;
# brackets anywhere else (bad[form], a[bot]b) are malformed.
LOGIN_PLAIN="${LOGIN%\[bot\]}"
case "$LOGIN_PLAIN" in ''|*[!A-Za-z0-9-]*)
  echo "watch-review.sh: --login must be a GitHub login, optionally with a [bot] suffix" >&2; usage ;;
esac
if [ -n "$REACTION_LOGIN" ]; then
  case "${REACTION_LOGIN%\[bot\]}" in ''|*[!A-Za-z0-9-]*)
    echo "watch-review.sh: --reaction-login must be a GitHub login, optionally with a [bot] suffix" >&2; usage ;;
  esac
fi
if [ -n "$HEAD" ]; then
  # Normalize to lowercase: the API returns lowercase SHAs and startswith()
  # is case-sensitive, so an uppercase --head would silently never match.
  HEAD=$(printf '%s' "$HEAD" | tr 'A-F' 'a-f')
  case "$HEAD" in *[!0-9a-f]*)
    echo "watch-review.sh: --head must be a 7-40 char hex commit SHA" >&2; usage ;;
  esac
  if [ "${#HEAD}" -lt 7 ] || [ "${#HEAD}" -gt 40 ]; then
    echo "watch-review.sh: --head must be a 7-40 char hex commit SHA" >&2; usage
  fi
fi
if [ -n "$REPO" ]; then
  case "$REPO" in
    */*/*|*[!A-Za-z0-9._/-]*)
      echo "watch-review.sh: --repo must be owner/name" >&2; usage ;;
    ?*/?*) ;;
    *) echo "watch-review.sh: --repo must be owner/name" >&2; usage ;;
  esac
fi
# The documented interface uses GraphQL-style reaction constants; the REST
# reactions endpoint returns lowercase forms (+1, eyes, ...). Map them, and
# reject anything outside the fixed GitHub reaction set.
rest_content() {
  case "$1" in
    THUMBS_UP) echo "+1" ;;
    THUMBS_DOWN) echo "-1" ;;
    LAUGH) echo "laugh" ;;
    HOORAY) echo "hooray" ;;
    CONFUSED) echo "confused" ;;
    HEART) echo "heart" ;;
    ROCKET) echo "rocket" ;;
    EYES) echo "eyes" ;;
    *) echo "" ;;
  esac
}
CLEAN_REST=$(rest_content "$CLEAN_CONTENT")
PROGRESS_REST=$(rest_content "$PROGRESS_CONTENT")
if [ -z "$CLEAN_REST" ] || [ -z "$PROGRESS_REST" ]; then
  echo "watch-review.sh: reaction constants must be one of THUMBS_UP, THUMBS_DOWN, LAUGH, HOORAY, CONFUSED, HEART, ROCKET, EYES" >&2
  usage
fi

# Normalize: reaction-only detection hands callers the REST-style name[bot]
# form, while GraphQL review authors use the plain name. Strip a passed
# suffix so --login accepts either form, then derive the reaction form from
# the plain base. A reviewer running as a machine user (no [bot] suffix)
# needs an explicit --reaction-login.
LOGIN="${LOGIN%\[bot\]}"
REACTION_LOGIN="${REACTION_LOGIN:-${LOGIN}[bot]}"
# Preflight the host CLI: without it every poll would fail silently and
# the watcher would sit out the full cap looking like "no reviewer
# activity", when the honest answer is that this environment cannot watch
# (the skill's prose documents the fallback for a missing host CLI).
command -v gh >/dev/null 2>&1 || {
  echo "watch-review.sh: gh (GitHub CLI) not found on PATH; cannot watch — use the skill's prose fallback" >&2
  exit 69
}
if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || {
    echo "watch-review.sh: not in a repo and no --repo given" >&2; usage
  }
fi
OWNER="${REPO%%/*}" NAME="${REPO##*/}"

# The loop is deadline-driven, not iteration-counted: sleeping only
# between N polls would wait (N-1) intervals, quitting short of the
# documented cap (with interval >= cap, immediately). The final poll runs
# at the deadline itself so the watcher covers the whole requested window.
DEADLINE=$(( SECONDS + CAP_MINUTES * 60 ))

# ISO-8601 UTC timestamps compare correctly as strings (the skill's
# time-not-enumeration rule). Each per-page jq line is "A B EDGE": two
# summable match counts and the page's baseline-side edge timestamp (the
# oldest item on a newest-first page, the first item on an ascending page),
# or "none" for an empty page. PENDING reviews have no submitted_at; treat
# them as not submitted.
# With --head, a review must be of that commit, and a comment must anchor
# to it — except replies to existing threads (in_reply_to_id set), which
# keep their old anchor yet are a genuine completion signal. startswith()
# lets callers pass an abbreviated SHA.
HEAD_REVIEWS=""
HEAD_COMMENTS=""
if [ -n "$HEAD" ]; then
  HEAD_REVIEWS=" and ((.commit_id // \"\") | startswith(\"$HEAD\"))"
  HEAD_COMMENTS=" and (((.commit_id // \"\") | startswith(\"$HEAD\")) or .in_reply_to_id != null)"
fi
JQ_COMMENTS="\"\([.[] | select(.user.login == \"$REACTION_LOGIN\" and .created_at > \"$BASELINE\"$HEAD_COMMENTS)] | length) 0 \(if length == 0 then \"none\" else .[-1].created_at end)\""
JQ_REVIEWS="\"\([.[] | select(.user.login == \"$REACTION_LOGIN\" and (.submitted_at // \"\") > \"$BASELINE\"$HEAD_REVIEWS)] | length) 0 \(([.[] | .submitted_at // empty] | first) // \"none\")\""
JQ_REACTIONS="\"\([.[] | select(.user.login == \"$REACTION_LOGIN\" and .content == \"$CLEAN_REST\" and .created_at > \"$BASELINE\")] | length) \([.[] | select(.user.login == \"$REACTION_LOGIN\" and .content == \"$PROGRESS_REST\")] | length) \(if length == 0 then \"none\" else .[0].created_at end)\""

# Both scanners report "t1 t2 status". A malformed page (transient API
# error, rate limit, missing scope) yields status=err: an error is not
# "zero matches", and the caller must not make an absence-based decision
# (CLEAN_PASS, or even pending) from a scan that did not actually complete.
# Positive matches remain valid evidence even from a partial scan.

# Newest-first forward walk (review comments support direction=desc): scan
# page 1 onward, stopping once a page's oldest item is at or before the
# baseline — every post-baseline item has then been seen. Termination is
# baseline-crossing, so pages scanned track actual post-baseline activity.
scan_desc() {
  sd_url="$1"; sd_jq="$2"
  sd_a='' sd_b='' sd_edge='' sd_t1=0 sd_t2=0 sd_p=1 sd_status=ok
  while :; do
    read -r sd_a sd_b sd_edge <<< "$(gh api "${sd_url}sort=created&direction=desc&per_page=100&page=${sd_p}" --jq "$sd_jq" 2>/dev/null)"
    case "${sd_a}${sd_b}" in ''|*[!0-9]*) sd_status=err; break ;; esac
    sd_t1=$((sd_t1 + sd_a)); sd_t2=$((sd_t2 + sd_b))
    [ "$sd_edge" = "none" ] && break
    [[ "$sd_edge" > "$BASELINE" ]] || break
    sd_p=$((sd_p + 1))
  done
  echo "$sd_t1 $sd_t2 $sd_status"
}

# Backward walk for ascending endpoints (reviews, reactions expose no sort
# parameter): locate the last page from the connection's totalCount, then
# walk toward page 1, stopping once a page's first (oldest) item is at or
# before the baseline. The count is refreshed every poll, so an item that
# slips past the computed last page is caught on the next check.
scan_asc_tail() {
  st_url="$1"; st_jq="$2"; st_total="$3"
  st_a='' st_b='' st_edge='' st_t1=0 st_t2=0 st_status=ok
  st_p=$(( (st_total + 99) / 100 ))
  [ "$st_p" -ge 1 ] || st_p=1
  while [ "$st_p" -ge 1 ]; do
    read -r st_a st_b st_edge <<< "$(gh api "${st_url}per_page=100&page=${st_p}" --jq "$st_jq" 2>/dev/null)"
    case "${st_a}${st_b}" in ''|*[!0-9]*) st_status=err; break ;; esac
    st_t1=$((st_t1 + st_a)); st_t2=$((st_t2 + st_b))
    if [ "$st_edge" = "none" ]; then
      # An empty page at the top of a backward walk means the GraphQL
      # totalCount over-counted the REST collection (pending reviews and
      # removed reactions inflate it, persistently): the real items live
      # on lower pages, so keep walking. Only an empty page 1 means the
      # collection is empty.
      [ "$st_p" -le 1 ] && break
      st_p=$((st_p - 1))
      continue
    fi
    [[ "$st_edge" > "$BASELINE" ]] || break
    st_p=$((st_p - 1))
  done
  echo "$st_t1 $st_t2 $st_status"
}

seen_progress=false
while :; do
  read -r n_reviews n_reactions <<< "$(gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviews{totalCount} reactions{totalCount}}}}' \
    -F o="$OWNER" -F r="$NAME" -F n="$PR" \
    --jq '"\(.data.repository.pullRequest.reviews.totalCount) \(.data.repository.pullRequest.reactions.totalCount)"' 2>/dev/null)"
  case "${n_reviews:-x}${n_reactions:-x}" in *[!0-9]*)
    # Count query failed; retry next poll. The cap is the backstop.
    n_reviews='' ;;
  esac
  if [ -n "$n_reviews" ]; then
    read -r replies _ c_status <<< "$(scan_desc "repos/$OWNER/$NAME/pulls/$PR/comments?" "$JQ_COMMENTS")"
    read -r revs _ v_status <<< "$(scan_asc_tail "repos/$OWNER/$NAME/pulls/$PR/reviews?" "$JQ_REVIEWS" "$n_reviews")"
    if [ $((replies + revs)) -gt 0 ]; then
      # Positive evidence stands even if a scan later failed part-way.
      echo "REVIEW_ACTIVITY {\"new_reviews\":$revs,\"new_review_comments\":$replies}"
      exit 0
    fi
    # A clean pass is an absence-based verdict: it requires that the
    # review and comment scans actually completed with zero matches. On a
    # failed scan, skip the verdict and retry next poll; the cap backstops
    # persistent failure.
    if [ "$c_status" = ok ] && [ "$v_status" = ok ]; then
      read -r clean eyes r_status <<< "$(scan_asc_tail "repos/$OWNER/$NAME/issues/$PR/reactions?" "$JQ_REACTIONS" "$n_reactions")"
      if [ "$r_status" = ok ] && [ "$clean" -gt 0 ]; then
        echo "CLEAN_PASS {\"clean_reactions\":$clean}"
        exit 3
      fi
      [ "$eyes" -gt 0 ] && seen_progress=true
    else
      echo "watch-review.sh: scan failed (comments=$c_status reviews=$v_status); retrying" >&2
    fi
  fi
  remaining=$(( DEADLINE - SECONDS ))
  [ "$remaining" -gt 0 ] || break
  if [ "$remaining" -lt "$INTERVAL" ]; then
    sleep "$remaining"
  else
    sleep "$INTERVAL"
  fi
done

echo "CAP_EXPIRED {\"baseline\":\"$BASELINE\",\"cap_minutes\":$CAP_MINUTES,\"in_progress_seen\":$seen_progress}"
exit 2
