#!/usr/bin/env bash
# watch-review.sh: poll a GitHub PR for automated-reviewer activity past a
# baseline, at zero model cost. The backgrounded no-model watcher from the
# await-pr-review skill (step 3). All three signal sources — submitted
# reviews, review comments (replies included, regardless of thread age),
# and PR-description reactions — are paged **until the baseline is
# crossed**, never to a fixed page ceiling: review comments walk a
# newest-first feed forward, and the ascending reviews/reactions endpoints
# walk backward from their last page (located via the connections'
# totalCounts). This watcher reads REST only, where reviews, review
# comments, and reactions all carry their author under user.login in the
# same name[bot] form, so one login matches all three sources; every signal
# counts only when dated after the baseline, except that a command request's
# whole-second creation boundary is inclusive. Artifacts present before a
# command request are snapshotted by ID, so an earlier same-second artifact
# cannot satisfy the new request. Its one write is the optional
# --request-comment, which asks a command-triggered reviewer for a pass.
#
# Usage:
#   watch-review.sh --help | -h                 # print this block, exit 0
#   watch-review.sh --pr N --baseline 2026-07-02T05:07:30Z \
#     --login chatgpt-codex-connector \   # plain or name[bot]; normalized
#     [--repo owner/name]                 # default: the repo the working
#                                         # directory belongs to. Pass it
#                                         # explicitly unless that is the
#                                         # PR's checkout: run from
#                                         # elsewhere (this script's own
#                                         # install directory, say) and the
#                                         # default resolves that repo's
#                                         # PR N instead, or no repo at all.
#     [--rest-login 'name[bot]']          # the REST login form matched
#                                         # against ALL three sources;
#                                         # default '<plain login>[bot]'.
#                                         # Set it to the plain login for a
#                                         # machine-user reviewer, which
#                                         # carries no [bot] suffix.
#                                         # (--reaction-login: deprecated
#                                         # alias, same meaning.)
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
#     [--request-comment <text>]          # command-triggered reviewer: when
#                                         # no PR comment with exactly this
#                                         # body is dated at or after
#                                         # --baseline, post
#                                         # it once and re-anchor the
#                                         # baseline to the host's creation
#                                         # time of that comment. That whole
#                                         # second is inclusive, so a response
#                                         # in the request second is visible.
#                                         # A pending request posts nothing
#                                         # and keeps --baseline. Either
#                                         # way stderr names the baseline
#                                         # the watch ran from.
#     [--request-artifacts <token>]       # token reported by an earlier
#                                         # request-comment watch. Pass it
#                                         # back when re-arming that request
#                                         # at its inclusive baseline so the
#                                         # pre-request IDs stay excluded.
#
# Successful watches print one report line on exit, tagged for the caller:
#   REVIEW_ACTIVITY <json>  reviewer review or comment in the watch window
#   CLEAN_PASS <json>       clean reaction in the window, nothing else
#   CAP_EXPIRED <json>      no reviewer activity within the cap
# A request whose post result is unknown prints the captured recovery state:
#   REQUEST_INCOMPLETE <json>  retry with its request_artifacts token
# The report is compact by design (the caller's context holds it for the
# rest of the session); the main agent refetches bodies and threads itself.
# Every report carries one PR-state field:
#   unresolved_threads  review threads whose isResolved is false, counted
#                 on the latest poll that read them (null when none did).
#                 Threads open since before the baseline count too, so a
#                 round with unresolved_threads above 0 is not clean,
#                 whatever the exit code.
# Persistent API failure surfaces as CAP_EXPIRED too: the cap is the
# backstop. Read the coverage fields in that payload before reporting the
# result; each failing poll also names its failure on stderr, followed by
# the first line of gh's own error for every query that failed.
#   last_poll_ok  the final poll scanned all three sources. Every poll
#                 rescans from the baseline, so that one scan covers the
#                 whole wait: true means "no review arrived" is sound, and
#                 false means coverage stops at some earlier poll and the
#                 tail of the wait is unobserved, whatever polls_ok says.
#   polls_ok      how many polls scanned all three sources. Only 0 is a
#                 verdict on its own: no poll ever observed the PR, so the
#                 honest report is "could not watch this PR".
#
# Exit codes: 0 review activity (or --help); 3 clean pass; 2 cap expired;
# 64 usage error; 69 gh (GitHub CLI) not found on PATH; 75 the request
# comment could not be checked or posted, nothing watched. When exit 75
# carries REQUEST_INCOMPLETE, pass its request_artifacts token on the retry.
set -u

PR="" BASELINE="" LOGIN="" REPO="" REST_LOGIN="" REACTION_LOGIN="" HEAD=""
REQUEST_COMMENT="" REQUEST_GIVEN=""
REQUEST_ARTIFACTS="" REQUEST_ARTIFACTS_GIVEN=""
BASELINE_INCLUSIVE=""
PREEXISTING_REVIEWS="" PREEXISTING_COMMENTS="" PREEXISTING_REACTIONS=""
CLEAN_CONTENT="THUMBS_UP" PROGRESS_CONTENT="EYES"
INTERVAL=75 CAP_MINUTES=25

# The header comment above is the usage text: print it on request to
# stdout (exit 0) and on a bad invocation to stderr (exit 64).
print_usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d'
}
usage() {
  print_usage >&2
  exit 64
}

# Recognize the option, then require its value, before reading $2: a
# trailing bare option must die as a usage error, not a set -u crash.
while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    -h|--help) print_usage; exit 0 ;;
    --pr|--baseline|--login|--repo|--rest-login|--reaction-login|--clean-content|--progress-content|--interval|--cap-minutes|--head|--request-comment|--request-artifacts) ;;
    *) echo "watch-review.sh: unknown option: $opt" >&2; usage ;;
  esac
  [ $# -ge 2 ] || { echo "watch-review.sh: $opt requires a value" >&2; usage; }
  val="$2"; shift 2
  case "$opt" in
    --pr) PR="$val" ;;
    --baseline) BASELINE="$val" ;;
    --login) LOGIN="$val" ;;
    --repo) REPO="$val" ;;
    --rest-login) REST_LOGIN="$val" ;;
    --reaction-login) REACTION_LOGIN="$val" ;;
    --clean-content) CLEAN_CONTENT="$val" ;;
    --progress-content) PROGRESS_CONTENT="$val" ;;
    --interval) INTERVAL="$val" ;;
    --cap-minutes) CAP_MINUTES="$val" ;;
    --head) HEAD="$val" ;;
    --request-comment) REQUEST_COMMENT="$val"; REQUEST_GIVEN=true ;;
    --request-artifacts) REQUEST_ARTIFACTS="$val"; REQUEST_ARTIFACTS_GIVEN=true ;;
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
if [ -n "$REST_LOGIN" ]; then
  case "${REST_LOGIN%\[bot\]}" in ''|*[!A-Za-z0-9-]*)
    echo "watch-review.sh: --rest-login must be a GitHub login, optionally with a [bot] suffix" >&2; usage ;;
  esac
fi
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
if [ -n "$REQUEST_GIVEN" ]; then
  case "$REQUEST_COMMENT" in *[![:space:]]*) ;; *)
    echo "watch-review.sh: --request-comment must not be blank" >&2; usage ;;
  esac
fi
if [ -n "$REQUEST_ARTIFACTS_GIVEN" ]; then
  [ -n "$REQUEST_GIVEN" ] || {
    echo "watch-review.sh: --request-artifacts requires --request-comment" >&2
    usage
  }
  if [[ "$REQUEST_ARTIFACTS" =~ ^r=([0-9]+(,[0-9]+)*)?\;c=([0-9]+(,[0-9]+)*)?\;a=([0-9]+(,[0-9]+)*)?$ ]]; then
    PREEXISTING_REVIEWS="${BASH_REMATCH[1]//,/$'\n'}"
    PREEXISTING_COMMENTS="${BASH_REMATCH[3]//,/$'\n'}"
    PREEXISTING_REACTIONS="${BASH_REMATCH[5]//,/$'\n'}"
  else
    echo "watch-review.sh: --request-artifacts must use r=ID,...;c=ID,...;a=ID,..." >&2
    usage
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

# Normalize: detection hands callers either login form (GraphQL review
# authors use the plain name, REST and reaction authors the name[bot] form).
# Strip a passed suffix so --login accepts either, then derive the single
# REST form every filter below matches on. A reviewer running as a machine
# user carries no [bot] suffix anywhere and needs an explicit --rest-login.
# --reaction-login is the former name of that flag: it never scoped to
# reactions (all three REST sources share one login), so it stays as an
# alias rather than a second, independently settable identity that a caller
# could set for reactions while reviews silently matched a different one.
LOGIN="${LOGIN%\[bot\]}"
REST_LOGIN="${REST_LOGIN:-${REACTION_LOGIN:-${LOGIN}[bot]}}"
# Preflight the host CLI: without it every poll would fail silently and
# the watcher would sit out the full cap looking like "no reviewer
# activity", when the honest answer is that this environment cannot watch
# (the skill's prose documents the fallback for a missing host CLI).
command -v gh >/dev/null 2>&1 || {
  echo "watch-review.sh: gh (GitHub CLI) not found on PATH; cannot watch — use the skill's prose fallback" >&2
  exit 69
}

# Every GitHub query runs through gh_q so a failure names its cause. The
# old retry notice listed four guesses (bad token, missing scope, rate
# limit, wrong repo) and hid which one applied; gh's own stderr says. Its
# first line is kept, labelled by query, until the next notice prints it.
# A file rather than a variable, because scans run in subshells.
ERRF=$(mktemp)
trap 'rm -f "$ERRF"' EXIT
gh_q() {
  gq_label="$1"; shift
  { gq_err=$(gh "$@" 2>&1 1>&3 3>&-); gq_rc=$?; } 3>&1
  [ "$gq_rc" -eq 0 ] && return 0
  gq_line="${gq_err%%$'\n'*}"
  echo "  $gq_label: ${gq_line:-gh exited $gq_rc with no message}" >> "$ERRF"
  return "$gq_rc"
}
notice() {
  echo "watch-review.sh: $1" >&2
  cat "$ERRF" >&2
  : > "$ERRF"
}
retrying() { notice "$1; retrying"; }

if [ -z "$REPO" ]; then
  REPO=$(gh_q "repo lookup" repo view --json nameWithOwner --jq .nameWithOwner) || {
    echo "watch-review.sh: not in a repo and no --repo given" >&2
    cat "$ERRF" >&2
    usage
  }
fi
OWNER="${REPO%%/*}" NAME="${REPO##*/}"

# A command-triggered reviewer is requested once per event, never per poll,
# and the request is the event its pass answers: the host's creation time of
# the request comment becomes the baseline (detection.md
# §event-anchored-baselines). Earlier seconds are snapshotted out; the
# request's creation second stays visible. An identical comment since the
# caller's baseline is a pending request: post nothing and keep that
# baseline. The match is at-or-after the baseline, not strictly after it:
# a re-armed wake passes the re-anchored baseline back, which is the posted
# request's own creation second, and a strict compare would post it again.
# The host's since= filter is exclusive too. Expressing the baseline with a
# +00:01 offset names an instant one minute earlier without date arithmetic,
# including when the baseline itself falls exactly on a minute boundary.
# GitHub timestamps every signal to a whole second, so a newly posted request,
# or a pending request exactly at the supplied baseline, makes that creation
# second inclusive. Otherwise a response emitted in the same second is lost
# permanently on this watch and every re-armed watch. Before a new request,
# snapshot the three reviewer artifact sources by ID. The inclusive filters
# then ignore only artifacts that provably predate the request while retaining
# new artifacts from the same second.
# The text reaches jq through $ENV, never by interpolation, so a quote in
# it cannot change the filter. Both failures exit 75 before any poll, and a
# retry is safe: a request that did post is found as pending.
if [ -n "$REQUEST_GIVEN" ]; then
  export WATCH_REQUEST_TEXT="$REQUEST_COMMENT"
  pending=$(gh_q "pending request" api \
    "repos/$OWNER/$NAME/issues/$PR/comments?since=${BASELINE%Z}%2B00:01&per_page=100" \
    --jq "[.[] | select(.body == \$ENV.WATCH_REQUEST_TEXT and .created_at >= \"$BASELINE\")] | \"\(length) \([.[] | select(.created_at == \"$BASELINE\")] | length)\"")
  read -r pending request_at_baseline <<< "$pending"
  case "${pending:-x}${request_at_baseline:-x}" in *[!0-9]*)
    notice "could not check for a pending request; nothing posted"
    exit 75 ;;
  esac
  if [ "$pending" -gt 0 ]; then
    if [ "$request_at_baseline" -gt 0 ]; then
      BASELINE_INCLUSIVE=true
      if [ -z "$REQUEST_ARTIFACTS_GIVEN" ]; then
        notice "an inclusive pending request needs its earlier --request-artifacts token; nothing watched"
        exit 75
      fi
    fi
    echo "watch-review.sh: request already pending; baseline stays $BASELINE" >&2
  else
    if [ -z "$REQUEST_ARTIFACTS_GIVEN" ]; then
      export WATCH_REST_LOGIN="$REST_LOGIN"
      export WATCH_SNAPSHOT_BASELINE="$BASELINE"
      PREEXISTING_REVIEWS=$(gh_q "pre-request reviews" api --paginate \
        "repos/$OWNER/$NAME/pulls/$PR/reviews?per_page=100" \
        --jq '.[] | select(.user.login == $ENV.WATCH_REST_LOGIN and (.submitted_at // "") >= $ENV.WATCH_SNAPSHOT_BASELINE) | .id') || {
        notice "could not snapshot pre-request reviews; nothing posted"
        exit 75
      }
      PREEXISTING_COMMENTS=$(gh_q "pre-request review comments" api --paginate \
        "repos/$OWNER/$NAME/pulls/$PR/comments?per_page=100" \
        --jq '.[] | select(.user.login == $ENV.WATCH_REST_LOGIN and .created_at >= $ENV.WATCH_SNAPSHOT_BASELINE) | .id') || {
        notice "could not snapshot pre-request review comments; nothing posted"
        exit 75
      }
      PREEXISTING_REACTIONS=$(gh_q "pre-request reactions" api --paginate \
        "repos/$OWNER/$NAME/issues/$PR/reactions?per_page=100" \
        --jq '.[] | select(.user.login == $ENV.WATCH_REST_LOGIN and .created_at >= $ENV.WATCH_SNAPSHOT_BASELINE) | .id') || {
        notice "could not snapshot pre-request reactions; nothing posted"
        exit 75
      }
      REQUEST_ARTIFACTS="r=$(printf '%s' "$PREEXISTING_REVIEWS" | tr '\n' ',');c=$(printf '%s' "$PREEXISTING_COMMENTS" | tr '\n' ',');a=$(printf '%s' "$PREEXISTING_REACTIONS" | tr '\n' ',')"
    fi
    requested=$(gh_q "request comment" api "repos/$OWNER/$NAME/issues/$PR/comments" \
      -f body="$REQUEST_COMMENT" --jq .created_at)
    case "$requested" in
      ????-??-??T??:??:??Z) case "$requested" in *[!0-9TZ:-]*) requested="" ;; esac ;;
      *) requested="" ;;
    esac
    if [ -z "$requested" ]; then
      echo "REQUEST_INCOMPLETE {\"request_artifacts\":\"$REQUEST_ARTIFACTS\"}"
      notice "request comment failed or carried no creation time; nothing watched"
      exit 75
    fi
    BASELINE="$requested"
    BASELINE_INCLUSIVE=true
    echo "watch-review.sh: requested review; baseline re-anchored to $BASELINE" >&2
  fi
fi
export WATCH_PREEXISTING_REVIEWS="$PREEXISTING_REVIEWS"
export WATCH_PREEXISTING_COMMENTS="$PREEXISTING_COMMENTS"
export WATCH_PREEXISTING_REACTIONS="$PREEXISTING_REACTIONS"
REQUEST_ARTIFACTS_REPORT=""
[ -n "$REQUEST_ARTIFACTS" ] && REQUEST_ARTIFACTS_REPORT=",\"request_artifacts\":\"$REQUEST_ARTIFACTS\""

# The loop is deadline-driven, not iteration-counted: sleeping only
# between N polls would wait (N-1) intervals, quitting short of the
# documented cap (with interval >= cap, immediately). The final poll runs
# at the deadline itself so the watcher covers the whole requested window.
DEADLINE=$(( SECONDS + CAP_MINUTES * 60 ))

# ISO-8601 UTC timestamps compare correctly as strings (the skill's
# time-not-enumeration rule). A request creation second is inclusive because
# GitHub's timestamps cannot order the request and its response within it.
# Each per-page jq line is "A B EDGE": two
# summable match counts and the page's baseline-side edge timestamp (the
# oldest item on a newest-first page, the first item on an ascending page),
# or "none" for an empty page. PENDING reviews have no submitted_at; treat
# them as not submitted. Every count is baseline-gated, the in-progress
# reaction included: reactions are mutable and one-per-user-per-emoji, so a
# leftover eyes from an earlier round would otherwise read as a review in
# progress and stretch the wait for a pass that already finished.
# With --head, a review must be of that commit, and a comment must anchor
# to it — except replies to existing threads (in_reply_to_id set), which
# keep their old anchor yet are a genuine completion signal. startswith()
# lets callers pass an abbreviated SHA.
HEAD_REVIEWS=""
HEAD_COMMENTS=""
BASELINE_OPERATOR=">"
[ -n "$BASELINE_INCLUSIVE" ] && BASELINE_OPERATOR=">="
if [ -n "$HEAD" ]; then
  HEAD_REVIEWS=" and ((.commit_id // \"\") | startswith(\"$HEAD\"))"
  HEAD_COMMENTS=" and (((.commit_id // \"\") | startswith(\"$HEAD\")) or .in_reply_to_id != null)"
fi
JQ_COMMENTS="\"\([.[] | select(.user.login == \"$REST_LOGIN\" and .created_at $BASELINE_OPERATOR \"$BASELINE\"$HEAD_COMMENTS and ((.id | tostring) as \$id | (\$ENV.WATCH_PREEXISTING_COMMENTS | split(\"\\n\") | index(\$id)) == null))] | length) 0 \(if length == 0 then \"none\" else .[-1].created_at end)\""
JQ_REVIEWS="\"\([.[] | select(.user.login == \"$REST_LOGIN\" and (.submitted_at // \"\") $BASELINE_OPERATOR \"$BASELINE\"$HEAD_REVIEWS and ((.id | tostring) as \$id | (\$ENV.WATCH_PREEXISTING_REVIEWS | split(\"\\n\") | index(\$id)) == null))] | length) 0 \(([.[] | .submitted_at // empty] | first) // \"none\")\""
# The per-poll count query also reads the first page of review threads;
# JQ_THREADS reads each later page. Both count threads whose isResolved is
# false and hand back the paging cursor.
JQ_COUNTS='.data.repository.pullRequest | "\(.reviews.totalCount) \(.reactions.totalCount) \([.reviewThreads.nodes[] | select(.isResolved == false)] | length) \(.reviewThreads.pageInfo.hasNextPage) \(.reviewThreads.pageInfo.endCursor // "none")"'
JQ_THREADS='.data.repository.pullRequest.reviewThreads | "\([.nodes[] | select(.isResolved == false)] | length) \(.pageInfo.hasNextPage) \(.pageInfo.endCursor // "none")"'
JQ_REACTIONS="\"\([.[] | select(.user.login == \"$REST_LOGIN\" and .content == \"$CLEAN_REST\" and .created_at $BASELINE_OPERATOR \"$BASELINE\" and ((.id | tostring) as \$id | (\$ENV.WATCH_PREEXISTING_REACTIONS | split(\"\\n\") | index(\$id)) == null))] | length) \([.[] | select(.user.login == \"$REST_LOGIN\" and .content == \"$PROGRESS_REST\" and .created_at $BASELINE_OPERATOR \"$BASELINE\" and ((.id | tostring) as \$id | (\$ENV.WATCH_PREEXISTING_REACTIONS | split(\"\\n\") | index(\$id)) == null))] | length) \(if length == 0 then \"none\" else .[0].created_at end)\""

# Both scanners report "t1 t2 status". A malformed page (transient API
# error, rate limit, missing scope) yields status=err: an error is not
# "zero matches", and the caller must not make an absence-based decision
# (CLEAN_PASS, or even pending) from a scan that did not actually complete.
# Positive matches remain valid evidence even from a partial scan.

# Return true while an edge remains inside the watched time window. The
# request boundary includes its creation second; ordinary event boundaries
# remain strictly after the baseline.
inside_window() {
  [[ "$1" > "$BASELINE" ]] ||
    { [ -n "$BASELINE_INCLUSIVE" ] && [ "$1" = "$BASELINE" ]; }
}

# Newest-first forward walk (review comments support direction=desc): scan
# page 1 onward, stopping once a page's oldest item crosses the baseline.
# Every item in the watched window has then been seen. Termination is
# baseline-crossing, so pages scanned track actual post-baseline activity.
scan_desc() {
  sd_url="$1"; sd_jq="$2"
  sd_a='' sd_b='' sd_edge='' sd_t1=0 sd_t2=0 sd_p=1 sd_status=ok
  while :; do
    read -r sd_a sd_b sd_edge <<< "$(gh_q "review comments" api "${sd_url}sort=created&direction=desc&per_page=100&page=${sd_p}" --jq "$sd_jq")"
    case "${sd_a}${sd_b}" in ''|*[!0-9]*) sd_status=err; break ;; esac
    sd_t1=$((sd_t1 + sd_a)); sd_t2=$((sd_t2 + sd_b))
    [ "$sd_edge" = "none" ] && break
    inside_window "$sd_edge" || break
    sd_p=$((sd_p + 1))
  done
  echo "$sd_t1 $sd_t2 $sd_status"
}

# Backward walk for ascending endpoints (reviews, reactions expose no sort
# parameter): locate the last page from the connection's totalCount, then
# walk toward page 1, stopping once a page's first (oldest) item crosses the
# baseline. The count is refreshed every poll, so an item that
# slips past the computed last page is caught on the next check.
scan_asc_tail() {
  st_url="$1"; st_jq="$2"; st_total="$3"; st_label="$4"
  st_a='' st_b='' st_edge='' st_t1=0 st_t2=0 st_status=ok
  st_p=$(( (st_total + 99) / 100 ))
  [ "$st_p" -ge 1 ] || st_p=1
  while [ "$st_p" -ge 1 ]; do
    read -r st_a st_b st_edge <<< "$(gh_q "$st_label" api "${st_url}per_page=100&page=${st_p}" --jq "$st_jq")"
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
    inside_window "$st_edge" || break
    st_p=$((st_p - 1))
  done
  echo "$st_t1 $st_t2 $st_status"
}

seen_progress=false
polls_ok=0
last_poll_ok=false
unresolved=null
while :; do
  # Every poll rescans each source from the fixed baseline (both scanners
  # restart and terminate on it), so one successful poll observes the whole
  # window from the baseline to now. Coverage therefore rests on the *last*
  # poll, not on how many succeeded: an early success followed by failures
  # leaves the tail of the wait unobserved, while a mid-run blip followed by
  # a success costs nothing. Reset per poll and report both.
  last_poll_ok=false
  read -r n_reviews n_reactions n_open more cursor <<< "$(gh_q "count query" api graphql \
    -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviews{totalCount} reactions{totalCount} reviewThreads(first:100){pageInfo{hasNextPage endCursor} nodes{isResolved}}}}}' \
    -F o="$OWNER" -F r="$NAME" -F n="$PR" --jq "$JQ_COUNTS")"
  case "${n_reviews:-x}${n_reactions:-x}${n_open:-x}" in *[!0-9]*)
    # Count query failed; retry next poll. The cap is the backstop. Say so
    # on stderr: this failure skips every scan below, so a run that fails
    # here on every poll would otherwise reach the cap in total silence and
    # read as "no review arrived" when nothing was ever observed.
    retrying "count query failed"
    n_reviews='' ;;
  esac
  # Threads past the first page are read the same way. A page that fails
  # leaves the count short, and a short count would let the caller call a
  # round clean over threads it never saw, so it fails the poll as the
  # count query does rather than reporting a low number.
  while [ -n "$n_reviews" ] && [ "$more" = true ]; do
    read -r t_open more cursor <<< "$(gh_q "thread page" api graphql \
      -f query='query($o:String!,$r:String!,$n:Int!,$c:String!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100,after:$c){pageInfo{hasNextPage endCursor} nodes{isResolved}}}}}' \
      -F o="$OWNER" -F r="$NAME" -F n="$PR" -f c="$cursor" --jq "$JQ_THREADS")"
    case "${t_open:-x}" in *[!0-9]*)
      retrying "thread page query failed"
      n_reviews=''; break ;;
    esac
    n_open=$((n_open + t_open))
  done
  if [ -n "$n_reviews" ]; then
    unresolved=$n_open
    read -r replies _ c_status <<< "$(scan_desc "repos/$OWNER/$NAME/pulls/$PR/comments?" "$JQ_COMMENTS")"
    read -r revs _ v_status <<< "$(scan_asc_tail "repos/$OWNER/$NAME/pulls/$PR/reviews?" "$JQ_REVIEWS" "$n_reviews" reviews)"
    if [ $((replies + revs)) -gt 0 ]; then
      # Positive evidence stands even if a scan later failed part-way, but
      # the failure still reaches stderr with gh's cause: exiting here
      # would otherwise leave it unread when the EXIT trap deletes the
      # file, and the caller cannot tell a complete scan from a partial one.
      [ "$c_status" = ok ] && [ "$v_status" = ok ] ||
        notice "scan failed part-way (comments=$c_status reviews=$v_status); positive evidence stands"
      echo "REVIEW_ACTIVITY {\"new_reviews\":$revs,\"new_review_comments\":$replies,\"unresolved_threads\":$unresolved$REQUEST_ARTIFACTS_REPORT}"
      exit 0
    fi
    # A clean pass is an absence-based verdict: it requires that the
    # review and comment scans actually completed with zero matches. On a
    # failed scan, skip the verdict and retry next poll; the cap backstops
    # persistent failure.
    if [ "$c_status" = ok ] && [ "$v_status" = ok ]; then
      read -r clean eyes r_status <<< "$(scan_asc_tail "repos/$OWNER/$NAME/issues/$PR/reactions?" "$JQ_REACTIONS" "$n_reactions" reactions)"
      if [ "$r_status" != ok ]; then
        retrying "reactions scan failed"
      else
        # Only now has this poll observed all three sources. Counting it
        # after the review and comment scans alone would call a run "watched"
        # while the clean-pass signal, which for some reviewers is the only
        # artifact of a clean round, was never read.
        polls_ok=$((polls_ok + 1))
        last_poll_ok=true
        if [ "$clean" -gt 0 ]; then
          echo "CLEAN_PASS {\"clean_reactions\":$clean,\"unresolved_threads\":$unresolved$REQUEST_ARTIFACTS_REPORT}"
          exit 3
        fi
      fi
      [ "$eyes" -gt 0 ] && seen_progress=true
    else
      retrying "scan failed (comments=$c_status reviews=$v_status)"
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

echo "CAP_EXPIRED {\"baseline\":\"$BASELINE\",\"cap_minutes\":$CAP_MINUTES,\"polls_ok\":$polls_ok,\"last_poll_ok\":$last_poll_ok,\"in_progress_seen\":$seen_progress,\"unresolved_threads\":$unresolved$REQUEST_ARTIFACTS_REPORT}"
exit 2
