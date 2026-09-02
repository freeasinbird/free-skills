# Accepting a local SSH host alias in self-merge's remote identity guard

`self-merge.sh` proves a base or head remote identifies the merged PR's
repository before it fetches, resyncs, or deletes the head branch, by matching
the remote's normalized URL identity against the forge's `clone_url`/`ssh_url`.
A remote written through a local `~/.ssh/config` `Host` alias
(`git@bnw.github.com:owner/name.git`, where the alias sets
`HostName github.com`) failed that match on the alias label and stopped
`remote-repo-mismatch` (#226). That made `check`, `merge`, and `cleanup`
unusable in the aliased-remote layout the forge record (#209, #223, #225)
exists to serve: the record fixes the `gh` calls but not the script's own
remote-identity check.

## Decisions

- **Mirrored merge-cleanup's proven design rather than invent a new one.**
  merge-cleanup solved the identical problem in its own copy on the same
  destructive path (2026-08-21 devlogs, PRs 150/151, both refute-passed).
  Ported `ssh_resolved_endpoint` (resolves the URL's user@host through
  `ssh -G`) and `ssh_alias_resolve` (rewrites the alias URL to its resolved
  endpoint for the identity comparison only) into self-merge, and wired them
  into `resolve_remote` and `remote_repo_check`. The user's own ssh config is
  the same trust domain as the git `insteadOf` rewrites the script already
  honors, so resolving it is consistent, not a new trust grant. Rejected an
  identity-bypass flag: it would weaken the guard for every layout, not just
  the alias it targets.
- **Kept self-merge's name-based transport; pinned only the head endpoint.**
  self-merge runs transports by remote name, not by URL like merge-cleanup, so
  it did not need merge-cleanup's `GIT_CONFIG` `insteadOf` URL-pin machinery.
  Instead `git_with_ssh_pin` sets a command-scoped `GIT_SSH_COMMAND`
  (`ssh -o HostName=... -o User=... -o Port=... -o CanonicalizeHostname=no`)
  on the two destructive head transports (the `ls-remote` OID read and the
  lease-protected delete). A `Match exec` change after identity acceptance
  then cannot reroute the delete. The base fetch and resync stay unpinned:
  they are non-destructive and route through the alias's own ssh config.
  Deliberately did not port merge-cleanup's other later hardening (inline-
  credential stop, push-URL capture, ambiguity stop): those are out of #226's
  scope and self-merge has not received them.
- **Failed closed on every uncertainty.** ssh absent, `ssh -G` error or
  garbage, a non-default resolved port, an option-shaped host/user, an
  ssh-command override active (`GIT_SSH_COMMAND`, `core.sshCommand`, or
  `GIT_SSH`), or a resolved host that names another repository all leave the
  guard on its existing `remote-repo-mismatch` stop. The accept decision always
  re-runs `remote_url_id` on the rewritten URL, so a rewrite can only produce a
  match the normal identity parser already agrees names the same endpoint; the
  owner/name path bytes are carried verbatim, so a different repository cannot
  pass. Under an override the offline `ssh -G` need not name the endpoint Git
  reaches, so the guard refuses to bless a possibly-divergent host.

## Refute-first verification (destructive path)

Eleven scenarios in `scripts/test-self-merge.sh` run behind a git-serving
`ssh` shim (serves both `ssh -G` resolution and the git transport that deletes
over the alias): explicit-alias delete, auto-resolve delete, the pin proof,
wrong-repo stop, non-default-port stop, resolver-failure-after-plausible-output
stop, unsafe-user stop, user-divergent stop, and the three ssh-command override
stops. Each was confirmed discriminating by mutation:

- Neutering `ssh_alias_resolve` (always fail) breaks all three accept
  scenarios (10 assertions), stopping `remote-repo-mismatch` on the explicit
  and pin paths (`remote_repo_check`) and `remote-unresolved` on the
  auto-resolve path (`resolve_remote`), so both code paths are exercised
  independently.
- Neutering the endpoint pin (drop the `GIT_SSH_COMMAND`) makes the
  lease-protected delete route to a rogue mirror at the merged head OID: the
  pin proof then deletes the rogue's copy, keeps the verified branch, and logs
  unpinned transports, so it fails.

Full matrix: 387 to 424 assertions, 0 failures.

Revisit when: a forge issues non-default-port ssh_url endpoints (the port-22
gate would then need widening), `ssh -G` output changes its
`hostname`/`user`/`port` keys, or self-merge adopts merge-cleanup's URL-based
transport (which would let it share the fuller pin machinery instead of the
`GIT_SSH_COMMAND` endpoint pin).
