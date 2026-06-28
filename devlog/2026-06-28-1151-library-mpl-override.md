# Licensing philosophy: MPL-2.0 override for static-link libraries

Mirrors the freeasinbird.com about-page change (its PR #14) into this repo's
canonical philosophy + the `license-philosopher` skill. LGPL-3.0 as a flat
library default is unenforceable where static linking or bundling is the norm
(Rust, Go, bundled JS, mobile SDKs) — the relinking obligation can't be
honored, so the copyleft protects nothing there.

## Decision

- **Override, not retreat.** Keep LGPL-3.0 as the library default; override to
  MPL-2.0 only where LGPL is unworkable. MPL is the _weaker_ license
  (file-level copyleft vs LGPL's library-level), so a blanket switch would
  step away from the philosophy. Governing rule, now stated: use the strongest
  weak-copyleft license the target ecosystem can actually honor.
- **Philosophy prose stays general** (no language names) — matches the about
  page. The SKILL is operational, so it _does_ name the ecosystems: it must
  detect them (Cargo.toml, go.mod, bundled JS, mobile SDK) to route a library
  to LGPL vs MPL.

## What changed

- `LICENSING-PHILOSOPHY.md` **and** `skills/.../references/LICENSING-PHILOSOPHY.md`
  — these are byte-identical (verified), so both got the same Libraries-paragraph
  edit to stay in sync.
- `SKILL.md` — split the Libraries table row into dynamic-link (LGPL-3.0) and
  static-link (MPL-2.0); added the governing-rule paragraph; added `mpl-2.0` to
  the SPDX list; added an MPL-2.0 single-file LICENSE note beside the LGPL
  two-file note (and, after Codex P2 on the re-review, a pointer to surface
  MPL's per-file Exhibit A source notice — the static-link branch otherwise
  skipped the manual-notice step the GPL family gets); added the MPL-2.0 README-format mapping; bumped the
  frontmatter description, kept as a `>-` block scalar per the
  parse-safety convention (Codex P2 flagged it on the first push, where the
  edit had left it a plain scalar; folded into this commit). Left
  `agent-setup` and `self-merge`, also plain scalars, untouched — pre-existing
  and out of scope for a licensing PR.
- Added bundled fallback `references/licenses/mpl-2.0.txt` (via
  `gh api /licenses/mpl-2.0`), matching the four existing license texts.
- **Fix-the-class sweep:** the license list "(CC BY-SA 4.0, LGPL-3.0, GPL-3.0,
  or AGPL-3.0)" and the count "the four supported" appeared in the SKILL
  description, two short-circuit sentences, and `README.md`'s skill table —
  updated every instance to include MPL-2.0 / "five".

## Verification

- Prettier `--check` clean on all changed markdown (ran the sibling repo's
  prettier binary; config resolves per-file to this repo's defaults).
- `gh api /licenses/mpl-2.0` returns the full text written to the bundled file
  (374 lines, MPL 2.0 header/footer correct, trailing newline like siblings).
- **Gap:** `markdownlint-cli2` could not run — not installed here and the
  npx auto-download was blocked in this environment. Additions follow the
  existing heading/list/table style and avoid the MD038 space-in-code-span
  gotcha; recorded as a Not-run in the PR for CI / a human to confirm.

## Not in scope

- The aspirational "moat is execution" paragraph — left unchanged (decision on
  the about-page PR; the gap that app-layer extensions stay with the builder is
  known and accepted).
- Pre-existing promote/deferred devlog items — unrelated to licensing.
