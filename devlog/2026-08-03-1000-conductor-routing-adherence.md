# Make conductor routing observable and structurally dominant

Recent Codex-app and Claude Code use was inconsistent about starting the
`await-pr-review` exchange in a subagent. The prior decisions made conductor
ownership the default, but the skill still contained competing instructions:
the main-owned no-model watcher was globally described as preferred, the
conductor gate alternated between mandatory isolation and isolation-or-
exclusivity, and only Claude Code received an explicit platform mapping.

## Decision

Eligible exchanges route to one conductor before any wait, CI check, or
feedback work. The gate remains four grants: write-capable delegation,
wait-and-resume continuity, completion notification, and either checkout
isolation or explicit shared-checkout exclusivity. Wait-and-resume continuity
means the same conductor can block through each bounded wait or receive a
scheduled wake without releasing ownership, then resume after surfaced
pauses. Codex app and Claude Code now have concrete mappings; invoking the
skill supplies the delegation request where host policy permits
skill-directed delegation.

Conductor ownership does not require a shell. A conductor runs the bundled
foreground watcher when a shell and host CLI exist, and otherwise reproduces
the same bounded detector contract through the available API or repository
connector. The transport changes, but the frozen baseline, expected head,
three observation sources, completion signals, and round-attribution rules do
not.

A main-owned exchange must emit
`Conductor skipped: <specific failed grant or allowed exception>.` before
starting its watcher. This makes legitimate fallbacks distinguishable from
prompt-adherence misses in future transcripts. The no-model watcher remains
the cheapest main-owned mechanism but is explicitly scoped to that fallback;
it no longer competes with the conductor decision.

The entry point is reduced below the skill-authoring limits (500 lines and
5,000 words). Detailed conductor, detection, and review-response mechanics
move to direct references with explicit read points. This changes routing and
loading structure, not the baseline, response, convergence, or reporting
semantics.

## Evaluation

`evals/routing-eval.json` records eligible and fallback scenarios for Codex
app, Claude Code, and generic agents. Eligible cases must choose the conductor
before a watcher or CI wait; fallback cases must name the failed grant. The
acceptance target is 100% on eligible cases, with at least 90% across repeated
fresh-context runs before prompt wording is accepted.

`scripts/test-await-pr-review-routing.sh` validates fixture structure and the
entry point's size and routing anchors. It derives the owner independently
from the grant booleans and trivial-feedback exception, so a mislabeled case
fails instead of grading itself. Model forward-tests remain evidence of
adherence rather than deterministic proof.

Before automated review, two fresh-context agents evaluated 11 held-out
presentations spanning Codex app, Claude Code, generic connector-only agents,
unrecorded reviewers, failed grants, substantial feedback, and the
trivial-feedback exception. All 11 selected the intended owner; all six
eligible presentations selected a conductor before watcher or CI work, and
all five main-owned presentations made the fallback observable.

Automated review then exposed three members of the connector-only lifecycle
class: the conductor first lacked executable detection, the added connector
loop assumed an ungranted delay mechanism, and the main-owned scheduled-wake
fallback still invoked the shell-only script. The widened gate now requires
wait-and-resume continuity, the conductor connector fixture explicitly
supplies a scheduled same-conductor wake, and the fallback fixture covers
instantaneous reads whose scheduling can re-enter only the main agent. The
main-owned ladder and scheduled-wake contract are transport-neutral, so that
fallback polls through the connector rather than handing control back.

The regression check requires the lifecycle contract in the entry point,
fixture derivation, and both execution references. Fresh-context routing
evaluation was not rerun for that widening because the active conductor
assignment prohibited delegation; the structural fixtures and mechanical
transport sweep are the available review-round evidence.

A fourth automated-review finding exposed a separate main-owned fallback
gap: a long round could request a fixer even when the conductor was skipped
because write-capable delegation was unavailable or forbidden. The fixer
choice now gates on delegation availability and permission before applying
its scale tests; otherwise the already-awake main agent handles the round. The
structural regression check requires that gate in the review-response
reference.

## Rejected alternatives

- **Add more repeated emphasis without restructuring.** Rejected because the
  skill had already grown to 1,041 lines; more duplicate prose would further
  lower adherence.
- **Require worktree isolation everywhere.** Rejected because Codex subagents
  can safely use a shared checkout when the main agent grants exclusivity for
  the exchange.
- **Prefer a watcher-only subagent.** Rejected because it keeps fix rounds and
  orchestration in the expensive main context. The desired default is the
  write-capable conductor; watcher-only delegation remains a main-owned
  fallback.

Revisit when: either platform changes its delegation, resumption, completion,
or checkout-isolation capabilities; or repeated routing evals fall below the
90% adherence threshold.
