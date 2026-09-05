#!/usr/bin/env bash
# Execute the shipped snippets, never a copy of their implementation.
set -euo pipefail
cd "$(dirname "$0")/.."
reference=$PWD/skills/prompt-crafter/references/verification.md
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
total=0

extract() {
  local section=$1 source=$2 destination=$3
  awk -v heading="## $section" '
    /^## / { active = ($0 == heading); if (active) sections++ }
    active && /^```sh$/ { fences++; copying = 1; next }
    active && /^```$/ { if (copying) closed++; copying = 0; next }
    active && copying { print; lines++ }
    END { if (sections != 1 || fences != 1 || closed != 1 || !lines) exit 1 }
  ' "$source" >"$destination"
}

for section in 'Core Parity' 'Self-Referential Style Bans'; do
  if ! extract "$section" "$reference" "$work/$section.sh"; then
    echo "FAIL: absent or ambiguous snippet: $section" >&2
    exit 1
  fi
done

# Reject damaged documentation instead of silently running an empty test.
printf '# No snippets\n' >"$work/absent.md"
cat "$reference" "$reference" >"$work/duplicate.md"
for broken in absent duplicate; do
  for section in 'Core Parity' 'Self-Referential Style Bans'; do
    total=$((total + 1))
    if extract "$section" "$work/$broken.md" "$work/discard.sh"; then
      echo "FAIL: extraction accepted $broken $section"
      fails=$((fails + 1))
    fi
  done
done

begin='<!-- BEGIN SHARED CORE -->'
end='<!-- END SHARED CORE -->'
core() { printf '%s\n' "$begin" "${2:-Shared text}" "$end" >"$1"; }

run_case() { # name, snippet section, fixture directory, status, diagnostic
  local name=$1 section=$2 fixture=$3 expected=$4 diagnostic=$5
  local shell context code output actual problem
  local -a command
  for shell in sh bash bash-nullglob; do
    command=("$shell")
    if [ "$shell" = bash-nullglob ]; then command=(bash -O nullglob); fi
    for context in ordinary errexit chain caller; do
      code=$(cat "$work/$section.sh")
      case $context in
        errexit) code=$(printf 'set -e\n%s\nprintf "CONTINUED\\n"\n' "$code") ;;
        chain) code=$(printf '{\n%s\n} && printf "CONTINUED\\n"\n' "$code") ;;
        caller) code=$(printf '%s\nverdict=$?\nprintf "SURVIVED\\n"\nexit "$verdict"\n' "$code") ;;
      esac
      actual=0
      output=$(cd "$fixture" && PATH="$fixture/bin:$PATH" "${command[@]}" -c "$code" 2>&1) || actual=$?
      problem=''
      [ "$actual" -eq "$expected" ] || problem="expected exit $expected, got $actual"
      if [ -n "$diagnostic" ] && ! printf '%s\n' "$output" | grep -Eq "$diagnostic"; then
        problem="$problem; missing diagnostic $diagnostic"
      fi
      if [ "$diagnostic" = 'invalid input|malformed shared core' ] &&
        printf '%s\n' "$output" | grep -q 'core drift'; then
        problem="$problem; invalid input reported as drift"
      fi
      if [ "$context" = caller ]; then
        if ! printf '%s\n' "$output" | grep -qx SURVIVED; then
          problem="$problem; snippet exited its caller"
        fi
      elif [ "$context" != ordinary ]; then
        if [ "$expected" -eq 0 ]; then
          if ! printf '%s\n' "$output" | grep -qx CONTINUED; then
            problem="$problem; success continuation did not run"
          fi
        elif printf '%s\n' "$output" | grep -qx CONTINUED; then
          problem="$problem; failure ran success continuation"
        fi
      fi
      total=$((total + 1))
      if [ -n "$problem" ]; then
        echo "FAIL: $shell/$context/$name ($problem)"
        fails=$((fails + 1))
      fi
    done
  done
}

echo "Platform: $(uname -srm)"
for shell in sh bash; do
  echo "Shell: $shell ($(command -v "$shell"))"
  ls -l "$(command -v "$shell")"
  "$shell" -c 'printf "BASH_VERSION=%s\n" "${BASH_VERSION:-not bash}"'
done
echo "Tools: awk=$(command -v awk), grep=$(command -v grep), sed=$(command -v sed)"
if command -v dpkg-query >/dev/null 2>&1; then
  dpkg-query -W dash bash mawk gawk grep sed 2>/dev/null || :
fi

for name in matching drift missing-both missing-begin missing-end matching-missing-end \
  mixed-invalid-first mixed-invalid-last duplicate-begin duplicate-end repeated-pair \
  same-line-duplicate reversed same-line-pair empty-family read-error awk-error sed-error invalid-before-drift; do
  fixture=$work/$name
  mkdir -p "$fixture/payloads"
  expected=1
  diagnostic='invalid input|malformed shared core'
  case $name in
    matching)
      core "$fixture/payloads/a.md"
      core "$fixture/payloads/b.md"
      printf 'Tool tail\n' >>"$fixture/payloads/b.md"
      expected=0; diagnostic='' ;;
    drift)
      core "$fixture/payloads/a.md"
      core "$fixture/payloads/b.md" 'Different text'
      diagnostic='core drift' ;;
    missing-both) printf 'No markers\n' >"$fixture/payloads/a.md" ;;
    missing-begin) printf '%s\n' 'Shared text' "$end" >"$fixture/payloads/a.md" ;;
    missing-end|matching-missing-end|mixed-invalid-first|mixed-invalid-last)
      printf '%s\n' "$begin" 'Shared text' >"$fixture/payloads/a.md"
      case $name in
        matching-missing-end) cp "$fixture/payloads/a.md" "$fixture/payloads/b.md" ;;
        mixed-invalid-first) core "$fixture/payloads/b.md" ;;
        mixed-invalid-last)
          mv "$fixture/payloads/a.md" "$fixture/payloads/b.md"
          core "$fixture/payloads/a.md" ;;
      esac ;;
    duplicate-begin) printf '%s\n' "$begin" "$begin" "$end" >"$fixture/payloads/a.md" ;;
    duplicate-end) printf '%s\n' "$begin" "$end" "$end" >"$fixture/payloads/a.md" ;;
    repeated-pair) printf '%s\n' "$begin" "$end" "$begin" "$end" >"$fixture/payloads/a.md" ;;
    same-line-duplicate) printf '%s\n' "$begin $begin" "$end" >"$fixture/payloads/a.md" ;;
    reversed) printf '%s\n' "$end" "$begin" >"$fixture/payloads/a.md" ;;
    same-line-pair) printf '%s\n' "$begin $end" >"$fixture/payloads/a.md" ;;
    empty-family) : ;;
    read-error) mkdir "$fixture/payloads/a.md" ;;
    awk-error|sed-error)
      core "$fixture/payloads/a.md"
      mkdir "$fixture/bin"
      printf '#!/bin/sh\nexit 2\n' >"$fixture/bin/${name%-error}"
      chmod +x "$fixture/bin/${name%-error}" ;;
    invalid-before-drift)
      core "$fixture/payloads/a.md"
      core "$fixture/payloads/b.md" 'Different text'
      printf '%s\n' "$begin" >"$fixture/payloads/c.md" ;;
  esac
  run_case "$name" 'Core Parity' "$fixture" "$expected" "$diagnostic"
done

for name in clean prohibited missing directory; do
  fixture=$work/style-$name
  mkdir "$fixture"
  expected=1
  diagnostic=''
  case $name in
    clean) printf 'Plain prose.\n' >"$fixture/payload.md"; expected=0 ;;
    prohibited) printf 'A pause \342\200\224 then more.\n' >"$fixture/payload.md"; diagnostic='1:A pause' ;;
    missing) diagnostic='payload.md.*[Nn]o such file' ;;
    directory) mkdir "$fixture/payload.md"; diagnostic='payload.md.*[Ii]s a directory' ;;
  esac
  run_case "$name" 'Self-Referential Style Bans' "$fixture" "$expected" "$diagnostic"
done

echo "prompt-verification matrix: passed $((total - fails)) / $total"
[ "$fails" -eq 0 ]
