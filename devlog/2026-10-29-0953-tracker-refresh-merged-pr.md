# Count Merged Pull Requests in Tracker Refresh

Chose an exact `MERGED` state with an empty normalized state reason as a
second way to count a unit or prerequisite as merged. This revises the
2026-10-14 rule, "Merged means closed with state reason `COMPLETED`", in
[Tracker Refresh Command](2026-10-14-1502-tracker-refresh-command.md).
Completed issues still count as merged; closed unmerged pull requests and
issues closed as not planned do not.

The old rule assumed prerequisites were issues. Freeside unit
[freeside-ai/freeside#2188](https://github.com/freeside-ai/freeside/issues/2188)
cites merged pull request #2169 in `starts-after`. GitHub CLI returns
`MERGED` with an empty state reason for a merged PR, so the old classifier
stopped the entire refresh. A read-only refresh of tracker #2386 now succeeds
and includes #2188 in its startable set.

Chose an exact match over accepting every `MERGED` state reason because an
unknown response must fail closed. Both units and prerequisites use the
classifier, so a merged PR listed as a unit also gains a tick and double
border. This follows the existing merged-unit rule rather than adding a
separate PR-only path. [Issue #358](https://github.com/freeasinbird/free-skills/issues/358)
carries the contract and implementation plan.

## Refute-First Findings

A fresh-context reviewer found no confirmed defect. Independent classifier
checks and the refresh regression cases resolved these claims:

- **Disproved by checks:** A PR closed unmerged could allow a start. Its
  `CLOSED` state with an empty reason remains unmerged.
- **Disproved by checks:** An open or draft PR could count as merged. An
  `OPEN` state remains open; draft status is not read by the classifier.
- **Disproved by checks:** Unexpected merged-state reasons or unknown states
  could pass. Nonempty reasons, including whitespace, unknown states, and
  lowercase `merged` exit 4. The match remains exact.
- **Allowed by existing decision:** A closed issue with reason `COMPLETED`
  counts as merged. The 2026-10-14 decision still applies to issues, while
  `NOT_PLANNED` remains unmerged.

Revisit if GitHub CLI changes the merged-PR response. The current exact match
will stop on an unfamiliar state rather than make a waiting unit startable.
