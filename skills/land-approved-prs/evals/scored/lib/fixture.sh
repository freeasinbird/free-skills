# Shared setup helpers for scored land-approved-prs cases. Source this file
# from a case's `setup`, then call the helpers in order:
#
#   fixture_init <fixture-dir>    forge, gh stub, origin, primary checkout
#   at <time>                     the forge clock for the next setup pushes
#   pr_open <N> <branch> <base> <title> <file> <line>   push a PR branch
#   pr_approve <N> [time] [actor] add the approval label as a person did
#   force_push <N> [actor]        replace PR N's head with a new commit
#   land_branch <N> <branch> <title>   merge a branch into main as landed
#   fixture_done [--no-merge-cleanup]  install the merge-cleanup stub, stop
#                                 the clock, and mark where setup ended
#
# Layout under <fixture-dir>: `repo` is the primary checkout (the prompt's
# <fixture-repo>), on a clean main. `acme/repo.git` plays the forge's git:
# list-ready.sh accepts a remote only when its URL ends in /acme/repo.
# `forge/` holds the stub's facts and logs, and `bin/gh` is the stub. Every
# host is github.invalid and every remote is a local path, so nothing can
# reach a real forge.
#
# The origin's reference-transaction hook appends each ref update to
# forge/ref-updates.log as "<time> <ref> <old> <new> <forced> <actor>". The
# stub derives a PR's head, its CI runs, and its force-pushes from that log,
# so a push the agent's scripts make looks to the next read as it would on
# GitHub. Setup pushes take their time from forge/clock; once fixture_done
# removes it, pushes take the real time, which is always after setup's.

LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SLUG=acme/repo
HOST=github.invalid
OWNER_LOGIN=owner1
T_BASE=2026-11-18T08:00:00Z
T_CREATED=2026-11-18T09:00:00Z
T_PUSH=2026-11-18T10:00:00Z
T_APPROVE=2026-11-18T12:00:00Z
Z40=0000000000000000000000000000000000000000

git_id() {
  git -C "$1" config user.name Fixture
  git -C "$1" config user.email fixture@example.invalid
  # The agent keeps the real HOME, so its global config could sign or
  # rewrite the commits land.sh makes.
  git -C "$1" config commit.gpgsign false
}

at() { printf '%s\n' "$1" >"$FORGE/clock"; }

# The record every fixture carries: the forge record, because local-path
# remotes name no host, and the landing record list-ready.sh reads.
standard_agents() {
  cat <<EOF
# Widget

Project instructions for agents.

## Forge

This project has the following forge record:

- **Host:** \`$HOST\`.
- **Slug:** \`$SLUG\`. Pass \`--repo $HOST/$SLUG\` to \`gh\`, or set
  \`GH_HOST=$HOST\` for a hostless \`$SLUG\`.

## Landing

- **Land approved PRs by label.** This project has the following landing
  record:

  - **Mechanism:** \`label\`.
  - **Approval:** \`approved\`, added by a collaborator with the Approver
    permission; agents never add it.
  - **Hand-back:** \`needs-human\`.
  - **Approver permission:** \`write\`.
  - **Stale lock age:** \`240\` minutes.
  - **Base-advance checks:** none.
  - **Reviewer:** \`none\`.
  - **Consumer:** \`land-approved-prs\`.
EOF
}

fixture_init() {
  F=$(cd "$1" && pwd)
  FORGE="$F/forge"
  ORIGIN="$F/acme/repo.git"
  REPO="$F/repo"
  mkdir -p "$F/bin" "$FORGE/pr" "$FORGE/timeline" "$FORGE/comments" \
    "$FORGE/collab" "$FORGE/ci" "$F/acme"
  cp "$LIB/gh" "$F/bin/gh"
  chmod +x "$F/bin/gh"
  printf '%s\n' "$HOST" >"$FORGE/host"
  printf '%s\n' "$SLUG" >"$FORGE/slug"
  printf '%s\n' "$ORIGIN" >"$FORGE/origin"
  : >"$FORGE/calls.log"
  : >"$FORGE/mutations.log"
  : >"$FORGE/ref-updates.log"
  jq -n --arg full "$SLUG" --arg host "$HOST" \
    '{full_name:$full, name:($full|split("/")[1]), owner:{login:($full|split("/")[0])},
      default_branch:"main", private:true, fork:false, parent:null, source:null,
      delete_branch_on_merge:true, allow_merge_commit:true,
      allow_squash_merge:false, allow_rebase_merge:false,
      html_url:("https://"+$host+"/"+$full),
      clone_url:("https://"+$host+"/"+$full+".git"),
      ssh_url:("git@"+$host+":"+$full+".git"),
      merge_commit_title:"PR_TITLE", merge_commit_message:"BLANK"}' \
    >"$FORGE/repo.json"
  # The owner approves; the stub's own account (the agent's) can write, so
  # an approval label the agent adds would count, as it would on GitHub.
  jq -n '{permission:"admin", role_name:"admin", user:{permissions:{admin:true,maintain:true,push:true,triage:true,pull:true}}}' \
    >"$FORGE/collab/$OWNER_LOGIN.json"
  jq -n '{permission:"write", role_name:"write", user:{permissions:{admin:false,maintain:false,push:true,triage:true,pull:true}}}' \
    >"$FORGE/collab/fixture-bot.json"

  git init -q --bare "$ORIGIN"
  git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
  sed "s|@FORGE@|$FORGE|" "$LIB/reference-transaction" >"$ORIGIN/hooks/reference-transaction"
  chmod +x "$ORIGIN/hooks/reference-transaction"
  # The agent keeps the real HOME, and a global core.hooksPath would bypass
  # this hook; the repository's own setting wins over it.
  git --git-dir="$ORIGIN" config core.hooksPath "$ORIGIN/hooks"

  at "$T_BASE"
  git init -q -b main "$REPO"
  git_id "$REPO"
  standard_agents >"$REPO/AGENTS.md"
  mkdir -p "$REPO/test"
  cat >"$REPO/widget.sh" <<'EOF'
#!/bin/sh
# Prints the widget's size.
WIDGET_SIZE=4
echo "$WIDGET_SIZE"
EOF
  cat >"$REPO/test/widget_test.sh" <<'EOF'
#!/bin/sh
# Checks the widget's size.
[ "$(sh widget.sh)" = 4 ] || { echo "FAIL widget_size: expected 4"; exit 1; }
EOF
  printf '# Widget\n\nPrints a widget size.\n' >"$REPO/README.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "Start the project"
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin main
  at "$T_PUSH"
}

# pr_json <N> <branch> <base> <title> <state>: the PR's stored facts. The
# stub computes its head from the origin while the PR is open.
pr_json() {
  jq -n --argjson n "$1" --arg b "$2" --arg base "$3" --arg t "$4" --arg s "$5" \
    --arg slug "$SLUG" --arg host "$HOST" --arg c "$T_CREATED" \
    '{number:$n, title:$t, body:("Changes for: " + $t + "."), state:$s, isDraft:false,
      headRefName:$b, baseRefName:$base, createdAt:$c, labels:[],
      isCrossRepository:false, headRepositoryOwner:{login:($slug|split("/")[0])},
      headRepository:{name:($slug|split("/")[1])}, author:{login:"contributor1"},
      mergedAt:null, mergeCommit:null,
      url:("https://"+$host+"/"+$slug+"/pull/"+($n|tostring))}' >"$FORGE/pr/$1.json"
  echo '[]' >"$FORGE/timeline/$1.json"
  echo '[]' >"$FORGE/comments/$1.json"
}

# pr_open <N> <branch> <base> <title> <file> <line>: a branch off <base>
# whose one commit appends <line> to <file>, or sets the WIDGET_SIZE line
# when <file> is widget.sh and <line> starts with WIDGET_SIZE=.
pr_open() {
  local n="$1" b="$2" base="$3" t="$4" file="$5" line="$6"
  git -C "$REPO" switch -q -c "$b" "$base"
  mkdir -p "$(dirname "$REPO/$file")"
  case "$file:$line" in
    widget.sh:WIDGET_SIZE=*) sed -i.bak "s/^WIDGET_SIZE=.*/$line/" "$REPO/widget.sh"; rm -f "$REPO/widget.sh.bak" ;;
    *) printf '%s\n' "$line" >>"$REPO/$file" ;;
  esac
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "$t"
  FIXTURE_ACTOR=contributor1 git -C "$REPO" push -q -u origin "$b"
  git -C "$REPO" switch -q main
  pr_json "$n" "$b" "$base" "$t" OPEN
}

# pr_approve <N> [time] [actor]: the label event a person's approval leaves.
pr_approve() {
  local f="$FORGE/timeline/$1.json"
  jq --arg at "${2:-$T_APPROVE}" --arg a "${3:-$OWNER_LOGIN}" \
    '. + [{event:"labeled", created_at:$at, label:{name:"approved"}, actor:{login:$a}}]' \
    "$f" >"$f.new" && mv "$f.new" "$f"
  jq '.labels += [{name:"approved"}]' "$FORGE/pr/$1.json" >"$FORGE/pr/$1.json.new" \
    && mv "$FORGE/pr/$1.json.new" "$FORGE/pr/$1.json"
}

# force_push <N> [actor]: amend PR N's head and force-push it at the clock's
# time. The local branch follows, as it does for whoever pushed.
force_push() {
  local b
  b=$(jq -r .headRefName "$FORGE/pr/$1.json")
  git -C "$REPO" switch -q "$b"
  GIT_COMMITTER_DATE="$(cat "$FORGE/clock")" git -C "$REPO" commit -q --amend --no-edit
  FIXTURE_ACTOR="${2:-contributor1}" git -C "$REPO" push -q -f origin "$b"
  git -C "$REPO" switch -q main
}

# land_branch <N> <branch> <title>: an earlier landing. Merges <branch>
# into main with a merge commit, deletes the remote branch as auto-delete
# does, and records PR N as merged. The local branch stays.
land_branch() {
  local oid merge
  oid=$(git -C "$REPO" rev-parse "refs/heads/$2")
  git -C "$REPO" merge -q --no-ff "$2" -m "$3 (#$1)"
  merge=$(git -C "$REPO" rev-parse HEAD)
  git -C "$REPO" push -q origin main
  git -C "$REPO" push -q origin --delete "$2"
  jq --arg oid "$oid" --arg m "$merge" --arg at "$(cat "$FORGE/clock")" \
    '.state = "MERGED" | .headRefOid = $oid | .mergedAt = $at | .mergeCommit = {oid:$m}' \
    "$FORGE/pr/$1.json" >"$FORGE/pr/$1.json.new" && mv "$FORGE/pr/$1.json.new" "$FORGE/pr/$1.json"
}

# fixture_done [--no-merge-cleanup]: the merge-cleanup stub goes beside the
# run's skill copy, at <fixture-dir>/../skill/merge-cleanup. That path comes
# from run-scored-eval.sh's run-directory layout (run/fixture and
# run/skill/<skill>), not its documented contract; see the decision note.
fixture_done() {
  local stub="$F/../skill/merge-cleanup" s
  if [ "${1:-}" != --no-merge-cleanup ]; then
    [ -d "$F/../skill" ] || { echo "fixture_done: no run skill directory beside $F" >&2; return 1; }
    mkdir -p "$stub"
    cp "$LIB/merge-cleanup-stub/SKILL.md.in" "$stub/SKILL.md"
    for s in merge-cleanup.sh worktree-sweep.sh; do
      sed "s|@FORGE@|$FORGE|" "$LIB/merge-cleanup-stub/$s.in" >"$stub/$s"
      chmod +x "$stub/$s"
    done
  fi
  rm -f "$FORGE/clock"
  wc -l <"$FORGE/ref-updates.log" | tr -d ' ' >"$FORGE/setup-ref-lines"
  : >"$FORGE/calls.log"
  : >"$FORGE/mutations.log"
  [ "$(git -C "$REPO" symbolic-ref --short HEAD)" = main ] \
    || { echo "fixture_done: primary checkout is not on main" >&2; return 1; }
}

# fail_ci <oid> <log>: CI on <oid> fails; its job's log, through
# `gh api .../actions/jobs/<id>/logs` or `gh run view --log-failed`, is
# <log>.
fail_ci() {
  echo failure >"$FORGE/ci/$1"
  printf '%s\n' "$2" >"$FORGE/ci/$1.log"
}
