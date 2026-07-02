---
name: visual-evidence
description: >-
  Capture before/after screenshots of a UI change so a human reviewer can see
  it, not just read the diff. Use this when implementing or reviewing a visual
  change (a UI bug fix, a CSS/layout/spacing/typography fix, a new component or
  screen, a theming change, or a visual regression), or when the user asks to
  "show the change", "add a screenshot", or "before/after". Reach for it early
  and proactively: the *before* state is perishable and is often destroyed once
  the fix lands. This skill owns capture craft and workflow timing (deciding to
  capture, getting a clean deterministic pair, framing/cropping tight); it hands
  the finished images to the gh-imgup skill to upload and attach. Review each
  image for sensitive data before uploading; that mandatory step lives in
  gh-imgup. Not for non-visual work (logic, backend, or docs with no output).
---

# Visual Evidence

Produce the before/after screenshots that let a reviewer judge a visual change
by looking at it instead of reading the diff. This skill owns the _capture
craft and timing_: deciding a screenshot is warranted, getting a clean
deterministic before/after pair, and framing it tightly on the change. It does
**not** upload: once the images are ready it hands them to the **gh-imgup**
skill, which owns safe upload and the mandatory pre-upload secret review.

Two skills, one clean seam:

- **this skill**: _I'm doing or reviewing visual work; produce review
  evidence._ Capture → compose labeled pair → decide where it goes.
- **gh-imgup**: _I have image bytes to publish._ Upload to the PR/issue and
  return Markdown, after its mandatory pre-upload review of each image.

Reach for this one _early_. The decisive reason is timing: the _before_ state
usually only exists before the fix lands, so prompting late loses it.

## When to use it

- Implementing a visual change: a UI bug or regression, a CSS/layout/spacing/
  color/typography change, a new or restyled component or screen, a theming
  change: anything where "looks right" is the acceptance test.
- About to open or review a **PR whose diff touches rendered UI**, where a
  reviewer would benefit from seeing the result rather than parsing the diff.
- The user asks to "show the change", "add a screenshot", or "before/after".

Bias toward suggesting this proactively on visual work, even unprompted:
capturing the _before_ is cheap now and impossible later.

## When NOT to use it

- Purely non-visual changes: logic, backend, data, build, or config work with
  no rendered output.
- Docs or comments that don't change anything a user sees rendered.
- You already have the image(s) in hand and only need to attach them: go
  straight to the gh-imgup skill; that's its trigger, not this one.

## Capture the before/after

### 1. Decide whether a pair is warranted

- **Before/after pair** for visible bugs/regressions and any layout, spacing,
  color, typography, or restyle change: the point is the _difference_.
- **A single _after_ shot** is enough for net-new UI, where there's no
  meaningful "before".
- **Skip** entirely for non-visual changes (see When NOT to use it).

### 2. Capture the _before_ first

The before state is perishable: capture it before the fix exists.

- Check out or run the **pre-change** state: the PR's base branch (its
  merge-base, not always `main`), or stash the fix. Then drive the app to the
  exact screen and interactive state that shows the problem, and capture →
  `before.png`.
- If the before state is **already gone** (fix committed), reconstruct it from
  the base branch in a separate worktree or checkout rather than skipping it:
  e.g. `git worktree add ../before-state <base-branch>`, run from there,
  capture, then remove the worktree.

### 3. Capture the _after_ under identical conditions

Apply the change, drive the app to the **same** screen and state, capture →
`after.png`. Identical conditions are the whole point: the only visible
difference between the two images must be the change itself. Hold constant:

- **Route / URL and app data**: prefer seeded or fixture data, not live or
  random data.
- **Viewport size** and device-pixel-ratio / zoom. Set a fixed, standard
  viewport rather than whatever the window happens to be: 1280×720 is a sane
  desktop default (or the app's design target); use a mobile width (e.g.
  390×844) when the change is mobile-specific. Prefer 2x DPR so text stays
  legible when the image is scaled down.
- **Theme**: capture **both light and dark** as separate pairs when the
  change affects appearance in both.
- **Interactive state**: default / hover / focus / active / error / empty /
  loading. Capture the state that demonstrates the change.
- **Crop region**: the same framing for both shots (see framing), so they
  line up when placed side by side.

### 4. Framing & cropping

- **Crop to the affected component or region, not the whole screen**, unless
  the change is genuinely page-level (overall layout, cross-page spacing). A
  full-screen shot buries the point in nav, chrome, and noise.
- Prefer **element-level capture** so the frame is tight and deterministic:
  - Playwright: `locator.screenshot()` / `elementHandle.screenshot()`, or
    `page.screenshot({ clip: { x, y, width, height } })`.
  - Chrome DevTools / CDP: read the node's bounding box and clip to it.
  - OS screenshot tools: crop to a fixed rectangle and reuse it for both shots.
- **No element capture available?** Capture the screen or window, then crop
  both images to the same fixed rectangle after the fact with whatever image
  tool the host provides (ImageMagick or macOS `sips` are examples, not
  requirements). The invariant is the identical crop rectangle across both
  shots, not any particular tool.
- Include **just enough surrounding context** to orient the reviewer (a
  little padding around the component) and cut irrelevant sidebars and
  headers.
  Tight is not context-free: keep one orienting landmark in frame (the
  component's own heading, or a sliver of the adjacent element) so the
  reviewer can tell where in the UI they are; a crop showing only the
  changed pixels reads as a floating fragment.
- Keep the **framing identical across before and after** so they're directly
  comparable: the same rectangle for fixed-rectangle capture; the same
  element and padding for element capture, where the element's own size may
  change when the fix changes it.
- **Mind the final dimensions.** The image has to stay legible rendered
  inline in a PR body (GitHub renders it at roughly 830 CSS px wide), so
  avoid extreme aspect ratios and multi-thousand-pixel captures: a full-page
  shot of a very tall page renders as an illegible strip. Reserve full-page
  capture for genuinely page-level changes, and even then prefer the
  relevant section. Use a reasonable resolution / DPR for legibility, but
  mind GitHub's size limits and gh-imgup's `--max-size` (default 25 MB).

These tools are examples for common host setups, not requirements: use
whatever capture mechanism your environment provides, applying the same
craft (tight crop, identical conditions, deterministic state).

### 5. Determinism & hygiene

- **Disable animations** and wait for network-idle and the target element to be
  visible before capturing, so shots are stable and repeatable.
- Use **seeded / fixture data**; avoid timestamps, random values, and live
  customer data that add noise.
- Hygiene here is about _clean, comparable_ shots. **Secret and PII safety is
  gh-imgup's mandatory pre-upload review**: defer to it; don't restate a
  weaker version here. (The two reinforce each other: fixture data also keeps
  secrets out of the frame.)

### 6. Check the shots before handing off

Open each captured image and look at it; don't publish evidence you haven't
verified. Confirm:

- **Not blank or truncated.** A common silent failure is an all-white or
  zero-size image (captured before render, or a locator that matched nothing /
  an offscreen element). If it's empty, fix the wait or selector and re-capture.
- **Shows the intended component and state.** The right screen, the right
  interactive state (hover/error/empty/…), and the change is actually visible
  in frame.
- **Before and after are comparable.** Same crop, viewport, and theme, so the
  only difference is the change. If they don't line up, re-capture the odd one
  under the other's conditions; a mismatched pair misleads the reviewer.
- **Dimensions are sane and explained.** Inspect the actual width×height of
  each file (ImageMagick `identify`, macOS
  `sips -g pixelWidth -g pixelHeight`, or your capture tool's output).
  Fixed-rectangle crops must match exactly. For element-level captures, the
  only dimension differences allowed are the ones the change itself
  explains, on either axis: a padding or line-height fix moves height, a
  widened button or column moves width, and the delta should roughly match
  the CSS change. Treat any unexplained difference as a non-comparable
  pair. Flag absurd sizes for re-capture: a multi-thousand-pixel-tall
  full-page scroll, or a sub-100px sliver that cropped away the subject.

This is the capture-quality pass and is separate from gh-imgup's secret review
(a different axis). You'll open each image again at upload time for that review;
doing the quality check now means one look covers both before you hand off.

## Compose & attach

Hand the captured files to the **gh-imgup skill**, which uploads them and
returns renderable Markdown. Do not re-implement upload or invent a host here.
If that skill isn't loaded in your environment, the underlying tool is the
`@freeasinbird/gh-imgup` **CLI**: run it with `npx -y @freeasinbird/gh-imgup`
(the `-y` skips npx's interactive first-run prompt; Node 22+). Its `--help`
notes the upload contract and the secret review, but only tersely; apply the
full review below (or read the gh-imgup skill's review section) before
uploading; don't treat `--help` as the complete checklist. Either way, the
upload step is gh-imgup's; this skill only produces the images.

- **Default placement: the PR description**, most visible to reviewers. A
  comment is the fallback, for after-the-fact additions or for issues.
- **Review each image before uploading, and not only for "secrets."** This is
  gh-imgup's mandatory, load-bearing step; there is no un-publish, so it comes
  before any step that puts bytes on the wire. Screenshots
  leak more than API keys, so check every image for: credentials, tokens, and
  keys; internal hostnames, IPs, and infrastructure details; customer data or
  PII (names, emails, account numbers); and anything else not meant to be
  shared. The gh-imgup skill carries the canonical checklist; defer to it when
  it's loaded, and never substitute a softer or narrower version. (The CLI's
  `--help` states the requirement only in one line; it's a reminder, not the
  full checklist.)
- Use gh-imgup's preferred body-composition flow: run it **upload-only** (no
  `--pr`/`--issue`) and compose the Markdown URLs it prints to stdout into the
  PR/issue body. Use `--pr`/`--issue` only for a follow-up comment on an
  existing thread.
- **Label clearly**: a **Before** / **After** pair, with captions naming the
  state shown (e.g. "Empty state, dark mode"). Show **both palettes** when the
  change affects appearance in light and dark.
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

- **Verify the rendered result.** This is the final step, after every image
  has passed the pre-upload review above and gh-imgup has uploaded it: view
  the rendered PR or issue body and confirm both images actually render (no
  broken attachment links), each label sits with its own image, and the pair
  reads in before → after order. A block that looks right in raw Markdown can
  still render broken; a missing image is only visible in the rendered view.

## Examples

### A CSS spacing bug fix (before/after pair)

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

### A net-new component (single _after_ shot)

A brand-new empty-state card: there's no meaningful "before". Drive the app to
the empty state with fixture data at a fixed viewport, element-capture the card
with a little padding → `after.png` (plus a dark variant if relevant). Run the
full pre-upload review (see _Compose & attach_), upload via gh-imgup, and place
a single captioned shot ("Empty state") in the PR description so the reviewer
sees the new surface at a glance.
