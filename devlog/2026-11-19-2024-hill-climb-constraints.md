# Record Climb Limits and Check In on a Repeated Unmeasured Fact

Issue #448 carries the contract. This extends the plateau rules in
`devlog/2026-11-18-2213-hill-climb-plateau.md`, which left the plateau and
budget counts as they are.

## Decisions

- **Chose a Constraints field apart from Guards.** Two council-scored idea
  climbs went wrong in opposite ways. One wrote its own hard rules into Guards,
  stricter than the project's written commitments, and its ideas were too
  narrow. The other carried no limits and accepted ideas that broke one the
  owner stated. Guards are checks on the artifact that must not regress;
  Constraints limit what a candidate may be. Owner limits are quoted in the
  owner's words, and each climber-added limit names its source and is never
  stricter than it, so sign-off covers both.
- **Chose a breach rule on every check tier over council only.** The issue
  proposed it for council. A program-scored climb can break an owner's limit
  too, and checking before scoring costs nothing. A breaching candidate is
  reverted or rejected unscored, so it never reaches a screen or panel and
  never counts as progress or the best near-miss.
- **Chose a check-in on a repeated unmeasured fact over a new stop rule.**
  In the second climb both judges named the same untested design question for
  two rounds while scores rose, so no stall fired and the budget went to ideas
  around that question. The climber now pauses and offers the measurement
  beside one more unit. It applies only when the panel's output has reasons,
  since council's Scoring Contract doesn't promise them; that contract stays
  unchanged.
- **Chose to log and continue for unattended runs.** An unattended run
  already logs stall proposals and keeps trying other kinds of change. It
  does the same with a measurement proposal and reports it. Rejected: a new
  stop, which would add a stop rule.
- **Chose to name single-source candidates at a set goal's stall.** In the
  first climb the climber wrote every candidate; the second started with four
  fresh-context generators, one lens each, and accepted more ideas. The stall
  check-in now names a single source and offers generators as a proposal.
- **Chose budget-counted runs that aren't units.** An approved measurement or
  generator run counts against the budget but is never a unit, so the plateau
  and budget counts don't change. Its cost is stated in the budget's own
  measure; when the budget counts only units, the owner says how much a run
  uses. A measurement's result reaches the panel only through later
  candidates' text, since the brief and rubric are frozen.

Revisit when council's Scoring Contract starts returning reasons or
candidates, or when a climb shows breach calls drifting stricter than the
quoted limits.
