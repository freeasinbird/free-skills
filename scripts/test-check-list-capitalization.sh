#!/usr/bin/env bash
# Regression tests for scripts/check-list-capitalization.sh: list markers,
# fenced code, skipped item kinds, allowlist matching, file-set exclusions,
# caller-relative paths, output shape, and exit codes.
set -euo pipefail
cd "$(dirname "$0")/.."

checker=$PWD/scripts/check-list-capitalization.sh
allowlist=$PWD/scripts/list-capitalization-allow.txt

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

# --- clean prose and skipped item kinds (exit 0) ---
clean=$(fixture clean.md '# Title' '- Capitalized bullet' '1. Numbered item')
run_case 'clean file' 0 "$clean"
run_case 'code-span-led item' 0 "$(fixture s1.md '- `lower` stays exact')"
run_case 'link-led item' 0 "$(fixture s2.md '- [lower](target)')"
run_case 'task item' 0 "$(fixture s3.md '- [ ] lower task text')"
run_case 'digit-led item' 0 "$(fixture s4.md '- 3 lowercase words')"
run_case 'bold-led item' 0 "$(fixture s5.md '- **lowercase emphasis**')"
run_case 'backtick fence' 0 \
  "$(fixture f1.md '```yaml' '- lowercase code' '```')"
run_case 'tilde fence' 0 \
  "$(fixture f2.md '~~~text' '* lowercase code' '~~~')"
run_case 'long fence ignores shorter run' 0 \
  "$(fixture f3.md '````markdown' '```' '- lowercase code' '````')"
run_case 'list-item fence' 0 \
  "$(fixture f4.md '- ```text' '  - lowercase code' '  ```')"
run_case 'continued list fence' 0 \
  "$(fixture f5.md '- Capitalized item' '  ```text' \
    '  - lowercase code' '  ```')"
run_case 'wide continued list fence' 0 \
  "$(fixture f6.md '- Capitalized item' '    ```text' \
    '    - lowercase code' '    ```')"
run_case 'tab-indented list fence' 0 \
  "$(fixture f7.md $'-\t```text' $'\t- lowercase code' $'\t```')"
run_case 'blockquote list fence' 0 \
  "$(fixture f8.md '> - ```text' '>   - lowercase code' '>   ```')"
run_case 'blockquote tab list fence' 0 \
  "$(fixture f9.md $'>-\t```text' '>    - lowercase code' '>    ```')"
run_case 'standalone non-one ordered fence' 0 \
  "$(fixture f10.md '2. ```text' '   - lowercase code' '   ```')"
run_case 'several files, all clean' 0 "$clean" "$work/s1.md"

# --- lowercase items for every supported marker (exit 1) ---
run_case 'hyphen marker' 1 "$(fixture m1.md '- lowercase item')"
run_case 'asterisk marker' 1 "$(fixture m2.md '* lowercase item')"
run_case 'plus marker' 1 "$(fixture m3.md '+ lowercase item')"
run_case 'number-dot marker' 1 "$(fixture m4.md '1. lowercase item')"
run_case 'number-paren marker' 1 "$(fixture m5.md '1) lowercase item')"
run_case 'nested item' 1 "$(fixture m6.md '  - lowercase nested item')"
run_case 'blockquote hyphen marker' 1 \
  "$(fixture q1.md '> - lowercase quoted item')"
run_case 'blockquote asterisk marker' 1 \
  "$(fixture q2.md '> * lowercase quoted item')"
run_case 'blockquote plus marker' 1 \
  "$(fixture q3.md '> + lowercase quoted item')"
run_case 'blockquote number-dot marker' 1 \
  "$(fixture q4.md '> 1. lowercase quoted item')"
run_case 'blockquote number-paren marker' 1 \
  "$(fixture q5.md '> 1) lowercase quoted item')"
run_case 'nested blockquote item' 1 \
  "$(fixture q6.md '> > - lowercase nested quoted item')"
run_case 'blockquote fence' 0 \
  "$(fixture q7.md '> ```markdown' '> - lowercase code' '> ```')"
run_case 'item after fence closes' 1 \
  "$(fixture m7.md '```' '- lowercase code' '```' '- lowercase prose')"
run_case 'blockquote end closes fence' 1 \
  "$(fixture m8.md '> ```text' '> - lowercase code' '- lowercase prose')"
run_case 'list end closes fence' 1 \
  "$(fixture m9.md '- ```text' '  - lowercase code' '- lowercase prose')"
run_case 'four-space bare fence is code' 1 \
  "$(fixture m10.md '    ```text' '- lowercase prose')"
run_case 'backtick in opener info rejects fence' 1 \
  "$(fixture m11.md '```inline```' '- lowercase prose')"
run_case 'container-like fence closer stays inside' 1 \
  "$(fixture m12.md '```text' '- ```' '    ```' '```' '- lowercase prose')"
run_case 'nested list fence preserves inner indent' 1 \
  "$(fixture m13.md '- Outer' '    - ```text' \
    '      - lowercase code' '      ```' '    - lowercase prose')"
run_case 'clean plus dirty file' 1 "$clean" "$work/m1.md"
run_case 'missing file' 2 "$work/does-not-exist.md"

# --- output format: findings print as file:line ---
total=$((total + 1))
out=$("$checker" "$work/m1.md" 2>/dev/null || true)
if ! grep -q 'm1.md:1: lowercase list item' <<<"$out"; then
  echo 'FAIL: finding output is not file:line: kind'
  fails=$((fails + 1))
fi

# --- caller-relative paths belong to the caller's directory ---
relative=$work/relative
mkdir -p "$relative"
printf '%s\n' '- lowercase relative item' >"$relative/input.md"
actual=0
(cd "$relative" && "$checker" input.md) >/dev/null 2>&1 || actual=$?
total=$((total + 1))
if [ "$actual" -ne 1 ]; then
  echo "FAIL: caller-relative path (expected exit 1, got $actual)"
  fails=$((fails + 1))
fi

# --- planted repo: allowlist errors, exact matching, and no-args file set ---
# The checker cds to its own repo root, so exercise repository-relative state
# with a copy inside a synthetic git repository.
repo=$work/repo
mkdir -p "$repo/scripts" "$repo/devlog" "$repo/.claude/worktrees/x"
cp "$checker" "$repo/scripts/"
printf '%s\n' '# Clean' '- Capitalized item' >"$repo/README.md"
git -C "$repo" -c init.defaultBranch=main init -q
git -C "$repo" add -A

planted_case() { # planted_case <name> <expected-exit> [checker args...]
  local name=$1 expected=$2
  shift 2
  local actual=0
  (cd "$repo" && ./scripts/check-list-capitalization.sh "$@") \
    >/dev/null 2>&1 || actual=$?
  total=$((total + 1))
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL: $name (expected exit $expected, got $actual)"
    fails=$((fails + 1))
  fi
}

planted_case 'missing allowlist' 2 README.md
cp "$allowlist" "$repo/scripts/"
printf '%s\n' '- repository and PR number' >"$repo/allowed.md"
planted_case 'exact allowlist entry' 0 allowed.md
printf '%s\n' '- repository and PR number plus suffix' >"$repo/suffix.md"
planted_case 'allowlist rejects suffix' 1 suffix.md
printf '%s\n' '- repository and pr number' >"$repo/case.md"
planted_case 'allowlist is case-sensitive' 1 case.md
rm "$repo/allowed.md" "$repo/suffix.md" "$repo/case.md"

printf '%s\n' '- lowercase frozen item' \
  >"$repo/devlog/2020-01-01-0000-frozen.md"
printf '%s\n' '- lowercase worktree copy' \
  >"$repo/.claude/worktrees/x/copy.md"
printf '%s\n' '- lowercase ignored item' >"$repo/ignored.md"
printf '%s\n' 'ignored.md' >"$repo/.gitignore"
printf '%s\n' '- repository and PR number' >"$repo/allowlisted.md"
printf '%s\n' '- Capitalized untracked item' >"$repo/notes.md"
git -C "$repo" add -A
planted_case 'no-args exclusions and allowlist' 0
printf '%s\n' '- lowercase scanned item' >"$repo/bad.md"
planted_case 'no-args finding' 1

echo "list-capitalization matrix: passed $((total - fails)) / $total"
exit "$([ "$fails" -eq 0 ] && echo 0 || echo 1)"
