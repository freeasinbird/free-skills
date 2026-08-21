# Pinning the alias-resolved SSH endpoint during remote deletion

Issue #151 revises the PR #150 decision that an accepted SSH alias stays the
transport URL. The alias URL still names every Git transport, so its `Host`
block, identity files, proxy configuration, and key selection remain active.
The revision is that the two destructive-path transports now also receive a
command-scoped `GIT_SSH_COMMAND` pinning `HostName`, `User`, and `Port` to the
effective values that passed the identity guard, with hostname canonicalization
disabled. A changing `Match exec` result can no longer alter those three
endpoint fields after identity acceptance; other trusted alias options remain
live as described below.

## Decision

- **Chose endpoint options over rewriting the URL.** Replacing the alias with
  its resolved hostname would stop the alias `Host` block from matching and
  discard legitimate routing or credentials. The command line still names the
  alias; only the endpoint fields are pinned with OpenSSH `-o` options.
- **Chose strict literals over shell quoting.** Git asks a shell to interpret
  `GIT_SSH_COMMAND`, so every hostname, user, and port read from `ssh -G` must
  match a narrow literal character set before it can enter the command. An
  uncertain value keeps the existing `remote-repo-mismatch` stop.
- **Chose explicit per-call scope over ambient state.** `git_pinned_url`
  receives an SSH command separately for each invocation. Only the head
  `ls-remote` OID read and lease-protected delete receive the alias pin; direct
  endpoints, hostless paths, the direct fork fallback, base fetches, and later
  prunes keep their prior environment.
- **Changed the alias resolver to publish outputs in the current shell.** The
  earlier implementation printed a rewritten URL inside command substitution,
  which meant its `SSH_ALIAS_*` globals existed only in a subshell. Both callers
  now invoke it directly and read explicit URL and pin outputs. This is an
  internal contract change, not a CLI or result-ledger change.

Static `Match exec` detection remains rejected because it cannot reproduce all
state-dependent OpenSSH configuration. Rewriting the transport URL to the bare
resolved hostname remains rejected for the configuration loss above.

## Refute-first verification

The destructive-path pass targeted stale or leaked pins, shell injection,
alias-versus-push URL divergence, direct and hostless fallbacks, and a transport
that changes endpoint after identity acceptance.

- **Confirmed and fixed:** process substitution discarded the exit status from
  `ssh -G`, so plausible fields followed by a nonzero exit could pass the old
  guard. Resolution now captures command output only on success before parsing
  it; a discriminating shim emits valid-looking fields and then fails.
- **Confirmed safe:** resolved fields enter the shell-interpreted command only
  after literal validation; `push_ids_match` still requires one push URL with
  the original alias identity; every remote check clears the active pin; and
  base fetches plus later prunes pass an explicitly empty SSH command.
- **Rejected by verification:** a test SSH transport routes an unpinned,
  lease-protected delete to a rogue bare mirror at the merged head OID. The
  pinned cleanup instead deletes the verified repository branch, preserves the
  rogue copy, and logs both destructive calls with all four endpoint options
  while still naming the alias.
- **Accepted by decision:** a configured `ProxyCommand` can itself ignore the
  pinned `%h`, `%r`, and `%p` values and route elsewhere. Local SSH configuration
  is already the alias trust domain, and statically proving arbitrary proxy
  programs is outside this guard. Existing Git SSH-command overrides continue
  to fail closed because they are a different transport implementation.

Revisit when: Git stops interpreting `GIT_SSH_COMMAND` through a shell, the
supported SSH implementation is no longer OpenSSH-compatible with `-G` and the
four `-o` options, or the project decides local proxy configuration is outside
the trusted alias domain.
