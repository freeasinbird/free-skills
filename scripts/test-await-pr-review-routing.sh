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

if (( line_count >= 500 )); then
  printf 'SKILL.md has %s lines; expected fewer than 500\n' "$line_count" >&2
  exit 1
fi

if (( word_count >= 5000 )); then
  printf 'SKILL.md has %s words; expected fewer than 5000\n' "$word_count" >&2
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

print(f"routing eval fixture valid: {len(cases)} cases ({eligible} conductor, {fallback} main)")
PY

python3 - "$convergence_eval" <<'PY'
import json
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
    "rotation-old-completion-ambiguous-new-owner",
    "rotation-final-checkout-gate-failure-new-owner",
    "rotation-replacement-interruption-after-transfer",
}
missing = rotation_ids - by_id.keys()
if missing:
    raise SystemExit(f"convergence eval is missing rotation cases: {sorted(missing)}")

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
    "no checkout-path transfer or replacement activation",
    "transfer exactly once from old to new",
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
for case_id in rotation_ids - {"checkpoint-rotation-success"} - post_transfer_ids:
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

print(f"convergence eval rotation fixtures valid: {len(rotation_ids)} presentations")
PY

for required in \
  'Default to one conductor subagent' \
  'fork_turns: "none"' \
  'ordinary named background subagent' \
  'optimization gap is not a failed' \
  'Apply one platform-neutral gate' \
  'wait-and-resume continuity' \
  'An applicable skill that explicitly requires delegation counts as' \
  'Do not require a separate user request.' \
  '“Higher-priority instruction” is not a valid failed grant by itself.' \
  'identify the prohibiting rule by source when disclosure' \
  'give a non-sensitive paraphrase of the binding constraint' \
  'Codex app:' \
  'Claude Code:' \
  'Any other agent:' \
  'Conductor skipped: <specific failed grant or allowed exception>.' \
  'Main-owned fallback only:' \
  'scheduled API or connector poll' \
  'bounded foreground API or connector polling' \
  'isolated checkout or explicit shared-checkout' \
  'current task contract at spawn' \
  'task-specific user constraints' \
  'remaining work is likely to repay' \
  'fixed round count, elapsed time, idle time, or context size alone'; do
  if ! grep -Fq "$required" "$skill"; then
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
  'No checkout-path transfer or replacement activation remains' \
  'forms transfer exactly once to the replacement' \
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
