#!/usr/bin/env bash
# Regression matrix for scripts/link-skills.sh. Offline and deterministic:
# each case copies the script into a scratch clone with two skills (alpha
# and beta) and runs it with a throwaway HOME, so it never touches the real
# checkout or the real skill directories.
#
# The cases pin the clone guard (a target that resolves into the clone,
# through any symlink spelling, is refused in every mode before any target
# changes) and the behavior it must not break: linking, adopting, and
# pruning in targets outside the clone, including a target symlinked to a
# dotfiles directory.
#
# Set LINK_SKILLS_SCRIPT to test a different copy of the script.
set -u

SCRIPT="${LINK_SKILLS_SCRIPT:-$(cd "$(dirname "$0")" && pwd)/link-skills.sh}"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*" >&2; }

# On macOS mktemp paths run through /var -> /private/var, so the clone's
# logical and physical paths differ; the guard must compare physical ones.
C="$TMP/clone"
H="$TMP/home"
TARGETS=(.claude/skills .agents/skills .gemini/config/skills)

# fresh: a new scratch clone and an empty HOME.
fresh() {
  rm -rf "$C" "$H" "$TMP/out" "$TMP/dotfiles" "$TMP/hop" "$TMP/homelink" \
    "$TMP/clone-other"
  mkdir -p "$C/scripts" "$C/skills/alpha" "$C/skills/beta" "$H"
  cp "$SCRIPT" "$C/scripts/link-skills.sh"
  echo alpha > "$C/skills/alpha/SKILL.md"
  echo beta > "$C/skills/beta/SKILL.md"
}

# run_ls [args...]: run the clone's script with HOME=$H; sets rc and leaves
# stdout and stderr in $TMP/out and $TMP/err.
run_ls() {
  HOME="$H" bash "$C/scripts/link-skills.sh" "$@" > "$TMP/out" 2> "$TMP/err"
  rc=$?
}

# snap: every path under the clone and HOME, with each symlink's text, so a
# before/after diff shows any change at all.
snap() {
  (
    cd "$TMP" || exit 1
    find clone home | sort | while IFS= read -r p; do
      if [ -L "$p" ]; then printf '%s -> %s\n' "$p" "$(readlink "$p")"
      else printf '%s\n' "$p"; fi
    done
  )
}

# expect_refused NAME TARGET [args...]: the run exits 1, names TARGET as
# refused, and changes nothing under the clone or HOME.
expect_refused() {
  local name=$1 target=$2 before
  shift 2
  before=$(snap)
  run_ls "$@"
  [ "$rc" -eq 1 ] || bad "$name: exit $rc, want 1"
  grep -qF "refusing target $target" "$TMP/err" \
    || bad "$name: stderr doesn't refuse $target: $(cat "$TMP/err")"
  [ "$(snap)" = "$before" ] || bad "$name: something changed"
  [ -f "$C/skills/alpha/SKILL.md" ] && [ -f "$C/skills/beta/SKILL.md" ] \
    || bad "$name: a clone skill file is gone"
  ok
}

# expect_linked NAME DIR: DIR holds alpha and beta links into the clone.
expect_linked() {
  local name=$1 dir=$2 s
  for s in alpha beta; do
    [ -L "$dir/$s" ] && [ "$(readlink "$dir/$s")" = "$C/skills/$s" ] \
      || bad "$name: $dir/$s isn't a link to the clone's $s"
  done
  ok
}

# 1. Each target symlinked to the clone's skills: --adopt, plain, and
#    --dry-run all refuse it and leave the skills in place.
for t in "${TARGETS[@]}"; do
  for mode in --adopt "" --dry-run; do
    fresh
    mkdir -p "$(dirname "$H/$t")"
    ln -s "$C/skills" "$H/$t"
    expect_refused "skills-link $t ${mode:-plain}" "$H/$t" $mode
  done
done

# 2. A target symlinked to the clone root: nothing is created in the clone.
for mode in "" --adopt; do
  fresh
  mkdir -p "$H/.agents"
  ln -s "$C" "$H/.agents/skills"
  expect_refused "root-link ${mode:-plain}" "$H/.agents/skills" $mode
done

# 3. A symlinked parent, ~/.gemini -> clone/x, with config/skills missing:
#    refused before mkdir -p can create clone/x/config. Covers x existing
#    and x missing (a dangling parent link).
for x_exists in 1 0; do
  fresh
  [ "$x_exists" -eq 0 ] || mkdir "$C/x"
  ln -s "$C/x" "$H/.gemini"
  expect_refused "parent-link x_exists=$x_exists" "$H/.gemini/config/skills" --adopt
  [ ! -e "$C/x/config" ] || bad "parent-link x_exists=$x_exists: created clone/x/config"
done

# 4. Other spellings of the same path into the clone.
fresh
mkdir -p "$H/.claude"
ln -s ../../clone/skills "$H/.claude/skills"
expect_refused "relative-link" "$H/.claude/skills" --adopt

fresh
mkdir -p "$H/.claude"
ln -s "$C/skills" "$TMP/hop"
ln -s "$TMP/hop" "$H/.claude/skills"
expect_refused "chained-link" "$H/.claude/skills" --adopt

fresh
mkdir -p "$H/.claude"
ln -s "$C/skills-new" "$H/.claude/skills"
expect_refused "dangling-link-into-clone" "$H/.claude/skills"
[ ! -e "$C/skills-new" ] || bad "dangling-link-into-clone: created clone/skills-new"

fresh
mkdir -p "$H/.claude"
ln -s "$H/.claude/skills" "$H/.claude/skills"
expect_refused "symlink-loop" "$H/.claude/skills"

# A HOME that is itself a symlink into the clone refuses every target.
fresh
mkdir -p "$C/home"
ln -s "$C/home" "$TMP/homelink"
before=$(snap)
HOME="$TMP/homelink" bash "$C/scripts/link-skills.sh" --adopt > "$TMP/out" 2> "$TMP/err"
rc=$?
[ "$rc" -eq 1 ] || bad "symlinked-home: exit $rc, want 1"
[ "$(grep -c '^refusing target' "$TMP/err")" -eq 3 ] \
  || bad "symlinked-home: want 3 refusals: $(cat "$TMP/err")"
[ "$(snap)" = "$before" ] || bad "symlinked-home: something changed"
ok

# A HOME spelled through link/.. reaches the link target's parent, as the
# kernel resolves it, not the textual parent. Here that is the clone, and a
# decoy at the textual spot must not fool the check.
fresh
rm -rf "$TMP/.claude"
ln -s "$C/skills" "$TMP/hop"
mkdir -p "$C/.claude/skills/alpha" "$TMP/.claude/skills"
before=$(snap)
HOME="$TMP/hop/.." bash "$C/scripts/link-skills.sh" --adopt > "$TMP/out" 2> "$TMP/err"
rc=$?
[ "$rc" -eq 1 ] || bad "dotdot-home: exit $rc, want 1"
[ "$(snap)" = "$before" ] || bad "dotdot-home: something changed"
[ -d "$C/.claude/skills/alpha" ] && [ ! -L "$C/.claude/skills/alpha" ] \
  || bad "dotdot-home: replaced a real directory inside the clone"
rm -rf "$TMP/.claude"
ok

# A later target that runs through a link dangling at the first check, and
# that an earlier target's new link then points into the clone, is refused
# when its turn comes, before anything is written there.
fresh
mkdir -p "$H/.claude/skills" "$H/.agents"
ln -s "$H/.claude/skills/alpha" "$H/.agents/skills"
run_ls
[ "$rc" -eq 1 ] || bad "redirected-target: exit $rc, want 1"
grep -qF "refusing target $H/.agents/skills" "$TMP/err" \
  || bad "redirected-target: .agents/skills not refused: $(cat "$TMP/err")"
[ "$(ls -A "$C/skills/alpha")" = SKILL.md ] \
  || bad "redirected-target: wrote inside clone/skills/alpha"
ok

# 5. One bad target among two good ones: refused, and the good targets get
#    no links either (check before change).
fresh
mkdir -p "$H/.agents"
ln -s "$C/skills" "$H/.agents/skills"
expect_refused "one-bad-two-good" "$H/.agents/skills" --adopt
[ ! -e "$H/.claude" ] && [ ! -e "$H/.gemini" ] \
  || bad "one-bad-two-good: a good target was created"

# 6. All three targets fresh: exit 0 and every target links each skill.
fresh
run_ls
[ "$rc" -eq 0 ] || bad "fresh: exit $rc: $(cat "$TMP/err")"
for t in "${TARGETS[@]}"; do expect_linked "fresh $t" "$H/$t"; done

# A dry run on a fresh HOME still resolves the missing targets and exits 0.
fresh
before=$(snap)
run_ls --dry-run
[ "$rc" -eq 0 ] || bad "fresh dry-run: exit $rc: $(cat "$TMP/err")"
[ "$(snap)" = "$before" ] || bad "fresh dry-run: something changed"
ok

# 7. A real alpha directory in a target outside the clone: a plain run
#    skips it, --adopt replaces it with a link.
fresh
mkdir -p "$H/.claude/skills/alpha"
echo old > "$H/.claude/skills/alpha/SKILL.md"
run_ls
[ "$rc" -eq 0 ] && [ -d "$H/.claude/skills/alpha" ] && [ ! -L "$H/.claude/skills/alpha" ] \
  || bad "real-dir plain: rc=$rc or alpha was replaced"
run_ls --adopt
[ "$rc" -eq 0 ] || bad "real-dir adopt: exit $rc: $(cat "$TMP/err")"
expect_linked "real-dir adopt" "$H/.claude/skills"

# 8. A target symlinked to a dotfiles directory outside the clone: links go
#    there, and --adopt replaces a real directory inside it.
fresh
mkdir -p "$TMP/dotfiles/skills/beta" "$H/.claude"
ln -s "$TMP/dotfiles/skills" "$H/.claude/skills"
run_ls --adopt
[ "$rc" -eq 0 ] || bad "dotfiles: exit $rc: $(cat "$TMP/err")"
expect_linked "dotfiles" "$TMP/dotfiles/skills"

# A sibling sharing the clone's name as a prefix isn't inside the clone.
fresh
mkdir -p "$TMP/clone-other/skills" "$H/.claude"
ln -s "$TMP/clone-other/skills" "$H/.claude/skills"
run_ls
[ "$rc" -eq 0 ] || bad "prefix-sibling: exit $rc: $(cat "$TMP/err")"
expect_linked "prefix-sibling" "$TMP/clone-other/skills"

# A clone checked out inside a target under a skill's name is never
# replaced by --adopt.
fresh
C2="$H/.claude/skills/alpha"
mkdir -p "$C2/scripts" "$C2/skills/alpha" "$C2/skills/beta"
cp "$SCRIPT" "$C2/scripts/link-skills.sh"
echo alpha > "$C2/skills/alpha/SKILL.md"
echo beta > "$C2/skills/beta/SKILL.md"
HOME="$H" bash "$C2/scripts/link-skills.sh" --adopt > "$TMP/out" 2> "$TMP/err"
rc=$?
[ "$rc" -eq 0 ] || bad "clone-in-target: exit $rc: $(cat "$TMP/err")"
[ -f "$C2/skills/alpha/SKILL.md" ] && [ ! -L "$C2" ] \
  || bad "clone-in-target: the clone was replaced"
grep -qF "skip (holds this clone" "$TMP/out" \
  || bad "clone-in-target: no skip message"
ok

# 9. Prune: a removed skill's links disappear, the rest stay.
fresh
run_ls
rm -rf "$C/skills/beta"
run_ls
[ "$rc" -eq 0 ] || bad "prune: exit $rc: $(cat "$TMP/err")"
for t in "${TARGETS[@]}"; do
  [ ! -e "$H/$t/beta" ] && [ ! -L "$H/$t/beta" ] || bad "prune: $t/beta remains"
  [ "$(readlink "$H/$t/alpha")" = "$C/skills/alpha" ] || bad "prune: $t/alpha lost"
done
ok

# 10. Case-insensitive filesystems (macOS default): a target linked through
#     a different-case spelling of the clone is still inside it, and so is
#     one when the script itself runs from a different-case spelling. Skipped
#     where the filesystem is case-sensitive.
fresh
if [ -d "$TMP/CLONE" ]; then
  mkdir -p "$H/.claude"
  ln -s "$TMP/CLONE/skills" "$H/.claude/skills"
  expect_refused "case-variant-target" "$H/.claude/skills" --adopt

  fresh
  mkdir -p "$H/.claude"
  ln -s "$C/skills" "$H/.claude/skills"
  before=$(snap)
  HOME="$H" bash "$TMP/CLONE/scripts/link-skills.sh" --adopt > "$TMP/out" 2> "$TMP/err"
  rc=$?
  [ "$rc" -eq 1 ] || bad "case-variant-script: exit $rc, want 1"
  [ "$(snap)" = "$before" ] || bad "case-variant-script: something changed"
  ok
else
  skip=$((skip + 2))
fi

# --help prints the guard sentence from the header.
fresh
run_ls --help
grep -q 'resolves into this clone' "$TMP/out" || bad "help: no guard sentence"
ok

echo "passed: $pass, failed: $fail, skipped: $skip"
[ "$fail" -eq 0 ]
