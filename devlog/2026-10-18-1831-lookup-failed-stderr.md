# Quote gh's Error on LOOKUP_FAILED

Chose to add a `stderr` key to every `LOOKUP_FAILED` JSON from the three
land-approved-prs scripts: the first 300 bytes of the failing gh read's
stderr, captured with gh's debug output turned off. Issue #313 carries the
contract. In #307's trial batch, `land` reported `LOOKUP_FAILED check-runs`
with gh's stderr discarded, and the agent had to rerun the read by hand to
learn the failure was transient.

## Decisions

- **A separate key, not text appended to `detail`.** Existing assertions and
  jq readers of `detail` keep working, and a reader can branch on the key's
  presence: no key means the failed read was git's or gh said nothing.
- **Clear `GH_DEBUG` rather than filter header lines.** Under debug, gh
  writes about 200 lines of request and response headers and bodies; a
  filter would have to track that format, and the noise would push the real
  error out of a 300-byte excerpt. `GH_DEBUG` is set empty, not unset: gh
  2.99.0 falls back to the legacy `DEBUG` variable only when `GH_DEBUG` is
  unset. A live check showed `DEBUG=api` alone produces 213 debug lines and
  `DEBUG=api GH_DEBUG=` none.
- **Drop `http2debug` from `GODEBUG`, keep the rest.** Go's http2 trace
  prints the `Authorization` header unredacted. Clearing all of `GODEBUG`
  would also drop settings a caller's gh may need, so only that one goes.
- **`head -c 300`, not the `tail -c 300` the STOP paths use.** gh writes its
  summary line, such as `gh: Not Found (HTTP 404)`, first.
- **Truncate the capture after each successful read.** A warning from a read
  that worked can't attach to a later failure. Each matrix's fake gh writes a
  notice on every successful read, so dropping the truncate fails a case in
  all three. The one tolerated gh failure, land's merge-state poll, keeps its
  stderr on purpose: a cap reached right after a failed poll quotes that
  poll's error, the latest word from the forge.
- **A failed `mktemp` for the capture file is `LOOKUP_FAILED tmp`.** That's
  the name list-ready already used for its scratch directory, so no new
  result name appears; a script that can't make a temp file would fail its
  later steps anyway.
- **git's stderr stays out.** Excerpting git-side failures such as
  `base-fetch` and `lock-read` was a non-goal; the rebase, push, and merge
  STOP paths already carry their own excerpts.

## Refute-First Findings

The change moves gh's stderr onto stdout that batch reports and hand-back
comments quote, so each attempt below tried to make a secret reach it.

- **`GH_DEBUG=api` or `GH_DEBUG=1`: disproved by a check.** Against the real
  forge, `landed-since.sh --pr 999999` printed the same one-line GraphQL
  error with and without either value. Each matrix proves a header line its
  fake gh prints under debug never reaches the output.
- **Legacy `DEBUG=api` with `GH_DEBUG` unset: disproved by a check.** Same
  live result; test-land.sh covers it with a case that unsets `GH_DEBUG`.
- **A bad `GH_TOKEN`, alone and with debug on: disproved by a check.** The
  excerpt was `gh: Bad credentials (HTTP 401)`; the token value never
  appeared.
- **No credentials at all: disproved by a check.** gh's message names the
  `GH_TOKEN` variable, not a value.
- **Response bodies: disproved by a check.** `gh api` writes an error's
  body to stdout, which the scripts already capture and discard; only the
  summary line reaches stderr.
- **`GODEBUG=http2debug=2`: confirmed, then fixed.** A fresh-context
  reviewer found Go's http2 trace writes the token unredacted; the 300-byte
  cut happened to exclude it. After the fix, live runs with that setting
  alone and beside another setting show no trace line, and test-land.sh
  covers it.
- **A stale excerpt on a git or `mktemp` failure: disproved by a check.**
  Every failed read but land's merge poll ends in `lookup_failed` at once,
  and the matrices fail when the truncate is removed.
- **EXIT traps losing the capture file: disproved by review.** land and
  list-ready each replace the startup trap once, and both replacements still
  remove it.
- **The SAML SSO URL: allowed.** gh prints an authorization URL built from
  the `X-GitHub-SSO` response header on a SAML 403. It names an
  authorization request the token's owner completes while signed in, not a
  credential.
- **A UTF-8 sequence split by the cut: allowed.** list-ready and
  landed-since pass high bytes through, so a cut can leave a partial
  character. gh's error text is ASCII, and jq, the documented reader,
  accepts the line; land escapes every high byte and stays valid.
- **A stale merge-poll excerpt misread as transient: allowed.** It can't
  cause more than the one rerun the SKILL already allows for any lookup
  failure.
- **`gh pr merge` under an ambient `GH_DEBUG`: deferred.** Its stderr tail
  feeds `STOP merge-refused`, which predates this change, and STOP output is
  a non-goal here. Follow-up: #316.

## Revisit When

gh changes its stderr format or debug variables, or a matrix shows a
response body crowding the summary line out of the excerpt.
