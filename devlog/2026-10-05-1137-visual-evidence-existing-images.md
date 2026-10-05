# Give visual-evidence the screenshots that already exist

Issue #287. visual-evidence now triggers when an agent holds screenshots of
rendered UI from any source and is about to put them on a PR or issue. This
revises the boundary drawn in `devlog/2026-06-26-1802-visual-evidence-skill.md`
and changes a credential-leak surface, which the project's mandatory-note list
includes.

## What Changed Since 2026-06-26

The 2026-06-26 note centered this skill on capture. It left "I have an image
to attach" to gh-imgup's skill, which then owned upload and the pre-upload
review. Two of its assumptions no longer hold:

- **The review and the first upload path live here.**
  `devlog/2026-09-03-0901-gh-attach-upload.md` made `gh --attach` the first
  path and moved the mandatory review into this skill. An agent sent away at
  "the image already exists" left the only text that carries the gates, the
  rewrite rules, and the review.
- **gh-imgup's skill is usually absent.** It wasn't installed in the
  downstream sessions #287 measured. Those sessions skipped this skill about
  half the time, then uploaded with no review, uploaded through an old path,
  or gave up.

## Decisions

The owner recorded the first two in #287 and assigned the work without a
veto. The agent made the rest during implementation.

- **Chose to own screenshots posted as review evidence, on either upload
  path, over keeping the boundary and fixing only the agent-setup text.** An
  agent decides from the skill listing at the upload moment. An exclusion in
  the description would still send it away, whatever a project's AGENTS.md
  says. gh-imgup's skill keeps explicit gh-imgup requests.
- **Chose to keep the trigger on screenshots and recordings of rendered UI
  over triggering on every image.** A diagram or photo needs the same review,
  and "When Not to Use It" says so. This skill's quality checks don't fit such
  an image, and a trigger on every image would fire on ordinary file handling.
- **Chose one procedure with a stated entry point over a separate upload-only
  section.** An agent with existing images starts at step 6. The review text
  exists once, ahead of every upload command, for both entries.
- **Chose a user override for a failed quality check over a hard stop.** An
  agent can't always capture a given image again. It re-runs project tooling
  when that can fix the failure. Otherwise it reports the image, and the user
  may accept it as it is. The override covers step 6 only; the sensitive-data
  review keeps its own rule.
- **Trimmed the description to stay under 1,024 characters.** Agent Skills
  cap a description there. The new trigger displaced two sentences: the one
  that listed what capture craft covers, and the one that compared the
  checklist to gh-imgup's bar. The body still states both. Naming screen
  recordings displaced the phrase "not just read the diff". The description
  is now 1,013 characters, so the next addition has to displace something.
- **Chose a comment on `freeasinbird/gh-imgup#100` over a new issue there.**
  #287 asked for an issue to narrow gh-imgup's description. Its sunset issue
  already lists that edit, so a second issue would duplicate it. The comment
  records the boundary this unit drew.

## Rejected Options

- **Keep the boundary and fix only the agent-setup text.** See the first
  decision.
- **Trigger on every image.** See the second decision.
- **A PowerShell variant of the fetch command.** Windows PowerShell 5.1
  writes UTF-16 through `>`. The command is labeled an example, and the
  section's first example is already a POSIX heredoc.

## Refute-First Findings

A fresh-context reviewer got the diff and the intended outcome, with
instructions to disprove three claims. The gh claims were checked against a
shallow clone of `cli/cli` at `v2.99.0`. No scratch PR was opened, so the
upload and the server side were not exercised.

- **Confirmed: the upload-only path reaches the review first.** The entry
  point leads to step 6. Step 6 points to the review, and the review opens
  Compose and Attach ahead of every runnable upload command.
- **Confirmed from source: gh never writes the body file back.** Each of the
  six commands reads `--body-file` with `cmdutil.ReadFile`. Neither those
  commands nor `internal/attachments` writes a file.
- **Confirmed from source: re-sending the original file overwrites the live
  body.** `gh pr edit` sends a supplied body as written. The reviewer found
  that an appended image is dropped, not replaced; the reference now says so.
- **Confirmed by a run: the fetch commands return the live body.**
  `gh pr view <n> --json body --jq .body` and its `gh issue view` form ran
  against this repository.
- **Confirmed from source, not run: adding one image leaves hosted URLs
  alone.** The rewrite edits byte ranges and skips remote destinations. gh's
  own test "a remote url is not touched" pins it.
- **Confirmed: the description excludes both cases the decisions leave
  out.** The 23 trigger queries of that draft match the description and both
  sections. The gh-imgup negative rests on the description's last clause,
  because the description also names gh-imgup as an upload path.
- **Disproved, then fixed: "the failed-check rule has an exit".** The first
  draft told the agent to re-run project tooling and otherwise wait for a
  replacement. A deterministic re-run reproduces the same failing image, and
  a user who wants a full-desktop bug shot posted had no way to say so. The
  rule now re-runs only when that can fix the failure and lets the user
  accept the image.
- **Disproved, then fixed: "step 6 is no weaker for fresh shots".** The
  first draft limited "capture again" to shots the agent can reproduce and
  named only given images in the don't-publish rule. A fresh shot whose state
  was gone fell under neither. The rule now covers any image the agent can't
  capture again.
- **Fixed: the gh-imgup exit dropped the review.** An agent already in the
  skill could read the bullet as leave to upload unreviewed. It now says the
  tool's review still comes first.
- **Fixed: a supplied recording had no review step.** "When Not to Use It"
  puts recordings of rendered UI in scope, while the review says "each
  image". The review itself now names recordings.
- **Allowed, then fixed in PR review: pair wording in checks that a single
  shot also passes through.** "The change must be visible" and "Both images
  must load" already met single _after_ shots before this change. The new
  entry point adds a case they never met: one supplied bug shot with no
  change and no pair. Steps 6 and 9 now state the single-image case, and the
  label rule says not to add a second image.
- **Allowed: the allow-rules bullet omits `gh pr view`.** It lists the
  upload commands; the fetch is read-only.
- **Fixed in PR review: recordings were in scope but not in the text.** An
  indexer reads only the description, which named no recordings, so a request
  to attach one could skip the skill and its review. The description, the
  entry point, and "When to Use It" now name them, and a 24th trigger query
  covers one. Compose and Attach counts a recording as an image. Its review
  covers the whole length and any audio, and treats a recording the agent
  can't inspect in full as flagged. A recording gets its own paragraph, and
  it stays local without `gh --attach`, because gh-imgup accepts only images.
- **Fixed in PR review: a fresh body file erased an existing description.**
  The only recipe wrote a new body, and the live-body rule covered later
  edits alone. An agent adding evidence to an open PR would have replaced its
  description. The rule now covers every edit of an existing body. A
  fresh-context refute pass on the recording text found this.
- **Not run: the trigger loop and the behavior evals' baseline.**
  `devlog/2026-07-01-2212-visual-evidence-eval.md` lists the harness defects
  that made earlier trigger runs misleading. The new negatives prove nothing
  until that loop runs.

Follow-up: `freeasinbird/gh-imgup#100`.

Revisit when gh-imgup's description narrows, changes, or is archived with
its repository; when a gh release changes how `--attach` treats the body
file; or when the description needs another trigger and has no room for it.
