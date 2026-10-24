#!/usr/bin/env bash
# list-ready.sh: the lookup half of the land-approved-prs skill. It owns the
# repository's landing lock and computes which approved PRs are ready, so no
# agent recomputes a filter or the lock by hand. The skill's prose owns the
# judgment (whether a ready PR still holds, rework, hand-back); this script
# decides nothing beyond the filters and the lock.
#
# Usage:
#   list-ready.sh --repo owner/name --run <id> [--order N,N,...]
#   list-ready.sh --repo owner/name --run <id> --pr <num> --pushed <40-hex-oid>...
#   list-ready.sh --repo owner/name --release <id>
#     [--base-remote NAME]   # override remote resolution for the repository
#
# --run       List the ready PRs and take or refresh the lock for run <id>.
#             An empty list releases the lock and ends the batch.
# --order     Land these PRs first, in this order; the rest follow by
#             approval time. A PR sequenced after an open PR that is not
#             ready is excluded with the dependency named.
# --pushed    Record a head this run pushed (a rebase or a rework) to PR
#             --pr in the run's push log and refresh the lock. Repeatable.
#             Lists nothing. A recorded head counts only for that PR, since
#             another branch can be pushed to the same commit.
# --release   Delete the lock held by run <id>: ends a batch early, or frees
#             a stale lock once the owner has confirmed the old run is gone.
#
# The landing record is read from AGENTS.md at the fetched default-branch
# tip, never from the working tree. The lock is refs/land/lock on the
# repository's remote: an orphan commit naming the run, the machine, and the
# PR in progress, whose committer date is the heartbeat. A lock held by
# another run, fresh or stale, is reported and never taken over.
#
# Last line on stdout is the machine-readable result:
#   OK <list|pushed|release> <json>
#   STOP <guard> <json>          a guard fired; the guard names are stable
#   LOOKUP_FAILED <what> <json>  a read failed; unknown is not absence; a
#                                failed forge read adds "stderr", the first
#                                300 bytes of gh's error output
# Exit codes: 0 OK; 2 STOP; 4 LOOKUP_FAILED; 64 usage error; 69 gh
# (GitHub CLI) not found on PATH.
set -u

REPO="" RUN="" RELEASE="" ORDER="" BASE_REMOTE_OPT="" PUSH_PR="" PUSHED=()

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed '$d' >&2
  exit 64
}

die_usage() { echo "list-ready.sh: $1" >&2; usage; }

while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --repo|--run|--release|--order|--pr|--pushed|--base-remote) ;;
    *) die_usage "unknown option: $opt" ;;
  esac
  [ $# -ge 2 ] || die_usage "$opt requires a value"
  val="$2"; shift 2
  case "$opt" in
    --repo) REPO="$val" ;;
    --run) RUN="$val" ;;
    --release) RELEASE="$val" ;;
    --order) ORDER="$val" ;;
    --pr) PUSH_PR="$val" ;;
    --pushed) PUSHED+=("$(printf '%s' "$val" | tr 'A-F' 'a-f')") ;;
    --base-remote) BASE_REMOTE_OPT="$val" ;;
  esac
done

case "$REPO" in
  */*/*|*[!A-Za-z0-9._/-]*) die_usage "--repo must be owner/name" ;;
  ?*/?*) ;;
  *) die_usage "--repo must be owner/name" ;;
esac
if [ -n "$RUN" ] && [ -n "$RELEASE" ]; then die_usage "--run and --release are exclusive"; fi
[ -n "$RUN$RELEASE" ] || die_usage "one of --run or --release is required"
# A run id lands in a ref's commit message and a file name, so it gets the
# narrowest shape that still holds a host-and-time id.
for id in "$RUN" "$RELEASE"; do
  [ -n "$id" ] || continue
  case "$id" in
    -*|.*|*[!A-Za-z0-9._-]*) die_usage "run ids use letters, digits, dot, underscore, and hyphen, and start with a letter or digit" ;;
  esac
  [ "${#id}" -le 64 ] || die_usage "run ids are at most 64 characters"
done
if [ -n "$RELEASE" ] && { [ -n "$ORDER" ] || [ "${#PUSHED[@]}" -gt 0 ]; }; then
  die_usage "--release takes no --order or --pushed"
fi
if [ -n "$ORDER" ] && [ "${#PUSHED[@]}" -gt 0 ]; then
  die_usage "--pushed lists nothing, so it takes no --order"
fi
if [ -n "$ORDER" ]; then
  case ",$ORDER," in
    *,,*|*,0*|*[!0-9,]*) die_usage "--order must be comma-separated PR numbers without leading zeros" ;;
  esac
fi
if [ "${#PUSHED[@]}" -gt 0 ] || [ -n "$PUSH_PR" ]; then
  [ "${#PUSHED[@]}" -gt 0 ] && [ -n "$PUSH_PR" ] \
    || die_usage "--pushed and --pr go together: name the PR each pushed head belongs to"
  case "$PUSH_PR" in 0*|*[!0-9]*) die_usage "--pr must be a PR number without leading zeros" ;; esac
fi
for p in ${PUSHED[@]+"${PUSHED[@]}"}; do
  case "$p" in *[!0-9a-f]*|'') die_usage "--pushed must be a full 40-hex commit OID" ;; esac
  [ "${#p}" -eq 40 ] || die_usage "--pushed must be a full 40-hex commit OID"
done
case "$BASE_REMOTE_OPT" in -*) die_usage "remote names must not begin with a hyphen" ;; esac

command -v gh >/dev/null 2>&1 || {
  echo "list-ready.sh: gh (GitHub CLI) not found on PATH; the skill needs an authenticated forge CLI, so stop and hand the batch to the owner" >&2
  exit 69
}

# --- reporting -------------------------------------------------------------

# Control bytes encode as \u00XX and every other byte passes through, so a
# UTF-8 branch name or label stays itself and the result line stays valid
# JSON.
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
stop() { # stop <guard> <detail> [extra-json-fields]
  echo "STOP $1 {\"detail\":\"$(json_escape "$2")\"${3:+,$3}}"
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
# GH_OUT holds one attempt's output, so a retry never follows a failed
# attempt's partial output (a page of a paginated read, an error body).
GH_ERR=$(mktemp) || lookup_failed tmp "mktemp failed"
GH_OUT=$(mktemp) || { rm -f -- "$GH_ERR"; lookup_failed tmp "mktemp failed"; }
trap 'rm -f -- "$GH_ERR" "$GH_OUT"' EXIT
# Go's http2debug trace prints the Authorization header unredacted. Drop
# that one setting and keep any other GODEBUG setting gh may rely on. Go
# turns the trace on when GODEBUG merely contains http2debug=1 or =2, so
# drop every element that mentions it, however it is spaced or nested.
GH_GODEBUG=$(printf '%s' "${GODEBUG:-}" | sed -E 's/(^|,)[^,]*http2debug[^,]*//g; s/^,//')
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

# --- repository and record -------------------------------------------------

GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null) \
  || stop not-a-repo "run from a checkout of $REPO"
GIT_COMMON=$(cd "$GIT_COMMON" && pwd -P)

# Whether a URL names the repository: it ends in /owner/name or
# :owner/name, ignoring case, a trailing slash, and .git.
# The host is deliberately unchecked: remotes here use SSH host aliases,
# so any host serving owner/name passes, and land.sh resolves aliases
# before it pushes or merges.
url_names_repo() { # url_names_repo <url>
  local want url
  want=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')
  url=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  url="${url%/}"; url="${url%.git}"
  case "$url" in */"$want"|*:"$want") return 0 ;; esac
  return 1
}
# Whether a remote's fetch URL and every push URL name the repository. The
# lock is read from the fetch side but written to the push side, so a
# pushurl aimed at a fork would hide this run's lock from other landers.
remote_names_repo() { # remote_names_repo <remote>
  local url pushes u
  url=$(git remote get-url -- "$1" 2>/dev/null) || return 1
  url_names_repo "$url" || return 1
  pushes=$(git remote get-url --push --all -- "$1" 2>/dev/null) || return 1
  [ -n "$pushes" ] || return 1
  while IFS= read -r u; do
    url_names_repo "$u" || return 1
  done <<< "$pushes"
}
# The remote whose URLs name the repository. Two matches are refused rather
# than guessed: the lock must live on exactly one server.
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
# sibling remote would serve its own lock and landing record while the forge
# calls still read $REPO.
if [ -n "$BASE_REMOTE_OPT" ]; then
  git remote get-url -- "$BASE_REMOTE_OPT" >/dev/null 2>&1 \
    || stop remote-unresolved "no remote named $BASE_REMOTE_OPT"
  remote_names_repo "$BASE_REMOTE_OPT" \
    || stop remote-repo-mismatch "remote $BASE_REMOTE_OPT's fetch or push URL does not name $REPO"
  REMOTE="$BASE_REMOTE_OPT"
else
  resolve_remote
fi

DEFAULT=$(gh_read api "repos/$REPO" --jq .default_branch) \
  || lookup_failed repo "could not read $REPO's default branch"
[ -n "$DEFAULT" ] || lookup_failed repo "$REPO reported no default branch"
git fetch -q --no-tags -- "$REMOTE" "+refs/heads/$DEFAULT:refs/remotes/$REMOTE/$DEFAULT" 2>/dev/null \
  || lookup_failed base-fetch "could not fetch $DEFAULT from $REMOTE"

# The record is the run of "  - **Key:** value" bullets that starts at the
# Mechanism bullet, with four-space continuation lines joined on. Prints
# "key<TAB>value" per bullet.
record_lines() {
  awk '
    !started && /^  - \*\*Mechanism:\*\* / { started = 1 }
    !started { next }
    /^  - \*\*[^*]+:\*\* / {
      if (key != "") print key "\t" val
      line = $0; sub(/^  - \*\*/, "", line)
      key = line; sub(/:\*\*.*$/, "", key)
      val = line; sub(/^[^*]+:\*\* /, "", val)
      next
    }
    /^    [^ ]/ && key != "" { line = $0; sub(/^ +/, "", line); val = val " " line; next }
    { exit }
    END { if (key != "") print key "\t" val }
  '
}
AGENTS_TEXT=$(git show "refs/remotes/$REMOTE/$DEFAULT:AGENTS.md" 2>/dev/null) \
  || stop no-landing-record "AGENTS.md is missing at $DEFAULT's tip, so there is no landing record"
RECORD=$(printf '%s\n' "$AGENTS_TEXT" | record_lines)
[ -n "$RECORD" ] || stop no-landing-record "AGENTS.md at $DEFAULT's tip has no landing record (no Mechanism bullet)"

# Repository roles from lowest to highest. The approval label counts when
# its actor's role is at or above the recorded Approver permission.
permission_rank() { # permission_rank <role>: -1 for a role outside the order
  case "$1" in admin) echo 4 ;; maintain) echo 3 ;; write) echo 2 ;; triage) echo 1 ;; read) echo 0 ;; *) echo -1 ;; esac
}

record_value() { printf '%s\n' "$RECORD" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'; }
first_span() { printf '%s' "$1" | sed -n 's/^[^`]*`\([^`]*\)`.*$/\1/p'; }
record_span() { first_span "$(record_value "$1")"; }

MECHANISM=$(record_span Mechanism)
[ "$MECHANISM" = label ] \
  || stop unsupported-mechanism "the landing record's mechanism is '${MECHANISM:-missing}'; this version lands only the label mechanism"
APPROVAL=$(record_span Approval)
HANDBACK=$(record_span Hand-back)
PERMISSION=$(record_span "Approver permission")
[ -n "$APPROVAL" ] && [ -n "$HANDBACK" ] && [ -n "$PERMISSION" ] \
  || stop bad-record "the landing record needs Approval, Hand-back, and Approver permission values in backticks; a record naming one Approver login predates this version"
PERMISSION_RANK=$(permission_rank "$PERMISSION")
[ "$PERMISSION_RANK" -ge 2 ] \
  || stop bad-record "Approver permission '$PERMISSION' is not write, maintain, or admin"
# A bullet present without a backticked value is a mistake, not a request
# for the default.
STALE_MINUTES=$(record_span "Stale lock age")
[ -n "$STALE_MINUTES" ] || [ -z "$(record_value "Stale lock age")" ] \
  || stop bad-record "Stale lock age needs its minutes in backticks"
STALE_MINUTES="${STALE_MINUTES:-240}"
case "$STALE_MINUTES" in ''|0*|*[!0-9]*) stop bad-record "Stale lock age must be a positive number of minutes" ;; esac
[ "${#STALE_MINUTES}" -le 6 ] || stop bad-record "Stale lock age is beyond any useful wait"
# Logins and the marker reach a jq program as string literals, so they get a
# shape that needs no escaping there.
# Reviewer has no default: a missing or unparsed bullet would otherwise
# turn filter 6 off without anyone choosing that.
REVIEWER=$(record_span Reviewer)
[ -n "$REVIEWER" ] \
  || stop bad-record "the landing record needs a Reviewer value in backticks, \`none\` when the project records no reviewer"
MARKER=""
if [ "$REVIEWER" != none ]; then
  case "$REVIEWER" in *[!A-Za-z0-9-]*) stop bad-record "Reviewer '$REVIEWER' is not a GitHub login (omit any [bot] suffix)" ;; esac
  MARKER=$(record_span "Reviewer completion marker")
  case "$MARKER" in ''|*[!A-Za-z0-9._-]*) stop bad-record "a recorded Reviewer needs a Reviewer completion marker of letters, digits, dot, underscore, or hyphen" ;; esac
fi

PUSHLOG_DIR="$GIT_COMMON/land-approved-prs"

# --- the lock ---------------------------------------------------------------

LOCK_REF=refs/land/lock
LOCK_OID="" LOCK_RUN="" LOCK_HOST="" LOCK_PR="" LOCK_AGE=0

read_lock() {
  local out msg ct got
  out=$(git ls-remote -- "$REMOTE" "$LOCK_REF" 2>/dev/null) \
    || lookup_failed lock-read "could not read $LOCK_REF from $REMOTE"
  LOCK_OID=$(printf '%s\n' "$out" | awk -F'\t' -v r="$LOCK_REF" '$2 == r { print $1 }')
  LOCK_RUN="" LOCK_HOST="" LOCK_PR="" LOCK_AGE=0
  [ -n "$LOCK_OID" ] || return 0
  git fetch -q --no-tags -- "$REMOTE" "+$LOCK_REF:refs/land/seen-lock" 2>/dev/null \
    || lookup_failed lock-read "could not fetch $LOCK_REF from $REMOTE"
  got=$(git rev-parse --verify --quiet refs/land/seen-lock) || got=""
  git update-ref -d refs/land/seen-lock 2>/dev/null
  [ "$got" = "$LOCK_OID" ] \
    || lookup_failed lock-read "$LOCK_REF moved while it was read; list again"
  msg=$(git log -1 --format=%B "$LOCK_OID" 2>/dev/null) \
    || lookup_failed lock-read "could not read the lock commit $LOCK_OID"
  ct=$(git log -1 --format=%ct "$LOCK_OID" 2>/dev/null) \
    || lookup_failed lock-read "could not read the lock commit's date"
  LOCK_RUN=$(printf '%s\n' "$msg" | sed -n 's/^run: //p' | head -n 1)
  LOCK_HOST=$(printf '%s\n' "$msg" | sed -n 's/^host: //p' | head -n 1)
  LOCK_PR=$(printf '%s\n' "$msg" | sed -n 's/^pr: //p' | head -n 1)
  LOCK_AGE=$(( ($(date +%s) - ct) / 60 ))
  [ "$LOCK_AGE" -ge 0 ] || LOCK_AGE=0
}

lock_fields() {
  printf '"run":"%s","host":"%s","pr":"%s","age_minutes":%s,"stale_minutes":%s' \
    "$(json_escape "$LOCK_RUN")" "$(json_escape "$LOCK_HOST")" \
    "$(json_escape "$LOCK_PR")" "$LOCK_AGE" "$STALE_MINUTES"
}

# Another run's lock is never taken: a stale heartbeat means the run is
# suspected dead, not known dead, and its land may still be waiting on CI.
refuse_foreign_lock() {
  [ -n "$LOCK_OID" ] || return 0
  [ "$LOCK_RUN" != "$1" ] || return 0
  if [ "$LOCK_AGE" -ge "$STALE_MINUTES" ]; then
    stop lock-stale "run '$LOCK_RUN' on $LOCK_HOST holds $LOCK_REF with a heartbeat $LOCK_AGE minutes old, past the $STALE_MINUTES-minute stale age; once the owner confirms that session and any land it started are gone, release it with --release $LOCK_RUN" "$(lock_fields)"
  fi
  stop lock-held "run '$LOCK_RUN' on $LOCK_HOST holds $LOCK_REF (heartbeat $LOCK_AGE minutes ago, PR ${LOCK_PR:-none}); one lander per repository" "$(lock_fields)"
}

lock_commit() { # lock_commit <run> <pr>: prints the new lock commit
  local tree
  tree=$(git mktree < /dev/null) || return 1
  printf 'land lock\n\nrun: %s\nhost: %s\npr: %s\n' "$1" "$(hostname 2>/dev/null || echo unknown)" "$2" \
    | GIT_AUTHOR_NAME=land-approved-prs GIT_AUTHOR_EMAIL=land-approved-prs@localhost \
      GIT_COMMITTER_NAME=land-approved-prs GIT_COMMITTER_EMAIL=land-approved-prs@localhost \
      git commit-tree "$tree"
}

# A lease that expects the ref absent succeeds for exactly one lander; one
# that expects the previous OID fails if anyone else moved it.
lock_push() { # lock_push <refspec> <expected-oid-or-empty>
  git push --quiet --force-with-lease="$LOCK_REF:$2" -- "$REMOTE" "$1" >/dev/null 2>&1
}

lock_push_or_stop() { # lock_push_or_stop <refspec> <expected> <what>
  lock_push "$1" "$2" && return 0
  local expected="$2"
  read_lock
  if [ "$LOCK_OID" != "$expected" ]; then
    [ -z "$LOCK_OID" ] || [ "$LOCK_RUN" = "$RUN$RELEASE" ] || refuse_foreign_lock "$RUN$RELEASE"
    stop lock-lost "$LOCK_REF changed while this run was $3 it; another lander or the owner moved it" "$(lock_fields)"
  fi
  lookup_failed lock-push "could not push $LOCK_REF to $REMOTE while $3 it"
}

# Leaves LOCK_STATE as acquired or refreshed.
hold_lock() { # hold_lock <pr-in-progress>
  local new
  new=$(lock_commit "$RUN" "$1") || lookup_failed lock-commit "could not create the lock commit"
  if [ -z "$LOCK_OID" ]; then
    lock_push_or_stop "$new:$LOCK_REF" "" acquiring
    LOCK_STATE=acquired
  else
    lock_push_or_stop "$new:$LOCK_REF" "$LOCK_OID" refreshing
    LOCK_STATE=refreshed
  fi
  LOCK_OID="$new"
}

release_lock() { # release_lock <run>
  if [ -n "$LOCK_OID" ]; then
    lock_push_or_stop ":$LOCK_REF" "$LOCK_OID" releasing
    LOCK_STATE=released
  else
    LOCK_STATE=absent
  fi
  rm -f -- "$PUSHLOG_DIR/pushed-$1"
}

# --- release and push-log modes ----------------------------------------------

read_lock

if [ -n "$RELEASE" ]; then
  if [ -n "$LOCK_OID" ] && [ "$LOCK_RUN" != "$RELEASE" ]; then
    stop lock-held "$LOCK_REF is held by run '$LOCK_RUN', not '$RELEASE'; nothing was released" "$(lock_fields)"
  fi
  release_lock "$RELEASE"
  echo "lock: $LOCK_STATE $LOCK_REF for run $RELEASE"
  echo "OK release {\"run\":\"$RELEASE\",\"lock\":\"$LOCK_STATE\"}"
  exit 0
fi

refuse_foreign_lock "$RUN"

if [ "${#PUSHED[@]}" -gt 0 ]; then
  # A push without the lock means this run lost it; recording the head
  # would let filter 4 accept a push no lock covered.
  [ -n "$LOCK_OID" ] \
    || stop lock-not-held "run '$RUN' holds no lock, so its push cannot be recorded; list first"
  mkdir -p -- "$PUSHLOG_DIR" || lookup_failed push-log "could not create $PUSHLOG_DIR"
  for p in "${PUSHED[@]}"; do printf '%s %s\n' "$PUSH_PR" "$p"; done >> "$PUSHLOG_DIR/pushed-$RUN" \
    || lookup_failed push-log "could not write the push log"
  hold_lock "$LOCK_PR"
  list=""
  for p in "${PUSHED[@]}"; do list+=",\"$p\""; done
  echo "recorded ${#PUSHED[@]} pushed head(s) of PR $PUSH_PR for run $RUN; lock $LOCK_STATE"
  echo "OK pushed {\"run\":\"$RUN\",\"pr\":$PUSH_PR,\"pushed\":[${list#,}],\"lock\":\"$LOCK_STATE\"}"
  exit 0
fi

# --- readiness filters -------------------------------------------------------

pushed_by_run() { # pushed_by_run <pr> <oid>
  [ -f "$PUSHLOG_DIR/pushed-$RUN" ] && grep -qxF -- "$1 $2" "$PUSHLOG_DIR/pushed-$RUN"
}

US=$'\037'
has_label() { case "$US$2$US" in *"$US$1$US"*) return 0 ;; esac; return 1; }

OWNER="${REPO%%/*}" NAME="${REPO#*/}"
REPO_LC=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')

open_threads() { # open_threads <pr>: prints the unresolved thread count
  local q n more cursor t_open total
  q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){pageInfo{hasNextPage endCursor} nodes{isResolved}}}}}'
  read -r n more cursor <<< "$(gh_read api graphql -f query="$q" -F o="$OWNER" -F r="$NAME" -F n="$1" \
    --jq '.data.repository.pullRequest.reviewThreads | "\([.nodes[] | select(.isResolved == false)] | length) \(.pageInfo.hasNextPage) \(.pageInfo.endCursor // "none")"')"
  case "${n:-x}" in *[!0-9]*) return 1 ;; esac
  total="$n"
  q='query($o:String!,$r:String!,$n:Int!,$c:String!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100,after:$c){pageInfo{hasNextPage endCursor} nodes{isResolved}}}}}'
  while [ "$more" = true ]; do
    read -r t_open more cursor <<< "$(gh_read api graphql -f query="$q" -F o="$OWNER" -F r="$NAME" -F n="$1" -f c="$cursor" \
      --jq '.data.repository.pullRequest.reviewThreads | "\([.nodes[] | select(.isResolved == false)] | length) \(.pageInfo.hasNextPage) \(.pageInfo.endCursor // "none")"')"
    case "${t_open:-x}" in *[!0-9]*) return 1 ;; esac
    total=$((total + t_open))
  done
  echo "$total"
}

TMPD=$(mktemp -d) || lookup_failed tmp "mktemp failed"
# This replaces the EXIT trap that removes GH_ERR and GH_OUT, so it
# removes all three.
trap 'rm -rf "$TMPD" "$GH_ERR" "$GH_OUT"' EXIT

gh_read pr list --repo "$REPO" --state open --limit 1000 \
  --json number,isDraft,baseRefName,headRefName,headRefOid,isCrossRepository,createdAt,labels \
  --jq '.[] | [(.number|tostring), (.isDraft|tostring), .baseRefName, .headRefName, .headRefOid, (.isCrossRepository|tostring), .createdAt, ([.labels[].name] | join("\u001f"))] | @tsv' \
  > "$TMPD/prs" \
  || lookup_failed pr-list "could not list $REPO's open PRs"

: > "$TMPD/ready"; : > "$TMPD/excluded"; : > "$TMPD/open"

exclude() { # exclude <pr> <filter> <detail>
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$TMPD/excluded"
}

# The role an actor holds on the repository, read once per actor into ROLE.
# role_name carries the fine-grained role (maintain and triage included, or
# an organization's custom role). A custom role is outside the order, so its
# base role is taken from the user.permissions flags; the legacy permission
# field maps maintain to write and triage to read, so it is only the last
# resort. A user who isn't a collaborator reads as none, not as a failure.
actor_role() { # actor_role <login>: sets ROLE
  local cache="$TMPD/role-$1" encoded out perm name
  [[ "$1" =~ ^[][A-Za-z0-9_-]+$ ]] || { ROLE=none; return; }
  if [ ! -f "$cache" ]; then
    encoded=$(printf '%s' "$1" | sed 's/\[/%5B/g; s/\]/%5D/g')
    out=$(gh_read api "repos/$REPO/collaborators/$encoded/permission" \
      --jq '[((.user.permissions // {}) | if .admin then "admin"
               elif .maintain then "maintain" elif .push then "write"
               elif .triage then "triage" elif .pull then "read"
               else null end) // .permission // "none",
             (.role_name // "")] | @tsv') \
      || lookup_failed permission "could not read $1's permission on $REPO"
    IFS=$'\t' read -r perm name <<< "$out"
    [ "$(permission_rank "$name")" -ge 0 ] || name="$perm"
    printf '%s\n' "$name" > "$cache"
  fi
  ROLE=$(cat "$cache")
}

# Sets REASON_FILTER and REASON on exclusion, APPROVED_AT on readiness.
# Cheap filters first (1, 2, 3, 7 from the listing), then the reads.
evaluate() { # evaluate <num> <draft> <base> <head> <oid> <cross> <created> <labels>
  local num="$1" draft="$2" base="$3" head="$4" oid="$5" cross="$6" created="$7" labels="$8"
  local events kind at name actor sha t="" t_actor="" h0="" h0_at="" runs line n_open sums s
  REASON_FILTER="" REASON="" APPROVED_AT=""
  if [ "$draft" = true ]; then REASON_FILTER=1 REASON="draft"; return; fi
  if [ "$base" != "$DEFAULT" ]; then REASON_FILTER=2 REASON="targets $base, not $DEFAULT"; return; fi
  if ! has_label "$APPROVAL" "$labels"; then REASON_FILTER=3 REASON="no $APPROVAL label"; return; fi
  if has_label "$HANDBACK" "$labels"; then REASON_FILTER=3 REASON="carries $HANDBACK"; return; fi
  if [ "$cross" = true ]; then REASON_FILTER=7 REASON="head branch is in another repository"; return; fi
  case "$oid" in *[!0-9a-f]*|'') lookup_failed pr-list "PR $num reported head '$oid'" ;; esac
  [ "${#oid}" -eq 40 ] || lookup_failed pr-list "PR $num reported head '$oid'"

  events=$(gh_read api --paginate "repos/$REPO/issues/$num/timeline?per_page=100" \
    --jq '.[] | select(.event == "labeled" or .event == "head_ref_force_pushed") | [.event, .created_at, (.label.name // "-"), (.actor.login // "-"), (.commit_id // "-")] | @tsv') \
    || lookup_failed timeline "could not read PR $num's timeline"
  : > "$TMPD/evidence"
  while IFS=$'\t' read -r kind at name actor sha; do
    [ -n "$kind" ] || continue
    if [ "$kind" = labeled ] && [ "$name" = "$APPROVAL" ]; then
      if [ -z "$t" ] || [[ ! "$at" < "$t" ]]; then t="$at" t_actor="$actor"; fi
    elif [ "$kind" = head_ref_force_pushed ]; then
      printf '%s\t%s\tforce-push\n' "$at" "$sha" >> "$TMPD/evidence"
    fi
  done <<< "$events"
  if [ -z "$t" ]; then REASON_FILTER=3 REASON="no labeled event for $APPROVAL in the timeline"; return; fi
  actor_role "$t_actor"
  if [ "$(permission_rank "$ROLE")" -lt "$PERMISSION_RANK" ]; then
    REASON_FILTER=3 REASON="$APPROVAL was last added by $t_actor, whose repository permission is $ROLE, below the recorded $PERMISSION"; return
  fi

  # Filter 4. A pull_request run created before the PR existed belongs to
  # an earlier PR that reused the branch name, and one whose head lives in
  # another repository belongs to a fork's PR from a same-named branch.
  runs=$(gh_read api -X GET --paginate "repos/$REPO/actions/runs" -f event=pull_request \
    -f branch="$head" -f per_page=100 \
    --jq ".workflow_runs[] | select((.head_repository.full_name // \"\" | ascii_downcase) == \"$REPO_LC\") | [.created_at, .head_sha] | @tsv") \
    || lookup_failed actions-runs "could not read PR $num's CI runs"
  while IFS=$'\t' read -r at sha; do
    [ -n "$at" ] || continue
    [[ "$at" < "$created" ]] && continue
    printf '%s\t%s\tci-run\n' "$at" "$sha" >> "$TMPD/evidence"
  done <<< "$runs"
  # H0 is the newest evidence at or before T. After T, a force-push this
  # run didn't make is another actor's, even when the head later returns
  # to H0; this run's own rebase is the force-push that stays eligible.
  while IFS=$'\t' read -r at sha kind; do
    if [[ "$at" > "$t" ]]; then
      if [ "$kind" = force-push ] && ! pushed_by_run "$num" "$sha"; then
        REASON_FILTER=4 REASON="force-push to $sha at $at, after approval at $t, was not pushed by this run"; return
      fi
    else
      h0="$sha" h0_at="$at"
    fi
  done < <(sort -t $'\t' -k1,1 "$TMPD/evidence")
  if [ -z "$h0" ]; then
    REASON_FILTER=4 REASON="no CI run or force-push at or before approval at $t, so the approved head is unknown"; return
  fi
  if [ "$oid" != "$h0" ] && ! pushed_by_run "$num" "$oid"; then
    REASON_FILTER=4 REASON="head $oid is neither the approved head $h0 (seen $h0_at, approval $t) nor a head this run pushed"; return
  fi

  n_open=$(open_threads "$num") || lookup_failed review-threads "could not read PR $num's review threads"
  if [ "$n_open" -gt 0 ]; then REASON_FILTER=5 REASON="$n_open unresolved review thread(s)"; return; fi

  if [ "$REVIEWER" != none ]; then
    sums=$(gh_read api --paginate "repos/$REPO/issues/$num/comments?per_page=100" \
      --jq ".[] | select(.user.type == \"Bot\" and (.user.login == \"$REVIEWER\" or .user.login == \"${REVIEWER}[bot]\") and (.body | contains(\"$MARKER\"))) | .body | split(\"\\n\")[] | select(contains(\"**Completed**\") and test(\"\`[0-9a-f]{7,40}\`\")) | capture(\"\`(?<sha>[0-9a-f]{7,40})\`\").sha") \
      || lookup_failed reviewer "could not read PR $num's comments for the reviewer's summary"
    local done_on_head=false
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      case "$oid" in "$s"*) done_on_head=true ;; esac
    done <<< "$sums"
    if [ "$done_on_head" = false ]; then
      REASON_FILTER=6 REASON="$REVIEWER has no completed round on head ${oid:0:7}"; return
    fi
  fi
  APPROVED_AT="$t"
}

while IFS=$'\t' read -r num draft base head oid cross created labels; do
  [ -n "$num" ] || continue
  echo "$num" >> "$TMPD/open"
  evaluate "$num" "$draft" "$base" "$head" "$oid" "$cross" "$created" "${labels:-}"
  if [ -n "$REASON_FILTER" ]; then
    exclude "$num" "$REASON_FILTER" "$REASON"
  else
    printf '%s\t%s\t%s\t%s\n' "$APPROVED_AT" "$num" "$oid" "$head" >> "$TMPD/ready"
  fi
done < "$TMPD/prs"

# Oldest approval first; a typed order goes ahead of it. An ordered PR that
# is open but not ready holds back every ordered PR after it.
sort -t $'\t' -k1,1 -k2,2n "$TMPD/ready" > "$TMPD/by-approval"
: > "$TMPD/final"
blocker=""
if [ -n "$ORDER" ]; then
  IFS=, read -r -a ordered <<< "$ORDER"
  seen=","
  for n in "${ordered[@]}"; do
    case "$seen" in *",$n,"*) continue ;; esac
    seen+="$n,"
    line=$(awk -F'\t' -v n="$n" '$2 == n' "$TMPD/by-approval")
    if [ -n "$blocker" ] && [ -n "$line" ]; then
      exclude "$n" order "sequenced after #$blocker, which is not ready"
    elif [ -n "$line" ]; then
      printf '%s\n' "$line" >> "$TMPD/final"
    elif grep -qxF -- "$n" "$TMPD/open"; then
      blocker="${blocker:-$n}"
    else
      echo "note: ordered #$n is not an open PR; skipped"
    fi
  done
  awk -F'\t' -v o=",$ORDER," 'index(o, "," $2 ",") == 0' "$TMPD/by-approval" >> "$TMPD/final"
else
  cp "$TMPD/by-approval" "$TMPD/final"
fi

FIRST=$(awk -F'\t' 'NR == 1 { print $2 }' "$TMPD/final")
if [ -n "$FIRST" ]; then
  hold_lock "$FIRST"
else
  release_lock "$RUN"
fi

echo "landing record: $MECHANISM mechanism, $APPROVAL by $PERMISSION or higher, hand-back $HANDBACK, reviewer $REVIEWER, stale lock age $STALE_MINUTES minutes"
ready_json="" excluded_json=""
echo "ready:"
while IFS=$'\t' read -r at num oid head; do
  [ -n "$num" ] || continue
  echo "  #$num $head head ${oid:0:7}, approved $at"
  ready_json+=",{\"number\":$num,\"head_oid\":\"$oid\",\"head_branch\":\"$(json_escape "$head")\",\"approved_at\":\"$at\"}"
done < "$TMPD/final"
[ -n "$ready_json" ] || echo "  (none)"
echo "excluded:"
while IFS=$'\t' read -r num filter detail; do
  [ -n "$num" ] || continue
  echo "  #$num filter $filter: $detail"
  excluded_json+=",{\"number\":$num,\"filter\":\"$filter\",\"detail\":\"$(json_escape "$detail")\"}"
done < <(sort -t $'\t' -k1,1n "$TMPD/excluded")
[ -n "$excluded_json" ] || echo "  (none)"
echo "lock: $LOCK_STATE $LOCK_REF for run $RUN${FIRST:+ (PR $FIRST)}"
echo "OK list {\"run\":\"$RUN\",\"lock\":\"$LOCK_STATE\",\"ready\":[${ready_json#,}],\"excluded\":[${excluded_json#,}]}"
