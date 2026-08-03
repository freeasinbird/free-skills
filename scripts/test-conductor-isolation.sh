#!/usr/bin/env bash
# Regression matrix for the conductor's isolation lifecycle. Offline and
# deterministic: every case builds real local repositories (a bare "remote"
# plus clones), so git's actual behavior decides each assertion, not a
# transcript of what git was believed to do.
#
# The cases exist because prose could not hold this lifecycle: each one
# pins a branch of the conditional that a review round found missing, or a
# git behavior that contradicts the obvious reading (worktree removal
# rejecting a clone, --ff-only advancing HEAD under uncommitted edits,
# a folded history never fast-forwarding).
#
# Grown one adversarial case per review finding; add a case with every
# future fix so the class stops recurring one finding at a time.
#
# Set CONDUCTOR_ISOLATION_SCRIPT to test a different copy of the script.
set -u

SCRIPT="${CONDUCTOR_ISOLATION_SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/skills/await-pr-review/conductor-isolation.sh}"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok() { pass=$((pass + 1)); }
no() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

check() { # desc, expected-exit, expected-tag, actual-exit, actual-out
  if [ "$4" -ne "$2" ]; then no "$1: exit $4 != $2 ($5)"; return; fi
  case "$5" in "$3"*) ok ;; *) no "$1: report '$5' is not $3" ;; esac
}

# A fresh scenario: bare remote, primary checkout on branch fix/x with one
# commit past main, remote and primary in sync.
scenario() {
  name=$1
  root="$WORK/$name"
  rm -rf "$root"; mkdir -p "$root"
  git init --quiet --bare "$root/remote.git"
  git init --quiet "$root/primary"
  (
    cd "$root/primary"
    git config user.email t@example.com
    git config user.name t
    git commit --quiet --allow-empty -m base
    git branch -M main
    git remote add origin "$root/remote.git"
    git push --quiet origin main
    git checkout --quiet -b fix/x
    git commit --quiet --allow-empty -m work
    git push --quiet origin fix/x
  )
  HEADSHA=$(git -C "$root/primary" rev-parse fix/x)
}

# --- usage and environment --------------------------------------------------

out=$(cd "$WORK" && bash "$SCRIPT" 2>&1); check "no subcommand" 64 "" $? "$out"
scenario usage
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" 2>&1)
check "setup without --pr or --head" 64 "" $? "$out"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --head deadbeef 2>&1)
check "setup-only flag on teardown" 64 "" $? "$out"
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --pr 1 --realign 2>&1)
check "teardown-only flag on setup" 64 "" $? "$out"
out=$(cd "$WORK" && bash "$SCRIPT" teardown --path "$WORK/nope" 2>&1)
check "outside any work tree" 69 "" $? "$out"

# --- setup ------------------------------------------------------------------

scenario setup_ok
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x 2>&1)
check "setup on the branch the primary holds" 0 ISOLATION_READY $? "$out"
# The branch form would have failed here; --detach is what makes it work.
[ "$(git -C "$root/w" rev-parse HEAD)" = "$HEADSHA" ] && ok || no "worktree head"
[ -z "$(git -C "$root/w" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" ] &&
  ok || no "worktree should be detached"

out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x 2>&1)
check "setup refuses an existing path" 1 BLOCKED $? "$out"

scenario setup_unknown
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" \
  --head 0123456789abcdef0123456789abcdef01234567 --branch fix/x 2>&1)
check "setup blocks on an unfetchable head" 1 BLOCKED $? "$out"
[ -e "$root/w" ] && no "blocked setup left a worktree behind" || ok

# A head absent locally but present on the remote branch is fetched, which
# is the fork/other-clone case that killed the prose version.
scenario setup_fetch
(
  cd "$root/primary"
  git checkout --quiet -b fix/y
  git commit --quiet --allow-empty -m remote-only
  git push --quiet origin fix/y
  git checkout --quiet fix/x
  git branch --quiet -D fix/y
)
REMOTEONLY=$(git -C "$root/remote.git" rev-parse fix/y)
git -C "$root/primary" update-ref -d refs/remotes/origin/fix/y 2>/dev/null
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$REMOTEONLY" --branch fix/y 2>&1)
check "setup fetches a head it does not hold" 0 ISOLATION_READY $? "$out"

# Host resolution, the path --head/--branch skip. A shim stands in for gh
# so the case stays offline; it was untested once, and the real run then
# failed on a malformed API path no local-repo fixture could have reached.
# Rebuilt per scenario: the shim answers with that scenario's own head, so
# a later scenario cannot be served a stale SHA.
# Three fields, as the real query always emits: its jq is
# `[.head.sha, .head.ref, (.head.repo.clone_url // "")]`, and a same-repo
# PR names the repository itself there. A two-field shim would quietly
# stand in for the null-head-repo response instead, which is its own case
# below.
hostshim() {
  SHIM="$root/shim"
  mkdir -p "$SHIM"
  cat > "$SHIM/gh" <<SH
#!/bin/sh
case "\$*" in
*"repo view"*) echo "owner/name" ;;
*"repos/owner/name/pulls/7"*) printf '%s\t%s\t%s\n' "$HEADSHA" "fix/x" "$root/remote.git" ;;
*) exit 1 ;;
esac
SH
  chmod +x "$SHIM/gh"
}

scenario setup_host
hostshim
out=$(cd "$root/primary" && PATH="$SHIM:$PATH" bash "$SCRIPT" setup --path "$root/w" --pr 7 2>&1)
check "setup resolves head and branch from the host" 0 ISOLATION_READY $? "$out"
[ "$(git -C "$root/w" rev-parse HEAD)" = "$HEADSHA" ] && ok || no "host-resolved head"
# An explicit --repo must reach the API path unmangled too.
scenario setup_host_repo
hostshim
out=$(cd "$root/primary" && PATH="$SHIM:$PATH" bash "$SCRIPT" setup --path "$root/w" \
  --repo owner/name --pr 7 2>&1)
check "setup honors an explicit --repo" 0 ISOLATION_READY $? "$out"
scenario setup_host_unknown
hostshim
out=$(cd "$root/primary" && PATH="$SHIM:$PATH" bash "$SCRIPT" setup --path "$root/w" \
  --repo owner/name --pr 999 2>&1)
check "setup blocks when the host has no such PR" 1 BLOCKED $? "$out"

# --- teardown ---------------------------------------------------------------

scenario teardown_ok
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" 2>&1)
check "teardown removes the worktree" 0 TEARDOWN_DONE $? "$out"
[ -e "$root/w" ] && no "worktree still present" || ok

out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" 2>&1)
check "teardown on nothing is a noop" 0 TEARDOWN_NOOP $? "$out"

scenario teardown_inside
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
out=$(cd "$root/w" && bash "$SCRIPT" teardown --path "$root/w" 2>&1)
check "teardown refuses from inside the target" 1 BLOCKED $? "$out"
[ -d "$root/w" ] && ok || no "refused teardown still unlinked the directory"

# A separate clone is not git's to remove (worktree removal rejects it),
# and deleting a directory is not this script's call, so removal is
# reported as the human's rather than performed or refused outright.
scenario teardown_clone
git clone --quiet "$root/remote.git" "$root/clone"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" 2>&1)
check "teardown flags a clone for manual removal" 0 TEARDOWN_DONE $? "$out"
case "$out" in *'"removed":"manual"'*) ok ;; *) no "clone not flagged manual: $out" ;; esac
[ -d "$root/clone" ] && ok || no "teardown deleted the clone"

# --- realign ----------------------------------------------------------------

# The conductor pushed a plain new commit: ordinary fast-forward.
scenario realign_ff
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --allow-empty -m fix &&
  git push --quiet origin HEAD:fix/x)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign fast-forwards" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "branch not advanced"

# The conductor folded a review fix and force-pushed, so the pushed head is
# NOT a descendant of the primary branch. This is the normal exchange, and
# the --ff-only prose failed exactly here.
scenario realign_folded
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
git -C "$root/primary" merge-base --is-ancestor "$HEADSHA" "$PUSHED" 2>/dev/null &&
  no "fixture is not actually a rewrite" || ok
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign moves a rewritten branch" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "branch not realigned"
[ -z "$(git -C "$root/primary" status --porcelain)" ] && ok || no "realign dirtied the tree"

# Uncommitted work in the primary checkout: --ff-only would advance HEAD
# underneath it, so realign must refuse instead.
scenario realign_dirty
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --allow-empty -m fix &&
  git push --quiet origin HEAD:fix/x)
echo "in progress" > "$root/primary/wip.txt"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses a dirty primary" 1 BLOCKED $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$HEADSHA" ] && ok || no "branch moved anyway"
[ -f "$root/primary/wip.txt" ] && ok || no "refused realign destroyed the edit"

# The primary branch gained a commit the conductor never saw: neither a
# fast-forward nor the recorded setup head, so it needs a human.
scenario realign_diverged
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
(cd "$root/primary" && git commit --quiet --allow-empty -m "meanwhile")
MINE=$(git -C "$root/primary" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses a diverged primary" 1 BLOCKED $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$MINE" ] && ok || no "local commit discarded"

# The branch is not checked out in the primary: move the ref, don't touch
# whatever tree the primary is actually holding.
scenario realign_not_checked_out
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
(cd "$root/primary" && git checkout --quiet main && echo untracked > keep.txt)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign updates an unchecked-out branch" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "ref not updated"
[ "$(git -C "$root/primary" symbolic-ref --short HEAD)" = main ] && ok || no "HEAD moved"
[ -f "$root/primary/keep.txt" ] && ok || no "untracked file lost"

# A third worktree holding the branch would be desynced by a ref move it
# has no way to notice, so realign refuses rather than moving it.
scenario realign_other_worktree
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
(cd "$root/primary" && git checkout --quiet main &&
  git worktree add --quiet "$root/other" fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses when another worktree holds the branch" 1 BLOCKED $? "$out"
[ "$(git -C "$root/other" rev-parse HEAD)" = "$HEADSHA" ] && ok || no "other worktree moved"

# A blocked realign must keep its state: the human clears whatever stopped
# it and re-runs, rather than reconstructing the branch and setup head.
scenario realign_resume
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
echo "in progress" > "$root/primary/wip.txt"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign blocks on a dirty primary" 1 BLOCKED $? "$out"
rm -f "$root/primary/wip.txt"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "the retry after clearing it succeeds" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "retry did not realign"

# A fork PR: the branch lives only in the fork, while refs/pull comes from
# the base. Fetching the branch from the base finds an unrelated same-named
# branch, so realigning to it would move the primary to the wrong commit.
scenario realign_fork
git init --quiet --bare "$root/fork.git"
git -C "$root/primary" remote add fork "$root/fork.git"
(cd "$root/primary" && git push --quiet fork fix/x)
# The base gains its own, unrelated fix/x.
(
  cd "$root/primary" && git checkout --quiet main &&
    git checkout --quiet -b decoy && git commit --quiet --allow-empty -m "base decoy" &&
    git push --quiet --force origin decoy:fix/x && git checkout --quiet fix/x &&
    git branch --quiet -D decoy
)
DECOY=$(git -C "$root/remote.git" rev-parse fix/x)
hostshim_fork() {
  SHIM="$root/shim"; mkdir -p "$SHIM"
  cat > "$SHIM/gh" <<SH
#!/bin/sh
case "\$*" in
*"repo view"*) echo "owner/name" ;;
*"repos/owner/name/pulls/7"*) printf '%s\t%s\t%s\n' "$HEADSHA" "fix/x" "$root/fork.git" ;;
*) exit 1 ;;
esac
SH
  chmod +x "$SHIM/gh"
}
hostshim_fork
out=$(cd "$root/primary" && PATH="$SHIM:$PATH" bash "$SCRIPT" setup --path "$root/w" --pr 7 2>&1)
check "setup records the fork as the head remote" 0 ISOLATION_READY $? "$out"
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force "$root/fork.git" HEAD:fix/x)
FORKPUSHED=$(git -C "$root/fork.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign fetches the branch from the fork" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$FORKPUSHED" ] && ok || no "realigned to the wrong remote"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$DECOY" ] && no "realigned to the base decoy" || ok

# The clone route: removal is the human's, but realignment still runs.
scenario teardown_clone_realign
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
git -C "$root/primary" worktree remove "$root/w"
# On the branch, as a conductor's clone is: `git clone` alone lands on
# the default branch, which is not a checkout any conductor ever hands
# over, and it would leave this case asserting realignment from a
# checkout that never touched fix/x.
git clone --quiet "$root/remote.git" "$root/w"
git -C "$root/w" checkout --quiet fix/x
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "clone teardown still realigns" 0 TEARDOWN_DONE $? "$out"
case "$out" in *'"removed":"manual"'*) ok ;; *) no "clone removal not flagged manual: $out" ;; esac
[ -d "$root/w" ] && ok || no "the clone was deleted"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "clone route did not realign"

# The override path skips host resolution, so --head-remote is the only
# way it learns where a fork's branch lives. Without it, the base's
# same-named branch is what teardown would find.
scenario realign_fork_override
git init --quiet --bare "$root/fork.git"
(cd "$root/primary" && git push --quiet "$root/fork.git" fix/x)
(
  cd "$root/primary" && git checkout --quiet main &&
    git checkout --quiet -b decoy && git commit --quiet --allow-empty -m "base decoy" &&
    git push --quiet --force origin decoy:fix/x && git checkout --quiet fix/x &&
    git branch --quiet -D decoy
)
DECOY=$(git -C "$root/remote.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" \
  --head "$HEADSHA" --branch fix/x --head-remote "$root/fork.git" 2>&1)
check "setup accepts an explicit head remote" 0 ISOLATION_READY $? "$out"
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force "$root/fork.git" HEAD:fix/x)
FORKPUSHED=$(git -C "$root/fork.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "override realign uses the recorded head remote" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$FORKPUSHED" ] && ok || no "wrong remote"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$DECOY" ] && no "realigned to the base decoy" || ok

# Retained state is not the next exchange's to clobber: setup refuses
# while a realignment is still pending, and works once it is done.
scenario setup_pending_state
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" 2>&1)
check "teardown without --realign retains state" 0 TEARDOWN_DONE $? "$out"
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x 2>&1)
check "setup refuses to clobber a pending realignment" 1 BLOCKED $? "$out"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "the pending realignment still runs" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "branch not realigned"
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$PUSHED" --branch fix/x 2>&1)
check "setup works once the state is cleared" 0 ISOLATION_READY $? "$out"

# `git status --porcelain` hides ignored files, so a "clean" tree is no
# proof that reset --hard destroys nothing: an ignored local file the
# pushed commit begins tracking would be overwritten in place.
scenario realign_ignored
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && echo "local.cache" > .gitignore && echo "committed" > local.cache &&
    git add -f .gitignore local.cache &&
    git commit --quiet --amend --allow-empty -m "work, tracks the cache" &&
    git push --quiet --force origin HEAD:fix/x
)
printf 'irreplaceable\n' > "$root/primary/local.cache"
# Ignored via info/exclude, deliberately: committing a .gitignore here
# would advance the primary branch and trip the "commits the conductor
# never saw" guard instead, so the case would pass without ever reaching
# the reset it exists to test.
printf 'local.cache\n' >> "$root/primary/.git/info/exclude"
[ -z "$(git -C "$root/primary" status --porcelain)" ] && ok || no "fixture is not status-clean"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$HEADSHA" ] && ok ||
  no "fixture moved the primary branch, so a different guard would fire"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses to clobber an ignored file" 1 BLOCKED $? "$out"
case "$out" in *"untracked or ignored"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac
[ "$(cat "$root/primary/local.cache")" = "irreplaceable" ] && ok || no "ignored file was destroyed"

# A credential in --head-remote would be persisted and later echoed.
scenario headremote_credentials
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" \
  --branch fix/x --head-remote 'https://tok3n@example.com/o/r.git' 2>&1)
check "credential-bearing head remote is refused" 64 "" $? "$out"
case "$out" in *tok3n*) no "the refusal echoed the credential" ;; *) ok ;; esac
[ -e "$root/w" ] && no "refused setup created a worktree" || ok
# State is owner-only: it records where a private fork lives.
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
STATEFILE=$(find "$root/primary/.git/conductor-isolation" -name '*.state' | head -1)
case "$(ls -l "$STATEFILE" | cut -c1-10)" in -rw-------) ok ;; *) no "state file is not 0600: $(ls -l "$STATEFILE")" ;; esac

# A clone the human made directly has no setup record, so --branch names
# what to realign; without the recorded setup head only a fast-forward is
# provably safe.
scenario clone_direct_realign
git clone --quiet "$root/remote.git" "$root/clone"
(
  cd "$root/clone" && git checkout --quiet fix/x &&
    git commit --quiet --allow-empty -m "conductor fix" && git push --quiet origin fix/x
)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --branch fix/x --realign 2>&1)
check "direct clone realigns with --branch" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "branch not realigned"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --realign 2>&1)
check "no branch and no state is a clear refusal" 1 BLOCKED $? "$out"

# The same route on a fork PR. No setup record names the fork, so
# `--remote` is the only thing standing between the realign and the
# base's unrelated same-named branch: this runs the recipe the skill
# documents for that case rather than asserting it works.
scenario clone_fork_realign
git clone --quiet --bare "$root/remote.git" "$root/fork.git"
(
  cd "$root/primary" && git checkout --quiet -b decoy &&
    git commit --quiet --allow-empty -m "base decoy" &&
    git push --quiet --force origin decoy:fix/x && git checkout --quiet fix/x &&
    git branch --quiet -D decoy
)
DECOY=$(git -C "$root/remote.git" rev-parse fix/x)
git clone --quiet "$root/fork.git" "$root/clone"
(
  cd "$root/clone" && git checkout --quiet fix/x &&
    git commit --quiet --amend --allow-empty -m "work, folded" &&
    git push --quiet --force origin fix/x
)
FORKPUSHED=$(git -C "$root/fork.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --realign \
  --branch fix/x --at-setup "$HEADSHA" --remote "$root/fork.git" 2>&1)
check "a fork clone realigns from the fork named by --remote" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$FORKPUSHED" ] && ok || no "not realigned to the fork"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$DECOY" ] && no "realigned to the base decoy" || ok

# Distinct paths must not share a state file.
scenario state_collision
mkdir -p "$root/a/b"
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/a/b/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/a_b_w" --head "$HEADSHA" --branch fix/x 2>&1)
check "a slash/underscore twin gets its own state" 0 ISOLATION_READY $? "$out"

# An ancestor component that is itself a local file: `-e` on the deeper
# path returns false (ENOTDIR), so testing only the full path misses the
# file reset --hard would delete to make room for the directory.
scenario realign_parent_collision
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && mkdir data && echo "from the conductor" > data/file.txt &&
    git add data/file.txt && git commit --quiet --amend --allow-empty -m "adds data/" &&
    git push --quiet --force origin HEAD:fix/x
)
printf 'PRECIOUS\n' > "$root/primary/data"
printf 'data\n' >> "$root/primary/.git/info/exclude"
[ -z "$(git -C "$root/primary" status --porcelain)" ] && ok || no "fixture not status-clean"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses when an ancestor is a local file" 1 BLOCKED $? "$out"
[ -f "$root/primary/data" ] && [ "$(cat "$root/primary/data")" = "PRECIOUS" ] &&
  ok || no "the local file was destroyed"

# --- what the collision scan sees, enumerated --------------------------------
#
# The scan asks one question per changed path: would `reset --hard`
# destroy something the index does not hold? The cases below walk the
# inputs that question has (the local shape: absent, file, real
# directory, symlink; the pushed shape: blob, tree, absent; the spelling
# git hands back; and the cwd the whole scan is resolved against) rather
# than the one shape a finding happened to name. Each must land on the
# same verdict twice: refuse where content would be lost, proceed where
# none would, since an over-refusal strands the branch just as surely.

# The collision cases need tracked paths in the commit the primary sits
# on. Committing them after setup would move the branch and trip the
# "commits the conductor never saw" guard instead, so they go in first.
seeded() { # name, then repo-relative paths to track
  scenario "$1"; shift
  (
    cd "$root/primary"
    for f; do
      mkdir -p "$(dirname "$f")"
      printf 'tracked\n' > "$f"
    done
    git add -A && git commit --quiet -m seed && git push --quiet origin fix/x
  )
  HEADSHA=$(git -C "$root/primary" rev-parse fix/x)
}

# A directory replaced by a blob. `git ls-files --error-unmatch -- foo`
# succeeds on any directory holding an indexed descendant, so the probe
# that flags a bare untracked file calls this one tracked and safe, while
# reset --hard removes the whole directory to make room for the file.
seeded realign_dir_to_blob foo/tracked
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && git rm --quiet -r foo && printf 'now a file\n' > foo &&
    git add foo && git commit --quiet --amend -m "foo becomes a file" &&
    git push --quiet --force origin HEAD:fix/x
)
printf 'IRREPLACEABLE\n' > "$root/primary/foo/cache"
printf 'foo/cache\n' >> "$root/primary/.git/info/exclude"
[ -z "$(git -C "$root/primary" status --porcelain)" ] && ok || no "fixture not status-clean"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$HEADSHA" ] && ok ||
  no "fixture moved the primary branch, so a different guard would fire"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses to replace a directory holding ignored files" 1 BLOCKED $? "$out"
case "$out" in *"untracked or ignored"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac
[ "$(cat "$root/primary/foo/cache" 2>/dev/null)" = IRREPLACEABLE ] &&
  ok || no "the ignored file inside the directory was destroyed"

# The same replacement with nothing unindexed inside: every byte there is
# recoverable, so refusing would strand the branch for no reason.
seeded realign_dir_all_tracked foo/tracked
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && git rm --quiet -r foo && printf 'now a file\n' > foo &&
    git add foo && git commit --quiet --amend -m "foo becomes a file" &&
    git push --quiet --force origin HEAD:fix/x
)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign replaces a fully tracked directory" 0 TEARDOWN_DONE $? "$out"
[ -f "$root/primary/foo" ] && ok || no "the pushed file was not materialized"

# The pushed tree merely empties the directory of tracked content. git
# removes a directory only once it is empty, so an ignored file inside
# survives and there is nothing to refuse.
seeded realign_dir_pruned foo/tracked
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && git rm --quiet foo/tracked &&
    git commit --quiet --amend --allow-empty -m "drops foo/tracked" &&
    git push --quiet --force origin HEAD:fix/x
)
printf 'IRREPLACEABLE\n' > "$root/primary/foo/cache"
printf 'foo/cache\n' >> "$root/primary/.git/info/exclude"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign proceeds when the directory is only emptied" 0 TEARDOWN_DONE $? "$out"
[ "$(cat "$root/primary/foo/cache" 2>/dev/null)" = IRREPLACEABLE ] &&
  ok || no "the ignored file was destroyed"

# A wholly untracked local directory the pushed tree writes into: the
# reset adds files beside its contents and destroys none of them.
scenario realign_untracked_dir
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && mkdir data && printf 'from the conductor\n' > data/file.txt &&
    git add data/file.txt && git commit --quiet --amend --allow-empty -m "adds data/" &&
    git push --quiet --force origin HEAD:fix/x
)
mkdir -p "$root/primary/data"
printf 'IRREPLACEABLE\n' > "$root/primary/data/notes.txt"
printf 'data/notes.txt\n' >> "$root/primary/.git/info/exclude"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign writes into an untracked directory" 0 TEARDOWN_DONE $? "$out"
[ "$(cat "$root/primary/data/notes.txt" 2>/dev/null)" = IRREPLACEABLE ] &&
  ok || no "the ignored file beside the new one was destroyed"
[ -f "$root/primary/data/file.txt" ] && ok || no "the pushed file was not materialized"

# The spelling git hands back is not always the spelling on disk:
# `--name-only` C-quotes any path with a non-ASCII byte, so the scan
# would probe a name (quotes and octal escapes included) that no
# filesystem has and find every such path absent and safe.
scenario realign_quoted_path
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && printf 'from the conductor\n' > "café.txt" && git add -A &&
    git commit --quiet --amend --allow-empty -m "tracks a non-ASCII path" &&
    git push --quiet --force origin HEAD:fix/x
)
printf 'IRREPLACEABLE\n' > "$root/primary/café.txt"
printf 'café.txt\n' >> "$root/primary/.git/info/exclude"
[ -z "$(git -C "$root/primary" status --porcelain)" ] && ok || no "fixture not status-clean"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses to clobber a C-quoted path" 1 BLOCKED $? "$out"
[ "$(cat "$root/primary/café.txt" 2>/dev/null)" = IRREPLACEABLE ] &&
  ok || no "the ignored non-ASCII path was destroyed"

# Run from a subdirectory: still the primary checkout, so "run from the
# primary checkout, never from inside --path" is satisfied. Comparing the
# cwd against `git worktree list` roots would report this checkout as
# another worktree holding the branch.
scenario realign_from_subdir
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
mkdir -p "$root/primary/sub"
out=$(cd "$root/primary/sub" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign runs from a subdirectory of the primary" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$(git -C "$root/remote.git" rev-parse fix/x)" ] &&
  ok || no "branch not realigned"

# The same subdirectory, now with a name that resolves differently there:
# the changed path is root-relative, so a pathspec evaluated against the
# cwd asks about sub/local.cache (tracked, judged safe) while the file
# the reset would overwrite is the ignored one at the root.
seeded realign_subdir_shadow sub/local.cache
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && printf 'from the conductor\n' > local.cache && git add local.cache &&
    git commit --quiet --amend -m "tracks local.cache at the root" &&
    git push --quiet --force origin HEAD:fix/x
)
printf 'IRREPLACEABLE\n' > "$root/primary/local.cache"
printf '/local.cache\n' >> "$root/primary/.git/info/exclude"
[ -z "$(git -C "$root/primary" status --porcelain)" ] && ok || no "fixture not status-clean"
out=$(cd "$root/primary/sub" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign resolves changed paths against the root, not the cwd" 1 BLOCKED $? "$out"
case "$out" in *"untracked or ignored"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac
[ "$(cat "$root/primary/local.cache" 2>/dev/null)" = IRREPLACEABLE ] &&
  ok || no "the ignored file at the root was destroyed"

# scp-style remotes carry userinfo with no `://` for a scheme pattern to
# anchor on, so a token there must be refused and never echoed.
scenario scp_credentials
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" \
  --branch fix/x --head-remote 'ghp_sekrit@127.0.0.1:o/r.git' 2>&1)
check "scp-style credential is refused" 64 "" $? "$out"
case "$out" in *ghp_sekrit*) no "the refusal echoed the token" ;; *) ok ;; esac
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" \
  --branch fix/x --remote 'ghp_sekrit@127.0.0.1:o/r.git' 2>&1)
check "--remote is checked for credentials too" 64 "" $? "$out"
# The conventional ssh identity is not a secret and must still work.
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" \
  --branch fix/x --head-remote 'git@github.com:o/r.git' 2>&1)
check "git@ ssh remotes are still accepted" 0 ISOLATION_READY $? "$out"

# Userinfo is one place a token rides, not the place. A signed URL keeps
# it in the query or the fragment, where a userinfo check sees nothing:
# the value was then accepted, written to the state file, and printed
# back in the BLOCKED report when the fetch failed.
for form in 'https://example.com/o/r.git?access_token=ghp_sekrit' \
  'https://example.com/o/r.git#ghp_sekrit' \
  'git@example.com:o/r.git?access_token=ghp_sekrit'; do
  scenario query_credentials
  out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" \
    --branch fix/x --head-remote "$form" 2>&1)
  check "a token outside userinfo is refused ($form)" 64 "" $? "$out"
  case "$out" in *ghp_sekrit*) no "the refusal echoed the token" ;; *) ok ;; esac
  [ -e "$root/w" ] && no "refused setup created a worktree" || ok
  [ -z "$(find "$root/primary/.git/conductor-isolation" -name '*.state' 2>/dev/null)" ] &&
    ok || no "refused setup persisted a state file"
  out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" \
    --branch fix/x --remote "$form" 2>&1)
  check "--remote is checked the same way ($form)" 64 "" $? "$out"
done

# The shape is what is refused, so a clean URL of every accepted form
# must still pass: refusing these would strand the fork route entirely.
scenario clean_remote_forms
for form in 'https://example.com/o/r.git' 'ssh://git@example.com/o/r.git' \
  "file://$root/remote.git" '../sibling.git'; do
  rm -rf "$root/w"
  out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" \
    --branch fix/x --head-remote "$form" 2>&1)
  check "a credential-free remote is accepted ($form)" 0 ISOLATION_READY $? "$out"
  (cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" >/dev/null 2>&1)
  find "$root/primary/.git/conductor-isolation" -name '*.state' -delete 2>/dev/null
done

# --- what the remote branch holds at teardown -------------------------------
#
# Every other realign guard asks what the *local* branch holds. None of
# them looks at whether the fetched tip is the one the conductor pushed,
# so a contributor landing a commit in the window between that push and
# teardown rides straight through them onto the primary checkout.

# Another contributor force-pushes an unrelated head over the branch.
scenario realign_hijacked
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
CONDUCTOR=$(git -C "$root/w" rev-parse HEAD)
git clone --quiet "$root/remote.git" "$root/other"
(
  cd "$root/other" && git checkout --quiet -b hijack "$HEADSHA" &&
    git commit --quiet --allow-empty -m "unreviewed, from someone else" &&
    git push --quiet --force origin hijack:fix/x
)
HIJACK=$(git -C "$root/remote.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses a head the conductor did not push" 1 BLOCKED $? "$out"
case "$out" in *"someone else pushed"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$HIJACK" ] &&
  no "the primary branch was reset to the unreviewed head" || ok
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$HEADSHA" ] && ok || no "the branch moved at all"

# "Unchanged since setup" is only "nothing the conductor missed" when
# there was nothing to miss at setup. A branch sitting on clean unpushed
# commits is unchanged at teardown while holding work the conductor never
# had, and the rewritten realign would reset it away.
scenario setup_local_ahead
(cd "$root/primary" && git commit --quiet --allow-empty -m "unpushed local work")
LOCAL=$(git -C "$root/primary" rev-parse fix/x)
[ "$LOCAL" != "$HEADSHA" ] && ok || no "fixture: the branch is not ahead of the PR head"
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x 2>&1)
check "setup proceeds with an unpushed local commit" 0 ISOLATION_READY $? "$out"
case "$out" in *local_unpushed*) ok ;; *) no "setup did not surface the unpushed state: $out" ;; esac
STATEFILE=$(find "$root/primary/.git/conductor-isolation" -name '*.state' | head -1)
grep -q '^primary=$' "$STATEFILE" && ok || no "the unseen tip was recorded as the setup head"
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses rather than discarding them" 1 BLOCKED $? "$out"
case "$out" in *"never saw"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$LOCAL" ] && ok || no "the branch moved"
git -C "$root/primary" merge-base --is-ancestor "$LOCAL" fix/x 2>/dev/null &&
  ok || no "the unpushed commit was discarded"
# --at-setup remains the explicit way to say "discard them, I mean it".
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign \
  --branch fix/x --at-setup "$LOCAL" 2>&1)
check "--at-setup still overrides deliberately" 0 TEARDOWN_DONE $? "$out"

# Refusing to realign is only half the protection. Removing the worktree
# drops the detached HEAD and its reflog, which are the only references
# to the conductor's commits when the push went to a URL rather than a
# configured remote, so the fixes the refusal exists to protect are
# collectable by the time the human reads it.
scenario realign_hijacked_objects
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "the review fixes" &&
  git push --quiet --force "$root/remote.git" HEAD:fix/x)
CONDUCTOR=$(git -C "$root/w" rev-parse HEAD)
[ -z "$(git -C "$root/primary" for-each-ref --contains "$CONDUCTOR" 2>/dev/null)" ] && ok ||
  no "fixture: some other ref already holds the commit, so nothing would be at risk"
git clone --quiet "$root/remote.git" "$root/other"
(
  cd "$root/other" && git checkout --quiet -b hj "$HEADSHA" &&
    git commit --quiet --allow-empty -m "unreviewed, from someone else" &&
    git push --quiet --force "$root/remote.git" hj:fix/x
)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign still refuses the hijacked head" 1 BLOCKED $? "$out"
case "$out" in *'"saved":"refs/conductor-isolation/'*) ok ;; *) no "the report does not name where the work is: $out" ;; esac
git -C "$root/primary" reflog expire --expire=now --all
git -C "$root/primary" gc --quiet --prune=now
git -C "$root/primary" cat-file -e "$CONDUCTOR^{commit}" 2>/dev/null &&
  ok || no "the conductor's commits were collected"

# The same window, but the contributor merely adds a commit on top. It
# still fast-forwards cleanly, which is exactly why the other guards miss
# it: the head is unreviewed either way.
scenario realign_appended
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
git clone --quiet "$root/remote.git" "$root/other"
(
  cd "$root/other" && git checkout --quiet fix/x &&
    git commit --quiet --allow-empty -m "appended by someone else" &&
    git push --quiet origin fix/x
)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign refuses an appended commit too" 1 BLOCKED $? "$out"
case "$out" in *"someone else pushed"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac

# The proof survives the removal, which happens before every guard: a
# realign blocked on a dirty primary must still be retryable once the
# human clears it, and by then the checkout is gone.
scenario realign_proof_persisted
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" >/dev/null 2>&1)
[ -e "$root/w" ] && no "the worktree was not removed" || ok
STATEFILE=$(find "$root/primary/.git/conductor-isolation" -name '*.state' | head -1)
grep -q "^final=$PUSHED$" "$STATEFILE" && ok || no "the final head was not recorded"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "a deferred realign uses the recorded proof" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "branch not realigned"

# With no checkout left and no record, there is nothing to check against,
# so the destructive path refuses rather than trusting the fetch.
scenario realign_no_proof
git clone --quiet "$root/remote.git" "$root/clone"
(
  cd "$root/clone" && git checkout --quiet fix/x &&
    git commit --quiet --allow-empty -m "conductor fix" && git push --quiet origin fix/x
)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
rm -rf "$root/clone"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --branch fix/x --realign 2>&1)
check "realign refuses with no proof available" 1 BLOCKED $? "$out"
case "$out" in *"no proof"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --branch fix/x --realign \
  --expect "$PUSHED" 2>&1)
check "--expect supplies that proof by hand" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "branch not realigned"

# And it is checked, not trusted: a wrong --expect refuses.
scenario realign_wrong_expect
git clone --quiet "$root/remote.git" "$root/clone"
(
  cd "$root/clone" && git checkout --quiet fix/x &&
    git commit --quiet --allow-empty -m "conductor fix" && git push --quiet origin fix/x
)
rm -rf "$root/clone"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --branch fix/x --realign \
  --expect "$HEADSHA" 2>&1)
check "a wrong --expect refuses" 1 BLOCKED $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$HEADSHA" ] && ok || no "the branch moved anyway"

# Which ref in a separate clone is the proof depends on where its HEAD
# sits, and all three placements are reachable: detached is the route the
# skill documents, and a clone parked on another branch is what a human
# leaves behind after pushing.
scenario clone_detached_proof
git clone --quiet "$root/remote.git" "$root/clone"
(
  cd "$root/clone" && git config user.email t@e.com && git config user.name t &&
    git checkout --quiet fix/x && git checkout --quiet --detach &&
    git commit --quiet --amend --allow-empty -m "work, folded" &&
    git push --quiet --force origin HEAD:fix/x
)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
[ "$(git -C "$root/clone" rev-parse refs/heads/fix/x)" = "$PUSHED" ] &&
  no "fixture: the stale branch ref would not distinguish the two" || ok
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --realign \
  --branch fix/x --at-setup "$HEADSHA" 2>&1)
check "a detached clone proves with HEAD, not its stale branch" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "branch not realigned"

# Parked on another branch after pushing: now HEAD is the unrelated one
# and the local branch is what it pushed.
scenario clone_parked_proof
git clone --quiet "$root/remote.git" "$root/clone"
(
  cd "$root/clone" && git config user.email t@e.com && git config user.name t &&
    git checkout --quiet fix/x &&
    git commit --quiet --amend --allow-empty -m "work, folded" &&
    git push --quiet --force origin fix/x && git checkout --quiet main
)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --realign \
  --branch fix/x --at-setup "$HEADSHA" 2>&1)
check "a clone parked elsewhere proves with the branch ref" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "branch not realigned"

# Parked elsewhere and never holding the branch at all: it knows nothing
# about it, so its HEAD must not be offered up as the pushed head.
scenario clone_unrelated_proof
git clone --quiet "$root/remote.git" "$root/clone"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --realign \
  --branch fix/x --at-setup "$HEADSHA" 2>&1)
check "a clone that never held the branch offers no proof" 1 BLOCKED $? "$out"
case "$out" in *"no proof"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac

# `status.showUntrackedFiles=no` must not be able to switch off a
# cleanliness guard: a post-checkout hook's output would then sit in a
# worktree reported clean, ready for a broad `git add` to sweep into the
# conductor's push.
scenario untracked_hidden
git -C "$root/primary" config status.showUntrackedFiles no
printf '#!/bin/sh\nprintf generated > "$PWD/hook-output.txt"\n' \
  > "$root/primary/.git/hooks/post-checkout"
chmod +x "$root/primary/.git/hooks/post-checkout"
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x 2>&1)
check "setup sees untracked files the config hides" 1 BLOCKED $? "$out"
case "$out" in *"not clean"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac

# The same config, on the teardown side's guard.
scenario untracked_hidden_realign
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
git -C "$root/primary" config status.showUntrackedFiles no
printf 'in progress\n' > "$root/primary/wip.txt"
[ -z "$(git -C "$root/primary" status --porcelain)" ] && ok ||
  no "fixture: the config is not hiding the file"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign sees untracked files the config hides" 1 BLOCKED $? "$out"
case "$out" in *"not clean"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac

# A path component may *end* in a newline, and command substitution
# strips every trailing one. The ancestor walk then steps to a different
# path than the one it is walking, and the collision it exists to find is
# at the name it skipped. `$'...'` here deliberately: `$(printf 'foo\n')`
# would lose the byte before the fixture ever started.
scenario realign_trailing_newline_ancestor
NLDIR=$'foo\n'
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(
  cd "$root/w" && mkdir "$NLDIR" && printf 'from the conductor\n' > "$NLDIR/bar" &&
    git add -A && git commit --quiet --amend --allow-empty -m "adds a newline-named directory" &&
    git push --quiet --force origin HEAD:fix/x
)
printf 'IRREPLACEABLE\n' > "$root/primary/$NLDIR"
# A literal newline cannot be written into an exclude pattern, so the
# glob stands in for the name.
printf 'foo*\n' >> "$root/primary/.git/info/exclude"
[ -z "$(git -C "$root/primary" status --porcelain --untracked-files=all)" ] && ok ||
  no "fixture not status-clean, so the cleanliness guard would fire instead"
[ -f "$root/primary/$NLDIR" ] && ok || no "fixture: the newline-named file was not created"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign walks ancestors without losing a trailing newline" 1 BLOCKED $? "$out"
case "$out" in *"untracked or ignored"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac
[ "$(cat "$root/primary/$NLDIR" 2>/dev/null)" = IRREPLACEABLE ] &&
  ok || no "the ignored file was destroyed"

# The same stripping in path normalization, where the trailing slash that
# tab completion adds must still be normalized away.
scenario abspath_shapes
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w/" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "a trailing slash still names the same worktree" 0 TEARDOWN_DONE $? "$out"
case "$out" in *'"removed":"worktree"'*) ok ;; *) no "the trailing-slash path was not recognized: $out" ;; esac
# The suffix position specifically: a newline in the middle of a path
# survives a command substitution, so the embedded-newline case above
# would pass while `--path w<newline>` silently operated on `w`, and
# teardown would then remove whatever unrelated worktree sits there.
scenario path_trailing_newline
NLPATH="$root/w"$'\n'
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$NLPATH" --head "$HEADSHA" --branch fix/x 2>&1)
check "setup keeps a trailing newline in --path" 0 ISOLATION_READY $? "$out"
[ -d "$NLPATH" ] && ok || no "the worktree was not created at the requested path"
[ -e "$root/w" ] && no "it was created at the stripped path instead" || ok
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$NLPATH" 2>&1)
check "teardown finds it at that same path" 0 TEARDOWN_DONE $? "$out"
case "$out" in *'"removed":"worktree"'*) ok ;; *) no "not recognized as a linked worktree: $out" ;; esac
[ -e "$NLPATH" ] && no "the worktree directory was left behind" || ok

scenario abspath_relative
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path ../w --head "$HEADSHA" --branch fix/x 2>&1)
check "a relative path resolves" 0 ISOLATION_READY $? "$out"
case "$out" in *"$root/w"*) ok ;; *) no "not resolved against the parent: $out" ;; esac

# A path may legally hold a newline, and both the parser and the report
# assumed otherwise: the line-oriented worktree read never saw a whole
# `worktree <target>` record, so teardown called its own linked worktree
# a foreign directory and left it registered, while the report split
# across two lines of invalid JSON.
scenario newline_path
NLPATH="$root/w
two"
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$NLPATH" --head "$HEADSHA" --branch fix/x 2>&1)
check "setup accepts a path containing a newline" 0 ISOLATION_READY $? "$out"
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = 0 ] && ok || no "the report spans more than one line"
case "$out" in *'w\ntwo'*) ok ;; *) no "the newline was not escaped: $out" ;; esac
[ -d "$NLPATH" ] && ok || no "the worktree was not created"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$NLPATH" 2>&1)
check "teardown removes a worktree at such a path" 0 TEARDOWN_DONE $? "$out"
case "$out" in *'"removed":"worktree"'*) ok ;; *) no "not recognized as a linked worktree: $out" ;; esac
[ -e "$NLPATH" ] && no "the worktree directory was left behind" || ok
[ "$(git -C "$root/primary" worktree list --porcelain | grep -c 'w$')" = 0 ] &&
  ok || no "the worktree is still registered"

# A byte that is not part of a valid UTF-8 sequence parses as text here
# but leaves the payload undecodable for any caller, so it is escaped
# too. Fed through --remote, which a BLOCKED report echoes back, since a
# filesystem that rejects such names (APFS does) cannot host the fixture.
scenario invalid_utf8_report
RAW=$(printf 'r\377')
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" \
  --head 0123456789abcdef0123456789abcdef01234567 --branch fix/x --remote "$RAW" 2>&1)
check "an unfetchable head still reports" 1 BLOCKED $? "$out"
case "$out" in *'r\u00ff'*) ok ;; *) no "the invalid byte was not escaped: $out" ;; esac
case "$out" in *"$(printf '\377')"*) no "the raw byte reached the payload" ;; *) ok ;; esac
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = 0 ] && ok || no "the report spans more than one line"

# Valid UTF-8 must survive it, or every non-ASCII path in a report turns
# into a wall of escapes for no reason.
scenario valid_utf8_report
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" \
  --head 0123456789abcdef0123456789abcdef01234567 --branch fix/x --remote 'café' 2>&1)
check "a valid UTF-8 remote still reports" 1 BLOCKED $? "$out"
case "$out" in *café*) ok ;; *) no "valid UTF-8 was mangled: $out" ;; esac

# A tab reaches the same report and needs the same escape.
scenario tab_path
TABPATH="$root/w$(printf '\t')tab"
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$TABPATH" --head "$HEADSHA" --branch fix/x 2>&1)
check "setup accepts a path containing a tab" 0 ISOLATION_READY $? "$out"
case "$out" in *'w\ttab'*) ok ;; *) no "the tab was not escaped: $out" ;; esac

# The state file is `key=value` lines, so a control character in a remote
# truncates what teardown later fetches from. No remote spelling needs one.
scenario control_remote
out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" \
  --branch fix/x --head-remote "https://example.com/o/r.git
headurl=https://evil.example.com/o/r.git" 2>&1)
check "a control character in a remote is refused" 64 "" $? "$out"
[ -z "$(find "$root/primary/.git/conductor-isolation" -name '*.state' 2>/dev/null)" ] &&
  ok || no "refused setup persisted a state file"

# `.head.repo` is null for a deleted or inaccessible fork, and the empty
# string that leaves is not the base repository, it is the host saying it
# does not know. Falling back to the base resolves the branch against a
# repository that never held it.
scenario host_null_head_repo
(
  cd "$root/primary" && git checkout --quiet -b decoy &&
    git commit --quiet --allow-empty -m "an unrelated base branch" &&
    git push --quiet --force origin decoy:fix/x && git checkout --quiet fix/x &&
    git branch --quiet -D decoy
)
SHIM="$root/shim"; mkdir -p "$SHIM"
cat > "$SHIM/gh" <<SH
#!/bin/sh
case "\$*" in
*"repo view"*) echo "owner/name" ;;
*"repos/owner/name/pulls/7"*) printf '%s\t%s\t%s\n' "$HEADSHA" "fix/x" "" ;;
*) exit 1 ;;
esac
SH
chmod +x "$SHIM/gh"
out=$(cd "$root/primary" && PATH="$SHIM:$PATH" bash "$SCRIPT" setup --path "$root/w" --pr 7 2>&1)
check "setup blocks when the host names no head repository" 1 BLOCKED $? "$out"
case "$out" in *"did not name the head repository"*) ok ;; *) no "blocked for the wrong reason: $out" ;; esac
[ -e "$root/w" ] && no "blocked setup created a worktree" || ok
# Naming it by hand is the way through, and it must still be recorded.
out=$(cd "$root/primary" && PATH="$SHIM:$PATH" bash "$SCRIPT" setup --path "$root/w" --pr 7 \
  --head-remote "$root/remote.git" 2>&1)
check "--head-remote supplies what the host omitted" 0 ISOLATION_READY $? "$out"

# The head repository URL is a field of a value the host handed back, and
# it reaches the same state file and the same reports as the flags do.
scenario host_credentials
SHIM="$root/shim"; mkdir -p "$SHIM"
cat > "$SHIM/gh" <<SH
#!/bin/sh
case "\$*" in
*"repo view"*) echo "owner/name" ;;
*"repos/owner/name/pulls/7"*)
  printf '%s\t%s\t%s\n' "$HEADSHA" "fix/x" "https://example.com/o/r.git?access_token=ghp_sekrit" ;;
*) exit 1 ;;
esac
SH
chmod +x "$SHIM/gh"
out=$(cd "$root/primary" && PATH="$SHIM:$PATH" bash "$SCRIPT" setup --path "$root/w" --pr 7 2>&1)
check "a credential in the host-resolved URL blocks setup" 1 BLOCKED $? "$out"
case "$out" in *ghp_sekrit*) no "the refusal echoed the host's token" ;; *) ok ;; esac
[ -z "$(find "$root/primary/.git/conductor-isolation" -name '*.state' 2>/dev/null)" ] &&
  ok || no "blocked setup persisted the host's URL"

# A same-named tag must not win the fetch and become the "pushed head".
scenario fetch_tag_shadow
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/w" && git commit --quiet --amend --allow-empty -m "work, folded" &&
  git push --quiet --force origin HEAD:fix/x)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
(
  cd "$root/primary" && git checkout --quiet main &&
    git commit --quiet --allow-empty -m "unrelated tagged commit" &&
    git tag decoy-tag && git push --quiet origin decoy-tag:refs/tags/fix/x &&
    git checkout --quiet fix/x
)
TAGGED=$(git -C "$root/primary" rev-parse decoy-tag)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign ignores a same-named tag" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "did not land on the branch head"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$TAGGED" ] && no "realigned to the tag" || ok

# The clone route's rewritten case: --at-setup supplies by hand the proof
# that setup would have recorded.
scenario clone_at_setup
BEFORE=$(git -C "$root/primary" rev-parse fix/x)
git clone --quiet "$root/remote.git" "$root/clone"
(
  cd "$root/clone" && git checkout --quiet fix/x &&
    git commit --quiet --amend --allow-empty -m "folded by hand" &&
    git push --quiet --force origin fix/x
)
PUSHED=$(git -C "$root/remote.git" rev-parse fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --branch fix/x --realign 2>&1)
check "a rewritten clone realign blocks without proof" 1 BLOCKED $? "$out"
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --branch fix/x \
  --at-setup "$BEFORE" --realign 2>&1)
check "--at-setup unlocks the rewritten case" 0 TEARDOWN_DONE $? "$out"
[ "$(git -C "$root/primary" rev-parse fix/x)" = "$PUSHED" ] && ok || no "not realigned"
# A wrong --at-setup proves nothing and must not unlock it.
scenario clone_at_setup_wrong
git clone --quiet "$root/remote.git" "$root/clone"
(cd "$root/clone" && git checkout --quiet fix/x &&
  git commit --quiet --amend --allow-empty -m "folded" && git push --quiet --force origin fix/x)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/clone" --branch fix/x \
  --at-setup "$(git -C "$root/primary" rev-parse main)" --realign 2>&1)
check "a wrong --at-setup still blocks" 1 BLOCKED $? "$out"

# Two spellings of one directory on a case-insensitive filesystem must
# share a state record, or the first exchange's realignment is orphaned.
scenario state_case
mkdir -p "$root/wt"
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/wt/Foo" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/wt/Foo" >/dev/null 2>&1)
printf 'probe' > "$root/wt/probe"
if [ -e "$root/wt/PROBE" ]; then
  out=$(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/wt/foo" --head "$HEADSHA" --branch fix/x 2>&1)
  check "a case twin sees the pending realignment" 1 BLOCKED $? "$out"
else
  ok  # case-sensitive filesystem: the two paths really are distinct
fi

# Nothing to do is not a failure.
scenario realign_noop
(cd "$root/primary" && bash "$SCRIPT" setup --path "$root/w" --head "$HEADSHA" --branch fix/x >/dev/null 2>&1)
out=$(cd "$root/primary" && bash "$SCRIPT" teardown --path "$root/w" --realign 2>&1)
check "realign with no new push" 0 TEARDOWN_DONE $? "$out"

printf 'conductor isolation: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
