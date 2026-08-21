#!/usr/bin/env bash
# Offline regression matrix for merge-cleanup.sh. Git runs against scratch
# repositories while a gh shim serves deterministic PR and repository facts.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${MERGE_CLEANUP_SCRIPT:-$ROOT/skills/merge-cleanup/merge-cleanup.sh}"
[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }
REAL_GIT=$(command -v git)
export REAL_GIT

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SHIMD="$TMP/shim"; FIX="$TMP/fix"
mkdir -p "$SHIMD" "$FIX"
pass=0; fail=0; skip=0; scenario_id=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $SCENARIO: $1" >&2; }
want_rc() {
  if [ "$RC" -eq "$1" ]; then ok
  else bad "exit $RC, want $1; out=$OUT; err=$(tail -c 240 "$FIX/stderr" 2>/dev/null)"; fi
}
want_out() { case "$OUT" in *"$1"*) ok ;; *) bad "stdout lacks $1: $OUT" ;; esac; }
want_ref() {
  if git --git-dir="$1" show-ref --verify --quiet "$2"; then ok
  else bad "missing ref $2 in $1"; fi
}
want_no_ref() {
  if git --git-dir="$1" show-ref --verify --quiet "$2"; then bad "unexpected ref $2 in $1"
  else ok; fi
}

# Validation uses a real checkout and a dead forge. Valid input reaches the
# forge lookup and exits 4; malformed input exits 64 first.
VALID="$TMP/valid"
git init -q "$VALID"
git -C "$VALID" config user.name Test
git -C "$VALID" config user.email test@example.invalid
touch "$VALID/a"
git -C "$VALID" add a
git -C "$VALID" commit -qm init
printf '#!/bin/sh\nexit 1\n' >"$SHIMD/gh"
chmod +x "$SHIMD/gh"

v() {
  expected="$1"; desc="$2"; shift 2
  if PATH="$SHIMD:$PATH" bash "$SCRIPT" "$@" >/dev/null 2>&1; then
    got=0
  else
    got=$?
  fi
  if [ "$got" -eq "$expected" ]; then ok
  else SCENARIO=validation; bad "$desc: exit $got, want $expected"; fi
}
SCENARIO=validation
v 4 "valid invocation" --repo github.invalid/acme/repo --pr 7 --checkout "$VALID"
v 64 "missing checkout" --repo github.invalid/acme/repo --pr 7
v 64 "missing repo" --pr 7 --checkout "$VALID"
v 64 "missing PR" --repo github.invalid/acme/repo --checkout "$VALID"
v 64 "zero PR" --repo github.invalid/acme/repo --pr 0 --checkout "$VALID"
v 64 "leading-zero PR" --repo github.invalid/acme/repo --pr 07 --checkout "$VALID"
v 64 "hostless repo" --repo acme/repo --pr 7 --checkout "$VALID"
v 64 "invalid repo" --repo github.invalid/acme/repo/extra --pr 7 --checkout "$VALID"
v 64 "invalid host" --repo .invalid/acme/repo --pr 7 --checkout "$VALID"
v 64 "invalid host character" --repo github_invalid/acme/repo --pr 7 --checkout "$VALID"
v 64 "unknown option" --repo github.invalid/acme/repo --pr 7 --checkout "$VALID" --bogus x
v 64 "remote option shape" --repo github.invalid/acme/repo --pr 7 --checkout "$VALID" --base-remote -x
if PATH="$SHIMD:$PATH" bash "$SCRIPT" --help >/dev/null 2>&1; then ok
else bad "--help failed"; fi

if ! command -v jq >/dev/null 2>&1; then
  skip=1
  echo "SKIP: behavior cases require jq; validation only" >&2
else
cat >"$SHIMD/gh" <<'GH'
#!/usr/bin/env bash
set -u
echo "$*" >>"$FIX/calls.log"
[ "${GH_FAIL_PR:-}" != 1 ] || {
  case " $* " in *" pr view "*"headRefName"*) exit 1 ;; esac
}
sub="" verb="" api="" json="" jqf="" head=false base=false slurp=false
prev=""
for arg in "$@"; do
  case "$prev" in --json) json="$arg" ;; --jq) jqf="$arg" ;; esac
  case "$arg" in
    pr|api) [ -n "$sub" ] || sub="$arg" ;;
    view|list|edit) [ "$sub" != pr ] || [ -n "$verb" ] || verb="$arg" ;;
    graphql|repos/*) api="$arg" ;;
    --json=*) json="${arg#--json=}" ;;
    --jq=*) jqf="${arg#--jq=}" ;;
    --head=*) head=true ;;
    --base=*) base=true ;;
    --slurp) slurp=true ;;
  esac
  prev="$arg"
done
fixture=""
if [ "$sub" = api ]; then
  case "$api" in
    graphql) fixture="$FIX/associated.json" ;;
    *"/pulls?"*"head="*) fixture="$FIX/shared.json" ;;
    *"/pulls?"*"base="*) fixture="$FIX/stacked.json" ;;
    repos/acme/fork) fixture="$FIX/repo-head.json" ;;
    repos/*)
      case "$jqf" in *default_branch*) fixture="$FIX/repo-base.json" ;; *)
        fixture="$FIX/repo-head.json" ;; esac ;;
  esac
elif [ "$sub" = pr ] && [ "$verb" = view ]; then
  case "$json" in *headRefName*) fixture="$FIX/pr.json" ;; *)
    fixture="$FIX/stacked-view.json" ;; esac
elif [ "$sub" = pr ] && [ "$verb" = list ]; then
  [ "$head" = false ] || fixture="$FIX/shared.json"
  [ "$base" = false ] || fixture="$FIX/stacked.json"
elif [ "$sub" = pr ] && [ "$verb" = edit ]; then
  exit "${GH_EDIT_RC:-0}"
fi
[ -n "$fixture" ] && [ -f "$fixture" ] || exit 1
if [ -n "$jqf" ]; then
  [ "$slurp" = false ] && exec jq -r "$jqf" "$fixture"
  exec jq -s -r "$jqf" "$fixture"
fi
[ "$slurp" = false ] || exec jq -s '.' "$fixture"
exec cat "$fixture"
GH
chmod +x "$SHIMD/gh"

write_repo_facts() {
  jq -n --arg full "$1" \
    '{default_branch:"main",fork:false,forks_count:0,
      delete_branch_on_merge:false,parent:null,source:null,
      clone_url:("https://github.invalid/"+$full+".git"),
      ssh_url:("git@github.invalid:"+$full+".git"),
      merge_commit_title:"PR_TITLE",merge_commit_message:"BLANK"}'
}
write_pr() { # repo head-repo branch oid fork [closing-number]
  local repo="$1" head_repo="$2" branch="$3" oid="$4" fork="$5" closing="${6:-}"
  local owner="${head_repo%%/*}" name="${head_repo#*/}"
  if [ -n "$closing" ]; then
    jq -n --arg b "$branch" --arg o "$oid" --argjson f "$fork" \
      --arg ow "$owner" --arg rn "$name" --arg repo "$repo" --argjson n "$closing" \
      '{state:"MERGED",mergedAt:"2026-08-20T12:00:00Z",headRefName:$b,
        baseRefName:"main",headRefOid:$o,isCrossRepository:$f,
        headRepositoryOwner:{login:$ow},headRepository:{name:$rn},
        url:("https://github.invalid/"+$repo+"/pull/7"),
        closingIssuesReferences:[{number:$n,repository:{nameWithOwner:$repo},
          url:("https://github.invalid/"+$repo+"/issues/"+($n|tostring))}]}'
  else
    jq -n --arg b "$branch" --arg o "$oid" --argjson f "$fork" \
      --arg ow "$owner" --arg rn "$name" --arg repo "$repo" \
      '{state:"MERGED",mergedAt:"2026-08-20T12:00:00Z",headRefName:$b,
        baseRefName:"main",headRefOid:$o,isCrossRepository:$f,
        headRepositoryOwner:{login:$ow},headRepository:{name:$rn},
        url:("https://github.invalid/"+$repo+"/pull/7"),
        closingIssuesReferences:[]}'
  fi >"$FIX/pr.json"
}
reset_forge() {
  rm -f "$FIX"/*.json "$FIX"/calls.log "$FIX"/stderr
  write_repo_facts acme/repo >"$FIX/repo-base.json"
  write_repo_facts acme/repo >"$FIX/repo-head.json"
  printf '[]\n' >"$FIX/shared.json"
  jq -n --arg oid "$HEAD_OID" \
    '{data:{repository:{object:{associatedPullRequests:{
      pageInfo:{hasNextPage:false,endCursor:"cursor"},
      nodes:[{number:7,state:"OPEN",headRefName:"feature",headRefOid:$oid,
        baseRepository:{nameWithOwner:"acme/repo"},
        headRepository:{nameWithOwner:"acme/repo"}}]}}}}}' \
    >"$FIX/associated.json"
  printf '[]\n' >"$FIX/stacked.json"
  printf '{"baseRefName":"main"}\n' >"$FIX/stacked-view.json"
}
setup_same() { # merge|squash|rebase
  local shape="$1"
  scenario_id=$((scenario_id + 1))
  SCEN="$TMP/scen-$scenario_id"; ORIGIN="$SCEN/origin.git"
  SEED="$SCEN/seed"; WORK="$SCEN/work"
  mkdir -p "$SCEN"
  git init -q --bare "$ORIGIN"
  git init -q "$SEED"
  git -C "$SEED" config user.name Test
  git -C "$SEED" config user.email test@example.invalid
  echo base >"$SEED/file"
  git -C "$SEED" add file
  git -C "$SEED" commit -qm base
  git -C "$SEED" branch -M main
  git -C "$SEED" remote add origin "$ORIGIN"
  git -C "$SEED" push -q -u origin main
  git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
  git -C "$SEED" switch -qc feature
  echo feature >>"$SEED/file"
  git -C "$SEED" commit -qam feature
  HEAD_OID=$(git -C "$SEED" rev-parse HEAD)
  git -C "$SEED" push -q -u origin feature
  git -C "$SEED" switch -q main
  if [ "$shape" = merge ]; then
    git -C "$SEED" merge -q --no-ff feature -m merged
  elif [ "$shape" = squash ]; then
    git -C "$SEED" merge -q --squash feature
    git -C "$SEED" commit -qm squashed
  else
    echo base-two >"$SEED/base-two"
    git -C "$SEED" add base-two
    git -C "$SEED" commit -qm base-two
    git -C "$SEED" cherry-pick "$HEAD_OID" >/dev/null
  fi
  git -C "$SEED" push -q origin main
  git clone -q "$ORIGIN" "$WORK"
  git -C "$WORK" config user.name Test
  git -C "$WORK" config user.email test@example.invalid
  git -C "$WORK" switch -qc feature --track origin/feature
  reset_forge
  write_pr acme/repo acme/repo feature "$HEAD_OID" false >"$FIX/pr.json"
}
run_cleanup() {
  if OUT=$(FIX="$FIX" PATH="$SHIMD:$PATH" bash "$SCRIPT" \
      --repo "github.invalid/$RUN_REPO" --pr 7 --checkout "$WORK" \
      --base-remote origin ${HEAD_REMOTE_ARG:-} 2>"$FIX/stderr"); then
    RC=0
  else
    RC=$?
  fi
}

run_cleanup_without_bashpid() {
  if OUT=$(FIX="$FIX" PATH="$SHIMD:$PATH" bash -c \
      'unset BASHPID; source "$0"' "$SCRIPT" \
      --repo "github.invalid/$RUN_REPO" --pr 7 --checkout "$WORK" \
      --base-remote origin ${HEAD_REMOTE_ARG:-} 2>"$FIX/stderr"); then
    RC=0
  else
    RC=$?
  fi
}

SCENARIO="same-repository merge cleanup"
setup_same merge
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
GH_HOST=wrong.invalid run_cleanup
want_rc 0
want_out '"remote_branch":"deleted"'
want_out '"base_resync":"resynced"'
want_no_ref "$ORIGIN" refs/heads/feature
if git -C "$WORK" show-ref --verify --quiet refs/heads/feature; then bad "local feature survived"
else ok; fi
[ "$(git -C "$WORK" symbolic-ref --short HEAD)" = main ] && ok || bad "HEAD is not main"
if rg -q -- 'pr view 7 --repo=github.invalid/acme/repo' "$FIX/calls.log" \
    && awk '$1 == "api" {
        seen = 1
        if ($2 == "graphql") {
          if ($3 != "--hostname" || $4 != "github.invalid") bad = 1
        } else if ($2 != "--hostname" || $3 != "github.invalid") bad = 1
      }
      END { exit !(seen && !bad) }' "$FIX/calls.log"; then
  ok
else
  bad "forge calls did not preserve the explicitly pinned host"
fi

SCENARIO="dirty preflight preserves refs"
setup_same merge
echo dirty >"$WORK/untracked"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP dirty-tree'
want_ref "$ORIGIN" refs/heads/feature
[ "$(git -C "$WORK" symbolic-ref --short HEAD)" = feature ] && ok || bad "dirty stop changed HEAD"

SCENARIO="moved remote head stops after safe resync"
setup_same merge
git -C "$SEED" switch -q feature
echo moved >>"$SEED/file"
git -C "$SEED" commit -qam moved
git -C "$SEED" push -q origin feature
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP oid-mismatch'
want_out '"base_resync":"resynced"'
want_ref "$ORIGIN" refs/heads/feature
if git -C "$WORK" show-ref --verify --quiet refs/heads/feature; then ok
else bad "moved-head stop deleted local feature"; fi

SCENARIO="auto-deleted remote still cleans local"
setup_same merge
git --git-dir="$ORIGIN" update-ref -d refs/heads/feature
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 0
want_out '"remote_branch":"already_absent"'
want_no_ref "$ORIGIN" refs/heads/feature

SCENARIO="squash merge uses forge-verified local delete"
setup_same squash
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 0
want_out '"local_branch":"deleted_verified_config_retained"'
want_no_ref "$ORIGIN" refs/heads/feature
if [ "$(git -C "$WORK" config branch.feature.remote)" = origin ]; then ok
else bad "compare-and-delete did not retain feature branch config"; fi

SCENARIO="rebase merge uses forge-verified local delete"
setup_same rebase
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 0
want_out '"local_branch":"deleted_verified_config_retained"'
want_no_ref "$ORIGIN" refs/heads/feature

SCENARIO="local delete refuses a concurrently advanced branch"
setup_same squash
LOCAL_RACE_OID=$(git -C "$WORK" rev-parse refs/remotes/origin/main)
export LOCAL_RACE_OID
cat >"$SHIMD/git" <<'GIT'
#!/bin/sh
if [ "${LOCAL_DELETE_RACE:-}" = 1 ] && [ "$1" = update-ref ] \
    && [ "$2" = -d ] && [ "$3" = refs/heads/feature ] \
    && [ ! -e "$FIX/local-delete-raced" ]; then
  : >"$FIX/local-delete-raced"
  "$REAL_GIT" update-ref refs/heads/feature "$LOCAL_RACE_OID" || exit
fi
exec "$REAL_GIT" "$@"
GIT
chmod +x "$SHIMD/git"
LOCAL_DELETE_RACE=1
export LOCAL_DELETE_RACE
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
unset LOCAL_DELETE_RACE LOCAL_RACE_OID
rm "$SHIMD/git"
want_rc 2
want_out 'STOP local-delete'
[ "$(git -C "$WORK" rev-parse refs/heads/feature)" = "$(git -C "$WORK" rev-parse refs/remotes/origin/main)" ] \
  && ok || bad "compare-and-delete lost the concurrently advanced local branch"

SCENARIO="a same-named tag cannot redirect base landing"
setup_same merge
git -C "$WORK" tag main "$HEAD_OID"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 0
want_out '"base_resync":"resynced"'
want_no_ref "$ORIGIN" refs/heads/feature

SCENARIO="absent option-shaped base requires owner creation"
setup_same merge
MERGED_OID=$(git --git-dir="$ORIGIN" rev-parse refs/heads/main)
git --git-dir="$ORIGIN" update-ref refs/heads/-x "$MERGED_OID"
jq '.baseRefName = "-x"' "$FIX/pr.json" >"$FIX/pr.base"
mv "$FIX/pr.base" "$FIX/pr.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP base-create-required'
if git -C "$WORK" show-ref --verify --quiet refs/heads/-x; then
  bad "cleanup created the absent option-shaped base"
else
  ok
fi
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="failed PR lookup mutates nothing"
setup_same merge
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
GH_FAIL_PR=1
export GH_FAIL_PR
run_cleanup
unset GH_FAIL_PR
want_rc 4
want_ref "$ORIGIN" refs/heads/feature
[ "$(git -C "$WORK" symbolic-ref --short HEAD)" = feature ] && ok || bad "failed lookup changed HEAD"

SCENARIO="malformed PR evidence mutates nothing"
setup_same merge
jq '.headRefOid = "not-an-oid"' "$FIX/pr.json" >"$FIX/pr.bad"
mv "$FIX/pr.bad" "$FIX/pr.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 4
want_out 'LOOKUP_FAILED pr-view'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="mismatched forge endpoints mutate nothing"
setup_same merge
FORK="$SCEN/fork.git"
git init -q --bare "$FORK"
git -C "$SEED" push -q "$FORK" "$HEAD_OID:refs/heads/feature"
git -C "$WORK" remote add fork "$FORK"
git -C "$WORK" fetch -q fork
reset_forge
write_repo_facts acme/base >"$FIX/repo-base.json"
write_repo_facts acme/fork >"$FIX/repo-head.json"
write_pr acme/base acme/fork feature "$HEAD_OID" true >"$FIX/pr.json"
jq '.clone_url = "https://github.invalid/acme/other.git" |
    .ssh_url = "git@github.invalid:acme/other.git"' \
  "$FIX/repo-head.json" >"$FIX/repo-head.bad"
mv "$FIX/repo-head.bad" "$FIX/repo-head.json"
RUN_REPO=acme/base; HEAD_REMOTE_ARG="--head-remote fork"
run_cleanup
want_rc 4
want_out 'LOOKUP_FAILED head-repo-facts'
want_ref "$FORK" refs/heads/feature

# A local ~/.ssh/config Host alias (label bnw.github.invalid, HostName
# github.invalid) names the forge's real endpoint. An ssh shim serves the alias
# both for `ssh -G` identity resolution and for the git transport that deletes
# over it, so the whole destructive path runs end to end. ALIAS_GHOST/GUSER/
# GPORT let a case perturb the resolved endpoint; ALIAS_SERVE is the bare repo
# the shim serves regardless of the path in the alias URL. The `-G` target is
# the last argument (after `--`); when it names a user (`user@host`) the shim
# can resolve differently via ALIAS_GHOST_U/GUSER_U/GPORT_U, which default to
# the userless values. That mirrors a user-dependent ssh config (`Match user`,
# `%r`) so a case can prove the guard resolves the same user@host Git connects
# through, not a bare host.
install_ssh_shim() {
  cat >"$SHIMD/ssh" <<'SSH'
#!/usr/bin/env bash
for a in "$@"; do
  [ "$a" = -G ] && {
    case "${!#}" in
      *@*) printf 'hostname %s\nuser %s\nport %s\n' \
             "${ALIAS_GHOST_U:-${ALIAS_GHOST:-github.invalid}}" \
             "${ALIAS_GUSER_U:-${ALIAS_GUSER:-git}}" \
             "${ALIAS_GPORT_U:-${ALIAS_GPORT:-22}}" ;;
      *) printf 'hostname %s\nuser %s\nport %s\n' \
           "${ALIAS_GHOST:-github.invalid}" \
           "${ALIAS_GUSER:-git}" "${ALIAS_GPORT:-22}" ;;
    esac
    exit 0
  }
done
cmd="${!#}"; verb="${cmd%% *}"
exec "$verb" "$ALIAS_SERVE"
SSH
  chmod +x "$SHIMD/ssh"
}
install_ssh_shim

SCENARIO="explicit ssh host alias resolves to the forge and deletes"
setup_same merge
git -C "$WORK" remote add alias 'git@bnw.github.invalid:acme/repo.git'
export ALIAS_SERVE="$ORIGIN"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote alias"
run_cleanup
want_rc 0
want_out '"remote_branch":"deleted"'
want_no_ref "$ORIGIN" refs/heads/feature

SCENARIO="ssh host alias auto-resolves as the head remote"
setup_same merge
git -C "$WORK" remote add alias 'git@bnw.github.invalid:acme/repo.git'
export ALIAS_SERVE="$ORIGIN"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG=""
run_cleanup
want_rc 0
want_out '"remote_branch":"deleted"'
want_no_ref "$ORIGIN" refs/heads/feature

SCENARIO="ssh alias to a different repository still stops"
setup_same merge
git -C "$WORK" remote add alias 'git@bnw.github.invalid:acme/other.git'
export ALIAS_SERVE="$ORIGIN"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote alias"
run_cleanup
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="ssh alias on a non-default port still stops"
setup_same merge
git -C "$WORK" remote add alias 'git@bnw.github.invalid:acme/repo.git'
export ALIAS_SERVE="$ORIGIN" ALIAS_GPORT=2222
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote alias"
run_cleanup
unset ALIAS_GPORT
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_ref "$ORIGIN" refs/heads/feature

# A user-dependent ssh config: the bare host resolves to the forge, but the
# user-qualified `git@host` Git actually connects through resolves elsewhere.
# The guard must resolve the same user@host Git uses; resolving the bare host
# would bless the forge yet delete via the other endpoint. Discriminating:
# neutering the user pass (querying only the bare host) resolves the forge and
# deletes, so this must stop.
SCENARIO="ssh alias diverging by remote user still stops"
setup_same merge
git -C "$WORK" remote add alias 'git@bnw.github.invalid:acme/repo.git'
export ALIAS_SERVE="$ORIGIN" ALIAS_GHOST_U=rogue.github.invalid
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote alias"
run_cleanup
unset ALIAS_GHOST_U
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_ref "$ORIGIN" refs/heads/feature

# Git honors an ssh-command override (GIT_SSH_COMMAND, core.sshCommand, GIT_SSH)
# for the transport, but the guard queries the plain ssh on PATH, so the offline
# resolution need not reflect the endpoint Git reaches. The guard fails closed
# whenever an override is active. Discriminating: without the fail-closed the
# alias resolves to the forge (via the shim) and the branch is deleted through
# the unverified endpoint, so each override must stop.
SCENARIO="ssh alias under GIT_SSH_COMMAND override still stops"
setup_same merge
git -C "$WORK" remote add alias 'git@bnw.github.invalid:acme/repo.git'
export ALIAS_SERVE="$ORIGIN" GIT_SSH_COMMAND='ssh -F /dev/null'
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote alias"
run_cleanup
unset GIT_SSH_COMMAND
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="ssh alias under core.sshCommand override still stops"
setup_same merge
git -C "$WORK" remote add alias 'git@bnw.github.invalid:acme/repo.git'
git -C "$WORK" config core.sshCommand 'ssh -F /dev/null'
export ALIAS_SERVE="$ORIGIN"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote alias"
run_cleanup
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="ssh alias under GIT_SSH override still stops"
setup_same merge
git -C "$WORK" remote add alias 'git@bnw.github.invalid:acme/repo.git'
export ALIAS_SERVE="$ORIGIN" GIT_SSH="$SHIMD/ssh"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote alias"
run_cleanup
unset GIT_SSH
want_rc 2
want_out 'STOP remote-repo-mismatch'
want_ref "$ORIGIN" refs/heads/feature

rm -f "$SHIMD/ssh"
unset ALIAS_SERVE

SCENARIO="credential-bearing forge endpoints mutate nothing"
setup_same merge
jq '.clone_url = "https://user:returned-secret@github.invalid/acme/repo.git"' \
  "$FIX/repo-base.json" >"$FIX/repo-base.bad"
mv "$FIX/repo-base.bad" "$FIX/repo-base.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 4
want_out 'LOOKUP_FAILED repo-facts'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="a divergent local base stops before remote deletion"
setup_same merge
git -C "$WORK" switch -q main
git -C "$WORK" reset -q --hard HEAD^
echo local-only >"$WORK/local-only"
git -C "$WORK" add local-only
git -C "$WORK" commit -qm local-only
git -C "$WORK" switch -q feature
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP resync-failed'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="branch-conditioned remote replacement stops before deletion"
setup_same merge
WRONG="$SCEN/wrong.git"; WRONG_WORK="$SCEN/wrong-work"
git clone -q --bare "$ORIGIN" "$WRONG"
git clone -q "$WRONG" "$WRONG_WORK"
git -C "$WRONG_WORK" config user.name Test
git -C "$WRONG_WORK" config user.email test@example.invalid
echo wrong >"$WRONG_WORK/wrong"
git -C "$WRONG_WORK" add wrong
git -C "$WRONG_WORK" commit -qm wrong
git -C "$WRONG_WORK" push -q origin main
FEATURE_CONFIG="$SCEN/feature.cfg"; MAIN_CONFIG="$SCEN/main.cfg"
git -C "$WORK" config --unset-all remote.origin.url
git -C "$WORK" config --add includeIf.onbranch:feature.path "$FEATURE_CONFIG"
git -C "$WORK" config --add includeIf.onbranch:main.path "$MAIN_CONFIG"
git config --file "$FEATURE_CONFIG" remote.origin.url "$ORIGIN"
git config --file "$MAIN_CONFIG" remote.origin.url "$WRONG"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP remote-config-changed'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="closing references are ledgered"
setup_same merge
write_pr acme/repo acme/repo feature "$HEAD_OID" false 42 >"$FIX/pr.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 0
want_out '"number":42'

SCENARIO="linked head worktree requires owner removal before mutation"
setup_same merge
git -C "$WORK" switch -q main
git -C "$WORK" branch -f feature origin/feature
HEAD_WT="$SCEN/head-wt"
git -C "$WORK" worktree add -q "$HEAD_WT" feature
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP head-worktree-present'
want_ref "$ORIGIN" refs/heads/feature
[ -e "$HEAD_WT" ] && ok || bad "linked head worktree was removed"

SCENARIO="dirty linked head worktree stops before mutation"
setup_same merge
git -C "$WORK" switch -q main
git -C "$WORK" branch -f feature origin/feature
HEAD_WT="$SCEN/head-wt"
git -C "$WORK" worktree add -q "$HEAD_WT" feature
echo hidden >"$HEAD_WT/untracked"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP head-worktree-present'
want_ref "$ORIGIN" refs/heads/feature
[ -e "$HEAD_WT" ] && ok || bad "dirty linked worktree was removed"

SCENARIO="ambiguous suffix ref stops the leased deletion"
setup_same merge
git --git-dir="$ORIGIN" update-ref refs/heads/refs/heads/feature "$HEAD_OID"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP ambiguous-ref'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="a suffix-only decoy is not mistaken for head absence"
setup_same merge
git --git-dir="$ORIGIN" update-ref refs/heads/refs/heads/feature "$HEAD_OID"
git --git-dir="$ORIGIN" update-ref -d refs/heads/feature
printf '[{"number":8}]\n' >"$FIX/stacked.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP ambiguous-ref'
if rg -q -- 'pr edit 8' "$FIX/calls.log"; then bad "decoy path retargeted a stack"
else ok; fi

SCENARIO="a shared head in another target repository stops deletion"
setup_same merge
jq '.data.repository.object.associatedPullRequests.pageInfo =
  {hasNextPage:true,endCursor:"first-page"}' \
  "$FIX/associated.json" >"$FIX/associated.more"
jq -n --arg oid "$HEAD_OID" \
  '{data:{repository:{object:{associatedPullRequests:{
    pageInfo:{hasNextPage:false,endCursor:"second-page"},
    nodes:[{number:7,state:"OPEN",headRefName:"feature",headRefOid:$oid,
      baseRepository:{nameWithOwner:"acme/other"},
      headRepository:{nameWithOwner:"acme/repo"}}]}}}}}' \
  >>"$FIX/associated.more"
mv "$FIX/associated.more" "$FIX/associated.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP shared-head'
want_ref "$ORIGIN" refs/heads/feature
if rg -q -- 'api graphql --hostname github.invalid --paginate' "$FIX/calls.log"; then ok
else bad "shared-head lookup was not exhaustive"; fi

SCENARIO="malformed network-wide consumer evidence stops deletion"
setup_same merge
jq '.data.repository.object.associatedPullRequests.nodes +=
  [{number:9,state:"OPEN",headRefName:"feature",headRefOid:"bad",
    baseRepository:{nameWithOwner:"acme/other"},
    headRepository:{nameWithOwner:"acme/repo"}}]' \
  "$FIX/associated.json" >"$FIX/associated.bad"
mv "$FIX/associated.bad" "$FIX/associated.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 4
want_out 'LOOKUP_FAILED shared-head'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="SCP-style inline credentials stop without trace exposure"
setup_same merge
git -C "$WORK" remote set-url origin \
  user:secret-token@github.invalid:acme/repo.git
if OUT=$(FIX="$FIX" PATH="$SHIMD:$PATH" bash -x "$SCRIPT" \
    --repo "github.invalid/acme/repo" --pr 7 --checkout "$WORK" \
    --base-remote origin --head-remote origin 2>"$FIX/stderr"); then
  RC=0
else
  RC=$?
fi
want_rc 2
want_out 'STOP credential-url'
want_ref "$ORIGIN" refs/heads/feature
if rg -q -- 'secret-token' "$FIX/stderr"; then bad "xtrace exposed inline credentials"
else ok; fi

SCENARIO="inline push credentials stop before remote deletion"
setup_same merge
git -C "$WORK" remote set-url --add --push origin \
  https://user:push-secret@github.invalid/acme/repo.git
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP credential-url'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="pinned transports work without BASHPID"
setup_same merge
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup_without_bashpid
want_rc 0
want_out '"remote_branch":"deleted"'
want_no_ref "$ORIGIN" refs/heads/feature

SCENARIO="validated head fetch identity survives a remote config race"
setup_same merge
OTHER="$SCEN/other.git"
git clone -q --bare "$ORIGIN" "$OTHER"
SHIM_AUTH_URL=https://github.invalid/acme/repo.git
SHIM_OTHER_URL=https://github.invalid/acme/other.git
SHIM_ORIGIN="$ORIGIN"; SHIM_OTHER="$OTHER"
export SHIM_AUTH_URL SHIM_OTHER_URL SHIM_ORIGIN SHIM_OTHER
git -C "$WORK" remote add head "$SHIM_AUTH_URL"
git -C "$WORK" remote set-url --push head "$SHIM_AUTH_URL"
cat >"$SHIMD/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = remote ] && [ "$2" = get-url ] && [ "$3" = -- ] \
    && [ "$4" = head ]; then
  count=0
  [ ! -f "$FIX/head-url-count" ] || count=$(cat "$FIX/head-url-count")
  count=$((count + 1))
  printf '%s\n' "$count" >"$FIX/head-url-count"
  "$REAL_GIT" "$@" || exit
  if [ "$count" -eq 2 ]; then
    "$REAL_GIT" config remote.head.url "$SHIM_OTHER_URL" || exit
    "$REAL_GIT" config --replace-all remote.head.pushurl "$SHIM_OTHER_URL" || exit
  fi
  exit 0
fi
mapped=()
for arg in "$@"; do
  case "$arg" in
    "$SHIM_AUTH_URL") mapped+=("$SHIM_ORIGIN") ;;
    "$SHIM_OTHER_URL") mapped+=("$SHIM_OTHER") ;;
    *) mapped+=("$arg") ;;
  esac
done
exec "$REAL_GIT" "${mapped[@]}"
GIT
chmod +x "$SHIMD/git"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote head"
run_cleanup
rm "$SHIMD/git"
unset SHIM_AUTH_URL SHIM_OTHER_URL SHIM_ORIGIN SHIM_OTHER
want_rc 2
want_out 'STOP pushurl-mismatch'
want_ref "$ORIGIN" refs/heads/feature
want_ref "$OTHER" refs/heads/feature

SCENARIO="validated literal URL ignores later rewrite config"
setup_same merge
OTHER="$SCEN/other.git"
git clone -q --bare "$ORIGIN" "$OTHER"
SHIM_ORIGIN="$ORIGIN"; SHIM_OTHER="$OTHER"
export SHIM_ORIGIN SHIM_OTHER
git -C "$WORK" remote add head "$SHIM_ORIGIN"
cat >"$SHIMD/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = ls-remote ] && [ ! -e "$FIX/url-rewrite-raced" ]; then
  : >"$FIX/url-rewrite-raced"
  "$REAL_GIT" config "url.$SHIM_OTHER.insteadOf" "$SHIM_ORIGIN" || exit
  "$REAL_GIT" config "url.$SHIM_OTHER.pushInsteadOf" "$SHIM_ORIGIN" || exit
fi
exec "$REAL_GIT" "$@"
GIT
chmod +x "$SHIMD/git"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote head"
run_cleanup
rm "$SHIMD/git"
unset SHIM_ORIGIN SHIM_OTHER
want_rc 0
want_no_ref "$ORIGIN" refs/heads/feature
want_ref "$OTHER" refs/heads/feature

SCENARIO="a lease race preserves the moved remote head"
setup_same merge
MOVED_OID=$(git --git-dir="$ORIGIN" rev-parse refs/heads/main)
HOOK="$(git -C "$WORK" rev-parse --absolute-git-dir)/hooks/pre-push"
printf '#!/bin/sh\ngit --git-dir="%s" update-ref refs/heads/feature "%s"\n' \
  "$ORIGIN" "$MOVED_OID" >"$HOOK"
chmod +x "$HOOK"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP lease-failed'
want_ref "$ORIGIN" refs/heads/feature
[ "$(git --git-dir="$ORIGIN" rev-parse refs/heads/feature)" = "$MOVED_OID" ] && ok \
  || bad "lease race did not preserve the moved head"

SCENARIO="a post-merge hook cannot falsify a completed resync"
setup_same merge
git -C "$WORK" switch -q main
git -C "$WORK" reset -q --hard HEAD^
git -C "$WORK" switch -q feature
HOOK="$(git -C "$WORK" rev-parse --absolute-git-dir)/hooks/post-merge"
printf '#!/bin/sh\ngit reset -q --hard HEAD^\n' >"$HOOK"
chmod +x "$HOOK"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP resync-changed'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="prune ignores a destructive configured fetch refspec"
setup_same merge
git -C "$WORK" config --unset-all remote.origin.fetch
git -C "$WORK" config --add remote.origin.fetch '+refs/cleanup/*:refs/heads/*'
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 0
want_ref "$WORK/.git" refs/heads/main
[ "$(git -C "$WORK" symbolic-ref -q HEAD)" = refs/heads/main ] && ok \
  || bad "safe prune left HEAD dangling"

SCENARIO="overlapping remote namespaces stop before base fetch"
setup_same merge
MERGED_OID=$(git --git-dir="$ORIGIN" rev-parse refs/heads/main)
git --git-dir="$ORIGIN" update-ref refs/heads/fork/main "$MERGED_OID"
git -C "$WORK" branch fork/main "$MERGED_OID"
ON_BASE_CONFIG="$SCEN/on-base.config"
printf '[remote "origin/fork"]\n\turl = %s\n' "$ORIGIN" >"$ON_BASE_CONFIG"
git -C "$WORK" config includeIf.onbranch:fork/main.path "$ON_BASE_CONFIG"
git -C "$WORK" update-ref refs/remotes/origin/fork/main "$HEAD_OID"
jq '.baseRefName = "fork/main"' "$FIX/pr.json" >"$FIX/pr.base"
mv "$FIX/pr.base" "$FIX/pr.json"
if git -C "$WORK" remote | rg -qxF origin/fork; then
  bad "onbranch remote was visible before landing"
else
  ok
fi
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 2
want_out 'STOP remote-namespace'
want_ref "$WORK/.git" refs/remotes/origin/fork/main
want_ref "$ORIGIN" refs/heads/feature
git -C "$WORK" config --unset-all includeIf.onbranch:fork/main.path
run_cleanup
want_rc 0
want_out '"remote_branch":"deleted"'

SCENARIO="case-folding remote namespaces stop scoped prune"
setup_same merge
REF_ROOT="$(git -C "$WORK" rev-parse --absolute-git-dir)/refs/remotes"
PROBE=$(mktemp -d "$REF_ROOT/.case-probe.XXXXXX")
touch "$PROBE/origin" "$PROBE/Origin"
if [ "${FORCE_CASE_FOLD_SKIP:-}" != 1 ] \
    && [ "$PROBE/origin" -ef "$PROBE/Origin" ]; then
  rm -rf -- "$PROBE"
  git -C "$WORK" config remote.Origin.url "$ORIGIN"
  git -C "$WORK" update-ref refs/remotes/Origin/keep "$HEAD_OID"
  RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
  run_cleanup
  want_rc 2
  want_out 'STOP remote-namespace'
  want_ref "$WORK/.git" refs/remotes/Origin/keep
else
  rm -rf -- "$PROBE"
  skip=$((skip + 1))
  echo "SKIP: case-folding remote namespace fixture requires a folding filesystem" >&2
fi

SCENARIO="auto-deleted head still retargets a same-repo stack"
setup_same merge
git --git-dir="$ORIGIN" update-ref -d refs/heads/feature
printf '[{"number":8}]\n' >"$FIX/stacked.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 0
want_out '"consumers":"retargeted:1"'
if rg -q -- 'pr edit 8 .*--base=main|pr edit 8 .*--base main' "$FIX/calls.log"; then ok
else bad "stacked PR was not retargeted"; fi

SCENARIO="failed stack retarget preserves the remote branch"
setup_same merge
printf '[{"number":8}]\n' >"$FIX/stacked.json"
GH_EDIT_RC=1
export GH_EDIT_RC
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
unset GH_EDIT_RC
want_rc 2
want_out 'STOP stacked-retarget'
want_ref "$ORIGIN" refs/heads/feature

SCENARIO="fork PR deletes the fork remote only"
setup_same merge
FORK="$SCEN/fork.git"
git init -q --bare "$FORK"
git -C "$SEED" push -q "$FORK" "$HEAD_OID:refs/heads/feature"
git -C "$WORK" remote add fork "$FORK"
git -C "$WORK" fetch -q fork
git -C "$WORK" switch -q main
git -C "$WORK" branch -f feature fork/feature
git -C "$WORK" switch -q feature
git --git-dir="$ORIGIN" update-ref -d refs/heads/feature
reset_forge
write_repo_facts acme/base >"$FIX/repo-base.json"
write_repo_facts acme/fork >"$FIX/repo-head.json"
write_pr acme/base acme/fork feature "$HEAD_OID" true >"$FIX/pr.json"
RUN_REPO=acme/base; HEAD_REMOTE_ARG="--head-remote fork"
run_cleanup
want_rc 0
want_no_ref "$FORK" refs/heads/feature
want_ref "$ORIGIN" refs/heads/main

SCENARIO="fork default branch is never a deletion target"
setup_same merge
FORK="$SCEN/fork.git"
git init -q --bare "$FORK"
git -C "$SEED" push -q "$FORK" "$HEAD_OID:refs/heads/feature"
git -C "$WORK" remote add fork "$FORK"
git -C "$WORK" fetch -q fork
reset_forge
write_repo_facts acme/base >"$FIX/repo-base.json"
write_repo_facts acme/fork | jq '.default_branch = "feature"' >"$FIX/repo-head.json"
write_pr acme/base acme/fork feature "$HEAD_OID" true >"$FIX/pr.json"
RUN_REPO=acme/base; HEAD_REMOTE_ARG="--head-remote fork"
run_cleanup
want_rc 2
want_out 'STOP name-collision'
want_ref "$FORK" refs/heads/feature

SCENARIO="an option-shaped head is cleaned without option confusion"
SCEN="$TMP/scen-option"; ORIGIN="$SCEN/origin.git"
SEED="$SCEN/seed"; WORK="$SCEN/work"
mkdir -p "$SCEN"
git init -q --bare "$ORIGIN"
git init -q "$SEED"
git -C "$SEED" config user.name Test
git -C "$SEED" config user.email test@example.invalid
echo base >"$SEED/file"
git -C "$SEED" add file
git -C "$SEED" commit -qm base
git -C "$SEED" branch -M main
git -C "$SEED" remote add origin "$ORIGIN"
git -C "$SEED" push -q -u origin main
git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
git -C "$SEED" switch -q --detach main
echo option >>"$SEED/file"
git -C "$SEED" commit -qam option
HEAD_OID=$(git -C "$SEED" rev-parse HEAD)
git -C "$SEED" update-ref refs/heads/-x "$HEAD_OID"
git -C "$SEED" push -q origin refs/heads/-x:refs/heads/-x
git -C "$SEED" switch -q main
git -C "$SEED" merge -q --no-ff refs/heads/-x -m merged
git -C "$SEED" push -q origin main
git clone -q "$ORIGIN" "$WORK"
git -C "$WORK" update-ref refs/heads/-x "$HEAD_OID"
git -C "$WORK" config branch.-x.remote origin
git -C "$WORK" config branch.-x.merge refs/heads/-x
git -C "$WORK" switch -q -- -x
reset_forge
write_pr acme/repo acme/repo -x "$HEAD_OID" false >"$FIX/pr.json"
RUN_REPO=acme/repo; HEAD_REMOTE_ARG="--head-remote origin"
run_cleanup
want_rc 0
want_no_ref "$ORIGIN" refs/heads/-x
if git -C "$WORK" show-ref --verify --quiet refs/heads/-x; then
  bad "option-shaped local branch survived"
else ok; fi

fi

echo "merge-cleanup orchestration: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
