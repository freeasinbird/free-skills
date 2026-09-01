# Generate the Reconciliation Trace Skeleton

Issue #205 makes merge-cleanup's project obligations visible up front and lets
`reconciliation-ledger.sh` print the trace instead of the agent writing it by
hand.

## Decisions

- Chose a `--skeleton` mode that prints the full happy-path trace from the
  `policy` and `plan` rows over improving the checker's errors to name the
  expected next line. The transcript audit found agents get the event order
  and the guard and recheck input lists wrong on the first try. A generated
  trace removes both error classes, while a better error still leaves the
  agent assembling the trace one rejection at a time.
- Filled every observation slot with its expected value (the policy tip,
  `accepted`, `changed`, `fresh`) rather than a placeholder. Those are the
  values freshness and verification compare against, so the skeleton
  validates as printed and a moved tip or failed write is one deliberate edit
  away from the expected line. Only a skip reason has no expected value, so
  it alone carries an angle-bracket placeholder.
- Kept the plan rows in the existing trace grammar as the skeleton's input
  rather than adding flag syntax for items and inputs. The plan rows are
  already the enumeration the skill requires, and the checker's plan
  validation runs on them unchanged.
- Emitted one write block per item rather than grouping writes that share an
  input set. A per-item block keeps the reread immediately before each
  attempt. An agent that performs an atomic multi-field write merges blocks by
  hand, which the checker already accepts.
- Added the obligation list as its own SKILL.md step before any tracker
  write, stated to the user, with the summary reporting each listed item as
  done, skipped, or blocked. Five audited sessions had the user asking
  afterward whether the tracker was updated.

Revisit when the trace grammar gains an event the skeleton cannot predict from
the plan rows, or when agents submit an unedited skeleton as evidence; the
second would argue for placeholders in every slot.
