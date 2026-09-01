#!/usr/bin/env bash
# Regression matrix for scripts/check-review-convergence-layers.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

checker=$PWD/scripts/check-review-convergence-layers.sh
reference=skills/await-pr-review/references/review-response.md

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

new_root() { # new_root <name> <reference text> <summary text>
  local root=$work/$1
  mkdir -p "$root/$(dirname "$reference")"
  printf '%s\n' "$2" >"$root/$reference"
  printf '%s\n' "$3" >"$root/summary.md"
  printf 'rule-a\t%s\trequired phrase\n' "$reference" >"$root/table.tsv"
  printf 'rule-a\tsummary.md\trequired phrase\n' >>"$root/table.tsv"
  echo "$root"
}

satisfied=$(new_root satisfied 'required phrase' 'required phrase')
run_case 'every row satisfied' 0 --root "$satisfied" "$satisfied/table.tsv"

wrapped=$(new_root wrapped 'required phrase' $'- required\n  phrase')
run_case 'wrapped indented phrase' 0 --root "$wrapped" "$wrapped/table.tsv"

marked=$(new_root marked 'required phrase' 'required **phrase**')
printf 'rule-b\t%s\tpublic boundary caller\n' "$reference" >>"$marked/table.tsv"
printf 'rule-b\tsummary.md\tpublic boundary caller\n' >>"$marked/table.tsv"
printf '%s\n' "required **phrase**; public **boundary** \`caller\`" \
  >"$marked/$reference"
printf '%s\n' "required **phrase**; public **boundary** \`caller\`" \
  >"$marked/summary.md"
run_case 'bold and code-span markers' 0 --root "$marked" "$marked/table.tsv"

comments=$(new_root comments 'required phrase' 'required phrase')
printf '# Comment\n\n' >>"$comments/table.tsv"
run_case 'comments and blank lines' 0 --root "$comments" "$comments/table.tsv"

missing=$(new_root missing 'required phrase' 'different phrase')
run_case 'summary phrase missing' 1 --root "$missing" "$missing/table.tsv"
total=$((total + 1))
output=$("$checker" --root "$missing" "$missing/table.tsv" 2>&1 || true)
if ! grep -Fq 'rule-a: summary.md lacks "required phrase"' <<<"$output"; then
  echo 'FAIL: finding output omits the rule key, path, or phrase'
  fails=$((fails + 1))
fi

reworded=$(new_root reworded 'changed phrase' 'required phrase')
run_case 'reference reworded' 1 --root "$reworded" "$reworded/table.tsv"

case_only=$(new_root case-only 'required phrase' 'Required phrase')
run_case 'case difference only' 1 --root "$case_only" "$case_only/table.tsv"

two_columns=$(new_root two-columns 'required phrase' 'required phrase')
printf 'broken\tonly-two\n' >>"$two_columns/table.tsv"
run_case 'two-column row' 2 --root "$two_columns" "$two_columns/table.tsv"

four_columns=$(new_root four-columns 'required phrase' 'required phrase')
printf 'broken\tpath\tphrase\textra\n' >>"$four_columns/table.tsv"
run_case 'four-column row' 2 --root "$four_columns" "$four_columns/table.tsv"

blank_phrase=$(new_root blank-phrase 'required phrase' 'required phrase')
printf 'rule-b\t%s\t   \n' "$reference" >>"$blank_phrase/table.tsv"
run_case 'whitespace-only phrase' 2 --root "$blank_phrase" \
  "$blank_phrase/table.tsv"

missing_file=$(new_root missing-file 'required phrase' 'required phrase')
printf 'rule-b\t%s\trequired phrase\n' "$reference" >>"$missing_file/table.tsv"
printf 'rule-b\tabsent.md\trequired phrase\n' >>"$missing_file/table.tsv"
run_case 'missing layer file' 2 --root "$missing_file" \
  "$missing_file/table.tsv"

no_reference=$(new_root no-reference 'required phrase' 'required phrase')
printf 'rule-b\tsummary.md\trequired phrase\n' >>"$no_reference/table.tsv"
run_case 'rule without reference row' 2 --root "$no_reference" \
  "$no_reference/table.tsv"

run_case 'live repository table' 0

echo "review-convergence-layer matrix: passed $((total - fails)) / $total"
exit "$([ "$fails" -eq 0 ] && echo 0 || echo 1)"
