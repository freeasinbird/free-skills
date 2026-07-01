# Add the prompt-crafter skill

Adds `skills/prompt-crafter/`: authoring, cross-cutting editing, and
review/audit of reusable agent prompt payloads (CLAUDE.md / AGENTS.md
content, pasteable chat instructions) for Claude and ChatGPT/Codex.
Transcribed, with adaptations, from the user's design spec
(`prompt-craft-skill-spec.md`, outside this repo), itself distilled from a
prompt-adherence audit in the free-prompts repo (its devlog,
2026-07-01-1505).

## Decisions

- Worth adding: platform-agnostic by design, no in-repo overlap
  (agent-setup owns scaffolding and managed sections, not free-form payload
  content), and every taxonomy class carries a live example rather than
  speculation. Devlog grep found no prior decision in this space.
- Named `prompt-crafter`, user-chosen from candidates they proposed;
  agent-noun form parallels license-philosopher. Rejected: `prompt-craft`
  (the spec's draft), `prompt-creator` (undersells the review half),
  `prompt-shaper` (weak trigger vocabulary).
- The spec's "spawn a reviewer" step is gated on delegation support with a
  stated fallback (external bot or human, or ask), per architecture
  invariant 2; the spec as written would have violated it.
- Tilt-table vendor claims verified against primary docs before shipping;
  the reference carries source links and a last-verified date
  (2026-07-01), and instructs re-verification when a model generation
  ships.
- Live audit examples kept but made self-contained: wording quoted, no
  paths into free-prompts.
- Carried over the spec's deferral: no inert-instruction linter yet; two
  data points is not a lint rule.
- Ran skill-creator's description-trigger evals (20 queries, 60/40
  train/test split, 3 runs per query, 5 optimizer iterations): the
  shipped description won on held-out test; four rewritten candidates,
  including deliberately pushier ones, didn't beat it, and no candidate
  ever fired on the near-miss negatives (precision 100% throughout).
  Absolute recall was low for every candidate alike, which reads as
  harness undertriggering rather than description signal, so the
  description ships unchanged; don't re-run the loop without a better
  harness.

## Review rounds

- Codex round 1 (P2, confirmed): the core-parity snippet treated an empty
  extraction as a pass, so a payload missing its shared-core markers,
  first in glob order, silently became a non-baseline. Fixed by failing
  on empty extraction, which also makes the empty-`ref` sentinel sound.
- Codex round 2 (two P2s, confirmed): the battery's snippets printed
  failures but their exit status didn't carry the verdict; the parity
  drift path exited 0, and `grep -c` exits 1 precisely when the payload
  is clean. Fixed as a class across the whole battery: every snippet's
  exit status is now its verdict, including the budget check (bare
  `wc -m`, uncited by the review but in the class, now an explicit
  comparison against the cap).
- Codex round 3 (P2, confirmed, self-inflicted): the round-2 fold
  dropped every verification.md fix; the rebuild committed after
  `git reset --soft` without re-staging the working tree, so the push
  re-shipped the old file while the threads claimed fixes by SHA. The
  round-2 verification gap: snippets were fixture-tested and the
  working tree linted, but the pushed commit's content was never read
  back. Fixed by folding the actual edits and verifying the fix lines
  in `origin/<branch>`'s file, which is now the standing check for any
  fold.

## Deferred

- Inert-instruction linter (grep payloads for slash commands and
  config-only vocabulary): deferred until the pattern list stabilizes, per
  the spec's own evolution notes.
