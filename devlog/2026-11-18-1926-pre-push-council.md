# Point Pre-Push Review at Council With an Evidence Bar

Issue #391 gives `docs/agent-workflow.md` §pre-push-review a procedure. With
the reviewer record at `none`, this section is the project's only active
review path before a human reads the PR. It now routes risk-class work to the
`council` skill (#388), gives the single reviewer a fixed brief, counts a
finding only once it is reproduced or traced, and re-reviews only while
blockers remain. The change reaches downstream projects through the
agent-setup scaffold.

## Decisions

- **Chose council for four risk categories over all risky work.** Destructive
  paths, credential-leak surfaces, returned-object trust boundaries, and
  contract or public-interface changes use council. A behavior change without
  tests keeps one fresh-context reviewer. Each council round costs a
  high-effort run per member, so #391 limits it to the categories where a
  second provider's view is worth that cost.
- **Chose a standing request in the convention over editing council's "When
  to Run."** Council runs only when the user asks or a calling skill invokes
  it. A project instruction is the owner's request, so the section says so
  outright. Changing council itself was a non-goal of #391.
- **Chose report-only council calls, with the pre-push loop owning fixes and
  re-review, over council's own staging.** Council's staging adds a narrow
  fix check and a final full panel. The pre-push contract re-reviews only
  while confirmed blockers remain, through the same route each round. The
  cost is a full risk-class panel on every round instead of one member
  checking fixes. That is accepted because risk-class work is rare.
- **Chose a fixed brief in a `text` block over a prose description.** The
  same words every round keep rounds comparable, and the output shape (claim,
  `file:line`, blocker or not, failing input or call path) makes each claim
  checkable. The evidence bar follows pstack's `interrogate`, and the brief
  follows tstack's `sol-loop`.
- **Kept no round cap and no required subagent.** The 2026-07-27 note added a
  cap; the 2026-08-02 note removed it in favor of a checkpoint, so "no cap"
  rests on 2026-08-02. The 2026-06-26 note keeps delegation optional, so every
  route names a fallback.

Revisit when council gains a fix-check input for report-only callers, or when
per-round panels on risk-class work prove too costly in practice.
