# Score await-pr-review With a Stub Forge and Reviewer

Issue #443 gives `await-pr-review` a program-graded eval, so #444 can shrink
`SKILL.md` while holding a score. The eval follows the layout
`scripts/run-scored-eval.sh` reads (`devlog/2026-11-18-2054-merge-cleanup-scored-eval.md`).
The proof record and draft goal file live in
`~/.hill-climb/free-skills/await-pr-review-size/`.

## Decisions

- **Chose a stub forge that also plays the reviewer.** A real reviewer is
  slow, costs money, and can't be held still between attempts. The stub
  gives a clean-pass reaction one second after each push, or after the
  trigger comment for a command reviewer. So a run that anchors its
  baseline to the event sees the pass at once. CI is the pushed head's own
  `test.sh`, so a planted bug fails until the fix lands.
- **Graded the baseline from the watch's own filter.** Pre-push review
  showed that "the run read reactions after its push" passed a run whose
  baseline came after the pass. `watch-review.sh` writes its baseline into
  each reactions read's `--jq`, so cases 1, 5, and 7 now require a read
  whose filter admits the pass.
- **Chose a frontmatter-only known-bad over a single-section drop, by the
  owner's decision.** No section's removal separated from the baseline
  (1.000 on all six repeats). Each of seven section drops scored 0.944 or
  1.000, and five single-rule removals scored 1.000. A frontmatter-only
  `SKILL.md` scored 0.722 with a best repeat of 0.833. The owner chose it
  over shipping without a proof record, with every silent rule bound as a
  goal-file Constraint instead.
- **Finding for #444: the score guards collapse, not individual rules.**
  The agent rebuilds the rules from `references/`, `watch-review.sh`, and
  the fixture's AGENTS.md conventions. Pooled, the section drops failed 7 of
  126 runs against 0 of 36 at baseline. That signal is real but too sparse
  for three repeats. So the climb may condense wording, while the
  Constraints, not the score, keep each rule.
- **Re-froze after proving found a stub bug.** An inline GraphQL reply
  body parsed as empty on BSD `sed`, and the stub still reported success.
  That cost one baseline run before the fix. A stub that reports success
  on a failed write turns its own bug into noise, so writers now fail
  loudly.

## Limits

- **Agents read the stub's state.** About half the proving runs read a
  `forge/` file, and a quarter read `forge/reviewer`, which names the
  reviewer. Cases 5 and 6 can't tell detection from lookup. No run wrote
  forge state. Follow-up: #474.
- **One model and route.** All scores use `claude-sonnet-5-5` in headless
  Claude Code. The reviewer never posts new findings, so fix rounds 2 and
  later stay hand-graded.

Revisit when #474 hides fixture state, or when a cheaper score allows
enough repeats for a single section's drop to separate.
