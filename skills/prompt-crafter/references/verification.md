# Verification Battery

Mechanical checks, run before shipping and cited factually in the result:
what ran, what it showed, gaps as explicit not-run items. Adjust paths and
markers to the host project; the shapes below are the
checks. Each snippet's exit status is its verdict (nonzero on failure),
so the checks compose under `set -e`, `&&` chains, and agents that key
off status.

## Core Parity

Extract the shared block from every family member and diff pairwise; expect
identical output (excluding any intentionally per-tool marker line). An
empty extraction is itself a failure: it means the file has no shared core,
not that it matches.

```sh
ok=1
ref=""
for f in payloads/*.md; do
  core="$(sed -n '/BEGIN SHARED CORE/,/END SHARED CORE/p' "$f")"
  if [ -z "$core" ]; then echo "missing shared core: $f"; ok=0; continue; fi
  if [ -z "$ref" ]; then ref="$core"; continue; fi
  [ "$core" = "$ref" ] || { echo "core drift: $f"; ok=0; }
done
[ "$ok" -eq 1 ]
```

The final test makes the block's exit status the verdict, without an
`exit` that would close an interactive shell.

## Self-Referential Style Bans

Grep each payload for every style it bans in itself; expect zero matches.
Example for a payload that bans em dashes:

```sh
! grep -n "$(printf '\xe2\x80\x94')" payload.md   # em dash; exits 0 when clean
```

(The pattern is spelled in bytes so this file passes its own check.)

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
