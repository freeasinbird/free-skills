# A Failed Prepare Gets One Rerun but Never Ends the Batch

`land-approved-prs` now gives a `prepare` that returns a transient
`LOOKUP_FAILED` the same single rerun `SKILL.md` gives any script, but only
while the previous PR's `land` still waits (#502). Chose the rerun over
discarding the preparation, and kept a failed `prepare` from ending the
batch or handing the PR back. This follows the lander-prepare-next note,
`2026-11-26-1416-lander-prepare-next.md`, which introduced preparation.

## Decisions

- **Rerun rather than discard.** Before this change,
  `references/prepare-next.md` discarded the preparation on any
  `LOOKUP_FAILED`, while `SKILL.md` reran any script once on a timeout, a
  5xx, a rate limit, or no `stderr` key. A freeside-ai/freeside batch on 2026-11-27 hit a `prepare` head-fetch failure
  and followed `SKILL.md`; the rerun produced a preparation whose tree
  matched what `land --prepared` later pushed. A rerun can't push, comment,
  or touch the PR, and it saves the most wait time on a conflicting PR.
  Discarding costs little on a clean rebase, but nothing makes the rerun
  unsafe: `phase_prepare` clears the prepared refs before it builds anything,
  and its `EXIT` trap removes the temporary worktree, so the rerun starts from
  the first try's state.
- **A failed `prepare` never ends the batch.** `SKILL.md` ends the batch on
  a 404, a permission or authentication error, or a failed rerun. For
  `prepare` those outcomes take the ordinary path after A merges instead.
  B's own `check` and `land` meet any lasting failure, and `SKILL.md`'s rule
  handles it there, so ending early from `prepare` would only act sooner on
  a read that the ordinary path repeats.
- **The eval fault keys on the process, not the fetch count.** Case 12's
  `git-fault` fails the head fetch of the first `land.sh prepare` process,
  however often it retries. It walks up to the outermost ancestor that runs
  `land.sh` under bash, so subshells count as the same process. #506 (for
  #501) retries git fetches inside the engine, so a fault that failed only
  the first fetch would let a retry in the same process pass and hide
  whether the agent reran. The grader counts distinct processes: exactly
  two means one rerun.
- **Case 12's prompt asks for preparation.** With the standard prompt, four
  pilot runs never read `references/prepare-next.md` and ran each `land` in
  the foreground, so no `prepare` ran and the case couldn't observe the
  rule. Adding only the fact that the platform runs background commands
  changed nothing in two more runs. The prompt now says to run each `land` in
  the background and prepare the next PR during its wait, which leaves the
  `LOOKUP_FAILED` handling, the behavior under test, to the skill. That the
  skill alone doesn't lead the agent to prepare is a separate gap.
- **The fixture forge models a late check.** `lib/gh` reported every check
  as completed, so `land`'s CI wait lasted one poll, too short to prepare
  anything. A head with `ci/<oid>.slow` now shows only `test` to its first
  read (`check`'s), then a `slow-test` run in progress for a set time. That
  is the case `ci_wait`'s two-green-read rule exists for.

Revisit when `prepare` stops clearing its refs first or stops removing its
worktree on exit, since the rerun's safety rests on both.
