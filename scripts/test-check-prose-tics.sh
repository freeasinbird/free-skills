#!/usr/bin/env bash
# Regression tests for scripts/check-prose-tics.sh: an adversarial
# enumeration of the input space (dash kinds, neighbor context, opener
# case/apostrophe/position variants, file-set exclusions) per the
# enumerate-once-as-tests rule from AGENTS.md's fix-the-class bullet.
#
# Fixture prose lives in throwaway .md files under mktemp, and the
# opener/dash literals live only in shell/fixture text, so neither the
# check nor the repo's markdown checks ever scan them.
set -euo pipefail
cd "$(dirname "$0")/.."

checker=$PWD/scripts/check-prose-tics.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fails=0
total=0
run_case() { # run_case <name> <expected-exit> [checker args...]
  local name=$1 expected=$2
  shift 2
  local actual=0
  "$checker" "$@" >/dev/null 2>&1 || actual=$?
  total=$((total + 1))
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL: $name (expected exit $expected, got $actual)"
    fails=$((fails + 1))
  fi
}

fixture() { # fixture <name> <content...>: one line per argument
  local path=$work/$1
  shift
  printf '%s\n' "$@" >"$path"
  echo "$path"
}

# --- clean prose and allowed en-dash ranges (exit 0) ---
clean=$(fixture clean.md '# Title' 'Plain prose, with a comma and (parens).')
run_case 'clean file' 0 "$clean"
run_case 'bare numeric range' 0 "$(fixture r1.md 'Use 2–4 words.')"
run_case 'multi-digit range' 0 "$(fixture r2.md 'Observed on PRs 41–44 live.')"
run_case 'unit-bearing range' 0 "$(fixture r3.md 'Landed 2m54s–4m46s after push.')"
run_case 'decimal/suffix range' 0 "$(fixture r4.md 'Costs about 1.5–3x the base.')"
run_case 'several files, all clean' 0 "$clean" "$clean"

# --- em dashes (exit 1) ---
run_case 'em dash in prose' 1 "$(fixture e1.md 'A pause — then more.')"
run_case 'tight em dash' 1 "$(fixture e2.md 'A pause—then more.')"
# Intentional strictness: code spans and fences are not exempt, so an em
# dash can't hide in backticks.
run_case 'em dash in code span' 1 "$(fixture e3.md 'Run `a — b` to see.')"

# --- misused en dashes (exit 1) ---
run_case 'spaced en dash' 1 "$(fixture n1.md 'A pause – then more.')"
run_case 'tight non-numeric en dash' 1 "$(fixture n2.md 'word–word compound')"
run_case 'en dash at line start' 1 "$(fixture n3.md '–4 degrees outside')"
run_case 'en dash at line end' 1 "$(fixture n4.md 'trailing dash 4–')"
run_case 'range next to spaced en dash' 1 \
  "$(fixture n5.md 'Both 2–4 here – and a tic.')"

# --- stock AI openers (exit 1) ---
run_case 'absolutely-right opener' 1 \
  "$(fixture o1.md "You're absolutely right about that.")"
run_case 'curly-apostrophe variant' 1 \
  "$(fixture o2.md 'You’re absolutely right about that.')"
run_case 'shouty case variant' 1 \
  "$(fixture o3.md "YOU'RE ABSOLUTELY RIGHT.")"
run_case 'great-question opener' 1 "$(fixture o4.md 'Great question!')"
run_case 'great question mid-sentence' 1 \
  "$(fixture o5.md 'That is a great question to ask.')"
run_case 'perfect with bang' 1 "$(fixture o6.md 'Perfect! Moving on.')"
run_case 'perfect mid-sentence with bang' 1 \
  "$(fixture o7.md 'This is perfect! Ship it.')"
# Boundary: "perfect" without the exclamation mark is ordinary prose.
run_case 'perfect without bang stays clean' 0 \
  "$(fixture o8.md 'A perfect fit for the API.')"

# --- mixed inputs and errors ---
run_case 'clean plus dirty file' 1 "$clean" "$work/e1.md"
run_case 'missing file' 2 "$work/does-not-exist.md"

# --- output format: findings print as file:line ---
total=$((total + 1))
out=$("$checker" "$work/e1.md" 2>/dev/null || true)
if ! grep -q "e1.md:1: em dash" <<<"$out"; then
  echo 'FAIL: finding output is not file:line: kind'
  fails=$((fails + 1))
fi

# --- no-args file set: devlog/, .claude/, and gitignored files excluded ---
# The checker cds to its own repo root, so exercise no-args mode by
# planting a copy of the script inside a synthetic git repo.
repo=$work/repo
mkdir -p "$repo/scripts" "$repo/devlog" "$repo/.claude/worktrees/x"
cp "$checker" "$repo/scripts/"
printf 'Frozen entry keeps its em dash — by protocol.\n' \
  >"$repo/devlog/2020-01-01-0000-frozen.md"
printf 'Worktree copy — not project prose.\n' \
  >"$repo/.claude/worktrees/x/copy.md"
printf 'ignored — file\n' >"$repo/ignored.md"
printf 'ignored.md\n' >"$repo/.gitignore"
printf '# Clean\n\nTracked prose.\n' >"$repo/README.md"
printf 'Untracked but scanned prose, clean.\n' >"$repo/notes.md"
git -C "$repo" -c init.defaultBranch=main init -q
git -C "$repo" add -A
planted_check() { # run the planted copy no-args against the synthetic repo
  local expected=$1 actual=0
  "$repo/scripts/check-prose-tics.sh" >/dev/null 2>&1 || actual=$?
  total=$((total + 1))
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL: synthetic-repo no-args (expected exit $expected, got $actual)"
    fails=$((fails + 1))
  fi
}
planted_check 0
printf 'Fresh prose with a tic — flagged.\n' >"$repo/bad.md"
planted_check 1

echo "prose-tics matrix: passed $((total - fails)) / $total"
exit "$([ "$fails" -eq 0 ] && echo 0 || echo 1)"
