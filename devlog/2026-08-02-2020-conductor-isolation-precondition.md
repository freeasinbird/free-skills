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

The establish-isolation paragraph names `git worktree add --detach` as
the platform-agnostic route. The route name is what refutes the misread
(isolation is one command away wherever there is a shell); the
lifecycle behind that command is a separate work unit, below.

**Where the split boundary actually fell.** The intent was to name the
route and stop, leaving all lifecycle to the follow-up. The boundary
moved, because the named route was wrong as written rather than merely
incomplete. Three failures, verified on git 2.50.1: `git worktree add`
resolves its commit-ish locally, so it exits `fatal: invalid reference`
on a host-resolved head the checkout has never fetched; a bare
`git push --force-with-lease=<branch>:<sha>` from the detached checkout
that route creates exits `fatal: You are not currently on a branch`,
since the lease argument supplies no refspec; and a fork head fetched
from the base remote fails or retrieves a same-named base branch, so the
remote placeholder has to name the PR head's own repository, resolved
from the host.

**Decision: the route's own preconditions belong with it; its lifecycle
does not.** What the named route needs in order to work (the fetch
before the add, the `HEAD:<pr-head-branch>` refspec on the push, and the
`<pr-head-remote>` placeholder carried through both) sits in this work
unit, because a named route that cannot resolve its own head is wrong
rather than incomplete. Everything past that point (teardown,
realignment, staleness of the primary checkout, and the fork-aware fetch
lifecycle behind the placeholder) belongs to the follow-up, where it is
a tested script rather than prose. Treat those three corrections as
decided rather than re-deriving them, and take further refinement of the
sequence to the follow-up rather than growing prose here.

## Split into two work units

The original PR carried this reclassification and, appended to it, a
lifecycle script that grew out of prescribing the route. In eight review
rounds the reclassification drew zero findings and the script drew all
of them, so the owner's call (2026-08-03) was to split, and let each be
judged as what it is. The reclassification is this note's decisions
above and below; the isolation script, the prescribed lifecycle, and
this note's lifecycle sections are the stacked follow-up.

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
