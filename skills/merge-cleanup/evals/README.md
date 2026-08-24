# merge-cleanup evals

Eval definitions for the skill-creator loop. Only the definitions live in the
repo; run outputs, fixture repositories, CLI stubs, and grading artifacts
belong in a scratch workspace outside the repo.

## Files

- `evals.json`: twenty-eight task evals for project-specific post-merge
  obligations.
  1. `no-obligations-record`: preserves generic cleanup and its summary.
  2. `freeside-style-tracker-refresh`: reconciles typed tracker lists.
  3. `multiple-containing-trackers`: updates every known container only.
  4. `unreadable-instruction-source`: reports required-source failure.
  5. `ambiguous-dependencies`: leaves unclear relations to the owner.
  6. `tracker-mutation-failure-after-git-cleanup`: preserves git results and
     reports the failed external mutation separately.
  7. `duplicate-obligations-records`: rejects competing complete records.
  8. `duplicate-obligations-field`: rejects competing values inside one
     record.
  9. `policy-source-before-base-resync`: reads policy from the current base
     commit after an earlier git stop.
  10. `policy-advance-between-tracker-writes`: stops a multi-tracker sequence
      rather than mixing policy versions.
  11. `non-tracker-mutation-request`: keeps delegated authority inside
      documented containing-tracker edits.
  12. `policy-advance-during-final-write`: detects a policy move with no later
      tracker to trigger another pre-write check.
  13. `unverifiable-policy-after-final-write`: fails closed when the final
      policy observation is unavailable.
  14. `tracker-verification-failure-still-checks-policy`: fixes the required
      ordering when tracker verification fails.
  15. `container-selection-input-changes`: rereads the closing issue that
      selected an otherwise unchanged target tracker.
  16. `readiness-input-changes`: rereads a dependency tracker used to compute a
      refreshed field on an unchanged target.
  17. `zero-known-trackers-final-freshness`: closes an empty plan against
      current policy.
  18. `noop-and-report-only-final-freshness`: closes derived zero-write work.
  19. `missing-tracker-interface`: skips work when no documented interface
      exists.
  20. `policy-advance-before-later-write`: preserves earlier work on a later
      pre-write move.
  21. `tracker-interface-failure-still-closes-write`: verifies and post-checks
      a failed attempt.
  22. `partial-field-verification`: ledgers completed and unknown fields from
      one call.
  23. `unverifiable-initial-base`: refuses policy discovery without a current
      base identity.
  24. `repeated-policy-movement-is-bounded`: stops after one unstable-policy
      restart.
  25. `policy-record-appears-after-readable-absence`: closes silent absence
      against the current base.
  26. `report-recomputed-after-planned-write`: orders derived reports after
      their writes.
  27. `noop-input-changes-with-stable-policy`: revalidates no-op inputs.
  28. `input-changes-during-write`: downgrades a verified target when another
      selector or computation input changes during the write window.

## Re-running

1. Create a separate scratch git repository per eval with a merged feature
   branch, a clean checkout, and local default and remote-tracking refs that
   let the ordinary cleanup sequence complete safely.
2. Supply a local PR-host CLI stub that reports a verified merge, the fixture's
   closing issues and trackers, and deterministic tracker mutations. Make the
   agent freshly reread every external object used for selection or computation
   immediately before each write, then apply the documented idempotent
   transition, support a per-field target reread, and reread the full input set
   after the write. Keep every stub and mutation log outside this repository.
3. For eval 1, provide readable governing instructions with no post-merge
   record. Compare the baseline and revised runs for identical git and issue
   behavior and no project-obligation summary text.
4. For evals 2 and 3, add a complete record and readable mechanics document.
   Define the exact unit entry and completion transition. Provide one typed
   tracker for eval 2 and two known containing trackers for eval 3; do not
   expose an unrelated tracker through the record's rule.
5. For eval 4, point **Detailed mechanics** at a missing file. For eval 5,
   make the known tracker state disagree with the documented dependency
   relation. Neither fixture should permit a guessed mutation.
6. For eval 6, let git cleanup succeed, then make the CLI stub fail one tracker
   mutation after recording its attempt.
7. For eval 7, provide two complete records with conflicting mechanics
   pointers. For eval 8, repeat **Detailed mechanics** with two conflicting
   values inside one otherwise complete record. Neither fixture should permit
   project-obligation discovery or mutation.
8. For eval 9, stop git cleanup before base resync and give the feature
   checkout, stale local base, and current remote base different reconciliation
   transitions. Permit mutation only when both policy sources are loaded from
   the current remote-base commit and that tip is rechecked before and after
   each write.
9. For eval 10, advance the base policy after the first of two tracker
   writes. Preserve the verified first write, stop the second, and report the
   mixed-version risk as partial reconciliation.
10. For eval 11, make the mechanics request a tracker transition plus
    deletion of a release artifact. Apply only the tracker transition and hand
    the non-tracker mutation to the owner.
11. For eval 12, advance the base during the only tracker write. Retain
    the verified write, detect the move in the post-write check, and report the
    reconciliation as partial rather than fully complete.
12. For eval 13, let the only tracker write verify but make the final base-tip
    lookup malformed. Preserve the verified write, stop, and require the same
    exact partial ledger as a detected move.
13. For eval 14, fail tracker verification and advance the base. Require the
    tracker reread and verification attempt before the mandatory post-write tip
    lookup, then report the write outcome as unknown and reconciliation partial.
14. For eval 15, remove the target's containing-tracker link from the closing
    issue before the fresh pre-write reread while leaving the target unchanged.
    The reread must detect that the target is no longer selected and stop the
    write.
15. For eval 16, change a dependency tracker used to compute readiness while
    leaving the target unchanged. Require the fresh pre-write reread to detect
    the change, recompute readiness, and stop without a write when the
    documented refresh no longer applies.
16. For eval 17, expose no known tracker and advance policy before the final
    observation. For eval 18, expose one already-satisfied transition and one
    report-only result, then make the final observation unverifiable. Neither
    zero-write run may claim completion under stale or unknown policy.
17. For eval 19, omit every supported tracker interface. Require a
    skipped transition, unchanged final policy, and an incomplete checked
    ledger whose owner action contains no precomputed edit.
18. For eval 20, advance policy at the second pre-write observation after one
    verified write. Preserve the first result, skip the second, and require a
    partial ledger rather than restarting into mixed policy.
19. For eval 21, make the documented tracker call fail without changing the
    target. Require target verification, post-attempt freshness, and a final
    freshness observation despite the known no-change result.
20. For eval 22, make one atomic tracker call verify its transition but leave a
    refreshed field unverifiable. Require completed and unknown per-field
    dispositions, then stop partial.
21. For eval 23, make the current base identity malformed and leave fresh fetch
    unavailable. Do not substitute any working-tree or stale-ref policy. For
    eval 24, move policy twice before any mutation; permit one replacement trace
    and require the second move to stop as unstable policy.
22. For eval 25, begin with readable instructions that contain no record, then
    advance the base to a complete record before the closing observation. The
    stale absence must restart once and the stable replacement policy must run.
23. For eval 26, make the pre-transition and post-transition tracker states
    produce different readiness reports. The report must stay pending through
    the write, then reread every named input and use only the post-write state.
24. For eval 27, keep policy stable but change an input after the initial no-op
    inference. Require the post-write observation to revalidate every named
    input and skip the stale no-op.
25. For eval 28, change a non-target selector or computation input after its
    fresh pre-write reread but before the target update completes. Let target
    verification succeed, then require the full-input recheck to detect the
    change and downgrade the otherwise verified field to unknown.
26. Run `scripts/test-merge-cleanup-reconciliation.sh` to verify the executable
    trace grammar, transition ordering, terminal classifications, per-field
    ledgers, and exact non-stale owner actions over the deterministic exit
    matrix.
27. Replace `<fixture-repo>` in each prompt with its per-run path. Run each task
    with and without the revised skill, grade outputs against the expectations,
    and retain all generated artifacts outside this repository.
