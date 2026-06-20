# free-skills

Open, platform-agnostic prompt skills for AI coding agents.

Skills are self-contained prompt instructions that teach an agent how to
perform a specific task — reviewing code, setting up a project, running a
deploy checklist, etc. Each skill is a directory under `skills/` with a
`SKILL.md` entry point that any compatible agent can load and execute. They
work with [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[Codex](https://openai.com/index/introducing-codex/), and other agents that
load `SKILL.md` prompts.

## Installation

A skill is just a `SKILL.md` directory, so installing one means putting it
where your agent looks for skills:

- **Claude Code** — `~/.claude/skills/<name>/`
- **Codex** — `~/.agents/skills/<name>/`

Copy or symlink the skill's directory there — symlink it from a clone of
this repo if you want it to track upstream — or point your agent at the
skill's `SKILL.md` and ask it to follow it. For example, to symlink one
skill into Claude Code from a clone (the skills directory may not exist
yet on a fresh setup, so create it first):

```sh
mkdir -p ~/.claude/skills
ln -s "$PWD/skills/license-philosopher" ~/.claude/skills/license-philosopher
```

### Convenience: link every skill (macOS / Linux)

To install all skills into both Claude Code and Codex at once — and keep
them current as the repo evolves — clone the repo and run the link helper.
It symlinks every skill into `~/.claude/skills` and `~/.agents/skills`, so a
single `git pull` refreshes them all:

```sh
git clone https://github.com/freeasinbird/free-skills.git
cd free-skills
scripts/link-skills.sh --dry-run   # preview the changes
scripts/link-skills.sh             # create the symlinks
```

Re-run it after a `git pull` that adds or removes skills. Pass `--adopt` to
replace an earlier copied install with a tracking symlink; see
`scripts/link-skills.sh --help` for all options.

## Skills

<!-- Listed alphabetically by skill name. Insert new skills in order. -->

| Skill                                              | Description                                                                                                                                                                  |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [agent-setup](skills/agent-setup/)                 | Set up a project for agent-driven development — generates AGENTS.md with managed workflow sections, devlog, PR template, and repo scaffolding                                |
| [license-philosopher](skills/license-philosopher/) | Apply the Free as in Bird licensing philosophy — suggests and adds the appropriate copyleft license (CC BY-SA 4.0, LGPL-3.0, GPL-3.0, or AGPL-3.0) based on the project type |
| [self-merge](skills/self-merge/)                   | Opt-in override of the safe default — lets an agent merge its own PR and clean up, with guardrails, only when the user or project policy explicitly allows it                |

## Repository layout

```text
skills/
  <skill-name>/
    SKILL.md             # Skill prompt (required entry point)
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
