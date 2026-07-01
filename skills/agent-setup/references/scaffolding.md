# Scaffolding Files

Content for project files created during agent setup. Copy each section's
content verbatim into the target file. If the target file already exists,
don't recreate it: drift handling (compare against the template, show the
diff, offer to refresh) is defined in SKILL.md init step 5 and update
step 8.

---

## §devlog-readme

Target: `devlog/README.md`

```markdown
# Devlog

The reasoning trail. One short entry per working session: what landed,
what was decided (with the why and what was rejected), what was
deliberately deferred, open questions. The README is the spec and always
holds current truth — if an entry here contradicts it, the README wins;
entries are the trail of how it got that way.

## Protocol

- **One file per entry**, named `YYYY-MM-DD-HHMM-slug.md` using local
  24-hour time. Directory-of-entries (not a single file) so parallel
  branches and agent sessions append without merge conflicts, while same-day
  entries still sort in session order.
- **Revisable until merge, then frozen.** An entry may be revised or
  consolidated while its PR is unmerged (in lockstep with branch rewrites —
  see fold-fix in AGENTS.md). It freezes when the PR merges; later
  corrections go in a new entry. Never rewrite an already-merged entry.
- **Dense, not capped.** Record decisions, deferrals, and rejected
  alternatives — never narration; the mechanical what-changed lives in
  commits and per-thread dispositions in the PR. Target ≤ ~40 lines _per
  session-round_; an entry that consolidates many review rounds scales with
  the count of distinct decisions. If it's overflowing, check you're not
  transcribing commits or thread replies — cut those, not the decisions.
- **Structure is optional, but the queue header is canonical.** A short
  entry needs no sub-headers. When sections help, this set keeps the trail
  greppable: Decisions / Fixed / Deferred / Gotchas / Verification /
  `## To promote`. Use the exact `## To promote` spelling for the promotion
  queue so one grep finds it across every entry.
- **Session bookends.** The operational protocol lives in AGENTS.md's
  Devlog section: read the latest entries before starting; append an entry
  and drain the open `## To promote` / deferred / needs-human queue (or
  explicitly re-defer) before finishing.
- Promote anything load-bearing into README.md or AGENTS.md — the devlog
  is archaeology (grep it when re-litigating), never standing context. An
  item needing a maintainer action you can't take (repo settings,
  release-engineering, publishing) gets a tracker issue, referenced from the
  devlog with `Refs #N` — not left only under a heading the start-of-session
  protocol won't re-read.
```

---

## §pr-template

Target: `.github/pull_request_template.md`

```markdown
<!-- Title: imperative, ≤ 72 chars, names the outcome — it becomes the
     merge-commit subject, so write it for `git log --first-parent`. -->

## Why

<!-- One to three short prose sentences. Link the devlog entry when one
     exists; don't duplicate it. Add a close keyword immediately before each
     issue number the PR fully resolves or finishes (`Closes #11`; repeat to
     close several — `Closes #11, closes #12`; a bare list `Closes #11, #12`
     closes only the first). Reference related-but-unfinished issues with a
     plain `#N` (e.g. `Refs #N`) and leave those for a human. -->

## What

<!-- Bullets required. Describe work-unit outcomes, not file-by-file churn.
     For multi-commit PRs, include a compact commit map. Say rejected
     alternatives live in the devlog when they do; don't duplicate them. -->

## Screenshots

<!-- Required for PRs with visible UI changes; delete for non-visual PRs.
     Replace this section with actual forge-hosted, reviewer-visible image or
     recording attachments before merging. Local paths, textual descriptions,
     and "checked locally" notes do not satisfy this section. -->

## Review Notes

<!-- Optional. Delete this section if there is no useful routing guidance. -->

## Verification

<!-- Bullets required. Start each bullet with Passed:, Checked:, Attempted:,
     or Not run:. Say what was actually run and observed. Facts only — never
     "should work"; verification gaps are explicit Not run: bullets. -->
```

---

## §contributing

Target: `CONTRIBUTING.md`

```markdown
# Contributing

Development conventions — branch naming, pull requests, commits, build
commands, and coding standards — live in
[AGENTS.md](AGENTS.md). That file is the single source of truth for both
human contributors and automated agents.

## AI-assisted contributions

AI-assisted contributions are welcome when they are understood, reviewed, and maintained by the human contributor.

By opening a pull request, you are asserting that:

- You understand the change.
- You have reviewed the generated material for correctness, security, licensing, and fit.
- You can explain the implementation and respond to review.
- You are not submitting unmodified AI output that you cannot maintain.
- You have not knowingly included code or content that violates another project's license.

Maintainers may close AI-generated issues, pull requests, or comments that appear automated, low-context, unreviewed, duplicative, or unmaintainable.

AI may assist in the work, but you are accountable for it.
```

---

## §claude-md

Target: `CLAUDE.md`

```markdown
# CLAUDE.md

The development guide lives in AGENTS.md:

@AGENTS.md
```
