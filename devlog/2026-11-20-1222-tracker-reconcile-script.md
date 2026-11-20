# Script Merge-Cleanup's Tracker Reconciliation

Issue #461 adds `skills/merge-cleanup/tracker-reconcile.sh`, which runs the
shared-format tracker reconciliation from the agent's plan file and writes
the trace from what it observed. A 14-PR landing batch had the agent write
this glue as a scratch driver, which broke on macOS bash 3.2 mid-batch.

## Decisions

- **Chose `--base <branch>` over a `--pr` flag.** The trace records only
  base-tip observations. A PR lookup would add a read that no trace row
  records, and the agent already knows the base branch.
- **Chose a tracker convention in the item name over a mapping flag.** An
  item names its tracker as `#N` or `#N/ID`, with an optional `:label` so one
  tracker can carry a write item and a report item. The plan file stays the
  single input, in the existing trace grammar, and the ledger needs no change.
- **Stdout is the ledger's output, and exit 1 covers every result short of
  complete.** A caller reads one verdict, and only `RESULT complete` exits 0.
  Exit 2 keeps its ledger meaning: the plan or trace is invalid.
- **Left these plans on the manual path:** a failed or unverifiable policy,
  an `unsupported` item, a tracker in another repository, and a project's
  own Startable now rule (`--edited`). Each needs a judgment the script can't
  observe, such as naming the failed source or editing the startable lines.
  The script refuses them before any forge call and writes no trace.

## Trust Boundary

The script decides what to record, and whether to write the next tracker,
from `tracker-write.sh`'s one stdout line. It accepts the line only when it
is exactly one RESULT line whose values form a combination `tracker-write.sh`
documents for that exit code.

- **Chose recording an untrusted result as an unknown write over a skip.**
  The issue plan suggested `guard unavailable` plus a skip. But a write that
  crashed or printed a malformed line may have reached the forge, and a skip
  would claim it did not. The script records `guard unavailable`, a failed
  attempt, `verify unknown`, and `recheck unverifiable`. The ledger then
  reports the item `UNKNOWN` with the owner action to inspect the edit
  history first.
- **Exits 64 and 69 from `tracker-write.sh` stay a `tooling` skip.** Its
  header documents that neither makes a gh call, so nothing was written.
- **Finished the trace instead of exiting 64 on a write's usage error.** The
  plan suggested exiting 64 without the ledger. Argument checks up front make
  that exit unreachable short of a bug. If it happens, a closed trace with a
  ledger verdict serves the owner better than a half-written one.
- **Every row comes from an observation.** The skeleton validates the plan
  but never feeds the trace. Reason text taken from tool output has tabs and
  carriage returns replaced, so the trace stays parseable.

## Refute-First Findings

A fresh-context reviewer tried to prove the script wrong before the first
commit. It found no path where the real `tracker-write.sh` or
`tracker-refresh.sh` makes the trace claim an unobserved write.

- **Confirmed and fixed: the result parser was looser than documented.** It
  accepted `unverified` with `verify=changed recheck=fresh`, which the ledger
  then reported as completed. `tracker-write.sh` never prints that
  combination, but the parser now accepts only the exact documented
  combinations.
- **Confirmed and fixed: a `--trace` or `--plan` value starting with `-`.**
  The ledger read `-` as stdin and `--help` as its own option, so stdout
  stopped being the ledger's output on the trace. Such a path now gets a
  `./` prefix.
- **Confirmed and fixed: four untested branches.** These are an
  unverifiable observation, tab replacement in a skip reason, a write exit
  64, and a tip move after an untrusted result. Each now has a case, and a
  mutant of each fails the suite.
- **Disproved by checks:** a trace the ledger rejects on any reachable path,
  exit 0 without `RESULT complete`, a write after a stop condition, a skip
  recorded where a write may have run, and argument injection into `gh`
  through the item name, repository, or base branch.

Revisit when `tracker-write.sh`'s RESULT line or exit codes,
`tracker-refresh.sh`'s `OK` status line, or the ledger's grammar changes.
