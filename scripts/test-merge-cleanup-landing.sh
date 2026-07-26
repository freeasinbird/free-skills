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
# against them: no switch verb, one fetch refspec, one tracking key, a plain
# --porcelain status, an --ignored status, an unconditional switch probe, a
# probe moved after the dirty guard, a probe that invokes `git switch -h`, a
# remote check scoped to the landing, a
# remote read without its `--`, a config check reading only an exit code, a
# help check using the colon form of the default, a help flag scanned across
# every argument, byte-wise `\u` escaping of UTF-8, no UTF-8 validation of the
# arguments, `show-ref --verify` as the existence probe, a stray `git fetch`, a
# stray write to FETCH_HEAD, no refusal of the revision-shorthand names, no
# case-collision stop, a collision guard keyed on core.ignoreCase rather than on
# what the ref store does, one that only folds names and so misses a Unicode
# alias, one that trims a remote URL before testing it, a
# character-counting locale with the byte count on a `local` declaration line,
# no fsmonitor override, a tracking key read as an aggregate rather than as its
# effective value, a
# remote checked by existence alone, a ref
# enumeration left in a pipeline, and a config read treating every failure as
# "not set". Where a case does not discriminate against any of those, the
# comment says so rather than implying coverage it lacks.
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

# discriminating: a one-refspec copy omits the local ref, and `switch -c` will
# not create the name, so the landing would have nothing to attach to.
scenario "a hyphen-leading base with no local branch fetches into both refs"
G "$REPO" update-ref -d refs/heads/-x
run origin -x
want_rc 0
want_out '"create":true'
want_out '"refs/heads/-x:refs/heads/-x"'
want_out '"refs/heads/-x:refs/remotes/origin/-x"'

# discriminating: a copy that always emits both refspecs writes a local branch
# on the ordinary path, where `checkout -b` is what should create it.
scenario "an ordinary base with no local branch fetches only the tracking ref"
run origin feat
want_rc 0
want_out '"create":true'
want_out '"refs/heads/feat:refs/remotes/origin/feat"'
want_no_out '"refs/heads/feat:refs/heads/feat"'

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
# passes this, and step 3 then fetches from the same unresolvable name after
# step 1 has already deleted the remote branch.
scenario "an unresolvable remote fails even where the landing would not use it"
track "$REPO" main origin
run origin2 main
want_rc 4
want_out 'LOOKUP_FAILED remote'

# discriminating: `git remote get-url` succeeds here and echoes the remote's
# own name, because git falls back to treating that name as a URL, so a check
# reading its output (empty or not) passes a remote that step 3's fetch then
# dies on. The configured value is what has to be read.
scenario "a remote configured with an empty URL is not a usable remote"
track "$REPO" main origin
G "$REPO" config remote.origin.url ""
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
# that does not exist, after step 1 has already deleted the remote one. JSON
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
# instead, before step 1 deletes anything.
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
# own HEAD check catches them only after step 1 deleted the remote branch.
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
