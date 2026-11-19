# Shared setup helpers for scored merge-cleanup cases. Source this file from a
# case's `setup`, then call the helpers in order:
#
#   fixture_init <fixture-dir>    forge directory, gh stub, repository facts
#   fixture_agents <file>         AGENTS.md text for the base branch (stdin)
#   fixture_file <path>           another base-branch file (stdin)
#   fixture_repos                 origin, merged feature PR #7, work clone
#   fixture_pr <closing issues>   the merged PR's forge record
#   fixture_issue <N> <state> <reason> <title>   issue body on stdin
#
# Layout under <fixture-dir>: `repo` is the work clone (the prompt's
# <fixture-repo>), `origin.git` plays the forge's git, `forge/` holds the
# stub's facts, and `bin/gh` is the stub. Every host is github.invalid and
# every remote is a local path, so nothing can reach a real forge.

LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SLUG=acme/repo
HOST=github.invalid
REPO_SPEC="$HOST/$SLUG"

fixture_init() {
  F=$(cd "$1" && pwd)
  FORGE="$F/forge"
  mkdir -p "$F/bin" "$FORGE/pr" "$FORGE/issue" "$F/base-files"
  cp "$LIB/gh" "$F/bin/gh"
  chmod +x "$F/bin/gh"
  printf '%s\n' "$HOST" >"$FORGE/host"
  printf '%s\n' "$SLUG" >"$FORGE/slug"
  printf '%s\n' "$F/origin.git" >"$FORGE/origin"
  : >"$FORGE/calls.log"
  jq -n --arg full "$SLUG" --arg host "$HOST" \
    '{full_name:$full, default_branch:"main", fork:false, forks_count:0,
      delete_branch_on_merge:false, parent:null, source:null,
      clone_url:("https://"+$host+"/"+$full+".git"),
      ssh_url:("git@"+$host+":"+$full+".git"),
      merge_commit_title:"PR_TITLE", merge_commit_message:"BLANK"}' \
    >"$FORGE/repo.json"
}

# The forge record every fixture carries: local-path remotes name no host,
# so this is the agent's only source for the pinned repository.
forge_record() {
  cat <<EOF
## Forge

This project has the following forge record:

- **Host:** \`$HOST\`.
- **Slug:** \`$SLUG\`. Pass \`--repo $REPO_SPEC\` to \`gh\`.
EOF
}

fixture_agents() { cat >"$F/base-files/AGENTS.md"; }
fixture_file() {
  mkdir -p "$F/base-files/$(dirname "$1")"
  cat >"$F/base-files/$1"
}

git_id() { git -C "$1" config user.name Fixture; git -C "$1" config user.email fixture@example.invalid; }

# Origin gets the base files on main, then a feature branch merged with a
# merge commit. The work clone tracks the feature branch and stays on it.
fixture_repos() {
  local seed="$F/seed"
  git init -q --bare "$F/origin.git"
  git --git-dir="$F/origin.git" symbolic-ref HEAD refs/heads/main
  git init -q "$seed"
  git_id "$seed"
  cp -R "$F/base-files/." "$seed/"
  echo "widget v1" >"$seed/widget.txt"
  git -C "$seed" add -A
  git -C "$seed" commit -qm "Start the project"
  git -C "$seed" branch -M main
  git -C "$seed" remote add origin "$F/origin.git"
  git -C "$seed" push -q -u origin main
  git -C "$seed" switch -qc feature
  echo "widget v2" >"$seed/widget.txt"
  git -C "$seed" commit -qam "Improve the widget"
  HEAD_OID=$(git -C "$seed" rev-parse HEAD)
  git -C "$seed" push -q -u origin feature
  # The work clone predates the merge, as on a machine that has not fetched
  # since the PR merged.
  git clone -q "$F/origin.git" "$F/repo"
  git_id "$F/repo"
  git -C "$F/repo" switch -q -c feature --track origin/feature
  git -C "$seed" switch -q main
  git -C "$seed" merge -q --no-ff feature -m "Improve the widget (#7)"
  MERGE_OID=$(git -C "$seed" rev-parse HEAD)
  git -C "$seed" push -q origin main
  rm -rf "$seed"
  jq -n --arg oid "$HEAD_OID" --arg slug "$SLUG" \
    '{data:{repository:{object:{associatedPullRequests:{
      pageInfo:{hasNextPage:false,endCursor:"cursor"},
      nodes:[{number:7,state:"MERGED",headRefName:"feature",headRefOid:$oid,
        baseRepository:{nameWithOwner:$slug},
        headRepository:{nameWithOwner:$slug}}]}}}}}' \
    >"$FORGE/associated.json"
}

# fixture_pr [closing-issue...]: PR #7 merged from feature into main.
fixture_pr() {
  local refs='[]' body="Improve the widget." n
  for n in "$@"; do
    refs=$(jq -c --argjson n "$n" --arg slug "$SLUG" --arg host "$HOST" \
      '. + [{number:$n, repository:{nameWithOwner:$slug},
             url:("https://"+$host+"/"+$slug+"/issues/"+($n|tostring))}]' <<<"$refs")
    body="$body"$'\n\n'"Closes #$n"
  done
  jq -n --arg oid "$HEAD_OID" --arg merge "$MERGE_OID" --arg slug "$SLUG" \
    --arg host "$HOST" --arg body "$body" --argjson refs "$refs" \
    '{number:7, title:"Improve the widget", body:$body, state:"MERGED",
      mergedAt:"2026-11-18T12:00:00Z", mergeCommit:{oid:$merge},
      headRefName:"feature", headRefOid:$oid, baseRefName:"main",
      isCrossRepository:false, headRepositoryOwner:{login:($slug|split("/")[0])},
      headRepository:{name:($slug|split("/")[1])},
      url:("https://"+$host+"/"+$slug+"/pull/7"),
      closingIssuesReferences:$refs}' >"$FORGE/pr/7.json"
}

# fixture_issue <N> <OPEN|CLOSED> <reason or ""> <title>, body on stdin.
fixture_issue() {
  local body
  body=$(cat)
  jq -n --argjson n "$1" --arg s "$2" --arg r "$3" --arg t "$4" --arg b "$body" \
    --arg slug "$SLUG" --arg host "$HOST" \
    '{number:$n, title:$t, state:$s,
      stateReason:(if $r == "" then null else $r end), body:$b,
      labels:[], url:("https://"+$host+"/"+$slug+"/issues/"+($n|tostring))}' \
    >"$FORGE/issue/$1.json"
}

# A tracker in the free-skills shared tracker format. #10 is the merged unit;
# #11 starts after #10; $TRACKER_EXTRA_NODES and $TRACKER_EXTRA_UNITS add
# lines for more units.
# tracker_body <x-or-space for #10> <startable class list> <startable bullet>
tracker_body() {
  cat <<EOF
**Widget rollout.** Tracks the widget units.

## Status

\`\`\`mermaid
flowchart LR
    i10["#10 Widget v2"]
    i11["#11 Widget docs"]${TRACKER_EXTRA_NODES:-}
    i10 --> i11
    classDef startable stroke:#15803d,stroke-width:3px
    class $2 startable
\`\`\`

- **Startable now:** $3.

## Units

- [$1] #10
- [ ] #11${TRACKER_EXTRA_UNITS:-}
EOF
}

# The project's reconciliation mechanics; `tracker_mechanics release` adds a
# request outside a tracker's authority.
tracker_mechanics() {
  cat <<'DOC'
# Tracker Mechanics

Trackers are issues in the shared tracker format: a `## Status` Mermaid
flowchart whose `startable` class marks units that can start, a
**Startable now** bullet, and a `## Units` checklist of unit issues.

## refresh

After a unit merges, refresh each containing tracker in one edit:

1. Tick the merged unit's box under `## Units` once its closing issue is
   closed as completed.
2. Recompute the startable set: each open unit whose every `starts-after`
   prerequisite is closed as completed. Update the `class ... startable`
   line and the **Startable now** bullet to match.

Never edit a unit issue during a refresh. Report a unit whose Dependencies
are unclear instead of guessing.
DOC
  [ "${1:-}" != release ] || cat <<'DOC'

## release

After the refresh, delete the release draft `v0.1.0-rc`, which the merged
unit superseded:
`gh release delete v0.1.0-rc --repo github.invalid/acme/repo --yes`.
DOC
}

# obligations_record <mechanics-path>
obligations_record() {
  cat <<EOF
### Post-merge obligations

- **Containing trackers:** tracker issue #1, when its \`## Units\` lists the
  merged unit's verified closing issue.
- **Refresh:** apply \`$1\` §refresh in each containing tracker, as one edit.
- **Detailed mechanics:** \`$1\`.
- **Report:** name newly unblocked units without claiming or starting them.
EOF
}

# AGENTS.md with the forge record and, given a mechanics path, the
# post-merge obligations record.
standard_agents() {
  {
    printf '# Widget\n\nProject instructions for agents.\n\n'
    forge_record
    [ -z "${1:-}" ] || { echo; obligations_record "$1"; }
  } | fixture_agents
}

# The usual tracker fixture: PR #7 closes #10 (now closed), tracker #1 lists
# #10 and #11, and #11 starts after #10.
tracker_issues() {
  fixture_pr 10
  printf '### Dependencies\n\nnone\n' | fixture_issue 10 CLOSED COMPLETED "Widget v2"
  printf '### Dependencies\n\n- starts-after #10\n' | fixture_issue 11 OPEN "" "Widget docs"
  printf '%s' "$(tracker_body ' ' i10 '#10')" | fixture_issue 1 OPEN "" "Widget rollout tracker"
}
