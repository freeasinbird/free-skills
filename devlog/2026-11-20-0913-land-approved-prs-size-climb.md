# Shrink land-approved-prs's SKILL.md by Measured Climb

Issue #440 ran a `hill-climb` size climb on `land-approved-prs/SKILL.md`,
holding the scored eval from #439. `SKILL.md` went from 6,186 to 4,339 words
(−30%). The climb split stayed at 1.000 with a 0.000 band, and held-out
cases 3 and 4 scored 1.000, as the base did. The climb reached its
4,300-word target at attempt 7; the two reviews of the final diff then
restored 39 words. The result holds for `claude-sonnet-5-5` only.

## Decisions

- **Chose to point at the scripts' header comments over restating them.**
  The scripts have no `--help`, so the agent sees a header only by reading
  the file. `### Running the Engine` and `## Script Results` now say that
  each script's header documents its phases, options, result lines, and
  exit codes. That pointer let the climb cut the phase checks, option
  defaults, and the exit-code table, which was the largest single cut. The
  JSON field lists went too: no header lists them, but each result line
  names its own fields.
- **Kept rules and judgment-bearing rationale; cut the rest.** Every
  `STOP` guard keeps its name and action, every rule in the eval README's
  owner-gated table stays, and so do the label defaults and
  `## Revoking Approval`. Rationale stayed where a judgment call leans on it:
  a stale lock is only suspected dead, the engine is label-blind, a bare
  `git worktree remove` deletes ignored files, and the label is the record
  because the owner gets no notification.
- **Restored the run-id clause after refute-first.** The cut sentence "The
  script treats a lock with this id as yours" was the only text explaining
  that `list-ready.sh` treats a same-id lock as the caller's, so reusing a
  dead run's id from a `lock-stale` message would take the lock over. The
  "unique to this batch" rule alone doesn't say why. The review also caught
  the known-flake rule narrowed to a single issue; the original wording is
  back. The pre-push review then caught that the cut had dropped how the
  cleanup rerun after the sweep retargets stacked children, which would make
  the batch report call them still waiting; both clauses are back.
- **Chose to end the batch on `unsupported-mechanism`.** It used to fall to
  "any other STOP: hand back", but it fires while parsing the record, before
  any PR is chosen, so there was no PR to hand back. It now shares
  `bad-record`'s action.
- **Stopped at the target, as the goal file's stop rule requires.** Three
  of ten attempts were left at the stop; the two review rescores used two. Cuts much below 4,300 would reach rules whose
  only home is `SKILL.md`.

## Findings

- **Every scored attempt held 27 of 27.** Six of seven attempts were kept.
  The one revert was a guard failure, not a score drop: attempt 1 removed
  the last mention of `--head-remote` and `--interval`, which
  `check-skill-structure.sh` requires.
- **The score is a weak guard for this cut.** The eval measured only
  `### Hand-Back` and `## Revoking Approval`. The refute-first review, not
  the score, found the run-id clause. For a skill whose rules live in its
  prose, plan on an adversarial review of the final diff, not just the eval.
- **Cost.** About $3.50 and 4 minutes per 27-run score at `--jobs 7`. The
  whole climb, proving and rescores included, cost about $50.

## Next Skill

Climb `visual-evidence` (#442) the same way once its eval (#441) exists:
prove sensitivity with one dropped section, set a relative target near 30%,
point at bundled script docs before cutting them, and run the guards
locally before each score, since a lint failure wastes a full score.

Revisit when a weaker model or a non-Claude agent runs `land-approved-prs`;
the shorter text leans on the agent reading the scripts' header comments.
