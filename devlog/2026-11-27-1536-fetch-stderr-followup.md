# Fetch Stderr Follow-Up

`list-ready.sh`, `landed-since.sh`, and `merge-cleanup.sh` now retry a
transient git fetch, fail a permanent one at once, and quote git's error in
the `LOOKUP_FAILED` result's `stderr` key, as `land.sh` does since #501
(#504). Before, these six fetches sent stderr to `/dev/null` and failed on the
first error, so a lander or cleanup caller fell back to a blind rerun.

## Choices

- **Copy the helpers over a shared sourced file.** `list-ready.sh` and
  `landed-since.sh` carry `land.sh`'s `git_fetch` and
  `git_fetch_err_permanent` verbatim, as they already carry `gh_read`. Each
  script stays runnable alone from its skill directory, and a sourced file
  would add a path-resolution step to every entry point. The cost is keeping
  three copies identical; a change to one must reach the others.
- **Give merge-cleanup its own helper.** Its fetches go through
  `git_pinned_url`, and it has no `GH_ERR`, so `git_fetch_pinned` wraps the
  pinned call with the same retry, trace drop, and userinfo strip, writing to
  its own `FETCH_ERR` file.
- **Add `stderr` to merge-cleanup's ledger, after `detail`.** It appears only
  on a `LOOKUP_FAILED` whose last fetch failed. Every other key, label, and
  exit code is unchanged, so existing readers keep working. A successful
  fetch empties `FETCH_ERR`, and every failed fetch ends the run through
  `lookup_failed`, so no excerpt can attach to a later, unrelated failure.
- **Map a vanished lock ref to the race, not a missing branch.** When the lock
  is released between `list-ready.sh`'s `ls-remote` and its fetch, git says
  `couldn't find remote ref`. That text in `stderr` would tell the lander to
  end the batch. The script instead drops the text and reports the existing
  "moved while it was read; list again" detail, which the lander reruns.
- **Strip to the last `@` in a token, not the first `/`.** See the first
  finding below. This changed `land.sh` too, because it had the same regex.

## Refute-First Findings

One fresh-context reviewer tried to leak a credential, lose merge-cleanup's
ledger line, attach a stale excerpt, or break bash 3.2.

- **Confirmed: a password with a raw `/` survived the strip.** The old regex
  `(://)[^/[:space:]]*@` stopped at the first `/`. Git 2.54 prints
  `https://x:TOK/EN@host/...` whole in "URL rejected", and
  `url_names_repo` accepts that URL because it reads only the tail. A raw `'`,
  legal in userinfo, broke the reviewer's proposed quote-bounded fix the same
  way. The strip now removes everything from `://` to the last `@` before
  whitespace. A path holding `@` loses its host as well, which hides nothing
  needed. All four suites pin the case.
- **Disproved: a stale excerpt in merge-cleanup.** Every caller of
  `git_fetch_pinned` exits through `lookup_failed` on failure, and a test fakes
  a successful fetch that writes stderr, then fails a later `ls-remote`.
- **Disproved: the lock mapping hiding an auth failure.** It applies only to
  the lock fetch, and git's auth messages never contain
  `couldn't find remote ref`.
- **Disproved: ledger loss or invalid JSON.** The excerpt goes through the
  byte-wise `json_escape`, as a `printf` argument. An `exit` inside the fetch
  subshell doesn't fire the parent's EXIT trap on bash 3.2.57 or 5.3.
- **Disproved: bash 3.2 or `set -u` breakage.** All three suites pass under
  `/bin/bash` 3.2.57, including the sourced run with `BASHPID` unset.
- **Allowed: `url-pin` now reports as `base-fetch` or `prune`.**
  `git_pinned_url`'s rare `lookup_failed url-pin` now runs inside the fetch
  subshell, so its line goes to `/dev/null` and the caller reports a failed
  fetch after the retries. Before, the same condition exited with no ledger at
  all.
- **Allowed: a transient fetch failure now proceeds to deletion.** A retry that
  succeeds continues the cleanup, which matches what a rerun would do; every
  deletion keeps its lease and guards.

## Revisit When

- Git prints a credential outside a URL's userinfo, or in a token the
  whitespace-bounded strip can't reach.
- A fourth script needs the fetch helper; at that point a shared sourced file
  may cost less than keeping the copies identical.
