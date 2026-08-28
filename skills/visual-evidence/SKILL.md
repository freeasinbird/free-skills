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
  image for sensitive data before uploading; that mandatory step is gh-imgup's,
  and it is written out in full here so it survives when that skill isn't
  loaded. Not for non-visual work (logic, backend, or docs with no output).
---

# Visual Evidence

Produce the before/after screenshots that let a reviewer judge a visual change
by looking at it instead of reading the diff. This skill owns the _capture
craft and timing_: deciding a screenshot is warranted, getting a clean
deterministic before/after pair, and framing it tightly on the change. It does
**not** upload: once the images are ready it hands them to the **gh-imgup**
skill, which owns safe upload and the mandatory pre-upload secret review
(written out under _Compose & attach_ so the review survives even where that
skill isn't loaded).

Two skills, one clean seam:

- **this skill**: _I'm doing or reviewing visual work; produce review
  evidence._ Capture → compose labeled pair → decide where it goes.
- **gh-imgup**: _I have image bytes to publish._ Upload to the PR/issue and
  return Markdown, after its mandatory pre-upload review of each image.

Reach for this one _early_. The decisive reason is timing: the _before_ state
usually only exists before the fix lands, so prompting late loses it.

## When to Use It

- Implementing a visual change: a UI bug or regression, a CSS/layout/spacing/
  color/typography change, a new or restyled component or screen, a theming
  change: anything where "looks right" is the acceptance test.
- About to open or review a **PR whose diff touches rendered UI**, where a
  reviewer would benefit from seeing the result rather than parsing the diff.
- The user asks to "show the change", "add a screenshot", or "before/after".

Bias toward suggesting this proactively on visual work, even unprompted:
capturing the _before_ is cheap now and impossible later.

## When NOT to Use It

- Purely non-visual changes: logic, backend, data, build, or config work with
  no rendered output.
- Docs or comments that don't change anything a user sees rendered.
- You already have the image(s) in hand and only need to attach them: go
  straight to the gh-imgup skill; that's its trigger, not this one.

## Capture the Before/After

### 1. Decide Whether a Pair Is Warranted

- **Before/after pair** for visible bugs/regressions and any layout, spacing,
  color, typography, or restyle change: the point is the _difference_.
- **A single _after_ shot** is enough for net-new UI, where there's no
  meaningful "before".
- **Skip** entirely for non-visual changes (see When NOT to use it).

### 2. Capture the _before_ First

The before state is perishable: capture it before the fix exists.

- Check out or run the **pre-change** state: the PR's base branch (its
  merge-base, not always `main`), or stash the fix. Then drive the app to the
  exact screen and interactive state that shows the problem, and capture →
  `before.png`.
- If the before state is **already gone** (fix committed), reconstruct it from
  the base branch in a separate worktree or checkout rather than skipping it:
  e.g. `git worktree add ../before-state <base-branch>`, run from there,
  capture, then remove the worktree.

### 3. Capture the _after_ Under Identical Conditions

Apply the change, drive the app to the **same** screen and state, capture →
`after.png`. Identical conditions are the whole point: the only visible
difference between the two images must be the change itself. Hold constant:

- **Route / URL and app data**: prefer seeded or fixture data, not live or
  random data.
- **Viewport size** and device-pixel-ratio / zoom. Set a fixed, standard
  viewport rather than whatever the window happens to be: 1280×720 is a sane
  desktop default (or the app's design target); use a mobile width (e.g.
  390×844) when the change is mobile-specific. When the change is
  responsive (it affects layout across widths), capture desktop and mobile
  as a viewport matrix in the same run (one command where your tooling
  supports it; see the reference capture script) instead of re-driving the
  app once per width; each width is its own before/after pair, named per
  width (`before-1280x720.png` / `after-1280x720.png`,
  `before-390x844.png` / `after-390x844.png`). Prefer 2x DPR so text stays
  legible when the image is scaled down.
- **Theme**: capture **both light and dark** as separate pairs when the
  change affects appearance in both.
- **Interactive state**: default / hover / focus / active / error / empty /
  loading. Capture the state that demonstrates the change.
- **Crop region**: the same framing for both shots (see framing), so they
  line up when placed side by side.

### 4. Framing & Cropping

- **Crop to the affected component or region, not the whole screen**, unless
  the change is genuinely page-level (overall layout, cross-page spacing). A
  full-screen shot buries the point in nav, chrome, and noise. An oversized
  shot also keeps costing after capture: an image placed into an agent
  conversation is typically re-read on every later turn, so a full-page
  screenshot spends context for the rest of the session, while a tight crop
  pays once.
- Prefer **element-level capture** so the frame is tight and deterministic:
  - Playwright: `locator.screenshot()` / `elementHandle.screenshot()`, or
    `page.screenshot({ clip: { x, y, width, height } })`.
  - Chrome DevTools / CDP: read the node's bounding box and clip to it.
  - OS screenshot tools: crop to a fixed rectangle and reuse it for both shots.
- **No element capture available?** Crop both images to the same fixed
  rectangle after capture. See `references/capture-craft.md` §crop-tools for
  tool choices and exact commands.

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
  mind GitHub's size limits and gh-imgup's `--max-size` cap.

These tools are examples for common host setups, not requirements: use
whatever capture mechanism your environment provides, applying the same
craft (tight crop, identical conditions, deterministic state).

### Reference Capture Script

Where headless Chrome and Node 22+ are available, `capture.mjs` alongside
this file makes the mechanics of steps 3–5 executable in one command:
deterministic readiness waits (network-idle, selector visibility), an
animation kill switch, a pinned color scheme (`--dark` for the dark
variant of a theme pair), a viewport matrix, DPR, element clipping with
padding, retries, and a total timeout budget.

Invoke it **by path, from the project directory the screenshots belong
in**, where `<skill-dir>` is the directory holding this file (its path
differs per platform and install):

```sh
node <skill-dir>/capture.mjs --url http://localhost:3000/cards \
  --out after.png --viewport 1280x720,390x844 --wait-for '#card-list' \
  --clip '#card-list'
```

Don't change directory into the skill to run it. `--out` (and `--chrome`,
where you pass a relative one) resolves from the working directory, not
the script's, so from a globally installed skill's own directory (the
usual install) the run writes its screenshots into the skill's install
directory, where the upload step under _Compose & attach_ will not find
them.

`--url` and `--out` are required; every other option has a default that
suits an ordinary capture:

| Option              | Default    | Effect                                                           |
| ------------------- | ---------- | ---------------------------------------------------------------- |
| `--viewport`        | `1280x720` | comma-separated list; widths ≤ 600 get Chrome's mobile emulation |
| `--wait-for`        | none       | CSS selector to wait on until present and visible                |
| `--clip`            | none       | CSS selector to crop to, its bounding box                        |
| `--clip-pad`        | `12`       | px of context padding around `--clip`                            |
| `--settle-ms`       | `500`      | quiet period after readiness, before the shot                    |
| `--dpr`             | `2`        | device pixel ratio, 1 to 4                                       |
| `--dark`            | off        | emulate `prefers-color-scheme: dark`                             |
| `--timeout-budget`  | `90`       | total seconds across all viewports and retries                   |
| `--attempt-timeout` | `30`       | per-attempt seconds, clamped to the remaining budget             |
| `--retries`         | `2`        | extra attempts per viewport                                      |
| `--chrome`          | autodetect | Chrome binary path (also read from `$CHROME`)                    |
| `--chrome-flag`     | none       | repeatable extra Chrome flag, e.g. `--no-sandbox` in a container |

**The output filenames follow the viewport count**: one viewport writes
exactly `--out`, and several insert the size before the extension, so the
run above writes `after-1280x720.png` and `after-390x844.png`, never
`after.png`. Look for the names the run actually reports, not the `--out`
you passed.

The script prints one line per written file with the image's actual
dimensions, which is the input to the step 6 dimension check. The timeout budget
(default 90 seconds, `--timeout-budget`) keeps the whole run under the
roughly 2-minute cap common to agent shell tools (see step 5), and its
exit codes are explicit: 64 usage, 69 no usable Chrome or Node, 1 capture
failed after retries. Where Chrome or Node 22+ is missing, the script
refuses with exit 69 and the prose in steps 3–6 is the specification:
apply the same craft with whatever capture mechanism your environment
provides.

### 5. Determinism & Hygiene

- **Disable animations** and wait for network-idle and the target element to be
  visible before capturing, so shots are stable and repeatable.
- **Budget the capture's wall-clock time explicitly.** Agent shell tools
  commonly cap a command around 2 minutes, and a capture that hangs on a
  readiness wait eats the whole cap and returns nothing. Give the run a
  total timeout budget under that cap (the reference script defaults to
  90 seconds) with per-attempt timeouts and retries, so a hung wait fails
  fast, retries, and reports a legible error instead of being killed
  opaquely.
- Use **seeded / fixture data**; avoid timestamps, random values, and live
  customer data that add noise.
- Hygiene here is about _clean, comparable_ shots. **Secret and PII safety is
  the mandatory pre-upload review under _Compose & attach_**, which is
  gh-imgup's step and runs before any upload; that checklist is the one to
  apply, so read it there rather than working from memory here. (The two
  reinforce each other: fixture data also keeps secrets out of the frame.)

### 6. Check the Shots Before Handing Off

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

This is the capture-quality pass and is separate from the pre-upload secret
review under _Compose & attach_ (a different axis). You'll open each image
again at upload time for that review;
doing the quality check now means one look covers both before you hand off.

## Compose & Attach

Hand the captured files to the **gh-imgup skill**, which uploads them and
returns renderable Markdown. Do not re-implement upload or invent a host here.
If that skill isn't loaded in your environment, the underlying tool is the
`@freeasinbird/gh-imgup` **CLI**. Apply the full pre-upload review below to
every image _before_ you run any of it. Images are positional arguments, and
**upload-only is simply omitting `--pr`/`--issue`**:

```sh
# GITHUB_TOKEN in the environment; --repo is inferred from the origin remote
npx -y @freeasinbird/gh-imgup before.png after.png
```

The `-y` skips npx's interactive first-run prompt, and the CLI needs Node 22+.
It prints one Markdown image line per file to stdout, in the order given, for
you to compose into the body; progress goes to stderr, so capturing stdout
gets you the links alone. Add `--repo <owner>/<repo>` when running outside the
target repository, and `--pr <n>` / `--issue <n>` only when you want the
images posted as a follow-up comment instead. `--help` lists the full option
surface and carries the same review in condensed form. Either way, the upload
step is gh-imgup's; this skill only produces the images.

- **Review each image before uploading, and not only for "secrets."** This is
  gh-imgup's mandatory, load-bearing step; there is no un-publish, so it comes
  before any step that puts bytes on the wire. It is written out in full here,
  at gh-imgup's own bar, because this is the copy that survives when neither
  the gh-imgup skill nor its `--help` is in front of you; **this is the
  checklist to apply**, and nothing softer or narrower substitutes for it.
  Screenshots leak more than API keys, so open each image and check it for:
  - API keys, tokens, passwords, session cookies, `.env` contents
  - internal hostnames, IPs, private URLs, infrastructure details
  - customer or personal data (PII), real names, emails, account numbers
  - anything from a terminal, editor, browser devtools, or notification that
    wasn't meant to be shared

  If an image contains any of these, **do not upload it**: stop, tell the user
  exactly what you found and where, and ask them to crop, redact, or pick a
  different image. When in doubt, ask before uploading.

- **Default placement: the PR description**, most visible to reviewers. A
  comment is the fallback, for after-the-fact additions or for issues.
- Prefer gh-imgup's **upload-only** mode and compose the Markdown it returns
  into the body yourself; that is what puts the images where a reviewer reads
  them, rather than in a trailing comment.
- **Label clearly**: a **Before** / **After** pair, with captions naming the
  state shown (e.g. "Empty state, dark mode"). Show **both palettes** when the
  change affects appearance in light and dark.
- **Use a concrete display layout.** See
  `references/capture-craft.md` §display-layout for the side-by-side and
  stacked rules.

- **Verify the rendered result.** This is the final step, after every image
  has passed the pre-upload review above and gh-imgup has uploaded it: view
  the rendered PR or issue body and confirm both images actually render (no
  broken attachment links), each label sits with its own image, and the pair
  reads in before → after order. A block that looks right in raw Markdown can
  still render broken; a missing image is only visible in the rendered view.

## Examples

See `references/capture-craft.md` §examples for a before/after spacing fix and
a net-new component.
