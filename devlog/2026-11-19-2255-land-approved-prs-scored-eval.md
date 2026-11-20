# Score land-approved-prs with a Fixture Forge

Issue #439 built the scored eval that the `land-approved-prs` size climb
(#440) holds. Eleven cases run the real bundled scripts against a fixture
forge and a stand-in merge-cleanup skill, graded by program. The current skill scored 1.000 twice with a 0.000 band;
dropping one section scored 0.556.

## Decisions

- **Chose to install the merge-cleanup stub at
  `<fixture-dir>/../skill/merge-cleanup` over changing the runner.** The
  skill requires merge-cleanup beside its own copy. `run-scored-eval.sh`
  copies the candidate to `<run>/skill/<name>` after setup and documents
  only the fixture directory, so setup writes outside its documented
  directory and relies on the run layout. A runner option to stage sibling
  skills would make that contract explicit, but #439 excluded runner
  changes, and one skill needs it. `fixture_done` fails loudly when the
  layout changes and `<fixture-dir>/../skill` is missing, so a runner change
  breaks every setup instead of silently dropping the stub.
- **Chose a stub over the real merge-cleanup.** The real skill would delete
  branches and worktrees in the fixture and need its own forge calls. The
  stub logs its arguments and removes nothing, so case 1 grades what the
  batch passes (`--pr 7`, `--repo host/owner/name`, a sweep with
  `--remove-landed` only, after the lock's release) without testing
  merge-cleanup, which its own eval covers.
- **Kept the stub's scripts as `.sh.in` templates.** `check-skill-structure.sh`
  reads every `.sh` under the skill, `evals/` included, and checked the
  skill's sweep examples against the stub's flags. The scripts already
  needed `@FORGE@` replaced at install, so `.in` matches `SKILL.md.in`.
- **Derived forge state from the origin's ref log.** A reference-transaction
  hook records every branch and lock update. The stub computes PR heads,
  pull_request CI runs, and force-push events from that log, so the real
  `land.sh` and `list-ready.sh` see a consistent forge after any push, and
  graders read lock use from the same log.
- **Kept `land.sh`'s `remote-unresolved` stop.** Local-path remotes can't
  resolve to a forge, so the agent must pass `--base-remote origin`. That is
  the skill's documented path for such a layout, not fixture friction.

## Findings

- **One dropped section separates the score.** Removing `### Hand-Back`
  scored 0.556 in every repeat, against 1.000 in all nine baseline repeats
  across two revisions. Without it, the agent commented and added
  `needs-human` but kept `approved`, in every run of cases 6, 7, 8, and 10.
  The plan's fallback sections (`## Ordering`, `## The End-of-Batch Sweep`)
  went untried.
- **Chose to report `## Revoking Approval` as weakly guarded over
  tightening case 9.** A fresh-context review found case 9 graded only that
  nothing ran, so its grader now also requires the answer to say to stop
  the `land` processes. Even so, a copy without the section failed case 9
  in only 2 of 9 runs: the agent reasons the advice out from how the engine
  merges. A stricter check would fail those correct answers. The size climb
  (#440) should keep that section as a constraint.
- **This skill's bundle doesn't restate its rules.** A frontmatter-only copy
  scored 0.407 with a 0.223 band, and two runs merged with no merge-cleanup
  installed. merge-cleanup's frontmatter-only copy scored 0.952, because its
  scripts' `--help` and `references/` rebuild the procedure. So a size climb
  here (#440) gets a sharper score, but each cut is likelier to drop a rule
  that lives only in `SKILL.md`.
- **Cost.** About $3.90 and 6 to 8 minutes per 27-run climb score.

Revisit when `run-scored-eval.sh` gains a way to stage sibling skills, or
changes its run-directory layout.
