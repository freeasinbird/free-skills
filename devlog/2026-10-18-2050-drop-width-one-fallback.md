# Drop the Width-One Fallback for a Missing Landing Check

The owner rejected planning default 1 from
`devlog/2026-10-14-1438-landing-rule-baseline.md`: a project without a
landing check no longer runs one unit at a time. agent-setup now reports the
gap, offers the check, and leaves concurrency to the owner's authorizations
and the capacity cap.

## Decisions

- **Chose a finding plus the manual recheck over width one.** The risk a
  missing landing check creates is two PRs merging untested together. The
  managed pull-requests block already covers that at merge time: without a
  landing check, repeat CI, final diff review, and readiness by hand. Width
  one guarded the same race by serializing every start, which throttles all
  work to protect one step. Instead, merges alone run one at a time until the
  check exists, so two by-hand rechecks cannot pass against the same base.
  For now that rule shapes only the setup report; persisting it in the
  canonical pull-requests block is its own managed-policy change.
- **Kept the push toward a real check.** The setup finding and the offer to
  enable the up-to-date rule, a merge queue, or a land command stay. On
  GitHub the up-to-date rule is one setting, so the fix is usually cheaper
  than living with a fallback.
- **Wrote no record for the gap.** A missing check is a setup finding, not a
  coordination model, so init and update write no record or width because
  of it. Evidence for a richer model still gets its normal record. This also
  restores the plain rule that the landing baseline has no record.
- **Retired existing width-one records by proposal only.** Projects set up
  since 2026-10-14 may carry a record whose only basis is the missing check.
  Update mode and reassessment report it as obsolete and offer removal.
  Neither removes unmanaged content without the owner's approval.

## Rejected Options

- **Keep width one but make it opt-in.** It still frames serialization as the
  answer to a merge-time race, and the owner can already cap width through
  the capacity rule.
- **A softer cap, such as width two.** Any fixed number is arbitrary without
  capacity evidence, and the capacity rule already asks the owner for one.

## Changed Assumption

The earlier note treated width one as following from an observable gap rather
than being a default. But setup treats an unreadable setting or an unanswered
question as absent, so width one would also freeze parallel work wherever the
check merely went unconfirmed. The manual recheck already handled the merge
race in both cases.

## Revisit When

Revisit when a project without a landing check breaks its default branch
through an untested combination despite the manual recheck. The first
response is still enabling a landing check, not limiting starts.

Follow-up: #321
