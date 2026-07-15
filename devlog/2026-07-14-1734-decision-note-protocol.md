# Replace session devlogs with selective decision notes

Owner decision (user-directed, from a four-repository audit): the
session-bookend protocol produced ~229 entries and ~105k words across
the sampled repos, with about half of non-merge commits touching a
devlog, and the marginal value did not justify one entry per session,
mandatory latest-entry reading, or the `## To promote` queue and its
marker state machine, which drifted and duplicated tracker state. The
demonstrated value (consequential decisions, direction-changing
discoveries, owner choices, high-risk verification conclusions,
multi-session context) is kept as selective decision notes.

## Decisions

- Chose selective decision notes with explicit triggers over keeping
  the queue with lighter markers: any in-devlog open-work state
  duplicates the issue tracker and needs a clock to stay honest.
  Actionable deferrals now go straight to the tracker; non-actionable
  observations become "Revisit when ..." conditions.
- Chose three agent-setup profiles (Standard / Decision-log /
  High-assurance) recorded as a plain `Agent-setup profile:` line in
  unmanaged AGENTS.md over a config or metadata file: one greppable
  line is enough for update-mode discovery, and a file would be a new
  state surface to sync.
- Kept `devlog/` as the directory name, `devlog` as the managed key,
  and the `YYYY-MM-DD-HHMM-slug.md` convention for compatibility;
  renaming would break downstream repos and history for no behavioral
  gain.
- Chose blanket anti-relitigation's replacement to be the
  owner-decision rule (identify the prior decision, state the changed
  assumption, surface the revision; never silently overturn), applied
  in the canonical devlog/reviewing sections and prompt-crafter.
- free-skills self-declares High-assurance; mandatory-note triggers
  are canonical-convention/scaffold changes, branch/PR/review/merge/
  release policy, destructive/credential/trust-boundary paths, and
  cross-project prompt decisions.
- No script changes: the comparator keeps the `devlog` key (this repo
  keeps its block; downstream Standard repos hit the tolerated
  missing-block path), and the prose-tics `devlog/` exclusion stays
  (historical entries remain frozen).
- Legacy-queue disposition (one-time, per the new migration guidance):
  the only item with no drain record was the needs-human upstream
  skill-creator bug report from `2026-07-01-2212-visual-evidence-eval`
  (carried in `2026-07-01-2351-net-new-eval-assertions`), now a
  tracker issue. Follow-up: #68. No `->` marker is appended to the
  frozen entries: the old protocol already accepts a tracker issue
  naming the item and its source entry as the drain record, and the
  new protocol forbids mutating history, so the marker never lands.
- This entry was written under the old protocol (the transition PR's
  required session entry) and is also the first High-assurance
  mandatory note (a canonical-convention change).

Revisit when: a downstream repo's migration surfaces a queue state the
one-time disposition guidance can't classify, or Standard projects
turn out to need durable rationale often enough that the
Decision-log default should be reconsidered.
