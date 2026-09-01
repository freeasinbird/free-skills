# Shorten await-pr-review SKILL.md to a routing core

Issue #202. The 2026-09-01 transcript audit found `SKILL.md` (495 lines,
24 KB) was the largest repeated read in the corpus: Codex sessions read it in
two or three bounded chunks and truncated the output 501 times.

## Decisions

- **Chose a line bound (220 lines, 2,000 words) in
  `scripts/test-await-pr-review-routing.sh` over a byte or token bound.** The
  audit observed line-chunked reads, and Codex's output cap is not stable
  across versions. Local session logs show Codex 0.147 truncating near
  10,000 tokens (about 40 KB retained), while July 2026 sessions retained
  about 4 KB. A line bound matches what the reads actually do; any byte cap
  small enough to matter would also reject every reference file. The bound
  is the budget #207 and #208 must fit within: a rule that needs more room
  moves to a reference and leaves a pointer.
- **Kept in `SKILL.md`:** the Authorization section, the ownership gate with
  its host examples (the routing test pins those strings), the six numbered
  steps, and the thirteen convergence phrases pinned for the `SKILL.md` layer
  in `scripts/review-convergence-layers.tsv`. Those pins set the floor: the
  file landed at 217 lines and 12 KB, not the issue's nominal 200, because
  the pinned phrases and the 80-column wrap leave no further slack without
  dropping a rule.
- **Chose `## §slug` headings only for sections `SKILL.md` points to,
  leaving other reference headings plain.** The structure check requires
  every `§` heading to be pointed at, and each pointer costs `SKILL.md`
  lines. `skills/agent-setup/references/scaffolding.md` already mixes the two
  styles. Contents lists keep their anchors, since GitHub and markdownlint
  strip `§` when slugging.
- **Rejected shortening the frontmatter description.** It is the trigger
  surface, and the issue scopes the body, not routing or triggering.
- **Rejected wrapping beyond 80 columns.** It would lower the line count
  without lowering bytes and would break the repo's wrap convention.

## Moved Content

- Host-specific grant mapping, in full: `conductor.md` §host-mapping.
- Spawn facts, model tier, attribution gap: `conductor.md` §spawn-brief.
- Terminal snapshot, readiness bars, stale base handling, checks wait, leave
  open: `conductor.md` §quiescence-and-reporting.
- Main-owned mechanism ladder and watcher-subagent limits: `detection.md`
  §main-owned-mechanisms.
- Watch invocation, exit codes, one watch per PR, coverage reporting:
  `detection.md` §watcher-invocation.
- Autosquash and standalone review-fix commit check: `review-response.md`
  §fold-push-verify-reply-resolve.

Revisit when Codex or Claude Code changes how skills are read (a whole-file
load with no cap makes the line bound moot), or when the pinned phrase table
shrinks enough to reach 200 lines without dropping a rule.
