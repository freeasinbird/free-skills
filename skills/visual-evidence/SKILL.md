---
name: visual-evidence
description: >-
  Capture before/after screenshots of a UI change so a reviewer can see it, or
  check, review, and upload screenshots that already exist. Use this when
  implementing or reviewing a visual change (a UI bug fix, a
  CSS/layout/spacing/typography fix, a new component or screen, a theming
  change, or a visual regression), or when the user asks to "show the change",
  "add a screenshot", or "before/after". Also use it when you hold screenshots
  or screen recordings from any source (a project capture script, screenshot
  tests, the user, QA) and are about to put them on a PR or issue: "attach the
  screenshots", "upload the screenshots", or filling a PR's Screenshots
  section. Capture early: the fix often destroys the *before* state. Uploads
  use `gh --attach` or an installed gh-imgup. Reviewing each image for
  sensitive data before uploading is mandatory. Not for non-visual work
  (logic, backend, or docs with no output), an image that isn't rendered UI (a
  diagram or photo), or an explicit request to upload with gh-imgup.
---

# Visual Evidence

Capture screenshots that let a reviewer judge a visual change without reading
the diff, or check, review, and upload screenshots that already exist. Start
early because the _before_ state usually disappears when the fix lands. Upload
with `gh --attach`, or with an installed gh-imgup where gh can't; without
either, stop at local files and say so.

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

**Screenshots that already exist:** Start at step 6 when a project capture
script, screenshot tests, the user, or QA already produced the images, or when
you were given a recording or a single image. Steps 6 to 9 apply.

## When to Use It

Use it for any change judged by appearance, for a PR that changes rendered
UI, and whenever you hold screenshots or recordings bound for a PR or issue.
Suggest it proactively for visual work: capturing the _before_ is cheap now
and may be impossible later.

## When Not to Use It

- **Non-visual work:** Skip changes with no rendered output, including docs
  and comments that change nothing a user sees.
- **Explicit gh-imgup request:** Leave a request to upload with gh-imgup by
  name to that tool's own instructions. Its review of each image still comes
  before the upload.
- **Images that aren't UI evidence:** A diagram, a photo, or any other image
  that isn't a screenshot or recording of rendered UI is outside this skill.
  It still needs a sensitive-data review before anyone uploads it.

## Capture the Before/After

### 1. Decide Whether a Pair Is Warranted

Use a before/after pair for visible fixes and any layout, spacing, color,
typography, or restyle change; the difference is the evidence. Use a single
_after_ shot for net-new UI with no meaningful before state.

Before the first screenshot, choose a method that can reach the state:

- **Project capture tooling exists:** Use the project's own capture script or
  screenshot tests. They already encode its fixtures, devices, and states.
- **Fresh URL load reaches the state:** Use `capture.mjs`, or any tool that
  keeps the craft in steps 3 to 5.
- **State needs setup:** For clicks, login, or prior navigation, use a
  stateful browser or application test setup that can establish the state.
  Tool availability alone doesn't prove it can reach it.
- **No usable method:** Name the missing capability and uncaptured state.
  Don't present a closed menu, login page, or blank shot as the requested state.

Record the method and reproducible setup in a local `capture-recipe.md` by
`references/capture-craft.md` §capture-recipe, and replay it before each
capture. Keep the recipe out of publication text.

### 2. Capture the _before_ First

Capture this state before the fix exists: run the PR's merge-base, which
isn't always `main`, or stash the fix. Drive the app to the exact screen and
interactive state that shows the problem, then capture `before.png`. If the
fix is committed, rebuild the state in a separate worktree or checkout
instead of skipping the shot, such as `../before-state` from `<base-branch>`.
Remove that worktree once you've captured there.

### 3. Capture the _after_ Under Identical Conditions

Apply the change. Drive the app to the same screen and state, then capture
`after.png`. The change must be the pair's only visible difference.

- **Route, URL, and data:** Keep them fixed. Prefer seeded or fixture data to
  live or random data.
- **Viewport, DPR, and zoom:** Fix all three instead of using the current
  window settings. Default to 1280×720 or the app's design target, a mobile
  size such as 390×844 for a mobile change, and 2x DPR so text stays legible.
- **Responsive change:** Capture desktop and mobile as one viewport matrix
  when the tool supports it, not once per width, with a pair per width such
  as `before-1280x720.png` and `after-1280x720.png`.
- **Theme:** Capture separate light and dark pairs when both appearances
  change.
- **Interactive state:** Capture the default, hover, focus, active, error,
  empty, or loading state that demonstrates the change.

### 4. Framing & Cropping

- **Crop to the change:** Use the affected component or region unless the
  change is page-level. A full-screen shot buries the point in navigation and
  browser chrome, and a later turn may re-read every irrelevant pixel. Even
  for a page-level change, prefer the relevant section to the full page.
- **Prefer element capture:** It gives a tight, deterministic frame, such as
  Playwright's `locator.screenshot()` or a CDP clip to the node's bounding
  box. Otherwise crop both full images to one fixed rectangle; see
  `references/capture-craft.md` §crop-tools.
- **Keep useful context:** Add a little padding and one landmark, such as the
  component heading, so the change doesn't look like a floating fragment.
  Remove irrelevant sidebars and headers.
- **Match the pair:** Use the same rectangle, or the same element and
  padding, for both shots. An element's size may change when the fix
  changes it.
- **Keep inline images legible:** GitHub renders the PR body at roughly 830 CSS
  px wide. Avoid extreme ratios and multi-thousand-pixel captures. Keep each
  image under 10 MB, and never export SVG.

Any capture method that keeps tight framing, identical conditions, and
deterministic state will do.

### Reference Capture Script

Use `capture.mjs` with headless Chrome and Node 22+ when a fresh URL load
reaches the requested state. It starts a fresh browser profile; it doesn't
restore sessions or perform clicks, and waiting for a visible selector doesn't
establish interactive state.

Run it by path from the project directory that will hold the screenshots,
never from the skill directory: relative `--out` and `--chrome` paths resolve
from the working directory, and Compose and Attach won't find screenshots
written into a skill install. `<skill-dir>` is this skill's directory.

```sh
node <skill-dir>/capture.mjs --url http://localhost:3000/cards \
  --out after.png --viewport 1280x720,390x844 --wait-for '#card-list' \
  --clip '#card-list'
```

The script's header comment documents every option, its default, the output
names, and the exit codes. The options are `--url` and `--out` (required),
`--viewport`, `--wait-for`, `--clip`, `--clip-pad`, `--settle-ms`, `--dpr`,
`--dark`, `--timeout-budget`, `--attempt-timeout`, `--retries`, `--chrome`,
and `--chrome-flag`. Several viewports insert the size into the filename, so
use the names its `WROTE` lines report; they also give the dimensions for the
step 6 check.

On exit 69 (no usable Chrome or Node), the prose in steps 3 through 6 is the
specification. Apply the same craft with another capture method.

### 5. Determinism & Hygiene

- **Stabilize the page:** Disable animations. Wait for network idle and for the
  target element to become visible.
- **Set a wall-clock budget:** Agent shell tools commonly cap commands near two
  minutes, and a hung wait can consume that cap and return nothing. Keep the
  total budget below it, with per-attempt timeouts and retries, so a hang
  reports an error. `capture.mjs` uses 90 seconds.
- **Use stable data:** Prefer seeded or fixture data. Avoid timestamps, random
  values, and live customer data; fixture data also keeps secrets out of the
  frame.
- **Review separately:** Clean capture doesn't replace the mandatory review
  under Compose and Attach before every upload. Read it there instead of
  relying on memory.

### 6. Check the Shots Before Handing Off

Open every image, whether you captured it or were given it. Don't publish
evidence you haven't checked.

- **Reject blank or truncated shots:** An all-white or zero-size image may
  mean capture ran before render or matched no visible element. Correct the
  wait or selector, then capture again.
- **Check subject and state:** Confirm the intended screen, component, and
  interactive state appear. The change, or the problem a lone bug shot
  reports, must be visible.
- **Check comparability:** Match crop, viewport, and theme. When the pair
  doesn't line up, re-capture the odd image under the other's conditions.
  Read dimensions with ImageMagick `identify`, macOS
  `sips -g pixelWidth -g pixelHeight`, or the `WROTE` output. Fixed crops
  must match exactly; an element crop may change only as much as the fix
  explains, such as a padding fix changing height. Treat an unexplained
  difference as a non-comparable pair.
- **Reject absurd sizes:** Re-capture a multi-thousand-pixel-tall scroll or a
  sub-100px sliver that lost the subject.
- **Check a recording by watching it:** Confirm it shows the intended screen,
  state, and change. If you can't watch it, say so; the review under Compose
  and Attach treats it as flagged.
- **Skip pair checks without a pair:** A single image or a recording has
  nothing to match.

This is the capture-quality pass; the secret review under Compose and Attach
is separate.

Several checks above say to capture again. Sometimes you can't, because the
image was given to you or its state is gone. Don't publish a failing image on
your own judgment:

- **Project tooling produced it:** Re-run that tooling when a re-run can fix
  the failure, such as a blank shot. Then check the new image.
- **Nothing you can run will fix it:** Tell the user which image failed and
  why. Publish it only if they accept it as it is; otherwise wait for a
  replacement.

That acceptance covers this step's quality checks only. The review under
Compose and Attach keeps its own rule.

## Compose and Attach

Apply the review below to every image before running any upload command.
Then take the first upload path whose gate passes. Don't reimplement upload or
invent another host. A recording you were given counts as an image throughout
this section, unless a line says otherwise.

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

  A recording gets this checklist across its whole length, including any
  audio. One frame or a preview isn't a review. Treat a recording you can't
  inspect in full as flagged: say so, and ask before uploading.

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
   It accepts only images, so a recording goes to path 3 too.
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
elaborate. Use `gh pr edit --attach` for an open PR's description, and
`gh pr comment` or `gh issue comment` only for a later addition; see
`references/gh-attach.md` §commands.

- **Use Markdown image syntax only:** gh leaves a raw `<img src>` as written
  and appends the file at the end. Labels belong in the body's references;
  the `#alt` suffix on `--attach` names only an unreferenced file.
- **Attach each file once:** Every run uploads every `--attach` file again. A
  second `gh pr edit --attach` with the same file appends a duplicate.
- **Start every edit of an existing body from the live body:** `--body-file`
  replaces the whole body, so a fresh file sent to an open PR or an existing
  issue erases its description. Fetch it first, such as
  `gh pr view <n> --json body --jq .body > pr-body.md`. gh rewrites the body
  it sends, not the local file, so resending `pr-body.md` with `--body-file`
  alone overwrites the hosted URLs with local paths and breaks the images.
- **Respect gh's limits:** Images up to 10 MB (`png`, `jpg`, `jpeg`, `gif`,
  `webp`), video up to 100 MB, 50 files per command, checked by extension
  only. Never attach SVG: gh
  accepts it, but it can carry scripts, and gh-imgup refuses it for that
  reason.
- **Give a recording its own paragraph:** A recording you were given uploads
  on this path; read `references/gh-attach.md` §video first. Write
  `![label](./demo.mp4)` alone in its paragraph so GitHub renders a player,
  with its label in the paragraph above.

### Upload With gh-imgup

Pass images as positional arguments. Use `--pr <n>` or `--issue <n>` only to
post a follow-up comment.

```sh
# GITHUB_TOKEN set; add --repo owner/repo when the remote doesn't resolve
gh-imgup before.png after.png
```

It prints one Markdown image line per file to stdout, in argument order, and
progress to stderr; compose the stdout lines into the body. It needs Node
22+, and `--help` lists every option and carries the same review.

### Place and Verify

- **Place evidence in the PR description:** It is most visible there, on
  either path, instead of a trailing comment. Use a comment for later
  additions or issues.
- **Label every image:** Use **Before** and **After** for a pair, plus the
  state shown, such as "Empty state, dark mode." Label a single image by what
  it shows; don't add a second image to make a pair. Include light and dark
  when both appearances change. See `references/capture-craft.md`
  §display-layout for side-by-side and stacked layouts.
- **Verify the rendered result:** After every image passes the review and the
  upload succeeds, check the rendered body, not the raw Markdown. Every image
  must load, and a recording must show a player. Each label must sit with its
  image, and a pair must read from Before to After.

## Examples

See `references/capture-craft.md` §examples for a spacing-fix pair and a
net-new component shot.
