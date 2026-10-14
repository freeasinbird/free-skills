# Start Projects from the Landing Rule

Issue #292 changes agent-setup's coordination defaults to rule 1 of the
parallel-work proposal (`docs/proposals/parallel-work-design.md`, #291, §4
step 4 and §6). Teloleo, Straylight, and future projects start from it.

## Decisions

- **Chose the landing baseline over the safe serial default.** Authorized
  units in isolated checkouts proceed unless a recorded dependency says
  otherwise, and the landing check is the baseline. This replaces the serial
  default chosen in
  `devlog/2026-08-15-1217-progressive-coordination-discovery.md`. An absent
  coordination record now means the landing baseline.
- **Dropped shape 5's repo-wide exclusivity.** The five-item mechanics list
  from `devlog/2026-08-18-2229-shape5-contract-exclusivity.md` went with the
  serialization it defined. Shape 5 keeps the integration spine and treats the
  shared contract as a review and declared-surface concern, matching the
  proposal's retained `kind:contract` review and declared paths. Landing
  catches a contract collision only when every consumer lives in the
  repository and the checks exercise it. Proposal §2.2 argues this for
  Freeside alone, so stored data and outside consumers keep a recorded start
  order.
- **Replaced the rule that serialized unknown relations.** An unresolved
  relation becomes a question for the owner or integrator in the work
  contract, and the unit proceeds under the landing check. No new wait rule
  replaces it.
- **Moved the base-moved recheck to the landing check.** Handoff step 3 and
  the pull-requests bullet now let a required check, merge queue, or land
  command rerun CI on the branch combined with the tip. After a conflicted
  rebase, the author reads `git range-diff` and records the resolution. A
  project without a landing check still repeats the recheck by hand; the core
  bullet says so too, because merge-and-resync and self-merge relied on it.
- **Kept a reader for each pushed refresh.** A landing check reruns CI, not
  review, and a clean rebase can follow an upstream rename. Proposal §6 lets
  the reviewer's pass on each push replace the author's diff review. The
  text keeps that condition: without a recorded automated reviewer, the
  author self-reviews the refreshed diff.

## Changed Assumption

The serial rules assumed conflicts must be prevented before a unit starts.
Proposal §5.1 showed the pre-start checks missed what mattered. Freeside's
`main` accepted untested combinations: two PRs adding the same struct field
merged 78 seconds apart and broke the build. Meanwhile contract units waited
in series with no recorded code dependence. A landing check catches the
combinations the pre-start comparison could not see.

## Planning Defaults Recorded as Decisions

The issue named four defaults the owner could reject; none was rejected.

1. **A project without a landing check** gets a setup finding and runs one
   unit at a time until the check exists. That fallback follows from an
   observable gap, not a default (proposal §4 step 4). Init writes it into
   the coordination record, because the skill's references never reach the
   project's own agents, so it looks for the check before its AGENTS.md
   write. Update mode only offers the record or a width-one change to an
   existing one: it changes unmanaged content on the owner's request alone,
   so a silent migration was rejected.
2. **Unknown review capacity** yields no width recommendation and a question
   to the owner. Until the owner gives a credible limit, their authorizations
   set how many units run. The capacity cap itself stays.
3. **Shape 5** keeps the integration spine and the shared-contract domain as a
   review and declared-surface concern.
4. **Step 3 still records the base commit** and prefers rebase for the refresh,
   so `git range-diff` applies.

The agent-setup evals still describe the serial baseline. Follow-up: #295.

## Revisit When

Revisit when a project's landing retries or rebase conflicts concentrate in a
few files (proposal §5.2). Fixing the file's structure is the first response,
but a recurring hot spot that resists restructuring may justify a recorded
start order or a narrower exclusion for that surface.
