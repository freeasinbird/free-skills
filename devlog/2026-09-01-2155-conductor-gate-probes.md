# Turn the await-pr-review conductor gate into observable probes

Issue #208. The 2026-09-01 transcript audit found about twelve sessions,
mostly on Codex, where the agent chose a main-owned watch while a spawn tool
was listed, and the user corrected it each time. The old gate named four
capabilities without saying how to check them, so agents resolved the
uncertainty toward the main agent.

## Decisions

- **Chose defaults that favor spawning when a probe cannot run, over failing
  closed.** A conductor spawned onto a host that cannot run it reports a
  concrete gap in its first turn and costs one short subagent turn. A
  conductor skipped on a host that could run it costs the whole exchange in
  main context, which the audit measured at a median of 17.7M tokens per
  Codex session against 1.4M without the skill. The audit found no session
  where a spawned conductor failed for a missing host capability. Revisit
  the defaults if a later audit finds one.
- **Kept the four-grant gate and rewrote each grant as evidence plus a
  default.** Rejected collapsing the gate to "a spawn tool is listed". Grants
  2 and 4 still fail on real hosts: a connector that returns only
  instantaneous reads with main-agent-only re-entry, and a shared checkout the
  main agent must keep changing. The routing fixtures pin both.
- **Named Claude Code and Codex tools in the gate text.** `Agent`,
  `SendMessage`, and `isolation: "worktree"` come from the Claude Code tool
  set. `spawn_agent`, `wait_agent`, `send_input`, `resume_agent`, and
  `fork_turns: "none"` were verified against local Codex rollouts, as was
  `followup_task` as an older continuation-tool name, and where
  `wait_agent` documents both the blocking wait and the completion
  notification. The generic "other hosts" row keeps the gate
  platform-agnostic; the named tools are evidence examples, not requirements.
- **Made the probe-to-grant mapping executable.** Fixtures may carry a
  `probes` object, and `scripts/test-await-pr-review-routing.sh` derives the
  grants from it with the documented defaults and rejects a fixture whose
  declared grants disagree. The new Codex case leaves resume continuity
  unobserved and still routes to a conductor, which is the audit failure. A
  generic case with wait, completion, and checkout all unobserved also
  routes to a conductor, pinning "unobserved takes the default" as code.
  A `spawn_write_capable` probe separates a listed spawn tool from one whose
  subagents can edit files and run commands; a read-only delegate fixture
  routes to main, since grant 1 requires write-capable delegation.
- **Kept same-agent resume inside grant 2.** A prompt review proposed
  demoting it to a brief fact so the grant would test only the wait
  mechanism. Rejected: without resume, the conductor cannot surface a
  judgment call and continue, which is the old grant's meaning, and the
  fixtures already fail the grant on resume absence. The fail clause now
  names both absences instead.
- **Replaced `conductor.md` §host-mapping with §probes rather than adding a
  second section.** The host mapping was the same content organized by host;
  organizing it by grant puts each probe, its per-host evidence, and its
  default in one place. `SKILL.md` stayed at 220 lines, the bound from #202,
  so the per-host detail lives in the reference.

Revisit when a host ships a spawn tool without completion notification or
same-agent resume, or when a transcript audit shows conductors spawned onto
hosts that cannot run them.
