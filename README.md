# free-skills

Open, platform-agnostic prompt skills for AI coding agents.

Skills are self-contained prompt instructions that teach an agent how to
perform a specific task — reviewing code, setting up a project, running a
deploy checklist, etc. Each skill is a directory under `skills/` with a
`prompt.md` entry point that any compatible agent can load and execute.

## Compatibility

Skills are designed to work with multiple agent platforms:

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Codex](https://openai.com/index/introducing-codex/)
- Other agents that support prompt-based skill loading

## Skills

| Skill                                              | Description                                                                                                                                                                  |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [agent-setup](skills/agent-setup/)                 | Set up a project for agent-driven development — generates AGENTS.md with managed workflow sections, devlog, PR template, and repo scaffolding                                |
| [license-philosopher](skills/license-philosopher/) | Apply the Free as in Bird licensing philosophy — suggests and adds the appropriate copyleft license (CC BY-SA 4.0, LGPL-3.0, GPL-3.0, or AGPL-3.0) based on the project type |

## Using a skill

Each skill lives in `skills/<skill-name>/` with at least a `prompt.md`.
How you load it depends on your agent platform — consult your platform's
docs for importing external skills or prompt files.

## Repository layout

```text
skills/
  <skill-name>/
    prompt.md            # Skill prompt (required entry point)
    references/          # Supporting material (optional)
    ...
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

This work is licensed under [CC BY-SA 4.0](./LICENSE).

See [LICENSING-PHILOSOPHY.md](./LICENSING-PHILOSOPHY.md) for why we chose this license.

---

A [Free as in Bird](https://freeasinbird.com) project.
