# Make review-loop authorization and convergence executable

Issue #119 implements, rather than overturns, the checkpoint decision in
`2026-08-02-0918-blocker-sustained-convergence.md`. Session evidence showed
that agents treated its recorded go/no-go checkpoint as a mandatory user
approval stop and asked again before ordinary task-scoped writes, even while
blockers were shrinking and the workflow safeguards held.

## Decision

Chose an internal go call over checkpoint-as-approval because the checkpoint's
load-bearing value is the conscious convergence assessment, not a user wake.
At the repeated round-five cadence, the exchange owner records the evidence
and continues when rounds shrink and fixes hold. Only a no-go or materially
uncertain call escalates with the current ledger.

Chose invocation-level authorization over per-action confirmation because
invoking `await-pr-review` already assigns the ordinary loop: wait, fix
accepted findings, fold, push under the pinned lease and checkout gates,
verify, reply, resolve, advance the baseline, and await the next pass. The
authorization does not cross destructive exceptions, failed safety
preconditions, material scope expansion, or genuine judgment calls.

Chose a fresh terminal snapshot over cached readiness because an interruption
or late host event can invalidate a previously clean ledger. Readiness now
requires the current PR head to match the last handled and verified head, with
required checks covering it. Review evidence is either a completed pass with
all activity dispositioned or a fully covered quiet timeout; a main-owned
final-triage push may instead record its re-review as pending. New same-head
reviewer activity after the handled boundary reopens the exchange, as do stale
base, thread, blocker, push, or incomplete-coverage states.

Chose an explicit root-cause hypothesis on the second same-class finding over
another wider grep alone because the second member is evidence that the first
sweep's model of the class was incomplete. The hypothesis must drive the
wider enumeration and the existing fresh-context refute pass.

## Rejected Alternatives

- **Ask at every checkpoint.** Rejected because a healthy convergence loop
  then still needs the user to restart work that the skill already owns.
- **Grant an unbounded go.** Rejected because repeated checkpoints remain the
  detector for genuinely new blockers arriving without convergence.
- **Trust the last ledger after resume.** Rejected because cached checks,
  threads, heads, and base state can all be stale without an agent-visible
  event.
- **Allow a dispositioned thread to remain unresolved at ready handoff.**
  Rejected because issue #119 explicitly makes no unresolved thread part of
  the skill's completion contract. This is stricter than the repository's
  merge policy, where thread resolution itself is not a hard merge gate.

## Refute-First Verification

Independent returned-object trust-boundary lenses produced these dispositions:

- **Confirmed and fixed:** terminal readiness omitted PR lifecycle, did not
  fail closed on missing required values, malformed or partially failed host
  results, and did not require the review-thread connection to be paged to
  exhaustion. Earlier refutation also confirmed a same-head late-activity gap.
  The prompt, conductor contract, detection reference, and regression fixtures
  now cover these cases. Review then confirmed that the first fail-closed
  wording treated expected nullable fields as missing evidence; the final
  contract rejects null only where a field requires a value and accepts null
  lifecycle timestamps for an open PR. A later pass confirmed that the
  illustrative terminal query fetched the base OID without its ref name; it now
  fetches and compares both, so a same-tip retarget invalidates freshness. A
  subsequent pass confirmed that individually complete pages could still form
  a mixed-time snapshot. Its first boundary fingerprint then missed mutable
  thread-resolution state. The final contract requires two complete canonical
  scans to match across lifecycle, identity, checks, push state, all activity,
  and the full thread-resolution map; any difference restarts both scans.
- **Rejected by verification:** changed head and base, in-progress review,
  failed reviewer-tail coverage, required checks, blockers, threads, and
  pending push were already explicit gates. The review fixes retain those
  gates and make the broader terminal snapshot fail closed.
- **Accepted by decision:** a fully covered quiet timeout remains terminal,
  and a main-owned final-triage push may record its re-review as pending. Both
  exceptions still require an open review-ready PR, exact verified head, green
  checks, fresh base, complete snapshot, and no undispositioned activity or
  thread.

Round-five go: earlier fixes held, the last two passes narrowed to one newly
enumerated schema field each, and no corrected finding recurred, so the
exchange continued with the base-identity blocker.

Revisit when: internal go calls repeatedly rubber-stamp non-converging loops;
the authorization envelope causes an action outside the task-scoped PR branch;
or fresh snapshots still permit a ready report with unresolved live state.
