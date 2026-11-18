# plan-and-handle-batch evals

These fixtures test routing and the orchestration contract. Keep transcripts,
simulated delegate output, and grading in a scratch workspace outside the
repository.

## Files

- `trigger-eval.json` separates batch plan-and-handle requests from a single
  plan or handle step, plan-only and implement-only batches, triage, and
  landing.
- `orchestration-eval.json` describes orchestration inputs and the actions
  each case requires or forbids.

## Orchestration Cases

- `no-background-delegation`: Stop with an error naming the missing
  capability; plan and implement nothing.
- `plan-work-unit-missing`: Stop with an error naming `plan-work-unit`.
- `set-named-earlier-resolves`: Run one explicit earlier list in its order and
  name it in the opening message.
- `two-candidate-sets`: Ask which list is meant; launch nothing.
- `set-described-by-criteria`: Ask for numbers; launch nothing and search
  nothing.
- `window-from-words-and-default`: Read "one at a time" as 1; state the
  default of 3 when no number is given.
- `window-never-exceeded`: Keep at most the window running and start the next
  queued issue when a slot frees.
- `planner-question-relayed`: Relay a pre-write planner question and return
  the answer to that planner.
- `non-startable-plans-held`: Dispatch only `startable now`; report blocked,
  held, and planning-blocked issues.
- `prerequisite-inside-batch`: Leave a dependent issue undispatched while its
  prerequisite in the batch awaits a human merge.
- `threads-before-subagents`: Use threads where offered; otherwise brief
  subagents with the branch setup.
- `run-ends-without-report`: Free the slot and never restart the run.
- `resumed-session`: Read the state file first and relaunch nothing.
- `final-table-every-issue`: Report every listed issue in one table.

## Rerunning Trigger Cases

Run each trigger query in a fresh context that sees only this skill's
`description` and the query. Ask whether the skill should load, and compare
the answer with `should_trigger`. Use a fresh delegate per query where the
platform offers one; otherwise use a new session per query. Include
`plan-work-unit`'s description beside this one when testing the single-issue
negatives, since those queries should route there instead.

## Rerunning Orchestration Cases

Run each case in a fresh context with the skill, the case `request`, and its
`artifacts`. Keep `required_actions`, `forbidden_actions`, and this README out
of the task context. A controller plays the platform and the delegates: it
lists the tools the case names and returns each planner and implementer
result from the artifacts. Never start real planners or implementers against
real issues.

Grade the launches, briefs, waits, state-file writes, messages to the owner,
and the final table against the case. Grade each presentation of a
two-presentation case in its own fresh context.

## Structural Validation

Parse both JSON files with `python3 -m json.tool`, directing output to scratch
files. Confirm 14 unique orchestration IDs match the inventory above. Parsing
validates structure only; it doesn't grade model behavior.
