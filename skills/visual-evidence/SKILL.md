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

Capture screenshots that let a reviewer judge a visual change without reading
the diff. Start early because the _before_ state usually disappears when the
fix lands.

This skill owns capture timing and craft. It produces clean, tightly framed
evidence. **gh-imgup** is the skill or CLI that reviews and uploads the finished
image files.

Follow this procedure:

1. Decide whether the change needs a pair or one _after_ shot.
2. Capture the _before_ state before changing it.
3. Capture the _after_ state under identical conditions.
4. Frame both shots tightly and consistently.
5. Make the capture deterministic.
6. Open and check every shot.
7. Review every image for secrets and private data.
8. Use gh-imgup to upload and place the evidence.
9. Verify the rendered result.

## When to Use It

- **Visual implementation:** Use it for a UI bug, regression, restyle, new
  surface, theme change, or any work judged by appearance.
- **UI review:** Use it when opening or reviewing a PR that changes rendered
  UI and screenshots would help the reviewer.
- The user asks to "show the change", "add a screenshot", or "before/after".

Suggest it proactively for visual work. Capturing the _before_ is cheap now and
may be impossible later.

## When Not to Use It

- **Non-visual work:** Skip logic, backend, data, build, or configuration
  changes that have no rendered output.
- Docs or comments that don't change anything a user sees rendered.
- **Images already captured:** Use gh-imgup directly when you only need to
  attach existing images.

## Capture the Before/After

### 1. Decide Whether a Pair Is Warranted

- **Before/after pair:** Use one for visible fixes and any layout, spacing,
  color, typography, or restyle change. The difference is the evidence.
- **Single _after_ shot:** Use one for net-new UI with no meaningful before
  state.
- **Skip** entirely for non-visual changes (see When NOT to use it).

### 2. Capture the _before_ First

Capture this state before the fix exists.

- **Run the pre-change state:** Use the PR's merge-base, which isn't always
  `main`, or stash the fix.
- **Show the problem:** Drive the app to the exact screen and interactive
  state, then capture it as `before.png`.
- **Reconstruct a lost state:** If the fix is committed, use a separate
  worktree or checkout instead of skipping the shot.
- **Clean up:** For example, add `../before-state` from `<base-branch>`, run
  and capture there, then remove the worktree.

### 3. Capture the _after_ Under Identical Conditions

Apply the change. Drive the app to the same screen and state, then capture
`after.png`. The change must be the pair's only visible difference.

- **Route, URL, and data:** Keep them fixed. Prefer seeded or fixture data to
  live or random data.
- **Viewport, DPR, and zoom:** Fix all three instead of using the current
  window settings.
- **Desktop viewport:** Use 1280×720 as a default, or use the app's design
  target.
- **Mobile viewport:** Use a mobile size such as 390×844 for a mobile-specific
  change.
- **Responsive change:** Capture desktop and mobile as one viewport matrix
  when the tool supports it. Don't drive the app once per width.
- **Responsive filenames:** Give each width its own pair, such as
  `before-1280x720.png` and `after-1280x720.png`.
- **Mobile filenames:** Name the other pair `before-390x844.png` and
  `after-390x844.png`.
- **DPR:** Prefer 2x so text stays legible when scaled down.
- **Theme:** Capture separate light and dark pairs when both appearances
  change.
- **Interactive state:** Capture the default, hover, focus, active, error,
  empty, or loading state that demonstrates the change.
- **Crop region:** Keep the same framing so the pair lines up side by side.

### 4. Framing & Cropping

- **Crop to the change:** Use the affected component or region unless the
  change is page-level, such as overall layout or cross-page spacing.
- **Avoid noise:** A full-screen shot buries the point in navigation, browser
  chrome, and unrelated UI.
- **Keep context cost low:** A conversation may re-read an image on every
  later turn. A tight crop avoids repeatedly spending context on irrelevant
  pixels.
- **Prefer element capture:** It gives a tight, deterministic frame.
  - Playwright: `locator.screenshot()` / `elementHandle.screenshot()`, or
    `page.screenshot({ clip: { x, y, width, height } })`.
  - Chrome DevTools or CDP: read the node's bounding box and clip to it.
  - OS screenshot tools: crop to one fixed rectangle and reuse it.
- **No element capture:** Crop both full images to one fixed rectangle after
  capture. See `references/capture-craft.md` §crop-tools for commands and tool
  choices.
- **Keep useful context:** Add a little padding. Remove irrelevant sidebars
  and headers.
- **Keep one landmark:** Show the component heading or part of an adjacent
  element. Changed pixels alone look like a floating fragment.
- **Match fixed crops:** Use the same rectangle for both shots.
- **Match element crops:** Use the same element and padding. Its size may
  change when the fix changes it.
- **Keep inline images legible:** GitHub renders the PR body at roughly 830 CSS
  px wide. Avoid extreme ratios and multi-thousand-pixel captures.
- **Limit full-page capture:** Reserve it for page-level changes. Even then,
  prefer the relevant section over the full page.
- **Balance resolution and size:** Use enough resolution or DPR for legibility.
  Respect GitHub's limits and gh-imgup's `--max-size` cap.

The named tools are examples, not requirements. Use any available capture
method that preserves tight framing, identical conditions, and deterministic
state.

### Reference Capture Script

Use `capture.mjs` with headless Chrome and Node 22+. It makes steps 3 through 5
executable in one command.

The script controls readiness waits, animations, color scheme, viewports, DPR,
element clipping, retries, and a total timeout budget.

Run it by path from the project directory that will hold the screenshots.
`<skill-dir>` is this skill's directory, whose installed path varies by
platform.

```sh
node <skill-dir>/capture.mjs --url http://localhost:3000/cards \
  --out after.png --viewport 1280x720,390x844 --wait-for '#card-list' \
  --clip '#card-list'
```

Don't change into the skill directory. Relative `--out` and `--chrome` paths
resolve from the working directory, not the script directory.

Running inside a global skill install writes screenshots into that install.
The Compose and Attach step won't find them there.

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

**Output filenames depend on viewport count.** One viewport writes exactly
`--out`. Several viewports insert the size before the extension.

The example writes `after-1280x720.png` and `after-390x844.png`, never
`after.png`. Use the names reported in the script's `WROTE` lines.

Each `WROTE` line includes actual dimensions for the step 6 check. The default
90-second `--timeout-budget` stays under the roughly two-minute cap common to
agent shell tools.

Exit 64 means invalid usage. Exit 69 means no usable Chrome or Node. Exit 1
means capture failed after retries.

On exit 69, the prose in steps 3 through 6 is the specification. Apply the
same craft with another capture method.

### 5. Determinism & Hygiene

- **Stabilize the page:** Disable animations. Wait for network idle and for the
  target element to become visible.
- **Set a wall-clock budget:** Agent shell tools commonly cap commands near two
  minutes. A hung readiness wait can consume that cap and return nothing.
- **Fail clearly:** Keep the total budget below the shell cap. Add per-attempt
  timeouts and retries so a hung wait reports an error.
- **Use the script default:** `capture.mjs` uses a 90-second total budget.
- **Use stable data:** Prefer seeded or fixture data. Avoid timestamps, random
  values, and live customer data.
- **Keep capture hygiene focused:** Make shots clean and comparable. Fixture
  data also keeps secrets out of the frame.
- **Apply upload hygiene separately:** Use the mandatory checklist under
  Compose and Attach before every upload. Read it there instead of relying on
  memory.

### 6. Check the Shots Before Handing Off

Open every captured image. Don't publish evidence you haven't checked.

- **Reject blank or truncated shots:** An all-white or zero-size image may
  mean capture ran before render or matched no visible element.
- **Fix empty shots:** Correct the wait or selector, then capture again.
- **Check subject and state:** Confirm the intended screen, component, and
  interactive state appear. The change must be visible.
- **Check comparability:** Match crop, viewport, and theme. Re-capture the odd
  image under the other's conditions when the pair doesn't line up.
- **Inspect dimensions:** Use ImageMagick `identify`, macOS
  `sips -g pixelWidth -g pixelHeight`, or the capture tool's `WROTE` output.
- **Match fixed crops exactly:** Their width and height must be identical.
- **Explain element-size changes:** A padding or line-height fix may change
  height. A wider button or column may change width.
- **Match the CSS delta:** Any dimension change should roughly match the visual
  change. Treat an unexplained difference as a non-comparable pair.
- **Reject absurd sizes:** Re-capture a multi-thousand-pixel-tall scroll or a
  sub-100px sliver that lost the subject.
- **Keep both checks:** This is the capture-quality pass. Apply the separate
  secret review under Compose and Attach when you open every image again.

## Compose and Attach

Hand the files to the **gh-imgup skill**. It uploads them and returns Markdown.
Don't reimplement upload or invent another host.

Use the `@freeasinbird/gh-imgup` CLI when the skill isn't loaded. Apply the full
pre-upload review below to every image before running any of it. Images are
positional arguments. Upload-only means omitting `--pr` and `--issue`.

```sh
# GITHUB_TOKEN in the environment; --repo is inferred from the origin remote
npx -y @freeasinbird/gh-imgup before.png after.png
```

- **Review each image before uploading, and not only for "secrets."** This is
  gh-imgup's mandatory step. It comes before upload because there is no
  un-publish. Keep this full copy for paths without the gh-imgup skill or its
  `--help`. **This is the checklist to apply.** Don't substitute a softer or
  narrower review. Open each image and check it for:
  - API keys, tokens, passwords, session cookies, `.env` contents
  - Internal hostnames, IPs, private URLs, infrastructure details
  - Customer or personal data (PII), real names, emails, account numbers
  - Anything from a terminal, editor, browser devtools, or notification that
    wasn't meant to be shared

  If an image contains any of these, **do not upload it**: stop, tell the user
  exactly what you found and where, and ask them to crop, redact, or pick a
  different image. When in doubt, ask before uploading.

The `-y` flag skips npx's interactive first-run prompt. The CLI needs Node 22+.

It prints one Markdown image line per file to stdout, in argument order.
Progress goes to stderr, so captured stdout contains only the links.

Pass `--repo <owner>/<repo>` outside the target repository. Use `--pr <n>` or
`--issue <n>` only to post a follow-up comment.

`--help` lists all options and carries the same review. gh-imgup owns upload;
this skill only produces the files.

- **Place evidence in the PR description:** It is most visible there. Use a
  comment for later additions or issues.
- **Prefer upload-only:** Compose the returned Markdown into the body instead
  of leaving the evidence in a trailing comment.
- **Label every image:** Use **Before** and **After**, plus the state shown,
  such as "Empty state, dark mode."
- **Show both palettes:** Include light and dark when both appearances change.
- **Choose a concrete layout:** See
  `references/capture-craft.md` §display-layout for side-by-side and stacked
  layouts.
- **Verify the rendered result:** Do this only after every image passes the
  review and gh-imgup uploads it.
- **Check the rendered body:** Both images must load. Each label must sit with
  its image, and the pair must read from Before to After.
- **Trust the rendered view:** Correct raw Markdown can still produce a broken
  image or layout.

## Examples

See `references/capture-craft.md` §examples for a spacing-fix pair and a
net-new component shot.
