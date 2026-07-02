# Skill-creator audit of await-pr-review: progressive disclosure

User asked for a skill-creator audit-and-improve pass over
`skills/await-pr-review/`. The audit verdict: the content decisions
(converged over the 2026-06-26 through 2026-07-02 sessions and their
review rounds) are sound and were explicitly out of scope to re-litigate;
the deficits were structural. SKILL.md had grown to 530 lines that all
load on every trigger, with long cost-model derivations inline, three
caveats each restated 3–4 times, 35 leftover em dashes (033ef6e swept
only PR-touched prose), and a never-trigger-tested ~180-word description.

## Fixed

- **Split derivations into `references/`** (progressive disclosure):
  `references/detection.md` takes the GraphQL snapshot query, the
  windowed-connection/paging derivation, and the reviewer-detection scan
  mechanics; `references/cost-model.md` takes the cache-keepalive
  arithmetic, the observed-latency/12x wake derivation, and the
  delegated/persistent-fixer break-even math. Every decision rule and
  headline number stays inline in SKILL.md (cadences, caps, the ~45 min
  keepalive ceiling, the both-must-hold fixer rule, 4+ rounds, the refute
  pass economics), so an agent that never opens references makes
  identical choices. SKILL.md: 530 → 500 lines.
- **Deduplicated the repeated caveats** to one canonical site each:
  baseline anchoring (step 1), the GraphQL-vs-REST login-form rule (step
  3's author-filter paragraph, now explicitly "the canonical login-form
  rule"), platform gating (general rule in Platform support; the
  per-mechanism gate+fallback clauses stay at their instruction sites per
  invariant 2, deliberately not hoisted).
- **Swept the remaining em dashes** (mechanical commit, recorded in a new
  `.git-blame-ignore-revs`).

## Verification

- A no-deletion token audit greps the union of the three files for every
  load-bearing number/rule token; all present. Lint, prettier,
  managed-sync, and the watcher validation matrix (41/41) green.
  `watch-review.sh` untouched.

## Decisions

- Two references files, not one: the load moments differ (detection.md is
  read when hand-rolling the watch or detecting an unrecorded reviewer;
  cost-model.md only when a break-even call is genuinely borderline).
- Step 5's refute-pass economics stay fully inline: at ~5 lines they are
  the decision rule itself, applied mid-loop when a reference read is
  least likely.
- The `.git-blame-ignore-revs` entry lands in an immediate follow-up
  commit because the sweep commit's SHA only exists after the sweep
  commit does.

## Deferred / open

- **Description-trigger optimization** (skill-creator `run_loop.py`): the
  ~20-query trigger eval set is drafted and the review page was opened
  for the user; the loop runs after their sign-off, and any
  `best_description` is applied only with approval (it must preserve
  watch-by-default, the clean-pass signal, and the not-for cases). If it
  lands, it is a follow-up commit on this PR.
- **Simulated-PR behavioral eval harness** (gh PATH-shim fake PR states,
  old-vs-new SKILL.md subagent runs, graded): offered as a follow-up, not
  built; static checks plus the live Codex dogfood cover this PR.
- Still-open observation items from `2026-07-02-0003` carry over
  unchanged: keepalive break-even re-derivation if pricing multipliers
  shift (now noted inside `references/cost-model.md` too), and whether a
  later clean Codex round refreshes the 👍 reaction's `createdAt`.
