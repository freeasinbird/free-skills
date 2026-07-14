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
# Decision notes

`devlog/` holds selective decision records, not session logs. Most
work leaves no note; AGENTS.md's Decision notes section defines when
one is warranted, this README defines the mechanics. The README and
AGENTS.md always hold current truth: if a note contradicts them, they
win; notes are the trail of how it got that way.

## Protocol

- **One file per note**, named `YYYY-MM-DD-HHMM-slug.md` using local
  24-hour time. Directory-of-notes (not a single file) so parallel
  branches and agent sessions add notes without merge conflicts, while
  same-day notes still sort in order.
- **At most one permanent note per work unit or PR** in the ordinary
  case. A note may evolve while its work unit or PR is active (in
  lockstep with branch rewrites; see fold-fix in AGENTS.md) and
  freezes when the PR merges; later corrections go in a new note,
  never edits to a frozen one.
- **Write for the future re-litigator**, not for someone following
  along. The decision sentence shape is "Chose X over Y because Z";
  name the decider when it isn't obvious (user choice, review finding,
  agent judgment). Record final rationale, rejected alternatives,
  changed assumptions, and verification findings that changed a
  decision or closed a risk; no chronology ("first tried..."), no
  commit diffs, no test transcripts, no PR status.
- **Add a "Revisit when ..." line** where a concrete condition would
  reopen the decision. It marks the decision's boundary, not open
  work: it needs no clock and no follow-up bookkeeping.
- **Actionable follow-ups live in the issue tracker.** When an issue
  originates from a note, link the note from the issue; the note may
  carry a plain `Follow-up: #N` historical link, but the issue, not
  the note, carries the status.

## Historical entries

Entries written under an earlier protocol (session bookends,
`## To promote` queues, `->` state markers) are frozen history: read
them as evidence when relevant, never mutate or reformat them, and
take no queue action from them; anything in one that is still
actionable belongs in the issue tracker.
```

---

## §pr-template

Target: `.github/pull_request_template.md`

```markdown
<!-- Title: imperative, ≤ 72 chars, names the outcome; it becomes the
     merge-commit subject, so write it for `git log --first-parent`. -->

## Why

<!-- One to three short prose sentences. Link the decision note when one
     exists; don't duplicate it. Add a close keyword immediately before each
     issue number the PR fully resolves or finishes: `Closes #11`, repeating
     the keyword to close several (`Closes #11, closes #12`), since a bare
     list `Closes #11, #12` closes only the first. Reference
     related-but-unfinished issues with a plain `#N` (e.g. `Refs #N`) and
     leave those for a human. -->

## What

<!-- Bullets required. Describe work-unit outcomes, not file-by-file churn.
     For multi-commit PRs, include a compact commit map, keyed by commit
     subject not SHA (folding review fixes rewrites SHAs). Say rejected
     alternatives live in the decision note when they do; don't duplicate
     them. -->

## Screenshots

<!-- Required for PRs with visible UI changes; delete for non-visual PRs.
     Replace this section with actual forge-hosted, reviewer-visible image or
     recording attachments before handing off, and in every case before merge.
     Local paths, textual descriptions, and "checked locally" notes do not
     satisfy this section. -->

## Review Notes

<!-- Optional. Delete this section if there is no useful routing guidance. -->

## Verification

<!-- Bullets required. Start each bullet with Passed:, Checked:, Attempted:,
     or Not run:. Say what was actually run and observed. Facts only, never
     "should work"; verification gaps are explicit Not run: bullets. -->
```

---

## §contributing

Target: `CONTRIBUTING.md`

```markdown
# Contributing

Development conventions (branch naming, pull requests, commits, build
commands, and coding standards) live in
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
