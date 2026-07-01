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
- **Session bookends.** Before starting work: read the most recent one or
  two entries
  (`find devlog -maxdepth 1 -type f -name '*.md' ! -name README.md | sort | tail -2`),
  and grep for the open `To promote` / deferred / needs-human queue. Before
  finishing: append an entry, and drain what the current scope covers from
  that queue (or explicitly re-defer).
- Promote anything load-bearing into README.md or AGENTS.md — the devlog
  is archaeology (grep it when re-litigating), never standing context. An
  item needing a maintainer action you can't take (repo settings,
  release-engineering, publishing) gets a tracker issue, referenced from the
  devlog with `Refs #N` — not left only under a heading the start-of-session
  protocol won't re-read.
