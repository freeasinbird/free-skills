# Score merge-cleanup With Program-Graded Fixtures

Issue #392 gives `merge-cleanup` a score that one command prints, so #393 can
shrink `SKILL.md` while holding it. This answers the hill-climb note's
"revisit when #392 builds a reusable eval runner"
(`devlog/2026-11-18-1928-hill-climb.md`): `scripts/run-scored-eval.sh` reads
any eval directory with the same layout.

## Decisions

- **Chose program-only grading over an LLM judge.** Graders read the stub
  forge's call log, the fixture's refs and worktrees, and facts in the final
  message, such as an issue number or a path. A program can't drift between
  attempts, and hill-climb ranks programs first. Graders never match wording,
  so a shorter `SKILL.md` that keeps the behavior keeps the score.
- **Chose a scored subset with a coverage rule over fixtures for every case.**
  Ten cases are scored: three existing ones, six from the skill's recorded
  failures, and a sweep case. Every `##` section that directs behavior has a
  climb case that exercises its behavior. The race cases (9, 10, 12 to 28)
  stay hand-graded; they need stubs that change state mid-run.
- **Proved sensitivity with an empty-body variant, against the plan.** The
  plan's variant removed `## Run the Guarded Cleanup`; it scored 1.000, like
  the baseline. Removing `## Reconcile Project Obligations` did too.
  Transcripts showed no contamination: the agent rebuilt each section from
  the scripts' `--help` and `references/`. The case grades behavior, and
  the behavior survived, so tuning a case to punish that removal would
  measure prose, not behavior. A `SKILL.md` with only its frontmatter
  scored 0.666 against a baseline of 1.000 with a 0.000 band.
- **Finding for #393: the score guards behavior, not sections.** Most
  sections restate the bundle, so the climb can likely cut them without
  losing score. That cuts both ways: an unsafe instruction (skip the
  scripts, force-remove worktrees) also scored 1.000, because the agent
  ignored it. The score can't catch a harmful sentence the model happens to
  disregard; review still has to.
- **Held out three history cases (30, 32, 34).** A climb that tunes against
  every case can overfit them. The held-out split runs once, at the end.
- **Chose the existing Claude Code login over an API key, and over
  `--bare`.** `--bare` isolates well but authenticates only with
  `ANTHROPIC_API_KEY`, and the owner rejected adding an API key for this.
  The agent keeps the real `HOME` and Claude config, since the login lives
  there. `--setting-sources ""` loads no settings and no user or project
  `CLAUDE.md`, `--disable-slash-commands` hides installed skills (the
  installed `merge-cleanup` among them), and `--strict-mcp-config` loads no
  MCP servers. `CLAUDE_CODE_DISABLE_AUTO_MEMORY` keeps runs from sharing
  notes through the login's memory directory. A probe confirmed that none of the owner's instructions or
  skills reached the agent.
- **Kept permission checks on, against the plan.** The plan bypassed them.
  `--allowedTools` pre-approves only the shell and file tools, so a run
  can't reach anything else, and the host's safety classifier also rejects
  a nested bypassed session.
- **Rejected redirecting `HOME`.** It hid the owner's shell and `gh`
  configuration but broke the login. `gh` isolation comes from an empty
  `GH_CONFIG_DIR`, a dummy `GH_TOKEN`, which gh prefers over stored
  credentials, a `PATH` without the real `gh`, and `.invalid` hosts with
  local-path remotes, so no fixture names a real server.
- **Kept the adapter Claude-only.** Other `--agent` values stop with the
  platform-gate error. A Codex adapter is a follow-up.

## Refute-First Findings

An independent review tried to break the runner's isolation, its scoring,
and the graders.

- **Confirmed, open for the owner: stored `gh` credentials stay reachable.**
  The dummy `GH_TOKEN` wins over the keychain; gh printed the dummy. But an
  agent that unsets it and calls the real `gh` by absolute path gets the
  owner's token. Fixtures name no real repository, so reaching a real one
  takes deliberate steps. Closing this needs Claude Code's OS sandbox with a
  network allowlist, or a separate OS user.
- **Confirmed and fixed:**
  - Exported bash functions survived the emptied environment.
  - The watchdog's orphaned `sleep` held a piped caller for 20 minutes.
  - A timed-out agent's child processes kept running.
  - A held-out name with trailing spaces joined the climb.
  - A hand-written tracker edit passed cases 11 and 34.
  - A lowercase `-X delete` escaped the mutation check.
  - The runner's header said errored runs were left out of the score.
- **Confirmed, deferred to #406:** the executor exits 1 silently under
  macOS's bash 3.2 when it gets explicit remotes.
- **Disproved:**
  - Git credential helpers: `GIT_CONFIG_NOSYSTEM` drops the system one, and
    the user config has none.
  - The API key on a command line.
  - The executor reaching a real host through case 30's alias.
  - A correct run failing case 1.
- **Declined:**
  - The hash ignores `--split`, `--model`, and `--repeats`. It identifies
    the check, and the summary names the run's settings.
  - Parallel runs share `~/.claude.json`, as concurrent Claude Code
    sessions always do.
  - An agent could overwrite the grader's evidence, but a run that follows
    a cleanup skill has no reason to edit the fixture forge. Transcripts
    show agents reading the forge files, never writing them.

Revisit when Claude Code changes what `--setting-sources`,
`--disable-slash-commands`, or `--strict-mcp-config` exclude, when
`merge-cleanup/SKILL.md` gains or loses a `##` section, or when a second
skill adopts the runner.
