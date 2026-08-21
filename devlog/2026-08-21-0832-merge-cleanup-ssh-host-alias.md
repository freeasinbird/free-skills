# Allowing local SSH host aliases in the merge-cleanup identity guard

`merge-cleanup.sh` proves a remote identifies the merged PR's repository
before it deletes the head branch, by matching the remote's normalized
URL identity against the forge's authoritative `clone_url`/`ssh_url`.
A remote written through a local `~/.ssh/config` `Host` alias
(`git@bnw.github.com:owner/name.git`, where the alias sets
`HostName github.com`) failed that match on the alias label and stopped
`remote-repo-mismatch`, a false positive: the alias names the same
endpoint. Git resolves the alias at connect time; the guard did not.

## Decision

- **Resolve the alias through `ssh -G` and re-match, rather than add an
  identity-bypass flag.** `ssh -G -- <user@host>` expands the effective
  ssh config offline (no connection) to the real hostname/user/port Git
  will reach. The URL's user is passed into the resolution because
  `~/.ssh/config` can expand a different HostName/port per remote user
  (`Match user`, `%r` in HostName); resolving a bare host could bless a
  userless endpoint while the delete routes through the user-qualified
  one (Codex P1 on PR 150). When the raw URL fails the identity match,
  both guards (`resolve_remote` candidate selection and
  `remote_repo_check` identity proof) rewrite the host to that resolved
  endpoint and compare again.
  The user's own ssh config is the same trust domain as the git
  `insteadOf` rewrites the script already honors, so resolving it is
  consistent, not a new trust grant. A bypass flag, by contrast, would
  weaken the guard for every layout, not just the alias it targets.
- **The rewrite feeds the identity check only; transport keeps the alias
  URL.** `CHECKED_REMOTE_URL` (the fetch/push URL) and
  `CHECKED_REMOTE_ID` (the push-target equality key) stay the original
  alias values. The delete therefore still routes through the alias so
  the user's ssh key selection and routing apply; the resolved
  github.com URL is never used for a git transport. This is the property
  the refute pass most wanted to break (see below).
- **Fail closed on every uncertainty.** ssh absent, `ssh -G` error,
  empty/garbage output, a non-default resolved port, an option-shaped
  host, or a host ssh config does not actually rewrite all leave the
  guard on its existing mismatch. The accept decision always re-runs
  `url_id`/`remote_url_id` on the rewritten string, so the rewrite can
  only ever produce a match that the normal identity parser already
  agrees names the same endpoint bytes; owner/name path bytes are
  carried verbatim, so a different repository cannot pass.
- **Fail closed under a Git ssh-command override.** Git honors
  `GIT_SSH_COMMAND` (env), then `core.sshCommand` (config), else
  `GIT_SSH` (env) for the fetch/ls-remote/push transport, but the guard
  queries the plain `ssh` on PATH, so under an override the offline
  `ssh -G` need not name the endpoint Git reaches (a second Codex P1 on
  PR 150). The class both P1s belong to: the guard's offline resolution
  must reproduce Git's actual SSH invocation, which is parameterized by
  the URL's user (P1 #1) and by Git's configured ssh command (P1 #2).
  Reproducing an arbitrary override command with `-G` injected is fragile
  (the override may not be OpenSSH or support `-G`), so the guard fails
  closed when any override is set, consistent with the existing
  fail-closed stance. The stopped intersection (an alias needing
  resolution while an override is active) is narrow and errs safe; a
  non-alias remote never calls the resolver.

## Refute-first verification (destructive path)

A fresh-context reviewer was tasked to disprove the guard's safety
across injection, wrong-repo acceptance, transport routing, port/user
logic, parser divergence, and fail-open. **No blocking findings.**

- **Confirmed safe (rejected as non-issues):** command/option injection
  (quoted argv exec, no `eval`; option-shaped host refused before `--`);
  wrong-repo acceptance (verdict re-parses the rewritten URL with
  `url_id`; only the authority is swapped, path bytes verbatim);
  fetch/push routing (transport uses the original alias URL via
  `VALIDATED_PUSH_URL`/`CHECKED_REMOTE_URL`, never the rewrite);
  port/user (non-22 rejected; userless alias resolves to the login user
  and correctly fails to match `git@`); parser divergence (host
  extraction matches `url_id`'s; a URL `url_id` rejects cannot be
  massaged into an accept); fail-open (all error paths fall through to
  the `stop`).
- **Accepted by decision:** none outstanding.

## Tests

`scripts/test-merge-cleanup.sh` gains eight scenarios behind a
git-serving `ssh` shim (serves both `ssh -G` identity resolution and the
git transport that deletes over the alias): explicit-alias end-to-end
delete, auto-resolve-as-head end-to-end delete, wrong-owner-still-stops,
non-default-port-still-stops, a user-divergent config that stops, and
`GIT_SSH_COMMAND`/`core.sshCommand`/`GIT_SSH` override stops. Each of the
last four stop-cases was confirmed discriminating: neutering the matching
guard deletes the branch through the unverified endpoint.
Both positives were confirmed discriminating: neutering
`ssh_alias_resolve` makes the explicit case stop `remote-repo-mismatch`
(the `remote_repo_check` path) and the auto-resolve case stop
`remote-unresolved` (the `resolve_remote` path), so the two code paths
are exercised independently. The user-divergent case (shim resolves the
bare host to the forge but `git@host` to a rogue host) was confirmed
discriminating too: neutering the user pass deletes the branch through
the rogue endpoint, so it must stop.

Revisit when: a forge issues non-default-port ssh_url endpoints (the
port-22 gate would then need widening to the forge's actual port), or
`ssh -G` output format changes its `hostname`/`user`/`port` keys.
