# Devlog protocol v2: drain markers, issue escalation, voice

A five-repo survey (straylight 81 entries, free-skills 55, gh-imgup 60,
freeasinbird.com 29, free-prompts 15) found the protocol healthy but
leaking in four places: Verification sections recapping what ran,
per-finding review replay (one 250-line entry), drained `## To promote`
headers matching the session-start grep forever, and drain phrasing too
varied to grep. straylight had already edited a frozen entry to mark an
item promoted (82188cb), a freeze violation that was the better
behavior; the protocol moves to it rather than outlawing it.

## Decisions

- **Queue items drain by `->` markers** appended in the source entry
  (promoted / re-deferred / declined / `Refs #N`); an unmarked item is
  open. Chose the append-only carve-out to the freeze rule over an O(1)
  queue-index file (Ben's call): no second artifact to drift, entries
  stay the single source. Drains the queue-index item deferred in
  2026-07-07-1213-context-discipline-section.md.
- **Devlog Verification records what verifying revealed**, not what
  ran; the run record lives in the PR body (Ben's pick over dropping
  the section). Review consolidation records finding classes and what
  verification refuted, never a per-finding replay.
- **Voice bullet**: write for the future re-litigator; "Chose X over Y
  because Z"; name the decider; no chronology or process narration.
- **Long-lived deferrals become tracker issues**: at write time when
  not expected to drain within a session or two; survivors at
  post-merge cleanup (merge-cleanup gains the step). A fresh item gets
  one PR cycle before escalating, so routine promotions stay
  issue-free.
- **Rejected: YAML frontmatter and a PR-number line** (Ben: wasted
  writes; the filename carries date/slug and `git log -- devlog/<entry>`
  recovers the PR).

## Review

- Codex rounds 1-2, three P2s confirmed and fixed, one class: prose
  state where the marker is the state. Round 1: merge-cleanup exempted
  items re-deferred "with reasoning", letting prose dodge escalation
  forever; exemption now requires an explicit `-> re-deferred` marker,
  which restarts the grace cycle. Round 2: write-time escalation said
  inline `Refs #N` while cleanup keys on `-> Refs #N` (would have filed
  duplicates), and the AGENTS.md managed bookends still said
  grep-and-re-defer without the marker, so a session following AGENTS.md
  alone would leave re-deferrals unmarked. Unified on the marker form
  everywhere; managed devlog and finish-line sections updated in the
  canonical source and repo copy together. Round 3: between a
  cleanup-filed issue and the next devlog PR the item is unmarked, so
  sessions would re-raise it; chose "the issue is the drain record
  until the marker lands" (the unmarked-item check consults the
  tracker) over cleanup opening a marker PR per run.
- Codex rounds 4-6, five more P2s, all confirmed and fixed, same class
  narrowing: the item-state predicates were coarser than the state
  machine (dedup ignored closed issues; the bookend stated
  unmarked-is-open without the drain-record exception; a `-> re-deferred`
  marker exempted forever instead of restarting the clock; an issue
  naming only the entry shadowed sibling items). Closed the class by
  enumerating the full state matrix (marker forms x consumers x drain
  records) instead of patching per finding; design lesson promoted below.

## Deferred

- Syncing the four downstream repos (straylight, free-prompts,
  freeasinbird.com, gh-imgup) waits for this PR to merge. straylight's
  sync should backfill `->` markers on its already-drained items;
  freeasinbird.com keeps its extra devlog/artifacts bullet.
  -> declined in 2026-07-13-1809-post-63-cleanup-drains.md (owner's call:
  downstream sync is handled per-repo, never queue-tracked or escalated to
  an issue)
- A legacy-queue audit of free-skills' older unmarked items; the
  merge-cleanup escalation step catches survivors from here on.
  -> Refs #64

## To promote

- The review's design lesson, if it recurs when another protocol grows
  state: item-state semantics need one owner (the README defines
  open/closed; every consumer defers to it), and a new state rule is
  done only when every consumer's predicate is checked against the full
  state matrix, not the instance that prompted it.
  -> promoted in 2026-07-13-1809-post-63-cleanup-drains.md (it recurred in
  PR #63 rounds 5 and 8; promoted to devlog/README.md and the scaffold)

## Verification

- Not run: the marker and escalation flow is untested until the first
  real drain and the first merge-cleanup run under the new rule.
