#!/usr/bin/env bash
# Verify AGENTS.md's agents-md:managed:* blocks match the canonical source
# (skills/agent-setup/references/canonical-sections.md). The nested
# agents-md:project:done-checks block is project-specific by design and
# excluded from the comparison. Exits non-zero on any drift.
set -euo pipefail
cd "$(dirname "$0")/.."

canon=skills/agent-setup/references/canonical-sections.md
agents=AGENTS.md
keys=(devlog finish-line branches pull-requests commits done)

# Marker validation must pass before exclusion-based extraction can be
# trusted: a missing nested block (or a missing closing marker) would
# otherwise make both sides extract equal and hide the loss.
marker_once() { # marker_once <file> <marker-line>
  local n
  n=$(grep -cxF "$2" "$1" || true)
  if [ "$n" -ne 1 ]; then
    echo "marker error: '$2' appears $n time(s) in $1"
    return 1
  fi
}

raw_block() { # raw_block <file> <key>: block body, nothing excluded
  awk -v key="$2" '
    $0 == "<!-- agents-md:managed:" key " -->" { inblock = 1; next }
    $0 == "<!-- /agents-md:managed:" key " -->" { inblock = 0 }
    inblock { print }
  ' "$1"
}

status=0
for f in "$canon" "$agents"; do
  # No unknown or malformed managed markers. Any comment line that
  # mentions the managed-marker tokens at all, in any spacing, case, or
  # indentation variant, must exactly equal one of the canonical marker
  # strings: a lookalike (typo_key, Done, <!--agents-md:managed:done-->,
  # an indented marker, <!-- agents-md:managed :done -->) is invisible
  # to the exact-match extraction below and would otherwise pass
  # silently. Scanning by tokens rather than by prefix shape means new
  # spacing variants can't slip past the scan.
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
  # Paired once each, open before close.
  for key in "${keys[@]}"; do
    marker_once "$f" "<!-- agents-md:managed:$key -->" || status=1
    marker_once "$f" "<!-- /agents-md:managed:$key -->" || status=1
    ol=$(grep -nxF "<!-- agents-md:managed:$key -->" "$f" | head -1 | cut -d: -f1)
    cl=$(grep -nxF "<!-- /agents-md:managed:$key -->" "$f" | head -1 | cut -d: -f1)
    if [ -n "$ol" ] && [ -n "$cl" ] && [ "$ol" -ge "$cl" ]; then
      echo "marker error: managed:$key close marker precedes open in $f"
      status=1
    fi
  done
  for m in "<!-- agents-md:project:done-checks -->" \
    "<!-- /agents-md:project:done-checks -->"; do
    marker_once "$f" "$m" || status=1
    if ! raw_block "$f" done | grep -qxF "$m"; then
      echo "marker error: '$m' is not inside the done block in $f"
      status=1
    fi
  done
  ol=$(grep -nxF "<!-- agents-md:project:done-checks -->" "$f" | head -1 | cut -d: -f1)
  cl=$(grep -nxF "<!-- /agents-md:project:done-checks -->" "$f" | head -1 | cut -d: -f1)
  if [ -n "$ol" ] && [ -n "$cl" ] && [ "$ol" -ge "$cl" ]; then
    echo "marker error: project:done-checks close marker precedes open in $f"
    status=1
  fi
done
if [ "$status" -ne 0 ]; then
  exit "$status"
fi

extract() { # extract <file> <key>: block body, nested project block removed
  # Exact line matches only: a regex contains-match would let an inexact
  # nested marker (indented, say) toggle the exclusion and hide managed
  # text from the diff.
  awk -v key="$2" '
    $0 == "<!-- agents-md:managed:" key " -->" { inblock = 1; next }
    $0 == "<!-- /agents-md:managed:" key " -->" { inblock = 0 }
    $0 == "<!-- agents-md:project:done-checks -->" { nested = 1 }
    inblock && !nested { print }
    $0 == "<!-- /agents-md:project:done-checks -->" { nested = 0 }
  ' "$1"
}

for key in "${keys[@]}"; do
  if diff -u --label "canonical:$key" --label "AGENTS.md:$key" \
    <(extract "$canon" "$key") <(extract "$agents" "$key"); then
    echo "ok: $key"
  else
    status=1
  fi
done
exit "$status"
