# Give the rotation trigger an observable proxy and name its handshake turn

Issue #148 closed the non-blocking gaps a post-review sanity check found in
the conductor rotation protocol shipped by #146 (issue #140). This note
freezes the three consequential decisions and the three lesser-item
dispositions. It refines, and does not overturn, the rotation design in
`2026-08-20-1137-compact-review-conductor-context.md`, which is frozen on
merge; that note is linked, not edited.

## Rotation trigger: a two-condition qualitative proxy

The rotation inequality `K × (C_old - C_new) > H_old + S_main + R_new` gates on
the expected remaining conductor calls and the old and new context-replay
sizes. None of those terms is observable on current hosts: no host exposes its
own context size, the replacement's, or a remaining-call count. Left as
written, the rule silently reduced to conductor judgment with no stated proxy,
which the #146 note conceded in its "Revisit when" line.

Decision: state the unobservability plainly in `cost-model.md` and give a
qualitative proxy the conductor can apply at a convergence checkpoint. Rotate
only when **both** hold: (a) the checkpoint's evidence expects several more
blocker-sustained fix rounds, not a final triage push; and (b) the conductor
shows replay strain: re-reading or re-deriving its own earlier output, host
compaction or context-limit warnings, or repeated within-turn state
reconstruction. Either condition alone keeps the existing conductor.

Two conjoined conditions rather than one: condition (b) alone (strain) would
force a handoff even when little work remains, where the reset cannot repay;
condition (a) alone (more work) is the normal steady state and would make
rotation routine rather than exceptional. Requiring both keeps rotation the
rare optimization the design intends. The proxy stays advisory: it never
becomes a fixed round, time, idle, or context-size kill switch, so the
non-goals of #148 hold.

Rejected: adding any measured threshold (a round count, an elapsed-time or
idle limit, a context-size trigger). The design forbids a kill switch, and no
host exposes the measured signal one would need anyway.

## Handshake: a named replacement-activation turn

Rotation step 4 acknowledged the old conductor's release but never said who
tells the replacement that release landed, leaving an implicit main-agent turn
that `S_main` did not count.

Decision: name it. After the old conductor's release acknowledgement, the main
agent sends the replacement one activation message stating that release landed
and that it now owns the exchange and the exact checkout path; the replacement
takes no owning action before that message. `S_main` in `cost-model.md` now
lists that turn. Step 5 is clarified so its "delayed or ambiguous" notice
refers to the old conductor's termination, not to the activation message,
removing the ambiguity the new message could otherwise introduce.

A lost or delayed activation message needs its own recovery, since ownership
has already transferred exactly once at the release acknowledgement. The
activation message is therefore idempotent: the replacement confirms receipt,
and while that confirmation is absent, whether the main agent was interrupted
or the message was simply dropped, the main agent re-sends the same message;
the replacement keeps waiting, taking no owning action, until one arrives, and
re-sending never re-transfers ownership. The recovery is acknowledgement-based,
not a fixed timeout. Without it, step 5's carve-out (which scopes its
retain-ownership rule to the old conductor's termination, not the activation
message) left a lost activation message with no stated recovery.

The same activation gap also bounds stranded-conductor recovery. Ownership
transfers once at the release acknowledgement, so a replacement interrupted
before the activation message arrives already owns the exchange and checkout
yet must take no owning action. Stranded-conductor recovery resumes the polling
loop, so applying it during that gap would start a watcher before activation
and before the required checkout gate, contradicting step 4's no-owning-action
rule. Decision: the discriminator is activation received, not the checkout
gate. Stranded recovery stays available to an ordinary conductor and to an
activated replacement interrupted at any point, including before its checkout
gate completes (the `rotation-replacement-interruption-after-transfer` fixture
models exactly that and requires stranded recovery); only a rotation
replacement still in the activation gap (activation not yet received) is
excluded, governed by step 4's re-wait and idempotent re-send instead. A
stranded replacement that has not completed its gate runs it first, per step 5,
before step 2 resumes any watcher, so no watcher precedes the gate. Step 5
routes an interruption after the activation message, whether or not the gate
has completed, to stranded recovery. Keying the exclusion on a passed checkout
gate instead would strip ordinary conductors of their only recovery path and
contradict that fixture, so a prose-anchor test guard pins the stranded section
against that narrowing.

## Test: state-derived properties replace self-reference

The convergence-fixture block in `scripts/test-await-pr-review-routing.sh`
mostly grepped each fixture for fragments of its own text, so it could not
fail unless the JSON was edited.

Decision: add properties derived from each fixture's `state` object. A rotation
fixture is a refusal iff at least one declared prerequisite gate fails; the
success fixture fails none; a post-transfer fixture already owns the exchange
and checkout and declares activation received, since step-5 recovery begins
only after the activation message and must not be modelled during the
activation gap. Add a forge-record exclusion property over every fixture's
required actions (not just the one leak case) so any future fixture that
records a chat-only field trips the test. Each property was shown to fail on an
injected violation and pass reverted. The existing fragment greps stay: they
pin prompt wording the skill depends on. A gate key absent from a fixture's
state is unasserted, so a new fixture must encode its failing gate in `state`
or the classifier names it. A dedicated activation-gap fixture
(`rotation-activation-gap-interruption-rewaits`) pins the recovery boundary
above: it owns the exchange and checkout but declares activation not yet
received (distinct from a post-transfer fixture, which must declare activation
received), and its classifier branch asserts it re-waits for the idempotent
activation message and forbids resuming polling, starting a watcher, running
the checkout gate, or routing to stranded recovery before activation.

The derived properties pin the design end to end. The cost proxy's favorable
outcome derives from its two conjoined conditions (expected blocker-sustained
rounds and observed replay strain) wherever a fixture declares them, so no
fixture asserts an opaque `favorable`; any declared comparison must carry both
condition fields and equal the derived value, and a fixture that does not test
cost omits the comparison. The success fixture must declare the complete gate
key set, derived from a single `GATE_CHECKS` source shared with `gate_failures`
and pinned to exact passing values, so a gate added anywhere is required
everywhere and a null or absent gate cannot pass fail-open. Each refusal
fixture is pinned to its exact failed-gate set, and `rotation_ids` is asserted
equal to the rotation fixtures actually present, so a drifting or newly added
fixture cannot be silently skipped.

The forge-record exclusion is an explicitly secondary, fail-closed lint over
fixture prose; the authoritative privacy assertion is the structured
`forge_record_contains_chat_only_material` gate. The lint judges each clause on
its own (split on `,`/`;`/`and`/`but`, destination nouns neutralized) and
requires an exclusion word to govern the persist verb or a keep-out frame in
which every protected term sits between `keep` and `out`; its protected-term
list covers the chat-only class `conductor.md` names. Free prose cannot be
parsed exhaustively, so the design choice is to keep the lint fail-closed and
treat it as a backstop, not to keep widening it: an unusual phrasing trips it
loudly rather than passing silently, and a residual prose bypass is escalated,
not patched indefinitely.

## Three lesser-item dispositions

- **`fork_turns: "none"` verified, kept.** Codex Multi-Agent V2 `spawn_agent`
  takes `fork_turns` with `"all"`, `"none"`, or a turn count, and `"none"`
  forks no conversation history (openai/codex issues #20077 and #32031). No
  text change.
- **"Experimental" dropped.** Claude Code's Agent tool names the
  context-inheriting type `fork` with no "experimental" qualifier, so the
  adjective was inaccurate. Removed from `SKILL.md` and `conductor.md`, keeping
  "context-inheriting fork". The internal `experimental_fork` fixture key and
  its assertion are left unchanged: they rename together or not at all, and
  neither is user-facing.
- **Step 3 success-record author: swap declined, rule clarified.** The main
  agent stays the writer of the success reconciliation record; the pointer-
  record side is already a main-agent turn counted in `S_main`, and moving one
  forge write does not justify reopening the ownership design (a #148
  non-goal). The conflation is fixed instead: step 2 now names the mutation
  classes the replacement must not touch before transfer (no checkout, host,
  or forge mutation), replacing the bare "performs no mutation" that lumped
  forge writes with checkout writes.

## Refutation and verification record

This PR touches the forge-record trust boundary, so a refute-first pass backs
every change. All review findings were confirmed real and none was
decline-class (none reversed a #148 non-goal); each was fixed and folded into
its owning commit. Nothing was rejected by verification: every finding
reproduced before it was fixed. Verification, by class:

- **Test-side properties.** Each was shown to fail on an injected violation and
  pass reverted: a success gate flipped to a failing value or type trips the
  every-gate assertion; a cost condition set false under a kept `favorable`
  trips the derivation; a clause persisting a chat-only field without a
  governing exclusion trips the forge-record lint. The guard carries an
  embedded adversarial self-test corpus enumerating the prose input space
  (compound joiners, exclusion position, keep-out per protected field, the
  chat-only class terms) that runs on every invocation. The activation-gap
  fixture is load-bearing the same way: flipping its `activation_received` to
  true trips the classifier ("must declare activation not yet received"), and
  dropping any of its forbidden actions (for example "run the checkout gate
  before activation") trips the assertion loop; reverted, the suite is green. A
  prose-anchor guard over the stranded-conductor recovery section pins its
  eligibility wording (ordinary conductors and activated pre-gate replacements
  stay recoverable); re-injecting the over-restricted "applies only to a
  replacement ... passed its checkout gate" phrasing trips it, reverted it
  passes.
- **Protocol prose.** The handshake self-contradiction (no-activation-remains
  vs. send-activation-message) was removed, and the idempotent,
  acknowledgement-based activation recovery is enumerated by the success
  fixture as well as stated in `conductor.md`.
- **Structural, not point, fixes.** The eval-fidelity gaps were closed at the
  root (single-source gate derivation, exact-value pinning, discovery-synced
  `rotation_ids`) and the exclusion lint was reframed as a fail-closed backstop
  to the structured privacy gate rather than widened, so successor findings in
  those classes are foreclosed by construction rather than patched one at a
  time.

Accepted by decision (not further changed): the three lesser-item dispositions
above, and keeping the prose lint secondary to the structured
`forge_record_contains_chat_only_material` gate rather than attempting
exhaustive prose parsing.

Deferred (declined this round): a recurring "add one more gate to the eval
map" finding asked to add `current_round_verified` and `baseline_advanced`
gates that `conductor.md`'s quiescent-boundary list requires but `GATE_CHECKS`
omits. Valid but non-blocking, and the 5th recurrence of that class across the
PR's review rounds. Per the AGENTS.md thrash guidance, the durable fix is to
derive the gate set from the prose so the eval and prose cannot drift, not to
add another hand-maintained gate per round; that work is tracked rather than
grown into this PR. Follow-up: #152.

Revisit when: hosts expose measured context size or remaining-call estimates
that make the rotation comparison directly executable, or Codex `fork_turns`
or the Claude Code `fork` tool-type change whether those spawns start without
parent history.
