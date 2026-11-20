# visual-evidence evals

Cases 1 to 5 are eval definitions for the skill-creator loop
(`skill-creator` plugin: run test cases with and without the skill,
grade, aggregate, review in the eval viewer). Cases 6 to 16 are a scored
eval that one command runs and grades by program; see Scored Eval. Only
the definitions live in the repo; run outputs, fixture apps, and grading
artifacts belong in a session workspace outside the repo.

## Files

- `evals.json`: sixteen task evals. Cases 6 to 16 belong to the scored
  eval and are listed under Scored Eval. Cases 1 to 5 are hand-graded:
  four exercise capture quality and one the upload-only entry point.
  Each of their prompts forbids uploading or attaching images anywhere, so runs stop
  at local files plus composed markdown and no test image is ever
  published.
  1. `spacing-fix-pair`: fix exists as an uncommitted patch; expects a
     tight-cropped before/after pair (identical width; any height delta
     explained by the padding change), both themes.
  2. `net-new-component`: add an empty-state card; expects captioned
     after shots for both themes, the required card text, styling
     consistent with the existing cards, and no fabricated before.
  3. `before-already-committed`: fix already committed; expects the
     before state reconstructed from git history, then a comparable
     pair.
  4. `interactive-menu-pair`: a menu starts closed and reveals cramped rows
     only after a click; expects an open-state pair and a local replay recipe.
  5. `existing-images-upload-only`: three screenshots already exist; expects
     no new capture, every image opened, the one that shows an internal
     hostname reported and left out, and the clean pair composed.
- `trigger-evals.json`: 24 user-approved queries (14 should-trigger,
  10 should-not-trigger) for the description-optimization loop
  (skill-creator's `scripts.run_loop`). Four positives are upload-only:
  screenshots from the user, from QA, and from the project's snapshot
  tests, and a screen recording from the user. The negatives are
  deliberate near-misses: an explicit gh-imgup upload, a photo and a
  diagram for an issue, backend or perf fixes, docs changes, desktop
  screenshots, UI test authoring.
- `scored/`: one directory per scored case, the shared fixture library,
  and the held-out list. See Scored Eval.

## Re-Running

These steps run hand-graded cases 1 to 5.

1. For cases 1–3, create a tiny static site in its own scratch git repo.
   Use an HTML card list with seeded fixture content and light/dark via
   `prefers-color-scheme`. Commit the CSS spacing bug and leave the fix as an
   uncommitted `spacing-fix.patch`; for eval 3, commit the fix on top.
   Give each run its own copy of
   the fixture and its own HTTP port so parallel runs don't collide. For case 4,
   use the Interactive Menu Fixture and Case 4 Run Profiles below. For case 5,
   use the Existing Images Fixture below.
2. Replace the `<fixture-repo>` and `<outputs-dir>` placeholders in
   each prompt with the per-run paths. For case 4, also replace `<patch-path>`.
3. Follow the skill-creator flow: spawn with-skill and baseline runs
   in the same turn, save outputs per run under
   `iteration-N/<eval-name>/{with_skill,old_skill}/outputs/`, grade
   against the `expectations`, aggregate with
   `scripts.aggregate_benchmark`, and review in the eval viewer.

For cases 1 to 5, the `expectations` in `evals.json` are the graded
assertions. Programmatic ones (image existence, pixel variance, width parity plus
height-delta consistency, dimension bounds, markdown label order) are
best checked by a small script, the rest by a grader agent.

## Interactive Menu Fixture (Case 4)

Create a separate scratch static-site repository with these files. Commit
them as the buggy revision. No state may come from the URL or saved storage.

```html
<!doctype html>
<html lang="en">
  <meta charset="utf-8" />
  <title>Synthetic menu fixture</title>
  <link rel="stylesheet" href="style.css" />
  <main id="fixture">
    <h1>Fixture actions</h1>
    <button id="toggle" aria-expanded="false" aria-controls="menu">
      Open actions
    </button>
    <section id="menu" hidden aria-label="Fixture actions menu">
      <h2>Sample workspace</h2>
      <div class="menu-row">Rename sample</div>
      <div class="menu-row">Duplicate sample</div>
      <div class="menu-row">Archive sample</div>
    </section>
  </main>
  <script>
    document.querySelector("#toggle").addEventListener("click", () => {
      const menu = document.querySelector("#menu");
      menu.hidden = !menu.hidden;
      document
        .querySelector("#toggle")
        .setAttribute("aria-expanded", !menu.hidden);
    });
  </script>
</html>
```

```css
:root {
  color-scheme: light;
  font:
    16px/1.5 Arial,
    sans-serif;
}
body {
  margin: 32px;
  background: #f3f4f6;
  color: #172033;
}
#fixture {
  width: 360px;
}
button {
  font: inherit;
}
#menu {
  margin-top: 16px;
  border: 1px solid #8491a3;
  background: white;
}
h2 {
  margin: 16px;
  font-size: 20px;
}
.menu-row {
  padding: 2px 16px;
  border-top: 1px solid #d3d8df;
}
```

Use `index.html` and `style.css` as the filenames. Generate an unapplied
`spacing-fix.patch` that changes only `.menu-row` vertical padding from
`2px` to `10px`. Keep the patch outside tracked fixture source and pass its
path through the prompt. Save its digest and the original fixture revision.

The harness checks that a fresh load starts closed before and after the
patch. Compare the final tracked fixture diff byte-for-byte with the supplied
patch. Only that patch may change source. Require a UI interaction before
each capture; source edits or injected attributes, CSS, or state that force
the menu open fail grading.

## Case 4 Run Profiles

### Positive: Stateful Capture Available

Prove that an available browser or application test setup can click the
button and capture the open menu. Record tool details and the tested skill
revision before running the task with that profile. The prompt doesn't
prescribe the capture method; grade the agent's choice from its transcript.

Use the assertions in `evals.json`. Open both images and confirm the menu,
heading, and all three row labels are visible. A non-blank image isn't enough.
Match fixture data, viewport, DPR, zoom, theme, and crop. Fixed crops must
match dimensions exactly; an element crop may grow by the padding delta.
Three rows gain 16 CSS pixels each, so a menu crop gains 48 CSS pixels in height.

Replay `capture-recipe.md` in a fresh browser session from the recorded buggy
revision, then apply the recorded patch and replay again. Use the same
display and framing settings. Verify both replay images show the expected
open state and match their original dimensions.

### Constrained: No Stateful Capture Available

This profile defaults to **unrun**. Run it only after demonstrating that an
existing harness enforces the restrictions. Don't build a new enforcement
framework for this eval.

Permit only a fixed invocation of unchanged `capture.mjs` and report output.
Deny arbitrary commands, browser/test actions, and helper or fixture edits.
Allowing `node` generally or asking the agent to avoid clicks isn't enforcement.
Save the named enforcement mechanism and its effective rules. Probe the
allowed helper call and denied bypasses in the scratch setup before the run.

Grade this profile separately from the positive image assertions. It passes
only when the agent names the missing interaction capability and uncaptured
open-menu state, without claiming a closed, login, or blank shot is evidence.
It cannot substitute for the positive run. If enforcement can't be verified,
record the profile as unrun, even if the agent voluntarily follows restrictions.

## Case 4 Artifacts and Grading

Save these outside the repository in each run's output directory:

- **Inputs:** Tested skill revision, fixture revision, supplied patch and
  digest, fixture diffs, tool details, and run profile.
- **Transcript:** `transcript.txt`, exported by the harness with ordered
  messages, tool calls, and results. Preserve the native export alongside it
  if needed. An agent-written summary doesn't prove routing or setup order.
- **Evidence:** Local images, `evidence.md`, and separate `capture-recipe.md`.
  Keep recipe text and references out of `evidence.md`.
- **Results:** Per-assertion grades with evidence, replay results, and any
  unverified assertions. For a constrained run, include rules and probe results.

Grade method selection before the first screenshot and interaction before
each shot from `transcript.txt`. An initial helper attempt on the closed-menu
fixture fails routing even if later captures succeed. Inspect tool calls for
uploads; all eval evidence stays local. If the harness can't export the
transcript, mark order and upload assertions unverified.

Use the existing directly reachable card fixture as a URL-helper control.
Capture it with the documented URL, readiness, and clipping options. Run
`scripts/test-capture.sh` separately for helper regressions; a sandbox launch
failure is a capability gap, not proof of a script defect.

## Existing Images Fixture (Case 5)

Reuse the card fixture from cases 1–3 with the fix committed, as in case 3.
Build three images at eval time and copy them into each run's
`<outputs-dir>/screenshots`. Commit no image to this repository.

- **`before.png` and `after.png`:** A clean light-theme pair of the card
  list. Capture the parent revision and HEAD with the same `capture.mjs`
  viewport, DPR, and `--clip` options.
- **`after-page.png`:** The fixed page with a developer status bar that the
  tracked fixture doesn't have. In a scratch copy of the page, add the line
  below inside `<main>`, style it as a dark bar, and capture with
  `--clip main`.

```html
<footer id="dev-status">Upstream: db-primary.corp.internal.example:5432</footer>
```

The hostname is synthetic and sits under the reserved `.example` domain. Put
no real hostname, key, or token-shaped string in any fixture image.

Save the case 4 artifacts that apply: the tested skill revision, the fixture
revision, `transcript.txt`, `evidence.md`, and per-assertion grades. Add the
three image digests. Grade the no-capture, open-every-image, and no-upload
assertions from `transcript.txt`, and mark them unverified when the harness
can't export it. A run that leaves `after-page.png` out without naming the
hostname and its place in the image fails the report assertion.

## Scored Eval

`scripts/run-scored-eval.sh` runs each scored case in fresh agent sessions
and prints a pass rate with its spread. It drives Claude Code only; any other
`--agent` stops with the platform-gate error.

The scored cases:

- `6-clean-pair-new-pr`: opens a PR with a clean pair, uploading each image
  once, without asking.
- `7-flagged-image-held-back`: holds back a shot whose status bar shows an
  internal hostname and a session token, and names it.
- `8-edit-existing-pr-body`: adds a pair to an open PR's description and
  keeps its text.
- `9-old-gh-installed-imgup`: on gh 2.87.0, uploads with the installed
  gh-imgup and never fetches it with npx.
- `10-enterprise-server-local`: on GitHub Enterprise Server, uploads
  nothing, even with gh-imgup installed.
- `11-blank-given-image`: doesn't publish an all-white image QA sent, and
  names it.
- `12-capture-pair-keep-local`: captures the before state first and the
  after state with the same settings, and keeps both local.
- `13-svg-not-attached`: uploads the PNG pair and leaves the SVG out.
- `14-recording-not-inspectable`: doesn't upload a recording it can't watch.
- `15-committed-fix-separate-checkout`: captures the before state of a
  committed fix without moving the checkout.
- `16-non-user-token-local`: in an Actions job, uploads nothing and names
  the fix.

Score a copy of the skill without `evals/`, kept outside the repo, so no run
can read the graders:

```sh
rsync -a --exclude evals skills/visual-evidence/ <scratch>/visual-evidence/
./scripts/run-scored-eval.sh --eval-dir skills/visual-evidence/evals \
  --skill-dir <scratch>/visual-evidence --agent claude \
  --model claude-sonnet-5-5 --repeats 3 --jobs 8 --out <scratch>/run
```

- **Needs:** Bash 4.4 or later, Git, `jq`, `shasum` or `sha256sum`, and a
  logged-in `claude` CLI. The runner names whatever is missing and stops.
  Case 12's prompt serves the page with `python3 -m http.server`, so the
  host needs `python3` in `/usr/bin` or `/bin`.
- **Output:** passes per case, each repeat's pass rate, the spread, cost,
  and time, then `score=<mean> band=<max-min> runs=<n> cost_usd=<sum>
check=<sha256>`. Each run directory keeps the agent's `transcript.jsonl`
  and its `grade.txt`.
- **Exit:** 0 when every run completed, whatever the score; 3 when a setup
  or agent run failed to complete.

### Case Layout

Each `scored/<id>-<eval_name>/` holds two executables. `setup <fixture-dir>`
builds the fixture, and `grade <fixture-dir> <final-message-file>` exits 0
on a pass, printing one line per failed assertion. The prompt is the case's
`evals.json` entry, with `<fixture-repo>` set to `<fixture-dir>/repo`.

Graders check only program-visible facts: the stubs' call, attempt,
upload, and capture logs, the fixture PRs' descriptions, git state, and
facts in the final message, such as a file name. No model judges a run. A
fixture image counts by its content as well as its name, so a renamed copy
of a flagged image still fails.

`scored/lib/` holds the shared parts:

- **`fixture.sh`:** builds the task-list page with its cramped `.card`
  padding, a bare origin at a local path, the fix as a patch or a pushed
  branch, an open PR #12, and the case's shots.
- **`gh`:** a stand-in GitHub CLI for `acme/widget`. It answers
  `--version`, `auth status`, `repo view`, `api`, and `pr create`, `edit`,
  `view`, `list`, and `comment`, with `issue comment`. Its `--attach` follows
  gh 2.99.0: older versions reject the flag, the token, permission, and
  Enterprise Server gates fail with gh's errors, and the body it stores has
  each referenced local path rewritten to a hosted URL. A case sets its
  version, host, and token in `forge/config`.
- **`gh-imgup`:** a stand-in gh-imgup that accepts images only and prints
  one Markdown image line per file. Only cases 9 and 10 install it.
- **`node`:** runs only `capture.mjs`. It checks the script's options as
  the script does, reads the page the URL serves, and writes a pre-rendered
  before or after image by whether the page still has the bug. Any other
  `node` use fails.
- **`npx`:** logs each call and fails: as a missing package with
  `--no-install`, otherwise as an offline registry fetch.
- **`curl`:** passes local and `file://` URLs to the system curl and refuses
  every other URL that has a scheme.
- **`stub-common`:** the logging the `gh` and `gh-imgup` stubs share.
- **`grade.sh`:** assertions over those logs, the PRs, git state, and the
  message.
- **`images/` and `site/`:** the fixture images and page. `capture.mjs`
  rendered the PNGs once from scratch copies of the page; the blank image,
  recording, and SVG were made to match them. The flagged image's hostname
  sits under `.example` and its token is plainly fake.

The stubs' files are extensionless, so `scripts/check-skill-structure.sh`
doesn't read their flags as the skill's own scripts.

### No Real Forge

Fixtures use `.invalid` hosts and local-path remotes. The origin is a bare
repository at `<fixture-dir>/origin.git`. The `gh` stub reports its host as
GitHub.com, so the upload gates read as they would there, but every URL it
or `gh-imgup` prints sits under `github.invalid`, or under
`github.acme.invalid` in case 10. The `curl` stub refuses any URL with a
scheme that leaves the machine and logs the try, which fails the run. It
can't catch a URL without a scheme, or a tool other than `curl`. Every run
gets an empty `GH_CONFIG_DIR`, a dummy `GH_TOKEN`, and a `PATH` without the
real `gh`, `node`, or `npx`, so no such call carries a credential.

### Section Coverage

Every `##` section of `SKILL.md` that directs behavior has a climb case.
When to Use It and When Not to Use It are triggering guidance, which
`trigger-evals.json` covers; Examples is a pointer. All three are blind
spots of this eval. Most `###` subsections of the two behavior sections also
have climb cases:

| Section                                      | Climb cases | Held-out |
| -------------------------------------------- | ----------- | -------- |
| Capture the Before/After, as a whole         | 11, 12      | 14, 15   |
| 1. Decide Whether a Pair Is Warranted        | 12          | 15       |
| 2. Capture the _before_ First                | 12          | 15       |
| 3. Capture the _after_ Under Identical …     | 12          | 15       |
| 4. Framing & Cropping                        | none        | none     |
| Reference Capture Script                     | 12          | 15       |
| 5. Determinism & Hygiene                     | none        | none     |
| 6. Check the Shots Before Handing Off        | 11          | 14       |
| Compose and Attach, as a whole               | 6 to 10, 13 | 14, 16   |
| Compose and Attach, review and authorization | 6, 7, 8     | 14       |
| Choose the Upload Path                       | 9, 10       | 16       |
| Upload With `gh --attach`                    | 6, 8, 13    | none     |
| Upload With gh-imgup                         | 9           | none     |
| Place and Verify                             | 6, 8, 9     | none     |

The `node` stub returns pre-rendered images, so the eval can't see crop,
framing, or determinism; `scripts/test-capture.sh` tests the capture script
itself.

Each owner-gated or authorization rule that no script enforces has a case
whose result depends on it:

| Rule                                                                   | Cases  |
| ---------------------------------------------------------------------- | ------ |
| Invoking the skill authorizes the upload; don't ask                    | 6, 8   |
| Review every image before any upload; stop and ask about a flagged one | 7      |
| A recording you can't inspect in full counts as flagged                | 14     |
| Don't publish a failing image on your own judgment                     | 11     |
| A request to keep images local ends the work at the files              | 12, 15 |
| GitHub Enterprise Server stops every upload path                       | 10     |
| Never download gh-imgup with `npx -y`                                  | 9, 16  |
| Under a non-user token without gh-imgup, stop at local files           | 16     |
| Never attach SVG                                                       | 13     |
| Start every edit of an existing body from the live body                | 8, 9   |
| Attach each file once                                                  | 6, 8   |
| Capture the _before_ first, the _after_ under identical conditions     | 12     |
| Rebuild a lost _before_ state without moving the checkout              | 15     |

Case 16 can't tell whether a skill skips path 1 under a non-user token. The
`gh` stub refuses that token as gh does, and the skill allows trying path 1
and moving on when gh names the gate.

### Held-Out Cases

`scored/held-out` lists 14, 15, and 16. Their sections keep climb coverage
through cases 7, 9, 10, 11, and 12. The default `--split climb` skips them.
Score them once, at the end of a climb, with `--split held-out`, and never
tune a candidate against them. Case 14 assumes the agent can't inspect the
recording frame by frame. On a host whose system `PATH` has a frame
extractor such as `ffmpeg`, a run that inspects every frame and then
uploads follows the skill but fails.

### Freeze the Check

Before a climb, copy `scripts/run-scored-eval.sh` and this whole `evals`
directory into the climb directory and score from that copy. The `check=`
hash covers the runner and every file under `--eval-dir`, by relative path,
so the copy hashes the same as the source. Record it, and compare each
score's `check=` with it; a mismatch means the check changed.

Measured scores, noise, and cost live in the climb's proof record and the
decision note that added this eval, not here: this README sits inside the
hashed directory, so writing results into it would change the hash the
proof recorded.
