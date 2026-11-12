# Let the Lander Rerun a Classified Flake Once

The lander may now rerun failed CI once per pinned head, after classifying
the failure as infrastructure, a known flake, or a suspected flake, instead
of handing every `checks-failed` back to the owner. Issue #377 carries the
contract. Before this, a known flake cost the owner a manual rerun and a
second approval.

## Why It Is Safe

The rerun changes nothing that decides a merge. `land` still merges only
after every check passes on the exact commit, so a rerun can turn a flake
green but can't turn a real failure into a merge.

## Decisions

- **Classify before rerunning.** A failure in the PR's own paths, or with no
  previous green run of the same check, stays under the rework rule or
  hands back. The path and previous-green conditions keep a regression the PR
  introduced from passing as a flake.
- **One rerun per pinned head, enforced by the engine.** `land.sh rerun`
  stops `rerun-spent` when a failed run that owns a failing check already
  has `run_attempt` above 1. The forge holds the budget, so it survives a lost
  session and doesn't rest on the agent's memory. A rerun the owner made by
  hand spends it too. A rebase onto a new tip gets a fresh budget, because
  the head changes.
- **Rerun only the runs that own a failing latest check.** A commit can
  carry older failed runs that no longer decide CI: a reopened PR, the same
  commit on another branch, or a manual dispatch each add runs. Rerunning
  such a run could turn CI red again, and its attempt count would spend the
  budget for a failure nobody retried. A fresh-context review found this;
  the first draft reran every failed run on the commit.
- **Only GitHub Actions failures.** A failing check from another app, or a
  failing commit status, can't be rerun with `gh run rerun`. Any such
  failure stops `rerun-unsupported` and the PR hands back as before.
  Downstream projects on other CI keep today's behavior.
- **The engine waits, not the agent.** GitHub refuses to rerun a run that is
  still going, and `land` stops `checks-failed` at the first failed check.
  So `rerun` waits under the CI cap for every run on the head to finish, and
  then waits again until the rerun jobs replace the failed check runs. A
  `land` read in that second gap would see the old failure and hand back a
  flake that was never retried. Checked on this repository's rerun of run
  39989472527: rerun jobs get new check-run IDs, and the default
  `filter=latest` listing drops the old failed ones.
- **A rerun counts against the existing three-run bound, and so does the
  `land` after it.** That keeps the longest gap between list calls inside
  the stale-lock age. free-skills' 240-minute age still covers three land
  runs at 45 minutes plus one rerun at up to 60 minutes. If the `land` after
  a rerun went uncounted, the worst case would reach exactly 240 minutes.
- **File an issue when a suspected flake passes.** Without it, flakes get
  absorbed quietly and never show up as a cost.
- **No debug output on the rerun request.** Its stderr is quoted in
  `STOP rerun-refused`, so it runs with `GH_DEBUG` empty and `http2debug`
  dropped from `GODEBUG`, as the forge reads do. Issue #316 is the same fix
  for the merge call.
- **`nothing-to-rerun` runs `land` again rather than handing back.** It means
  no GitHub Actions job on the head is failing any more, for example after
  someone reran it or after a lost `rerun` session's retry passed. `land` merges only
  on green, so running it is safe; a second `checks-failed` hands back.

## Refute-First Findings

A fresh-context review tried to prove the change wrong.

- **Confirmed and fixed:** the rerun set first came from every failed run on
  the commit (see above); the retry bound didn't say the `land` after a
  rerun counts; the single-command limit didn't cover `rerun`'s two waits;
  and the tests lacked a late-registering rerun and a multi-run rerun.
- **Disproved by checks:** collapsed tab fields (every field before the name
  is non-empty), gojq output under real `gh api`, here-string stdin reaching
  `gh run rerun` (it reads `/dev/null`), debug output reaching the
  `rerun-refused` excerpt (a test sets both debug variables and finds no
  header), and arithmetic on unvalidated run fields.
- **Allowed by decision:** a check that an Actions workflow posts through the
  Checks API has no job link, so it stops `rerun-unsupported` and hands back.
  That fails safe.
- **Unverified:** whether GitHub's "re-run failed jobs" also reruns a
  cancelled matrix sibling. If it doesn't, `rerun` ends `rerun-unconfirmed`
  after the CI cap and the PR hands back.

Revisit when a project needs reruns for CI other than GitHub Actions, or when
flake issues show one rerun is routinely not enough.
