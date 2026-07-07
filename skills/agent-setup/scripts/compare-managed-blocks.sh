#!/usr/bin/env bash
# Compare a project's AGENTS.md managed blocks against the canonical
# sections shipped with the agent-setup skill. A read-only reporter for
# update mode's mechanical parts: marker validation plus a per-block
# diff. The nested agents-md:project:done-checks block is project-owned
# and excluded from the comparison.
#
# Usage: compare-managed-blocks.sh [--require-all] [path/to/AGENTS.md]
#   --require-all  fail when a managed block is missing entirely
#                  (default: missing is reported but tolerated, since
#                  removing a block's markers is the documented opt-out)
#
# Exit 0: no drift, no malformed markers (and, with --require-all, no
# missing blocks). Exit 1 otherwise.
set -euo pipefail

canon="$(cd "$(dirname "$0")/.." && pwd)/references/canonical-sections.md"
require_all=0
agents=AGENTS.md
for arg in "$@"; do
  case "$arg" in
    --require-all) require_all=1 ;;
    *) agents="$arg" ;;
  esac
done
if [ ! -f "$canon" ]; then
  echo "canonical sections not found: $canon"
  exit 1
fi
if [ ! -f "$agents" ]; then
  echo "AGENTS.md not found: $agents"
  exit 1
fi

keys=(devlog finish-line context branches pull-requests commits done)
status=0

count_line() { # count_line <file> <exact-line>
  grep -cxF "$2" "$1" || true
}

raw_block() { # raw_block <file> <key>: block body, nothing excluded
  awk -v key="$2" '
    $0 == "<!-- agents-md:managed:" key " -->" { inblock = 1; next }
    $0 == "<!-- /agents-md:managed:" key " -->" { inblock = 0 }
    inblock { print }
  ' "$1"
}

extract() { # extract <file> <key>: block body, nested project block removed
  # Exact line matches only: a regex contains-match would let an inexact
  # nested marker (indented, say) toggle the exclusion and hide managed
  # text from the diff.
  awk -v key="$2" '
    $0 == "<!-- agents-md:managed:" key " -->" { inblock = 1; next }
    $0 == "<!-- /agents-md:managed:" key " -->" { inblock = 0 }
    $0 == "<!-- agents-md:project:done-checks -->" && key == "done" {
      nested = 1
      # A sentinel keeps the nested block position in the comparison;
      # dropping the range silently would let a moved pair compare equal.
      if (inblock) print "<nested project:done-checks block>"
    }
    inblock && !nested { print }
    $0 == "<!-- /agents-md:project:done-checks -->" && key == "done" { nested = 0 }
  ' "$1"
}

# Marker validation must pass before exclusion-based extraction can be
# trusted: mistyped keys or nonstandard marker spellings are invisible
# to the exact-match extraction and would otherwise pass silently, and a
# missing closing marker would swallow project text into the block.
for f in "$canon" "$agents"; do
  # Any comment line that mentions the managed-marker tokens at all, in
  # any spacing, case, or indentation variant, must exactly equal one of
  # the canonical marker strings. Scanning by tokens rather than by
  # prefix shape means new spacing variants can't slip past the scan.
  while IFS= read -r line; do
    ok=0
    for key in "${keys[@]}"; do
      if [ "$line" = "<!-- agents-md:managed:$key -->" ] ||
        [ "$line" = "<!-- /agents-md:managed:$key -->" ]; then
        ok=1
        break
      fi
    done
    if [ "$ok" -ne 1 ]; then
      echo "marker error: malformed or unknown managed marker '$line' in $f"
      status=1
    fi
  done < <(grep -E '^[[:space:]]*<!--' "$f" | grep -i 'agents-md' | grep -i 'managed' || true)
  # Same token-based scan for the nested pair: an inexact nested marker
  # (e.g. indented) must be rejected, not silently ignored.
  while IFS= read -r line; do
    if [ "$line" != "<!-- agents-md:project:done-checks -->" ] &&
      [ "$line" != "<!-- /agents-md:project:done-checks -->" ]; then
      echo "marker error: malformed nested done-checks marker '$line' in $f"
      status=1
    fi
  done < <(grep -E '^[[:space:]]*<!--' "$f" | grep -i 'agents-md' | grep -i 'done-checks' || true)

  # A block's open/close markers travel together, once each, open before
  # close. Both absent is a legitimate opt-out; anything else is
  # malformed.
  for key in "${keys[@]}"; do
    o=$(count_line "$f" "<!-- agents-md:managed:$key -->")
    c=$(count_line "$f" "<!-- /agents-md:managed:$key -->")
    # Every line containing this key's marker fragment must BE an exact
    # marker line: any excess is the fragment embedded mid-line (a
    # prefixed "- <!-- agents-md:managed:KEY -->", say), a broken
    # boundary whether or not an exact block also exists. Prose mentions
    # use a * wildcard and never contain a real key's full marker text.
    frag=$(grep -cF "agents-md:managed:$key -->" "$f" || true)
    if [ "$frag" -gt $((o + c)) ]; then
      echo "marker error: managed:$key marker text embedded in a longer line in $f"
      status=1
    fi
    if [ "$o" -eq 0 ] && [ "$c" -eq 0 ]; then
      continue
    fi
    if [ "$o" -ne 1 ] || [ "$c" -ne 1 ]; then
      echo "marker error: managed:$key markers unpaired or duplicated in $f (open=$o close=$c)"
      status=1
      continue
    fi
    ol=$(grep -m1 -nxF "<!-- agents-md:managed:$key -->" "$f" | cut -d: -f1)
    cl=$(grep -m1 -nxF "<!-- /agents-md:managed:$key -->" "$f" | cut -d: -f1)
    if [ "$ol" -ge "$cl" ]; then
      echo "marker error: managed:$key close marker precedes open in $f"
      status=1
    fi
  done

  # When a managed done block exists, the nested project pair must sit
  # inside it, once each. Nested markers with no managed done block are
  # the documented opt-out, not a malformation.
  if [ "$(count_line "$f" '<!-- agents-md:managed:done -->')" -eq 1 ]; then
    for m in "<!-- agents-md:project:done-checks -->" \
      "<!-- /agents-md:project:done-checks -->"; do
      if [ "$(count_line "$f" "$m")" -ne 1 ]; then
        echo "marker error: '$m' must appear exactly once in $f"
        status=1
      # grep without -q drains its input: with pipefail, -q's early exit
      # would SIGPIPE awk on a large done block and falsely reject it.
      elif ! raw_block "$f" done | grep -xF "$m" >/dev/null; then
        echo "marker error: '$m' is not inside the done block in $f"
        status=1
      fi
    done
    # Same embedded-fragment invariant for the nested pair.
    nfrag=$(grep -cF "agents-md:project:done-checks -->" "$f" || true)
    nexact=$(($(count_line "$f" "<!-- agents-md:project:done-checks -->") + $(count_line "$f" "<!-- /agents-md:project:done-checks -->")))
    if [ "$nfrag" -gt "$nexact" ]; then
      echo "marker error: project:done-checks marker text embedded in a longer line in $f"
      status=1
    fi
    ol=$(grep -m1 -nxF "<!-- agents-md:project:done-checks -->" "$f" | cut -d: -f1)
    cl=$(grep -m1 -nxF "<!-- /agents-md:project:done-checks -->" "$f" | cut -d: -f1)
    if [ -n "$ol" ] && [ -n "$cl" ] && [ "$ol" -ge "$cl" ]; then
      echo "marker error: project:done-checks close marker precedes open in $f"
      status=1
    fi
  fi
done
if [ "$status" -ne 0 ]; then
  exit "$status"
fi

for key in "${keys[@]}"; do
  if [ "$(count_line "$agents" "<!-- agents-md:managed:$key -->")" -eq 0 ]; then
    echo "missing: $key (opted out or not yet adopted)"
    if [ "$require_all" -eq 1 ]; then
      status=1
    fi
    continue
  fi
  if diff -u --label "canonical:$key" --label "project:$key" \
    <(extract "$canon" "$key") <(extract "$agents" "$key"); then
    echo "ok: $key"
  else
    status=1
  fi
done
exit "$status"
