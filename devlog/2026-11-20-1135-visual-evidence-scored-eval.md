# Score visual-evidence with Stub Tools

Issue #441 built the scored eval that the `visual-evidence` size climb
(#442) holds. Eleven cases run against stand-in `gh`, `gh-imgup`, `npx`,
`curl`, and `node` commands, graded by program. The current skill scored
1.000 twice with a 0.000 band. Dropping `### Choose the Upload Path` scored
0.917 (0.875 in every repeat at an earlier freeze).

## Decisions

- **Chose stubs over real tools.** The runner gives a case no `node`, no
  Chrome, and no real `gh`, and every upload rule lives in prose, since no
  bundled script uploads. The `gh` stub follows gh 2.99.0's `--attach`: its
  version, token, permission, and Enterprise Server gates fail with gh's own
  errors, and it stores the body with each referenced local path rewritten.
  So a grader can read the description an agent's commands would leave.
- **Chose a `node` that returns pre-rendered images.** It checks
  `capture.mjs`'s options as the script does, reads the page the URL serves,
  and logs whether the page still had the bug. That grades capture order and
  matching settings, not crop or framing; `scripts/test-capture.sh` still
  tests the script.
- **Graded images by content as well as name.** A renamed or copied flagged
  image still fails, because the stubs log each file's SHA-256 before any
  gate runs.
- **Added a `curl` stub that refuses any URL off the machine.** The stub
  `gh` reports its host as GitHub.com so the gates read naturally, but every
  URL it prints is under `.invalid`. Refusing other hosts keeps a run that
  invents an upload host from reaching one, and fails that run. It lets
  `[::]` and `0.0.0.0` through, since a local `python3` server prints them;
  pre-push review found the first freeze failed such runs. It doesn't catch
  a URL without a scheme, and no run holds a credential.
- **Kept the stubs extensionless.** `scripts/check-skill-structure.sh` reads
  every `.sh`, `.mjs`, and `.js` file under the skill for flags, as the
  `land-approved-prs` eval found.

## Findings

- **One section separates the score, through one case.** Without
  `### Choose the Upload Path`, case 10 failed 5 of 6 runs across two
  freezes: on GitHub Enterprise Server the agent fell back to the installed
  gh-imgup and uploaded both images. The gap of 0.083 rests on that case
  alone, so a
  climb candidate that keeps the Enterprise Server stop but loses the rest
  of the path order scores the same as the baseline.
- **The review and authorization block is a blind spot.** With the lead
  block of `## Compose and Attach` removed, the score stayed 1.000: the
  frontmatter says the review is mandatory, and step 6 and the gh-imgup
  section repeat parts of it. Step 6 scored 0.958 without it, and two of
  its three repeats matched the baseline; its blank-image case passed every
  run. The proof record makes both rules climb constraints.
- **Case 16 can't see the non-user token rule.** The `gh` stub refuses a
  `ghs_` token as gh does, and the skill allows trying path 1 first, so the
  case grades the local fallback. The goal file keeps the rule stated.
- **The frontmatter carries much of the upload safety.** A frontmatter-only
  copy scored 0.542. It still held back the flagged image, rejected the
  blank one, and used the installed gh-imgup, but it uploaded on Enterprise
  Server, attached the SVG, and never captured anything.
- **Cost.** About $2.35 and 2 minutes per 24-run climb score with
  `--jobs 8`; $0.85 for the held-out split. Proving cost $13.85 at the
  first freeze and $7.77 at the second; the smoke test, $1.20.

The proof record, coverage map, and draft goal file are in
`~/.hill-climb/free-skills/visual-evidence-size/`. Any edit under
`skills/visual-evidence/evals/` after this note changes the check hash and
needs a new freeze and proof.

Revisit when `run-scored-eval.sh` changes its `PATH` or tools, or when
visual-evidence gains a bundled upload script.
