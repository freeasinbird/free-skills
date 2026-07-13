# Post-#63 cleanup: drain the 2026-07-08 marker-era queue

Post-merge cleanup of #63 surfaced the only marker-era entry with open
queue items, `2026-07-08-0919-devlog-protocol-v2.md`. Drains its three
survivors; the pre-marker-rule backlog stays out of scope (issue #64 now
tracks that audit). Owner decided each disposition.

## Decisions

- **Downstream-repo sync: declined, not escalated.** The item "sync the
  four downstream repos" is closed without an issue. Owner's call:
  downstream sync is handled per-repo, out of band, never queue-tracked or
  turned into a tracker issue. Marked `-> declined` in the source entry.
- **Legacy-queue audit: escalated to #64.** The one-time audit of
  free-skills' pre-marker-rule unmarked items is a real survivor; filed as
  a `deferral`-labeled issue carrying its `Source devlog entry`
  back-reference, dogfooding the contract #63 just shipped. Marked
  `-> Refs #64`; the `deferral` label was created in the repo (it lacked
  it).
- **Design lesson: promoted.** "Item-state semantics need one owner; a new
  state rule is done only when every consumer's predicate is checked
  against the full state matrix." It was filed conditionally ("if it
  recurs") and it recurred in #63 (rounds 5 and 8 were consumers,
  merge-cleanup and the recognition sites, not checked against the full
  drain-state matrix). Promoted to the devlog-README protocol (canonical
  scaffold + this repo's live copy) as a one-sentence editor guideline.
  Marked `-> promoted`.

## Drains

- Drains all three open items from `2026-07-08-0919-devlog-protocol-v2.md`
  (downstream sync -> declined, legacy audit -> Refs #64, design lesson ->
  promoted).

## Review

- Codex round 1, one P2, folded into the promotion commit: the promoted
  sentence itself under-enumerated the matrix, naming a marker-by-consumer
  check while the lesson's own bugs were drain-record states (legacy-prose
  vs labeled, open vs closed issue). Broadened the wording to include the
  drain-record forms in both the scaffold and the live README.

## Verification

- markdownlint, prettier, prose-tics, managed-sync, comparator green;
  `devlog/README.md` still byte-identical to the scaffold template after
  the promotion sync.
