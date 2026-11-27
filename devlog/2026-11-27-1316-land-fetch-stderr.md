# Land Fetch Stderr

`land.sh`'s three git fetches (`head-fetch` in prepare, `base-fetch` in
prepare and land) now retry a transient failure the way forge reads do and
quote git's error in the `LOOKUP_FAILED` result's `stderr` key (#501). Before,
each fetch sent its output to `/dev/null` and failed on the first error, so a
lander couldn't tell a blip from an auth failure that won't clear.

## Choices

- **Reuse `GH_ERR` over a second stderr file.** `lookup_failed` already
  quotes `GH_ERR`, and every reader of it emptied it on success. A fetch that
  writes there and empties it on success keeps one rule: the file holds only
  the most recent failure. A second file would need `lookup_failed` to pick
  between two sources and could quote a stale one.
- **Permanent patterns.** A fetch fails at once when git's stderr names a
  missing branch (`couldn't find remote ref`), a missing or unreadable
  repository (`does not appear to be a git repository`,
  `Repository not found`), or refused credentials (`Authentication failed`,
  `Permission denied`, `could not read Username`, an HTTP 401, 403, or 404).
  Anything else retries, as `gh_read` treats a failure it can't name. A wrong
  miss costs two retries (3 s); a wrong hit fails a blip at once, which was
  the old behavior. The first two patterns were checked against git 2.54; the
  rest come from git's usual messages.
- **Drop trace settings, then strip URL userinfo.** With `GIT_TRACE=1` and
  `GIT_TRACE_REDACT=0`, git 2.54 printed the remote URL's userinfo five times
  on one failed fetch, and `GIT_TRACE_CURL` adds request headers. Each fetch
  runs with every `GIT_TRACE*` variable and `GIT_CURL_VERBOSE` unset,
  mirroring how `gh_read` drops `http2debug` from `GODEBUG`; a redaction pass
  alone would have to know every shape a header line takes. The plan assumed
  git's own messages always hide userinfo. The refute-first pass found two
  that don't (below), so git's stderr also loses every `user:pass@` after a
  `://` before it is kept. Tests pin both layers.

## Refute-First Findings

One fresh-context reviewer tried to make a token reach land.sh's output
through the new path, testing against local HTTP servers on git 2.54.

- **Confirmed: git's redirect error prints userinfo.** When `info/refs`
  redirects to a login page, git prints `asked for:` and `redirect:` lines
  with the URL whole, token included. Reproduced by hand. This overturned the
  plan's assumption that git's messages always anonymize the URL, so the
  helper now strips `user:pass@` after every `://` in git's stderr before
  keeping it. A shim test pins it on both the excerpt and the retry line.
- **Confirmed: a dumb-HTTP failure prints userinfo.** Its
  `Unable to find <sha> under <url>` line carries the URL whole. The same
  strip covers it.
- **Confirmed: a plain HTTP 404 retried.** Git says
  `repository '<url>' not found`, lowercase, which no pattern matched. Added.
- **Covered by the strip: trace2 set in git config.** Unsetting variables
  misses a `trace2.normalTarget` in config. Trace2 logs URLs, not request
  headers, and the strip now removes userinfo from any URL in stderr; request
  headers come only from `GIT_TRACE_CURL`, which is unset.
- **Second round, no blockers.** The reviewer of the fixed revision found the
  strip runs before the 300-byte cut and the classification, so nothing
  straddles the cut. It flagged, unverified, that piping stderr into the
  strip could hang a fetch while an older OpenSSH's ControlPersist master
  held the pipe. Writing stderr to a file and stripping it there costs
  nothing, so the helper does that.
- **Disproved by checks:** the subshell `unset` under bash 3.2 and `set -u`,
  exit-code pass-through, `GH_ERR` emptied on success, and the 401, 403,
  missing-ref, 500, and DNS classifications.

## Revisit When

- Git writes a credential in a form the strip misses, such as a request
  header outside curl tracing or a token outside a URL's userinfo.
- The follow-up for `list-ready.sh`, `landed-since.sh`, and
  `merge-cleanup.sh` lands a shared fetch helper; this one should move there.
