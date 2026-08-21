# Splitting the canonical sections into always-loaded core and on-demand reference

The managed AGENTS.md blocks agent-setup emits are the dominant fixed
per-turn cost in every downstream repo: in this repo the eight blocks
(excluding the project-specific `done-checks` sub-block) were 35,357
bytes, re-sent on every tool call. Roughly half of that text is
procedure an agent needs at one step, not on every turn. Issue #153
set the contract: every convention keeps existing and stays reachable
from an imperative read trigger at the step that needs it, while the
managed payload shrinks to at most 20 KB.

## Decisions

- **Reference file is a scaffolded `docs/agent-workflow.md`, not a
  ninth managed block and not part of `CONTRIBUTING.md`.** The template
  is `scaffolding.md` §agent-workflow; init step 6 and update step 9
  create it, and `check-managed-sync.sh` diffs this repo's copy against
  the template. Rejected: `CONTRIBUTING.md` is the human AI-contribution
  policy, and mixing step-local agent procedure into it repeats the
  "one home per protocol" problem the 2026-07-01 audit note fixed; a
  marker-managed second file would extend the comparator (AGENTS.md-only
  today) for a win the byte diff delivers in a few lines of awk.
- **Core/reference boundary is "runs every turn or every review round"
  versus "runs once at a step".** Core keeps: finish line, work
  contract, stages, the checklist, the refute-first trigger (which risk
  classes), context discipline, writing for humans, branch naming and
  isolation, commit rules, PR title and body shape, self-review,
  integration evidence, the independence ladder, evaluate-on-merits,
  fold-then-reply, fix-the-class, convergence's blocker rule,
  keep-the-body-current, and the handoff sequence in one paragraph.
  Reference holds, each verbatim from the pre-split text:
  `handing-off` (watch mechanics, baseline anchoring, base-freshness
  detail, close-out), `merge-and-resync` (the merge recipe and the
  worktree-removal hazard), `stacked-prs`, `reviewing-a-pr`,
  `review-convergence` (the rising-bar essay and the input-space
  enumeration), `pre-push-review`, `reviewer-record` (field list),
  `pr-body` (the per-section bars), and `refute-first` (lenses,
  old-vs-new harness, confirmed/rejected/accepted recording).
- **Two chunks moved beyond the issue's list: the PR body section bars
  (`pr-body`) and the optional pre-push review (`pre-push-review`).**
  Pure compression of the issue's core list bottomed out near 21.8 KB;
  reaching the 20 KB bar without dropping a rule needed two more
  step-local moves. Both run once per PR (writing the body, the moment
  before push), the body bars are already scaffolded verbatim into the
  PR template the agent fills in, and the pre-push review keeps its
  platform gate in the reference text. The `screenshots` slug the plan
  named is folded into `pr-body`, since the Screenshots bar is one of
  the five body sections; the UI-change trigger names that bar.
- **Bare-pointer sections are out; every pointer is an imperative,
  step-anchored read trigger.** Each moved chunk leaves "when X, read
  `docs/agent-workflow.md` §slug and follow it" at its original
  position; the merge trigger adds "do not merge or resync from
  memory" because the 2026-07-07 context-discipline note records a
  pointer-skipped merge recipe re-embedding PR bodies in history.
- **Relocation and compression are separate commits.** The first moves
  text verbatim (sentence-level coverage: 0 of 331 pre-split sentences
  missing), so the diff proves nothing was dropped; the second tightens
  core prose only and leaves the reference and template untouched. The
  only non-verbatim edits in the reference are two back-references
  that pointed "above" at text now in AGENTS.md (the self-review bullet
  and the convergence rule), rewritten to name their new location
  (fresh-context review finding).
- **The round-one severity guardrails stay in core.** A fresh-context
  review found that "judge severity yourself, the reviewer's tag is
  input, not verdict" and "when unsure, treat a finding as blocking"
  had moved with the convergence essay, whose trigger fires only after
  the early rounds; both clauses are back in the core Converge bullet.
- **The sync check also validates the pointers and the byte budget.**
  `check-skill-structure.sh` only resolves `references/<file>.md` §slug
  pointers, so nothing checked the nine `docs/agent-workflow.md` §slug
  pointers; `check-managed-sync.sh` now asserts the pointed and headed
  slug sets are equal and that the managed blocks stay within 20,000
  bytes, so the split's two invariants fail loudly instead of eroding.
  The headed set is every level-two heading in the reference, not only
  slug-shaped ones: matching `^## [a-z0-9-]+$` would have let a
  prose-titled section added to both template and reference pass as
  though it did not exist, which is the unreachable-procedure state the
  check exists to prevent (Codex review, P2). Repeated slugs are
  rejected for the same reason: the set comparison dedupes, so a second
  `## refute-first` would hide behind the first and leave a pointer
  with two targets (refute pass). Pointer targets are extracted whole,
  to the next space minus sentence punctuation, and then validated:
  taking the longest slug-shaped prefix let `§reviewing-a-pr_EXTRA`
  pass as `reviewing-a-pr`. That is the third finding on this one
  regex, so the input space was enumerated once instead of widened
  again (suffix, uppercase prefix, mid-token uppercase, space after
  the section sign, valid-but-unheaded slug, trailing punctuation,
  no space before the sign, duplicated pointer, wrapped pointer):
  10 cases, run against mutated repo copies. Follow-up: that
  enumeration belongs in a `test-check-managed-sync.sh` beside the
  repo's other check matrices.
- **A missing `docs/agent-workflow.md` next to slimmed blocks is drift
  to fix, not an optional offer.** Update step 9 treats it as a
  dangling-pointer state once step 6 has synced blocks that carry the
  pointers; the other scaffolds stay offer-only because nothing in the
  blocks depends on them. A decline is recorded in the sync report. A
  locally customized copy does not fall back to "leave it as it
  stands" either (the rule the other scaffolds get): the blocks depend
  on the canonical text, so it is refreshed and the project's own
  sections kept alongside it (Codex review, P2). The file is settled in
  step 6's decision rather than step 9's, because a step-9-only rule
  can only report the stranded state that step 6 already created;
  blocks carrying pointers hold at their existing text when the
  reference cannot be written. Rejected: rolling back applied blocks,
  which is machinery for a state the ordering prevents (Codex review,
  P2). The rule is stated per write, not per step: init step 5, update
  steps 6 and 8, and the reviewer-record refresh all write blocks, and
  a step-numbered list was already one site short when a refute pass
  found the reviewer-record path (Codex review round 4 plus the refute
  pass it triggered).
- **The four-backtick outer fence the plan proposed is dropped.**
  Prettier normalizes the fence to the minimum width the content
  needs, and would widen it again if a fenced block ever entered the
  template; `check-managed-sync.sh` accepts any fence of three or more
  backticks.

## Coverage check

A scratch script split the pre-split canonical text into 331
sentence-level units (bullets and paragraphs first, then on sentence
punctuation), normalized whitespace and case, and looked each up in
the new canonical text plus `docs/agent-workflow.md`. After the
relocation commit: 0 missing. After the compression commit: 83
reworded units, audited one by one. They fall into four classes, none
a dropped rule:

- Restated rationale removed ("a human handed ten questions silently
  drops most of them"; "each miss costs another review round"; "the
  merge commit carries the narrative"; "CI asserts that, and it goes
  stale"; "merges are title-only, so the body's review material never
  lands in history").
- Cross-block duplicates collapsed to a pointer (checklist steps 1–2
  now defer to Branches for start-tip and primary-checkout rules; the
  handoff intro no longer repeats the finish-line paragraph; the PR Body
  bullet defers to §pr-body).
- Sentence merges that keep every clause (stages paragraph and
  checklist intro; fold-then-reply restated once instead of twice;
  self-review and integration-evidence wording).
- Moved, not reworded, but split differently by the tokenizer (the
  worktree-removal hazard, now in §merge-and-resync verbatim).

Two genuine drops surfaced ("Don't re-enable around them", the
repo-settings guardrail, by the audit; "or self-review" as a fold
trigger, by the fresh-context review) and were restored before commit.

## Measured sizes

Bytes, this repo, at the three commits; tokens are not measured (no
tokenizer was available in the session; the issue's ~4 bytes per token
puts the managed-block saving near 3.8k tokens per cache miss and
per-call cache-read cost), so no session-level percentage is claimed.

| Artifact                                  | Before (`5f95812`) | After relocation | After compression |
| ----------------------------------------- | -----------------: | ---------------: | ----------------: |
| Managed blocks, excl. `done-checks`       |             35,357 |           23,528 |            19,991 |
| `AGENTS.md` whole file                    |             45,974 |                  |            30,838 |
| `docs/agent-workflow.md` (read on demand) |                  0 |           16,032 |            16,032 |

Per block after compression: devlog 2,084 and context 2,073 (unchanged
by decision), finish-line 3,255, communication 1,807, branches 2,583,
pull-requests 5,497, commits 2,346, done 346. The margin under the
20,000 bar is nine bytes; the sync check holds the line.

## Verification findings

- The comparator run against the pre-split `AGENTS.md` (what update
  mode step 6 shows a downstream repo) reports drift on exactly the
  five rewritten blocks and `ok` on devlog, context, and done. A full
  agent-driven update on a downstream clone was not run; the file
  creation is a SKILL.md prose step, so the first real downstream sync
  is the test of the dangling-pointer rule.
- `check-managed-sync.sh` exits 1 on a one-byte change to
  `docs/agent-workflow.md`, on a renamed reference heading, and on a
  managed-block drift, running every check before exiting; its fence
  extraction survives a three-backtick block nested in a four-backtick
  template (Prettier widens the outer fence itself), and exits 0 when
  everything matches. The budget check counts the extracted stream with
  `wc -c` rather than awk's `length()`, which counts characters in a
  UTF-8 locale and under-reported these blocks by 22 bytes on the
  reviewer's machine: with nine bytes of margin that gap is the whole
  check (Codex review, P2).

Revisit when: a downstream sync reports a missing reference file, an
agent merges or resyncs from memory despite the trigger, or a managed
block regrows past its post-split size without a new convention behind
it.
