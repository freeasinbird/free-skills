# Drop Codex as the Automated Reviewer

The owner turned off automatic Codex reviews for this repository. The project
now records no automated reviewer, and the landing record's Reviewer is
`none`.

- **Remove the reviewer record rather than keep Codex as a manual reviewer.**
  With automatic reviews off, Codex reviews only when someone comments
  `@codex review`. A record that still named Codex would make
  `land-approved-prs` filter 6 wait for a summary row that no push produces,
  so every approved PR would stall until someone remembered the manual
  trigger. Rejected: keeping Codex with a manual Trigger line, which leaves
  the landing gate on a step people forget.
- **Set the landing Reviewer to `none` instead of deleting the bullet.**
  `list-ready.sh` gives Reviewer no default and stops `bad-record` on a
  missing bullet, so `none` is the explicit way to turn filter 6 off. The
  completion marker bullet goes with it; the script reads it only for a
  named reviewer.
- **Say so in AGENTS.md instead of leaving the record silently absent.** The
  managed pull-requests block tells agents to record an automated reviewer
  they observe. Without a stated absence, a manual `@codex review` run could
  lead an agent to record Codex again. The handoff step also starts
  `await-pr-review` when installed, and its detection would find Codex on
  older PRs and wait on it. The replacement bullet skips that watch and
  reserves the reviewer choice for the owner.
- **Keep the stale lock age at 240 minutes.** Its reasoning no longer
  includes a reviewer wait, but the CI and merge caps still need 180 minutes,
  and a larger margin costs only a slower recovery from a crashed batch.

Without a bot reviewer, the managed pull-requests block already routes every
push through `docs/agent-workflow.md` §pre-push-review, and handoff relies
on a human reviewer. No managed text changes.

The 2026-06-27 and 2026-07-02 notes on Codex detection stay as the history of
that record. `await-pr-review` keeps its Codex examples; they describe how the
skill works with that reviewer anywhere, not this project's setup.

Revisit when the owner enables an automated reviewer again: observe it on a
PR, record it per §reviewer-record, and restore the landing Reviewer and
completion marker.
