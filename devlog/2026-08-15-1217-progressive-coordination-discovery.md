# Derive Coordination from Current Evidence

Issue #122 adds progressive coordination discovery to agent-setup without
assigning projects a permanent topology or maturity label.

## Decisions

- Chose the smallest evidence-supported coordination model over a standard
  lane model. A fresh project stays serial; later capabilities can be skipped
  or combined because typed relations, named streams, and an integration spine
  solve different problems. A later owner-assigned reassessment may simplify
  the model.
- Chose an unmanaged, fixed-field AGENTS.md record over a ninth managed section
  or separate configuration file. The shape, evidence, mechanics pointer, and
  reassessment trigger are project-specific owner choices, extending the
  work-unit stage precedent in
  `devlog/2026-08-15-1013-staged-work-unit-records.md`. Absence remains the safe
  serial default.
- Kept the canonical managed blocks unchanged. Their existing concurrency,
  isolation, and declared-record gates are sufficient; putting a coordination
  shape into canonical text would impose project-specific structure during
  every sync.
- Treated plans as evidence rather than authority because plans may describe
  an intended architecture before code, history, and operating capacity can
  support it. Speculative plans cannot establish typed relations, named
  streams, or an integration spine by themselves.
- Required recurring work-unit or PR history for stable named streams. Rejected
  top-level directories as proof because code layout does not demonstrate a
  durable work boundary, ownership rule, or useful integration route.
- Modeled shared-contract serialization separately from component ownership.
  A component boundary does not make a shared contract safe for concurrent
  edits, while a designated integrator need not own every contributing
  component.
- Kept start order, merge order, intentional stacking, and mutual exclusion as
  distinct semantics when evidence requires typed relations. Rejected one
  overloaded dependency edge because it cannot tell an agent whether work may
  start, which branch to base on, or whether concurrent activity is forbidden.
- Used Freeside PR #801 as a calibration example, not a universal template. Its
  recurring streams, serialized contract chain, and integration role support
  its richer model; its lane names, labels, and vocabulary remain local.
- Capped proposed concurrency by review and integration capacity, not worker
  count alone. Parallel starts without credible review, CI, and integration
  throughput create an unowned queue rather than useful concurrency.

Revisit when agent-setup gains an owner-requested topology-reassessment
lifecycle, or when several downstream projects independently converge on
identical shape semantics that belong in a canonical managed gate.
