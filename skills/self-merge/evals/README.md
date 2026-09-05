# Self-Merge Project-Duty Evals

These fixtures test the handoff after a verified merge. They supply simulated
project instructions, task authority, and forge observations. Outputs, CLI
stubs, and grading artifacts belong in a scratch workspace outside the repo.

## Files

- `project-duty-evals.json`: Thirteen task evals. Each `prompt` contains its
  simulated inputs; `files` is empty because no separate fixture is needed.
  1. `no-project-duties`: Ordinary handoff without a companion skill.
  2. `authorized-project-procedure`: Scoped, verified project-local duty.
  3. `already-satisfied-duty`: Verified no-op without a repeated write.
  4. `unavailable-procedure`: Missing mechanics block the duty.
  5. `unavailable-tool`: Existing authority with missing tracker tooling.
  6. `missing-authority`: Issue verification without closure or tracker writes.
  7. `cleanup-stop-after-merge`: Independent duty and watch shutdown survive
     a cleanup STOP; the dependent local audit stays blocked.
  8. `unreadable-policy`: Missing source is not readable absence.
  9. `unverified-duty-result`: A successful write call with an unknown result.
  10. `reuse-reconciliation-procedure`: Reuse merge-cleanup's non-Git stages,
      including freshness, full-input rereads, and its observed ledger.
  11. `reuse-without-authority`: Available reconciliation procedures and a
      complete record don't grant tracker authority to a self-merge request.
  12. `policy-revoked-before-write`: A changed base revokes the sole tracker
      grant before a project-local write, leaving the duty blocked.
  13. `policy-moved-before-report`: A final base change preserves the verified
      tracker result but blocks an overall claim of project completion.

## Re-Running

Run these commands from the repository root. Check JSON syntax first:

```sh
python3 -m json.tool skills/self-merge/evals/project-duty-evals.json >/dev/null
```

Validate the task shape with the standard library. This checks fixture
structure, not model behavior:

```sh
python3 - <<'PY'
import json
from pathlib import Path

path = Path("skills/self-merge/evals/project-duty-evals.json")
data = json.loads(path.read_text())
assert data["skill_name"] == "self-merge"
cases = data["evals"]
assert isinstance(cases, list) and cases
ids, names = set(), set()
for case in cases:
    assert type(case["id"]) is int and case["id"] > 0
    assert case["id"] not in ids
    ids.add(case["id"])
    for key in ("eval_name", "prompt", "expected_output"):
        assert isinstance(case[key], str) and case[key].strip()
    assert case["eval_name"] not in names
    names.add(case["eval_name"])
    assert isinstance(case["files"], list)
    assert all(isinstance(p, str) and p.strip() for p in case["files"])
    assert isinstance(case["expectations"], list) and case["expectations"]
    assert all(isinstance(e, str) and e.strip() for e in case["expectations"])
print(f"Validated {len(cases)} task evals")
PY
```

Prepare an input per fresh context, withholding the grading fields:

```sh
python3 - <<'PY'
import json
import tempfile
from pathlib import Path

cases = json.loads(Path(
    "skills/self-merge/evals/project-duty-evals.json"
).read_text())["evals"]
out = Path(tempfile.mkdtemp(prefix="self-merge-duty-inputs-"))
for case in cases:
    payload = {key: case[key] for key in ("prompt", "files")}
    (out / f'{case["id"]}.json').write_text(json.dumps(payload, indent=2))
print(out)
PY
```

1. Supply each input and the tested `SKILL.md` in a fresh agent context using
   supported, permitted delegation or an external runner. Don't expose this
   README, `expected_output`, or `expectations` to the tested agent.
2. Ask for ordered proposed tool actions and a final report based only on
   simulated observations. Permit reads of the supplied skill and available
   procedures. Permit no live forge, Git, tracker, or watch mutations.
3. For cases 10 and 11, also supply merge-cleanup's Verify Issue Closure through
   Reconcile Project Obligations sections, Summarize, and
   `skills/merge-cleanup/references/project-obligations.md`. The simulated
   checker result is input, not evidence that a real trace checker ran.
4. Save each input and full response outside the repo. Grade required and
   forbidden actions against that case's withheld expectations. Record the
   exact source revision, any uncommitted diff or file hashes, model, effort,
   case verdicts, and isolation limits in the run record and PR.
5. Distinguish simulated decisions from executed behavior. For stronger
   evidence, replace observations with isolated project-file and CLI stubs
   that log reads and mutations. Never connect them to a live forge.
6. Run `./scripts/test-self-merge.sh` to completion and
   `./scripts/test-merge-cleanup-reconciliation.sh` for the unchanged mechanics.
   Those suites and JSON validation don't prove the new prompt behavior.

No runner is required or installed by this skill. Report unavailable
behavioral evaluation as a gap, never a pass. Keep all run artifacts outside
the repository.
