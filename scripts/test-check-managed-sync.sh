#!/usr/bin/env bash
# Validation matrix for scripts/check-managed-sync.sh.
#
# These cases preserve the input-space enumeration that closed PR #154's
# pointer-scan review. Fenced-heading cases also pin the current contract:
# example headings inside code fences are not reference sections.
#
# Exit codes: 0 all cases passed, 1 any failed.
set -u

source_root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0
fail=0

repo() { # repo <slug>: copy the minimal repository surface; echo its root
  local slug=$1 root="$work/$1"
  if [ -e "$root" ]; then
    echo "duplicate fixture slug: $slug" >&2
    exit 1
  fi
  mkdir -p \
    "$root/docs" \
    "$root/scripts" \
    "$root/skills/agent-setup/references" \
    "$root/skills/agent-setup/scripts"
  cp "$source_root/AGENTS.md" "$root/AGENTS.md"
  cp "$source_root/docs/agent-workflow.md" "$root/docs/agent-workflow.md"
  cp "$source_root/scripts/check-managed-sync.sh" "$root/scripts/check-managed-sync.sh"
  cp "$source_root/skills/agent-setup/references/canonical-sections.md" \
    "$root/skills/agent-setup/references/canonical-sections.md"
  cp "$source_root/skills/agent-setup/references/scaffolding.md" \
    "$root/skills/agent-setup/references/scaffolding.md"
  cp "$source_root/skills/agent-setup/scripts/compare-managed-blocks.sh" \
    "$root/skills/agent-setup/scripts/compare-managed-blocks.sh"
  echo "$root"
}

replace_once() { # replace_once <file> <old> <new>
  python3 - "$1" "$2" "$3" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old, new = sys.argv[2:]
text = path.read_text(encoding="utf-8")
if text.count(old) != 1:
    raise SystemExit(f"expected one occurrence in {path}, found {text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
}

setup() { # setup <step> <command...>: abort when a fixture mutation fails
  local step=$1
  shift
  if ! "$@"; then
    echo "fixture setup failed: $step" >&2
    exit 1
  fi
}

both() { # both <root> <old> <new>: keep canonical and AGENTS.md in sync
  local root=$1 old=$2 new=$3
  setup "replace_once canonical-sections.md" replace_once \
    "$root/skills/agent-setup/references/canonical-sections.md" "$old" "$new"
  setup "replace_once AGENTS.md" replace_once "$root/AGENTS.md" "$old" "$new"
}

pair() { # pair <root> <text>: append to the workflow reference and template
  setup "pair $1" python3 - "$1" "$2" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
addition = sys.argv[2].rstrip("\n") + "\n"
reference = root / "docs/agent-workflow.md"
reference.write_text(
    reference.read_text(encoding="utf-8").rstrip("\n") + "\n\n" + addition,
    encoding="utf-8",
)

template = root / "skills/agent-setup/references/scaffolding.md"
lines = template.read_text(encoding="utf-8").splitlines(keepends=True)
closing = next(
    (index for index in range(len(lines) - 1, -1, -1)
     if re.fullmatch(r"`{3,}\n?", lines[index])),
    None,
)
if closing is None:
    raise SystemExit(f"workflow template fence not found in {template}")
lines[closing:closing] = ["\n", addition]
template.write_text("".join(lines), encoding="utf-8")
PY
}

# t <expected-exit> <description> <root> [regex...]: run the copied check and
# assert its exit status plus every output pattern. A leading ! negates one.
t() {
  local expected=$1 desc=$2 root=$3 out status ok pattern
  shift 3
  out=$("$root/scripts/check-managed-sync.sh" 2>&1)
  status=$?
  ok=1
  [ "$status" = "$expected" ] || ok=0
  for pattern in "$@"; do
    case "$pattern" in
      '!'*) grep -qE -- "${pattern#!}" <<<"$out" && ok=0 ;;
      *) grep -qE -- "$pattern" <<<"$out" || ok=0 ;;
    esac
  done
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL ($status != $expected): $desc" >&2
    for pattern in "$@"; do
      echo "  pattern: $pattern" >&2
    done
    printf '%s\n' "$out" | sed 's/^/  | /' >&2
  fi
}

pointer='`docs/agent-workflow.md` §reviewing-a-pr'

root=$(repo clean)
t 0 'unmodified repository passes' "$root" 'ok: pointers \(9 slugs\)'

root=$(repo pointer-suffix)
both "$root" "$pointer" "${pointer}_EXTRA"
t 1 'suffix after a valid pointer slug is rejected' "$root" \
  'pointer target\(s\) that are not §slugs' '!exceed the 20000 budget'

root=$(repo pointer-uppercase)
both "$root" "$pointer" '`docs/agent-workflow.md` §Reviewing-A-PR'
t 1 'uppercase pointer slug is rejected' "$root" \
  'pointer target\(s\) that are not §slugs' '!exceed the 20000 budget'

root=$(repo pointer-mixed-case)
both "$root" "$pointer" '`docs/agent-workflow.md` §reviewing-A-PR'
t 1 'mixed-case pointer slug is rejected' "$root" \
  'pointer target\(s\) that are not §slugs' '!exceed the 20000 budget'

root=$(repo pointer-space)
both "$root" "$pointer" '`docs/agent-workflow.md` § reviewing-a-pr'
t 1 'space after the section sign is rejected' "$root" \
  'pointer mismatch' '!exceed the 20000 budget'

root=$(repo pointer-missing-heading)
both "$root" "$pointer" '`docs/agent-workflow.md` §reviewing-a-prs'
t 1 'valid pointer slug without a heading is rejected' "$root" \
  'pointer mismatch' '!exceed the 20000 budget'

root=$(repo prose-heading)
pair "$root" $'## Merge safety notes\n\nExample text.'
t 1 'prose-titled reference heading is rejected' "$root" \
  'heading\(s\) are not §slugs a pointer can name'

root=$(repo duplicate-heading)
pair "$root" $'## refute-first\n\nRepeated text.'
t 1 'duplicate reference heading is rejected' "$root" \
  'has repeated §slug heading\(s\)'

commit_rule='- **Keep one concern in each commit'

root=$(repo byte-budget)
# Pad beyond the full budget so the fixture holds at any block size.
both "$root" "$commit_rule" \
  "$commit_rule $(head -c 20001 /dev/zero | tr '\0' x)"
t 1 'managed blocks over the byte budget are rejected' "$root" \
  'managed blocks [0-9]+ bytes exceed the 20000 budget'

root=$(repo reference-drift)
printf '\nReference-only drift.\n' >>"$root/docs/agent-workflow.md"
t 1 'reference and template drift is rejected' "$root" \
  'drift: docs/agent-workflow.md differs from .* §agent-workflow'

root=$(repo managed-drift)
setup "replace_once AGENTS.md" replace_once "$root/AGENTS.md" "$commit_rule" \
  '- **Keep one changed concern in each commit'
t 1 'managed-block drift is rejected' "$root" '^drift: commits$'

root=$(repo trailing-punctuation)
both "$root" "$pointer" "${pointer})."
t 0 'sentence punctuation may follow a pointer' "$root" \
  'ok: pointers \(9 slugs\)'

root=$(repo no-space-before-sign)
both "$root" "$pointer" '`docs/agent-workflow.md`§reviewing-a-pr'
t 0 'a pointer needs no space before the section sign' "$root" \
  'ok: pointers \(9 slugs\)'

root=$(repo wrapped-pointer)
both "$root" "$pointer" $'`docs/agent-workflow.md`\n§reviewing-a-pr'
t 0 'a pointer may wrap before the section sign' "$root" \
  'ok: pointers \(9 slugs\)'

root=$(repo tilde-fenced-heading)
pair "$root" $'~~~markdown\n## example-heading\n~~~'
t 0 'a heading inside a tilde fence is ignored' "$root" \
  'ok: pointers \(9 slugs\)'

root=$(repo backtick-fenced-heading)
pair "$root" $'```markdown\n## example-heading\n```'
t 0 'a heading inside a backtick fence is ignored' "$root" \
  'ok: pointers \(9 slugs\)'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
