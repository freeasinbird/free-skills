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
