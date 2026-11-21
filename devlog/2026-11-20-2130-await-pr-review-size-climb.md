# Shrink await-pr-review's SKILL.md by Measured Climb

Issue #444 ran a `hill-climb` size climb on `await-pr-review/SKILL.md`,
holding the scored eval from #443. `SKILL.md` went from 1,884 to 1,606
words (−15%). The climb spent its 8-attempt budget at 1,589 words, 89 short
of the 1,500 target. Review fixes then added 17 words. The final candidate
scored 1.000 on the climb split and 1.000 on the held-out split, as the
base did. The result holds for `claude-sonnet-5-5` only.

## Decisions

- **Chose pointers over restatement.** The three largest cuts removed prose
  that restated `references/conductor.md` §probes and §spawn-brief (130
  words), `references/detection.md`'s polling contract (58), and
  `references/review-response.md`'s hardening, checkpoint, and recurrence
  sections (51). Every routing pin, convergence pin, `##` heading, and
  `references/` pointer stayed, so the eval README needed no edit.
- **Allowed one failed run per score, by owner decision.** The proof
  record's 0.000 noise band didn't reproduce: the unchanged base rescored
  0.944 on Claude Code 2.1.330 (one case-5 run left the new reviewer record
  uncommitted). With 1 failure in 54 base runs, an all-18-pass rule would
  revert about three good candidates in ten. The owner chose to let the
  scored guard hold at 0.944 or above.
- **Continued to the budget, by owner decision.** After attempt 3, the
  owner chose to spend the remaining five attempts rather than stop early.
  They saved 4 to 17 words each.
- **Restored three weakenings the review found.** A fresh-context review of
  the final diff, comparing old and new text rule by rule, found no lost
  deletion, forge-write, or hand-back rule. It found three smaller losses:
  - "Address feedback already in hand without a watcher" had no other home.
  - Step 3's scheduled wake had lost its "only when the loop can't delay
    in-turn" condition.
  - The spawn brief read as containing only the task contract.
- **Declined four review findings.** Each rule lives in a reference that
  `SKILL.md` still points to: the class-recurrence procedure, the
  hardening check's fix rule, the main-owned ladder's other rungs
  (including the handoff), and the grants' fail conditions.
- **Folded the review fixes into the last commit.** Each attempt commit
  names the score of the state it holds. Folding a fix into an earlier
  attempt would make that claim false, so the last commit carries the
  fixes and names them.

## Findings

- **The score was a weak guard again.** Every score was 1.000 or 0.944.
  The review, not the score, found every weakening above.
- **Case 1 failed once in each of attempts 5 and 6.** Both times the
  conductor treated an old, resolved nit as a current finding. Attempts 7,
  8, and the post-review rescore passed case 1 nine of nine on the same
  text, and the proof saw this mode under several section drops, so it
  reads as noise. It's the first place to look if case 1 drifts.
- **Pins set the floor.** About 30 routing pins and 13 convergence pins
  sit in Route Ownership and steps 4 and 5. Under 1,600 words, nearly every
  remaining sentence is a pin or a goal-file Constraint.
- **Cost.** About $3.50 to $4.40 per 18-run climb score. The base rescore,
  8 attempts, held-out, and post-review rescores cost $41.39.

## Next Climbs

- **Don't size-climb `plan-work-unit` or `plan-and-handle-batch` yet.**
  Tracker #445's exit asks this question. Both skills are prose-only: about
  3,800 and 3,900 words, with one 390-word reference between them and no
  scripts. The cuts in #393, #442, and this climb came from prose that
  restated a script or reference. Without one, a cut has to drop a rule,
  which the score can't see. Neither skill has a scored eval yet, and
  #443's proving cost about $67.
- **Revisit when** either skill gains a script or reference that its prose
  restates, or a review-led edit has already moved mechanics out and a
  scored eval exists.
