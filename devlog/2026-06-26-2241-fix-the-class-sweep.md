# Strengthen fix-the-class: make the sweep mechanical (grep, don't eyeball)

The await-pr-review dogfood loop (#27) exposed a hole in the #24 "fix the class"
convention: round 7 I fixed the cited sentence and eyeballed for siblings, but
missed one — round 8 flagged it, the exact one-at-a-time loop the convention is
meant to prevent. The wording said "sweep the file/repo" but didn't push hard
enough on _how_; I read "sweep" and didn't actually grep.

## Change

Added one clause to the `pull-requests` "Fix the class" bullet: **make the sweep
mechanical** — grep/search for the finding's pattern rather than eyeballing
nearby lines, because the class routinely recurs in sibling sentences or files
the citation never named, and a half-sweep just resurfaces it next round.

Applied to both the agent-setup canonical source
(`skills/agent-setup/references/canonical-sections.md`) and free-skills' own
`managed:pull-requests` block (dogfooding-sync rule), verified byte-identical.

## Note

Did **not** touch the await-pr-review SKILL.md's own fix-the-class line — that
PR (#27) is converged/handed off, and its wording ("sweep the file/repo") is
adequate; reopening it for a wording echo would restart its review loop.

## Verification

Markdownlint + prettier --check clean; bullet diffs identical across both files.
