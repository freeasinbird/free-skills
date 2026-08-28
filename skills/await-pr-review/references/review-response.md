# Review Response and Convergence

Read this reference before changing the branch in response to an automated
review, and while deciding whether another round earns its cost.

## Contents

- [Disposition rules](#disposition-rules)
- [Fold, push, verify, reply, resolve](#fold-push-verify-reply-resolve)
- [Main-owned fixer choices](#main-owned-fixer-choices)
- [Rising convergence bar](#rising-convergence-bar)
- [Final triage push](#final-triage-push)
- [Thrash and checkpoints](#thrash-and-checkpoints)
- [Finding-class recurrence](#finding-class-recurrence)
- [Disposition ledger](#disposition-ledger)

## Disposition Rules

Evaluate each finding on its merits:

- Fix a real finding.
- Decline contrived, speculative, marginal, or already-fixed feedback with a
  one-line reason.
- Surface ambiguous, contentious, or design-altering calls to the user.
- Sweep the cited finding's whole class mechanically before pushing: fix every
  instance of that class across the file and repository, not just the cited
  line.

A round dispositions every finding it contains, not only the blockers that
earned another round. Nothing carries silently into a later pass.

## Fold, Push, Verify, Reply, Resolve

To fold a fix is to squash it into the original commit it belongs to, leaving
no separate review-fix commit. Where the project folds review fixes this way,
the round order is a gate:

1. Apply every accepted fix and sweep its class.
2. Run the relevant local verification.
3. Fold each fix into the commit it belongs to.
4. Push the whole round once.
5. Verify every SHA you will cite is contained in the pushed PR ref.
6. Reply to each thread with its disposition and final SHA.
7. Resolve handled threads.

Never reply before folding and pushing. A later fold rewrites a previously
cited standalone fix SHA, so an early reply would cite a SHA that no longer
exists. When several findings are accepted, fold them all before the single
push and all replies.

Use the project's prescribed folding mechanism:

- Amend, or a `fixup!` commit followed by autosquash, are the common options.
- Git before 2.44 may need the interactive form with a no-op sequence editor.
- A range containing a merge needs `--rebase-merges`, so the merge is not
  silently flattened.

After pushing, resolve the actual remote and PR head from the host. Confirm the
cited SHA is contained in that pushed ref, and inspect the commit there to
confirm the fold kept the edit. A fork PR's head need not be `origin`.

If the project appends review-fix commits instead, cite the pushed fix commit
as-is. The pushed-ref verification still applies. A decline has no commit;
reply with the reason only.

## Main-Owned Fixer Choices

This section applies only after the conductor was skipped for a named gate.

The already-awake main agent handles a short round itself. Delegate a capable
fresh fixer only when all three hold:

- The write-capable delegation is available and permitted;
- The round is long (many findings, a wide class sweep, or dozens of calls);
  and
- The main context dwarfs the fixer's compact brief.

Otherwise the main agent handles the round. This fallback is load-bearing when
the conductor was skipped because write-capable delegation itself is
unavailable or forbidden.

A delegated fixer auto-addresses clear-cut findings, verifies them, and reports
judgment calls instead of deciding them. Its final report contains only final
pushed SHAs, one-line dispositions, and the minimum context for surfaced calls.
The main agent spot-checks those judgment calls rather than re-running the whole
clear-cut round.

If a main-owned exchange grows to roughly four or more rounds and the platform
can resume a write-capable fixer, keep the same fixer alive. It pays the
context rebuild once and keeps round debris out of the main context.

## Rising Convergence Bar

A fix round is a round that pushes code. Decline-only rounds do not advance the
count, and they end the exchange, because unchanged code needs no new pass.

Raise the bar as fix rounds accumulate:

- Fix rounds 1 and 2: address every worthwhile correctness, clarity, and safety
  finding.
- From fix round 3: only blockers earn another full reviewer round. A blocker
  is a matter of correctness, security, data loss, a broken invariant, or red
  CI.
- When severity is uncertain, treat the finding as blocking.

The reviewer's severity label is evidence, not the verdict. Make the severity
call independently.

After any fix push, advance the baseline to the actual push or handled review
before waiting. Otherwise the watcher immediately replays old feedback. A
push-triggered reviewer runs again automatically; a command-triggered one must
be requested once after the push.

## Final Triage Push

From the third fix round onward, a pass with no blockers is the taper signal:
the point to wind the exchange down rather than open another full round. Triage
every non-blocker:

- Fix it in one final push only when correctness is locally verifiable before
  pushing: behavior-inert text, or a change fully covered by a check you run
  first. Prompt and instruction wording is behavior, not inert prose.
- Defer a valid non-blocker that needs real or hard-to-verify work to a linked
  tracker issue that quotes enough context to act.
- Decline marginal style, micro-wording, or contrived cases with a reason.

Do not put logic, parsing, validation, destructive-path, credential-leak, or
returned-object trust-boundary changes in the final triage push unless they are
blockers that earn a fully verified round. A blocking item never becomes a
follow-up merely to end the loop.

Under main ownership, a final triage push may hand off without paying another
main-context wait, with the pending review noted. Under conductor ownership, the
foreground wait is cheap, so the conductor waits to quiescence.

Past the final triage push, a new blocker reopens fix rounds. Further
non-blockers receive terminal deferrals or declines without another push.

## Thrash and Checkpoints

Stop and surface thrash when either holds:

- The same finding recurs after a correct, complete fix; or
- Fixes keep producing new problems without net progress.

A recurrence caused by patching only the cited line is a half-fix, not a reason
to stop. Sweep the class properly and continue.

At about five blocker-sustained fix rounds, make and record a one-line go/no-go.
A go is the exchange owner's internal decision: name the convergence evidence,
such as shrinking rounds and fixes that hold, record it in the ledger, and
continue without yielding or asking permission. Surface a no-go or a materially
uncertain call with the current ledger for human judgment. Repeat the checkpoint
at the same cadence while blockers continue; an earlier go does not authorize an
unbounded loop.

## Finding-Class Recurrence

Classify every finding, whatever its source, and sweep its class on first
appearance. If a second member appears despite that sweep:

- Form an explicit root-cause hypothesis for why the first sweep missed it.
- Widen the class one level and enumerate the larger input space, rather than
  patching the new instance at the old width.
- Drive that wider enumeration from the hypothesis.

On that second member, use one fresh-context adversarial refute pass where
read-only delegation is permitted. Give the lenses raw artifacts and ask them to
disprove the change; they report evidence and never edit. Use one pass per PR,
re-arming only if a class recurs after it. Skip it for mixed declining nits, a
small change, or a single-surface diff.

Track recurrence by rule as well as by class. Repeated findings that an
instruction omitted another clause mean the prose is re-deriving a program.
Escalate to the owner with the recurrence evidence, and recommend moving the
rule into a small tested script or check.

## Disposition Ledger

At termination every finding has exactly one state:

- Fixed, with the final pushed SHA;
- Declined, with the inline reason;
- Deferred, with a linked follow-up issue; or
- Outstanding for the human.

Also record any no-blocker call that ended the exchange, a watch timeout or
coverage gap, thread state, checks state, and whether a review remains pending
after a main-owned final push. “Stop” means the automated exchange ended, not
that human review is unnecessary.
