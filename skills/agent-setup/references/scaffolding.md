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
holds current truth: if an entry here contradicts it, the README wins;
entries are the trail of how it got that way.

## Protocol

- **One file per entry**, named `YYYY-MM-DD-HHMM-slug.md` using local
  24-hour time. Directory-of-entries (not a single file) so parallel
  branches and agent sessions append without merge conflicts, while same-day
  entries still sort in session order.
- **Revisable until merge, then frozen.** An entry may be revised or
  consolidated while its PR is unmerged (in lockstep with branch rewrites;
  see fold-fix in AGENTS.md). It freezes when the PR merges; later
  corrections go in a new entry. One append-only exception: the `->`
  queue-item state markers below. Everything else in a merged entry is
  never rewritten.
- **Checkpoint long sessions.** The unmerged entry may be written
  incrementally: at a natural checkpoint (a PR opened, a review round
  closed, a decision made), write or update it so a fresh session can
  resume from the entry plus the PR body instead of carrying the whole
  session forward. Revisable-until-merge covers these rewrites.
- **Write for the future re-litigator**, not for someone following along.
  The decision sentence shape is "Chose X over Y because Z"; name the
  decider when it isn't obvious (user choice, review finding, agent
  judgment), since whether a question may be reopened later hinges on it.
  No chronology ("first tried..."), no restating what the diff shows, no
  hedging or process narration.
- **Dense, not capped.** Record decisions, deferrals, and rejected
  alternatives, never narration; the mechanical what-changed lives in
  commits and per-thread dispositions in the PR. Target ≤ ~40 lines _per
  session-round_. An entry that consolidates many review rounds scales
  with the count of distinct decisions, recording finding classes, the
  design lesson, and what verification refuted (so it isn't re-raised),
  never a per-finding replay. If it's overflowing, check you're not
  transcribing commits or thread replies; cut those, not the decisions.
- **Structure is optional, but the queue header is canonical.** A short
  entry needs no sub-headers. When sections help, this set keeps the trail
  greppable: Decisions / Fixed / Deferred / Gotchas / Verification /
  `## To promote`. Use the exact `## To promote` spelling for the promotion
  queue so one grep finds it across every entry. Verification records what
  verifying revealed (a result that changed a decision, a flake or gotcha
  discovered, a gap deliberately left), not what ran; the run record lives
  in the PR body's Verification section and goes stale here.
- **Queue items drain by annotation.** When a queue item (a
  `## To promote` bullet, a deferral, a needs-human note) is dealt with,
  append a one-line `->` state marker to it in its source entry:
  `-> promoted in <commit or entry>`, `-> re-deferred in <entry>`,
  `-> declined in <entry>`, or `-> Refs #N` (escalated to a tracker
  issue). An item without a marker is open, and `-> re-deferred` only
  restarts the item's clock at the entry it names, it does not close the
  item: once the named entry has had its own cycle, the item is open
  again. The marker is the one
  permitted edit to a frozen entry and lands through a PR like any other
  change; the draining entry still names its source ("Drains
  `<entry-filename>`") so the record greps from both ends. Before
  re-raising an unmarked item, check for its drain record elsewhere:
  entries that predate this rule drain by reference in later entries, and
  a cleanup-filed tracker issue naming the specific item and its source
  entry (new ones via a `deferral` label and `Source devlog entry` field,
  older ones in prose), open or closed, is that item's drain record (never
  its neighbors') until the `-> Refs #N` marker lands in the next
  devlog-touching PR. This README owns the open/closed definition and every
  consumer (the session-start grep, cleanup's escalation, drain-record
  recognition) defers to it; when you add or change a drain-state rule,
  check each consumer's predicate against the full state matrix (every
  marker form and every drain-record form: a later entry, or a tracker
  issue that is legacy-prose or labeled, open or closed) across every
  consumer, not just the case that prompted it.
- **Session bookends.** The operational protocol lives in AGENTS.md's
  Devlog section: read the latest entries before starting; append an entry
  and drain the open `## To promote` / deferred / needs-human queue (or
  explicitly re-defer, marking the source item) before finishing.
- **Long-lived items become tracker issues, labeled by origin.** Promote
  anything load-bearing into README.md or AGENTS.md: the devlog is
  archaeology (grep it when re-litigating), never standing context. A
  deferral not expected to drain within a session or two gets a tracker
  issue when the entry is written, carrying its `-> Refs #N` marker from
  the start (the same form cleanup recognizes, so it is never
  re-escalated); an item needing a maintainer action you can't take (repo
  settings, release-engineering, publishing) always does, and takes a
  `needs-human` label (never agent-selected work). Every escalated issue
  carries a `deferral` origin label, so the deferred backlog is one issue
  query instead of devlog archaeology, and a `Source devlog entry`
  reference naming the entry filename (ordinary, non-deferral issues omit
  it or write `none`); with `-> Refs #N` at the devlog end, the record
  greps from both ends. Any categorization past the `deferral` origin
  follows the repo's existing issue-label practice, or is omitted where it
  has none. Post-merge cleanup files issues for items that outlive their
  PR cycle, so no item lives only under a heading the start-of-session
  protocol won't re-read.
```

---

## §pr-template

Target: `.github/pull_request_template.md`

```markdown
<!-- Title: imperative, ≤ 72 chars, names the outcome; it becomes the
     merge-commit subject, so write it for `git log --first-parent`. -->

## Why

<!-- One to three short prose sentences. Link the devlog entry when one
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
     alternatives live in the devlog when they do; don't duplicate them. -->

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
