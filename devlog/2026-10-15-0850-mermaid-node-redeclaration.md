# Mermaid Node Redeclaration

Chose a small stream tokenizer over a per-line regex to count how often a
tracker chart declares each node ID, so `tracker-refresh.sh` exits 4 when a
unit's ID is declared again inline on an edge. Issue #301 carries the
contract; it follows a Codex finding on PR #299, whose decisions are in
[the tracker refresh note](2026-10-14-1502-tracker-refresh-command.md).

## Decisions

- **Tokenize the chart as one stream, not line by line.** A regex count of
  `<ID>` before a shape character on each line was tried and refuted before
  PR #299 merged. It stopped on `%%` comments, on longer IDs such as
  `lane-i10`, and on edge text and keyword statements. It also missed a
  redeclaration after a multi-line Markdown-string label, since it read
  quotes one line at a time.
- **Recognize only what tells a mention from a declaration.** A declaration
  is an ID followed at once by `[`, `(`, `{`, `>`, or `@{`. The scan skips
  front matter, strings across lines, `%%` comments, keyword statements
  (`subgraph`, `class`, `accTitle`, `accDescr {...}`, and the like), edge
  text in `-- text -->` and `|text|` forms, and shape bodies. It isn't a
  Mermaid parser.
- **Pass over unknown syntax rather than stop.** The contract states this
  as a planning assumption the owner may veto; the owner assigned the work
  without vetoing it. A miss only misplaces a chart marker while the
  **Startable now** bullet stays right; a false stop blocks a merge-time
  refresh. The Dependencies grammar fails closed for the opposite reason: a
  miss there can start a unit too early.
- **Take Mermaid's ID boundary, not the script's `[A-Za-z0-9_-]`.** An ID runs
  to whitespace, a quote, `;`, one of `()<=>@[]^{|}~`, or an arrow. Measured
  against Mermaid 11.4.1: `a.i11`, `a&i11`, `a:i11`, and `aéi11` are each
  one node, while `i10 & i11` with spaces is two. Defining the ID by its
  delimiters keeps non-ASCII IDs whole in both byte-mode and UTF-8 `awk`.
- **Leave the unit-to-node mapping alone.** The standalone `id["#N ..."]`
  line stays the only form the rewrite reads, so a unit drawn only inline
  still exits 2.

## Refute-First Findings

The parser trusts issue text that `gh` returns, so the change ran the
refute-first pass: an independent reviewer, real Mermaid as an oracle, and
mutation checks.

- **Confirmed, fixed: IDs narrower than Mermaid's.** The reviewer found that
  `old.i11["..."]` beside `i11["#11 ..."]` stopped the run, though Mermaid
  draws two nodes. The ID boundary decision above fixes it.
- **Confirmed, fixed: front matter scanned as chart text.** A `---` block
  with `title: Reader i11(x)` stopped the run; Mermaid strips front matter
  first. The scan now skips a leading `---` block.
- **Disproved: `--old i11(r)-->` hides `i11`.** Mermaid lexes `--o` as an
  arrow too, so `i11(r)` is a real declaration there.
- **Disproved: a lone `"` in edge text swallows later lines.** Mermaid opens
  a string at `"` in every lexer state, so it swallows the same text.
- **Allowed by decision: a space between ID and shape.** `i11 ["x"]` is a
  Mermaid parse error, so the scan needn't count it.
- **Checked: every test chart is valid Mermaid.** Mermaid 11.4.1 parsed all
  19 new charts. It gave `i11` the later label in each stop case and kept
  `#11`'s label in each pass case. Brackets in unquoted pipe text or
  subgraph titles fail to parse, so those cases use `>` or quotes instead.
- **Checked: every rule is covered.** Removing any single rule makes at
  least one matrix case fail.
- **Checked: live trackers don't newly stop.** Freeside #2021 and #1616
  refresh unchanged. Across 27 charts in 17 Freeside issues, the one
  redeclaration found is real: #835 draws `844[["#844"]]` twice. #835
  predates the shared format, so the command already exits 2 on it.

Revisit when the tracker format allows chart forms the scan passes over,
such as `@{ label: ... }` nodes for units, or when a refresh stops on a
chart that Mermaid draws with one node per ID.
