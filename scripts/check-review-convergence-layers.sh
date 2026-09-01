#!/usr/bin/env bash
# Check exact per-layer phrases for the review-convergence rules. This makes
# the AGENTS.md dogfooded-sync convention for those layers mechanical.
#
# Usage: check-review-convergence-layers.sh [--root DIR] [TABLE]
#   Root defaults to the repository containing this script. Table defaults to
#   scripts/review-convergence-layers.tsv and resolves against root.
#
# Exit codes: 0 clean, 1 findings, 2 usage/environment error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
caller_dir=$PWD
root=$repo_root
table=scripts/review-convergence-layers.tsv
table_set=false

usage() {
  echo 'usage: check-review-convergence-layers.sh [--root DIR] [TABLE]' >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      root=$2
      shift 2
      ;;
    --*)
      usage
      exit 2
      ;;
    *)
      if [ "$table_set" = true ]; then
        usage
        exit 2
      fi
      table=$1
      table_set=true
      shift
      ;;
  esac
done

case "$root" in
  /*) ;;
  *) root=$caller_dir/$root ;;
esac
case "$table" in
  /*) ;;
  *) table=$root/$table ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo 'review-convergence layers: python3 is required' >&2
  exit 2
fi

python3 - "$root" "$table" <<'PY'
import os
import sys

REFERENCE_PATH = "skills/await-pr-review/references/review-response.md"


def normalize(value):
    return " ".join(value.replace("**", "").replace("`", "").split())


root, table_path = sys.argv[1:]
try:
    table_file = open(table_path, encoding="utf-8")
except OSError as err:
    print("review-convergence layers: %s" % err, file=sys.stderr)
    sys.exit(2)

rows = []
malformed = False
seen = set()
with table_file:
    for lineno, raw in enumerate(table_file, 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 3 or any(not field.strip() for field in fields):
            print(
                "%s:%d: expected three non-empty tab-separated columns"
                % (table_path, lineno),
                file=sys.stderr,
            )
            malformed = True
            continue
        key, path, phrase = fields
        row_id = (key, path)
        if row_id in seen:
            print(
                "%s:%d: duplicate rule key and layer path: %s, %s"
                % (table_path, lineno, key, path),
                file=sys.stderr,
            )
            malformed = True
            continue
        seen.add(row_id)
        rows.append((key, path, phrase))

if malformed:
    sys.exit(2)
if not rows:
    print("review-convergence layers: table has no rules", file=sys.stderr)
    sys.exit(2)

keys = {key for key, _, _ in rows}
reference_keys = {key for key, path, _ in rows if path == REFERENCE_PATH}
missing_reference = sorted(keys - reference_keys)
if missing_reference:
    for key in missing_reference:
        print(
            "%s: rule has no reference row: %s" % (table_path, key),
            file=sys.stderr,
        )
    sys.exit(2)

contents = {}
for path in sorted({path for _, path, _ in rows}):
    full_path = os.path.join(root, path)
    try:
        with open(full_path, encoding="utf-8") as layer_file:
            contents[path] = normalize(layer_file.read())
    except OSError as err:
        print("review-convergence layers: %s" % err, file=sys.stderr)
        sys.exit(2)

findings = []
for key, path, phrase in rows:
    if normalize(phrase) not in contents[path]:
        findings.append((key, path, phrase))

rule_count = len(keys)
file_count = len(contents)
if findings:
    for key, path, phrase in findings:
        print('%s: %s lacks "%s"' % (key, path, phrase))
    print(
        "review-convergence layers: %d finding(s), %d rule(s), "
        "%d file(s) checked" % (len(findings), rule_count, file_count)
    )
    sys.exit(1)

print(
    "review-convergence layers: clean (%d rule(s), %d file(s) checked)"
    % (rule_count, file_count)
)
PY
