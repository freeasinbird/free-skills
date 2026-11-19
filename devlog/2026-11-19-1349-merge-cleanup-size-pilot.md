# Shrink merge-cleanup's SKILL.md by Measured Climb

Issue #393 piloted a `hill-climb` size climb on `merge-cleanup/SKILL.md`,
holding the scored eval from #392. `SKILL.md` went from 4,193 to 2,180 words
(−48%) with the climb split at 1.000 and a 0.000 band. The owner stopped the
climb short of its 1,500-word target. The result holds for
`claude-sonnet-5-5` only.

## Decisions

- **Chose to cut prose that restates the bundle over cutting rules.** Nine
  attempts were scored and all nine kept. Most of the drop came from four
  sections whose text restated `worktree-sweep.sh --help`,
  `merge-cleanup.sh --help`, `tracker-write.sh --help`, and
  `references/project-obligations.md`. What stayed is what no script
  enforces: who authorizes a sweep, which flags only the owner may choose,
  the caller-directory rule, tracker writes only through `tracker-write.sh`,
  and the result-to-trace table.
- **Stopped at 2,166 words, not 1,500, by owner decision.** About 50 to 100
  words of wording-only cuts were left. Below that, each cut would drop a
  rule whose only home is `SKILL.md`, or text `check-skill-structure.sh`
  requires: the frontmatter, the 18 `references/` pointers, and a mention of
  every parsed flag. A fixed 1,500-word ceiling doesn't fit a skill with a
  bundle and references.
- **Restored two cues the held-out split showed were needed.** Attempts 2
  and 6 cut "Explicit remotes help ambiguous layouts and hostless local-path
  fixtures" and "Inspect configured remotes when necessary." The climb split
  didn't notice. On held-out case 30, every base run passed `--base-remote`
  and `--head-remote` up front, while every final run first stopped
  `remote-unresolved` and retried; one probed the alias's slug, which the
  grader rejects. With both cues back, case 30 passed 3 of 3 with no probe,
  but 2 of 3 runs still passed the remotes only on the retry. That stop
  comes before any mutation, so the delta was accepted rather than chased.
  Held-out was no longer independent for this candidate, so its rescore
  confirms the fix but isn't a clean held-out result.
- **Relied on the safety map, not the score, for deletion safety.** Each
  removed rule that limits a deletion, a forge write, or an owner hand-back
  maps to a script, `--help`, `references/`, or a remaining sentence. The
  map is in the PR body.

## Findings

- **The guard barely sees prose.** Scored from an export without `evals/`,
  a frontmatter-only `SKILL.md` passed 20 of 21 climb runs (0.952), where
  #392 measured 0.666. The agent rebuilds the procedure from the scripts'
  `--help` and `references/`. The goal file's separation rule still passed,
  since the band was 0.000, but the score guards behavior, not instructions
  the agent happens to follow anyway.
- **Cost.** About $2.60 and 8 minutes per 21-run score at `--jobs 7`, not
  the 3 minutes #392 measured. The whole climb, proving and rescores
  included, cost $44.20.

## Rollout

Chose to roll out skill by skill, each with its own scored eval first,
over climbing skills that have none. The owner chose `land-approved-prs`,
`visual-evidence`, and `await-pr-review`, one at a time (tracker #445). Each
eval proves sensitivity with a single dropped section, not only a
frontmatter-only copy, and covers rules only `SKILL.md` holds. Each climb sets
a relative target and a budget of about 10 attempts. The prose-only skills
(`plan-work-unit`, `plan-and-handle-batch`) stay out: with no bundle to fall
back on, a cut removes an instruction outright.

Revisit when a weaker model or a non-Claude agent runs `merge-cleanup`; the
shorter text leans on the agent reading `--help`.
