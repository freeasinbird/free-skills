# Gate the length of touched prose

Issue [#190](https://github.com/freeasinbird/free-skills/issues/190) adds a
length gate for prose that a pull request adds or changes. Existing long text
stays grandfathered until a change touches its sentence or paragraph.

## Decisions

- **Gate touched line ranges, not whole files.** A sentence or paragraph is
  touched when its source range intersects an added or modified line. This
  lets a small fix in a legacy file pass without adopting every old sentence.
- **Set ceilings at 40 words per sentence and 120 per paragraph.** The report
  already highlights sentences over 40 words, and the hand-rewritten files
  clear that bar with room. A word ceiling for paragraphs stays independent
  of line wrapping and applies outside `skills/`, unlike the structure check.
- **Keep word volume visible but advisory.** Gate mode prints before, after,
  and signed word counts for each changed file. It never fails on the delta
  because large features can add legitimate prose.
- **Put exception regions in the file.** `<!-- readability: allow -->` starts
  an exempt region. `<!-- readability: end -->` ends it, and an omitted end
  marker carries the exception to end of file. The region is independent of
  Markdown container structure, and both boundaries appear in the reviewed
  diff.
- **Preserve line count while stripping frontmatter.** Blank frontmatter lines
  keep gate messages aligned with the file without changing report metrics.
- **Parse the repository diff once.** One `git diff -U0 -M` supplies changed
  paths, rename pairs, and touched line ranges. A pure rename has no added
  lines, so it reports a zero word delta without gating legacy prose.
- **Use one prose counter.** Report and gate modes share the same sentence
  expression, including punctuation before common Markdown closers. The gate
  does not add abbreviation exceptions or another parsing mode.

## Rejected Alternatives

- **Gate each file's maximum or median:** rejected because unrelated legacy
  prose would fail a focused edit, and a median can improve through choppy
  fragments without improving clarity.
- **Ratchet whole-file metrics:** rejected because one justified long sentence
  could fail in an otherwise clean file.
- **Cap added words:** rejected because volume needs review, not a fixed limit.
- **Use a pull-request label for exceptions:** rejected because a label is not
  part of the reviewed content and can disappear from the historical diff.
- **Parse the next Markdown block after a marker:** rejected because lists,
  tables, blockquotes, and other containers turn the escape hatch into a
  Markdown parser. Explicit regions state the intended review boundary.

## Accepted Gaps

- Pure deletion hunks do not mark the surrounding block as touched, even when
  a deletion joins sentences.
- Untracked files are invisible until added to the index. Use `git add -N` for
  a local check without staging their contents.
- A changed symlink target does not cause tracked Markdown links to that target
  to be checked.
- Periods in abbreviations may split a sentence and make the ceiling lenient.
  This cannot create a false failure.

Do not add parser cases for these gaps without evidence of a real miss in this
repository. Revisit when such a miss occurs, the prose wrapping convention
changes, or repeated exception regions show that the ceilings need revision.
