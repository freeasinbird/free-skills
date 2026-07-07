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

mutate "t = t.replace('$(printf "$O" done)\n', '').replace('$(printf "$C" done)\n', '')"
run_case 'done opt-out, tolerant' 0 "$work/mutated.md"
run_case 'done opt-out, strict' 1 "$work/mutated.md" --require-all

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

# --- nested-block structure ---
mutate "t = t.replace('$NO\n', '').replace('$NC\n', '')"
run_case 'nested pair missing, done present' 1 "$work/mutated.md"

mutate "import re; m = re.search(r'(?s)($(printf "$O" done)\n)(.*?)($NO.*?$NC\n)(.*?)($(printf "$C" done))', t); t = t[:m.start()] + m.group(1) + m.group(3) + m.group(2) + m.group(4) + m.group(5) + t[m.end():]"
run_case 'nested pair moved within done' 1 "$work/mutated.md"

# nested pair planted inside another block, done opted out
mutate "t = t.replace('$(printf "$O" done)\n', '').replace('$(printf "$C" done)\n', ''); t = t.replace('$(printf "$O" branches)\n', '$(printf "$O" branches)\n$NO\nHIDDEN\n$NC\n', 1)"
run_case 'nested pair hides text in another block' 1 "$work/mutated.md"

echo "passed $((total - fails)) / $total"
exit "$([ "$fails" -eq 0 ] && echo 0 || echo 1)"
