# License Preservation Evaluations

These cases test whether license selection survives fetching, README output,
and the final report. `evals.json` separates raw requests and input files from
grading expectations. Bundled references supply full license texts without
duplicating them in JSON.

## Cases

- **Retained GPL:** Preserve `GPL-3.0-only` in `LICENSE.md` and an explicit
  `GPL-3.0-or-later` notice with `COPYING`.
- **Retained LGPL:** Preserve `LGPL-3.0-only`, its notice, and both `COPYING`
  and `COPYING.LESSER` with their respective roles.
- **New LGPL:** Cross both explicit version choices with API success and
  forced fallback. Each run needs GPL text in `LICENSE` and LGPL text in
  `LICENSE.LESSER`.
- **Version evidence:** Honor a stated project policy for new GPL. Ask a
  focused question for missing policy or conflicting retained declarations.

## Prepare a Fresh Run

Use Python 3.9 or later and Bash. From this checkout, choose a case and create
a scratch directory outside the project:

```sh
export LICENSE_EVAL_CASE=retain-gpl-only
export LICENSE_EVAL_RUN="$(mktemp -d "${TMPDIR:-/tmp}/license-eval.XXXXXX")"
python3 - <<'PY'
import json
import os
from pathlib import Path
import shutil

skill = Path('skills/license-philosopher').resolve()
run = Path(os.environ['LICENSE_EVAL_RUN'])
cases = json.loads((skill / 'evals/evals.json').read_text())['evals']
case = next(c for c in cases if c['eval_name'] == os.environ['LICENSE_EVAL_CASE'])
(run / 'before').mkdir()
for f in case['files']:
    data = ((skill / 'references/licenses' / (f['bundled'] + '.txt')).read_bytes()
            if 'bundled' in f else f['text'].encode())
    (run / 'before' / f['path']).write_bytes(data)
shutil.copytree(run / 'before', run / 'repo')
(run / 'skill').mkdir()
shutil.copyfile(skill / 'SKILL.md', run / 'skill/SKILL.md')
shutil.copytree(skill / 'references', run / 'skill/references')
(run / 'request.txt').write_text(case['prompt'] + '\n')
(run / 'fetch.log').touch()
(run / 'bin').mkdir()
PY
```

Create the following `gh` stub at `$LICENSE_EVAL_RUN/bin/gh` and make it
executable. Set `LICENSE_EVAL_MODE=api` for success or `fallback` to force API
failure. Retained and unresolved cases use `api`; their expected call log is
empty. Pass these variables and the stub directory in `PATH` to every shell
the agent uses.

```bash
#!/usr/bin/env bash
set -euo pipefail
key="${2:-}"
key="${key#/licenses/}"
text="$LICENSE_EVAL_RUN/skill/references/licenses/$key.txt"
if [ "$#" -ne 4 ] || [ "$1" != api ] || [ "$3" != --jq ] ||
   [ "$4" != .body ] || [ ! -f "$text" ]; then
  printf '%s unexpected\n' "$*" >> "$LICENSE_EVAL_RUN/fetch.log"
  exit 1
fi
if [ "$LICENSE_EVAL_MODE" = fallback ]; then
  printf '%s fail\n' "$key" >> "$LICENSE_EVAL_RUN/fetch.log"
  exit 1
fi
printf '%s ok\n' "$key" >> "$LICENSE_EVAL_RUN/fetch.log"
cat "$text"
```

The API-success stub returns bundled canonical bytes. A fallback run records
failed API attempts; the agent then reads the bundled references. Compare both
resulting texts with those references. Read the transcript to
confirm the route; files and call logs alone don't prove which file was read.

## Run and Grade

When the platform supports isolated agents, give a fresh agent only the copied
skill, raw request, and `repo/` inputs. Explain the stub environment and local
write boundary. Do not give it `evals.json`, this README, expected outputs,
prior conclusions, or the `before/` snapshot.

Disable real network access and require the supplied `gh` transport for license
fetching. Capture tool calls and the final report outside `repo/`. If the
platform can't isolate a context, use a new user-controlled session. Record
unavailable runs as evaluation gaps. Never grade an inherited conversation as
a fresh-context run.

After the agent finishes, grade its actual files and fetch log:
After the agent finishes, grade its actual files and fetch log against the
case's `license_files`, `expected_expression`, and `fetch_mode`:

- **Retained inputs:** Every file in `before/` except `README.md` is
  byte-identical in `repo/`, including notices and companion files.
- **License texts:** Each path in `license_files` holds the canonical text
  for its key. Retained cases keep the original bytes; new cases match the
  bundled reference for that key.
- **Philosophy:** `LICENSING-PHILOSOPHY.md` is byte-identical to the
  bundled reference. Unresolved cases may omit it.
- **README:** The original content survives, one License section follows it,
  and the section links `expected_expression` to its actual primary file.
  LGPL bundles also link the GPL base text. No other license expression
  appears anywhere in the README. Unresolved cases leave the README unchanged.
- **Fetch log:** Retained and unresolved cases log nothing. New cases log
  each key in `license_files` once, with `ok` for API success or `fail` for
  forced fallback. A missing log is an error; an empty instrumented log is
  evidence.

Review these behaviors manually:

- **Questions:** Missing or conflicting policy produces a focused question
  before an exact declaration is written.
- **Reports:** The final expression, paths, retained files, and remaining
  manual notice steps match the files.
- **Scope:** Existing notices survive; no new source notices are added.
- **Fetch route:** Retained cases make zero calls. Each new LGPL run attempts
  both keys and uses fallback only after that key's API failure.

Record the tested prompt's commit or SHA-256, runner/model, raw case, observed
files and calls, and grading findings. List each unexecuted case by name,
including API and fallback variants. Repeat with a fresh scratch directory for
every run. An optional no-skill baseline needs its own context.
