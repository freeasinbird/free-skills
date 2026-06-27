# Make watching for the reviewer the default, not ask-permission

Follow-up to the reviewer-identity PR (devlog `2026-06-27-0047`), split out so
that PR holds a single contract. Stacked on `feat/await-review-detection`;
auto-retargets to `main` when the base merges.

## Why

Dogfooding the await-pr-review skill surfaced that the agent _asks permission_ to
run the watch after opening a PR — which is exactly the manual "go poll the PR"
friction the skill exists to remove. Two things licensed the stop-and-ask:

- the finish-line hedge "This is guidance, not mandated automation"; and
- the skill describing itself around whether the user "wants" a watch.

## Change

Where a reviewer is active and the platform can watch non-blockingly, **starting
the watch is the default** — gated on platform capability, never on whether to
bother; fall back (bounded foreground poll / hand back) where the capability is
absent. The convention must still be capability-agnostic: use any available
review-watch skill/tool/automation first, but name none in canonical text.
Guardrails added during review: one active watch per PR/reviewer; on push,
advance/replace the watch baseline; don't oversell non-blocking as "free"; and
foreground polling is only a bounded current-turn fallback. Two surfaces:

- Managed finish-line "Watch for new review activity" bullet (canonical + this
  repo's AGENTS.md, diff-identical) — replaced the hedge. Kept invariant-#2-safe:
  the canonical text names no skill, only the generic watch capability.
- Skill description / intro / when-to-use — dropped the "want the agent to watch"
  framing.

## Codex review

- Baseline-vs-checks ordering: the handoff list waits on required checks
  _before_ the now-default watch starts, but await-pr-review baselines existing
  reviews at start — so a review the bot posts during the checks wait (Codex
  fires on PR open) would be swallowed as already-seen and handed off
  unhandled. Fixed by anchoring the watch baseline to the **last push**, not
  watch-start: activity since that push is in-scope regardless of when the watch
  begins, and the watch should start as soon as the PR is open so the checks
  wait can't defer it.
- Re-review P1 (sweep miss on my own fix): I anchored the convention text
  (AGENTS/canonical) to last-push but left the skill's own **step 1 baseline**
  ("record what already exists") un-anchored — so a review landing after the
  last push but before the watcher starts would still be banked as pre-existing.
  Fixed step 1 to anchor the baseline to the open/push event time and start the
  watch before waiting on CI. Same class as the convention fix; folded into the
  same commit.
- Re-review P2 (correctness of the P1 fix): last-push anchoring is right for an
  open/push-triggered wait but wrong for a **manual re-trigger with no new push**
  — reviews already handled since the last push would re-count as new and exit
  the wait before the requested pass posts. Fixed step 1 to anchor to the
  _triggering event_: last push for push/open waits, the **request time** for a
  manual recheck (snapshot current reviews as already-seen). Folded into the same
  commit. (Note: per user, we don't manually trigger Codex on this repo — but the
  skill is general and still documents manual triggers, so the case must be
  correct.)
- Re-review P2 (actual push time, not commit time): using the head commit's
  authored/committed time as "last push" can replay an already-handled review
  when a locally-created commit is pushed later. Fixed step 1 to capture the PR
  open/ready or actual push event timestamp at the event boundary (or read that
  event timestamp from the host), and explicitly reject commit timestamps as the
  baseline proxy. Folded into the same commit.
- Re-review P2 (managed fallback no-push triggers): I fixed the skill baseline
  but left the managed fallback convention saying every watch baseline anchors to
  last push. That is wrong for no-push triggers (marking ready or a manual review
  request) because already-handled reviews since the last push can replay. Fixed
  the managed convention to anchor to the event expected to produce the next
  reviewer pass: PR open/ready or actual push for open/push-triggered reviews,
  request time for no-push rechecks. Folded into the same commit.
- Re-review P2 (checklist gap): I updated the handoff prose but not the
  start-of-session finish-line checklist, so the checklist still said open PR →
  poll checks → self-review → hand off with no review-watch step. Fixed by adding
  the watch/baseline step immediately after opening the PR and before waiting on
  checks in canonical + AGENTS.md. Folded into the same commit.
- Codex-app watcher path: this session proved a Codex app subagent can poll PR
  review state, but that alone is not enough for await-pr-review's non-blocking
  contract — if completion doesn't reliably notify/re-enter the main agent, the
  main thread can sit idle after the watcher returns. Updated await-pr-review to
  require that completion signal before selecting delegated watcher/subagent, and
  swept the managed convention to require a watch mechanism that can report back
  without manual polling. Kept watcher-only guardrails (no edits, commits,
  pushes, trigger comments, thread replies, or resolves) and kept Codex CLI as
  the synchronous/no-subagent fallback case. Folded into the same commit.
- Re-review P2 (permission-gated subagents): the delegated watcher path gated on
  capability but not on whether the session policy allowed delegation without
  asking. Fixed await-pr-review and swept the managed review-watch convention to
  require a permitted mechanism; if permission is not already granted, it falls
  through to backgrounded polling, scheduled wake-up, bounded foreground polling,
  or hand-back. Tightened "ask permission" wording to "ask whether to watch" so
  permission only refers to policy/tool approval. Folded into the same commit.
- Re-review P2 (watcher report body): the delegated watcher report contract
  named review state, threads, and checks but omitted the top-level review body,
  even though review state/body can hold actionable feedback with no inline
  thread. Fixed await-pr-review to require the matching review ID, state,
  `submittedAt`, body, thread/comment IDs, path/line, and checks status — or an
  explicit instruction for the main agent to refetch the body before declaring
  clean. Folded into the same commit.
- Re-review P2 (watch completion before handoff): the finish-line checklist
  started a watch but still allowed checks/self-review to finish and hand off
  while the watch was pending. Fixed the managed checklist to require the watch
  to finish before handoff: handle in-scope activity, or record the bounded
  timeout / no-review result with the baseline. Folded into the same commit.

## Why separate from the base PR

This is workflow _policy_ (when to engage the watch at all), distinct from the
base PR's contract (what identity a repo records so the watch can match a
reviewer). Mixing them expanded the base PR while its contract was still being
revised across review rounds — so it became its own unit.

## Verification

Markdownlint clean; prettier --check clean; finish-line bullet diff-identical
across canonical + AGENTS.md; SKILL.md frontmatter parse-safe `>-` block scalar.
