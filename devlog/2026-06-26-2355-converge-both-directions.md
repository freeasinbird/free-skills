# AGENTS.md: convergence cuts both ways (don't under-converge)

The await-pr-review dogfood (#27, 9 rounds) exposed an asymmetry in the review
conventions: fix-the-class warns against _over_-chasing ("converge … rather than
chasing every round to zero"), and "Responding to automated review" says
resolving every thread isn't a gate — both push toward "it's OK to stop."
Nothing guarded the opposite failure, which is the one I kept hitting: declaring
"done" while real findings still came, and treating a class that recurred from my
_own_ incomplete sweep as convergence. The user caught it three times.

## Change

New `pull-requests` bullet — **"Don't under-converge either"**: don't declare a
PR addressed while the reviewer is still raising real issues; a finding that
recurs from your own incomplete fix is a miss to sweep, not convergence; agents
lean toward stopping early, so bias toward continuing while findings are
worthwhile, and treat the human's merge as the reliable convergence signal.

Applied to the agent-setup canonical source and free-skills' synced
`managed:pull-requests` block, byte-identical.

## Verification

Markdownlint + prettier --check clean; bullet diffs identical across both files.
