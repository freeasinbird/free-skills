#!/usr/bin/env bash
# Flag prose tics in markdown: em dashes, en dashes outside numeric
# ranges, and stock AI openers (the AGENTS.md Conventions "write prose
# without em dashes" rule, made mechanical).
#
# Usage: check-prose-tics.sh [file ...]
#   With no arguments, scans tracked and untracked-unignored *.md files,
#   excluding devlog/ (merged devlog entries are frozen by the devlog
#   protocol, so their historical punctuation stays) and .claude/
#   (session-local worktree copies, not project prose).
#
# En-dash rule: an en dash is allowed only as a tight range joiner, both
# neighbors non-whitespace with at least one a digit ("2-4", "2m54s-4m46s");
# anything else is treated as an em-dash substitute.
#
# Exit codes: 0 clean, 1 findings, 2 usage/environment error.
set -euo pipefail
cd "$(dirname "$0")/.."

files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(git ls-files -z --cached --others --exclude-standard -- \
    '*.md' ':!devlog' ':!.claude')
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "prose tics: no markdown files to scan"
  exit 0
fi

python3 - "${files[@]}" <<'PY'
import sys

EM = "—"
EN = "–"
# Stock AI openers, matched case-insensitively anywhere in a line, with
# curly apostrophes normalized to straight ones first. The literals live
# only here (a non-scanned file) so the check can't flag itself.
OPENERS = ("you're absolutely right", "great question", "perfect!")


def en_dash_misused(line):
    for i, ch in enumerate(line):
        if ch != EN:
            continue
        prev = line[i - 1] if i > 0 else " "
        nxt = line[i + 1] if i + 1 < len(line) else " "
        tight = not prev.isspace() and not nxt.isspace()
        if not (tight and (prev.isdigit() or nxt.isdigit())):
            return True
    return False


findings = 0
for path in sys.argv[1:]:
    try:
        fh = open(path, encoding="utf-8")
    except OSError as err:
        print("prose tics: %s" % err, file=sys.stderr)
        sys.exit(2)
    with fh:
        for lineno, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            hits = []
            if EM in line:
                hits.append("em dash")
            if en_dash_misused(line):
                hits.append("en dash outside a numeric range")
            lowered = line.lower().replace("’", "'")
            hits.extend(
                'stock AI opener ("%s")' % o for o in OPENERS if o in lowered
            )
            for hit in hits:
                print("%s:%d: %s" % (path, lineno, hit))
            findings += len(hits)

scanned = len(sys.argv) - 1
if findings:
    print("prose tics: %d finding(s), %d file(s) scanned" % (findings, scanned))
    sys.exit(1)
print("prose tics: clean (%d file(s) scanned)" % scanned)
PY
