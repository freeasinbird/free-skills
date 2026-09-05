# Verification Battery

Mechanical checks, run before shipping and cited factually in the result:
what ran, what it showed, gaps as explicit not-run items. Adjust paths and
markers to the host project; the shapes below are the
checks. Run them in POSIX `sh` or Bash with standard shell tools.
Each snippet returns 0 on success and nonzero on failure, including input
errors. To chain a whole snippet, wrap it in `{ ...; } && next_command`.
They also work under `set -e`, which stops the caller on a failed check.

## Core Parity

Require exactly one `BEGIN SHARED CORE` and one `END SHARED CORE` per file,
with BEGIN on an earlier line. Validate every input before comparing cores,
so malformed input isn't reported as drift. Missing files and an empty
family also fail.

Extract the shared block, including marker lines, from every family member
and compare pairwise. Expect identical output; adjust any intentionally
per-tool marker lines before using this check.

```sh
ok=1
inputs=0
for f in payloads/*.md; do
  inputs=$((inputs + 1))
  if [ ! -f "$f" ]; then echo "invalid input: $f"; ok=0; continue; fi
  if ! awk '
    /BEGIN SHARED CORE/ { begin_line = NR }
    /END SHARED CORE/ { end_line = NR }
    {
      begins += gsub(/BEGIN SHARED CORE/, "&")
      ends += gsub(/END SHARED CORE/, "&")
    }
    END { exit !(begins == 1 && ends == 1 && begin_line < end_line) }
  ' "$f"; then
    echo "invalid input (malformed shared core or read error): $f"
    ok=0
  fi
done
[ "$inputs" -gt 0 ] || { echo "invalid input: no payload files"; ok=0; }
if [ "$ok" -eq 1 ]; then
  ref=""
  for f in payloads/*.md; do
    if ! core="$(sed -n '/BEGIN SHARED CORE/,/END SHARED CORE/p' "$f")"; then
      echo "invalid input (read error): $f"; ok=0; continue
    fi
    if [ -z "$ref" ]; then ref="$core"; continue; fi
    [ "$core" = "$ref" ] || { echo "core drift: $f"; ok=0; }
  done
fi
[ "$ok" -eq 1 ]
```

The final test returns 0 for matching valid cores and 1 otherwise.
No shell `exit` closes an interactive caller; the awk `exit` only ends awk.
Keep input files unchanged during validation and comparison.

## Self-Referential Style Bans

Grep each payload for every style it bans in itself; expect zero matches.
Example for a payload that bans em dashes:

```sh
style_status=0
grep -n "$(printf '\342\200\224')" payload.md || style_status=$?
[ "$style_status" -eq 1 ]
```

The octal bytes spell an em dash in both shells without putting one in this
file. Grep returns 1 only after a successful search with no matches.
The final test turns that into success; a match or grep error returns 1.
The guarded grep preserves this behavior under `set -e` and keeps matching
lines and read errors visible.

Enumerate the bans by reading the payload, not from memory; each ban the
payload declares is one grep.

## Budgets

Character count against the platform cap, with real headroom (the cap minus
a trailing newline is not headroom). Set `CAP` to the platform's limit:

```sh
[ "$(wc -m < chat-variant.md)" -le "$CAP" ]
```

## Pointer Payoff

For every "see section X" or equivalent forward reference, open X and
confirm it answers the pointer without contradiction. Judgment, not grep;
list each pointer and its payoff in the report.

## Host Formatter and Linter

Run the host repo's formatter and linter over the payload files. Payloads
ship verbatim, so formatting changes are content changes; a formatter that
rewraps a payload has edited the prompt.

## Read-As-The-Agent Pass

One full read of each payload in its final form, checking that no rule
conflicts with another and no rule addresses the wrong reader. This is
judgment, not grep; it is still required, and it is the pass that catches
what the mechanical checks structurally cannot.

## Report Discipline

Facts only: what ran and what it showed. Every check not run is an explicit
not-run item with the reason. Never "should work".
