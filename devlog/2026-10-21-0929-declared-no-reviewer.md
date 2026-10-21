# Declared No Automated Reviewer

The shared workflow now lets a project's owner record that the project has no
automated PR reviewer: a reviewer record whose reviewer is `none`. With that
record, the handoff starts no review watch and `await-pr-review` stops before
routing, without scanning PR history or recording a reviewer it sees there.
With no record at all, nothing changes.

The trigger was Freeside and this repository, which both turned off automatic
Codex reviews and each needed a project override, because the shared text said
"never record an absence" and its handoff always started a watch. Without a
stated absence, detection found Codex on older PRs, waited out the cap, and
tried to record it again.

- **Reuse `none` from the landing record instead of a new token.** Chose a
  `Reviewer:` bullet valued `none` because land-approved-prs already reads
  that value as "no reviewer". Rejected: a free-form "None" section like
  Freeside's, which an agent can't tell apart from prose.
- **Keep a landing record's `Reviewer: none` from counting as the
  declaration.** list-ready.sh needs some Reviewer value and its error text
  tells projects with no recorded reviewer to use `none`, so a landing `none`
  can also mean "nothing recorded yet". Treating it as the owner's absence
  would stop discovery in a project whose bot simply isn't recorded.
  land-approved-prs is unchanged.
- **Only the owner writes the record.** Silence, a quiet PR history, or a
  reviewer that stopped posting can't establish it, so agents never infer it.
  The agent-setup audit reports it as present and keeps it verbatim; it
  offers one only when the owner says so.
- **Stop before routing, not inside the conductor.** The cost to avoid is the
  history scan and capped wait, which a conductor would run before it learned
  anything. Rejected: a per-PR override for a user who asks to await a named
  reviewer anyway. The conductor would treat that reviewer as unrecorded and
  write it into the owner's record; changing the record is the owner's path.
- **Keep risk-scaled review as it was.** The mechanical-change line now names
  the human reviewer when there is no bot, but §pre-push-review still asks
  for fresh eyes on risky work and on other work without a bot reviewer, and
  still falls back to the human when the agent can't delegate. Rejected:
  requiring a fresh-context review on every PR, which stays a per-project
  choice.
- **Convert this repository's override into the record.** The "Expect no
  automated reviewer" convention now carries the `none` record; its "skip the
  watch" instruction moved into the managed handoff text.

Revisit when a project needs to declare a reviewer that runs only on manual
request, which this record doesn't express.
