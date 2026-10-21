# Read a Plan-Limit 403 on Branch Rules as No Queue

Chose to treat GitHub's plan-limit 403 on the branch-rules read as "no merge
queue" over keeping it a lookup failure. `land.sh` reads
`repos/{repo}/rules/branches/{base}` in `check`, `land`, and `merge`. On a
private repository whose plan lacks rulesets, GitHub refuses that read, so no
PR could land on Teloleo, Straylight, freeasinbird.com, or Canny. A Teloleo
landing batch stopped on it on 2026-10-21.

## Decisions

- **The refusal is an answer, not an unknown.** GitHub's docs give rulesets
  on private repositories only to Pro, Team, and Enterprise Cloud, and merge
  queues on private repositories only to Enterprise Cloud organizations. A
  repository that gets this refusal therefore can't have a queue. Protected
  branches have the same plan limit, so no classic rule can add one either.
- **Match gh's whole stderr, not a prefix.** The engine compares the captured
  stderr with the exact line gh 2.99.0 prints, which carries both GitHub's
  message and the 403. Any other 403 (token scope, SSO, permission), a 404, a
  5xx, extra stderr lines, or a changed message still stops with
  `LOOKUP_FAILED queue-rules`. If gh or GitHub rewords the line, the engine
  fails closed again rather than guessing.
- **Rejected: matching the error body on stdout.** The body is JSON whose
  `documentation_url` can change, and parsing it would need jq beside gh.
  The stderr line already holds the status and the message.
- **Rejected: a separate visibility or plan lookup.** Reading `private` and
  the owner's plan would add a second read that can disagree with the rules
  read. The rules read's own refusal is the most direct evidence.

## History

The retired self-merge engine read the same endpoint from c972a4e on. It
discarded stderr and never handled this response. The 2026-10-14 land-command
note chose `land` because these repositories have no branch protection, but no
landing batch had run on one until now. No other read in `land.sh`,
`list-ready.sh`, or `landed-since.sh` hits a plan-gated endpoint. The GraphQL
merge-queue fields `gh pr merge` reads return `false` and `null` on these
repositories, not an error.

## Refute-First Findings

A fresh-context reviewer tried to prove the change wrong.

- **Stale stderr on a later failure: confirmed, then fixed.** The first draft
  returned without clearing the capture file, so a later git failure in
  `land` quoted the plan-limit 403 as its cause. The path now clears it as
  `gh_read` does after a read that worked, and test-land.sh covers it.
- **A free organization answers differently: disproved by a check.** Live
  reads on free-plan organization and user repositories return the same
  single stderr line and exit 1.
- **A queue from classic branch protection: disproved by a check.** The
  protection and rulesets endpoints are plan-gated the same way on these
  repositories.
- **A plan-limit 403 on a later page after real rules: allowed.** The gate
  is per repository, so a first page can't succeed and a later one refuse.
- **A downgraded Enterprise Cloud organization: allowed.** Not checkable
  here. The docs offer private-repository queues only on Enterprise Cloud,
  and the GraphQL queue fields read false on these repositories.
- **Trailing newlines, CRLF, extra lines, and a failed `cat`: disproved by a
  check.** Each one matches exactly or fails closed.

## Revisit When

Revisit when gh changes its error format, when GitHub rewords the plan-limit
message, or when one of these repositories moves to a paid plan.
