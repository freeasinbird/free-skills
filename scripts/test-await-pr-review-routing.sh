#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
skill="$repo_root/skills/await-pr-review/SKILL.md"
eval_file="$repo_root/skills/await-pr-review/evals/routing-eval.json"
convergence_eval="$repo_root/skills/await-pr-review/evals/convergence-eval.json"
conductor="$repo_root/skills/await-pr-review/references/conductor.md"
cost_model="$repo_root/skills/await-pr-review/references/cost-model.md"
detection="$repo_root/skills/await-pr-review/references/detection.md"
review_response="$repo_root/skills/await-pr-review/references/review-response.md"

line_count=$(wc -l < "$skill" | tr -d ' ')
word_count=$(wc -w < "$skill" | tr -d ' ')

# SKILL.md is a routing core that must fit one bounded read (issue #202: about
# 200 lines). Mechanics and rationale belong in references/, reached through
# `references/<file>.md` §slug pointers, so a rule that needs more room moves
# there instead of raising these bounds.
if (( line_count > 220 )); then
  printf 'SKILL.md has %s lines; expected at most 220\n' "$line_count" >&2
  exit 1
fi

if (( word_count > 2000 )); then
  printf 'SKILL.md has %s words; expected at most 2000\n' "$word_count" >&2
  exit 1
fi

python3 - "$eval_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

cases = data.get("cases", [])
if not cases:
    raise SystemExit("routing eval has no cases")

ids = [case.get("id") for case in cases]
if any(not case_id for case_id in ids) or len(ids) != len(set(ids)):
    raise SystemExit("routing eval case IDs must be present and unique")

# Probe evidence maps to grants with the defaults SKILL.md documents (issue
# #208): only concrete absence fails a grant, and an unobserved probe takes
# the grant's default. A missing spawn tool fails delegation and completion;
# a spawn tool whose subagents cannot edit files or run commands fails
# delegation alone; a subagent with no wait mechanism fails wait-and-resume;
# a checkout the main agent must keep changing fails exclusivity.
PROBE_VALUES = {
    "spawn_tool_listed": {True, False, "unobserved"},
    "spawn_write_capable": {True, False, "unobserved"},
    "delegation_prohibition": {"none", "explicit", "unobserved"},
    "subagent_wait": {"shell", "scheduled_wake", "none", "unobserved"},
    "completion_signal": {
        "notification", "blocking_wait", "documented_absent", "unobserved",
    },
    "checkout": {"isolated", "shared", "unobserved"},
    "main_agent_must_change_checkout": {True, False},
}
PROBE_KEYS = tuple(PROBE_VALUES) + ("spawn_tool", "same_agent_resume")


def validate_probes(case_id, probes):
    if set(probes) != set(PROBE_KEYS):
        raise SystemExit(f"{case_id}: probes must carry exactly {PROBE_KEYS}")
    for key, allowed in PROBE_VALUES.items():
        if probes[key] not in allowed or type(probes[key]) is int:
            raise SystemExit(
                f"{case_id}: probe {key}={probes[key]!r} must be one of "
                f"{sorted(allowed, key=str)}"
            )
    if probes["spawn_tool"] is not None and not isinstance(probes["spawn_tool"], str):
        raise SystemExit(f"{case_id}: probe spawn_tool must be a tool name or null")
    # A tool name, "absent", or "unobserved"; only "absent" fails the grant.
    if not isinstance(probes["same_agent_resume"], str) or not probes["same_agent_resume"]:
        raise SystemExit(f"{case_id}: probe same_agent_resume must be a non-empty string")


def derive_grants(probes):
    spawn_tool_present = probes["spawn_tool_listed"] is not False
    return {
        "write_capable_delegation": bool(
            spawn_tool_present
            and probes["spawn_write_capable"] is not False
            and probes["delegation_prohibition"] != "explicit"
        ),
        "wait_and_resume": bool(
            probes["subagent_wait"] != "none"
            and probes["same_agent_resume"] != "absent"
        ),
        "completion_notification": bool(
            spawn_tool_present
            and probes["completion_signal"] != "documented_absent"
        ),
        "checkout_isolation": probes["checkout"] == "isolated",
        "checkout_exclusivity": bool(
            probes["checkout"] != "isolated"
            and not probes["main_agent_must_change_checkout"]
        ),
    }


for case in cases:
    grants = case.get("grants")
    if not isinstance(grants, dict):
        raise SystemExit(f"{case['id']}: grants must be an object")
    required = (
        "write_capable_delegation",
        "wait_and_resume",
        "completion_notification",
        "checkout_isolation",
        "checkout_exclusivity",
    )
    for grant in required:
        if not isinstance(grants.get(grant), bool):
            raise SystemExit(f"{case['id']}: {grant} must be boolean")

    expected = case.get("expected_owner")
    if expected not in {"conductor", "main"}:
        raise SystemExit(f"{case['id']}: invalid expected_owner {expected!r}")

    known_trivial = bool(
        case.get("review_already_in_hand")
        and case.get("known_trivial_feedback")
    )
    gate_holds = bool(
        grants["write_capable_delegation"]
        and grants["wait_and_resume"]
        and grants["completion_notification"]
        and (
            grants["checkout_isolation"]
            or grants["checkout_exclusivity"]
        )
    )
    derived_owner = "conductor" if gate_holds and not known_trivial else "main"
    if expected != derived_owner:
        raise SystemExit(
            f"{case['id']}: expected_owner {expected!r} conflicts with "
            f"derived owner {derived_owner!r}"
        )

    probes = case.get("probes")
    if probes is not None:
        validate_probes(case["id"], probes)
        derived_grants = derive_grants(probes)
        if derived_grants != grants:
            raise SystemExit(
                f"{case['id']}: declared grants {grants} disagree with "
                f"grants derived from probes {derived_grants}"
            )

    if expected == "main" and not (
        case.get("expected_fallback_gate") or case.get("allowed_exception")
    ):
        raise SystemExit(
            f"{case['id']}: main-owned case needs a fallback gate or allowed exception"
        )

eligible = sum(case["expected_owner"] == "conductor" for case in cases)
fallback = len(cases) - eligible

connector_only = [
    case for case in cases
    if case.get("host_access") == "connector"
    and case.get("shell_available") is False
]
if not any(
    case["expected_owner"] == "conductor"
    and case["grants"]["wait_and_resume"]
    for case in connector_only
):
    raise SystemExit("routing eval needs a connector-only conductor with wait continuity")
if not any(
    case["expected_owner"] == "main"
    and not case["grants"]["wait_and_resume"]
    for case in connector_only
):
    raise SystemExit("routing eval needs a connector-only main fallback without wait continuity")
if not any(
    case["expected_owner"] == "main"
    and (case.get("probes") or {}).get("spawn_write_capable") is False
    for case in cases
):
    raise SystemExit("routing eval needs a read-only delegation main fallback")

skill_authorization = next(
    (
        case
        for case in cases
        if case["id"]
        == "skill-authorizes-conductor-under-disabled-proactive-delegation"
    ),
    None,
)
if skill_authorization is None:
    raise SystemExit("routing eval needs the skill-authorized delegation case")
policy = skill_authorization.get("multi_agent_policy", {})
if policy != {
    "proactive_delegation_default": "disabled",
    "delegation_exceptions": [
        "the user explicitly requests delegation",
        "an applicable skill explicitly requires delegation",
    ],
}:
    raise SystemExit(
        "skill-authorized delegation case must state the disabled default "
        "and its applicable-skill exception"
    )
authorization = skill_authorization.get("delegation_authorization", {})
if authorization != {
    "user_requested_delegation": False,
    "triggered_skill": "await-pr-review",
    "triggered_skill_requires_delegation": True,
}:
    raise SystemExit(
        "skill-authorized delegation case must disable proactive delegation "
        "while making the triggered skill the authorization"
    )
if (
    skill_authorization["expected_owner"] != "conductor"
    or skill_authorization.get("expected_first_action")
    != "spawn_conductor"
):
    raise SystemExit(
        "skill-authorized delegation case must spawn the conductor before waiting"
    )

restricted_prohibition = next(
    (
        case
        for case in cases
        if case["id"]
        == "disclosure-restricted-prohibition-blocks-delegation"
    ),
    None,
)
if restricted_prohibition is None:
    raise SystemExit(
        "routing eval needs the disclosure-restricted prohibition case"
    )
if (
    restricted_prohibition["expected_owner"] != "main"
    or restricted_prohibition.get("prohibiting_rule_disclosure")
    != "restricted"
    or restricted_prohibition.get("expected_skip_explanation")
    != (
        "Conductor skipped: delegation is forbidden by a non-disclosable "
        "developer instruction whose exceptions do not include "
        "skill-mandated delegation."
    )
):
    raise SystemExit(
        "disclosure-restricted prohibition case must use a non-sensitive "
        "paraphrase and analyze the skill exception"
    )

context_cases = {
    "codex-app-shared-checkout-exclusive": {
        "control_available": True,
        "mechanism": 'fork_turns: "none"',
        "expected_mode": "fresh or empty",
    },
    "claude-code-worktree": {
        "control_available": True,
        "mechanism": "ordinary named background subagent",
        "expected_mode": "fresh",
        "experimental_fork": False,
    },
    "generic-inheritance-control-unavailable": {
        "control_available": False,
        "mechanism": "unavailable",
        "expected_mode": "inherited context may remain",
        "expected_notice": (
            "inheritance could not be controlled; continue with the compact "
            "self-contained brief"
        ),
        "optimization_gap_not_gate_failure": True,
    },
}
by_id = {case["id"]: case for case in cases}
for case_id, expected_context in context_cases.items():
    case = by_id.get(case_id)
    if case is None:
        raise SystemExit(f"routing eval needs initial-context case {case_id}")
    if case.get("expected_owner") != "conductor":
        raise SystemExit(f"{case_id}: context control must not change ownership")
    if case.get("initial_context") != expected_context:
        raise SystemExit(f"{case_id}: initial-context contract does not match")

# The 2026-09-01 audit failure (issue #208): Codex lists spawn_agent, the
# checkout is shared, resume continuity went unobserved, and the agent still
# must spawn a conductor rather than fall back to a main-owned watch.
codex_probed = by_id.get("codex-subagents-listed-routes-to-conductor")
if codex_probed is None:
    raise SystemExit("routing eval needs the Codex subagents-listed case")
codex_probes = codex_probed.get("probes") or {}
if (
    codex_probed.get("surface") != "codex-app"
    or codex_probes.get("spawn_tool") != "spawn_agent"
    or codex_probes.get("checkout") != "shared"
    or codex_probes.get("same_agent_resume") != "unobserved"
    or codex_probed["expected_owner"] != "conductor"
    or codex_probed.get("expected_first_action") != "spawn_conductor"
    or not codex_probed.get("forbidden_skip_reasons")
):
    raise SystemExit(
        "Codex subagents-listed case must probe spawn_agent on a shared "
        "checkout with unobserved resume, spawn the conductor first, and "
        "name the skip reasons it forbids"
    )

probed_owners = {
    case["expected_owner"] for case in cases if case.get("probes") is not None
}
if probed_owners != {"conductor", "main"}:
    raise SystemExit("routing eval needs probe-derived cases for both owners")

# An unobserved probe takes the grant's default, so a case whose wait, resume,
# completion, and checkout probes all went unobserved still spawns.
unobserved = [
    case for case in cases
    if case.get("probes") is not None
    and case["probes"]["subagent_wait"] == "unobserved"
    and case["probes"]["checkout"] == "unobserved"
]
if not any(case["expected_owner"] == "conductor" for case in unobserved):
    raise SystemExit("routing eval needs an unobserved-probes conductor case")

print(f"routing eval fixture valid: {len(cases)} cases ({eligible} conductor, {fallback} main)")
PY

python3 - "$convergence_eval" <<'PY'
import json
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

cases = data.get("cases", [])
presentations = []
for case in cases:
    presentations.append(case)
    presentations.extend(case.get("variants", []))

by_id = {case.get("id"): case for case in presentations}
if None in by_id or len(by_id) != len(presentations):
    raise SystemExit("convergence eval case and variant IDs must be present and unique")

rotation_ids = {
    "checkpoint-rotation-success",
    "rotation-without-checkpoint-go-refused",
    "rotation-unfavorable-cost-refused",
    "rotation-uncertain-cost-refused",
    "rotation-fresh-context-unavailable-refused",
    "rotation-checkout-transfer-unavailable-refused",
    "rotation-pointer-record-write-failure-refused",
    "rotation-reconciliation-record-write-failure-refused",
    "rotation-stale-pointer-record-refused",
    "rotation-replacement-prompt-missing-task-contract-refused",
    "rotation-forge-record-chat-only-material-refused",
    "rotation-unresolved-work-refused",
    "rotation-unresolved-decision-refused",
    "rotation-pending-push-refused",
    "rotation-watcher-overlap-refused",
    "rotation-acceptance-failure-refused",
    "rotation-activation-gap-interruption-rewaits",
    "rotation-old-completion-ambiguous-new-owner",
    "rotation-final-checkout-gate-failure-new-owner",
    "rotation-replacement-interruption-after-transfer",
}
missing = rotation_ids - by_id.keys()
if missing:
    raise SystemExit(f"convergence eval is missing rotation cases: {sorted(missing)}")

# rotation_ids must equal the rotation fixtures actually present, so a new
# rotation-* presentation added to the JSON without being registered here is
# not silently skipped by the classifier (which would void the unmapped-
# refusal guarantee below).
discovered_rotation_ids = {
    cid for cid in by_id
    if cid == "checkpoint-rotation-success" or cid.startswith("rotation-")
}
if discovered_rotation_ids != rotation_ids:
    raise SystemExit(
        "rotation_ids is out of sync with the fixtures; symmetric difference: "
        f"{sorted(discovered_rotation_ids ^ rotation_ids)}")

# State-derived properties: a rotation fixture is a refusal iff at least one
# declared prerequisite gate fails; the success fixture fails none; a post-
# transfer fixture already owns the exchange and checkout. A gate key absent
# from a fixture's state is unasserted, not a failure, so a new fixture must
# encode its failing gate in `state` or this classification names it.
# Single source of truth for the pre-transfer gates. Both gate_failures and
# required_success_keys derive from it, so a gate added here is enforced in
# every place at once (the head-match pair is a cross-field check below).
GATE_CHECKS = (
    ("checkpoint_call", lambda v: v == "go"),
    ("rotation_cost_comparison", lambda v: v == "favorable"),
    ("fresh_replacement_context_available", lambda v: v is True),
    ("existing_checkout_path_transferable", lambda v: v is True),
    ("durable_pointer_record_writable", lambda v: v is True),
    ("durable_pointer_record", lambda v: v != "write failed"),
    ("durable_reconciliation_record", lambda v: v != "write failed"),
    ("pending_push", lambda v: v is False),
    ("active_watcher", lambda v: v is False),
    ("undispositioned_findings", lambda v: v == 0),
    ("unresolved_decisions", lambda v: v == 0),
    ("forge_record_contains_chat_only_material", lambda v: v is not True),
    ("private_replacement_prompt_current_task_contract_present",
     lambda v: v is not False),
    ("live_reviewer_state_matches_pointer_record", lambda v: v is not False),
    ("provisional_checkout_inspection", lambda v: v != "failed"),
)
def gate_failures(state):
    fails = [key for key, ok in GATE_CHECKS
             if key in state and not ok(state[key])]
    if ("pointer_record_head" in state and "live_head" in state
            and state["pointer_record_head"] != state["live_head"]):
        fails.append("pointer_record_head")
    return fails

# The success fixture must model every rotation prerequisite; because
# gate_failures ignores absent keys, deleting one would otherwise leave it
# silently unasserted, so require the full key set before checking values.
# Derived from GATE_CHECKS so a newly added gate is automatically required in
# the success fixture; the head-match pair and the two cost-proxy fields are
# not in GATE_CHECKS, so name them here.
required_success_keys = {key for key, _ in GATE_CHECKS} | {
    "pointer_record_head", "live_head",
    "expected_more_blocker_rounds", "conductor_replay_strain",
}

# Each refusal fixture must fail exactly the gate(s) its ID and expected
# action name, so drift to a different gate is caught rather than passing on
# "any gate fails". A new refusal without a mapping trips the classifier.
REFUSAL_EXPECTED_FAILURES = {
    "rotation-without-checkpoint-go-refused": {"checkpoint_call"},
    "rotation-unfavorable-cost-refused": {"rotation_cost_comparison"},
    "rotation-uncertain-cost-refused": {"rotation_cost_comparison"},
    "rotation-fresh-context-unavailable-refused":
        {"fresh_replacement_context_available"},
    "rotation-checkout-transfer-unavailable-refused":
        {"existing_checkout_path_transferable"},
    "rotation-pointer-record-write-failure-refused": {"durable_pointer_record"},
    "rotation-reconciliation-record-write-failure-refused":
        {"durable_reconciliation_record"},
    "rotation-stale-pointer-record-refused":
        {"pointer_record_head", "live_reviewer_state_matches_pointer_record"},
    "rotation-replacement-prompt-missing-task-contract-refused":
        {"private_replacement_prompt_current_task_contract_present"},
    "rotation-forge-record-chat-only-material-refused":
        {"forge_record_contains_chat_only_material"},
    "rotation-unresolved-work-refused": {"undispositioned_findings"},
    "rotation-unresolved-decision-refused": {"unresolved_decisions"},
    "rotation-pending-push-refused": {"pending_push"},
    "rotation-watcher-overlap-refused": {"active_watcher"},
    "rotation-acceptance-failure-refused": {"provisional_checkout_inspection"},
}

# Exact passing value for every success gate. The gate_failures predicates are
# fail-open (e.g. `v is not True`, `v != "failed"`), so a success gate set to
# JSON null would pass without asserting the prerequisite; the success fixture
# must therefore match these exact values. Keys are asserted equal to
# required_success_keys so a gate added to GATE_CHECKS without a passing value
# here (or vice versa) trips.
SUCCESS_GATE_VALUES = {
    "checkpoint_call": "go",
    "rotation_cost_comparison": "favorable",
    "expected_more_blocker_rounds": True,
    "conductor_replay_strain": True,
    "fresh_replacement_context_available": True,
    "existing_checkout_path_transferable": True,
    "durable_pointer_record_writable": True,
    "durable_pointer_record": "written",
    "durable_reconciliation_record": "written",
    "pending_push": False,
    "active_watcher": False,
    "undispositioned_findings": 0,
    "unresolved_decisions": 0,
    "forge_record_contains_chat_only_material": False,
    "private_replacement_prompt_current_task_contract_present": True,
    "live_reviewer_state_matches_pointer_record": True,
    "provisional_checkout_inspection": "passed",
    "pointer_record_head": "deadbeef",
    "live_head": "deadbeef",
}
if set(SUCCESS_GATE_VALUES) != required_success_keys:
    raise SystemExit(
        "SUCCESS_GATE_VALUES keys must equal required_success_keys; symmetric "
        f"difference: {sorted(set(SUCCESS_GATE_VALUES) ^ required_success_keys)}")

post_transfer_ids = {
    "rotation-old-completion-ambiguous-new-owner",
    "rotation-final-checkout-gate-failure-new-owner",
    "rotation-replacement-interruption-after-transfer",
}
# Activation-gap fixtures sit between release-ack and the activation message:
# ownership has transferred (the replacement owns exchange and checkout) but
# activation has NOT been received, so step-5 recovery has not begun and the
# replacement must only re-wait, never run a watcher or the checkout gate.
# They are neither refusals nor post-transfer (post-transfer requires
# activation received), so they classify and assert separately.
activation_gap_ids = {
    "rotation-activation-gap-interruption-rewaits",
}
for case_id in sorted(rotation_ids):
    fixture_state = by_id[case_id].get("state", {})
    fails = gate_failures(fixture_state)
    if case_id == "checkpoint-rotation-success":
        missing_keys = required_success_keys - fixture_state.keys()
        if missing_keys:
            raise SystemExit(
                "success fixture must declare every rotation gate; "
                f"missing: {sorted(missing_keys)}")
        # Type-strict: `False == 0` and `True == 1` in Python, so compare type
        # as well as value, or a bool gate set to 0/1 (or an int gate set to
        # false/true) would silently satisfy its exact-value assertion.
        wrong = {
            key: fixture_state[key]
            for key, want in SUCCESS_GATE_VALUES.items()
            if fixture_state[key] != want
            or type(fixture_state[key]) is not type(want)
        }
        if wrong:
            raise SystemExit(
                "success fixture must hold each gate's exact passing value "
                f"and type; wrong: {sorted(wrong)}")
        if fails:
            raise SystemExit(
                f"success fixture must pass every rotation gate; failed: {fails}")
    elif case_id in post_transfer_ids:
        if fixture_state.get("replacement_owns_exchange_and_checkout") is not True:
            raise SystemExit(
                f"{case_id}: post-transfer fixture must own exchange and checkout")
        # Step 5 (checkout gate, ambiguous-completion or interruption recovery)
        # begins only after the activation message, so a post-transfer fixture
        # must declare activation received; otherwise it would bless owning
        # recovery actions during the activation gap the conductor forbids.
        if fixture_state.get("activation_received") is not True:
            raise SystemExit(
                f"{case_id}: post-transfer fixture must declare activation "
                "received before step-5 recovery")
    elif case_id in activation_gap_ids:
        # The activation gap: ownership has transferred but activation has not
        # arrived. The fixture must model exactly that, so it cannot be
        # misread as a post-transfer (activation-received) recovery.
        if fixture_state.get("replacement_owns_exchange_and_checkout") is not True:
            raise SystemExit(
                f"{case_id}: activation-gap fixture must own exchange and checkout")
        if fixture_state.get("activation_received") is not False:
            raise SystemExit(
                f"{case_id}: activation-gap fixture must declare activation not "
                "yet received")
    elif case_id.endswith("-refused"):
        expected = REFUSAL_EXPECTED_FAILURES.get(case_id)
        if expected is None:
            raise SystemExit(
                f"{case_id}: refusal fixture has no expected failed-gate mapping")
        if set(fails) != expected:
            raise SystemExit(
                f"{case_id}: refusal must fail exactly {sorted(expected)}, "
                f"got {sorted(fails)}")
    else:
        raise SystemExit(f"{case_id}: unclassified rotation fixture")

# Derive the qualitative cost proxy from its two observable conditions
# wherever a fixture declares them, so no fixture can assert a
# "favorable" or "unfavorable" comparison without the two conjoined
# conditions the cost model requires. Any fixture that declares one of those
# comparisons must carry both proxy fields and equal the value derived from
# them, so an opaque label cannot pass; a fixture that does not test cost
# omits the comparison entirely (an absent gate is unasserted). Only the
# separate "materially uncertain" outcome stays opaque, matching the cost
# model's distinct uncertainty clause.
for case_id in sorted(rotation_ids):
    proxy_state = by_id[case_id].get("state", {})
    declared = proxy_state.get("rotation_cost_comparison")
    if declared in ("favorable", "unfavorable"):
        if not ("expected_more_blocker_rounds" in proxy_state
                and "conductor_replay_strain" in proxy_state):
            raise SystemExit(
                f"{case_id}: a declared {declared} cost comparison must carry "
                "both proxy conditions or omit the comparison")
        derived = (
            "favorable"
            if proxy_state["expected_more_blocker_rounds"] is True
            and proxy_state["conductor_replay_strain"] is True
            else "unfavorable"
        )
        if declared != derived:
            raise SystemExit(
                f"{case_id}: rotation_cost_comparison must derive from "
                f"its two proxy conditions (expected {derived})")

# Forge-record exclusion: a bounded lint over fixture actions, secondary to
# the structured `forge_record_contains_chat_only_material` gate, which is the
# authoritative privacy assertion. It flags a clause that persists a chat-only
# field unless an exclusion word immediately governs the persist verb (sits in
# the few words before it) or a "keep <field> ... out" frame wraps it. Free
# prose cannot be parsed exhaustively, so the lint is fail-closed: an unusual
# exclusion phrasing trips it (a loud failure prompting a reword), never a
# silent pass of a leak.
persist_re = re.compile(r"persist|record|publish|write|store|copy")
EXCLUSION_WORDS = {"exclude", "excluded", "never", "not", "without"}
chat_only_terms = (
    "task contract", "user constraint", "checkout path",
    "host detail", "operating prompt", "ownership mechanics",
)
def _clause_leaks(clause):
    persist_hits = list(persist_re.finditer(clause))
    if not persist_hits or not any(t in clause for t in chat_only_terms):
        return False
    # "keep <field> ... out" frame excludes the clause only when EVERY protected
    # term in it sits between the keep and the out, so an unrelated keep-out
    # ("keep the watcher out while you record the task contract") does not vouch
    # for a persisting clause, and a frame that excludes one field while
    # persisting another ("keep the task contract out while you record the
    # operating prompt") is not excused by the excluded field. Word-boundary
    # matched so "without"/"throughout" are not read as "out".
    keeps = [m.start() for m in re.finditer(r"\bkeep\b", clause)]
    outs = [m.start() for m in re.finditer(r"\bout\b", clause)]
    if keeps and outs:
        k, o = min(keeps), max(outs)
        term_positions = [
            m.start()
            for t in chat_only_terms
            for m in re.finditer(re.escape(t), clause)
        ]
        if k < o and term_positions and all(
                k < pos < o for pos in term_positions):
            return False
    # A leak remains if any persist verb lacks an exclusion word among the
    # three words immediately preceding it, so an exclusion governing an
    # unrelated verb (e.g. "do not start a watcher before you record ...")
    # does not vouch for the persistence.
    for m in persist_hits:
        preceding = re.findall(r"[a-z]+", clause[:m.start()])[-3:]
        if not any(w in EXCLUSION_WORDS for w in preceding):
            return True
    return False
def persists_chat_only_without_exclusion(text):
    # Neutralize the destination nouns so "forge record"/"pointer record" do
    # not read as the verb "record", then judge each clause on its own so an
    # exclusion in one clause cannot vouch for a persisting clause in another.
    scan = text.replace("forge record", "forge sink").replace(
        "pointer record", "pointer sink")
    return any(_clause_leaks(c) for c in re.split(r"[,;]|\band\b|\bbut\b", scan))
# Self-test the guard against an adversarial corpus so its own logic cannot
# silently regress: compound joiners (and/but/comma/semicolon), exclusion
# position (before vs after, governing an unrelated verb), and the keep-out
# frame.
_GUARD_CORPUS = (
    ("record the task contract", True),
    ("record the task contract and do not start a watcher", True),
    ("record the task contract, without starting a watcher", True),
    ("record the task contract but never start a watcher", True),
    ("record the task contract without starting a watcher", True),
    ("do not start a watcher before you record the task contract", True),
    ("never persist the task contract, but record the operating prompt", True),
    ("publish the operating prompt to the forge record", True),
    ("keep the watcher out while you record the task contract", True),
    ("keep the task contract out while you record the operating prompt", True),
    ("record ownership mechanics in the forge record", True),
    ("never record ownership mechanics", False),
    ("never persist the task contract", False),
    ("do not persist the task contract", False),
    ("without persisting the task contract", False),
    ("exclude the task contract from the forge record", False),
    ("keep the task contract, host details, and operating prompt out of the "
     "forge record", False),
    ("inspect the exact transferable checkout path read-only without checking "
     "out the PR branch", False),
)
for _text, _want in _GUARD_CORPUS:
    if persists_chat_only_without_exclusion(_text.lower()) is not _want:
        raise SystemExit(
            f"forge-record guard self-test failed (expected {_want}): {_text}")
for case_id in sorted(rotation_ids):
    for action in by_id[case_id].get("required_actions", []):
        if persists_chat_only_without_exclusion(action.lower()):
            raise SystemExit(
                f"{case_id}: required action persists chat-only material "
                f"without an exclusion verb: {action}")

success = by_id["checkpoint-rotation-success"]
success_required = " ".join(success.get("required_actions", []))
for fragment in (
    "pointer-only forge record",
    "supply the fresh-context replacement with the current private contract",
    "every post-spawn decision and constraint amendment from surfaced judgment calls",
    "authoritative tracker issue or PR comment",
    "keep the task contract, user constraints, checkout paths, host details, and operating prompt out of the forge record",
    "fresh-context replacement",
    "exact transferable checkout path read-only",
    "main agent",
    "persist only the replacement's refreshed forge-derivable state and exact next action",
    "already-live replacement",
    "only the activation notification to the replacement remaining",
    "transfer exactly once from old to new",
    "send the replacement one activation message after the release acknowledgement",
    "re-send that idempotent message while the replacement's receipt "
    "confirmation is absent",
    "retain ownership through ambiguous old-owner completion",
):
    if fragment not in success_required:
        raise SystemExit(f"rotation success case is missing contract: {fragment}")

success_forbidden = " ".join(success.get("forbidden_actions", []))
if "persist the task contract, user constraints, checkout paths, host details, or operating prompt" not in success_forbidden:
    raise SystemExit("rotation success case does not enforce the forge-record privacy boundary")

leak_case = by_id["rotation-forge-record-chat-only-material-refused"]
leak_required = " ".join(leak_case.get("required_actions", []))
leak_forbidden = " ".join(leak_case.get("forbidden_actions", []))
for fragment in (
    "refuse to publish",
    "pointer-only record",
    "forge-derivable head, base, baseline and attribution, finding dispositions, threads, checks, and exact next action",
    "live main agent carry the excluded current private inputs",
    "every post-spawn decision and constraint amendment from surfaced judgment calls",
):
    if fragment not in leak_required:
        raise SystemExit(f"credential-boundary case is missing: {fragment}")
if "redact and persist chat-only fields" not in leak_forbidden:
    raise SystemExit("credential-boundary case must exclude, not redact, chat-only fields")

post_transfer_ids = {
    "rotation-old-completion-ambiguous-new-owner",
    "rotation-final-checkout-gate-failure-new-owner",
    "rotation-replacement-interruption-after-transfer",
}
refusal_case_ids = (
    rotation_ids
    - {"checkpoint-rotation-success"}
    - post_transfer_ids
    - activation_gap_ids
)
for case_id in refusal_case_ids:
    case = by_id[case_id]
    if case.get("safety_case") is not True:
        raise SystemExit(f"{case_id}: refusal must be a safety case")
    forbidden = " ".join(case.get("forbidden_actions", []))
    for fragment in (
        "start a replacement watcher",
        "overlap active checkout ownership",
        "terminate the old conductor before replacement acceptance",
        "report the PR ready",
    ):
        if fragment not in forbidden:
            raise SystemExit(f"{case_id}: missing forbidden action {fragment}")

for case_id in post_transfer_ids:
    case = by_id[case_id]
    if case.get("safety_case") is not True:
        raise SystemExit(f"{case_id}: post-transfer recovery must be a safety case")
    required = " ".join(case.get("required_actions", []))
    forbidden = " ".join(case.get("forbidden_actions", []))
    if "same replacement" not in required and "replacement as the sole owner" not in required:
        raise SystemExit(f"{case_id}: recovery must retain the replacement owner")
    for fragment in (
        "release replacement ownership",
        "spawn another replacement",
        "start a replacement watcher",
        "report the PR ready",
    ):
        if fragment not in forbidden:
            raise SystemExit(f"{case_id}: missing forbidden action {fragment}")

# Activation-gap recovery: the replacement must only re-wait for the idempotent
# activation message and must not resume polling, start a watcher, run the
# checkout gate, or route to stranded-conductor recovery before activation.
for case_id in activation_gap_ids:
    case = by_id[case_id]
    if case.get("safety_case") is not True:
        raise SystemExit(f"{case_id}: activation-gap recovery must be a safety case")
    required = " ".join(case.get("required_actions", []))
    forbidden = " ".join(case.get("forbidden_actions", []))
    if "replacement as the sole owner" not in required:
        raise SystemExit(f"{case_id}: recovery must retain the replacement owner")
    if "activation message" not in required:
        raise SystemExit(f"{case_id}: recovery must re-wait for the activation message")
    for fragment in (
        "resume the polling loop before activation",
        "start a replacement watcher before activation",
        "run the checkout gate before activation",
        "route the activation-gap interruption to stranded-conductor recovery",
    ):
        if fragment not in forbidden:
            raise SystemExit(f"{case_id}: missing forbidden action {fragment}")

pre_spawn_refusal_ids = {
    "rotation-without-checkpoint-go-refused",
    "rotation-unfavorable-cost-refused",
    "rotation-uncertain-cost-refused",
    "rotation-fresh-context-unavailable-refused",
    "rotation-checkout-transfer-unavailable-refused",
    "rotation-pointer-record-write-failure-refused",
    "rotation-unresolved-work-refused",
    "rotation-unresolved-decision-refused",
    "rotation-pending-push-refused",
    "rotation-watcher-overlap-refused",
}
for case_id in pre_spawn_refusal_ids:
    forbidden = " ".join(by_id[case_id].get("forbidden_actions", []))
    if "spawn a replacement conductor" not in forbidden:
        raise SystemExit(f"{case_id}: prerequisite refusal must forbid replacement spawn")

print(
    f"convergence eval rotation fixtures valid ({len(rotation_ids)} "
    "presentations): fixture shape, state-derived refusal consistency, "
    "forbidden-action coverage, forge-record exclusion")
PY

# Match pinned phrases against the file with line wraps collapsed, so a
# rewrap inside the 220-line budget does not break a pin.
skill_flat=$(tr '\n' ' ' < "$skill" | tr -s ' ')
for required in \
  'Default to one conductor subagent' \
  'fork_turns: "none"' \
  'ordinary named background subagent' \
  'optimization gap, not a failed grant' \
  'Apply one platform-neutral gate through four probes' \
  '**Write-capable delegation.** Evidence: a spawn tool is listed' \
  '**Wait-and-resume continuity.** Evidence:' \
  '**Completion notification.** Evidence:' \
  '**Checkout isolation or exclusivity.** Evidence: `git worktree list`' \
  'Claude Code `Agent`' \
  '`spawn_agent` with `fork_turns: "none"`' \
  'this skill supplies that request' \
  '"Higher-priority instruction" alone never fails it' \
  'name the rule by source' \
  'give a non-sensitive paraphrase' \
  'Default: grant exclusivity' \
  'A probe you cannot run is not a failed grant' \
  'failed grant from an unfamiliar tool name' \
  'Conductor skipped: <specific failed grant or allowed exception>.' \
  'Main-owned fallback only:' \
  'scheduled API or connector poll' \
  'bounded foreground API or connector polling' \
  'current task contract at spawn' \
  'task-specific user constraints' \
  'remaining work is likely to repay' \
  'fixed round count, elapsed time, idle time, or context size alone'; do
  if ! grep -Fq "$required" <<< "$skill_flat"; then
    printf 'SKILL.md is missing routing contract: %s\n' "$required" >&2
    exit 1
  fi
done

for required in \
  'compact, self-contained task' \
  'current task contract at spawn: objective, acceptance criteria, scope' \
  'Prepare two deliberately separate rotation artifacts.' \
  'private replacement brief containing the current task contract:' \
  "initial brief's contract plus every post-spawn decision" \
  'the current operating contract, including every post-spawn amendment' \
  'The forge-persisted pointer record contains only:' \
  'Never persist the task contract, task-specific user constraints,' \
  'Do not copy and redact those private inputs' \
  'transfer that exact path to the replacement' \
  'automated reviewer login in every required API form' \
  'current taper or rising-bar phase' \
  'no pending push, active watcher,' \
  'forge read-only, including current head' \
  'The main agent coordinates ownership with this handshake:' \
  'persists the pointer-only record in the work unit' \
  'persists the refreshed forge state and next action there' \
  'already-live' \
  'only the activation notification to the replacement' \
  'forms transfer exactly once to the replacement' \
  'activation message stating that release landed' \
  'replacement retains ownership' \
  'Never overlap watchers or active checkout ownership'; do
  if ! grep -Fq "$required" "$conductor"; then
    printf 'conductor reference is missing rotation contract: %s\n' \
      "$required" >&2
    exit 1
  fi
done

python3 - "$conductor" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
start = "The forge-persisted pointer record contains only:\n"
end = "\nThese fields are forge-derivable"
if start not in text or end not in text:
    raise SystemExit("conductor reference is missing the bounded forge-record field list")

record_fields = text.split(start, 1)[1].split(end, 1)[0]
for required in (
    "repository and PR number",
    "current PR head, base branch and tip, event baseline, and attribution state",
    "every finding class and disposition",
    "complete review-thread and required-check state",
    "the exact next action",
):
    if required not in record_fields:
        raise SystemExit(f"forge-record field list is missing: {required}")

for forbidden in (
    "task contract",
    "user constraint",
    "checkout",
    "ownership",
    "host-observation",
    "operating contract",
    "skill path",
):
    if forbidden in record_fields:
        raise SystemExit(f"forge-record field list leaks chat-only class: {forbidden}")

# Stranded-conductor recovery must stay reachable for ordinary conductors and
# for an activated replacement interrupted before its checkout gate completes;
# restricting eligibility to a gate-passed replacement (the round-12 regression)
# strips the ordinary recovery path and contradicts the
# rotation-replacement-interruption-after-transfer fixture. Scan the section,
# whitespace-flattened so a line wrap cannot hide the anchor.
strand_marker = "## §stranded-conductor-recovery\n"
if strand_marker not in text:
    raise SystemExit("conductor reference is missing the stranded-conductor recovery section")
strand = " ".join(text.split(strand_marker, 1)[1].split("\n## ", 1)[0].split())
for required in (
    "whether it is an ordinary conductor or an activated rotation replacement",
    "whether or not that replacement has completed its checkout gate",
):
    if required not in strand:
        raise SystemExit(
            "stranded-conductor recovery must keep ordinary and pre-gate "
            f"conductors eligible: {required}")
for forbidden in (
    "applies only to a replacement",
    "passed its checkout gate",
):
    if forbidden in strand:
        raise SystemExit(
            "stranded-conductor recovery must not restrict eligibility to a "
            f"gate-passed replacement: {forbidden}")
PY

if ! grep -Fq \
    'a checkpoint-approved context-rotation handoff or' "$conductor"; then
  printf 'conductor operating contract cannot surface rotation handoff\n' >&2
  exit 1
fi

for required in \
  'H_old + S_main + R_new + K × C_new' \
  'K × (C_old - C_new) > H_old + S_main + R_new' \
  'pointer-record write cost' \
  'persisting only the' \
  'automatic kill switch'; do
  if ! grep -Fq "$required" "$cost_model"; then
    printf 'cost model is missing rotation accounting: %s\n' "$required" >&2
    exit 1
  fi
done

for contract_file in "$conductor" "$detection"; do
  if ! grep -Fq 'connector' "$contract_file" || \
      ! grep -Fq 'frozen' "$contract_file" || \
      ! grep -Fq 'baseline' "$contract_file" || \
      ! grep -Eq 'expected (PR )?head' "$contract_file" || \
      ! grep -Fq 'scheduled' "$contract_file"; then
    printf '%s is missing the connector polling contract\n' \
      "${contract_file#"$repo_root/"}" >&2
    exit 1
  fi
done

if ! grep -Fq 'write-capable delegation is available and permitted' \
    "$review_response"; then
  printf 'review-response reference is missing the main-owned fixer gate\n' >&2
  exit 1
fi

printf 'await-pr-review routing structure valid: %s lines, %s words\n' \
  "$line_count" "$word_count"
