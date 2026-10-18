# Land Approved PRs Under a Forge Lock

Chose a skill, `land-approved-prs`, that lands every PR the owner labeled
`approved`, one at a time under a lock ref on the forge, over giving
self-merge a batch mode. Issue #307 carries the contract and the owner's
decisions. This note records why the shape holds, what the live forge showed,
and where the implementation departs from the plan.

## Decisions

- **Self-merge retired, not folded in.** Approving a PR and landing it are
  different acts. Self-merge let one agent do both for one PR; this skill
  lands a batch and must never be something an agent grants itself. Its
  engine survives as `skills/land-approved-prs/land.sh`, moved in a
  mechanical commit listed in `.git-blame-ignore-revs`, with its matrix
  unchanged apart from names (469 cases before and after).
- **The lock is a ref on the forge, `refs/land/lock`.** It points at an
  orphan commit with an empty tree whose message names the run, host, and
  PR; the committer date is the heartbeat. Rejected: a file under `.git/`,
  which one machine can't see from another, and a branch, which runs
  workflows, meets branch protection, and can be auto-deleted.
- **The lease's job is the gap between read and push.** A live probe on
  GitHub showed that acquire with a lease on absence fails when the ref
  exists. A heartbeat or release with a lease on a stale OID also fails. The
  server compares against the value the push advertises, so a race at the
  push itself is always caught. What the lease adds is catching a change
  between the script's `ls-remote` and its push; the matrix injects one
  there, at the PR list call, because a race injected in a pre-push hook is
  caught even under `--force` and can't tell the two apart.
- **The label is the approval signal here.** GitHub won't let the owner
  approve a PR their own account opened, and agents open PRs under that
  account. The record names the approver, and only that login's `labeled`
  event counts.
- **Filter 4 comes from push evidence.** On PR 308 the Actions runs API
  returned an empty `pull_requests` array, so runs are matched by head branch
  and kept only when created at or after the PR, which drops runs from an
  earlier PR on a reused branch name. Force-push timeline events carry only
  the after commit. The approval-time head is the newest of those two kinds
  of evidence at or before the approval.
- **Filter 6 reads the reviewer's summary comment.** The completion marker
  comment lists rounds; a `Completed` row whose short SHA prefixes the
  current head ends the round, matching the reviewer record.
- **The record is read from the default branch's tip.** A PR can't relax the
  rules it is judged by. The consequence is that a project's first batch
  runs only after its landing record has merged.
- **No prose fallback.** Without a shell, git, and an authenticated forge
  CLI the skill stops and hands the batch to the owner. A prose copy of the
  lock and filters would drift, as prose copies of the merge sequence did
  (`devlog/2026-07-26-1047-merge-cleanup-imported-guards.md`).
- **The approval freeze exempts the lander.** The handoff rule tells every
  other session to stop pushing once a PR is approved. The batch still
  rebases and reworks, and records each push so filter 4 accepts it. A
  freeze that bound the lander too would contradict the skill.
- **A checkout fault ends the batch; it doesn't hand back PRs.** Stops such
  as `wrong-checkout` or a dirty primary checkout say nothing about the PR.
  Handing each PR back for them would label the whole batch `needs-human`
  one PR at a time. The batch releases the lock and reports instead.

## Departures From the Plan

- **Two record keys added: Reviewer and Reviewer completion marker.** Filter
  6 needs the reviewer's login and marker, and the reviewer record is prose
  the script can't parse reliably. Reviewer has no default; a project
  without one writes `none`, so a typo can't turn filter 6 off.
- **`--pushed` only records and heartbeats.** It never lists, so a call made
  mid-PR can't release the lock on an empty list while `land` still runs.
- **`--pushed` takes the PR it pushed to, with `--pr`.** Codex found that
  a log of bare OIDs let another approved PR, force-pushed to the same
  commit, pass filter 4 without re-approval. Each entry now pairs the PR
  number with the OID, and only that PR's entries count.
- **The first head is unknown when a force-push precedes the earliest CI
  run.** The plan took the earliest force-push's commit as a fallback, but
  that is the head after the push; its merge base can be later than the
  original one and skip exactly the commits the read exists for.
- **Both scripts take `--base-remote`**, matching `land.sh`, to pick among
  several remotes that name the repository. Unlike `land.sh`, they refuse
  any override whose URL does not name it, even a local path: a fork's or
  mirror's lock would not exclude another lander, and its record could
  name another approver. `list-ready.sh` checks every push URL too, since
  it writes the lock there. Rejected: matching the forge host, which would
  refuse SSH host aliases such as this repository's own remote; `land.sh`
  resolves those before it pushes or merges.
- **`landed-since.sh` stops when the record can't be read.** A tip without
  `AGENTS.md`, without a record, or without a Base-advance checks bullet
  stops rather than run no checks, the same no-default rule as Reviewer.
- **The renamed test override is `LAND_SCRIPT`**, after
  `SELF_MERGE_SCRIPT`, so the variable says what it points at.

## Refute-First Findings

A fresh-context reviewer tried to prove the scripts and the skill wrong, with
fixture experiments and mutations.

- **Confirmed: a fork's CI run could stand in as the approved head.** Runs
  were matched by branch name only, so a fork's PR from a same-named branch
  could set the approval-time head, and a later fast-forward to that commit
  passed filter 4. Both scripts now keep only runs whose head repository is
  this one.
- **Confirmed: the skill never tied `land` to the listed head.** A push
  between the list and `check` would have been refreshed into and landed.
  The skill now pins the list's `head_oid`, or the last `--pushed` OID,
  lists again when `check` reports another head, and leases rework pushes
  on the pinned head.
- **Confirmed: record mistakes silently dropped filter 6.** A missing,
  unbackticked, or cut-off Reviewer bullet read as `none`. Reviewer is now
  required, and a Stale lock age bullet without a backticked value stops
  instead of defaulting.
- **Confirmed: a user account under the reviewer's bare login passed filter 6.** Only a bot account's summary counts now; the live summary on PR 308
  reports `type` Bot.
- **Confirmed: a backticked `none` ran as a command** in the Base-advance
  bullet. It now means none, and the skill says every other backticked span
  on that bullet is a command.
- **Confirmed, minor: UTF-8 branch names were escaped byte by byte**, and a
  repeated `--order` entry listed its PR twice. Both fixed and tested.
- **Fixed in the skill, not the script: two sessions sharing a run id both
  hold the lock.** The suggested id now carries a random suffix. Rejected:
  also matching the lock's host, because a macOS host name can change with
  the network mid-batch and would lock a live run out of its own lock.
- **Allowed: approval and evidence in the same second count as before
  approval.** Exploiting it means timing a push to the label's second; a
  strict comparison would buy nothing at this scale.
- **Allowed: a run whose lock the owner released re-acquires it on its next
  list.** The owner releases only after confirming the run is gone, and a
  second lander's lock would refuse it.
- **Allowed: two guards stay untested.** The exact-line push-log match can't
  differ from a prefix match, because `--pushed` takes only full OIDs. The
  moved-while-read check needs a race between two git calls inside one read
  and fails closed as a lookup failure.
- **Disproved:** acquire, heartbeat, and release overwriting a racer (each
  mutation fails the matrix), a re-added label by another actor counting,
  null timeline fields passing, and a working-tree record weakening the
  rules.

## Revisit when

- Manual batches have worked several times: add the scheduled start.
- A lander dies mid-wait more than rarely: automatic stale-lock takeover
  needs a heartbeat during `land`'s waits and a way to stop the old run's
  `land` from merging.
- Removing `approved` during a `land` wait needs to stop that merge: add a
  pre-merge label check to the engine.
- A project wants the review or auto-merge mechanism: each needs its own
  contract before `list-ready.sh` accepts it.
