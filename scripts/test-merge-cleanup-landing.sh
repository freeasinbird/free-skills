#!/usr/bin/env bash
# Validation matrix for skills/merge-cleanup/base-landing-plan.sh.
#
# Every case here is either a hazard reproduced against real git before the
# rule existed, or one of the five review rounds that the prose version of this
# landing decision drew on PR #99: the hyphen base treated as a stop (r1), the
# `git switch` probe and the missing upstream (r2), the tracking repair judged
# by consequence rather than parity (r4), and the one-key-versus-two-key check
# (r5). Round 3 left no case because its finding was a missing terminator on
# `git branch -D`, off this path. A case that only passes is not enough, so the
# ones marked
# "discriminating" were also run against degraded copies of the script and fail
# against them. On the landing decision: no switch verb, one fetch refspec, one
# tracking key, a plain --porcelain status, an --ignored status, an
# unconditional switch probe, a probe moved after the dirty guard, a probe that
# invokes `git switch -h`, a remote check scoped to the landing, a remote read
# without its `--`, a config check reading only an exit code, a help check using
# the colon form of the default, a help flag scanned across every argument,
# byte-wise `\u` escaping of UTF-8, no UTF-8 validation of the arguments, a
# character-counting locale with the byte count on a `local` declaration line,
# no fsmonitor override, a tracking key read as an aggregate rather than as its
# effective value, a remote checked by existence alone, a remote URL trimmed
# before testing, a ref enumeration left in a pipeline, a config read treating
# every failure as "not set", an unscoped inactive ref-storage extension, and a
# raw repository-format string dispatch. On the ref-path guards: `show-ref
# --verify` as the existence probe, no refusal of the revision-shorthand names,
# no case-collision stop, a collision keyed on core.ignoreCase rather than on
# what the ref store does, a packed-case fallback applied only to branches, one
# that only folds names and so misses a Unicode alias, no directory/file
# conflict guard, a scan rooted in each destination's own namespace, one relying
# on the enumeration alone and so blind to a dangling symref, one testing
# ancestors but not descendants, one rooting its ref stats at the worktree's
# own git dir, one gating the tracking-destination check on create, one stopping
# on directory existence alone, and one scanning a ref directory for regular
# files only, plus one classifying special entries only at the destinations and
# only after broad ref enumeration, and a blanket special-node scan that
# includes invalid ref paths. Where a case does not discriminate against any of
# those, the comment says so rather than implying coverage it lacks.
#
# Usage: test-merge-cleanup-landing.sh
# Exit codes: 0 all passed, 1 a case failed.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT="$ROOT/skills/merge-cleanup/base-landing-plan.sh"
TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

REALGIT=$(command -v git) || { echo "test: git is not on PATH" >&2; exit 1; }
REALBASH=$(command -v bash) || { echo "test: bash is not on PATH" >&2; exit 1; }

# A UTF-8 locale that is actually installed. Naming one that is not (a minimal
# container often has only C, C.utf8 and POSIX) makes setlocale fail and leaves
# the previous locale in place, so the case below would run under C byte
# semantics and pass with the bug it exists to catch restored. Empty means none
# was found, and that case says so rather than pretending to cover it.
UTF8_LOCALE=""
for l in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  if locale -a 2>/dev/null | grep -qxF "$l"; then UTF8_LOCALE="$l"; break; fi
done

PASS=0
FAIL=0
NAME=""

G() { local d="$1"; shift; git -C "$d" "$@" >/dev/null 2>&1; }

scenario() { # scenario <name>: a bare origin at $ORIGIN, a work repo at $REPO
  NAME="$1"
  SCEN=$(mktemp -d "$TMP/scen.XXXXXX")
  ORIGIN="$SCEN/origin.git"
  REPO="$SCEN/work"
  SHIM=""
  git init -q --bare "$ORIGIN"
  git init -q -b main "$REPO"
  printf 'a\n' > "$REPO/a.txt"
  printf '.env\n' > "$REPO/.gitignore"
  G "$REPO" add .
  G "$REPO" commit -m seed
  G "$REPO" remote add origin "$ORIGIN"
  G "$REPO" push origin main
  # `git branch` refuses an option-shaped name ("is not a valid branch name")
  # while update-ref creates it, and a forge creating refs through its API is
  # under no stricter constraint. Both sides get the branch so the create paths
  # have something real to fetch.
  OID=$(git -C "$REPO" rev-parse HEAD)
  G "$REPO" update-ref refs/heads/-x "$OID"
  G "$REPO" push origin 'refs/heads/-x:refs/heads/-x'
}

scenario_reftable() { # scenario_reftable <name>: scenario using reftable refs
  NAME="$1"
  SCEN=$(mktemp -d "$TMP/scen.XXXXXX")
  ORIGIN="$SCEN/origin.git"
  REPO="$SCEN/work"
  SHIM=""
  git init -q --bare "$ORIGIN"
  git init -q --ref-format=reftable -b main "$REPO" 2>/dev/null || return 1
  printf 'a\n' > "$REPO/a.txt"
  printf '.env\n' > "$REPO/.gitignore"
  G "$REPO" add .
  G "$REPO" commit -m seed
  G "$REPO" remote add origin "$ORIGIN"
  G "$REPO" push origin main
}

track() { # track <repo> <branch> <remote>: write a complete upstream pair
  G "$1" config "branch.$2.remote" "$3"
  G "$1" config "branch.$2.merge" "refs/heads/$2"
}

make_shim() { # make_shim: sets $SHIM to a PATH dir whose git has no `switch`
  SHIM="$SCEN/shim"
  mkdir -p "$SHIM"
  cat > "$SHIM/git" <<EOF
#!/bin/sh
# git 2.22 and earlier, where switch does not exist yet: absent from the
# builtin list, and not a command.
if [ "\$1" = "--list-cmds=builtins" ]; then
  $REALGIT "\$@" | grep -vx switch
  exit 0
fi
if [ "\$1" = switch ]; then
  echo "git: 'switch' is not a git command." >&2
  exit 1
fi
exec $REALGIT "\$@"
EOF
  chmod +x "$SHIM/git"
}

run_in() { # run_in <dir> <args...>: captures OUT and RC
  local d="$1"; shift
  OUT=$(cd "$d" && "$SUT" "$@" 2>&1)
  RC=$?
}
run() { run_in "$REPO" "$@"; }
run_nul() { # run_nul <args...>: captures NUL_FIELDS and RC
  local file field
  file="$SCEN/nul-plan"
  NUL_FIELDS=()
  (cd "$REPO" && "$SUT" --format nul "$@" >"$file" 2>&1)
  RC=$?
  while IFS= read -r -d '' field; do
    NUL_FIELDS[${#NUL_FIELDS[@]}]="$field"
  done <"$file"
  OUT=$(LC_ALL=C tr '\0' '|' <"$file")
}
run_with_fifo_breaker() { # run_with_fifo_breaker <fifo> <marker> <args...>
  local fifo="$1" marker="$2" breaker
  shift 2
  (
    sleep 1
    printf 'not-a-ref\n' > "$fifo"
    : > "$marker"
  ) &
  breaker=$!
  run "$@"
  if kill -0 "$breaker" 2>/dev/null; then
    kill "$breaker" 2>/dev/null
    wait "$breaker" 2>/dev/null
  fi
  [ ! -e "$marker" ]
}
run_switchless() { # run <args...> against a git that lacks `switch`
  [ -n "$SHIM" ] || make_shim
  OUT=$(cd "$REPO" && PATH="$SHIM:$PATH" "$SUT" "$@" 2>&1)
  RC=$?
}

snapshot() { # snapshot <repo>: everything a read-only run must leave alone
  local g
  g=$(git -C "$1" rev-parse --absolute-git-dir 2>&1)
  git -C "$1" for-each-ref 2>&1
  git -C "$1" symbolic-ref HEAD 2>&1
  git -C "$1" config --list 2>&1
  git -C "$1" --no-optional-locks status -uall --porcelain 2>&1
  # Refs and config alone miss three whole classes of mutation: a stray fetch
  # writes FETCH_HEAD without touching any ref that was already current, a
  # merge or reset writes ORIG_HEAD, and a plain `git status` rewrites the
  # index to refresh stale stat information. cksum rather than a hash tool,
  # for POSIX portability.
  cat "$g/FETCH_HEAD" "$g/ORIG_HEAD" 2>&1
  git -C "$1" reflog show --all 2>&1
  cksum < "$g/index" 2>&1
}

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $NAME: $1"; }

want_rc() {
  if [ "$RC" -eq "$1" ]; then ok; else bad "exit $RC, wanted $1 (got: $OUT)"; fi
}
want_out() {
  case "$OUT" in
    *"$1"*) ok ;;
    *) bad "output lacks '$1' (got: $OUT)" ;;
  esac
}
want_no_out() {
  case "$OUT" in
    *"$1"*) bad "output holds '$1' and should not (got: $OUT)" ;;
    *) ok ;;
  esac
}

# --- the ordinary baseline ---------------------------------------------------

# does not discriminate: the baseline every other case is read against.
scenario "an ordinary base with a local branch and a complete pair"
track "$REPO" main origin
run origin main
want_rc 0
want_out 'OK landing'
want_out '"verb":"checkout"'
want_out '"create":false'
want_out '"fetch":[]'
want_out '"tracking":"ok"'
want_out '"tag_shadow":false'

# The executable orchestrator consumes this contract. Assert every field and
# its order directly so a JSON-only planner cannot pass while breaking cleanup.
scenario "the NUL plan exposes the complete existing-branch contract"
track "$REPO" main origin
run_nul origin main
want_rc 0
[ "${#NUL_FIELDS[@]}" -eq 8 ] && ok || bad "field count is ${#NUL_FIELDS[@]}, wanted 8"
expected=("OK landing" origin main checkout false ok false 0)
for i in 0 1 2 3 4 5 6 7; do
  [ "${NUL_FIELDS[$i]:-}" = "${expected[$i]}" ] && ok \
    || bad "field $i is '${NUL_FIELDS[$i]:-}', wanted '${expected[$i]}'"
done

scenario "the NUL plan includes the ordinary create refspec"
run_nul origin feat
want_rc 0
[ "${#NUL_FIELDS[@]}" -eq 9 ] && ok || bad "field count is ${#NUL_FIELDS[@]}, wanted 9"
[ "${NUL_FIELDS[7]:-}" = 1 ] && ok || bad "fetch count is '${NUL_FIELDS[7]:-}'"
[ "${NUL_FIELDS[8]:-}" = 'refs/heads/feat' ] && ok \
  || bad "unexpected create refspec: ${NUL_FIELDS[8]:-}"

scenario "a remote literally named --format keeps the two-position contract"
G "$REPO" config remote.--format.url "$ORIGIN"
run --format main
want_rc 0
want_out 'OK landing'
want_out '"remote":"--format"'

scenario "a NUL-format stop stays human-readable"
printf 'changed\n' >"$REPO/a.txt"
run_nul origin main
want_rc 2
[ "${#NUL_FIELDS[@]}" -eq 0 ] && ok || bad "stop output contained NUL fields"
want_out 'STOP dirty'

# discriminating: read-only is what lets this run before the destructive step.
# All three landing shapes are exercised, because the create paths are the ones
# a mutating copy would fetch or branch on: checking only the create=false path
# leaves the claim asserted rather than tested. A stale index is set up first,
# so a plain `git status` (which rewrites it) shows up as a mutation too.
scenario "the plan mutates nothing, on any of the three landing shapes"
touch -t 200001010000 "$REPO/a.txt"
BEFORE=$(snapshot "$REPO")
run origin -x
want_rc 0
want_out '"create":false'
if [ "$BEFORE" = "$(snapshot "$REPO")" ]; then ok; else bad "the create=false plan changed something"; fi
G "$REPO" update-ref -d refs/heads/-x
touch -t 200001010000 "$REPO/a.txt"
BEFORE=$(snapshot "$REPO")
run origin -x
want_rc 0
want_out '"create":true'
if [ "$BEFORE" = "$(snapshot "$REPO")" ]; then ok; else bad "the switch-create plan changed something"; fi
touch -t 200001010000 "$REPO/a.txt"
BEFORE=$(snapshot "$REPO")
run origin feat
want_rc 0
want_out '"create":true'
if [ "$BEFORE" = "$(snapshot "$REPO")" ]; then ok; else bad "the checkout-create plan changed something"; fi

# --- r1: a hyphen-leading base is a plan, not a stop -------------------------

# discriminating: kills the shipped-then-reversed rule that made the name a
# stop on the premise that the switch is unspellable.
scenario "a hyphen-leading base with a local branch plans a switch"
run origin -x
want_rc 0
want_out '"verb":"switch"'
want_out '"create":false'
want_no_out 'STOP'

# discriminating (weakly): the verb assertion kills the copy that stops on an
# option-shaped name. Its point is the other half, that the name shape decides
# the verb and nothing else, leaving an existing complete pair alone.
scenario "a hyphen-leading base with a complete pair keeps its tracking"
track "$REPO" -x origin
run origin -x
want_rc 0
want_out '"verb":"switch"'
want_out '"tracking":"ok"'

# --- r2: the switch probe, and only where the name needs it ------------------

scenario "a git without switch stops a hyphen-leading base"
run_switchless origin -x
want_rc 2
want_out 'STOP switch-missing'

# discriminating: an unconditional probe stops here too, and would refuse
# every ordinary cleanup on a git older than 2.23.
scenario "a git without switch still plans an ordinary base"
track "$REPO" main origin
run_switchless origin main
want_rc 0
want_out '"verb":"checkout"'

# discriminating: with the probe moved below the dirty guard, this reports
# STOP dirty, and the caller cleans a tree that was never the blocker. An
# environment the tree cannot fix is reported first.
scenario "a missing switch outranks a dirty tree"
printf 'changed\n' > "$REPO/a.txt"
run_switchless origin -x
want_rc 2
want_out 'STOP switch-missing'

# discriminating: where switch is not yet a builtin, `git switch -h` expands an
# `alias.switch`, and git runs a `!`-prefixed alias as a shell command with the
# -h appended. A probe that invokes switch therefore executes it, inside a
# preflight whose whole claim is that it touches nothing, and reading the
# output afterwards cannot undo the write. Listing builtins expands no alias.
scenario "the switch probe never executes an alias standing in for it"
make_shim
cat > "$SHIM/git" <<EOF
#!/bin/sh
if [ "\$1" = "--list-cmds=builtins" ]; then
  $REALGIT "\$@" | grep -vx switch
  exit 0
fi
if [ "\$1" = switch ]; then
  : > "$SCEN/alias-ran"
  exit 0
fi
exec $REALGIT "\$@"
EOF
chmod +x "$SHIM/git"
run_switchless origin -x
want_rc 2
want_out 'STOP switch-missing'
if [ -e "$SCEN/alias-ran" ]; then bad "the probe executed the alias"; else ok; fi

# --- r2: the create path fetches enough to make the start-point exist --------

# discriminating: an option-shaped branch also stays in FETCH_HEAD so the
# executable caller can create its local ref with an absence lease.
scenario "a hyphen-leading base also fetches only to FETCH_HEAD"
G "$REPO" update-ref -d refs/heads/-x
run origin -x
want_rc 0
want_out '"create":true'
want_out '"refs/heads/-x"'
want_no_out '"refs/heads/-x:refs/heads/-x"'
want_no_out '"refs/heads/-x:refs/remotes/origin/-x"'

# discriminating: the ordinary path leaves the source in FETCH_HEAD so checkout
# creates the local branch without touching a tracking namespace pre-landing.
scenario "an ordinary base with no local branch fetches only to FETCH_HEAD"
run origin feat
want_rc 0
want_out '"create":true'
want_out '"refs/heads/feat"'
want_no_out '"refs/heads/feat:refs/heads/feat"'
want_no_out '"refs/heads/feat:refs/remotes/origin/feat"'

# The oracle is what the create LEAVES BEHIND, not its exit status, because on a
# folding filesystem the packed-ref case exits 0 and is the more dangerous of
# the two: the new loose file case-folds over the packed entry, so the existing
# branch starts resolving to the new tip while for-each-ref still reports the
# old one. An exit-status oracle calls that success and blesses a hijack, which
# is how an earlier version of this very case did exactly that. Both storage
# shapes run because each catches a different wrong guard.
#
# discriminating: against a guard gated on core.ignoreCase (stops on a
# case-sensitive volume with a stale flag, and on a folding volume misses
# nothing, so it fails the sensitive cell), against one probing only
# `show-ref --verify` (misses the packed hijack), and against no stop at all.
for storage in loose packed; do
  scenario "the case-collision verdict matches what the create leaves, $storage refs"
  OID_A=$(git -C "$REPO" rev-parse HEAD)
  printf 'second\n' > "$REPO/second.txt"
  G "$REPO" add .
  G "$REPO" commit -m second
  OID_B=$(git -C "$REPO" rev-parse HEAD)
  G "$REPO" update-ref refs/heads/release "$OID_A"
  G "$REPO" checkout main
  [ "$storage" = packed ] && G "$REPO" pack-refs --all
  run origin Release
  case "$RC" in
    0 | 2) ok ;;
    *) bad "neither planned nor stopped (exit $RC: $OUT)" ;;
  esac
  # attempt the landing the plan would have prescribed, then ask whether the
  # pre-existing branch survived it intact
  if G "$REPO" checkout --no-overwrite-ignore -b Release "$OID_B"; then made=yes; else made=no; fi
  still=$(git -C "$REPO" rev-parse refs/heads/release 2>/dev/null)
  if [ "$made" = yes ] && [ "$still" = "$OID_A" ]; then safe=yes; else safe=no; fi
  if [ "$RC" -eq 2 ] && [ "$safe" = no ]; then ok
  elif [ "$RC" -eq 0 ] && [ "$safe" = yes ]; then ok
  elif [ "$RC" -eq 2 ]; then bad "stopped where the create is safe (made=$made, release=$still)"
  else bad "planned a create that is unsafe (made=$made, release=$still, wanted $OID_A)"
  fi
done

# The remote-tracking destination needs the same packed-ref case fallback as a
# branch create. A loose alias is visible through the destination path itself;
# once packed, only the enumerated name remains. On a case-sensitive filesystem
# both spellings coexist safely, so the oracle compares the plan with what the
# mandatory fetch leaves rather than assuming this host folds names.
for storage in loose packed; do
  scenario "the tracking case-alias verdict matches the fetch, $storage refs"
  OLD=$(git -C "$REPO" rev-parse HEAD)
  for r in $(git -C "$REPO" for-each-ref --format='%(refname)' refs/remotes/); do
    G "$REPO" update-ref -d "$r"
  done
  G "$REPO" update-ref refs/remotes/Origin/main "$OLD"
  [ "$storage" = packed ] && G "$REPO" pack-refs --all
  printf 'second\n' > "$REPO/second.txt"
  G "$REPO" add .
  G "$REPO" commit -m second
  NEW=$(git -C "$REPO" rev-parse HEAD)
  G "$REPO" push origin HEAD:refs/heads/case-alias-fixture
  G "$ORIGIN" update-ref refs/heads/main "$NEW"
  G "$ORIGIN" update-ref -d refs/heads/case-alias-fixture
  G "$REPO" update-ref -d refs/remotes/origin/case-alias-fixture
  G "$REPO" reset --hard "$OLD"
  run origin main
  case "$RC" in
    0 | 2) ok ;;
    *) bad "neither planned nor stopped (exit $RC: $OUT)" ;;
  esac
  if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/main'
  then fetched=yes; else fetched=no; fi
  still=$(git -C "$REPO" rev-parse refs/remotes/Origin/main 2>/dev/null)
  if [ "$fetched" = yes ] && [ "$still" = "$OLD" ]; then safe=yes; else safe=no; fi
  if [ "$RC" -eq 2 ] && [ "$safe" = no ]; then ok
  elif [ "$RC" -eq 0 ] && [ "$safe" = yes ]; then ok
  elif [ "$RC" -eq 2 ]; then bad "stopped where the fetch is safe"
  else
    bad "planned a fetch that aliased Origin/main (plan rc $RC: $OUT; got $still, wanted $OLD; new $NEW)"
  fi
done

# The same oracle for an alias the filesystem makes by Unicode rules rather than
# by case: APFS resolves refs/heads/café onto an existing CAFÉ, which an ASCII
# fold cannot see, so the guard stats the ref path instead of folding the name
# itself. Loose refs only, deliberately: the packed form of this collision is a
# known gap, because there is no file to stat and the fallback fold is ASCII.
#
# discriminating: against a guard that only folds names, which plans a create
# that then fails at rc 128.
scenario "a Unicode ref alias is judged by what the create leaves"
OID_A=$(git -C "$REPO" rev-parse HEAD)
printf 'second\n' > "$REPO/second.txt"
G "$REPO" add .
G "$REPO" commit -m second
OID_B=$(git -C "$REPO" rev-parse HEAD)
UPPER=$(printf 'CAF\xc3\x89')
LOWER=$(printf 'caf\xc3\xa9')
G "$REPO" update-ref "refs/heads/$UPPER" "$OID_A"
G "$REPO" checkout main
run origin "$LOWER"
case "$RC" in
  0 | 2) ok ;;
  *) bad "neither planned nor stopped (exit $RC: $OUT)" ;;
esac
if G "$REPO" checkout --no-overwrite-ignore -b "$LOWER" "$OID_B"; then made=yes; else made=no; fi
still=$(git -C "$REPO" rev-parse "refs/heads/$UPPER" 2>/dev/null)
if [ "$made" = yes ] && [ "$still" = "$OID_A" ]; then safe=yes; else safe=no; fi
if [ "$RC" -eq 2 ] && [ "$safe" = no ]; then ok
elif [ "$RC" -eq 0 ] && [ "$safe" = yes ]; then ok
elif [ "$RC" -eq 2 ]; then bad "stopped where the create is safe (made=$made)"
else bad "planned a create that is unsafe (made=$made, $UPPER=$still, wanted $OID_A)"
fi

# discriminating: whitespace is legal in a Unix path, so a remote URL of three
# spaces naming a directory that holds a repository is one git fetches through.
# A copy that trims before testing emptiness refuses that cleanup. Only a truly
# empty value is missing.
scenario "a whitespace-only remote URL is a URL, an empty one is not"
G "$REPO" config remote.origin.url "   "
run origin main
want_rc 0
want_out 'OK landing'
G "$REPO" config remote.origin.url ""
run origin main
want_rc 4
want_out 'LOOKUP_FAILED remote'

# A ref name cannot also be a directory of refs, so the create fails in both
# directions and in both storages: release blocking release/next, release/next
# blocking release, loose or packed. Only one of the four was reported; the
# other three came from sweeping the shape, and the two packed ones are the
# reason this is a name comparison rather than more stats, since a packed parent
# leaves no directory behind. Same oracle as the collision cases: the verdict
# has to match what the create actually does.
#
# discriminating: against a copy without the df_conflict guard, three of the
# four fail. The fourth, a loose release/next blocking release, still passes
# there because the ref-path stat above catches it as a directory; it is kept
# because the packed form of that same shape is not caught that way.
for shape in "release|release/next" "release/next|release"; do
  existing="${shape%%|*}"
  want="${shape##*|}"
  for storage in loose packed; do
    scenario "a $storage ref $existing blocks creating $want"
    OID=$(git -C "$REPO" rev-parse HEAD)
    G "$REPO" update-ref "refs/heads/$existing" "$OID"
    [ "$storage" = packed ] && G "$REPO" pack-refs --all
    run origin "$want"
    case "$RC" in
      0 | 2) ok ;;
      *) bad "neither planned nor stopped (exit $RC: $OUT)" ;;
    esac
    if G "$REPO" checkout --no-overwrite-ignore -b "$want" main; then made=yes; else made=no; fi
    if [ "$RC" -eq 2 ] && [ "$made" = no ]; then ok
    elif [ "$RC" -eq 0 ] && [ "$made" = yes ]; then ok
    elif [ "$RC" -eq 2 ]; then bad "stopped where the create succeeds"
    else bad "planned a create the ref store refuses"
    fi
  done
done

# An ancestor can sit at or above the namespace boundary, where a scan rooted in
# the destination's own namespace cannot see it. Both verified: refs/remotes/
# origin existing as a ref blocks the fetch's refs/remotes/origin/<base>, and
# refs/heads existing as a ref blocks refs/heads/<base>. Reported for the remote
# side only; the heads side came from checking whether the same shape existed
# one level up, which it does.
#
# discriminating: against a copy enumerating each destination's own namespace
# rather than refs/, which is what the first version of this guard did.
scenario "an ancestor above the namespace boundary still blocks the landing"
OID=$(git -C "$REPO" rev-parse HEAD)
G "$REPO" for-each-ref --format='%(refname)' refs/remotes/
for r in $(git -C "$REPO" for-each-ref --format='%(refname)' refs/remotes/); do
  G "$REPO" update-ref -d "$r"
done
G "$REPO" update-ref refs/remotes/origin "$OID"
run origin brandnew
want_rc 2
want_out 'STOP ref-conflict'
# and the fetch the plan would otherwise have prescribed really does fail
if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/brandnew'; then
  bad "the fetch succeeded, so the stop is wrong"
else ok; fi

# `git for-each-ref` omits a ref it cannot resolve while still exiting 0, so an
# enumeration cannot see a dangling symbolic ref sitting on an ancestor path,
# even though the file is there and the ref store refuses to create beneath it.
# The ancestor paths are therefore stated directly.
#
# discriminating: against a copy relying on the enumeration alone.
scenario "a dangling symbolic ref on an ancestor path still blocks the landing"
G "$REPO" symbolic-ref refs/heads/release refs/heads/does-not-exist
run origin release/next
want_rc 2
want_out 'STOP ref-conflict'
# and the create it would otherwise have prescribed really does fail
if G "$REPO" checkout --no-overwrite-ignore -b release/next main; then
  bad "the create succeeded, so the stop is wrong"
else ok; fi

# Refs beneath the destination block it as an ancestor does, and a dangling one
# is again invisible to the enumeration, so the destination path is tested for
# being a directory. On the remote-tracking side because that is where the plan
# creates a ref the caller never names.
#
# discriminating: against a copy testing ancestors only.
scenario "a dangling descendant of the fetch destination blocks the landing"
G "$REPO" update-ref -d refs/remotes/origin/release
G "$REPO" symbolic-ref refs/remotes/origin/release/next refs/heads/gone
run origin release
want_rc 2
want_out 'STOP ref-conflict'
if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/release'; then
  bad "the fetch succeeded, so the stop is wrong"
else ok; fi

# Branches and remote-tracking refs live in the common git directory, while a
# linked worktree's own git dir holds only its per-worktree refs, so a stat
# rooted at the private one sees none of them. This is not a corner: the skill's
# relocate rule runs step 1 inside a linked worktree when the base branch is
# checked out there.
#
# discriminating: against a copy using --absolute-git-dir.
scenario "the ref stats read the common git directory, not the worktree's"
G "$REPO" symbolic-ref refs/heads/release refs/heads/gone
G "$REPO" branch wtbranch
git -C "$REPO" worktree add -q "$SCEN/linked" wtbranch 2>/dev/null
run_in "$SCEN/linked" origin release/next
want_rc 2
want_out 'STOP ref-conflict'
if G "$SCEN/linked" checkout --no-overwrite-ignore -b release/next main; then
  bad "the create succeeded, so the stop is wrong"
else ok; fi
git -C "$REPO" worktree remove --force "$SCEN/linked" 2>/dev/null

# Step 2 fetches into refs/remotes/<remote>/<base> on every cleanup, not only
# when the local branch had to be created, so the remote-tracking conflict check
# is not gated on create. With a local base already present nothing is created,
# and the plan would otherwise pass a fetch that fails during resync.
#
# discriminating: against a copy with that check inside the create branch.
scenario "the tracking destination is checked even when nothing is created"
G "$REPO" checkout main
for r in $(git -C "$REPO" for-each-ref --format='%(refname)' refs/remotes/); do
  G "$REPO" update-ref -d "$r"
done
G "$REPO" update-ref refs/remotes/origin "$(git -C "$REPO" rev-parse HEAD)"
run origin main
want_rc 2
want_out 'STOP ref-conflict'
if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/main'; then
  bad "the fetch succeeded, so the stop is wrong"
else ok; fi

# A directory at the destination is not by itself a collision: git replaces an
# empty one, and a tree of empty ones with it. What blocks the create is any
# entry that is not a directory, which is git's own "non-empty directory
# blocking reference", so a dangling symlink counts as much as a loose ref and
# either may be invisible to the enumeration. Verdict asserted against the
# fetch, over all four states.
#
# discriminating: against a copy stopping on directory existence alone (which
# refuses two landings git performs) and against one scanning for regular files
# only (which misses the symlink).
for shape in "empty|no" "nested|no" "occupied|yes" "symlink|yes"; do
  kind="${shape%%|*}"
  blocks="${shape##*|}"
  scenario "a $kind directory at the fetch destination"
  G "$REPO" update-ref -d refs/remotes/origin/main
  rm -rf "$REPO/.git/refs/remotes/origin/main"
  case "$kind" in
    empty) mkdir -p "$REPO/.git/refs/remotes/origin/main" ;;
    nested) mkdir -p "$REPO/.git/refs/remotes/origin/main/deeper" ;;
    occupied) mkdir -p "$REPO/.git/refs/remotes/origin/main"
      printf 'ref: refs/heads/gone\n' > "$REPO/.git/refs/remotes/origin/main/next" ;;
    symlink) mkdir -p "$REPO/.git/refs/remotes/origin/main"
      ln -s /nowhere/at/all "$REPO/.git/refs/remotes/origin/main/next" ;;
  esac
  run origin main
  if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/main'; then fetched=yes; else fetched=no; fi
  if [ "$blocks" = yes ]; then
    want_rc 2
    if [ "$fetched" = no ]; then ok; else bad "the fetch succeeded, so the stop is wrong"; fi
  else
    want_rc 0
    if [ "$fetched" = yes ]; then ok; else bad "the fetch failed, so planning was wrong"; fi
  fi
done

# An exact symlink is judged by the ref update Git actually performs, not by
# whether its target merely exists. A symlink to an enumerated direct ref is
# replaced without changing its target file; a symlink to a directory remains
# a blocking non-empty directory. The origin is advanced so the fetch must
# update the destination rather than accepting an already-current ref.
for shape in "file|no" "directory|yes"; do
  kind="${shape%%|*}"
  blocks="${shape##*|}"
  scenario "an exact $kind symlink at the fetch destination"
  OLD=$(git -C "$REPO" rev-parse HEAD)
  printf 'second\n' > "$REPO/second.txt"
  G "$REPO" add .
  G "$REPO" commit -m second
  NEW=$(git -C "$REPO" rev-parse HEAD)
  G "$REPO" push origin main
  G "$REPO" reset --hard "$OLD"
  G "$REPO" update-ref -d refs/remotes/origin/main
  mkdir -p "$REPO/.git/refs/remotes/origin"
  case "$kind" in
    file)
      printf '%s\n' "$OLD" > "$SCEN/target-ref"
      ln -s "$SCEN/target-ref" "$REPO/.git/refs/remotes/origin/main"
      ;;
    directory)
      mkdir -p "$SCEN/target-dir"
      ln -s "$SCEN/target-dir" "$REPO/.git/refs/remotes/origin/main"
      ;;
  esac
  run origin main
  if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/main'
  then fetched=yes; else fetched=no; fi
  if [ "$blocks" = yes ]; then
    want_rc 2
    if [ "$fetched" = no ]; then ok
    else bad "the fetch succeeded, so the stop is wrong"; fi
  else
    want_rc 0
    if [ "$fetched" = yes ] \
      && [ ! -L "$REPO/.git/refs/remotes/origin/main" ] \
      && [ "$(cat "$SCEN/target-ref")" = "$OLD" ] \
      && [ "$(git -C "$REPO" rev-parse refs/remotes/origin/main)" = "$NEW" ]
    then ok; else bad "the fetch did not safely replace the symlink"; fi
  fi
done

# The branch destination follows the same empty-tree rule as the tracking
# destination. The old exact-path stat stopped both empty shapes. At the other
# edge, a broken symbolic ref makes checkout exit 0 while attaching HEAD to its
# missing target, whereas a dangling filesystem symlink is safely replaced;
# the oracle therefore checks the resulting HEAD, not only the exit status.
for shape in "empty|no" "nested|no" "broken|yes" "symlink|no"; do
  kind="${shape%%|*}"
  blocks="${shape##*|}"
  scenario "a $kind entry at the branch destination"
  G "$REPO" update-ref -d refs/heads/release
  rm -rf "$REPO/.git/refs/heads/release"
  case "$kind" in
    empty) mkdir -p "$REPO/.git/refs/heads/release" ;;
    nested) mkdir -p "$REPO/.git/refs/heads/release/deeper" ;;
    broken) printf 'ref: refs/heads/gone\n' > "$REPO/.git/refs/heads/release" ;;
    symlink) ln -s /nowhere/at/all "$REPO/.git/refs/heads/release" ;;
  esac
  run origin release
  if G "$REPO" checkout --no-overwrite-ignore -b release main \
    && [ "$(git -C "$REPO" symbolic-ref -q HEAD 2>/dev/null)" = refs/heads/release ]
  then safe=yes; else safe=no; fi
  if [ "$blocks" = yes ]; then
    want_rc 2
    if [ "$safe" = no ]; then ok; else bad "the create was safe, so the stop is wrong"; fi
  else
    want_rc 0
    if [ "$safe" = yes ]; then ok; else bad "the create was unsafe, so planning was wrong"; fi
  fi
done

# A special node at the exact loose-ref path must be classified before any Git
# command tries to read it as a ref. `git symbolic-ref` opens a FIFO, including
# one reached through a symlink, and waits for a writer. The breaker attempts a
# write after one second and creates the marker only after that write connects
# to a reader; elapsed time alone is not a failure. Both destinations run
# because the tracking ref is unconditional and an existing branch-shaped
# entry takes a different control-flow path.
for destination in tracking branch; do
  for shape in direct symlink; do
    scenario "a $shape FIFO at the $destination destination does not hang"
    case "$destination" in
      tracking)
        G "$REPO" update-ref -d refs/remotes/origin/main
        path="$REPO/.git/refs/remotes/origin/main"
        ;;
      branch)
        G "$REPO" update-ref -d refs/heads/release
        path="$REPO/.git/refs/heads/release"
        ;;
    esac
    rm -rf "$path"
    mkdir -p "$(dirname "$path")"
    case "$shape" in
      direct)
        mkfifo "$path"
        fifo="$path"
        ;;
      symlink)
        fifo="$SCEN/target-fifo"
        mkfifo "$fifo"
        ln -s "$fifo" "$path"
        ;;
    esac
    if [ "$destination" = tracking ]; then
      if run_with_fifo_breaker "$fifo" "$SCEN/fifo-opened" origin main
      then prompt=yes; else prompt=no; fi
    else
      if run_with_fifo_breaker "$fifo" "$SCEN/fifo-opened" origin release
      then prompt=yes; else prompt=no; fi
    fi
    want_rc 2
    want_out 'STOP ref-conflict'
    if [ "$prompt" = yes ]; then ok
    else bad "the planner opened the FIFO before classifying its path"; fi
  done
done

# The enumerations span every ref namespace, so target-only classification is
# still too late for a special entry elsewhere. This FIFO sits under tags,
# outside both destinations, and must stop before for-each-ref can open it. A
# shim makes the planner take more than the breaker's one-second delay before
# reaching the scan, proving the marker means a connected writer, not a timer.
scenario "an unrelated FIFO cannot hang a slow broad ref enumeration"
fifo="$REPO/.git/refs/tags/unrelated-fifo"
mkdir -p "$(dirname "$fifo")"
mkfifo "$fifo"
SHIM="$SCEN/shim"
mkdir -p "$SHIM"
cat > "$SHIM/git" <<EOF
#!/bin/sh
if [ "\$1" = remote ] && [ "\$2" = get-url ]; then sleep 2; fi
exec $REALGIT "\$@"
EOF
chmod +x "$SHIM/git"
if PATH="$SHIM:$PATH" \
  run_with_fifo_breaker "$fifo" "$SCEN/fifo-opened" origin main
then prompt=yes; else prompt=no; fi
want_rc 2
want_out 'STOP ref-conflict'
if [ "$prompt" = yes ]; then ok
else bad "the broad ref enumeration opened an unrelated FIFO"; fi

# Git ignores a loose entry whose path is not a valid ref name, without opening
# it. Such a special node is therefore not reachable by broad enumeration and
# cannot justify stopping cleanup. Both filesystem shapes run because the
# whole-tree scan classifies direct special nodes and symlink targets separately.
for shape in direct symlink; do
  scenario "an invalid-ref $shape FIFO does not block cleanup"
  path="$REPO/.git/refs/tags/bad..name"
  mkdir -p "$(dirname "$path")"
  case "$shape" in
    direct)
      mkfifo "$path"
      fifo="$path"
      ;;
    symlink)
      fifo="$SCEN/target-fifo"
      mkfifo "$fifo"
      ln -s "$fifo" "$path"
      ;;
  esac
  if run_with_fifo_breaker "$fifo" "$SCEN/fifo-opened" origin main
  then prompt=yes; else prompt=no; fi
  want_rc 0
  want_out 'OK landing'
  if [ "$prompt" = yes ]; then ok
  else bad "the planner opened the FIFO at an invalid ref path"; fi
  if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/main'
  then ok; else bad "the safe tracking fetch failed"; fi
done

# A symlink on an ancestor is not only a lock conflict when dangling. Where it
# resolves to a directory, git follows it and writes the ref outside the common
# git directory. The plan refuses both shapes rather than blessing that escape.
scenario "a symlinked ref ancestor cannot redirect the fetch outside git"
G "$REPO" update-ref -d refs/remotes/origin/main
mkdir -p "$SCEN/outside"
rm -rf "$REPO/.git/refs/remotes/origin"
ln -s "$SCEN/outside" "$REPO/.git/refs/remotes/origin"
run origin main
want_rc 2
want_out 'STOP ref-conflict'
if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/main' \
  && [ -f "$SCEN/outside/main" ]
then ok; else bad "the symlink did not reproduce the outside ref write"; fi

scenario "a dangling symlink ancestor blocks a branch create"
ln -s /nowhere/at/all "$REPO/.git/refs/heads/release"
run origin release/next
want_rc 2
want_out 'STOP ref-conflict'
if G "$REPO" checkout --no-overwrite-ignore -b release/next main
then bad "the create succeeded, so the stop is wrong"; else ok; fi

# A failed descendant scan is unknown, not empty. A PATH shim makes the failure
# deterministic even under root, where chmod 000 would still be readable.
scenario "a failed descendant scan is a lookup failure"
G "$REPO" update-ref -d refs/remotes/origin/main
mkdir -p "$REPO/.git/refs/remotes/origin/main"
SHIM="$SCEN/shim"
mkdir -p "$SHIM"
cat > "$SHIM/find" <<EOF
#!/bin/sh
exit 1
EOF
chmod +x "$SHIM/find"
OUT=$(cd "$REPO" && PATH="$SHIM:$PATH" "$SUT" origin main 2>&1)
RC=$?
want_rc 4
want_out 'LOOKUP_FAILED refs'

# Extension keys do not select a backend unless this repository activates
# extensions through format version 1, and repository extensions are local:
# neither an inactive local value nor an inherited global value changes Git's
# files backend. Git 2.43 exposed the inactive local key while continuing to
# use files; newer Git rejects that malformed combination before the planner
# runs, so the shim reproduces the older config reads this guard must handle.
#
# discriminating: the pre-fix unscoped extension lookup consumes the shimmed
# inactive value and reports STOP ref-storage.
scenario "a ref-storage extension under format zero is inactive"
SHIM="$SCEN/shim"
mkdir -p "$SHIM"
cat > "$SHIM/git" <<EOF
#!/bin/sh
if [ "\$1" = config ] && [ "\$2" = --local ] \
  && [ "\$3" = --get ] && [ "\$4" = core.repositoryFormatVersion ]; then
  echo 0
  exit 0
fi
if [ "\$1" = config ] && [ "\$2" = --local ] \
  && [ "\$3" = --get ] && [ "\$4" = extensions.refStorage ]; then
  echo reftable
  exit 0
fi
if [ "\$1" = config ] && [ "\$2" = --get ] \
  && [ "\$3" = extensions.refStorage ]; then
  echo reftable
  exit 0
fi
exec $REALGIT "\$@"
EOF
chmod +x "$SHIM/git"
OUT=$(cd "$REPO" && PATH="$SHIM:$PATH" "$SUT" origin main 2>&1)
RC=$?
want_rc 0
want_out 'OK landing'

scenario "a global ref-storage extension is not a repository extension"
G "$REPO" config --local core.repositoryFormatVersion 1
GLOBAL_CONFIG="$SCEN/global-config"
git config --file "$GLOBAL_CONFIG" extensions.refStorage reftable
OUT=$(cd "$REPO" && GIT_CONFIG_GLOBAL="$GLOBAL_CONFIG" "$SUT" origin main 2>&1)
RC=$?
want_rc 0
want_out 'OK landing'

# Repository format is an integer-valued key, so Git accepts alternate integer
# spellings and normalizes them when asked for the typed value. Dispatching on
# the raw string rejects repositories Git itself accepts.
for shape in "01|1" "+1|1" "0x0|0"; do
  spelling="${shape%%|*}"
  normalized="${shape##*|}"
  scenario "repository format $spelling normalizes to $normalized"
  G "$REPO" config --local core.repositoryFormatVersion "$spelling"
  run origin main
  want_rc 0
  want_out 'OK landing'
done

# Reftable stores a marker at .git/refs/heads, not a loose ref, and has no
# read-only way to enumerate dangling symbolic refs. Preparing a transaction
# writes a lock that can survive interruption, so this read-only plan names the
# unsupported backend explicitly rather than reporting a false conflict.
if scenario_reftable "reftable is an explicit read-only stop"; then
  OID=$(git -C "$REPO" rev-parse HEAD)
  G "$ORIGIN" update-ref refs/heads/release "$OID"
  BEFORE=$(snapshot "$REPO")
  run origin release
  want_rc 2
  want_out 'STOP ref-storage'
  if [ "$BEFORE" = "$(snapshot "$REPO")" ]; then ok
  else bad "the reftable stop changed the repository"; fi
  G "$REPO" fetch -- origin 'refs/heads/release:refs/remotes/origin/release'
  if G "$REPO" checkout --no-overwrite-ignore -b release refs/remotes/origin/release
  then ok; else bad "the ordinary reftable create did not reproduce"; fi
else
  echo "skip: reftable ref conflicts (git init lacks --ref-format=reftable)"
fi

# A resolvable symbolic ref is more dangerous than a dangling one because the
# commands return success. Checkout attaches HEAD to the symbolic target, and a
# fetch into a symbolic tracking destination advances its target. Both exact
# destinations stop before either redirection can happen.
scenario "a symbolic branch ref cannot redirect checkout"
G "$REPO" branch victim
G "$REPO" symbolic-ref refs/heads/release refs/heads/victim
run origin release
want_rc 2
want_out 'STOP ref-conflict'
if G "$REPO" checkout --no-overwrite-ignore release \
  && [ "$(git -C "$REPO" symbolic-ref -q HEAD 2>/dev/null)" = refs/heads/victim ]
then ok; else bad "the symbolic branch did not reproduce the redirected checkout"; fi

scenario "a symbolic tracking ref cannot redirect fetch"
G "$REPO" branch victim
VICTIM_BEFORE=$(git -C "$REPO" rev-parse refs/heads/victim)
printf 'second\n' > "$REPO/second.txt"
G "$REPO" add .
G "$REPO" commit -m second
G "$REPO" push origin main
G "$REPO" update-ref -d refs/remotes/origin/main
G "$REPO" symbolic-ref refs/remotes/origin/main refs/heads/victim
run origin main
want_rc 2
want_out 'STOP ref-conflict'
if G "$REPO" fetch -- origin 'refs/heads/main:refs/remotes/origin/main' \
  && [ "$(git -C "$REPO" rev-parse refs/heads/victim)" != "$VICTIM_BEFORE" ]
then ok; else bad "the symbolic tracking ref did not reproduce the redirected fetch"; fi

# does not discriminate: the control for the four above, so a guard that stops
# on any slash in the name would be caught rather than looking correct.
scenario "an unrelated branch does not block a slashed name"
OID=$(git -C "$REPO" rev-parse HEAD)
G "$REPO" update-ref refs/heads/unrelated "$OID"
run origin release/next
want_rc 0
want_out 'OK landing'

# --- r4: tracking is judged by consequence, in every clone shape -------------

# A single-branch clone's fetch refspec covers only main, so `checkout -b` and
# `--set-upstream-to` both leave a fetched-into-place branch untracked, and a
# later plain `git pull` there fast-forwards onto main's tip at exit 0.
# discriminating only incidentally, through its base name: a copy that stops on
# an option-shaped name, or one whose probe invokes `git switch -h`, fails here
# because the base is `-x`. Its own point is the clone shape the tracking rule
# exists for. The create=false assertion is load-bearing, because
# a silently failed fetch in the setup leaves the branch absent, where
# `tracking: write` would also hold and the case would pass while testing the
# opposite of its name.
scenario "a branch outside the clone's fetch refspec needs its pair written"
git clone -q --single-branch --branch main "$ORIGIN" "$SCEN/sb"
G "$SCEN/sb" fetch origin 'refs/heads/-x:refs/heads/-x'
run_in "$SCEN/sb" origin -x
want_rc 0
want_out '"create":false'
want_out '"tracking":"write"'

# does not discriminate: pins that a complete pair is the user's configuration,
# not a gap to overwrite, even when it names another remote or branch.
scenario "a complete pair naming something else is left alone"
G "$REPO" remote add other "$ORIGIN"
G "$REPO" config branch.main.remote other
G "$REPO" config branch.main.merge refs/heads/somewhere-else
run origin main
want_rc 0
want_out '"tracking":"ok"'

# --- r5: half a tracking pair behaves exactly like none ----------------------

# discriminating: a copy reading only branch.<name>.remote passes this, and the
# branch it passes still fast-forwards onto the wrong tip at exit 0.
scenario "a pair missing only merge needs writing"
G "$REPO" config branch.main.remote origin
run origin main
want_rc 0
want_out '"tracking":"write"'

# discriminating: the mirror image, which a copy reading only .merge passes.
scenario "a pair missing only remote needs writing"
G "$REPO" config branch.main.merge refs/heads/main
run origin main
want_rc 0
want_out '"tracking":"write"'

# discriminating: `git config --get-all` exits 0 on a key set to the empty
# string, so an existence-only test that trusts the exit code passes a pair
# that git cannot use.
scenario "a key set to the empty string counts as missing"
G "$REPO" config branch.main.remote ""
G "$REPO" config branch.main.merge refs/heads/main
run origin main
want_rc 0
want_out '"tracking":"write"'

# does not discriminate against the listed copies: pins the config key form,
# where a dot in the branch name lands inside the subsection.
scenario "a dotted branch name reads its own config keys"
OID=$(git -C "$REPO" rev-parse HEAD)
G "$REPO" update-ref refs/heads/v1.2 "$OID"
track "$REPO" v1.2 origin
run origin v1.2
want_rc 0
want_out '"tracking":"ok"'

# --- the guards the landing keeps -------------------------------------------

scenario "a modified tracked file stops the landing"
printf 'changed\n' > "$REPO/a.txt"
track "$REPO" main origin
run origin main
want_rc 2
want_out 'STOP dirty'

# discriminating: status.showUntrackedFiles=no empties the plain porcelain
# form, switching the guard off from inside the repository it protects.
scenario "an untracked file stops it even with showUntrackedFiles=no"
G "$REPO" config status.showUntrackedFiles no
printf 'u\n' > "$REPO/u.txt"
track "$REPO" main origin
run origin main
want_rc 2
want_out 'STOP dirty'

# discriminating: a copy passing --ignored stops on an ordinary ignored file,
# refusing a landing git would abort by itself. --no-overwrite-ignore on the
# landing command is what covers this, so the plan deliberately ignores it.
scenario "an ignored file alone is not a stop"
printf 'secret\n' > "$REPO/.env"
track "$REPO" main origin
run origin main
want_rc 0
want_out 'OK landing'

# does not discriminate: pins the field the caller's post-landing HEAD check
# reads, for the shape where a bare checkout would detach at the tag.
scenario "a same-named tag with no local branch is reported"
G "$REPO" update-ref refs/tags/feat HEAD
run origin feat
want_rc 0
want_out '"tag_shadow":true'
want_out '"create":true'

scenario "a same-named tag with a local branch is still reported"
G "$REPO" update-ref refs/tags/main HEAD
track "$REPO" main origin
run origin main
want_rc 0
want_out '"tag_shadow":true'
want_out '"create":false'

# --- the remote, read only where the plan would use it -----------------------

scenario "an unresolvable remote fails a create"
run origin2 feat
want_rc 4
want_out 'LOOKUP_FAILED remote'

scenario "an unresolvable remote fails a tracking write"
run origin2 main
want_rc 4
want_out 'LOOKUP_FAILED remote'

# discriminating: a remote check scoped to what the landing itself touches
# passes this, and step 2 then fetches from the same unresolvable name.
scenario "an unresolvable remote fails even where the landing would not use it"
track "$REPO" main origin
run origin2 main
want_rc 4
want_out 'LOOKUP_FAILED remote'

# discriminating: `git remote get-url` succeeds here and echoes the remote's
# own name, because git falls back to treating that name as a URL, so a check
# reading its output (empty or not) passes a remote that step 2's fetch then
# dies on. The configured value is what has to be read.
scenario "a remote configured with an empty URL is not a usable remote"
track "$REPO" main origin
G "$REPO" config remote.origin.url ""
run origin main
want_rc 4
want_out 'LOOKUP_FAILED remote'

# Does not discriminate within the planner: it pins the reason the caller must
# resolve the base role and run the plan again after checkout. The same remote
# name is usable under feature and has no URL under main because Git evaluates
# onbranch includes against the branch currently checked out.
scenario "an onbranch remote result is scoped to the checked-out branch"
G "$REPO" branch feature
G "$REPO" checkout feature
INC="$SCEN/feature-remote.cfg"
G "$REPO" config --unset-all remote.origin.url
G "$REPO" config --add includeIf.onbranch:feature.path "$INC"
git config --file "$INC" remote.origin.url "$ORIGIN"
run origin main
want_rc 0
want_out 'OK landing'
G "$REPO" checkout main
run origin main
want_rc 4
want_out 'LOOKUP_FAILED remote'

# discriminating: a remote is a bare positional, so without the terminator an
# option-shaped remote reads as an unknown switch and a remote that exists is
# reported missing. This is the one instance of the hazard the script is built
# around that its own reads could still trip on.
scenario "an option-shaped remote is read past the option parser"
G "$REPO" remote add -- -r "$ORIGIN"
run -r feat
want_rc 0
want_out '"create":true'
want_no_out 'LOOKUP_FAILED'

# `git config` can name a remote that `git remote add` rejects. It still
# resolves through `remote get-url`, but its derived tracking ref is invalid and
# the mandatory resync fetch rejects the refspec, so validate that destination
# before returning a plan.
scenario "a configured remote must form a valid tracking ref"
G "$REPO" config 'remote.bad..remote.url' "$ORIGIN"
run bad..remote main
want_rc 64
want_out 'do not form a valid remote-tracking ref'
if G "$REPO" fetch -- bad..remote 'refs/heads/main:refs/remotes/bad..remote/main'
then bad "the invalid tracking refspec unexpectedly fetched"; else ok; fi

# --- arguments and environment ----------------------------------------------

scenario "no arguments and each help spelling print the contract"
run
want_rc 0
want_out 'base-landing-plan.sh <base-remote> <base-branch>'
run --help
want_rc 0
want_out 'Exit codes'
run -h
want_rc 0
want_out 'Exit codes'

# discriminating: a help check that scans every argument for the flag swallows
# a branch literally named -h, which is exactly the shape this script exists
# for. Only the first argument is ever a help request.
scenario "-h in the branch position is a branch name"
OID=$(git -C "$REPO" rev-parse HEAD)
G "$REPO" update-ref refs/heads/-h "$OID"
run origin -h
want_rc 0
want_out '"base":"-h"'
want_out '"verb":"switch"'
want_out '"create":false'

# discriminating: with the help check ungated by the argument count, an empty
# remote reaches ${1:---help}, where the default expands for an empty value as
# well as an unset one, and the script prints help and exits 0 on a call that
# named no remote at all.
scenario "a wrong argument count is a usage error"
run origin
want_rc 64
run origin main extra
want_rc 64
run origin ""
want_rc 64
run "" main
want_rc 64
# discriminating against the colon form, `${1:---help}`, which substitutes its
# default for an empty value as well as an unset one, so a lone "" printed the
# contract and exited 0 on a call that named no remote. Note it is the colon
# specifically: removing the `[ $# -le 1 ]` gate while keeping `${1---help}`
# changes nothing here, since "" still matches neither spelling. The exit code
# is the whole assertion, because help and this usage error print the same text
# and only the code separates them.
run ""
want_rc 64

scenario "a name git cannot use as a ref is a usage error"
run origin 'bad..name'
want_rc 64
want_out 'not a valid branch name'

# does not discriminate: a double quote is legal in a ref name, so the JSON
# tail has to escape it or the caller cannot parse the line it is handed.
scenario "a quote in the branch name is escaped"
OID=$(git -C "$REPO" rev-parse HEAD)
G "$REPO" update-ref 'refs/heads/a"b' "$OID"
run origin 'a"b'
want_rc 0
want_out '"base":"a\"b"'
want_out '"create":false'

# discriminating: byte-wise \u escaping emits one escape per UTF-8 byte, and
# those decode to mojibake, so the caller fetches a refspec naming a branch
# that does not exist. JSON
# is UTF-8, so the bytes belong in the line verbatim.
scenario "a non-ASCII branch name survives the JSON tail"
OID=$(git -C "$REPO" rev-parse HEAD)
G "$REPO" update-ref 'refs/heads/café' "$OID"
run origin 'café'
want_rc 0
want_out '"base":"café"'
want_out '"create":false'
want_no_out '\u00'
# The whole point of the escaping is a line a parser accepts, so one case
# actually parses it rather than pattern-matching the bytes.
if command -v python3 > /dev/null 2>&1; then
  if printf '%s' "${OUT#OK landing }" \
    | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["base"] == "café" else 1)'
  then ok; else bad "the plan line did not parse back to the branch name"; fi
else
  echo "skip: $NAME (no python3 to parse with)"
fi

# A ref name may hold raw bytes above 0x7f that are not UTF-8, and no JSON
# string can carry one: escaping it to \u00XX would round-trip to a different
# name, so the plan would name a branch that does not exist. Refused up front
# instead, before step 1 mutates anything.
scenario "a base name that is not valid UTF-8 is refused"
run origin "$(printf 'bad\xffname')"
want_rc 64
want_out 'not valid UTF-8'
run "$(printf 'bad\xffremote')" main
want_rc 64
want_out 'not valid UTF-8'

scenario "a missing git and a missing work tree are environment errors"
mkdir -p "$SCEN/empty"
OUT=$(cd "$REPO" && PATH="$SCEN/empty" "$REALBASH" "$SUT" origin main 2>&1)
RC=$?
want_rc 69
want_out 'git is not on PATH'
run_in "$TMP" origin main
want_rc 69
want_out 'not inside a git work tree'

# The third exit-69 branch, and the reason the trap chmods before removing.
scenario "a non-bash shell and an unreadable index are reported, not guessed"
if command -v zsh > /dev/null 2>&1; then
  OUT=$(cd "$REPO" && zsh "$SUT" origin main 2>&1)
  RC=$?
  want_rc 69
  want_out 'needs bash'
else
  echo "skip: $NAME (no zsh on this machine)"
fi
# Through a shim rather than by making the index unreadable: `chmod 000` is a
# no-op for root, so in a root CI container or devcontainer the read would
# succeed and this case would fail there and only there. What the case is for
# is the contract, that a failed status read is reported rather than passed
# off as a clean tree, and the shim asserts that wherever it runs.
make_shim
cat > "$SHIM/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  [ "\$a" = status ] || continue
  echo "fatal: could not read the index" >&2
  exit 128
done
exec $REALGIT "\$@"
EOF
chmod +x "$SHIM/git"
OUT=$(cd "$REPO" && PATH="$SHIM:$PATH" "$SUT" origin main 2>&1)
RC=$?
want_rc 4
want_out 'LOOKUP_FAILED status'

# --- names git reads as revision shorthand ----------------------------------

# discriminating: each of these is a valid branch name that no landing command
# attaches HEAD to, because git resolves the shorthand before refs/heads. Two
# are silent (exit 0 on the wrong branch), so without the refusal the caller's
# own HEAD check is the last line of defence against resyncing the wrong branch.
# The update-ref below is scene-setting, not a precondition: the refusal is on
# the name and fires before any ref is read, so the case would pass in a
# repository holding none of these branches. It is here because the refusal is
# only interesting for names that could really exist.
scenario "a base named -, @, or HEAD is refused before anything is deleted"
OID=$(git -C "$REPO" rev-parse HEAD)
for n in - @ HEAD; do
  G "$REPO" update-ref "refs/heads/$n" "$OID"
  run origin "$n"
  want_rc 2
  want_out 'STOP unspellable'
done

# discriminating only incidentally: `--`, `-h`, and `--all` are option-shaped,
# so a copy that stops on that shape fails here. Its own point is that the
# refusal above is three literals and not a pattern.
scenario "the other awkward spellings still plan normally"
OID=$(git -C "$REPO" rev-parse HEAD)
for n in -- -h --all a/b HEAD-ish; do
  G "$REPO" update-ref "refs/heads/$n" "$OID"
  run origin "$n"
  want_rc 0
  want_out 'OK landing'
done

# --- repository configuration must not execute, and must not mislead --------

# discriminating, against a copy that drops the global C locale and takes
# utf8_valid's byte count on its own `local LC_ALL=C` declaration line, where
# the assignment does not yet apply: the count is then characters, so a name of
# valid multibyte text followed by an invalid byte is measured short and its
# tail never validated, and the plan emits the raw byte into a refspec. The two
# reverts are needed together, because the global locale alone makes the
# declaration-line count harmless; that redundancy is deliberate, so each
# function stays correct in isolation. Needs a real UTF-8 locale to see any of
# it, which is why one is resolved above rather than named.
scenario "a multibyte name with a trailing invalid byte is still refused"
if [ -n "$UTF8_LOCALE" ]; then
  OUT=$(cd "$REPO" && LC_ALL="$UTF8_LOCALE" "$SUT" origin "$(printf 'caf\xc3\xa9\xff')" 2>&1)
  RC=$?
  want_rc 64
  want_out 'not valid UTF-8'
  # An ordinary name under the same locale, to show the locale itself breaks
  # nothing. Deliberately no assertion that grep never reports "illegal byte
  # sequence": the UTF-8 validation above refuses an invalid name before the ref
  # match can ever see one, so such an assertion would be unreachable rather
  # than passing, and the degraded copy is caught by the refusal assertion.
  OUT=$(cd "$REPO" && LC_ALL="$UTF8_LOCALE" "$SUT" origin main 2>&1)
  RC=$?
  want_rc 0
else
  echo "skip: $NAME (no UTF-8 locale installed; this case cannot discriminate)"
fi

# discriminating: git runs a configured fsmonitor as a hook during status, even
# under --no-optional-locks, so without the override the inspected repository's
# own configuration executes code inside a preflight that runs before anything
# is deleted.
scenario "a configured fsmonitor hook is not executed by the status read"
track "$REPO" main origin
cat > "$SCEN/fsmon" <<EOF
#!/bin/sh
: > "$SCEN/fsmon-ran"
exit 1
EOF
chmod +x "$SCEN/fsmon"
G "$REPO" config core.fsmonitor "$SCEN/fsmon"
run origin main
want_rc 0
if [ -e "$SCEN/fsmon-ran" ]; then bad "the status read executed the fsmonitor hook"; else ok; fi

# discriminating: git's effective value for a single-valued key is the last one
# set, so a key set to origin and then to empty is empty to git while the
# --get-all aggregate still looks populated. The plan would report a complete
# upstream over configuration `git pull` cannot use.
scenario "a tracking key whose effective value is empty needs writing"
G "$REPO" config --add branch.main.remote origin
G "$REPO" config --add branch.main.remote ""
G "$REPO" config branch.main.merge refs/heads/main
run origin main
want_rc 0
want_out '"tracking":"write"'

# --- a failed read is not an established absence ----------------------------

# discriminating on a case-sensitive filesystem only, and says so: piping the
# enumeration into grep reports grep's status, so a failure arrives as "no
# match" and is read as absence. Where the filesystem folds, the case-collision
# guard runs its own separate enumeration, hits the same shim, and reports
# LOOKUP_FAILED by that other path, so the assertions pass without the pipeline
# being the reason. The case still pins the intended behaviour everywhere.
scenario "a failed ref enumeration is reported, not read as absence"
track "$REPO" main origin
make_shim
cat > "$SHIM/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  [ "\$a" = for-each-ref ] || continue
  echo "fatal: could not read refs" >&2
  exit 128
done
exec $REALGIT "\$@"
EOF
chmod +x "$SHIM/git"
OUT=$(cd "$REPO" && PATH="$SHIM:$PATH" "$SUT" origin main 2>&1)
RC=$?
want_rc 4
want_out 'LOOKUP_FAILED refs'
want_no_out '"create":true'

# discriminating: git answers "not set" with exit 1 and a real failure with
# another code, so a check that treats every non-zero as "not set" turns an
# unreadable config into a tracking write.
scenario "a config read that fails is reported, not read as unset"
track "$REPO" main origin
make_shim
cat > "$SHIM/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  [ "\$a" = config ] || continue
  echo "fatal: bad config line" >&2
  exit 128
done
exec $REALGIT "\$@"
EOF
chmod +x "$SHIM/git"
OUT=$(cd "$REPO" && PATH="$SHIM:$PATH" "$SUT" origin main 2>&1)
RC=$?
want_rc 4
want_out 'LOOKUP_FAILED config'

echo "merge-cleanup landing matrix: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
