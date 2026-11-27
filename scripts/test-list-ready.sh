#!/usr/bin/env bash
# Regression matrix for land-approved-prs' list-ready.sh. Offline and
# deterministic: a PATH shim replaces gh, serving canned JSON per endpoint
# through the caller's own --jq filter (so a wrong field name fails a test
# rather than silently matching nothing), while git runs for real against a
# bare scratch remote, where the lock ref is pushed, leased, and deleted.
#
# Covers each readiness filter's pass and fail, the lock's acquire, refuse,
# heartbeat, release, and stale report, and the transitions the work
# contract names (issue #307).
#
# Set LIST_READY_SCRIPT to test a different copy of the script.
set -u

SCRIPT="${LIST_READY_SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/skills/land-approved-prs/list-ready.sh}"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Run from scratch, outside any repository: a git -C "$var" whose var came
# back empty then fails instead of acting on the checkout this runs from.
cd "$TMP" || exit 1
DEAD="$TMP/dead"; FIX="$TMP/fix"; SHIMD="$TMP/shim"
mkdir -p "$DEAD" "$FIX" "$SHIMD"
printf '#!/bin/sh\nexit 1\n' > "$DEAD/gh"
chmod +x "$DEAD/gh"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

pass=0; fail=0; skip=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*" >&2; }

# A scratch remote whose path ends in owner/name, so remote resolution
# finds it by URL, and a working clone to run from.
SRV="$TMP/srv/owner/name.git"
WORK="$TMP/work"

RECORD_DEFAULT='  - **Mechanism:** `label`.
  - **Approval:** `approved`, added only by the approver; agents never
    add it.
  - **Hand-back:** `needs-human`.
  - **Approver permission:** `write`.
  - **Stale lock age:** `240` minutes.
  - **Base-advance checks:** none.
  - **Reviewer:** `codexbot`.
  - **Reviewer completion marker:** `codex-pull-request-review-summary`.'

new_repo() { # new_repo [record-body]: fresh remote, clone, and fixtures
  local record="${1-$RECORD_DEFAULT}"
  rm -rf "$TMP/srv" "$WORK" "$TMP/seed" "$FIX"
  mkdir -p "$TMP/srv/owner" "$FIX"
  git init -q --bare -b main "$SRV"
  git init -q -b main "$TMP/seed"
  {
    echo "# Project"
    echo
    if [ -n "$record" ]; then
      echo "- **Land approved PRs by label.** This project has the following"
      echo "  landing record:"
      echo
      printf '%s\n' "$record"
      echo
    fi
    echo "## Other"
  } > "$TMP/seed/AGENTS.md"
  git -C "$TMP/seed" add AGENTS.md
  git -C "$TMP/seed" commit -q -m seed
  git -C "$TMP/seed" push -q "$SRV" main
  git clone -q "$SRV" "$WORK"
  echo '{"default_branch":"main"}' > "$FIX/repo.json"
  echo '[]' > "$FIX/prs.json"
  echo '{"permission":"admin","role_name":"admin"}' > "$FIX/role-owner1.json"
}

# --- validation half: dead gh shim ------------------------------------------
# Input that passes validation reaches the first forge read against the dead
# shim and exits 4; rejected input exits 64 first.

new_repo
OID=0123456789abcdef0123456789abcdef01234567

t() {
  expected="$1"; desc="$2"; shift 2
  (cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" "$@") >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$expected" ]; then ok; else bad "($got != $expected) $desc: $*"; fi
}

t 4 "valid list reaches the forge read" --repo owner/name --run r1
t 4 "valid ordered list reaches the forge read" --repo owner/name --run r1 --order 3,1,2
t 4 "valid pushed reaches the forge read" --repo owner/name --run r1 --pr 1 --pushed "$OID"
t 4 "uppercase pushed OID normalized" --repo owner/name --run r1 --pr 1 --pushed "$(printf '%s' "$OID" | tr 'a-f' 'A-F')"
t 4 "repeated pushed accepted" --repo owner/name --run r1 --pr 1 --pushed "$OID" --pushed "$OID"
t 4 "valid release reaches the forge read" --repo owner/name --release r1
t 4 "explicit base remote accepted" --repo owner/name --run r1 --base-remote origin
t 64 "no arguments at all"
t 64 "unknown option" --repo owner/name --run r1 --bogus x
t 64 "trailing bare option" --repo owner/name --run
t 64 "missing repo" --run r1
t 64 "neither run nor release" --repo owner/name
t 64 "run and release together" --repo owner/name --run r1 --release r1
t 64 "repo extra segment" --repo a/b/c --run r1
t 64 "repo query injection" --repo 'a/b?x=1' --run r1
t 64 "run id with a slash" --repo owner/name --run a/b
t 64 "run id with a leading hyphen" --repo owner/name --run -r
t 64 "run id with a leading dot" --repo owner/name --run .r
t 64 "run id beyond 64 characters" --repo owner/name --run "$(printf 'r%.0s' $(seq 1 65))"
t 64 "order with leading zero" --repo owner/name --run r1 --order 1,02
t 64 "order with empty item" --repo owner/name --run r1 --order 1,,2
t 64 "order non-numeric" --repo owner/name --run r1 --order 1,a
t 64 "pushed abbreviated" --repo owner/name --run r1 --pr 1 --pushed 0123456
t 64 "pushed non-hex" --repo owner/name --run r1 --pr 1 --pushed zz23456789abcdef0123456789abcdef01234567
t 64 "release with order" --repo owner/name --release r1 --order 1
t 64 "release with pushed" --repo owner/name --release r1 --pr 1 --pushed "$OID"
t 64 "pushed without pr" --repo owner/name --run r1 --pushed "$OID"
t 64 "pr without pushed" --repo owner/name --run r1 --pr 1
t 64 "pr with leading zero" --repo owner/name --run r1 --pr 01 --pushed "$OID"
t 64 "pr non-numeric" --repo owner/name --run r1 --pr x --pushed "$OID"
t 64 "pushed with order" --repo owner/name --run r1 --pr 1 --pushed "$OID" --order 1
t 0 "cleaned reads nothing from the forge" --repo owner/name --cleaned 7
t 64 "cleaned with run" --repo owner/name --cleaned 7 --run r1
t 64 "cleaned with release" --repo owner/name --cleaned 7 --release r1
t 64 "cleaned with pushed" --repo owner/name --cleaned 7 --pr 1 --pushed "$OID"
t 64 "cleaned with leading zero" --repo owner/name --cleaned 07
t 64 "cleaned non-numeric" --repo owner/name --cleaned x
t 64 "base remote leading hyphen" --repo owner/name --run r1 --base-remote --upload-pack=/x
t 2 "an unknown base remote stops" --repo owner/name --run r1 --base-remote nosuch
git -C "$WORK" remote add fork "$TMP/srv/forker/name.git"
(cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --run r1 --base-remote fork) > "$TMP/out" 2>/dev/null
got=$?
if [ "$got" -eq 2 ] && grep -q '^STOP remote-repo-mismatch ' "$TMP/out"; then ok; else bad "a base remote naming another repository stops remote-repo-mismatch ($got)"; fi
git -C "$WORK" remote add mirror "$SRV"
t 2 "two remotes naming the repository are ambiguous" --repo owner/name --run r1
t 4 "the override picks among remotes that name the repository" --repo owner/name --run r1 --base-remote mirror
git -C "$WORK" remote set-url --push mirror "$TMP/srv/forker/name.git"
(cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --run r1 --base-remote mirror) > "$TMP/out" 2>/dev/null
got=$?
if [ "$got" -eq 2 ] && grep -q '^STOP remote-repo-mismatch ' "$TMP/out"; then ok; else bad "a push URL naming another repository stops remote-repo-mismatch ($got)"; fi
t 4 "a remote whose push URL names a fork does not count toward ambiguity" --repo owner/name --run r1
git -C "$WORK" remote remove fork
git -C "$WORK" remote remove mirror
ORIGIN_URL=$(git -C "$WORK" remote get-url origin)
# The URL matcher: a suffix-trap URL doesn't name the repository, while the
# scp form in another case does, so it makes the remotes ambiguous.
dead_stop() { # dead_stop <guard> <desc>: last run's result is STOP <guard>
  if [ "$got" -eq 2 ] && grep -q "^STOP $1 " "$TMP/out"; then ok; else bad "$2 ($got): $(tail -n 1 "$TMP/out")"; fi
}
git -C "$WORK" remote add trap "$TMP/srv/xowner/name.git"
t 4 "a suffix-trap URL does not name the repository" --repo owner/name --run r1
git -C "$WORK" remote set-url trap git@github.com:Owner/Name.git
(cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --run r1) > "$TMP/out" 2>/dev/null
got=$?
dead_stop remote-ambiguous "an scp URL in another case names the repository"
git -C "$WORK" remote remove trap
git -C "$WORK" remote set-url origin "$TMP/srv/forker/name.git"
(cd "$WORK" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --run r1) > "$TMP/out" 2>/dev/null
got=$?
dead_stop remote-unresolved "no remote naming the repository stops remote-unresolved"
git -C "$WORK" remote set-url origin "$ORIGIN_URL"

(cd "$TMP" && PATH="$DEAD:$PATH" bash "$SCRIPT" --repo owner/name --run r1) > "$TMP/out" 2>/dev/null
got=$?
if [ "$got" -eq 2 ] && grep -q '^STOP not-a-repo ' "$TMP/out"; then ok; else bad "outside a repository stops not-a-repo ($got)"; fi

NOGH=$(mktemp -d)
(cd "$WORK" && PATH="$NOGH" "$(command -v bash)" "$SCRIPT" --repo owner/name --run r1) >/dev/null 2>"$TMP/err"
got=$?
rm -rf "$NOGH"
if [ "$got" -eq 69 ] && grep -qF 'hand the batch to the owner' "$TMP/err"; then ok; else bad "missing gh exits 69 and hands off ($got)"; fi

# --- behavior half: fixture-serving gh shim + real scratch git ---------------

if ! command -v jq >/dev/null 2>&1; then
  skip=1
  echo "SKIP: behavior cases need jq on PATH; only validation ran" >&2
else

{
  echo '#!/bin/bash'
  echo "FIX=\"$FIX\""
  cat <<'SHIMEOF'
echo "$*" >> "$FIX/calls.log"
# Real gh under GH_DEBUG (or the legacy DEBUG when GH_DEBUG is unset), and
# Go whenever GODEBUG contains http2debug=1 or =2, write request headers to
# stderr on every call.
if [ -n "${GH_DEBUG:-}" ] || { [ -z "${GH_DEBUG+set}" ] && [ -n "${DEBUG:-}" ]; } \
   || [[ "${GODEBUG:-}" == *http2debug=[12]* ]]; then
  echo "> Authorization: token SECRET-313" >&2
fi
sub='' verb='' api='' jqval='' prev='' branch='' cursor='' prnum='' query=''
for a in "$@"; do
  case "$prev" in
    --jq) jqval="$a" ;;
    -f) case "$a" in branch=*) branch="${a#branch=}" ;; c=*) cursor="${a#c=}" ;; query=*) query="${a#query=}" ;; esac ;;
    -F) case "$a" in n=*) prnum="${a#n=}" ;; esac ;;
  esac
  case "$a" in
    pr|api) [ -z "$sub" ] && sub="$a" ;;
    list|view) [ "$sub" = pr ] && [ -z "$verb" ] && verb="$a" ;;
    repos/*|graphql) [ -z "$api" ] && api="$a" ;;
  esac
  prev="$a"
done
fixture='' default='' match="$api$verb"
if [ "$sub" = api ]; then
  case "$api" in
    graphql)
      if [[ "$query" == *timelineItems* ]]; then
        # The batched read: one alias per PR, assembled from that PR's thread
        # and timeline fixtures. batch-null-<n> serves the alias as null and
        # batch-omit-<n> leaves it out. A fail-* pattern of "batch" matches
        # only this read; "graphql" matches it and the per-PR thread read.
        match="graphql batch"
        echo '{}' > "$FIX/batch.json"
        for n in $(printf '%s' "$query" | grep -oE 'p[0-9]+:pullRequest' | sed 's/^p//; s/:.*//'); do
          [ -f "$FIX/batch-omit-$n" ] && continue
          if [ -f "$FIX/batch-null-$n" ]; then v=null
          else
            th='{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
            [ -f "$FIX/threads-$n.json" ] && th=$(jq -c '.data.repository.pullRequest.reviewThreads' "$FIX/threads-$n.json")
            c=0
            [ -f "$FIX/timeline-$n.json" ] && c=$(jq '[.[] | select(.event == "labeled" or .event == "unlabeled" or .event == "head_ref_force_pushed")] | length' "$FIX/timeline-$n.json")
            v="{\"reviewThreads\":$th,\"timelineItems\":{\"filteredCount\":$c}}"
          fi
          jq --arg k "p$n" --argjson v "$v" '. + {($k): $v}' "$FIX/batch.json" > "$FIX/batch.tmp" && mv "$FIX/batch.tmp" "$FIX/batch.json"
        done
        jq '{data:{repository:.}}' "$FIX/batch.json" > "$FIX/batch.tmp" && mv "$FIX/batch.tmp" "$FIX/batch.json"
        fixture="$FIX/batch.json"
      elif [ -n "$cursor" ]; then fixture="$FIX/threads-$prnum-page2.json"
      else fixture="$FIX/threads-$prnum.json"; fi
      default='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}' ;;
    */issues/*/timeline*)
      n="${api#*/issues/}"; n="${n%%/*}"
      fixture="$FIX/timeline-$n.json"; default='[]' ;;
    */issues/*/comments*)
      n="${api#*/issues/}"; n="${n%%/*}"
      fixture="$FIX/comments-$n.json"; default='[]' ;;
    */actions/runs*)
      fixture="$FIX/runs-$(printf '%s' "$branch" | tr / _).json"; default='{"workflow_runs":[]}' ;;
    */collaborators/*/permission*)
      u="${api#*/collaborators/}"; u="${u%%/*}"
      u=$(printf '%s' "$u" | sed 's/%5B/[/g; s/%5D/]/g')  # the server decodes the path
      fixture="$FIX/role-$u.json"; default='{"permission":"none","role_name":""}' ;;
    repos/*/*) fixture="$FIX/repo.json" ;;
  esac
elif [ "$sub" = pr ] && [ "$verb" = list ]; then
  fixture="$FIX/prs.json"
  # A one-shot action between the script's lock read and its push.
  if [ -f "$FIX/on-list" ]; then sh "$FIX/on-list" >/dev/null 2>&1; rm -f "$FIX/on-list"; fi
fi
# A fail-* file fails each call whose API path or verb contains its first line, as
# real gh reports a failure: the message on stderr, exit 1. An optional
# second line fails only that many matching calls, counted down in a
# .left file, and then the call is served as usual.
for f in "$FIX"/fail-*; do
  [ -e "$f" ] || continue
  case "$f" in *.left) continue ;; esac
  pat='' times=''
  { IFS= read -r pat; IFS= read -r times; } < "$f"
  case "$match" in *"$pat"*) ;; *) continue ;; esac
  if [ -n "$times" ]; then
    [ -f "$f.left" ] || echo "$times" > "$f.left"
    left=$(cat "$f.left")
    [ "$left" -gt 0 ] || continue
    echo $((left - 1)) > "$f.left"
  fi
  [ -f "$FIX/gh-stderr" ] && cat "$FIX/gh-stderr" >&2
  exit 1
done
if [ -z "$fixture" ]; then exit 1; fi
if [ ! -f "$fixture" ]; then
  [ -n "$default" ] || exit 1
  printf '%s\n' "$default" > "$FIX/default.json"; fixture="$FIX/default.json"
fi
# A read that works can still write to stderr; none of it may reach a
# later failure's excerpt.
echo "gh: notice from a read that worked" >&2
if [ -n "$jqval" ]; then exec jq -r "$jqval" "$fixture"; fi
exec cat "$fixture"
SHIMEOF
} > "$SHIMD/gh"
chmod +x "$SHIMD/gh"

CREATED=2026-10-01T00:00:00Z

# --- fixture builders ---

# pr_add <num> <branch> <oid> [draft] [base] [cross] [labels-json]
pr_add() {
  local labels="${7:-[\"approved\"]}"
  jq --argjson n "$1" --arg b "$2" --arg o "$3" --argjson d "${4:-false}" \
    --arg base "${5:-main}" --argjson x "${6:-false}" --argjson l "$labels" --arg c "$CREATED" \
    '. + [{number:$n, isDraft:$d, baseRefName:$base, headRefName:$b, headRefOid:$o,
           isCrossRepository:$x, createdAt:$c, labels:($l | map({name:.}))}]' \
    "$FIX/prs.json" > "$FIX/prs.tmp" && mv "$FIX/prs.tmp" "$FIX/prs.json"
}
pr_set() { # pr_set <num> <jq-update>
  jq --argjson n "$1" "map(if .number == \$n then $2 else . end)" "$FIX/prs.json" > "$FIX/prs.tmp" \
    && mv "$FIX/prs.tmp" "$FIX/prs.json"
}
labeled() { # labeled <num> <at> [actor] [label]
  local f="$FIX/timeline-$1.json"
  [ -f "$f" ] || echo '[]' > "$f"
  jq --arg at "$2" --arg a "${3:-owner1}" --arg l "${4:-approved}" \
    '. + [{event:"labeled", created_at:$at, label:{name:$l}, actor:{login:$a}}]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
collaborator() { # collaborator <login> <permission> [role-name] [base-role]
  # A base role adds the user.permissions flags a custom role inherits.
  jq -n --arg p "$2" --arg r "${3-$2}" --arg b "${4-}" '{permission:$p, role_name:$r}
    + (if $b == "" then {} else (["read","triage","write","maintain","admin"] | index($b)) as $i
       | {user:{permissions:{pull:($i >= 0), triage:($i >= 1), push:($i >= 2), maintain:($i >= 3), admin:($i >= 4)}}} end)' \
    > "$FIX/role-$1.json"
}
unlabeled() { # unlabeled <num> <at> [actor] [label]
  local f="$FIX/timeline-$1.json"
  [ -f "$f" ] || echo '[]' > "$f"
  jq --arg at "$2" --arg a "${3:-owner1}" --arg l "${4:-approved}" \
    '. + [{event:"unlabeled", created_at:$at, label:{name:$l}, actor:{login:$a}}]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
force_pushed() { # force_pushed <num> <at> <oid>
  local f="$FIX/timeline-$1.json"
  [ -f "$f" ] || echo '[]' > "$f"
  jq --arg at "$2" --arg o "$3" \
    '. + [{event:"head_ref_force_pushed", created_at:$at, commit_id:$o, actor:{login:"someone"}}]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
ci_run() { # ci_run <branch> <at> <oid> [head-repository]
  local f
  f="$FIX/runs-$(printf '%s' "$1" | tr / _).json"
  [ -f "$f" ] || echo '{"workflow_runs":[]}' > "$f"
  jq --arg at "$2" --arg o "$3" --arg r "${4:-Owner/Name}" \
    '.workflow_runs += [{created_at:$at, head_sha:$o, head_repository:{full_name:$r}}]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
reviewed() { # reviewed <num> <oid> [login] [account-type]
  local f="$FIX/comments-$1.json" short="${2:0:7}"
  jq -n --arg u "${3:-codexbot[bot]}" --arg t "${4:-Bot}" --arg s "$short" '[{user:{login:$u, type:$t},
    body:("<!-- codex-pull-request-review-summary -->\n| Review | Status | Commit |\n| --- | --- | --- |\n| Code Review | ✅ **Completed** <relative-time datetime=\"2026-10-01T02:00:00Z\"> | `" + $s + "` |")}]' > "$f"
}
threads() { # threads <num> <unresolved> [has-next]
  jq -n --argjson u "$2" --argjson m "${3:-false}" '{data:{repository:{pullRequest:{reviewThreads:{
    pageInfo:{hasNextPage:$m, endCursor:(if $m then "c1" else null end)},
    nodes:([range(0; $u)] | map({isResolved:false}) + [{isResolved:true}])}}}}}' > "$FIX/threads-$2.json.tmp"
  mv "$FIX/threads-$2.json.tmp" "$FIX/threads-$1.json"
}

# A PR that passes every filter: approved by the recorded approver after a
# CI run on its current head, reviewer round complete on that head.
ready_pr() { # ready_pr <num> <branch> <oid> [approved-at]
  pr_add "$1" "$2" "$3"
  ci_run "$2" 2026-10-01T01:00:00Z "$3"
  labeled "$1" "${4:-2026-10-02T00:00:00Z}"
  reviewed "$1" "$3"
}

H1=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222
H3=3333333333333333333333333333333333333333
H4=4444444444444444444444444444444444444444

# --- runner and assertions ---

RC=0 LAST="" JSON=""
lr() { # lr <args...>: run from the work clone with the fixture shim
  (cd "$WORK" && PATH="$SHIMD:$PATH" bash "$SCRIPT" --repo owner/name "$@") > "$TMP/out" 2> "$TMP/err"
  RC=$?
  LAST=$(tail -n 1 "$TMP/out")
  JSON="${LAST#* }"; JSON="${JSON#* }"
}
expect_calls() { # expect_calls <count> <text> <desc>: exactly <count> gh calls contained <text>
  local n
  n=$(grep -cF -- "$2" "$FIX/calls.log" 2>/dev/null)
  if [ "${n:-0}" -eq "$1" ]; then ok; else bad "$3: ${n:-0} gh calls contained '$2', want $1"; fi
}
expect_err() { if grep -qF -- "$1" "$TMP/err"; then ok; else bad "$2: script stderr lacks '$1'"; fi; }
expect_no_err() { if grep -qF -- "$1" "$TMP/err"; then bad "$2: script stderr has '$1'"; else ok; fi; }
expect_stderr() { # expect_stderr <text> <desc>
  if [ "$(printf '%s' "$JSON" | jq -j '.stderr // empty' 2>/dev/null)" = "$1" ]; then ok
  else bad "$2: stderr is not '$1': $LAST"; fi
}
expect_rc() { if [ "$RC" -eq "$1" ]; then ok; else bad "$2: exit $RC, want $1: $LAST"; fi; }
expect_ready() { # expect_ready <csv> <desc>
  local got
  got=$(printf '%s' "$JSON" | jq -r '[.ready[].number | tostring] | join(",")' 2>/dev/null)
  if [ "$RC" -eq 0 ] && [ "$got" = "$1" ]; then ok; else bad "$2: ready '$got', want '$1' (exit $RC): $LAST"; fi
}
expect_excluded() { # expect_excluded <num> <filter> <desc> [detail-substring]
  local got detail
  got=$(printf '%s' "$JSON" | jq -r --argjson n "$1" '.excluded[] | select(.number == $n) | .filter' 2>/dev/null)
  detail=$(printf '%s' "$JSON" | jq -r --argjson n "$1" '.excluded[] | select(.number == $n) | .detail' 2>/dev/null)
  if [ "$RC" -eq 0 ] && [ "$got" = "$2" ] && { [ -z "${4:-}" ] || [[ "$detail" == *"$4"* ]]; }; then ok
  else bad "$3: #$1 filter '$got' ($detail), want '$2'${4:+ with '$4'} (exit $RC): $LAST"; fi
}
expect_stop() { # expect_stop <guard> <desc>
  case "$LAST" in "STOP $1 "*) [ "$RC" -eq 2 ] && { ok; return; } ;; esac
  bad "$2: want STOP $1, got exit $RC: $LAST"
}
expect_lock_state() { # expect_lock_state <state> <desc>
  local got
  got=$(printf '%s' "$JSON" | jq -r .lock 2>/dev/null)
  if [ "$got" = "$1" ]; then ok; else bad "$2: lock '$got', want '$1': $LAST"; fi
}
remote_lock() { git -C "$SRV" rev-parse --verify --quiet refs/land/lock; }
remote_lock_field() { git -C "$SRV" log -1 --format=%B refs/land/lock | sed -n "s/^$1: //p"; }
expect_remote_lock() { # expect_remote_lock <run-or-absent> <desc>
  local got
  if [ "$1" = absent ]; then
    if remote_lock >/dev/null; then bad "$2: lock still present"; else ok; fi
    return
  fi
  got=$(remote_lock_field run 2>/dev/null)
  if [ "$got" = "$1" ]; then ok; else bad "$2: remote lock run '$got', want '$1'"; fi
}
plant_lock() { # plant_lock <run> <age-minutes>: another lander's lock
  local tree c
  tree=$(git -C "$SRV" mktree < /dev/null)
  c=$(printf 'land lock\n\nrun: %s\nhost: elsewhere\npr: 7\n' "$1" \
    | GIT_COMMITTER_DATE="@$(( $(date +%s) - $2 * 60 )) +0000" git -C "$SRV" commit-tree "$tree")
  git -C "$SRV" update-ref refs/land/lock "$c"
}

# --- filters ---

new_repo
ready_pr 1 'feat/é"q' "$H1"
lr --run r1
got=$(printf '%s' "$JSON" | jq -r '.ready[0].head_branch' 2>/dev/null)
if [ "$got" = 'feat/é"q' ]; then ok; else bad "a UTF-8 branch with a quote round-trips through the JSON: '$got'"; fi

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
expect_ready 1 "a PR passing every filter is ready"
expect_lock_state acquired "the first list acquires the lock"
expect_remote_lock r1 "the acquired lock names the run"
if [ "$(remote_lock_field pr)" = 1 ]; then ok; else bad "the lock names the PR in progress"; fi
grep -q '^  #1 feat/one head 1111111, approved 2026-10-02T00:00:00Z$' "$TMP/out" && ok \
  || bad "the human list shows the ready PR"

new_repo
ready_pr 1 feat/one "$H1"; pr_set 1 '.isDraft = true'
lr --run r1
expect_excluded 1 1 "filter 1: a draft is excluded" draft
expect_lock_state absent "an empty first list takes no lock"
expect_remote_lock absent "an empty first list leaves no lock"

new_repo
ready_pr 1 feat/one "$H1"; pr_set 1 '.baseRefName = "feat/parent"'
lr --run r1
expect_excluded 1 2 "filter 2: a stacked PR is excluded" "targets feat/parent"

new_repo
ready_pr 1 feat/one "$H1"; pr_set 1 '.labels = []'
lr --run r1
expect_excluded 1 3 "filter 3: no approved label" "no approved label"

new_repo
ready_pr 1 feat/one "$H1"; pr_set 1 '.labels += [{name:"needs-human"}]'
lr --run r1
expect_excluded 1 3 "filter 3: handed back" "carries needs-human"

new_repo
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z owner1
labeled 1 2026-10-03T00:00:00Z intruder
lr --run r1
expect_excluded 1 3 "filter 3: the latest approved label came from a non-collaborator" "permission is none, below the recorded write"

new_repo
collaborator writer write
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z writer
lr --run r1
expect_ready 1 "filter 3: any collaborator with write permission approves"

new_repo
collaborator triager read triage
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z triager
lr --run r1
expect_excluded 1 3 "filter 3: triage is below write" "permission is triage, below the recorded write"

new_repo
collaborator lead write release-manager
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z lead
lr --run r1
expect_ready 1 "filter 3: a custom role falls back to the legacy permission"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Approver permission/s/`write`/`maintain`/')"
collaborator writer write
collaborator lead write maintain
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z writer
pr_add 2 feat/two "$H2"; ci_run feat/two 2026-10-01T01:00:00Z "$H2"; reviewed 2 "$H2"
labeled 2 2026-10-02T00:00:00Z lead
lr --run r1
expect_excluded 1 3 "filter 3: a maintain record rejects write" "permission is write, below the recorded maintain"
expect_ready 2 "filter 3: a maintain record reads role_name, which the legacy field hides"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Approver permission/s/`write`/`maintain`/')"
collaborator captain write release-captain maintain
collaborator helper write release-helper write
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z captain
pr_add 2 feat/two "$H2"; ci_run feat/two 2026-10-01T01:00:00Z "$H2"; reviewed 2 "$H2"
labeled 2 2026-10-02T00:00:00Z helper
lr --run r1
expect_ready 1 "filter 3: a custom role based on maintain passes a maintain floor through user.permissions"
expect_excluded 2 3 "filter 3: a custom role based on write fails a maintain floor through user.permissions" "permission is write, below the recorded maintain"

new_repo
collaborator 'release[bot]' write
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z 'release[bot]'
lr --run r1
expect_ready 1 "filter 3: a bot login's brackets are encoded in the permission path"
if grep -q 'collaborators/release%5Bbot%5D/permission' "$FIX/calls.log"; then ok; else bad "the permission read encodes [bot]"; fi

new_repo
collaborator mona-cat_octo write
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z mona-cat_octo
lr --run r1
expect_ready 1 "filter 3: a managed user's underscore is in the login alphabet"
if grep -q 'collaborators/mona-cat_octo/permission' "$FIX/calls.log"; then ok; else bad "an underscore login was not sent to the permission endpoint"; fi

new_repo
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z '../owner1'
lr --run r1
expect_excluded 1 3 "filter 3: an actor login outside the login alphabet never reaches the forge" "permission is none"
if grep -q 'collaborators/' "$FIX/calls.log"; then bad "a rejected login was sent to the permission endpoint"; else ok; fi

new_repo
collaborator writer write
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z writer
pr_add 2 feat/two "$H2"; ci_run feat/two 2026-10-01T01:00:00Z "$H2"; reviewed 2 "$H2"
labeled 2 2026-10-02T00:00:00Z writer
lr --run r1
expect_ready 1,2 "filter 3: one actor's role is read once per run"
if [ "$(grep -c 'collaborators/writer/permission' "$FIX/calls.log")" -eq 1 ]; then ok; else bad "the role cache made $(grep -c 'collaborators/writer/permission' "$FIX/calls.log") permission reads"; fi

new_repo
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
lr --run r1
expect_excluded 1 3 "filter 3: a label with no labeled event" "no labeled event"

new_repo
ready_pr 1 feat/one "$H1"; pr_set 1 '.isCrossRepository = true'
lr --run r1
expect_excluded 1 7 "filter 7: a fork head is excluded" "another repository"

new_repo
ready_pr 1 feat/one "$H1"
ci_run feat/one 2026-10-03T00:00:00Z "$H2"; pr_set 1 ".headRefOid = \"$H2\""; reviewed 1 "$H2"
lr --run r1
expect_excluded 1 4 "filter 4: a push after approval hands back" "neither the approved head $H1"

new_repo
ready_pr 1 feat/one "$H1"
force_pushed 1 2026-10-03T00:00:00Z "$H2"; pr_set 1 ".headRefOid = \"$H2\""; reviewed 1 "$H2"
lr --run r1
expect_excluded 1 4 "transition: another actor's force-push after approval hands back" "not pushed by this run"

new_repo
ready_pr 1 feat/one "$H1"
force_pushed 1 2026-10-03T00:00:00Z "$H2"; force_pushed 1 2026-10-03T01:00:00Z "$H1"
lr --run r1
expect_excluded 1 4 "filter 4: a force-push away and back is still another actor's" "force-push to $H2"

# The current head has no CI run: pushed before approval while the PR was
# conflicted, so the newest evidence is the older head.
new_repo
pr_add 1 feat/one "$H2"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"
labeled 1 2026-10-02T00:00:00Z; reviewed 1 "$H2"
lr --run r1
expect_excluded 1 4 "transition: a current head with no CI run hands back" "neither the approved head $H1"

new_repo
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-03T00:00:00Z "$H1"
labeled 1 2026-10-02T00:00:00Z; reviewed 1 "$H1"
lr --run r1
expect_excluded 1 4 "filter 4: no evidence at or before approval" "approved head is unknown"

new_repo
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-09-20T00:00:00Z "$H1"
labeled 1 2026-10-02T00:00:00Z; reviewed 1 "$H1"
lr --run r1
expect_excluded 1 4 "filter 4: a CI run older than the PR belongs to another PR" "approved head is unknown"

# Two pushes before approval: the owner read the newer one.
new_repo
pr_add 1 feat/one "$H2"
ci_run feat/one 2026-10-01T01:00:00Z "$H1"; ci_run feat/one 2026-10-01T05:00:00Z "$H2"
labeled 1 2026-10-02T00:00:00Z; reviewed 1 "$H2"
lr --run r1
expect_ready 1 "filter 4: the newest evidence before approval is the approved head"

new_repo
ready_pr 1 feat/one "$H1"
labeled 1 2026-10-01T01:00:00Z
lr --run r1
expect_ready 1 "filter 4: evidence at the approval second counts as at or before"

new_repo
ready_pr 1 feat/one "$H1"; threads 1 2
lr --run r1
expect_excluded 1 5 "filter 5: unresolved threads" "2 unresolved"

new_repo
ready_pr 1 feat/one "$H1"; threads 1 0 true
jq -n '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:false,endCursor:null},nodes:[{isResolved:false}]}}}}}' > "$FIX/threads-1-page2.json"
lr --run r1
expect_excluded 1 5 "filter 5: an unresolved thread on a later page" "1 unresolved"

new_repo
ready_pr 1 feat/one "$H1"; reviewed 1 "$H2"
lr --run r1
expect_excluded 1 6 "filter 6: the reviewer's round is for another head" "no completed round on head 1111111"

new_repo
ready_pr 1 feat/one "$H1"; reviewed 1 "$H1" someone-else
lr --run r1
expect_excluded 1 6 "filter 6: a summary by another login does not count"

new_repo
ready_pr 1 feat/one "$H1"; reviewed 1 "$H1" codexbot
lr --run r1
expect_ready 1 "filter 6: a bot account under the reviewer's bare login counts"

new_repo
ready_pr 1 feat/one "$H1"; reviewed 1 "$H1" codexbot User
lr --run r1
expect_excluded 1 6 "filter 6: a user account under the reviewer's bare login does not count"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Reviewer:/s/`codexbot`/`none`/' | sed '/completion marker/d')"
ready_pr 1 feat/one "$H1"; rm -f "$FIX/comments-1.json"
lr --run r1
expect_ready 1 "filter 6: no recorded reviewer means no reviewer filter"

new_repo
pr_add 1 feat/one "$H2"
ci_run feat/one 2026-10-01T01:00:00Z "$H1"
ci_run feat/one 2026-10-01T01:30:00Z "$H2" stranger/name
labeled 1 2026-10-02T00:00:00Z
reviewed 1 "$H2"
lr --run r1
expect_excluded 1 4 "filter 4: a fork's run on a same-named branch is not the approved head" "approved head $H1"

# --- ordering ---

new_repo
ready_pr 1 feat/one "$H1" 2026-10-05T00:00:00Z
ready_pr 2 feat/two "$H2" 2026-10-02T00:00:00Z
lr --run r1
expect_ready 2,1 "oldest approval first, not lowest number"

new_repo
ready_pr 1 feat/one "$H1" 2026-10-02T00:00:00Z
ready_pr 2 feat/two "$H2" 2026-10-05T00:00:00Z
lr --run r1 --order 2,1
expect_ready 2,1 "a typed order overrides approval order"

new_repo
ready_pr 1 feat/one "$H1"; pr_set 1 '.labels = [{name:"needs-human"}]'
ready_pr 2 feat/two "$H2"
ready_pr 3 feat/three "$H3"
lr --run r1 --order 1,2
expect_ready 3 "an unsequenced PR still lands when an ordered one is held"
expect_excluded 2 order "a PR sequenced after a handed-back PR is held" "sequenced after #1"

new_repo
ready_pr 2 feat/two "$H2"
lr --run r1 --order 5,2
expect_ready 2 "an ordered number that is not open is skipped"
grep -q '^note: ordered #5 is not an open PR; skipped$' "$TMP/out" && ok || bad "the skipped order entry is reported"

new_repo
ready_pr 1 feat/one "$H1"
ready_pr 2 feat/two "$H2"
lr --run r1 --order 2,2
expect_ready 2,1 "a repeated order entry lists its PR once"

# --- the lock ---

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
first=$(remote_lock)
# The heartbeat is the committer date, so a refresh in the same second
# rebuilds the identical commit.
sleep 1
lr --run r1
expect_lock_state refreshed "a second list by the same run refreshes the lock"
second=$(remote_lock)
if [ -n "$first" ] && [ -n "$second" ] && [ "$first" != "$second" ]; then ok; else bad "the heartbeat moves the lock ref"; fi
if [ "$(git -C "$SRV" rev-list --parents -n 1 refs/land/lock | wc -w | tr -d ' ')" = 1 ]; then ok; else bad "the lock commit is an orphan"; fi
pr_set 1 '.labels = []'
lr --run r1
expect_ready "" "transition: approval removed during a land wait drops the PR at the next list"
expect_lock_state released "an empty fresh list releases the lock"
expect_remote_lock absent "the released lock ref is gone"

new_repo
ready_pr 1 feat/one "$H1"
plant_lock other 5
before=$(remote_lock)
lr --run r1
expect_stop lock-held "a fresh lock held by another run is refused"
if [ "$(remote_lock)" = "$before" ]; then ok; else bad "a refused list leaves the other lock untouched"; fi
if printf '%s' "$JSON" | jq -e '.run == "other" and .age_minutes >= 4' >/dev/null 2>&1; then ok; else bad "the refusal names the holder and its age: $LAST"; fi

new_repo
ready_pr 1 feat/one "$H1"
plant_lock other 300
before=$(remote_lock)
lr --run r1
expect_stop lock-stale "a lock past the stale age is reported, not taken over"
if [ "$(remote_lock)" = "$before" ]; then ok; else bad "a stale report leaves the lock untouched"; fi
grep -qF -- '--release other' "$TMP/out" && ok || bad "the stale report names the release command"
lr --release other
expect_rc 0 "transition: the owner releases a stale lock by its run id"
expect_lock_state released "the stale lock release reports released"
lr --run r2
expect_ready 1 "transition: a new run starts after the stale lock is released"
expect_remote_lock r2 "the new run holds the lock"

new_repo
ready_pr 1 feat/one "$H1"
plant_lock r1 300
lr --run r1
expect_ready 1 "transition: a live run outlasting the stale age keeps its own lock"
expect_lock_state refreshed "the live run's heartbeat refreshes its stale lock"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Stale lock age/d')"
ready_pr 1 feat/one "$H1"
plant_lock other 239
lr --run r1
expect_stop lock-held "with no recorded age, a 239-minute lock is still live"
plant_lock other 241
lr --run r1
expect_stop lock-stale "with no recorded age, the default stale age is 240 minutes"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Stale lock age/s/`240`/`30`/')"
ready_pr 1 feat/one "$H1"
plant_lock other 45
lr --run r1
expect_stop lock-stale "the record's stale age overrides the default"

new_repo
plant_lock other 5
lr --release r1
expect_stop lock-held "releasing another run's lock is refused"
expect_remote_lock other "a refused release leaves the lock"

new_repo
lr --release r1
expect_rc 0 "releasing an absent lock succeeds"
expect_lock_state absent "an absent lock reports absent"

new_repo
lr --run r1 --pr 1 --pushed "$H2"
expect_stop lock-not-held "a push cannot be recorded without the lock"

# Another lander takes the lock while this run lists, after its lock read
# and before its push. The lease on the value this run read is what refuses
# the push: a plain force would overwrite the other lander's lock.
new_repo
ready_pr 1 feat/one "$H1"
tree=$(git -C "$SRV" mktree < /dev/null)
foreign=$(printf 'land lock\n\nrun: racer\nhost: elsewhere\npr: 1\n' | git -C "$SRV" commit-tree "$tree")
printf 'git -C "%s" update-ref refs/land/lock %s\n' "$SRV" "$foreign" > "$FIX/on-list"
lr --run r1
expect_stop lock-held "a lock taken while this run lists is refused"
if [ "$(remote_lock)" = "$foreign" ]; then ok; else bad "the racing lander keeps the lock"; fi

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
tree=$(git -C "$SRV" mktree < /dev/null)
foreign=$(printf 'land lock\n\nrun: r1\nhost: elsewhere\npr: 1\n' | git -C "$SRV" commit-tree "$tree")
printf 'git -C "%s" update-ref refs/land/lock %s\n' "$SRV" "$foreign" > "$FIX/on-list"
lr --run r1
expect_stop lock-lost "a heartbeat whose lock moved under it stops lock-lost"
if [ "$(remote_lock)" = "$foreign" ]; then ok; else bad "a lost heartbeat leaves the mover's lock"; fi

# --- the push log ---

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
lr --run r1 --pr 1 --pushed "$H2"
expect_rc 0 "a pushed head is recorded under the lock"
expect_lock_state refreshed "recording a push refreshes the lock"
if [ "$(remote_lock_field pr)" = 1 ]; then ok; else bad "recording a push keeps the PR in progress"; fi
grep -qxF "1 $H2" "$WORK/.git/land-approved-prs/pushed-r1" && ok || bad "the push log is under the git directory, keyed by run"
force_pushed 1 2026-10-03T00:00:00Z "$H2"; pr_set 1 ".headRefOid = \"$H2\""
ci_run feat/one 2026-10-03T00:00:10Z "$H2"; reviewed 1 "$H2"
lr --run r1
expect_ready 1 "transition: the lander's own rebase after approval stays eligible"
lr --run r9 --pr 1 --pushed "$H3"
expect_stop lock-held "another run cannot record into a held lock"
lr --release r1
if [ -e "$WORK/.git/land-approved-prs/pushed-r1" ]; then bad "release removes the run's push log"; else ok; fi

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
lr --run r1 --pr 1 --pushed "$H2"
force_pushed 1 2026-10-03T00:00:00Z "$H2"; pr_set 1 ".headRefOid = \"$H2\""; reviewed 1 "$H2"
lr --run r2
expect_stop lock-held "a second run sees the first run's lock"
lr --release r1
lr --run r2
expect_excluded 1 4 "recovery: a PR the dead run rebased hands back to the next run" "not pushed by this run"

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
lr --run r1 --pr 1 --pushed "$H2"
pr_set 1 ".headRefOid = \"$H4\""; ci_run feat/one 2026-10-03T00:00:00Z "$H4"; reviewed 1 "$H4"
lr --run r1
expect_excluded 1 4 "a push on top of this run's push is another actor's" "neither the approved head"

# A head this run pushed to one PR counts only for that PR: another branch
# can be force-pushed to the same commit without the owner approving it.
new_repo
ready_pr 1 feat/one "$H1"
ready_pr 2 feat/two "$H3"
lr --run r1
lr --run r1 --pr 1 --pushed "$H2"
force_pushed 2 2026-10-03T00:00:00Z "$H2"; pr_set 2 ".headRefOid = \"$H2\""; reviewed 2 "$H2"
lr --run r1
expect_excluded 2 4 "a head pushed to another PR does not exempt this one" "not pushed by this run"

# --- the per-run cache ---

CACHE="$WORK/.git/land-approved-prs/listed-r1"
relist() { : > "$FIX/calls.log"; lr --run r1; } # relist: list again with a fresh call log
lists() { printf '%s' "$JSON" | jq -c '{ready, excluded}' 2>/dev/null; }

# A relist of unchanged PRs costs the same calls for one PR as for four,
# and reads no timeline, CI runs, or reviewer comments.
new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
first=$(lists)
relist
expect_ready 1 "a relist of an unchanged PR keeps it ready"
if [ "$(lists)" = "$first" ]; then ok; else bad "a cached relist lists the same PRs: $(lists), want $first"; fi
expect_calls 0 /timeline "a relist of an unchanged PR reads no timeline"
expect_calls 0 actions/runs "a relist of an unchanged PR reads no CI runs"
expect_calls 0 /comments "a relist of an unchanged PR reads no reviewer comments"
expect_calls 1 "timelineItems(itemTypes" "a relist reads threads and event counts in one batched read"
if [ -f "$CACHE/1" ]; then ok; else bad "the list caches the PR under the run's directory"; fi
one=$(grep -c "" "$FIX/calls.log")
new_repo
ready_pr 1 feat/one "$H1"; ready_pr 2 feat/two "$H2"; ready_pr 3 feat/three "$H3"; ready_pr 4 feat/four "$H4"
lr --run r1
first=$(lists)
relist
expect_ready 1,2,3,4 "a relist of four unchanged PRs keeps them ready"
if [ "$(lists)" = "$first" ]; then ok; else bad "a cached relist of four PRs lists the same PRs"; fi
four=$(grep -c "" "$FIX/calls.log")
if [ "$one" -eq "$four" ]; then ok; else bad "a relist of four unchanged PRs made $four calls, one PR made $one"; fi

# Every change that can move filters 3 or 4 rereads the PR.
new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
unlabeled 1 2026-10-03T00:00:00Z; labeled 1 2026-10-04T00:00:00Z
relist
got=$(printf '%s' "$JSON" | jq -r '.ready[0].approved_at' 2>/dev/null)
if [ "$got" = 2026-10-04T00:00:00Z ]; then ok; else bad "removing and re-adding the label re-times the approval: '$got'"; fi
expect_calls 1 issues/1/timeline "a label change rereads the timeline"

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
unlabeled 1 2026-10-03T00:00:00Z; pr_set 1 '.labels = []'
relist
expect_excluded 1 3 "a removed label excludes the PR on the relist" "no approved label"

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
pr_set 1 ".headRefOid = \"$H2\""; ci_run feat/one 2026-10-03T00:00:00Z "$H2"; reviewed 1 "$H2"
relist
expect_excluded 1 4 "a new head on the relist is checked against the approved head" "neither the approved head"

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
force_pushed 1 2026-10-03T00:00:00Z "$H2"; force_pushed 1 2026-10-03T00:01:00Z "$H1"
relist
expect_excluded 1 4 "a force-push away and back is seen on the relist" "not pushed by this run"

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
threads 1 1
relist
expect_excluded 1 5 "a new unresolved thread excludes the PR on the relist" "1 unresolved"

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
collaborator owner1 read
relist
expect_excluded 1 3 "the approver's permission is read on every list" "permission is read"

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
lr --run r1 --pr 1 --pushed "$H2"
relist
expect_calls 1 issues/1/timeline "a recorded push rereads the PR on the next list"
expect_calls 1 /comments "a recorded push rereads the reviewer comments"

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
printf 'garbage\n' > "$CACHE/1"
relist
expect_ready 1 "a malformed cache file is a miss"
expect_calls 1 issues/1/timeline "a malformed cache file rereads the timeline"
if [ "$(head -n 1 "$CACHE/1" | cut -f 1)" = key ]; then ok; else bad "a malformed cache file is rewritten"; fi

new_repo
ready_pr 1 feat/one "$H1"
mkdir -p "$WORK/.git/land-approved-prs"; : > "$CACHE"
lr --run r1
expect_ready 1 "a cache that can't be written leaves the list uncached"
expect_err "could not write the list cache" "an unwritable cache warns"
rm -f "$CACHE"

# The batched read fails closed.
new_repo
ready_pr 1 feat/one "$H1"
echo batch > "$FIX/fail-batch"
lr --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED review-threads "* ]]; then ok; else bad "a failed batched read is LOOKUP_FAILED review-threads: $LAST"; fi
for kind in null omit; do
  case "$kind" in null) what="a null alias" ;; omit) what="a missing alias" ;; esac
  new_repo
  ready_pr 1 feat/one "$H1"; ready_pr 2 feat/two "$H2"
  : > "$FIX/batch-$kind-2"
  lr --run r1
  if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED review-threads "*"PR 2"* ]]; then ok
  else bad "$what in the batched read is LOOKUP_FAILED review-threads: $LAST"; fi
done

# The cache goes with the lock.
new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
lr --release r1
if [ -e "$CACHE" ]; then bad "release removes the run's list cache"; else ok; fi
new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
pr_set 1 '.labels = []'
relist
expect_lock_state released "an empty relist releases the lock"
if [ -e "$CACHE" ]; then bad "an empty relist removes the run's list cache"; else ok; fi

# --- the landing record ---

new_repo ""
ready_pr 1 feat/one "$H1"
lr --run r1
expect_stop no-landing-record "a repository without a landing record stops"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Mechanism/s/`label`/`review`/')"
lr --run r1
expect_stop unsupported-mechanism "only the label mechanism is implemented"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Approver permission/s/`write`/`triage`/')"
lr --run r1
expect_stop bad-record "an Approver permission below write is refused"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed 's/\*\*Approver permission:\*\* `write`/**Approver:** `owner1`/')"
lr --run r1
expect_stop bad-record "a record naming one Approver login predates this version and stops"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/completion marker/d')"
lr --run r1
expect_stop bad-record "a recorded reviewer needs a completion marker"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Reviewer/d')"
ready_pr 1 feat/one "$H1"
lr --run r1
expect_stop bad-record "a record without a Reviewer bullet stops rather than skip filter 6"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Reviewer:/s/`codexbot`/codexbot/')"
ready_pr 1 feat/one "$H1"
lr --run r1
expect_stop bad-record "a Reviewer value without backticks stops"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Base-advance/a\
\
  Stray paragraph.')"
ready_pr 1 feat/one "$H1"
lr --run r1
expect_stop bad-record "a record cut short before its Reviewer bullet stops"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Stale lock age/s/`240`/240/')"
ready_pr 1 feat/one "$H1"
lr --run r1
expect_stop bad-record "a Stale lock age without backticks stops rather than default"

new_repo "$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Approver permission/s/`write`/`maintain`/')"
collaborator writer write
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z writer
sed -i.bak 's/`maintain`/`write`/' "$WORK/AGENTS.md"
lr --run r1
expect_excluded 1 3 "the record comes from the default-branch tip, not the working tree" "below the recorded maintain"

new_repo
ready_pr 1 feat/one "$H1"
git -C "$TMP/seed" mv AGENTS.md OTHER.md
git -C "$TMP/seed" commit -q -m "drop record"
git -C "$TMP/seed" push -q "$SRV" main
lr --run r1
expect_stop no-landing-record "the record is read from the fetched tip, which no longer has it"

# --- fail-closed Markdown landing-record reader (#436) ---

push_agents() { # push_agents: replace AGENTS.md on remote main from stdin
  rm -f "$TMP/seed/AGENTS.md"
  cat > "$TMP/seed/AGENTS.md"
  git -C "$TMP/seed" add -A AGENTS.md
  git -C "$TMP/seed" commit -q --allow-empty -m "update agents"
  git -C "$TMP/seed" push -q "$SRV" main
}

RECORD_MAINTAIN=$(printf '%s\n' "$RECORD_DEFAULT" | sed '/Approver permission/s/`write`/`maintain`/')

new_repo ""
collaborator writer write
pr_add 1 feat/one "$H1"; ci_run feat/one 2026-10-01T01:00:00Z "$H1"; reviewed 1 "$H1"
labeled 1 2026-10-02T00:00:00Z writer

push_agents <<EOF
# Project

\`\`\`markdown
$RECORD_DEFAULT
\`\`\`
EOF
lr --run r1
expect_stop no-landing-record "a backtick-fenced example alone stops no-landing-record"

push_agents <<EOF
# Project

~~~markdown
$RECORD_DEFAULT
~~~
EOF
lr --run r1
expect_stop no-landing-record "a tilde-fenced example alone stops no-landing-record"

push_agents <<EOF
# Project

- Example:

  \`\`\`markdown
$RECORD_DEFAULT
  \`\`\`
EOF
lr --run r1
expect_stop no-landing-record "a two-space list-indented fenced example alone stops no-landing-record"

push_agents <<EOF
# Project

<!--   - **Mechanism:** \`label\`. -->
EOF
lr --run r1
expect_stop no-landing-record "a single-line commented example alone stops no-landing-record"

push_agents <<EOF
# Project

<!--
$RECORD_DEFAULT
-->
EOF
lr --run r1
expect_stop no-landing-record "a multi-line commented example alone stops no-landing-record"

push_agents <<EOF
# Project

\`\`\`markdown
$RECORD_DEFAULT
\`\`\`

- **Land approved PRs by label.** This project has the following landing record:

$RECORD_MAINTAIN
EOF
lr --run r1
expect_excluded 1 3 "a fenced example before the real record is skipped" "below the recorded maintain"

push_agents <<EOF
# Project

<!--
$RECORD_DEFAULT
-->

- **Land approved PRs by label.** This project has the following landing record:

$RECORD_MAINTAIN
EOF
lr --run r1
expect_excluded 1 3 "a commented example before the real record is skipped" "below the recorded maintain"

push_agents <<EOF
# Project

<!-- managed:start -->

- **Claim shape:**

  \`\`\`markdown
  <!-- work-claim:v1 -->
$RECORD_DEFAULT
  \`\`\`

<!--
\`\`\`markdown
$RECORD_DEFAULT
-->

- **Land approved PRs by label.** This project has the following landing record:

$RECORD_MAINTAIN

<!-- managed:end -->
EOF
lr --run r1
expect_excluded 1 3 "comment inside fence and fence inside comment do not break reading the real record" "below the recorded maintain"

# CRLF AGENTS.md passes cleanly.
printf '# Project\r\n\r\n%s\r\n' "$RECORD_MAINTAIN" | sed 's/$/\r/' | sed 's/\r\r$/\r/' | push_agents
lr --run r1
expect_excluded 1 3 "CRLF AGENTS.md passes cleanly" "below the recorded maintain"

# Fail-closed ambiguous and malformed layouts.
push_agents <<EOF
$RECORD_MAINTAIN

\`\`\`markdown
unclosed fence
EOF
lr --run r1
expect_stop bad-record "an unclosed fenced code block stops bad-record"

push_agents <<EOF
<!--
unclosed comment
$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "an unclosed HTML comment stops bad-record"

push_agents <<EOF
<!--
<!-- nested
-->

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a nested <!-- inside a comment stops bad-record"

push_agents <<EOF
Stray closer -->

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "an orphan --> stops bad-record"

push_agents <<EOF
<!-->

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "short ambiguous <!--> stops bad-record"

push_agents <<EOF
<!--->

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "short ambiguous <!---> stops bad-record"

push_agents <<EOF
Text <!-- mid-line unclosed

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a mid-line unclosed <!-- stops bad-record"

push_agents <<EOF
<!-- comment --> trailing text

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "trailing non-whitespace on a line-start comment closer stops bad-record"

push_agents <<EOF
Unbalanced \`code <!-- comment -->

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "an unbalanced backtick span on a line with <!-- stops bad-record"

push_agents <<EOF
> <!-- unclosed on blockquote

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "an unbalanced <!-- on a blockquote line stops bad-record"

push_agents <<EOF
    \`\`\`markdown
    indented fence
    \`\`\`

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a 4-space indented fence outside an active fence stops bad-record"

push_agents <<EOF
  \`\`\`markdown
  body
    \`\`\`
  \`\`\`

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a 4-space matching closer inside a 2-space fence stops bad-record"

push_agents <<EOF
  \`\`\`markdown
  body
     \`\`\`
  \`\`\`

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a 5-space matching closer inside a 2-space fence stops bad-record"

push_agents <<EOF
<pre>
$RECORD_DEFAULT
</pre>

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a raw HTML <pre> block stops bad-record"

push_agents <<EOF
<details>
$RECORD_DEFAULT
</details>

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a raw HTML <details> block stops bad-record"

push_agents <<EOF
---
title: unclosed

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "unclosed line-1 --- front matter stops bad-record"

push_agents <<EOF
[ref]: https://example.com
$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a link reference definition immediately before the record stops bad-record"

push_agents <<EOF
$RECORD_DEFAULT

## Second

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "duplicate visible landing records stop bad-record"

push_agents <<EOF
$RECORD_MAINTAIN
  - **Approval:** \`other\`.
EOF
lr --run r1
expect_stop bad-record "duplicate keys within a landing record stop bad-record"

push_agents <<EOF
  * **Mechanism:** \`label\`.
  - **Approval:** \`approved\`.
EOF
lr --run r1
expect_stop bad-record "a non-canonical Mechanism bullet with * marker stops bad-record"

push_agents <<EOF
- **Mechanism:** \`label\`.
  - **Approval:** \`approved\`.
EOF
lr --run r1
expect_stop bad-record "a non-canonical Mechanism bullet at 0-space indent stops bad-record"

push_agents <<EOF
  - **Mechanism**: \`label\`.
  - **Approval:** \`approved\`.
EOF
lr --run r1
expect_stop bad-record "a non-canonical Mechanism bullet with colon outside bold stops bad-record"

push_agents <<EOF
  - **Mechanism:** \`label\`.
  - **Approval:** \`approved\`,
  lazy continuation line.
  - **Hand-back:** \`needs-human\`.
  - **Approver permission:** \`maintain\`.
  - **Reviewer:** \`none\`.
EOF
lr --run r1
expect_stop bad-record "a lazy continuation inside a record stops bad-record"

push_agents <<EOF
  - **Mechanism:** \`label\`.
  - **Approval:** \`approved\`.
    - nested sub-bullet
  - **Hand-back:** \`needs-human\`.
  - **Approver permission:** \`maintain\`.
  - **Reviewer:** \`none\`.
EOF
lr --run r1
expect_stop bad-record "a nested sub-bullet inside a record stops bad-record"

push_agents <<EOF
  - **Mechanism:** \`label\`.
  <!-- comment inside record -->
  - **Approval:** \`approved\`.
  - **Hand-back:** \`needs-human\`.
  - **Approver permission:** \`maintain\`.
  - **Reviewer:** \`none\`.
EOF
lr --run r1
expect_stop bad-record "an HTML comment inside a record stops bad-record"

push_agents <<EOF
- \`\`\`
$RECORD_DEFAULT

  \`\`\`
  \`\`\`
EOF
lr --run r1
expect_stop bad-record "a code fence opened on a bullet marker line stops bad-record"

push_agents <<EOF
- <script>

$RECORD_DEFAULT

  </script>.
EOF
lr --run r1
expect_stop bad-record "a raw HTML block opened on a bullet marker line stops bad-record"

push_agents <<EOF
> \`\`\`markdown
> $RECORD_DEFAULT
> \`\`\`
EOF
lr --run r1
expect_stop bad-record "a code fence opened on a blockquote line stops bad-record"

push_agents <<EOF
$RECORD_MAINTAIN

    continued second paragraph of last bullet.
EOF
lr --run r1
expect_stop bad-record "a four-space continuation paragraph after the record stops bad-record"

push_agents <<EOF
$RECORD_MAINTAIN

  - **Stale lock age:** \`30\` minutes.
EOF
lr --run r1
expect_stop bad-record "a loose-list record bullet after a blank line stops bad-record"

push_agents <<EOF
$RECORD_MAINTAIN

   - **Stale lock age:** \`30\` minutes.
EOF
lr --run r1
expect_stop bad-record "a 3-space loose sibling bullet after a blank line stops bad-record"

push_agents <<EOF
  - **Mechanism:** \`review\` (see note]: below)

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a Mechanism bullet containing ]: is not skipped as a link reference"

push_agents <<EOF
> - **Mechanism:** \`review\`.

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a blockquoted Mechanism bullet stops bad-record"

push_agents <<EOF
  - **Mechanism\\:** \`review\`.

$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "an escaped-colon Mechanism bullet stops bad-record"

push_agents <<EOF
<source src=a>trailing
$RECORD_MAINTAIN
EOF
lr --run r1
expect_stop bad-record "a cmark-gfm <source> HTML block stops bad-record"

# File-level checks: symlink, NUL byte, bare CR, UTF-8 BOM.
rm -f "$TMP/seed/AGENTS.md"
printf '%s\n' "$RECORD_MAINTAIN" > "$TMP/seed/REAL.md"
ln -s REAL.md "$TMP/seed/AGENTS.md"
git -C "$TMP/seed" add REAL.md AGENTS.md
git -C "$TMP/seed" commit -q -m "symlink agents"
git -C "$TMP/seed" push -q "$SRV" main
lr --run r1
expect_stop bad-record "a symlinked AGENTS.md stops bad-record"
git -C "$TMP/seed" rm -q REAL.md AGENTS.md
git -C "$TMP/seed" commit -q -m "cleanup symlink"
git -C "$TMP/seed" push -q "$SRV" main

printf '# Project\n\0\n%s\n' "$RECORD_MAINTAIN" | push_agents
lr --run r1
expect_stop bad-record "a NUL byte in AGENTS.md stops bad-record"

printf '# Project\n%s\rtrailing\n' "$RECORD_MAINTAIN" | push_agents
lr --run r1
expect_stop bad-record "a bare CR in AGENTS.md stops bad-record"

printf '\357\273\277# Project\n\n%s\n' "$RECORD_MAINTAIN" | push_agents
lr --run r1
expect_stop bad-record "a leading UTF-8 BOM in AGENTS.md stops bad-record"

# Failed git read stops LOOKUP_FAILED record (exit 4), not no-landing-record.
printf '# Project\n\n%s\n' "$RECORD_MAINTAIN" | push_agents
BADGIT="$TMP/badgit"
mkdir -p "$BADGIT"
REAL_GIT=$(command -v git)
cat > "$BADGIT/git" <<GITSHIM
#!/bin/sh
if [ "\$1" = "ls-tree" ]; then exit 128; fi
exec "$REAL_GIT" "\$@"
GITSHIM
chmod +x "$BADGIT/git"
(cd "$WORK" && PATH="$BADGIT:$SHIMD:$PATH" bash "$SCRIPT" --repo owner/name --run r1) > "$TMP/out" 2> "$TMP/err"
RC=$?
LAST=$(tail -n 1 "$TMP/out")
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED record "* ]]; then ok
else bad "a failed git ls-tree stops LOOKUP_FAILED record (exit 4), got exit $RC: $LAST"; fi

# --- read failures ---

new_repo
ready_pr 1 feat/one "$H1"
echo timeline > "$FIX/fail-timeline"
echo 'gh: Service Unavailable (HTTP 503)' > "$FIX/gh-stderr"
GH_DEBUG=api lr --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED timeline "* ]]; then ok; else bad "a timeline read failure is LOOKUP_FAILED: $LAST"; fi
expect_stderr 'gh: Service Unavailable (HTTP 503)' "a timeline read failure quotes gh's error"
case "$LAST" in *SECRET-313*) bad "a GH_DEBUG header reached the excerpt: $LAST" ;; *) ok ;; esac
expect_remote_lock absent "a read failure takes no lock"
expect_calls 3 issues/1/timeline "a timeline read that keeps failing with a 503 stops after three attempts"
expect_err 'list-ready.sh: forge read failed (attempt 2 of 3): gh: Service Unavailable (HTTP 503); retrying in 2s' "each retry is logged"
expect_no_err SECRET-313 "a GH_DEBUG header never reaches the retry line"

new_repo
ready_pr 1 feat/one "$H1"
printf 'timeline\n2\n' > "$FIX/fail-timeline"
echo 'gh: Service Unavailable (HTTP 503)' > "$FIX/gh-stderr"
lr --run r1
expect_ready 1 "a timeline read that fails twice with a 503 then works"
expect_calls 3 issues/1/timeline "the timeline read took three attempts"
expect_err 'list-ready.sh: forge read failed (attempt 1 of 3): gh: Service Unavailable (HTTP 503); retrying in 1s' "the first retry is logged"

new_repo
ready_pr 1 feat/one "$H1"
echo collaborators/ > "$FIX/fail-permission"
printf 'gh: Not Found (HTTP 404)\n' > "$FIX/gh-stderr"
GH_DEBUG=api lr --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED permission "* ]]; then ok; else bad "a permission read failure is LOOKUP_FAILED: $LAST"; fi
expect_stderr 'gh: Not Found (HTTP 404)' "a permission read failure quotes gh's error"
expect_calls 1 collaborators/ "a 404 is not retried"
expect_no_err 'forge read failed' "a 404 logs no retry"
case "$LAST" in *SECRET-313*) bad "a GH_DEBUG header reached the permission excerpt: $LAST" ;; *) ok ;; esac

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
echo graphql > "$FIX/fail-threads"
echo 'GraphQL: API rate limit exceeded' > "$FIX/gh-stderr"
lr --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED review-threads "* ]]; then ok; else bad "a thread read failure is LOOKUP_FAILED: $LAST"; fi
expect_stderr 'GraphQL: API rate limit exceeded' "a thread read failure quotes gh's error"
expect_err 'forge read failed (attempt 2 of 3): GraphQL: API rate limit exceeded' "a rate limit is retried"
expect_remote_lock r1 "a read failure mid-batch neither releases nor moves the lock"

new_repo
ready_pr 1 feat/one "$H1"
echo actions/runs > "$FIX/fail-runs"
printf 'gh: "quoted" failure\nline two %0400d\n' 0 > "$FIX/gh-stderr"
lr --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED actions-runs "* ]]; then ok; else bad "a CI-run read failure is LOOKUP_FAILED: $LAST"; fi
case "$LAST" in *'"stderr":"gh: \"quoted\" failure\u000aline two 000'*) ok ;; *) bad "the excerpt is not JSON-escaped: $LAST" ;; esac
expect_stderr "$(head -c 300 "$FIX/gh-stderr")" "the excerpt is cut to 300 bytes"

new_repo
echo list > "$FIX/fail-list"
echo 'gh: Bad credentials (HTTP 401)' > "$FIX/gh-stderr"
lr --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED pr-list "* ]]; then ok; else bad "a PR-list failure is LOOKUP_FAILED, not an empty list: $LAST"; fi
expect_stderr 'gh: Bad credentials (HTTP 401)' "a PR-list failure quotes gh's error"
expect_calls 1 'pr list' "a 401 is not retried"
expect_remote_lock absent "a failed listing never reads as empty"

# A lookup failure after reads that worked carries no excerpt, even though
# every one of those reads wrote to stderr.
new_repo
ready_pr 1 feat/one "not-an-oid"
GH_DEBUG=api lr --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED pr-list "* ]]; then ok; else bad "an unparseable head is LOOKUP_FAILED: $LAST"; fi
case "$LAST" in *'"stderr"'*) bad "a failure past successful reads carries an excerpt: $LAST" ;; *) ok ;; esac

# --- git fetch failures ---

# FETCH_SHIM fails each git fetch whose arguments contain the first line
# of $FIX/git-fetch-fail, writing $FIX/git-fetch-stderr and exiting 128 as
# git does. A second line caps how many matching calls fail (absent: all);
# with $FIX/git-fetch-fake-ok, a matching call past the cap writes the same
# stderr and exits 0 without fetching. $FIX/git-fetch-calls counts the
# matching calls. Every other git command runs the real git.
FETCH_SHIM="$TMP/fetch-shim"
mkdir -p "$FETCH_SHIM"
{
  echo '#!/bin/bash'
  printf 'REAL_GIT=%q\n' "$(command -v git)"
  printf 'FIX=%q\n' "$FIX"
  cat <<'FETCHEOF'
if [ "${1:-}" = fetch ] && [ -f "$FIX/git-fetch-fail" ]; then
  { IFS= read -r match; IFS= read -r cap; } < "$FIX/git-fetch-fail"
  case " $* " in
    *"$match"*)
      n=$(( $(cat "$FIX/git-fetch-calls" 2>/dev/null || echo 0) + 1 ))
      echo "$n" > "$FIX/git-fetch-calls"
      if [ -z "$cap" ] || [ "$n" -le "$cap" ]; then
        cat "$FIX/git-fetch-stderr" >&2; exit 128
      fi
      if [ -f "$FIX/git-fetch-fake-ok" ]; then
        cat "$FIX/git-fetch-stderr" >&2; exit 0
      fi
      ;;
  esac
fi
exec "$REAL_GIT" "$@"
FETCHEOF
} > "$FETCH_SHIM/git"
chmod +x "$FETCH_SHIM/git"
fetch_fail_fx() { # fetch_fail_fx <arg-text> <cap-or-empty> <stderr>
  printf '%s\n%s\n' "$1" "$2" > "$FIX/git-fetch-fail"
  printf '%s\n' "$3" > "$FIX/git-fetch-stderr"
}
expect_fetch_calls() { # expect_fetch_calls <count> <desc>: matching git fetch calls
  local n
  n=$(cat "$FIX/git-fetch-calls" 2>/dev/null)
  if [ "${n:-0}" -eq "$1" ]; then ok; else bad "$2: ${n:-0} matching git fetch calls, want $1"; fi
}
lr_fetch_shim() { # lr_fetch_shim <args...>: lr with FETCH_SHIM's git
  local saved="$SHIMD"
  SHIMD="$SHIMD:$FETCH_SHIM"; lr "$@"; SHIMD="$saved"
}
BASE_FETCH=refs/remotes/origin/main
LOCK_FETCH=refs/land/seen-lock
DNS_ERR="fatal: unable to access 'https://github.invalid/owner/name.git/': Could not resolve host: github.invalid"

new_repo
ready_pr 1 feat/one "$H1"
fetch_fail_fx "$BASE_FETCH" 2 "$DNS_ERR"
lr_fetch_shim --run r1
expect_ready 1 "a base fetch that fails twice with a DNS error then works"
expect_fetch_calls 3 "the base fetch took three attempts"
expect_err "list-ready.sh: git fetch failed (attempt 1 of 3): $DNS_ERR; retrying in 1s" "the first fetch retry is logged"
expect_err 'list-ready.sh: git fetch failed (attempt 2 of 3)' "the second fetch retry is logged"

new_repo
ready_pr 1 feat/one "$H1"
fetch_fail_fx "$BASE_FETCH" "" "$DNS_ERR"
lr_fetch_shim --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED base-fetch "* ]]; then ok; else bad "a base fetch that keeps failing is LOOKUP_FAILED base-fetch: $LAST"; fi
expect_stderr "$DNS_ERR" "a failed base fetch quotes git's error"
expect_fetch_calls 3 "a persistent DNS error stops after three attempts"
expect_remote_lock absent "a failed base fetch takes no lock"

new_repo
ready_pr 1 feat/one "$H1"
fetch_fail_fx "$BASE_FETCH" "" "fatal: couldn't find remote ref main"
lr_fetch_shim --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED base-fetch "* ]]; then ok; else bad "a base fetch of a missing branch is LOOKUP_FAILED base-fetch: $LAST"; fi
expect_stderr "fatal: couldn't find remote ref main" "a missing branch quotes git's error"
expect_fetch_calls 1 "a missing branch is not retried"
expect_no_err 'git fetch failed' "a missing branch logs no retry"

new_repo
ready_pr 1 feat/one "$H1"
# Git's redirect error prints the asked-for URL with its userinfo, and the
# retry line quotes the first line, so the token is on both. A URL git
# can't parse is printed whole too, and its password may hold a raw slash
# or quote.
fetch_fail_fx "$BASE_FETCH" "" "error: Unable to find abc under https://x:TESTTOKEN@github.invalid/owner/name.git
fatal: unable to access 'https://x:TESTTOKEN/a'b@github.invalid/owner/name.git/'
fatal: unable to update url base from redirection:
  asked for: https://x:TESTTOKEN@github.invalid/owner/name.git/info/refs?service=git-upload-pack"
lr_fetch_shim --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED base-fetch "* ]]; then ok; else bad "a fetch error naming credentials is LOOKUP_FAILED base-fetch: $LAST"; fi
expect_err 'git fetch failed (attempt 1 of 3): error: Unable to find abc under https://github.invalid/' "the retry line keeps the URL without its userinfo"
if grep -qF 'asked for: https://github.invalid/owner/name.git/info/refs' "$TMP/out"; then ok; else bad "the excerpt keeps the URL without its userinfo: $LAST"; fi
if grep -qF "unable to access 'https://github.invalid/owner/name.git/'" "$TMP/out"; then ok; else bad "a password with a slash or quote is stripped too: $LAST"; fi
if grep -qF TESTTOKEN "$TMP/out"; then bad "a credential in git's error reached stdout: $LAST"; else ok; fi
expect_no_err TESTTOKEN "a credential in git's error never reaches stderr"

new_repo
ready_pr 1 feat/one "$H1"
git -C "$WORK" remote set-url origin 'https://x:TESTTOKEN@github.invalid/owner/name.git'
GIT_TRACE=1 GIT_TRACE_CURL=1 GIT_TRACE_REDACT=0 GIT_CURL_VERBOSE=1 lr --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED base-fetch "* ]]; then ok; else bad "a fetch from an unreachable token URL is LOOKUP_FAILED base-fetch: $LAST"; fi
case "$LAST" in *'"stderr":"fatal: unable to access'*) ok ;; *) bad "the fetch excerpt is git's error: $LAST" ;; esac
if grep -qF TESTTOKEN "$TMP/out"; then bad "a token in the remote URL reached stdout under git tracing: $LAST"; else ok; fi
expect_no_err TESTTOKEN "a token in the remote URL never reaches stderr under git tracing"

new_repo
ready_pr 1 feat/one "$H1"
plant_lock other 5
fetch_fail_fx "$LOCK_FETCH" 2 "$DNS_ERR"
lr_fetch_shim --run r1
expect_stop lock-held "a lock fetch that fails twice then works still reads the lock"
expect_fetch_calls 3 "the lock fetch took three attempts"

new_repo
ready_pr 1 feat/one "$H1"
plant_lock other 5
fetch_fail_fx "$LOCK_FETCH" "" "$DNS_ERR"
lr_fetch_shim --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED lock-read "* ]]; then ok; else bad "a lock fetch that keeps failing is LOOKUP_FAILED lock-read: $LAST"; fi
expect_stderr "$DNS_ERR" "a failed lock fetch quotes git's error"
expect_fetch_calls 3 "a failing lock fetch stops after three attempts"

# A lock released between ls-remote and the fetch is the race the OID
# check reports, not a missing branch the lander would end the batch on.
new_repo
ready_pr 1 feat/one "$H1"
plant_lock other 5
fetch_fail_fx "$LOCK_FETCH" "" "fatal: couldn't find remote ref refs/land/lock"
lr_fetch_shim --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == 'LOOKUP_FAILED lock-read {"detail":"refs/land/lock moved while it was read; list again"}' ]]; then ok
else bad "a lock gone before its fetch asks for a fresh list with no excerpt: $LAST"; fi
expect_fetch_calls 1 "a vanished lock is not retried"

# The fake fetch writes git's progress lines and succeeds without
# creating the seen-lock ref, so the OID check after it fails.
new_repo
ready_pr 1 feat/one "$H1"
plant_lock other 5
fetch_fail_fx "$LOCK_FETCH" 0 "From $SRV
 * branch            refs/land/lock -> refs/land/seen-lock"
touch "$FIX/git-fetch-fake-ok"
lr_fetch_shim --run r1
if [ "$RC" -eq 4 ] && [[ "$LAST" == "LOOKUP_FAILED lock-read "* ]]; then ok; else bad "a fetch that left no seen-lock ref is LOOKUP_FAILED lock-read: $LAST"; fi
case "$LAST" in *'"stderr"'*) bad "a successful fetch's output reached a later failure: $LAST" ;; *) ok ;; esac

# --- merges awaiting cleanup ---

new_repo
ready_pr 1 feat/one "$H1"
lr --run r1
expect_rc 0 "a list without a cleanup-pending file succeeds"
[ "$(printf '%s' "$JSON" | jq -c .cleanup_pending)" = "[]" ] && ok || bad "no file reports no merges awaiting cleanup: $LAST"
CLEANUP="$WORK/.git/land-approved-prs/cleanup-pending"
mkdir -p "${CLEANUP%/*}"
printf '7\n9\n7\n' > "$CLEANUP"
lr --run r1
[ "$(printf '%s' "$JSON" | jq -c .cleanup_pending)" = "[7,9]" ] && ok || bad "the list reports each merge awaiting cleanup once: $LAST"
grep -qF 'cleanup pending: #7, #9' "$TMP/out" && ok || bad "the prose names the merges awaiting cleanup"
lr --release r1
[ -s "$CLEANUP" ] && ok || bad "release keeps the cleanup-pending file, which outlives a run"
: > "$FIX/calls.log"
lr --cleaned 7
expect_rc 0 "a finished cleanup is cleared"
[ "$(printf '%s' "$JSON" | jq -r .removed)" = true ] && ok || bad "cleaned reports the removal: $LAST"
[ "$(cat "$CLEANUP")" = 9 ] && ok || bad "cleaned removes every entry for that PR and keeps the others"
[ ! -s "$FIX/calls.log" ] && ok || bad "cleaned reads the forge"
lr --cleaned 7
[ "$(printf '%s' "$JSON" | jq -r .removed)" = false ] && ok || bad "cleaning an unlisted PR reports nothing removed: $LAST"
lr --run r1
[ "$(printf '%s' "$JSON" | jq -c .cleanup_pending)" = "[9]" ] && ok || bad "the next list reports what remains: $LAST"

fi

echo "list-ready matrix: $pass passed, $fail failed$([ "$skip" -eq 0 ] || echo ", behavior half skipped")"
[ "$fail" -eq 0 ]
