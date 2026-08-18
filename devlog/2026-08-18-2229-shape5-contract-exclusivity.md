# Operationalize Shape-5 Serialization as Repo-Wide Exclusivity

Issue #135 makes coordination-discovery's shape 5 (integration spine or
shared-contract domain) define what "must change serially" means, instead of
leaving it as compliant-sounding prose a repo can satisfy while still
colliding.

## Decision

Shared-contract serialization means **repo-wide mutual exclusion** among
changes to the shared surface: at most one active contract change at a time,
checked against every other in-flight contract change before starting. The
failing reading it displaces is **per-unit ordering**: sequencing only each
unit's own contract change before that unit's own dependents. Per-unit
ordering passes a naive read of the old text yet lets several units each open
"its own serialized" schema change concurrently.

For the shared-contract-serialization case (not an integration-spine-only
model), shape 5 now also enumerates the five things the detailed-mechanics
project document must define: the surface as concrete paths and generated artifacts
(including downstream same-change sites like exhaustive-match sites and
generated consumers); the exclusivity rule with check-before-start,
wait-or-surface on collision, and a race-safe acquisition protocol (a
deterministic tie-break or an authority-granted lock, since forge
create-then-check is not atomic); a forge-visible enumeration of in-flight
contract changes registered before implementation begins, including a
directly assigned unit whose contract would otherwise stay in the prompt;
the registration lifecycle (when an entry joins and leaves the active set,
and how a stale or abandoned entry is released) so a dead lock neither
blocks the surface forever nor is bypassed by guesswork; and ordering relief
(an explicit chain, or one combined leading contract change) when several
planned units need the surface.

The marker/label form and tracker visibility stay project-derived; §freeside's
anti-copy rule is unchanged, so no default label vocabulary is prescribed.

## Evidence

teloleo ran exactly the per-unit rule: "a change to the shared runtime schema
types is its own PR, merged before dependent items adapt." On 2026-08-18 four
units each opened "its own serialized schema PR" concurrently (teloleo PRs 57,
58, 59, and 61; open windows 13:21–14:07Z, all touching `schema.py`),
colliding semantically: a `Manifest` extension plus a schema-version bump
against concurrent union growth, plus out-of-scope edits forced by
`assert_never` exhaustiveness sites. Textual merge tooling did not surface
these. teloleo has since rewritten its rule around a `contract` label with a
one-open-PR rule (teloleo PR #71 and its decision note).

## Rejected Alternatives

- **A default label vocabulary in the skill:** rejected. §freeside's
  derive-locally rule stands; prescribing a marker name would be the copied
  vocabulary that rule forbids. The mechanics name what a project must define,
  not the tokens it uses.
- **Placing the rule in `canonical-sections.md`:** rejected. The exclusivity
  mechanics are shape-5 project documentation guidance, not canonical managed
  workflow text every profile inherits verbatim; keeping it in
  coordination-discovery.md avoids the two-place managed sync and scopes it to
  the shape that needs it.

Revisit when downstream evidence shows one repo-wide active change is too
coarse for genuinely disjoint sub-surfaces (a project that can prove two parts
of its shared contract never co-change), which would argue for
per-sub-surface exclusivity rather than one surface-wide lock.
