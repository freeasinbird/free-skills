# agent-setup evals

Eval definitions for the skill-creator loop. Only the definitions live in the
repo; run outputs, fixture projects, and grading artifacts belong in a scratch
workspace outside the repo.

## Files

- `trigger-eval.json`: eighteen description-only queries, twelve positive and
  six negative, for setup, devlog, sync, reassessment, and standalone scaffolds.
- `evals.json`: fifty-six task evals for scope routing, factual intake, profiles,
  optional work-unit stages, coordination discovery, and reassessment.
  1. `single-stage-init`: initializes a plain project and expects the normal
     single implementation workflow with no stage record.
  2. `planning-implementation-handoff`: initializes a project with separate
     planning and implementation stages, a durable issue-backed handoff, and
     no implied implementation authorization.
  3. `later-review-integration-adoption`: updates an existing staged project,
     preserving its stage and coordination records while adding review and
     integration.
  4. `first-stage-adoption-update`: updates an agent-ready project that has no
     stage record, adding an owner-requested planning-only record while
     preserving unrelated guidance and the undeclared implementation default.
  5. `empty-repository-serial-baseline`: initializes an empty project with the
     safe serial default and no invented coordination structure.
  6. `speculative-plan-is-evidence`: keeps an uncorroborated draft plan from
     becoming lanes, a graph, or unsupported parallel width.
  7. `mature-simple-adoption`: adopts management while preserving demonstrated
     serial behavior in a mature project that needs no richer coordination.
  8. `recurring-independent-streams`: derives stable named streams from
     recurring history and caps width at proven integration capacity.
  9. `shared-contract-integration-spine`: separates serialized shared-contract
     work from component ownership and keeps typed relations distinct.
  10. `new-evidence-after-serial-init`: proposes an evidence-supported upgrade
      after an early serial initialization without mutating before approval.
  11. `stale-streams-after-architecture-change`: identifies obsolete named
      streams and proposes simplification without silently renaming them.
  12. `repeated-shared-surface-collisions`: derives shared-contract
      serialization from recurring collisions and integration limits.
  13. `obsolete-integration-spine`: removes a spine from the proposal when its
      bottleneck has disappeared.
  14. `ordinary-update-does-not-reassess`: preserves a rich coordination record
      byte-for-byte during an ordinary managed-section update.
  15. `malformed-markers-block-reassessment`: stops before interpreting or
      changing coordination policy when AGENTS.md boundaries are malformed.
  16. `rejected-diff-keeps-triggers-report-only`: keeps new reassessment
      triggers out of an existing record after the owner rejects its diff.
  17. `missing-agents-keeps-reassessment-report-only`: reports a supported
      recommendation without creating a partial agent setup.
  18. `managed-record-blocks-reassessment`: rejects a coordination record and
      pointer inside structurally valid managed ranges.
  19. `unsafe-mechanics-target-blocks-reassessment`: resolves the mechanics
      pointer and rejects a target inside a managed range.
  20. `managed-stage-record-blocks-reassessment`: rejects a stage record inside
      a structurally valid managed range.
  21. `combined-init-then-reassessment`: completes a requested Standard setup
      before reassessing the resulting evidence-supported coordination model.
  22. `duplicate-coordination-records-block-reassessment`: stops before
      choosing between conflicting coordination records.
  23. `duplicate-coordination-field-blocks-reassessment`: stops before
      resolving conflicting values for one fixed coordination field.
  24. `duplicate-stage-records-block-reassessment`: stops before using
      conflicting stage records as coordination evidence.
  25. `multi-stage-record-remains-valid`: treats several stage definitions in
      one project-specific stage section as one valid record.
  26. `external-work-contract-remains-read-only`: accepts a shape-2 tracker
      issue as unavailable read-only evidence rather than an unsafe target.
  27. `missing-current-shape-blocks-reassessment`: stops before inferring a
      model from an incomplete fixed-field record.
  28. `zero-record-uses-serial-baseline`: skips present-record field checks and
      keeps the absent-record safe serial baseline.
  29. `composed-rich-shape-requires-local-mechanics`: keeps the local mechanics
      requirement when shape 2 composes with a richer shape.
  30. `combined-update-preflights-policy-location`: validates project-policy
      placement before the setup half may refresh an existing managed block.
  31. `incomplete-stage-entry-blocks-reassessment`: stops before using a stage
      entry that lacks any of its six fixed fields.
  32. `combined-adoption-preflights-planned-ranges`: checks planned adoption
      ranges before markers or refresh can enclose project policy.
  33. `duplicate-stage-field-blocks-reassessment`: stops on a repeated field
      inside one named stage entry.
  34. `duplicate-stage-name-blocks-reassessment`: stops before choosing between
      two complete entries with the same stage name.
  35. `shared-stage-guidance-is-not-an-entry`: keeps leading record-level prose
      outside the named stage-entry count.
  36. `legacy-single-stage-record-remains-valid`: accepts the prior direct-field
      single-stage layout without forcing a migration.
  37. `mixed-stage-layout-blocks-reassessment`: stops before combining direct
      record fields with a child-heading entry.
  38. `empty-child-stage-field-blocks-reassessment`: rejects an immediate-child
      entry whose field label has no value.
  39. `empty-legacy-stage-field-blocks-reassessment`: rejects a legacy direct
      entry whose field label has no value.
  40. `legacy-sibling-addition-requires-migration-approval`: requires an exact,
      approval-gated structural migration before adding a sibling stage.
  41. `generic-legacy-container-does-not-invent-stage-name`: accepts a complete
      unnamed legacy stage without treating its container as its name.
  42. `skipped-level-stage-heading-blocks-reassessment`: stops on a descendant
      heading that cannot define an immediate-child entry.
  43. `legacy-fields-plus-child-stage-blocks-reassessment`: stops before a
      complete descendant stage is swallowed as legacy-stage content.
  44. `combined-update-survives-semantic-preflight-failure`: completes safe
      setup before semantic policy validation stops reassessment.
  45. `combined-update-preflights-local-target-location`: stops before update
      refreshes a local mechanics target hidden behind an unmanaged pointer.
  46. `blank-legacy-shape-one-mechanics-remains-valid`: accepts the prior blank
      mechanics value for a shape-1 record.
  47. `blank-legacy-shape-two-mechanics-remains-valid`: accepts the prior blank
      mechanics value for a shape-2 record without inventing a work contract.
  48. `blank-rich-shape-mechanics-still-blocks`: retains the local-document gate
      when a composed shape includes a richer capability.
  49. `standalone-pr-template-absent-agents`: exits the loaded skill before Init.
  50. `standalone-pr-template-managed-agents`: exits before Update and preserves
      AGENTS.md verbatim.
  51. `standalone-contributing-absent-agents`: exits before Init without importing
      setup policy into CONTRIBUTING.md.
  52. `standalone-contributing-managed-agents`: exits before Update without
      redirecting to the scaffolding reference.
  53. `populated-repository-evidence-first`: uses agreeing repository facts
      without asking the owner to repeat them or running builds for intake.
  54. `missing-and-conflicting-intake`: reuses settled facts and asks only
      about a missing run command and a concrete runtime conflict.
  55. `explicit-devlog-default`: retains Decision-log for a devlog request.
  56. `explicit-devlog-mandatory-classes`: retains High-assurance when the owner
      supplies mandatory note classes.

## Re-Running

These are behavioral specifications, not an automatic runner. Keep separate
fixture copies and fresh agent contexts for the old and revised skill. Save
the exact revisions, model, supplied prompt, tool transcript, questions, file
diff, and outcome for each expectation. Missing model runs are verification
gaps; parsing JSON or matching phrases is not behavioral evidence.

### Description Selection

Present each query with only the skill's name and description, without forcing
the skill to load. Record whether the agent selects agent-setup and compare
that selection with `should_trigger`. Repeat against the old description in a
fresh context. Keep this separate from loaded-skill task runs below: selection
alone cannot prove that an explicitly loaded skill exits before choosing a mode.

### Existing Stage and Coordination Fixtures

1. Create one scratch git repository per eval with a README that documents
   simple build, test, lint, and format commands. For eval 1, omit AGENTS.md.
2. For eval 2, also provide project facts sufficient for a Standard-profile
   init. No committed stage record exists before the run.
3. For eval 3, first run eval 2's setup, then introduce a small drift in one
   managed block, add a complete four-field coordination model record, and add
   unrelated unmanaged project guidance. This makes managed refresh and both
   record-preservation paths observable together.
4. For eval 4, start with an agent-ready project whose AGENTS.md has current
   managed blocks and unrelated unmanaged guidance, but no stage record.
5. For eval 5, provide only the basic README. Do not add a plan, code,
   architecture document, work-unit history, or AGENTS.md.
6. For eval 6, add only the speculative PLAN.md described by the prompt. Its
   proposed lanes and graph must have no corroborating code or history.
7. For eval 7, provide a mature code tree, architecture notes, serial work-unit
   history with no recurring independent boundaries or bottleneck, and an
   unmarked AGENTS.md containing project guidance that adoption must preserve.
8. For eval 8, provide architecture notes and six completed work-unit records
   that demonstrate the same two independent boundaries. Directory names must
   not be the only evidence.
9. For eval 9, provide code, architecture notes, and work-unit history showing
   independent components, a serialized shared schema, one integration role,
   and examples of all four typed relations.
10. For eval 10, start from an agent-ready serial project with no coordination
    record, then add architecture notes and six work-unit records showing two
    recurring independent boundaries and a two-unit integration limit.
11. For eval 11, add an unmanaged API/UI stream record and mechanics document,
    then add newer architecture notes and history showing repeated work across
    those boundaries.
12. For eval 12, start with path-and-dependency units and add architecture plus
    five work-unit records showing repeated shared-schema and generated-output
    collisions, integration delays, and a two-unit component capacity.
13. For eval 13, add an integration-spine record, evidence that its shared
    contract was split behind versioned interfaces, and eight work units that
    integrated without the spine or manual scheduling.
14. For eval 14, add current managed blocks plus unrelated unmanaged guidance
    and a complete rich coordination record. Introduce managed drift and
    potentially stale topology evidence, then request only an ordinary update.
15. For eval 15, add a managed opener with a mismatched closer and put an
    apparent coordination record inside the malformed boundary.
16. For eval 16, add valid managed blocks and an unmanaged coordination record
    whose existing reassessment trigger differs from current evidence.
17. For eval 17, omit AGENTS.md and add architecture plus recurring work-unit
    evidence for two stable independent streams.
18. For eval 18, put a complete coordination record and its project-document
    pointer inside a structurally valid managed block.
19. For eval 19, keep the record unmanaged but point its detailed mechanics to
    a section inside a structurally valid AGENTS.md managed block.
20. For eval 20, keep the coordination record unmanaged but put a complete
    work-unit stage record inside a structurally valid managed block.
21. For eval 21, omit AGENTS.md and provide architecture plus six work-unit
    records showing two stable independent streams and a two-unit integration
    limit.
22. For eval 22, add two complete unmanaged coordination records with
    conflicting shapes and mechanics pointers.
23. For eval 23, add one unmanaged coordination record with two different
    Detailed mechanics fields and corresponding candidate documents.
24. For eval 24, add one unmanaged coordination record plus two unmanaged stage
    records with conflicting activation and transition rules.
25. For eval 25, add one unmanaged coordination record and one unmanaged stage
    section containing complete Planning, Implementation, Review, and
    Integration definitions.
26. For eval 26, add a complete unmanaged shape-2 coordination record whose
    mechanics field points to an unavailable tracker issue, plus usable local
    architecture and work-unit evidence.
27. For eval 27, add one unmanaged coordination record that omits Current shape
    but includes the other three fields and a mechanics document.
28. For eval 28, omit the coordination record and mechanics field, and add one
    valid unmanaged multi-stage section plus evidence for serial coordination.
29. For eval 29, add one complete unmanaged record combining path-and-dependency
    units with typed relations, but point mechanics only to an external issue.
30. For eval 30, place a complete coordination record inside a structurally
    valid managed block that also contains canonical drift.
31. For eval 31, add one unmanaged stage section with a complete Planning entry
    and an Implementation entry missing Allowed mutations and Transition.
32. For eval 32, use an unmarked AGENTS.md whose canonical-looking Pull requests
    section contains a coordination record that planned adoption would enclose.
33. For eval 33, add one Planning child entry with two conflicting Allowed
    mutations fields.
34. For eval 34, add two complete child entries both named Review with
    conflicting activation and mutation rules.
35. For eval 35, place shared record prose before complete Planning and
    Implementation child entries.
36. For eval 36, add one project-specific Implementation stage section with no
    child stage entries, all six direct field-label bullets exactly once with
    substantive rendered values, and a nested Verification notes content
    heading.
37. For eval 37, mix direct Activation and Required input bullets with a
    Planning child entry containing the other four fields.
38. For eval 38, add one Planning child entry with six labels but give Allowed
    mutations only an HTML TODO comment.
39. For eval 39, add one legacy Implementation stage with no descendant
    headings, but give its direct Transition field only a TBD placeholder.
40. For eval 40, add one complete legacy Implementation section, including
    wrapped field values and an unlabelled handoff constraint, then request an
    additional Review sibling without preapproving a structural migration.
41. For eval 41, add one generic Work-unit stages section with no descendant
    headings and six complete direct fields.
42. For eval 42, put an Implementation heading two levels beneath a Work-unit
    stages section and put six complete fields below it.
43. For eval 43, put six complete direct fields under an Implementation stage
    section, then add a Review child heading with another complete field set.
44. For eval 44, add valid managed ranges with canonical drift plus an
    incomplete stage record wholly outside those ranges.
45. For eval 45, put a coordination record outside managed ranges and point its
    local mechanics value into a drifted managed section update would refresh.
46. For eval 46, add one complete legacy shape-1 record with a present but blank
    Detailed mechanics field.
47. For eval 47, add one complete legacy shape-2 record with a present but blank
    Detailed mechanics field and no external work contract.
48. For eval 48, add one record combining shapes 2 and 3 with a present but blank
    Detailed mechanics field.

### Scope and Intake Fixtures

For cases 49–52, use the populated fixture below and omit the requested
artifact. Omit AGENTS.md for 49 and 51. For 50 and 52, add valid Standard
managed blocks, the required workflow reference, and an unmanaged sentinel:
`Local instruction: preserve this sentence verbatim.` Save its original bytes.

Explicitly load the tested skill revision for these four cases. Grade whether
it enters either setup mode, offers setup scaffolds, reads or redirects to its
scaffolding reference, or imports setup policy into the artifact request.
Compare AGENTS.md bytes and the complete file diff. The ordinary requested
artifact may be produced after the skill exits; setup-driven changes fail.

For case 53, create the following populated fixture with no AGENTS.md. For
cases 55 and 56, use the same fixture; their prompts supply the profile intent.
All paths below are relative to the scratch fixture root.

- `package.json`:

  ```json
  {
    "name": "intake-fixture",
    "private": true,
    "type": "module",
    "scripts": {
      "build": "node scripts/build.mjs",
      "test": "node scripts/test.mjs",
      "start": "node src/main.mjs",
      "lint": "node scripts/lint.mjs",
      "format": "node scripts/format.mjs"
    }
  }
  ```

- `.nvmrc`: `22`, followed by a newline.
- `src/main.mjs`: `export const answer = 42;`, followed by a newline.
- `scripts/build.mjs`, `scripts/test.mjs`, `scripts/lint.mjs`, and
  `scripts/format.mjs`: use this content, replacing `ACTION` with the filename
  stem. These executable fixture stubs record invocation without dependencies.

  ```js
  import { appendFileSync } from "node:fs";
  import { strict as assert } from "node:assert";
  import { answer } from "../src/main.mjs";
  appendFileSync(".eval-executions", "ACTION\n");
  assert.equal(answer, 42);
  ```

- `.github/workflows/ci.yml`:

  ```yaml
  name: checks
  on: [push]
  jobs:
    check:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-node@v4
          with:
            node-version-file: .nvmrc
        - run: npm run build
        - run: npm test
        - run: npm run lint
        - run: npm run format
  ```

- `README.md`: describe a Node 22 project with no external dependencies.
  Document `npm run build`, `npm test`, `npm start`, `npm run lint`, and
  `npm run format`, each alongside its script path from the manifest. State
  that `src/main.mjs` is the entry point, CI lives in
  `.github/workflows/ci.yml`, and no external dependencies may be added.

For case 54, copy case 53's fixture and remove `start` from the manifest and
the run-command sentence from README. Keep the entry point documented. Replace
CI's `node-version-file: .nvmrc` with `node-version: 20`; keep `.nvmrc` at 22.

Grade intake against source facts, questions, and tool calls. Inspect
`.eval-executions` alongside the transcript to distinguish builds or tests run
for intake from any later verification. A source-verified command definition
is not evidence that the command ran successfully. In case 54, require the
runtime question to name both conflicting sources and the other question to
ask for the missing run command; settled facts need no confirmation.

### Task Runs and Regression Coverage

Replace `<fixture-repo>` in each prompt with its per-run path. Run new task
cases against both skill revisions, grade each expectation, and retain the
scratch artifacts. Rerun cases 1, 5, 7, 14, 17, and 21 for Standard init,
empty-project placeholders, adoption preservation, sync, and reassessment.
Cases 55 and 56 cover the note-keeping profile defaults.

Parse both JSON files before behavioral runs. Check task IDs and names for
uniqueness, the existing task fields for presence, and trigger values for
Boolean type. Verify the counts above from parsed data and preserve all 48
existing task definitions and expectations unchanged.
