# Drain the deferred net-new-component assertion gap

Branch `docs/net-new-eval-assertions`, in a dedicated worktree so the
main checkout stays free for other work. Drains the second deferred
item from `2026-07-01-2212-visual-evidence-eval.md`: the
`net-new-component` eval asserted the capture process but not the
content, so a run could pass while capturing a card with the wrong text
or a dark variant that doesn't match the page's card styling. Both
grading runs happened to get those right, so the gap was real but
uncaught.

## Change

- `evals.json` eval 2: two new expectations (required card text:
  heading plus body; after shots for both themes with styling
  consistent with the existing cards for that theme), and the
  existing singular phrasing generalized ("Every image ...", captions
  name state and theme) now that two themed shots are expected.
- `expected_output` tightened from "a dark variant is welcome" to
  expecting both themes: the eval prompt already requires styling the
  card for both modes, and the skill's own guidance says to show both
  palettes when the change affects both, so the soft wording
  under-specified what the prompt demands. Not a contract change,
  an alignment.
- `evals/README.md` eval-2 summary updated to match (the round-2
  review lesson applied: sweep every description of the thing, not
  just the primary file).

## Deferred (carried)

- The new assertions are unexercised until the next suite run; they
  bind that run (same status as the width-parity respec from the eval
  session).
- Upstream skill-creator harness bug report: still needs-human; a
  self-contained draft now exists outside the repo at
  `../skill-creator-trigger-harness-bug-report.md` (written after the
  eval session; inlines the workaround scripts and the evidence
  pointers).

## Verification

- markdownlint-cli2 and prettier --check clean; evals.json validated
  as JSON.
- Not run: the eval suite itself (assertion-definition change only,
  consistent with the "before the next run" deferral it drains).
