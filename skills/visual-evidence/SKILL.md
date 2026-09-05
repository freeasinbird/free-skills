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
  capture, getting a clean deterministic pair, framing/cropping tight), then
  uploads the finished images with `gh --attach`, falling back to an installed
  gh-imgup. Review each image for sensitive data before uploading; that step is
  mandatory here, and its checklist matches gh-imgup's bar. Not for non-visual
  work (logic, backend, or docs with no output), or for attaching an image
  that already exists.
---

# Visual Evidence

Capture screenshots that let a reviewer judge a visual change without reading
the diff. Start early because the _before_ state usually disappears when the
fix lands.

This skill owns capture timing and craft. It produces clean, tightly framed
evidence, then uploads it with `gh --attach`, or with an installed gh-imgup
where gh can't upload. Without either, it stops at local files and says so.

Follow this procedure:

1. Decide whether the change needs a pair or one _after_ shot, and choose a
   capture method that can reach the required state.
2. Capture the _before_ state before changing it.
3. Capture the _after_ state under identical conditions.
4. Frame both shots tightly and consistently.
5. Make the capture deterministic.
6. Open and check every shot.
7. Review every image for secrets and private data.
8. Upload and place the evidence.
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
- **Images already captured:** Run `gh pr comment --attach` or gh-imgup
  directly when you only need to attach existing images.

## Capture the Before/After

### 1. Decide Whether a Pair Is Warranted

- **Before/after pair:** Use one for visible fixes and any layout, spacing,
  color, typography, or restyle change. The difference is the evidence.
- **Single _after_ shot:** Use one for net-new UI with no meaningful before
  state.
- **Skip** entirely for non-visual changes (see When NOT to use it).

Before the first screenshot, including the _before_ shot, choose the method:

- **Fresh URL load reaches the state:** Use `capture.mjs` when appropriate.
- **State needs setup:** For clicks, login, or prior navigation, use an
  available stateful browser or application test setup that can establish and
  capture the state. Tool availability alone doesn't prove it can reach it.
- **No usable method:** Name the missing capability and uncaptured state.
  Don't present a closed menu, login page, or blank shot as the requested state.

Record the method and reproducible setup in local `capture-recipe.md` using
`references/capture-craft.md` §capture-recipe. Replay that setup before each
capture. Keep the recipe separate from publication text.

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
  Keep each image under 10 MB, and never export SVG; see the limits under
  Compose and Attach.

The named tools are examples, not requirements. Use any available capture
method that preserves tight framing, identical conditions, and deterministic
state.

### Reference Capture Script

Use `capture.mjs` with headless Chrome and Node 22+ when a fresh URL load
reaches the requested state. It starts a fresh browser profile; it doesn't
restore sessions or perform clicks. Waiting for a visible selector doesn't
establish interactive state. For state setup, follow the method decision above.

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

Apply the review below to every image before running any upload command.
Then take the first upload path whose gate passes. Don't reimplement upload or
invent another host.

- **Authorization:** Invoking this skill authorizes the upload once every image
  passes the review below. Don't ask the user for permission to run the upload
  command or to upload a reviewed image. Two things still override this: a
  request to keep the images local, which ends the work at the files, and an
  image the review flags. Stop and ask about a flagged image only.
- **Review each image before uploading, and not only for "secrets."** This
  review is mandatory here, on every upload path. Its checklist is held at
  gh-imgup's own bar. The review comes before upload because there is no
  un-publish. **This is the checklist to apply.** Don't substitute a softer or
  narrower review. Open each image and check it for:
  - API keys, tokens, passwords, session cookies, `.env` contents
  - Internal hostnames, IPs, private URLs, infrastructure details
  - Customer or personal data (PII), real names, emails, account numbers
  - Anything from a terminal, editor, browser devtools, or notification that
    wasn't meant to be shared

  If an image contains any of these, **do not upload it**: stop, tell the user
  exactly what you found and where, and ask them to crop, redact, or pick a
  different image. When in doubt, ask before uploading.

### Choose the Upload Path

Take the first path whose gate passes. GitHub Enterprise Server is a stop on
every path: keep the evidence local.

1. **`gh --attach`**, when all three hold: `gh --version` reports 2.99.0 or
   newer; `gh auth status` shows a user token, with a `gho_`, `ghp_`, or
   `github_pat_` prefix; the host is GitHub.com or GitHub Enterprise Cloud.
   In GitHub Actions, the default `GITHUB_TOKEN` isn't a user token, so skip
   to path 2 unless the workflow supplies a PAT. gh names a failed gate
   itself. On any of these errors, go to path 2:
   - `unsupported authentication type`
   - `attaching files requires write access to the repository`
   - `attaching files is not supported on GitHub Enterprise Server`
2. **gh-imgup, when it's already installed.** Check `command -v gh-imgup`, or
   `Get-Command gh-imgup` in PowerShell, then
   `npx --no-install @freeasinbird/gh-imgup`. It's recommended, not required.
   This is the path under the Actions `GITHUB_TOKEN`, where it's the only
   option that needs no extra secret, and on gh older than 2.99.0. It uploads
   only to `github.com`, so on GitHub Enterprise Cloud go to path 3 instead.
   Never download it with `npx -y`; an approval reviewer blocks an unknown
   package with credential access.
3. **Stop at local files.** Say so at handoff and name the fix: upgrade gh for
   interactive use; in CI, install gh-imgup or supply a PAT secret.

Pass `-R owner/repo` to gh, or `--repo owner/repo` to gh-imgup, when the
checkout's remote doesn't resolve to the target repository.

### Upload With `gh --attach`

Write the body first. Reference each file by its local path with Markdown
image syntax, then attach the same files:

```sh
cat > pr-body.md <<'EOF'
## Screenshots

![Before: cramped rows, light theme](./before.png)

![After: fixed padding, light theme](./after.png)
EOF
gh pr create --title "Fix card list padding" --body-file pr-body.md \
  --attach ./before.png --attach ./after.png
```

gh uploads each file and rewrites its reference to the hosted URL. Read
`references/gh-attach.md` §body-rewrite before composing anything more
elaborate than this.

- **Pick the command by target:** Use `gh pr create --attach` for a new PR,
  `gh pr edit --attach` for an open PR's description, and
  `gh pr comment --attach` or `gh issue comment --attach` for a later
  addition. See `references/gh-attach.md` §commands.
- **Use Markdown image syntax only:** Write `![label](./file.png)`. gh rewrites
  Markdown image and link nodes. A raw `<img src="./file.png">` is left as
  written and the file is appended at the end instead.
- **Put labels in the body references:** The `#alt` suffix, as in
  `--attach './after.png#After: empty state'`, applies only to a file the body
  doesn't reference. An in-body reference keeps its own alt text.
- **Attach each file once:** Every run uploads every `--attach` file again. A
  second `gh pr edit --attach` with the same file appends a duplicate.
- **Respect gh's limits:** Images up to 10 MB (`png`, `jpg`, `jpeg`, `gif`,
  `webp`), video up to 100 MB, 50 files per command, validated by extension
  only. Never attach SVG: gh accepts it, but it can carry scripts, and
  gh-imgup refuses it for that reason. Video is described in
  `references/gh-attach.md` §video and is outside this skill's procedure.
- **Pre-authorize on platforms with a command allowlist:** An operator can
  allow `gh pr create`, `gh pr edit`, `gh pr comment`, and `gh issue comment`
  for this path, and `gh-imgup` for the fallback. In Claude Code,
  `Bash(gh pr create *)` is one such rule; each platform has its own syntax.

### Upload With gh-imgup

Images are positional arguments. Upload-only means omitting `--pr` and
`--issue`.

```sh
# GITHUB_TOKEN set; add --repo owner/repo when the remote doesn't resolve
gh-imgup before.png after.png
```

It prints one Markdown image line per file to stdout, in argument order.
Progress goes to stderr, so captured stdout contains only the links. Compose
those lines into the body. Use `--pr <n>` or `--issue <n>` only to post a
follow-up comment. The CLI needs Node 22+. `--help` lists all options and
carries the same review.

### Place and Verify

- **Place evidence in the PR description:** It is most visible there. Use a
  comment for later additions or issues.
- **Compose into the body:** On either path, put the evidence in the
  description instead of leaving it in a trailing comment.
- **Label every image:** Use **Before** and **After**, plus the state shown,
  such as "Empty state, dark mode."
- **Show both palettes:** Include light and dark when both appearances change.
- **Choose a concrete layout:** See
  `references/capture-craft.md` §display-layout for side-by-side and stacked
  layouts.
- **Verify the rendered result:** Do this only after every image passes the
  review and the upload succeeds.
- **Check the rendered body:** Both images must load. Each label must sit with
  its image, and the pair must read from Before to After.
- **Trust the rendered view:** Correct raw Markdown can still produce a broken
  image or layout.

## Examples

See `references/capture-craft.md` §examples for a spacing-fix pair and a
net-new component shot.
