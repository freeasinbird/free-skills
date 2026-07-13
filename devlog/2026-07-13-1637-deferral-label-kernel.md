# Flow the deferral-labeling kernel back into agent-setup

Freeside escalates long-lived devlog deferrals to tracker issues carrying
a `deferral` origin label; only the generalizable kernel of that flows
back. agent-setup already had the escalation _mechanism_ (the `-> Refs #N`
marker, write-time / merge-cleanup triggers, the tracker-issue drain
record), so this is the labeling + provenance layer on top, not a
re-introduction.

## Decisions

- **`deferral` origin label + `needs-human` label.** Every escalated issue
  carries `deferral` so the deferred backlog is one issue query, not a
  devlog grep; maintainer-only items (repo settings, release-engineering,
  publishing) also take `needs-human`, never agent-selected work. The
  `needs-human` label lands on the maintainer-action clause the scaffold
  already singled out (user confirmed promoting it from a bare heading).
- **`Source devlog entry` field formalizes the issue end of the bridge.**
  The devlog end (`-> Refs #N`) already existed; the loose "naming ... its
  source entry" phrasing is swept to a named field so both ends grep.
  Ordinary, non-deferral issues omit it or write `none`.
- **Budget split by altitude.** AGENTS.md managed `devlog` block (loaded
  every session) gets a near-swap only; the substantive detail lands in
  the devlog-README scaffold, which is the protocol spec and not
  session-loaded. Canonical source and this repo's AGENTS.md copy edited
  together (dogfooding); `compare-managed-blocks.sh` reports `ok: devlog`.
- **Classification defers to the repo.** Past the `deferral` origin,
  categorization follows the target repo's _existing_ label practice or is
  omitted; agent-setup neither prescribes nor bans a taxonomy.
- **SKILL.md label audit (user confirmed).** Compact detect-report-offer
  for the two labels in Repo settings, GitHub-gated, so the first
  escalation isn't when a label is found absent.
- **No issue template (user confirmed).** `Source devlog entry` stays a
  body convention, not a scaffolded `.github/ISSUE_TEMPLATE`; a template
  would prescribe issue-management UI many single-maintainer targets don't
  want. No marker key added, so the comparator is untouched.

## Fenced off (deliberately not flowed back)

- **A classification taxonomy** (`kind:*` type, `lane:*` ownership) as
  mandate _or_ ban: the repo's own call. agent-setup stays silent beyond
  the generic `deferral` origin.
- **The multi-agent coordination apparatus**: pickup-authorization rules,
  waves / tracking-issue-per-wave / the `spine` role, contract
  serialization, the full work-unit issue-template field set (Contract /
  Acceptance / Declared paths / Dependencies). It assumes a parallel
  issue-driven coordination model most agent-setup targets (often
  single-maintainer) don't have, so it doesn't generalize.

## Review

- Codex round 1, two P2s, both confirmed and folded. **Class: a synced
  convention has more than two live copies.** The dogfood rule names
  canonical + AGENTS.md, but this repo's own `devlog/README.md` is a third
  live copy of the scaffold template, and AGENTS.md points to it as
  authoritative; editing the template and AGENTS.md alone left the live
  README contradicting the managed block. Fix: sync `devlog/README.md`
  with the same enrichment (folded into the scaffold commit); the drift is
  now zero against the template. Lesson worth promoting (see To promote).
- Codex round 2, one P2, confirmed and folded into the devlog-block commit.
  **Class: formalizing a match key silently coarsened its granularity.**
  Edit A's near-swap replaced "a tracker issue naming _that item_ and its
  source entry" with a match on the `Source devlog entry` field alone,
  which keys on the _entry_, not the item; an entry with several open
  bullets and one filed tracker would then read all its siblings as
  drained. Fix: restore the specific-item match in canonical + AGENTS.md
  (its `Source devlog entry` field pointing back to the item's entry), so
  the field adds provenance without loosening the drain unit. Scaffolding
  and README had kept the item match, so the fix realigns canonical to
  them rather than the reverse.
- Codex rounds 1,3-5, four P2s on the label-detection snippet, one class
  that widened each round until the right primitive closed it, folded into
  the SKILL.md commit. **Class: deciding label presence needs both the
  full set and proof of read access.** `gh label list` paged at 30 (round
  1); per-label lookups fixed paging but a 404 is overloaded (absent vs
  unauthorized), the repo-metadata preflight (round 3) proved the wrong
  scope, and reading exit code / stderr `HTTP 404` (round 4) still can't
  tell an access-404 from an absence-404 (round 5, since GitHub 404s
  unauthorized private-resource reads). Final: one paginated label read
  (`gh api --paginate .../labels`) is both the access proof (a successful
  read means label-read scope) and the complete set, so a name's absence
  is genuine and any read failure surfaces instead of driving a create.
  Confirmed against this repo (existing label -> exists, absent -> missing,
  inaccessible repo -> failure branch). Lesson: don't infer a semantic
  state from an overloaded error; get a positive read whose success is
  unambiguous.
- Codex round 5, second P2, confirmed. **Class: changing a recognition
  contract obligates every production site.** The new drain-record rule
  requires escalated issues to carry a `deferral` label and
  `Source devlog entry` field, but merge-cleanup (the skill that files
  survivor issues) still filed title/body-only issues, so a cleanup-filed
  survivor wouldn't match and later sessions could re-raise it. Fix: align
  merge-cleanup's create/search instructions to the same label+field
  contract (create the label if absent). await-pr-review's "escalate" is
  review-finding-only, not devlog issues, so it needed no change.
- Codex round 6, one P2, a completeness follow-on to round 5's
  merge-cleanup fix: it filed with both `deferral` and `needs-human` but
  only created `deferral` when absent, so a maintainer-only survivor in an
  un-audited repo would block on the missing `needs-human` label. Fix:
  create whichever label the issue will use. Swept the class: the only two
  sites that emit label-filing commands are this and the agent-setup audit
  (which already creates both); the write-time escalation is protocol
  prose with no command, so no sibling. Lesson: when a fix adds a second
  label to a create-if-absent step, the guard has to cover both.
- Codex round 7, two P2s (bare `gh label create` and fork/multi-remote
  repo targeting): one fixed, one declined. Fixed merge-cleanup: it is
  fork-aware (resolves a `<base-repo>` from the PR URL that can differ from
  gh's default) and files the survivor issue there, so the bare
  label-create could land the label in the fork while the issue is in the
  base; pinned the creates to `--repo '<base-repo>'`. Declined the same
  finding on agent-setup: its detect (`gh api repos/{owner}/{repo}/labels`)
  and the bare create resolve to the same current-repo context, and the
  whole Repo settings section targets that one repo with no base/default
  split, so pinning only the label create would be inconsistent. Evaluated
  on merits per the review-response convention, not reflexively applied.
- Codex round 8, one P2, confirmed, a design correction spanning five
  files. **Class: the new markers are production conventions, not
  recognition filters.** The edits had made a drain record require a
  `deferral` label (canonical/AGENTS) or `Source devlog entry` field
  (scaffolding/README/merge-cleanup lookup) and narrowed merge-cleanup's
  dedup search by the label, but survivors filed under the old rule carry
  neither, so recognition/search would miss them and duplicate or re-raise
  during migration. Fix: recognition matches by "names the specific item
  and its source entry" (legacy-safe, and still item-specific per round
  2); new escalations _carry_ the label (discoverability) and field
  (greppable provenance), which is exactly the kernel's framing (item 1
  discoverability, item 2 provenance), never a match filter. The reviewer
  cited only the merge-cleanup search; swept the whole class since every
  recognition site shared the over-reach.

## To promote

- Dogfooding sync is not "canonical + AGENTS.md"; it is "every live copy
  of the synced text." This repo's `devlog/README.md` is generated from
  `scaffolding.md` §devlog-readme, so a scaffold-template edit must move
  it too. The AGENTS.md dogfooding-conventions bullet enumerated only the
  managed-block pair.
  -> promoted in "Extend the dogfood sync rule to scaffolded files" (this PR)

## Verification

- `compare-managed-blocks.sh AGENTS.md` -> `ok: devlog`; `devlog/README.md`
  now byte-identical to the scaffold template body; markdownlint, prettier,
  prose-tics clean (full suite run at PR).
- The label/provenance flow is doc-only; untested until a real repo runs
  the escalation and the SKILL.md audit against a live GitHub label set.
