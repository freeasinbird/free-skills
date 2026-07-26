# Turning the skill audit's defect classes into a standing check

Issue #79 closed the audit set (#73 to #78) by making three hand-found
defect classes mechanical: a runaway prose paragraph, a `description`
written as a plain scalar, and a script flag no `SKILL.md` mentions. The
issue's comment added a fourth from PR #78's per-section pointers. The
work is `scripts/check-skill-structure.sh`, its matrix, and one
done-checks entry; the measurements below reshaped it on the way.

## Decisions

- **Chose a 15-line paragraph ceiling with the offenders fixed first, over
  a ceiling today's tree already passes.** Measurement drove this: at the
  planning cut, `skills/` still held paragraphs of 29, 23, 20, 19, 19, 19,
  18, 18, and 16 lines, so any "passes as-is" ceiling would have been 30,
  which catches only the extreme case (the 72-line merge-cleanup paragraph
  the audit found by hand) and nothing plausible. The nine were
  re-presented as bullets first, and 15 is one line above the tallest
  survivor (`agent-setup/references/canonical-sections.md`, 14). The
  ceiling therefore forbids regrowth, not existing prose. Owner's call at
  planning time, after both options were priced.
- **Rejected an exemption list for the long paragraphs.** It would have
  kept the PR to scripts plus AGENTS.md, but an allowlist entry is a
  permanent hole in exactly the files that earned the rule, and the
  follow-up issue that removes it competes with everything else in the
  backlog.
- **Chose to document the twelve undocumented flags rather than exempt
  them.** Reaching green required one or the other: seven `capture.mjs`
  knobs, four `self-merge.sh` overrides, and `watch-review.sh`'s
  deprecated `--reaction-login` alias appeared in no skill markdown. A
  parity check that starts life with its three real subjects exempted
  asserts nothing.
- **Chose an asymmetric flag rule.** Forward, every parsed flag must
  appear in some markdown of the skill; a flag documented only in the
  script's own header is undocumented, since no skill prose points a
  reader there (that is the `--require-all` defect issue #76 fixed by
  hand). Backward, only flags inside a fenced command that names the
  script are checked, because skill prose is full of `gh` and `git` flags
  that the skill's own script has no business parsing. A symmetric rule
  would have produced dozens of false findings on day one.
- **Chose to match pointers on whitespace-flattened text.** Prose wraps at
  ~76 columns, so a `` `references/x.md` §slug `` pointer routinely splits
  between the file name and the slug (two live examples:
  `merge-cleanup/SKILL.md` and `agent-setup/SKILL.md`). A line-oriented
  match reports the target section as unreferenced, and the obvious
  "fix" for a false unreferenced reading is deleting a section that is in
  use. The wrap has its own matrix case.
- **Chose structural frontmatter rules with an optional YAML parse**, over
  requiring PyYAML. The repo has no Python dependency and no CI; a hard
  requirement would make the check unrunnable where the convention most
  needs enforcing. The structural rules (opening and closing `---`, `name`
  matching the directory, `description` exactly `>-`) carry the contract,
  and where PyYAML happens to be importable the block is parsed too. The
  matrix skips that arm loudly rather than silently.

## Verification

Run against a worktree of `337c589` (the commit before the audit set's
first PR), the check exits 1 with 30 findings: 12 paragraph findings
including merge-cleanup's 72-line block, and 18 flag findings including
agent-setup's `--require-all` and every `watch-review.sh` and
`capture.mjs` flag the audit later documented. Against the post-fix tree
it is clean over 18 files. So the check would have caught the defects the
earlier issues fixed by hand.

## Review round 1 (Codex, PR #92)

All four findings confirmed and fixed; none rejected.

- **P1, clean without validating YAML.** Right: with PyYAML absent (the
  verification environment, and any bare `python3`), an unindented body line
  after `description: >-` passed. Requiring a parser was rejected, since it
  would make the check unrunnable exactly where the convention most needs
  enforcing; instead the structural fallback now carries the contract, so a
  frontmatter line must be a top-level key, an indented continuation, or
  blank, tab indentation is a finding, and so is a duplicate key.
- **P2, `cd` before resolving the positional root.** Right, and worse than
  it looks: `check-skill-structure.sh skills` from another worktree checked
  _this_ repository and reported it clean, so a broken tree would have
  looked validated. An explicit root is now absolutized before any `cd`.
  Swept the class: `check-prose-tics.sh` had the same shape (cd to the
  repository root, then read caller-relative path arguments) and now
  absolutizes its arguments first. `check-managed-sync.sh` takes no path
  argument and `compare-managed-blocks.sh` never cds, so neither is
  affected.
- **P2, option values read as flags.** Right:
  `capture.mjs --chrome-flag --no-sandbox` would have reported the
  passthrough value as an invented flag, forbidding documentation of a
  supported invocation. The token after a recognized flag is now its value
  (unless the flag carried `=value`). **Accepted tradeoff**: an invented
  flag written directly after another flag goes unreported. A false positive
  blocks documenting real usage while a false negative just misses one
  placement, so the check errs toward the cheaper failure.
- **P2, headings inside fences counted as targets.** Right: a `## §slug`
  shown in a markdown example resolved a pointer that leads nowhere in the
  rendered document. Heading collection now reads through the same fence map
  the pointer side already used, in both directions.

## Review round 2 (Codex, PR #92)

One P1, and a recurrence of round 1's class from an incomplete fix rather
than a new defect: round 1 fixed the cited shape (an unindented block-scalar
body) instead of the class (malformed YAML the structural rules do not
model), so `extra: [` still exited 0. Confirmed by re-running it.

- **Widened the rule to a validatable subset.** The parser-free path now
  accepts only what it can actually judge: top-level keys whose values are a
  block-scalar header, a closed quoted scalar, a plain scalar, or empty;
  block-scalar bodies; comments; blanks. Anything else (a flow collection, an
  anchor, a nested mapping) is reported as unvalidatable with the remedy in
  the message, rather than passed. Where PyYAML is importable the parser
  judges those constructs instead, so the divergence is explicit and only
  ever errs toward reporting.
- **Rejected requiring PyYAML** a second time, on the same grounds: this repo
  has no Python dependency and no CI, so a mandatory check that cannot run on
  a stock `python3` moves the failure from "reported" to "never run".
- **Swept the input space as tests** rather than patching the cited value,
  since serial widening is what cost the extra round: unclosed flow sequence,
  colon-then-space plain scalar, unterminated quote, comment lines, quoted
  values, empty values, non-`>-` block scalars, valid-but-unmodelled flow
  sequences and anchors, and a nested mapping. The last three key off whether
  PyYAML is present, and the matrix was run both ways (52 cases without it,
  53 with).

## Review round 3 (Codex, PR #92)

Three findings, all confirmed and fixed.

- **P1, invalid double-quoted escapes accepted** (`owner: "\q"`). The third
  instance of the parser-free certification class, so the subset moved again
  rather than gaining an escape table: a double-quoted value containing any
  backslash is now outside it. Single quotes stay in, since their only escape
  is a doubled quote, which the pattern models exactly.
- **P2, reverse parity fired on a command that merely names the script**
  (`cp demo.sh /tmp --preserve`). A logical command is now split on shell
  operators, and a segment counts only when the script is its command word,
  after environment assignments and launchers (`node`, `bash`, and the rest).
- **P2, indented prose escaped the ceiling.** Any leading whitespace was a
  paragraph break, so a 16-line paragraph indented two spaces passed.
  Markdown renders one to three spaces as prose, so only a list body and a
  four-space indented code block are exempt now.

The paragraph rewrite then flagged `self-merge/references/cleanup-sequence.md`,
which turned out to be the rule's own bug rather than a defect in the prose: a
bullet holding a wrapped `gh api` command at column 0 is a **lazy
continuation**, which markdown keeps inside the list item, while the first
implementation read it as the list ending. A list block now ends only at a
blank line followed by an unindented non-item, and that shape is a matrix
case, taken from the real file.

## Review round 4 (Codex, PR #92)

Two findings, both confirmed and fixed, and both the same shape: a pattern
written loosely enough to exempt what it should judge.

- **P1, block-scalar headers.** `>10` and `>0` passed, though YAML's
  indentation indicator is a single digit 1 to 9, optionally combined with a
  chomping indicator in either order. The header pattern now spells that out,
  so an out-of-range indicator falls outside the subset and is reported.
- **P2, `#hashtag` read as a heading.** Markdown needs a space or the line's
  end after one to six hashes, so a paragraph of `#hashtag` lines slipped the
  ceiling entirely. Swept the sibling markers in the same pass rather than
  waiting for the next round to name them: `<` now needs a tag-shaped opener
  (`<3` is prose), while `>`, `|`, the thematic break, and the list markers
  were already written as markdown recognizes them. Both directions are
  matrix cases: three lookalikes that must count, four real markers that must
  not.

## Review round 5 (Codex, PR #92)

Four findings, all confirmed and fixed.

- **P1, block-scalar body indentation.** The first content line now fixes the
  block's indentation and a later line indented less (but not back to the
  mapping) is reported, since no parser accepts that dedent.
- **P2, `name: 'demo'` compared as source text.** The quotes made valid
  frontmatter fail, in both environments, because a structural finding
  suppresses the parse. Quoted forms are decoded before the comparison.
- **P2, an indented fence marker read as a fence opener.** At four spaces or
  more it is an indented code line, so treating it as an opener blanked the
  rest of the file and hid real headings from the reverse pointer check. Now
  gated on indentation, with a list-aware exception, since a fence inside a
  list item is legitimately indented (three live examples in this repo).
- **P2, a leading pipe treated as a table.** A table needs a header row and a
  delimiter row; without them, `| ordinary prose` repeated is a paragraph.
  Table rows are detected as blocks now.

**Stopping rule for this class**, since four of the five P1s have been the
parser-free path certifying YAML it could not judge, each fix narrower than
the class: if a sixth lands there, the design flips to requiring PyYAML and
the subset goes away. That trades a check that runs everywhere for one that
cannot be wrong, and the trade is only worth making once the evidence says
the subset cannot be finished. Recorded here rather than acted on, because
each round's fix has been small, testable, and has left the subset smaller
and more explicit rather than more elaborate. (Round 6 met the condition.)

## Review round 6 (Codex, PR #92): the stopping rule fires

Two findings, both confirmed.

- **P1, a body contradicting an explicit indentation indicator** (`notes: >3`
  over a two-space body). The sixth construct outside the validatable subset,
  and the one that ends the design: `block_indent` came from the first body
  line and never read the header's indicator, and there is no reason to
  believe the seventh construct would be the last either.
- **P2, an inline comment after `name`** (`name: demo # the directory name`)
  compared as source text. The parser-based rewrite fixes it for free, since
  the comparison now reads the loaded value.

**Decision: require PyYAML.** `check-skill-structure.sh` now exits 2 with an
install instruction when the parser is absent, `safe_load` decides whether
frontmatter is valid, and the check keeps only the two rules a parser cannot
answer: `name` matching the directory, and `description` written as a `>-`
block scalar (read from the source, since a loaded value cannot say how it
was written). Roughly 90 lines of subset machinery are gone, and with them a
whole class of false certification.

The cost, stated plainly: a mandatory done-check now has a dependency the
repository did not previously have, and a stock `python3` cannot run it until
`pip install pyyaml`. That is why this was deferred through five rounds
rather than taken at the first P1, and why the requirement is spelled out in
the done-checks entry rather than left to a runtime surprise. **This is an
owner-facing change**: it is on an open PR precisely so it can be vetoed.
The alternative, if the dependency is unwanted, is to drop the "frontmatter
parses as YAML" claim entirely and check only `name` and `description` from
the source; that is a smaller check, and it would fail this issue's stated
acceptance criteria.

**Revisit when**: the repository grows a CI environment or an installer step,
which would make the dependency invisible in practice; or if the dependency
is rejected, the frontmatter rule narrows to the two convention checks and
the issue's acceptance criteria are amended to match.

## Review rounds 6 and 7 (Codex, PR #92): the paged-read miss

Five findings from these rounds were missed on the first read, and the cause
is worth recording because this repository ships a skill about it.
`gh api repos/.../pulls/N/comments` returns one page of 30, and the review
threads on this PR had grown past that, so a filtered read of page one showed
"no new comments" while five were waiting. The watcher had reported
`new_review_comments:3` from its own paged scan; the manual read was trusted
over the instrument, and the instrument was right. `await-pr-review`'s
`references/detection.md` states this exact rule ("a single page is a window,
not the collection"), and it applies to reading a review, not only to
detecting one. Every `gh api` list read here now uses `--paginate`.

The findings themselves, all confirmed and fixed:

- **P1, duplicate keys with a spaced separator.** `name : wrong` then
  `name: demo` loads as one key, last value winning, while a tight-colon scan
  saw two unrelated lines. The key pattern now allows whitespace before the
  colon.
- **P2, over-indented fence closers.** A delimiter four spaces past the
  opener is fenced content, so closing on it exposed sample markdown, and a
  pointer at a sample heading resolved to a section nobody can read.
- **P2, launcher options attributed to the script.** `node --no-warnings
capture.mjs --url http://x` reported `--no-warnings` as an invented
  `capture.mjs` flag. Invocation detection already skipped launcher options;
  reverse parity now reads only the tokens after the script's own token.
- **P2, list state surviving an unindented block marker.** `- item` then
  `# Heading` left the list open, so a following four-space fence was read as
  a list fence rather than indented code. An unindented block marker now ends
  the list even with no blank line before it.
- **P2, an inline comment after the description header.**
  `description: >- # folded and stripped` is the same block scalar to a
  loader; the source comparison now strips a trailing comment.

## Review round 8 (Codex, PR #92)

Four findings, no P1, all confirmed and fixed. One of them is the reason this
section exists:

- **P2, the paragraph scanner kept its own list state.** Round 7 fixed the
  block-marker reset in `fence_map()` and not in `check_paragraphs()`, which
  ran a second copy of the same rule; the two drifted immediately. The copies
  are gone: `fence_map()` returns the list state it already has to compute,
  and the paragraph scanner consumes it. Fixing one site of a duplicated rule
  is the failure mode this whole review has repeated, and deduplicating is
  the only fix that holds.
- **P2, a closer with trailing content.** A fenced delimiter followed by text
  is content, not a closing fence.
- **P2, flattening across a paragraph boundary.** A file name ending one
  paragraph could pair with a slug in the next, marking an orphaned section
  as used. Blank lines now survive the flattening as newlines.
- **P2, a quoted `description` key.** `'description': >-` loads normally, but
  the source-style lookup needs the key to compare the block-scalar header.

## Review round 9 (Codex, PR #92)

Four findings, no P1, all confirmed and fixed. Two would have rejected valid
documentation (a GFM table written without outer pipes, read as a 16-line
paragraph; a paragraph opening with `<span>`, exempted because it looked
tag-shaped), and two were spec exactness on fences (a closing fence's
three-space limit is absolute outside a list container, not relative to the
opener; a backtick anywhere in a backtick fence's info string means no fence
opens at all).

**Second stopping rule, for the markdown-modelling class.** Rounds 3, 4, 5,
7, 8 and 9 have all turned on regexes approximating what markdown actually
renders, exactly as rounds 1 to 6 turned on regexes approximating YAML. The
YAML class ended by handing the question to a parser. If this class produces
findings in two more rounds, the same move applies: the repository already
runs Node for prettier and markdownlint, so the paragraph, fence, and table
rules should be derived from a real markdown parse (markdownlint's own token
stream, or remark) rather than from patterns. It is recorded rather than
taken now because each of these fixes is small, spec-cited, and covered by a
case, and because the dependency question deserves the owner's answer once,
not twice in one PR.

## Review round 10 (Codex, PR #92)

Three findings, no P1, all confirmed and fixed, all container modelling:

- **P2, indented lines after a paragraph.** Indentation cannot interrupt a
  paragraph in progress, so four spaces under an open paragraph is a lazy
  continuation, not a code block. Fixing that surfaced a collision with the
  list rule (an unindented lazy continuation inside a bullet started a
  paragraph that then swallowed the bullet's indented body, which the check
  caught on the real tree at `cleanup-sequence.md:44` again). Inside a list
  item everything is now the item's own content, indented or not.
- **P2, block quotes.** A quote container does not stop its contents from
  being a paragraph. Quote markers are stripped before every paragraph-side
  map, so a quoted fence or table behaves like an unquoted one.
- **P2, HTML block interiors.** Only the opener is tag-shaped, so the
  interior counted as prose and a block of documentation markup would have
  been rejected. HTML blocks now run to the next blank line (a comment to its
  `-->`), per CommonMark.

Rounds in the markdown-modelling class: 3, 4, 5, 7, 8, 9, 10. The stopping
rule recorded in round 9 gives it one more before the paragraph, fence, and
table rules move to a real markdown parse.

## Review round 11 (Codex, PR #92): the markdown stopping rule fires

Four findings. Three were the markdown-modelling class again (an HTML block
with a tag terminator such as `</script>` ends there, not at the next blank
line; a setext underline is a heading, not prose joined to what follows; a
block boundary need not be blank, so a heading can end one), which is the
second round after the rule was recorded, and two of them said "or derive
paragraph spans from a Markdown parse" in as many words.

**Decision: derive the markdown structure from a parse.** `markdown-it-py`
joins PyYAML as a required dependency, and the paragraph, fence, table, HTML,
quote, and list rules are gone: one `blocks()` call returns the code and
raw-HTML spans, the paragraph spans the ceiling applies to (every paragraph
not inside a list item, since the issue exempts list bodies), and the block
boundaries that stop pointer flattening. Eleven rounds of patterns collapse
into about seventy lines that are correct by construction.

The fourth finding was not markdown at all: a `#` comment inside a documented
invocation was read as arguments. Commands are now tokenized with `shlex`
(comments and quoting handled), which is stdlib, not a new dependency.

Two bugs surfaced while wiring it, both caught by the corpus and the matrix
rather than by review, which is the point of having them: the boundary branch
first skipped the line it was meant to break before (dropping its pointers),
and then failed to break at all when the previous line's newline had already
collapsed to a space.

**Both stopping rules have now fired**, and the shape was the same each time:
a rule that models a format with patterns accumulates review rounds until the
format's own parser answers it. What remains hand-written is what no parser
knows: the ceiling, the flag-parity contract, and the pointer convention.

## Review round 12 (Codex, PR #92)

Four findings, no P1, all confirmed and fixed, all in the two rules that are
still hand-written because no parser knows them:

- **P2, `&` missing from the shell operator split**, so a backgrounded
  command absorbed the next command's flags.
- **P2, launcher options with separate values** (`env -u OLD ./demo.sh`) hid
  the script, because the scan skipped the option token and then read its
  value as the command word. Option arity is unknowable from here, so past a
  launcher the script is simply the next token bearing its name; a
  non-launcher command word still means the script is only being named, not
  run (`cp demo.sh /tmp`).
- **P2, indented code blocks collected as invocations.** The reverse-parity
  contract is about fenced commands; an indented block is prose formatting,
  and failing valid documentation over one is the wrong direction. Both kinds
  still count as code for the paragraph and pointer rules.
- **P2, indented reference headings.** Markdown allows a heading up to three
  spaces of indentation. Heading detection moved onto the parse, which also
  drops the last hand-written markdown pattern from the pointer rule.

## Review round 13 (Codex, PR #92)

Two findings, both confirmed and fixed, both regressions introduced by the
previous round's own fixes:

- **P2, the level-two constraint lost.** Moving heading detection onto parser
  tokens inspected every `heading_open` without checking its tag, so `#` and
  `###` sections resolved pointers the `## §slug` contract does not define.
- **P2, splitting before lexing.** The operator split ran on raw text, so a
  quoted `"a|b"` cut the command in two and the parity check saw a script
  with no flags and flags with no script. Lexing now comes first
  (`shlex.shlex` with `punctuation_chars`), and segments are split on the
  operator tokens it emits, which also handles an operator written without
  surrounding spaces.

Worth noting for the record: both were introduced by fixes from the round
before, which is what the matrix is for. Neither survived a single round.

## Review round 14 (Codex, PR #92)

Three findings, all confirmed and fixed. Two share a principle worth stating
once: **hidden text cannot satisfy a visible contract.** A flag mentioned
only inside `<!-- ... -->` is undocumented, and a pointer hidden there keeps
no section alive, because in both cases the reader the convention exists for
never sees it. Comment spans are now blanked (not deleted, so line numbers
hold) before either rule reads the text, and inline comments are handled
separately from raw HTML blocks, since markdown parses a comment after prose
as part of the paragraph.

The third was the round-13 ordering bug in its last hiding place: line
continuations were joined on the raw text, so a backslash inside a `#`
comment swallowed the command on the next line. Comments are stripped from
each line before continuations are joined.

## Revisit when

A skill grows a script whose flags are not parsed by a `case` arm (`.sh`)
or an option map or `===` comparison (`.mjs`). Both extractors are
deliberately narrow, and a third parsing idiom will read as "this script
parses no flags", which fails open and silently. Also when a fenced example
needs to pass an invented flag directly after a valid one: that is the
reverse direction's accepted blind spot, and closing it means classifying
each flag as valued or boolean from the script's source.
