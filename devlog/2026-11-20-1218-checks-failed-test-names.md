# Name Failing Tests in checks-failed

Issue #460: `land.sh`'s `STOP checks-failed` result now names the failing Go
tests for each failed GitHub Actions job. It fetches the job's log and adds
`failing_tests`, `failing_tests_omitted`, or `log_error` to that entry. Log
text from the forge now reaches the engine's result, so this is a
returned-object trust boundary.

## Decisions

- **Chose `gh api --allow-escape-sequences .../actions/jobs/<id>/logs` over
  `gh run view --log-failed`.** In a 14-PR landing batch, `gh run view`
  refused the log because it held terminal escape sequences. The API route
  with the flag worked. SKILL.md now names the API route for a fallback read.
- **Chose a degraded `log_error` over `LOOKUP_FAILED`.** The checks failed
  whatever the log says, and the agent can still read the log itself. A log
  that can't be fetched or holds no Go failure never changes the result type
  or exit code.
- **Chose one POSIX `awk` pass over `jq`.** `land.sh` needs no standalone
  `jq` today, and the parser must run on BSD awk (macOS) and mawk or gawk
  (CI). It reads `go test -json` events first, then plain output in both the
  `-v` and non-`-v` orders.
- **Capped the output.** At most 20 tests per job; each name and failure line
  is cut to 300 bytes. The awk pass keeps at most 4096 escaped bytes of a JSON
  output line, so unescaping stays linear on a huge line. Every log-derived
  string goes through `json_escape`.
- **Kept the log in a file.** `GH_LOG` is created with `GH_ERR` and
  `GH_OUT` and removed by the same EXIT trap, including the trap the rebase
  path installs. A log never enters a shell variable.
- **Decoded only ASCII `\uXXXX` escapes in JSON events.** Go escapes `<`,
  `>`, and `&` this way, so decoding them keeps lines readable. Other code
  points stay as escaped text instead of needing a UTF-8 encoder in awk.

## Refute-First Findings

Each attempt fed a crafted log through the real `json_escape`,
`job_log_fields`, and parser under bash 5 and macOS bash 3.2, then checked
the result with `jq`.

- **Disproved: a log can break the one-line JSON.** Quotes, backslashes,
  control bytes, DEL, high and invalid UTF-8 bytes, NUL, escaped newlines in
  a test name, a cut `\u` escape, and truncated JSON all gave valid JSON.
- **Disproved: a huge log stalls the parser.** A 1 MB failure line, a 1 MB
  JSON output of backslashes, a 1 MB test name, and 100,000 lines each
  parsed in under a second, with values cut to 300 bytes.
- **Disproved: a log fetch changes the result.** A 404 on the log route
  still exits 2 with `STOP checks-failed` and a `log_error`; the matrix
  covers it.
- **Disproved: the log file leaks.** The matrix runs `land` with a scratch
  `TMPDIR` and finds it empty after `STOP checks-failed`.
- **Confirmed and fixed: a passing test's line stuck to a later failure.**
  Pre-push review fed a `-v` log where `TestFoo` logs and passes in one
  package, then fails in another. The parser reported the passing run's
  line. A new `=== RUN` of a name that hasn't failed now drops the kept
  line, and the matrix's `-v` log covers it.
- **Confirmed and fixed: `json_escape` made a full result slow.** It forked
  once per byte, so a job at the caps took tens of seconds in review.
  Printable ASCII now skips the fork. Old and new versions gave identical
  output on every byte 1–255 and 300 random strings under bash 3.2 and 5.
- **Allowed: plain output dedupes a test name across packages.** Plain
  output names the package only after its tests, so two packages failing
  `TestNew` list it once and undercount `failing_tests_omitted`. JSON events
  key by package.
- **Allowed: every failed job's log is fetched.** A failing 30-job matrix
  downloads 30 logs once, at a stop that already ends the landing round.
- **Allowed: a log with CR-only line endings reads as one line.** It loses
  the failure lines but stays valid. GitHub serves logs with LF endings.
- **Allowed: a passing test's `t.Log` line can be the reported line.** The
  first `_test.go:N:` line under a failed test is reported, which may be a
  log call rather than the failing assertion. The agent can read the log.

Revisit when GitHub changes its job-log line prefix, or a project lands Go
tests through a runner such as gotestsum that rewrites go test's output.
