# Reranked the post-hoc crop tools in visual-evidence

`skills/visual-evidence/SKILL.md` §4 offered ImageMagick and macOS `sips` as
examples for the "no element capture available" fallback (screenshot, then crop
both shots to the same fixed rectangle). Ben flagged that `sips` has cropping
issues and asked whether to recommend Pillow as a cross-platform alternative.

## Findings

- **`sips` crop, corrected (macOS):** an initial test of _bare_ `sips -c H W`
  showed it crops **centered** (no origin), and I wrongly generalized that to
  "`sips` can't crop an arbitrary rectangle." A Codex re-review (round 2, P2)
  challenged it; empirical testing (sips-316) confirmed Codex: `sips -c H W
--cropOffset TOP LEFT` performs an exact arbitrary-origin crop (offset `0 0`
  → white=0, `60 120` → full marker, `60 130` → exactly half; positive +
  negative + partial controls). So `sips` _is_ usable, and since it's
  pre-installed on every Mac it's a zero-install macOS option, not one to
  avoid. Only bare `-c` (centered) is the trap. Lesson: verify the whole flag
  surface before writing a prohibition, not just the default form.
- **Repo sweep:** only two tool references exist, both in this SKILL.md. Line
  ~119 is the crop fallback (fixed). Line ~202 uses `sips -g pixelWidth` for
  reading dimensions, a different use case where `sips` is fine; left as-is.
- **No prior decision** in the devlog picked `sips` over anything, so nothing
  was relitigated.

## Decisions

- **Reframed around agent self-setup friction, not "cross-platform" alone.**
  The real target (Ben) is low friction for an agent to get working unattended,
  especially in auto mode. That splits the tools: system binaries (vips,
  ImageMagick) are zero-setup one-liners _when present_ but an agent usually
  can't install them unattended; language-package libs (Pillow via pip, Sharp
  via npm) cost one install step but one an agent _can_ run non-interactively.
- **Pillow leads as the self-installable default, not Sharp.** Decisive detail:
  the fallback branch is exactly where `capture.mjs` is _not_ running, so the
  skill's Node-22 assumption doesn't hold there; Sharp's "stay on the existing
  Node runtime" edge evaporates in this spot, and Python/Pillow is more broadly
  present. Sharp still named for Node environments.
- **Kept the examples-not-requirements framing (invariant #2).** The bullet
  orders examples by friction (already-installed system binary, incl. macOS
  `sips` with `--cropOffset` → self-install Pillow/Sharp); it does not mandate a
  tool. (The "avoid sips" clause this bullet originally carried was removed in
  review round 2; see Review below.) Rejected: adding a "setup/recommendations"
  subsection (scope creep for a one-bullet fix) and touching `capture.mjs` (its
  element-capture path clips precisely and needs no external crop tool).
- **Left the dimension-reading `sips -g` (line ~202).** Reading dimensions
  works fine there and already lists `identify` and "your capture tool's
  output" as alternatives.

## Verification

- Passed: markdownlint, prettier, and prose-tics on the changed files.
- Checked: `sips` crop behavior on a marker image (sips-316) across bare `-c`
  (centered) and `-c --cropOffset` (arbitrary origin), with positive, negative,
  and partial-overlap controls; see the corrected finding above. The initial
  bare-`-c`-only check was the incomplete verification that produced the wrong
  "avoid sips" claim.
- Checked: npm save behavior (`npm install` vs `--no-save --no-package-lock`,
  npm 10.9.8) for the Sharp fix.
- Passed: ran each crop example end-to-end on a marker image and confirmed it
  produces the right crop _and_ leaves the input intact: ImageMagick, libvips
  (`L T W H` = left/top/width/height order confirmed), Pillow, and `sips ...
--out`. Sharp's `extract()` is the standard documented API (not run locally:
  install needs network); stated, not verified.

## Review

- **Codex P2 (confirmed, fixed): Sharp install pollutes the repo under review.**
  Plain `npm install sharp` writes `package-lock.json` and a `dependencies`
  entry (verified, npm 10.9.8); since this skill runs during _unrelated_ visual
  work, that's collateral in the diff being reviewed. Fixed the Sharp example to
  `npm install --no-save --no-package-lock sharp` (verified: leaves package.json
  and lockfile untouched, only the gitignored node_modules). Class check: the
  offender is tracked-file writes, unique to npm's save-by-default; a
  `pip install` of Pillow mutates the environment but writes no repo file, and
  apt/brew system installs don't touch the repo, so the fix is Sharp-scoped.
- **Codex P2 round 2 (confirmed, my claim was wrong): the `sips` warning was
  too broad.** See the corrected finding above: `--cropOffset <top> <left>`
  gives `sips` an arbitrary origin, verified empirically. Fixed by folding
  `sips` into the "already installed" bucket for macOS with the offset form,
  and dropping the "avoid sips" bullet. This is a correctness fix _and_ an
  improvement (sips is the one crop tool guaranteed present on macOS with zero
  install).
- **Codex P2 round 3 (confirmed, fixed): the `sips` example was incomplete and
  destructive.** It showed only flags, no input/output, and `sips` crops **in
  place** by default, so following it literally overwrites the captured
  screenshot. Fixed to the complete non-destructive form `sips in.png -c H W
--cropOffset TOP LEFT --out out.png`, matching the sibling in→out examples.
  Class check: swept all five crop examples end-to-end (see Verification);
  `sips` was the only one missing an explicit output, the others already read
  input and write a separate file. Meta-lesson across rounds 2–3: I kept
  shipping plausible crop commands verified only partially; the fix was to
  _run_ each command on a real image, not eyeball it.
- **Network-sandbox caveat added (from Ben's question).** Neither Claude nor
  Codex has a _classifier_ that refuses package installs; the real gates are
  permission prompts (open in full-auto) and, decisively, sandbox network
  access, which Codex commonly disables at exec time. So self-install fails
  loud (not refused) in a network-restricted sandbox. Added a clause noting
  that an already-installed tool or `capture.mjs`'s element clip stays the
  reliable path there. Folded into the same commit as the Sharp fix.

## To promote

- Nothing outstanding. Pre-existing queue items are unrelated
  agent-setup-learnings, left as-is.
