# Context discipline: a seventh canonical section

Ben asked which agent-setup changes would be large wins for context
management. Four candidates were ranked by replay accounting (every
tool call re-sends the conversation; cached reads ~0.1x, cache writes
~1.25x, ~5 min TTL; re-derive if pricing shifts):

- The ~5k-token managed payload costs ~56k token-equivalents over a
  100-call session, so trimming it is a ~1% win per 1k tokens cut.
- A 30k-token raw exploration dump pulled in early replays to ~240k
  equivalents, 40-50x the static-trim lever. Keeping bulk out of the
  working context is the win that matters; that drove the ranking.
- A review round measures ~1.5-3x the main context (see the 2026-07-02
  cost-signals entry); a fresh ~25k session vs a bloated ~150k one is
  ~6x cheaper per call, and the rebuild from PR body + devlog entry
  amortizes inside the first round.

## Decisions

- **New managed section `context` ("Context discipline")**, between
  finish-line and Build: keep raw bulk out (ungated core, doubles as
  every fallback), delegate broad exploration, right-size delegated
  work, no quiet fan-out, prefer a fresh session over a bloated one.
  Capability-dependent rules gated per invariant 2. No pricing figures
  in canonical text; multipliers live here and go stale here.
- **Devlog checkpoint bullet** (README template, one home): the
  unmerged entry may be written incrementally at checkpoints so a
  fresh session can resume from entry + PR body. The bookend gains
  only a pointer half-sentence.
- **Init guidance: lean project-specific payload**; reference material
  goes to docs/ behind a pointer naming its read trigger.

## Deferred

- **Progressive disclosure of the pull-requests section** (~65-75
  movable lines: merge mechanics, Reviewing a PR, Stacked PRs, the
  reviewer-record field list) into a scaffolded playbook file. Honest
  token win is ~1%/session; the case is attention and window headroom.
  Needs read-before-act triggers inline (a pointer-skipped merge
  recipe re-embeds PR bodies in history, the exact PR #60 regression
  class) and a watch on the first downstream sync. Not re-raised by
  this entry's scope.
- **O(1) promotion-queue index** (one mutable file, drained lines
  deleted) replacing the grep + drain-record cross-reference, which
  grows with entry count (54 entries, 12 queue files today). Deferred:
  it re-litigates the directory-of-entries merge-conflict rationale in
  devlog/README.md, so it needs Ben's explicit sign-off, not an
  agent's judgment.
