# Read the Landing Record Fail-Closed Inside AGENTS.md

`skills/land-approved-prs/list-ready.sh` and
`skills/land-approved-prs/landed-since.sh` now share
`skills/land-approved-prs/landing-record.sh` to read a repository's landing
record from `AGENTS.md`. The helper verifies the committed blob, skips fenced
code blocks, HTML comments, and closed line-1 front matter, and stops
`bad-record` on any layout it can't classify with certainty. Issue #436 carries
the contract.

## Decisions

- **Chose a fail-closed Markdown reader over moving the record to a plain
  file.** Review of #405 showed that raw-line Markdown scans keep breaking on
  fences, HTML comments, raw HTML blocks, list continuations, and symlinks;
  that unit moved its list to `.worktree-disposables` (see
  `devlog/2026-11-18-2223-worktree-disposables.md`). Moving the landing record
  out of `AGENTS.md` would break existing downstream repositories and the
  frozen scored eval fixtures under `skills/land-approved-prs/evals/`. Keeping
  the record in `AGENTS.md` and failing closed on every ambiguous layout closes
  the misread defect without a cross-repo migration.
- **Chose one sourced helper over duplicate scans.** Both `list-ready.sh` and
  `landed-since.sh` previously ran separate `git show` and `awk` blocks on the
  same record, and `landed-since.sh` executes every backticked command in
  `Base-advance checks`. One helper keeps blob checks, parsing, and tab-safe
  key lookup identical across both callers.
- **Chose `git ls-tree --full-tree` plus `git cat-file blob` over `git show`.**
  `git show <ref>:AGENTS.md` conflated git read errors with a missing file,
  accepted a symlink's target path as file content, and lost NUL bytes under
  command substitution. Checking tree mode (`100644` or `100755` blob),
  extracting the blob to a temp file, and reporting git failures as
  `LOOKUP_FAILED record` separates read errors, missing files, and bad files.
- **Chose bash 3.2 and POSIX/BSD `awk` over `python3` or GNU `awk`.** The
  landing scripts run on macOS (bash 3.2 and BSD `awk`) and Linux CI (bash 5
  and GNU `awk`) without extra runtime dependencies. Keeping the parser free of
  `{m,n}` regex bounds, `gensub`, multi-arg `match`, and bash 4+ syntax keeps
  both platforms identical.

## Refute-First Verification

The landing record gates merge eligibility and shell command execution, so it
sits on a returned-object trust boundary. Before committing, adversarial checks
tested CommonMark fences, HTML comments, raw HTML blocks, front matter, link
reference definitions, list continuations, symlinks, NUL/CR/BOM bytes, and
macOS bash 3.2 plus BSD `awk` compatibility.

- **Confirmed and fixed: pipeline-masked inspection errors.** Under `set -u`
  without `pipefail`, piping `head | od | tr` could mask a failed `head` or
  `od` as an empty BOM or last byte. The helper now checks the BOM with
  `od -An -tx1 -N 3` directly and reuses the scratch temp file for `tail -c 1`
  followed by `od`, checking every exit status without pipelines.
- **Confirmed and fixed: lone trailing CR at EOF.** Per-line `sub(/\r$/, "")`
  in `awk` would treat a file ending in bare `\r` without `\n` as CRLF. The
  helper now rejects any file whose final byte is `0x0d` before invoking `awk`.
- **Confirmed and fixed: dedented lines inside 2–3 space fences or comments.**
  Inside a 2-space list item, a non-blank line indented fewer than 2 spaces
  terminates the list item and its fence or comment in CommonMark, turning a
  later indented triple-backtick closer into a new opener. The parser now stops
  `bad-record` on any dedented non-blank line or 4–6 space matching closer
  inside a 2–3 space fence, and on any dedented non-blank line inside a 2–3
  space multi-line comment.
- **Confirmed and fixed: fence or comment inside a link-reference paragraph.**
  In CommonMark, a multi-line link reference title can contain literal triple
  backticks or `<!--` without opening a fence or comment. Any fence, HTML
  comment, or `Mechanism` bullet that follows a link reference definition
  without an intervening blank line now stops `bad-record`.
- **Confirmed and fixed: greedy key extraction on values holding `**Note:**`.**
  The old `sub(/:\*\*.*$/, "", key)` matched the last `:**` on a line. The
  helper now splits on the first `index(line, ":** ")` after verifying the key
  holds no `*` or `:`.
- **Disproved by check: multi-line backtick spans hiding a line-start comment
  or `Mechanism` bullet.** CommonMark parses block structure before inline code
  spans, so line-start `<!--` and `- **Mechanism:**` interrupt a paragraph
  regardless of an earlier backtick; a mid-line `<!--` inside a multi-line
  backtick span leaves an odd backtick count on that line and stops
  `bad-record`. Verified across 93 adversarial cases under `/bin/bash` (3.2)
  and BSD `awk`.
- **Allowed by explicit decision: strict rejection of raw HTML blocks and
  4+-space fences anywhere in `AGENTS.md`.** Downstream repos using `<details>`
  or 4-space nested code fences outside the landing record stop `bad-record`
  instead of guessing. `free-skills`'s own `AGENTS.md` and canonical templates
  contain none and parse with zero false positives.
- **Allowed by explicit decision: requiring a blank line after the landing
  record.** Issue #436's contract requires stopping `bad-record` on any
  non-blank line directly following the record, while keeping `SKILL.md`
  unchanged as a non-goal (so `SKILL.md`'s older sentence about ending at the
  first line of another shape stays for a follow-up if needed).

## Pre-Push Review

One fresh-context reviewer (Opus 5.5 High) reviewed the change:

- **Fixed (blocking): fences and raw HTML blocks opened after a container
  marker.** Lines such as a bullet-prefixed code fence, `- <script>`,
  `- <div>`, or a blockquote-prefixed code fence bypassed top-level fence and
  raw-HTML checks because the marker preceded them. The parser now peels
  leading blockquote and list markers (after inline-comment stripping) and
  stops `bad-record` on any code fence, raw HTML block, or nested `Mechanism`
  bullet opened there, while tracking container-prefixed link reference
  definitions.
- **Fixed (non-blocking): a second paragraph or loose-list bullet after the
  record's closing blank line.** Previously the first blank line ended the
  record silently, dropping a four-space continuation paragraph in the last
  bullet (such as a second `Base-advance checks` command). The parser now stops
  `bad-record` when the next non-blank line after the record is indented 4+
  spaces, starts with a tab, or opens another two-space list bullet.
- **Declined (non-blocking): relaxing the blank-line end rule or editing
  `SKILL.md`.** Both are fixed by Issue #436's contract (Criterion 2 requires
  failing closed on non-blank lines directly following the record; `SKILL.md`
  is an explicit non-goal).

A second fresh-context pass (Opus 5.5 High) found no blockers and seven
non-blocking issues:

- **Fixed (non-blocking):** widened the post-blank-line sibling bullet guard
  from 2 spaces to 1–3 spaces; scoped multi-line link-label matching so a
  `Mechanism` bullet containing `]:` isn't skipped; rejected blockquoted and
  escaped-colon `Mechanism` bullets; added `source` to the HTML block tag list
  for `cmark-gfm` parity; added `# shellcheck shell=bash` and updated
  `docs/project-checks.md` conditional test triggers.
- **Declined (non-blocking):** moving `--release` before the record read
  (explicit non-goal tracked in #452), dropping line-1 `+++` front matter
  (required by Criterion 2), and allowing bare `-->` in prose (rejecting
  orphan `-->` is required by Criterion 2).

## Revisit

Revisit when a downstream repository needs `<details>` or 4-space nested code
fences in `AGENTS.md`, or when the owner chooses to migrate the landing record
out of `AGENTS.md` across repositories and scored eval fixtures.
