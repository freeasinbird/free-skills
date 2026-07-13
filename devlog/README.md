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
