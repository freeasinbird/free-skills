#!/usr/bin/env bash
# Dogfood check: free-skills' own AGENTS.md must stay byte-identical to
# the canonical source (modulo the nested project:done-checks block,
# which is project-specific by design); its docs/agent-workflow.md must
# stay byte-identical to the §agent-workflow scaffold template; every
# `docs/agent-workflow.md §slug` pointer in the canonical text must
# resolve to a `## slug` heading in that file and every level-two
# heading there must be such a slug and be pointed at; and the
# managed blocks (excluding the project sub-block) must stay
# within the byte budget the core/reference split set (see
# devlog/2026-08-21-1049-core-reference-split.md). Thin strict-mode
# wrapper over the comparator shipped with the agent-setup skill, plus
# the checks the split added. Every check runs; the exit status is the
# worst of them.
set -uo pipefail
cd "$(dirname "$0")/.."

CANONICAL=skills/agent-setup/references/canonical-sections.md
TEMPLATE=skills/agent-setup/references/scaffolding.md
REFERENCE=docs/agent-workflow.md
BUDGET=20000
status=0

skills/agent-setup/scripts/compare-managed-blocks.sh --require-all AGENTS.md || status=1

# The template body is the fenced block under `## §agent-workflow`. The
# opening fence may be any run of three or more backticks; the block
# ends at a fence of exactly that length, so a shorter fence nested in
# the body does not end it.
template_body() {
  awk '
    /^## §agent-workflow$/ { in_section = 1; next }
    in_section && !in_fence && /^```+markdown$/ {
      in_fence = 1; fence = $0; sub(/markdown$/, "", fence); next
    }
    in_fence && $0 == fence { exit }
    in_fence { print }
  ' "$TEMPLATE"
}

if diff -u <(template_body) "$REFERENCE"; then
  echo "ok: $REFERENCE"
else
  echo "drift: $REFERENCE differs from $TEMPLATE §agent-workflow" >&2
  status=1
fi

# A fenced example is not a section a pointer can name. Exclude backtick and
# tilde fenced blocks before the heading checks, or a template-identical
# example containing `## heading` would be rejected by the pointer scan.
reference_headings() {
  awk '
    function fence_run(line, marker, count) {
      marker = substr(line, 1, 1)
      if (marker != "`" && marker != "~") return 0
      count = 0
      while (substr(line, count + 1, 1) == marker) count++
      return count
    }
    {
      line = $0
      indent = 0
      while (indent < 3 && substr(line, 1, 1) == " ") {
        line = substr(line, 2)
        indent++
      }
      run = fence_run(line)
      marker = substr(line, 1, 1)
      if (in_fence) {
        if (marker == fence_marker && run >= fence_length &&
            substr(line, run + 1) ~ /^[[:space:]]*$/) {
          in_fence = 0
        }
        next
      }
      if (run >= 3) {
        info = substr(line, run + 1)
        if (marker == "~" || index(info, "`") == 0) {
          in_fence = 1
          fence_marker = marker
          fence_length = run
          next
        }
      }
      if ($0 ~ /^## /) print
    }
  ' "$REFERENCE"
}

# Pointers wrap across lines between the path and the slug, so join the
# canonical text before matching.
# A target runs to the next space, and only sentence punctuation may
# end it: taking the longest slug-shaped prefix instead would let
# `§reviewing-a-pr_EXTRA` pass as the heading `reviewing-a-pr`.
targets=$(tr '\n' ' ' < "$CANONICAL" | grep -o '`docs/agent-workflow.md` *§[^[:space:]]*' | sed 's/.*§//' | sed -E 's/[].,;:)}`"'"'"']+$//')
stray=$(printf '%s' "$targets" | grep -vE '^[a-z0-9-]+$' || true)
if [ -n "$stray" ]; then
  echo "$CANONICAL has pointer target(s) that are not §slugs:" >&2
  printf '%s\n' "$stray" >&2
  status=1
fi
pointed=$(printf '%s\n' "$targets" | sort -u)
# Every level-two heading in the reference is a pointer target, so match
# them all rather than only slug-shaped ones: a narrower pattern would
# hide a prose-titled section from the "every heading is pointed at"
# half of the check, leaving a section core never sends anyone to.
headed=$(reference_headings | sed 's/^## *//' | sort -u)
malformed=$(reference_headings | sed 's/^## *//' | grep -vE '^[a-z0-9-]+$' || true)
if [ -n "$malformed" ]; then
  echo "$REFERENCE heading(s) are not §slugs a pointer can name:" >&2
  printf '%s\n' "$malformed" >&2
  status=1
fi
# The set comparison below dedupes, so repeated slugs would hide behind
# their first occurrence and leave a pointer with two possible targets.
duplicated=$(reference_headings | sed 's/^## *//' | sort | uniq -d)
if [ -n "$duplicated" ]; then
  echo "$REFERENCE has repeated §slug heading(s):" >&2
  printf '%s\n' "$duplicated" >&2
  status=1
fi
if [ "$pointed" = "$headed" ]; then
  echo "ok: pointers ($(printf '%s\n' "$headed" | wc -l | tr -d ' ') slugs)"
else
  echo "pointer mismatch between $CANONICAL and $REFERENCE:" >&2
  diff <(printf '%s\n' "$pointed") <(printf '%s\n' "$headed") >&2
  status=1
fi

# The budget is encoded bytes, and awk's length() counts characters in
# a UTF-8 locale (the blocks hold en dashes, arrows and `≤`), so print
# the extracted lines and let wc -c count the stream.
bytes=$(awk '
  /^<!-- agents-md:managed:/ { m = 1 }
  /^<!-- agents-md:project:/ { p = 1 }
  { if (m && !p) print }
  /^<!-- \/agents-md:project:/ { p = 0 }
  /^<!-- \/agents-md:managed:/ { m = 0 }
' AGENTS.md | wc -c | tr -d ' ')
if [ "$bytes" -le "$BUDGET" ]; then
  echo "ok: managed blocks $bytes bytes (budget $BUDGET)"
else
  echo "managed blocks $bytes bytes exceed the $BUDGET budget" >&2
  status=1
fi

exit "$status"
