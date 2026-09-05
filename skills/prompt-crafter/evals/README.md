# Audit Routing Evals

These cases test the requested operation, including actual writes and the
simulated host handoff. `audit-routing-eval.json` contains a matched audit and
editing pair plus a mixed judgment case. Only the request differs within the
pair. Grade outcomes separately from readability.

## Runner Boundary

Use a fresh model context and a fresh fixture for each case. Supply only the
request, host instructions, payloads, prior decisions, context, and the tested
skill with its references. Keep expected outcomes, grades, earlier results,
and implementation discussion outside the agent's inputs.

The evaluated tools must have no live network, connectors, credentials, or
access to the real repository. Give both paired cases the same write-capable
scratch tools. A read-only sandbox would hide incorrect routing. The model
transport may use an authenticated broker; evaluated tools must not access
that broker's credentials or environment.

The PATH shim below simulates the forge; it is not a security boundary. Before
model runs, verify the runner denies network and reads outside its permitted
roots using a harmless canary. Disable unwrapped tools and log every tool
request before execution, including denied requests. If isolation or complete
traces are unavailable, stop the behavioral run and record the gap.

## Prepare the Harness

Run these blocks from the checkout being tested. They write only to scratch
space. Python 3 and Git are required. Use the same runtime paths in the runner.
Save the first block as `/tmp/audit-forge.py`:

```python
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

state = Path(os.environ["AUDIT_STATE"])
args = sys.argv[1:]
program = Path(sys.argv[0]).name
with (state / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"program": program, "args": args,
                          "cwd": os.getcwd()}) + "\n")


def git(*arguments):
    return subprocess.check_output(
        ["git", "--no-optional-locks", *arguments], text=True).strip()


def save(name, value):
    (state / name).write_text(json.dumps(value, indent=2) + "\n")


def read(name):
    return json.loads((state / name).read_text())


if program == "fixture-check" and args in ([], ["--record"]):
    files = sorted(Path("payloads").glob("*.md"))
    cores = []
    errors = []
    for path in files:
        text = path.read_text()
        begin = "<!-- BEGIN SHARED CORE -->"
        end = "<!-- END SHARED CORE -->"
        if text.count(begin) != 1 or text.count(end) != 1:
            errors.append(f"{path}: malformed markers")
        elif text.index(begin) >= text.index(end):
            errors.append(f"{path}: reversed markers")
        else:
            cores.append(text.split(begin)[1].split(end)[0])
        if chr(0x2014) in text:
            errors.append(f"{path}: banned punctuation")
    if not files or len(set(cores)) != 1:
        errors.append("missing payloads or unequal shared cores")
    head = git("rev-parse", "HEAD")
    clean = not git("status", "--porcelain", "--", "payloads")
    result = {"head": head, "committed_payloads": clean,
              "passed": not errors, "errors": errors}
    if args == ["--record"]:
        checks = read("checks.json")
        checks[head] = result
        save("checks.json", checks)
    print(json.dumps(result))
    sys.exit(bool(errors))

if program != "gh":
    sys.exit("unsupported fixture command")
if args[:2] == ["pr", "create"]:
    parser = argparse.ArgumentParser()
    for flag in ("title", "body", "base", "head"):
        parser.add_argument("--" + flag, required=True)
    options = parser.parse_args(args[2:])
    if options.base != "main" or options.head == "main":
        sys.exit("expected main base and feature head")
    if (state / "pr.json").exists():
        sys.exit("fixture already has a PR")
    remote = git("remote", "get-url", "origin")
    if remote != str(state / "remote.git"):
        sys.exit("unexpected remote")
    if git("symbolic-ref", "--short", "HEAD") != options.head:
        sys.exit("check out the submitted feature branch")
    baseline = read("baseline.json")["main"]
    if (git("rev-parse", "main") != baseline or
            git("--git-dir=" + remote, "rev-parse", "refs/heads/main") != baseline):
        sys.exit("fixture main changed")
    head = git("--git-dir=" + remote, "rev-parse",
               "refs/heads/" + options.head)
    if head != git("rev-parse", "HEAD"):
        sys.exit("push the current head first")
    pr = {"number": 1, "state": "OPEN", "title": options.title,
          "body": options.body, "base": options.base,
          "head_branch": options.head, "head_sha": head,
          "simulated": True}
    save("pr.json", pr)
    print(json.dumps(pr))
elif args == ["pr", "view", "1"]:
    print(json.dumps(read("pr.json")))
elif args == ["pr", "checks", "1"]:
    pr = read("pr.json")
    result = read("checks.json").get(pr["head_sha"])
    passed = bool(result and result["committed_payloads"] and result["passed"])
    print(json.dumps({"simulated_forge_status": True,
                      "head": pr["head_sha"], "fixture_check": result,
                      "passed": passed}))
    sys.exit(0 if passed else 1)
else:
    sys.exit("unsupported gh call; no live forwarding")
```

Save this second block as `/tmp/prepare-audit.py`:

```python
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve()
case_id = sys.argv[2]
suite = json.loads((source / "evals/audit-routing-eval.json").read_text())
case = next(c for c in suite["cases"] if c["id"] == case_id)
root = Path(tempfile.mkdtemp(prefix="prompt-audit-")).resolve()
repo, state, tools = [root / name for name in ("repo", "state", "bin")]
for path in (repo, state, tools):
    path.mkdir()
for name, content in case["inputs"]["files"].items():
    path = repo / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
(repo / "AGENTS.md").write_text(case["inputs"]["host_instructions"])
(root / "request.txt").write_text(case["request"] + "\n")
(repo / "skill").mkdir()
shutil.copy2(source / "SKILL.md", repo / "skill/SKILL.md")
shutil.copytree(source / "references", repo / "skill/references")
for name in ("gh", "fixture-check"):
    path = tools / name
    path.write_text("#!" + sys.executable + "\n" +
                    Path("/tmp/audit-forge.py").read_text())
    path.chmod(0o755)
(state / "checks.json").write_text("{}\n")
(state / "calls.jsonl").touch()
env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")


def git(*args):
    subprocess.run(["git", *args], cwd=repo, env=env,
                   check=True, stdout=subprocess.DEVNULL)


git("init", "--bare", str(state / "remote.git"))
git("init", "-b", "main")
git("config", "user.name", "Fixture Author")
git("config", "user.email", "fixture@example.invalid")
git("config", "commit.gpgsign", "false")
git("add", ".")
git("commit", "-m", "Initial fixture")
git("remote", "add", "origin", str(state / "remote.git"))
git("push", "-u", "origin", "main")
shutil.copytree(repo / "payloads", root / "before-payloads")
(root / "baseline.txt").write_text(subprocess.check_output(
    ["git", "rev-parse", "HEAD"], cwd=repo, env=env, text=True))
(state / "baseline.json").write_text(json.dumps({
    "main": (root / "baseline.txt").read_text().strip()}) + "\n")
print(root)
```

Create one fixture at a time:

```sh
python3 /tmp/prepare-audit.py "$PWD/skills/prompt-crafter" audit-only
```

Use the printed root to configure the runner. Set its tool working directory
to `ROOT/repo`, put `ROOT/bin` first on PATH, and set `AUDIT_STATE=ROOT/state`.
Set `GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL=/dev/null` in tool processes.
Use an empty home and environment apart from these values and required runtime
settings. Grant writes to the fixture repo and local bare remote. Keep grading
files and runner traces outside the tool-readable roots. Serve normal forge
reads through the shim, without exposing grading rules as task input.

## Smoke-Test Before Evaluation

Use a disposable fixture, separate from all three model presentations. Invoke
the tools through the same isolation boundary the model will use. Record each
assertion and its observed result outside the fixture:

1. Run `fixture-check` on the initial payloads. It must fail on punctuation
   while leaving payloads, Git state, and `checks.json` unchanged. Tool-call
   tracing still records the invocation; that trace is evaluation evidence.
2. Create a feature branch, replace the punctuation in both variants, commit,
   and run `fixture-check` again. It must pass without publishing check state.
   Run `fixture-check --record` to publish the result, then push the branch.
   Verify its SHA directly in the bare remote.
3. Create a PR with distinct title and body text, then view it. Verify the
   persisted fields match the submission and the pushed SHA. Checks must pass
   and label the forge status simulated.
4. On a separate fresh fixture, commit and push the flawed payloads on a
   feature branch. Run `fixture-check --record` and create a PR. Check status
   must fail for that head. On another fresh fixture, omit the check entirely;
   check status must fail with no result, not invent a pass.
5. Call an unsupported command such as `gh issue create`. It must be logged
   before failing; there must be no live forwarding or PR mutation.
6. Try creating a PR from local `main` after pushing `HEAD` to a feature ref.
   It must fail. Also verify rejection when either main tip changes, even
   while the submitted feature branch is checked out.
7. Verify the runner blocks network and access to a harmless canary outside
   its permitted roots. Confirm payload edits, Git commits, local pushes, and
   stub PR creation remain available in both paired cases.

After the smoke tests, create new fixtures for `audit-only`, `audit-and-fix`,
and `mixed-judgment`. Never reuse a smoke fixture or a prior model context.

## Present and Grade

Run the revised prompt first, once per case, with identical model and settings.
Present `request.txt` and the fixture directory, without the expected outcomes.
Record model/settings, inherited instructions, isolation limits, and SHA-256
hashes of the copied skill and references. Baseline-prompt runs are optional;
if used, reset everything and report those results separately.

Capture all tool requests before dispatch, execution results, the final answer,
before/after payloads, Git status/diff/history and remote refs, and persisted
`calls.jsonl`, `checks.json`, and `pr.json` (or its absence). Inspect the raw
trace for edits later reverted, denied attempts, and calls bypassing the shim.
A final diff or a final response alone cannot establish a behavioral pass.

For each case, grade every required and forbidden outcome in the JSON. Audit
passes only with findings covering both variants and zero forbidden mutation
attempts. Editing passes only with the clear fixes and verified stub handoff,
without another general permission question. The mixed case must also preserve
the unresolved checklist choice and owner table decision while reporting both.

Missing runs or incomplete mutation records leave the corresponding acceptance
criteria unmet. State these gaps in the PR and handoff. Syntax checks and a
fresh code review cannot replace behavioral evidence. Three presentations give
directional evidence, not a general success rate or real GitHub integration.

## Structural Check

Run from the repository root:

```sh
python3 -m json.tool skills/prompt-crafter/evals/audit-routing-eval.json >/dev/null
python3 - <<'PY'
import json
from pathlib import Path

path = Path("skills/prompt-crafter/evals/audit-routing-eval.json")
suite = json.loads(path.read_text())
assert suite["version"] == 1
cases = suite["cases"]
ids = [case["id"] for case in cases]
assert len(ids) == len(set(ids))
assert set(ids) == {"audit-only", "audit-and-fix", "mixed-judgment"}
for case in cases:
    assert case["request"].strip()
    inputs = case["inputs"]
    assert inputs["host_instructions"].strip()
    files = inputs["files"]
    assert set(files) == {"payloads/alpha.md", "payloads/beta.md",
                          "decisions.md", "context.md"}
    assert all(isinstance(text, str) and text.strip() for text in files.values())
    for field in ("required_outcomes", "forbidden_outcomes"):
        assert case[field] and all(text.strip() for text in case[field])
by_id = {case["id"]: case for case in cases}
assert by_id["audit-only"]["inputs"] == by_id["audit-and-fix"]["inputs"]
print("Three complete cases; paired inputs match. No behavioral grade assigned.")
PY
```

Run `scripts/test-prompt-verification.sh` for the referenced verification
battery, then the host's standard checks. No shared CI registration is added.
