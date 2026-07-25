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
# Run it from the project root: the canonical sections resolve relative
# to this script, but the AGENTS.md path resolves from the caller's
# working directory (it defaults to AGENTS.md there).
#
# Reports one line per key, scannable together: "ok:", "drift:" (after
# that key's diff), or "missing:"; boundary problems print "marker
# error:" and stop the run before any comparison.
#
# Exit 0: no drift, no malformed markers (and, with --require-all, no
# missing blocks). Exit 1 otherwise, including a usage error.
set -euo pipefail

usage() {
  echo "usage: compare-managed-blocks.sh [--require-all] [path/to/AGENTS.md]" >&2
}

canon="$(cd "$(dirname "$0")/.." && pwd)/references/canonical-sections.md"
require_all=0
agents=
for arg in "$@"; do
  case "$arg" in
    --require-all) require_all=1 ;;
    # An unknown flag must not fall through to the path arm: a typo like
    # --require_all was otherwise read as a filename, so alone it failed
    # with a misleading "AGENTS.md not found" and ahead of a real path it
    # was overwritten, running tolerantly while looking strict.
    -*)
      echo "unknown option: $arg" >&2
      usage
      exit 1
      ;;
    *)
      if [ -n "$agents" ]; then
        echo "unexpected extra argument: $arg" >&2
        usage
        exit 1
      fi
      agents="$arg"
      ;;
  esac
done
agents="${agents:-AGENTS.md}"
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

# A marker namespace claim: the agents-md root, any run of separator
# characters, a section word, and the colon that introduces a key. Both
# halves earn their place. The separator is unbounded but alphanumeric
# free, so any number of spaces, colons, or punctuation between root and
# section word matches, while prose with words between them
# ("docs/agents-md.md for managed conventions") does not; a bounded
# separator would be the same spelling trap with a number in it. The
# trailing colon is what distinguishes a marker claim from prose that
# happens to say agents-md and managed in one comment, the false
# positive that aborts an otherwise valid update. A form with no key
# colon at all ("<!-- agents-md managed done -->") is deliberately out of
# scope: it no longer claims to be a marker, and widening to reach it
# re-introduces the false positive.
namespace_re='agents-md[^A-Za-z0-9]*(managed|project)[^A-Za-z0-9]*:'

# Every string that is a marker: anything else carrying marker text is a
# malformation, whatever it is trying to be.
exact_markers=("<!-- agents-md:project:done-checks -->" "<!-- /agents-md:project:done-checks -->")
for key in "${keys[@]}"; do
  exact_markers+=("<!-- agents-md:managed:$key -->" "<!-- /agents-md:managed:$key -->")
done

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
  # One scan, and it reads neither the key nor the delimiters. Earlier
  # versions matched on marker spelling (comment-leading lines, then a
  # per-key literal, then a key pattern, then a well-formed arrow), and
  # each spelling let the next mangling through: indented, prefixed,
  # unknown key, uppercase key, spaced key, broken arrow. The rule
  # instead: a line carrying a marker *namespace* (agents-md, a colon,
  # managed or project, in any case or spacing) near comment syntax is
  # claiming to be a marker, so it must BE an exact marker line, however
  # mangled its delimiters are. The namespace, not the bare agents-md
  # token, is the trigger: a downstream file may mention agents-md in an
  # ordinary comment ("<!-- see docs/agents-md.md -->") and that is not a
  # marker claim. Two forms are prose, and both come from what the
  # canonical file and this repo's AGENTS.md actually contain, not from
  # guesswork: the documented `*` wildcard (dropped first, and only when
  # no key character follows, so `:*bogus` stays a malformation), and a
  # mention carrying no comment delimiters at all.
  while IFS= read -r line; do
    ok=0
    for m in "${exact_markers[@]}"; do
      if [ "$line" = "$m" ]; then
        ok=1
        break
      fi
    done
    if [ "$ok" -eq 1 ]; then
      continue
    fi
    stripped=$(printf '%s\n' "$line" |
      sed -E 's/agents-md:(managed|project):\*([^A-Za-z0-9_.-]|$)/\2/g')
    printf '%s\n' "$stripped" | grep -qiE "$namespace_re" || continue
    if printf '%s\n' "$stripped" | grep -qE '<!--|--[[:space:]]*>'; then
      echo "marker error: marker text malformed, embedded, or unknown in '$line' in $f"
      status=1
    fi
  done < <(grep -iE "$namespace_re" "$f" || true)

  # A block's open/close markers travel together, once each, open before
  # close. Both absent is a legitimate opt-out; anything else is
  # malformed.
  ranges=()
  for key in "${keys[@]}"; do
    o=$(count_line "$f" "<!-- agents-md:managed:$key -->")
    c=$(count_line "$f" "<!-- /agents-md:managed:$key -->")
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
      continue
    fi
    ranges+=("$ol $cl $key")
  done

  # Blocks must also be globally disjoint. Per-key pairing can't see a
  # crossing or nested pair (open branches, open commits, close branches,
  # close commits): every key is paired once in order, so extraction would
  # silently pull the inner marker into the outer block and a refresh
  # would delete it.
  while read -r outer inner line; do
    echo "marker error: managed:$outer and managed:$inner blocks overlap in $f (line $line)"
    status=1
  done < <(printf '%s\n' ${ranges[@]+"${ranges[@]}"} | sort -n | awk '
    NR > 1 && $1 < prev_close { print prev_key, $3, $1 }
    { if ($2 > prev_close) { prev_close = $2; prev_key = $3 } }
  ')

  # The nested project pair is either absent entirely or exactly one
  # correctly ordered pair, checked whether or not a managed done block
  # exists: a half or reversed pair left behind by an opt-out is
  # malformed, not project content, and re-adopting done would inherit
  # it. Only containment (the pair sits inside the done block) depends
  # on that block existing.
  nopen=$(count_line "$f" "<!-- agents-md:project:done-checks -->")
  nclose=$(count_line "$f" "<!-- /agents-md:project:done-checks -->")
  has_done=$(count_line "$f" "<!-- agents-md:managed:done -->")
  # The embedded-fragment case needs no check of its own here: the
  # marker-text scan above covers both namespaces.
  if [ "$has_done" -eq 1 ] || [ "$nopen" -ne 0 ] || [ "$nclose" -ne 0 ]; then
    for m in "<!-- agents-md:project:done-checks -->" \
      "<!-- /agents-md:project:done-checks -->"; do
      if [ "$(count_line "$f" "$m")" -ne 1 ]; then
        echo "marker error: '$m' must appear exactly once in $f"
        status=1
      # grep without -q drains its input: with pipefail, -q's early exit
      # would SIGPIPE awk on a large done block and falsely reject it.
      elif [ "$has_done" -eq 1 ] && ! raw_block "$f" done | grep -xF "$m" >/dev/null; then
        echo "marker error: '$m' is not inside the done block in $f"
        status=1
      fi
    done
    ol=$(grep -m1 -nxF "<!-- agents-md:project:done-checks -->" "$f" | cut -d: -f1)
    cl=$(grep -m1 -nxF "<!-- /agents-md:project:done-checks -->" "$f" | cut -d: -f1)
    if [ -n "$ol" ] && [ -n "$cl" ] && [ "$ol" -ge "$cl" ]; then
      echo "marker error: project:done-checks close marker precedes open in $f"
      status=1
    fi
    # Containment cuts both ways, and the second half only shows up with
    # done opted out: the pair may sit inside the done block, or outside
    # every managed block as plain project content, but never inside a
    # sibling block. There it reads as that block's content, so a refresh
    # would delete the project's own checks; the diff alone reports it as
    # ordinary drift, which is exactly the untrusted boundary this
    # validation exists to stop.
    # Compare intervals, not endpoints: a pair that opens before a block
    # and closes inside it (or envelops the block) crosses the same
    # boundary as one sitting wholly within it, and testing the opener
    # alone would miss both.
    if [ "$has_done" -eq 0 ] && [ -n "$ol" ] && [ -n "$cl" ]; then
      for r in ${ranges[@]+"${ranges[@]}"}; do
        r_open=${r%% *}
        r_rest=${r#* }
        r_close=${r_rest%% *}
        r_key=${r_rest#* }
        if [ "$cl" -ge "$r_open" ] && [ "$ol" -le "$r_close" ]; then
          echo "marker error: project:done-checks pair overlaps the managed:$r_key block with no managed done block in $f"
          status=1
        fi
      done
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
    echo "drift: $key"
    status=1
  fi
done
exit "$status"
