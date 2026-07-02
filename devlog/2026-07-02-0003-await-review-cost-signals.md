# Optimize await-pr-review: watcher cost, wake cost, reviewer status signals

The user flagged the skill as working but expensive, with three concerns:
the watcher's model class, the token cost of waking the master thread, and
missed out-of-band status signals (Codex reacting on the PR description).
All three confirmed; the third empirically, against this repo's own PRs.

## Findings

- **The listener was over-classed.** The watch is mechanical (query,
  timestamp compare, sleep); the ladder listed a delegated subagent first,
  which in practice spawns a frontier-class agent. The original decision
  (devlog 2026-06-26-2127) put the backgrounded poll first; the subagent path
  was added later (2026-06-27-0126) and drifted to "preferred". Restored:
  no-model backgrounded poll first (zero tokens while waiting, one master
  wake), delegated watcher only where background processes are absent, on the
  smallest model class, polling inside one long-running command.
- **Wake cost varies by mechanism, and the fixed ladder hid it.** Replaced
  with a cost model: watcher-side cost (what runs while waiting) plus
  master-side cost (each re-entry replays the whole main context). Nuance
  worth keeping: the single wake on activity is usually cache-cold (reviews
  land in 3–7 min, past a 5-min cache TTL), so for a large main context on a
  platform with steeply discounted cached reads, keepalive-cadence scheduled
  wake-ups (~270s at ~0.1x per read) can beat one cold wake (~1.25x) up to a
  break-even of roughly a dozen wakes (~45 min of waiting). Stated
  platform-agnostically in the skill so the agent picks per situation.
- **The dominant residual cost is the fix rounds themselves** replaying a fat
  master context on every tool call. Added a platform-gated delegated-fixer
  path (step 4): a fresh compact context addresses clear-cut findings, runs
  verification itself, and reports judgment calls back rather than deciding
  them, under a compact report contract. Guards that keep delegation cheaper
  rather than double-paying: only the final report crosses back; the master
  spot-checks judgment calls only, never re-verifies clear-cut fixes. Skip it
  when the round is short, the master context is small, or the round is
  mostly judgment calls. Requires delegation with write access, a larger
  grant than the read-only watcher; falls back to in-master rounds or a
  fresh session. Refined mid-review after the user challenged the
  accounting: delegation does not reduce master wakes, it adds them (spawn
  turn plus completion wake), and a fresh fixer rebuilds working context the
  master already holds; the saving is only the per-tool-call context replay
  during the fix work, so it pays off only on long rounds where the master
  context dwarfs the fixer's brief. The skill states that break-even
  explicitly rather than implying delegation is generally cheaper.
- **Codex signals status via PR-description reactions the skill never read.**
  Verified on PRs 41–44 via GraphQL (reactions + reviews + threads in one
  query): on clean passes (41, 43) Codex posted no review and no threads,
  only a THUMBS_UP reaction 3–7 min after open; on findings PRs (42, 44) the
  👍 landed only after the final clean round. The user also observes 👀 while
  a review is in progress (absent from completed-PR snapshots, so evidently
  removed on completion: an in-progress signal only). The old skill would
  wait out the full 20–30 min cap on a clean PR and report "no review
  arrived". Added: reactions in the step-1 snapshot, a fourth completion
  signal (clean-pass signal dated after the baseline), the in-progress
  signal treated like an ack (presence keeps waiting, absence proves
  nothing), and the login-form quirk (GraphQL returns reaction authors in
  the REST-style `name[bot]` form, unlike GraphQL review authors).

## Reaction caveats (encoded in the skill)

Reactions are one-per-user-per-emoji and mutable, so a clean-pass signal
counts only with `createdAt` after the baseline; a leftover 👍 from an
earlier round does not. Whether Codex refreshes the reaction timestamp on a
later clean round is unverified from this data, so the wait cap stays as the
backstop for ambiguity.

## Decisions

- Ladder reorder is a restoration of the 2026-06-26 decision on cost
  grounds, not a re-litigation of the 2026-06-27 subagent addition; all of
  that addition's guardrails (notify/re-enter requirement, permission gate,
  watcher-only, report-body requirement) are retained.
- The delegated-fixer path relocates where rounds run, not when they stop;
  the convergence stop rules (value tapering, never cap a worthwhile
  exchange) are unchanged and remain settled.
- Promoted alongside: the canonical "record a noticed automated reviewer"
  convention now records observed status signals too (canonical source +
  managed block, diff-identical), and this repo's Codex record carries the
  observed 👀/👍 signals.

## Codex review rounds (dogfooded on this PR)

The skill's own watcher (backgrounded no-model poll, reaction-aware) ran
each round; every round was a real finding, each fixed with a class sweep:

1. agent-setup's "Automated reviewer record" check still enumerated only
   name/login/trigger after the convention gained status signals; the sweep
   found exactly one sibling.
2. The four-signal prose said to match reactions via `author.login`, but
   GraphQL exposes a reaction's author as `user.login` (the working watcher
   already used `user.login`; the prose contradicted it). Split the matcher
   and swept the generic `author.login` references.
3. The record convention's trigger required observing a bot-authored
   review, which a clean-pass-only reviewer never posts; expanded the
   trigger (canonical + managed block) and the skill's detection fallback
   to accept an observed reviewer status signal.
4. The script's default reaction login (`<login>[bot]`) double-suffixed a
   login that arrived already suffixed, exactly what the round-3
   reaction-only detection path hands callers; the script now normalizes
   either form, and the detection prose says to strip the suffix and record
   both forms.
5. Two findings: an existing name/login/trigger-only reviewer record blocked
   signal recording (the trigger said "hasn't recorded the reviewer");
   convention and skill now say to augment an existing record with newly
   observed signals. And the script's thread scan inherited the
   `reviewThreads(first:50)` page window, hiding a reply on an old thread
   beyond it; the script now also reads the REST review-comments feed
   sorted newest-first, where any post-baseline comment is on the first
   page by construction.
6. That round-5 "first page by construction" claim was a half-fix: more
   than a page of post-baseline comments can push the match past page one.
   The script now pages the feed (bounded) until a comment at or before the
   baseline appears; the prose claim was corrected in both places. A
   recurrence caused by our own incomplete sweep, so fixed, not declined.
   (Correction: the round-6 reply claimed the prose was fixed alongside
   the script; it was not, and round 7 caught exactly that. Owned in the
   7b reply.)
7. Three findings, all the third recurrence of the same class (a
   single-page read treated as the collection): detection stopping at
   review history without scanning reactions for signals, the step-1 prose
   still claiming first-page-by-construction, and the script's
   `reactions(last:20)` window. Swept the class for real this time: the
   script now reads all three signal sources (reviews, comments,
   reactions) through bounded-paged REST feeds — the class member Codex
   never cited, `reviews(last:20)`, was equally vulnerable on this very PR
   (17+ reviews) — and the prose names the windowed-connection class and
   the paged-read rule instead of blessing any single page.
8. The adversarial pass's own fix was a half-sweep: "validate every option
   before interpolation" missed `--reaction-login` (jq filter) and
   `--repo` (URL path). Both validated now. Evidence for the
   recurrence-after-sweep escalation rule: the sweeper (me) drew the class
   as "the flags the lens cited" instead of "every caller value reaching a
   filter or URL".
9. The round-7 rewrite's fixed 10-page ceiling violated the "page until
   the baseline" contract (and dropped the comments feed's desc sort,
   making all three scans ascending, so >1000 pre-baseline items would
   hide new activity past page 10 until the cap). Replaced the ceiling
   with baseline-crossing termination: comments walk a newest-first feed
   forward until a page's oldest item is at or before the baseline;
   reviews and reactions (no sort parameter) walk backward from their last
   page, located via the connections' totalCounts refreshed each poll.
   Pages scanned now track actual post-baseline activity, not a constant.
10. The script matched by timestamp only, while the skill's
    delegated-watcher contract says "activity on that head": a pass
    against a superseded head landing after a new push's baseline would
    end the wait as if it were the awaited round. Added `--head`: reviews
    must be of that commit and comments must anchor to it, except replies
    to existing threads (`in_reply_to_id` set), which keep their old
    anchor yet are a genuine completion signal, so naive head-filtering
    would have broken the reply signal. Reactions carry no commit, so the
    clean-pass signal stays time-only (documented).
11. Two findings: em dashes in the PR's added skill-prompt prose (the
    repo convention lint cannot catch; every added em-dash line replaced,
    as its own mechanical commit per the churn convention and the
    visual-evidence precedent), and `--pr 0` passing the digits-only check
    to burn the full cap on a nonexistent PR (validation now rejects zero
    and leading zeros).
12. A failed review/comment scan was indistinguishable from zero matches,
    so a transient API error concurrent with a post-baseline clean-pass
    reaction could report a findings round as CLEAN_PASS. Scanners now
    return a status; the clean-pass verdict (absence-based) requires all
    scans to have completed, while positive activity evidence stands even
    from a partial scan. Verified with a gh shim that fails only the
    comments endpoint: the script logs the failed scan and falls to the
    cap instead of emitting CLEAN_PASS.
13. The round-7 detection sentence said to scan reactions "by that same
    login" after reviews identify the bot, but that login is the
    review-author form and matches no reactions: the login-form class
    re-introduced by our own fix, third member (rounds 2, 4, 13). The
    sentence now names the reaction form explicitly.
14. (User P2, not Codex.) The argument-validation class was still open:
    every option arm read `$2` before checking a value existed (bare
    `--pr` crashed with set -u instead of exit 64), the baseline shape
    check accepted fragments like `T00:00:00Z`, `--head` accepted
    over-40-char and uppercase SHAs (case-sensitive matching would then
    silently never match), and logins accepted malformed bracket forms
    (`bad[form]`, `a[bot]b`). Fixed as one parser/validation sweep, and
    the whole matrix now lives as a committed offline regression test
    (`scripts/test-watch-review.sh`, 37 cases against an always-failing
    gh shim: valid inputs cap out with exit 2, rejects exit 64), wired
    into the done checks so future validation fixes must add their case
    instead of dripping one finding per round.
15. With gh missing from the environment (and --repo supplied so nothing
    touched gh before the loop), every poll failed silently and the
    watcher sat out the full cap looking like "no reviewer activity". A
    command -v preflight now exits 69 immediately with a pointer to the
    skill's prose fallback for a missing host CLI; matrix case added
    (38 total). Codex's pass before this one was the PR's first live
    clean pass: no review, only the 👍, detected by the script's exit-3
    path in minutes instead of the 25-minute cap.
16. The iteration-counted loop slept only between polls, waiting
    (N-1) intervals: short of the documented cap, and with interval >=
    cap, not at all (cap 1 min at interval 75 exited immediately).
    Replaced with a deadline-driven loop whose final poll runs at the
    deadline itself; timed against a dead-gh shim, a 1-minute cap at a
    45s interval now takes exactly 60s with polls at 0/45/60.
17. Declined with evidence: the round-17 ask to tie reply comments to the
    expected head via their enclosing review cannot work, verified
    empirically on this PR's own replies: GitHub stamps a review's
    commit_id with the head current at submission (a reply posted 16s
    after a push carries the new head regardless of what was analyzed)
    and retroactively re-anchors comment commit_ids (a comment showed a
    head pushed ten minutes after the comment's creation). No API-level
    discriminator for a racing pass exists; the failure mode is one early
    wake the main agent absorbs. The --head docs now state their
    best-effort scope honestly.

## Second adversarial pass (script re-refute, after round 16)

The script had been rewritten far past the first pass's audit surface
(paging walks, head filter, preflight, scan status, deadline loop) while
serial rounds kept yielding one script defect each: the
recurrence-after-sweep trigger. One lens, one confirmed HIGH the matrix
missed: scan_asc_tail broke on an empty top page of a backward walk, but
GraphQL totalCounts over-count the REST collections (pending reviews,
removed reactions) persistently, so the walk returned zero without ever
reading page 1: a real review or clean pass reported as CAP_EXPIRED,
every poll. Fixed (empty page above page 1 now walks down; only an empty
page 1 means empty) and the matrix gained canned-response page shims
that exercise the walk logic itself (41 cases), which the dead-gh shim
never reached. The lens verified and dropped six other suspicions.

Mid-review the user asked for the watcher as a shipped artifact:
`watch-review.sh` now lives in the skill directory (parameterized on PR,
baseline, both login forms, signal contents, cadence, cap; distinct exit
codes for review activity, clean pass, cap expiry) and the prose points to
it as the canonical GitHub implementation, precisely because round 2 proved
prose and working script drift apart.

## Adversarial pass (three refute lenses, after round 5)

With five consecutive same-class rounds, the user asked whether an
adversarial review would pay; three parallel fresh-context refute lenses
(script robustness, cross-surface consistency, factual/platform claims) ran
per the optional risk-gated convention. Dispositions:

- Confirmed and fixed: script crash on zero/non-numeric `--interval` /
  `--cap-minutes`; jq injection through unvalidated `--clean-content` /
  `--progress-content` (demonstrated false CLEAN_PASS); quote-in-login
  silently disabling detection; negative/non-numeric option values (all
  closed by validating every option before interpolation, as an
  input-space enumeration, not per-flag patching). Codex trigger described
  inconsistently across three surfaces (step 2 read as command-required,
  the repo record lacked the push trigger we observed live all session,
  step 5 assumed every reviewer is push-triggered; all three aligned, and
  step 5 now says to re-issue a command trigger after a fix push).
  Universal `name[bot]` reaction-form claim contradicted the script's own
  machine-user carve-out (prose now states the App-bot vs machine-user
  split in both places). "One-line note" contradicted the multi-field
  record the same bullet mandates (now "compact record", all surfaces).
  Break-even figure said "a dozen wakes / ~45 min" where the stated
  cadence and one-cold-read framing yield ~ten (corrected). Backgrounded
  no-model poll gate strengthened: backgrounding without completion
  re-invocation stalls silently, so the gate now names re-invocation.
- Declined with reasons: strict after-baseline comparison at the exact
  baseline second (deliberate: matches the documented "after the baseline"
  semantics; a same-second reviewer pass is not a realistic behavior and
  inclusive matching would replay handled reviews on request-time
  anchors). The 👀 in-progress claim being unverifiable on completed PRs
  (already hedged as user-observed and transient in the text).
- Verified clean by the lenses: all GitHub API field/form claims
  (empirically, against PRs 41–46), managed-block byte-identity, exit-code
  contract, cadence/cap ranges, and the step cross-references.

## Deferred / open

- The keepalive break-even math assumes typical current pricing multipliers
  (cached read ~0.1x, cache write ~1.25x); if those shift, the wake figure
  in the skill should be re-derived. (The skill's stated figure is ~ten
  wakes, consistent with its own one-cold-read framing at a 270s cadence;
  this entry's earlier "~12 wakes / ~55 min" derives from the 1.25x
  cold-with-cache-write variant.)
- Whether a later clean round refreshes the Codex 👍 `createdAt` (see
  caveats) is worth confirming when a multi-round PR next goes clean.

Session retrospective (user-approved deferrals): watching is now free, so
the remaining cost driver is per-round ceremony in a fat main context
(~12–15 mechanical tool calls per round against 1–2 actual edits, each
replaying the full context). Deferred follow-ups, in leverage order:

- **Drop SHAs from the PR-body commit map** (reference commits by subject):
  every fold rewrites all SHAs, forcing a body rewrite per round; subjects
  don't go stale. Inline thread replies keep citing SHAs (written once,
  post-fold). A canonical pull-requests convention tweak.
- **Bundle a round close-out script** (reply-with-disposition + resolve
  thread + fold-verify + watch restart), same rationale as
  `watch-review.sh`: the sequence is mechanical, identical every round, and
  regenerating it per round both costs tokens and drifts.
- **Persistent fixer subagent across rounds**: the skill's delegated-fixer
  break-even treats rounds independently (fresh fixer pays rebuild every
  round, so short rounds lose); a fixer that persists across the
  convergence loop pays rebuild once and keeps the main context from
  accumulating round debris, likely winning on any 4+ round exchange even
  when each round is individually below the break-even. Skill text doesn't
  yet make this distinction.
- **Watcher cadence vs cache TTL, observed**: Codex latency ran 2m54s–4m46s
  after each push, right at a 5-minute cache TTL, so a tight (75s) no-model
  poll often wakes the main agent inside the TTL (cached read) where a 270s
  poll would wake it cold: a ~12x swing on the wake read that strengthens
  the fast-cadence guidance already in the skill.
- **Auto-trigger an adversarial class-sweep from finding history** (step 5
  policy change, own PR). Trigger unit refined mid-session by the user:
  hinge on **individual findings sharing a class, not on rounds** — rounds
  are just the serial reviewer's delivery batching, and a single review
  carrying two same-class findings (round 5 here) is already the signal.
  Rule: classify every finding as it arrives (any source: serial rounds,
  adversarial passes, self-review); when a class gains its **second
  member** — same review, adjacent rounds, wherever — sweep that class
  exhaustively. And when a class recurs **after** you believed it swept,
  the class boundary was drawn too narrow, so escalate: redefine the class
  one level up and enumerate it (this PR's paging class needed that twice:
  "thread page" → "REST comment page" → the true class, "any single-page
  read of any connection"; the finding-level trigger at round 5b/6 would
  have preempted round 7's three findings). Economics: a round costs
  R ≈ 1.5–3x the main context in token-equivalents plus ~10 min latency; a
  3-lens refute pass costs about one R and one round's wall clock, so it
  pays when P(≥2 more preemptable rounds) ≳ 0.3–0.5, which a second
  same-class finding empirically clears (this PR ran seven findings
  rounds; this session's own pass surfaced eight confirmed defects for
  roughly one round's cost). Guardrails: one pass per PR, re-arm only on a
  repeated post-pass class; platform-gated on delegation with serial as
  fallback; evidence-or-drop on the pass's findings. Don't fire on
  mixed-class declining-severity findings, small contexts, or
  single-surface diffs.
