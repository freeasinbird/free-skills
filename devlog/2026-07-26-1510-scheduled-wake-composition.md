# Scheduled wakes compose with watch-review.sh, they do not replace it

Issue #96 reported a Codex scheduled-heartbeat implementation of
`await-pr-review` that hand-rebuilt the GitHub review, thread, reaction, and
check queries inside every model wake instead of invoking the shipped
`watch-review.sh`, and that anchored its baseline to a local clock reading
taken after the push. Both are prompt gaps: step 3 opened the timer-re-entry
case and stopped at economics, never saying what a wake's body does, and
step 1 rejected the commit timestamp as a push proxy but not a later clock
reading.

## Decisions

**Chose prose in SKILL.md over a new `references/scheduled-wake.md`.** The
failure mode was a reader missing the composition, so burying the fix in a
reference reproduces it; `references/cost-model.md` already fixes the
contract that decision rules live in SKILL.md and an agent that never opens
a reference makes the same choices. The pasteable wake prompt _is_ the
guidance, so it cannot move. What did move: the `gh api` push-timestamp
queries went to `references/detection.md`, which already owns query
mechanics, and the wake-cost arithmetic to `references/cost-model.md`.

**Chose prose over escalating baseline resolution into a `watch-review.sh`
flag** (owner decision, made when this looked like a single instance).
Review then found baseline resolution drawing defects repeatedly, so the
premise that it was not yet a recurring problem did not survive; the decision
stands for this change, and the escalation is tracked separately rather than
here. A `--baseline-from-push` flag would make the paging, feed selection,
and head matching executable and testable instead of restated, at the cost of
moving the events feed's roughly one-minute cache lag and its fork blind spot
inside the detector.

**Chose a `text` fence for the example**, accepting that
`scripts/check-skill-structure.sh` then skips its flag-parity check
(`:754` scans only shell-language fences). A shell fence would parse the
prompt's English exit-code branches as commands. Every flag the example uses
is mentioned elsewhere in the file, so the checker's mention rule still
holds and only this block's flag correctness rests on review.

**Chose to leave `SKILL.md`'s existing cadence paragraph intact** and append
the composition rule, rather than rewriting it: the paragraph is correct in
isolation, and what was missing is only that the two numbers compose.

**Chose no watcher-side bullet for the scheduled wake.** It is a re-entry
mechanism, so it sits on the main-agent side and cross-references the
watcher list; a second bullet would fork the exit-code guidance into a copy
that drifts, which is a version of the confusion #96 reports.

## What verification established

Two review passes, a refute-first pre-push review and the repository's
automated reviewer, changed the text substantially. Their durable results,
by invariant rather than by pass:

**Round validation is unconditional.** `watch-review.sh` documents head
attribution as best-effort for _every_ baseline, since GitHub stamps a review
with the head current at submission rather than the head it analyzed, and
puts the confirmation on the caller in those words. A review already running
when you push finishes afterwards carrying your new head, clearing both the
baseline and the `--head` gate while the push-triggered pass is still
outstanding. Nothing downstream repeats the check: step 4 evaluates findings
and step 6 reports. An earlier draft gated this on the pre-push fallback,
which left the common path unguarded.

**The head filter is best-effort, so the rule is "confirm what a pass
covered", not an enumeration of what cannot cross it.** Replies on existing
threads are exempt by design, reactions carry no commit at all, and comment
`commit_id`s re-anchor as the PR advances; any enumeration is a claim about
GitHub's attribution that the script itself declines to make.

**The pre-push fallback needs two readings, from the host clock, with
distinct roles.** A pre-push bound proves only that a signal followed the
bound, not that it followed the push, so it cannot support the validation
above on its own. The pre-push reading is the baseline; a post-push reading
is kept solely for disambiguation and never passed as the baseline, which is
the one legitimate use of the clock reading this change otherwise rejects.
Both come from the host, since they are compared against host-authored
timestamps across a window only as wide as a push and runner skew alone would
invert that ordering. That push-width window is the only unresolvable region,
and holding neither reading is an explicit handoff rather than a verdict.

**A property that bounds the whole composition is stated once at that
level.** The overall deadline bounds the schedule, not one exit code: three
branches re-arm and the script is stateless, so a signal that cannot be
placed returns the same exit every wake and a deadline living in one branch
would never be reached. The deadline ends with a `--cap-minutes 0` poll,
because a wake stops polling at its own cap and the gap to the deadline would
otherwise go unscanned, which is the skill's own "a source that never scanned
is not a source that was quiet" rule reappearing at the composition boundary.

**The payload fields mean what the script does, not what their names
suggest.** `polls_ok` resets per process, so it is a whole-run verdict that
misreads a four-minute wake; exit 2 therefore tolerates one blind wake before
giving up. `last_poll_ok` carries coverage, since every poll rescans from the
fixed baseline. `in_progress_seen` is never reset once set, making it history
inside a multi-poll wake but current on the single-poll final wake, where it
means pending rather than quiet.

**The script detects; it does not report.** It polls reviews, review
comments, and reactions, and does not read review bodies or required checks,
so a prohibition on querying the host has to be scoped to detection. A review
or comment match also ends its poll before the reactions scan, so a stale
item starves the reaction source for as long as it sits past the baseline:
the exit-0 stale path reads reactions directly, and that scan decides rather
than decorates, since a clean pass placeable in this round finishes it.

**Exit codes map to schedule actions.** 64 and 69 are deterministic
properties of the invocation or the environment, so re-arming repeats the
same failure every gap at a full context replay each time; both cancel. 69
still hand-rolls from `references/detection.md` rather than declaring the
environment unable to watch, per the guidance the skill already carries.

**Documented queries paginate.** `gh api` returns a single page without
`--paginate` and both push-event endpoints default to 30 items, which is the
window the detection reference's own paging rule rejects.

Script behaviors confirmed and relied on: `--cap-minutes 0` performs exactly
one poll and exits 2; consecutive wakes sharing a baseline leave no coverage
hole, because both scanners are stateless and baseline-terminated; and the
`CAP_EXPIRED` payload carries `polls_ok`, `last_poll_ok`, and
`in_progress_seen`, the last of which the skill had never mentioned.

Rejected during review: a sentence endorsing `--cap-minutes 0` on a
sub-two-minute wake gap, which contradicted the 4-5 minute band and the
ten-wake break-even in the same section; and a blanket "do not query the host
any other way", which would have blocked the refetching the fix and report
steps require.

**The lesson worth carrying.** Every sentence describing what the detector, a
neighbouring step, or a composition of them guarantees has to be checked
against the thing itself: a plausible reading of a flag name is not its
behavior, and a cross-reference to another step is a claim about that step
rather than a way of deferring the work. The dominant defect shape was
narrowing a property that holds everywhere to one exit code, one baseline
source, or one branch. The narrowing costs the rounds, not the rule.

**Weigh next time:** the pre-push fallback carries most of the intricacy in
this change, and most of what review found. It serves a narrow case, no host
event resolving, chiefly a plain push on a fork PR. Simplifying it to "no
host event resolved, so hand back" is a real alternative to keeping the
disambiguation machinery; the machinery was kept here because the fork case
is genuine and the rules now hold.

## Scope

Documentation only; `watch-review.sh` is unchanged, so no new rows in
`scripts/test-watch-review.sh`. No canonical or managed-block edit: the
canonical review-watch convention must stay capability-agnostic and name no
skill (architecture invariant 2), so "prefer the shipped detector" belongs
in the skill alone.

Revisit when: a second scheduled-heartbeat implementation still reimplements
detection, or baseline-resolution defects recur. Either would mean prose is
re-deriving a program, and the medium should escalate to a script flag.
