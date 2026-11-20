# Shrink visual-evidence's SKILL.md by Measured Climb

Issue #442 ran a `hill-climb` size climb on `visual-evidence/SKILL.md`,
holding the scored eval from #441. `SKILL.md` went from 3,648 to 2,614
words (−28%). The climb split held 1.000 with a 0.000 band on every score.
The held-out split ended at 1.000, as the base did, after one owner-approved
fix. The climb spent its 12-attempt budget at 2,543 words, 43 short of the
2,500 target. Review fixes and the recording fix then added 71 words. The result holds for
`claude-sonnet-5-5` only.

## Decisions

- **Chose pointers over restatement.** The largest cuts replaced prose that
  restated `capture.mjs`'s header comment (options, defaults, output names,
  exit codes) and `references/gh-attach.md` (§commands, §body-rewrite,
  §video) with pointers. Every flag stays named, and every §slug keeps its
  pointer.
- **Kept every rule the eval can't see.** The goal file pinned the review
  checklist, the flagged-image stop, the recording rule, the authorization
  rule, step 6's failing-image hand-back, the `npx -y` ban, the Actions
  `GITHUB_TOKEN` sentence, and the eval README's rule table. A guard script
  checked those phrases before each score. No section heading changed, so
  the eval README's Section Coverage tables needed no edit and the check's
  hash still holds for a later climb.
- **Restored 10 weakenings the reviews found.** A refute-first pass,
  comparing old and new text rule by rule, and a fixed-brief pre-push review
  found no lost forge-write gate or owner hand-back. Both found smaller
  losses, each fixed in the commit that caused it:
  - Worktree cleanup had become part of an example; it's a rule again.
  - The page-level exception for full-page capture was gone.
  - `capture.mjs` read as mandatory, and the element-capture examples were
    gone.
  - Re-capture read as unconditional.
  - gh command routing (`pr edit` for the description, comments only for
    later additions) was flattened, and gh-imgup's `--pr` and `--issue` lost
    "only".
  - "Checked by extension only" and gh-imgup's stderr note were gone.
- **Declined three review findings.**
  - The operator command-allowlist note is operator setup, not an agent
    step.
  - The "recommended, not required" and "no extra secret" clauses for
    gh-imgup are rationale; the path's gate and the stop path still decide.
  - "Use it as the frontmatter describes" relies on frontmatter that the
    agent has already matched.
- **Tightened the recording rule, by owner decision.** After the review
  fixes, held-out case 14 failed one run in three. The agent wrote a Swift
  AVFoundation frame sampler (`/usr/bin/swift` is on the runner's system
  `PATH`), read five frames of the clip, called that a review, and uploaded
  it. The unchanged base skill passed the same split 9 of 9. Every case-14
  run, base included, probed for a frame extractor first, so the sample
  can't separate the climb from noise. The owner chose to name sampled or
  extracted frames as not a review. The held-out split guided that change,
  so its 1.000 rescore is a confirmation, not an independent test.

## Findings

- **Every attempt scored 1.000.** Eleven of 12 attempts were kept. The one
  revert was a guard failure: a bare "§commands" isn't a
  `references/gh-attach.md` §commands pointer, which
  `check-skill-structure.sh` requires.
- **The score was a weak guard again.** The eval can't see capture craft
  or routing between `gh` commands. The two reviews, not the score, found
  every weakening above. Gains per attempt fell from 243 words to about 50
  after the first five attempts, so the 30% target sat at the edge of what
  rule-preserving cuts allow here.
- **The host affects case 14.** The eval README's caveat names `ffmpeg`.
  macOS also ships `swift` with AVFoundation in `/usr/bin`, which a run can
  turn into a frame extractor.
- **Cost.** About $2 and 1.5 minutes per 24-run score at `--jobs 8`. The
  climb, held-out scores, and review rescores cost $29.08, within the
  owner's $30 budget; proving at #441 cost $22.82 more.

## Next Skill

Climb `await-pr-review` (#444) after its eval (#443), but with a smaller
relative target, near 20%. It starts at 1,884 words, and
`scripts/review-convergence-layers.tsv` pins phrases in it that the climb
can't cut. Point at `watch-review.sh`'s own documentation before cutting
prose, budget about 8 attempts, and plan both reviews of the final diff
from the start. When a held-out case drops, score the base on the same
split before diagnosing.

Revisit when a weaker model or a non-Claude agent runs `visual-evidence`;
the shorter text leans on the agent reading `capture.mjs`'s header and
`references/gh-attach.md`.
