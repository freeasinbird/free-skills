# Handoff Report

## §finished

Write the report in this order, with bold lead words and no headings or
tables. Aim for 120 to 200 words. Omit a part only where its rule says so.

1. **Status.** One line in one of three forms, linking the issue once:

   - Startable: `#N planned, startable now`.
   - Implementation blocked: `#N planned, blocked on #M until <event>`.
   - Held: `#N planned, startable but I'd hold: <reason>`.

   Name the contract record here only when it is not the issue body. Status
   already says planning finished, so add no separate statement that
   implementation was not started.

2. **Result.** One or two sentences on what the change does once built, in
   behavior terms, not record terms. Mention size or shape only when it
   changes a decision, such as a proposed split or a contract unit.
3. **What planning changed.** Up to four one-line bullets. Cover corrections
   to the issue's premise, scope added or removed, an approach chosen where
   the issue left it open, and dependencies reconciled. Also name any
   coordination record, assessment, or other issue or tracker you edited,
   with the issues it is on. Write "Nothing beyond completing the contract"
   when that is true.
4. **Your call.** Up to three bullets, each a choice you made that the owner
   can veto, naming the chosen default. Assumptions that don't change the
   plan stay in the contract. Omit when there are none.
5. **Not verified.** Up to two bullets of claims the plan rests on that you
   read but did not run, or write-safety gaps that no reread closes, such as
   a whole-body write that could lose a concurrent edit. If the default
   branch advanced during planning, say so in one line and recommend
   verification or a replan. An unchecked-occupancy line (see Check
   Occupancy) doesn't count toward the two. Do not reinspect and republish
   here. Omit when there is nothing to report.
6. **Kickoff.** The kickoff prompt for a fresh implementation task, with the
   real issue number in place of `N`:

   ```text
   Handle #N, implementation plan in comments.
   ```

   This prompt is for the user to send; sending it is the separate
   implementation assignment. If an implementation blocker or hold remains,
   precede the prompt with one clause saying when it applies, such as "after
   #M merges" or "once you settle X".

Leave out the record locations, the grounding revision, the plan's steps, and
read-back narration. The plan comment carries the grounding revision.

## §blocked-or-paused

A blocked report keeps **Status** and **What planning changed**. Status says
planning is blocked, not finished, and names the precise blocker, as in
`#N planning blocked: <blocker>`. This differs from a finished plan whose
implementation waits on another unit.

- Add one line on what clears the block.
- Give the recommended action before any options.
- Verify any required prior-plan invalidation before reporting.
- If the prior plan remains actionable, report its location as an unsafe
  state, unless the block is occupancy (see Check Occupancy).
- Never hand off an incomplete authoritative record.
- Omit the implementation kickoff prompt.

A mid-planning question leads with your recommendation, then asks the
question, then stops. Send no partial report with it. Ask it only before any
planning write persists; after one does, report Blocked instead.

## §platform-gates

- **End on the report.** The report is the final message of the operation.
  Where the platform can end a turn on background work, the report must
  still be the last message.
- **Compress any recap box.** Where the platform shows a recap box, its recap
  is Status, Result, and What planning changed in three sentences. For a
  blocked report, it is Status, what clears the block, and the
  recommendation. Its question is a pending Your call item, or nothing.
- **Propose no task or session card.** Where the platform offers task or
  session cards, do not propose one. The kickoff prompt is the only handoff.
