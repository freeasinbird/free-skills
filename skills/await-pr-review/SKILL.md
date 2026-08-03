---
name: await-pr-review
description: >-
  Wait for an automated PR reviewer (such as Codex) after opening or pushing
  a pull request, then handle its feedback without making the user request
  repeated checks. Start the watch by default, detect review bodies, inline
  comments, replies, and out-of-band clean-pass signals, auto-address
  clear-cut findings, and surface judgment calls. Where write-capable
  delegation has wait-and-resume continuity plus checkout isolation or
  exclusivity,
  spawn a conductor subagent to own the whole exchange; use a main-owned
  watcher only when a named conductor gate is unavailable. Not for human-only
  review, a branch without an open PR, or a repository with no automated
  reviewer.
---

# Await PR Review

Watch an open pull request for its automated reviewer, address the feedback,
and converge without asking the user to babysit the polling loop. This skill
owns waiting and orchestration; the project's review-response conventions
still govern commits, replies, resolution, and handoff.

## Route ownership before waiting

**Default to one conductor subagent.** First resolve only the event-boundary
facts needed for its brief, then spawn it before reading feedback, waiting on
CI, or starting any watcher. The conductor owns steps 1 through 5 and wakes
the main agent only for a judgment call, a checkpoint escalation, or its
terminal disposition ledger.

Apply one platform-neutral gate. A conductor owns the exchange when all four
grants hold:

1. Write-capable delegation is available and permitted.
2. The same subagent has wait-and-resume continuity: it can stay active through
   each bounded wait or receive a scheduled wake without ending exchange
   ownership, and it can resume after surfaced pauses.
3. Completion reliably notifies or re-enters the main agent.
4. The PR branch has either an isolated checkout or explicit shared-checkout
   exclusivity until the terminal ledger.

Invoking this skill supplies the workflow request to delegate where the host
allows a skill to do so. Do not ask separately merely because delegation is
involved. A higher-priority prohibition still wins.

Map any agent's actual tools to those grants. The named surfaces below are
concrete examples that prevent repeated capability guesswork; they do not
replace the generic route:

- **Codex app:** collaboration tools that expose spawn and completion
  notification satisfy grants 1 and 3. Follow-up/resume plus a conductor-local
  foreground wait or scheduled same-conductor wake satisfy grant 2. If agents
  share the checkout, grant branch exclusivity by having the main agent make no
  edit, commit, fetch of the PR branch, rebase, or push until the terminal
  ledger. If the main agent must keep changing that checkout, grant 4 does not
  hold.
- **Claude Code:** use one write-capable background subagent with explicit
  worktree isolation. Its blocking foreground wait plus re-messaging the same
  agent satisfy grant 2; completion notification satisfies grant 3.
- **Any other agent:** inspect its delegation, conductor-local wait and resume,
  completion, and checkout controls and apply the same four-grant gate. An API
  or connector that can only return instantaneous reads does not satisfy grant
  2 unless it can schedule the same conductor to resume without ending the
  exchange. Do not infer a failed gate from unfamiliar tool names; name the
  concrete missing grant if one is absent.

Keep the exchange in the main agent only when a grant is concretely absent or
forbidden, or when feedback is already in hand and known to require at most a
couple of trivial operations. A small main context, a background shell, or a
prediction that the review will be clean or one-shot is not an exception.

Before any main-owned watch, state the fallback in this exact shape, naming
either the failed grant or the narrow trivial-feedback exception:

```text
Conductor skipped: <specific failed grant or allowed exception>.
```

The main agent captures and passes: repository and PR, any already-recorded
reviewer identity and status signals, the event-anchored baseline (or its
explicit attribution gap), expected PR head, base branch and base tip, the
available host-observation surface (script, API, or connector), the
conductor-local wait or scheduled-wake mechanism, the project review-response
conventions, and the conductor contract in
`references/conductor.md`. An unrecorded reviewer is not a reason to delay the
spawn; assign step-2 discovery to the conductor. Grant checkout isolation or
exclusivity explicitly. Use a model capable of editing and review judgment,
not the cheapest watcher tier. Read that reference before spawning; it
contains the ready-to-use brief, turn discipline, checkout alignment, and
lease rules.

## The exchange

### 1. Resolve the PR and anchor the baseline

Resolve the current branch's PR and record the event that should produce the
next pass. For an open- or push-triggered wait, use the host's open, ready, or
push event time. For a manual no-push recheck, use the request time. Never use
the commit authored time or a local clock reading taken after the event.

Record the expected head plus the base branch and current base tip from the
host. The main agent captures these facts at the event boundary even when a
conductor will own everything afterward.

Confirm which round a returned pass actually covered before accepting it.
GitHub attributes a review to the head current at submission, not necessarily
the head the reviewer analyzed, and reactions carry no head. This attribution
check belongs to the exchange owner and is not repeated later.

Read `references/detection.md` for host-event queries, the two-reading
pre-push fallback, source paging, login forms, and attribution caveats.

### 2. Identify and, if needed, request the reviewer

Prefer the project's recorded automated-reviewer identity, trigger, and
status signals. Otherwise detect a bot that actually submits reviews or a
clean-pass-only bot with recurring PR-description reactions. If detection
finds multiple bot reviewers, ask which one to await. If the trigger cannot
be established, ask rather than burning the wait cap.

Record a newly observed reviewer, or newly observed status signals for an
existing reviewer, in the project's designated unmanaged conventions section.
Never record an absence. Request a command-triggered reviewer once when no
request is pending; do not re-trigger every poll.

### 3. Wait for new activity

**Conductor-owned exchange:** when a shell and host CLI are available, run
`watch-review.sh` as a bounded foreground command inside the conductor. When
they are not, use an equivalent bounded foreground API or connector polling
loop over the same frozen baseline, expected head, sources, and completion
signals. A connector loop that cannot delay in-turn uses the scheduled
same-conductor wake established by grant 2. Either mechanism stays under
conductor ownership; it must not emit terminal completion merely to wait. The
script blocks only the small conductor context and costs no model tokens while
polling. The connector loop may require model wakes, but it preserves conductor
ownership and the same round-attribution rules.

Keep one active watch per PR/reviewer. Start it promptly before waiting on
required checks. After a new push, advance or replace its baseline instead of
leaving duplicate watchers alive. Checks remain a separate required wait; the
review detector does not prove them green.

**Main-owned fallback only:** after emitting the required `Conductor skipped`
line, choose the cheapest permitted mechanism that reliably re-enters the
main agent:

1. A background no-model `watch-review.sh` process whose completion re-enters
   the agent, when a shell and host CLI are available.
2. A read-only watcher subagent on the smallest capable model when background
   process re-entry is absent.
3. A cancellable scheduled API or connector poll, or script invocation, that
   uses the same frozen baseline and expected head on every wake.
4. A bounded foreground detector when the main agent can remain active through
   the wait, using the script or equivalent API/connector snapshots.
5. Hand back the baseline when none can run.

The watcher-only subagent is not the conductor. It must not edit, commit,
push, trigger a review, reply, or resolve threads. Report compact IDs,
timestamps, states, paths/lines, the top-level review body, status reactions,
and checks state.

When the script is selected, run it from the PR checkout, or pass
`--repo owner/name` explicitly:

```sh
<skill-dir>/watch-review.sh --repo owner/name --pr 46 \
  --login chatgpt-codex-connector --head 9c346ab \
  --baseline 2026-07-02T05:07:30Z --interval 75 --cap-minutes 25
```

Branch on every exit: 0 review activity, 3 clean pass, 2 cap expired, 64 bad
invocation, and 69 missing `gh`. For exit 2, `polls_ok:0` means the watch never
worked; otherwise `last_poll_ok` determines whether the final window was
covered. An API or connector detector maps its outcomes to the same states as
specified in `references/detection.md`. Report incomplete coverage as
incomplete, not quiet.

Finish a round only on target-reviewer activity after the baseline: a
submitted review, a new thread, a new reply on an existing thread, or the
configured clean-pass signal. An in-progress reaction or acknowledgement is
not completion. Read the review state and body before declaring a round clean.

All detection mechanics, scheduled-wake rules, cadence, status reactions, API
field/login forms, and script exit semantics live in
`references/detection.md`.

### 4. Address feedback

Read `references/review-response.md` before changing the branch. Its gates are
part of this workflow, not optional advice.

For every finding:

- Evaluate it on its merits. Fix real findings and decline contrived,
  speculative, or already-fixed ones with a one-line reason.
- Sweep the whole finding class, not only the cited line.
- Auto-address clear-cut fixes. Surface ambiguous, contentious, or
  design-altering calls to the user.
- Follow the project's commit convention. Where review fixes fold into their
  originating commits, the order is: fix, fold, push, verify on the pushed
  ref, reply with the final SHA, then resolve. Fold all fixes in a round and
  push once before replying to any of them.

Under conductor ownership these operations remain in the conductor. Under
main ownership, delegate a fixer only when write-capable delegation is
available and permitted, the round is long, and the main context dwarfs the
fixer's brief; otherwise address it in main.

### 5. Converge on a rising bar

After a fix push, advance the baseline and await the newly triggered pass. A
decline-only round ends the exchange because unchanged code needs no confirming
round. A command-triggered reviewer must be requested again after a push.

In the first two fix rounds, address every worthwhile finding. From the third
fix round onward, only blockers (correctness, security, data loss, broken
invariants, or red CI) earn another full round. Triage non-blockers into a
locally verifiable final push, a linked follow-up issue, or a reasoned decline.
When unsure whether a finding blocks, treat it as blocking.

Stop for human judgment on thrash: the same class recurring after a correct
complete fix, or fixes producing new problems without net progress. At about
five blocker-sustained fix rounds, record a go/no-go checkpoint and repeat it
at the same cadence while blockers continue.

Track finding classes across the whole exchange. A second member after a
class sweep widens the class one level and earns one fresh-context adversarial
refute pass where read-only delegation is available. Repeated prose-clause
findings on one rule surface should trigger an owner escalation to replace the
prose program with a tested script or check.

The full taper, final-push, checkpoint, recurrence, refute-pass, and ledger
rules live in `references/review-response.md`.

### 6. Report the ledger

Every finding ends as fixed (pushed SHA), declined (reason), deferred (linked
issue), or explicitly outstanding for the human. State any no-blocker call
that ended the exchange, whether threads are resolved, checks status, and any
bounded timeout or coverage gap.

Before calling the PR ready, resolve the current base branch and tip again. If
either differs from the recorded base, report the review exchange complete but
integration evidence stale and return to the project's freshness workflow.
Do not update the branch as part of the watcher role.

Wait for every required check and fix any known-red result before claiming the
PR ready. The ledger records the final checks state rather than treating review
completion as CI completion.

Where fixes are folded, confirm the pushed branch contains no autosquash
subjects and no standalone review-fix commits. Leave the PR open for human
review and merge unless the project explicitly opts into self-merge.

## References

- `references/conductor.md`: read before spawning or resuming a conductor.
- `references/detection.md`: read for baseline capture, reviewer detection,
  watcher execution, scheduled wakes, or hand-rolled detection.
- `references/review-response.md`: read before addressing findings and while
  applying convergence policy.
- `references/cost-model.md`: read only when re-deriving or auditing a
  borderline cost decision.

This skill assumes an open PR, an automated reviewer that can be identified,
access to the host's reviews/comments/reactions through either the bundled
script or an equivalent API/connector, and a permitted wait/re-entry
mechanism. A host CLI and shell are preferred, not mandatory. When neither
script nor API-based detection can observe the required host data, name that
missing capability and hand control back rather than pretending to watch.
