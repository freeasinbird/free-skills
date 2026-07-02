# Trigger-eval result for await-pr-review: keep the description

Closes the deferred description-trigger optimization from
`2026-07-02-0418-await-review-skill-audit.md`. The user approved the
20-query eval set (10 should-trigger, 10 near-miss should-not) as drafted;
the skill-creator optimization loop
(`run_loop.py --model claude-fable-5 --max-iterations 5`, 60/40
train/test split, 3 probe runs per query per iteration) then ran twice.

## Outcome

- **Keep the current description unchanged.** The original won the train
  split (8/12) against all four generated rewrites (6–7/12), and every
  variant tied at 4/8 on the held-out split, so `best_description` came
  back byte-identical to the shipped one. No commit to SKILL.md.
- The eval set is committed at
  `skills/await-pr-review/evals/trigger-eval.json` so a future
  description change can be re-scored against the same baseline instead
  of regenerating queries.

## Harness gotchas (why the first run was thrown away)

- **A user-installed copy of the skill invalidates the measurement.**
  This repo symlinks its skills into `~/.claude/skills/`
  (`link-skills.sh`), so probe sessions saw both the real
  `await-pr-review` and the harness's hashed sandbox copy with the same
  description. Probes invoked the real name; the detector counts only the
  sandbox name; result: 0 triggers in 300 probes, and the "scores" were
  just the should-not queries passing by default. Rerunning with the
  symlink parked outside `~/.claude/skills/` (a dot-renamed link in the
  same directory still loads) restored detection, verified with a
  2-query sanity eval before paying for the full loop.
- **Absolute trigger rates from this harness are depressed and not
  representative.** Probes run `claude -p` from the home directory with
  no repo, no PR, and no session context, and every failure was a
  should-trigger query at a 0.0–0.33 rate while the skill demonstrably
  triggers in live sessions (it fired unprompted for PR 50 in the same
  session). Use the harness comparatively (variant A vs variant B on the
  same set), never as an absolute health metric.

## Deferred

- Simulated-PR behavioral eval harness: still not built; carried over
  from the audit entry unchanged.
