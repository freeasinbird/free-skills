# free-skills

Open-source, platform-agnostic prompt skills for AI coding agents.

Skills are self-contained prompt instructions that teach an agent how to
perform a specific task — reviewing code, setting up a project, running a
deploy checklist, etc. Each skill is a directory under `skills/` with a
`prompt.md` entry point that any compatible agent can load and execute.

## Compatibility

Skills are designed to work with multiple agent platforms:

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Codex](https://openai.com/index/introducing-codex/)
- Other agents that support prompt-based skill loading

## Using a skill

Each skill lives in `skills/<skill-name>/` with at least a `prompt.md`.
How you load it depends on your agent platform — consult your platform's
docs for importing external skills or prompt files.

## Repository layout

```
skills/
  <skill-name>/
    prompt.md            # Skill prompt (required entry point)
    references/          # Supporting material (optional)
    ...
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), which points to
[AGENTS.md](AGENTS.md) — the single source of truth for development
conventions.

## License

[MIT](LICENSE)
