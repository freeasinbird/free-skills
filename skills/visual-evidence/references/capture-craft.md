# Capture Craft

## §crop-tools

- **No element capture available?** Capture the screen or window, then crop
  both images to the same fixed rectangle after the fact. The invariant is the
  identical crop rectangle across both shots, not any particular tool; prefer
  one that can crop an arbitrary rectangle and that your environment either
  already has or can install unattended (auto-mode agents can't stop to
  hand-install a system package). Examples, roughly in that friction order:
  - **Already installed?** A system binary is a zero-setup one-liner:
    ImageMagick (`magick in.png -crop WxH+X+Y +repage out.png`) or libvips
    (`vips crop in.png out.png L T W H`). On macOS, `sips` is always present, but
    it crops **in place** and **centered** by default, so pass an explicit
    `--out` and pin the origin with `--cropOffset`:
    `sips in.png -c H W --cropOffset TOP LEFT --out out.png` (bare `-c` alone
    overwrites the input with a centered crop).
  - **Otherwise install one via a runtime you already have**, which an agent
    can do non-interactively: Pillow (`pip install pillow`, prebuilt wheels on
    common platforms) with `Image.open(p).crop((left, top, right, bottom)).save(out)`,
    or, on Node, Sharp (`npm install --no-save --no-package-lock sharp`, so
    cropping a screenshot leaves no stray dependency or lockfile in the change
    under review) with
    `sharp(p).extract({ left, top, width, height }).toFile(out)`.

  Self-installing assumes the agent's sandbox allows network (and, in full-auto,
  open permissions); a network-restricted sandbox (common under Codex and locked-
  down automode) makes even `pip`/`npm` fail, so an already-installed tool, or
  `capture.mjs`'s own element clip on the primary path, stays the most reliable.

## §display-layout

- **Use a concrete display layout.** Judge width by the saved file's actual
  pixel width, not the element's logical width: a 2x-DPR capture doubles it,
  and GitHub sizes the image by file pixels. When each file is narrow enough
  to pair side by side (roughly ≤600px file width each; a table cell gets
  about half of the ~830px body, so wider files shrink badly), put the pair
  in a two-column GFM table so the reviewer's eye can jump between them:

  ```markdown
  | Before                | After               |
  | --------------------- | ------------------- |
  | ![Before](before-url) | ![After](after-url) |
  ```

  When the images are wider, stack them with a bold **Before** caption above
  the first and **After** above the second, so neither is shrunk to
  illegibility. Repeat the block per theme, with the caption naming the theme
  ("Before (dark)" / "After (dark)").

## §examples

### A CSS Spacing Bug Fix (Before/After Pair)

A list's rows are cramped: vertical padding is too tight. Before touching the
CSS: run the app on the PR's base branch (its merge-base, not always `main`;
could be a release or a stacked branch), navigate to the list with seeded
fixture rows, set
a fixed viewport, and element-capture just the list → `before.png`. Apply the
padding fix, reload the **same** route at the **same** viewport with the
**same** fixture data, and capture the same element with the same framing →
`after.png` (same width; the height grows by the padding you added). If the component renders in both themes, repeat for dark →
`before-dark.png` / `after-dark.png`. Run the full pre-upload review on each
image (see _Compose & attach_), hand all of them to gh-imgup upload-only, and
compose a labeled Before/After block (both palettes) into the PR description.

### A Net-New Component (Single _after_ Shot)

A brand-new empty-state card: there's no meaningful "before". Drive the app to
the empty state with fixture data at a fixed viewport, element-capture the card
with a little padding → `after.png` (plus a dark variant if relevant). Run the
full pre-upload review (see _Compose & attach_), upload via gh-imgup, and place
a single captioned shot ("Empty state") in the PR description so the reviewer
sees the new surface at a glance.
