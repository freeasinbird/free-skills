# Reject Invalid Prompt Verification Inputs

The snippets now validate every shared-core boundary before comparing any
cores, and interpret grep's status explicitly. This preserves the
[original shared-core and exit-status decisions](2026-07-01-1814-prompt-crafter-skill.md)
while fixing the false passes tracked in #238.

Chose a validation pass followed by the existing sed extraction over a new
parser or temporary-file protocol. A sole missing-END file and matching
malformed files could pass before; mixed families usually failed as drift.
Validation now rejects all three as invalid input before parity comparison.
Inputs must remain unchanged across the two passes.

Fresh-context review found that Bash's `nullglob` option could skip both
loops for an empty family and return success. Count loop inputs explicitly
and include that Bash option in the regression matrix.

Chose guarded grep status capture over negation because grep returns 1 for
a successful search with no matches, but higher statuses for errors.
Negation accepts both. Guarding the command also lets clean inputs reach the
final status test under `set -e`. POSIX octal escapes replace hex escapes
so the pattern represents the intended character in both sh and Bash.

The regression extracts the shipped snippets by section and shell fence.
It rejects missing or ambiguous extraction and tests status, diagnostic
class, success continuation, and return to the caller. Separate fixtures
cover malformed input, directory read errors, and injected awk/sed errors.
No user's payload is a fixture.

## Cleanup Review

The harness removes only the directory returned by its own successful
`mktemp -d` call. The quoted path is assigned once, isn't input-controlled,
and is removed by an EXIT trap. Fresh-context review found no cleanup defect.
Scratch sentinel checks disproved the claim that cleanup removes a caller's
payload: the outside payload survived and the harness's temporary directory
was removed.

Revisit when the marker syntax, supported shells, or comparison semantics
change. This decision does not revise the taxonomy's live examples or audit
authorization policy.
