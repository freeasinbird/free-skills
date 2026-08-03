#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
skill="$repo_root/skills/await-pr-review/SKILL.md"
eval_file="$repo_root/skills/await-pr-review/evals/routing-eval.json"
conductor="$repo_root/skills/await-pr-review/references/conductor.md"
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

print(f"routing eval fixture valid: {len(cases)} cases ({eligible} conductor, {fallback} main)")
PY

for required in \
  'Default to one conductor subagent' \
  'Apply one platform-neutral gate' \
  'wait-and-resume continuity' \
  'Codex app:' \
  'Claude Code:' \
  'Any other agent:' \
  'Conductor skipped: <specific failed grant or allowed exception>.' \
  'Main-owned fallback only:' \
  'scheduled API or connector poll' \
  'bounded foreground API or connector polling' \
  'isolated checkout or explicit shared-checkout'; do
  if ! grep -Fq "$required" "$skill"; then
    printf 'SKILL.md is missing routing contract: %s\n' "$required" >&2
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
