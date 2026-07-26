# A conservative structure check for skills

Issue #79 closes the skill audit (#73 to #78) by making its hand-found defect
classes mechanical: a runaway prose paragraph, a `description` written as a
plain scalar, a script flag no `SKILL.md` mentions, and (from the issue's
comment) a `references/<file>.md` §slug pointer that resolves to nothing.

## Decisions

- **Chose a 15-line paragraph ceiling with the offenders re-presented
  first.** At the planning cut `skills/` held paragraphs of 29, 23, 20, 19,
  19, 19, 18, 18 and 16 lines, so any "passes as-is" ceiling would have been
  30, which catches only the extreme case. The nine were re-presented as
  bullets, and 15 is one line above the tallest survivor
  (`agent-setup/references/canonical-sections.md`, 14 lines). The ceiling
  forbids regrowth rather than re-flagging accepted prose. Owner's call at
  planning time, after both options were priced.
- **Chose to document the twelve undocumented flags rather than exempt
  them.** Seven `capture.mjs` knobs, four `self-merge.sh` overrides, and
  `watch-review.sh`'s deprecated `--reaction-login` appeared in no skill
  markdown. A parity check that starts life with its three real subjects
  exempted asserts nothing.
- **Chose stdlib only, and rules biased toward missing a defect rather than
  inventing one.** A false finding blocks valid work and costs whoever hits
  it a debugging pass; a missed one costs a review comment. So the paragraph
  rule measures only unambiguous column-zero prose and abandons any run it
  cannot read confidently, and the frontmatter rule checks what the
  convention says (`---` fences, `name` matching the directory, a `>-`
  header) rather than deciding whether arbitrary YAML loads.
- **Chose an asymmetric flag rule.** Forward, every parsed flag must appear
  in some markdown of the skill, since a flag documented only in the script's
  own header is one no skill prose points a reader to. Backward, only flags
  inside a fenced command whose command word is the script are checked,
  because skill prose is full of `gh` and `git` flags the skill's own script
  has no business parsing.
- **Chose to match pointers on whitespace-flattened text**, since prose wraps
  at ~76 columns and a pointer routinely splits between the file name and the
  slug; a line-oriented match calls the target unreferenced, and the obvious
  "fix" for that reading is deleting a live section. Flattening stops at
  blank lines and headings, so wrapped lines join while separate blocks do
  not.

## Rejected

- **Parser-backed exactness.** The first implementation (PR #92, closed) used
  PyYAML and markdown-it-py so every rule matched CommonMark and YAML
  exactly. Fourteen automated review rounds produced 45 findings, nearly all
  against the machinery modelling those two formats, and the measurement that
  ended it: **all twelve paragraph defects in the pre-audit tree were plain
  column-zero prose.** Every exotic construct that work modelled (setext
  headings, `<script>` terminators, tables without outer pipes, lazy
  continuations, fence info strings) had zero instances in the real defect
  population. Exactness was buying coverage of defects that do not occur, at
  the price of two dependencies in front of a mandatory check. Both versions
  find exactly the same 30 defects on that tree.
- **An exemption list for the long paragraphs**, and **requiring PyYAML**: an
  allowlist is a permanent hole in the files that earned the rule, and a
  mandatory check that cannot run on a stock `python3` moves the failure from
  reported to never run.
- **Flag arity**, after eight review rounds on this PR of which six touched
  it. Telling a boolean flag from a value-taking one meant reading shell arms,
  multiline arms, `shift`, comments, single-quoted literals, and JavaScript
  branch bodies, and each answer needed more of the language than a text scan
  holds. Every recognized flag now consumes the token after it, which is what
  a passthrough option needs and what no semantics are required for. The cost
  is one pinned blind spot: an invented flag written directly after a known
  flag is not reported.
- **String-context tracking in shell and JavaScript**, declined three times
  between them: heredoc bodies (twice) and JavaScript string literals. Each
  would let a script that _prints_ option-parsing text have that text read as
  a parser. Recognizing `<<` and `<<-`, quoted
  delimiters and body ends, or JavaScript's single, double, and template
  strings with their escapes, is language parsing. Two cheap containments
  were taken instead: a case pattern is read only inside a `case`/`esac`
  block, and comments are stripped in both languages. The residue is a script
  that prints option-parsing source in its help text, which nothing here
  does.

## One container rule, added deliberately

The pointer rule tracks whether a list is open, which is the only markdown
container state anywhere in this check. It is there because both directions
risked a false finding: excluding blank-then-indented lines as code erased a
pointer in a loose list's continuation paragraph, while not excluding them let
an indented sample invent a missing reference file. A single boolean settles
it, and it is the ceiling for this kind of state: anything needing nested
containers, lazy continuation, or block quotes inside lists is the parser
question that closed PR #92.

## Pinned under-reports

Each is a passing matrix case, so none can be quietly "fixed" into a false
finding. A missed defect costs a review comment; a false one costs whoever
hits it a debugging pass, so the rules lean this way on purpose.

- A paragraph inside a quote, list, table, HTML block, or indented text is not
  measured.
- An invented flag written directly after a known flag is not reported.
- A launcher option taking a separate value (`env -u NAME ./x.sh`) hides its
  invocation.
- Option-parsing text a script _prints_ rather than executes reads as a
  parser: an option-shaped line in a heredoc inside a `case` block, or a
  JavaScript comparison inside a string literal.

## Verification finding worth keeping

Reverse flag parity was silently inert for the two skills whose documentation
writes `<skill-dir>/watch-review.sh` and `<skill-dir>/self-merge.sh`. The
shell lexer was configured with its default punctuation set, which treats `<`
and `>` as redirection operators, so those commands split into fragments where
the script was never the command word and no invocation was found. The matrix
missed it because every fixture spelled its command `./demo.sh`. Found in
review round 18, while chasing an unrelated basename finding.

A second instance of the same lesson: two fixtures added in later rounds
never landed, because the insertions were anchored on comment text that had
since been reworded and the failure was silent. The matrix stayed green while
missing the cases it was supposed to gain. Fixture edits now assert that the
count changed.

The rule is now exercised against the real files, not only fixtures: injecting
a bogus flag into each of those two invocations produces exactly one finding
per file, and removing it returns the tree to clean. Worth remembering that a
green matrix over synthetic fixtures says nothing about the spellings the
repository actually uses.

## Verification

Run against a worktree of `337c589` (the commit before the audit set's first
PR), the check exits 1 with 30 findings: 12 paragraph, including
merge-cleanup's 72-line block, and 18 flag, including agent-setup's
`--require-all` and every `watch-review.sh` and `capture.mjs` flag the audit
later documented. Clean on the current tree, 62-case matrix green, well under a second.

## Where the review stopped, and why

Twenty-seven automated review rounds produced 63 findings: 59 fixed, 4
declined. The declines are one class (tracking string context in shell
heredocs and JavaScript literals, plus scanning a script language no skill
ships), and they are recorded under Rejected.

The rounds were worth taking for a long time, and stopped being so. The
useful ones found input this repository's own toolchain accepts but the check
rejected: indented frontmatter, tables without outer pipes, `<span>` prose,
mixed-case and underscored options, quoted case labels, loose-list
continuations. Two found silent gaps no fixture covered, both recorded above.
By the last several rounds the findings were constructs that appear in no
skill and would have to be written deliberately: an unterminated HTML comment
inside an indented code sample, a file-descriptor redirection prefixed to a
documented command, a JavaScript comment following an object key with no
space. Each was real, each fix was one or two lines, and several of those
fixes produced the next round's finding.

The reviewer will keep finding constructs of that kind indefinitely, because
the space of legal-but-unused spellings is unbounded while this repository's
corpus is 18 files and 4 scripts. The check has been clean on that corpus and
correct on the pre-audit tree (30 findings, unchanged) throughout. So the
watch stopped here rather than at zero findings, per the convergence rule that
value captured is the bar; a human's merge is the convergence signal, and the
remaining findings are not worth a round each.

## Revisit when

A defect this rule deliberately skips (a paragraph inside a quote, a list, or
an HTML block) actually reaches a merge, which would mean the under-report is
costing more than a parser dependency would. Or when CI arrives: a strict,
parser-backed mode is cheap there, where a dependency is one setup line and a
false finding meets a human rather than blocking an agent mid-task.
