# Capture Craft

## §crop-tools

Use one crop rectangle for both images. Identical coordinates matter more than
the tool.

- **Capture first:** When element capture isn't available, capture the screen
  or window. Crop both images afterward.
- **Prefer low friction:** Use a tool that crops arbitrary rectangles and is
  already installed. An auto-mode agent can't pause for a manual system
  install.
- **Installed binaries:** Use ImageMagick
  (`magick in.png -crop WxH+X+Y +repage out.png`) or libvips
  (`vips crop in.png out.png L T W H`).
- **macOS `sips`:** It crops in place and from the center by default. Pass an
  explicit `--out` and set the origin with `--cropOffset`:
  `sips in.png -c H W --cropOffset TOP LEFT --out out.png`.
- **Avoid bare `sips -c`:** It overwrites the input with a centered crop.
- **Pillow fallback:** Install its common-platform wheel with
  `pip install pillow`. Then use
  `Image.open(p).crop((left, top, right, bottom)).save(out)`.
- **Sharp fallback:** On Node, install with
  `npm install --no-save --no-package-lock sharp`. Those flags avoid adding a
  dependency or lockfile to the reviewed change. Crop with
  `sharp(p).extract({ left, top, width, height }).toFile(out)`.
- **Restricted sandbox:** Self-installation needs network access and open
  permissions. Otherwise, use an installed tool or `capture.mjs` element
  clipping.

## §display-layout

Choose the layout from each saved file's pixel width.

- **Use file pixels:** Don't use the element's logical width. A 2x-DPR capture
  doubles the file width, and GitHub sizes images from file pixels.
- **Pair narrow images:** Use a two-column GFM table when each file is roughly
  600px wide or less. Each cell gets about half of the 830px PR body.

  ```markdown
  | Before                | After               |
  | --------------------- | ------------------- |
  | ![Before](before-url) | ![After](after-url) |
  ```

- **Stack wide images:** Put a bold **Before** caption above the first image and
  **After** above the second. Stacking prevents unreadable shrinkage.
- **Repeat by theme:** Use one block per theme. Name the theme in each caption,
  such as "Before (dark)" and "After (dark)."

## §examples

These examples apply the capture and upload rules to common changes.

### A CSS Spacing Bug Fix (Before/After Pair)

A list's rows are cramped because their vertical padding is too small.

1. Run the PR's merge-base, which isn't always `main`. It could be a release
   or stacked branch.
2. Open the list with seeded fixture rows at a fixed viewport.
3. Capture only the list as `before.png`.
4. Apply the padding fix. Reload the same route, viewport, and fixture data.
5. Capture the same element and framing as `after.png`.
6. Confirm the width matches. The height should grow by the added padding.
7. If both themes apply, repeat as `before-dark.png` and `after-dark.png`.
8. Apply the full review under Compose and Attach to every image.
9. Use gh-imgup upload-only. Put a labeled pair for each palette in the PR
   description.

### A Net-New Component (Single _after_ Shot)

A new empty-state card has no meaningful before state.

1. Open the empty state with fixture data at a fixed viewport.
2. Capture the card with a little padding as `after.png`.
3. Add a dark variant when relevant.
4. Apply the full review under Compose and Attach.
5. Upload through gh-imgup.
6. Put one shot captioned "Empty state" in the PR description.
