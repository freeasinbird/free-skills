#!/usr/bin/env bash
# Regression tests for skills/agent-setup/scripts/compare-managed-blocks.sh.
# Each case is a failure mode verified during the PR #36/#37 review cycle;
# the matrix exists so a comparator edit can't silently regress one (the
# enumerate-once-as-tests rule from AGENTS.md's fix-the-class bullet).
#
# Fixtures are synthesized from the canonical sections, so the tests track
# canonical text changes without editing this file.
set -euo pipefail
cd "$(dirname "$0")/.."

comparator=skills/agent-setup/scripts/compare-managed-blocks.sh
canon=skills/agent-setup/references/canonical-sections.md
keys=(devlog finish-line context branches pull-requests commits done)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Build a downstream-style AGENTS.md: intro plus every managed block in
# canonical order, with fake project checks in the nested block.
build_fixture() { # build_fixture <out-file>
  {
    printf '# Test Project\n\nIntro prose for a synthetic downstream repo.\n'
    for key in "${keys[@]}"; do
      printf '\n'
      awk -v key="$key" '
        $0 == "<!-- agents-md:managed:" key " -->" { inblock = 1 }
        inblock { print }
        $0 == "<!-- /agents-md:managed:" key " -->" { inblock = 0 }
      ' "$canon"
    done
    printf '\n## Local section\n\nUnmanaged project content.\n'
  } >"$1"
}

fixture="$work/AGENTS.md"
build_fixture "$fixture"

fails=0
total=0
run_case() { # run_case <name> <expected-exit> <file> [comparator args...]
  local name=$1 expected=$2 file=$3
  shift 3
  local actual=0
  "$comparator" "$@" "$file" >/dev/null 2>&1 || actual=$?
  total=$((total + 1))
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL: $name (expected exit $expected, got $actual)"
    fails=$((fails + 1))
  fi
}

run_output_case() { # run_output_case <name> <expected-exit> <regex> <file> [args...]
  # A leading '!' on the regex asserts the output does NOT match it.
  local name=$1 expected=$2 pattern=$3 file=$4
  shift 4
  local out actual=0
  out=$("$comparator" "$@" "$file" 2>&1) || actual=$?
  total=$((total + 1))
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL: $name (expected exit $expected, got $actual)"
    fails=$((fails + 1))
  elif [ "${pattern#!}" != "$pattern" ]; then
    if grep -qE "${pattern#!}" <<<"$out"; then
      echo "FAIL: $name (output matched /${pattern#!}/, expected not to)"
      fails=$((fails + 1))
    fi
  elif ! grep -qE "$pattern" <<<"$out"; then
    echo "FAIL: $name (output missing /$pattern/)"
    fails=$((fails + 1))
  fi
}

mutate() { # mutate <python-snippet>: fixture -> $work/mutated.md via stdin/out
  python3 -c "import sys; t = sys.stdin.read(); $1; sys.stdout.write(t)" \
    <"$fixture" >"$work/mutated.md"
}

O='<!-- agents-md:managed:%s -->'
C='<!-- /agents-md:managed:%s -->'
NO='<!-- agents-md:project:done-checks -->'
NC='<!-- /agents-md:project:done-checks -->'

# --- healthy states ---
run_case 'clean fixture' 0 "$fixture"
run_case 'clean fixture, strict' 0 "$fixture" --require-all
run_output_case 'clean fixture reports ok per key' 0 '^ok: branches$' "$fixture"

# --- argument handling ---
run_output_case 'unknown long flag rejected' 1 '^usage:' "$fixture" --require_all
run_output_case 'unknown flag not read as a path' 1 '!AGENTS.md not found' \
  "$fixture" --require_all
run_output_case 'unknown short flag rejected' 1 '^usage:' "$fixture" -x
run_output_case 'extra positional rejected' 1 '^usage:' "$fixture" "$fixture"

mutate "t = t.replace('$(printf "$O" done)\n', '').replace('$(printf "$C" done)\n', '')"
run_case 'done opt-out, tolerant' 0 "$work/mutated.md"
run_case 'done opt-out, strict' 1 "$work/mutated.md" --require-all
run_output_case 'opt-out reports the missing key' 0 '^missing: done' "$work/mutated.md"

mutate "import re; t = re.sub(r'(?s)\n$(printf "$O" branches).*?$(printf "$C" branches)\n', '\n', t)"
run_case 'whole-block opt-out, tolerant' 0 "$work/mutated.md"
run_case 'whole-block opt-out, strict' 1 "$work/mutated.md" --require-all

mutate "t = t.replace('$NO\n', '$NO\n' + '- filler line\n' * 1200, 1)"
run_case 'large nested block (SIGPIPE regression)' 0 "$work/mutated.md"

mutate "t += '<!-- Project note: conventions are managed for agents by maintainers. -->\n'"
run_case 'innocent agents+managed comment' 0 "$work/mutated.md"

# --- drift ---
mutate "t = t.replace('$(printf "$O" branches)\n', '$(printf "$O" branches)\nDRIFT LINE\n', 1)"
run_case 'content drift inside a block' 1 "$work/mutated.md"
run_output_case 'drift names its key beside the diff' 1 '^drift: branches$' \
  "$work/mutated.md"

mutate "t = t.replace('$NO\n', '$NO\nEXTRA CHECK\n', 1)"
run_case 'nested-only change stays excluded' 0 "$work/mutated.md"

# --- malformed markers ---
for bad in \
  '<!-- agents-md:managed:unknown_key -->' \
  '<!--agents-md:managed:done-->' \
  '  <!-- agents-md:managed:devlog -->' \
  '<!-- AGENTS-MD:MANAGED:done -->' \
  '<!-- agents-md:managed :done -->' \
  '<!-- / agents-md:managed:done -->' \
  '<!-- agents-md:managed:done --> trailing' \
  '  <!-- AGENTS-MD:MANAGED:done -->' \
  '  <!-- agents-md:project:done-checks -->'; do
  mutate "t += '''$bad''' + '\n'"
  run_case "lookalike rejected: $bad" 1 "$work/mutated.md"
done

mutate "t = t.replace('$(printf "$C" commits)\n', '', 1)"
run_case 'missing closing marker' 1 "$work/mutated.md"

mutate "t += '$(printf "$O" commits)\nbogus\n$(printf "$C" commits)\n'"
run_case 'duplicate block' 1 "$work/mutated.md"

mutate "t = t.replace('$(printf "$O" commits)', '@@T@@').replace('$(printf "$C" commits)', '$(printf "$O" commits)').replace('@@T@@', '$(printf "$C" commits)')"
run_case 'inverted marker order' 1 "$work/mutated.md"

# --- embedded fragments ---
mutate "t += '- $(printf "$O" branches)\n'"
run_case 'embedded fragment, block present' 1 "$work/mutated.md"

mutate "t = t.replace('$(printf "$O" devlog)', '- $(printf "$O" devlog)').replace('$(printf "$C" devlog)', '- $(printf "$C" devlog)')"
run_case 'embedded pair, block absent' 1 "$work/mutated.md"

mutate "t += 'see - $NO for details\n'"
run_case 'embedded nested fragment' 1 "$work/mutated.md"

# Marker text that names a concrete key must be an exact marker line.
# Enumerated once across the input space (case, punctuation, spacing,
# prefix/suffix, comment opener, namespace) rather than widened a
# character class at a time, per AGENTS.md's fix-the-class rule; two
# rounds of pattern-widening is what this list replaces.
for bad in \
  '- <!-- agents-md:managed:unknown -->' \
  '- <!-- agents-md:managed:UNKNOWN_KEY -->' \
  '- <!-- AGENTS-MD:MANAGED:done -->' \
  '- <!--agents-md:managed:weird.key-->' \
  '- <!-- agents-md:managed:done  -->' \
  '<!-- agents-md:managed:unknown --> trailing' \
  'see agents-md:managed:branches --> for the rule' \
  'see AGENTS-MD:MANAGED:UNKNOWN --> for the rule' \
  '- <!-- agents-md:project:DONE-CHECKS -->' \
  'inline <!-- agents-md:project:done-checks --> mention' \
  '- <!-- agents-md:managed: done -->' \
  '- <!-- agents-md:managed:unknown key -->' \
  '- <!-- agents-md:managed :done -->' \
  '- <!-- agents-md : managed : done -->' \
  '- <!-- agents-md:managed:*bogus -->' \
  '<!-- agents-md:managed:unknown -- >' \
  '- <!-- agents-md:managed:done -- >' \
  '<!-- agents-md:managed:done' \
  'agents-md:managed:done -- >' \
  '<!-- agents-md managed:unknown -->' \
  '<!-- agents-md::managed:done -->' \
  '- <!-- agents-md project:done-checks -->' \
  '<!-- agents-md    managed:unknown -->' \
  '<!-- agents-md :::  managed : done -->'; do
  mutate "t += '''$bad''' + '\n'"
  run_output_case "marker text rejected: $bad" 1 'marker error' "$work/mutated.md"
done

# The negative half of the same rule: the documented wildcard is how
# prose refers to markers (both namespaces), and a mention with no
# closing arrow is prose too. Widening the scan must not swallow these,
# or every downstream AGENTS.md documenting its own setup fails.
for good in \
  'its `<!-- agents-md:managed:* -->` blocks are managed' \
  'a nested `<!-- agents-md:project:* -->` sub-block' \
  'outside `agents-md:managed:*` blocks, so syncs skip it' \
  'the `agents-md:project:done-checks` block inside `done`' \
  'see agents-md:managed:done in the setup docs' \
  '<!-- See docs/agents-md.md for managed conventions. -->' \
  '<!-- agents-md is generated; see the managed project docs -->' \
  '<!-- agents-md, managed by the platform team -->'; do
  mutate "t += '''$good''' + '\n'"
  run_output_case "prose mention accepted: $good" 0 '^ok: done$' "$work/mutated.md"
done

# --- nested-block structure ---
mutate "t = t.replace('$NO\n', '').replace('$NC\n', '')"
run_case 'nested pair missing, done present' 1 "$work/mutated.md"

# Every nested configuration other than one correctly ordered pair is
# malformed, not a variant of the opt-out: a half pair or a reversed one
# would otherwise reach adoption and be "fixed" by adding a second pair.
mutate "t = t.replace('$NC\n', '', 1)"
run_output_case 'lone nested opener, done present' 1 'exactly once' "$work/mutated.md"

mutate "t = t.replace('$NO\n', '', 1)"
run_output_case 'lone nested closer, done present' 1 'exactly once' "$work/mutated.md"

mutate "t = t.replace('$NO', '@@T@@', 1).replace('$NC', '$NO', 1).replace('@@T@@', '$NC', 1)"
run_output_case 'inverted nested pair, done present' 1 'precedes open' "$work/mutated.md"

mutate "import re; m = re.search(r'(?s)($(printf "$O" done)\n)(.*?)($NO.*?$NC\n)(.*?)($(printf "$C" done))', t); t = t[:m.start()] + m.group(1) + m.group(3) + m.group(2) + m.group(4) + m.group(5) + t[m.end():]"
run_case 'nested pair moved within done' 1 "$work/mutated.md"

# nested pair planted inside another block, done opted out. Assert the
# marker error, not just exit 1: drift alone satisfies the exit code
# while still offering that block for refresh, which would delete the
# enclosed project checks.
mutate "t = t.replace('$(printf "$O" done)\n', '').replace('$(printf "$C" done)\n', ''); t = t.replace('$(printf "$O" branches)\n', '$(printf "$O" branches)\n$NO\nHIDDEN\n$NC\n', 1)"
run_output_case 'nested pair hides text in another block' 1 'marker error' "$work/mutated.md"

# Same shape without the drift that masked it: the pair alone, inside a
# sibling block, with done opted out. Then the two shapes only an
# interval test catches, where one endpoint sits outside the block.
drop_done="t = t.replace('$(printf "$O" done)\n', '').replace('$(printf "$C" done)\n', ''); t = t.replace('$NO\n', '', 1).replace('$NC\n', '', 1)"
mutate "$drop_done; t = t.replace('$(printf "$C" branches)\n', '$NO\n- check\n$NC\n$(printf "$C" branches)\n', 1)"
run_output_case 'nested pair inside a sibling block' 1 'overlaps the managed:branches' "$work/mutated.md"

mutate "$drop_done; t = t.replace('$(printf "$O" branches)\n', '$NO\n$(printf "$O" branches)\n', 1).replace('$(printf "$C" branches)\n', '$NC\n$(printf "$C" branches)\n', 1)"
run_output_case 'nested pair straddles a sibling opener' 1 'overlaps the managed:branches' "$work/mutated.md"

mutate "$drop_done; t = t.replace('$(printf "$O" branches)\n', '$NO\n$(printf "$O" branches)\n', 1).replace('$(printf "$C" branches)\n', '$(printf "$C" branches)\n$NC\n', 1)"
run_output_case 'nested pair envelops a sibling block' 1 'overlaps the managed:branches' "$work/mutated.md"

# The same three shapes with done opted out: pair count and order don't
# depend on the done block, or re-adopting done later would inherit a
# half pair that the earlier run reported as clean.
optout="t = t.replace('$(printf "$O" done)\n', '').replace('$(printf "$C" done)\n', '')"
mutate "$optout; t = t.replace('$NC\n', '', 1)"
run_output_case 'lone nested opener, done opted out' 1 'exactly once' "$work/mutated.md"

mutate "$optout; t = t.replace('$NO\n', '', 1)"
run_output_case 'lone nested closer, done opted out' 1 'exactly once' "$work/mutated.md"

mutate "$optout; t = t.replace('$NO', '@@T@@', 1).replace('$NC', '$NO', 1).replace('@@T@@', '$NC', 1)"
run_output_case 'inverted nested pair, done opted out' 1 'precedes open' "$work/mutated.md"

# --- block boundaries ---
# Per-key pairing passes on crossing or nested blocks (each key still
# opens once and closes once, in order), so disjointness is its own
# check: extraction would otherwise pull the inner marker into the outer
# block and a refresh would delete it.
mutate "t = t.replace('$(printf "$C" branches)\n', '', 1).replace('$(printf "$C" commits)\n', '$(printf "$C" branches)\n$(printf "$C" commits)\n', 1)"
run_output_case 'crossing managed blocks' 1 'blocks overlap' "$work/mutated.md"

mutate "t = t.replace('$(printf "$O" commits)\n', '', 1).replace('$(printf "$C" branches)\n', '$(printf "$O" commits)\n$(printf "$C" branches)\n', 1)"
run_output_case 'nested managed blocks' 1 'blocks overlap' "$work/mutated.md"

echo "passed $((total - fails)) / $total"
exit "$([ "$fails" -eq 0 ] && echo 0 || echo 1)"
