# Offer a Claim Record in agent-setup

agent-setup now offers a claim record to projects that run concurrent
dispatch. The record is a `## Claiming` section in unmanaged AGENTS.md
content. Its template lives in
`skills/agent-setup/references/project-sections.md` §claim-record. Issue #418
carries the contract; #417 adds the same shape to free-skills itself.

## Decisions

- **Chose an explicit offer over "never invent one silently".** The old rule
  let setup record claim handling only when a project already had a
  mechanism. A project that dispatched issues in batches had no supported way
  to get claim rules, so two overlapping dispatches could start one issue
  twice. The plan-and-handle-batch skill counts an issue as occupied only by
  an open PR when the project defines no rules. The owner decided setup may
  write claim rules, but only after the owner accepts the offer. The ban on
  placeholder claim rules in `coordination-discovery.md` §record stays.
- **Chose a gated offer over claim rules for every project.** A serial
  project has no second worker to collide with. Rules it never uses would
  cost every session that loads AGENTS.md, so no record still means no claim
  rules.
- **Chose a project record over a fallback marker inside skills.** The forge,
  landing, and post-merge records already follow one pattern: agent-setup
  defines the record, AGENTS.md holds it, and skills read it. A marker
  hard-coded in plan-and-handle-batch would give two sources for one rule and
  would bind projects that already have their own mechanism.
- **Rejected draft PRs as the claim signal.** The owner rejected them. A
  draft PR needs a pushed branch, so it can't mark the window before the
  first commit.
- **Chose the label as the default marker, with Assignees as a variant.**
  One owner's agents usually share a forge account, so an assignee can't
  tell one run from another. The claim comment names the run and carries the
  expiry. Assignees is the better marker only when several people work under
  their own accounts.
- **Left the expiry length to the owner, with 24 hours as the suggestion.**
  The right length depends on how long a run waits on the owner. The template
  requires the record to state why its length was chosen, and a
  noninteractive run writes nothing.
- **Kept the template as prose, not a parser contract.** Skills read the
  Claiming section as written. Update mode therefore preserves a reworded or
  project-specific record verbatim and never reports it as drift.
- **Copied free-skills' merged Claiming section as the template.** #417
  landed first, so the template takes its text, with the expiry length and
  its reason left open. `devlog/2026-11-18-2238-claim-rules.md` holds the
  reasons for the label, the comment marker, the reread, and release by
  deleting the comment. One shape in both places lets the dogfooded-files
  row verify them by a side-by-side read.
- **Made tracker issues evidence of concurrent dispatch, not proof.** A
  project can keep tracker issues and still work one unit at a time. An
  owner statement or project text that work is serial closes the gate.
- **Accepted the remaining races.** A label and a comment can't be changed
  atomically, so two runs can still interleave within seconds of an expiry
  or a release. Pre-push review raised several such cases. Each needs a
  crash or an expiry inside a window of seconds, and the cost is one
  duplicated or delayed unit, so the template stays short instead of
  guarding each one.

## Assumptions

- **Skills that read claim rules need no change.** plan-and-handle-batch
  already looks for a Claiming section and applies its expiry and release
  rules as written, and the managed Branches block already points agents at
  the project's claim.
- **The planning window stays open.** The template covers implementation
  claims only. Nothing reserves an issue while it is being planned.

Revisit when a skill needs to parse the record mechanically, or when a
project needs a planning reservation.
