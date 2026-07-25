# One canonical secret review in visual-evidence

`visual-evidence` carried the mandatory pre-upload secret review twice with no
statement of which governs (issue #75, item 2): the step 5 hygiene bullet said
to defer to gh-imgup and not restate a weaker version, while _Compose &
attach_ restated the checklist and said to apply it. This note covers a
credential-leak surface, which the project's mandatory-note list includes.

## Decision

- Keep the _Compose & attach_ copy as the checklist to apply, and reduce the
  step 5 bullet to a pointer at it. Rejected: honoring step 5's prohibition by
  deleting the _Compose & attach_ checklist. That is the only copy that
  survives when neither the gh-imgup skill nor its `--help` is loaded, so
  deleting it leaves the fallback path with no review at all.
- Raise that copy to gh-imgup's own bar rather than leaving a second, softer
  standard in the tree. The bar is unchanged; the restatement now matches it.
- Ownership of the step stays with gh-imgup. This is a documentation
  consolidation, not a move of work across the skill seam.

## Refute-first verification

A fresh-context reviewer was pointed at the change with the job of disproving
"the full review still happens, on every path, no weaker than before". It broke
the first draft on three counts, all fixed before commit:

- **Confirmed, fixed.** The draft declared the local copy governing while it
  was materially weaker than gh-imgup's: it omitted session cookies, `.env`
  contents, private URLs, and terminal/editor/devtools content, and had no
  stop-and-tell-the-user directive. The local copy now carries both.
- **Confirmed, fixed.** The draft claimed the CLI's `--help` review section was
  a condensed form of the local checklist. The direction was inverted: `--help`
  was the superset. Both are now the same review, and the text says so.
- **Confirmed, fixed.** The draft opened _Compose & attach_ with a runnable
  `npx` invocation using the exact filenames the skill produces, with no review
  mention until three paragraphs later, so an agent arriving directly at that
  section could upload before reading the gate. The review is now the first
  bullet, and the invocation is preceded by an explicit before-you-run gate.
- **Rejected by verification.** An agent that stops after step 6 loses nothing:
  steps 5 and 6 both still warn, and now name an in-file location instead of a
  skill that may not be loaded. Cross-references resolve verbatim, and the
  published CLI contract now documented in the skill (positional files,
  upload-only by omitting `--pr`/`--issue`, Markdown lines on stdout, progress
  on stderr, `--repo` inferred from the origin remote, Node 22+) matches
  `@freeasinbird/gh-imgup` at v0.1.3.
- **Accepted by decision.** Dropping the `--max-size` "(default 25 MB)"
  parenthetical loses an accurate detail, per the issue: this skill cannot
  guarantee another package's version-specific default.

Revisit when gh-imgup's own review text changes, since the copy here is a
deliberate duplicate held at the same bar and will not notice the drift on its
own.
