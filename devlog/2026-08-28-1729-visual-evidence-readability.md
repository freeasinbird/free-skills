# Visual-evidence readability split

Issue #167 rewrites the visual-evidence skill without changing its behavior.
This note is mandatory because the skill carries a credential-leak check.

## Decisions

- Move crop-tool fallbacks, display layout, and worked examples to
  `references/capture-craft.md`. These details support the procedure but do
  not need to interrupt it.
- Keep the `capture.mjs` option table in `SKILL.md`. It is already skimmable,
  and it keeps every script flag visible beside the invocation.
- Keep the complete secret review in `SKILL.md`. Its four checklist items and
  stop directive remain byte-identical to the prior version.
- Keep the review ahead of every upload path. The opening procedure puts review
  before upload. Steps 5 and 6 point to the in-file checklist. The CLI gate
  appears before the runnable `npx` command.

## Refute-first findings

- **Disproved by exact comparison:** The rewrite did not weaken the four secret
  checks or the stop directive. Their bytes match `origin/main`.
- **Disproved by path review:** An agent that reads only Compose and Attach
  still meets an explicit review gate before the upload command. The review is
  that section's first bullet.
- **Disproved by path review:** An agent that stops after step 6 still sees the
  review requirement. Steps 5 and 6 both point to Compose and Attach.
- **Disproved by survival check:** Three old sentences fell below the
  55 percent word-survival signal. Manual checks found their rules in the new
  UI-review, restricted-sandbox, and reported-filename text.
- **Deferred to independent review:** Session policy did not permit a fresh
  delegate. The repository's automated reviewer will test the same upload-path
  claim after the PR opens.

Revisit when gh-imgup's review text changes or a later unit changes the
reference convention.
