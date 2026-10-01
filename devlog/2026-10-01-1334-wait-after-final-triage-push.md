# Wait for the Reviewer After the Final Triage Push

Chose to wait for the review a final triage push triggers, under main and
conductor ownership alike, over handing the PR off with that review pending.
The owner decided this by filing issue #280.

This reverses one decision in `2026-08-14-1455-review-loop-authorization.md`.
That note accepted, "by decision", that "a main-owned final-triage push may
record its re-review as pending". Its other decisions stand, including the
fully covered quiet timeout as a terminal state.

## What Changed

The earlier decision assumed the last pass was a formality and that a
main-context wait cost more than it returned. An incident on a docs-only PR
in a private project, with Codex as the reviewer, contradicted both:

- The agent made its final triage push and reported the PR ready. Codex
  posted a review with two P2 findings four minutes later.
- Both findings were in the same class as every earlier round, and the
  agent's own sweep had found them and set them aside. The skipped pass was
  the one most likely to say something.
- The wait saved was four minutes. Its cost moved to the owner, who had to
  check a "ready" claim and then run another exchange.

Two weaknesses in the wording made the failure likely anywhere:

- **The layers disagreed on who could skip the wait.** `await-pr-review`
  limited it to a main-owned exchange. The scaffolded `## handing-off` text
  had no ownership qualifier, and the main agent used it to tell its
  conductor not to wait.
- **The pushing agent judged its own push.** The scaffold said only "locally
  verified", and the agent that wanted to stop made that call.

## Decision

After any push that triggers the reviewer, the exchange owner waits for that
review to finish or for the bounded watch to time out, then reports
readiness. "The reviewer is known to be in progress" blocks readiness with no
exception.

Chose a replacement paragraph in `## handing-off` step 6 over deleting the
exception outright. The agent in the incident read only the project's copy of
that step. With nothing there about the last push, §review-convergence's "one
final push" could still read as permission to stop. The paragraph also says
what to do with the last review's findings: a blocker reopens fix rounds, and
a review with no blocker gets deferrals or declines without another push.

## Rejected Alternatives

- **Keep the exception and add the ownership qualifier to the scaffold.**
  Rejected because the incident's findings would still have arrived after
  the ready report in a main-owned exchange.
- **Tighten "locally verified" instead.** Rejected because the agent that
  wants to stop still makes the call, and the wait it saves is short.
- **Remove the final triage push.** Rejected as out of scope: the rising bar
  still needs one verified push for non-blockers. Only the early hand-off
  goes.

## Unchanged

- **The step 1 fallback in `## handing-off`.** A platform that can't wait at
  all still hands the PR back and names the review as pending. The step's
  text doesn't yet say that this hand-back isn't a ready report.
- **The bounded watch.** A reviewer that never answers still ends in a
  covered timeout, so the wait stays bounded.
- **The cost model.** Its main-ownership cost already counts one wake for
  every review round.

Revisit when: the wait after a final triage push regularly runs to the watch
cap without a review, or measured outcomes from #245 show the last pass
almost never returns a finding.
