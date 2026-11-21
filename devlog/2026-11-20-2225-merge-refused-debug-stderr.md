# Keep Debug Headers Out of Merge-Refused Stderr

Chose to run `phase_merge`'s `gh pr merge` with `GH_DEBUG=` and
`GODEBUG="$GH_GODEBUG"` directly in `skills/land-approved-prs/land.sh`,
rather than routing it through `gh_read` or stripping headers after the
fact. Issue #316 carries the contract. It closes the follow-up deferred
from #313 (see `devlog/2026-10-18-1831-lookup-failed-stderr.md`).

## Decisions

- **Reuse `GH_DEBUG= GODEBUG="$GH_GODEBUG"`, matching `gh_read` and
  `phase_rerun`.** Setting `GH_DEBUG` empty (not unset) stops `gh` from
  falling back to the legacy `DEBUG` variable, while `GH_GODEBUG` strips
  every comma-separated `http2debug` element and keeps unrelated Go debug
  settings such as `netdns=go`. Filtering stderr after the fact would
  track `gh` and Go trace formats and still risk pushing the real error
  out of the 300-byte excerpt.
- **Keep `gh pr merge` outside `gh_read`.** A merge is a single-attempt
  write, not an idempotent read. Routing it through `gh_read` would apply
  read retries and shared capture truncation to a mutation.
- **Keep `tail -c 300` and `STOP merge-refused` unchanged.** Switching to
  `head -c 300`, altering the JSON shape, or changing `local err`
  handling is outside #316's scope and unnecessary once debug noise is
  suppressed at the source.

## Refute-First Findings

`STOP merge-refused` quotes `gh pr merge`'s stderr tail on stdout, which
batch reports and hand-back comments quote. Each check tried to reach
that output with a secret or bypass the filter.

- **`GH_DEBUG=api`, `GH_DEBUG=1`, and legacy `DEBUG=api` with `GH_DEBUG`
  unset: disproved by a check.** Against real `gh` 2.99.0 targeting a
  non-existent PR, unmitigated `GH_DEBUG=api` and `DEBUG=api` each wrote
  606 stderr lines including 3 authorization-header matches. With
  `GH_DEBUG=`, all three produced only the single GraphQL error line and
  0 debug or authorization matches. `scripts/test-land.sh` covers both
  `GH_DEBUG=api` and `DEBUG=api` with `GH_DEBUG` unset.
- **`GODEBUG` `http2debug` variants (bare, spaced, nested, and alongside
  `netdns=go`): disproved by a check.** Against real `gh` 2.99.0,
  unmitigated `GODEBUG=http2debug=2` wrote 59 stderr lines including an
  unredacted authorization-header trace. Passing `GODEBUG="$GH_GODEBUG"`
  for `http2debug=1`, `http2debug=2`, `netdns=go,http2debug=2`,
  `netdns=go, http2debug=1`, `x=http2debug=2`, and
  `http2debug=2,netdns=go` yielded 1 stderr line and 0 debug or
  authorization matches. `scripts/test-land.sh` verifies all five forms
  and checks that `GH_DEBUG= GODEBUG=netdns=go` reaches `gh pr merge`.
- **Other bare `gh` invocations across `skills/land-approved-prs/`:
  disproved by a check.** Inspecting `land.sh`, `list-ready.sh`, and
  `landed-since.sh` showed every other `gh` invocation already passes
  `GH_DEBUG= GODEBUG="$GH_GODEBUG"` (`gh_read` in all three scripts and
  `phase_rerun` in `land.sh`). Because `phase_land` calls `phase_merge`
  directly, both `land` and `merge` are covered.
- **Succeeding merge under debug settings: disproved by a check.**
  Running `merge` under `GH_DEBUG=api DEBUG=api GODEBUG=netdns=go,http2debug=2`
  in `scripts/test-land.sh` verified `gh pr merge` receives
  `GH_DEBUG= GODEBUG=netdns=go`, so debug traces do not leak to caller
  logs on success either.
- **`GH_TELEMETRY=log` on `gh` 2.99.0: allowed.** Live probing showed
  `GH_TELEMETRY=log` appends a 26-line JSON telemetry payload to stderr
  after the error line. It carries no credentials (0 token or
  authorization matches; only command name, flags, platform metadata,
  and an anonymous `device_id` UUID). Suppressing `GH_TELEMETRY` across
  `gh_read`, `phase_rerun`, and `phase_merge` is outside #316's scope.

## Revisit When

A newer `gh` or Go release adds another stderr debug variable that emits
headers or tokens, or `GH_TELEMETRY=log` truncation of `STOP` details
becomes a practical problem.
