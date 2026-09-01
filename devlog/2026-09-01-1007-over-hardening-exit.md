# Review convergence: test reachability and exit over-hardening loops

Agents running await-pr-review kept landing 8 to 10 fix rounds deep, adding
guards for states nobody could reach, until the owner asked "are you in an
over-hardening hole?" That question reliably made the agent step back. The
skill should make the agent ask it first.

## Why the existing guards did not fire

- "Decline contrived or speculative findings" had no test. A bot reviewer
  phrases every finding as a concrete failure, so nothing looked speculative
  from inside the loop.
- "When unsure, treat the finding as blocking" merged two uncertainties.
  Uncertainty about a real defect's severity should bias toward fixing.
  Uncertainty about whether the failing state is reachable should trigger a
  check, not a patch. Merged, the rule guaranteed a fix for every
  hypothetical.
- The round-five checkpoint measured shrinking counts and fixes that hold.
  An over-hardening loop has both properties: each new guard "holds," and a
  bot's finding count on fresh guards drifts down. The checkpoint recorded a
  go and the loop ran on.
- Thrash was defined as recurrence or regressions. The hole is a third
  pattern: each round's findings cite the guards the previous round added.
  Every finding gets dispositioned, so the agent perceives progress.
- Class sweeps and "widen one level" ratcheted outward with no counter.

## Decision

- **Two disposition questions gate a guard or other behavioral change.**
  Reachable: name what produces the failing state, an input the interface
  admits at a public or untrusted boundary or an existing caller for internal
  code. Material: is the harm real at the expected scale and trust boundary?
  A fix that adds a guard, branch, fallback, or handled case is hardening and
  needs both to pass. Clarity, documentation, naming, and maintainability
  findings keep their ordinary merits and severity call.
- **Split the uncertainty rule.** Unsure severity of a reachable defect:
  blocking. Unsure reachability: check before patching. This refines, and
  does not reverse, the 2026-06-26 "converge both directions" decision. Real
  findings still get fixed at any round; "worthwhile" now has a test.
- **Add a hardening check with observable signals.** Provenance (most
  findings cite lines an earlier round added), shape (recent fixes are all
  hardening whose ledger names no caller the agent traced), growth (the diff
  grew without delivering the What), and cadence (flat finding count). Two
  signals mean the reviewer is reviewing the agent's hardening. It runs before
  each fix round from round 3 and at every checkpoint. Each signal is phrased
  so justified work cannot trip it.
- **Define the exit.** Fix only what still passes both questions and clears
  the current bar, decline the rest naming the unreachable path, list earlier
  hardening that fails those questions as removal candidates, and surface the
  ledger. Removal changes scope,
  so it is surfaced rather than done silently.
- **A go at the checkpoint needs blockers that passed the two questions**, not
  only shrinking counts. It is not gated on the hardening check, so real
  blockers cannot block their own go.
- **A posted review is not evidence that work remains.** A reviewer that
  posts only on findings has a floor on new code.

The skill carries the full rubric in `references/review-response.md`. The
managed convention (`§review-convergence` and the pull-requests block) carries
a compact version so downstream projects inherit the same default.

## Rejected options

- **A hard round cap requiring human approval.** Blunt, and it contradicts the
  recorded decision that a justified go continues without yielding. The eval
  `round-five-converging-go` pins that behavior. Observable signals target the
  failure mode instead of the round number.
- **Skill-only change.** Downstream agents read the AGENTS.md block, which
  still said "when unsure, treat as blocking." Leaving it would make the skill
  and the convention disagree at the exact moment the rule matters.
- **Reviewer-specific throttling** (for example, ignoring Codex after round
  N). Reviewer-agnostic reachability is the property that actually
  discriminates a real finding from a hypothetical one.
- **Gating every finding on the two questions.** Review found this forces a
  decline for any clarity or documentation finding, because no input reaches a
  failing runtime state. That contradicts the same file's promise that rounds
  1 and 2 address every worthwhile correctness, clarity, and safety finding.
  The gate is scoped to guards and other behavioral changes instead.

## Verification

Skill prompts were reviewed against the eval fixtures added for the hole, the
one-real-defect variant, a late reachable blocker, an early hypothetical
guard, a non-behavioral finding that must still be fixed, and a hypothetical
second class member that must not widen a class. The project checks all
passed. No live review exchange was run under the new text.

Review of this change found the same fixture defect three times, in three
separate rounds: a case whose required action assumed a qualifier the case
never established. Declining without a completed caller trace, and widening a
class on a second member never shown to be real, were both instances. Two
prose sweeps and one fresh-context audit each missed a later member, because
each sweep matched on wording rather than on the predicate the required action
depends on. That recurrence is by rule, not by class.

Revisit when an exchange still reaches eight or more fix rounds with the check
in place, or when a reachable defect is declined citing the round count. The
first means the signals are too weak; the second means the split uncertainty
rule is being read as a cap. Revisit the fixture too if a fourth case is found
asserting a qualifier its state does not establish: at that point the
invariant belongs in a mechanical check over the fixture, not in another prose
sweep.
