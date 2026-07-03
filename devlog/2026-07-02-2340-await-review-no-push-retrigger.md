# await-pr-review: re-trigger the reviewer after a no-push round

Fills a gap in the convergence loop (step 5): it assumed every handled
round produces a fix push, and that the push is what re-triggers the next
automated pass. A push-triggered reviewer (Codex) after a round handled with
**no push** (every finding declined, or a pure judgment-call round with no
code change) never gets a fresh pass, and if the loop then waits,
`watch-review.sh` burns its entire cap to `CAP_EXPIRED` on a pass that will
never come. The manual re-trigger affordances exist (`@codex review`;
draft->ready toggle, both recorded in this repo's Codex entry), but the skill
never told the agent to use them here.

## Decision

- **Always re-trigger after a no-push round**, over the safer
  "converge unless reconsideration is wanted" alternative. User chose it:
  a declined finding gets a chance to be reconsidered and unaddressed items
  stay in front of the reviewer. The risk (a decline -> re-raise -> decline
  loop) is absorbed by step 5's existing value-taper stop: a marginal-nit
  round gets declined and handed off, so the loop still terminates.
- **Prefer the manual command over the draft toggle.** `@codex review` has
  no side effects; marking a PR draft can dismiss approvals and block merge,
  so the toggle is a fallback used only when the reviewer has no command but
  its recorded trigger set includes ready-for-review. Reviewer-specific
  command + host-generic toggle keeps it platform-honest (invariant 2): use
  only what the reviewer's _recorded_ trigger re-fires on, else hand off
  rather than emit a doomed wait.
- **Reused existing machinery, no new code.** Baseline anchoring for a
  no-push re-trigger already lives in step 1 (the manual-recheck rule); the
  edit points step 5 at it instead of leaving the no-push path undefined.
  `watch-review.sh` is untouched (read-only watcher; re-triggering is the
  caller's job), so no managed-block, canonical, or eval changes.

## Scope

`skills/await-pr-review/SKILL.md` prose only: step 5 opening paragraph
rewritten to split on "did this round push a fix?"; a one-line pointer added
to step 4's decline bullet; the step 5 loop line changed from "after each
fix" to "after each round, re-trigger as above" so no-push rounds are visibly
in the loop.

## Verification

- Prose-tics clean, markdownlint 0 errors, prettier clean (full repo, 205
  files).
- Not run: `watch-review.sh` unchanged, so the watcher matrix and
  managed-sync checks aren't triggered by this change.

## Review round (Codex)

- P2, confirmed and folded: this devlog used `*recorded*`; prettier's
  markdown style is `_recorded_`. The pre-handoff full-repo prettier check
  ran before this file existed, so it never covered it; re-running
  `prettier --check` on the file caught it. Fixed by `prettier --write`,
  folded into the commit that introduced the file. Lesson: run the format
  check after the devlog is written, not before.
