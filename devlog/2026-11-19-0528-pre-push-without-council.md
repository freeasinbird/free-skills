# Drop Council From Pre-Push Review by Default

The owner decided that pre-push review should not run council by default and
that council should stay for hill-climbs and explicit requests. This reverses
the routing chosen in `2026-11-18-1926-pre-push-council.md` (#391), which sent
destructive-path, credential-leak, trust-boundary, and contract changes to
council. `docs/agent-workflow.md` §pre-push-review and its agent-setup scaffold
now give every covered change one fresh-context reviewer with the fixed brief.

## Decisions

- **Chose one fresh-context reviewer for all risk classes over a council
  panel per round.** Owner decision. A panel costs one high-effort run per
  member on every blocker round, and this procedure re-reviews until no
  confirmed blocker remains. The fixed brief and the evidence bar (count only
  reproduced or traced findings) stay, since they don't depend on council.
- **Removed the standing request and its delegate budget from the section.**
  With no council route, the bullet that made the section a standing request
  and an advance budget (`2026-11-18-2208-council-standing-request.md`) has
  nothing to cover. The rung 3 fallback from
  `2026-11-18-2250-lone-member-findings.md` goes with it.
- **Kept council's "When to Run" third requester.** A project may still name
  council for a class of work in its own instructions. The canonical
  procedure just no longer does. Council's skill and evals are unchanged.

The tracker #394 exit item "Pre-push review uses council for risk-class work"
no longer describes the canonical procedure; the owner decides how to close
it.

Revisit when a risk-class change ships a defect that a second provider's
review would likely have caught.
