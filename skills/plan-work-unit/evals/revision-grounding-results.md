# Revision-Grounding Probe Results

On 2026-09-04, one fresh-context skill probe completed the stale-checkout case.
Two other skill probes reached source inspection but could not persist their
outputs because automatic approval review rejected the local fixture writes.
These observations do not meet the fixture's repeated-run target.

## Method and Scope

The probes used `gpt-5.6-terra` at low reasoning effort, with fresh context for
each presentation. Skill runs loaded the revised `SKILL.md` from this change.
Baselines loaded no skill. Each task received a raw request, project and issue
artifacts, and an adapter for source and disposable tracker operations.

Source operations read actual Git objects. Tracker operations persisted local
JSON and recorded each request and response. Access was limited by task
instructions to the case adapter; this was not an OS-enforced isolation test.
No real issue or pull request was used as an evaluation target.

The controller withheld grading criteria and source-layout answers. The
moving-base controller was set to emit the base change on the first tracker
write, after source inspection. That write was blocked, so the event was not
delivered during the skill probe.

## Observed Results

- **`local-checkout-differs-from-grounding-revision`, skill:** Passed one
  presentation. The trace resolved B before reading its README, source, and
  tests. The persisted contract and single plan used `RenderService.render`,
  `RenderedDocument`, and B's test path, and reported B as provenance.
- **`selected-revision-tree-unreadable`, skill:** Incomplete. The trace
  resolved B and received a source-access failure. Approval review blocked
  preparation of the prior-plan retirement and final-report files. The probe
  reported a grounding blocker, but retirement was not verified.
- **`repository-revision-advances`, skill:** Incomplete. The trace resolved R1
  and read its README, `LegacyRenderer.draw` source, and tests. Approval review
  blocked preparation of the contract and plan files. No base-move handoff was
  observed.

- **`local-checkout-differs-from-grounding-revision`, baseline:** B-grounded
  reads and persisted outputs were observed. Before resolving B, the task
  attempted a mutable-reference read of a nonexistent input file. It then
  resolved B, read its source, README, and tests, and verified both writes.
  This did not follow the resolve-before-inspection ordering.

One earlier baseline presentation was discarded because the scratch controller
cloned the detached repository without preserving its unreferenced B object.
The valid rerun copied the repository's object database and verified B was
readable before starting. The shipped helper itself retains B in mismatch.

The rejected actions were local writes for simulated issues #109 and #108.
Approval review treated those fixture identifiers as unrelated to the user's
issue #237 assignment. Clarifying the delegated test scope did not clear the
unreadable-case rejection; no alternative write path was attempted.

## Structural Evidence and Limits

The setup helper ran both revisions' two tests and compile commands. After
independent review, checks confirmed every case's HEAD and local main select
A, only mismatch contains B, and no case retains a remote. B replaces A's
source and test paths. JSON parsing confirmed 14 unique case IDs matching the
README, with the 11 unrelated case definitions unchanged.

The full 14-case semantic battery and repeated presentations were not run.
No shared semantic runner exists; the scratch adapter covered only the three
revision cases. The unreadable and moving-base baselines were not run after
approval review blocked those skill presentations. Structural success does
not close these behavioral coverage gaps.
