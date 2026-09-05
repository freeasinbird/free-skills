# Match Prompt Audits to the Requested Operation

Chose an explicit audit endpoint over unconditional apply-and-ship instructions
in #243. A request for findings does not authorize payload changes, commits,
pushes, or a PR. An audit-and-fix request already authorizes clear scoped fixes;
a universal approval step would make that request needlessly stop twice.

The endpoint alone was insufficient. The whole-class guardrail and the
recorded-decisions wording clause also implied permission to edit. They now
preserve whole-class discovery for audits and allow fixes only within an
authorized editing scope. Auditors use non-mutating verification modes because
formatter output changes the payload that ships.

Prior decisions still govern substantive choices. An authorized wording
improvement may preserve a decided rule without another permission question.
It cannot silently reverse that rule or settle an unresolved judgment call.
Independent clear fixes can proceed while those choices reach the owner.

Kept the platform-neutral scope and delegation fallback recorded in the
[original skill decision](2026-07-01-1814-prompt-crafter-skill.md).
Kept the direct workflow sections chosen in the
[readability decision](2026-08-21-1617-readability-rule-map-format.md).
The live-example dispute remains owned by #174.

The evaluation pair holds the flawed payload family and host PR convention
constant, changing only the request. A third case separates independent fixes
and wording improvements from unresolved choices. A logging forge shim and
throwaway bare remote make the host handoff observable without live writes.
A blocked write still counts as an attempted mutation, so final diffs and
polished responses cannot substitute for raw tool records.

Kept audit checks separate from publishing their results to the simulated
forge. The default check prints its result without changing check state;
implementation uses an explicit `--record` call after committing. Recording
failed checks during audits would contradict their zero-mutation criterion.
Tool-call traces remain evaluation evidence, outside the graded forge state.

The local runner probe exposed a verification limit: an explicitly restricted
filesystem profile still allowed reading an outside temporary-file canary.
The fresh-context behavioral cases were withheld because the runner did not
meet the required isolation boundary. The passing forge smoke tests prove the
stub can perform the handoff, not that an agent chooses the correct route.
Issue #243 retains that acceptance gap until an isolated runner is available.

Fresh review also found that matching the submitted feature ref to a pushed
SHA did not prove the commit was made on that branch. The stub now checks the
current branch and preserves both initial main tips. Those conditions belong
in outcome grading too; a plausible PR response alone does not prove them.

Revisit when task-scoped evaluations show another instruction overriding the
requested operation, or when host verification tools cannot offer an audit-safe
mode. Do not respond by adding a universal approval gate.
