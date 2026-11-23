# Finished Report Stays Inline

`plan-work-unit` keeps its Finished report rules and Platform Gates in
`SKILL.md`, not behind a pointer into `references/handoff-report.md`. Chose
this over a more forceful pointer because text that every successful run needs
at its last step is the text an agent is least likely to look up. Only text for
a conditional branch, such as Blocked or Paused, belongs behind a pointer.

## Evidence

- **A planner skipped the lookup.** After #479 moved Finished, Blocked or
  Paused, and Platform Gates into `references/handoff-report.md`, a planner on
  freeside-ai/freeside `Plan #3469` (2026-11-23 UTC) never opened §finished. It
  wrote a free-form report of about 400 words, with headings, no fixed Status
  line, and the kickoff as an inline sentence instead of its own `text` block.
- **The pointer was clear but badly placed.** It sat at the end of the run,
  when the context is longest and writing a report feels familiar. Pointers to
  conditional branches don't have that problem, because the branch itself is
  the signal to stop and read.
- **The evals could not catch it.** `planning-eval.json` checked only that the
  report contained the kickoff text, so the free-form report would likely have
  passed. Its scoring now grades the report's shape: Status form, bold lead
  words without headings or tables, and the kickoff alone in a `text` block.

## Settled Points

- **Platform Gates moved inline too.** They apply to every handoff report, so
  they had the same skippable lookup.
- **Blocked or Paused stays in the reference.** It runs only when planning
  blocks, which is the case #479 moved text out for.
- **The plan-comment shape stays in `references/plan-comment.md`.** It lived
  there before #479, `SKILL.md` already names its five parts, and inlining it
  would add about 360 words for little gain.
- **`SKILL.md` grows past #479's soft size range.** It goes from 2,236 to
  2,746 words, above the 2,000 to 2,300 range. The total across `SKILL.md` and
  `references/` stays about the same, since the text moved rather than grew.
- **Rejected: a more forceful pointer.** Stronger wording would still depend
  on the agent stopping to read at the step where it least wants to.

This incident meets the "Revisit when" condition in
[the plan report contract note](2026-10-21-2151-plan-report-contract.md):
reports drifted from the shape.

Revisit when forward tests show finished reports drifting even with the rules
inline, or when `SKILL.md` size itself starts causing skipped sections.
