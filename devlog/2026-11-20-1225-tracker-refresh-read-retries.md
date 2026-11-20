# Retry Transient Forge Reads in tracker-refresh.sh

Chose to retry each transient forge read inside merge-cleanup's
`tracker-refresh.sh` with #352's helper, so only a failure that persists or
isn't transient reaches `LOOKUP_FAILED`. Issue #462 carries the contract. A
landing batch ended one tracker reconciliation `RESULT incomplete` on one
dropped issue read, and an identical rerun seconds later completed.

## Decisions

- **Copy the helper instead of sharing a file.** Each skill installs on its
  own, so merge-cleanup can't depend on land-approved-prs. The copy keeps
  #352's classification, bound, and backoff, and the 2026-10-23 note's
  reasons still hold. Rejected: a shared library under `scripts/`, which an
  installed skill can't reach. A comment in the copy names its source,
  `landed-since.sh`, so a change there can be carried here.
- **Retry lines name the read by its `LOOKUP_FAILED` label and never quote
  gh's stderr.** `tracker-refresh.sh` never printed gh's stderr, and its
  `LOOKUP_FAILED` line carries no excerpt. Quoting it in the retry line would
  open the credential surface #313 hardened in the landing scripts for no
  diagnostic gain the agent needs. `GH_ERR` is kept only to classify the
  failure.
- **The status line stays last on stderr; `tracker-write.sh` reads the last
  line.** A recovered read logs its retry before the status line, so
  `tracker-write.sh`'s first-line read would refuse a good refresh.
  Rejected: holding retry lines until the end, which would put them after
  the status line and break the agents' contract that the status ends the
  output. `tracker-refresh.sh` prints nothing to stderr after its `OK`,
  `STOP`, or `LOOKUP_FAILED` line on any path, so the last line is the
  status.
- **Only the refresh's reads retry.** `tracker-write.sh`'s guard reads and
  its write keep one attempt: a failed guard read already refuses the write,
  and a retried write could double-apply. `merge-cleanup.sh` reads inline and
  shares no helper, so it stays out.

## Refute-First Findings

`tracker-write.sh` performs the destructive whole-body overwrite, and the
refresh now captures gh's stderr, so each attempt below tried to make the
change unsafe.

- **A debug header in output under `GH_DEBUG=api`, legacy `DEBUG=1` with
  `GH_DEBUG` unset, or a spaced or leading `http2debug` in `GODEBUG`:
  disproved by a check.** The refresh suite runs a retried read under each
  setting; its fake gh prints a fake token whenever debug output would be on,
  and sees `GH_DEBUG` empty and `http2debug` dropped on every call. The token
  never reaches stdout or stderr.
- **`tracker-write.sh` accepting a refresh that failed after an earlier `OK`
  line: disproved by a check.** A non-zero exit is refused before the status
  line is read. The write suite runs a refresh stub that prints `OK` and then
  a later `STOP` line with exit 0, and the write refuses it. Against `main`'s
  first-line read, that case writes, and the retry-logged case is refused.
- **A failed attempt's partial stdout untested: confirmed, then fixed.** A
  fresh-context reviewer found the suite's fake gh printed nothing to stdout
  on failure, so a helper without the `GH_OUT` buffer passed. The fake gh now
  prints a partial line before it fails, and that mutant fails 22 checks.
- **Eval 29 (`29-tracker-refresh-failure`): unaffected.** Its fake gh answers
  the missing unit with `GraphQL: Could not resolve to ...`, which stays
  permanent: a run against its fixture reads #11 once and prints the same
  `LOOKUP_FAILED issue acme/repo#11` line.

Revisit when gh rewords a permanent failure, since the landing scripts' copy
and this one classify by its text.
