# Make skill-authorized conductor delegation explicit

The conductor gate already treated invocation of `await-pr-review` as the
delegation request, but its adjacent “higher-priority prohibition” sentence
left an ambiguous escape hatch. A general rule disabling proactive delegation
could be cited while ignoring its exception for an applicable skill that
explicitly requests delegation.

## Decision

Skill-mandated delegation satisfies a multi-agent rule whose exception allows
delegation requested by an applicable skill. It does not require a separate
user request. This interprets grant 1 of the existing four-grant conductor
gate; it does not add a fifth grant or change the platform capability checks.

A higher-priority prohibition can still fail grant 1, but the skip must
identify the rule's source when disclosure is permitted, or give a
non-sensitive paraphrase of its binding constraint otherwise, and explain why
none of its exceptions apply. The generic label “higher-priority instruction”
is not an auditable failed grant. The existing unavailable-or-forbidden
fallback fixture is narrowed to actual delegation unavailability so it does
not preserve the ambiguous escape hatch. A separate disclosure-restricted
fixture proves the audit requirement remains usable without exposing hidden
prompt text.

## Evaluation

The routing fixture now includes the exact precedence case: proactive
delegation is disabled by default, the user did not separately request a
subagent, the triggered skill explicitly requires delegation, all conductor
capability grants hold, and the expected first action is to spawn the
conductor before waiting. The structural test fixes those facts in place so
the case cannot silently regress into ordinary grant coverage. One
fresh-context forward run selected spawning the conductor as its first
ownership action for that exact scenario.

## Rejected alternative

More general warnings were rejected. One concrete precedence example, one
auditable but disclosure-safe skip requirement, and targeted regression cases
address the observed failure without competing with the four-grant route.

Revisit when: the host changes whether applicable skills can authorize
delegation, or routing evaluations show another distinct precedence failure.
