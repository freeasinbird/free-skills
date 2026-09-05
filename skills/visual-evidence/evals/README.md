# visual-evidence evals

Eval definitions for the skill-creator loop
(`skill-creator` plugin: run test cases with and without the skill,
grade, aggregate, review in the eval viewer). Only the definitions
live in the repo; run outputs, the fixture app, and grading artifacts
belong in a session workspace outside the repo.

## Files

- `evals.json`: four task evals exercising capture quality. Each
  prompt forbids uploading or attaching images anywhere, so runs stop
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
- `trigger-evals.json`: 20 user-approved queries (10 should-trigger,
  10 should-not-trigger) for the description-optimization loop
  (skill-creator's `scripts.run_loop`). The negatives are deliberate
  near-misses: attach-an-already-taken image (upload alone, no capture),
  backend or perf fixes, docs changes, desktop screenshots, UI test
  authoring.

## Re-Running

1. For cases 1–3, create a tiny static site in its own scratch git repo.
   Use an HTML card list with seeded fixture content and light/dark via
   `prefers-color-scheme`. Commit the CSS spacing bug and leave the fix as an
   uncommitted `spacing-fix.patch`; for eval 3, commit the fix on top.
   Give each run its own copy of
   the fixture and its own HTTP port so parallel runs don't collide. For case 4,
   use the Interactive Menu Fixture and Case 4 Run Profiles below.
2. Replace the `<fixture-repo>` and `<outputs-dir>` placeholders in
   each prompt with the per-run paths. For case 4, also replace `<patch-path>`.
3. Follow the skill-creator flow: spawn with-skill and baseline runs
   in the same turn, save outputs per run under
   `iteration-N/<eval-name>/{with_skill,old_skill}/outputs/`, grade
   against the `expectations`, aggregate with
   `scripts.aggregate_benchmark`, and review in the eval viewer.

The `expectations` in `evals.json` are the graded assertions;
programmatic ones (image existence, pixel variance, width parity plus
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
