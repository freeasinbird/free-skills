# plan-work-unit evals

These fixtures test routing and the planning handoff. Keep generated issue
copies, transcripts, and grading output in a scratch workspace outside the
repository.

## Files

- `trigger-eval.json` distinguishes explicit planning operations from
  implementation, assessment, overlap, review, and in-chat proposal requests.
- `planning-eval.json` describes planning inputs and expected outcomes.
- `setup-revision-trees.py` creates real source trees for the three revision
  cases. It prepares inputs; it does not run agents or grade their behavior.

## Planning Cases

- `stale-issue-contract`: Correct stale paths and interfaces on a stock repo
  without demanding a planning stage or lock.
- `dependency-blocked-unit`: Preserve an open dependency while completing a
  truthful plan for later implementation.
- `shared-contract-unit`: Preserve shared-contract serialization, generated
  types, adapter sequencing, and integration checks.
- `code-reality-invalidates-existing-plan`: Retire the stale plan before
  changing its contract, then publish one replacement grounded in current code.
- `owner-decision-blocks-contract`: Mark the old plan blocked, verify that
  state, and ask for the unresolved owner decision without inventing a plan.
- `concurrent-contract-edit`: Proceed on a whole-body, last-write-wins forge.
  Acknowledge that a reread cannot detect a lost concurrent owner edit.
- `replacement-plan-write-fails`: Retire the old plan before changing the
  contract. Report failed replacement publication as a partial unsafe state.
- `unchanged-contract-plan-write-fails`: Preserve the valid contract, retire
  the stale plan, and report blocked publication without leaving it actionable.
- `designated-contract-record`: Update the designated record without
  duplicating its authority in the issue body. Verify it and one issue plan.
- `pr-routing-forbids-direct-writes`: Report a precondition error before
  source inspection, artifact preparation, or any planning mutation.
- `partial-planning-stage-permission`: Refuse the entire operation when the
  stage permits only part of its required writes. Do not perform a subset.
- `repository-revision-advances`: Plan from readable R1, then report a later
  base move without importing R2 interfaces, reinspecting, or republishing.
- `local-checkout-differs-from-grounding-revision`: Read authoritative B
  while the checkout contains A. Ground the contract, plan, and identifier in B.
- `selected-revision-tree-unreadable`: Report the B source-access gap as
  planning blocked. Invalidate the prior A plan without publishing a replacement.

## Revision-Tree Setup

Run this command from the repository root. Python 3 and Git are required for
this fixture setup, not for the skill itself. The helper creates a unique
scratch directory and prints its controller manifest path:

```sh
python3 skills/plan-work-unit/evals/setup-revision-trees.py
```

The manifest names two commits and three repositories. Each commit has runnable
source, tests, and API documentation. The helper runs the documented test and
compile commands at both commits before preparing the cases.

- **A:** `LegacyRenderer.draw` in `src/export/render.py`, tested by
  `test/test_legacy_render.py`.
- **B:** `RenderService.render` returning `RenderedDocument` in
  `src/render/service.py`, tested by `test/test_render_service.py`.

Both APIs reject empty input with `InvalidDocument`. Neither implements the
requested title prefix. B removes A's source and test paths.

The controller prepares one disposable tracker per presentation. Initialize
its issue body and comments from the case artifacts. Offer issue-body and
comment reads, writes, and rereads that persist to that tracker. Keep a trace
of each operation and returned content. Never use real repository issues.

Expose authoritative reference lookup separately from the local checkout.
Return the manifest's selected commit when the task asks for the host's main
reference. Offer source access only to the case's repository. A local tracker
adapter or controller-mediated tool responses can supply these capabilities.

Use the matching case setup:

1. **`local-checkout-differs-from-grounding-revision`:** Start in `mismatch`,
   whose checkout is A and object database contains B. Host main returns B.
   Offer revision-specific reads such as `git show <B>:src/render/service.py`.
   Keep the working checkout at A throughout the presentation.
2. **`selected-revision-tree-unreadable`:** Start in `unreadable`, cloned
   before B existed and with its remote removed. Host main returns B.
   That repository cannot resolve B. Offer no remote fetch, snapshot, or forge
   source route, while keeping tracker writes working.
3. **`repository-revision-advances`:** Start in `advance`, with host main
   initially returning A as R1. This repository contains only A. After inspection,
   change the host reference to B as R2 and deliver that reference event.
   Do not disclose B's interfaces before inspection. Immutable R1 reads remain
   available through handoff.

Keep the controller manifest, other repositories, and grading rules outside the
task's accessible inputs. For the unreadable case, isolate its repository from
the helper's source repository and other case directories. Check that
`git cat-file -e <B>` fails there and that no alternative source route exists.

The helper does not enforce agent isolation or implement a tracker adapter.
The runner must provide both. If the platform cannot supply those capabilities,
record the affected behavioral runs as unavailable; setup success is not a pass.

## Forward-Testing

Run each case in a fresh context with the skill and only the raw request and
artifacts named by the fixture. Replace symbolic revisions with actual commit
identifiers and supply the case's source-access location. Keep this README,
the setup helper, and controller instructions out of the task context.

Do not include required actions, forbidden actions, intended answers, or prior
run conclusions. Grade the selected contract record, plan comment, completion
report, and observed source reads afterward. A printed SHA alone proves
nothing about which source supplied the plan.

When isolated tasks or agents are available, use a fresh one per presentation.
Otherwise, use a new user-controlled session. Repeat without the skill as a
baseline, with the same capabilities and fresh tracker state. Never reuse
generated artifacts as inputs to another run.

Retain each transcript, tool trace, persisted tracker snapshot, final report,
case ID, model, skill revision, and baseline/skill label. For the revision
cases, record these separate verdicts:

- **Reads:** The selected revision was resolved before inspection. Trace each
  existing path, interface, test, and command claim to that tree's content.
- **Outputs:** The persisted contract and plan match those reads and the
  requested behavior. Proposed paths or interfaces are explicitly new.
- **Failure and movement:** Unreadable B blocks grounding without a fabricated
  handoff. A later base move retains R1 provenance and reports the move without
  a reinspection loop.

For the other cases, grade preconditions, retirement-first ordering, one current
plan, write hygiene, and the planning-only boundary against the fixture.
Record failures and unavailable runs individually. Repeat presentations before
claiming the fixture's repeated-run target was met.

## Structural Validation

Parse both JSON files with `python3 -m json.tool`, directing output to scratch
files. Confirm 14 unique planning IDs match the inventory above: the original
12 plus the two new revision-access cases.

JSON parsing and inventory checks only validate fixture structure. They do not
grade model behavior, source reads, or persisted output. Report structural
results separately from semantic results and name any behavioral coverage gap.
