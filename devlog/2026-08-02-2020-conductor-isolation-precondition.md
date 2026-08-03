# Checkout isolation is a precondition to establish, not a gate to check

Observed live in a Codex (app) session on an unrelated repo's PR 478: the
agent declined conductor ownership with "the review skill's
isolated-conductor gate is not available in this shared checkout" and ran
the bounded foreground watcher instead, blocking its own thread for the
wait. Subagents, write access, and a shell were all available to it; the
only missing piece was an isolated checkout, which it could have created
with `git worktree add` at any point. When the user pointed this out, the
agent agreed immediately and switched, having already paid for one
watcher.

The misread was invited by the skill text, not invented by the agent.
Three properties of the pre-change wording produced it:

- **False parallelism at the routing decision.** The step-0 gate listed
  "checkout isolation or exclusivity for the PR branch" alongside three
  genuine platform capabilities (write-capable delegation, resumability,
  completion re-entry). Four grammatically parallel items read as four
  things the platform either extends or withholds.
- **A passive framing instruction.** "Map the gate against what the
  platform actually offers" told the agent to inventory features, which
  is the correct move for three of the four items and the wrong move for
  the fourth.
- **The Claude Code example generalized wrongly.** "Worktree isolation at
  spawn satisfies the checkout grant" reads as a native spawn-time
  feature. A platform without that spawn parameter reads itself as
  lacking the grant, though plain `git worktree add` was always the
  platform-agnostic path (AGENTS.md's own Branches section already names
  it).

The escape hatch existed ("otherwise grant it exclusivity over the shared
checkout") but sat ~670 lines below the routing decision, at the end of a
step-4 paragraph. A scanner routes at step 0 and never reaches it.

## Decision

Split the conductor gate by kind wherever it appears: three platform
capabilities you check, and one precondition you establish. Checkout
isolation is stated as establish-first with three ordered routes (native
mechanism, plain `git worktree add` or a clone, declared exclusivity over
the shared checkout), and the observed bad inference is named and refuted
in the text: a shared default checkout is never itself a reason to fall
back, because it is the starting state isolation is established from.
Naming isolation as the unmet gate now requires having found all three
routes unavailable.

Applied in four places so the skim layer stops carrying the old
parallelism: the frontmatter description, the step-0 ownership decision,
the step-4 gate paragraph, and the platform-support ladder bullet (where
isolation is removed from the ladder entirely, since a ladder rung is by
definition a grant the platform extends or withholds).

The establish-isolation paragraph names the route in prose, a detached
worktree at the PR head or a separate clone, and prescribes no command
at all. Naming the route is what refutes the misread (isolation is
establishable wherever there is a shell); every mechanic behind it is a
separate work unit, below.

**A runnable command was tried here and withdrawn.** An intermediate
revision prescribed the sequence, reasoning that a named route which
cannot resolve its own head is wrong rather than merely incomplete.
Three real failures back that reasoning, verified on git 2.50.1:
`git worktree add` resolves its commit-ish locally, so it fails on a
host-resolved head the checkout has never fetched; a bare force-push
with a pinned lease from the detached checkout supplies no refspec and
fails for want of a branch; and a fork head fetched from the base
repository fails or retrieves a same-named base branch.

**The reasoning is sound and the conclusion still went the other way.**
Prescribing the sequence drew six further review rounds, and the round
that followed the last of them raised a leading-hyphen branch name
parsed as a fetch option: the hardening surface of a runnable command
is unbounded in prose, and each clause added invites the next finding.
That is this skill's own signal that prose is re-deriving a program, so
the three failures above are recorded here as evidence for why the
mechanics are the follow-up's tested script, not as clauses to patch
into this unit. Owner's call, 2026-08-03, over the intermediate
revision's boundary.

## Split into two work units

The original PR carried this reclassification and, appended to it, a
lifecycle script that grew out of prescribing the route. In eight review
rounds the reclassification drew zero findings and the script drew all
of them, so the owner's call (2026-08-03) was to split, and let each be
judged as what it is. The reclassification is this note's decisions
above and below; the isolation script, the prescribed lifecycle, and
this note's lifecycle sections are the stacked follow-up.

## The sibling gate: permission, resolved by attempting

The review exchange surfaced that the conductor gate's _first_ clause has
the same defect this note's main decision fixed in its fourth. "Write-capable
delegation **permitted without asking**" asks the agent to predict a
permission, exactly as the old isolation wording asked it to check for a
checkout, and a prediction of "not permitted" is unfalsifiable: nothing
later contradicts it, so the exchange silently runs in the expensive
context forever.

The evidence was this session. Delegation was simultaneously forbidden by
injected session guidance, permitted by the owner's own global
conventions ("one subagent for exploration or review is normal"), and
routinely exercised by other skills in the same session. The agent
followed the strictest reading and never tested it, paying five review
rounds of full-context replay for a permission it never checked. The
owner's observation that authorization "is inconsistent, and some of the
time it _is_ authorized" is the general case, not this session's quirk:
authorization is per-pathway, not per-capability.

**Decision: attempt once and route on the outcome.** A refusal is cheap,
observable, and recorded as "refused when attempted"; a prediction is
none of those. Ambiguity resolves toward attempting. The carve-out stays
narrow: a policy that plainly forbids the spawn, where attempting is the
violation rather than the test.

**A policy that merely conditions the spawn is not that carve-out; it is
the paradigm case for attempting.** Rejected: widening the carve-out to
cover approval-conditioned policies, tried and reversed. The falsifiable
evidence is this
work unit: session guidance carried "do not call the delegation tool
unless the user requested it", which reads as forbidding, and on both
occasions it was actually attempted, in two separate sessions, the spawn
went straight through with no permission prompt and no refusal. The first
misread cost six review rounds of main-context replay, the second one
round. Widening the carve-out would route exactly that class to the
fallback, reinstating the prediction this decision exists to remove.

**That directive was a shipped default of one platform configuration,
not one operator's setup.** On the configuration this work ran under,
the agent platform's own system prompt told the agent not to delegate
unless the user asked, while the same session's project conventions and
bundled skills exercised delegation routinely. No local configuration
reconciled them: the text was absent from the user's settings, the
user's global instructions, this repo's AGENTS.md, and the installed
plugins, and whether it appeared was decided by the platform rather than
by the operator. An agent that predicts the permission therefore
mispredicts by construction there, for every user of that
configuration. Not claimed: that this holds for other models, other
sessions, or other versions; the specific configuration was checked
once, at one point in time, and a platform can change it at any moment
without notice.

That is also the direct refutation of the review finding. The policy it
would have honored as a no-spawn case is the default in that
configuration, so honoring it disables conductor ownership there
entirely. The skill prose stays platform-agnostic per the architecture
invariant; this note carries the platform specifics.

Stated at both altitudes, for the reason the main decision was: the
ownership call happens at step 0, so a rule reachable only from step 4,
some 700 lines below, is unread by exactly the agents that route without
it. Step 0 carries the instruction, step 4 the argument and the
carve-out.

**Not the ask-once alternative**, which an earlier draft of this note
carried and the owner rejected: converting the unmet carve-out into a
prose question spends the turn this decision exists to save and returns
policy rather than the approval itself. The turn is better spent on the
next permitted path, which the user can override at any point.

Rejected: leaving this to the operator's configuration. The owner can
grant a standing permission, and probably should, but a skill whose
routing collapses when two authorization signals disagree is defective
independent of any one operator's setup, and disagreement is the normal
condition.

## Rejected alternatives

- **Fix only the step-4 paragraph** (where the observed sentence lives).
  The routing call happens at step 0; leaving the parallel four-item list
  there would have preserved the misread for exactly the agents that
  route without reading step 4 in full.
- **Add a Codex-specific carve-out.** The defect is platform-agnostic
  phrasing that happened to fail on Codex first. Any platform without a
  native isolation spawn parameter, which is most of them, reads the old
  text the same way.

Revisit when: a platform appears where an agent genuinely cannot create a
second checkout and cannot hold exclusivity over the one it has (a
sandbox with no `git worktree` and concurrent writers). That would make
isolation a real gate again on that platform, though still not a ladder
rung elsewhere.
