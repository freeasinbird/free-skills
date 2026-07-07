# Title-only merge commits: PR bodies stay out of history

Ben flagged that merge commits carry too much ceremony, especially
screenshot references: straylight's PR 59 merge commit embedded six
image URLs with captions, because the intended repo setup folded the
full PR body (Why/What/Screenshots/Review Notes/Verification) into the
merge commit message. His verdict: "that makes git history impossible
to use."

## Decisions

- **Title-only merge messages (Ben's pick from three options).** The
  merge commit is the PR title plus number, nothing else; the PR body
  stays the rich review packet, unchanged, and simply never enters
  history. Rejected: restructuring the PR body down to Why/What and
  moving screenshots/verification to a PR comment (keeps a narrative
  in `--first-parent` at the cost of demoting review material; Ben
  wants the body as it is); curating the message by hand in the merge
  dialog (per-merge burden, one forgotten edit re-embeds image URLs).
- **The Why/What narrative now lives only on the forge and in the
  devlog.** `git log --first-parent` reads as the list of PR titles;
  the title-writing rule is unchanged. The keep-body-current rule's
  rationale shifts from "the body becomes the merge commit" to "the
  body is the work unit's durable record on the forge".
- **The repo-settings audit now prescribes `merge_commit_message=BLANK`**
  (was `PR_BODY`), and the settings enumeration in the pull-requests
  section gains title-only merge messages, with the manual fallback
  (keep the message to the PR title when the setting is absent).

## Applied live

- Repo settings flipped to `merge_commit_title=PR_TITLE`,
  `merge_commit_message=BLANK` on freeasinbird/free-skills and
  straylight-ai/straylight (this PR itself should merge title-only).
- straylight's AGENTS.md managed block gets the matching text in its
  own PR, so the next agent-setup sync is a no-op there.

## Automated review (round 1, three P2s, folded in)

- **Prettier, confirmed and fixed:** the first cut's settings-table row
  broke `npx prettier --check '**/*.md'`; ran `--write` on the changed
  files.
- **Manual merges inherit forge defaults, confirmed and fixed:** the
  merge recipes (`gh pr merge <n> --merge` in the pull-requests
  canonical section and the self-merge skill) now say to pass
  `--subject '<PR title> (#<n>)' --body ''` when the repo's title-only
  settings aren't confirmed set, instead of inheriting whatever the
  forge default writes.
- **"Plus its number" claim, declined with evidence:** Codex read the
  GitHub docs' "just the pull request title" as omitting `#N`, but two
  straylight merges performed under `merge_commit_title=PR_TITLE`
  (f46cbf4, 123415c) both carry the `(#N)` suffix in the subject and an
  empty body; the doc sentence it cites describes the squash title
  form. The canonical text's "plus its number" matches observed
  behavior.

## Verification

- Passed: `./scripts/check-managed-sync.sh` (all sections ok),
  `./scripts/check-prose-tics.sh` (clean; the first draft's em dashes
  were caught and rewritten).
- Checked: repo-wide grep for `PR_BODY`, "title and body", "body
  become" finds no remaining instance outside stale worktree copies
  and frozen devlog entries.
