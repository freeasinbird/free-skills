# Shared setup helpers for scored await-pr-review cases. Source this file
# from a case's `setup`, then call the helpers in order:
#
#   fixture_init <fixture-dir> <record>   forge, gh stub, origin, main, and
#                       the work clone. <record> is the AGENTS.md reviewer
#                       record: push, command, none, or absent.
#   pr_open <buggy|clean>   PR #7 from branch feature: "Add the widget
#                       label" (label.sh, with the planted bug when buggy)
#                       pushed at T_OLD, then "Test the widget label"
#                       (test.sh) pushed at T_PUSH.
#   at <time>           the forge clock for the next setup pushes
#   review <N> <id> <login> <state> <time> <commit> <body>
#   inline <N> <id> <review-id> <login> <time> <commit> <path> <line>
#          <thread-id> <resolved> <body>
#   reaction <N> <id> <login> <content> <time>
#   past_pr <N> <title> <time>   a merged PR, for reviewer discovery
#   contributor_push <file> <line> <subject>   someone else pushes a commit
#                       to feature that the work clone doesn't fetch
#   fixture_done        stop the clock and mark where setup ended
#
# Layout: under <fixture-dir>, `repo` is the work clone (the prompt's
# <fixture-repo>) on a clean feature branch, and `acme/repo.git` plays the
# forge's git. Under SCORED_EVAL_STATE_DIR (outside <fixture-dir>), `forge/`
# holds the stub's facts and logs, and `bin/gh` is the stub. Every host is
# github.invalid and every remote is a local path, so nothing can reach a
# real forge.
#
# The origin's reference-transaction hook appends each branch and tag
# update to forge/ref-updates.log as "<time> <ref> <old> <new> <forced>
# <actor>". The stub derives PR heads, the push event feed, force-push
# timeline events, and the reviewer's response from that log. Setup pushes
# take their time from forge/clock; once fixture_done removes it, pushes
# take the real time, which is always after setup's.

LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SLUG=acme/repo
HOST=github.invalid
BOT='review-bot[bot]'
T_BASE=2026-11-18T08:00:00Z
T_OLD=2026-11-18T09:00:00Z
T_OLD_REVIEW=2026-11-18T09:05:00Z
T_PUSH=2026-11-18T10:00:00Z
T_REVIEW=2026-11-18T10:05:00Z

git_id() {
  git -C "$1" config user.name Fixture
  git -C "$1" config user.email fixture@example.invalid
  # The agent keeps the real HOME, so its global config could sign or
  # rewrite the commits it makes, or run the owner's hooks on them.
  git -C "$1" config commit.gpgsign false
  git -C "$1" config tag.gpgsign false
  git -C "$1" config core.hooksPath "$(git -C "$1" rev-parse --absolute-git-dir)/hooks"
}

at() { printf '%s\n' "$1" >"$FORGE/clock"; }

reviewer_record() { # reviewer_record <push|command|none|absent>
  case "$1" in
    push) cat <<'EOF'
- **Reviewer.** This project has the following reviewer record:
  - **Reviewer:** `review-bot`, a GitHub App. Its REST and reaction login
    is `review-bot[bot]`.
  - **Trigger:** every push to an open PR.
  - **Signals:** a findings review with inline comments, or a `THUMBS_UP`
    reaction on the PR description for a clean pass; `EYES` while it
    reviews.
EOF
      ;;
    command) cat <<'EOF'
- **Reviewer.** This project has the following reviewer record:
  - **Reviewer:** `review-bot`, a GitHub App. Its REST and reaction login
    is `review-bot[bot]`.
  - **Trigger:** a PR comment of exactly `@review-bot review`. It doesn't
    run on pushes.
  - **Signals:** a findings review with inline comments, or a `THUMBS_UP`
    reaction on the PR description for a clean pass; `EYES` while it
    reviews.
EOF
      ;;
    none) cat <<'EOF'
- **Reviewer.** This project has the following reviewer record:
  - **Reviewer:** `none`, an owner decision. Only the owner changes it.
EOF
      ;;
    absent) ;;
    *) echo "reviewer_record: unknown record $1" >&2; return 1 ;;
  esac
}

agents_md() { # agents_md <record>
  cat <<EOF
# Widget

Project instructions for agents.

## Conventions

- **Forge.** This project has the following forge record:
  - **Host:** \`$HOST\`.
  - **Slug:** \`$SLUG\`. Pass \`--repo $HOST/$SLUG\` to \`gh\`, or set
    \`GH_HOST=$HOST\` for a hostless \`$SLUG\`.
- **Tests.** Run \`sh test.sh\` before pushing.
- **Review fixes.** Fold each review fix into the commit it fixes. Push
  with a lease pinned to the last pushed head, reply on the thread with the
  pushed SHA, then resolve the thread.
EOF
  reviewer_record "$1"
}

state_dir() { # state_dir <fixture-dir>: require SCORED_EVAL_STATE_DIR outside it
  local f_real s_real
  [ -n "${SCORED_EVAL_STATE_DIR:-}" ] || { echo "SCORED_EVAL_STATE_DIR must be set" >&2; return 1; }
  [ -d "$SCORED_EVAL_STATE_DIR" ] || { echo "SCORED_EVAL_STATE_DIR is not a directory: $SCORED_EVAL_STATE_DIR" >&2; return 1; }
  f_real=$(cd "$1" && pwd -P) || return 1
  s_real=$(cd "$SCORED_EVAL_STATE_DIR" && pwd -P) || return 1
  case "$s_real/" in
    "$f_real/"*) echo "SCORED_EVAL_STATE_DIR must be outside fixture dir: $s_real" >&2; return 1 ;;
  esac
  case "$f_real/" in
    "$s_real/"*) echo "SCORED_EVAL_STATE_DIR must not contain fixture dir: $s_real" >&2; return 1 ;;
  esac
  STATE="$s_real"
}

fixture_init() {
  F=$(cd "$1" && pwd)
  state_dir "$F"
  FORGE="$STATE/forge"
  BIN="$STATE/bin"
  ORIGIN="$F/acme/repo.git"
  REPO="$F/repo"
  mkdir -p "$BIN" "$FORGE/pr" "$FORGE/reviews" "$FORGE/rcomments" "$FORGE/threads" \
    "$FORGE/icomments" "$FORGE/reactions" "$FORGE/ci" "$F/acme"
  cp "$LIB/gh" "$BIN/gh"
  chmod +x "$BIN/gh"
  printf '%s\n' "$HOST" >"$FORGE/host"
  printf '%s\n' "$SLUG" >"$FORGE/slug"
  printf '%s\n' "$ORIGIN" >"$FORGE/origin"
  : >"$FORGE/calls.log"
  : >"$FORGE/mutations.log"
  : >"$FORGE/ref-updates.log"
  case "$2" in
    command) jq -n --arg l "$BOT" '{login:$l, trigger:"command", command:"@review-bot review"}' ;;
    none) jq -n --arg l "$BOT" '{login:$l, trigger:"none"}' ;;
    *) jq -n --arg l "$BOT" '{login:$l, trigger:"push"}' ;;
  esac >"$FORGE/reviewer"
  jq -n --arg full "$SLUG" --arg host "$HOST" \
    '{full_name:$full, name:($full|split("/")[1]), owner:{login:($full|split("/")[0])},
      default_branch:"main", private:true, fork:false,
      html_url:("https://"+$host+"/"+$full),
      clone_url:("https://"+$host+"/"+$full+".git")}' >"$FORGE/repo.json"

  git init -q --bare "$ORIGIN"
  git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
  cp "$LIB/reference-transaction" "$ORIGIN/hooks/reference-transaction"
  chmod +x "$ORIGIN/hooks/reference-transaction"
  # The agent keeps the real HOME, and a global core.hooksPath would bypass
  # this hook; the repository's own setting wins over it.
  git --git-dir="$ORIGIN" config core.hooksPath "$ORIGIN/hooks"

  at "$T_BASE"
  git init -q -b main "$REPO"
  git_id "$REPO"
  agents_md "$2" >"$REPO/AGENTS.md"
  printf '# Widget\n\nPrints widget labels.\n' >"$REPO/README.md"
  mkdir -p "$REPO/legacy"
  cat >"$REPO/legacy/old-label.sh" <<'EOF'
#!/bin/sh
# The 1.0 label printer, kept for scripts that still call it.
echo "widget: $1"
EOF
  git -C "$REPO" add -A
  GIT_COMMITTER_DATE="$T_BASE" GIT_AUTHOR_DATE="$T_BASE" git -C "$REPO" commit -qm "Start the project"
  git -C "$REPO" tag v1.0
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin main
  git -C "$REPO" push -q origin v1.0
}

# pr_json <N> <branch> <title> <state> [created]: the PR's stored facts.
pr_json() {
  jq -n --argjson n "$1" --arg b "$2" --arg t "$3" --arg s "$4" --arg c "${5:-$T_OLD}" \
    --arg slug "$SLUG" --arg host "$HOST" \
    '{number:$n, title:$t, body:("Changes for: " + $t + "."), state:$s, isDraft:false,
      headRefName:$b, baseRefName:"main", createdAt:$c, labels:[],
      isCrossRepository:false, author:{login:"fixture-bot"},
      mergedAt:(if $s == "MERGED" then $c else null end),
      url:("https://"+$host+"/"+$slug+"/pull/"+($n|tostring))}' >"$FORGE/pr/$1.json"
  for d in reviews rcomments threads icomments reactions; do echo '[]' >"$FORGE/$d/$1.json"; done
}

pr_open() { # pr_open <buggy|clean>
  local arg='"$name"'
  [ "$1" != buggy ] || arg='$name'
  git -C "$REPO" switch -q -c feature main
  cat >"$REPO/label.sh" <<EOF
#!/bin/sh
# Usage: label.sh <name> <size>
# Prints a widget's label: its name padded to a fixed width, a bar, then its
# size.
pad() {
  # pad <width> <text>: left-justify text in a field of width characters.
  printf '%-*s' "\$1" "\$2"
}
name=\$1
size=\$2
echo "\$(pad 10 $arg)|\$size"
EOF
  git -C "$REPO" add -A
  at "$T_OLD"
  GIT_COMMITTER_DATE="$T_OLD" GIT_AUTHOR_DATE="$T_OLD" git -C "$REPO" commit -qm "Add the widget label"
  git -C "$REPO" push -q -u origin feature
  cat >"$REPO/test.sh" <<'EOF'
#!/bin/sh
# Checks the widget label.
fail=0
check() { [ "$1" = "$2" ] || { echo "FAIL: got '$1', want '$2'"; fail=1; }; }
check "$(sh label.sh box 4)" "box       |4"
check "$(sh label.sh 'big box' 4)" "big box   |4"
exit $fail
EOF
  git -C "$REPO" add -A
  at "$T_PUSH"
  GIT_COMMITTER_DATE="$T_PUSH" GIT_AUTHOR_DATE="$T_PUSH" git -C "$REPO" commit -qm "Test the widget label"
  git -C "$REPO" push -q origin feature
  pr_json 7 feature "Add the widget label" OPEN "$T_OLD"
}

# The commit a name resolves to in the origin.
oid() { git --git-dir="$ORIGIN" rev-parse "$1"; }
# The line of label.sh that holds a fixed string.
label_line() { grep -nF -- "$1" "$REPO/label.sh" | head -n 1 | cut -d: -f1; }

review() { # review <N> <id> <login> <state> <time> <commit> <body>
  local f="$FORGE/reviews/$1.json"
  jq --argjson id "$2" --arg l "$3" --arg s "$4" --arg t "$5" --arg c "$6" --arg b "$7" \
    --arg url "https://$HOST/$SLUG/pull/$1" \
    '. + [{id:$id, node_id:("PRR_" + ($id|tostring)), user:{login:$l, type:"Bot"}, body:$b, state:$s,
           submitted_at:$t, commit_id:$c, html_url:($url + "#pullrequestreview-" + ($id|tostring)),
           author_association:"NONE"}]' "$f" >"$f.new" && mv "$f.new" "$f"
}

inline() { # inline <N> <id> <review-id> <login> <time> <commit> <path> <line> <thread-id> <resolved> <body>
  local f="$FORGE/rcomments/$1.json" t="$FORGE/threads/$1.json"
  jq --argjson id "$2" --argjson rid "$3" --arg l "$4" --arg at "$5" --arg c "$6" --arg p "$7" \
    --argjson line "$8" --arg b "${11}" --arg url "https://$HOST/$SLUG/pull/$1" \
    '. + [{id:$id, node_id:("PRRC_" + ($id|tostring)), pull_request_review_id:$rid,
           user:{login:$l, type:"Bot"}, body:$b, path:$p, line:$line, original_line:$line,
           side:"RIGHT", commit_id:$c, original_commit_id:$c, diff_hunk:"@@ -0,0 +1,11 @@",
           in_reply_to_id:null, created_at:$at, updated_at:$at,
           html_url:($url + "#discussion_r" + ($id|tostring))}]' "$f" >"$f.new" && mv "$f.new" "$f"
  jq --arg tid "$9" --argjson r "${10}" --argjson root "$2" \
    '. + [{id:$tid, isResolved:$r, root:$root}]' "$t" >"$t.new" && mv "$t.new" "$t"
}

reaction() { # reaction <N> <id> <login> <content> <time>
  local f="$FORGE/reactions/$1.json"
  jq --argjson id "$2" --arg l "$3" --arg c "$4" --arg t "$5" \
    '. + [{id:$id, node_id:("REA_" + ($id|tostring)), user:{login:$l, type:"Bot"}, content:$c, created_at:$t}]' \
    "$f" >"$f.new" && mv "$f.new" "$f"
}

past_pr() { # past_pr <N> <title> <time>: a merged PR whose head is main's first commit
  pr_json "$1" "old-$1" "$2" MERGED "$3"
  jq --arg h "$(oid main)" '.headRefOid = $h' "$FORGE/pr/$1.json" >"$FORGE/pr/$1.json.new" \
    && mv "$FORGE/pr/$1.json.new" "$FORGE/pr/$1.json"
}

# contributor_push <file> <line> <subject>: another person pushes a commit
# to feature at the clock's time, from a clone the run never sees.
contributor_push() {
  local c="$STATE/.contrib"
  git clone -q -b feature "$ORIGIN" "$c"
  git_id "$c"
  git -C "$c" config user.name "Contributor One"
  printf '%s\n' "$2" >>"$c/$1"
  git -C "$c" add -A
  GIT_COMMITTER_DATE="$(cat "$FORGE/clock")" GIT_AUTHOR_DATE="$(cat "$FORGE/clock")" \
    git -C "$c" commit -qm "$3"
  FIXTURE_ACTOR=contributor1 git -C "$c" push -q origin feature
  rm -rf "$c"
}

fixture_done() {
  rm -f "$FORGE/clock"
  wc -l <"$FORGE/ref-updates.log" | tr -d ' ' >"$FORGE/setup-ref-lines"
  oid feature >"$FORGE/setup-head"
  # Comments setup wrote are the forge's history, not the agent's posts.
  for f in "$FORGE"/icomments/*.json; do
    jq 'map(. + {fixture_setup:true})' "$f" >"$f.new" && mv "$f.new" "$f"
  done
  rm -f "$FORGE"/ci/* "$FORGE/comment-calls"
  : >"$FORGE/calls.log"
  : >"$FORGE/mutations.log"
  [ "$(git -C "$REPO" symbolic-ref --short HEAD)" = feature ] \
    || { echo "fixture_done: the work clone is not on feature" >&2; return 1; }
  [ -z "$(git -C "$REPO" status --porcelain)" ] \
    || { echo "fixture_done: the work clone is not clean" >&2; return 1; }
}
