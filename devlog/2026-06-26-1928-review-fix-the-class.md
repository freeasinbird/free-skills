# Reinforce agent-setup: fix the review class, not the cited line

The visual-evidence PR (#20) drew five Codex rounds. A recurring shape: the bot
cited one instance (e.g. a hard-coded `main`), I fixed only that line, and the
next push got flagged for the sibling instance. The base-branch nit alone cost
two rounds for exactly this reason. agent-setup's "Responding to automated
review" bullet covered evaluate-on-merits / reply-with-SHA / resolve, but not
_sweep the whole class_ or _converge vs. chase-to-zero_.

## Change

- New bullet in the `pull-requests` canonical section — **"Fix the class, not
  just the cited line"**: when a finding names one location, sweep the file/repo
  and fix every instance in the same push (bots re-review per push and flag
  siblings otherwise); expect the loop and diminishing returns, so converge and
  hand off rather than chasing every round to zero.
- Applied to both the canonical source
  (`skills/agent-setup/references/canonical-sections.md`) and free-skills' own
  synced `managed:pull-requests` block in AGENTS.md (free-skills is itself an
  agent-setup consumer). Verified byte-identical between the two.

## Scope held

Only this one gap was a genuine convention miss. Other session frictions were
already covered (in-thread reply + SHA + resolve, fold-fixes, watch-between-
turns), project-specific (the `>-` frontmatter rule, #22), or my own execution
slips (a top-level comment before switching to inline; committing before
confirming lint) — none warranting a convention change.

## Verification

Markdownlint + prettier --check clean. Diffed the inserted bullet across both
files — identical.
