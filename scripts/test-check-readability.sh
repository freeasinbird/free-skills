#!/usr/bin/env bash
# Regression tests for scripts/check-readability.sh: exclusions, markdown
# unit boundaries, sentence boundaries, thresholds, caller-relative paths,
# and report-only exit behavior.
set -euo pipefail
cd "$(dirname "$0")/.."

checker=$PWD/scripts/check-readability.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fails=0
total=0
last_output=

run_case() { # run_case <name> <expected-exit> [checker args...]
  local name=$1 expected=$2 actual=0
  shift 2
  last_output=$work/output
  "$checker" "$@" >"$last_output" 2>&1 || actual=$?
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

expect_row() { # expect_row <name> <path> <words> <median> <max> <over> <para>
  local name=$1 path=$2 words=$3 median=$4 max=$5 over=$6 para=$7
  local expected="| $path | $words | $median | $max | $over | $para |"
  total=$((total + 1))
  if ! grep -Fqx "$expected" "$last_output"; then
    echo "FAIL: $name (missing row: $expected)"
    fails=$((fails + 1))
  fi
}

words() { # words <count>: print a numbered whitespace-token sequence
  local count=$1 index=1 result=
  while [ "$index" -le "$count" ]; do
    result="${result}${result:+ }w${index}"
    index=$((index + 1))
  done
  printf '%s' "$result"
}

# --- sentence splitting and basic metrics ---
basic=$(fixture basic.md 'One two. Three four five! Six?')
run_case 'basic sentence boundaries' 0 "$basic"
expect_row 'basic metrics' "$basic" 6 2 3 0 6

closers=$(fixture closers.md 'One two.** Three four.) Five six?"')
run_case 'sentence boundaries include Markdown closers' 0 "$closers"
expect_row 'Markdown closer metrics' "$closers" 6 2 2 0 6

abbreviation=$(fixture abbreviation.md 'Use e.g. simple words here.')
run_case 'simple abbreviation rule' 0 "$abbreviation"
# The specified punctuation rule treats the period after "e.g." as a
# sentence end. This known false split is deliberate until thresholds exist.
expect_row 'abbreviation follows simple rule' "$abbreviation" 5 2.5 3 0 5

# --- frontmatter, comments, and fenced code are excluded ---
frontmatter=$(fixture frontmatter.md \
  '---' 'title: Hidden metadata tokens' 'owner: Hidden Name' '---' \
  'Visible body only.')
run_case 'frontmatter skipped' 0 "$frontmatter"
expect_row 'frontmatter metrics' "$frontmatter" 3 3 3 0 3

comments=$(fixture comments.md \
  'Visible <!-- hidden inline words --> body.' \
  '<!-- hidden' 'multiline words -->' 'Final line.')
run_case 'HTML comments skipped' 0 "$comments"
expect_row 'comment metrics' "$comments" 4 2 2 0 2

inline_comment=$(fixture inline-comment.md \
  'Inline `<!--` and ``<!--`` markers stay. Visible words after them.')
run_case 'comment markers inside code spans stay' 0 "$inline_comment"
expect_row 'inline-code comment metrics' "$inline_comment" 10 5 6 0 10

unmatched_tick=$(fixture unmatched-tick.md \
  'Unmatched ` tick <!-- hidden words --> leaves visible prose.')
run_case 'unmatched code delimiter leaves comment active' 0 "$unmatched_tick"
expect_row 'unmatched-delimiter comment metrics' "$unmatched_tick" 6 6 6 0 6

escaped_tick=$(fixture escaped-tick.md \
  'Escaped \` tick <!-- hidden words --> leaves visible prose.')
run_case 'escaped code delimiter leaves comment active' 0 "$escaped_tick"
expect_row 'escaped-delimiter comment metrics' "$escaped_tick" 6 6 6 0 6

multiline_code=$(fixture multiline-code.md \
  'Before ``code' 'middle <!-- literal marker -->' 'end`` after.')
run_case 'multiline code span protects markdown markers' 0 "$multiline_code"
expect_row 'multiline code-span metrics' "$multiline_code" 9 9 9 0 9

span_fence_boundary=$(fixture span-fence-boundary.md \
  'Before ` unmatched' '```text' 'hidden ` close' '```' 'Visible after.')
run_case 'multiline code span stops before fence' 0 "$span_fence_boundary"
expect_row 'span fence-boundary metrics' "$span_fence_boundary" 5 2.5 3 0 3

span_list_boundary=$(fixture span-list-boundary.md \
  '- Before ` code' '- Visible <!-- hidden ` close --> after.')
run_case 'multiline code span stops before list item' 0 "$span_list_boundary"
expect_row 'span list-boundary metrics' "$span_list_boundary" 5 2.5 3 0 3

escaped_comment=$(fixture escaped-comment.md \
  'Visible \<!-- literal comment --> after.')
run_case 'escaped comment opener stays visible' 0 "$escaped_comment"
expect_row 'escaped comment metrics' "$escaped_comment" 6 6 6 0 6

fenced_comment=$(fixture fenced-comment.md \
  '```text' '<!-- fenced marker stays unclosed' '```' 'Visible after fence.')
run_case 'comment markers inside fences stay isolated' 0 "$fenced_comment"
expect_row 'fenced comment metrics' "$fenced_comment" 3 3 3 0 3

commented_fence=$(fixture commented-fence.md \
  '<!-- hidden fence starts' '```' '-->' 'Visible after comment.')
run_case 'fence markers inside comments stay isolated' 0 "$commented_fence"
expect_row 'commented fence metrics' "$commented_fence" 3 3 3 0 3

unclosed_comment=$(fixture unclosed-comment.md \
  'Visible before. <!-- hidden words' 'still hidden')
run_case 'unclosed HTML comment skipped' 0 "$unclosed_comment"
expect_row 'unclosed comment metrics' "$unclosed_comment" 2 2 2 0 2

fences=$(fixture fences.md \
  'Visible prose stays.' \
  '```text' 'hidden backtick words do not count' '~~~ not this closer' '```' \
  '- Visible list prose.' \
  '  ~~~' '  hidden tilde words do not count' '  ~~~')
run_case 'fences skipped by opener character' 0 "$fences"
expect_row 'fence metrics' "$fences" 6 3 3 0 3

fence_lengths=$(fixture fence-lengths.md \
  'Visible before.' \
  '````text' 'hidden before short fence' '```' 'hidden after short fence' '`````' \
  'Visible after.')
run_case 'fence closer must cover opener length' 0 "$fence_lengths"
expect_row 'mixed fence-length metrics' "$fence_lengths" 4 2 2 0 2

backtick_info=$(fixture backtick-info.md \
  '```inline```' 'Visible after inline span.')
run_case 'backtick fence info rejects backticks' 0 "$backtick_info"
expect_row 'standalone backtick-span metrics' "$backtick_info" 5 5 5 0 5

indented_fence=$(fixture indented-fence.md \
  '    ```text' 'Visible prose remains.')
run_case 'four-space line is not a fence opener' 0 "$indented_fence"
expect_row 'indented fence-like metrics' "$indented_fence" 4 4 4 0 4

blockquote_fence=$(fixture blockquote-fence.md \
  '> ```text' '> hidden fenced words' '> ```' 'Visible prose after.')
run_case 'blockquote fence is excluded' 0 "$blockquote_fence"
expect_row 'blockquote fence metrics' "$blockquote_fence" 3 3 3 0 3

unclosed_quote_fence=$(fixture unclosed-quote-fence.md \
  '> ```text' '> hidden fenced words' 'Visible outside quote.')
run_case 'blockquote end closes unclosed fence' 0 "$unclosed_quote_fence"
expect_row 'unclosed blockquote-fence metrics' "$unclosed_quote_fence" 3 3 3 0 3

list_fence=$(fixture list-fence.md \
  '- ```text' '  hidden fenced words' '  ```' 'Visible prose after.')
run_case 'list-item fence is excluded' 0 "$list_fence"
expect_row 'list-item fence metrics' "$list_fence" 3 3 3 0 3

unclosed_list_fence=$(fixture unclosed-list-fence.md \
  '- ```text' '  hidden fenced words' 'Visible outside list.')
run_case 'list end closes unclosed fence' 0 "$unclosed_list_fence"
expect_row 'unclosed list-fence metrics' "$unclosed_list_fence" 3 3 3 0 3

continued_list_fence=$(fixture continued-list-fence.md \
  '- item' '  ```text' '  hidden fenced words' 'Visible outside list.')
run_case 'continuation fence inherits list container' 0 "$continued_list_fence"
expect_row 'continued list-fence metrics' "$continued_list_fence" 4 2 3 0 3

wide_list_fence=$(fixture wide-list-fence.md \
  '- item' '    ```text' '    hidden fenced words' 'Visible outside list.')
run_case 'wide continuation fence consumes list indentation' 0 "$wide_list_fence"
expect_row 'wide list-fence metrics' "$wide_list_fence" 4 2 3 0 3

tab_list_fence=$(fixture tab-list-fence.md \
  $'-\t```text' $'\thidden fenced words' $'\t```' 'Visible outside list.')
run_case 'tab-indented list fence stays contained' 0 "$tab_list_fence"
expect_row 'tab list-fence metrics' "$tab_list_fence" 3 3 3 0 3

invalid_closers=$(fixture invalid-closers.md \
  '```text' 'hidden before invalid closers' '- ```' '    ```' \
  'hidden after invalid closers' '```' 'Visible after.')
run_case 'container-like lines do not close bare fence' 0 "$invalid_closers"
expect_row 'invalid fence-closer metrics' "$invalid_closers" 2 2 2 0 2

# --- markdown structures stay in separate units ---
bullet_25="$(words 25)."
bullets=$(fixture bullets.md "- $bullet_25" "- $bullet_25")
run_case 'adjacent bullets split' 0 "$bullets"
expect_row 'bullet unit lengths' "$bullets" 50 25 25 0 25

wrapped=$(fixture wrapped.md 'One two three' 'four five six.')
run_case 'wrapped paragraph joins' 0 "$wrapped"
expect_row 'wrapped paragraph metrics' "$wrapped" 6 6 6 0 6

structures=$(fixture structures.md \
  '# Two word heading ##' 'Setext heading' '---' \
  '| alpha beta | gamma |' '| --- | --- |')
run_case 'headings and table rows split' 0 "$structures"
expect_row 'structural markers removed' "$structures" 8 3 3 0 3

literal_pipe=$(fixture literal-pipe.md \
  'Use A | B syntax' 'inside one ordinary paragraph.')
run_case 'literal pipe is not a table' 0 "$literal_pipe"
expect_row 'literal pipe stays in its block' "$literal_pipe" 9 9 9 0 9

table_code=$(fixture table-code.md \
  '| Value |' '| --- |' '| `alpha|beta` |' '| alpha\|beta |')
run_case 'table separators respect code and escapes' 0 "$table_code"
expect_row 'table code-span metrics' "$table_code" 3 1 1 0 1

quoted_structures=$(fixture quoted-structures.md \
  '> # Quoted heading' '> - alpha beta.' '> - gamma delta epsilon.' \
  '>' '> | Header |' '> | --- |' '> | value |')
run_case 'blockquote containers expose inner structures' 0 "$quoted_structures"
expect_row 'quoted structure metrics' "$quoted_structures" 9 2 3 0 3

# --- the over-40 metric is strict and never gates the report ---
forty="$(words 40)."
forty_one="$(words 41)."
threshold=$(fixture threshold.md "$forty" '' "$forty_one")
run_case 'long prose still exits zero' 0 "$threshold"
expect_row 'over-40 boundary' "$threshold" 81 40.5 41 1 41

# --- explicit paths resolve against the caller's directory ---
relative_dir=$work/relative
mkdir -p "$relative_dir"
printf 'Caller relative words.\n' >"$relative_dir/input.md"
actual=0
(cd "$relative_dir" && "$checker" input.md) >"$work/relative-output" 2>&1 || actual=$?
last_output=$work/relative-output
total=$((total + 1))
if [ "$actual" -ne 0 ]; then
  echo "FAIL: caller-relative path (expected exit 0, got $actual)"
  fails=$((fails + 1))
fi
expect_row 'caller-relative metrics' "$relative_dir/input.md" 3 3 3 0 3

# --- missing explicit paths are environment errors ---
run_case 'missing file' 2 "$work/does-not-exist.md"

# --- default file set includes only tracked and untracked-unignored markdown ---
repo=$work/repo
mkdir -p "$repo/scripts" "$repo/devlog" "$repo/.claude/worktrees/x"
cp "$checker" "$repo/scripts/"
printf '# Included tracked file\n' >"$repo/tracked.md"
printf '# Included untracked file\n' >"$repo/untracked.md"
printf '# Excluded deleted file\n' >"$repo/deleted.md"
printf '# Excluded frozen entry\n' >"$repo/devlog/frozen.md"
printf '# Excluded worktree copy\n' >"$repo/.claude/worktrees/x/copy.md"
printf '# Excluded ignored file\n' >"$repo/ignored.md"
printf 'ignored.md\n' >"$repo/.gitignore"
git -C "$repo" -c init.defaultBranch=main init -q
git -C "$repo" add .gitignore tracked.md deleted.md
rm "$repo/deleted.md"
actual=0
"$repo/scripts/check-readability.sh" >"$work/default-output" 2>&1 || actual=$?
total=$((total + 1))
if [ "$actual" -ne 0 ]; then
  echo "FAIL: synthetic-repo default scan (expected exit 0, got $actual)"
  fails=$((fails + 1))
fi
total=$((total + 1))
if ! grep -Fq '| tracked.md |' "$work/default-output" || \
  ! grep -Fq '| untracked.md |' "$work/default-output" || \
  grep -Fq '| deleted.md |' "$work/default-output" || \
  grep -Eq 'devlog|\.claude|ignored\.md' "$work/default-output"; then
  echo 'FAIL: default file-set inclusions or exclusions'
  fails=$((fails + 1))
fi

# --- gate mode checks touched ranges and reports word deltas ---
gate_repo=$work/gate-repo
mkdir -p "$gate_repo/scripts" "$gate_repo/devlog" "$gate_repo/.claude"
cp "$checker" "$gate_repo/scripts/"
git -C "$gate_repo" -c init.defaultBranch=main init -q
git -C "$gate_repo" config user.name 'Readability Test'
git -C "$gate_repo" config user.email 'readability@example.invalid'

long_line=$(words 15)
long_end="$(words 15)."
long_end_changed="changed $(words 14)."
printf '%s\n' "$long_line" "$long_line" "$long_end" '' \
  'Short paragraph.' >"$gate_repo/legacy.md"

ten_words="$(words 10)."
{
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    printf '%s\n' "$ten_words"
  done
} >"$gate_repo/paragraph.md"

printf 'two words.\n' >"$gate_repo/delta-modified.md"
printf 'three base words.\n' >"$gate_repo/delta-deleted.md"
git -C "$gate_repo" add .
git -C "$gate_repo" commit -qm 'Fixture base'

run_gate_case() { # run_gate_case <name> <expected-exit> [checker args...]
  local name=$1 expected=$2 actual=0
  shift 2
  last_output=$work/output
  "$gate_repo/scripts/check-readability.sh" "$@" >"$last_output" 2>&1 || \
    actual=$?
  total=$((total + 1))
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL: $name (expected exit $expected, got $actual)"
    sed 's/^/  | /' "$last_output"
    fails=$((fails + 1))
  fi
}

restore_gate_repo() {
  git -C "$gate_repo" restore --staged .
  git -C "$gate_repo" restore .
  git -C "$gate_repo" clean -fdq
}

run_gate_case 'gate requires base' 2 --gate
total=$((total + 1))
if ! grep -Fqx \
  'usage: check-readability.sh [--gate --base <ref>] [file ...]' \
  "$last_output"; then
  echo 'FAIL: gate without base prints usage'
  fails=$((fails + 1))
fi
run_gate_case 'base requires gate' 2 --base main

printf '%s\n' "$long_line" "$long_line" "$long_end_changed" '' \
  'Short paragraph.' >"$gate_repo/legacy.md"
run_gate_case 'wrapped touched long sentence fails' 1 --gate --base main
total=$((total + 1))
if ! grep -Fqx \
  'legacy.md:1: sentence of 45 words (limit 40)' "$last_output"; then
  echo 'FAIL: wrapped sentence violation or line number'
  fails=$((fails + 1))
fi
restore_gate_repo

printf '%s\n' "$long_line" "$long_line" "$long_end" '' \
  'Changed paragraph.' >"$gate_repo/legacy.md"
run_gate_case 'untouched long sentence passes' 0 --gate --base main
restore_gate_repo

printf '%s\n' "$(words 41)." >"$gate_repo/café.md"
git -C "$gate_repo" add -N café.md
run_gate_case 'intent-to-add long sentence fails' 1 --gate --base main
total=$((total + 1))
if ! grep -Fqx 'café.md:1: sentence of 41 words (limit 40)' \
  "$last_output"; then
  echo 'FAIL: intent-to-add file was not gated'
  fails=$((fails + 1))
fi
restore_gate_repo

printf 'changed %s\n' "$(words 9)." >"$gate_repo/paragraph.md"
for _ in 1 2 3 4 5 6 7 8 9 10 11; do
  printf '%s\n' "$ten_words" >>"$gate_repo/paragraph.md"
done
run_gate_case 'touched 120-word paragraph passes' 0 --gate --base main
restore_gate_repo

printf 'changed extra %s\n' "$(words 9)." >"$gate_repo/paragraph.md"
for _ in 1 2 3 4 5 6 7 8 9 10 11; do
  printf '%s\n' "$ten_words" >>"$gate_repo/paragraph.md"
done
run_gate_case 'touched 121-word paragraph fails' 1 --gate --base main
total=$((total + 1))
if ! grep -Fqx \
  'paragraph.md:1: paragraph of 121 words (limit 120)' "$last_output"; then
  echo 'FAIL: paragraph violation or threshold'
  fails=$((fails + 1))
fi
restore_gate_repo

printf '%s\n' '<!-- readability: allow -->' "$(words 41)." \
  '<!-- readability: end -->' "$(words 42)." \
  >"$gate_repo/region.md"
git -C "$gate_repo" add -N region.md
run_gate_case 'allow region ends at end marker' 1 --gate --base main
total=$((total + 1))
if ! grep -Fqx \
  'region.md:4: sentence of 42 words (limit 40)' "$last_output"; then
  echo 'FAIL: region end did not restore gating'
  fails=$((fails + 1))
fi
restore_gate_repo

printf '%s\n' '<!-- readability: allow -->' \
  "- $(words 41)." \
  "> $(words 42)." \
  '| heading |' '| --- |' "| $(words 43). |" \
  >"$gate_repo/region-eof.md"
git -C "$gate_repo" add -N region-eof.md
run_gate_case 'allow region reaches end across structures' 0 \
  --gate --base main
restore_gate_repo

git -C "$gate_repo" mv legacy.md renamed-legacy.md
run_gate_case 'pure rename has no touched prose' 0 --gate --base main
total=$((total + 1))
if ! grep -Fqx \
  '| renamed-legacy.md | 47 | 47 | +0 |' "$last_output"; then
  echo 'FAIL: pure rename word delta lost its source path'
  fails=$((fails + 1))
fi
run_gate_case 'explicit pure rename has no touched prose' 0 \
  --gate --base main "$gate_repo/renamed-legacy.md"
restore_gate_repo

printf '%s\n' '---' 'title: Hidden words' '---' "$(words 41)." \
  >"$gate_repo/frontmatter-line.md"
git -C "$gate_repo" add -N frontmatter-line.md
run_gate_case 'frontmatter keeps gate line numbers' 1 --gate --base main
total=$((total + 1))
if ! grep -Fqx \
  'frontmatter-line.md:4: sentence of 41 words (limit 40)' \
  "$last_output"; then
  echo 'FAIL: frontmatter shifted the gate line number'
  fails=$((fails + 1))
fi
restore_gate_repo

printf 'four changed words now.\n' >"$gate_repo/delta-modified.md"
rm "$gate_repo/delta-deleted.md"
printf 'five brand new words here.\n' >"$gate_repo/delta-new.md"
git -C "$gate_repo" add -A
run_gate_case 'gate word deltas are report-only' 0 --gate --base main
for expected in \
  '| delta-deleted.md | 3 | 0 | -3 |' \
  '| delta-modified.md | 2 | 4 | +2 |' \
  '| delta-new.md | 0 | 5 | +5 |'; do
  total=$((total + 1))
  if ! grep -Fqx "$expected" "$last_output"; then
    echo "FAIL: missing word-delta row: $expected"
    fails=$((fails + 1))
  fi
done
restore_gate_repo

mkdir -p "$gate_repo/devlog" "$gate_repo/.claude"
printf '%s\n' "$(words 41)." >"$gate_repo/devlog/excluded.md"
printf '%s\n' "$(words 41)." >"$gate_repo/.claude/excluded.md"
git -C "$gate_repo" add -N devlog/excluded.md .claude/excluded.md
run_gate_case 'gate excludes devlog and claude trees' 0 --gate --base main
restore_gate_repo

# --- an empty default file set is a successful empty report ---
empty_repo=$work/empty-repo
mkdir -p "$empty_repo/scripts"
cp "$checker" "$empty_repo/scripts/"
git -C "$empty_repo" -c init.defaultBranch=main init -q
run_empty=0
"$empty_repo/scripts/check-readability.sh" >"$work/empty-output" 2>&1 || run_empty=$?
total=$((total + 1))
if [ "$run_empty" -ne 0 ] || \
  ! grep -Fqx 'readability: no markdown files to report' "$work/empty-output"; then
  echo 'FAIL: empty default file set'
  fails=$((fails + 1))
fi

echo "readability matrix: passed $((total - fails)) / $total"
exit "$([ "$fails" -eq 0 ] && echo 0 || echo 1)"
