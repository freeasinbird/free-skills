# Skill-creator review of visual-evidence: capture quality, evals, triggering

Ran the full skill-creator loop on the visual-evidence skill: four
targeted capture-quality edits, a three-case task-eval suite with a
with-skill vs old-skill benchmark, a human viewer review, an em-dash
sweep, and the description trigger-optimization loop. Branch
`docs/visual-evidence-capture-quality`, five commits including this
entry.

## Decisions

- **SKILL.md edits scoped to the review's four gaps** (viewport and
  dimension sanity, post-hoc cropping fallback, dimension check in the
  step-6 checklist, GFM before/after display template with render
  verification). The gh-imgup secret-review boundary was left verbatim
  per the 2026-06-26 constraint.
- **Viewer feedback addressed by counterbalance, not re-run.** The only
  feedback was one calibration-level comment on the with-skill spacing
  run ("may actually be a hair over-focused. It loses some context").
  Fixed with one sentence in the framing guidance ("Tight is not
  context-free: keep one orienting landmark in frame..."), folded into
  the capture-quality commit.
- **Iteration-2 of the task evals skipped (decided, not forgotten).**
  Re-running six subagents to test one wording sentence is not
  proportionate when the benchmark was already green and the feedback
  was calibration-level. Confirmed with the user via the orchestrator.
- **Trigger loop ran; description NOT changed (decided).** The current
  post-sweep description won on held-out test (7/8, 88% accuracy, 100%
  precision, 75% recall); all five improvement candidates tied it on
  test while raising train accuracy 75% to 89%, the overfitting pattern
  the held-out gate exists to catch. Per the plan gate (apply only on a
  held-out win), no frontmatter change and no description commit. The
  description now has measured trigger evidence instead of none.
- **Em-dash sweep mirrors 0c85eee**: all 36 em dashes replaced
  per-sentence (colons after bold bullet leads, semicolons for
  elaborations, parentheses and commas for asides), no blame-ignore
  entry, frontmatter kept as a `>-` block scalar and YAML-parse
  verified.

## Benchmark (iteration-1, n=1 per config per eval; directional)

- Pass rate: with-skill 96% ± 6% vs old-skill 93% ± 13% (+4pp).
- Time 221.8s vs 185.9s (+35.9s); tokens 50,190 vs 44,025 (+6,165).
- The one discriminating assertion was crop tightness on the
  spacing-fix eval: with-skill did element-level capture at 2x DPR (no
  page chrome); old-skill shipped full-page shots with the page title
  and up to 113px of trailing background. Evals 2 and 3 passed 100% in
  both arms (the old skill already carried the no-fake-before and
  worktree-reconstruction workflows).

## Eval-design findings (deferred fixes)

- **"Identical pixel dimensions" is mis-specified** for element
  captures of a component whose height IS the fix: both arms failed it
  structurally on the spacing eval. The better rule is width-only
  parity plus height-delta-matches-CSS-change. Initially deferred, then
  Codex's review (P2) independently raised the same defect against
  SKILL.md's step-6 check, overturning the deferral: SKILL.md now
  states exact match for fixed-rectangle crops and width-parity plus
  explained-height-delta for element captures (the "identical crop
  rectangle" invariant stays, scoped to fixed-rectangle capture), and
  the `evals/evals.json` assertions were re-specified to match so the
  committed suite doesn't contradict the skill it tests. The respec'd
  assertions haven't been exercised by a run yet; they bind the next
  suite run.
- net-new-component asserts capture process but not the required card
  text or cross-theme styling consistency; both runs happened to get
  those right, so the gap is real but uncaught.

## Skill-creator trigger-harness defects (found while running Phase 5)

Three defects, each masking as "recall 0%" because wrong-name triggers
and worker exceptions both score False (negatives then pass
"correctly", so precision stays 100% and the numbers look plausible):

1. `find_project_root()` walks up from cwd to `$HOME`, so probe command
   files land in `~/.claude/commands`: user config, phantom skills leak
   into live sessions, and writing there trips permission boundaries.
2. Probes load user-level settings, so a really-installed copy of the
   skill under test absorbs the triggers instead of the uuid-named
   probe. This repo dogfoods its own skills, so visual-evidence was
   installed and shadowed every probe.
3. All queries x runs probe concurrently into one shared project root
   (each subprocess sees every uuid probe, ~1/N picks the "right" one),
   and `ProcessPoolExecutor` spawn workers are unreachable by
   parent-process monkeypatches; `run_eval` swallows worker exceptions
   as False.

Workaround (session scratchpad, not committed): a wrapper giving each
probe its own temp project root containing only its own command file,
plus `--setting-sources project` applied inside the worker; delegation
goes to a pristine copy of `run_eval.py` loaded under a different
module name because spawn workers re-import `__main__`, re-apply the
patch, and the patched attribute otherwise recurses. Two earlier patch
attempts failed on exactly those worker-process subtleties; the fix
that shipped was validated through the real executor path first.
Detection semantics worth knowing when reading recall: only a first
tool call of Skill/Read counts, so a run that opens with any other tool
scores as no-trigger.

## Codex review rounds (five P2 findings, all fixed and folded)

Round 1:

- Dimension gate too strict (above): fixed as described in the
  eval-design finding; folded into the capture-guidance commit.
- Display-layout threshold ignored DPR: "≤600px logical width each"
  collided with the skill's own 2x-DPR advice (a 600-logical-px element
  saves as a 1200px file, and GitHub sizes table images by file
  pixels). The table-vs-stack decision now keys on the saved file's
  actual pixel width, with the half-of-~830px table-cell budget spelled
  out. Same fold target.

Round 2 (on the round-1 push):

- **Upload-before-review ordering hazard** (credential-leak surface):
  the Phase-2 render-verification bullet landed before the mandatory
  pre-upload secret review in Compose & attach, so a sequential
  bullet-follower would reach a post-upload step before the review that
  gates upload. Fixed by moving the secret-review bullet ahead of the
  upload-flow bullet and anchoring rendered verification as the final
  step, explicitly after review and upload. Refute-first pass run
  in-context (delegation unavailable this session) across
  sequential-follower, cherry-picker, and wording-weakening lenses:
  no bullet path reaches upload before the review; the intro and both
  Examples were already review-first; the review wording only gained
  "before any step that puts bytes on the wire" (strictly stronger);
  gh-imgup remains the canonical owner. Confirmed-and-fixed.
- **README instance missed by the round-1 class sweep**: the round-1
  width-parity sweep grepped SKILL.md and evals.json but not
  `evals/README.md`, which still said "identical dimensions". Fixed
  (width parity plus explained height delta), and the sweep re-run
  repo-wide over md/json; zero instances remain outside this entry's
  historical narrative. The miss is the fix-the-class lesson again:
  sweep by repo-wide grep, not by the file list you remember touching.

Round 3 (on the round-2 push):

- **Width parity was pattern-widening, not the class fix**: the round-1
  correction hard-coded width equality, which carries the identical
  flaw one axis over (a widened button or changed column width is an
  intended width delta). Codex caught the recurrence. Closed with the
  general invariant in SKILL.md step 6: fixed-rectangle crops match
  exactly; for element captures the only dimension deltas allowed are
  the ones the intended change explains, on either axis, roughly
  matching the CSS change; anything unexplained is a non-comparable
  pair. This is the AGENTS.md pattern-widening warning playing out in
  miniature: state the input-space invariant, don't widen the cited
  pattern. The evals.json and evals/README.md wording stays
  instance-level (width parity, explained height delta) because the
  spacing eval is a vertical padding fix where that is exactly what
  the invariant predicts.

## Process notes

- Fold hiccup, recovered: while folding the viewer-feedback fix into
  the capture-quality commit via detached-head amend + cherry-pick, an
  invalid `cherry-pick -q` flag left the evals commit briefly off the
  rebuilt branch. Recovered immediately; evals content verified
  byte-identical; branch was local-only throughout.
- The benchmark aggregator orders configs alphabetically (old_skill
  before with_skill), inverting the delta sign, and skips timing.json
  tokens when grading.json carries timing; both post-processed in the
  workspace copy of benchmark.json.

## To promote / deferred

- **Deferred (needs-human): upstream bug report to skill-creator** for
  the three trigger-harness defects above, with the isolated-probe
  workaround as a suggested fix. The full repro and workaround live in
  this session's scratchpad workspace (`run_loop*.log`,
  `isolated_probe.py`, `run_loop_isolated.py`).
- Deferred: add card-text/theme-consistency assertions to
  net-new-component before the next eval run. (The dimension-assertion
  respec that was deferred alongside it landed early, pulled in by the
  Codex review fold; see the eval-design findings.)
