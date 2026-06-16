# Scaffolding Files

Content for project files created during agent setup. Copy each section's
content verbatim into the target file. Skip creation if the target file
already exists.

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
- **Append-only.** Entries are never edited after their session ends.
  Corrections happen in a later entry.
- **Short.** Target ≤ 40 lines. Decisions and deferrals, not narration —
  commits and PRs carry the mechanical what-changed.
- **Session bookends.** Before starting work: read the most recent one or
  two entries
  (`find devlog -maxdepth 1 -type f -name '*.md' ! -name README.md | sort | tail -2`).
  Before finishing: append one.
- Promote anything load-bearing into README.md or AGENTS.md — the devlog
  is archaeology (grep it when re-litigating), never standing context.
```

---

## §pr-template

Target: `.github/pull_request_template.md`

```markdown
<!-- Title: imperative, ≤ 72 chars, names the outcome — it becomes the
     merge-commit subject, so write it for `git log --first-parent`. -->

## Why

<!-- One to three short prose sentences. Link the devlog entry when one
     exists; don't duplicate it. -->

## What

<!-- Bullets required. Describe work-unit outcomes, not file-by-file churn.
     For multi-commit PRs, include a compact commit map. Include rejected
     alternatives, or point to the devlog entry that records them. -->

## Screenshots

<!-- Required for PRs with visible UI changes; delete for non-visual PRs.
     Replace this section with actual GitHub-hosted, reviewer-visible image or
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

Start there.
```

---

## §claude-md

Target: `CLAUDE.md`

```markdown
# CLAUDE.md

The development guide lives in AGENTS.md:

@AGENTS.md
```
