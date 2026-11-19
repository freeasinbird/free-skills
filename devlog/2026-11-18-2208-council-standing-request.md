# Let Council Honor Pre-Push's Standing Request

Issue #408 finishes the standing request that #391 put in
`docs/agent-workflow.md` §pre-push-review (see
`devlog/2026-11-18-1926-pre-push-council.md`). Two canonical texts still read
against it: council's "When to Run" accepted only the user or a calling skill,
and the managed `context` block asks before running more than one delegate
unless a budget is already set. A downstream Tier A pre-push review hit the
second conflict while syncing freeside-ai/freeside, PR 3419.

## Decisions

- **Chose to name project instructions in council's "When to Run" over
  leaving council alone again.** #391 argued that a project instruction is
  the owner's request, so council's "the user asks for it" condition already
  held. An agent reading council alone still sees only the user and a calling
  skill, and may refuse or ask. Council now lists a project instruction for a
  named class of work as a third requester. The "named class" limit keeps
  "never on your own initiative" true for everything else, and an eval case
  pins the uncovered path.
- **Chose to state the delegate budget in §pre-push-review over naming an
  exception in the managed `context` block.** The bullet now says the
  standing request is a budget the owner set in advance: one council panel
  per review round, at the rung council picks. The `context` block's "stay
  within a budget they already set" then holds unchanged. Keeping the request
  and its budget in one place leaves the managed block, `canonical-sections.md`,
  and every downstream `AGENTS.md` untouched. It rests on the same reading as
  #391: the context block's "they" covers the owner speaking through a
  project instruction. The budget caps each round, not the number of rounds;
  rounds continue only while blockers remain, and §review-convergence's
  reassess step bounds a long run, as the 2026-08-02 note chose over a cap.
- **Kept council's `description` and "State the Cost First" unchanged.**
  "Never run it on your own initiative" stays true under a standing request,
  since the project asked. The cost rule already applies before every launch;
  "When to Run" only says a standing request doesn't skip it. Leaving both
  sections alone also keeps clear of #409 and #410, which edit them.

Revisit when the owner rejects the reading that a project instruction speaks
for the user in the `context` block. Then name the exception in that block,
which pulls in `canonical-sections.md`, `AGENTS.md`, and the managed-sync
check.
