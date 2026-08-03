# Review response and convergence

Read this reference before changing the branch in response to an automated
review and while deciding whether another round earns its cost.

## Contents

- [Disposition rules](#disposition-rules)
- [Fold, push, verify, reply, resolve](#fold-push-verify-reply-resolve)
- [Main-owned fixer choices](#main-owned-fixer-choices)
- [Rising convergence bar](#rising-convergence-bar)
- [Final triage push](#final-triage-push)
- [Thrash and checkpoints](#thrash-and-checkpoints)
- [Finding-class recurrence](#finding-class-recurrence)
- [Disposition ledger](#disposition-ledger)

## Disposition rules

Evaluate each finding on its merits:

- Fix a real finding.
- Decline contrived, speculative, marginal, or already-fixed feedback with a
  one-line reason.
- Surface ambiguous, contentious, or design-altering calls to the user.
- Sweep the cited finding's whole class mechanically across the file and
  repository before pushing.

A round dispositions every finding it contains, not only the blockers that
earned another round. Nothing carries silently into a later pass.

## Fold, push, verify, reply, resolve

Where the project folds review fixes into their originating commits, the
round order is a gate:

1. Apply every accepted fix and sweep its class.
2. Run the relevant local verification.
3. Fold each fix into the commit it belongs to.
4. Push the whole round once.
5. Verify every SHA to be cited on the pushed PR ref.
6. Reply to each thread with its disposition and final SHA.
7. Resolve handled threads.

Never reply before folding and pushing. A later fold rewrites a previously
cited standalone fix SHA. When several findings are accepted, fold all of
them before the one push and all replies.

Use the project's prescribed folding mechanism. Common options are amend or
a `fixup!` commit followed by autosquash. Git before 2.44 may require the
interactive form with a no-op sequence editor; a range containing a merge
requires `--rebase-merges` so the merge is not silently flattened.

After pushing, resolve the actual remote and PR head from the host. Confirm
the cited SHA is contained in that pushed ref and inspect the commit there to
ensure the fold retained the edit. A fork PR's head need not be `origin`.

If the project appends review-fix commits instead, cite the pushed fix commit
as-is. The pushed-ref verification still applies. A decline has no commit;
reply with the reason only.

## Main-owned fixer choices

This section applies only after the conductor was skipped for a named gate.

The already-awake main agent handles a short round. Delegate a capable fresh
fixer only when all three are true:

- write-capable delegation is available and permitted
- the round is long (many findings, a wide class sweep, or dozens of calls)
- the main context dwarfs the fixer's compact brief

Otherwise the already-awake main agent handles the round. This fallback is
load-bearing when the conductor was skipped because write-capable delegation
itself is unavailable or forbidden.

The fixer auto-addresses clear-cut findings, verifies them, and reports
judgment calls instead of deciding them. Its final report contains only final
pushed SHAs, one-line dispositions, and the minimum context for surfaced
calls. The main agent spot-checks judgment calls rather than re-running the
whole clear-cut round.

If a main-owned exchange grows to roughly four or more rounds and the
platform can resume a write-capable fixer, keep the same fixer alive. It pays
the context rebuild once and keeps round debris out of the main context.

## Rising convergence bar

A fix round is a round that pushes code. Decline-only rounds do not advance
the count and end the exchange because no new pass is needed for unchanged
code.

- Fix rounds 1–2: address every worthwhile correctness, clarity, and safety
  finding.
- From fix round 3: only blockers earn another full reviewer round. Blockers
  are correctness, security, data loss, broken invariants, or red CI.
- When severity is uncertain, treat the finding as blocking.

The reviewer's severity label is evidence, not the verdict. Make the severity
call independently.

After any fix push, advance the baseline to the actual push or handled review
before waiting. Otherwise the watcher immediately replays old feedback. A
push-triggered reviewer runs again automatically; a command-triggered one
must be requested once after the push.

## Final triage push

From the third fix round onward, a pass with no blockers is the taper signal.
Triage every non-blocker:

- Fix it in one final push only when correctness is locally verifiable before
  pushing: behavior-inert text, or a change fully covered by a check run
  first. Prompt and instruction wording is behavior, not inert prose.
- Defer a valid non-blocker needing real or hard-to-verify work to a linked
  tracker issue that quotes enough context to act.
- Decline marginal style, micro-wording, or contrived cases with a reason.

Do not put logic, parsing, validation, destructive-path, credential-leak, or
returned-object trust-boundary changes in the final triage push unless they
are blockers that earn a fully verified round. A blocking item never becomes
a follow-up merely to end the loop.

Under main ownership, a final triage push may hand off without paying another
main-context wait, with the pending review noted. Under conductor ownership,
the foreground wait is cheap, so the conductor waits to quiescence.

Past the final triage push, a new blocker reopens fix rounds. Further
non-blockers receive terminal deferrals or declines without another push.

## Thrash and checkpoints

Stop and surface thrash when:

- the same finding recurs after a correct, complete fix, or
- fixes keep producing new problems without net progress.

A recurrence caused by patching only the cited line is a half-fix, not a
reason to stop. Sweep the class properly and continue.

At about five blocker-sustained fix rounds, record a one-line go/no-go.
Continue only with evidence of convergence, such as shrinking rounds and
fixes that hold. Repeat the checkpoint at the same cadence while blockers
continue; one approval does not authorize an unbounded loop.

## Finding-class recurrence

Classify every finding, regardless of source, and sweep its class on first
appearance. If a second member appears despite that sweep, widen the class
one level and enumerate the larger input space rather than patching the new
instance at the old width.

On that second member, use one fresh-context adversarial refute pass where
read-only delegation is permitted. Give lenses raw artifacts and ask them to
disprove the change; they report evidence and never edit. Use one pass per PR,
re-arming only if a class recurs after it. Skip it for mixed declining nits,
a small change, or a single-surface diff.

Track recurrence by rule as well as class. Repeated findings that say an
instruction omitted another clause indicate prose is re-deriving a program.
Escalate to the owner with the recurrence evidence and recommend moving the
rule into a small tested script or check.

## Disposition ledger

At termination every finding has exactly one state:

- fixed, with the final pushed SHA
- declined, with the inline reason
- deferred, with a linked follow-up issue
- outstanding for the human

Also record any no-blocker call that ended the exchange, watch timeout or
coverage gap, thread state, checks state, and whether a review remains pending
after a main-owned final push. “Stop” means the automated exchange ended, not
that human review is unnecessary.
